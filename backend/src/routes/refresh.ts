import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import type { IngestionOrchestrator } from "../services/ingestionOrchestrator.js";

const MIN = 60_000;
const refreshLimiter = rateLimit({ name: "refresh", max: 12, windowMs: 5 * MIN });
const streamLimiter = rateLimit({ name: "refresh:stream", max: 12, windowMs: 5 * MIN });

const RefreshBodySchema = z.object({
  only: z.array(z.string()).optional(),
  skip: z.array(z.string()).optional(),
  perConnectorLimit: z.number().int().min(1).max(40).optional(),
  legistarLookaheadDays: z.number().int().min(1).max(60).optional(),
  openStatesJurisdiction: z.string().min(2).max(80).optional(),
});

export interface RefreshRouteDeps {
  orchestrator: IngestionOrchestrator;
}

/**
 * Public refresh trigger. Calling clients (the iOS app, scheduled tasks, etc.)
 * hit this to kick a full ingestion pass and get back a per-source report.
 *
 * Rate-limited per client IP so a stuck refresh button doesn't hammer the
 * upstream APIs.
 */
export function refreshRoute(deps: RefreshRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/refresh", async (request, reply) => {
      if (!refreshLimiter(request, reply)) return;
      const parsed = RefreshBodySchema.safeParse(request.body ?? {});
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }
      try {
        const report = await deps.orchestrator.run(parsed.data);
        return reply.send(report);
      } catch (err) {
        request.log.error({ err }, "orchestrator failed");
        return reply.code(500).send({
          error: {
            code: "refresh_failed",
            message: err instanceof Error ? err.message : "Refresh failed.",
          },
        });
      }
    });

    /// SSE variant that streams per-source progress as connectors complete.
    /// Emits three event types:
    ///   - `source_start` — `{id, name}` right before a connector kicks off
    ///   - `source_done`  — full SourceReport the moment the connector lands
    ///   - `complete`     — final OrchestratorReport when all are done
    ///   - `error`        — `{message}` if the orchestrator itself blew up
    fastify.post("/v1/refresh/stream", async (request, reply) => {
      if (!streamLimiter(request, reply)) return;
      const parsed = RefreshBodySchema.safeParse(request.body ?? {});
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }

      // Hand the raw socket back to us — Fastify won't try to send its
      // own response when our async handler returns. Without this, Fastify
      // can clobber the stream the moment `await` yields.
      reply.hijack();
      reply.raw.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
        "X-Accel-Buffering": "no",
      });
      // Force TCP_NODELAY so SSE events flush the instant we write them.
      // Without this, Node coalesces multiple writes for ~40ms before
      // sending — fine for HTML but breaks the live-progress feel here.
      try { request.raw.socket?.setNoDelay(true); } catch {}
      try { (reply.raw as any).flushHeaders?.(); } catch {}

      const write = (event: string, data: unknown) => {
        try {
          reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
        } catch {
          // Client disconnected; we'll catch the close event below.
        }
      };

      // Heartbeat so iOS NSURLSession + intermediate proxies don't time out
      // when a connector is taking its sweet time.
      const heartbeat = setInterval(() => {
        try {
          reply.raw.write(`event: heartbeat\ndata: {"t":${Date.now()}}\n\n`);
        } catch {}
      }, 10_000);

      let aborted = false;
      // Listen on the underlying TCP socket — `request.raw.on("close")`
      // fires when the POST body upload finishes (instantly for small
      // payloads), which would mark us aborted before any work is done.
      // The socket close is the real disconnect signal.
      const socket = request.raw.socket;
      const onSocketClose = () => {
        aborted = true;
        clearInterval(heartbeat);
        try { reply.raw.end(); } catch {}
      };
      socket?.once("close", onSocketClose);

      write("started", { startedAt: new Date().toISOString() });
      try {
        const report = await deps.orchestrator.run({
          ...parsed.data,
          onSourceStart: (info) => {
            if (aborted) return;
            write("source_start", info);
          },
          onSourceDone: (rep) => {
            if (aborted) return;
            write("source_done", rep);
          },
        });
        if (!aborted) {
          write("complete", report);
          clearInterval(heartbeat);
          socket?.off("close", onSocketClose);
          reply.raw.end();
        }
      } catch (err) {
        request.log.error({ err }, "orchestrator stream failed");
        if (!aborted) {
          write("error", {
            message: err instanceof Error ? err.message : "Refresh failed.",
          });
          clearInterval(heartbeat);
          socket?.off("close", onSocketClose);
          reply.raw.end();
        }
      }
    });
  };
}
