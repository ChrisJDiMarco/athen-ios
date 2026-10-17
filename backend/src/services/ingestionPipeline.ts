import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { config } from "../config.js";
import { CivicError } from "../lib/errors.js";

const FIRECRAWL_SCRAPE = "https://api.firecrawl.dev/v1/scrape";

export type IngestedScope = "federal" | "state" | "local-philly" | "unknown";

export interface IngestedFact {
  label: string;
  value: string;
}

export interface IngestedCitation {
  label: string;
  quote: string;
  url?: string;
}

export interface IngestedIssue {
  title: string;
  category: string;
  jurisdiction: string;
  scope: IngestedScope;
  zipCode: string;
  summary: string;
  impactLevel: "urgent" | "material" | "watch";
  voteDateISO: string;
  sourceName: string;
  sourceDetail: string;
  facts: IngestedFact[];
  topics: string[];
  officialName: string;
  officialTitle: string;
  officialDistrict: string;
  officialContactTarget: string;
  sourceURL: string;
  extractionConfidence: number;
  citations: IngestedCitation[];
}

interface FirecrawlScrapeResponse {
  success?: boolean;
  data?: {
    markdown?: string;
    metadata?: { title?: string; sourceURL?: string; url?: string };
  };
}

const EXTRACTION_SYSTEM = `You are the ingestion layer of Athen. You read a council agenda, committee packet, or government webpage and extract one civic issue into structured JSON.

Rules:
- Output ONE JSON object — nothing else, no markdown fences.
- Required keys: title, category, jurisdiction, scope, zipCode, summary, impactLevel, voteDateISO, sourceName, sourceDetail, facts, topics, officialName, officialTitle, officialDistrict, officialContactTarget, extractionConfidence, citations.
- impactLevel: "urgent" if the vote is within 72 hours OR has direct constituent-cost implications; "material" for funded changes ≥ $100K or programmatic shifts; "watch" otherwise.
- scope: "federal" for U.S. Congress / FCC / federal agency; "state" for state legislature; "local-philly" for Philadelphia City Council / Free Library / Water Board / etc; "unknown" if you can't tell.
- voteDateISO: ISO-8601 of the next vote/hearing. If only a date is stated, use 12:00:00 local time.
- facts: exactly 3 entries, each with label and value. Labels MUST be "What it does", "The cost", "The timeline".
- topics: subset of ["housing", "transit", "education", "environment", "publicSafety", "health", "money"]. 1–3 most relevant.
- officialContactTarget: the public comment portal name or inbox label (e.g. "Council public comment portal", "Board comment inbox").
- extractionConfidence: integer 0–100 for how clearly the source supports the extracted fields. Penalize missing dates, unclear jurisdiction, or thin source text.
- citations: 1–5 short source-backed citations. Each citation must have label and quote. Quote only text that appeared in the provided source content or structured fields.
- Do NOT invent statistics. If the page doesn't state the cost or timeline, write "Not specified in source".
- Use plain English. Short sentences. No legalese.`;

const TopicSchema = z.enum([
  "housing",
  "transit",
  "education",
  "environment",
  "publicSafety",
  "health",
  "money",
]);

const ExtractionSchema = z.object({
  title: z.string().min(3),
  category: z.string().min(1).default("Civic"),
  jurisdiction: z.string().min(1),
  scope: z.enum(["federal", "state", "local-philly", "unknown"]).catch("unknown"),
  zipCode: z.string().default(""),
  summary: z.string().min(20),
  impactLevel: z.string().default("watch"),
  voteDateISO: z.string().min(1),
  sourceName: z.string().min(1),
  sourceDetail: z.string().default(""),
  facts: z
    .array(z.object({ label: z.string().min(1), value: z.string().min(1) }))
    .default([]),
  topics: z.array(z.string()).default([]),
  officialName: z.string().default("Filing target"),
  officialTitle: z.string().default("Public Comment Intake"),
  officialDistrict: z.string().default(""),
  officialContactTarget: z.string().default("Public comment portal"),
  extractionConfidence: z.coerce.number().min(0).max(100).default(70),
  citations: z
    .array(
      z.object({
        label: z.string().min(1),
        quote: z.string().min(1),
        url: z.string().url().optional(),
      }),
    )
    .default([]),
});

