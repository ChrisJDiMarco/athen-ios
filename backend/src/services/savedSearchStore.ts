import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import type { StoredIssue } from "./issueStore.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Persisted saved searches per Athen install. Each search has a free-text
 * query plus optional scope / state filters. When ingestion produces new
 * or updated issues, the matcher scans active searches and queues an
 * inbox notification.
 *
 * Stored at `data/saved-searches.json` so it survives backend restarts.
 */

export type SavedSearchScope = "any" | "federal" | "state" | "local-philly";

export interface SavedSearch {
  id: string;
  installId: string;
  name: string;
  /** Free-text keyword query (case-insensitive). Matches title, summary, topics. */
  query: string;
  scope: SavedSearchScope;
  /** Optional state filter when scope is `state`. */
  stateCode?: string;
  alertsEnabled: boolean;
  createdAt: string;
  updatedAt: string;
  /** Issue IDs that have already triggered an alert — prevents repeat pings. */
  matchedIssueIds: string[];
  /** ISO timestamp of the last time the user pulled the saved-searches list
   *  (read receipts for the unread badge). */
  lastSeenAt?: string;
}

interface StoreFile {
  version: 1;
  searches: SavedSearch[];
}

export class SavedSearchStore {
  private constructor(
    private readonly filePath: string,
    private cache: StoreFile,
  ) {}

  static async load(filePath?: string): Promise<SavedSearchStore> {
    const path = filePath ?? resolve(__dirname, "..", "..", "data", "saved-searches.json");
    try {
      const text = await readFile(path, "utf8");
      const parsed = JSON.parse(text) as StoreFile;
      if (parsed.version === 1 && Array.isArray(parsed.searches)) {
        return new SavedSearchStore(path, parsed);
      }
    } catch {
      // file missing or corrupt — start fresh
    }
    return new SavedSearchStore(path, { version: 1, searches: [] });
  }

  /** All searches for one install. */
  forInstall(installId: string): SavedSearch[] {
    return this.cache.searches
      .filter((s) => s.installId === installId)
      .map((s) => ({ ...s, matchedIssueIds: s.matchedIssueIds.slice() }))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  /** All searches with alerts enabled across all installs — used by the matcher. */
  allActive(): SavedSearch[] {
    return this.cache.searches.filter((s) => s.alertsEnabled);
  }

  async add(input: {
    installId: string;
    name: string;
    query: string;
    scope?: SavedSearchScope;
    stateCode?: string;
    alertsEnabled?: boolean;
  }): Promise<SavedSearch> {
    const now = new Date().toISOString();
    const search: SavedSearch = {
      id: randomUUID(),
      installId: input.installId,
      name: input.name.trim() || input.query.trim() || "Untitled search",
      query: input.query.trim(),
      scope: input.scope ?? "any",
      ...(input.stateCode ? { stateCode: input.stateCode } : {}),
      alertsEnabled: input.alertsEnabled ?? true,
      createdAt: now,
      updatedAt: now,
      matchedIssueIds: [],
    };
    this.cache.searches.push(search);
    await this.persist();
    return search;
  }

  async update(installId: string, id: string, patch: Partial<Pick<SavedSearch, "name" | "query" | "scope" | "stateCode" | "alertsEnabled" | "lastSeenAt">>): Promise<SavedSearch | null> {
    const search = this.cache.searches.find((s) => s.id === id && s.installId === installId);
    if (!search) return null;
    if (patch.name !== undefined) search.name = patch.name.trim() || search.name;
    if (patch.query !== undefined) search.query = patch.query.trim();
    if (patch.scope !== undefined) search.scope = patch.scope;
    if (patch.stateCode !== undefined) {
      if (patch.stateCode) search.stateCode = patch.stateCode;
      else delete search.stateCode;
    }
    if (patch.alertsEnabled !== undefined) search.alertsEnabled = patch.alertsEnabled;
    if (patch.lastSeenAt !== undefined) search.lastSeenAt = patch.lastSeenAt;
    search.updatedAt = new Date().toISOString();
    await this.persist();
    return search;
  }

  async remove(installId: string, id: string): Promise<boolean> {
    const before = this.cache.searches.length;
    this.cache.searches = this.cache.searches.filter((s) => !(s.id === id && s.installId === installId));
    if (this.cache.searches.length === before) return false;
    await this.persist();
    return true;
  }

  /** Mark an issue as already-alerted-for so we don't re-notify. */
  async recordMatch(searchId: string, issueId: string): Promise<void> {
    const search = this.cache.searches.find((s) => s.id === searchId);
    if (!search) return;
    if (!search.matchedIssueIds.includes(issueId)) {
      search.matchedIssueIds.push(issueId);
      // Cap at 200 most recent so the array doesn't grow forever.
      if (search.matchedIssueIds.length > 200) {
        search.matchedIssueIds = search.matchedIssueIds.slice(-200);
      }
      await this.persist();
    }
  }

  /**
   * Run one search against the current issue corpus and return matches.
   * Used by the on-demand "Run now" endpoint AND by the alert worker.
   */
  static evaluate(search: SavedSearch, issues: StoredIssue[]): StoredIssue[] {
    const q = search.query.toLowerCase().trim();
    return issues.filter((issue) => {
      if (search.scope !== "any" && issue.scope !== search.scope) return false;
      if (search.scope === "state" && search.stateCode && issue.stateCode !== search.stateCode) return false;
      if (q.length === 0) return true;
      const haystack = [
        issue.title,
        issue.summary,
        issue.jurisdiction,
        issue.official?.name ?? "",
        ...(issue.topics ?? []),
      ].join(" ").toLowerCase();
      return haystack.includes(q);
    });
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, JSON.stringify(this.cache, null, 2));
  }
}
