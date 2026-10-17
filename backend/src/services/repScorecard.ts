import type { IssueStore, StoredIssue } from "./issueStore.js";
import { canonicalizeOfficialName, type VoteStore } from "./voteStore.js";

/**
 * Closes the loop on user filings: for each official the user has written
 * to, summarize the relationship. v1 leverages what we already ingest — bill
 * status, vote dates, official metadata — and leaves a clean interface for
 * plugging in actual roll-call vote data later (OpenStates votes endpoint,
 * congress.gov VotesAPI, state-level Legistar votes).
 *
 * The iOS app posts its filing history (we don't persist per-user filings
 * server-side; iOS is the source of truth) and gets back a scorecard.
 */

export interface ScorecardFilingInput {
  issueId: string;
  issueTitle: string;
  position: "endorse" | "oppose";
  filedAtISO: string;
  officialName: string;
}

export interface ScorecardMismatch {
  issueId: string;
  issueTitle: string;
  userPosition: "endorse" | "oppose";
  officialVote?: "yes" | "no" | "abstain" | "not-yet-voted";
  voteDateISO?: string;
}

export interface RepScorecard {
  officialName: string;
  totalFilings: number;
  endorseCount: number;
  opposeCount: number;
  /** Topics the user has filed against this rep on. */
  topicBreakdown: { topic: string; count: number }[];
  /** Mismatches between user's position and the rep's actual vote. Empty
   *  when we haven't yet ingested vote data for the underlying bill. */
  mismatches: ScorecardMismatch[];
  /** Pending alignment items — filings on bills that haven't been voted yet. */
  pending: ScorecardMismatch[];
  /** 0-100. Null when no votes have been recorded for any underlying bill. */
  alignmentPct: number | null;
  /** Per-filing breakdown — chronological, most recent first. */
  history: ScorecardHistoryEntry[];
}

export interface ScorecardHistoryEntry {
  issueId: string;
  issueTitle: string;
  position: "endorse" | "oppose";
  filedAtISO: string;
  vote?: "yes" | "no" | "abstain" | "not-yet-voted";
  voteDateISO?: string;
}

export interface ScorecardResponse {
  scorecards: RepScorecard[];
  /** Officials the user has *never* filed with, but who represent them. */
  notFiledYet: string[];
  generatedAtISO: string;
}

export class RepScorecardService {
  constructor(
    private readonly issues: IssueStore,
    private readonly votes?: VoteStore,
  ) {}

  build(filings: ScorecardFilingInput[]): ScorecardResponse {
    const byOfficial = new Map<string, ScorecardFilingInput[]>();
    for (const f of filings) {
      const key = f.officialName.trim();
      if (!key) continue;
      const list = byOfficial.get(key) ?? [];
      list.push(f);
      byOfficial.set(key, list);
    }
    const scorecards = Array.from(byOfficial.entries()).map(([official, items]) => this.scorecardFor(official, items));
    return {
      scorecards: scorecards.sort((a, b) => b.totalFilings - a.totalFilings),
      notFiledYet: [],
      generatedAtISO: new Date().toISOString(),
    };
  }

  private scorecardFor(officialName: string, filings: ScorecardFilingInput[]): RepScorecard {
    const topics = new Map<string, number>();
    const history: ScorecardHistoryEntry[] = [];
    const mismatches: ScorecardMismatch[] = [];
    const pending: ScorecardMismatch[] = [];
    let endorseCount = 0;
    let opposeCount = 0;
    let agreement = 0;
    let recordedVotes = 0;

    for (const filing of filings) {
      if (filing.position === "endorse") endorseCount += 1;
      else opposeCount += 1;

      const issue = this.issues.findById(filing.issueId);
      const category = (issue?.category ?? "uncategorized").toLowerCase();
      topics.set(category, (topics.get(category) ?? 0) + 1);

      const knownVote = this.resolveVote(issue, filing.officialName);
      const entry: ScorecardHistoryEntry = {
        issueId: filing.issueId,
        issueTitle: filing.issueTitle,
        position: filing.position,
        filedAtISO: filing.filedAtISO,
      };
      if (knownVote) {
        entry.vote = knownVote.vote;
        if (knownVote.dateISO) entry.voteDateISO = knownVote.dateISO;
      }
      history.push(entry);

      if (knownVote && knownVote.vote !== "not-yet-voted") {
        recordedVotes += 1;
        const aligned =
          (filing.position === "endorse" && knownVote.vote === "yes") ||
          (filing.position === "oppose" && knownVote.vote === "no");
        if (aligned) {
          agreement += 1;
        } else {
          const mm: ScorecardMismatch = {
            issueId: filing.issueId,
            issueTitle: filing.issueTitle,
            userPosition: filing.position,
            officialVote: knownVote.vote,
          };
          if (knownVote.dateISO) mm.voteDateISO = knownVote.dateISO;
          mismatches.push(mm);
        }
      } else {
        const pendingItem: ScorecardMismatch = {
          issueId: filing.issueId,
          issueTitle: filing.issueTitle,
          userPosition: filing.position,
          officialVote: "not-yet-voted",
        };
        pending.push(pendingItem);
      }
    }

    history.sort((a, b) => b.filedAtISO.localeCompare(a.filedAtISO));

    const topicBreakdown = Array.from(topics.entries())
      .map(([topic, count]) => ({ topic, count }))
      .sort((a, b) => b.count - a.count);

    return {
      officialName,
      totalFilings: filings.length,
      endorseCount,
      opposeCount,
      topicBreakdown,
      mismatches,
      pending,
      alignmentPct: recordedVotes > 0 ? Math.round((agreement / recordedVotes) * 100) : null,
      history,
    };
  }

  /**
   * Looks the official's actual vote up in the VoteStore. Falls back to
   * "not-yet-voted" when we haven't ingested a vote for this bill yet.
   * Matches official names case- and prefix-insensitively (Senator / Rep /
   * etc.) so the user's filing-time string finds the upstream record.
   */
  private resolveVote(
    issue: StoredIssue | undefined,
    officialName: string,
  ): { vote: "yes" | "no" | "abstain" | "not-yet-voted"; dateISO?: string } | null {
    if (!issue) return null;
    if (!this.votes) return { vote: "not-yet-voted" };

    // Find the most recent vote on this bill from any chamber.
    const candidates = issue.sourceRecordID
      ? this.votes.byBillExternalID(issue.sourceRecordID)
      : this.votes.byIssueFingerprint(issue.sourceFingerprint);
    if (candidates.length === 0) return { vote: "not-yet-voted" };
    const latest = candidates.sort((a, b) => b.voteDateISO.localeCompare(a.voteDateISO))[0]!;

    const key = canonicalizeOfficialName(officialName);
    const officialVote = latest.byOfficialName[key];
    if (!officialVote) return { vote: "not-yet-voted", dateISO: latest.voteDateISO };
    if (officialVote === "yes" || officialVote === "no" || officialVote === "abstain") {
      return { vote: officialVote, dateISO: latest.voteDateISO };
    }
    return { vote: "not-yet-voted", dateISO: latest.voteDateISO };
  }
}

