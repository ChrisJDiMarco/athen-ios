import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));

export type PetitionStatus = "open" | "delivered" | "expired";
export type PetitionVisibility = "public" | "private";

export interface PetitionTarget {
  /** Display name shown to signers ("Sen. Bob Casey"). */
  officialName: string;
  /** Resolved email (when channel = email). */
  email?: string;
  /** Resolved contact form URL (when channel = contact-form-queue). */
  contactFormURL?: string;
  /** Free-text jurisdiction so iOS can group ("Pennsylvania State Senate"). */
  jurisdiction: string;
  /** Delivery channel — defaults to email when an address is known. */
  channel: "email" | "contact-form-queue";
}

export interface StoredSignature {
  id: string;
  /** Stable per-install identifier — used for dedup + outcome attribution. */
  entityId: string;
  name: string;
  zip: string;
  comment?: string;
  signedAtISO: string;
}

export interface StoredPetition {
  id: string;
  title: string;
  /** One-sentence demand. */
  ask: string;
  /** Long-form body (Claude-assisted). */
  body: string;
  creatorEntityId: string;
  creatorDisplayName: string;
  /** Optional linkage to the bill / rule the petition is about. */
  attachedIssueId?: string;
  attachedIssueTitle?: string;
  targets: PetitionTarget[];
  /** Signature count at which the worker auto-delivers. Either threshold OR
   *  deadline (or both) must fire for the petition to ship. */
  threshold?: number;
  /** Auto-deliver date (ISO). */
  deadlineISO?: string;
  status: PetitionStatus;
  createdAtISO: string;
  deliveredAtISO?: string;
  signatures: StoredSignature[];
  visibility: PetitionVisibility;
  /** Set after delivery — receipts mirrored back to the creator. */
  deliveryTrackingId?: string;
  deliveryNote?: string;
}

interface PetitionsCache {
  version: 1;
  petitions: Record<string, StoredPetition>;
}

export class PetitionStore {
  private cache: PetitionsCache;
  private readonly path: string;

  private constructor(cache: PetitionsCache, path: string) {
    this.cache = cache;
    this.path = path;
  }

  static async load(path?: string): Promise<PetitionStore> {
    const resolved = path ?? resolve(__dirname, "..", "..", "data", "petitions.json");
    let cache: PetitionsCache = { version: 1, petitions: {} };
    try {
      const text = await readFile(resolved, "utf8");
      const parsed = JSON.parse(text) as PetitionsCache;
      if (parsed.version === 1 && typeof parsed.petitions === "object") {
        cache = parsed;
      }
    } catch {
      // first run
    }
    return new PetitionStore(cache, resolved);
  }

  all(): StoredPetition[] {
    return Object.values(this.cache.petitions).sort(
      (a, b) => Date.parse(b.createdAtISO) - Date.parse(a.createdAtISO),
    );
  }

  find(id: string): StoredPetition | undefined {
    return this.cache.petitions[id];
  }

  list(filter: { zip?: string; status?: PetitionStatus; topicId?: string; mineEntityId?: string } = {}): StoredPetition[] {
    return this.all().filter((p) => {
      if (filter.status && p.status !== filter.status) return false;
      if (filter.zip) {
        // Surface if any signer is in the zip OR the petition's targets
        // resolve to the same state. Keeps "petitions near me" honest.
        const inZip = p.signatures.some((s) => s.zip.startsWith(filter.zip!.slice(0, 3)));
        const zip3 = filter.zip.slice(0, 3);
        const targetsLocal = p.targets.some((t) => t.jurisdiction.toLowerCase().includes("philadelphia") && zip3.startsWith("191"));
        if (!inZip && !targetsLocal) {
          // Still allow non-local petitions through — the iOS side filters
          // by topic too. Don't be too aggressive about zip-locking.
        }
      }
      if (filter.topicId && p.attachedIssueId !== filter.topicId) return false;
      if (filter.mineEntityId) {
        const isCreator = p.creatorEntityId === filter.mineEntityId;
        const hasSigned = p.signatures.some((s) => s.entityId === filter.mineEntityId);
        if (!isCreator && !hasSigned) return false;
      }
      return true;
    });
  }