export interface StructuredIngestionInput {
  sourceURL: string;
  jurisdiction: string;
  scopeHint: IngestedScope;
  fields: Record<string, string | number | null | undefined>;
  extraContext?: string;
  defaultContactTarget?: string;
}

export interface IngestionPipeline {
  ingestFromURL(url: string, jurisdictionHint?: string): Promise<IngestedIssue>;
  ingestFromStructured(input: StructuredIngestionInput): Promise<IngestedIssue>;
}

export class FirecrawlIngestionPipeline implements IngestionPipeline {
  private readonly client: Anthropic;

  constructor(client?: Anthropic) {
    this.client = client ?? new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  }

  async ingestFromURL(url: string, jurisdictionHint?: string): Promise<IngestedIssue> {
    validateSourceURL(url);
    if (!config.FIRECRAWL_API_KEY) {
      throw new CivicError(
        "firecrawl_unavailable",
        "FIRECRAWL_API_KEY is not configured; cannot scrape source.",
        503,
      );
    }

    const scraped = await this.scrape(url);
    if (!scraped.markdown || scraped.markdown.trim().length < 200) {
      throw new CivicError("source_empty", "Source page returned no usable content.", 422);
    }

    const userPrompt = [
      jurisdictionHint ? `Jurisdiction hint (use if confirmed by content): ${jurisdictionHint}` : "",
      `Source URL: ${url}`,
      `Source title: ${scraped.title ?? "Unknown"}`,
      "",
      "Page content (markdown):",
      scraped.markdown.slice(0, 18_000),
    ]
      .filter(Boolean)
      .join("\n");

    const response = await this.client.messages.create({
      model: config.ANTHROPIC_MODEL,
      max_tokens: 1400,
      system: EXTRACTION_SYSTEM,
      messages: [{ role: "user", content: userPrompt }],
    });

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new CivicError("extraction_failed", "Model returned no text.", 502);
    }

