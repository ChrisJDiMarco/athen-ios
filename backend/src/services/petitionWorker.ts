import type { FilingDispatcher } from "./filingDispatcher.js";
import type { ComposioService } from "./composio.js";
import type { PetitionStore } from "./petitionStore.js";
import { deliverPetition } from "./petitionDelivery.js";

type Logger = { info: (msg: string, meta?: object) => void; error: (msg: string, meta?: object) => void };

/**
 * Periodic loop that ships petitions whose threshold has been met or whose
 * deadline has passed. Conservative: at most one delivery per tick, and we
 * mark delivered before sending so a network blip can't double-fire.
 */
export class PetitionDeliveryWorker {
  private timer: NodeJS.Timeout | null = null;
  private inFlight = false;

  constructor(
    private readonly store: PetitionStore,
    private readonly dispatcher: FilingDispatcher,
    private readonly composio: ComposioService | null,
    private readonly logger: Logger,
    private readonly intervalMs: number = 10 * 60_000,
  ) {}

  start() {
    if (this.timer) return;
    // Run shortly after boot, then on the interval.
    this.timer = setInterval(() => void this.tick(), this.intervalMs);
    setTimeout(() => void this.tick(), 5_000);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  async tick(): Promise<void> {
    if (this.inFlight) return;
    this.inFlight = true;
    try {
      const ready = this.store.readyForDelivery();
      for (const petition of ready) {
        try {
          // Mark delivered first so a crash mid-send doesn't requeue forever.
          this.store.markDelivered(petition.id, {
            trackingId: `pending:${petition.id.slice(0, 8)}`,
            note: "Delivery in progress",
          });
          const result = await deliverPetition({
            petition,
            dispatcher: this.dispatcher,
            composio: this.composio,
          });
          this.store.markDelivered(petition.id, {
            trackingId: result.trackingId,
            note: result.note,
          });
          this.logger.info("petition delivered", {
            petitionId: petition.id,
            channel: result.channel,
            signers: petition.signatures.length,
          });
        } catch (err) {
          this.logger.error("petition delivery failed", {
            petitionId: petition.id,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    } finally {
      this.inFlight = false;
    }
  }
}
