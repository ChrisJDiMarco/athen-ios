import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import type { BriefAnalysis } from "./briefAnalysis.js";
import type { StoredIssue } from "./issueStore.js";

export type BriefAudience = "kid" | "parent" | "landlord" | "neighbor" | "lawyer";

const AUDIENCE_GUIDE: Record<BriefAudience, string> = {
  kid: "Explain to a curious 12-year-old. Short sentences. No legalese. Use a concrete everyday example they'd recognize (school, allowance, parents). 4-6 sentences total.",
  parent:
    "Explain to a parent juggling work and kids. Lead with what changes for their family — school, healthcare, childcare, taxes, safety. 4-6 sentences. Practical and direct.",
  landlord:
    "Explain to a small landlord who owns 1-4 units. Lead with: does this change rent rules, eviction process, taxes, maintenance obligations, or building codes? Cite specifics from the source. 4-6 sentences.",
  neighbor:
    "Explain to a busy neighbor at the mailbox who has 30 seconds. Plain English, one main takeaway, what (if anything) they should do. 3-4 sentences.",
  lawyer:
    "Explain to an attorney scanning for legal exposure. Use precise statutory language where the source uses it. Flag which sections do the work. 4-6 sentences.",
};

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) _client = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  return _client;
}

/**
 * One-shot Claude rewrite of an existing brief for a specific audience.
 * No caching — these are cheap and personalized. Returns plain text.
 */
export async function rewriteBrief(
  brief: BriefAnalysis,
  issue: StoredIssue,
  audience: BriefAudience,
): Promise<string> {
  const guide = AUDIENCE_GUIDE[audience];
  const sourceFacts = [
    `Title: ${issue.title}`,
    `Jurisdiction: ${issue.jurisdiction}`,
    `Headline: ${brief.headline}`,
    `Subhead: ${brief.subhead}`,
    `Lead: ${brief.lead}`,
    `Fiscal: ${brief.fiscalImpact}`,
    `Next step: ${brief.recommendedAction}`,
  ].join("\n");

  const system = `You rewrite civic-policy briefs for different audiences. NEVER invent numbers, names, dates, or quotes that aren't already in the source brief below. Stay grounded. Stay plain. Stay short.`;

  const user = `AUDIENCE: ${audience}
GUIDE: ${guide}

SOURCE BRIEF (do not contradict, do not invent beyond):
${sourceFacts}

Output: just the rewritten explanation. No preamble. No header. No "Here's the explanation:". Just the words you'd say.`;

  const response = await client().messages.create({
    model: config.ANTHROPIC_MODEL,
    max_tokens: 400,
    system,
    messages: [{ role: "user", content: user }],
  });
  const text = response.content.find((b) => b.type === "text");
  if (!text || text.type !== "text") throw new Error("Claude returned no text");
  return text.text.trim();
}
