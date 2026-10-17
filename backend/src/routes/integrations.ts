import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import { COMPOSIO_APPS, ComposioService } from "../services/composio.js";

const MIN = 60_000;
const listLimiter = rateLimit({ name: "integrations:list", max: 120, windowMs: 5 * MIN });
const writeLimiter = rateLimit({ name: "integrations:write", max: 40, windowMs: 5 * MIN });
const execLimiter = rateLimit({ name: "integrations:exec", max: 60, windowMs: 5 * MIN });

const EntityHeader = z.object({
  "x-athen-entity": z.string().min(8).max(80),
});

const ConnectBody = z.object({
  appName: z.enum(COMPOSIO_APPS.map((a) => a.appName) as [string, ...string[]]),
});

const DisconnectParams = z.object({
  connectionId: z.string().min(8),
});

const SendEmailBody = z.object({
  to: z.string().email(),
  subject: z.string().min(1).max(998),
  body: z.string().min(1).max(20000),
});

const AutomateBody = z.object({
  automation: z.enum(["calendar_event", "notion_log", "slack_message", "discord_message", "twitter_post", "linkedin_post", "gmail_email"]),
  input: z.object({
    title: z.string().optional(),
    startISO: z.string().optional(),
    endISO: z.string().optional(),
    notes: z.string().optional(),
    location: z.string().optional(),
    databaseId: z.string().optional(),
    pageTitle: z.string().optional(),
    properties: z.record(z.unknown()).optional(),
    channel: z.string().optional(),
    text: z.string().optional(),
    body: z.string().optional(),
    hashtags: z.array(z.string()).optional(),
    to: z.string().optional(),
    subject: z.string().optional(),
  }),
});

export interface IntegrationsDeps {
  composio: ComposioService | null;
}

export function integrationsRoute(deps: IntegrationsDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/integrations/catalog", async (_request, reply) => {
      // Static catalog so the client can render the connection grid even when
      // Composio is disabled. Status is fetched separately.
      return reply.send({
        enabled: deps.composio !== null,
        apps: COMPOSIO_APPS,
      });
    });

    fastify.get("/v1/integrations", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      if (!deps.composio) {
        return reply.send({ enabled: false, items: COMPOSIO_APPS.map((a) => ({ appName: a.appName, isConnected: false })) });
      }
      const headers = EntityHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_entity", message: "x-athen-entity header required." } });
      }
      try {
        const items = await deps.composio.statusFor(headers.data["x-athen-entity"]);
        return reply.send({ enabled: true, items });
      } catch (err) {
        request.log.error({ err }, "composio status failed");
        return reply.code(502).send({
          error: { code: "composio_failed", message: err instanceof Error ? err.message : "Composio unreachable." },
        });
      }
    });

    fastify.post("/v1/integrations/connect", async (request, reply) => {
      if (!writeLimiter(request, reply)) return;
      if (!deps.composio) return reply.code(503).send({ error: { code: "composio_disabled", message: "COMPOSIO_API_KEY not set." } });
      const headers = EntityHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_entity", message: "x-athen-entity header required." } });
      }
      const body = ConnectBody.safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: body.error.message } });
      }
      try {
        const result = await deps.composio.initiateConnection(headers.data["x-athen-entity"], body.data.appName);
        return reply.send(result);
      } catch (err) {
        request.log.error({ err }, "composio connect failed");
        return reply.code(502).send({
          error: { code: "composio_connect_failed", message: err instanceof Error ? err.message : "Connect failed." },
        });
      }
    });

    fastify.delete("/v1/integrations/:connectionId", async (request, reply) => {
      if (!writeLimiter(request, reply)) return;
      if (!deps.composio) return reply.code(503).send({ error: { code: "composio_disabled", message: "COMPOSIO_API_KEY not set." } });
      const params = DisconnectParams.safeParse(request.params);
      if (!params.success) {
        return reply.code(400).send({ error: { code: "invalid_params", message: params.error.message } });
      }
      try {
        await deps.composio.disconnect(params.data.connectionId);
        return reply.send({ ok: true });
      } catch (err) {
        request.log.error({ err }, "composio disconnect failed");
        return reply.code(502).send({
          error: { code: "composio_disconnect_failed", message: err instanceof Error ? err.message : "Disconnect failed." },
        });
      }
    });

    fastify.post("/v1/integrations/automate", async (request, reply) => {
      if (!execLimiter(request, reply)) return;
      if (!deps.composio) return reply.code(503).send({ error: { code: "composio_disabled", message: "COMPOSIO_API_KEY not set." } });
      const headers = EntityHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_entity", message: "x-athen-entity header required." } });
      }
      const body = AutomateBody.safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: body.error.message } });
      }
      try {
        const result = await deps.composio.runAutomation({
          entityId: headers.data["x-athen-entity"],
          automation: body.data.automation,
          input: body.data.input,
        });
        if (!result.successful) {
          return reply.code(502).send({
            error: { code: "automation_failed", message: result.error ?? "Automation failed." },
          });
        }
        return reply.send({ ok: true, data: result.data });
      } catch (err) {
        return reply.code(502).send({
          error: { code: "automation_failed", message: err instanceof Error ? err.message : "Automation failed." },
        });
      }
    });

    // Convenience action: send an email via the user's connected Gmail.
    // Used by the filing dispatcher when "Send from my Gmail" is on.
    fastify.post("/v1/integrations/gmail/send", async (request, reply) => {
      if (!execLimiter(request, reply)) return;
      if (!deps.composio) return reply.code(503).send({ error: { code: "composio_disabled", message: "COMPOSIO_API_KEY not set." } });
      const headers = EntityHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_entity", message: "x-athen-entity header required." } });
      }
      const body = SendEmailBody.safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: body.error.message } });
      }
      try {
        const result = await deps.composio.executeAction({
          entityId: headers.data["x-athen-entity"],
          actionName: "GMAIL_SEND_EMAIL",
          input: {
            recipient_email: body.data.to,
            subject: body.data.subject,
            body: body.data.body,
            is_html: false,
          },
        });
        if (!result.successful) {
          return reply.code(502).send({
            error: { code: "gmail_send_failed", message: result.error ?? "Gmail send failed." },
          });
        }
        return reply.send({ ok: true, data: result.data });
      } catch (err) {
        request.log.error({ err }, "gmail send failed");
        return reply.code(502).send({
          error: { code: "gmail_send_failed", message: err instanceof Error ? err.message : "Gmail send failed." },
        });
      }
    });
  };
}
