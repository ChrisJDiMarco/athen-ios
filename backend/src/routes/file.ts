import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { CivicError } from "../lib/errors.js";
import { newConfirmationCode } from "../lib/confirmationCode.js";
import { rateLimit } from "../lib/rateLimiter.js";
import type { LocationResolver, ResolvedLocation } from "../services/locationResolver.js";
import type { OfficialResolver } from "../services/officialResolver.js";
import type { MessageDrafter } from "../services/messageDrafter.js";
import type { FilingDispatcher } from "../services/filingDispatcher.js";
import type { FilingReceipt, ResolvedOfficial } from "../lib/types.js";
import type { ComposioService } from "../services/composio.js";
import type { FilingTallyStore } from "../services/filingTallyStore.js";

const HOUR_MS = 60 * 60 * 1000;
const draftLimiter = rateLimit({ name: "file:draft", max: 30, windowMs: HOUR_MS });
const sendLimiter = rateLimit({ name: "file:send", max: 10, windowMs: HOUR_MS });
const legacyLimiter = rateLimit({ name: "file:legacy", max: 10, windowMs: HOUR_MS });

const IssueSchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  category: z.string().min(1),
  jurisdiction: z.string().min(1),
  sourceName: z.string().min(1),
  summary: z.string().min(1),
  facts: z
    .array(z.object({ label: z.string().min(1), value: z.string().min(1) }))
    .min(1),
  voteDateISO: z.string().min(1),
});

const DraftRequestSchema = z.object({
  action: z.enum(["endorse", "oppose"]),
  address: z.string().min(3).max(300),
  issue: IssueSchema,
});

const SendRequestSchema = z.object({
  action: z.enum(["endorse", "oppose"]),
  address: z.string().min(3).max(300),
  issue: IssueSchema,
  message: z.object({
    subject: z.string().min(1).max(300),
    body: z.string().min(1).max(8000),
  }),
  // When true, route the email through the user's own Gmail account via
  // Composio instead of the backend mailer. Requires `entityId`.
  useUserGmail: z.boolean().optional(),
  entityId: z.string().min(8).max(80).optional(),
});

const LegacyFileRequestSchema = DraftRequestSchema;

export interface FileRouteDeps {
  locations: LocationResolver;
  officials: OfficialResolver;
  drafter: MessageDrafter;
  dispatcher: FilingDispatcher;
  composio?: ComposioService | null;
  tally?: FilingTallyStore;
}

