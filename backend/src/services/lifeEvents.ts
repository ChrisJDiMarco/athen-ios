import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import { withNeutralityGuardrail } from "../lib/neutralityGuardrail.js";

/**
 * Life-event planner. Takes natural language ("I just got laid off in NJ")
 * + optional user profile (state, ZIP, factors) and asks Claude to produce
 * a structured, actionable plan: immediate steps, near-term steps, qualifying
 * programs, civic asks, and notes. No conversation memory — each call is
 * stateless. The iOS app persists prior plans locally.
 */

export type StepUrgency = "today" | "this-week" | "this-month" | "ongoing";
export type StepActionKind = "url" | "phone" | "calendar" | "file-issue" | "service" | "petition" | "manual";

export interface PlanStep {
  id: string;
  title: string;
  description: string;
  urgency: StepUrgency;
  action: {
    kind: StepActionKind;
    /** URL to open (action kind = url, file-issue, petition, service). */
    url?: string;
    /** Phone number (action kind = phone). */
    phone?: string;
    /** Calendar event details (action kind = calendar). */
    calendarTitle?: string;
    calendarDateISO?: string;
    /** Display label override; falls back to action kind default. */
    label?: string;
  };
}

export interface QualifyingProgram {
  name: string;
  agency: string;
  eligibility: string;
  benefits: string;
  applyURL?: string;
  notes?: string;
}

export interface CivicAsk {
  title: string;
  description: string;
  scope: "federal" | "state" | "local" | "unknown";
  why: string;
}

export interface LifeEventPlan {
  generatedAtISO: string;
  situation: string;
  category: string;
  immediateSteps: PlanStep[];
  nearTermSteps: PlanStep[];
  longerTermSteps: PlanStep[];
  qualifyingPrograms: QualifyingProgram[];
  civicAsks: CivicAsk[];
  notes: string[];
}

export interface LifeEventProfile {
  stateCode?: string;
  stateName?: string;
  zip?: string;
  locality?: string;
  factors?: string[];
  householdSize?: number;
  incomeBand?: string;
}

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) _client = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  return _client;
}

const SYSTEM = `You are Athen's life-event civic planner. The user tells you something that just happened in their life (a layoff, a baby, a move, a new business, a death, a medical event, a new visa status, etc.). You produce a concrete, structured plan of what to do, when to do it, what programs they qualify for, and what civic actions might matter.

CRITICAL RULES:
- Never tell anyone how to vote.
- Never invent program names, eligibility cutoffs, dollar amounts, or deadlines. If a number isn't widely known, say "varies by state — check the linked portal."
- Use the user's state when relevant (e.g., NJ unemployment, CA paid family leave). When state matters but isn't provided, say "rules vary by state."
- Be practical. Lead with the thing they should do today.
- Plain English. No jargon without a one-line explainer.
- Keep the action plan tight: at most 5 immediate, 5 near-term, 5 longer-term steps. Better to be specific than exhaustive.
- For qualifying programs, only include ones that plausibly apply given the situation. Don't list every social program.
- For civic asks, only include them when there's a real, current civic lever (e.g., this state is debating paid family leave). It's fine to return an empty civic asks array.

OUTPUT: strict JSON only, single object, no markdown fences, no preamble. Schema:

{
  "situation": "1 sentence summarizing what happened, in your words",
  "category": "snake_case category like layoff, baby, move_in_state, move_out_of_state, house_purchase, new_business, illness, divorce, retirement, immigration_milestone, death_in_family, caregiving, military_separation, other",
  "immediateSteps": [
    {
      "id": "auto-generated short hash",
      "title": "Imperative — e.g. File for unemployment",
      "description": "1-2 sentences",
      "urgency": "today|this-week|this-month|ongoing",
      "action": {
        "kind": "url|phone|calendar|file-issue|service|petition|manual",
        "url": "https://... (when kind=url)",
        "phone": "1-800-... (when kind=phone)",
        "calendarTitle": "string (when kind=calendar)",
        "calendarDateISO": "ISO date (when kind=calendar)",
        "label": "optional button label override"
      }
    }
  ],
  "nearTermSteps": [ ...same shape... ],
  "longerTermSteps": [ ...same shape... ],
  "qualifyingPrograms": [
    {
      "name": "e.g. Unemployment Insurance",
      "agency": "U.S. Dept of Labor + state agency",
      "eligibility": "Plain English — who qualifies",
      "benefits": "Plain English — what they get",
      "applyURL": "https://...",
      "notes": "optional — anything tricky"
    }
  ],
  "civicAsks": [
    {
      "title": "What to push for",
      "description": "Plain English",
      "scope": "federal|state|local|unknown",
      "why": "Why this matters given the situation"
    }
  ],
  "notes": [
    "Anything important the user should know but didn't fit above"
  ]
}

When the action.kind is "url", "phone", "calendar", or "manual", you must include the matching field. The "id" can be any short string — the iOS app uses it as a stable key.`;

