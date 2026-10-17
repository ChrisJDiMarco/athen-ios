import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { config } from "../config.js";
import { rateLimit } from "../lib/rateLimiter.js";
import { dailyQuota } from "../lib/dailyQuota.js";
import { CivicError } from "../lib/errors.js";

const MIN = 60_000;
const variantLimiter = rateLimit({ name: "draft:variants", max: 20, windowMs: 5 * MIN });
const variantDailyQuota = dailyQuota({ name: "claude:draft-variants", max: 40 });

const IssueSchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  jurisdiction: z.string().min(1),
  sourceName: z.string().min(1),
  summary: z.string().min(1),
  facts: z
    .array(z.object({ label: z.string().min(1), value: z.string().min(1) }))
    .min(1),
  voteDateISO: z.string().min(1),
});

const VariantsBody = z.object({
  action: z.enum(["endorse", "oppose"]),
  zip: z.string().min(5).max(10),
  stateCode: z.string().length(2).optional(),
  localityLabel: z.string().max(80).optional(),
  issue: IssueSchema,
});

export type ToneVariantKey =
  | "concerned"
  | "businessOwner"
  | "parent"
  | "renter"
  | "professional";

export interface ToneVariant {
  key: ToneVariantKey;
  label: string;
  description: string;
  subject: string;
  body: string;
}

const TONES: { key: ToneVariantKey; label: string; description: string; tone: string }[] = [
  {
    key: "concerned",
    label: "Concerned constituent",
    description: "Warm, personal — opens with why you live here and care.",
    tone: "Speak as a regular constituent who has lived in the jurisdiction for a few years. Be warm, specific about why this issue touches your block or your day-to-day, and direct about the ask. Avoid lobbyist or jargon language.",
  },
  {
    key: "businessOwner",
    label: "Business owner",
    description: "Frames the impact on jobs, payroll, customers.",
    tone: "Speak as a local small-business owner. Lead with concrete operational effects — payroll, customer foot traffic, permitting, hiring. Stay specific, never hostile.",
  },
  {
    key: "parent",
    label: "Parent / caregiver",
    description: "Centers schools, safety, kids' future.",
    tone: "Speak as a parent or caregiver. Center your kids or the kids in your block — schools, safety, after-school programs, climate they'll inherit. Stay civil.",
  },
  {
    key: "renter",
    label: "Renter",
    description: "Centers housing stability and affordability.",
    tone: "Speak as a renter. Center housing stability, the local rental market, displacement risk, and the realities of moving costs. Stay civil.",
  },
  {
    key: "professional",
    label: "Subject professional",
    description: "Tight, evidence-led, peer-to-peer tone.",
    tone: "Speak as a professional in a relevant field (planning, healthcare, education, transit, etc — pick what fits the issue). Use precise evidence-led language without being condescending. Keep it under 180 words.",
  },
];

function dateAwareSystem(): string {
  const now = new Date();
  const today = now.toISOString().slice(0, 10);
  return SYSTEM_BASE.replaceAll("{{TODAY_ISO}}", today);
}

const SYSTEM_BASE = `You write formal constituent messages to government officials.

Today's date is {{TODAY_ISO}}. When referencing dates, reason about them relative to today. If a vote is in the past, do not say "the upcoming vote".

Rules:
- First person, present tense.
- Open with verified residency: cite city, state, and ZIP — never street address.
- State the action ("I support" or "I oppose") in the first sentence.
- Reference the agenda item by source name + title.
- Cite at most two concrete facts from the provided facts list, in the constituent's own words.
- Close with a single ask: that the official record the constituent's position.
- Do not invent statistics, names, dates, or quotes that are not in the source.
- Never include placeholders like [NAME] or [DATE].
- Match the requested tone exactly — that's the whole point of this variant.

Output strict JSON only — single object, no markdown:
{ "subject": "...", "body": "..." }`;

export function draftVariantsRoute(): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/file/variants", async (request, reply) => {
      if (!variantLimiter(request, reply)) return;
      if (!variantDailyQuota(request, reply)) return;
      const parsed = VariantsBody.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }
      const args = parsed.data;
      const client = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });

      const results = await Promise.all(
        TONES.map(async (tone) => {
          try {
            const variant = await writeVariant(client, tone, args);
            return variant;
          } catch (err) {
            request.log.warn({ err, tone: tone.key }, "tone variant failed");
            return null;
          }
        }),
      );

      const variants = results.filter((v): v is ToneVariant => v !== null);
      if (variants.length === 0) {
        throw new CivicError("variants_failed", "All tone variants failed to generate.", 502);
      }
      return reply.send({ variants });
    });
  };
}

async function writeVariant(
  client: Anthropic,
  tone: { key: ToneVariantKey; label: string; description: string; tone: string },
  args: z.infer<typeof VariantsBody>,
): Promise<ToneVariant> {
  const userPrompt = [
    `Tone: ${tone.tone}`,
    "",
    `Action: ${args.action === "endorse" ? "support" : "oppose"}`,
    `Jurisdiction: ${args.issue.jurisdiction}`,
    `Constituent ZIP: ${args.zip}${args.stateCode ? ` (${args.stateCode})` : ""}${args.localityLabel ? ` — ${args.localityLabel}` : ""}`,
    `Agenda item: ${args.issue.sourceName} — "${args.issue.title}"`,
    `Vote date (ISO): ${args.issue.voteDateISO}`,
    `Issue summary: ${args.issue.summary}`,
    "Facts the constituent can draw from:",
    ...args.issue.facts.map((f) => `- ${f.label}: ${f.value}`),
    "",
    "Write the message now. Strict JSON only.",
  ].join("\n");

  const response = await client.messages.create({
    model: config.ANTHROPIC_MODEL,
    max_tokens: 700,
    system: dateAwareSystem(),
    messages: [{ role: "user", content: userPrompt }],
  });
  const block = response.content.find((b) => b.type === "text");
  if (!block || block.type !== "text") throw new Error("no text from Claude");
  const text = block.text.trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end < 0) throw new Error("variant writer did not return JSON");
  const parsed = JSON.parse(text.slice(start, end + 1)) as { subject?: string; body?: string };
  if (typeof parsed.subject !== "string" || typeof parsed.body !== "string") {
    throw new Error("variant missing subject/body");
  }
  return {
    key: tone.key,
    label: tone.label,
    description: tone.description,
    subject: parsed.subject,
    body: parsed.body,
  };
}
