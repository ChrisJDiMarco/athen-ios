import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import yaml from "js-yaml";
import { config } from "../config.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Master directory of US elected officials.
 *
 * Federal layer: downloads + caches the unitedstates/congress-legislators
 * JSON feeds (Public Domain, community-maintained, refreshed daily). One
 * file for current members, one for their verified social handles.
 *
 * Executive branch: small static seed (President, VP, Governors). Updated
 * by hand at election cycles — these positions don't churn weekly.
 *
 * State layer: live wrap of OpenStates /people. Lazily fetched per state.
 *
 * Local layer: deferred to a future iteration (Legistar council members
 * have inconsistent metadata; better to surface that via a separate path).
 */

// unitedstates/congress-legislators now ships only YAML. We fetch from
// raw.githubusercontent.com (the canonical mirror) and parse with js-yaml.
const LEGISLATORS_CURRENT_URL = "https://raw.githubusercontent.com/unitedstates/congress-legislators/refs/heads/main/legislators-current.yaml";
const LEGISLATORS_SOCIAL_URL = "https://raw.githubusercontent.com/unitedstates/congress-legislators/refs/heads/main/legislators-social-media.yaml";
const PHOTO_BASE = "https://bioguide.congress.gov/bioguide/photo";

export type OfficialLevel = "federal" | "state" | "local";

export interface DirectoryOffice {
  type: "dc" | "district" | "state-capitol" | "city-hall" | "other";
  label: string;
  address?: string;
  phone?: string;
  fax?: string;
}

export interface DirectorySocials {
  twitter?: string;
  facebook?: string;
  instagram?: string;
  youtube?: string;
  linkedin?: string;
  tiktok?: string;
}

export interface DirectoryOfficial {
  id: string;                    // stable per-official key (bioguide for fed, openstates id for state)
  level: OfficialLevel;
  name: string;
  photoURL?: string;
  role: string;                  // "U.S. Senator", "President", "State Senator", "Governor"
  party?: string;
  jurisdiction: string;          // "United States", "Pennsylvania", "Philadelphia"
  state?: string;                // 2-letter
  district?: string;             // "PA-12", "District 5"
  chamber?: "senate" | "house" | "executive" | "judicial" | "other";
  termStartISO?: string;
  termEndISO?: string;
  bioBirthday?: string;
  gender?: string;
  websites: string[];
  offices: DirectoryOffice[];
  socials: DirectorySocials;
  externalIDs: {
    bioguide?: string;
    govtrack?: number;
    opensecrets?: string;
    fec?: string[];
    votesmart?: number;
    wikipedia?: string;
    ballotpedia?: string;
    wikidata?: string;
    openstates?: string;
  };
  /** Free-text bio paragraph when available. */
  bio?: string;
  fetchedAtISO: string;
}

interface DirectoryCache {
  version: 1;
  federal: DirectoryOfficial[];
  /** state legislators keyed by stateCode. */
  stateByCode: Record<string, DirectoryOfficial[]>;
  fetchedAtISO?: string;
}

export class OfficialsDirectoryService {
  private cache: DirectoryCache;
  private readonly cachePath: string;

  private constructor(cache: DirectoryCache, cachePath: string) {
    this.cache = cache;
    this.cachePath = cachePath;
  }

  static async load(cachePath?: string): Promise<OfficialsDirectoryService> {
    const path = cachePath ?? resolve(__dirname, "..", "..", "data", "officials-cache.json");
    let cache: DirectoryCache = { version: 1, federal: [], stateByCode: {} };
    try {
      const text = await readFile(path, "utf8");
      const parsed = JSON.parse(text) as DirectoryCache;
      if (parsed.version === 1 && Array.isArray(parsed.federal)) cache = parsed;
    } catch {
      // first run
    }
    return new OfficialsDirectoryService(cache, path);
  }

  /** Returns the cached federal directory. Triggers a refresh in the
   *  background if the data is older than 7 days OR empty. */
  federal(): DirectoryOfficial[] {
    if (this.cache.federal.length === 0 || this.isStale()) {
      void this.refreshFederal();
    }
    return [...EXECUTIVE_OFFICIALS, ...this.cache.federal];
  }

  /** Force-refresh and return the new list. */
  async federalRefreshed(): Promise<DirectoryOfficial[]> {
    await this.refreshFederal();
    return [...EXECUTIVE_OFFICIALS, ...this.cache.federal];
  }

