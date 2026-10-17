import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import Anthropic from "@anthropic-ai/sdk";
import { rateLimit } from "../lib/rateLimiter.js";
import { config } from "../config.js";
import { withNeutralityGuardrail } from "../lib/neutralityGuardrail.js";

const MIN = 60_000;
const newsLimiter = rateLimit({ name: "news", max: 60, windowMs: 5 * MIN });

const QuerySchema = z.object({
  city: z.string().min(1).max(80).optional(),
  state: z.string().min(2).max(80).optional(),
  fresh: z.string().optional(),
  /** When set, response includes a Claude-generated 2-3 sentence summary
   *  of the day's headlines. Cached alongside the items. */
  summary: z.string().optional(),
});

interface CacheEntry {
  fetchedAt: number;
  items: NewsItem[];
  /** Claude-generated summary, computed lazily on first ?summary=1 hit. */
  summary?: string;
}

interface NewsItem {
  id: string;
  title: string;
  link: string;
  source: string;
  publishedISO: string | null;
  snippet: string | null;
}

const CACHE_TTL_MS = 30 * MIN;
const cache: Map<string, CacheEntry> = new Map();
const anthropic = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });

/// Free-source news feed for the Home → News mode. Pulls Google News RSS
/// scoped to the user's locality. No API key, no payment — Google News RSS
/// is a public endpoint. Cached server-side for 30 min to avoid hammering
/// Google with one request per opener.
export function newsRoute(): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/news", async (request, reply) => {
      if (!newsLimiter(request, reply)) return;
      const parsed = QuerySchema.safeParse(request.query ?? {});
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_request", message: parsed.error.message },
        });
      }
      const { city, state, fresh, summary } = parsed.data;
      const wantsSummary = summary === "1" || summary === "true";
      const key = `${(city ?? "").toLowerCase()}|${(state ?? "").toLowerCase()}`;
      const now = Date.now();

      const respondWith = async (entry: CacheEntry, cached: boolean, stale = false) => {
        const out: Record<string, unknown> = { items: entry.items, cached };
        if (stale) out.stale = true;
        if (wantsSummary) {
          if (!entry.summary) {
            entry.summary = await buildSummary({ items: entry.items, city, state });
          }
          out.summary = entry.summary;
        }
        return reply.send(out);
      };

      if (!fresh) {
        const entry = cache.get(key);
        if (entry && now - entry.fetchedAt < CACHE_TTL_MS) {
          return respondWith(entry, true);
        }
      }

      try {
        const items = await fetchGoogleNewsRSS({ city, state });
        const entry: CacheEntry = { fetchedAt: now, items };
        cache.set(key, entry);
        return respondWith(entry, false);
      } catch (err) {
        request.log.error({ err }, "news fetch failed");
        const entry = cache.get(key);
        if (entry) return respondWith(entry, true, true);
        return reply.code(502).send({
          error: {
            code: "news_unreachable",
            message: err instanceof Error ? err.message : "News source unreachable.",
          },
        });
      }
    });
  };
}

/// Quick-glance 2-3 sentence summary of today's headlines. Caps the prompt
/// at the top 10 items + their snippets so we stay tight on tokens.
/// Returns "" on any failure so the caller can hide the card gracefully.
async function buildSummary(args: {
  items: NewsItem[];
  city?: string | undefined;
  state?: string | undefined;
}): Promise<string> {
  if (args.items.length === 0) return "";
  const topItems = args.items.slice(0, 10);
  const location = args.city
    ? `${args.city}${args.state ? `, ${args.state}` : ""}`
    : (args.state ?? "your area");
  const digest = topItems
    .map((it, i) => `${i + 1}. ${it.title}${it.snippet ? ` — ${it.snippet.slice(0, 160)}` : ""}`)
    .join("\n");
  const SYSTEM = `You write a 2-3 sentence "quick glance" of today's local news for an Athen user. No bullets, no lists, no preambles like "Here's a summary". Write as one tight paragraph in plain English. Surface the most consequential story first. Use natural transitions ("Meanwhile,", "Also,"). Do not invent facts not in the headlines below.`;
  const userMsg = `Headlines from around ${location}:\n\n${digest}\n\nWrite the quick glance now (2-3 sentences, plain prose).`;
  try {
    const response = await anthropic.messages.create({
      model: config.ANTHROPIC_MODEL,
      max_tokens: 250,
      system: withNeutralityGuardrail(SYSTEM),
      messages: [{ role: "user", content: userMsg }],
    });
    const block = response.content.find((b) => b.type === "text");
    return (block && block.type === "text" ? block.text : "").trim();
  } catch {
    return "";
  }
}

