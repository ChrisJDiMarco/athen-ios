import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import type { IssueStore, StoredIssue } from "../services/issueStore.js";
import type { CivicSourceRegistry } from "../services/sourceRegistry.js";
import type { VoteStore } from "../services/voteStore.js";
import { matchServices, type ServiceMatchProfile } from "../services/serviceCatalog.js";
import { buildCivicBrief } from "../services/civicBrief.js";

const QuerySchema = z.object({
  stateCode: z.string().length(2).optional(),
  zip: z.string().min(5).max(10).optional(),
  scope: z.enum(["federal", "state", "local-philly", "unknown"]).optional(),
  needs: z.union([z.string(), z.array(z.string())]).optional(),
  signals: z.union([z.string(), z.array(z.string())]).optional(),
  documents: z.union([z.string(), z.array(z.string())]).optional(),
  language: z.string().max(40).optional(),
  /** Free-text search across title/summary/topics (added 2026-05-21). */
  q: z.string().max(200).optional(),
});

const ExportQuerySchema = QuerySchema.extend({
  limit: z.coerce.number().int().min(1).max(2000).optional(),
});

export interface IssuesRouteDeps {
  store: IssueStore;
  sourceRegistry?: CivicSourceRegistry;
  votes?: VoteStore;
}

export function issuesRoute(deps: IssuesRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/issues", async (request, reply) => {
      const parsed = QuerySchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_query", message: parsed.error.message },
        });
      }

      const { stateCode, zip, scope } = parsed.data;
      const all = deps.store.all();

      const filtered = all.filter((issue) => {
        if (scope && issue.scope !== scope) return false;
        if (issue.scope === "federal") return true;
        if (issue.scope === "local-philly") {
          if (zip && !zip.startsWith("191")) return false;
          if (stateCode && stateCode !== "PA") return false;
          return true;
        }
        if (issue.scope === "state") {
          if (stateCode && issue.stateCode && stateCode !== issue.stateCode) return false;
          return true;
        }
        return true;
      });

      // Sort: nearest vote first, then most recently updated.
      filtered.sort((a, b) => {
        const av = Date.parse(a.voteDateISO);
        const bv = Date.parse(b.voteDateISO);
        if (Number.isFinite(av) && Number.isFinite(bv) && av !== bv) return av - bv;
        return Date.parse(b.updatedAt) - Date.parse(a.updatedAt);
      });

      const serviceProfile: ServiceMatchProfile = {
        needs: splitQueryList(parsed.data.needs),
        signals: splitQueryList(parsed.data.signals),
        preparedDocuments: splitQueryList(parsed.data.documents),
      };
      if (parsed.data.language) serviceProfile.language = parsed.data.language;

      const serviceMatches = matchServices(serviceProfile, { limit: 3 });

      return reply.send({
        issues: filtered.map(shape),
        brief: buildCivicBrief({
          issues: filtered,
          serviceMatches,
          stateCode,
          zip,
          registeredSources: deps.sourceRegistry?.list().length ?? null,
        }),
      });
    });

    // --- Bill timeline ---------------------------------------------------
    //
    // Chronological events for one issue: introduced (createdAt),
    // last updated (updatedAt), and every roll-call vote on record from
    // the VoteStore. Reporters + Hill staff use this to see where a bill
    // is in the pipeline at a glance.
    fastify.get<{ Params: { id: string } }>("/v1/issues/:id/timeline", async (request, reply) => {
      const issue = deps.store.findById(request.params.id);
      if (!issue) {
        return reply.code(404).send({ error: { code: "not_found", message: "Issue not found." } });
      }
      const events: TimelineEvent[] = [];
      events.push({
        kind: "introduced",
        atISO: issue.createdAt,
        title: "Introduced",
        detail: `Added to Athen from ${issue.sourceName}.`,
      });
      if (issue.updatedAt && issue.updatedAt !== issue.createdAt) {
        events.push({
          kind: "updated",
          atISO: issue.updatedAt,
          title: "Most recent update",
          detail: "Source reported new activity on this bill.",
        });
      }
      if (issue.voteDateISO && Number.isFinite(Date.parse(issue.voteDateISO))) {
        const future = Date.parse(issue.voteDateISO) > Date.now();
        events.push({
          kind: future ? "vote-scheduled" : "vote-passed-date",
          atISO: issue.voteDateISO,
          title: future ? "Vote scheduled" : "Scheduled vote date",
          detail: future
            ? "Currently on the calendar."
            : "The official date listed on this bill has passed.",
        });
      }
      if (deps.votes) {
        for (const vote of deps.votes.byIssueFingerprint(issue.sourceFingerprint)) {
          events.push({
            kind: "roll-call",
            atISO: vote.voteDateISO,
            title: `${vote.chamber} ${vote.result}: ${vote.motion}`,
            detail: `Yes ${vote.totals.yes} · No ${vote.totals.no} · Abstain ${vote.totals.abstain} · Absent ${vote.totals.absent}`,
            voteId: vote.id,
          });
        }
      }
      events.sort((a, b) => Date.parse(a.atISO) - Date.parse(b.atISO));
      return reply.send({
        issueId: issue.id,
        events,
      });
    });

    // --- CSV export ------------------------------------------------------
    //
    // Same filter set as `/v1/issues`. Streams a flat CSV with the
    // columns reporters + Hill staff most often want. Capped at 2000
    // rows so a runaway query doesn't tank the backend.
    fastify.get("/v1/issues/export.csv", async (request, reply) => {
      const parsed = ExportQuerySchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_query", message: parsed.error.message },
        });
      }
      const { stateCode, zip, scope, q, limit } = parsed.data;
      const filterArgs: Parameters<typeof filterIssues>[1] = {};
      if (stateCode) filterArgs.stateCode = stateCode;
      if (zip) filterArgs.zip = zip;
      if (scope) filterArgs.scope = scope;
      if (q) filterArgs.q = q;
      const filtered = filterIssues(deps.store.all(), filterArgs)
        .slice(0, limit ?? 2000);
      const headers = [
        "id",
        "title",
        "scope",
        "stateCode",
        "jurisdiction",
        "category",
        "impactLevel",
        "voteDate",
        "sourceName",
        "sourceURL",
        "official",
        "topics",
        "summary",
      ];
      const rows = filtered.map((issue) => [
        issue.id,
        issue.title,
        issue.scope,
        issue.stateCode ?? "",
        issue.jurisdiction,
        issue.category,
        issue.impactLevel,
        issue.voteDateISO,
        issue.sourceName,
        issue.sourceURL,
        issue.official?.name ?? "",
        (issue.topics ?? []).join("; "),
        issue.summary,
      ]);
      const csv = [headers, ...rows].map(toCSVRow).join("\r\n");
      reply.header("content-type", "text/csv; charset=utf-8");
      reply.header(
        "content-disposition",
        `attachment; filename="athen-issues-${new Date().toISOString().slice(0, 10)}.csv"`,
      );
      return reply.send(csv);
    });
  };
}

