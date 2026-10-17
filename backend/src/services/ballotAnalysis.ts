import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";

export interface BallotItemBrief {
  rawText: string;
  itemTitle: string;
  itemKind: "candidate" | "measure" | "amendment" | "unknown";
  plainEnglish: string;
  whatYesMeans: string | null;
  whatNoMeans: string | null;
  considerations: string[];
}

export interface BallotAnalysis {
  generatedAtISO: string;
  model: string;
  items: BallotItemBrief[];
  notice: string;
}

const SYSTEM = `You are an impartial ballot explainer. The user has uploaded the text from a sample or live ballot. Your job: turn it into a list of items, each with a plain-English explanation a non-expert can read in 20 seconds.

CRITICAL RULES:
- Never tell the user how to vote. No "vote yes" or "vote no" recommendations.
- Explain what YES and NO actually do in concrete terms — what changes, what stays, who's affected.
- If the ballot text is too ambiguous to interpret, say so on that item rather than guessing.
- Strip header noise like "OFFICIAL BALLOT", precinct numbers, instructions, etc.
- One JSON object out, no markdown, no preamble. Schema:

{
  "items": [
    {
      "rawText": "the exact ballot text you used for this item",
      "itemTitle": "short title (5-10 words)",
      "itemKind": "candidate|measure|amendment|unknown",
      "plainEnglish": "2-3 sentences explaining what this item is about",
      "whatYesMeans": "1 sentence — what YES does, or null if not a yes/no item",
      "whatNoMeans": "1 sentence — what NO does, or null if not a yes/no item",
      "considerations": ["3-5 short bullets a voter might weigh — facts, not advice"]
    }
  ],
  "notice": "one-sentence reminder this is informational, not voting advice"
}`;

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) _client = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  return _client;
}

export async function analyzeBallotText(rawText: string): Promise<BallotAnalysis> {
  const trimmed = rawText.trim();
  if (!trimmed) throw new Error("ballot_text_empty");

  const user = `BALLOT TEXT (extracted from a photo, may have OCR noise):
${trimmed.slice(0, 8000)}`;

  const response = await client().messages.create({
    model: config.ANTHROPIC_MODEL,
    max_tokens: 3000,
    system: SYSTEM,
    messages: [{ role: "user", content: user }],
  });
  const text = response.content.find((b) => b.type === "text");
  if (!text || text.type !== "text") throw new Error("Claude returned no text");
  const parsed = parseJson(text.text);
  return {
    generatedAtISO: new Date().toISOString(),
    model: config.ANTHROPIC_MODEL,
    items: parsed.items,
    notice: parsed.notice,
  };
}

function parseJson(s: string): { items: BallotItemBrief[]; notice: string } {
  const cleaned = s
    .replace(/^```json\s*/i, "")
    .replace(/```$/i, "")
    .trim();
  try {
    const obj = JSON.parse(cleaned);
    if (!Array.isArray(obj.items)) throw new Error("missing items");
    return {
      items: obj.items as BallotItemBrief[],
      notice:
        typeof obj.notice === "string"
          ? obj.notice
          : "Informational only — not voting advice.",
    };
  } catch (err) {
    throw new Error(`ballot_parse_failed: ${err instanceof Error ? err.message : String(err)}`);
  }
}
