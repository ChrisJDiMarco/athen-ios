import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));

export type QueueStatus = "queued" | "submitted" | "failed" | "skipped";

export interface QueuedSubmission {
  id: string;
  bioguide?: string;
  officialName: string;
  contactFormURL?: string;
  constituent: {
    zipCode: string;
    stateCode?: string;
  };
  message: {
    subject: string;
    body: string;
  };
  status: QueueStatus;
  statusReason?: string;
  queuedAt: string;
  updatedAt: string;
  attempts: number;
}

interface QueueFile {
  version: 1;
  submissions: QueuedSubmission[];
}

export class ContactFormQueue {
  private constructor(private readonly filePath: string, private cache: QueueFile) {}

  static async load(filePath?: string): Promise<ContactFormQueue> {
    const path = filePath ?? resolve(__dirname, "..", "..", "data", "federal-queue.json");
    try {
      const text = await readFile(path, "utf8");
      const parsed = JSON.parse(text) as QueueFile;
      if (parsed.version !== 1 || !Array.isArray(parsed.submissions)) {
        return new ContactFormQueue(path, { version: 1, submissions: [] });
      }
      return new ContactFormQueue(path, parsed);
    } catch {
      return new ContactFormQueue(path, { version: 1, submissions: [] });
    }
  }

  async enqueue(input: {
    bioguide?: string;
    officialName: string;
    contactFormURL?: string;
    constituent: { zipCode: string; stateCode?: string };
    message: { subject: string; body: string };
  }): Promise<QueuedSubmission> {
    const now = new Date().toISOString();
    const submission: QueuedSubmission = {
      id: randomUUID(),
      ...(input.bioguide ? { bioguide: input.bioguide } : {}),
      officialName: input.officialName,
      ...(input.contactFormURL ? { contactFormURL: input.contactFormURL } : {}),
      constituent: input.constituent,
      message: input.message,
      status: "queued",
      queuedAt: now,
      updatedAt: now,
      attempts: 0,
    };
    this.cache.submissions.push(submission);
    await this.persist();
    return submission;
  }

  async mark(id: string, status: QueueStatus, reason?: string): Promise<QueuedSubmission | null> {
    const submission = this.cache.submissions.find((s) => s.id === id);
    if (!submission) return null;
    submission.status = status;
    if (reason !== undefined) {
      submission.statusReason = reason;
    } else {
      delete submission.statusReason;
    }
    submission.updatedAt = new Date().toISOString();
    if (status === "submitted" || status === "failed") submission.attempts += 1;
    await this.persist();
    return submission;
  }

  list(args: { status?: QueueStatus; limit?: number } = {}): QueuedSubmission[] {
    let rows = this.cache.submissions.slice();
    if (args.status) rows = rows.filter((s) => s.status === args.status);
    rows.sort((a, b) => Date.parse(b.queuedAt) - Date.parse(a.queuedAt));
    if (args.limit) rows = rows.slice(0, args.limit);
    return rows;
  }

  count(): { total: number; queued: number; submitted: number; failed: number } {
    const all = this.cache.submissions;
    return {
      total: all.length,
      queued: all.filter((s) => s.status === "queued").length,
      submitted: all.filter((s) => s.status === "submitted").length,
      failed: all.filter((s) => s.status === "failed").length,
    };
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, JSON.stringify(this.cache, null, 2), "utf8");
  }
}
