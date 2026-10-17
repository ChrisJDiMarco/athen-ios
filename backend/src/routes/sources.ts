import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import type { IssueStore } from "../services/issueStore.js";
import type { CivicSourceRegistry, CivicSource } from "../services/sourceRegistry.js";

export interface SourcesRouteDeps {
  sourceRegistry: CivicSourceRegistry;
  issueStore: IssueStore;
}

/**
 * Public read-only sources catalog so the iOS app can render its Sources panel
 * without needing the admin token. No secret-bearing fields are exposed —
 * scheduler config, ingestion clients, and queue contents stay admin-gated.
 */
export function sourcesRoute(deps: SourcesRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/sources", async (_request, reply) => {
      const sources = deps.sourceRegistry.list();
      const issues = deps.issueStore.all();

      const usageByHost = new Map<string, { issueCount: number; lastUpdatedAt: string | null }>();
      for (const issue of issues) {
        const host = (issue.sourceHost ?? "").toLowerCase();
        if (!host) continue;
        const entry = usageByHost.get(host) ?? { issueCount: 0, lastUpdatedAt: null };
        entry.issueCount += 1;
        if (!entry.lastUpdatedAt || issue.updatedAt > entry.lastUpdatedAt) {
          entry.lastUpdatedAt = issue.updatedAt;
        }
        usageByHost.set(host, entry);
      }

      return reply.send({
        generatedAtISO: new Date().toISOString(),
        sources: sources.map((source) => shape(source, usageByHost)),
        totals: {
          registered: sources.length,
          activeHosts: usageByHost.size,
          issues: issues.length,
        },
      });
    });
  };
}

function shape(source: CivicSource, usage: Map<string, { issueCount: number; lastUpdatedAt: string | null }>) {
  const primaryHost = source.allowedHosts[0]?.toLowerCase() ?? "";
  let issueCount = 0;
  let lastUpdatedAt: string | null = null;
  for (const host of source.allowedHosts) {
    const entry = usage.get(host.toLowerCase());
    if (!entry) continue;
    issueCount += entry.issueCount;
    if (entry.lastUpdatedAt && (!lastUpdatedAt || entry.lastUpdatedAt > lastUpdatedAt)) {
      lastUpdatedAt = entry.lastUpdatedAt;
    }
  }
  return {
    id: source.id,
    name: source.name,
    jurisdiction: source.jurisdiction,
    scope: source.scope,
    stateCode: source.stateCode ?? null,
    kind: source.kind,
    trustTier: source.trustTier,
    url: source.url,
    primaryHost,
    allowedHosts: source.allowedHosts,
    defaultContactTarget: source.defaultContactTarget,
    issueCount,
    lastUpdatedAt,
  };
}
