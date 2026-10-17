import Anthropic from "@anthropic-ai/sdk";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { config } from "../config.js";
import { withNeutralityGuardrail } from "../lib/neutralityGuardrail.js";
import type { StoredIssue } from "./issueStore.js";
import type { GovInfoService } from "./govInfo.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * AI-generated explainer for one specific civic issue. Unlike the templated
 * card scaffolding in the seed feed, every field here is grounded in the
 * source document's actual contents — never invented stats, never invented
 * quotes, always says "not stated in source" when the data isn't there.
 */
export interface BriefAnalysis {
  /** Stable hash of the source bill text so cached briefs invalidate when
   *  the underlying bill is amended. */
  sourceFingerprint: string;
  /** ISO timestamp the brief was generated. */
  generatedAtISO: string;
  /** Model that wrote it (e.g. claude-sonnet-4-6). */
  model: string;
  /** 8–14 word headline in plain English. */
  headline: string;
  /** One-sentence subhead — what the bill literally does. */
  subhead: string;
  /** 2–4 sentence paragraph framing the stakes for a non-expert. */
  lead: string;
  /** Bullet-style "key facts" — exactly 3, derived from source. */
  keyFacts: BriefKeyFact[];
  /** Both perspectives on the bill, bill-specific not generic. */
  twoSides: BriefSide[];
  /** Fiscal impact paragraph — cite the source's own numbers or say so. */
  fiscalImpact: string;
  /** Timeline — next vote, comment deadline, key future dates. */
  timeline: BriefTimelineEntry[];
  /** Per-cohort impact projection — same body for every reader, the iOS
   *  app picks the matching cohort to display. */
  cohortProjections: BriefCohortProjection[];
  /** Recommended next action for the constituent. */
  recommendedAction: string;
  /** 1-line confidence label + reason. */
  confidence: {
    label: "high" | "medium" | "low";
    reason: string;
  };
  /** Optional editorial pull-quote from the source — for spotlight cards. */
  pullQuote?: string;
  /** Source attribution footer line. */
  sourceLine: string;
}

export interface BriefKeyFact {
  label: string;
  value: string;
}

export interface BriefSide {
  stance: "support" | "concern" | "watch";
  headline: string;
  argument: string;
  who: string;
}

export interface BriefTimelineEntry {
  dateISO: string;
  label: string;
}

export interface BriefCohortProjection {
  cohort:
    | "renter"
    | "homeowner"
    | "parent"
    | "commuter"
    | "businessOwner"
    | "lowIncome"
    | "olderAdult"
    | "general";
  impact: string;
}

