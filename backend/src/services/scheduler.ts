import type { JurisdictionIngestor, IngestionReport } from "./jurisdictionIngestor.js";

export interface ScheduledClient {
  type: "legistar";
  client: string;
  lookaheadDays?: number;
  limit?: number;
}

export interface SchedulerStatus {
  enabled: boolean;
  intervalMinutes: number;
  clients: ScheduledClient[];
  lastTick?: string;
  isRunning: boolean;
  lastReport?: Record<string, IngestionReport | { error: string }>;
}

export interface SchedulerLogger {
  info(msg: string, meta?: unknown): void;
  error(msg: string, meta?: unknown): void;
}

/**
 * Same-process ingestion scheduler. Good for single-instance deploys (Railway
 * Hobby, Fly free tier). For multi-instance deploys, split into a dedicated
 * worker process and use a lock (Redis SETNX or Postgres advisory lock) so
 * only one replica ticks at a time.
 */
export class IngestionScheduler {
  private readonly enabled: boolean;
  private readonly intervalMs: number;
  private readonly clients: ScheduledClient[];
  private readonly ingestor: JurisdictionIngestor;
  private readonly logger: SchedulerLogger;

  private timer: NodeJS.Timeout | null = null;
  private isRunning = false;
  private lastTickAt: Date | null = null;
  private lastReport: Record<string, IngestionReport | { error: string }> = {};

  constructor(args: {
    enabled: boolean;
    intervalMinutes: number;
    clients: ScheduledClient[];
    ingestor: JurisdictionIngestor;
    logger: SchedulerLogger;
  }) {
    this.enabled = args.enabled;
    this.intervalMs = Math.max(1, args.intervalMinutes) * 60_000;
    this.clients = args.clients;
    this.ingestor = args.ingestor;
    this.logger = args.logger;
  }

  start(): void {
    if (!this.enabled) {
      this.logger.info("scheduler: disabled (set INGEST_SCHEDULE_ENABLED=true to enable).");
      return;
    }
    if (this.clients.length === 0) {
      this.logger.info("scheduler: enabled but no clients configured; not scheduling.");
      return;
    }

    this.logger.info(
      `scheduler: enabled, polling ${this.clients.length} clients every ${this.intervalMs / 60_000} min.`,
    );
    // Fire a tick on boot so operators don't wait one full interval.
    void this.tick();
    this.timer = setInterval(() => void this.tick(), this.intervalMs);
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  status(): SchedulerStatus {
    return {
      enabled: this.enabled,
      intervalMinutes: this.intervalMs / 60_000,
      clients: this.clients,
      ...(this.lastTickAt ? { lastTick: this.lastTickAt.toISOString() } : {}),
      isRunning: this.isRunning,
      ...(Object.keys(this.lastReport).length > 0 ? { lastReport: this.lastReport } : {}),
    };
  }

  private async tick(): Promise<void> {
    if (this.isRunning) {
      this.logger.info("scheduler: previous tick still running, skipping.");
      return;
    }
    this.isRunning = true;
    this.lastTickAt = new Date();
    const report: Record<string, IngestionReport | { error: string }> = {};

    try {
      for (const cfg of this.clients) {
        if (cfg.type !== "legistar") continue;
        try {
          const args: Parameters<JurisdictionIngestor["ingestLegistar"]>[0] = {
            client: cfg.client,
          };
          if (cfg.lookaheadDays !== undefined) args.lookaheadDays = cfg.lookaheadDays;
          if (cfg.limit !== undefined) args.limit = cfg.limit;

          const r = await this.ingestor.ingestLegistar(args);
          report[cfg.client] = r;
          this.logger.info(
            `scheduler: ${cfg.client} → inspected=${r.inspected} inserted=${r.inserted} updated=${r.updated} failed=${r.failures.length}`,
          );
        } catch (err) {
          const errMsg = err instanceof Error ? err.message : String(err);
          report[cfg.client] = { error: errMsg };
          this.logger.error(`scheduler: ${cfg.client} failed`, err);
        }
      }
    } finally {
      this.lastReport = report;
      this.isRunning = false;
    }
  }
}

/**
 * Parses INGEST_CLIENTS env (e.g. "legistar:phila,legistar:nyc:14:20" — client
 * name with optional `:lookaheadDays:limit`) into typed configs.
 */
export function parseClientsEnv(raw: string | undefined): ScheduledClient[] {
  if (!raw || raw.trim().length === 0) return [];
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map((entry): ScheduledClient | null => {
      const parts = entry.split(":");
      if (parts.length < 2) return null;
      const [type, client, lookaheadRaw, limitRaw] = parts;
      if (type !== "legistar" || !client) return null;
      const cfg: ScheduledClient = { type: "legistar", client };
      const lookahead = lookaheadRaw ? Number(lookaheadRaw) : NaN;
      if (Number.isFinite(lookahead) && lookahead > 0) cfg.lookaheadDays = lookahead;
      const limit = limitRaw ? Number(limitRaw) : NaN;
      if (Number.isFinite(limit) && limit > 0) cfg.limit = limit;
      return cfg;
    })
    .filter((c): c is ScheduledClient => c !== null);
}