export class LifeEventsService {
  async plan(description: string, profile: LifeEventProfile = {}): Promise<LifeEventPlan> {
    const trimmed = description.trim();
    if (trimmed.length < 4) throw new Error("life_event_too_short");

    const profileLines: string[] = [];
    if (profile.stateName) profileLines.push(`State: ${profile.stateName} (${profile.stateCode ?? "?"})`);
    if (profile.zip) profileLines.push(`ZIP: ${profile.zip}`);
    if (profile.locality) profileLines.push(`Locality: ${profile.locality}`);
    if (profile.factors && profile.factors.length > 0) profileLines.push(`Civic factors: ${profile.factors.join(", ")}`);
    if (profile.householdSize) profileLines.push(`Household size: ${profile.householdSize}`);
    if (profile.incomeBand) profileLines.push(`Income band: ${profile.incomeBand}`);

    const userMessage = [
      `SITUATION FROM USER: ${trimmed}`,
      "",
      profileLines.length > 0 ? `USER PROFILE:\n${profileLines.join("\n")}` : "USER PROFILE: not provided",
      "",
      `TODAY: ${new Date().toISOString().slice(0, 10)}`,
    ].join("\n");

    const response = await client().messages.create({
      model: config.ANTHROPIC_MODEL,
      // Plans can be long: 3 step sections × 5 steps × ~200 tokens, plus
      // programs, civic asks, notes. 3200 truncates routinely mid-JSON.
      // 8000 leaves comfortable headroom for verbose plans.
      max_tokens: 8000,
      system: withNeutralityGuardrail(SYSTEM),
      messages: [{ role: "user", content: userMessage }],
    });

    const text = response.content.find((b) => b.type === "text");
    if (!text || text.type !== "text") throw new Error("life_event_no_text");
    const parsed = parsePlan(text.text);
    return {
      ...parsed,
      generatedAtISO: new Date().toISOString(),
    };
  }
}

function parsePlan(raw: string): Omit<LifeEventPlan, "generatedAtISO"> {
  const cleaned = raw
    .replace(/^```json\s*/i, "")
    .replace(/```$/i, "")
    .trim();
  let parsed: any;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    // Claude truncated mid-JSON. Try to salvage by repairing the trailing
    // braces/brackets so we at least keep the parts that did make it.
    const salvaged = trySalvageJson(cleaned);
    if (!salvaged) {
      throw new Error("life_event_bad_json: Claude returned malformed JSON. Try again or shorten your description.");
    }
    parsed = salvaged;
  }

  if (typeof parsed.situation !== "string" || typeof parsed.category !== "string") {
    throw new Error("life_event_invalid_shape");
  }

  const normalizeSteps = (xs: any[]): PlanStep[] =>
    (Array.isArray(xs) ? xs : []).map((s, idx) => {
      const action = s.action ?? {};
      const step: PlanStep = {
        id: typeof s.id === "string" && s.id ? s.id : `step-${idx}`,
        title: String(s.title ?? ""),
        description: String(s.description ?? ""),
        urgency: (["today", "this-week", "this-month", "ongoing"].includes(s.urgency) ? s.urgency : "this-week") as StepUrgency,
        action: { kind: validKind(action.kind) },
      };
      if (action.url) step.action.url = String(action.url);
      if (action.phone) step.action.phone = String(action.phone);
      if (action.calendarTitle) step.action.calendarTitle = String(action.calendarTitle);
      if (action.calendarDateISO) step.action.calendarDateISO = String(action.calendarDateISO);
      if (action.label) step.action.label = String(action.label);
      return step;
    });

  const programs: QualifyingProgram[] = (Array.isArray(parsed.qualifyingPrograms) ? parsed.qualifyingPrograms : []).map((p: any) => {
    const out: QualifyingProgram = {
      name: String(p.name ?? ""),
      agency: String(p.agency ?? ""),
      eligibility: String(p.eligibility ?? ""),
      benefits: String(p.benefits ?? ""),
    };
    if (p.applyURL) out.applyURL = String(p.applyURL);
    if (p.notes) out.notes = String(p.notes);
    return out;
  });

  const asks: CivicAsk[] = (Array.isArray(parsed.civicAsks) ? parsed.civicAsks : []).map((a: any) => ({
    title: String(a.title ?? ""),
    description: String(a.description ?? ""),
    scope: (["federal", "state", "local"].includes(a.scope) ? a.scope : "unknown") as CivicAsk["scope"],
    why: String(a.why ?? ""),
  }));

  return {
    situation: parsed.situation,
    category: parsed.category,
    immediateSteps: normalizeSteps(parsed.immediateSteps),
    nearTermSteps: normalizeSteps(parsed.nearTermSteps),
    longerTermSteps: normalizeSteps(parsed.longerTermSteps),
    qualifyingPrograms: programs,
    civicAsks: asks,
    notes: Array.isArray(parsed.notes) ? parsed.notes.map(String) : [],
  };
}

function validKind(k: any): StepActionKind {
  const allowed: StepActionKind[] = ["url", "phone", "calendar", "file-issue", "service", "petition", "manual"];
  return allowed.includes(k) ? (k as StepActionKind) : "manual";
}

/**
 * Best-effort recovery when Claude truncates mid-JSON (e.g., hits max_tokens
 * mid-array). We scan forward through the string, track brace + bracket +
 * quote depth, and close out anything still open. Loses any half-written
 * trailing value but preserves all complete entries before the cutoff.
 */
function trySalvageJson(raw: string): any | null {
  let depth = 0;        // {} depth
  let arrayDepth = 0;   // [] depth
  let inString = false;
  let escape = false;
  let lastCompletePos = -1;
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
    // Mark positions where the object has just closed a child completely:
    // after a `,` or `]` or `}` at the outer level we know everything up
    // to here is well-formed if we close out properly.
    if ((ch === "," || ch === "}" || ch === "]") && depth > 0 && !inString) {
      lastCompletePos = i;
    }
  }
  if (lastCompletePos < 0) return null;
  // Take everything up to and including the last safe position, then strip
  // trailing comma if any, then append closing brackets/braces to balance.
  let truncated = raw.slice(0, lastCompletePos + 1).replace(/,\s*$/, "");
  // Recount depth in the truncated piece — string state should be balanced
  // by now since we stopped at a structural char.
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
