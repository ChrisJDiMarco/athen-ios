/**
 * Downloads the current U.S. Congress roster from the
 * @unitedstates/congress-legislators repo (the canonical public dataset,
 * updated daily by a community of journalists + advocacy groups) and writes
 * it to src/data/us-federal-officials.json in the format the runtime expects.
 *
 * Run with: npm run fetch:congress
 *
 * Source: https://github.com/unitedstates/congress-legislators
 */
import { writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const SOURCE =
  "https://unitedstates.github.io/congress-legislators/legislators-current.json";

interface Person {
  id: { bioguide: string; thomas?: string; govtrack?: number };
  name: { official_full: string; first: string; last: string };
  bio?: { gender?: string };
  terms: Array<{
    type: "sen" | "rep";
    state: string;
    district?: number;
    party?: string;
    start: string;
    end: string;
    class?: number;
    state_rank?: "senior" | "junior";
    contact_form?: string;
    url?: string;
    phone?: string;
    office?: string;
  }>;
}

interface SenatorEntry {
  bioguide: string;
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
  bioguide: string;
  name: string;
  title: string;
  party?: string;
  district: string;
  email: string;
  contactFormURL?: string;
  websiteURL?: string;
  source: string;
}

interface OutputShape {
  _comment: string;
  generatedAt: string;
  senators: Record<string, SenatorEntry[]>;
  representativeByDistrict: Record<string, RepresentativeEntry>;
  representativeByState: Record<string, string> & { _fallbackTemplate: string };
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_PATH = resolve(__dirname, "..", "src", "data", "us-federal-officials.json");

async function main() {
  console.log("Fetching @unitedstates/congress-legislators…");
  const res = await fetch(SOURCE);
  if (!res.ok) {
    throw new Error(`Source returned ${res.status} ${res.statusText}`);
  }

  const people = (await res.json()) as Person[];
  console.log(`Loaded ${people.length} current legislators.`);

  const senators: Record<string, SenatorEntry[]> = {};
  const representativeByDistrict: Record<string, RepresentativeEntry> = {};

  for (const person of people) {
    const term = mostRecentTerm(person);
    if (!term) continue;

    if (term.type === "sen") {
      const entry: SenatorEntry = {
        bioguide: person.id.bioguide,
        seniority: term.state_rank ?? "junior",
        name: person.name.official_full,
        title: "United States Senator",
        ...(term.party ? { party: term.party } : {}),
        email: routingEmailFor(person.id.bioguide),
        ...(term.contact_form ? { contactFormURL: term.contact_form } : {}),
        ...(term.url ? { websiteURL: term.url } : {}),
        source: "unitedstates/congress-legislators",
      };
      const bucket = senators[term.state] ?? (senators[term.state] = []);
      bucket.push(entry);
    } else if (term.type === "rep") {
      const district = formatDistrict(term);
      const entry: RepresentativeEntry = {
        bioguide: person.id.bioguide,
        name: person.name.official_full,
        title: "Member, U.S. House of Representatives",
        ...(term.party ? { party: term.party } : {}),
        district,
        email: routingEmailFor(person.id.bioguide),
        ...(term.contact_form ? { contactFormURL: term.contact_form } : {}),
        ...(term.url ? { websiteURL: term.url } : {}),
        source: "unitedstates/congress-legislators",
      };
      representativeByDistrict[district] = entry;
    }
  }

  // Sort senator entries within each state: senior first.
  for (const state of Object.keys(senators)) {
    senators[state]!.sort((a, b) => {
      if (a.seniority === b.seniority) return a.name.localeCompare(b.name);
      return a.seniority === "senior" ? -1 : 1;
    });
    if (senators[state]!.length > 2) {
      // Should never happen, but guard anyway: only keep the 2 most senior.
      senators[state] = senators[state]!.slice(0, 2);
    }
  }

  const output: OutputShape = {
    _comment:
      "Auto-generated from @unitedstates/congress-legislators. Run `npm run fetch:congress` to refresh. The `email` field is a routing inbox keyed by bioguide ID — production deployments should route via the contactFormURL via headless form automation, since the U.S. Senate/House do not publish direct email addresses.",
    generatedAt: new Date().toISOString(),
    senators,
    representativeByDistrict,
    representativeByState: {
      _fallbackTemplate: "U.S. Representative for {stateName}",
    },
  };

  await writeFile(OUT_PATH, JSON.stringify(output, null, 2), "utf8");
  console.log(
    `Wrote ${Object.keys(senators).length} states of senators + ${Object.keys(representativeByDistrict).length} representatives to ${OUT_PATH}`,
  );
}

function mostRecentTerm(person: Person) {
  return person.terms
    .slice()
    .sort((a, b) => a.start.localeCompare(b.start))
    .at(-1);
}

function formatDistrict(term: { state: string; district?: number }): string {
  if (term.district === undefined) return `${term.state}-AL`;
  if (term.district === 0) return `${term.state}-AL`;
  return `${term.state}-${String(term.district).padStart(2, "0")}`;
}

function routingEmailFor(bioguide: string): string {
  // Routing inbox per bioguide ID; operators map these to real form-submitter
  // automation in production. Until that's wired, EMAIL_DRY_RUN should stay on.
  return `route+${bioguide.toLowerCase()}@civic-os.example`;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
