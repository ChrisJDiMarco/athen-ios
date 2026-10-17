import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import { rateLimit } from "../lib/rateLimiter.js";
import { dailyQuota } from "../lib/dailyQuota.js";
import { withNeutralityGuardrail } from "../lib/neutralityGuardrail.js";
import type { IssueStore, StoredIssue } from "../services/issueStore.js";

const MIN = 60_000;
const limiter = rateLimit({ name: "url:analyze", max: 30, windowMs: 5 * MIN });
const quota = dailyQuota({ name: "url-analyze", max: 25 });

const Body = z.object({
  url: z.string().url().max(2000),
});

interface RelatedIssue {
  id: string;
  title: string;
  scope: string;
}

interface AnalyzeResponse {
  url: string;
  fetchedAt: string;
  pageTitle: string | null;
  summary: string;
  relatedIssues: RelatedIssue[];
  suggestedActions: string[];
}

export interface UrlAnalyzeDeps {
  issues: IssueStore;
}

/**
 * Paste-any-URL endpoint. Fetches the page via Firecrawl, hands the
 * extracted text to Claude alongside the user's issue store, and returns
 * a tight "what is this + what can I do" payload. Powers the iOS
 * "Athen, what is this?" flow that lives in the Assistant tab.
 */
export function urlAnalyzeRoute(deps: UrlAnalyzeDeps): FastifyPluginAsync {
  const anthropic = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  return async function (fastify: FastifyInstance) {
    fastify.post("/v1/url/analyze", async (request, reply) => {
      if (!limiter(request, reply)) return;
      if (!quota(request, reply)) return;
      const parsed = Body.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: { code: "invalid_body", message: parsed.error.message },
        });
      }
      const { url } = parsed.data;

      let pageTitle: string | null = null;
      let bodyText = "";
      try {
        const fetched = await scrapeUrl(url);
        pageTitle = fetched.title;
        bodyText = fetched.text;
      } catch (err) {
        return reply.code(502).send({
          error: { code: "fetch_failed", message: err instanceof Error ? err.message : "Couldn't fetch URL." },
        });
      }
      if (bodyText.trim().length === 0) {
        return reply.code(422).send({
          error: { code: "empty_page", message: "Page had no readable text." },
        });
      }

      // Build a compact corpus of issue titles for Claude to match against.
      const corpus = deps.issues
        .all()
        .slice(0, 200)
        .map((i) => `${i.id} | ${i.scope} | ${i.title}`)
        .join("\n");

      const SYSTEM = `You analyze a URL the user pasted into a civic-engagement app called Athen.

Return PURE JSON with this exact shape:
{
  "summary": "2-3 sentence plain-English summary of what the page is about and why it matters civically",
  "relatedIssueIds": ["uuid-1", "uuid-2"],
  "suggestedActions": ["one short imperative", "another", "a third"]
}

Hard rules:
- "summary" must be your own words, not a quote. 2-3 sentences.
- "relatedIssueIds" must come from the ISSUE CATALOG below — only include IDs that genuinely relate. Empty array if none match.
- "suggestedActions" should be 2-4 concrete things the user could do today (e.g. "Email Sen. Casey", "Sign the petition", "Attend Tuesday's hearing"). Each one short.
- No prose outside the JSON. No markdown. No code fence.`;

      const userPrompt = [
        `URL: ${url}`,
        pageTitle ? `PAGE TITLE: ${pageTitle}` : "",
        "",
        "PAGE TEXT (truncated):",
        bodyText.slice(0, 12_000),
        "",
        "ISSUE CATALOG (id | scope | title):",
        corpus,
      ].filter(Boolean).join("\n");

      let parsedOut: ParsedAnalysis;
      try {
        const response = await anthropic.messages.create({
          model: config.ANTHROPIC_MODEL,
          max_tokens: 1200,
          system: withNeutralityGuardrail(SYSTEM),
          messages: [{ role: "user", content: userPrompt }],
        });
        const block = response.content.find((b) => b.type === "text");
        const text = block && block.type === "text" ? block.text.trim() : "";
        parsedOut = safeJsonParse(text);
      } catch (err) {
        return reply.code(502).send({
          error: { code: "claude_failed", message: err instanceof Error ? err.message : "Claude analysis failed." },
        });
      }

      const related: RelatedIssue[] = (parsedOut.relatedIssueIds ?? [])
        .map((id) => deps.issues.findById(id))
        .filter((i): i is StoredIssue => i !== undefined)
        .slice(0, 5)
        .map((i) => ({ id: i.id, title: i.title, scope: i.scope }));

      const out: AnalyzeResponse = {
        url,
        fetchedAt: new Date().toISOString(),
        pageTitle,
        summary: (parsedOut.summary ?? "").trim() || "Couldn't summarize this page.",
        relatedIssues: related,
        suggestedActions: (parsedOut.suggestedActions ?? []).slice(0, 4).map((s) => s.trim()).filter(Boolean),
      };
      return reply.send(out);
    });
  };
}

async function scrapeUrl(url: string): Promise<{ title: string | null; text: string }> {
  if (!config.FIRECRAWL_API_KEY) {
    // Firecrawl-less fallback — direct fetch with a basic HTML strip.
    const res = await fetch(url, {
      headers: { "User-Agent": "AthenURLAnalyzer/1.0 (+https://athen.app)" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) throw new Error(`Page returned ${res.status}`);
    const html = await res.text();
    const titleMatch = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    return {
      title: titleMatch ? decodeEntities(stripTags(titleMatch[1] ?? "")).trim() : null,
      text: stripTags(html).slice(0, 30_000),
    };
  }
  const res = await fetch("https://api.firecrawl.dev/v1/scrape", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.FIRECRAWL_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      url,
      formats: ["markdown"],
      onlyMainContent: true,
    }),
    signal: AbortSignal.timeout(25_000),
  });
  if (!res.ok) {
    const t = await res.text().catch(() => "");
    throw new Error(`Firecrawl ${res.status}: ${t.slice(0, 200)}`);
  }
  const payload = (await res.json()) as {
    data?: { markdown?: string; metadata?: { title?: string } };
  };
  return {
    title: payload.data?.metadata?.title ?? null,
    text: payload.data?.markdown?.slice(0, 30_000) ?? "",
  };
}

interface ParsedAnalysis {
  summary?: string;
  relatedIssueIds?: string[];
  suggestedActions?: string[];
}

function safeJsonParse(text: string): ParsedAnalysis {
  // Tolerate a leading "```json" fence or trailing prose, just in case.
  const cleaned = text
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```$/, "")
    .trim();
  try {
    const parsed = JSON.parse(cleaned) as Record<string, unknown>;
    const out: ParsedAnalysis = {};
    if (typeof parsed.summary === "string") out.summary = parsed.summary;
    if (Array.isArray(parsed.relatedIssueIds)) {
      out.relatedIssueIds = parsed.relatedIssueIds.filter((x): x is string => typeof x === "string");
    }
    if (Array.isArray(parsed.suggestedActions)) {
      out.suggestedActions = parsed.suggestedActions.filter((x): x is string => typeof x === "string");
    }
    return out;
  } catch {
    return {};
  }
}

function stripTags(s: string): string {
  return s
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function decodeEntities(s: string): string {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'");
}
