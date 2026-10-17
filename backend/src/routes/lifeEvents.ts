import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import { dailyQuota } from "../lib/dailyQuota.js";
import type { LifeEventsService, LifeEventProfile } from "../services/lifeEvents.js";

const MIN = 60_000;
const planLimiter = rateLimit({ name: "life-events:plan", max: 20, windowMs: 5 * MIN });
const planDailyQuota = dailyQuota({ name: "claude:life-event-plan", max: 30 });

const PlanBody = z.object({
  description: z.string().min(4).max(2000),
  profile: z
    .object({
      stateCode: z.string().length(2).optional(),
      stateName: z.string().min(1).optional(),
      zip: z.string().min(5).max(10).optional(),
      locality: z.string().min(1).optional(),
      factors: z.array(z.string()).optional(),
      householdSize: z.number().int().positive().optional(),
      incomeBand: z.string().optional(),
    })
    .optional(),
});

export interface LifeEventsRouteDeps {
  lifeEvents: LifeEventsService;
}

export function lifeEventsRoute(deps: LifeEventsRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/life-events/plan", async (request, reply) => {
      if (!planLimiter(request, reply)) return;
      if (!planDailyQuota(request, reply)) return;
      const parsed = PlanBody.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: parsed.error.message } });
      }
      try {
        const profile: LifeEventProfile = {};
        if (parsed.data.profile) {
          const p = parsed.data.profile;
          if (p.stateCode) profile.stateCode = p.stateCode;
          if (p.stateName) profile.stateName = p.stateName;
          if (p.zip) profile.zip = p.zip;
          if (p.locality) profile.locality = p.locality;
          if (p.factors) profile.factors = p.factors;
          if (p.householdSize) profile.householdSize = p.householdSize;
          if (p.incomeBand) profile.incomeBand = p.incomeBand;
        }
        const plan = await deps.lifeEvents.plan(parsed.data.description, profile);
        return reply.send({ plan });
      } catch (err) {
        request.log.error({ err }, "life event plan failed");
        return reply.code(502).send({
          error: {
            code: "plan_failed",
            message: err instanceof Error ? err.message : "Plan generation failed.",
          },
        });
      }
    });
  };
}
