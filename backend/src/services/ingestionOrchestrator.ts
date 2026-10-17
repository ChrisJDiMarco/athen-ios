import { createHash } from "node:crypto";
import { config } from "../config.js";
import type { IssueStore } from "./issueStore.js";
import type { JurisdictionIngestor } from "./jurisdictionIngestor.js";
import type { StoredIssueInput } from "./issueNormalizer.js";
import { hostFromURL } from "./issueNormalizer.js";

/**
 * Real-time ingestion orchestrator. When the iOS app taps "refresh", or when
 * the backend boots with an empty issue store, this runs every available
 * connector in parallel, normalizes results, and upserts them into the issue
 * store so `/v1/issues` returns something useful immediately.
 *
 * Connectors are intentionally direct field-mapped (no Claude in the hot path)
 * so a refresh completes in seconds, not minutes. The Claude drafting pipeline
 * still fires when the user endorses/opposes a specific issue.
 */

export interface OrchestratorReport {
  startedAt: string;
  finishedAt: string;
  durationMs: number;
  totalInserted: number;
  totalUpdated: number;
  totalIssues: number;
  sources: SourceReport[];
}

export interface SourceReport {
  id: string;
  name: string;
  status: "ok" | "skipped" | "failed";
  inspected: number;
  inserted: number;
  updated: number;
  skippedReason?: string;
  error?: string;
  durationMs: number;
}

export interface OrchestratorOptions {
  /** Skip connectors that match these IDs. */
  skip?: string[] | undefined;
  /** Only run connectors that match these IDs. */
  only?: string[] | undefined;
  /** Per-connector timeout in ms. Defaults to 25s. */
  perConnectorTimeoutMs?: number | undefined;
  /** Optional state filter for OpenStates (default "Pennsylvania"). */
  openStatesJurisdiction?: string | undefined;
  /** Legistar lookahead window in days. */
  legistarLookaheadDays?: number | undefined;
  /** Cap items returned per connector. */
  perConnectorLimit?: number | undefined;
  /** Fired before each connector starts — used by SSE for live progress. */
  onSourceStart?: (info: { id: string; name: string }) => void;
  /** Fired the moment a connector completes (success or failure). */
  onSourceDone?: (report: SourceReport) => void;
}

interface ResolvedOptions {
  perConnectorTimeoutMs: number;
  openStatesJurisdiction: string;
  legistarLookaheadDays: number;
  perConnectorLimit: number;
}

interface Connector {
  id: string;
  name: string;
  run(args: { store: IssueStore; opts: ResolvedOptions }): Promise<{
    inspected: number;
    inserted: number;
    updated: number;
    skippedReason?: string;
  }>;
}

export class IngestionOrchestrator {
  constructor(
    private readonly store: IssueStore,
    private readonly jurisdictionIngestor: JurisdictionIngestor,
    private readonly connectors?: Connector[],
  ) {}

  private get allConnectors(): Connector[] {
    return (
      this.connectors ?? [
        new LegistarPhillyConnector(this.jurisdictionIngestor),
        new OpenStatesConnector(),
        new FederalRegisterConnector(),
        new CongressGovConnector(),
      ]
    );
  }

