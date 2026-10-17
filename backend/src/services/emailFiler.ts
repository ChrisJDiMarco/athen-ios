import { ServerClient } from "postmark";
import { config } from "../config.js";
import { CivicError } from "../lib/errors.js";
import type { DraftedMessage, ResolvedOfficial } from "../lib/types.js";

export interface FilingResult {
  providerMessageId: string;
  deliveredTo: string;
  dryRun: boolean;
}

export interface EmailFiler {
  send(args: { official: ResolvedOfficial; message: DraftedMessage; constituentZip: string }): Promise<FilingResult>;
}

/**
 * Picks the right filer based on what's configured:
 *  - Postmark token + from-address set → PostmarkEmailFiler (live or dry-run)
 *  - otherwise → LoggingEmailFiler (server log, no network call, dryRun=true)
 */
export function makeEmailFiler(): EmailFiler {
  if (config.POSTMARK_SERVER_TOKEN && config.EMAIL_FROM_ADDRESS) {
    return new PostmarkEmailFiler();
  }
  return new LoggingEmailFiler();
}

export class PostmarkEmailFiler implements EmailFiler {
  private readonly client: ServerClient;

  constructor(client?: ServerClient) {
    if (!config.POSTMARK_SERVER_TOKEN) {
      throw new CivicError(
        "postmark_not_configured",
        "PostmarkEmailFiler instantiated without POSTMARK_SERVER_TOKEN.",
        500,
      );
    }
    this.client = client ?? new ServerClient(config.POSTMARK_SERVER_TOKEN);
  }

  async send(args: {
    official: ResolvedOfficial;
    message: DraftedMessage;
    constituentZip: string;
  }): Promise<FilingResult> {
    const { official, message, constituentZip } = args;

    const recipient = config.EMAIL_DRY_RUN ? config.EMAIL_DRY_RUN_RECIPIENT : official.email;
    if (!recipient) {
      throw new CivicError(
        "dry_run_recipient_missing",
        "EMAIL_DRY_RUN is true but EMAIL_DRY_RUN_RECIPIENT is not set.",
        500,
      );
    }

    const subjectPrefix = config.EMAIL_DRY_RUN ? "[DRY RUN] " : "";
    const bodyPrefix = config.EMAIL_DRY_RUN
      ? `--- DRY RUN ---\nWould have been sent to: ${official.email}\nConstituent ZIP: ${constituentZip}\n\n`
      : "";

    const response = await this.client.sendEmail({
      From: `${config.EMAIL_FROM_NAME} <${config.EMAIL_FROM_ADDRESS}>`,
      To: recipient,
      Subject: `${subjectPrefix}${message.subject}`,
      TextBody: `${bodyPrefix}${message.body}`,
      MessageStream: "outbound",
    });

    return {
      providerMessageId: response.MessageID,
      deliveredTo: recipient,
      dryRun: config.EMAIL_DRY_RUN,
    };
  }
}

/**
 * Used when Postmark isn't configured. Records the filing to the server log
 * and returns a dry-run receipt so the iOS app still completes its flow.
 */
export class LoggingEmailFiler implements EmailFiler {
  async send(args: {
    official: ResolvedOfficial;
    message: DraftedMessage;
    constituentZip: string;
  }): Promise<FilingResult> {
    const { official, message, constituentZip } = args;
    const id = `local-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    // eslint-disable-next-line no-console
    console.log(
      `[athen] dry-run filing ${id} → ${official.name} <${official.email ?? "no-email"}> (ZIP ${constituentZip})\n  subject: ${message.subject}\n  body: ${message.body.slice(0, 200)}…`,
    );
    return {
      providerMessageId: id,
      deliveredTo: official.email ?? "logger://stdout",
      dryRun: true,
    };
  }
}
