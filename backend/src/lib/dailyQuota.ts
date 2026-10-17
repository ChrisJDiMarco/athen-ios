import type { FastifyReply, FastifyRequest } from "fastify";

/**
 * In-memory daily quota per install ID. Resets at UTC midnight.
 *
 * Two quota types:
 *   • Calls — for endpoints (Claude-backed: brief, chat, plan, draft, etc).
 *   • Characters — for endpoints whose cost scales with content length
 *     (ElevenLabs speech synth).
 *
 * Keyed by `X-Athen-Install` header. Falls back to client IP if missing.
 * If `INSTALL_AUTH_REQUIRED=true`, installAuth has already rejected requests
 * without the header, so the fallback only matters in dev.
 *
 * Limits are deliberately generous for v1 — these are abuse ceilings, not
 * rationing. Adjust upward freely once we have real usage data.
 */

interface DayBucket {
  dayKey: string;
  total: number;
}

const QUOTAS: Map<string, Map<string, DayBucket>> = new Map();
const LIMITS: Map<string, number> = new Map();

export interface QuotaUsage {
  /** Quota name, e.g. "claude:brief". */
  name: string;
  /** Units used today by this install. */
  used: number;
  /** Configured per-day ceiling. */
  max: number;
  /** Remaining capacity until UTC midnight. */
  remaining: number;
}

/** Snapshot of every quota for one install. Used by /v1/quota. */
export function quotaUsageFor(installID: string): QuotaUsage[] {
  const dayKey = utcDayKey();
  const key = `install:${installID}`;
  const out: QuotaUsage[] = [];
  for (const [name, buckets] of QUOTAS.entries()) {
    const max = LIMITS.get(name) ?? 0;
    const bucket = buckets.get(key);
    const used = bucket && bucket.dayKey === dayKey ? bucket.total : 0;
    out.push({ name, used, max, remaining: Math.max(0, max - used) });
  }
  return out.sort((a, b) => a.name.localeCompare(b.name));
}

export interface DailyQuotaConfig {
  /** Identifier for telemetry/messages (e.g. "claude:brief"). */
  name: string;
  /** Max units per day. Units are calls unless `weightFromBody` is provided. */
  max: number;
  /** When provided, computes the per-request weight from the request body
   *  (e.g. for ElevenLabs return `body.text.length`). Default: 1 per call. */
  weightFromBody?: (body: unknown) => number;
}

export function dailyQuota(config: DailyQuotaConfig) {
  let nsBuckets = QUOTAS.get(config.name);
  if (!nsBuckets) {
    nsBuckets = new Map();
    QUOTAS.set(config.name, nsBuckets);
  }
  LIMITS.set(config.name, config.max);
  const buckets = nsBuckets;

  return function handler(request: FastifyRequest, reply: FastifyReply): boolean {
    const installID = identify(request);
    const dayKey = utcDayKey();
    const existing = buckets.get(installID);
    const weight = config.weightFromBody ? Math.max(0, config.weightFromBody(request.body)) : 1;

    if (!existing || existing.dayKey !== dayKey) {
      // New day or first request — reset.
      if (weight > config.max) {
        reply.code(429).send({
          error: {
            code: "quota_exceeded",
            message: `Request exceeds the per-day ${config.name} quota.`,
          },
        });
        return false;
      }
      buckets.set(installID, { dayKey, total: weight });
      return true;
    }

    if (existing.total + weight > config.max) {
      reply
        .header("Retry-After", String(secondsUntilUtcMidnight()))
        .code(429)
        .send({
          error: {
            code: "daily_quota_exceeded",
            message: `Daily quota for ${config.name} reached. Resets at UTC midnight.`,
          },
        });
      return false;
    }

    existing.total += weight;
    return true;
  };
}

function identify(request: FastifyRequest): string {
  const raw = request.headers["x-athen-install"];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (typeof value === "string" && value.trim().length > 0) {
    return `install:${value.trim()}`;
  }
  const forwarded = request.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return `ip:${forwarded.split(",")[0]!.trim()}`;
  }
  return `ip:${request.ip ?? "unknown"}`;
}

function utcDayKey(): string {
  const d = new Date();
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
}

function secondsUntilUtcMidnight(): number {
  const now = new Date();
  const midnight = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + 1,
    0, 0, 0, 0,
  ));
  return Math.max(1, Math.ceil((midnight.getTime() - now.getTime()) / 1000));
}
