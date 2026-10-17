import type { FastifyReply, FastifyRequest } from "fastify";

/**
 * In-memory sliding-window rate limiter. Keyed by client IP.
 *
 * Good enough for single-process / single-region deploys at small scale.
 * Replace with Redis-backed limiter if you scale beyond one process.
 */

interface Bucket {
  windowStart: number;
  count: number;
}

const BUCKETS: Map<string, Map<string, Bucket>> = new Map();

export interface RateLimitConfig {
  /** Identifier used to namespace buckets (e.g. "file:draft"). */
  name: string;
  /** Max requests allowed in the window. */
  max: number;
  /** Window length in milliseconds. */
  windowMs: number;
}

export function rateLimit(config: RateLimitConfig) {
  let nsBuckets = BUCKETS.get(config.name);
  if (!nsBuckets) {
    nsBuckets = new Map();
    BUCKETS.set(config.name, nsBuckets);
  }
  const buckets = nsBuckets;

  return function handler(request: FastifyRequest, reply: FastifyReply): boolean {
    const clientID = identify(request);
    const now = Date.now();
    const existing = buckets.get(clientID);

    if (!existing || now - existing.windowStart >= config.windowMs) {
      buckets.set(clientID, { windowStart: now, count: 1 });
      return true;
    }

    if (existing.count >= config.max) {
      const retryMs = config.windowMs - (now - existing.windowStart);
      const retrySeconds = Math.max(1, Math.ceil(retryMs / 1000));
      reply
        .header("Retry-After", String(retrySeconds))
        .code(429)
        .send({
          error: {
            code: "rate_limited",
            message: `Too many ${config.name} requests. Retry in ${retrySeconds}s.`,
          },
        });
      return false;
    }

    existing.count += 1;
    return true;
  };
}

function identify(request: FastifyRequest): string {
  const forwarded = request.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0]!.trim();
  }
  if (Array.isArray(forwarded) && forwarded.length > 0) {
    return forwarded[0]!.split(",")[0]!.trim();
  }
  return request.ip ?? "unknown";
}
