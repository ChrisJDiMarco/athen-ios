import Anthropic from "@anthropic-ai/sdk";
import { createHash } from "node:crypto";
import { config } from "../config.js";
import { withNeutralityGuardrail } from "../lib/neutralityGuardrail.js";
import type { BriefAnalysisService } from "./briefAnalysis.js";
import type { IssueStore, StoredIssue } from "./issueStore.js";

/**
 * Generates a personalized 5-minute spoken civic briefing.
 *
 * Flow:
 *   1. Pick the top N issues for the listener's location.
 *   2. Pull the cached BriefAnalysis for each (generate any missing).
 *   3. Ask Claude to write a tight 700–900-word spoken script with
 *      natural transitions, no jargon, no list-like recitations.
 *   4. Stream that script to ElevenLabs TTS, return the MP3.
 *
 * Falls back gracefully when ElevenLabs isn't configured — the caller
 * gets the script back as text and the iOS app uses AVSpeechSynthesizer.
 */

/**
 * Build the system prompt at the requested duration. ~150 spoken words per
 * minute is the radio-broadcast convention.
 */
function scriptSystemFor(durationMin: 5 | 10 | 15): string {
  const wordTargets = {
    5: "700–900 spoken words",
    10: "1400–1800 spoken words",
    15: "2100–2700 spoken words",
  } as const;
  return `You write the script for "Athen Daily" — a ${durationMin}-minute civic audio briefing read aloud by an AI host. Listeners are commuting, cooking, or walking. They have no screen.

Hard rules:
- Total length: ${wordTargets[durationMin]}.
- No bulleted lists, no "first... second... third...". Use natural transitions ("Closer to home,...", "Meanwhile in PA...", "Heading back to D.C.,...").
- Open warmly with a one-line scene-setter using the user's location and the date.
- End with one specific call to action that fits today's items.
- Pronounce bill numbers naturally ("House Bill 1429", not "HB 1429").
- Never invent facts not in the briefs.
- Conversational, not robotic. Light contractions ("here's", "you've").
- Output PLAIN TEXT only — no SSML, no markdown, no stage directions.`;
}

export interface BriefingScriptArgs {
  stateName: string;
  zip?: string;
  topIssues: StoredIssue[];
  briefs: Awaited<ReturnType<BriefAnalysisService["analyze"]>>[];
  todayLabel: string;
  durationMin: 5 | 10 | 15;
  focus?: string;
}

export class AudioBriefingService {
  private readonly anthropic: Anthropic;
  /** In-memory dedupe so concurrent listeners share one TTS render per day. */
  private inflight = new Map<string, Promise<AudioBriefingResult>>();
  private cache = new Map<string, AudioBriefingResult>();

  constructor(private readonly briefs: BriefAnalysisService, private readonly issues: IssueStore) {
    this.anthropic = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  }

  async render(args: {
    stateCode?: string;
    stateName?: string;
    zip?: string;
    limit?: number;
    duration?: 5 | 10 | 15;
    voiceId?: string;
    focus?: string;
  }): Promise<AudioBriefingResult> {
    const today = new Date();
    const todayLabel = today.toLocaleDateString("en-US", {
      weekday: "long",
      month: "long",
      day: "numeric",
    });

    const durationMin: 5 | 10 | 15 = args.duration ?? 5;
    // Longer briefings cover more issues. ~1 issue per ~3-4 min of script.
    const defaultLimit = durationMin === 5 ? 4 : durationMin === 10 ? 6 : 8;
    const ranked = this.rankIssues(args).slice(0, args.limit ?? defaultLimit);
    const topBriefs = await Promise.all(ranked.map((issue) => this.briefs.analyze(issue)));

    // Cache key — region-shared by state + date + ranked issue set + the
    // listener-controllable params. Users with identical settings share a
    // single ElevenLabs render; custom focus / voice / duration each get
    // their own render.
    const cacheKey = createHash("sha1")
      .update(JSON.stringify({
        stateCode: args.stateCode,
        date: today.toISOString().slice(0, 10),
        issueIds: ranked.map((i) => i.id).sort(),
        duration: durationMin,
        voiceId: args.voiceId ?? "default",
        focus: (args.focus ?? "").trim().toLowerCase(),
      }))
      .digest("hex");

    if (this.cache.has(cacheKey)) {
      return this.cache.get(cacheKey)!;
    }
    if (this.inflight.has(cacheKey)) {
      return this.inflight.get(cacheKey)!;
    }

    const job = this.build({
      stateName: args.stateName ?? args.stateCode ?? "your area",
      topIssues: ranked,
      briefs: topBriefs,
      todayLabel,
      durationMin,
      ...(args.zip !== undefined ? { zip: args.zip } : {}),
      ...(args.focus !== undefined && args.focus.trim().length > 0
        ? { focus: args.focus.trim() }
        : {}),
    }, args.voiceId).then(
      (result) => {
        this.cache.set(cacheKey, result);
        this.inflight.delete(cacheKey);
        return result;
      },
      (err) => {
        this.inflight.delete(cacheKey);
        throw err;
      },
    );
    this.inflight.set(cacheKey, job);
    return job;
  }

