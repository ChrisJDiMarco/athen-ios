import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { CivicError } from "../lib/errors.js";
import type { NewsCorroborator, IssueScopeForNews } from "../services/newsCorroborator.js";

const BackgroundRequestSchema = z.object({
  issueTitle: z.string().min(1).max(300),
  jurisdiction: z.string().min(1).max(200),
  scope: z.enum(["federal", "state", "local-philly", "unknown"]),
  stateCode: z.string().length(2).optional(),
});

export interface BackgroundRouteDeps {
  corroborator: NewsCorroborator;
}

export function backgroundRoute(deps: BackgroundRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/issue/background", async (request, reply) => {
      const parsed = BackgroundRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }

      try {
        const args: Parameters<NewsCorroborator["background"]>[0] = {
          issueTitle: parsed.data.issueTitle,
          jurisdiction: parsed.data.jurisdiction,
          scope: parsed.data.scope as IssueScopeForNews,
        };
        if (parsed.data.stateCode) args.stateCode = parsed.data.stateCode;
        const result = await deps.corroborator.background(args);
        if (!result) {
          return reply.send({ summary: null, citations: [], generatedAt: null });
        }
        return reply.send(result);
      } catch (err) {
        if (err instanceof CivicError) {
          return reply
            .code(err.statusCode)
            .send({ error: { code: err.code, message: err.message } });
        }
        request.log.error({ err }, "background lookup failed");
        return reply.code(500).send({
          error: { code: "background_failed", message: "Could not fetch background reading." },
        });
      }
    });
  };
}
