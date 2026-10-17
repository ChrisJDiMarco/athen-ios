import { CivicError, AddressNotFoundError } from "../lib/errors.js";
import zipPrefixes from "../data/us-state-zip-prefixes.json" with { type: "json" };

const CENSUS_BASE = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress";

interface CensusMatch {
  matchedAddress: string;
  coordinates: { x: number; y: number };
  addressComponents: { zip: string; city: string; state: string };
}

interface CensusResponse {
  result: { addressMatches: CensusMatch[] };
}

export interface ResolvedLocation {
  zipCode: string;
  stateCode: string;
  stateName: string;
  city?: string;
  latitude?: number;
  longitude?: number;
  normalized?: string;
  source: "zip-prefix" | "census-geocoder";
}

export interface LocationResolver {
  resolveFromZip(zip: string): Promise<ResolvedLocation>;
  resolveFromAddress(rawAddress: string): Promise<ResolvedLocation>;
}

const ZIP_REGEX = /^(\d{5})(-\d{4})?$/;

export class CompositeLocationResolver implements LocationResolver {
  constructor(private readonly fetchImpl: typeof fetch = fetch) {}

  async resolveFromZip(zip: string): Promise<ResolvedLocation> {
    if (!ZIP_REGEX.test(zip)) {
      throw new CivicError("invalid_zip", `ZIP must be 5 digits. Got: ${zip}`, 422);
    }

    const fiveDigit = zip.slice(0, 5);
    const prefix = fiveDigit.slice(0, 3);
    const entry = (zipPrefixes.prefixes as Record<string, { state: string; name: string } | undefined>)[prefix];
    if (!entry) {
      throw new CivicError(
        "zip_not_recognized",
        `ZIP prefix ${prefix} is not assigned to a US state.`,
        422,
      );
    }

    return {
      zipCode: fiveDigit,
      stateCode: entry.state,
      stateName: entry.name,
      source: "zip-prefix",
    };
  }

  async resolveFromAddress(rawAddress: string): Promise<ResolvedLocation> {
    const url = new URL(CENSUS_BASE);
    url.searchParams.set("address", rawAddress);
    url.searchParams.set("benchmark", "Public_AR_Current");
    url.searchParams.set("format", "json");

    const res = await this.fetchImpl(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) {
      throw new AddressNotFoundError(rawAddress);
    }

    const json = (await res.json()) as CensusResponse;
    const match = json.result.addressMatches[0];
    if (!match) {
      throw new AddressNotFoundError(rawAddress);
    }

    const stateCode = match.addressComponents.state;
    const fallback = (zipPrefixes.prefixes as Record<string, { state: string; name: string } | undefined>)[
      match.addressComponents.zip.slice(0, 3)
    ];
    const stateName = fallback?.name ?? stateCode;

    return {
      zipCode: match.addressComponents.zip,
      stateCode,
      stateName,
      city: match.addressComponents.city,
      latitude: match.coordinates.y,
      longitude: match.coordinates.x,
      normalized: match.matchedAddress,
      source: "census-geocoder",
    };
  }
}
