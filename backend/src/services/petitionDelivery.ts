import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import type { StoredPetition } from "./petitionStore.js";
import type { FilingDispatcher } from "./filingDispatcher.js";
import type { ComposioService } from "./composio.js";

export interface PetitionPacket {
  subject: string;
  body: string;
  signerCount: number;
}

export interface PetitionDeliveryResult {
  trackingId: string;
  channel: "email" | "user-gmail" | "contact-form-queue" | "log-only";
  deliveredTo: string;
  note: string;
}

let _client: Anthropic | null = null;
function claudeClient(): Anthropic {
  if (!_client) _client = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
  return _client;
}

/**
 * Builds the email body that lands in the target official's inbox. Claude
 * writes a short cover letter from the petition title + ask + body + signer
 * count, then we append the signature roll deterministically (no LLM in the
 * receipt section — signers see their exact name + zip + comment as filed).
 */
export async function buildPacket(petition: StoredPetition): Promise<PetitionPacket> {
  const signerCount = petition.signatures.length;
  const targets = petition.targets.map((t) => t.officialName).join(", ");
  const zipBreakdown = summarizeZips(petition.signatures.map((s) => s.zip).filter(Boolean));

  const system = `You write formal cover letters that accompany constituent petitions to elected officials. Tone: respectful, plain, specific. No hyperbole. 4-6 sentences. Address the official(s) directly. Lead with the ask, then why, then call to action. Do not invent statistics or sources beyond what the petition body provides.`;

  const userPrompt = `PETITION TITLE: ${petition.title}
ASK: ${petition.ask}
BODY: ${petition.body}
TARGET: ${targets}
SIGNERS: ${signerCount} verified constituents
SIGNER LOCATIONS: ${zipBreakdown}

Write a 4-6 sentence cover letter that introduces the petition and asks the official(s) to take the action requested. No subject line in your output, no salutation header — just the body paragraphs.`;

  let coverLetter = "";
  try {
    const response = await claudeClient().messages.create({
      model: config.ANTHROPIC_MODEL,
      max_tokens: 600,
      system,
      messages: [{ role: "user", content: userPrompt }],
    });
    const text = response.content.find((b) => b.type === "text");
    if (text && text.type === "text") coverLetter = text.text.trim();
  } catch (err) {
    // Fall back to a deterministic letter so delivery never blocks on
    // Claude. The signer roll is the most important part anyway.
    coverLetter = fallbackLetter(petition);
  }
  if (!coverLetter) coverLetter = fallbackLetter(petition);

  const signatureRoll = petition.signatures
    .map((s, idx) => {
      const num = `${idx + 1}.`.padStart(4, " ");
      const loc = s.zip ? ` (ZIP ${s.zip})` : "";
      const note = s.comment ? `\n      "${s.comment.trim()}"` : "";
      return `${num} ${s.name}${loc}${note}`;
    })
    .join("\n");

  const subject = petition.ask.length > 80
    ? `Constituent petition: ${petition.title}`
    : `Constituent petition: ${petition.ask}`;

  const body = [
    `Dear ${targets},`,
    "",
    coverLetter,
    "",
    `THE PETITION`,
    `Title: ${petition.title}`,
    `Ask: ${petition.ask}`,
    "",
    petition.body,
    "",
    `SIGNATURES (${signerCount} verified constituents)`,
    signatureRoll,
    "",
    "This petition was assembled by Athen, a civic engagement app that verifies each signature against a unique device installation. Constituents have authorized the delivery of their names and ZIP codes to your office.",
    "",
    "Sincerely,",
    `${petition.creatorDisplayName} (petition organizer) on behalf of all signers`,
  ].join("\n");

  return { subject, body, signerCount };
}

