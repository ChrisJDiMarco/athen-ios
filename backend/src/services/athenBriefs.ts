import type { EvidenceRecord } from "./evidenceVault.js";
import type { StoredIssue } from "./issueStore.js";

export interface AthenBriefFeedItem {
  id: string;
  issueID?: string;
  authorName: string;
  authorHandle: string;
  authorEmoji: string;
  kind: "aiBrief";
  locality: string;
  body: string;
  createdAtISO: string;
  issueTitle: string;
  explainer: {
    headline: string;
    plainEnglish: string;
    stakes: string;
    positions: { kind: "support" | "concern" | "watch"; title: string; summary: string }[];
    nextStep: string;
    visualPrompt: string;
    sourceLine: string;
    confidenceLabel: string;
  };
  evidence: EvidenceRecord[];
}

export function buildAthenBriefs(args: {
  issues: StoredIssue[];
  evidence: EvidenceRecord[];
  limit?: number;
}): AthenBriefFeedItem[] {
  const byIssue = new Map<string, EvidenceRecord[]>();
  for (const record of args.evidence) {
    if (!record.issueID) continue;
    const existing = byIssue.get(record.issueID) ?? [];
    existing.push(record);
    byIssue.set(record.issueID, existing);
  }

  const issueBriefs = args.issues
    .slice()
    .sort((a, b) => Date.parse(a.voteDateISO) - Date.parse(b.voteDateISO))
    .map((issue) => briefFromIssue(issue, byIssue.get(issue.id) ?? []));

  const unlinkedEvidenceBriefs = args.evidence
    .filter((record) => !record.issueID)
    .slice(0, Math.max(0, (args.limit ?? 20) - issueBriefs.length))
    .map(briefFromEvidence);

  return [...issueBriefs, ...unlinkedEvidenceBriefs].slice(0, args.limit ?? 20);
}

export function briefFromIssue(issue: StoredIssue, evidence: EvidenceRecord[]): AthenBriefFeedItem {
  const trust = issue.trustScore ?? 70;
  const confidence = issue.extractionConfidence ?? trust;
  const strongestEvidence = evidence[0];
  const sourceLine = strongestEvidence
    ? `Based on ${strongestEvidence.sourceName} evidence captured from ${strongestEvidence.sourceHost}.`
    : `Based on ${issue.sourceName}${issue.sourceHost ? ` via ${issue.sourceHost}` : ""}.`;
  const costFact = issue.facts.find((fact) => /cost|pay|fund|budget/i.test(fact.label + fact.value));
  const timelineFact = issue.facts.find((fact) => /timeline|date|deadline|vote/i.test(fact.label + fact.value));

  return {
    id: `athen-brief-${issue.id}`,
    issueID: issue.id,
    authorName: "Athen",
    authorHandle: "@athen.brief",
    authorEmoji: "*",
    kind: "aiBrief",
    locality: issue.jurisdiction,
    body: `${issue.title}: ${issue.summary}`,
    createdAtISO: issue.updatedAt,
    issueTitle: issue.title,
    explainer: {
      headline: headlineFor(issue),
      plainEnglish: issue.summary,
      stakes: stakesFor(issue, costFact?.value, timelineFact?.value),
      positions: positionsFor(issue),
      nextStep: nextStepFor(issue),
      visualPrompt: visualPromptFor(issue),
      sourceLine,
      confidenceLabel: confidenceLabel(trust, confidence),
    },
    evidence: evidence.slice(0, 4),
  };
}

function briefFromEvidence(record: EvidenceRecord): AthenBriefFeedItem {
  return {
    id: `athen-evidence-${record.id}`,
    authorName: "Athen",
    authorHandle: "@athen.brief",
    authorEmoji: "*",
    kind: "aiBrief",
    locality: record.jurisdiction,
    body: `${record.title}: ${record.summary}`,
    createdAtISO: record.updatedAtISO ?? record.capturedAtISO,
    issueTitle: record.title,
    explainer: {
      headline: `New source signal from ${record.sourceName}.`,
      plainEnglish: record.summary,
      stakes: "This is a fresh government-source change that Athen can attach to a local issue, service, rulemaking, or public comment window as the evidence graph grows.",
      positions: [
        { kind: "support", title: "Why it matters", summary: "Official records reduce guesswork and make it easier to trace claims back to the source." },
        { kind: "concern", title: "What is still missing", summary: "A source signal is not the full story until deadlines, affected residents, and action paths are verified." },
        { kind: "watch", title: "What Athen checks next", summary: "Jurisdiction, deadlines, public comment windows, fiscal notes, and impacted services." },
      ],
      nextStep: "Open the source, then ask Athen to explain what changed and who is affected.",
      visualPrompt: `A clean civic evidence board showing ${record.sourceName}, source snippets, deadlines, and affected residents.`,
      sourceLine: `Captured from ${record.sourceHost}.`,
      confidenceLabel: confidenceLabel(record.trustScore ?? 70, record.extractionConfidence ?? 70),
    },
    evidence: [record],
  };
}

function headlineFor(issue: StoredIssue): string {
  if (issue.impactLevel === "urgent") return "A deadline is close, and this one deserves a quick decision.";
  if (issue.impactLevel === "material") return "A material policy change is moving through government.";
  return "A civic item is worth watching before it becomes urgent.";
}

function stakesFor(issue: StoredIssue, cost?: string, timeline?: string): string {
  const pieces = [];
  if (cost) pieces.push(`Cost/funding: ${cost}`);
  if (timeline) pieces.push(`Timeline: ${timeline}`);
  pieces.push(`Impact: ${issue.impactLevel}.`);
  return pieces.join(" ");
}

function positionsFor(issue: StoredIssue) {
  return [
    {
      kind: "support" as const,
      title: "Why supporters may back it",
      summary: `Supporters will usually point to the stated goal: ${issue.facts[0]?.value ?? issue.summary}`,
    },
    {
      kind: "concern" as const,
      title: "What critics may question",
      summary: "Critics may focus on costs, enforcement, who benefits first, and whether the source packet answers implementation details.",
    },
    {
      kind: "watch" as const,
      title: "What to verify",
      summary: "Check amendments, fiscal notes, public testimony, and whether the deadline or public comment channel changes.",
    },
  ];
}

function nextStepFor(issue: StoredIssue): string {
  if (issue.impactLevel === "watch") return "Save it, read the source, and watch for a hearing or amendment.";
  return "Read the evidence card, choose support or oppose, and file before the deadline.";
}

function visualPromptFor(issue: StoredIssue): string {
  return `An editorial civic explainer image for "${issue.title}": residents, source documents, deadline clock, and a clear public decision path.`;
}

function confidenceLabel(trustScore: number, extractionConfidence: number): string {
  const score = Math.round((trustScore + extractionConfidence) / 2);
  if (score >= 85) return "High source confidence";
  if (score >= 65) return "Medium source confidence";
  return "Needs verification";
}
