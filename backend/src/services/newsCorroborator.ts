import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import sourcesFile from "../data/news-sources.json" with { type: "json" };

const FIRECRAWL_SEARCH = "https://api.firecrawl.dev/v1/search";

interface NewsSources {
  philly: string[];
  pennsylvania: string[];
  federal: string[];
  civic_specialty: string[];
}

const sources = sourcesFile as unknown as NewsSources;

export type IssueScopeForNews = "federal" | "state" | "local-philly" | "unknown";

export interface BackgroundCitation {
  source: string;
  title: string;
  url: string;
  snippet: string;
}

export interface BackgroundReading {
  summary: string;
  citations: BackgroundCitation[];
  generatedAt: string;
}

interface FirecrawlSearchResult {
  url: string;
  title?: string;
  description?: string;
  markdown?: string;
}

interface FirecrawlSearchResponse {
  data?: FirecrawlSearchResult[];
  success?: boolean;
}

export interface NewsCorroborator {
  background(args: {
    issueTitle: string;
    jurisdiction: string;
    scope: IssueScopeForNews;
    stateCode?: string;
  }): Promise<BackgroundReading | null>;
}

export class FirecrawlNewsCorroborator implements NewsCorroborator {
  private readonly client: Anthropic;

  constructor(client?: Anthropic) {
    this.client = client ?? new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  }

  async background(args: {
    issueTitle: string;
    jurisdiction: string;
    scope: IssueScopeForNews;
    stateCode?: string;
  }): Promise<BackgroundReading | null> {
    if (!config.FIRECRAWL_API_KEY) {
      return null;
    }

    const allowlist = this.allowlistFor(args.scope, args.stateCode);
    const query = this.buildQuery(args.issueTitle, args.jurisdiction);

    const results = await this.firecrawlSearch(query, allowlist);
    if (results.length === 0) return null;

    const top = results.slice(0, 4);
    const summary = await this.summarize(args.issueTitle, top);

    return {
      summary,
      citations: top.map((r) => ({
        source: hostFromURL(r.url),
        title: r.title ?? r.url,
        url: r.url,
        snippet: (r.description ?? r.markdown ?? "").slice(0, 220).trim(),
      })),
      generatedAt: new Date().toISOString(),
    };
  }

  private allowlistFor(scope: IssueScopeForNews, stateCode?: string): string[] {
    const list = new Set<string>(sources.federal);
    if (scope === "local-philly") {
      sources.philly.forEach((d) => list.add(d));
      sources.pennsylvania.forEach((d) => list.add(d));
    } else if (scope === "state" && stateCode === "PA") {
      sources.pennsylvania.forEach((d) => list.add(d));
    }
    sources.civic_specialty.forEach((d) => list.add(d));
    return Array.from(list);
  }

  private buildQuery(title: string, jurisdiction: string): string {
    return `${title} ${jurisdiction}`.trim();
  }

  private async firecrawlSearch(query: string, allowlist: string[]): Promise<FirecrawlSearchResult[]> {
    const body = {
      query,
      limit: 8,
      sources: ["web"],
      origin: "civic-os",
      scrapeOptions: { formats: ["markdown"] },
    };

    const res = await fetch(FIRECRAWL_SEARCH, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${config.FIRECRAWL_API_KEY}`,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });

    if (!res.ok) return [];
    const json = (await res.json()) as FirecrawlSearchResponse;
    const all = json.data ?? [];

    return all.filter((r) => {
      try {
        const host = new URL(r.url).host.replace(/^www\./, "");
        return allowlist.some((domain) => host === domain || host.endsWith(`.${domain}`));
      } catch {
        return false;
      }
    });
  }

  private async summarize(issueTitle: string, results: FirecrawlSearchResult[]): Promise<string> {
    const userPrompt = [
      `Issue: "${issueTitle}"`,
      "",
      "Reporters' coverage:",
      ...results.map((r, i) => `[${i + 1}] ${r.title ?? r.url} (${hostFromURL(r.url)})\n${(r.description ?? r.markdown ?? "").slice(0, 600)}`),
      "",
      "Write a 2–3 sentence background reading paragraph. Cite which numbered source supports each claim like [1]. No editorializing. If reporters disagree, say so.",
    ].join("\n");

    const response = await this.client.messages.create({
      model: config.ANTHROPIC_MODEL,
      max_tokens: 300,
      system: "You compress local journalism into trustworthy background for civic action. Plain English. No invented facts. Always cite by number.",
      messages: [{ role: "user", content: userPrompt }],
    });

    const textBlock = response.content.find((b) => b.type === "text");
    return textBlock && textBlock.type === "text" ? textBlock.text.trim() : "";
  }
}

function hostFromURL(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, "");
  } catch {
    return url;
  }
}
