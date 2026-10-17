import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { quotaUsageFor } from "../lib/dailyQuota.js";

/// Exposes per-install daily quota state so the iOS app can render
/// transparent "X of Y AI requests left today" copy in the You tab
/// instead of waiting for an opaque 429.
///
/// Returns only the namespaces the install has actually touched today —
/// callers will display whichever ones come back. UTC-midnight reset
/// is implicit: a fresh day shows used=0 with the configured ceiling.

export function quotaRoute(): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/quota", async (request, reply) => {
      const raw = request.headers["x-athen-install"];
      const installID = Array.isArray(raw) ? raw[0] : raw;
      if (!installID || typeof installID !== "string" || installID.trim().length === 0) {
        return reply.code(401).send({
          error: { code: "install_required", message: "X-Athen-Install header required." },
        });
      }
      const usage = quotaUsageFor(installID.trim());
      return reply.send({ ok: true, usage });
    });
  };
}
