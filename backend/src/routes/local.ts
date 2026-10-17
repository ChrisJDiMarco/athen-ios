import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import type { LocalDataService } from "../services/localData.js";

const MIN = 60_000;
const lookupLimiter = rateLimit({ name: "local:lookup", max: 60, windowMs: 5 * MIN });

const DatasetQuery = z.object({
  q: z.string().min(2).max(100),
  limit: z.coerce.number().int().min(1).max(25).optional(),
});

const FetchQuery = z.object({
  domain: z.string().min(3).max(100),
  id: z.string().min(4).max(50),
  limit: z.coerce.number().int().min(1).max(100).optional(),
});

const ZipQuery = z.object({
  zip: z.string().min(5).max(10),
  limit: z.coerce.number().int().min(1).max(50).optional(),
});

export interface LocalRouteDeps {
  localData: LocalDataService;
}

export function localRoute(deps: LocalRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/local/datasets/search", async (request, reply) => {
      if (!lookupLimiter(request, reply)) return;
      const parsed = DatasetQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      const datasets = await deps.localData.findDatasets(parsed.data.q, parsed.data.limit ?? 10);
      return reply.send({ enabled: deps.localData.socrataEnabled, datasets });
    });

    fastify.get("/v1/local/datasets/rows", async (request, reply) => {
      if (!lookupLimiter(request, reply)) return;
      const parsed = FetchQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      const rows = await deps.localData.fetchRows(parsed.data.domain, parsed.data.id, parsed.data.limit ?? 25);
      return reply.send({ rows });
    });

    fastify.get("/v1/local/311", async (request, reply) => {
      if (!lookupLimiter(request, reply)) return;
      const parsed = ZipQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      const endpoint = deps.localData.endpointForZip(parsed.data.zip);
      const requests = await deps.localData.recentRequests(parsed.data.zip, parsed.data.limit ?? 10);
      return reply.send({
        enabled: deps.localData.open311Enabled,
        endpoint,
        requests,
      });
    });
  };
}