  async run(options: OrchestratorOptions = {}): Promise<OrchestratorReport> {
    const startedAt = new Date();
    const opts: ResolvedOptions = {
      // 40s gives each connector room for its own internal HTTP timeouts
      // (15-20s) plus one retry, without holding the whole orchestrator
      // hostage for a flaky source.
      perConnectorTimeoutMs: options.perConnectorTimeoutMs ?? 40_000,
      openStatesJurisdiction: options.openStatesJurisdiction ?? "Pennsylvania",
      legistarLookaheadDays: options.legistarLookaheadDays ?? 21,
      perConnectorLimit: options.perConnectorLimit ?? 15,
    };

    const selected = this.allConnectors.filter((c) => {
      if (options.only && options.only.length > 0) return options.only.includes(c.id);
      if (options.skip && options.skip.includes(c.id)) return false;
      return true;
    });

    const settled = await Promise.allSettled(
      selected.map(async (connector) => {
        const t0 = Date.now();
        // Notify before kickoff so the SSE client can paint a spinner.
        try { options.onSourceStart?.({ id: connector.id, name: connector.name }); } catch {}
        // One-shot retry on transient failures. Government APIs are flaky;
        // a single retry catches most blips without doubling our load.
        const runOnce = async () =>
          withTimeout(
            connector.run({ store: this.store, opts }),
            opts.perConnectorTimeoutMs,
            `${connector.id} timed out after ${opts.perConnectorTimeoutMs}ms`,
          );
        let report: SourceReport;
        try {
          let result;
          try {
            result = await runOnce();
          } catch (firstErr) {
            // Backoff briefly, then try once more.
            await new Promise((r) => setTimeout(r, 750));
            try {
              result = await runOnce();
            } catch {
              throw firstErr;
            }
          }
          report = {
            id: connector.id,
            name: connector.name,
            status: result.skippedReason ? "skipped" : "ok",
            inspected: result.inspected,
            inserted: result.inserted,
            updated: result.updated,
            durationMs: Date.now() - t0,
          };
          if (result.skippedReason) report.skippedReason = result.skippedReason;
        } catch (err) {
          report = {
            id: connector.id,
            name: connector.name,
            status: "failed",
            inspected: 0,
            inserted: 0,
            updated: 0,
            error: err instanceof Error ? err.message : String(err),
            durationMs: Date.now() - t0,
          };
        }
        // Push the per-source report to subscribers the moment it lands so
        // the iOS drawer can tick connectors off as they finish.
        try { options.onSourceDone?.(report); } catch {}
        return report;
      }),
    );

    const reports: SourceReport[] = settled.map((s, i) =>
      s.status === "fulfilled"
        ? s.value
        : {
            id: selected[i]!.id,
            name: selected[i]!.name,
            status: "failed",
            inspected: 0,
            inserted: 0,
            updated: 0,
            error: s.reason instanceof Error ? s.reason.message : String(s.reason),
            durationMs: 0,
          },
    );

    const finishedAt = new Date();
    return {
      startedAt: startedAt.toISOString(),
      finishedAt: finishedAt.toISOString(),
      durationMs: finishedAt.getTime() - startedAt.getTime(),
      totalInserted: reports.reduce((a, r) => a + r.inserted, 0),
      totalUpdated: reports.reduce((a, r) => a + r.updated, 0),
      totalIssues: this.store.all().length,
      sources: reports,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connectors

class LegistarPhillyConnector implements Connector {
  readonly id = "legistar-phila";
  readonly name = "Philadelphia City Council (Legistar)";

  constructor(private readonly jurisdictionIngestor: JurisdictionIngestor) {}

  async run({ opts }: { store: IssueStore; opts: ResolvedOptions }) {
    const report = await this.jurisdictionIngestor.ingestLegistar({
      client: "phila",
      lookaheadDays: opts.legistarLookaheadDays,
      limit: opts.perConnectorLimit,
    });
    return {
      inspected: report.inspected,
      inserted: report.inserted,
      updated: report.updated,
    };
  }
}

class OpenStatesConnector implements Connector {
  readonly id = "openstates-bills";
  readonly name = "OpenStates state bills";

  async run({ store, opts }: { store: IssueStore; opts: ResolvedOptions }) {
    if (!config.OPENSTATES_API_KEY) {
      return { inspected: 0, inserted: 0, updated: 0, skippedReason: "OPENSTATES_API_KEY not set" };
    }
    const url = new URL("https://v3.openstates.org/bills");
    url.searchParams.set("jurisdiction", opts.openStatesJurisdiction);
    url.searchParams.set("sort", "updated_desc");
    url.searchParams.set("per_page", String(opts.perConnectorLimit));
    // Pull only bills with action in the last 60 days. Prevents 2-year-old
    // bills from showing up as "active" just because they're in the catalog.
    const cutoff = new Date(Date.now() - 60 * 86_400_000).toISOString().slice(0, 10);
    url.searchParams.set("action_since", cutoff);
    // OpenStates returns much richer text when you ask for abstracts +
    // sponsorships + actions — without it the brief writer can't say
    // anything substantive about the bill. (`subject` is already inline,
    // not an include.)
    url.searchParams.append("include", "abstracts");
    url.searchParams.append("include", "sponsorships");
    url.searchParams.append("include", "actions");

    const res = await fetch(url, {
      headers: { Accept: "application/json", "X-API-KEY": config.OPENSTATES_API_KEY },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) throw new Error(`OpenStates HTTP ${res.status}`);
    const json = (await res.json()) as OpenStatesResponse;
    const bills = (json.results ?? []).slice(0, opts.perConnectorLimit);

    let inserted = 0;
    let updated = 0;
    for (const bill of bills) {
      const detailURL =
        bill.openstates_url ??
        bill.sources?.[0]?.url ??
        `https://openstates.org/bills/${encodeURIComponent(opts.openStatesJurisdiction)}/${bill.identifier}/`;
      const fingerprint = createHash("sha1").update(`openstates:${bill.id}`).digest("hex");
      const existing = store.byFingerprint(fingerprint);

      const stateCode = inferStateCode(bill.jurisdiction?.name ?? opts.openStatesJurisdiction);
      const sponsor = bill.sponsorships?.[0]?.name;
      const sponsorParty = bill.sponsorships?.[0]?.party;
      const sponsorList = (bill.sponsorships ?? [])
        .slice(0, 4)
        .map((s) => [s.name, s.party].filter(Boolean).join(" — "))
        .join(", ");
      const abstract = bill.abstracts?.find((a) => (a.abstract ?? "").length > 20)?.abstract;
      const recentActions = (bill.actions ?? [])
        .slice(-3)
        .map((a) => `${a.date}: ${a.description}`);
      const subjects = (bill.subject ?? bill.subjects ?? []).slice(0, 5).join(", ");

      const facts: StoredIssueInput["facts"] = [
        {
          label: "What it does",
          value: abstract
            ? truncate(abstract, 220)
            : (bill.title ?? bill.latest_action_description ?? "State legislation update."),
        },
        {
          label: "The latest action",
          value: bill.latest_action_description ?? "Action details pending.",
        },
        {
          label: "Primary sponsor",
          value: sponsor
            ? `${sponsor}${sponsorParty ? ` (${sponsorParty})` : ""}`
            : "Sponsor not listed",
        },
      ];

      const citations: StoredIssueInput["citations"] = [];
      if (abstract) {
        citations.push({ label: "Official abstract", quote: truncate(abstract, 600), url: detailURL });
      }
      for (const action of recentActions) {
        citations.push({ label: "Recent action", quote: action });
      }
      if (sponsorList) {
        citations.push({ label: "Sponsors", quote: sponsorList });
      }
      if (subjects) {
        citations.push({ label: "Subjects", quote: subjects });
      }

      const summary = abstract
        ? truncate(abstract, 280)
        : bill.latest_action_description ?? bill.title ?? "State bill update.";

      const input: StoredIssueInput = {
        sourceFingerprint: fingerprint,
        title: `${bill.identifier ?? "State bill"}: ${truncate(bill.title ?? "State bill", 140)}`,
        category: "State legislation",
        jurisdiction: bill.jurisdiction?.name ?? opts.openStatesJurisdiction,
        scope: "state",
        summary,
        impactLevel: classifyImpact(bill),
        voteDateISO: classifyVoteDate(bill),
        sourceName: `OpenStates · ${bill.identifier ?? "bill"}`,
        sourceDetail: bill.title ?? "State bill",
        sourceURL: detailURL,
        sourceHost: hostFromURL(detailURL),
        sourceType: "official-api:openstates",
        sourceRecordID: bill.id,
        trustScore: 78,
        extractionConfidence: 95,
        citations,
        ingestedAt: new Date().toISOString(),
        topics: deriveTopics(bill.title ?? "", bill.latest_action_description ?? ""),
        facts,
        official: {
          name: sponsor ?? `Primary sponsor (${stateCode ?? "state"})`,
          title: sponsor ? "Bill sponsor" : "State legislator",
          district: stateCode ?? "State",
          contactTarget: "State legislative office",
        },
        filingRoute: {
          verificationStep: "Verified address confirms eligibility in this state.",
          routingStep: `Routing agent maps your address to ${stateCode ?? "your state"} representatives.`,
          destinationStep: "Message is filed to the bill's primary sponsor and the relevant committee.",
          deliveryWindow: "Typical confirmation within a few minutes",
        },
        ...(stateCode ? { stateCode } : {}),
      };

      await store.upsert(input);
      if (existing) updated += 1;
      else inserted += 1;
    }

    return { inspected: bills.length, inserted, updated };
  }
}

class FederalRegisterConnector implements Connector {
  readonly id = "federal-register";
  readonly name = "Federal Register (proposed + final rules)";

  async run({ store, opts }: { store: IssueStore; opts: ResolvedOptions }) {
    // Federal Register public API — no key required. Pulls recent rules with
    // an open public comment period so they're actually actionable.
    const url = new URL("https://www.federalregister.gov/api/v1/documents.json");
    url.searchParams.set("per_page", String(opts.perConnectorLimit));
    url.searchParams.set("order", "newest");
    url.searchParams.append("conditions[type][]", "RULE");
    url.searchParams.append("conditions[type][]", "PRORULE");
    url.searchParams.set("fields[]", "title");
    url.searchParams.append("fields[]", "abstract");
    url.searchParams.append("fields[]", "document_number");
    url.searchParams.append("fields[]", "html_url");
    url.searchParams.append("fields[]", "publication_date");
    url.searchParams.append("fields[]", "comments_close_on");
    url.searchParams.append("fields[]", "agencies");
    url.searchParams.append("fields[]", "type");
    url.searchParams.append("fields[]", "regulations_dot_gov_info");

    const res = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) throw new Error(`Federal Register HTTP ${res.status}`);
    const json = (await res.json()) as FederalRegisterResponse;
    const docs = (json.results ?? []).slice(0, opts.perConnectorLimit);

    let inserted = 0;
    let updated = 0;
    for (const doc of docs) {
      if (!doc.document_number || !doc.html_url) continue;
      const fingerprint = createHash("sha1").update(`fr:${doc.document_number}`).digest("hex");
      const existing = store.byFingerprint(fingerprint);

      const agencyName = doc.agencies?.[0]?.name ?? "Federal agency";
      const closesOn = doc.comments_close_on ?? null;
      const voteDateISO = closesOn
        ? new Date(`${closesOn}T17:00:00Z`).toISOString()
        : new Date(Date.now() + 14 * 86_400_000).toISOString();

      const facts: StoredIssueInput["facts"] = [
        {
          label: "What it does",
          value: truncate(doc.abstract ?? doc.title, 220),
        },
        {
          label: "Public comment",
          value: closesOn
            ? `Comment period closes ${closesOn}.`
            : "Public comment window may apply — check the official record.",
        },
        {
          label: "Issuing agency",
          value: agencyName,
        },
      ];

      const input: StoredIssueInput = {
        sourceFingerprint: fingerprint,
        title: truncate(doc.title, 160),
        category: doc.type === "Proposed Rule" || doc.type === "Proposed Rule (PRORULE)" ? "Proposed rule" : "Federal rule",
        jurisdiction: agencyName,
        scope: "federal",
        summary: truncate(doc.abstract ?? doc.title, 320),
        impactLevel: classifyFederalImpact(doc),
        voteDateISO,
        sourceName: `Federal Register · ${doc.document_number}`,
        sourceDetail: doc.title,
        sourceURL: doc.html_url,
        sourceHost: "federalregister.gov",
        sourceType: "official-api:federalregister",
        sourceRecordID: doc.document_number,
        trustScore: 88,
        extractionConfidence: 96,
        citations: [],
        ingestedAt: new Date().toISOString(),
        topics: deriveTopics(doc.title, doc.abstract ?? ""),
        facts,
        official: {
          name: agencyName,
          title: "Federal rulemaking agency",
          district: "United States",
          contactTarget: closesOn ? "Regulations.gov comment docket" : "Agency public record",
        },
        filingRoute: {
          verificationStep: "Verified address confirms U.S. residency for the public record.",
          routingStep: `Routing agent files your comment with ${agencyName}.`,
          destinationStep: doc.regulations_dot_gov_info?.docket_id
            ? `Comment submitted to docket ${doc.regulations_dot_gov_info.docket_id} on regulations.gov.`
            : `Comment submitted to ${agencyName}'s public docket.`,
          deliveryWindow: "Typical confirmation within a few minutes",
        },
      };

      await store.upsert(input);
      if (existing) updated += 1;
      else inserted += 1;
    }

    return { inspected: docs.length, inserted, updated };
  }
}

/**
 * Congress.gov bills connector. The Federal Register connector only pulls
 * agency rulemaking; this one pulls actual federal legislation (H.R., S.
 * bills) — the stuff Athen users most often want to file on. Requires
 * CONGRESS_API_KEY (free key from api.congress.gov).
 */
class CongressGovConnector implements Connector {
  readonly id = "congress-gov";
  readonly name = "Congress.gov (federal bills)";

  async run({ store, opts }: { store: IssueStore; opts: ResolvedOptions }) {
    if (!config.CONGRESSGOV_API_KEY) {
      return {
        inspected: 0,
        inserted: 0,
        updated: 0,
        skippedReason: "CONGRESSGOV_API_KEY not set — skipping federal bills.",
      };
    }
    const url = new URL("https://api.congress.gov/v3/bill");
    url.searchParams.set("limit", String(opts.perConnectorLimit));
    url.searchParams.set("sort", "updateDate+desc");
    url.searchParams.set("format", "json");
    url.searchParams.set("api_key", config.CONGRESSGOV_API_KEY);

    const res = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(20_000),
    });
    if (!res.ok) throw new Error(`Congress.gov HTTP ${res.status}`);
    const json = (await res.json()) as CongressBillsResponse;
    const bills = (json.bills ?? []).slice(0, opts.perConnectorLimit);

    let inserted = 0;
    let updated = 0;
    for (const bill of bills) {
      if (!bill.number || !bill.type || !bill.congress) continue;
      const fingerprintKey = `cg:${bill.congress}:${bill.type}:${bill.number}`;
      const fingerprint = createHash("sha1").update(fingerprintKey).digest("hex");
      const existing = store.byFingerprint(fingerprint);

      const billTitle = bill.title?.trim() || `${bill.type} ${bill.number}`;
      const latestActionDate = bill.latestAction?.actionDate ?? bill.updateDate ?? new Date().toISOString();
      const latestActionText = bill.latestAction?.text ?? "Status update available on Congress.gov";
      const url = `https://www.congress.gov/bill/${bill.congress}th-congress/${bill.type.toLowerCase()}/${bill.number}`;

      const facts: StoredIssueInput["facts"] = [
        {
          label: "What it does",
          value: truncate(billTitle, 220),
        },
        {
          label: "Latest action",
          value: truncate(latestActionText, 200),
        },
        {
          label: "Status",
          value: `Last updated ${latestActionDate.slice(0, 10)}.`,
        },
      ];

      const voteDateISO = projectFederalVoteDate(latestActionDate);

      const input: StoredIssueInput = {
        sourceFingerprint: fingerprint,
        title: truncate(`${bill.type} ${bill.number}: ${billTitle}`, 160),
        category: "Federal legislation",
        jurisdiction: bill.congress
          ? `U.S. ${bill.type.startsWith("H") ? "House" : "Senate"}, ${bill.congress}th Congress`
          : "United States Congress",
        scope: "federal",
        summary: truncate(latestActionText, 320),
        impactLevel: classifyCongressImpact(latestActionText),
        voteDateISO,
        sourceName: `Congress.gov · ${bill.type} ${bill.number}`,
        sourceDetail: billTitle,
        sourceURL: url,
        sourceHost: "congress.gov",
        sourceType: "official-api:congress",
        sourceRecordID: `${bill.congress}-${bill.type}-${bill.number}`,
        trustScore: 92,
        extractionConfidence: 96,
        citations: [],
        ingestedAt: new Date().toISOString(),
        topics: deriveTopics(billTitle, latestActionText),
        facts,
        official: {
          name: bill.type.startsWith("H") ? "U.S. House of Representatives" : "U.S. Senate",
          title: "Federal legislators",
          district: "United States",
          contactTarget: "Your federal delegation",
        },
        filingRoute: {
          verificationStep: "Verified address determines your federal delegation (2 senators + 1 house rep).",
          routingStep: "Athen routes your position to all three offices simultaneously.",
          destinationStep: "Submitted via each office's public contact form / email gateway.",
          deliveryWindow: "Confirmation queued, typically delivered within the hour",
        },
      };

      await store.upsert(input);
      if (existing) updated += 1;
      else inserted += 1;
    }

    return { inspected: bills.length, inserted, updated };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers

function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(label)), ms);
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}

