import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { config } from "../config.js";
import { buildCivicBrief } from "../services/civicBrief.js";
import type { EvidenceVault } from "../services/evidenceVault.js";
import type { IssueStore, StoredIssue } from "../services/issueStore.js";
import type { CivicSourceRegistry } from "../services/sourceRegistry.js";
import { matchServices, type ServiceMatchProfile } from "../services/serviceCatalog.js";
import type { LocationResolver } from "../services/locationResolver.js";
import type { OfficialResolver } from "../services/officialResolver.js";
import type { MessageDrafter } from "../services/messageDrafter.js";

const ToolProfileSchema = z.object({
  stateCode: z.string().length(2).optional(),
  zip: z.string().min(5).max(10).optional(),
  needs: z.union([z.string(), z.array(z.string())]).optional(),
  signals: z.union([z.string(), z.array(z.string())]).optional(),
  documents: z.union([z.string(), z.array(z.string())]).optional(),
  language: z.string().max(40).optional(),
});

const ExplainIssueSchema = z.object({
  issueId: z.string().uuid(),
});

const DraftFilingSchema = z.object({
  issueId: z.string().uuid(),
  action: z.enum(["endorse", "oppose"]),
  zip: z.string().min(5).max(10),
});

const ReadDraftSchema = z.object({
  action: z.enum(["endorse", "oppose"]).optional(),
  officialName: z.string().max(200).optional(),
  subject: z.string().max(300),
  body: z.string().max(8000),
});

export interface VoiceRouteDeps {
  issueStore: IssueStore;
  sourceRegistry: CivicSourceRegistry;
  evidenceVault: EvidenceVault;
  locations: LocationResolver;
  officials: OfficialResolver;
  drafter: MessageDrafter;
}

export function voiceRoute(deps: VoiceRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/voice/session", async (_request, reply) => {
      const hasElevenLabs = Boolean(config.ELEVENLABS_API_KEY && config.ELEVENLABS_AGENT_ID);
      const toolBasePath = "/v1/voice/tools";
      if (!hasElevenLabs) {
        return reply.send({
          provider: "elevenlabs",
          configured: false,
          mode: "native-fallback",
          fallbackReason: "Set ELEVENLABS_API_KEY and ELEVENLABS_AGENT_ID to mint signed Conversational AI sessions.",
          tools: voiceTools(toolBasePath),
        });
      }

      const url = new URL("https://api.elevenlabs.io/v1/convai/conversation/get_signed_url");
      url.searchParams.set("agent_id", config.ELEVENLABS_AGENT_ID ?? "");
      const res = await fetch(url, {
        headers: {
          Accept: "application/json",
          "xi-api-key": config.ELEVENLABS_API_KEY ?? "",
        },
        signal: AbortSignal.timeout(12_000),
      });
      if (!res.ok) {
        return reply.code(502).send({
          error: {
            code: "elevenlabs_session_failed",
            message: `ElevenLabs returned ${res.status} while minting the signed session.`,
          },
        });
      }
      const json = (await res.json()) as { signed_url?: string; signedUrl?: string };
      return reply.send({
        provider: "elevenlabs",
        configured: true,
        mode: "signed-websocket",
        agentID: config.ELEVENLABS_AGENT_ID,
        signedURL: json.signed_url ?? json.signedUrl,
        tools: voiceTools(toolBasePath),
      });
    });

    fastify.get("/v1/voice/tools/daily-brief", async (request, reply) => {
      const parsed = ToolProfileSchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      const serviceMatches = matchServices(profileFrom(parsed.data), { limit: 3 });
      const issues = filterIssues(deps.issueStore.all(), parsed.data.stateCode, parsed.data.zip);
      return reply.send({
        spoken: spokenDailyBrief(issues),
        brief: buildCivicBrief({
          issues,
          serviceMatches,
          stateCode: parsed.data.stateCode,
          zip: parsed.data.zip,
          registeredSources: deps.sourceRegistry.list().length,
        }),
      });
    });

    fastify.get("/v1/voice/tools/explain-issue", async (request, reply) => {
      const parsed = ExplainIssueSchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      const issue = deps.issueStore.all().find((candidate) => candidate.id === parsed.data.issueId);
      if (!issue) return reply.code(404).send({ error: { code: "not_found", message: "No issue found." } });
      return reply.send(issueExplanation(issue, deps.evidenceVault.byIssue(issue.id)));
    });

    fastify.get("/v1/voice/tools/service-match", async (request, reply) => {
      const parsed = ToolProfileSchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      const matches = matchServices(profileFrom(parsed.data), { limit: 5 });
      return reply.send({
        spoken: matches[0]
          ? `Your strongest match is ${matches[0].title}, at ${matches[0].matchScore} percent fit. Next step: ${matches[0].nextStep}.`
          : "I do not have enough profile details to rank services yet.",
        services: matches,
      });
    });

    fastify.post("/v1/voice/tools/draft-filing", async (request, reply) => {
      const parsed = DraftFilingSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_request", message: parsed.error.message } });
      }
      const issue = deps.issueStore.all().find((candidate) => candidate.id === parsed.data.issueId);
      if (!issue) return reply.code(404).send({ error: { code: "not_found", message: "No issue found." } });
      const location = await deps.locations.resolveFromZip(parsed.data.zip);
      const official = await deps.officials.resolve(issue.jurisdiction, location);
      const draft = await deps.drafter.draft({
        action: parsed.data.action,
        issue: issuePayload(issue),
        address: {
          raw: parsed.data.zip,
          normalized: location.normalized ?? `${location.stateName} (${location.zipCode})`,
          latitude: location.latitude ?? 0,
          longitude: location.longitude ?? 0,
          zipCode: location.zipCode,
        },
        official,
      });
      return reply.send({
        draft,
        official: {
          name: official.name,
          title: official.title,
          district: official.district,
          source: official.source,
        },
        readback: readbackForDraft(draft.subject, draft.body, parsed.data.action, official.name),
        requiresExplicitConfirmation: true,
      });
    });

    fastify.post("/v1/voice/tools/read-draft-back", async (request, reply) => {
      const parsed = ReadDraftSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_request", message: parsed.error.message } });
      }
      return reply.send({
        readback: readbackForDraft(parsed.data.subject, parsed.data.body, parsed.data.action, parsed.data.officialName),
        requiresExplicitConfirmation: true,
      });
    });
  };
}

