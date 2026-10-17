import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import { dailyQuota } from "../lib/dailyQuota.js";
import type { SpeechService, SpeechRequest } from "../services/speech.js";

const MIN = 60_000;
const synthLimiter = rateLimit({ name: "speech:synthesize", max: 60, windowMs: 10 * MIN });
const voicesLimiter = rateLimit({ name: "speech:voices", max: 30, windowMs: 10 * MIN });

// Per-install daily character cap on ElevenLabs. 50k chars/day is enough for
// ~100 reads of an avg brief; abuse ceiling, not rationing.
const synthCharQuota = dailyQuota({
  name: "elevenlabs:chars",
  max: 50_000,
  weightFromBody: (body) => {
    if (!body || typeof body !== "object") return 0;
    const text = (body as { text?: unknown }).text;
    return typeof text === "string" ? text.length : 0;
  },
});

const Body = z.object({
  text: z.string().min(1).max(8_000),
  voiceId: z.string().min(1).max(128).optional(),
  modelId: z.string().min(1).max(128).optional(),
  stability: z.number().min(0).max(1).optional(),
  similarityBoost: z.number().min(0).max(1).optional(),
  style: z.number().min(0).max(1).optional(),
  speakerBoost: z.boolean().optional(),
});

export interface SpeechRouteDeps {
  speech: SpeechService;
}

export function speechRoute(deps: SpeechRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/speech/synthesize", async (request, reply) => {
      if (!synthLimiter(request, reply)) return;
      if (!synthCharQuota(request, reply)) return;
      const parsed = Body.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_body", message: parsed.error.message },
        });
      }
      const args: SpeechRequest = { text: parsed.data.text };
      if (parsed.data.voiceId) args.voiceId = parsed.data.voiceId;
      if (parsed.data.modelId) args.modelId = parsed.data.modelId;
      if (parsed.data.stability !== undefined) args.stability = parsed.data.stability;
      if (parsed.data.similarityBoost !== undefined) args.similarityBoost = parsed.data.similarityBoost;
      if (parsed.data.style !== undefined) args.style = parsed.data.style;
      if (parsed.data.speakerBoost !== undefined) args.speakerBoost = parsed.data.speakerBoost;

      try {
        const result = await deps.speech.synthesize(args);
        return reply.send(result);
      } catch (err) {
        request.log.error({ err }, "speech synth failed");
        return reply.code(502).send({
          error: {
            code: "speech_failed",
            message: err instanceof Error ? err.message : "Speech synth failed",
          },
        });
      }
    });

    fastify.get("/v1/speech/voices", async (request, reply) => {
      if (!voicesLimiter(request, reply)) return;
      try {
        const voices = await deps.speech.listVoices();
        return reply.send({ voices });
      } catch (err) {
        request.log.error({ err }, "speech voices failed");
        return reply.code(502).send({
          error: {
            code: "speech_voices_failed",
            message: err instanceof Error ? err.message : "Voice list failed",
          },
        });
      }
    });
  };
}