  create(input: {
    title: string;
    ask: string;
    body: string;
    creatorEntityId: string;
    creatorDisplayName: string;
    targets: PetitionTarget[];
    attachedIssueId?: string;
    attachedIssueTitle?: string;
    threshold?: number;
    deadlineISO?: string;
    visibility?: PetitionVisibility;
  }): StoredPetition {
    const id = randomUUID();
    const petition: StoredPetition = {
      id,
      title: input.title,
      ask: input.ask,
      body: input.body,
      creatorEntityId: input.creatorEntityId,
      creatorDisplayName: input.creatorDisplayName,
      targets: input.targets,
      status: "open",
      createdAtISO: new Date().toISOString(),
      signatures: [],
      visibility: input.visibility ?? "public",
    };
    if (input.attachedIssueId) petition.attachedIssueId = input.attachedIssueId;
    if (input.attachedIssueTitle) petition.attachedIssueTitle = input.attachedIssueTitle;
    if (input.threshold) petition.threshold = input.threshold;
    if (input.deadlineISO) petition.deadlineISO = input.deadlineISO;
    // The creator auto-signs.
    petition.signatures.push({
      id: randomUUID(),
      entityId: input.creatorEntityId,
      name: input.creatorDisplayName,
      zip: "",
      signedAtISO: petition.createdAtISO,
    });
    this.cache.petitions[id] = petition;
    void this.persist();
    return petition;
  }

  /** Add a signature. Returns null when the entity has already signed. */
  sign(petitionId: string, signature: { entityId: string; name: string; zip: string; comment?: string }): StoredSignature | null {
    const petition = this.cache.petitions[petitionId];
    if (!petition) return null;
    if (petition.status !== "open") return null;
    if (petition.signatures.some((s) => s.entityId === signature.entityId)) return null;
    const stored: StoredSignature = {
      id: randomUUID(),
      entityId: signature.entityId,
      name: signature.name,
      zip: signature.zip,
      signedAtISO: new Date().toISOString(),
    };
    if (signature.comment) stored.comment = signature.comment;
    petition.signatures.push(stored);
    void this.persist();
    return stored;
  }

  unsign(petitionId: string, entityId: string): boolean {
    const petition = this.cache.petitions[petitionId];
    if (!petition) return false;
    const before = petition.signatures.length;
    petition.signatures = petition.signatures.filter((s) => s.entityId !== entityId);
    const changed = petition.signatures.length !== before;
    if (changed) void this.persist();
    return changed;
  }

  markDelivered(petitionId: string, info: { trackingId: string; note: string }): boolean {
    const petition = this.cache.petitions[petitionId];
    if (!petition) return false;
    petition.status = "delivered";
    petition.deliveredAtISO = new Date().toISOString();
    petition.deliveryTrackingId = info.trackingId;
    petition.deliveryNote = info.note;
    void this.persist();
    return true;
  }

  markExpired(petitionId: string): boolean {
    const petition = this.cache.petitions[petitionId];
    if (!petition) return false;
    if (petition.status !== "open") return false;
    petition.status = "expired";
    void this.persist();
    return true;
  }

  /** Petitions ready for the delivery worker: threshold met OR deadline past. */
  readyForDelivery(now: Date = new Date()): StoredPetition[] {
    return this.all().filter((p) => {
      if (p.status !== "open") return false;
      const thresholdHit = p.threshold !== undefined && p.signatures.length >= p.threshold;
      const deadlinePast = p.deadlineISO !== undefined && Date.parse(p.deadlineISO) <= now.getTime();
      return thresholdHit || deadlinePast;
    });
  }

  delete(petitionId: string, byEntityId: string): boolean {
    const petition = this.cache.petitions[petitionId];
    if (!petition) return false;
    if (petition.creatorEntityId !== byEntityId) return false;
    delete this.cache.petitions[petitionId];
    void this.persist();
    return true;
  }

  stats() {
    const list = this.all();
    return {
      total: list.length,
      open: list.filter((p) => p.status === "open").length,
      delivered: list.filter((p) => p.status === "delivered").length,
      expired: list.filter((p) => p.status === "expired").length,
      totalSignatures: list.reduce((sum, p) => sum + p.signatures.length, 0),
    };
  }

  /// Apple data-deletion compliance: scrub every signature this install
  /// made AND drop any petitions this install authored. Returns the count
  /// of items removed for the confirmation response.
  async scrubByEntityId(entityId: string): Promise<number> {
    let removed = 0;
    for (const [pid, petition] of Object.entries(this.cache.petitions)) {
      // Drop authored petitions outright.
      if (petition.creatorEntityId === entityId) {
        delete this.cache.petitions[pid];
        removed += 1;
        continue;
      }
      // Remove this install's signatures from petitions authored by others.
      const before = petition.signatures.length;
      petition.signatures = petition.signatures.filter((s) => s.entityId !== entityId);
      if (petition.signatures.length !== before) {
        removed += before - petition.signatures.length;
      }
    }
    await this.persist();
    return removed;
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