function voiceTools(basePath: string) {
  return [
    { name: "getDailyBrief", method: "GET", path: `${basePath}/daily-brief` },
    { name: "explainIssue", method: "GET", path: `${basePath}/explain-issue` },
    { name: "matchServices", method: "GET", path: `${basePath}/service-match` },
    { name: "draftFiling", method: "POST", path: `${basePath}/draft-filing` },
    { name: "readDraftBack", method: "POST", path: `${basePath}/read-draft-back` },
  ];
}

function profileFrom(input: z.infer<typeof ToolProfileSchema>): ServiceMatchProfile {
  const profile: ServiceMatchProfile = {
    needs: splitQueryList(input.needs),
    signals: splitQueryList(input.signals),
    preparedDocuments: splitQueryList(input.documents),
  };
  if (input.language) profile.language = input.language;
  return profile;
}

function splitQueryList(value: string | string[] | undefined): string[] {
  if (!value) return [];
  const values = Array.isArray(value) ? value : [value];
  return values
    .flatMap((entry) => entry.split(","))
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}

function filterIssues(issues: StoredIssue[], stateCode?: string, zip?: string): StoredIssue[] {
  return issues.filter((issue) => {
    if (issue.scope === "federal") return true;
    if (issue.scope === "local-philly") {
      if (zip && !zip.startsWith("191")) return false;
      if (stateCode && stateCode !== "PA") return false;
      return true;
    }
    if (issue.scope === "state") {
      if (stateCode && issue.stateCode && stateCode !== issue.stateCode) return false;
      return true;
    }
    return true;
  });
}

function spokenDailyBrief(issues: StoredIssue[]): string {
  const next = issues
    .filter((issue) => Date.parse(issue.voteDateISO) > Date.now())
    .sort((a, b) => Date.parse(a.voteDateISO) - Date.parse(b.voteDateISO))[0];
  if (!next) return "No live civic deadlines are loaded yet. Try refreshing sources or set your ZIP.";
  return `Your top civic item is ${next.title}. ${next.summary} The recommended next step is to review the evidence and decide whether to support or oppose before the deadline.`;
}

function issueExplanation(issue: StoredIssue, evidence: Awaited<ReturnType<EvidenceVault["byIssue"]>>) {
  return {
    issueID: issue.id,
    title: issue.title,
    spoken: `${issue.title}. In plain English: ${issue.summary}. The source is ${issue.sourceName}.`,
    plainEnglish: issue.summary,
    facts: issue.facts,
    positions: [
      { kind: "support", title: "Support logic", summary: issue.facts[0]?.value ?? "Supporters may point to the stated public benefit." },
      { kind: "concern", title: "Concern logic", summary: "Critics may question cost, enforcement, timeline, or who is left out." },
      { kind: "watch", title: "Verify next", summary: "Check amendments, source citations, fiscal notes, and the final vote or comment date." },
    ],
    evidence,
  };
}

function issuePayload(issue: StoredIssue) {
  return {
    id: issue.id,
    title: issue.title,
    category: issue.category,
    jurisdiction: issue.jurisdiction,
    sourceName: issue.sourceName,
    summary: issue.summary,
    facts: issue.facts.map((fact) => ({ label: fact.label, value: fact.value })),
    voteDateISO: issue.voteDateISO,
  };
}

function readbackForDraft(subject: string, body: string, action?: "endorse" | "oppose", officialName?: string): string {
  const stance = action === "oppose" ? "oppose" : action === "endorse" ? "support" : "send";
  const destination = officialName ? ` to ${officialName}` : "";
  const compactBody = body.replace(/\s+/g, " ").trim();
  return `Here is the draft I would ${stance}${destination}. Subject: ${subject}. Body: ${compactBody}. To send it, say clearly: yes, submit this filing.`;
}