  /** Returns governor + state legislators for a state. State legislators
   *  fetched from OpenStates lazily; cached per-state. */
  async state(stateCode: string): Promise<DirectoryOfficial[]> {
    const code = stateCode.toUpperCase();
    const governor = GOVERNORS.find((g) => g.state === code);
    const legislators = this.cache.stateByCode[code] ?? [];
    if (legislators.length === 0) {
      const fetched = await this.fetchStateLegislators(code);
      if (fetched.length > 0) {
        this.cache.stateByCode[code] = fetched;
        void this.persist();
      }
    }
    const all: DirectoryOfficial[] = [];
    if (governor) all.push(governor);
    all.push(...(this.cache.stateByCode[code] ?? []));
    return all;
  }

  /** Find one official by id across federal + state caches. */
  findById(id: string): DirectoryOfficial | undefined {
    if (id.startsWith("exec:")) {
      return EXECUTIVE_OFFICIALS.find((o) => o.id === id);
    }
    if (id.startsWith("gov:")) {
      return GOVERNORS.find((o) => o.id === id);
    }
    const fed = this.cache.federal.find((o) => o.id === id);
    if (fed) return fed;
    for (const list of Object.values(this.cache.stateByCode)) {
      const hit = list.find((o) => o.id === id);
      if (hit) return hit;
    }
    return undefined;
  }

  /** Plain substring search across all loaded officials. */
  search(query: string): DirectoryOfficial[] {
    const q = query.toLowerCase().trim();
    if (q.length < 2) return [];
    const matches: DirectoryOfficial[] = [];
    const all = [
      ...EXECUTIVE_OFFICIALS,
      ...GOVERNORS,
      ...this.cache.federal,
      ...Object.values(this.cache.stateByCode).flat(),
    ];
    for (const o of all) {
      if (o.name.toLowerCase().includes(q) ||
          (o.role && o.role.toLowerCase().includes(q)) ||
          (o.state && o.state.toLowerCase().includes(q)) ||
          (o.district && o.district.toLowerCase().includes(q))) {
        matches.push(o);
        if (matches.length >= 30) break;
      }
    }
    return matches;
  }

  stats() {
    return {
      executive: EXECUTIVE_OFFICIALS.length,
      governors: GOVERNORS.length,
      federalCongress: this.cache.federal.length,
      statesLoaded: Object.keys(this.cache.stateByCode).length,
      stateLegislators: Object.values(this.cache.stateByCode).reduce((a, b) => a + b.length, 0),
      fetchedAtISO: this.cache.fetchedAtISO,
    };
  }

  private isStale(): boolean {
    if (!this.cache.fetchedAtISO) return true;
    const age = Date.now() - Date.parse(this.cache.fetchedAtISO);
    return age > 7 * 86_400_000;
  }

  /** Pull the latest federal members + social handles, merge, replace cache. */
  async refreshFederal(): Promise<void> {
    try {
      const [membersRes, socialRes] = await Promise.all([
        fetch(LEGISLATORS_CURRENT_URL, { signal: AbortSignal.timeout(45_000) }),
        fetch(LEGISLATORS_SOCIAL_URL, { signal: AbortSignal.timeout(45_000) }),
      ]);
      if (!membersRes.ok) throw new Error(`legislators-current HTTP ${membersRes.status}`);
      const membersYaml = await membersRes.text();
      const members = yaml.load(membersYaml) as RawLegislator[];
      let social: RawSocial[] = [];
      if (socialRes.ok) {
        const socialYaml = await socialRes.text();
        social = (yaml.load(socialYaml) as RawSocial[]) ?? [];
      }
      const socialMap = new Map<string, RawSocial["social"]>();
      for (const s of social) {
        const bg = s.id?.bioguide;
        if (bg) socialMap.set(bg, s.social);
      }
      const normalized = (members ?? []).map((m) => normalizeFederalMember(m, socialMap.get(m.id?.bioguide ?? "")));
      this.cache.federal = normalized;
      this.cache.fetchedAtISO = new Date().toISOString();
      await this.persist();
    } catch (err) {
      // Soft fail — keep whatever cache we have so the iOS surface still
      // renders. The caller can retry.
      console.error("officials directory refresh failed", err);
    }
  }

