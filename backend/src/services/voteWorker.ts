import type { VoteIngestor } from "./voteIngestor.js";

type Logger = { info: (msg: string, meta?: object) => void; error: (msg: string, meta?: object) => void };

/**
 * Background loop that polls upstream APIs for new roll-call vote data.
 * Runs less aggressively than the issue ingest because vote events are
 * sparse — a 30-min cadence is more than enough.
 */
export class VoteWorker {
  private timer: NodeJS.Timeout | null = null;
  private inFlight = false;

  constructor(
    private readonly ingestor: VoteIngestor,
    private readonly logger: Logger,
    private readonly intervalMs: number = 30 * 60_000,
  ) {}

  start() {
    if (this.timer) return;
    this.timer = setInterval(() => void this.tick(), this.intervalMs);
    // First run shortly after boot so the scorecard has something to work
    // with even before the periodic cycle kicks in.
    setTimeout(() => void this.tick(), 30_000);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  async tick(): Promise<void> {
    if (this.inFlight) return;
    this.inFlight = true;
    try {
      await this.ingestor.runOnce();
    } catch (err) {
      this.logger.error("vote worker tick failed", {
        error: err instanceof Error ? err.message : String(err),
      });
    } finally {
      this.inFlight = false;
    }
  }
}
