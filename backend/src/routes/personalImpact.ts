import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import { rateLimit } from "../lib/rateLimiter.js";
import { dailyQuota } from "../lib/dailyQuota.js";
import { withNeutralityGuardrail } from "../lib/neutralityGuardrail.js";
import type { IssueStore } from "../services/issueStore.js";
import type { BriefAnalysisService } from "../services/briefAnalysis.js";

const MIN = 60_000;
const limiter = rateLimit({ name: "impact", max: 60, windowMs: 5 * MIN });
const quota = dailyQuota({ name: "personal-impact", max: 40 });

const Body = z.object({
  monthlyRent: z.number().min(0).max(50_000).optional(),
  annualIncome: z.number().min(0).max(10_000_000).optional(),
  householdSize: z.number().int().min(1).max(20).optional(),
  hasKidsInPublicSchool: z.boolean().optional(),
  commuteMode: z.enum(["car", "transit", "bike", "walk", "remote", "mixed"]).optional(),
  homeOwner: z.boolean().optional(),
  zip: z.string().min(5).max(10).optional(),
  state: z.string().min(2).max(60).optional(),
});

const Params = z.object({ id: z.string() });

interface ImpactResponse {
  issueId: string;
  generatedAt: string;
  /** 1-2 sentence headline, written like a personal text from a friend. */
  headline: string;
  /** Bulleted breakdown of specific impacts (3-5 items). */
  details: string[];
  /** Confidence band — "estimate", "rough estimate", "speculative". */
  confidence: "estimate" | "rough estimate" | "speculative";
  /** What we're missing that would tighten the estimate. */
  missingInputs: string[];
}

export interface PersonalImpactDeps {
  issues: IssueStore;
  briefs: BriefAnalysisService;
}

export function personalImpactRoute(deps: PersonalImpactDeps): FastifyPluginAsync {
  const anthropic = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  return async function (fastify: FastifyInstance) {
    fastify.post<{ Params: { id: string } }>("/v1/issues/:id/impact", async (request, reply) => {
      if (!limiter(request, reply)) return;
      if (!quota(request, reply)) return;
      const params = Params.safeParse(request.params);
      if (!params.success) {
        return reply.code(400).send({ error: { code: "invalid_params", message: params.error.message } });
      }
      const issue = deps.issues.findById(params.data.id);
      if (!issue) {
        return reply.code(404).send({ error: { code: "not_found", message: "Issue not found." } });
      }
      const body = Body.safeParse(request.body ?? {});
      if (!body.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: body.error.message } });
      }
      const profile = body.data;

      // Pull the existing brief so Claude has structured analysis to reason
      // from — no fresh research call, fast + cheap.
      let brief;
      try {
        brief = await deps.briefs.analyze(issue);
      } catch {
        brief = null;
      }

      const SYSTEM = `You estimate how a specific civic item affects ONE user, based on the profile they provided. Return PURE JSON only.

Shape:
{
  "headline": "1-2 sentences in plain English, written like a friend texting them — concrete numbers when reasonable, hedged when not",
  "details": ["bullet 1", "bullet 2", "bullet 3"],
  "confidence": "estimate" | "rough estimate" | "speculative",
  "missingInputs": ["what you'd need to be more confident"]
}

Hard rules:
- Use the listener's numbers. If they gave rent + income, ANCHOR your math to those.
- "Speculative" confidence whenever you have to guess at numbers the profile doesn't provide. Be honest.
- Never invent specific dollar amounts for things you can't reason about from the brief + profile. Use a range or skip.
- 3-5 details max. Concrete. No general talking points.
- Tone: like a friend who happens to read budgets. Casual but precise.
- NO prose outside JSON. NO markdown.`;

      const profileLines = [
        profile.monthlyRent !== undefined ? `Monthly rent: $${profile.monthlyRent}` : null,
        profile.annualIncome !== undefined ? `Annual income: $${profile.annualIncome}` : null,
        profile.householdSize !== undefined ? `Household size: ${profile.householdSize}` : null,
        profile.hasKidsInPublicSchool !== undefined ? `Kids in public school: ${profile.hasKidsInPublicSchool ? "yes" : "no"}` : null,
        profile.commuteMode ? `Commute: ${profile.commuteMode}` : null,
        profile.homeOwner !== undefined ? `Homeowner: ${profile.homeOwner ? "yes" : "no"}` : null,
        profile.zip ? `ZIP: ${profile.zip}` : null,
        profile.state ? `State: ${profile.state}` : null,
      ].filter(Boolean).join("\n");

      const briefDigest = brief ? [
        `Headline: ${brief.headline}`,
        `Subhead: ${brief.subhead}`,
        `Lead: ${brief.lead}`,
        `Fiscal: ${brief.fiscalImpact}`,
        `Key facts: ${brief.keyFacts.slice(0, 4).map((f) => `${f.label}: ${f.value}`).join(" | ")}`,
        `Two sides:\n${brief.twoSides.map((s) => `  ${s.stance}: ${s.argument} (${s.who})`).join("\n")}`,
      ].join("\n") : `Title: ${issue.title}\nSummary: ${issue.summary}`;

      const userPrompt = [
        `ISSUE: ${issue.title}`,
        `JURISDICTION: ${issue.jurisdiction} (${issue.scope})`,
        `OFFICIAL: ${issue.official.name}`,
        "",
        "ISSUE BRIEF:",
        briefDigest,
        "",
        "USER PROFILE:",
        profileLines || "(no profile inputs — be honest about confidence)",
        "",
        "Generate the JSON impact analysis now.",
      ].join("\n");

      try {
        const response = await anthropic.messages.create({
          model: config.ANTHROPIC_MODEL,
          max_tokens: 1200,
          system: withNeutralityGuardrail(SYSTEM),
          messages: [{ role: "user", content: userPrompt }],
        });
        const block = response.content.find((b) => b.type === "text");
        const text = block && block.type === "text" ? block.text.trim() : "";
        const parsed = safeParseImpact(text);
        const out: ImpactResponse = {
          issueId: issue.id,
          generatedAt: new Date().toISOString(),
          headline: parsed.headline || "We couldn't estimate a personal impact for this item.",
          details: parsed.details ?? [],
          confidence: parsed.confidence ?? "speculative",
          missingInputs: parsed.missingInputs ?? [],
        };
        return reply.send(out);
      } catch (err) {
        return reply.code(502).send({
          error: { code: "claude_failed", message: err instanceof Error ? err.message : "Claude analysis failed." },
        });
      }
    });
  };
}

interface ParsedImpact {
  headline?: string;
  details?: string[];
  confidence?: "estimate" | "rough estimate" | "speculative";
  missingInputs?: string[];
}

function safeParseImpact(text: string): ParsedImpact {
  const cleaned = text
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```$/, "")
    .trim();
  try {
    const parsed = JSON.parse(cleaned) as Record<string, unknown>;
    const out: ParsedImpact = {};
    if (typeof parsed.headline === "string") out.headline = parsed.headline;
    if (Array.isArray(parsed.details)) {
      out.details = parsed.details.filter((x): x is string => typeof x === "string");
    }
    const conf = typeof parsed.confidence === "string" ? parsed.confidence : "";
    if (conf === "estimate" || conf === "rough estimate" || conf === "speculative") {
      out.confidence = conf;
    }
    if (Array.isArray(parsed.missingInputs)) {
      out.missingInputs = parsed.missingInputs.filter((x): x is string => typeof x === "string");
    }
    return out;
  } catch {
    return {};
  }
}
