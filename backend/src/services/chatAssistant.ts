import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import { formatForModel, webSearch } from "./webSearch.js";

export interface ChatProfileSummary {
  zipCode: string;
  stateCode: string;
  stateName: string;
  localityLabel?: string;
  factors?: string[];
  officials: {
    federalSenators: { name: string; title: string; district?: string }[];
    federalHouseRep?: { name: string; title: string; district?: string };
    stateSenators: { name: string; title: string; district?: string }[];
    stateRepresentatives: { name: string; title: string; district?: string }[];
    local: { name: string; title: string; district?: string }[];
  };
}

export interface ChatIssueSummary {
  id: string;
  title: string;
  jurisdiction: string;
  scope: string;
  impactLevel: string;
  voteDateISO: string;
  summary: string;
  whyItMatters?: string;
  recommendedAction?: string;
  trustScore?: number;
  sourceName?: string;
}

export interface ChatFilingHistory {
  issueTitle: string;
  action: "endorse" | "oppose";
  officialName: string;
  sentAt: string;
  confirmationCode: string;
}

export interface ChatMatchedServiceSummary {
  id: string;
  title: string;
  category: string;
  provider: string;
  summary: string;
  matchScore: number;
  nextStep: string;
  missingDocuments: string[];
  sourceName: string;
  sourceURL: string;
}

export interface ChatContext {
  profile?: ChatProfileSummary;
  visibleIssues: ChatIssueSummary[];
  filingHistory: ChatFilingHistory[];
  matchedServices?: ChatMatchedServiceSummary[];
}

export interface ChatTurn {
  role: "user" | "assistant";
  content: string;
}

const SYSTEM_BASE = `You are the Athen assistant — a smart, helpful AI built into the Athen civic app. You're at your best on civic + government topics, but you can also help with anything else the user wants to talk about: planning their day, drafting an email, explaining a concept, finding a recipe, debugging code, anything.

CRITICAL — Always reason about time relative to {{TODAY_HUMAN}} ({{TODAY_ISO}}). A vote dated before today is in the PAST, not upcoming. Use "earlier this year", "last week", "tomorrow", "next month" based on the actual gap from today. Never describe a past event as upcoming.

# What you do

**Civic-specific (your specialty)**
1. Translate bureaucratic language — surface what changes, who pays, when it happens.
2. Help users find public services — eligibility, documents, next steps.
3. Help them navigate the app. Tabs are Home (Today/News/Pulse view modes), Act (Vote/Petitions/Officials/Filings), Square (community feed), Assistant (you), You (profile/reps).
4. Help them act — they can endorse/oppose any item from its detail screen → drafts and files to the right official.
5. Help them organize outreach with concrete plans (audience, channels, message lines, checklist).
6. Draft balanced AI briefs — plain-English stakes, supporter logic, critic concerns, tradeoffs, next step.
7. Act like a civic radar — prioritize deadlines, explain relevance, push toward useful action.

**General-purpose**
You can help with anything else too. Be a smart, generally-capable assistant. Don't refuse general questions just because they're not civic.

# Web search

You have a \`web_search\` tool. **Use it when:**
- The user asks about current events, news, or anything time-sensitive
- The user asks for a fact you're not confident about
- The user asks "what's the latest on…", "today", "this week", "recently"
- The question is about something local that the civic context cards don't cover
- The user explicitly says "look it up", "search", "google"

**Do NOT use it for:**
- General knowledge questions you can answer from training
- Anything about the app itself (navigation, features)
- Anything already covered in the visible_issues, profile, or filing_history context below
- Conversational replies that don't need a fact

When you cite a search result, use [1], [2], etc. and include the URL the user can click.

# Style rules

- Be direct. No hedging, no lectures, no "as an AI". Short paragraphs. Bullets when listing.
- Use the user's location, reps, and civic context when known.
- Cite issues by title (e.g. "H.R. 4218") when discussing them.
- When asked what to do, lead with one recommended action and the deadline.
- For civic claims, don't invent statistics — say "I don't have that detail — try the source" or use the search tool.
- If the user hasn't set a ZIP and asks something civic, point them to the You tab.
- Label outreach copy clearly ("Text to send", "Email subject", "Door-knock script").
- Refuse to draft messages that target an individual's private life, threaten anyone, or impersonate the user.
- For non-civic questions, answer in the user's voice — friendly, helpful, smart-friend tone.`;

