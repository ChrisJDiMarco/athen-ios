import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Per-issue endorse/oppose tally. Persisted to disk so counts survive
 * restarts. Incremented from /v1/file on each successful filing — read
 * from the new /v1/issues/:id/tally endpoint by iOS to display social
 * proof above the action bar.
 *
 * Privacy: stores ONLY counts. No installId, no who-said-what mapping.
 * Aggregate-only.
 */

export interface IssueTally {
  endorseCount: number;
  opposeCount: number;
}

interface StoreFile {
  version: 1;
  tallies: Record<string, IssueTally>;
}

export class FilingTallyStore {
  private constructor(
    private readonly path: string,
    private cache: StoreFile,
  ) {}

  static async load(path?: string): Promise<FilingTallyStore> {
    const resolved = path ?? resolve(__dirname, "..", "..", "data", "filing-tallies.json");
    try {
      const text = await readFile(resolved, "utf8");
      const parsed = JSON.parse(text) as StoreFile;
      if (parsed.version === 1 && typeof parsed.tallies === "object") {
        return new FilingTallyStore(resolved, parsed);
      }
    } catch {
      // first run
    }
    return new FilingTallyStore(resolved, { version: 1, tallies: {} });
  }

  forIssue(issueId: string): IssueTally {
    return this.cache.tallies[issueId] ?? { endorseCount: 0, opposeCount: 0 };
  }

  async increment(issueId: string, kind: "endorse" | "oppose"): Promise<IssueTally> {
    const existing = this.cache.tallies[issueId] ?? { endorseCount: 0, opposeCount: 0 };
    const next: IssueTally = kind === "endorse"
      ? { endorseCount: existing.endorseCount + 1, opposeCount: existing.opposeCount }
      : { endorseCount: existing.endorseCount, opposeCount: existing.opposeCount + 1 };
    this.cache.tallies[issueId] = next;
    await this.persist();
    return next;
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    await writeFile(this.path, JSON.stringify(this.cache, null, 2));
  }
}
