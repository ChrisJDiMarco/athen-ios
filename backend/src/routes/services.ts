import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { matchServices, serviceCatalog, type ServiceMatchProfile } from "../services/serviceCatalog.js";

const ServicesQuerySchema = z.object({
  category: z.string().max(40).optional(),
  needs: z.union([z.string(), z.array(z.string())]).optional(),
  signals: z.union([z.string(), z.array(z.string())]).optional(),
  documents: z.union([z.string(), z.array(z.string())]).optional(),
  language: z.string().max(40).optional(),
  limit: z.coerce.number().int().positive().max(50).optional(),
});

export function servicesRoute(): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/services", async (request, reply) => {
      const parsed = ServicesQuerySchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_query", message: parsed.error.message },
        });
      }

      const profile: ServiceMatchProfile = {
        needs: splitQueryList(parsed.data.needs),
        signals: splitQueryList(parsed.data.signals),
        preparedDocuments: splitQueryList(parsed.data.documents),
      };
      if (parsed.data.language) profile.language = parsed.data.language;

      const hasPersonalization =
        profile.needs.length > 0 ||
        profile.signals.length > 0 ||
        profile.preparedDocuments.length > 0 ||
        Boolean(profile.language);

      const services = hasPersonalization
        ? matchServices(profile, { limit: parsed.data.limit, category: parsed.data.category })
        : serviceCatalog
            .filter((service) => !parsed.data.category || service.category === parsed.data.category)
            .slice(0, parsed.data.limit ?? serviceCatalog.length);

      return reply.send({
        generatedAtISO: new Date().toISOString(),
        count: services.length,
        services,
      });
    });
  };
}

function splitQueryList(value: string | string[] | undefined): string[] {
  if (!value) return [];
  const values = Array.isArray(value) ? value : [value];
  return values
    .flatMap((entry) => entry.split(","))
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}
