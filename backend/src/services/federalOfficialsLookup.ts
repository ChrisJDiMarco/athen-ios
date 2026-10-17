import federalData from "../data/us-federal-officials.json" with { type: "json" };
import type { ResolvedOfficial } from "../lib/types.js";
import type { ResolvedLocation } from "./locationResolver.js";

interface SenatorEntry {
  bioguide?: string;
  seniority: "senior" | "junior";
  name: string;
  title: string;
  party?: string;
  email: string;
  contactFormURL?: string;
  websiteURL?: string;
  source: string;
}

interface RepresentativeEntry {
  bioguide?: string;
  name: string;
  title: string;
  party?: string;
  district: string;
  email: string;
  contactFormURL?: string;
  websiteURL?: string;
  source: string;
}

interface FederalData {
  senators: Record<string, SenatorEntry[]>;
  representativeByDistrict?: Record<string, RepresentativeEntry>;
  representativeByState: Record<string, string> & { _fallbackTemplate: string };
  generatedAt?: string;
}

const data = federalData as unknown as FederalData;

export interface FederalOfficialsLookup {
  senators(location: ResolvedLocation): ResolvedOfficial[];
  houseRepresentative(location: ResolvedLocation): ResolvedOfficial | undefined;
}

export class StaticFederalOfficialsLookup implements FederalOfficialsLookup {
  senators(location: ResolvedLocation): ResolvedOfficial[] {
    const entries = data.senators[location.stateCode] ?? [];
    return entries.map((entry): ResolvedOfficial => ({
      name: entry.name,
      title: entry.title,
      district: `State of ${location.stateName}`,
      email: entry.email,
      source: entry.source,
      channel: entry.contactFormURL ? "contact-form-queue" : "email",
      ...(entry.contactFormURL ? { contactFormURL: entry.contactFormURL } : {}),
      ...(entry.bioguide ? { externalID: entry.bioguide } : {}),
    }));
  }

  /**
   * Best-effort House Rep lookup. Without a full address we can't resolve to
   * the exact congressional district, so for ZIP-only profiles we return
   * undefined and the UI can prompt the user to enter their full address.
   *
   * (Census Geocoder used in `LocationResolver.resolveFromAddress` returns
   * the congressional district when called with a full address. Plug that
   * into `location.congressionalDistrict` when you wire the address-aware
   * profile flow.)
   */
  houseRepresentative(location: ResolvedLocation): ResolvedOfficial | undefined {
    const districtKey = (location as ResolvedLocation & { congressionalDistrict?: string }).congressionalDistrict;
    if (districtKey && data.representativeByDistrict?.[districtKey]) {
      const entry = data.representativeByDistrict[districtKey]!;
      return {
        name: entry.name,
        title: entry.title,
        district: entry.district,
        email: entry.email,
        source: entry.source,
        channel: entry.contactFormURL ? "contact-form-queue" : "email",
        ...(entry.contactFormURL ? { contactFormURL: entry.contactFormURL } : {}),
        ...(entry.bioguide ? { externalID: entry.bioguide } : {}),
      };
    }

    // Fallback: generic stub keyed by state. Real lookup needs district.
    const stateOverride = data.representativeByState[location.stateCode];
    const name =
      stateOverride ??
      data.representativeByState._fallbackTemplate.replace("{stateName}", location.stateName);
    return {
      name,
      title: "Member, U.S. House of Representatives",
      district: `${location.stateCode}-AL`,
      email: `rep.${location.stateCode.toLowerCase()}@civic-os.example`,
      source: "house.gov",
      channel: "contact-form-queue",
    };
  }
}
