import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { CivicError } from "../lib/errors.js";
import { requireAdminAuth } from "../lib/adminAuth.js";
import type { IngestionPipeline } from "../services/ingestionPipeline.js";
import type { JurisdictionIngestor } from "../services/jurisdictionIngestor.js";
import type { IngestionScheduler } from "../services/scheduler.js";
import type { ContactFormQueue, QueueStatus } from "../services/contactFormQueue.js";
import type { IssueStore } from "../services/issueStore.js";
import type { CivicSourceRegistry } from "../services/sourceRegistry.js";
import type { FirecrawlSourceDiscovery } from "../services/sourceDiscovery.js";
import type { EvidenceVault } from "../services/evidenceVault.js";
import type { CivicSourceSweeper } from "../services/connectors/civicSourceConnectors.js";
import { fingerprintForURL, storedIssueFromIngested } from "../services/issueNormalizer.js";

const IngestURLSchema = z.object({
  url: z.string().url(),
  jurisdictionHint: z.string().max(200).optional(),
  sourceId: z.string().max(80).optional(),
  persist: z.boolean().default(true),
});

const IngestJurisdictionSchema = z.object({
  type: z.literal("legistar"),
  client: z.string().min(1).max(40),
  lookaheadDays: z.number().int().positive().max(120).optional(),
  limit: z.number().int().positive().max(40).optional(),
});

const IngestSourceSchema = z.object({
  sourceId: z.string().min(1).max(80),
  query: z.string().min(3).max(300).optional(),
  lookaheadDays: z.number().int().positive().max(120).optional(),
  limit: z.number().int().positive().max(40).optional(),
});

const SourceSweepSchema = z.object({
  connectors: z.array(z.enum(["congress", "govinfo", "regulations", "openstates", "socrata", "open311"])).optional(),
  daysBack: z.number().int().positive().max(365).optional(),
  limit: z.number().int().positive().max(50).optional(),
});

export interface AdminRouteDeps {
  ingestion: IngestionPipeline;
  jurisdictionIngestor: JurisdictionIngestor;
  scheduler: IngestionScheduler;
  contactFormQueue: ContactFormQueue;
  issueStore: IssueStore;
  sourceRegistry: CivicSourceRegistry;
  sourceDiscovery: FirecrawlSourceDiscovery;
  evidenceVault: EvidenceVault;
  sourceSweeper: CivicSourceSweeper;
}

const QueueListQuery = z.object({
  status: z.enum(["queued", "submitted", "failed", "skipped"]).optional(),
  limit: z.coerce.number().int().positive().max(200).optional(),
});

const QueueMarkSchema = z.object({
  id: z.string().uuid(),
  status: z.enum(["submitted", "failed", "skipped"]),
  reason: z.string().max(500).optional(),
});