    const json = parseExtraction(textBlock.text);
    json.sourceURL = scraped.finalURL ?? url;
    return json;
  }

  async ingestFromStructured(input: StructuredIngestionInput): Promise<IngestedIssue> {
    const fieldLines = Object.entries(input.fields)
      .filter(([, v]) => v !== null && v !== undefined && String(v).trim().length > 0)
      .map(([k, v]) => `- ${k}: ${v}`)
      .join("\n");

    const userPrompt = [
      `Source URL: ${input.sourceURL}`,
      `Jurisdiction: ${input.jurisdiction}`,
      `Jurisdiction scope hint (use unless content contradicts): ${input.scopeHint}`,
      input.defaultContactTarget
        ? `Default officialContactTarget (use unless content contradicts): ${input.defaultContactTarget}`
        : "",
      "",
      "Structured fields from the source system:",
      fieldLines,
      input.extraContext ? `\nAdditional context:\n${input.extraContext.slice(0, 12_000)}` : "",
    ]
      .filter(Boolean)
      .join("\n");

    const response = await this.client.messages.create({
      model: config.ANTHROPIC_MODEL,
      max_tokens: 1400,
      system: EXTRACTION_SYSTEM,
      messages: [{ role: "user", content: userPrompt }],
    });

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new CivicError("extraction_failed", "Model returned no text.", 502);
    }

    const json = parseExtraction(textBlock.text);
    json.sourceURL = input.sourceURL;
    return json;
  }

  private async scrape(url: string): Promise<{ markdown?: string; title?: string; finalURL?: string }> {
    const res = await fetch(FIRECRAWL_SCRAPE, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${config.FIRECRAWL_API_KEY}`,
      },
      body: JSON.stringify({
        url,
        formats: ["markdown"],
        onlyMainContent: true,
      }),
      signal: AbortSignal.timeout(30_000),
    });

    if (!res.ok) {
      throw new CivicError(
        "scrape_failed",
        `Firecrawl returned ${res.status} for ${url}`,
        502,
      );
    }

    const json = (await res.json()) as FirecrawlScrapeResponse;
    const out: { markdown?: string; title?: string; finalURL?: string } = {};
    if (json.data?.markdown) out.markdown = json.data.markdown;
    if (json.data?.metadata?.title) out.title = json.data.metadata.title;
    if (json.data?.metadata?.sourceURL) out.finalURL = json.data.metadata.sourceURL;
    else if (json.data?.metadata?.url) out.finalURL = json.data.metadata.url;
    return out;
  }
}

function parseExtraction(raw: string): IngestedIssue {
  const trimmed = raw.trim();
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start < 0 || end < 0) {
    throw new CivicError("extraction_failed", "Model output was not JSON.", 502);
  }
  const candidate = trimmed.slice(start, end + 1);

  let decoded: unknown;
  try {
    decoded = JSON.parse(candidate);
  } catch {
    throw new CivicError("extraction_failed", "Model JSON did not parse.", 502);
  }

  const parsed = ExtractionSchema.safeParse(decoded);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((issue) => `${issue.path.join(".") || "root"}: ${issue.message}`)
      .join("; ");
    throw new CivicError("extraction_incomplete", `Extracted JSON failed schema: ${issues}`, 502);
  }

  const data = parsed.data;

  return {
    title: data.title.trim(),
    category: data.category.trim(),
    jurisdiction: data.jurisdiction.trim(),
    scope: data.scope as IngestedScope,
    zipCode: data.zipCode.trim(),
    summary: data.summary.trim(),
    impactLevel: normalizeImpactLevel(data.impactLevel),
    voteDateISO: normalizeDateISO(data.voteDateISO),
    sourceName: data.sourceName.trim(),
    sourceDetail: data.sourceDetail.trim(),
    facts: normalizeFacts(data.facts),
    topics: normalizeTopics(data.topics),
    officialName: data.officialName.trim() || "Filing target",
    officialTitle: data.officialTitle.trim() || "Public Comment Intake",
    officialDistrict: data.officialDistrict.trim(),
    officialContactTarget: data.officialContactTarget.trim() || "Public comment portal",
    sourceURL: "",
    extractionConfidence: Math.round(data.extractionConfidence),
    citations: data.citations.slice(0, 5).map((citation) => {
      const normalized: IngestedCitation = {
        label: citation.label.trim(),
        quote: citation.quote.trim().slice(0, 300),
      };
      if (citation.url) normalized.url = citation.url;
      return normalized;
    }),
  };
}

function validateSourceURL(url: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new CivicError("invalid_source_url", "Source URL is not valid.", 400);
  }
  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new CivicError("invalid_source_url", "Source URL must use http or https.", 400);
  }
}

function normalizeImpactLevel(raw: string): IngestedIssue["impactLevel"] {
  const value = raw.trim().toLowerCase();
  if (value === "urgent" || value === "high impact" || value === "high") return "urgent";
  if (value === "material" || value === "medium") return "material";
  return "watch";
}

function normalizeDateISO(raw: string): string {
  const dateOnly = raw.match(/^\d{4}-\d{2}-\d{2}$/);
  if (dateOnly) return `${raw}T12:00:00.000Z`;

  const direct = Date.parse(raw);
  if (Number.isFinite(direct)) return new Date(direct).toISOString();

  return new Date().toISOString();
}

function normalizeFacts(facts: IngestedFact[]): IngestedFact[] {
  const labels = ["What it does", "The cost", "The timeline"];
  return labels.map((label) => {
    const match = facts.find((fact) => fact.label.trim().toLowerCase() === label.toLowerCase());
    return {
      label,
      value: match?.value.trim() || "Not specified in source",
    };
  });
}

function normalizeTopics(rawTopics: string[]): string[] {
  const out: string[] = [];
  for (const topic of rawTopics) {
    const parsed = TopicSchema.safeParse(topic);
    if (parsed.success && !out.includes(parsed.data)) out.push(parsed.data);
  }
  return out.slice(0, 3);
}
