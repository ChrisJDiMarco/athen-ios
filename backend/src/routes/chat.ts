import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { CivicError } from "../lib/errors.js";
import { dailyQuota } from "../lib/dailyQuota.js";
import type { ChatAssistant, ChatContext, ChatTurn } from "../services/chatAssistant.js";

const chatDailyQuota = dailyQuota({ name: "claude:chat", max: 100 });

const ChatRequestSchema = z.object({
  messages: z
    .array(
      z.object({
        role: z.enum(["user", "assistant"]),
        content: z.string().max(8000),
      }),
    )
    .min(1),
  context: z.object({
    profile: z
      .object({
          zipCode: z.string(),
          stateCode: z.string(),
          stateName: z.string(),
          localityLabel: z.string().optional(),
          factors: z.array(z.string()).optional(),
          officials: z.object({
          federalSenators: z.array(z.object({ name: z.string(), title: z.string(), district: z.string().optional() })),
          federalHouseRep: z
            .object({ name: z.string(), title: z.string(), district: z.string().optional() })
            .optional(),
          stateSenators: z.array(z.object({ name: z.string(), title: z.string(), district: z.string().optional() })),
          stateRepresentatives: z.array(z.object({ name: z.string(), title: z.string(), district: z.string().optional() })),
          local: z.array(z.object({ name: z.string(), title: z.string(), district: z.string().optional() })),
        }),
      })
      .optional(),
    visibleIssues: z.array(
      z.object({
        id: z.string(),
        title: z.string(),
        jurisdiction: z.string(),
        scope: z.string(),
        impactLevel: z.string(),
        voteDateISO: z.string(),
        summary: z.string(),
        whyItMatters: z.string().optional(),
        recommendedAction: z.string().optional(),
        trustScore: z.number().optional(),
        sourceName: z.string().optional(),
      }),
    ),
    filingHistory: z.array(
      z.object({
        issueTitle: z.string(),
        action: z.enum(["endorse", "oppose"]),
        officialName: z.string(),
        sentAt: z.string(),
        confirmationCode: z.string(),
      }),
    ),
    matchedServices: z
      .array(
        z.object({
          id: z.string(),
          title: z.string(),
          category: z.string(),
          provider: z.string(),
          summary: z.string(),
          matchScore: z.number(),
          nextStep: z.string(),
          missingDocuments: z.array(z.string()),
          sourceName: z.string(),
          sourceURL: z.string(),
        }),
      )
      .default([]),
  }),
});

export interface ChatRouteDeps {
  assistant: ChatAssistant;
}

export function chatRoute(deps: ChatRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/chat", async (request, reply) => {
      if (!chatDailyQuota(request, reply)) return;
      const parsed = ChatRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }

      reply.raw.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
        "X-Accel-Buffering": "no",
      });

      const messages = parsed.data.messages as ChatTurn[];
      const context = parsed.data.context as ChatContext;

      try {
        for await (const event of deps.assistant.stream({ messages, context })) {
          if ("delta" in event) {
            reply.raw.write(`event: delta\ndata: ${JSON.stringify({ text: event.delta })}\n\n`);
          } else if ("tool_start" in event) {
            reply.raw.write(`event: tool_start\ndata: ${JSON.stringify(event.tool_start)}\n\n`);
          } else if ("tool_done" in event) {
            reply.raw.write(`event: tool_done\ndata: ${JSON.stringify(event.tool_done)}\n\n`);
          } else if ("done" in event) {
            reply.raw.write(`event: done\ndata: {}\n\n`);
          }
        }
      } catch (err) {
        const message =
          err instanceof CivicError
            ? err.message
            : err instanceof Error
              ? err.message
              : "Chat stream failed.";
        request.log.error({ err }, "chat stream failed");
        reply.raw.write(`event: error\ndata: ${JSON.stringify({ message })}\n\n`);
      } finally {
        reply.raw.end();
      }
    });
  };
}
