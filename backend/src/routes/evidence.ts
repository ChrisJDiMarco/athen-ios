import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import type { EvidenceVault } from "../services/evidenceVault.js";
import type { IssueStore } from "../services/issueStore.js";

const EvidenceQuery = z.object({
  issueId: z.string().uuid().optional(),
  sourceHost: z.string().max(200).optional(),
  limit: z.coerce.number().int().positive().max(100).optional(),
});

export interface EvidenceRouteDeps {
  vault: EvidenceVault;
  store: IssueStore;
}

export function evidenceRoute(deps: EvidenceRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/evidence", async (request, reply) => {
      const parsed = EvidenceQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_query", message: parsed.error.message },
        });
      }

      await deps.vault.seedFromIssues(deps.store.all());

      let records = parsed.data.issueId
        ? deps.vault.byIssue(parsed.data.issueId)
        : deps.vault.all();
      if (parsed.data.sourceHost) {
        records = records.filter((record) => record.sourceHost.includes(parsed.data.sourceHost ?? ""));
      }
      records = records.slice(0, parsed.data.limit ?? 50);

      return reply.send({
        generatedAtISO: new Date().toISOString(),
        stats: deps.vault.stats(),
        count: records.length,
        evidence: records,
      });
    });

    fastify.get("/v1/issues/:id/evidence", async (request, reply) => {
      const parsed = z.object({ id: z.string().uuid() }).safeParse(request.params);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }
      await deps.vault.seedFromIssues(deps.store.all());
      return reply.send({
        generatedAtISO: new Date().toISOString(),
        evidence: deps.vault.byIssue(parsed.data.id),
      });
    });
  };
}