export function fileRoute(deps: FileRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/file/draft", async (request, reply) => {
      if (!draftLimiter(request, reply)) return;
      const parsed = DraftRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }
      const { action, address, issue } = parsed.data;

      try {
        const location = await resolveLocation(deps.locations, address);
        const official = await deps.officials.resolve(issue.jurisdiction, location);
        const draft = await deps.drafter.draft({
          action,
          issue,
          address: draftAddressFor(address, location),
          official,
        });

        return reply.send({
          draft,
          official: publicOfficial(official),
          verifiedAddress: location.normalized ?? `${location.stateName} (${location.zipCode})`,
        });
      } catch (err) {
        return handleError(reply, request, err, "draft");
      }
    });

    fastify.post("/v1/file/send", async (request, reply) => {
      if (!sendLimiter(request, reply)) return;
      const parsed = SendRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }
      const { action, address, issue, message, useUserGmail, entityId } = parsed.data;

      try {
        // Re-resolve the official server-side so the iOS client can't redirect
        // the email to an arbitrary inbox. The message body is user-editable;
        // the destination is not.
        const location = await resolveLocation(deps.locations, address);
        const official = await deps.officials.resolve(issue.jurisdiction, location);

        let dispatch;
        if (useUserGmail && entityId && deps.composio && official.email && (official.channel ?? "email") === "email") {
          // Route through the user's own Gmail via Composio. We still keep
          // the official's resolved email — the destination is server-locked.
          const exec = await deps.composio.executeAction({
            entityId,
            actionName: "GMAIL_SEND_EMAIL",
            input: {
              recipient_email: official.email,
              subject: message.subject,
              body: message.body,
              is_html: false,
            },
          });
          if (!exec.successful) {
            throw new CivicError(
              "gmail_send_failed",
              exec.error ?? "Gmail send failed via Composio.",
              502,
            );
          }
          dispatch = {
            channel: "email" as const,
            trackingId: `gmail:${entityId.slice(0, 8)}`,
            deliveredTo: official.email,
            queued: false,
            dryRun: false,
            statusNote: `Sent from your Gmail to ${official.email}.`,
          };
        } else {
          const dispatchArgs: Parameters<FilingDispatcher["dispatch"]>[0] = {
            official,
            message,
            constituentZip: location.zipCode,
          };
          if (location.stateCode) dispatchArgs.constituentStateCode = location.stateCode;
          dispatch = await deps.dispatcher.dispatch(dispatchArgs);
        }

        const receipt: FilingReceipt = {
          action,
          sentAt: new Date().toISOString(),
          officialName: official.name,
          confirmationCode: newConfirmationCode(),
          messagePreview: previewFrom(message.body),
        };

        if (deps.tally) {
          await deps.tally.increment(issue.id, action);
        }

        return reply.send({
          receipt,
          delivery: dispatch,
          verifiedAddress: location.normalized ?? `${location.stateName} (${location.zipCode})`,
        });
      } catch (err) {
        return handleError(reply, request, err, "send");
      }
    });

    // Legacy one-shot path. Drafts + sends without user review.
    fastify.post("/v1/file", async (request, reply) => {
      if (!legacyLimiter(request, reply)) return;
      const parsed = LegacyFileRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }
      const { action, address, issue } = parsed.data;

      try {
        const location = await resolveLocation(deps.locations, address);
        const official = await deps.officials.resolve(issue.jurisdiction, location);
        const message = await deps.drafter.draft({
          action,
          issue,
          address: draftAddressFor(address, location),
          official,
        });
        const dispatchArgs: Parameters<FilingDispatcher["dispatch"]>[0] = {
          official,
          message,
          constituentZip: location.zipCode,
        };
        if (location.stateCode) dispatchArgs.constituentStateCode = location.stateCode;
        const dispatch = await deps.dispatcher.dispatch(dispatchArgs);

        const receipt: FilingReceipt = {
          action,
          sentAt: new Date().toISOString(),
          officialName: official.name,
          confirmationCode: newConfirmationCode(),
          messagePreview: previewFrom(message.body),
        };

        if (deps.tally) {
          await deps.tally.increment(issue.id, action);
        }

        return reply.send({
          receipt,
          delivery: dispatch,
          verifiedAddress: location.normalized ?? `${location.stateName} (${location.zipCode})`,
        });
      } catch (err) {
        return handleError(reply, request, err, "file");
      }
    });

    // Public aggregate tally for one issue. No auth required — counts only.
    fastify.get<{ Params: { id: string } }>("/v1/issues/:id/tally", async (request, reply) => {
      const id = request.params.id;
      if (!id || id.length < 4) {
        return reply.code(400).send({ error: { code: "invalid_id", message: "Issue id required." } });
      }
      const tally = deps.tally?.forIssue(id) ?? { endorseCount: 0, opposeCount: 0 };
      return reply.send({ issueId: id, ...tally });
    });

    // Lightweight "I'm taking a position" endpoint — bumps the public tally
    // without requiring address resolution or email delivery. This is what
    // iOS hits the moment a user taps Endorse/Oppose so their position is
    // always counted, even when the official can't be reached directly
    // (regulatory rules, ZIP-only state issues, etc.). The optional email
    // send remains a separate /v1/file/send call.
    fastify.post<{ Params: { id: string } }>("/v1/issues/:id/position", async (request, reply) => {
      const body = z.object({
        action: z.enum(["endorse", "oppose"]),
      }).safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: body.error.message } });
      }
      const id = request.params.id;
      const next = deps.tally
        ? await deps.tally.increment(id, body.data.action)
        : { endorseCount: 0, opposeCount: 0 };
      return reply.send({ issueId: id, ...next });
    });
  };
}

function isZipOnly(input: string): boolean {
  return /^\d{5}(-\d{4})?$/.test(input.trim());
}

function resolveLocation(locations: LocationResolver, address: string): Promise<ResolvedLocation> {
  return isZipOnly(address) ? locations.resolveFromZip(address) : locations.resolveFromAddress(address);
}

function draftAddressFor(rawAddress: string, location: ResolvedLocation) {
  return {
    raw: rawAddress,
    normalized: location.normalized ?? `${location.stateName} (${location.zipCode})`,
    latitude: location.latitude ?? 0,
    longitude: location.longitude ?? 0,
    zipCode: location.zipCode,
  };
}

function publicOfficial(official: ResolvedOfficial) {
  return {
    name: official.name,
    title: official.title,
    district: official.district,
    source: official.source,
    channel: official.channel ?? "email",
    ...(official.contactFormURL ? { contactFormURL: official.contactFormURL } : {}),
  };
}

function previewFrom(body: string): string {
  const firstParagraph = body.split(/\n\s*\n/, 1)[0] ?? body;
  return firstParagraph.length > 220 ? `${firstParagraph.slice(0, 217)}…` : firstParagraph;
}

function handleError(reply: any, request: any, err: unknown, stage: string) {
  if (err instanceof CivicError) {
    return reply
      .code(err.statusCode)
      .send({ error: { code: err.code, message: err.message } });
  }
  request.log.error({ err, stage }, "filing failed");
  return reply.code(500).send({
    error: { code: "filing_failed", message: "Filing failed. Try again." },
  });
}
