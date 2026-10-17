import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { StoredIssue, StoredScope } from "./issueStore.js";
import { hostFromURL } from "./sourceRegistry.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface EvidenceSnippet {
  label: string;
  text: string;
  url?: string;
}

export interface EvidenceRecord {
  id: string;
  issueID?: string;
  sourceFingerprint?: string;
  sourceRecordID?: string;
  sourceName: string;
  sourceURL: string;
  sourceHost: string;
  sourceType: string;
  jurisdiction: string;
  scope: StoredScope;
  title: string;
  summary: string;
  snippets: EvidenceSnippet[];
  trustScore?: number;
  extractionConfidence?: number;
  capturedAtISO: string;
  publishedAtISO?: string;
  updatedAtISO?: string;
  tags: string[];
  rawRecord?: Record<string, unknown>;
}

interface EvidenceFile {
  version: 1;
  records: EvidenceRecord[];
}

export interface EvidenceVaultStats {
  total: number;
  linkedIssues: number;
  sourceHosts: number;
  lastCapturedAt: string | null;
}

export type EvidenceRecordInput = Omit<EvidenceRecord, "id" | "capturedAtISO"> & {
  id?: string;
  capturedAtISO?: string;
};

export class EvidenceVault {
  private constructor(private readonly filePath: string, private cache: EvidenceFile) {}

  static async load(filePath?: string): Promise<EvidenceVault> {
    const path = filePath ?? resolve(__dirname, "..", "..", "data", "evidence.json");
    try {
      const text = await readFile(path, "utf8");
      const parsed = JSON.parse(text) as EvidenceFile;
      if (parsed.version !== 1 || !Array.isArray(parsed.records)) {
        return new EvidenceVault(path, { version: 1, records: [] });
      }
      return new EvidenceVault(path, parsed);
    } catch {
      return new EvidenceVault(path, { version: 1, records: [] });
    }
  }

  all(): EvidenceRecord[] {
    return this.cache.records.slice().sort((a, b) => Date.parse(b.capturedAtISO) - Date.parse(a.capturedAtISO));
  }

  stats(): EvidenceVaultStats {
    const linkedIssues = new Set(this.cache.records.flatMap((record) => (record.issueID ? [record.issueID] : []))).size;
    const sourceHosts = new Set(this.cache.records.map((record) => record.sourceHost).filter(Boolean)).size;
    let lastCapturedAt: string | null = null;
    for (const record of this.cache.records) {
      if (!lastCapturedAt || Date.parse(record.capturedAtISO) > Date.parse(lastCapturedAt)) {
        lastCapturedAt = record.capturedAtISO;
      }
    }
    return { total: this.cache.records.length, linkedIssues, sourceHosts, lastCapturedAt };
  }

  byIssue(issueID: string): EvidenceRecord[] {
    return this.all().filter((record) => record.issueID === issueID);
  }

  bySourceFingerprint(fingerprint: string): EvidenceRecord[] {
    return this.all().filter((record) => record.sourceFingerprint === fingerprint);
  }

  async seedFromIssues(issues: StoredIssue[]): Promise<void> {
    let changed = false;
    for (const issue of issues) {
      const record = evidenceFromIssue(issue);
      if (!this.cache.records.some((existing) => existing.id === record.id)) {
        this.cache.records.push(record);
        changed = true;
      }
    }
    if (changed) await this.persist();
  }

  async upsertFromIssue(issue: StoredIssue): Promise<EvidenceRecord> {
    return this.upsert(evidenceFromIssue(issue));
  }

  async upsert(input: EvidenceRecordInput): Promise<EvidenceRecord> {
    const now = new Date().toISOString();
    const record: EvidenceRecord = {
      ...input,
      id: input.id ?? fingerprintForEvidence(input),
      capturedAtISO: input.capturedAtISO ?? now,
    };
    const idx = this.cache.records.findIndex((existing) => existing.id === record.id);
    if (idx >= 0) {
      this.cache.records[idx] = { ...this.cache.records[idx], ...record, capturedAtISO: now };
    } else {
      this.cache.records.push(record);
    }
    await this.persist();
    return record;
  }

  async upsertMany(inputs: EvidenceRecordInput[]): Promise<EvidenceRecord[]> {
    const records: EvidenceRecord[] = [];
    let changed = false;
    const now = new Date().toISOString();
    for (const input of inputs) {
      const record: EvidenceRecord = {
        ...input,
        id: input.id ?? fingerprintForEvidence(input),
        capturedAtISO: input.capturedAtISO ?? now,
      };
      const idx = this.cache.records.findIndex((existing) => existing.id === record.id);
      if (idx >= 0) {
        this.cache.records[idx] = { ...this.cache.records[idx], ...record, capturedAtISO: now };
        records.push(this.cache.records[idx]);
      } else {
        this.cache.records.push(record);
        records.push(record);
      }
      changed = true;
    }
    if (changed) await this.persist();
    return records;
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, JSON.stringify(this.cache, null, 2), "utf8");
  }
}

export function evidenceFromIssue(issue: StoredIssue): EvidenceRecord {
  const snippets: EvidenceSnippet[] = [];
  for (const citation of issue.citations ?? []) {
    const snippet: EvidenceSnippet = {
      label: citation.label,
      text: citation.quote,
    };
    if (citation.url) snippet.url = citation.url;
    snippets.push(snippet);
  }
  for (const fact of issue.facts.slice(0, 3)) {
    snippets.push({ label: fact.label, text: fact.value });
  }

  const sourceHost = issue.sourceHost ?? hostFromURL(issue.sourceURL);
  const record: EvidenceRecord = {
    id: createHash("sha1").update(`issue:${issue.id}:${issue.sourceFingerprint}`).digest("hex"),
    issueID: issue.id,
    sourceFingerprint: issue.sourceFingerprint,
    sourceName: issue.sourceName,
    sourceURL: issue.sourceURL,
    sourceHost,
    sourceType: issue.sourceType ?? "government-source",
    jurisdiction: issue.jurisdiction,
    scope: issue.scope,
    title: issue.title,
    summary: issue.summary,
    snippets,
    capturedAtISO: issue.ingestedAt ?? issue.updatedAt,
    tags: issue.topics,
  };
  if (issue.sourceRecordID) record.sourceRecordID = issue.sourceRecordID;
  if (typeof issue.trustScore === "number") record.trustScore = issue.trustScore;
  if (typeof issue.extractionConfidence === "number") record.extractionConfidence = issue.extractionConfidence;
  if (issue.voteDateISO) record.publishedAtISO = issue.voteDateISO;
  record.updatedAtISO = issue.updatedAt;
  return record;
}

function fingerprintForEvidence(input: EvidenceRecordInput): string {
  const key = [
    input.sourceName,
    input.sourceURL,
    input.sourceRecordID ?? "",
    input.title,
    input.updatedAtISO ?? input.publishedAtISO ?? "",
  ].join("|");
  return createHash("sha1").update(`evidence:${key}`).digest("hex");
}
