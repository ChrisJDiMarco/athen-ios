import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { config } from "../config.js";

/**
 * Per-install bearer-token gate for /v1/* routes (excluding /healthz, /readyz,
 * and admin which has its own gate).
 *
 * The contract:
 *   - iOS sends `X-Athen-Install: <uuid>` on every request. The UUID is
 *     generated once on first launch and persisted in UserDefaults.
 *   - Backend accepts any non-empty UUID-shaped value when `INSTALL_AUTH_REQUIRED`
 *     is true. We don't verify *which* install — that would require a registry
 *     and registration flow we don't yet have. What this DOES prevent:
 *       • Drive-by scanners hitting the bare endpoint
 *       • A leaked backend URL being abused without app context
 *       • Bots that don't bother to send a custom header
 *   - When `INSTALL_AUTH_REQUIRED=false` (default), the gate is a no-op so dev
 *     loops aren't broken.
 *
 * v1.1 plan: replace this with a per-install signed JWT minted by backend on
 * first contact, with a rolling rotation window. Today's gate is the minimum
 * viable defense against opportunistic abuse, not a strong authn boundary.
 */
const HEADER = "x-athen-install";
const UUID_RE = /^[0-9a-fA-F-]{36}$/;

const ALLOW_PREFIXES = ["/healthz", "/readyz", "/v1/admin/"];

export function registerInstallAuth(fastify: FastifyInstance): void {
  if (!config.INSTALL_AUTH_REQUIRED) {
    fastify.log.info("Install auth disabled (INSTALL_AUTH_REQUIRED=false) — open mode");
    return;
  }
  fastify.log.info("Install auth enabled — requires X-Athen-Install on /v1/*");

  fastify.addHook("onRequest", async (request: FastifyRequest, reply: FastifyReply) => {
    const url = request.url ?? "";
    if (ALLOW_PREFIXES.some((p) => url.startsWith(p))) return;
    if (!url.startsWith("/v1/")) return;

    const raw = request.headers[HEADER];
    const install = Array.isArray(raw) ? raw[0] : raw;
    if (!install || typeof install !== "string" || !UUID_RE.test(install.trim())) {
      reply.code(401).send({
        error: {
          code: "install_required",
          message: "This endpoint requires the X-Athen-Install header (per-install UUID).",
        },
      });
      return reply;
    }
  });
}
