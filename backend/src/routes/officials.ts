import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import type { OfficialsDirectoryService } from "../services/officialsDirectory.js";

const MIN = 60_000;
const listLimiter = rateLimit({ name: "officials:list", max: 120, windowMs: 5 * MIN });
const refreshLimiter = rateLimit({ name: "officials:refresh", max: 6, windowMs: 60 * MIN });

const StateParam = z.object({ stateCode: z.string().length(2) });
const SearchQuery = z.object({ q: z.string().min(2).max(60) });
const IdParam = z.object({ id: z.string().min(2) });

export interface OfficialsRouteDeps {
  directory: OfficialsDirectoryService;
}

export function officialsRoute(deps: OfficialsRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/officials/federal", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      return reply.send({
        officials: deps.directory.federal(),
        stats: deps.directory.stats(),
      });
    });

    fastify.post("/v1/officials/federal/refresh", async (request, reply) => {
      if (!refreshLimiter(request, reply)) return;
      try {
        const officials = await deps.directory.federalRefreshed();
        return reply.send({ officials, stats: deps.directory.stats() });
      } catch (err) {
        return reply.code(502).send({
          error: { code: "directory_refresh_failed", message: err instanceof Error ? err.message : "Refresh failed." },
        });
      }
    });

    fastify.get("/v1/officials/state/:stateCode", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      const parsed = StateParam.safeParse(request.params);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_params", message: parsed.error.message } });
      }
      const officials = await deps.directory.state(parsed.data.stateCode);
      return reply.send({ officials });
    });

    fastify.get("/v1/officials/search", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      const parsed = SearchQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      const officials = deps.directory.search(parsed.data.q);
      return reply.send({ officials });
    });

    fastify.get("/v1/officials/:id", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      const parsed = IdParam.safeParse(request.params);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_params", message: parsed.error.message } });
      }
      const official = deps.directory.findById(parsed.data.id);
      if (!official) {
        return reply.code(404).send({ error: { code: "official_not_found", message: "Not in directory." } });
      }
      return reply.send({ official });
    });
  };
}