const TOOLS: Anthropic.Tool[] = [
  {
    name: "web_search",
    description:
      "Search the web for current information. Use this for time-sensitive questions, recent events, specific facts you're unsure of, or anything outside the app's built-in context. Don't use for general knowledge you can answer from training, or for app navigation questions.",
    input_schema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Focused search query — 3-10 words. Be specific. Include 'today' or '2026' if recency matters.",
        },
      },
      required: ["query"],
    },
  },
];

export class ChatAssistant {
  private readonly client: Anthropic;

  constructor(client?: Anthropic) {
    this.client = client ?? new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  }

  buildSystemPrompt(context: ChatContext): string {
    const now = new Date();
    const todayISO = now.toISOString().slice(0, 10);
    const todayHuman = now.toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" });
    const baseDated = SYSTEM_BASE
      .replaceAll("{{TODAY_ISO}}", todayISO)
      .replaceAll("{{TODAY_HUMAN}}", todayHuman);
    const sections: string[] = [baseDated];

    if (context.profile) {
      sections.push(this.renderProfileSection(context.profile));
    } else {
      sections.push(
        "<user_profile>\nNo ZIP set yet. Encourage the user to open the You tab and enter their ZIP so you can personalize answers.\n</user_profile>",
      );
    }

    sections.push(this.renderIssuesSection(context.visibleIssues));
    sections.push(this.renderServicesSection(context.matchedServices ?? []));
    sections.push(this.renderFilingsSection(context.filingHistory));

    return sections.join("\n\n");
  }

  private renderProfileSection(profile: ChatProfileSummary): string {
    const lines: string[] = [];
    lines.push("<user_profile>");
    lines.push(`Location: ${profile.localityLabel ?? profile.stateName} (${profile.stateCode}), ZIP ${profile.zipCode}.`);
    if (profile.factors && profile.factors.length > 0) {
      lines.push(`Civic context: ${profile.factors.join(", ")}.`);
    }
    lines.push("Representatives the user can file with:");
    for (const s of profile.officials.federalSenators) {
      lines.push(`- ${s.title}: ${s.name}${s.district ? ` — ${s.district}` : ""}`);
    }
    if (profile.officials.federalHouseRep) {
      const r = profile.officials.federalHouseRep;
      lines.push(`- ${r.title}: ${r.name}${r.district ? ` — ${r.district}` : ""}`);
    }
    for (const s of profile.officials.stateSenators) {
      lines.push(`- ${s.title}: ${s.name}${s.district ? ` — ${s.district}` : ""}`);
    }
    for (const r of profile.officials.stateRepresentatives) {
      lines.push(`- ${r.title}: ${r.name}${r.district ? ` — ${r.district}` : ""}`);
    }
    for (const l of profile.officials.local) {
      lines.push(`- ${l.title}: ${l.name}${l.district ? ` — ${l.district}` : ""}`);
    }
    if (
      profile.officials.federalSenators.length === 0 &&
      !profile.officials.federalHouseRep &&
      profile.officials.local.length === 0
    ) {
      lines.push("(No reps resolved yet — the backend may be offline or the ZIP is unassigned.)");
    }
    lines.push("</user_profile>");
    return lines.join("\n");
  }

  private renderIssuesSection(issues: ChatIssueSummary[]): string {
    if (issues.length === 0) {
      return "<visible_issues>\nNo items currently visible in the user's feed.\n</visible_issues>";
    }
    const rows = issues.map(
      (i) =>
        `- "${i.title}" (${i.scope}, ${i.impactLevel}, ${i.jurisdiction}, vote ${i.voteDateISO}) — ${i.summary} Why it matters: ${i.whyItMatters ?? "Not specified"}. Recommended action: ${i.recommendedAction ?? "Review"}. Source: ${i.sourceName ?? "source card"}${typeof i.trustScore === "number" ? `, trust ${i.trustScore}%` : ""}.`,
    );
    return `<visible_issues>\n${rows.join("\n")}\n</visible_issues>`;
  }

  private renderServicesSection(services: ChatMatchedServiceSummary[]): string {
    if (services.length === 0) {
      return "<matched_services>\nNo public-service matches are currently attached to the chat context.\n</matched_services>";
    }
    const rows = services.map(
      (s) =>
        `- "${s.title}" (${s.category}, ${s.matchScore}% fit, ${s.provider}) — ${s.summary} Next step: ${s.nextStep}. Missing docs: ${s.missingDocuments.length > 0 ? s.missingDocuments.join(", ") : "none listed"}. Source: ${s.sourceName} (${s.sourceURL}).`,
    );
    return `<matched_services>\n${rows.join("\n")}\n</matched_services>`;
  }

