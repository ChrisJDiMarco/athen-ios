/// Free web search via DuckDuckGo's HTML "lite" page. No API key required.
///
/// Used by the chat assistant's `web_search` tool — Claude decides when to
/// call it (anything time-sensitive, recent events, or facts beyond its
/// training cutoff). Results are parsed from the no-JS HTML page and capped
/// to 8 hits so we don't blow the context window.
///
/// Falls back to a structured error result (not a thrown exception) so the
/// model can still respond to the user gracefully if search is down.

export interface WebSearchResult {
  title: string;
  url: string;
  snippet: string;
}

export interface WebSearchResponse {
  query: string;
  results: WebSearchResult[];
  fetchedAtISO: string;
  error?: string;
}

const SEARCH_TIMEOUT_MS = 12_000;
const MAX_RESULTS = 8;

export async function webSearch(query: string): Promise<WebSearchResponse> {
  const trimmed = query.trim().slice(0, 240);
  if (trimmed.length === 0) {
    return {
      query: trimmed,
      results: [],
      fetchedAtISO: new Date().toISOString(),
      error: "Empty query",
    };
  }

  const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(trimmed)}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), SEARCH_TIMEOUT_MS);

  try {
    const resp = await fetch(url, {
      signal: controller.signal,
      headers: {
        // DDG blocks the default fetch UA. Spoof a regular browser.
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        "Accept": "text/html,application/xhtml+xml",
      },
    });
    if (!resp.ok) {
      return {
        query: trimmed,
        results: [],
        fetchedAtISO: new Date().toISOString(),
        error: `DuckDuckGo responded ${resp.status}`,
      };
    }
    const html = await resp.text();
    const results = parseDDGHtml(html).slice(0, MAX_RESULTS);
    return {
      query: trimmed,
      results,
      fetchedAtISO: new Date().toISOString(),
    };
  } catch (err) {
    return {
      query: trimmed,
      results: [],
      fetchedAtISO: new Date().toISOString(),
      error: err instanceof Error ? err.message : String(err),
    };
  } finally {
    clearTimeout(timer);
  }
}

/// DDG HTML format (May 2026):
///   <a rel="nofollow" class="result__a" href="https://example.com">Title</a>
///   ... later in the same row ...
///   <a class="result__snippet" href="...">Snippet text</a>
///
/// Strategy: iterate every `result__a` anchor (those are the per-result
/// titles), then scan forward up to ~2KB for the matching `result__snippet`.
/// Loose enough to survive minor DDG markup churn, tight enough to not
/// confuse two adjacent results.
function parseDDGHtml(html: string): WebSearchResult[] {
  const out: WebSearchResult[] = [];
  const seenUrls = new Set<string>();
  const titleRegex = /<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
  let match: RegExpExecArray | null;
  while ((match = titleRegex.exec(html)) !== null) {
    const rawUrl = match[1] ?? "";
    const title = stripHtml(match[2] ?? "");
    const realUrl = extractDDGTarget(rawUrl);
    if (!title || !realUrl || seenUrls.has(realUrl)) continue;
    seenUrls.add(realUrl);

    // Search the next ~2KB for a snippet — keeps us inside this result's row.
    const lookFrom = match.index + match[0].length;
    const lookSlice = html.slice(lookFrom, lookFrom + 2500);
    const snippetMatch =
      lookSlice.match(/<a[^>]*class="result__snippet"[^>]*>([\s\S]*?)<\/a>/) ??
      lookSlice.match(/<div[^>]*class="result__snippet[^"]*"[^>]*>([\s\S]*?)<\/div>/);
    const snippet = stripHtml(snippetMatch?.[1] ?? "");

    out.push({ title, url: realUrl, snippet });
  }
  return out;
}

function extractDDGTarget(url: string): string {
  try {
    // Some links come absolute, others as /l/?uddg=https%3A%2F%2F...
    if (url.startsWith("//")) url = "https:" + url;
    if (url.startsWith("http")) {
      const u = new URL(url);
      const target = u.searchParams.get("uddg");
      return target ?? url;
    }
    if (url.startsWith("/l/")) {
      const u = new URL("https://duckduckgo.com" + url);
      return u.searchParams.get("uddg") ?? url;
    }
    return url;
  } catch {
    return url;
  }
}

function stripHtml(s: string): string {
  return s
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#x27;|&#39;|&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .trim();
}

/// Compact text representation we hand back to Claude when it calls the
/// web_search tool. One result per line keeps tokens cheap.
export function formatForModel(resp: WebSearchResponse): string {
  if (resp.error) {
    return `Search error: ${resp.error}. Tell the user you couldn't reach the web and answer from memory if possible.`;
  }
  if (resp.results.length === 0) {
    return `No results for "${resp.query}". Tell the user you couldn't find anything relevant.`;
  }
  const lines = resp.results.map((r, i) => `[${i + 1}] ${r.title}\n    ${r.url}\n    ${r.snippet}`);
  return `Web search results for "${resp.query}" (fetched ${resp.fetchedAtISO}):\n\n${lines.join("\n\n")}\n\nWhen citing, use [1], [2], etc. and include the URLs the user can click.`;
}
