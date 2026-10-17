import Anthropic from "@anthropic-ai/sdk";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { config } from "../config.js";
import type { BallotContestRaw, VoterInfo } from "./voterRail.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

export type ContestKind = "candidate" | "measure" | "judicial" | "other";

export interface BallotContestBrief {
  /** Stable fingerprint over the contest content used for caching. */
  fingerprint: string;
  kind: ContestKind;
  title: string;
  /** Office name for candidate races; null for measures. */
  office?: string;
  district?: string;
  /** 2-3 sentence plain-English explanation of what this is. */
  plainEnglish: string;
  /** Optional — only on measures. */
  whatYesMeans?: string;
  whatNoMeans?: string;
  /** Neutral considerations the voter might weigh. */
  considerations: string[];
  candidates?: BallotBriefCandidate[];
  rawText?: string;
}

export interface BallotBriefCandidate {
  name: string;
  party?: string;
  blurb?: string;
}

export interface SampleBallotResult {
  generatedAtISO: string;
  electionId?: string;
  electionName?: string;
  electionDay?: string;
  contests: BallotContestBrief[];
  notice: string;
}

interface BallotCache {
  version: 1;
  /** Per-contest cached briefs keyed by fingerprint. */
  briefs: Record<string, BallotContestBrief>;
}

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) _client = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  return _client;
}

export class SampleBallotService {
  private cache: BallotCache;
  private readonly cachePath: string;

  private constructor(cache: BallotCache, cachePath: string) {
    this.cache = cache;
    this.cachePath = cachePath;
  }

  static async load(cachePath?: string): Promise<SampleBallotService> {
    const path = cachePath ?? resolve(__dirname, "..", "..", "data", "ballot-cache.json");
    let cache: BallotCache = { version: 1, briefs: {} };
    try {
      const text = await readFile(path, "utf8");
      const parsed = JSON.parse(text) as BallotCache;
      if (parsed.version === 1 && typeof parsed.briefs === "object") cache = parsed;
    } catch {
      // first run
    }
    return new SampleBallotService(cache, path);
  }

  async generate(voterInfo: VoterInfo): Promise<SampleBallotResult> {
    const contests = voterInfo.contests ?? [];

    // Generate briefs in parallel, bounded to keep Claude costs sane.
    const briefs: BallotContestBrief[] = [];
    const tasks = contests.map((contest) => () => this.briefFor(contest));
    const concurrency = 4;
    let cursor = 0;
    async function runner(): Promise<void> {
      while (cursor < tasks.length) {
        const idx = cursor++;
        const result = await tasks[idx]!();
        if (result) briefs[idx] = result;
      }
    }
    await Promise.all(Array.from({ length: Math.min(concurrency, tasks.length) }, runner));

    const result: SampleBallotResult = {
      generatedAtISO: new Date().toISOString(),
      contests: briefs.filter(Boolean),
      notice: "Informational only — not voting advice. Source: Google Civic Information API + Claude explanations.",
    };
    if (voterInfo.election) {
      result.electionId = voterInfo.election.id;
      result.electionName = voterInfo.election.name;
      result.electionDay = voterInfo.election.electionDay;
    }
    return result;
  }