function truncate(text: string, max: number): string {
  if (!text) return text;
  return text.length <= max ? text : `${text.slice(0, max - 1).trimEnd()}…`;
}

function deriveTopics(...sources: string[]): string[] {
  const haystack = sources.join(" ").toLowerCase();
  const topics: string[] = [];
  const pairs: [string, string[]][] = [
    ["housing", ["housing", "rent", "tenant", "landlord", "eviction", "zoning"]],
    ["transit", ["transit", "transportation", "highway", "rail", "bus"]],
    ["education", ["education", "school", "student", "teacher", "campus"]],
    ["environment", ["environment", "climate", "epa", "emission", "water", "river", "pollution"]],
    ["publicSafety", ["police", "safety", "crime", "firearm", "public safety"]],
    ["health", ["health", "medicaid", "medicare", "hospital", "clinic", "fda"]],
    ["money", ["tax", "budget", "appropriation", "spending", "fee", "fund"]],
  ];
  for (const [topic, keywords] of pairs) {
    if (keywords.some((k) => haystack.includes(k))) topics.push(topic);
    if (topics.length >= 3) break;
  }
  return topics.length > 0 ? topics : ["money"];
}

function classifyImpact(bill: OpenStatesBill): "urgent" | "material" | "watch" {
  const action = (bill.latest_action_description ?? "").toLowerCase();
  if (/floor vote|third reading|signed|passed/.test(action)) return "urgent";
  if (/committee|reported|amended|introduced/.test(action)) return "material";
  return "watch";
}

