import { randomBytes } from "node:crypto";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function newConfirmationCode(prefix = "COS"): string {
  const bytes = randomBytes(6);
  let suffix = "";
  for (let i = 0; i < bytes.length; i++) {
    suffix += ALPHABET[bytes[i]! % ALPHABET.length];
  }
  return `${prefix}-${suffix}`;
}
