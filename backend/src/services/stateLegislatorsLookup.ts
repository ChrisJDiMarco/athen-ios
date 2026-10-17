import type { ResolvedOfficial } from "../lib/types.js";
import type { ResolvedLocation } from "./locationResolver.js";

const OPEN_STATES_BASE = "https://v3.openstates.org/people.geo";

interface OpenStatesPerson {
  name: string;
  party?: string;
  current_role?: {
    title?: string;
    district?: string | number;
    org_classification?: string;
  };
  email?: string;
  offices?: { name?: string; voice?: string; email?: string }[];
}

interface OpenStatesGeoResponse {
  results: OpenStatesPerson[];
}

export interface StateLegislatorsLookup {
  forLocation(location: ResolvedLocation): Promise<{
    senate: ResolvedOfficial[];
    house: ResolvedOfficial[];
  }>;
}

export class OpenStatesLegislatorsLookup implements StateLegislatorsLookup {
  constructor(
    private readonly apiKey: string | undefined,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  async forLocation(location: ResolvedLocation): Promise<{
    senate: ResolvedOfficial[];
    house: ResolvedOfficial[];
  }> {
    if (!this.apiKey) {
      return { senate: [], house: [] };
    }
    if (location.latitude === undefined || location.longitude === undefined) {
      return { senate: [], house: [] };
    }

    const url = new URL(OPEN_STATES_BASE);
    url.searchParams.set("lat", String(location.latitude));
    url.searchParams.set("lng", String(location.longitude));
    url.searchParams.set("include", "offices");

    const res = await this.fetchImpl(url, {
      headers: { "X-API-KEY": this.apiKey },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) {
      return { senate: [], house: [] };
    }

    const json = (await res.json()) as OpenStatesGeoResponse;
    const senate: ResolvedOfficial[] = [];
    const house: ResolvedOfficial[] = [];

    for (const person of json.results ?? []) {
      const role = person.current_role;
      if (!role) continue;

      const email =
        person.email ?? person.offices?.find((o) => o.email)?.email ?? `placeholder@civic-os.example`;
      const official: ResolvedOfficial = {
        name: person.name,
        title: role.title ?? "State Legislator",
        district: role.district !== undefined ? String(role.district) : "Unknown district",
        email,
        source: "openstates.org",
        channel: email.endsWith("@civic-os.example") ? "contact-form-queue" : "email",
      };

      const classification = role.org_classification?.toLowerCase();
      if (classification === "upper") {
        senate.push(official);
      } else if (classification === "lower") {
        house.push(official);
      }
    }

    return { senate, house };
  }
}
