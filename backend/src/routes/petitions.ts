import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import type { PetitionStore, PetitionStatus, PetitionTarget } from "../services/petitionStore.js";
import type { IssueStore } from "../services/issueStore.js";
import type { OfficialResolver } from "../services/officialResolver.js";
import type { LocationResolver } from "../services/locationResolver.js";
import type { FilingDispatcher } from "../services/filingDispatcher.js";
import type { ComposioService } from "../services/composio.js";
import { buildPacket, deliverPetition } from "../services/petitionDelivery.js";

const MIN = 60_000;
const listLimiter = rateLimit({ name: "petitions:list", max: 120, windowMs: 5 * MIN });
const createLimiter = rateLimit({ name: "petitions:create", max: 8, windowMs: 60 * MIN });
const signLimiter = rateLimit({ name: "petitions:sign", max: 60, windowMs: 5 * MIN });
const deliverLimiter = rateLimit({ name: "petitions:deliver", max: 6, windowMs: 60 * MIN });

const EntityHeader = z.object({
  "x-athen-entity": z.string().min(8).max(80),
});

const TargetSchema = z.object({
  officialName: z.string().min(1).max(120),
  jurisdiction: z.string().min(1).max(200),
  email: z.string().email().optional(),
  contactFormURL: z.string().url().optional(),
  channel: z.enum(["email", "contact-form-queue"]).default("email"),
});

const CreateBody = z.object({
  title: z.string().min(6).max(140),
  ask: z.string().min(6).max(280),
  body: z.string().min(20).max(8000),
  creatorDisplayName: z.string().min(1).max(80),
  attachedIssueId: z.string().optional(),
  targets: z.array(TargetSchema).min(1).max(8).optional(),
  threshold: z.number().int().min(2).max(100_000).optional(),
  deadlineISO: z.string().datetime().optional(),
  visibility: z.enum(["public", "private"]).optional(),
  /** ZIP of the creator for auto-resolving targets when none were provided. */
  zip: z.string().min(5).max(10).optional(),
});

const SignBody = z.object({
  name: z.string().min(1).max(80),
  zip: z.string().min(5).max(10),
  comment: z.string().max(280).optional(),
});

const ListQuery = z.object({
  status: z.enum(["open", "delivered", "expired"]).optional(),
  zip: z.string().min(5).max(10).optional(),
  topicId: z.string().optional(),
  mine: z.coerce.boolean().optional(),
});

export interface PetitionsRouteDeps {
  petitions: PetitionStore;
  issues: IssueStore;
  officials: OfficialResolver;
  locations: LocationResolver;
  dispatcher: FilingDispatcher;
  composio: ComposioService | null;
}

