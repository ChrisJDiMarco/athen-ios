import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { rateLimit } from "../lib/rateLimiter.js";
import type { PetitionStore } from "../services/petitionStore.js";
import type { ModerationStore } from "../services/moderationStore.js";

const MIN = 60_000;
const deleteLimiter = rateLimit({ name: "data:delete", max: 5, windowMs: 60 * MIN });

/// Apple Guideline 5.1.1(v) requires every app that creates an account or
/// collects user data to provide an in-app way to delete that data. We don't
/// have accounts, but we do have backend-side records keyed by install ID:
///   - Petition signatures (the signer's display name + ZIP prefix)
///   - Moderation reports they filed
///
/// This endpoint scrubs both. The iOS app handles UserDefaults wiping
/// on its own. Idempotent — calling twice is safe.

export interface DataDeleteRouteDeps {
  petitions: PetitionStore;
  moderation: ModerationStore;
}

export function dataDeleteRoute(deps: DataDeleteRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.delete("/v1/data", async (request, reply) => {
      if (!deleteLimiter(request, reply)) return;

      const raw = request.headers["x-athen-install"];
      const installId = Array.isArray(raw) ? raw[0] : raw;
      if (!installId || typeof installId !== "string" || installId.trim().length === 0) {
        return reply.code(401).send({
          error: {
            code: "install_required",
            message: "Per-install header required to identify what to delete.",
          },
        });
      }
      const id = installId.trim();

      // Petition signatures by this install
      const petitionsScrubbed = await deps.petitions.scrubByEntityId(id);
      // Moderation reports filed by this install
      const reportsScrubbed = await deps.moderation.scrubByReporter(id);

      return reply.send({
        ok: true,
        scrubbed: {
          petitionSignatures: petitionsScrubbed,
          moderationReports: reportsScrubbed,
        },
      });
    });
  };
}