const SYSTEM_PROMPT_BASE = `You are the AI brief writer for Athen, a civic OS that helps Americans understand bills, rules, and government actions in time to act on them.

You are given ONE real civic item (a state bill, federal rule, council ordinance, etc.) with its source-of-truth fields. Your job: write a brief that explains it accurately to a busy non-expert.

CRITICAL — TODAY IS {{TODAY_ISO}} ({{TODAY_HUMAN}}).
Reason about dates relative to today. A bill that "passed the House on May 6, 2025" is in the PAST. A vote scheduled for {{NEXT_WEEK}} is UPCOMING. Use "earlier this year", "last year", "next week", "in two months" based on actual elapsed time from {{TODAY_ISO}}. Never imply a past event is upcoming. Never imply an upcoming event has already happened.

NEVER invent statistics, dollar amounts, names, dates, or quotes that are not in the source. If the fiscal impact is not stated, write exactly "Fiscal impact not stated in source." If a deadline is unclear, say "Deadline not yet set." If you don't know who supports something, write "Supporters not yet identified."

ALWAYS ground "supporters argue" / "critics worry" in something specific to THIS bill. Generic statements like "supporters argue this will help families" are forbidden. Instead: "Supporters argue Section 3's eligibility cap at 300% of poverty line catches families currently too well-off for existing aid."

TONE: direct, plain English, no jargon without inline explanation. Imagine you're texting a neighbor who has 90 seconds before their bus arrives.

Output strict JSON only, single object, no markdown fences, no preamble. Required schema:
{
  "headline": "string, 8-14 words, plain English",
  "subhead": "string, one sentence stating what the bill literally does",
  "lead": "string, 2-4 sentences, framing the stakes",
  "keyFacts": [
    { "label": "What it does", "value": "..." },
    { "label": "Who it affects", "value": "..." },
    { "label": "What's at stake", "value": "..." }
  ],
  "twoSides": [
    { "stance": "support", "headline": "...", "argument": "specific to this bill", "who": "who is making this argument (or 'Supporters not yet identified')" },
    { "stance": "concern", "headline": "...", "argument": "specific to this bill", "who": "who is making this argument (or 'Critics not yet identified')" }
  ],
  "fiscalImpact": "string — quote source numbers if present, else 'Fiscal impact not stated in source.'",
  "timeline": [
    { "dateISO": "ISO-8601", "label": "what happens that day" }
  ],
  "cohortProjections": [
    { "cohort": "renter|homeowner|parent|commuter|businessOwner|lowIncome|olderAdult|general", "impact": "1-2 sentences" }
  ],
  "recommendedAction": "string — single concrete next step",
  "confidence": { "label": "high|medium|low", "reason": "one line" },
  "pullQuote": "optional one-sentence quote from source",
  "sourceLine": "Based on [source name] · [URL host]"
}

Thin-source handling:
- If the source is thin (just a title + a committee referral, no bill text), DO NOT refuse. Write an "early read" brief that:
  - States plainly what's known (the title, sponsor, committee, latest action).
  - Says explicitly "Bill text and detailed analysis are not yet posted; this brief will deepen when the source publishes more."
  - Uses confidence: "low" with a reason that names the gap.
  - Still fills every field; never returns the error shape.
- Only return { "error": "insufficient_source", "reason": "..." } if the source has nothing usable — no title, no jurisdiction, no sponsor, no action description.`;

export class BriefAnalysisService {
  private readonly client: Anthropic;
  private cache: BriefCache;
  private readonly cachePath: string;
  private govInfo: GovInfoService | null = null;

  private constructor(client: Anthropic, cache: BriefCache, cachePath: string) {
    this.client = client;
    this.cache = cache;
    this.cachePath = cachePath;
  }

  static async load(cachePath?: string, client?: Anthropic): Promise<BriefAnalysisService> {
    const path = cachePath ?? resolve(__dirname, "..", "..", "data", "brief-cache.json");
    let cache: BriefCache = { version: 1, briefs: {} };
    try {
      const text = await readFile(path, "utf8");
      const parsed = JSON.parse(text) as BriefCache;
      if (parsed.version === 1 && typeof parsed.briefs === "object") cache = parsed;
    } catch {
      // first run — cache stays empty
    }
    return new BriefAnalysisService(
      client ?? new Anthropic({ apiKey: config.ANTHROPIC_API_KEY }),
      cache,
      path,
    );
  }

  /** Inject the GovInfo enricher. When set, briefs for federal bills get
   *  full bill text added to the prompt so Claude writes from the source. */
  attachGovInfo(govInfo: GovInfoService) {
    this.govInfo = govInfo;
  }

  /** Returns the cached brief if available, else generates one with Claude. */
  async analyze(issue: StoredIssue, options: { force?: boolean } = {}): Promise<BriefAnalysis> {
    const existing = this.cache.briefs[issue.sourceFingerprint];
    if (existing && !options.force && existing.model === config.ANTHROPIC_MODEL) {
      return existing;
    }

    // Enrich with full bill text from GovInfo when the issue is a federal
    // bill and we have a key. Doesn't block on failure — Claude still gets
    // the title/summary/facts even if GovInfo is unreachable.
    let fullText: string | null = null;
    if (this.govInfo && issue.sourceType === "official-api:congress" && issue.sourceRecordID) {
      try {
        fullText = await this.govInfo.billText(issue.sourceRecordID);
      } catch {
        // soft fail
      }
    }
    const userPrompt = buildPrompt(issue, fullText);
    const response = await this.client.messages.create({
      model: config.ANTHROPIC_MODEL,
      // Brief JSON is rich: headline + subhead + lead + 3 facts + 2 sides +
      // fiscal + timeline + cohort projections + recommendation + confidence
      // + pull quote + source line. 1800 truncates routinely. 6000 is safe.
      max_tokens: 6000,
      system: withNeutralityGuardrail(dateAwareSystemPrompt()),
      messages: [{ role: "user", content: userPrompt }],
    });

    const text = response.content.find((b) => b.type === "text");
    if (!text || text.type !== "text") throw new Error("Claude returned no text");
    const parsed = parseBrief(text.text);
    if ("error" in parsed) {
      throw new Error(`brief_unavailable:${parsed.error}: ${parsed.reason}`);
    }
    const brief: BriefAnalysis = {
      ...parsed,
      sourceFingerprint: issue.sourceFingerprint,
      generatedAtISO: new Date().toISOString(),
      model: config.ANTHROPIC_MODEL,
    };
    this.cache.briefs[issue.sourceFingerprint] = brief;
    await this.persist();
    return brief;
  }

