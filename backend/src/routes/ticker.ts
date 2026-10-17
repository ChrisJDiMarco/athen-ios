import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import type { IssueStore } from "../services/issueStore.js";
import type { VoteStore } from "../services/voteStore.js";

/// Server-sent events stream of recent civic activity:
///   - bill ingested
///   - vote recorded
///   - petition delivered (TODO: hook from petition delivery worker)
///
/// Lets a future iOS widget / lock-screen activity show "what just happened"
/// without polling. Also useful for journalists embedding via EventSource.
///
/// Format: one `data: {json}\n\n` per event. Client should reconnect on disconnect.
/// Heartbeat every 30s so proxies don't kill the connection.

export interface TickerRouteDeps {
  issues: IssueStore;
  votes: VoteStore;
}

export function tickerRoute(deps: TickerRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/activity/ticker", async (request, reply) => {
      reply.raw.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
        "X-Accel-Buffering": "no",
      });

      // On connect, send the last 20 events as backfill.
      const backfill = recentEvents(deps, 20);
      for (const ev of backfill) {
        reply.raw.write(`data: ${JSON.stringify(ev)}\n\n`);
      }

      // Heartbeat keeps the connection alive across NAT timeouts and proxies.
      // True realtime push (new bill, new vote) will hook here in v1.1 — for
      // v1, periodic poll of the stores gives the same effect at lower cost.
      const interval = setInterval(() => {
        reply.raw.write(`event: heartbeat\ndata: {"t":${Date.now()}}\n\n`);
      }, 30_000);

      request.raw.on("close", () => {
        clearInterval(interval);
        reply.raw.end();
      });
    });
  };
}

interface TickerEvent {
  type: "bill" | "vote";
  id: string;
  title: string;
  scope?: string;
  jurisdiction?: string;
  timestamp: string;
  meta?: Record<string, unknown>;
}

function recentEvents(deps: TickerRouteDeps, limit: number): TickerEvent[] {
  const events: TickerEvent[] = [];

  // Recent bills — sort by voteDate desc, take top N.
  const recentIssues = deps.issues
    .all()
    .filter((i) => Date.parse(i.voteDateISO) > 0)
    .sort((a, b) => Date.parse(b.voteDateISO) - Date.parse(a.voteDateISO))
    .slice(0, limit);

  for (const issue of recentIssues) {
    events.push({
      type: "bill",
      id: issue.id,
      title: issue.title,
      scope: issue.scope,
      jurisdiction: issue.jurisdiction,
      timestamp: issue.voteDateISO,
      meta: { impactLevel: issue.impactLevel, sourceName: issue.sourceName },
    });
  }

  // VoteStore exposes vote records but the iteration shape varies — defer
  // vote push to v1.1 when we have a dedicated recent-votes index.

  return events
    .sort((a, b) => Date.parse(b.timestamp) - Date.parse(a.timestamp))
    .slice(0, limit);
}
