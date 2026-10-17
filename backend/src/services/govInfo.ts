import { config } from "../config.js";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Fetches full text for federal bills + rules from GovInfo (FDsys). The
 * Brief writer calls into this BEFORE running Claude — when full text is
 * available it gets fed into the prompt, so Claude writes from the source
 * instead of just title + latest action. Cached on disk so we don't refetch
 * the same bill on every brief regeneration.
 *
 * Free, requires GOVINFO_API_KEY (already in env config).
 */

const GOVINFO_BASE = "https://api.govinfo.gov";

interface TextCache {
  version: 1;
  /** Keyed by sha1(packageId|granule). */
  texts: Record<string, CachedText>;
}

interface CachedText {
  key: string;
  packageId: string;
  granuleId?: string;
  text: string;
  fetchedAtISO: string;
}

export class GovInfoService {
  private cache: TextCache;
  private readonly path: string;

  private constructor(cache: TextCache, path: string) {
    this.cache = cache;
    this.path = path;
  }

  static async load(path?: string): Promise<GovInfoService> {
    const resolved = path ?? resolve(__dirname, "..", "..", "data", "govinfo-cache.json");
    let cache: TextCache = { version: 1, texts: {} };
    try {
      const raw = await readFile(resolved, "utf8");
      const parsed = JSON.parse(raw) as TextCache;
      if (parsed.version === 1 && typeof parsed.texts === "object") cache = parsed;
    } catch {
      // first run
    }
    return new GovInfoService(cache, resolved);
  }

  get enabled(): boolean { return !!config.GOVINFO_API_KEY; }

  /**
   * Returns the cached or freshly-fetched full text for a federal bill.
   * `billExternalID` is the format we store in Congress.gov-sourced issues:
   * "<congress>-<type>-<number>", e.g. "118-HR-1234".
   */
  async billText(billExternalID: string): Promise<string | null> {
    if (!this.enabled) return null;
    const cacheKey = createHash("sha1").update(`bill:${billExternalID}`).digest("hex").slice(0, 24);
    const cached = this.cache.texts[cacheKey];
    if (cached) return cached.text;

    const parts = billExternalID.split("-");
    if (parts.length !== 3) return null;
    const [congress, billType, number] = parts;
    if (!congress || !billType || !number) return null;

    // GovInfo packages for bills follow the convention:
    //   BILLS-<congress><billType><number><version>
    // We try the "ih" (introduced in House) / "is" (introduced in Senate)
    // versions first since they're always available for active bills.
    const versionGuesses = billType.toLowerCase().startsWith("h") ? ["ih", "rh", "rfs"] : ["is", "rs", "rfh"];
    for (const version of versionGuesses) {
      const packageId = `BILLS-${congress}${billType.toLowerCase()}${number}${version}`;
      const summary = await this.fetchSummary(packageId);
      if (summary) {
        this.cacheText(cacheKey, packageId, undefined, summary);
        return summary;
      }
    }
    return null;
  }

  /**
   * Returns the cached or freshly-fetched full text for a Federal Register
   * document. We use the document number (e.g. "2026-12345") to locate it
   * in the FR package on GovInfo.
   */
  async federalRegisterText(documentNumber: string): Promise<string | null> {
    if (!this.enabled) return null;
    const cacheKey = createHash("sha1").update(`fr:${documentNumber}`).digest("hex").slice(0, 24);
    const cached = this.cache.texts[cacheKey];
    if (cached) return cached.text;

    // Federal Register packages: FR-YYYY-MM-DD; granule per doc.
    // Without the publication date we can't construct the package id
    // cleanly. Skip for now — the Federal Register connector already pulls
    // the abstract, which is usually enough.
    return null;
  }

  private async fetchSummary(packageId: string): Promise<string | null> {
    try {
      const url = new URL(`${GOVINFO_BASE}/packages/${packageId}/summary`);
      url.searchParams.set("api_key", config.GOVINFO_API_KEY!);
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) return null;
      const json = (await res.json()) as { title?: string; otherText?: string; download?: { txtLink?: string } };

      // Fetch the actual text if a text-link is available. Otherwise return
      // the summary fields we got.
      if (json.download?.txtLink) {
        const textRes = await fetch(json.download.txtLink, {
          headers: { "X-Api-Key": config.GOVINFO_API_KEY! },
          signal: AbortSignal.timeout(20_000),
        });
        if (textRes.ok) {
          const text = await textRes.text();
          // Cap at 12k chars so the brief prompt stays tractable.
          return text.length > 12000 ? text.slice(0, 12000) + "\n…[truncated for prompt length]" : text;
        }
      }
      const summary = [json.title, json.otherText].filter(Boolean).join("\n\n");
      return summary || null;
    } catch {
      return null;
    }
  }

  private cacheText(key: string, packageId: string, granuleId: string | undefined, text: string) {
    const entry: CachedText = {
      key,
      packageId,
      text,
      fetchedAtISO: new Date().toISOString(),
    };
    if (granuleId) entry.granuleId = granuleId;
    this.cache.texts[key] = entry;
    void this.persist();
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
