import { createHash } from "node:crypto";
import type { IngestedIssue } from "./ingestionPipeline.js";
import type { CivicSource } from "./sourceRegistry.js";
import type { StoredIssue, StoredScope } from "./issueStore.js";

export type StoredIssueInput = Omit<StoredIssue, "id" | "createdAt" | "updatedAt">;

export function storedIssueFromIngested(
  issue: IngestedIssue,
  args: {
    sourceFingerprint?: string;
    source?: CivicSource;
    sourceRecordID?: string;
    sourceType?: string;
  } = {},
): StoredIssueInput {
  const sourceType = args.sourceType ?? args.source?.kind ?? "government-web";
  const sourceHost = hostFromURL(issue.sourceURL);
  const trustArgs: { sourceType: string; sourceTrustTier?: CivicSource["trustTier"]; sourceHost: string } = {
    sourceType,
    sourceHost,
  };
  if (args.source?.trustTier) trustArgs.sourceTrustTier = args.source.trustTier;
  const trustScore = trustScoreForIssue(issue, trustArgs);

  const input: StoredIssueInput = {
    sourceFingerprint: args.sourceFingerprint ?? fingerprintForURL(issue.sourceURL),
    title: issue.title,
    category: issue.category,
    jurisdiction: issue.jurisdiction,
    scope: issue.scope as StoredScope,
    summary: issue.summary,
    impactLevel: issue.impactLevel,
    voteDateISO: issue.voteDateISO,
    sourceName: issue.sourceName,
    sourceDetail: issue.sourceDetail,
    sourceURL: issue.sourceURL,
    sourceHost,
    sourceType,
    trustScore,
    extractionConfidence: issue.extractionConfidence,
    citations: issue.citations,
    ingestedAt: new Date().toISOString(),
    topics: issue.topics,
    facts: issue.facts.map((fact) => ({ label: fact.label, value: fact.value })),
    official: {
      name: issue.officialName,
      title: issue.officialTitle,
      district: issue.officialDistrict,
      contactTarget: issue.officialContactTarget,
    },
    filingRoute: {
      verificationStep: "Verified address confirms eligibility in this jurisdiction.",
      routingStep: `Routing agent maps your profile to ${issue.officialDistrict || issue.jurisdiction}.`,
      destinationStep: `Message is filed to ${issue.officialContactTarget}.`,
      deliveryWindow: "Typical confirmation within a few minutes",
    },
  };

  const stateCode = args.source?.stateCode ?? inferStateCode(issue);
  if (stateCode) input.stateCode = stateCode;
  if (issue.zipCode) input.zipCode = issue.zipCode;
  if (args.sourceRecordID) input.sourceRecordID = args.sourceRecordID;

  return input;
}

export function fingerprintForURL(url: string): string {
  return createHash("sha1").update(`url:${canonicalURL(url)}`).digest("hex");
}

export function hostFromURL(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, "").toLowerCase();
  } catch {
    return "";
  }
}

function canonicalURL(url: string): string {
  try {
    const parsed = new URL(url);
    parsed.hash = "";
    parsed.searchParams.sort();
    return parsed.toString().replace(/\/$/, "");
  } catch {
    return url.trim();
  }
}

function trustScoreForIssue(
  issue: IngestedIssue,
  args: { sourceType: string; sourceTrustTier?: CivicSource["trustTier"]; sourceHost: string },
): number {
  let score = 45;

  if (args.sourceTrustTier === "official") score += 22;
  else if (args.sourceTrustTier === "verified") score += 14;
  else if (args.sourceTrustTier === "watch") score += 6;

  if (["legistar", "official-api", "official-web"].includes(args.sourceType)) score += 10;
  if (args.sourceHost) score += 5;
  if (issue.sourceName.trim()) score += 5;
  if (issue.sourceDetail.trim()) score += 5;
  score += Math.min(issue.facts.length, 3) * 3;
  score += Math.min(issue.citations.length, 4) * 2;
  score += Math.round((issue.extractionConfidence - 50) / 5);

  return Math.max(35, Math.min(99, score));
}

function inferStateCode(issue: IngestedIssue): string | undefined {
  if (issue.scope === "local-philly") return "PA";
  const match = issue.jurisdiction.match(/\b[A-Z]{2}\b/);
  return match?.[0];
}
