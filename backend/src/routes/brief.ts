import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import { dailyQuota } from "../lib/dailyQuota.js";
import type { BriefAnalysisService } from "../services/briefAnalysis.js";
import type { IssueStore, StoredIssue } from "../services/issueStore.js";
import { rewriteBrief, type BriefAudience } from "../services/briefRewriter.js";

const MIN = 60_000;
const briefLimiter = rateLimit({ name: "brief", max: 60, windowMs: 5 * MIN });
const digestLimiter = rateLimit({ name: "brief:digest", max: 30, windowMs: 5 * MIN });
const rewriteLimiter = rateLimit({ name: "brief:rewrite", max: 40, windowMs: 5 * MIN });

// Per-install daily caps on Claude-backed endpoints. Generous; abuse ceiling.
const briefDailyQuota = dailyQuota({ name: "claude:brief", max: 80 });
const rewriteDailyQuota = dailyQuota({ name: "claude:brief-rewrite", max: 120 });
const digestDailyQuota = dailyQuota({ name: "claude:brief-digest", max: 40 });

const DigestQuery = z.object({
  stateCode: z.string().length(2).optional(),
  zip: z.string().min(5).max(10).optional(),
  limit: z.coerce.number().int().min(1).max(12).optional(),
  warm: z.coerce.boolean().optional(),
});

const RewriteBody = z.object({
  audience: z.enum(["kid", "parent", "landlord", "neighbor", "lawyer"]),
});

export interface BriefRouteDeps {
  briefs: BriefAnalysisService;
  issues: IssueStore;
}

export function briefRoute(deps: BriefRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/brief/:issueId", async (request, reply) => {
      if (!briefLimiter(request, reply)) return;
      if (!briefDailyQuota(request, reply)) return;
      const { issueId } = request.params as { issueId: string };
      const query = request.query as { force?: string } | undefined;
      const force = query?.force === "true" || query?.force === "1";
      const issue = deps.issues.findById(issueId);
      if (!issue) {
        return reply.code(404).send({
          error: { code: "issue_not_found", message: `No issue ${issueId}` },
        });
      }
      try {
        // `force=true` busts the cache and re-runs Claude. Used by the
        // Brief tab's "Regenerate all" menu action.
        const brief = await deps.briefs.analyze(issue, { force });
        return reply.send({ brief, issueId: issue.id });
      } catch (err) {
        request.log.error({ err }, "brief generation failed");
        return reply.code(502).send({
          error: {
            code: "brief_failed",
            message: err instanceof Error ? err.message : "Brief generation failed.",
          },
        });
      }
    });

    fastify.post("/v1/brief/:issueId/rewrite", async (request, reply) => {
      if (!rewriteLimiter(request, reply)) return;
      if (!rewriteDailyQuota(request, reply)) return;
      const { issueId } = request.params as { issueId: string };
      const parsed = RewriteBody.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_body", message: parsed.error.message },
        });
      }
      const issue = deps.issues.findById(issueId);
      if (!issue) {
        return reply.code(404).send({
          error: { code: "issue_not_found", message: `No issue ${issueId}` },
        });
      }
      let brief = deps.briefs.cached(issue);
      if (!brief) {
        try {
          brief = await deps.briefs.analyze(issue);
        } catch (err) {
          return reply.code(502).send({
            error: {
              code: "brief_unavailable",
              message: err instanceof Error ? err.message : "Brief generation failed.",
            },
          });
        }
      }
      try {
        const text = await rewriteBrief(brief, issue, parsed.data.audience);
        return reply.send({ audience: parsed.data.audience, text });
      } catch (err) {
        request.log.error({ err }, "brief rewrite failed");
        return reply.code(502).send({
          error: {
            code: "rewrite_failed",
            message: err instanceof Error ? err.message : "Rewrite failed.",
          },
        });
      }
    });

    fastify.get("/v1/brief", async (request, reply) => {
      if (!digestLimiter(request, reply)) return;
      if (!digestDailyQuota(request, reply)) return;
      const parsed = DigestQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_query", message: parsed.error.message },
        });
      }
      const { stateCode, zip, warm } = parsed.data;
      const limit = parsed.data.limit ?? 8;

      const filter: { stateCode?: string; zip?: string } = {};
      if (stateCode) filter.stateCode = stateCode;
      if (zip) filter.zip = zip;
      const ranked = rankIssues(deps.issues.all(), filter).slice(0, limit);

      // By default, return whatever's already cached so the iOS list paints fast.
      // When `warm=true`, generate any missing briefs IN PARALLEL on demand —
      // sequential warm-up made first paint 60-90 seconds. Now it's bounded by
      // the slowest Claude call (~10s), not their sum.
      const items = await Promise.all(
        ranked.map(async (issue) => {
          let brief = deps.briefs.cached(issue);
          if (!brief && warm) {
            try {
              brief = await deps.briefs.analyze(issue);
            } catch (err) {
              request.log.warn({ err, issueId: issue.id }, "brief warm-up failed");
            }
          }
          return { issue, brief };
        }),
      );

      return reply.send({
        generatedAtISO: new Date().toISOString(),
        cacheStats: deps.briefs.stats(),
        items: items.map((entry) => ({
          issueId: entry.issue.id,
          issue: shapeIssue(entry.issue),
          brief: entry.brief ?? null,
        })),
      });
    });
  };
}

function rankIssues(issues: StoredIssue[], filter: { stateCode?: string; zip?: string }): StoredIssue[] {
  return issues
    .filter((issue) => {
      if (issue.scope === "federal") return true;
      if (issue.scope === "local-philly") {
        if (filter.zip && !filter.zip.startsWith("191")) return false;
        if (filter.stateCode && filter.stateCode !== "PA") return false;
        return true;
      }
      if (issue.scope === "state") {
        if (filter.stateCode && issue.stateCode && filter.stateCode !== issue.stateCode) return false;
        return true;
      }
      return true;
    })
    .sort((a, b) => {
      const impactScore: Record<typeof a.impactLevel, number> = { urgent: 0, material: 1, watch: 2 };
      if (impactScore[a.impactLevel] !== impactScore[b.impactLevel]) {
        return impactScore[a.impactLevel] - impactScore[b.impactLevel];
      }
      return Date.parse(a.voteDateISO) - Date.parse(b.voteDateISO);
    });
}

function shapeIssue(issue: StoredIssue) {
  return {
    id: issue.id,
    title: issue.title,
    category: issue.category,
    jurisdiction: issue.jurisdiction,
    scope: issue.scope,
    stateCode: issue.stateCode,
    summary: issue.summary,
    impactLevel: issue.impactLevel,
    voteDateISO: issue.voteDateISO,
    sourceName: issue.sourceName,
    sourceHost: issue.sourceHost,
    sourceURL: issue.sourceURL,
    trustScore: issue.trustScore,
  };
}
