import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import { analyzeBallotText } from "../services/ballotAnalysis.js";

const MIN = 60_000;
const limiter = rateLimit({ name: "ballot:analyze", max: 12, windowMs: 5 * MIN });

const Body = z.object({
  // OCR-extracted ballot text from the iOS Vision pass. Capped at 16k chars
  // so a stuck OCR can't blow up our Claude budget.
  text: z.string().min(20).max(16000),
});

export function ballotRoute(): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/ballot/analyze", async (request, reply) => {
      if (!limiter(request, reply)) return;
      const parsed = Body.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_body", message: parsed.error.message },
        });
      }
      try {
        const analysis = await analyzeBallotText(parsed.data.text);
        return reply.send(analysis);
      } catch (err) {
        request.log.error({ err }, "ballot analysis failed");
        return reply.code(502).send({
          error: {
            code: "ballot_failed",
            message: err instanceof Error ? err.message : "Ballot analysis failed.",
          },
        });
      }
    });
  };
}