  /** Returns whatever's in the cache without calling Claude. Used by the
   *  digest endpoint to never block on generation. */
  cached(issue: StoredIssue): BriefAnalysis | undefined {
    return this.cache.briefs[issue.sourceFingerprint];
  }

  stats() {
    return {
      cached: Object.keys(this.cache.briefs).length,
    };
  }

  private async persist() {
    try {
      await mkdir(dirname(this.cachePath), { recursive: true });
      await writeFile(this.cachePath, JSON.stringify(this.cache, null, 2), "utf8");
    } catch {
      // non-fatal — cache writes are best-effort
    }
  }
}

interface BriefCache {
  version: 1;
  briefs: Record<string, BriefAnalysis>;
}

function dateAwareSystemPrompt(): string {
  const now = new Date();
  const todayISO = now.toISOString().slice(0, 10);
  const todayHuman = now.toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" });
  const nextWeek = new Date(now.getTime() + 7 * 86_400_000).toISOString().slice(0, 10);
  return SYSTEM_PROMPT_BASE
    .replaceAll("{{TODAY_ISO}}", todayISO)
    .replaceAll("{{TODAY_HUMAN}}", todayHuman)
    .replaceAll("{{NEXT_WEEK}}", nextWeek);
}

function buildPrompt(issue: StoredIssue, fullText: string | null = null): string {
  const lines: string[] = [];
  const todayISO = new Date().toISOString().slice(0, 10);
  lines.push(`Today's date (UTC): ${todayISO}`);
  lines.push("");
  lines.push(`Title: ${issue.title}`);
  lines.push(`Source: ${issue.sourceName} (${issue.sourceURL})`);
  lines.push(`Jurisdiction: ${issue.jurisdiction}`);
  lines.push(`Scope: ${issue.scope}`);
  if (issue.stateCode) lines.push(`State: ${issue.stateCode}`);
  lines.push(`Category: ${issue.category}`);
  lines.push(`Summary: ${issue.summary}`);
  lines.push(`Vote/Hearing date (ISO): ${issue.voteDateISO}`);
  if (issue.impactLevel) lines.push(`Existing impact label: ${issue.impactLevel}`);
  lines.push("");
  lines.push("Key facts extracted from source:");
  for (const fact of issue.facts) {
    lines.push(`- ${fact.label}: ${fact.value}`);
  }
  if (fullText) {
    lines.push("");
    lines.push("FULL BILL TEXT (from GovInfo):");
    lines.push(fullText);
  }
  if (issue.citations && issue.citations.length > 0) {
    lines.push("");
    lines.push("Source citations:");
    for (const c of issue.citations) {
      lines.push(`- ${c.label}: "${c.quote}"`);
    }
  }
  lines.push("");
  lines.push("Write the brief now. Strict JSON only.");
  return lines.join("\n");
}

type ParseResult =
  | (Omit<BriefAnalysis, "sourceFingerprint" | "generatedAtISO" | "model">)
  | { error: string; reason: string };

