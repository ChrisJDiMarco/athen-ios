import dotenv from "dotenv";
import { z } from "zod";

// `override: true` so .env wins over whatever was in the parent shell — keeps
// the backend deterministic regardless of how the operator launched node.
dotenv.config({ override: true });

// Treat empty strings as unset for optional fields (zod doesn't by default).
const optionalEmail = z
  .preprocess((v) => (typeof v === "string" && v.trim() === "" ? undefined : v), z.string().email().optional());
const optionalString = z
  .preprocess((v) => (typeof v === "string" && v.trim() === "" ? undefined : v), z.string().optional());

const schema = z.object({
  PORT: z.coerce.number().int().positive().default(8787),
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),

  ANTHROPIC_API_KEY: z.string().min(1, "ANTHROPIC_API_KEY is required"),
  ANTHROPIC_MODEL: z.string().default("claude-sonnet-4-6"),

  // Postmark is optional in dry-run dev. When unset, filings are logged and
  // the receipt is marked dryRun=true so the iOS app can render "queued".
  POSTMARK_SERVER_TOKEN: optionalString,
  EMAIL_FROM_ADDRESS: optionalEmail,
  EMAIL_FROM_NAME: z.string().default("Athen"),

  EMAIL_DRY_RUN: z
    .string()
    .default("true")
    .transform((v) => v.toLowerCase() !== "false"),
  EMAIL_DRY_RUN_RECIPIENT: optionalEmail,

  OPENSTATES_API_KEY: optionalString,
  OPENSTATES_JURISDICTIONS: optionalString,

  CONGRESSGOV_API_KEY: optionalString,
  GOVINFO_API_KEY: optionalString,
  REGULATIONS_API_KEY: optionalString,
  SOCRATA_APP_TOKEN: optionalString,
  SOCRATA_CATALOG_DOMAINS: optionalString,
  OPEN311_ENDPOINTS: optionalString,

  ELEVENLABS_API_KEY: optionalString,
  ELEVENLABS_AGENT_ID: optionalString,
  ELEVENLABS_MODEL: z.string().default("eleven_turbo_v2_5"),
  ELEVENLABS_VOICE_ID: z.string().default("EXAVITQu4vr4xnSDxMaL"),

  FIRECRAWL_API_KEY: optionalString,

  // Composio bridges the app to user-owned third-party tools (Gmail,
  // Calendar, Slack, Notion, etc.) via OAuth. Per-user connections are
  // identified by an entity id (we use the device install id).
  COMPOSIO_API_KEY: optionalString,
  COMPOSIO_REDIRECT_URI: optionalString,

  // Google Civic Information API — powers polling place lookups,
  // upcoming-elections list, and sample-ballot fetch (voterInfoQuery).
  // Falls back to static state data + "look it up at vote.gov" when missing.
  GOOGLE_CIVIC_API_KEY: optionalString,

  // OpenSecrets API — federal campaign finance + lobbying data. Powers
  // the "money trail" surface on rep scorecards.
  OPENSECRETS_API_KEY: optionalString,

  ADMIN_API_TOKEN: optionalString,

  // When true, every /v1/* route requires X-Athen-Install header (per-install
  // UUID). Default off for dev. Production deploy MUST set to true.
  INSTALL_AUTH_REQUIRED: z
    .string()
    .default("false")
    .transform((v) => v.toLowerCase() === "true"),

  INGEST_SCHEDULE_ENABLED: z
    .string()
    .default("false")
    .transform((v) => v.toLowerCase() === "true"),
  INGEST_INTERVAL_MINUTES: z.coerce.number().int().positive().default(360),
  INGEST_CLIENTS: z.string().default(""),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  const issues = parsed.error.issues
    .map((i) => `  • ${i.path.join(".")}: ${i.message}`)
    .join("\n");
  throw new Error(`Invalid environment configuration:\n${issues}`);
}

export const config = parsed.data;
export type Config = typeof config;
