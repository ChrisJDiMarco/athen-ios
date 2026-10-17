import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import { withNeutralityGuardrail } from "../lib/neutralityGuardrail.js";
import type { CivicAction, DraftedMessage, IssuePayload, ResolvedOfficial, VerifiedAddress } from "../lib/types.js";

const SYSTEM_PROMPT = `You draft formal constituent messages to local government officials.

Rules:
- Write as the constituent in first person.
- Plain English. Short paragraphs. No purple prose, no slogans.
- Open with verified residency: cite city, district, and ZIP — never the street address.
- State the action ("I support" or "I oppose") in the first sentence.
- Reference the agenda item by name and identifier.
- Cite at most two concrete facts from the provided facts list, in the constituent's own words.
- Close with a single ask: that the official record the constituent's position.
- Do not invent statistics, names, dates, or quotes.
- Do not include placeholders like [NAME] or [DATE].

Return ONLY a JSON object on a single line with keys "subject" and "body". No markdown, no preamble.`;

export interface MessageDrafter {
  draft(args: {
    action: CivicAction;
    issue: IssuePayload;
    address: VerifiedAddress;
    official: ResolvedOfficial;
  }): Promise<DraftedMessage>;
}

export class ClaudeMessageDrafter implements MessageDrafter {
  private readonly client: Anthropic;

  constructor(client?: Anthropic) {
    this.client = client ?? new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  }

  async draft(args: {
    action: CivicAction;
    issue: IssuePayload;
    address: VerifiedAddress;
    official: ResolvedOfficial;
  }): Promise<DraftedMessage> {
    const { action, issue, address, official } = args;

    const userPrompt = [
      `Action: ${action === "endorse" ? "support" : "oppose"}`,
      `Official: ${official.name}, ${official.title} (${official.district})`,
      `Jurisdiction: ${issue.jurisdiction}`,
      `Agenda item: ${issue.sourceName} — "${issue.title}"`,
      `Vote date (ISO): ${issue.voteDateISO}`,
      `Constituent ZIP: ${address.zipCode}`,
      `Issue summary: ${issue.summary}`,
      "Facts the constituent can draw from:",
      ...issue.facts.map((f) => `- ${f.label}: ${f.value}`),
    ].join("\n");

    const response = await this.client.messages.create({
      model: config.ANTHROPIC_MODEL,
      max_tokens: 700,
      system: withNeutralityGuardrail(SYSTEM_PROMPT),
      messages: [{ role: "user", content: userPrompt }],
    });

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new Error("Claude returned no text content");
    }

    return parseDraft(textBlock.text);
  }
}

function parseDraft(raw: string): DraftedMessage {
  const trimmed = raw.trim();
  const jsonStart = trimmed.indexOf("{");
  const jsonEnd = trimmed.lastIndexOf("}");
  if (jsonStart < 0 || jsonEnd < 0) {
    throw new Error(`Drafter did not return JSON: ${trimmed.slice(0, 200)}`);
  }

  const parsed = JSON.parse(trimmed.slice(jsonStart, jsonEnd + 1)) as Partial<DraftedMessage>;
  if (typeof parsed.subject !== "string" || typeof parsed.body !== "string") {
    throw new Error("Drafter JSON missing 'subject' or 'body'");
  }
  return { subject: parsed.subject, body: parsed.body };
}
