import { readFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import booleanPointInPolygon from "@turf/boolean-point-in-polygon";
import { point } from "@turf/helpers";
import type { Feature, FeatureCollection, Polygon, MultiPolygon } from "geojson";
import { NoOfficialForDistrictError, CivicError } from "../lib/errors.js";
import type { ResolvedOfficial } from "../lib/types.js";
import type { ResolvedLocation } from "./locationResolver.js";
import type { FederalOfficialsLookup } from "./federalOfficialsLookup.js";
import type { StateLegislatorsLookup } from "./stateLegislatorsLookup.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

interface PhillyOfficialEntry {
  name: string;
  title: string;
  district: string;
  email: string;
  source: string;
}

interface JurisdictionEntry extends Partial<PhillyOfficialEntry> {
  useDistrict?: boolean;
}

interface PhillyOfficialsFile {
  districts: Record<string, PhillyOfficialEntry>;
  byJurisdiction: Record<string, JurisdictionEntry>;
}

type DistrictFeature = Feature<Polygon | MultiPolygon, { DISTRICT?: string | number; district?: string | number }>;

export interface OfficialResolver {
  resolve(jurisdiction: string, location: ResolvedLocation): Promise<ResolvedOfficial>;
  treeFor(location: ResolvedLocation): Promise<OfficialsTree>;
}

export interface OfficialsTree {
  federalSenators: ResolvedOfficial[];
  federalHouseRep?: ResolvedOfficial;
  stateSenators: ResolvedOfficial[];
  stateRepresentatives: ResolvedOfficial[];
  local: ResolvedOfficial[];
}

export class JurisdictionAwareOfficialResolver implements OfficialResolver {
  private constructor(
    private readonly phillyDistricts: FeatureCollection<Polygon | MultiPolygon> | undefined,
    private readonly phillyOfficials: PhillyOfficialsFile,
    private readonly federal: FederalOfficialsLookup,
    private readonly stateLegislators: StateLegislatorsLookup,
  ) {}

  static async load(args: {
    federal: FederalOfficialsLookup;
    stateLegislators: StateLegislatorsLookup;
  }): Promise<JurisdictionAwareOfficialResolver> {
    const geoPath = resolve(__dirname, "..", "..", "data", "philly-council-districts.geojson");
    const officialsPath = resolve(__dirname, "..", "data", "philly-officials.json");

    let phillyDistricts: FeatureCollection<Polygon | MultiPolygon> | undefined;
    try {
      const geoText = await readFile(geoPath, "utf8");
      phillyDistricts = JSON.parse(geoText) as FeatureCollection<Polygon | MultiPolygon>;
    } catch {
      phillyDistricts = undefined;
    }

    const phillyOfficials = JSON.parse(await readFile(officialsPath, "utf8")) as PhillyOfficialsFile;
    return new JurisdictionAwareOfficialResolver(
      phillyDistricts,
      phillyOfficials,
      args.federal,
      args.stateLegislators,
    );
  }

  async resolve(jurisdiction: string, location: ResolvedLocation): Promise<ResolvedOfficial> {
    const normalized = jurisdiction.trim();

    if (normalized === "U.S. Senate") {
      const senators = this.federal.senators(location);
      const senior = senators.find((s) => s.title.includes("Senator")) ?? senators[0];
      if (!senior) throw new NoOfficialForDistrictError(`U.S. Senate for ${location.stateCode}`);
      return senior;
    }

    if (normalized === "U.S. House of Representatives") {
      const rep = this.federal.houseRepresentative(location);
      if (!rep) throw new NoOfficialForDistrictError(`U.S. House for ${location.stateCode}`);
      return rep;
    }

    if (/State Senate$/i.test(normalized)) {
      const { senate } = await this.stateLegislators.forLocation(location);
      const first = senate[0];
      if (!first) {
        throw new CivicError(
          "state_legislators_unavailable",
          "Set OPENSTATES_API_KEY and provide a full address (not ZIP-only) to file with state legislators.",
          422,
        );
      }
      return first;
    }

    if (/State (House|Assembly|Representatives)$/i.test(normalized)) {
      const { house } = await this.stateLegislators.forLocation(location);
      const first = house[0];
      if (!first) {
        throw new CivicError(
          "state_legislators_unavailable",
          "Set OPENSTATES_API_KEY and provide a full address (not ZIP-only) to file with state legislators.",
          422,
        );
      }
      return first;
    }

    const jurisdictionEntry = this.phillyOfficials.byJurisdiction[normalized];
    if (jurisdictionEntry && jurisdictionEntry.useDistrict !== true) {
      return this.fromJurisdiction(normalized, jurisdictionEntry);
    }

    if (
      jurisdictionEntry?.useDistrict === true ||
      normalized === "Philadelphia City Council"
    ) {
      const districtNumber = this.phillyDistrictFor(location);
      if (districtNumber === undefined) {
        throw new NoOfficialForDistrictError("unknown (not in Philadelphia council districts)");
      }
      const entry = this.phillyOfficials.districts[districtNumber];
      if (!entry) throw new NoOfficialForDistrictError(districtNumber);
      return { ...entry, channel: "email" };
    }

    // Federal regulatory items (Cabinet departments, EPA, etc.) don't
    // map to a single emailable official — public comments go through
    // regulations.gov / the Federal Register. Surface a friendly error
    // so the iOS app can swap the action with "Comment on source."
    if (/Department|Agency|Service|Administration|Commission|Bureau|Authority/i.test(normalized)) {
      throw new CivicError(
        "regulatory_no_filing_official",
        `${normalized} rules accept public comments on regulations.gov instead of direct email. Open the source link to submit one.`,
        422,
      );
    }
    throw new NoOfficialForDistrictError(normalized);
  }

  async treeFor(location: ResolvedLocation): Promise<OfficialsTree> {
    const stateLegislators = await this.stateLegislators.forLocation(location);
    const tree: OfficialsTree = {
      federalSenators: this.federal.senators(location),
      stateSenators: stateLegislators.senate,
      stateRepresentatives: stateLegislators.house,
      local: [],
    };

    const houseRep = this.federal.houseRepresentative(location);
    if (houseRep) tree.federalHouseRep = houseRep;

    const phillyDistrict = this.phillyDistrictFor(location);
    if (phillyDistrict !== undefined) {
      const entry = this.phillyOfficials.districts[phillyDistrict];
      if (entry) tree.local.push({ ...entry });
    }

    return tree;
  }

  private fromJurisdiction(jurisdiction: string, entry: JurisdictionEntry): ResolvedOfficial {
    const { name, title, district, email, source } = entry;
    if (!name || !title || !district || !email || !source) {
      throw new NoOfficialForDistrictError(jurisdiction);
    }
    return { name, title, district, email, source, channel: "email" };
  }

  private phillyDistrictFor(location: ResolvedLocation): string | undefined {
    if (!this.phillyDistricts) return undefined;
    if (location.latitude === undefined || location.longitude === undefined) return undefined;
    if (location.stateCode !== "PA") return undefined;

    const pt = point([location.longitude, location.latitude]);
    for (const feature of this.phillyDistricts.features) {
      if (booleanPointInPolygon(pt, feature as DistrictFeature)) {
        const raw =
          (feature.properties as DistrictFeature["properties"] | null)?.DISTRICT ??
          (feature.properties as DistrictFeature["properties"] | null)?.district;
        if (raw === undefined || raw === null) continue;
        return String(raw);
      }
    }
    return undefined;
  }
}
