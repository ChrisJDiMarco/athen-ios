import type { StoredIssue } from "./issueStore.js";
import type { MatchedService } from "./serviceCatalog.js";

export interface CivicBriefInput {
  issues: StoredIssue[];
  serviceMatches: MatchedService[];
  stateCode: string | undefined;
  zip: string | undefined;
  registeredSources: number | null;
}

export function buildCivicBrief(input: CivicBriefInput) {
  const now = new Date();
  const actionable = input.issues.filter((issue) => !hasVotePassed(issue, now));
  const urgent = actionable.filter((issue) => issue.impactLevel === "urgent" || hoursUntil(issue, now) <= 72);
  const nextIssue = actionable[0] ?? input.issues[0];
  const averageTrustScore = averageTrust(input.issues);
  const lastUpdatedAt = latestUpdatedAt(input.issues);
  const activeSourceHosts = new Set(
    input.issues
      .map((issue) => issue.sourceHost)
      .filter((host): host is string => Boolean(host)),
  ).size;

  const activeCount = actionable.length;
  const headline = nextIssue
    ? `${urgent.length > 0 ? `${urgent.length} urgent` : `${activeCount} active`} civic item${(urgent.length > 0 ? urgent.length : activeCount) === 1 ? "" : "s"} to review`
    : "No civic deadlines loaded yet";

  const summary = nextIssue
    ? `Start with "${nextIssue.title}." ${nextIssue.summary}`
    : "Connect official sources or run ingestion to generate a local civic brief.";

  return {
    generatedAtISO: now.toISOString(),
    locationLabel: locationLabel(input.stateCode, input.zip),
    headline,
    summary,
    metrics: {
      activeIssues: actionable.length,
      urgentIssues: urgent.length,
      serviceMatches: input.serviceMatches.length,
      averageTrustScore,
    },
    sourceHealth: {
      registeredSources: input.registeredSources,
      activeSourceHosts,
      lastUpdatedAt,
      freshnessLabel: freshnessLabel(lastUpdatedAt, now),
      averageTrustScore,
    },
    actions: buildActions(nextIssue, input.serviceMatches[0], urgent.length),
    serviceMatches: input.serviceMatches,
  };
}

function buildActions(issue: StoredIssue | undefined, service: MatchedService | undefined, urgentCount: number) {
  const actions = [];
  if (issue) {
    actions.push({
      id: `issue-${issue.id}`,
      kind: "issue",
      priority: urgentCount > 0 ? 1 : 2,
      title: urgentCount > 0 ? "File before the deadline" : "Review top civic item",
      detail: issue.title,
      cta: issue.impactLevel === "watch" ? "Review" : "Act",
      systemImage: issue.impactLevel === "watch" ? "eye.fill" : "bolt.fill",
      issueID: issue.id,
    });
  }
  if (service) {
    actions.push({
      id: `service-${service.id}`,
      kind: "service",
      priority: 2,
      title: "Check a benefit match",
      detail: `${service.title} · ${service.matchScore}% fit`,
      cta: "Open Help",
      systemImage: "heart.text.square.fill",
      serviceID: service.id,
    });
  }
  actions.push({
    id: "assistant-daily-plan",
    kind: "assistant",
    priority: 3,
    title: "Ask for a 5-minute plan",
    detail: "Athen can turn today's issues, services, and reps into a short action list.",
    cta: "Ask",
    systemImage: "sparkles",
  });
  return actions;
}

function averageTrust(issues: StoredIssue[]): number | null {
  const scores = issues
    .map((issue) => issue.trustScore)
    .filter((score): score is number => typeof score === "number");
  if (scores.length === 0) return null;
  return Math.round(scores.reduce((sum, score) => sum + score, 0) / scores.length);
}

function latestUpdatedAt(issues: StoredIssue[]): string | null {
  let latest: string | null = null;
  for (const issue of issues) {
    if (!latest || Date.parse(issue.updatedAt) > Date.parse(latest)) {
      latest = issue.updatedAt;
    }
  }
  return latest;
}

function freshnessLabel(lastUpdatedAt: string | null, now: Date): string {
  if (!lastUpdatedAt) return "No live source run";
  const ageHours = (now.getTime() - Date.parse(lastUpdatedAt)) / 3_600_000;
  if (ageHours <= 6) return "Fresh";
  if (ageHours <= 24) return "Updated today";
  if (ageHours <= 72) return "Needs a sweep";
  return "Stale";
}

function hasVotePassed(issue: StoredIssue, now: Date): boolean {
  return Date.parse(issue.voteDateISO) < now.getTime() - 3_600_000;
}

function hoursUntil(issue: StoredIssue, now: Date): number {
  return (Date.parse(issue.voteDateISO) - now.getTime()) / 3_600_000;
}

function locationLabel(stateCode?: string, zip?: string): string {
  if (zip && stateCode) return `${zip}, ${stateCode}`;
  if (stateCode) return stateCode;
  return "your area";
}
