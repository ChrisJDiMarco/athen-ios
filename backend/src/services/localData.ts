import { config } from "../config.js";

/**
 * Wraps two layers of hyperlocal civic data:
 *   - Socrata Open Data — city/state portals expose datasets like 311
 *     complaints, crime, contracts, budgets through a standard SODA API.
 *   - Open311 — standardized API for submitting + querying 311 service
 *     requests across thousands of US municipalities.
 *
 * Both are config-driven so adding a city is one env var, not a code change.
 */

const SOCRATA_DEFAULT_LIMIT = 25;

export interface SocrataDataset {
  domain: string;
  id: string;
  name: string;
  description?: string;
  recordCount: number;
  updatedAtISO?: string;
}

export interface SocrataRow {
  [field: string]: unknown;
}

export interface Open311Endpoint {
  jurisdiction: string;
  baseURL: string;
}

export interface Open311ServiceRequest {
  serviceRequestId: string;
  status: string;
  serviceName: string;
  description?: string;
  agencyResponsible?: string;
  address?: string;
  requestedDatetime?: string;
}

export class LocalDataService {
  /** Catalog domains we'll search for datasets. Comma-separated env. */
  private socrataDomains: string[];
  /** Per-jurisdiction Open311 endpoints. Pipe-separated env: name=baseURL|name=baseURL. */
  private open311Endpoints: Open311Endpoint[];

  constructor() {
    this.socrataDomains = (config.SOCRATA_CATALOG_DOMAINS ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    if (this.socrataDomains.length === 0) {
      // Sensible defaults — major cities with rich Socrata coverage.
      this.socrataDomains = [
        "data.cityofnewyork.us",
        "data.cityofchicago.org",
        "data.lacity.org",
        "data.austintexas.gov",
        "data.seattle.gov",
        "data.sfgov.org",
      ];
    }
    this.open311Endpoints = parseOpen311(config.OPEN311_ENDPOINTS ?? "");
  }

  get socrataEnabled(): boolean {
    return this.socrataDomains.length > 0;
  }

  get open311Enabled(): boolean {
    return this.open311Endpoints.length > 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Socrata — catalog search + dataset query

  async findDatasets(query: string, limit: number = 10): Promise<SocrataDataset[]> {
    if (!this.socrataEnabled) return [];
    const url = new URL("https://api.us.socrata.com/api/catalog/v1");
    url.searchParams.set("q", query);
    url.searchParams.set("limit", String(limit));
    for (const d of this.socrataDomains) {
      url.searchParams.append("domains", d);
    }
    if (config.SOCRATA_APP_TOKEN) {
      url.searchParams.set("$$app_token", config.SOCRATA_APP_TOKEN);
    }
    try {
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) return [];
      const json = (await res.json()) as SocrataCatalogResponse;
      return (json.results ?? []).map((r) => {
        const dataset: SocrataDataset = {
          domain: r.metadata?.domain ?? "",
          id: r.resource?.id ?? "",
          name: r.resource?.name ?? "Untitled dataset",
          recordCount: Number(r.resource?.columns_field_name?.length ?? 0),
        };
        if (r.resource?.description) dataset.description = r.resource.description;
        if (r.resource?.updatedAt) dataset.updatedAtISO = r.resource.updatedAt;
        return dataset;
      });
    } catch {
      return [];
    }
  }

  async fetchRows(domain: string, datasetId: string, limit: number = SOCRATA_DEFAULT_LIMIT): Promise<SocrataRow[]> {
    const url = new URL(`https://${domain}/resource/${datasetId}.json`);
    url.searchParams.set("$limit", String(limit));
    if (config.SOCRATA_APP_TOKEN) {
      url.searchParams.set("$$app_token", config.SOCRATA_APP_TOKEN);
    }
    try {
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) return [];
      return (await res.json()) as SocrataRow[];
    } catch {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Open311 — lookup recent requests near a ZIP

  /** Which Open311 endpoints we have configured. */
  listOpen311Jurisdictions(): Open311Endpoint[] {
    return this.open311Endpoints.slice();
  }

  /** Pick the best-matching endpoint for a ZIP, if any. */
  endpointForZip(zip: string): Open311Endpoint | null {
    // Naive match by name keyword for now. Operators can refine via env.
    const prefix3 = zip.slice(0, 3);
    const map: Record<string, string> = {
      "191": "philadelphia", "190": "philadelphia",
      "100": "nyc", "101": "nyc", "102": "nyc", "112": "nyc",
      "606": "chicago",
      "021": "boston",
      "900": "losangeles", "901": "losangeles",
      "200": "dc",
      "981": "seattle",
      "972": "portland",
      "941": "sf",
      "770": "houston",
      "787": "austin",
    };
    const wanted = map[prefix3];
    if (!wanted) return null;
    return this.open311Endpoints.find((e) => e.jurisdiction.toLowerCase().includes(wanted)) ?? null;
  }

  async recentRequests(zip: string, limit: number = 10): Promise<Open311ServiceRequest[]> {
    const endpoint = this.endpointForZip(zip);
    if (!endpoint) return [];
    const url = new URL(`${endpoint.baseURL.replace(/\/$/, "")}/requests.json`);
    url.searchParams.set("page_size", String(limit));
    try {
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) return [];
      const json = (await res.json()) as RawOpen311Request[];
      return json.slice(0, limit).map((r) => {
        const req: Open311ServiceRequest = {
          serviceRequestId: r.service_request_id ?? "",
          status: r.status ?? "open",
          serviceName: r.service_name ?? "Service request",
        };
        if (r.description) req.description = r.description;
        if (r.agency_responsible) req.agencyResponsible = r.agency_responsible;
        if (r.address) req.address = r.address;
        if (r.requested_datetime) req.requestedDatetime = r.requested_datetime;
        return req;
      });
    } catch {
      return [];
    }
  }
}

function parseOpen311(raw: string): Open311Endpoint[] {
  if (!raw.trim()) return [];
  return raw
    .split("|")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      const eq = part.indexOf("=");
      if (eq === -1) return null;
      const jurisdiction = part.slice(0, eq).trim();
      const baseURL = part.slice(eq + 1).trim();
      if (!jurisdiction || !baseURL) return null;
      return { jurisdiction, baseURL };
    })
    .filter((e): e is Open311Endpoint => e !== null);
}

interface SocrataCatalogResponse {
  results?: Array<{
    metadata?: { domain?: string };
    resource?: {
      id?: string;
      name?: string;
      description?: string;
      updatedAt?: string;
      columns_field_name?: string[];
    };
  }>;
}

interface RawOpen311Request {
  service_request_id?: string;
  status?: string;
  service_name?: string;
  description?: string;
  agency_responsible?: string;
  address?: string;
  requested_datetime?: string;
}
