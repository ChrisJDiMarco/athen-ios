import { config } from "../config.js";
import { CivicError } from "../lib/errors.js";
import type { CivicSource } from "./sourceRegistry.js";
import { hostFromURL } from "./sourceRegistry.js";

const FIRECRAWL_SEARCH = "https://api.firecrawl.dev/v1/search";

interface FirecrawlSearchResult {
  url: string;
  title?: string;
  description?: string;
}

interface FirecrawlSearchResponse {
  data?: FirecrawlSearchResult[];
  success?: boolean;
}

export interface DiscoveredSourceURL {
  url: string;
  title: string;
  snippet: string;
  host: string;
}

export class FirecrawlSourceDiscovery {
  async discover(args: {
    source: CivicSource;
    query?: string;
    limit?: number;
  }): Promise<DiscoveredSourceURL[]> {
    if (!config.FIRECRAWL_API_KEY) {
      throw new CivicError(
        "firecrawl_unavailable",
        "FIRECRAWL_API_KEY is not configured; cannot discover source URLs.",
        503,
      );
    }

    const limit = Math.min(Math.max(args.limit ?? 8, 1), 20);
    const query = this.buildQuery(args.source, args.query);
    const res = await fetch(FIRECRAWL_SEARCH, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${config.FIRECRAWL_API_KEY}`,
      },
      body: JSON.stringify({
        query,
        limit,
        sources: ["web"],
        origin: "civic-os-source-discovery",
      }),
      signal: AbortSignal.timeout(20_000),
    });

    if (!res.ok) {
      throw new CivicError("source_discovery_failed", `Firecrawl returned ${res.status}.`, 502);
    }

    const json = (await res.json()) as FirecrawlSearchResponse;
    const seen = new Set<string>();
    const out: DiscoveredSourceURL[] = [];

    for (const result of json.data ?? []) {
      const host = hostFromURL(result.url);
      if (!host || !this.isAllowedHost(host, args.source.allowedHosts)) continue;
      const key = canonicalURL(result.url);
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({
        url: result.url,
        title: result.title ?? result.url,
        snippet: result.description ?? "",
        host,
      });
    }

    return out.slice(0, limit);
  }

  private buildQuery(source: CivicSource, query?: string): string {
    const base = query?.trim() || source.defaultQueries?.join(" OR ") || "agenda hearing vote public comment";
    const siteHints = source.allowedHosts.slice(0, 3).map((host) => `site:${host}`).join(" OR ");
    return siteHints ? `${base} ${siteHints}` : base;
  }

  private isAllowedHost(host: string, allowedHosts: string[]): boolean {
    return allowedHosts.some((allowed) => host === allowed || host.endsWith(`.${allowed}`));
  }
}

function canonicalURL(url: string): string {
  try {
    const parsed = new URL(url);
    parsed.hash = "";
    parsed.searchParams.sort();
    return parsed.toString().replace(/\/$/, "");
  } catch {
    return url.trim();
  }
}