function parseBrief(raw: string): ParseResult {
  const trimmed = raw.trim();
  const jsonStart = trimmed.indexOf("{");
  const jsonEnd = trimmed.lastIndexOf("}");
  if (jsonStart < 0) {
    throw new Error(`brief writer did not return JSON: ${trimmed.slice(0, 200)}`);
  }
  let parsed: Record<string, unknown>;
  if (jsonEnd > jsonStart) {
    const slice = trimmed.slice(jsonStart, jsonEnd + 1);
    try {
      parsed = JSON.parse(slice) as Record<string, unknown>;
    } catch {
      const salvaged = trySalvageJsonObject(trimmed.slice(jsonStart));
      if (!salvaged) {
        throw new Error("brief JSON malformed and unrecoverable");
      }
      parsed = salvaged as Record<string, unknown>;
    }
  } else {
    // No closing brace at all — definitely truncated. Try to salvage.
    const salvaged = trySalvageJsonObject(trimmed.slice(jsonStart));
    if (!salvaged) {
      throw new Error("brief JSON truncated and unrecoverable");
    }
    parsed = salvaged as Record<string, unknown>;
  }
  if (parsed.error) {
    return {
      error: String(parsed.error),
      reason: typeof parsed.reason === "string" ? parsed.reason : "no reason given",
    };
  }
  // Loose validation — Claude almost always returns the right shape.
  const out: Omit<BriefAnalysis, "sourceFingerprint" | "generatedAtISO" | "model"> = {
    headline: String(parsed.headline ?? ""),
    subhead: String(parsed.subhead ?? ""),
    lead: String(parsed.lead ?? ""),
    keyFacts: Array.isArray(parsed.keyFacts) ? (parsed.keyFacts as BriefKeyFact[]) : [],
    twoSides: Array.isArray(parsed.twoSides) ? (parsed.twoSides as BriefSide[]) : [],
    fiscalImpact: String(parsed.fiscalImpact ?? "Fiscal impact not stated in source."),
    timeline: Array.isArray(parsed.timeline) ? (parsed.timeline as BriefTimelineEntry[]) : [],
    cohortProjections: Array.isArray(parsed.cohortProjections)
      ? (parsed.cohortProjections as BriefCohortProjection[])
      : [],
    recommendedAction: String(parsed.recommendedAction ?? ""),
    confidence: (parsed.confidence as BriefAnalysis["confidence"]) ?? {
      label: "medium",
      reason: "no confidence stated",
    },
    sourceLine: String(parsed.sourceLine ?? ""),
  };
  if (typeof parsed.pullQuote === "string" && parsed.pullQuote.trim().length > 0) {
    out.pullQuote = parsed.pullQuote;
  }
  return out;
}

/**
 * Best-effort recovery when Claude truncates mid-JSON. Tracks brace depth
 * + string state, walks back to the last safe structural boundary, then
 * closes any open braces/brackets. Preserves all complete entries.
 */
function trySalvageJsonObject(raw: string): unknown | null {
  let depth = 0;
  let arrayDepth = 0;
  let inString = false;
  let escape = false;
  let lastSafe = -1;
  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i]!;
    if (escape) { escape = false; continue; }
    if (ch === "\\") { escape = true; continue; }
    if (ch === '"') { inString = !inString; continue; }
    if (inString) continue;
    if (ch === "{") depth++;
    else if (ch === "}") depth--;
    else if (ch === "[") arrayDepth++;
    else if (ch === "]") arrayDepth--;
    if ((ch === "," || ch === "}" || ch === "]") && depth > 0) {
      lastSafe = i;
    }
  }
  if (lastSafe < 0) return null;
  let truncated = raw.slice(0, lastSafe + 1).replace(/,\s*$/, "");
  let openObj = 0;
  let openArr = 0;
  let s = false;
  let e = false;
  for (const ch of truncated) {
    if (e) { e = false; continue; }
    if (ch === "\\") { e = true; continue; }
    if (ch === '"') { s = !s; continue; }
    if (s) continue;
    if (ch === "{") openObj++;
    else if (ch === "}") openObj--;
    else if (ch === "[") openArr++;
    else if (ch === "]") openArr--;
  }
  while (openArr-- > 0) truncated += "]";
  while (openObj-- > 0) truncated += "}";
  try {
    return JSON.parse(truncated);
  } catch {
    return null;
  }
}
