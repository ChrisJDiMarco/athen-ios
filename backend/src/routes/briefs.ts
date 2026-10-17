import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { buildAthenBriefs } from "../services/athenBriefs.js";
import type { EvidenceVault } from "../services/evidenceVault.js";
import type { IssueStore } from "../services/issueStore.js";

const BriefQuery = z.object({
  stateCode: z.string().length(2).optional(),
  zip: z.string().min(5).max(10).optional(),
  limit: z.coerce.number().int().positive().max(50).optional(),
});

export interface BriefsRouteDeps {
  store: IssueStore;
  evidenceVault: EvidenceVault;
}

export function briefsRoute(deps: BriefsRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/briefs", async (request, reply) => {
      const parsed = BriefQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_query", message: parsed.error.message },
        });
      }

      await deps.evidenceVault.seedFromIssues(deps.store.all());
      const all = deps.store.all();
      const issues = all.filter((issue) => {
        if (issue.scope === "federal") return true;
        if (issue.scope === "local-philly") {
          if (parsed.data.zip && !parsed.data.zip.startsWith("191")) return false;
          if (parsed.data.stateCode && parsed.data.stateCode !== "PA") return false;
          return true;
        }
        if (issue.scope === "state") {
          if (parsed.data.stateCode && issue.stateCode && parsed.data.stateCode !== issue.stateCode) return false;
          return true;
        }
        return true;
      });

      return reply.send({
        generatedAtISO: new Date().toISOString(),
        count: issues.length,
        briefs: buildAthenBriefs({
          issues,
          evidence: deps.evidenceVault.all(),
          limit: parsed.data.limit ?? 20,
        }),
      });
    });
  };
}
