import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { CivicError } from "../lib/errors.js";
import type { LocationResolver, ResolvedLocation } from "../services/locationResolver.js";
import type { OfficialResolver, OfficialsTree } from "../services/officialResolver.js";

const ResolveRequestSchema = z.object({
  zip: z.string().min(5).max(10).optional(),
  address: z.string().min(3).max(300).optional(),
}).refine((v) => Boolean(v.zip) || Boolean(v.address), {
  message: "Provide either 'zip' or 'address'.",
});

export interface ProfileRouteDeps {
  locations: LocationResolver;
  officials: OfficialResolver;
}

export function profileRoute(deps: ProfileRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/profile/resolve", async (request, reply) => {
      const parsed = ResolveRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }

      try {
        const location = parsed.data.address
          ? await deps.locations.resolveFromAddress(parsed.data.address)
          : await deps.locations.resolveFromZip(parsed.data.zip!);

        const tree = await deps.officials.treeFor(location);

        return reply.send({
          location: shapeLocation(location),
          officials: shapeTree(tree),
        });
      } catch (err) {
        if (err instanceof CivicError) {
          return reply
            .code(err.statusCode)
            .send({ error: { code: err.code, message: err.message } });
        }
        request.log.error({ err }, "profile resolve failed");
        return reply.code(500).send({
          error: { code: "resolve_failed", message: "Could not resolve location." },
        });
      }
    });
  };
}

function shapeLocation(loc: ResolvedLocation) {
  return {
    zipCode: loc.zipCode,
    stateCode: loc.stateCode,
    stateName: loc.stateName,
    city: loc.city,
    normalized: loc.normalized,
    source: loc.source,
  };
}

function shapeTree(tree: OfficialsTree) {
  return {
    federalSenators: tree.federalSenators.map((o) => ({
      name: o.name,
      title: o.title,
      level: "federal-senate",
      district: o.district,
      contactLabel: o.source,
    })),
    federalHouseRep: tree.federalHouseRep
      ? {
          name: tree.federalHouseRep.name,
          title: tree.federalHouseRep.title,
          level: "federal-house",
          district: tree.federalHouseRep.district,
          contactLabel: tree.federalHouseRep.source,
        }
      : null,
    stateSenators: tree.stateSenators.map((o) => ({
      name: o.name,
      title: o.title,
      level: "state-senate",
      district: o.district,
      contactLabel: o.source,
    })),
    stateRepresentatives: tree.stateRepresentatives.map((o) => ({
      name: o.name,
      title: o.title,
      level: "state-house",
      district: o.district,
      contactLabel: o.source,
    })),
    local: tree.local.map((o) => ({
      name: o.name,
      title: o.title,
      level: "local",
      district: o.district,
      contactLabel: o.source,
    })),
  };
}
