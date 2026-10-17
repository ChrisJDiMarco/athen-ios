import sourcesFile from "../data/civic-sources.json" with { type: "json" };

export type CivicSourceKind = "legistar" | "official-web" | "official-api" | "verified-web";
export type CivicSourceTrustTier = "official" | "verified" | "watch";
export type CivicSourceScope = "federal" | "state" | "local-philly" | "unknown";

export interface CivicSource {
  id: string;
  name: string;
  jurisdiction: string;
  scope: CivicSourceScope;
  stateCode?: string;
  kind: CivicSourceKind;
  trustTier: CivicSourceTrustTier;
  url: string;
  allowedHosts: string[];
  legistarClient?: string;
  defaultContactTarget: string;
  defaultQueries?: string[];
}

interface CivicSourcesFile {
  version: 1;
  sources: CivicSource[];
}

const bundled = sourcesFile as unknown as CivicSourcesFile;

export class CivicSourceRegistry {
  constructor(private readonly sources: CivicSource[] = bundled.sources) {}

  list(): CivicSource[] {
    return this.sources.slice();
  }

  byId(id: string): CivicSource | undefined {
    return this.sources.find((source) => source.id === id);
  }

  matchURL(url: string): CivicSource | undefined {
    const host = hostFromURL(url);
    if (!host) return undefined;
    return this.sources.find((source) =>
      source.allowedHosts.some((allowed) => host === allowed || host.endsWith(`.${allowed}`)),
    );
  }
}

export function hostFromURL(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, "").toLowerCase();
  } catch {
    return "";
  }
}