  private async fetchStateLegislators(stateCode: string): Promise<DirectoryOfficial[]> {
    if (!config.OPENSTATES_API_KEY) return [];
    const jurisdiction = stateNameForCode(stateCode);
    if (!jurisdiction) return [];
    const url = new URL("https://v3.openstates.org/people");
    url.searchParams.set("jurisdiction", jurisdiction);
    url.searchParams.set("per_page", "75");
    url.searchParams.set("apikey", config.OPENSTATES_API_KEY);

    try {
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(25_000),
      });
      if (!res.ok) return [];
      const json = (await res.json()) as { results?: RawOpenStatesPerson[] };
      return (json.results ?? []).map((p) => normalizeStatePerson(p, stateCode, jurisdiction));
    } catch {
      return [];
    }
  }

  private async persist(): Promise<void> {
    try {
      await mkdir(dirname(this.cachePath), { recursive: true });
      await writeFile(this.cachePath, JSON.stringify(this.cache, null, 2), "utf8");
    } catch {
      // non-fatal
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Normalizers + wire shapes

function normalizeFederalMember(m: RawLegislator, social?: RawSocial["social"]): DirectoryOfficial {
  const term = m.terms?.[m.terms.length - 1];
  const isSenator = term?.type === "sen";
  const state = term?.state ?? "";
  const district = isSenator ? `${state} (Senate)` : term?.district != null ? `${state}-${String(term.district).padStart(2, "0")}` : state;
  const offices: DirectoryOffice[] = [];
  if (term?.office) {
    offices.push({
      type: "dc",
      label: "Washington D.C. office",
      address: term.office,
      ...(term.phone ? { phone: term.phone } : {}),
    });
  }
  const externalIDs: DirectoryOfficial["externalIDs"] = {};
  if (m.id?.bioguide) externalIDs.bioguide = m.id.bioguide;
  if (m.id?.govtrack) externalIDs.govtrack = m.id.govtrack;
  if (m.id?.opensecrets) externalIDs.opensecrets = m.id.opensecrets;
  if (m.id?.fec) externalIDs.fec = m.id.fec;
  if (m.id?.votesmart) externalIDs.votesmart = m.id.votesmart;
  if (m.id?.wikipedia) externalIDs.wikipedia = m.id.wikipedia;
  if (m.id?.ballotpedia) externalIDs.ballotpedia = m.id.ballotpedia;
  if (m.id?.wikidata) externalIDs.wikidata = m.id.wikidata;
  const out: DirectoryOfficial = {
    id: `fed:${m.id?.bioguide ?? m.id?.govtrack ?? m.name?.official_full ?? Math.random().toString(36)}`,
    level: "federal",
    name: m.name?.official_full ?? `${m.name?.first ?? ""} ${m.name?.last ?? ""}`.trim(),
    role: isSenator ? "U.S. Senator" : "U.S. Representative",
    jurisdiction: "United States",
    chamber: isSenator ? "senate" : "house",
    websites: term?.url ? [term.url] : [],
    offices,
    socials: normalizeSocials(social),
    externalIDs,
    fetchedAtISO: new Date().toISOString(),
  };
  if (m.id?.bioguide) out.photoURL = `${PHOTO_BASE}/${m.id.bioguide[0]}/${m.id.bioguide}.jpg`;
  if (term?.party) out.party = term.party;
  if (state) out.state = state;
  if (district) out.district = district;
  if (term?.start) out.termStartISO = term.start;
  if (term?.end) out.termEndISO = term.end;
  if (m.bio?.birthday) out.bioBirthday = m.bio.birthday;
  if (m.bio?.gender) out.gender = m.bio.gender;
  return out;
}

function normalizeStatePerson(p: RawOpenStatesPerson, stateCode: string, jurisdiction: string): DirectoryOfficial {
  const role = p.current_role?.title ?? (p.current_role?.org_classification === "lower" ? "State Representative" : "State Senator");
  const chamber: "senate" | "house" | undefined = p.current_role?.org_classification === "upper" ? "senate"
    : p.current_role?.org_classification === "lower" ? "house"
    : undefined;
  const offices: DirectoryOffice[] = [];
  for (const o of p.offices ?? []) {
    const office: DirectoryOffice = {
      type: o.classification === "capitol" ? "state-capitol" : "district",
      label: o.name ?? (o.classification === "capitol" ? "Capitol office" : "District office"),
    };
    if (o.address) office.address = o.address;
    if (o.voice) office.phone = o.voice;
    if (o.fax) office.fax = o.fax;
    offices.push(office);
  }
  const out: DirectoryOfficial = {
    id: `os:${p.id}`,
    level: "state",
    name: p.name ?? "Unknown",
    role,
    jurisdiction,
    state: stateCode,
    websites: p.links?.map((l) => l.url).filter(Boolean) ?? [],
    offices,
    socials: {},
    externalIDs: { openstates: p.id },
    fetchedAtISO: new Date().toISOString(),
  };
  if (chamber) out.chamber = chamber;
  if (p.image) out.photoURL = p.image;
  if (p.party) out.party = p.party;
  if (p.current_role?.district) out.district = `District ${p.current_role.district}`;
  return out;
}

function normalizeSocials(raw?: RawSocial["social"]): DirectorySocials {
  if (!raw) return {};
  const out: DirectorySocials = {};
  if (raw.twitter) out.twitter = raw.twitter;
  if (raw.facebook) out.facebook = raw.facebook;
  if (raw.instagram) out.instagram = raw.instagram;
  if (raw.youtube) out.youtube = raw.youtube;
  if (raw.linkedin) out.linkedin = raw.linkedin;
  if (raw.tiktok) out.tiktok = raw.tiktok;
  return out;
}

function stateNameForCode(code: string): string | null {
  return STATE_NAME_BY_CODE[code.toUpperCase()] ?? null;
}

const STATE_NAME_BY_CODE: Record<string, string> = {
  AL: "Alabama", AK: "Alaska", AZ: "Arizona", AR: "Arkansas", CA: "California",
  CO: "Colorado", CT: "Connecticut", DE: "Delaware", FL: "Florida", GA: "Georgia",
  HI: "Hawaii", ID: "Idaho", IL: "Illinois", IN: "Indiana", IA: "Iowa",
  KS: "Kansas", KY: "Kentucky", LA: "Louisiana", ME: "Maine", MD: "Maryland",
  MA: "Massachusetts", MI: "Michigan", MN: "Minnesota", MS: "Mississippi", MO: "Missouri",
  MT: "Montana", NE: "Nebraska", NV: "Nevada", NH: "New Hampshire", NJ: "New Jersey",
  NM: "New Mexico", NY: "New York", NC: "North Carolina", ND: "North Dakota", OH: "Ohio",
  OK: "Oklahoma", OR: "Oregon", PA: "Pennsylvania", RI: "Rhode Island", SC: "South Carolina",
  SD: "South Dakota", TN: "Tennessee", TX: "Texas", UT: "Utah", VT: "Vermont",
  VA: "Virginia", WA: "Washington", WV: "West Virginia", WI: "Wisconsin", WY: "Wyoming",
  DC: "District of Columbia",
};

interface RawLegislator {
  id?: {
    bioguide?: string;
    thomas?: string;
    lis?: string;
    govtrack?: number;
    opensecrets?: string;
    votesmart?: number;
    fec?: string[];
    wikipedia?: string;
    ballotpedia?: string;
    wikidata?: string;
  };
  name?: {
    first?: string;
    last?: string;
    official_full?: string;
  };
  bio?: {
    birthday?: string;
    gender?: string;
  };
  terms?: Array<{
    type?: "sen" | "rep";
    start?: string;
    end?: string;
    state?: string;
    district?: number;
    party?: string;
    url?: string;
    office?: string;
    phone?: string;
  }>;
}

interface RawSocial {
  id?: { bioguide?: string };
  social?: {
    twitter?: string;
    facebook?: string;
    instagram?: string;
    youtube?: string;
    linkedin?: string;
    tiktok?: string;
  };
}

interface RawOpenStatesPerson {
  id: string;
  name?: string;
  image?: string;
  party?: string;
  current_role?: {
    title?: string;
    org_classification?: "upper" | "lower";
    district?: string | number;
  };
  links?: Array<{ url: string }>;
  offices?: Array<{
    classification?: string;
    name?: string;
    address?: string;
    voice?: string;
    fax?: string;
  }>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Static executive + gubernatorial seed (small, refreshed at election cycles).

const NOW = new Date().toISOString();

const EXECUTIVE_OFFICIALS: DirectoryOfficial[] = [
  {
    id: "exec:potus",
    level: "federal",
    name: "Donald J. Trump",
    role: "President of the United States",
    party: "Republican",
    jurisdiction: "United States",
    chamber: "executive",
    websites: ["https://www.whitehouse.gov"],
    offices: [{ type: "dc", label: "The White House", address: "1600 Pennsylvania Ave NW, Washington, DC 20500", phone: "(202) 456-1111" }],
    socials: { twitter: "POTUS", facebook: "POTUS", instagram: "POTUS" },
    externalIDs: { wikipedia: "Donald_Trump" },
    photoURL: "https://www.whitehouse.gov/wp-content/uploads/2025/01/donald-trump.jpg",
    fetchedAtISO: NOW,
  },
  {
    id: "exec:vpotus",
    level: "federal",
    name: "JD Vance",
    role: "Vice President of the United States",
    party: "Republican",
    jurisdiction: "United States",
    chamber: "executive",
    websites: ["https://www.whitehouse.gov/administration/vice-president-jd-vance/"],
    offices: [{ type: "dc", label: "Office of the Vice President", address: "Eisenhower Executive Office Building, Washington, DC 20501" }],
    socials: { twitter: "VP" },
    externalIDs: { wikipedia: "JD_Vance" },
    fetchedAtISO: NOW,
  },
];

const GOVERNORS: DirectoryOfficial[] = [
  // Seed only the highest-population states. The cache can grow as state
  // lookups happen; static governor data is fine for a v1 directory.
  govSeed("CA", "California", "Gavin Newsom", "Democratic", "https://www.gov.ca.gov", "CAgovernor"),
  govSeed("TX", "Texas", "Greg Abbott", "Republican", "https://gov.texas.gov", "GovAbbott"),
  govSeed("FL", "Florida", "Ron DeSantis", "Republican", "https://www.flgov.com", "GovRonDeSantis"),
  govSeed("NY", "New York", "Kathy Hochul", "Democratic", "https://www.governor.ny.gov", "GovKathyHochul"),
  govSeed("PA", "Pennsylvania", "Josh Shapiro", "Democratic", "https://www.governor.pa.gov", "GovernorShapiro"),
  govSeed("IL", "Illinois", "JB Pritzker", "Democratic", "https://www.illinois.gov/government/governor", "GovPritzker"),
  govSeed("OH", "Ohio", "Mike DeWine", "Republican", "https://governor.ohio.gov", "GovMikeDeWine"),
  govSeed("GA", "Georgia", "Brian Kemp", "Republican", "https://gov.georgia.gov", "GovKemp"),
  govSeed("NC", "North Carolina", "Josh Stein", "Democratic", "https://governor.nc.gov", "NC_Governor"),
  govSeed("MI", "Michigan", "Gretchen Whitmer", "Democratic", "https://www.michigan.gov/whitmer", "GovWhitmer"),
  govSeed("NJ", "New Jersey", "Phil Murphy", "Democratic", "https://nj.gov/governor/", "GovMurphy"),
  govSeed("VA", "Virginia", "Glenn Youngkin", "Republican", "https://www.governor.virginia.gov", "GlennYoungkin"),
  govSeed("WA", "Washington", "Bob Ferguson", "Democratic", "https://governor.wa.gov", "GovBobFerguson"),
  govSeed("AZ", "Arizona", "Katie Hobbs", "Democratic", "https://azgovernor.gov", "GovernorHobbs"),
  govSeed("MA", "Massachusetts", "Maura Healey", "Democratic", "https://www.mass.gov/orgs/office-of-the-governor", "MassGovernor"),
];

function govSeed(state: string, stateName: string, name: string, party: string, website: string, twitter?: string): DirectoryOfficial {
  return {
    id: `gov:${state.toLowerCase()}`,
    level: "state",
    name,
    role: `Governor of ${stateName}`,
    party,
    jurisdiction: stateName,
    state,
    chamber: "executive",
    websites: [website],
    offices: [{ type: "state-capitol", label: "Governor's Office", address: `Office of the Governor, ${stateName}` }],
    socials: twitter ? { twitter } : {},
    externalIDs: { wikipedia: name.replace(/\s+/g, "_") },
    fetchedAtISO: NOW,
  };
}