function classifyVoteDate(bill: OpenStatesBill): string {
  // OpenStates rarely exposes a true next-vote date. We want a useful "watch
  // window" anchor that is ALWAYS in the future relative to today — otherwise
  // the issue shows up as an upcoming-deadline card even though its real-world
  // action already happened.
  const last = bill.latest_action_date ?? bill.first_action_date;
  const now = Date.now();
  if (last) {
    const lastTs = Date.parse(last);
    if (Number.isFinite(lastTs)) {
      const proposed = lastTs + 7 * 86_400_000;
      if (proposed > now) {
        return new Date(proposed).toISOString();
      }
    }
  }
  // Default: 14 days from today so the card means "watch this fortnight".
  return new Date(now + 14 * 86_400_000).toISOString();
}

function classifyFederalImpact(doc: FederalRegisterDocument): "urgent" | "material" | "watch" {
  if (doc.comments_close_on) {
    const days = Math.ceil((Date.parse(doc.comments_close_on) - Date.now()) / 86_400_000);
    if (days <= 7) return "urgent";
    if (days <= 30) return "material";
  }
  return "watch";
}

function inferStateCode(name: string): string | undefined {
  const map: Record<string, string> = {
    Pennsylvania: "PA",
    California: "CA",
    "New York": "NY",
    Texas: "TX",
    Florida: "FL",
    Illinois: "IL",
    Washington: "WA",
    Massachusetts: "MA",
    Oregon: "OR",
  };
  return map[name];
}

