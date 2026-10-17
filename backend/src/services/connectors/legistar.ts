import { CivicError } from "../../lib/errors.js";

const BASE = "https://webapi.legistar.com/v1";

export interface LegistarClient {
  client: string;
  publicSiteURL: string;
  scope: "local-philly" | "federal" | "state" | "unknown";
  jurisdictionName: string;
  defaultContactTarget: string;
}

export const LEGISTAR_CLIENTS: Record<string, LegistarClient> = {
  phila: {
    client: "phila",
    publicSiteURL: "https://phila.legistar.com",
    scope: "local-philly",
    jurisdictionName: "Philadelphia City Council",
    defaultContactTarget: "Council public comment portal",
  },
  nyc: {
    client: "nyc",
    publicSiteURL: "https://legistar.council.nyc.gov",
    scope: "unknown",
    jurisdictionName: "New York City Council",
    defaultContactTarget: "Council public comment portal",
  },
  chicago: {
    client: "chicago",
    publicSiteURL: "https://chicago.legistar.com",
    scope: "unknown",
    jurisdictionName: "Chicago City Council",
    defaultContactTarget: "Council public comment portal",
  },
  boston: {
    client: "boston",
    publicSiteURL: "https://boston.legistar.com",
    scope: "unknown",
    jurisdictionName: "Boston City Council",
    defaultContactTarget: "Council public comment portal",
  },
  losangeles: {
    client: "losangeles",
    publicSiteURL: "https://cityclerk.lacity.org",
    scope: "unknown",
    jurisdictionName: "Los Angeles City Council",
    defaultContactTarget: "Council public comment portal",
  },
  dc: {
    client: "dc",
    publicSiteURL: "https://lims.dccouncil.gov",
    scope: "unknown",
    jurisdictionName: "Council of the District of Columbia",
    defaultContactTarget: "Council public comment portal",
  },
  seattle: {
    client: "seattle",
    publicSiteURL: "https://seattle.legistar.com",
    scope: "unknown",
    jurisdictionName: "Seattle City Council",
    defaultContactTarget: "Council public comment portal",
  },
  portland: {
    client: "portland",
    publicSiteURL: "https://efiles.portlandoregon.gov",
    scope: "unknown",
    jurisdictionName: "Portland City Council",
    defaultContactTarget: "Council public comment portal",
  },
  sf: {
    client: "sfgov",
    publicSiteURL: "https://sfgov.legistar.com",
    scope: "unknown",
    jurisdictionName: "San Francisco Board of Supervisors",
    defaultContactTarget: "Board public comment portal",
  },
  detroit: {
    client: "detroitmi",
    publicSiteURL: "https://detroitmi.legistar.com",
    scope: "unknown",
    jurisdictionName: "Detroit City Council",
    defaultContactTarget: "Council public comment portal",
  },
  houston: {
    client: "houston",
    publicSiteURL: "https://houston.novusagenda.com",
    scope: "unknown",
    jurisdictionName: "Houston City Council",
    defaultContactTarget: "Council public comment portal",
  },
  austin: {
    client: "austin",
    publicSiteURL: "https://www.austintexas.gov/cityclerk",
    scope: "unknown",
    jurisdictionName: "Austin City Council",
    defaultContactTarget: "Council public comment portal",
  },
  minneapolis: {
    client: "minneapolis",
    publicSiteURL: "https://lims.minneapolismn.gov",
    scope: "unknown",
    jurisdictionName: "Minneapolis City Council",
    defaultContactTarget: "Council public comment portal",
  },
};

/**
 * Maps a US ZIP to the most-likely Legistar (or equivalent) client id.
 * Conservative: only matches well-known city ZIP prefixes. Falls back to
 * `null` for ZIPs outside our coverage list.
 */
export function legistarClientForZip(zip: string): string | null {
  const prefix3 = zip.slice(0, 3);
  const prefix2 = zip.slice(0, 2);
  // Philadelphia
  if (prefix3 === "191" || prefix3 === "190" || prefix3 === "192") return "phila";
  // NYC (Manhattan, Bronx, Brooklyn, Queens, Staten Island)
  if (prefix3 === "100" || prefix3 === "101" || prefix3 === "102" || prefix3 === "103" ||
      prefix3 === "104" || prefix3 === "112" || prefix3 === "113" || prefix3 === "114" ||
      prefix3 === "116" || prefix3 === "110") return "nyc";
  // Chicago
  if (prefix3 === "606" || prefix3 === "607" || prefix3 === "608") return "chicago";
  // Boston
  if (prefix3 === "021" || prefix3 === "022") return "boston";
  // Los Angeles
  if (prefix3 === "900" || prefix3 === "901" || prefix3 === "902") return "losangeles";
  // DC
  if (prefix2 === "20" && prefix3.startsWith("200")) return "dc";
  // Seattle
  if (prefix3 === "981") return "seattle";
  // Portland
  if (prefix3 === "972") return "portland";
  // San Francisco
  if (prefix3 === "941") return "sf";
  // Detroit
  if (prefix3 === "482") return "detroit";
  // Houston
  if (prefix3 === "770" || prefix3 === "771" || prefix3 === "772") return "houston";
  // Austin
  if (prefix3 === "787") return "austin";
  // Minneapolis
  if (prefix3 === "554") return "minneapolis";
  return null;
}

