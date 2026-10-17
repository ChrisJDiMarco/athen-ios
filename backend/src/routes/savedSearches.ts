import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import { SavedSearchStore } from "../services/savedSearchStore.js";
import type { IssueStore } from "../services/issueStore.js";

const MIN = 60_000;
const listLimiter = rateLimit({ name: "saved:list", max: 240, windowMs: 5 * MIN });
const writeLimiter = rateLimit({ name: "saved:write", max: 60, windowMs: 5 * MIN });

const InstallHeader = z.object({
  "x-athen-install": z.string().min(8).max(128),
});

const ScopeEnum = z.enum(["any", "federal", "state", "local-philly"]);

const CreateBody = z.object({
  name: z.string().min(1).max(80),
  query: z.string().min(1).max(200),
  scope: ScopeEnum.optional(),
  stateCode: z.string().length(2).optional(),
  alertsEnabled: z.boolean().optional(),
});

const UpdateBody = z.object({
  name: z.string().min(1).max(80).optional(),
  query: z.string().min(1).max(200).optional(),
  scope: ScopeEnum.optional(),
  stateCode: z.string().length(2).nullable().optional(),
  alertsEnabled: z.boolean().optional(),
  lastSeenAt: z.string().optional(),
});

export interface SavedSearchesDeps {
  searches: SavedSearchStore;
  issues: IssueStore;
}

export function savedSearchesRoute(deps: SavedSearchesDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/saved-searches", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      const headers = InstallHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_install", message: "x-athen-install header required." } });
      }
      const installId = headers.data["x-athen-install"];
      const items = deps.searches.forInstall(installId);
      // Enrich with current match count so the client can show "12 hits".
      const issues = deps.issues.all();
      const enriched = items.map((s) => {
        const matches = SavedSearchStore.evaluate(s, issues);
        return { ...s, currentMatchCount: matches.length };
      });
      return reply.send({ items: enriched });
    });

    fastify.post("/v1/saved-searches", async (request, reply) => {
      if (!writeLimiter(request, reply)) return;
      const headers = InstallHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_install", message: "x-athen-install header required." } });
      }
      const body = CreateBody.safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: body.error.message } });
      }
      const search = await deps.searches.add({
        installId: headers.data["x-athen-install"],
        name: body.data.name,
        query: body.data.query,
        ...(body.data.scope ? { scope: body.data.scope } : {}),
        ...(body.data.stateCode ? { stateCode: body.data.stateCode } : {}),
        ...(body.data.alertsEnabled !== undefined ? { alertsEnabled: body.data.alertsEnabled } : {}),
      });
      // Seed `matchedIssueIds` with everything that already matches at
      // creation time so the first alert only fires on truly new hits.
      const issues = deps.issues.all();
      const existing = SavedSearchStore.evaluate(search, issues);
      for (const issue of existing) {
        await deps.searches.recordMatch(search.id, issue.id);
      }
      return reply.send({ search, initialMatchCount: existing.length });
    });

    fastify.put<{ Params: { id: string } }>("/v1/saved-searches/:id", async (request, reply) => {
      if (!writeLimiter(request, reply)) return;
      const headers = InstallHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_install", message: "x-athen-install header required." } });
      }
      const body = UpdateBody.safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: body.error.message } });
      }
      const patch: Parameters<typeof deps.searches.update>[2] = {};
      if (body.data.name !== undefined) patch.name = body.data.name;
      if (body.data.query !== undefined) patch.query = body.data.query;
      if (body.data.scope !== undefined) patch.scope = body.data.scope;
      if (body.data.stateCode !== undefined) patch.stateCode = body.data.stateCode ?? "";
      if (body.data.alertsEnabled !== undefined) patch.alertsEnabled = body.data.alertsEnabled;
      if (body.data.lastSeenAt !== undefined) patch.lastSeenAt = body.data.lastSeenAt;
      const updated = await deps.searches.update(headers.data["x-athen-install"], request.params.id, patch);
      if (!updated) return reply.code(404).send({ error: { code: "not_found", message: "Saved search not found." } });
      return reply.send({ search: updated });
    });

    fastify.delete<{ Params: { id: string } }>("/v1/saved-searches/:id", async (request, reply) => {
      if (!writeLimiter(request, reply)) return;
      const headers = InstallHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_install", message: "x-athen-install header required." } });
      }
      const ok = await deps.searches.remove(headers.data["x-athen-install"], request.params.id);
      if (!ok) return reply.code(404).send({ error: { code: "not_found", message: "Saved search not found." } });
      return reply.send({ ok: true });
    });

    fastify.post<{ Params: { id: string } }>("/v1/saved-searches/:id/run", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      const headers = InstallHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_install", message: "x-athen-install header required." } });
      }
      const search = deps.searches.forInstall(headers.data["x-athen-install"]).find((s) => s.id === request.params.id);
      if (!search) return reply.code(404).send({ error: { code: "not_found", message: "Saved search not found." } });
      const matches = SavedSearchStore.evaluate(search, deps.issues.all());
      return reply.send({ search, matches });
    });
  };
}
