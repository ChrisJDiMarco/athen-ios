import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));

/// Per Apple Guideline 1.2, UGC apps must provide a mechanism for users to
/// report objectionable content, and must commit to acting on reports within
/// 24 hours. This store persists every report so a human can review.
///
/// Reports include the install ID of the reporter (for de-duping and abuse
/// prevention) but no other PII. The reported post ID is referenced — the
/// actual post content lives client-side, so a real moderation tool would
/// fetch the post payload from the iOS client's separate report-with-content
/// flow (v1.1).

export type ReportStatus = "pending" | "reviewed" | "removed" | "dismissed";

export interface ModerationReport {
  id: string;
  postId: string;
  reason: string;
  reportedAt: string;
  reporterInstallId: string;
  status: ReportStatus;
  reviewedAt?: string;
  reviewerNote?: string;
}

interface StoreFile {
  version: 1;
  reports: ModerationReport[];
}

export class ModerationStore {
  private constructor(private readonly filePath: string, private cache: StoreFile) {}

  static async load(filePath?: string): Promise<ModerationStore> {
    const path = filePath ?? resolve(__dirname, "..", "..", "data", "moderation-reports.json");
    try {
      const text = await readFile(path, "utf8");
      const parsed = JSON.parse(text) as StoreFile;
      if (parsed.version !== 1 || !Array.isArray(parsed.reports)) {
        return new ModerationStore(path, { version: 1, reports: [] });
      }
      return new ModerationStore(path, parsed);
    } catch {
      return new ModerationStore(path, { version: 1, reports: [] });
    }
  }

  async report(input: { postId: string; reason: string; reporterInstallId: string }): Promise<ModerationReport> {
    const now = new Date().toISOString();
    // Dedup: don't accept the same install reporting the same post twice
    // within 24h — counts as spam pressure on the queue.
    const existing = this.cache.reports.find(
      (r) =>
        r.postId === input.postId &&
        r.reporterInstallId === input.reporterInstallId &&
        Date.parse(r.reportedAt) > Date.now() - 24 * 60 * 60 * 1000,
    );
    if (existing) return existing;

    const record: ModerationReport = {
      id: randomUUID(),
      postId: input.postId,
      reason: input.reason.slice(0, 500),
      reportedAt: now,
      reporterInstallId: input.reporterInstallId,
      status: "pending",
    };
    this.cache.reports.push(record);
    await this.persist();
    return record;
  }

  pendingCount(): number {
    return this.cache.reports.filter((r) => r.status === "pending").length;
  }

  /// Counts unique reports per post in the last N hours — used to surface
  /// "this is being reported a lot" auto-hides in a future moderation UI.
  reportsForPost(postId: string, hours = 24): number {
    const cutoff = Date.now() - hours * 60 * 60 * 1000;
    return this.cache.reports.filter(
      (r) => r.postId === postId && Date.parse(r.reportedAt) > cutoff,
    ).length;
  }

  stats() {
    return {
      total: this.cache.reports.length,
      pending: this.pendingCount(),
      lastReportAt: this.cache.reports.at(-1)?.reportedAt ?? null,
    };
  }

  /// Apple data-deletion compliance: remove every report filed by this
  /// install ID. The reported content itself is unaffected (those reports
  /// from OTHER users still count).
  async scrubByReporter(installId: string): Promise<number> {
    const before = this.cache.reports.length;
    this.cache.reports = this.cache.reports.filter(
      (r) => r.reporterInstallId !== installId,
    );
    const removed = before - this.cache.reports.length;
    if (removed > 0) await this.persist();
    return removed;
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, JSON.stringify(this.cache, null, 2), "utf8");
  }
}