interface TimelineEvent {
  kind:
    | "introduced"
    | "updated"
    | "vote-scheduled"
    | "vote-passed-date"
    | "roll-call";
  atISO: string;
  title: string;
  detail: string;
  voteId?: string;
}

function filterIssues(
  all: StoredIssue[],
  args: { stateCode?: string; zip?: string; scope?: string; q?: string },
): StoredIssue[] {
  const q = args.q?.toLowerCase().trim() ?? "";
  return all.filter((issue) => {
    if (args.scope && issue.scope !== args.scope) return false;
    if (issue.scope === "federal") {
      // federal is always included
    } else if (issue.scope === "local-philly") {
      if (args.zip && !args.zip.startsWith("191")) return false;
      if (args.stateCode && args.stateCode !== "PA") return false;
    } else if (issue.scope === "state") {
      if (args.stateCode && issue.stateCode && args.stateCode !== issue.stateCode) return false;
    }
    if (q.length > 0) {
      const haystack = [
        issue.title,
        issue.summary,
        issue.jurisdiction,
        issue.official?.name ?? "",
        ...(issue.topics ?? []),
      ].join(" ").toLowerCase();
      if (!haystack.includes(q)) return false;
    }
    return true;
  });
}

function toCSVRow(cells: string[]): string {
  return cells.map(escapeCSV).join(",");
}

function escapeCSV(value: string): string {
  // CSV needs quoting on any cell with comma, quote, newline, or carriage
  // return. Inner quotes are doubled. Always quote text fields with spaces
  // to keep output readable when imported into Sheets/Excel.
  const needsQuote = /[",\r\n]/.test(value);
  if (!needsQuote) return value;
  return `"${value.replace(/"/g, '""')}"`;
}

function splitQueryList(value: string | string[] | undefined): string[] {
  if (!value) return [];
  const values = Array.isArray(value) ? value : [value];
  return values
    .flatMap((entry) => entry.split(","))
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}

function shape(issue: StoredIssue) {
  return {
    id: issue.id,
    title: issue.title,
    category: issue.category,
    jurisdiction: issue.jurisdiction,
    scope: issue.scope,
    stateCode: issue.stateCode,
    zipCode: issue.zipCode,
    summary: issue.summary,
    impactLevel: issue.impactLevel,
    voteDateISO: issue.voteDateISO,
    sourceName: issue.sourceName,
    sourceDetail: issue.sourceDetail,
    sourceURL: issue.sourceURL,
    sourceHost: issue.sourceHost,
    sourceType: issue.sourceType,
    trustScore: issue.trustScore,
    extractionConfidence: issue.extractionConfidence,
    citations: issue.citations ?? [],
    ingestedAt: issue.ingestedAt,
    topics: issue.topics,
    facts: issue.facts,
    official: issue.official,
    filingRoute: issue.filingRoute,
    reply: null,
  };
}