  private rankIssues(args: { stateCode?: string; zip?: string }): StoredIssue[] {
    return this.issues
      .all()
      .filter((issue) => {
        if (issue.scope === "federal") return true;
        if (issue.scope === "local-philly") {
          if (args.zip && !args.zip.startsWith("191")) return false;
          if (args.stateCode && args.stateCode !== "PA") return false;
          return true;
        }
        if (issue.scope === "state") {
          if (args.stateCode && issue.stateCode && args.stateCode !== issue.stateCode) return false;
          return true;
        }
        return true;
      })
      .sort((a, b) => {
        const impactScore: Record<typeof a.impactLevel, number> = { urgent: 0, material: 1, watch: 2 };
        if (impactScore[a.impactLevel] !== impactScore[b.impactLevel]) {
          return impactScore[a.impactLevel] - impactScore[b.impactLevel];
        }
        return Date.parse(a.voteDateISO) - Date.parse(b.voteDateISO);
      });
  }

  private async build(args: BriefingScriptArgs, voiceIdOverride?: string): Promise<AudioBriefingResult> {
    const script = await this.writeScript(args);
    const audio = await this.synthesize(script, voiceIdOverride);
    return {
      generatedAtISO: new Date().toISOString(),
      script,
      audio,
      issueIds: args.topIssues.map((i) => i.id),
    };
  }

  private async writeScript(args: BriefingScriptArgs): Promise<string> {
    if (args.briefs.length === 0) {
      return [
        `It's ${args.todayLabel}, and your Athen briefing for ${args.stateName} is quiet today.`,
        "No urgent civic items showed up in your feed. That's not nothing — it means the regular machinery of government is grinding along without surprises for your block.",
        "If you've got a minute, that's a good day to set up your interests in the You tab. The more Athen knows about what affects your household, the better your future briefings will be.",
        "I'll catch you tomorrow.",
      ].join(" ");
    }
    const itemDigest = args.briefs.map((brief, i) => {
      const issue = args.topIssues[i];
      const title = issue?.title ?? brief.headline;
      const sides = brief.twoSides
        .map((s) => `${s.stance.toUpperCase()}: ${s.argument} (${s.who})`)
        .join(" | ");
      return [
        `ITEM ${i + 1}: ${title}`,
        `Headline: ${brief.headline}`,
        `Subhead: ${brief.subhead}`,
        `Lead: ${brief.lead}`,
        `Two sides: ${sides}`,
        `Fiscal: ${brief.fiscalImpact}`,
        `Next: ${brief.recommendedAction}`,
      ].join("\n");
    }).join("\n\n---\n\n");

    const focusLine = args.focus
      ? `\nLISTENER DIRECTION (honor as long as it doesn't conflict with the hard rules above): ${args.focus}\n`
      : "";

    const userPrompt = [
      `Today is ${args.todayLabel}.`,
      `Listener is in ${args.stateName}${args.zip ? ` (ZIP ${args.zip})` : ""}.`,
      focusLine,
      "Write the spoken briefing script now. Use the items below as your only source material — do not invent anything outside them.",
      "",
      itemDigest,
    ].join("\n");

    // 15-min scripts can run ~2700 words ≈ ~3700 tokens. Cap at 6000 to be safe.
    const maxTokens = args.durationMin === 5 ? 2000 : args.durationMin === 10 ? 4000 : 6000;

    const response = await this.anthropic.messages.create({
      model: config.ANTHROPIC_MODEL,
      max_tokens: maxTokens,
      system: withNeutralityGuardrail(scriptSystemFor(args.durationMin)),
      messages: [{ role: "user", content: userPrompt }],
    });
    const block = response.content.find((b) => b.type === "text");
    if (!block || block.type !== "text") throw new Error("Claude returned no script");
    return block.text.trim();
  }

  private async synthesize(script: string, voiceIdOverride?: string): Promise<AudioBriefingResult["audio"]> {
    if (!config.ELEVENLABS_API_KEY) {
      return { provider: "client-fallback", reason: "ELEVENLABS_API_KEY is not set" };
    }
    // ElevenLabs "Sarah" — calm, news-anchor cadence — default when the
    // caller doesn't pass a specific voice ID.
    const voiceId = voiceIdOverride ?? "EXAVITQu4vr4xnSDxMaL";
    const url = `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`;
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          Accept: "audio/mpeg",
          "Content-Type": "application/json",
          "xi-api-key": config.ELEVENLABS_API_KEY,
        },
        body: JSON.stringify({
          text: script,
          model_id: "eleven_turbo_v2_5",
          voice_settings: { stability: 0.55, similarity_boost: 0.75, style: 0.15, use_speaker_boost: true },
        }),
        signal: AbortSignal.timeout(45_000),
      });
      if (!res.ok) {
        const body = await res.text().catch(() => "");
        return { provider: "client-fallback", reason: `ElevenLabs HTTP ${res.status}: ${body.slice(0, 120)}` };
      }
      const buf = Buffer.from(await res.arrayBuffer());
      return {
        provider: "elevenlabs",
        contentType: "audio/mpeg",
        base64: buf.toString("base64"),
        bytes: buf.byteLength,
      };
    } catch (err) {
      return {
        provider: "client-fallback",
        reason: err instanceof Error ? err.message : "ElevenLabs request failed",
      };
    }
  }
}

export interface AudioBriefingResult {
  generatedAtISO: string;
  script: string;
  audio: AudioPayload;
  issueIds: string[];
}

export type AudioPayload =
  | { provider: "elevenlabs"; contentType: "audio/mpeg"; base64: string; bytes: number }
  | { provider: "client-fallback"; reason: string };