export function petitionsRoute(deps: PetitionsRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/petitions", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      const parsed = ListQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      const headers = EntityHeader.safeParse(request.headers);
      const entityId = headers.success ? headers.data["x-athen-entity"] : undefined;
      const filter: {
        zip?: string;
        status?: PetitionStatus;
        topicId?: string;
        mineEntityId?: string;
      } = {};
      if (parsed.data.zip) filter.zip = parsed.data.zip;
      if (parsed.data.status) filter.status = parsed.data.status;
      if (parsed.data.topicId) filter.topicId = parsed.data.topicId;
      if (parsed.data.mine && entityId) filter.mineEntityId = entityId;
      const items = deps.petitions.list(filter);
      return reply.send({
        items,
        stats: deps.petitions.stats(),
        viewer: entityId ? viewerSummary(entityId, items) : undefined,
      });
    });

    fastify.get("/v1/petitions/:id", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      const { id } = request.params as { id: string };
      const petition = deps.petitions.find(id);
      if (!petition) return reply.code(404).send({ error: { code: "petition_not_found", message: "Not found." } });
      const headers = EntityHeader.safeParse(request.headers);
      const entityId = headers.success ? headers.data["x-athen-entity"] : undefined;
      return reply.send({
        petition,
        viewer: entityId
          ? {
              hasSigned: petition.signatures.some((s) => s.entityId === entityId),
              isCreator: petition.creatorEntityId === entityId,
            }
          : undefined,
      });
    });

    fastify.post("/v1/petitions", async (request, reply) => {
      if (!createLimiter(request, reply)) return;
      const headers = EntityHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_entity", message: "x-athen-entity header required." } });
      }
      const body = CreateBody.safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: body.error.message } });
      }

      // Resolve targets — either user-provided, or derive from the attached issue.
      let targets: PetitionTarget[] = (body.data.targets ?? []).map((t) => {
        const target: PetitionTarget = {
          officialName: t.officialName,
          jurisdiction: t.jurisdiction,
          channel: t.channel,
        };
        if (t.email) target.email = t.email;
        if (t.contactFormURL) target.contactFormURL = t.contactFormURL;
        return target;
      });
      if (targets.length === 0) {
        if (!body.data.attachedIssueId || !body.data.zip) {
          return reply.code(400).send({
            error: {
              code: "no_targets",
              message: "Either provide targets explicitly or supply attachedIssueId + zip so we can resolve officials.",
            },
          });
        }
        const issue = body.data.attachedIssueId ? deps.issues.findById(body.data.attachedIssueId) : undefined;
        if (!issue) {
          return reply.code(404).send({ error: { code: "issue_not_found", message: "Attached issue not found." } });
        }
        try {
          const location = await deps.locations.resolveFromZip(body.data.zip);
          const official = await deps.officials.resolve(issue.jurisdiction, location);
          const target: PetitionTarget = {
            officialName: official.name,
            jurisdiction: issue.jurisdiction,
            channel: official.channel ?? "email",
          };
          if (official.email) target.email = official.email;
          if (official.contactFormURL) target.contactFormURL = official.contactFormURL;
          targets = [target];
        } catch (err) {
          return reply.code(502).send({
            error: { code: "target_resolution_failed", message: err instanceof Error ? err.message : "Could not resolve target." },
          });
        }
      }

      const createInput: Parameters<typeof deps.petitions.create>[0] = {
        title: body.data.title,
        ask: body.data.ask,
        body: body.data.body,
        creatorEntityId: headers.data["x-athen-entity"],
        creatorDisplayName: body.data.creatorDisplayName,
        targets,
      };
      if (body.data.attachedIssueId) createInput.attachedIssueId = body.data.attachedIssueId;
      if (body.data.attachedIssueId) {
        const attached = deps.issues.findById(body.data.attachedIssueId);
        if (attached) createInput.attachedIssueTitle = attached.title;
      }
      if (body.data.threshold !== undefined) createInput.threshold = body.data.threshold;
      if (body.data.deadlineISO) createInput.deadlineISO = body.data.deadlineISO;
      if (body.data.visibility) createInput.visibility = body.data.visibility;
      const petition = deps.petitions.create(createInput);
      return reply.code(201).send({ petition });
    });

    fastify.post("/v1/petitions/:id/sign", async (request, reply) => {
      if (!signLimiter(request, reply)) return;
      const headers = EntityHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_entity", message: "x-athen-entity header required." } });
      }
      const { id } = request.params as { id: string };
      const petition = deps.petitions.find(id);
      if (!petition) return reply.code(404).send({ error: { code: "petition_not_found", message: "Not found." } });
      if (petition.status !== "open") {
        return reply.code(409).send({ error: { code: "petition_closed", message: "This petition is no longer open." } });
      }
      const body = SignBody.safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: body.error.message } });
      }
      const signInput: { entityId: string; name: string; zip: string; comment?: string } = {
        entityId: headers.data["x-athen-entity"],
        name: body.data.name,
        zip: body.data.zip,
      };
      if (body.data.comment) signInput.comment = body.data.comment;
      const signature = deps.petitions.sign(id, signInput);
      if (!signature) {
        return reply.code(409).send({ error: { code: "already_signed", message: "You've already signed this petition." } });
      }
      const updated = deps.petitions.find(id)!;
      return reply.send({ signature, petition: updated });
    });

    fastify.delete("/v1/petitions/:id/signature", async (request, reply) => {
      if (!signLimiter(request, reply)) return;
      const headers = EntityHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_entity", message: "x-athen-entity header required." } });
      }
      const { id } = request.params as { id: string };
      const removed = deps.petitions.unsign(id, headers.data["x-athen-entity"]);
      if (!removed) return reply.code(404).send({ error: { code: "signature_not_found", message: "You haven't signed this petition." } });
      const updated = deps.petitions.find(id);
      return reply.send({ ok: true, petition: updated });
    });

    fastify.get("/v1/petitions/:id/packet", async (request, reply) => {
      if (!listLimiter(request, reply)) return;
      const { id } = request.params as { id: string };
      const petition = deps.petitions.find(id);
      if (!petition) return reply.code(404).send({ error: { code: "petition_not_found", message: "Not found." } });
      const packet = await buildPacket(petition);
      return reply.send({ packet });
    });

    fastify.post("/v1/petitions/:id/deliver", async (request, reply) => {
      if (!deliverLimiter(request, reply)) return;
      const headers = EntityHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_entity", message: "x-athen-entity header required." } });
      }
      const { id } = request.params as { id: string };
      const petition = deps.petitions.find(id);
      if (!petition) return reply.code(404).send({ error: { code: "petition_not_found", message: "Not found." } });
      if (petition.creatorEntityId !== headers.data["x-athen-entity"]) {
        return reply.code(403).send({ error: { code: "not_creator", message: "Only the creator can manually deliver." } });
      }
      if (petition.status !== "open") {
        return reply.code(409).send({ error: { code: "already_delivered", message: "Petition is not open." } });
      }
      try {
        const result = await deliverPetition({ petition, dispatcher: deps.dispatcher, composio: deps.composio });
        deps.petitions.markDelivered(id, { trackingId: result.trackingId, note: result.note });
        const updated = deps.petitions.find(id);
        return reply.send({ delivery: result, petition: updated });
      } catch (err) {
        return reply.code(502).send({
          error: { code: "delivery_failed", message: err instanceof Error ? err.message : "Delivery failed." },
        });
      }
    });

    fastify.delete("/v1/petitions/:id", async (request, reply) => {
      const headers = EntityHeader.safeParse(request.headers);
      if (!headers.success) {
        return reply.code(400).send({ error: { code: "missing_entity", message: "x-athen-entity header required." } });
      }
      const { id } = request.params as { id: string };
      const ok = deps.petitions.delete(id, headers.data["x-athen-entity"]);
      if (!ok) return reply.code(404).send({ error: { code: "not_authorized_or_not_found", message: "Cannot delete this petition." } });
      return reply.send({ ok: true });
    });
  };
}

function viewerSummary(entityId: string, items: ReturnType<PetitionStore["list"]>) {
  return {
    signedIds: items.filter((p) => p.signatures.some((s) => s.entityId === entityId)).map((p) => p.id),
    createdIds: items.filter((p) => p.creatorEntityId === entityId).map((p) => p.id),
  };
}
