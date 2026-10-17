import { config } from "../config.js";
import type { IssueStore } from "./issueStore.js";
import { canonicalizeOfficialName, type StoredVote, type VoteOutcome, type VoteResult, type VoteStore } from "./voteStore.js";

/**
 * Fetches roll-call votes for bills already in our issue store. Walks our
 * known bills (OpenStates + Congress.gov sourced) and asks each upstream
 * API for any votes recorded on them. Per-bill calls are throttled so we
 * don't hammer the APIs on every refresh.
 *
 * Designed to run as a background worker — separate from the issue-ingest
 * orchestrator because vote data changes less often and the calls are slow.
 */
export class VoteIngestor {
  constructor(
    private readonly issueStore: IssueStore,
    private readonly voteStore: VoteStore,
    private readonly logger: { info: (msg: string, meta?: object) => void; error: (msg: string, meta?: object) => void },
  ) {}

  async runOnce(): Promise<{ openstates: number; congress: number; skipped: string[] }> {
    const skipped: string[] = [];
    let openstatesCount = 0;
    let congressCount = 0;

    const issues = this.issueStore.all();
    const stateBills = issues.filter((i) => i.sourceType === "official-api:openstates" && i.sourceRecordID);
    const federalBills = issues.filter((i) => i.sourceType === "official-api:congress" && i.sourceRecordID);

    if (config.OPENSTATES_API_KEY) {
      for (const bill of stateBills.slice(0, 30)) {
        try {
          const added = await this.ingestOpenStatesVotes(bill.sourceRecordID!, bill.sourceFingerprint);
          openstatesCount += added;
          // Polite delay between calls to avoid rate limiting.
          await sleep(250);
        } catch (err) {
          this.logger.error("openstates vote fetch failed", {
            billId: bill.sourceRecordID,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    } else {
      skipped.push("openstates (OPENSTATES_API_KEY not set)");
    }

    if (config.CONGRESSGOV_API_KEY) {
      for (const bill of federalBills.slice(0, 30)) {
        try {
          const added = await this.ingestCongressVotes(bill.sourceRecordID!, bill.sourceFingerprint);
          congressCount += added;
          await sleep(250);
        } catch (err) {
          this.logger.error("congress vote fetch failed", {
            billId: bill.sourceRecordID,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    } else {
      skipped.push("congress (CONGRESSGOV_API_KEY not set)");
    }

    this.logger.info("vote ingest finished", { openstates: openstatesCount, congress: congressCount, skipped });
    return { openstates: openstatesCount, congress: congressCount, skipped };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OpenStates

  /**
   * OpenStates exposes votes nested inside the bill response. Pull the bill
   * with `include=votes` and store any vote_events returned.
   */
  private async ingestOpenStatesVotes(billId: string, fingerprint: string): Promise<number> {
    const url = new URL(`https://v3.openstates.org/bills/${encodeURIComponent(billId)}`);
    url.searchParams.set("include", "votes");
    url.searchParams.set("apikey", config.OPENSTATES_API_KEY ?? "");

    const res = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      if (res.status === 404) return 0;
      throw new Error(`OpenStates votes HTTP ${res.status}`);
    }
    const json = (await res.json()) as OpenStatesBillWithVotes;
    const events = json.votes ?? [];
    let added = 0;
    for (const event of events) {
      if (!event.start_date || !event.motion_text) continue;
      const byOfficial: Record<string, VoteOutcome> = {};
      for (const v of event.votes ?? []) {
        const name = v.voter_name?.trim();
        if (!name) continue;
        byOfficial[canonicalizeOfficialName(name)] = openStatesOption(v.option);
      }
      const totals = event.counts
        ? {
            yes: event.counts.find((c) => c.option === "yes")?.value ?? 0,
            no: event.counts.find((c) => c.option === "no")?.value ?? 0,
            abstain: event.counts.find((c) => c.option === "abstain")?.value ?? 0,
            absent: event.counts.find((c) => c.option === "absent")?.value ?? 0,
          }
        : tallyFrom(byOfficial);

      this.voteStore.upsert({
        issueFingerprint: fingerprint,
        billExternalID: billId,
        source: "openstates",
        chamber: event.organization?.classification ?? event.organization?.name ?? "",
        motion: event.motion_text,
        voteDateISO: event.start_date,
        result: openStatesResult(event.result),
        totals,
        byOfficialName: byOfficial,
      });
      added += 1;
    }
    return added;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Congress.gov

  /**
   * Congress.gov exposes votes per-chamber. The bill ID we stored is
   * "<congress>-<type>-<number>". We poll House + Senate roll-call endpoints
   * filtered by bill. Simpler v1: look up actions on the bill and pull any
   * roll-call links from there.
   */
  private async ingestCongressVotes(billId: string, fingerprint: string): Promise<number> {
    const parts = billId.split("-");
    if (parts.length !== 3) return 0;
    const [congress, billType, number] = parts;
    if (!congress || !billType || !number) return 0;

    const url = new URL(
      `https://api.congress.gov/v3/bill/${congress}/${billType.toLowerCase()}/${number}/actions`,
    );
    url.searchParams.set("limit", "20");
    url.searchParams.set("format", "json");
    url.searchParams.set("api_key", config.CONGRESSGOV_API_KEY ?? "");

    const res = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      if (res.status === 404) return 0;
      throw new Error(`Congress actions HTTP ${res.status}`);
    }
    const json = (await res.json()) as CongressActionsResponse;
    const actions = (json.actions ?? []).filter((a) => a.recordedVotes && a.recordedVotes.length > 0);

    let added = 0;
    for (const action of actions) {
      for (const vote of action.recordedVotes ?? []) {
        if (!vote.rollNumber || !vote.chamber || !vote.date) continue;
        // We don't pull per-member roll-call from this endpoint (it requires
        // a separate fetch per vote). Store the aggregate now; per-member
        // detail can be filled in later if needed.
        this.voteStore.upsert({
          issueFingerprint: fingerprint,
          billExternalID: billId,
          source: "congress",
          chamber: vote.chamber,
          motion: action.text ?? `Roll-call ${vote.rollNumber}`,
          voteDateISO: vote.date,
          result: congressVoteResult(action.text ?? ""),
          totals: { yes: 0, no: 0, abstain: 0, absent: 0 },
          byOfficialName: {},
        });
        added += 1;
      }
    }
    return added;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers + wire shapes

function tallyFrom(byOfficial: Record<string, VoteOutcome>): { yes: number; no: number; abstain: number; absent: number } {
  const counts = { yes: 0, no: 0, abstain: 0, absent: 0 };
  for (const v of Object.values(byOfficial)) {
    if (v === "yes") counts.yes += 1;
    else if (v === "no") counts.no += 1;
    else if (v === "abstain") counts.abstain += 1;
    else counts.absent += 1;
  }
  return counts;
}

function openStatesOption(opt: string | undefined): VoteOutcome {
  switch ((opt ?? "").toLowerCase()) {
    case "yes": return "yes";
    case "no": return "no";
    case "abstain": return "abstain";
    case "absent": return "absent";
    default: return "not-voting";
  }
}

function openStatesResult(result: string | undefined): VoteResult {
  switch ((result ?? "").toLowerCase()) {
    case "pass": case "passed": return "passed";
    case "fail": case "failed": return "failed";
    case "tie": return "tied";
    default: return "scheduled";
  }
}

function congressVoteResult(actionText: string): VoteResult {
  const t = actionText.toLowerCase();
  if (t.includes("passed") || t.includes("agreed to")) return "passed";
  if (t.includes("failed") || t.includes("rejected")) return "failed";
  return "scheduled";
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

interface OpenStatesBillWithVotes {
  votes?: Array<{
    start_date?: string;
    motion_text?: string;
    organization?: { name?: string; classification?: string };
    result?: string;
    counts?: Array<{ option: string; value: number }>;
    votes?: Array<{ voter_name?: string; option?: string }>;
  }>;
}

interface CongressActionsResponse {
  actions?: Array<{
    text?: string;
    actionDate?: string;
    recordedVotes?: Array<{
      rollNumber?: number;
      chamber?: string;
      date?: string;
      url?: string;
    }>;
  }>;
}
