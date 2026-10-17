import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));

export type VoteOutcome = "yes" | "no" | "abstain" | "absent" | "not-voting";
export type VoteResult = "passed" | "failed" | "tied" | "scheduled";

export interface StoredVote {
  /** Stable per-vote id: sha1 of (source, billExtId, motion, voteDateISO). */
  id: string;
  /** Matches issueStore's sourceFingerprint when the bill is in our store. */
  issueFingerprint?: string;
  /** Loose match — same value the connector used as sourceRecordID. */
  billExternalID: string;
  source: "openstates" | "congress";
  chamber: string;
  motion: string;
  voteDateISO: string;
  result: VoteResult;
  totals: {
    yes: number;
    no: number;
    abstain: number;
    absent: number;
  };
  /** Each official's vote, keyed by their name (canonicalized lowercase). */
  byOfficialName: Record<string, VoteOutcome>;
  ingestedAtISO: string;
}

interface VoteCache {
  version: 1;
  votes: Record<string, StoredVote>;
}

export class VoteStore {
  private cache: VoteCache;
  private readonly path: string;

  private constructor(cache: VoteCache, path: string) {
    this.cache = cache;
    this.path = path;
  }

  static async load(path?: string): Promise<VoteStore> {
    const resolved = path ?? resolve(__dirname, "..", "..", "data", "votes.json");
    let cache: VoteCache = { version: 1, votes: {} };
    try {
      const text = await readFile(resolved, "utf8");
      const parsed = JSON.parse(text) as VoteCache;
      if (parsed.version === 1 && typeof parsed.votes === "object") cache = parsed;
    } catch {
      // first run
    }
    return new VoteStore(cache, resolved);
  }

  all(): StoredVote[] {
    return Object.values(this.cache.votes);
  }

  byBillExternalID(billExternalID: string): StoredVote[] {
    return this.all().filter((v) => v.billExternalID === billExternalID);
  }

  byIssueFingerprint(fingerprint: string): StoredVote[] {
    return this.all().filter((v) => v.issueFingerprint === fingerprint);
  }

  /** Most recent vote per bill — used when there are multiple (committee, floor, etc.). */
  mostRecentForBill(billExternalID: string): StoredVote | undefined {
    return this.byBillExternalID(billExternalID).sort((a, b) =>
      b.voteDateISO.localeCompare(a.voteDateISO),
    )[0];
  }

  upsert(vote: Omit<StoredVote, "id" | "ingestedAtISO"> & { id?: string }): StoredVote {
    const id = vote.id ?? Self.voteId(vote);
    const stored: StoredVote = {
      ...vote,
      id,
      ingestedAtISO: new Date().toISOString(),
    };
    this.cache.votes[id] = stored;
    void this.persist();
    return stored;
  }

  /** How many votes we've recorded total. */
  count(): number {
    return Object.keys(this.cache.votes).length;
  }

  stats() {
    const list = this.all();
    return {
      total: list.length,
      bySource: list.reduce(
        (acc, v) => {
          acc[v.source] = (acc[v.source] ?? 0) + 1;
          return acc;
        },
        { openstates: 0, congress: 0 } as Record<string, number>,
      ),
      uniqueOfficials: new Set(list.flatMap((v) => Object.keys(v.byOfficialName))).size,
    };
  }

  private async persist() {
    try {
      await mkdir(dirname(this.path), { recursive: true });
      await writeFile(this.path, JSON.stringify(this.cache, null, 2), "utf8");
    } catch {
      // non-fatal
    }
  }
}

// Class-side helper exposed via a Self alias to make the upsert call readable.
const Self = {
  voteId(v: Omit<StoredVote, "id" | "ingestedAtISO">): string {
    return createHash("sha1")
      .update(`${v.source}|${v.billExternalID}|${v.motion}|${v.voteDateISO}`)
      .digest("hex")
      .slice(0, 24);
  },
};

/** Canonicalize an official name for vote lookups. */
export function canonicalizeOfficialName(name: string): string {
  return name
    .toLowerCase()
    .replace(/[.,]/g, "")
    .replace(/\s+/g, " ")
    .replace(/^(sen|rep|representative|senator|hon)\.?\s+/i, "")
    .trim();
}
