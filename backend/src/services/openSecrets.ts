import { config } from "../config.js";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Wraps the OpenSecrets API for federal campaign finance + lobbying data.
 * The big value-add: pair an official's voting record (from VoteStore)
 * with their top donor industries, so the iOS scorecard can show "Senator
 * Y voted X on the energy bill; their top contributor industry was oil
 * & gas." Cached aggressively because finance data updates yearly.
 */

const OS_BASE = "https://www.opensecrets.org/api";

export interface IndustryDonor {
  industryCode: string;
  industryName: string;
  total: number;
  cycle: string;
}

export interface OfficialFinanceSummary {
  cid: string;             // OpenSecrets-assigned candidate id
  officialName: string;
  cycle: string;
  cashOnHand?: number;
  total: number;
  totalIndustries: IndustryDonor[];
  source: "opensecrets";
  fetchedAtISO: string;
}

interface FinanceCache {
  version: 1;
  /** Keyed by canonical official name. */
  byOfficial: Record<string, OfficialFinanceSummary>;
}

export class OpenSecretsService {
  private cache: FinanceCache;
  private readonly path: string;

  private constructor(cache: FinanceCache, path: string) {
    this.cache = cache;
    this.path = path;
  }

  static async load(path?: string): Promise<OpenSecretsService> {
    const resolved = path ?? resolve(__dirname, "..", "..", "data", "opensecrets-cache.json");
    let cache: FinanceCache = { version: 1, byOfficial: {} };
    try {
      const raw = await readFile(resolved, "utf8");
      const parsed = JSON.parse(raw) as FinanceCache;
      if (parsed.version === 1 && typeof parsed.byOfficial === "object") cache = parsed;
    } catch {
      // first run
    }
    return new OpenSecretsService(cache, resolved);
  }

  get enabled(): boolean { return !!config.OPENSECRETS_API_KEY; }

  /**
   * Looks up the official by CID (if provided) or by name + state via
   * candSearch first. Returns the cached summary if we already have one for
   * this official + cycle.
   */
  async summaryFor(args: { officialName: string; cid?: string; stateCode?: string; chamber?: "S" | "H" }): Promise<OfficialFinanceSummary | null> {
    if (!this.enabled) return null;
    const key = canonicalKey(args.officialName);
    const cached = this.cache.byOfficial[key];
    // Cycle changes every two years; refresh if the cached entry is older
    // than 14 days.
    if (cached) {
      const ageMs = Date.now() - Date.parse(cached.fetchedAtISO);
      if (ageMs < 14 * 86_400_000) return cached;
    }

    let cid: string | undefined = args.cid;
    if (!cid) {
      const looked = await this.lookupCID(args.officialName, args.stateCode);
      if (!looked) return null;
      cid = looked;
    }
    const summary = await this.fetchIndustries(cid, args.officialName);
    if (summary) {
      this.cache.byOfficial[key] = summary;
      void this.persist();
    }
    return summary;
  }

  private async lookupCID(officialName: string, _stateCode: string | undefined): Promise<string | null> {
    // OpenSecrets doesn't have a clean public search endpoint; their
    // "getLegislators" returns the full federal delegation for a state and
    // we'd then match by name. Many integrations build their own crosswalk.
    //
    // For v1: bail out when no CID is provided. The /v1/rep/finance route
    // accepts an explicit cid so callers can override.
    void officialName;
    return null;
  }

  private async fetchIndustries(cid: string, officialName: string): Promise<OfficialFinanceSummary | null> {
    try {
      const url = new URL(`${OS_BASE}/`);
      url.searchParams.set("method", "candIndustry");
      url.searchParams.set("cid", cid);
      url.searchParams.set("output", "json");
      url.searchParams.set("apikey", config.OPENSECRETS_API_KEY!);
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(20_000),
      });
      if (!res.ok) return null;
      const json = (await res.json()) as OpenSecretsIndustryResponse;
      const block = json.response?.industries;
      if (!block) return null;
      const industries = (block.industry ?? []).map((row) => ({
        industryCode: row["@attributes"]?.industry_code ?? "",
        industryName: row["@attributes"]?.industry_name ?? "Unknown",
        total: Number(row["@attributes"]?.total ?? 0),
        cycle: block["@attributes"]?.cycle ?? "",
      }));
      const totalSum = industries.reduce((a, i) => a + i.total, 0);

      return {
        cid,
        officialName,
        cycle: block["@attributes"]?.cycle ?? "",
        total: totalSum,
        totalIndustries: industries
          .sort((a, b) => b.total - a.total)
          .slice(0, 10),
        source: "opensecrets",
        fetchedAtISO: new Date().toISOString(),
      };
    } catch {
      return null;
    }
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

function canonicalKey(name: string): string {
  return name.toLowerCase().replace(/[.,]/g, "").replace(/\s+/g, " ").trim();
}

interface OpenSecretsIndustryResponse {
  response?: {
    industries?: {
      "@attributes"?: { cycle?: string };
      industry?: Array<{
        "@attributes"?: {
          industry_code?: string;
          industry_name?: string;
          total?: string;
        };
      }>;
    };
  };
}
