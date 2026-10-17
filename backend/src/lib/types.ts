export type CivicAction = "endorse" | "oppose";

export interface IssuePayload {
  id: string;
  title: string;
  category: string;
  jurisdiction: string;
  sourceName: string;
  summary: string;
  facts: { label: string; value: string }[];
  voteDateISO: string;
}

export interface VerifiedAddress {
  raw: string;
  normalized: string;
  latitude: number;
  longitude: number;
  zipCode: string;
}

export type FilingChannel = "email" | "contact-form-queue";

export interface ResolvedOfficial {
  name: string;
  title: string;
  district: string;
  email: string;
  source: string;
  /**
   * Preferred delivery channel.
   * - "email": direct delivery via Postmark.
   * - "contact-form-queue": queued for submission to the official's public
   *   contact form. Real production submits via Playwright + CWC partnership
   *   or vendor (Phone2Action / Quorum). v1 queues to JSON for operator
   *   review; the iOS receipt reflects "queued" state honestly.
   */
  channel?: FilingChannel;
  /** Form URL when channel is "contact-form-queue". */
  contactFormURL?: string;
  /** Stable identifier for partner integrations (e.g. bioguide). */
  externalID?: string;
}

export interface DraftedMessage {
  subject: string;
  body: string;
}

export interface FilingReceipt {
  action: CivicAction;
  sentAt: string;
  officialName: string;
  confirmationCode: string;
  messagePreview: string;
}
