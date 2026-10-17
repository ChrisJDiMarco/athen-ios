import type { DraftedMessage, ResolvedOfficial, FilingChannel } from "../lib/types.js";
import type { EmailFiler, FilingResult } from "./emailFiler.js";
import type { ContactFormQueue } from "./contactFormQueue.js";

export interface DispatchResult {
  channel: FilingChannel;
  trackingId: string;
  deliveredTo: string;
  queued: boolean;
  dryRun: boolean;
  /** Human-friendly status line surfaced in the iOS receipt. */
  statusNote: string;
}

export interface FilingDispatcher {
  dispatch(args: {
    official: ResolvedOfficial;
    message: DraftedMessage;
    constituentZip: string;
    constituentStateCode?: string;
  }): Promise<DispatchResult>;
}

export class ChannelAwareFilingDispatcher implements FilingDispatcher {
  constructor(
    private readonly emailFiler: EmailFiler,
    private readonly contactFormQueue: ContactFormQueue,
  ) {}

  async dispatch(args: {
    official: ResolvedOfficial;
    message: DraftedMessage;
    constituentZip: string;
    constituentStateCode?: string;
  }): Promise<DispatchResult> {
    const channel: FilingChannel = args.official.channel ?? "email";

    if (channel === "contact-form-queue") {
      return this.queueContactForm(args);
    }
    return this.sendEmail(args);
  }

  private async sendEmail(args: {
    official: ResolvedOfficial;
    message: DraftedMessage;
    constituentZip: string;
  }): Promise<DispatchResult> {
    const result: FilingResult = await this.emailFiler.send({
      official: args.official,
      message: args.message,
      constituentZip: args.constituentZip,
    });

    return {
      channel: "email",
      trackingId: result.providerMessageId,
      deliveredTo: result.deliveredTo,
      queued: false,
      dryRun: result.dryRun,
      statusNote: result.dryRun
        ? `Test send: rerouted to ${result.deliveredTo}.`
        : `Delivered via email to ${result.deliveredTo}.`,
    };
  }

  private async queueContactForm(args: {
    official: ResolvedOfficial;
    message: DraftedMessage;
    constituentZip: string;
    constituentStateCode?: string;
  }): Promise<DispatchResult> {
    const submission = await this.contactFormQueue.enqueue({
      ...(args.official.externalID ? { bioguide: args.official.externalID } : {}),
      officialName: args.official.name,
      ...(args.official.contactFormURL ? { contactFormURL: args.official.contactFormURL } : {}),
      constituent: {
        zipCode: args.constituentZip,
        ...(args.constituentStateCode ? { stateCode: args.constituentStateCode } : {}),
      },
      message: args.message,
    });

    const target = args.official.contactFormURL ?? args.official.name;
    return {
      channel: "contact-form-queue",
      trackingId: submission.id,
      deliveredTo: target,
      queued: true,
      dryRun: false,
      statusNote:
        args.official.contactFormURL
          ? `Queued for ${args.official.name}'s public contact form. We'll submit it within the next hour.`
          : `Queued for ${args.official.name}. No public form URL on file; an operator will route it manually.`,
    };
  }
}