// ─────────────────────────────────────────────────────────────────────────────
// Wire shapes from external APIs

interface OpenStatesResponse {
  results?: OpenStatesBill[];
}

interface OpenStatesBill {
  id: string;
  identifier?: string;
  title?: string;
  session?: string;
  jurisdiction?: { name?: string };
  latest_action_date?: string;
  latest_action_description?: string;
  first_action_date?: string;
  updated_at?: string;
  openstates_url?: string;
  sources?: { url: string }[];
  sponsorships?: { name?: string; party?: string; person?: { party?: string } }[];
  abstracts?: { abstract?: string; note?: string }[];
  actions?: { date: string; description: string }[];
  subject?: string[];
  /** Old/alternate spelling — keep tolerant. */
  subjects?: string[];
}

interface FederalRegisterResponse {
  results?: FederalRegisterDocument[];
}

interface FederalRegisterDocument {
  document_number: string;
  title: string;
  abstract?: string;
  html_url: string;
  publication_date?: string;
  comments_close_on?: string;
  type?: string;
  agencies?: { name?: string }[];
  regulations_dot_gov_info?: { docket_id?: string };
}

interface CongressBillsResponse {
  bills?: CongressBill[];
}

interface CongressBill {
  number?: string;
  type?: string;
  congress?: number;
  title?: string;
  updateDate?: string;
  latestAction?: {
    actionDate?: string;
    text?: string;
  };
}

function classifyCongressImpact(latestAction: string): "urgent" | "material" | "watch" {
  const a = latestAction.toLowerCase();
  if (a.includes("passed") || a.includes("vote scheduled") || a.includes("conference")) return "urgent";
  if (a.includes("committee") || a.includes("reported") || a.includes("markup")) return "material";
  return "watch";
}

function projectFederalVoteDate(latestActionDateISO: string): string {
  // Federal bills don't have a single hard "vote date" — most go through
  // committee → floor → conference over weeks. Project ~21 days out from
  // the last known action as a reasonable "watch this window" anchor.
  const base = Date.parse(latestActionDateISO);
  if (Number.isNaN(base)) return new Date(Date.now() + 21 * 86_400_000).toISOString();
  return new Date(base + 21 * 86_400_000).toISOString();
}