export function adminRoute(deps: AdminRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/admin/sources", async (request, reply) => {
      if (!requireAdminAuth(request, reply)) return;
      return reply.send({
        sources: deps.sourceRegistry.list(),
        issueStore: deps.issueStore.stats(),
      });
    });

    fastify.post("/v1/admin/ingest-url", async (request, reply) => {
      if (!requireAdminAuth(request, reply)) return;
      const parsed = IngestURLSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }

      try {
        const source = parsed.data.sourceId
          ? deps.sourceRegistry.byId(parsed.data.sourceId)
          : deps.sourceRegistry.matchURL(parsed.data.url);
        if (parsed.data.sourceId && !source) {
          return reply.code(404).send({
            error: { code: "unknown_source", message: "No source registered with that id." },
          });
        }

        const issue = await deps.ingestion.ingestFromURL(
          parsed.data.url,
          parsed.data.jurisdictionHint ?? source?.jurisdiction,
        );
        if (!parsed.data.persist) {
          return reply.send({ issue, persisted: false });
        }

        const storedIssue = await deps.issueStore.upsert(
          storedIssueFromIngested(issue, source ? { source } : {}),
        );
        await deps.evidenceVault.upsertFromIssue(storedIssue);
        return reply.send({ issue: storedIssue, extracted: issue, persisted: true });
      } catch (err) {
        if (err instanceof CivicError) {
          return reply
            .code(err.statusCode)
            .send({ error: { code: err.code, message: err.message } });
        }
        request.log.error({ err }, "ingest-url failed");
        return reply.code(500).send({
          error: { code: "ingest_failed", message: "Ingestion failed." },
        });
      }
    });

    fastify.post("/v1/admin/ingest-source", async (request, reply) => {
      if (!requireAdminAuth(request, reply)) return;
      const parsed = IngestSourceSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }

      const source = deps.sourceRegistry.byId(parsed.data.sourceId);
      if (!source) {
        return reply.code(404).send({
          error: { code: "unknown_source", message: "No source registered with that id." },
        });
      }

      try {
        if (source.kind === "legistar") {
          if (!source.legistarClient) {
            return reply.code(400).send({
              error: { code: "source_misconfigured", message: "Legistar source has no client." },
            });
          }
          const args: Parameters<JurisdictionIngestor["ingestLegistar"]>[0] = {
            client: source.legistarClient,
          };
          if (parsed.data.lookaheadDays !== undefined) args.lookaheadDays = parsed.data.lookaheadDays;
          if (parsed.data.limit !== undefined) args.limit = parsed.data.limit;
          const report = await deps.jurisdictionIngestor.ingestLegistar(args);
          return reply.send({ source, report });
        }

        const discoveryArgs: Parameters<FirecrawlSourceDiscovery["discover"]>[0] = { source };
        if (parsed.data.query !== undefined) discoveryArgs.query = parsed.data.query;
        if (parsed.data.limit !== undefined) discoveryArgs.limit = parsed.data.limit;
        const discovered = await deps.sourceDiscovery.discover(discoveryArgs);

        const report = {
          inspected: discovered.length,
          inserted: 0,
          updated: 0,
          skipped: 0,
          failures: [] as { url: string; error: string }[],
        };

        const storedIssues = [];
        for (const candidate of discovered) {
          try {
            const fingerprint = fingerprintForURL(candidate.url);
            const existing = deps.issueStore.byFingerprint(fingerprint);
            const ingested = await deps.ingestion.ingestFromURL(candidate.url, source.jurisdiction);
            const stored = await deps.issueStore.upsert(
              storedIssueFromIngested(ingested, { source, sourceFingerprint: fingerprint }),
            );
            await deps.evidenceVault.upsertFromIssue(stored);
            storedIssues.push(stored);
            if (existing) report.updated += 1;
            else report.inserted += 1;
          } catch (err) {
            report.skipped += 1;
            report.failures.push({
              url: candidate.url,
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }

        return reply.send({ source, discovered, report, issues: storedIssues });
      } catch (err) {
        if (err instanceof CivicError) {
          return reply
            .code(err.statusCode)
            .send({ error: { code: err.code, message: err.message } });
        }
        request.log.error({ err }, "ingest-source failed");
        return reply.code(500).send({
          error: { code: "ingest_failed", message: "Source ingestion failed." },
        });
      }
    });

    fastify.get("/v1/admin/scheduler", async (request, reply) => {
      if (!requireAdminAuth(request, reply)) return;
      return reply.send(deps.scheduler.status());
    });

    fastify.post("/v1/admin/source-sweep", async (request, reply) => {
      if (!requireAdminAuth(request, reply)) return;
      const parsed = SourceSweepSchema.safeParse(request.body ?? {});
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }

      const sweepArgs: Parameters<CivicSourceSweeper["sweep"]>[0] = {};
      if (parsed.data.connectors) sweepArgs.connectors = parsed.data.connectors;
      if (parsed.data.daysBack !== undefined) sweepArgs.daysBack = parsed.data.daysBack;
      if (parsed.data.limit !== undefined) sweepArgs.limit = parsed.data.limit;

      const results = await deps.sourceSweeper.sweep(sweepArgs);
      const records = await deps.evidenceVault.upsertMany(results.flatMap((result) => result.records));
      return reply.send({
        generatedAtISO: new Date().toISOString(),
        results: results.map((result) => ({
          connector: result.connector,
          inspected: result.inspected,
          records: result.records.length,
          skippedReason: result.skippedReason,
          error: result.error,
        })),
        evidenceInsertedOrUpdated: records.length,
        evidenceVault: deps.evidenceVault.stats(),
      });
    });

    fastify.get("/v1/admin/contact-form-queue", async (request, reply) => {
      if (!requireAdminAuth(request, reply)) return;
      const parsed = QueueListQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_query", message: parsed.error.message },
        });
      }
      const queueArgs: { status?: QueueStatus; limit?: number } = {};
      if (parsed.data.status) queueArgs.status = parsed.data.status as QueueStatus;
      if (parsed.data.limit) queueArgs.limit = parsed.data.limit;
      return reply.send({
        counts: deps.contactFormQueue.count(),
        items: deps.contactFormQueue.list(queueArgs),
      });
    });

    fastify.post("/v1/admin/contact-form-queue/mark", async (request, reply) => {
      if (!requireAdminAuth(request, reply)) return;
      const parsed = QueueMarkSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }
      const updated = await deps.contactFormQueue.mark(
        parsed.data.id,
        parsed.data.status as QueueStatus,
        parsed.data.reason,
      );
      if (!updated) {
        return reply.code(404).send({
          error: { code: "not_found", message: "No submission with that id." },
        });
      }
      return reply.send({ submission: updated });
    });

    fastify.post("/v1/admin/ingest-jurisdiction", async (request, reply) => {
      if (!requireAdminAuth(request, reply)) return;
      const parsed = IngestJurisdictionSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }

      try {
        const args: Parameters<JurisdictionIngestor["ingestLegistar"]>[0] = {
          client: parsed.data.client,
        };
        if (parsed.data.lookaheadDays !== undefined) args.lookaheadDays = parsed.data.lookaheadDays;
        if (parsed.data.limit !== undefined) args.limit = parsed.data.limit;

        const report = await deps.jurisdictionIngestor.ingestLegistar(args);
        return reply.send({ report });
      } catch (err) {
        if (err instanceof CivicError) {
          return reply
            .code(err.statusCode)
            .send({ error: { code: err.code, message: err.message } });
        }
        request.log.error({ err }, "ingest-jurisdiction failed");
        return reply.code(500).send({
          error: { code: "ingest_failed", message: "Jurisdiction ingestion failed." },
        });
      }
    });
  };
}