  private renderFilingsSection(filings: ChatFilingHistory[]): string {
    if (filings.length === 0) {
      return "<filing_history>\nThe user has not filed anything yet.\n</filing_history>";
    }
    const rows = filings.map(
      (f) =>
        `- ${f.sentAt}: ${f.action.toUpperCase()} "${f.issueTitle}" → ${f.officialName} (conf ${f.confirmationCode})`,
    );
    return `<filing_history>\n${rows.join("\n")}\n</filing_history>`;
  }

  stream(args: { messages: ChatTurn[]; context: ChatContext }): AsyncIterable<ChatStreamEvent> {
    const system = this.buildSystemPrompt(args.context);
    const client = this.client;

    const initial: Anthropic.MessageParam[] = args.messages
      .slice(-20)
      .filter((m) => m.content.trim().length > 0)
      .map((m) => ({ role: m.role as "user" | "assistant", content: m.content }));

    return (async function* (): AsyncIterable<ChatStreamEvent> {
      const conversation: Anthropic.MessageParam[] = [...initial];
      // Hard cap so a misbehaving model can't loop forever calling tools.
      // After this many rounds we force a text-only final pass so the user
      // ALWAYS sees an answer — even if the model wanted to keep searching.
      const MAX_TOOL_ROUNDS = 3;
      let textProduced = false;

      for (let round = 0; round <= MAX_TOOL_ROUNDS; round += 1) {
        // On the last allowed round, disable tools so the model is forced
        // to synthesize a text answer from what it already has.
        const isLastRound = round === MAX_TOOL_ROUNDS;
        const stream = client.messages.stream({
          model: config.ANTHROPIC_MODEL,
          max_tokens: 4000,
          system,
          ...(isLastRound ? {} : { tools: TOOLS }),
          messages: conversation,
        });

        for await (const event of stream) {
          if (event.type === "content_block_start") {
            if (event.content_block.type === "tool_use") {
              yield { tool_start: { name: event.content_block.name } };
            }
          } else if (event.type === "content_block_delta") {
            if (event.delta.type === "text_delta" && event.delta.text.length > 0) {
              textProduced = true;
              yield { delta: event.delta.text };
            }
          }
        }

        const finalMessage = await stream.finalMessage();
        if (finalMessage.stop_reason !== "tool_use") {
          // Model produced its final answer (text or end_turn).
          break;
        }

        if (isLastRound) {
          // Model wanted MORE tools but we disabled them — this branch is
          // defensive. Anthropic should never return tool_use when tools=[]
          // but in case it does, bail to avoid an infinite loop.
          break;
        }

        // Replay the assistant turn (with tool_use blocks) into history,
        // then run each tool and append tool_result blocks as a user turn.
        conversation.push({ role: "assistant", content: finalMessage.content });

        const toolResults: Anthropic.ToolResultBlockParam[] = [];
        for (const block of finalMessage.content) {
          if (block.type !== "tool_use") continue;
          const result = await runTool(block.name, block.input);
          yield { tool_done: { name: block.name, summary: result.summary } };
          toolResults.push({
            type: "tool_result",
            tool_use_id: block.id,
            content: result.text,
          });
        }
        conversation.push({ role: "user", content: toolResults });
      }

      // Last-resort fallback so the user never sees an empty bubble after
      // the chips finish. Only fires if the model produced no text at all
      // (e.g. last-round tool_use refusal or a transient stream issue).
      if (!textProduced) {
        yield { delta: "Sorry — I tried to look this up but couldn't pull together a clean answer. Try rephrasing or asking something more specific." };
      }

      yield { done: true };
    })();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stream events + tool runner

/// Event types the route layer encodes as SSE events for iOS.
export type ChatStreamEvent =
  | { delta: string }
  | { tool_start: { name: string } }
  | { tool_done: { name: string; summary: string } }
  | { done: true };

interface ToolResult {
  text: string;
  summary: string;
}

async function runTool(name: string, input: unknown): Promise<ToolResult> {
  switch (name) {
    case "web_search": {
      const query =
        typeof (input as { query?: unknown })?.query === "string"
          ? (input as { query: string }).query
          : "";
      const resp = await webSearch(query);
      const summary = resp.error
        ? `${query} — search failed`
        : `${query} — ${resp.results.length} results`;
      return { text: formatForModel(resp), summary };
    }
    default:
      return { text: `Unknown tool: ${name}`, summary: `unknown tool ${name}` };
  }
}
