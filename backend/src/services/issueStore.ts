import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));

export type StoredScope = "federal" | "state" | "local-philly" | "unknown";

export interface StoredFact {
  label: string;
  value: string;
  systemImage?: string;
}

export interface StoredOfficial {
  name: string;
  title: string;
  district: string;
  contactTarget: string;
}

export interface StoredFilingRoute {
  verificationStep: string;
  routingStep: string;
  destinationStep: string;
  deliveryWindow: string;
}

export interface StoredCitation {
  label: string;
  quote: string;
  url?: string;
}

export interface StoredIssue {
  id: string;
  sourceFingerprint: string;
  title: string;
  category: string;
  jurisdiction: string;
  scope: StoredScope;
  stateCode?: string;
  zipCode?: string;
  summary: string;
  impactLevel: "urgent" | "material" | "watch";
  voteDateISO: string;
  sourceName: string;
  sourceDetail: string;
  sourceURL: string;
  sourceHost?: string;
  sourceType?: string;
  sourceRecordID?: string;
  trustScore?: number;
  extractionConfidence?: number;
  citations?: StoredCitation[];
  ingestedAt?: string;
  topics: string[];
  facts: StoredFact[];
  official: StoredOfficial;
  filingRoute: StoredFilingRoute;
  createdAt: string;
  updatedAt: string;
}

interface StoreFile {
  version: 1;
  issues: StoredIssue[];
}

export interface IssueStoreStats {
  total: number;
  byScope: Record<StoredScope, number>;
  byImpact: Record<StoredIssue["impactLevel"], number>;
  averageTrustScore: number | null;
  lastUpdatedAt: string | null;
}

export class IssueStore {
  private constructor(private readonly filePath: string, private cache: StoreFile) {}

  static async load(filePath?: string): Promise<IssueStore> {
    const path = filePath ?? resolve(__dirname, "..", "..", "data", "issues.json");
    try {
      const text = await readFile(path, "utf8");
      const parsed = JSON.parse(text) as StoreFile;
      if (parsed.version !== 1 || !Array.isArray(parsed.issues)) {
        return new IssueStore(path, { version: 1, issues: [] });
      }
      return new IssueStore(path, parsed);
    } catch {
      return new IssueStore(path, { version: 1, issues: [] });
    }
  }

  all(): StoredIssue[] {
    return this.cache.issues.slice();
  }

  /**
   * Lookup by ID — case-insensitive. iOS UUIDs are uppercase by default
   * and Node's crypto.randomUUID() is lowercase, so a strict ===
   * comparison silently fails for every iOS-originated request.
   */
  findById(issueId: string): StoredIssue | undefined {
    const normalized = issueId.toLowerCase();
    return this.cache.issues.find((i) => i.id.toLowerCase() === normalized);
  }

  stats(): IssueStoreStats {
    const byScope: Record<StoredScope, number> = {
      federal: 0,
      state: 0,
      "local-philly": 0,
      unknown: 0,
    };
    const byImpact: Record<StoredIssue["impactLevel"], number> = {
      urgent: 0,
      material: 0,
      watch: 0,
    };

    let trustSum = 0;
    let trustCount = 0;
    let lastUpdatedAt: string | null = null;

    for (const issue of this.cache.issues) {
      byScope[issue.scope] += 1;
      byImpact[issue.impactLevel] += 1;
      if (typeof issue.trustScore === "number") {
        trustSum += issue.trustScore;
        trustCount += 1;
      }
      if (!lastUpdatedAt || Date.parse(issue.updatedAt) > Date.parse(lastUpdatedAt)) {
        lastUpdatedAt = issue.updatedAt;
      }
    }

    return {
      total: this.cache.issues.length,
      byScope,
      byImpact,
      averageTrustScore: trustCount > 0 ? Math.round(trustSum / trustCount) : null,
      lastUpdatedAt,
    };
  }

  byFingerprint(fingerprint: string): StoredIssue | undefined {
    return this.cache.issues.find((i) => i.sourceFingerprint === fingerprint);
  }

  filter(args: { stateCode?: string; scope?: StoredScope }): StoredIssue[] {
    return this.cache.issues.filter((issue) => {
      if (args.scope && issue.scope !== args.scope) return false;
      if (args.stateCode && issue.stateCode && issue.stateCode !== args.stateCode) return false;
      return true;
    });
  }

  /**
   * Insert if new, or overwrite if an issue with the same fingerprint exists.
   * Returns the stored row.
   */
  async upsert(input: Omit<StoredIssue, "id" | "createdAt" | "updatedAt">): Promise<StoredIssue> {
    const now = new Date().toISOString();
    const existing = this.byFingerprint(input.sourceFingerprint);
    if (existing) {
      Object.assign(existing, input, { updatedAt: now });
      await this.persist();
      return existing;
    }

    const stored: StoredIssue = {
      ...input,
      id: randomUUID(),
      createdAt: now,
      updatedAt: now,
    };
    this.cache.issues.push(stored);
    await this.persist();
    return stored;
  }

  async clear(): Promise<void> {
    this.cache.issues = [];
    await this.persist();
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, JSON.stringify(this.cache, null, 2), "utf8");
  }
}
