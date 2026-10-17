import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import { dailyQuota } from "../lib/dailyQuota.js";
import type { AudioBriefingService } from "../services/audioBriefing.js";

const MIN = 60_000;
const briefingLimiter = rateLimit({ name: "briefing:audio", max: 10, windowMs: 10 * MIN });
const briefingDailyQuota = dailyQuota({ name: "audio-briefing", max: 8 });

const Query = z.object({
  stateCode: z.string().length(2).optional(),
  stateName: z.string().min(2).max(60).optional(),
  zip: z.string().min(5).max(10).optional(),
  limit: z.coerce.number().int().min(1).max(6).optional(),
  // Listener-controlled customization (added 2026-05-21):
  // - duration: target minutes for the spoken briefing (5/10/15)
  // - voiceId: ElevenLabs voice ID override
  // - focus:   free-text direction ("focus on housing", "skip federal", etc.)
  duration: z.coerce.number().int().refine((n) => n === 5 || n === 10 || n === 15, {
    message: "duration must be 5, 10, or 15",
  }).optional(),
  voiceId: z.string().min(8).max(64).optional(),
  focus: z.string().max(500).optional(),
});

export interface BriefingRouteDeps {
  audioBriefing: AudioBriefingService;
}

export function briefingRoute(deps: BriefingRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/briefing/audio", async (request, reply) => {
      if (!briefingLimiter(request, reply)) return;
      if (!briefingDailyQuota(request, reply)) return;
      const parsed = Query.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_query", message: parsed.error.message },
        });
      }
      try {
        const args: Parameters<AudioBriefingService["render"]>[0] = {};
        if (parsed.data.stateCode) args.stateCode = parsed.data.stateCode;
        if (parsed.data.stateName) args.stateName = parsed.data.stateName;
        if (parsed.data.zip) args.zip = parsed.data.zip;
        if (parsed.data.limit !== undefined) args.limit = parsed.data.limit;
        if (parsed.data.duration !== undefined) args.duration = parsed.data.duration as 5 | 10 | 15;
        if (parsed.data.voiceId) args.voiceId = parsed.data.voiceId;
        if (parsed.data.focus) args.focus = parsed.data.focus;
        const result = await deps.audioBriefing.render(args);
        return reply.send(result);
      } catch (err) {
        request.log.error({ err }, "audio briefing failed");
        return reply.code(502).send({
          error: {
            code: "briefing_failed",
            message: err instanceof Error ? err.message : "Briefing failed",
          },
        });
      }
    });
  };
}