export interface LegistarEvent {
  EventId: number;
  EventBodyId: number;
  EventBodyName: string;
  EventDate: string;
  EventTime: string;
  EventLocation: string;
  EventAgendaFile: string | null;
  EventInSiteURL: string;
}

export interface LegistarEventItem {
  EventItemId: number;
  EventItemEventId: number;
  EventItemMatterId: number | null;
  EventItemMatterFile: string | null;
  EventItemMatterName: string | null;
  EventItemMatterType: string | null;
  EventItemMatterStatus: string | null;
  EventItemTitle: string | null;
  EventItemActionText: string | null;
  EventItemAgendaSequence: number | null;
}

export interface LegistarMatter {
  MatterId: number;
  MatterFile: string;
  MatterName: string;
  MatterTitle: string;
  MatterTypeName: string;
  MatterStatusName: string;
  MatterBodyName: string;
  MatterIntroDate: string;
  MatterAgendaDate: string | null;
  MatterPassedDate: string | null;
}

export interface LegistarMatterAttachment {
  MatterAttachmentId: number;
  MatterAttachmentName: string;
  MatterAttachmentHyperlink: string;
}

export interface LegistarMatterFull {
  matter: LegistarMatter;
  attachments: LegistarMatterAttachment[];
  detailURL: string;
}

interface FetchOptions {
  signal?: AbortSignal;
}

export class LegistarConnector {
  constructor(private readonly fetchImpl: typeof fetch = fetch) {}

  knownClient(client: string): LegistarClient {
    const known = LEGISTAR_CLIENTS[client.toLowerCase()];
    if (!known) {
      throw new CivicError(
        "unknown_legistar_client",
        `No Legistar client registered for "${client}".`,
        400,
      );
    }
    return known;
  }

  async fetchUpcomingEvents(
    client: string,
    lookaheadDays: number = 30,
    opts: FetchOptions = {},
  ): Promise<LegistarEvent[]> {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const startISO = today.toISOString().slice(0, 10);
    const endDate = new Date(today.getTime() + lookaheadDays * 24 * 60 * 60 * 1000);
    const endISO = endDate.toISOString().slice(0, 10);

    const filter = `EventDate ge datetime'${startISO}' and EventDate le datetime'${endISO}'`;
    const url = `${BASE}/${client}/Events?$filter=${encodeURIComponent(filter)}&$orderby=EventDate&$top=80`;

    const events = await this.fetchJSON<LegistarEvent[]>(url, opts);
    return events ?? [];
  }

  async fetchEventItems(
    client: string,
    eventId: number,
    opts: FetchOptions = {},
  ): Promise<LegistarEventItem[]> {
    const url = `${BASE}/${client}/EventItems/${eventId}`;
    const items = await this.fetchJSON<LegistarEventItem[]>(url, opts);
    return items ?? [];
  }

  async fetchMatter(
    client: string,
    matterId: number,
    opts: FetchOptions = {},
  ): Promise<LegistarMatterFull | null> {
    const matter = await this.fetchJSON<LegistarMatter>(
      `${BASE}/${client}/Matters/${matterId}`,
      opts,
    );
    if (!matter) return null;

    const attachments =
      (await this.fetchJSON<LegistarMatterAttachment[]>(
        `${BASE}/${client}/Matters/${matterId}/Attachments`,
        opts,
      )) ?? [];

    const detailURL = `${LEGISTAR_CLIENTS[client]?.publicSiteURL ?? `https://${client}.legistar.com`}/LegislationDetail.aspx?ID=${matterId}`;

    return { matter, attachments, detailURL };
  }

  /**
   * Convenience: fetch upcoming events, expand their items into matters,
   * and return one LegistarMatterFull per unique matter.
   */
  async collectUpcomingMatters(
    client: string,
    lookaheadDays: number = 30,
  ): Promise<LegistarMatterFull[]> {
    const events = await this.fetchUpcomingEvents(client, lookaheadDays);
    const matterIds = new Set<number>();
    for (const event of events) {
      const items = await this.fetchEventItems(client, event.EventId);
      for (const item of items) {
        if (item.EventItemMatterId) matterIds.add(item.EventItemMatterId);
      }
    }

    const collected: LegistarMatterFull[] = [];
    for (const id of matterIds) {
      const full = await this.fetchMatter(client, id);
      if (full) collected.push(full);
    }
    return collected;
  }

  private async fetchJSON<T>(url: string, opts: FetchOptions): Promise<T | null> {
    const res = await this.fetchImpl(url, {
      headers: { Accept: "application/json" },
      signal: opts.signal ?? AbortSignal.timeout(15_000),
    });
    if (res.status === 404) return null;
    if (!res.ok) {
      throw new CivicError("legistar_fetch_failed", `Legistar returned ${res.status} for ${url}`, 502);
    }
    return (await res.json()) as T;
  }
}