/** Picks a delivery channel and ships the packet. */
export async function deliverPetition(args: {
  petition: StoredPetition;
  dispatcher: FilingDispatcher;
  composio: ComposioService | null;
}): Promise<PetitionDeliveryResult> {
  const packet = await buildPacket(args.petition);

  // Pick first email target as the primary recipient. Cc the rest.
  const emailTargets = args.petition.targets.filter((t) => t.channel === "email" && t.email);
  const contactFormTargets = args.petition.targets.filter((t) => t.channel === "contact-form-queue");

  if (emailTargets.length > 0) {
    const primary = emailTargets[0]!;
    // If the creator has Composio Gmail connected, deliver from their inbox.
    if (args.composio) {
      try {
        const exec = await args.composio.executeAction({
          entityId: args.petition.creatorEntityId,
          actionName: "GMAIL_SEND_EMAIL",
          input: {
            recipient_email: primary.email,
            subject: packet.subject,
            body: packet.body,
            is_html: false,
            cc: emailTargets.slice(1).map((t) => t.email).filter(Boolean),
          },
        });
        if (exec.successful) {
          return {
            trackingId: `gmail:${args.petition.creatorEntityId.slice(0, 8)}:${args.petition.id.slice(0, 8)}`,
            channel: "user-gmail",
            deliveredTo: primary.email!,
            note: `Sent from the organizer's Gmail to ${primary.officialName}${emailTargets.length > 1 ? ` (+${emailTargets.length - 1} cc'd)` : ""}.`,
          };
        }
      } catch {
        // Fall through to backend dispatcher.
      }
    }

    // Fall back to the backend email dispatcher.
    const dispatch = await args.dispatcher.dispatch({
      official: {
        name: primary.officialName,
        title: "",
        district: "",
        email: primary.email,
        contactTarget: primary.email!,
        channel: "email",
      } as any,
      message: { subject: packet.subject, body: packet.body },
      constituentZip: args.petition.signatures[0]?.zip ?? "",
    });
    return {
      trackingId: dispatch.trackingId,
      channel: "email",
      deliveredTo: dispatch.deliveredTo,
      note: `${dispatch.statusNote} ${emailTargets.length > 1 ? `(${emailTargets.length - 1} additional target(s) not delivered — only primary in v1.)` : ""}`.trim(),
    };
  }

  if (contactFormTargets.length > 0) {
    const primary = contactFormTargets[0]!;
    const dispatch = await args.dispatcher.dispatch({
      official: {
        name: primary.officialName,
        title: "",
        district: "",
        contactFormURL: primary.contactFormURL,
        channel: "contact-form-queue",
        contactTarget: primary.contactFormURL ?? primary.officialName,
      } as any,
      message: { subject: packet.subject, body: packet.body },
      constituentZip: args.petition.signatures[0]?.zip ?? "",
    });
    return {
      trackingId: dispatch.trackingId,
      channel: "contact-form-queue",
      deliveredTo: dispatch.deliveredTo,
      note: dispatch.statusNote,
    };
  }

  // No usable channel — log only so the creator can route manually.
  return {
    trackingId: `log:${args.petition.id}`,
    channel: "log-only",
    deliveredTo: args.petition.targets.map((t) => t.officialName).join(", "),
    note: "No deliverable channel resolved. Organizer should route manually.",
  };
}

function fallbackLetter(petition: StoredPetition): string {
  return `We the undersigned constituents of ${petition.targets[0]?.jurisdiction ?? "your jurisdiction"} are writing to ask you to ${petition.ask.toLowerCase().replace(/\.$/, "")}. ${petition.body.split("\n").filter(Boolean).slice(0, 2).join(" ")} We urge you to take the action requested above and would appreciate a substantive response indicating your position.`;
}

function summarizeZips(zips: string[]): string {
  if (zips.length === 0) return "no zip data on file";
  const counts = new Map<string, number>();
  for (const zip of zips) {
    const prefix = zip.slice(0, 3);
    counts.set(prefix, (counts.get(prefix) ?? 0) + 1);
  }
  const top = Array.from(counts.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([prefix, count]) => `${prefix}xx (${count})`);
  return top.join(", ");
}