  private async briefFor(contest: BallotContestRaw): Promise<BallotContestBrief | null> {
    const fingerprint = fingerprintContest(contest);
    const cached = this.cache.briefs[fingerprint];
    if (cached) return cached;

    const kind = classifyContest(contest);
    const title = contestTitle(contest);
    const rawText = JSON.stringify(contest, null, 2).slice(0, 4000);

    const system = `You explain ballot contests to a busy non-expert. Be neutral — never tell anyone how to vote. Output strict JSON only.`;

    const userPrompt = `BALLOT CONTEST (raw from Google Civic API):
${rawText}

KIND: ${kind}

Output JSON with this exact shape:
{
  "plainEnglish": "2-3 sentences explaining what this contest is about",
  "whatYesMeans": "1 sentence — what YES does (null for candidate races)",
  "whatNoMeans": "1 sentence — what NO does (null for candidate races)",
  "considerations": ["3-5 short bullets a voter might weigh — facts, not advice"],
  "candidates": [ { "name": "...", "party": "...", "blurb": "1 sentence describing them or their party" } ]
}

For candidate races, fill candidates from the raw input (party affiliation if known). For measures, candidates can be omitted. Never invent statistics, sources, or biographical details beyond what's in the raw input.`;

    let parsed: Pick<BallotContestBrief, "plainEnglish" | "whatYesMeans" | "whatNoMeans" | "considerations" | "candidates"> = {
      plainEnglish: kind === "measure" ? "This measure appeared on the ballot. Read the official text below for the full proposal." : "This race is on your ballot. Candidate information shown below.",
      considerations: [],
    };

    try {
      const response = await client().messages.create({
        model: config.ANTHROPIC_MODEL,
        max_tokens: 700,
        system,
        messages: [{ role: "user", content: userPrompt }],
      });
      const text = response.content.find((b) => b.type === "text");
      if (text && text.type === "text") {
        const cleaned = text.text
          .replace(/^```json\s*/i, "")
          .replace(/```$/i, "")
          .trim();
        const json = JSON.parse(cleaned);
        if (typeof json.plainEnglish === "string") {
          parsed = {
            plainEnglish: json.plainEnglish,
            considerations: Array.isArray(json.considerations) ? json.considerations : [],
          };
          if (json.whatYesMeans) parsed.whatYesMeans = String(json.whatYesMeans);
          if (json.whatNoMeans) parsed.whatNoMeans = String(json.whatNoMeans);
          if (Array.isArray(json.candidates)) parsed.candidates = json.candidates as BallotBriefCandidate[];
        }
      }
    } catch {
      // Fall back to the template so the user still sees the contest.
    }

    const brief: BallotContestBrief = {
      fingerprint,
      kind,
      title,
      ...parsed,
    };
    if (contest.office) brief.office = contest.office;
    if (contest.district?.name) brief.district = contest.district.name;
    if (kind === "measure" && contest.referendumText) brief.rawText = contest.referendumText.slice(0, 1200);
    if (!brief.candidates && contest.candidates) {
      brief.candidates = contest.candidates.map((c) => {
        const out: BallotBriefCandidate = { name: c.name };
        if (c.party) out.party = c.party;
        return out;
      });
    }

    this.cache.briefs[fingerprint] = brief;
    void this.persist();
    return brief;
  }

  private async persist() {
    try {
      await mkdir(dirname(this.cachePath), { recursive: true });
      await writeFile(this.cachePath, JSON.stringify(this.cache, null, 2), "utf8");
    } catch {
      // non-fatal
    }
  }
}

function fingerprintContest(contest: BallotContestRaw): string {
  const stable = JSON.stringify({
    type: contest.type,
    office: contest.office,
    ballotTitle: contest.ballotTitle,
    referendumTitle: contest.referendumTitle,
    referendumText: contest.referendumText?.slice(0, 500),
    candidates: contest.candidates?.map((c) => `${c.name}|${c.party ?? ""}`),
  });
  return createHash("sha1").update(stable).digest("hex").slice(0, 16);
}

function classifyContest(contest: BallotContestRaw): ContestKind {
  const type = (contest.type ?? "").toLowerCase();
  if (type.includes("referendum") || contest.referendumTitle || contest.referendumText) return "measure";
  if (type.includes("retention") || (contest.office ?? "").toLowerCase().includes("judge")) return "judicial";
  if (type.includes("general") || contest.candidates) return "candidate";
  return "other";
}

function contestTitle(contest: BallotContestRaw): string {
  return (
    contest.referendumTitle ||
    contest.office ||
    contest.ballotTitle ||
    "Ballot contest"
  );
}