async function fetchGoogleNewsRSS(args: { city?: string | undefined; state?: string | undefined }): Promise<NewsItem[]> {
  // Build the query: prioritize city, then state, then general civic terms.
  const queryParts: string[] = [];
  if (args.city) queryParts.push(`"${args.city}"`);
  if (args.state && args.state !== args.city) queryParts.push(args.state);
  if (queryParts.length === 0) queryParts.push("local government");
  // Bias toward civic / government coverage.
  queryParts.push("(council OR mayor OR legislature OR governor OR bill OR ordinance)");
  const q = encodeURIComponent(queryParts.join(" "));

  const url = `https://news.google.com/rss/search?q=${q}&hl=en-US&gl=US&ceid=US:en`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const resp = await fetch(url, {
      signal: controller.signal,
      headers: { "User-Agent": "AthenNewsBot/1.0 (+https://athen.app)" },
    });
    if (!resp.ok) throw new Error(`Google News responded ${resp.status}`);
    const xml = await resp.text();
    return parseRSS(xml).slice(0, 20);
  } finally {
    clearTimeout(timeout);
  }
}

/// Tiny purpose-built RSS parser. We only need title / link / pubDate /
/// source / description per item — no schema validation, no XML lib.
function parseRSS(xml: string): NewsItem[] {
  const items: NewsItem[] = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/g;
  let match: RegExpExecArray | null;
  let idx = 0;
  while ((match = itemRegex.exec(xml)) !== null) {
    const body = match[1] ?? "";
    const title = extractTag(body, "title") ?? "";
    const link = extractTag(body, "link") ?? "";
    const pubDate = extractTag(body, "pubDate") ?? "";
    const description = extractTag(body, "description") ?? "";
    const sourceTag = body.match(/<source[^>]*>([\s\S]*?)<\/source>/);
    const source = sourceTag ? unescapeXml(sourceTag[1] ?? "") : extractDomainFromLink(link);
    const publishedISO = pubDate ? toISO(pubDate) : null;
    const snippet = stripHtml(description);
    if (title && link) {
      items.push({
        id: `g-news-${idx}-${link}`,
        title: unescapeXml(title),
        link,
        source: unescapeXml(source ?? extractDomainFromLink(link) ?? "Google News"),
        publishedISO,
        snippet: snippet || null,
      });
    }
    idx += 1;
  }
  return items;
}

function extractTag(body: string, tag: string): string | null {
  const m = body.match(new RegExp(`<${tag}>([\\s\\S]*?)<\\/${tag}>`, "i"));
  if (!m) return null;
  let value = m[1] ?? "";
  // Strip CDATA wrapper if present.
  value = value.replace(/^<!\[CDATA\[/, "").replace(/\]\]>$/, "");
  return value.trim();
}

function unescapeXml(s: string): string {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'");
}

function stripHtml(s: string): string {
  return unescapeXml(s.replace(/<[^>]+>/g, "")).trim();
}

function extractDomainFromLink(link: string): string {
  try {
    return new URL(link).hostname.replace(/^www\./, "");
  } catch {
    return "news";
  }
}

function toISO(rfc: string): string | null {
  const d = new Date(rfc);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
