import { createHash } from "node:crypto";
import { CivicError } from "../lib/errors.js";
import type { IngestionPipeline } from "./ingestionPipeline.js";
import type { LegistarConnector, LegistarMatterFull } from "./connectors/legistar.js";
import { LEGISTAR_CLIENTS } from "./connectors/legistar.js";
import type { IssueStore, StoredScope } from "./issueStore.js";
import { storedIssueFromIngested } from "./issueNormalizer.js";
import type { EvidenceVault } from "./evidenceVault.js";

export interface IngestionReport {
  inspected: number;
  inserted: number;
  updated: number;
  skipped: number;
  failures: { matterId?: number; error: string }[];
}

export interface JurisdictionIngestor {
  ingestLegistar(args: { client: string; lookaheadDays?: number; limit?: number }): Promise<IngestionReport>;
}

export class DefaultJurisdictionIngestor implements JurisdictionIngestor {
  constructor(
    private readonly connector: LegistarConnector,
    private readonly pipeline: IngestionPipeline,
    private readonly store: IssueStore,
    private readonly evidenceVault?: EvidenceVault,
  ) {}

  async ingestLegistar(args: {
    client: string;
    lookaheadDays?: number;
    limit?: number;
  }): Promise<IngestionReport> {
    const config = LEGISTAR_CLIENTS[args.client.toLowerCase()];
    if (!config) {
      throw new CivicError(
        "unknown_legistar_client",
        `No Legistar client registered for "${args.client}".`,
        400,
      );
    }

    const matters = await this.connector.collectUpcomingMatters(
      args.client,
      args.lookaheadDays ?? 21,
    );

    const report: IngestionReport = {
      inspected: matters.length,
      inserted: 0,
      updated: 0,
      skipped: 0,
      failures: [],
    };

    const slice = args.limit ? matters.slice(0, args.limit) : matters;

    for (const full of slice) {
      try {
        const fingerprint = this.fingerprintFor(args.client, full);
        const existing = this.store.byFingerprint(fingerprint);

        const ingested = await this.pipeline.ingestFromStructured({
          sourceURL: full.detailURL,
          jurisdiction: config.jurisdictionName,
          scopeHint: config.scope as StoredScope,
          defaultContactTarget: config.defaultContactTarget,
          fields: {
            "Matter file number": full.matter.MatterFile,
            "Matter name": full.matter.MatterName,
            "Matter title": full.matter.MatterTitle,
            "Matter type": full.matter.MatterTypeName,
            "Matter status": full.matter.MatterStatusName,
            "Committee or body": full.matter.MatterBodyName,
            "Introduced": full.matter.MatterIntroDate,
            "Next agenda date": full.matter.MatterAgendaDate,
            "Attachments": full.attachments.map((a) => a.MatterAttachmentName).join("; "),
          },
        });

        const storedInput = storedIssueFromIngested(ingested, {
          sourceFingerprint: fingerprint,
          sourceRecordID: String(full.matter.MatterId),
          sourceType: "legistar",
        });
        if (config.scope === "local-philly") storedInput.stateCode = "PA";
        storedInput.filingRoute = {
          verificationStep: "Verified address confirms eligibility in this jurisdiction.",
          routingStep: `Routing agent maps your address to the ${full.matter.MatterBodyName ?? ingested.jurisdiction}.`,
          destinationStep: `Message is filed to ${ingested.officialContactTarget}.`,
          deliveryWindow: "Typical confirmation within a few minutes",
        };

        const stored = await this.store.upsert({
          ...storedInput,
          sourceFingerprint: fingerprint,
          scope: ingested.scope as StoredScope,
          ...(config.scope === "local-philly" ? { stateCode: "PA" } : {}),
        });
        await this.evidenceVault?.upsertFromIssue(stored);

        if (existing) {
          report.updated += 1;
        } else {
          report.inserted += 1;
        }
        void stored;
      } catch (err) {
        report.failures.push({
          matterId: full.matter.MatterId,
          error: err instanceof Error ? err.message : String(err),
        });
        report.skipped += 1;
      }
    }

    return report;
  }

  private fingerprintFor(client: string, full: LegistarMatterFull): string {
    return createHash("sha1")
      .update(`legistar:${client}:${full.matter.MatterId}:${full.matter.MatterAgendaDate ?? ""}`)
      .digest("hex");
  }
}
