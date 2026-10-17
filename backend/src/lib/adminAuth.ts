import type { FastifyReply, FastifyRequest } from "fastify";
import { config } from "../config.js";

/**
 * Bearer-token gate for /v1/admin/* routes. Returns true if the request is
 * authorized to proceed; otherwise writes the appropriate response and returns
 * false (the caller should return immediately).
 *
 * Locked-down default: if ADMIN_API_TOKEN is unset, all admin routes are denied
 * regardless of request. This is intentional — admin endpoints stay safe by
 * default until the operator explicitly opts in.
 */
export function requireAdminAuth(request: FastifyRequest, reply: FastifyReply): boolean {
  if (!config.ADMIN_API_TOKEN) {
    reply.code(503).send({
      error: {
        code: "admin_locked",
        message: "Admin routes are disabled. Set ADMIN_API_TOKEN to enable.",
      },
    });
    return false;
  }

  const header = request.headers.authorization ?? "";
  const expected = `Bearer ${config.ADMIN_API_TOKEN}`;

  if (header !== expected) {
    reply.code(401).send({
      error: { code: "unauthorized", message: "Missing or invalid admin token." },
    });
    return false;
  }

  return true;
}
