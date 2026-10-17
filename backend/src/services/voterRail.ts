import { config } from "../config.js";
import { STATE_REGISTRATION_INFO, getStateRegistrationInfo, type StateRegistrationInfo } from "./stateRegistrationData.js";

const CIVIC_BASE = "https://www.googleapis.com/civicinfo/v2";

export interface UpcomingElection {
  id: string;
  name: string;
  electionDay: string;
  ocdDivisionId?: string;
}

export interface PollingPlace {
  name: string;
  address: string;
  pollingHours?: string;
  notes?: string;
  latitude?: number;
  longitude?: number;
  sources?: { name: string; official: boolean }[];
}

export interface BallotContestRaw {
  type: string;
  office?: string;
  level?: string[];
  roles?: string[];
  district?: { name: string; scope?: string };
  ballotTitle?: string;
  candidates?: BallotCandidate[];
  referendumTitle?: string;
  referendumSubtitle?: string;
  referendumText?: string;
  referendumBallotResponses?: string[];
  referendumPassageThreshold?: string;
  numberElected?: string;
}

export interface BallotCandidate {
  name: string;
  party?: string;
  candidateUrl?: string;
  email?: string;
  phone?: string;
}

export interface VoterInfo {
  election: UpcomingElection | null;
  pollingPlaces: PollingPlace[];
  earlyVoteSites: PollingPlace[];
  dropOffLocations: PollingPlace[];
  contests: BallotContestRaw[];
  state?: { name?: string; electionAdministrationBody?: { name?: string; electionInfoUrl?: string; ballotInfoUrl?: string } };
}

export class VoterRailService {
  private readonly apiKey: string | null;

  constructor(apiKey: string | null) {
    this.apiKey = apiKey;
  }

  static fromEnv(): VoterRailService {
    return new VoterRailService(config.GOOGLE_CIVIC_API_KEY ?? null);
  }

  get enabled(): boolean { return this.apiKey !== null; }

  /** Returns list of upcoming elections known to Google's database. */
  async listElections(): Promise<UpcomingElection[]> {
    if (!this.apiKey) return [];
    const url = `${CIVIC_BASE}/elections?key=${encodeURIComponent(this.apiKey)}`;
    const response = await fetch(url, { headers: { accept: "application/json" } });
    if (!response.ok) {
      throw new Error(`Google Civic elections failed: ${response.status}`);
    }
    const payload = (await response.json()) as {
      elections?: Array<{ id: string; name: string; electionDay: string; ocdDivisionId?: string }>;
    };
    return (payload.elections ?? [])
      .filter((e) => e.id !== "2000") // 2000 is Google's "Voter Information Test Election"
      .map((e) => {
        const out: UpcomingElection = { id: e.id, name: e.name, electionDay: e.electionDay };
        if (e.ocdDivisionId) out.ocdDivisionId = e.ocdDivisionId;
        return out;
      });
  }

  /** Fetch ballot + polling info for a specific address and election. */
  async voterInfo(address: string, electionId?: string): Promise<VoterInfo> {
    if (!this.apiKey) {
      return { election: null, pollingPlaces: [], earlyVoteSites: [], dropOffLocations: [], contests: [] };
    }
    const url = new URL(`${CIVIC_BASE}/voterinfo`);
    url.searchParams.set("key", this.apiKey);
    url.searchParams.set("address", address);
    if (electionId) url.searchParams.set("electionId", electionId);
    url.searchParams.set("returnAllAvailableData", "true");

    const response = await fetch(url.toString(), { headers: { accept: "application/json" } });
    if (!response.ok) {
      // 400 means no election scheduled within the lookahead window for this
      // address — treat as empty rather than error.
      if (response.status === 400 || response.status === 404) {
        return { election: null, pollingPlaces: [], earlyVoteSites: [], dropOffLocations: [], contests: [] };
      }
      throw new Error(`Google Civic voterinfo failed: ${response.status}`);
    }
    const payload = (await response.json()) as {
      election?: { id: string; name: string; electionDay: string; ocdDivisionId?: string };
      pollingLocations?: RawLocation[];
      earlyVoteSites?: RawLocation[];
      dropOffLocations?: RawLocation[];
      contests?: BallotContestRaw[];
      state?: VoterInfo["state"][];
    };

    const election: UpcomingElection | null = payload.election
      ? (() => {
          const e: UpcomingElection = { id: payload.election!.id, name: payload.election!.name, electionDay: payload.election!.electionDay };
          if (payload.election!.ocdDivisionId) e.ocdDivisionId = payload.election!.ocdDivisionId;
          return e;
        })()
      : null;

    const info: VoterInfo = {
      election,
      pollingPlaces: (payload.pollingLocations ?? []).map(toPollingPlace),
      earlyVoteSites: (payload.earlyVoteSites ?? []).map(toPollingPlace),
      dropOffLocations: (payload.dropOffLocations ?? []).map(toPollingPlace),
      contests: payload.contests ?? [],
    };
    if (payload.state?.[0]) info.state = payload.state[0];
    return info;
  }

  /** State registration info — always available since it's static. */
  getRegistrationInfo(stateCode: string): StateRegistrationInfo | null {
    return getStateRegistrationInfo(stateCode);
  }

  allRegistrationInfo(): StateRegistrationInfo[] {
    return Object.values(STATE_REGISTRATION_INFO);
  }
}

interface RawLocation {
  address?: { line1?: string; city?: string; state?: string; zip?: string; locationName?: string };
  pollingHours?: string;
  notes?: string;
  latitude?: number;
  longitude?: number;
  sources?: { name?: string; official?: boolean }[];
}

function toPollingPlace(loc: RawLocation): PollingPlace {
  const addr = loc.address;
  const line = addr?.line1?.trim() ?? "";
  const cityStateZip = [addr?.city, addr?.state, addr?.zip].filter(Boolean).join(", ");
  const fullAddress = [line, cityStateZip].filter(Boolean).join(", ");
  const out: PollingPlace = {
    name: addr?.locationName?.trim() || fullAddress || "Polling place",
    address: fullAddress || (addr?.locationName ?? "Address unavailable"),
  };
  if (loc.pollingHours) out.pollingHours = loc.pollingHours;
  if (loc.notes) out.notes = loc.notes;
  if (typeof loc.latitude === "number") out.latitude = loc.latitude;
  if (typeof loc.longitude === "number") out.longitude = loc.longitude;
  if (loc.sources) {
    out.sources = loc.sources
      .filter((s) => s.name)
      .map((s) => ({ name: s.name!, official: s.official ?? false }));
  }
  return out;
}
