import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import type { ModerationStore } from "../services/moderationStore.js";

const MIN = 60_000;
// Limit each IP to 30 reports per hour. Reports beyond that suggest abuse
// (mass-reporting a target user) and should be throttled, not honored.
const reportLimiter = rateLimit({ name: "moderation:report", max: 30, windowMs: 60 * MIN });

const ReportBody = z.object({
  postId: z.string().min(1).max(64),
  reason: z.string().min(1).max(500),
});

export interface ModerationRouteDeps {
  store: ModerationStore;
}

export function moderationRoute(deps: ModerationRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/moderation/report", async (request, reply) => {
      if (!reportLimiter(request, reply)) return;
      const parsed = ReportBody.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_body", message: parsed.error.message },
        });
      }

      const raw = request.headers["x-athen-install"];
      const installId = Array.isArray(raw) ? raw[0] : raw;
      if (!installId || typeof installId !== "string") {
        return reply.code(401).send({
          error: { code: "install_required", message: "Per-install header required for reports." },
        });
      }

      try {
        const record = await deps.store.report({
          postId: parsed.data.postId,
          reason: parsed.data.reason,
          reporterInstallId: installId.trim(),
        });
        return reply.send({
          id: record.id,
          status: record.status,
          reportedAt: record.reportedAt,
          autoHideThresholdReached: deps.store.reportsForPost(parsed.data.postId) >= 3,
        });
      } catch (err) {
        request.log.error({ err }, "moderation report failed");
        return reply.code(502).send({
          error: {
            code: "report_failed",
            message: err instanceof Error ? err.message : "Could not record report.",
          },
        });
      }
    });
  };
}
