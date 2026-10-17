import { config } from "../../config.js";
import type { EvidenceRecordInput, EvidenceSnippet } from "../evidenceVault.js";
import { hostFromURL } from "../sourceRegistry.js";

export interface SourceSweepArgs {
  daysBack?: number;
  limit?: number;
  connectors?: string[];
}

export interface SourceSweepResult {
  connector: string;
  inspected: number;
  records: EvidenceRecordInput[];
  skippedReason?: string;
  error?: string;
}

interface CivicConnector {
  id: string;
  collect(args: Required<Pick<SourceSweepArgs, "daysBack" | "limit">>): Promise<SourceSweepResult>;
}

export class CivicSourceSweeper {
  private readonly connectors: CivicConnector[];

  constructor(connectors?: CivicConnector[]) {
    this.connectors = connectors ?? [
      new CongressGovConnector(),
      new GovInfoConnector(),
      new RegulationsGovConnector(),
      new OpenStatesBillsConnector(),
      new SocrataCatalogConnector(),
      new Open311Connector(),
    ];
  }

  async sweep(args: SourceSweepArgs = {}): Promise<SourceSweepResult[]> {
    const daysBack = args.daysBack ?? 7;
    const limit = args.limit ?? 10;
    const requested = new Set((args.connectors ?? []).map((entry) => entry.toLowerCase()));
    const selected = requested.size > 0
      ? this.connectors.filter((connector) => requested.has(connector.id))
      : this.connectors;

    const results: SourceSweepResult[] = [];
    for (const connector of selected) {
      try {
        results.push(await connector.collect({ daysBack, limit }));
      } catch (err) {
        results.push({
          connector: connector.id,
          inspected: 0,
          records: [],
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
    return results;
  }
}

class CongressGovConnector implements CivicConnector {
  readonly id = "congress";

  async collect(args: Required<Pick<SourceSweepArgs, "daysBack" | "limit">>): Promise<SourceSweepResult> {
    if (!config.CONGRESSGOV_API_KEY) return skipped(this.id, "CONGRESSGOV_API_KEY is not configured.");
    const url = new URL("https://api.congress.gov/v3/bill");
    url.searchParams.set("format", "json");
    url.searchParams.set("limit", String(args.limit));
    url.searchParams.set("sort", "updateDate+desc");
    url.searchParams.set("fromDateTime", startDateTime(args.daysBack));
    url.searchParams.set("api_key", config.CONGRESSGOV_API_KEY);

    const json = await fetchJSON<CongressBillsResponse>(url.toString(), { Accept: "application/json" });
    const bills = json.bills ?? [];
    return {
      connector: this.id,
      inspected: bills.length,
      records: bills.map((bill) => {
        const publicURL = billPublicURL(bill);
        return evidence({
          sourceName: "Congress.gov",
          sourceURL: publicURL,
          sourceType: "official-api:congress.gov",
          jurisdiction: "U.S. Congress",
          scope: "federal",
          title: bill.title ?? `${bill.type ?? "Bill"} ${bill.number ?? ""}`.trim(),
          summary: bill.latestAction?.text ?? "Congress.gov bill record updated.",
          snippets: snippetList([
            ["Latest action", bill.latestAction?.text],
            ["Bill number", [bill.type, bill.number].filter(Boolean).join(" ")],
          ]),
          sourceRecordID: [bill.congress, bill.type, bill.number].filter(Boolean).join("-"),
          publishedAtISO: dateToISO(bill.latestAction?.actionDate),
          updatedAtISO: dateToISO(bill.updateDate),
          tags: ["federal", "congress"],
          rawRecord: compactRecord(bill),
        });
      }),
    };
  }
}

class GovInfoConnector implements CivicConnector {
  readonly id = "govinfo";

  async collect(args: Required<Pick<SourceSweepArgs, "daysBack" | "limit">>): Promise<SourceSweepResult> {
    if (!config.GOVINFO_API_KEY) return skipped(this.id, "GOVINFO_API_KEY is not configured.");
    const date = new Date(Date.now() - args.daysBack * 86_400_000).toISOString().slice(0, 10);
    const url = new URL(`https://api.govinfo.gov/collections/BILLS/${date}T00:00:00Z`);
    url.searchParams.set("pageSize", String(args.limit));
    url.searchParams.set("offsetMark", "*");
    url.searchParams.set("api_key", config.GOVINFO_API_KEY);

    const json = await fetchJSON<GovInfoCollectionResponse>(url.toString(), { Accept: "application/json" });
    const packages = json.packages ?? [];
    return {
      connector: this.id,
      inspected: packages.length,
      records: packages.map((pkg) =>
        evidence({
          sourceName: "GovInfo",
          sourceURL: pkg.detailsLink ?? pkg.packageLink ?? "https://www.govinfo.gov/app/collection/bills",
          sourceType: "official-api:govinfo",
          jurisdiction: "Federal Government",
          scope: "federal",
          title: pkg.title ?? pkg.packageId ?? "GovInfo package",
          summary: pkg.title ?? "GovInfo federal package updated.",
          snippets: snippetList([
            ["Package", pkg.packageId],
            ["Collection", pkg.collectionCode],
          ]),
          sourceRecordID: pkg.packageId,
          publishedAtISO: dateToISO(pkg.dateIssued),
          updatedAtISO: dateToISO(pkg.lastModified),
          tags: ["federal", "govinfo"],
          rawRecord: compactRecord(pkg),
        }),
      ),
    };
  }
}

class RegulationsGovConnector implements CivicConnector {
  readonly id = "regulations";

  async collect(args: Required<Pick<SourceSweepArgs, "daysBack" | "limit">>): Promise<SourceSweepResult> {
    if (!config.REGULATIONS_API_KEY) return skipped(this.id, "REGULATIONS_API_KEY is not configured.");
    const postedAfter = new Date(Date.now() - args.daysBack * 86_400_000).toISOString().slice(0, 10);
    const url = new URL("https://api.regulations.gov/v4/documents");
    url.searchParams.set("filter[postedDate][ge]", postedAfter);
    url.searchParams.set("sort", "-postedDate");
    url.searchParams.set("page[size]", String(args.limit));
    url.searchParams.set("api_key", config.REGULATIONS_API_KEY);

    const json = await fetchJSON<RegulationsDocumentsResponse>(url.toString(), { Accept: "application/vnd.api+json" });
    const docs = json.data ?? [];
    return {
      connector: this.id,
      inspected: docs.length,
      records: docs.map((doc) => {
        const attrs = doc.attributes ?? {};
        return evidence({
          sourceName: "Regulations.gov",
          sourceURL: `https://www.regulations.gov/document/${doc.id}`,
          sourceType: "official-api:regulations.gov",
          jurisdiction: attrs.agencyId ?? "Federal rulemaking",
          scope: "federal",
          title: attrs.title ?? doc.id,
          summary: [attrs.documentType, attrs.commentEndDate ? `Comments due ${attrs.commentEndDate}` : ""]
            .filter(Boolean)
            .join(". ") || "Regulations.gov document posted.",
          snippets: snippetList([
            ["Document type", attrs.documentType],
            ["Docket", attrs.docketId],
            ["Comment deadline", attrs.commentEndDate],
          ]),
          sourceRecordID: doc.id,
          publishedAtISO: dateToISO(attrs.postedDate),
          updatedAtISO: dateToISO(attrs.modifyDate),
          tags: ["federal", "rulemaking", "public-comment"],
          rawRecord: compactRecord(doc),
        });
      }),
    };
  }
}

class OpenStatesBillsConnector implements CivicConnector {
  readonly id = "openstates";

  async collect(args: Required<Pick<SourceSweepArgs, "daysBack" | "limit">>): Promise<SourceSweepResult> {
    if (!config.OPENSTATES_API_KEY) return skipped(this.id, "OPENSTATES_API_KEY is not configured.");
    const jurisdictions = splitEnv(config.OPENSTATES_JURISDICTIONS || "Pennsylvania");
    const records: EvidenceRecordInput[] = [];

    for (const jurisdiction of jurisdictions) {
      const url = new URL("https://v3.openstates.org/bills");
      url.searchParams.set("jurisdiction", jurisdiction);
      url.searchParams.set("sort", "updated_desc");
      url.searchParams.set("per_page", String(args.limit));
      const json = await fetchJSON<OpenStatesBillsResponse>(url.toString(), {
        Accept: "application/json",
        "X-API-KEY": config.OPENSTATES_API_KEY,
      });
      for (const bill of json.results ?? []) {
        records.push(evidence({
          sourceName: "OpenStates",
          sourceURL: bill.openstates_url ?? bill.sources?.[0]?.url ?? "https://openstates.org/",
          sourceType: "official-api:openstates",
          jurisdiction: bill.jurisdiction?.name ?? jurisdiction,
          scope: "state",
          title: `${bill.identifier ?? "Bill"}: ${bill.title ?? "State bill"}`,
          summary: bill.latest_action_description ?? bill.title ?? "State bill updated.",
          snippets: snippetList([
            ["Latest action", bill.latest_action_description],
            ["Session", bill.session],
          ]),
          sourceRecordID: bill.id,
          publishedAtISO: dateToISO(bill.first_action_date),
          updatedAtISO: dateToISO(bill.updated_at),
          tags: ["state", "openstates"],
          rawRecord: compactRecord(bill),
        }));
      }
    }

    return { connector: this.id, inspected: records.length, records };
  }
}

class SocrataCatalogConnector implements CivicConnector {
  readonly id = "socrata";

  async collect(args: Required<Pick<SourceSweepArgs, "daysBack" | "limit">>): Promise<SourceSweepResult> {
    const domains = splitEnv(config.SOCRATA_CATALOG_DOMAINS || "data.cityofnewyork.us,data.sfgov.org,data.cityofchicago.org");
    const records: EvidenceRecordInput[] = [];
    for (const domain of domains) {
      const url = new URL("https://api.us.socrata.com/api/catalog/v1");
      url.searchParams.set("domains", domain);
      url.searchParams.set("only", "datasets");
      url.searchParams.set("limit", String(args.limit));
      if (config.SOCRATA_APP_TOKEN) url.searchParams.set("$$app_token", config.SOCRATA_APP_TOKEN);
      const json = await fetchJSON<SocrataCatalogResponse>(url.toString(), { Accept: "application/json" });
      for (const result of json.results ?? []) {
        const resource = result.resource ?? {};
        const link = result.permalink ?? (resource.id ? `https://${domain}/d/${resource.id}` : `https://${domain}`);
        records.push(evidence({
          sourceName: `Socrata (${domain})`,
          sourceURL: link,
          sourceType: "official-api:socrata",
          jurisdiction: domain,
          scope: "unknown",
          title: resource.name ?? "Open data dataset",
          summary: resource.description ?? "Public open-data dataset discovered through Socrata catalog.",
          snippets: snippetList([
            ["Dataset", resource.name],
            ["Attribution", resource.attribution],
          ]),
          sourceRecordID: resource.id,
          publishedAtISO: dateToISO(resource.createdAt),
          updatedAtISO: dateToISO(resource.updatedAt),
          tags: ["open-data", "socrata"],
          rawRecord: compactRecord(result),
        }));
      }
    }

    return { connector: this.id, inspected: records.length, records };
  }
}

class Open311Connector implements CivicConnector {
  readonly id = "open311";

  async collect(args: Required<Pick<SourceSweepArgs, "daysBack" | "limit">>): Promise<SourceSweepResult> {
    const endpoints = splitEnv(config.OPEN311_ENDPOINTS || "");
    if (endpoints.length === 0) return skipped(this.id, "OPEN311_ENDPOINTS is not configured.");
    const records: EvidenceRecordInput[] = [];
    for (const endpoint of endpoints) {
      const servicesURL = new URL(appendPath(endpoint, "services.json"));
      const services = await fetchJSON<Open311Service[]>(servicesURL.toString(), { Accept: "application/json" });
      for (const service of services.slice(0, args.limit)) {
        records.push(evidence({
          sourceName: `Open311 (${servicesURL.host})`,
          sourceURL: servicesURL.toString(),
          sourceType: "official-api:open311",
          jurisdiction: servicesURL.host,
          scope: "unknown",
          title: service.service_name ?? service.service_code ?? "Open311 service",
          summary: service.description ?? "Open311 request type available for local service reporting.",
          snippets: snippetList([
            ["Service code", service.service_code],
            ["Metadata", service.metadata],
          ]),
          sourceRecordID: service.service_code,
          updatedAtISO: new Date().toISOString(),
          tags: ["local", "service-requests", "open311"],
          rawRecord: compactRecord(service),
        }));
      }
    }
    return { connector: this.id, inspected: records.length, records };
  }
}

type LooseEvidenceInput = Omit<
  EvidenceRecordInput,
  "sourceHost" | "trustScore" | "extractionConfidence" | "sourceRecordID" | "publishedAtISO" | "updatedAtISO" | "rawRecord"
> & {
  sourceRecordID?: string | undefined;
  publishedAtISO?: string | undefined;
  updatedAtISO?: string | undefined;
  rawRecord?: Record<string, unknown> | undefined;
};

function evidence(input: LooseEvidenceInput): EvidenceRecordInput {
  const out: EvidenceRecordInput = {
    sourceName: input.sourceName,
    sourceURL: input.sourceURL,
    sourceHost: hostFromURL(input.sourceURL),
    sourceType: input.sourceType,
    jurisdiction: input.jurisdiction,
    scope: input.scope,
    title: input.title,
    summary: input.summary,
    snippets: input.snippets,
    tags: input.tags,
    trustScore: trustFor(input.sourceType),
    extractionConfidence: 82,
  };
  if (input.sourceRecordID) out.sourceRecordID = input.sourceRecordID;
  if (input.publishedAtISO) out.publishedAtISO = input.publishedAtISO;
  if (input.updatedAtISO) out.updatedAtISO = input.updatedAtISO;
  if (input.rawRecord) out.rawRecord = input.rawRecord;
  return out;
}

function skipped(connector: string, reason: string): SourceSweepResult {
  return { connector, inspected: 0, records: [], skippedReason: reason };
}

async function fetchJSON<T>(url: string, headers: Record<string, string>): Promise<T> {
  const res = await fetch(url, { headers, signal: AbortSignal.timeout(20_000) });
  if (!res.ok) throw new Error(`${new URL(url).host} returned ${res.status}`);
  return (await res.json()) as T;
}

function startDateTime(daysBack: number): string {
  return new Date(Date.now() - daysBack * 86_400_000).toISOString().replace(/\.\d{3}Z$/, "Z");
}

function dateToISO(value: string | undefined | null): string | undefined {
  if (!value) return undefined;
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) return undefined;
  return new Date(parsed).toISOString();
}

function snippetList(entries: [string, string | undefined | null][]): EvidenceSnippet[] {
  return entries
    .filter((entry): entry is [string, string] => Boolean(entry[1]))
    .map(([label, text]) => ({ label, text: text.slice(0, 400) }));
}

function compactRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>;
}

function trustFor(sourceType: string): number {
  if (sourceType.includes("official-api")) return 92;
  return 78;
}

function splitEnv(value: string): string[] {
  return value
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function appendPath(base: string, path: string): string {
  return `${base.replace(/\/+$/, "")}/${path.replace(/^\/+/, "")}`;
}

function billPublicURL(bill: CongressBill): string {
  if (bill.url?.includes("congress.gov")) return bill.url;
  const congress = bill.congress ? `${bill.congress}th-congress` : "";
  const type = billTypePath(bill.type);
  if (congress && type && bill.number) return `https://www.congress.gov/bill/${congress}/${type}/${bill.number}`;
  return "https://www.congress.gov/";
}

function billTypePath(type: string | undefined): string {
  const normalized = (type ?? "").toLowerCase();
  const map: Record<string, string> = {
    hr: "house-bill",
    hres: "house-resolution",
    hjres: "house-joint-resolution",
    hconres: "house-concurrent-resolution",
    s: "senate-bill",
    sres: "senate-resolution",
    sjres: "senate-joint-resolution",
    sconres: "senate-concurrent-resolution",
  };
  return map[normalized] ?? normalized;
}

interface CongressBillsResponse {
  bills?: CongressBill[];
}

interface CongressBill {
  congress?: number;
  number?: string;
  title?: string;
  type?: string;
  url?: string;
  updateDate?: string;
  latestAction?: { actionDate?: string; text?: string };
}

interface GovInfoCollectionResponse {
  packages?: {
    packageId?: string;
    title?: string;
    collectionCode?: string;
    dateIssued?: string;
    lastModified?: string;
    packageLink?: string;
    detailsLink?: string;
  }[];
}

interface RegulationsDocumentsResponse {
  data?: {
    id: string;
    attributes?: {
      title?: string;
      agencyId?: string;
      docketId?: string;
      documentType?: string;
      postedDate?: string;
      modifyDate?: string;
      commentEndDate?: string;
    };
  }[];
}

interface OpenStatesBillsResponse {
  results?: {
    id?: string;
    identifier?: string;
    title?: string;
    session?: string;
    jurisdiction?: { name?: string };
    latest_action_description?: string;
    first_action_date?: string;
    updated_at?: string;
    openstates_url?: string;
    sources?: { url?: string }[];
  }[];
}

interface SocrataCatalogResponse {
  results?: {
    permalink?: string;
    resource?: {
      id?: string;
      name?: string;
      description?: string;
      attribution?: string;
      createdAt?: string;
      updatedAt?: string;
    };
  }[];
}

interface Open311Service {
  service_code?: string;
  service_name?: string;
  description?: string;
  metadata?: string;
}
