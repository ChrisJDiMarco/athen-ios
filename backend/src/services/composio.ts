import { config } from "../config.js";

/**
 * Thin wrapper around the Composio HTTP API. Composio bridges our backend to
 * user-owned third-party apps (Gmail, Calendar, Slack, Notion, etc.) via
 * OAuth. We identify each user by a stable `entityId` — the iOS install id —
 * so the same user's connections persist across requests.
 *
 * Talks to REST directly rather than depending on a specific SDK shape that
 * keeps drifting between Composio releases.
 */

const COMPOSIO_BASE = "https://backend.composio.dev";

export interface ComposioApp {
  appName: string;
  displayName: string;
  systemImage: string;
  description: string;
}

/** Apps we surface to the user. Add freely as we wire more actions. */
export const COMPOSIO_APPS: ComposioApp[] = [
  {
    appName: "gmail",
    displayName: "Gmail",
    systemImage: "envelope.fill",
    description: "Send filings from your own Gmail. Replies come straight to you, not us.",
  },
  {
    appName: "googlecalendar",
    displayName: "Google Calendar",
    systemImage: "calendar",
    description: "Auto-add vote deadlines and comment windows to your calendar when you bookmark a bill.",
  },
  {
    appName: "slack",
    displayName: "Slack",
    systemImage: "bubble.left.and.bubble.right.fill",
    description: "Post group rallies to a Slack channel your crew already uses.",
  },
  {
    appName: "notion",
    displayName: "Notion",
    systemImage: "doc.text.fill",
    description: "Log every filing receipt to a Notion database for your civic record.",
  },
  {
    appName: "discord",
    displayName: "Discord",
    systemImage: "bubble.left.and.text.bubble.right.fill",
    description: "Cross-post group rallies + petition deliveries to a Discord server channel.",
  },
  {
    appName: "twitter",
    displayName: "X (Twitter)",
    systemImage: "bird.fill",
    description: "Optionally post your filings — tagged at the official — to X.",
  },
  {
    appName: "linkedin",
    displayName: "LinkedIn",
    systemImage: "briefcase.fill",
    description: "Share petition wins and filings as professional civic-engagement updates.",
  },
];

export interface ConnectionStatus {
  appName: string;
  isConnected: boolean;
  connectionId?: string;
  connectedAtISO?: string;
  status?: "INITIATED" | "ACTIVE" | "FAILED" | "EXPIRED";
}

export interface InitiateConnectionResult {
  connectionId: string;
  redirectUrl: string;
  status: string;
}

export interface ExecuteActionResult {
  successful: boolean;
  data?: unknown;
  error?: string;
}

export class ComposioService {
  private readonly apiKey: string;
  /** Cache of toolkit slug → composio-managed auth_config_id. v3 requires
   *  an auth_config_id when initiating a connection; this lookup adds one
   *  extra round-trip the first time the user tries to connect a given
   *  app, then is permanent for the process lifetime. */
  private authConfigCache = new Map<string, string>();

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  static fromEnv(): ComposioService | null {
    if (!config.COMPOSIO_API_KEY) return null;
    return new ComposioService(config.COMPOSIO_API_KEY);
  }

  /** List per-app status for one user (v3). */
  async statusFor(entityId: string): Promise<ConnectionStatus[]> {
    const url = new URL("/api/v3/connected_accounts", COMPOSIO_BASE);
    url.searchParams.set("user_id", entityId);
    const response = await this.fetch(url);
    const payload = (await this.parseJson(response)) as {
      items?: Array<{
        id: string;
        status: string;
        created_at?: string;
        toolkit?: { slug?: string };
      }>;
    };
    const byApp = new Map<string, ConnectionStatus>();
    for (const item of payload.items ?? []) {
      const slug = item.toolkit?.slug;
      if (!slug) continue;
      const existing = byApp.get(slug);
      // If the user reconnected, prefer the ACTIVE record over older ones.
      if (!existing || item.status === "ACTIVE") {
        const next: ConnectionStatus = {
          appName: slug,
          isConnected: item.status === "ACTIVE",
          connectionId: item.id,
        };
        const statusValue = item.status as ConnectionStatus["status"];
        if (statusValue) next.status = statusValue;
        if (item.created_at) next.connectedAtISO = item.created_at;
        byApp.set(slug, next);
      }
    }
    return COMPOSIO_APPS.map(
      (app) =>
        byApp.get(app.appName) ?? {
          appName: app.appName,
          isConnected: false,
        },
    );
  }

  /** Kick off an OAuth flow (v3). Returns the redirect URL the user opens. */
  async initiateConnection(entityId: string, appName: string): Promise<InitiateConnectionResult> {
    const authConfigId = await this.resolveAuthConfigId(appName);
    const url = new URL("/api/v3/connected_accounts", COMPOSIO_BASE);
    const body: Record<string, unknown> = {
      auth_config: { id: authConfigId },
      connection: { user_id: entityId },
    };
    if (config.COMPOSIO_REDIRECT_URI) {
      // v3 redirect override goes on the connection block.
      (body.connection as Record<string, unknown>).callback_url = config.COMPOSIO_REDIRECT_URI;
    }
    const response = await this.fetch(url, {
      method: "POST",
      body: JSON.stringify(body),
    });
    const payload = (await this.parseJson(response)) as {
      id?: string;
      status?: string;
      redirect_url?: string;
      redirect_uri?: string;
    };
    const redirect = payload.redirect_url ?? payload.redirect_uri;
    if (!payload.id || !redirect) {
      throw new Error("Composio did not return a redirect URL");
    }
    return {
      connectionId: payload.id,
      redirectUrl: redirect,
      status: payload.status ?? "INITIATED",
    };
  }

  /** Revoke a connection (v3). */
  async disconnect(connectionId: string): Promise<void> {
    const url = new URL(`/api/v3/connected_accounts/${connectionId}`, COMPOSIO_BASE);
    await this.fetch(url, { method: "DELETE" });
  }

  /**
   * Look up (and cache) the composio-managed auth_config_id for a toolkit
   * slug. v3 requires this when initiating a connection.
   */
  private async resolveAuthConfigId(toolkitSlug: string): Promise<string> {
    const cached = this.authConfigCache.get(toolkitSlug);
    if (cached) return cached;
    const url = new URL("/api/v3/auth_configs", COMPOSIO_BASE);
    url.searchParams.set("toolkit_slug", toolkitSlug);
    const response = await this.fetch(url);
    const payload = (await this.parseJson(response)) as {
      items?: Array<{ id: string; is_composio_managed?: boolean; status?: string }>;
    };
    const items = payload.items ?? [];
    // Prefer a composio-managed + enabled config; fall back to first item.
    const pick =
      items.find((a) => a.is_composio_managed && a.status === "ENABLED")
      ?? items.find((a) => a.is_composio_managed)
      ?? items[0];
    if (!pick?.id) {
      throw new Error(`No auth_config available for toolkit "${toolkitSlug}". Open Composio dashboard → Auth Configs and enable one for this app.`);
    }
    this.authConfigCache.set(toolkitSlug, pick.id);
    return pick.id;
  }

  /**
   * Dispatches one of Athen's typed automations to the right Composio
   * action. Centralizing the action-name lookup here means iOS doesn't need
   * to know Composio's verbose naming (and survives renames).
   */
  async runAutomation(params: {
    entityId: string;
    automation: AutomationName;
    input: AutomationInput;
  }): Promise<ExecuteActionResult> {
    const mapping = AUTOMATION_MAP[params.automation];
    if (!mapping) {
      return { successful: false, error: `unknown_automation:${params.automation}` };
    }
    const actionInput = mapping.transform(params.input);
    return this.executeAction({
      entityId: params.entityId,
      actionName: mapping.actionName,
      input: actionInput,
    });
  }

  /** Execute a Composio action on behalf of one user (v3). */
  async executeAction(params: {
    entityId: string;
    actionName: string;
    input: Record<string, unknown>;
  }): Promise<ExecuteActionResult> {
    const url = new URL(`/api/v3/tools/execute/${params.actionName}`, COMPOSIO_BASE);
    const response = await this.fetch(url, {
      method: "POST",
      body: JSON.stringify({
        user_id: params.entityId,
        arguments: params.input,
      }),
    });
    const payload = (await this.parseJson(response)) as {
      successful?: boolean;
      data?: unknown;
      error?: string;
    };
    const result: ExecuteActionResult = {
      successful: payload.successful ?? false,
    };
    if (payload.data !== undefined) result.data = payload.data;
    if (payload.error) result.error = payload.error;
    return result;
  }

  private async fetch(url: URL, init: RequestInit = {}): Promise<Response> {
    const headers: Record<string, string> = {
      "x-api-key": this.apiKey,
      "content-type": "application/json",
      accept: "application/json",
      ...(init.headers as Record<string, string> | undefined),
    };
    const response = await fetch(url.toString(), { ...init, headers });
    return response;
  }

  private async parseJson(response: Response): Promise<unknown> {
    const text = await response.text();
    if (!response.ok) {
      let message = `Composio ${response.status}`;
      try {
        const parsed = JSON.parse(text) as { message?: string; error?: string };
        message = parsed.message ?? parsed.error ?? text.slice(0, 200);
      } catch {
        message = text.slice(0, 200) || message;
      }
      throw new Error(message);
    }
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch {
      throw new Error(`Composio returned non-JSON: ${text.slice(0, 200)}`);
    }
  }
}

// MARK: - Automation routing
//
// Each typed Athen automation maps to a single Composio action. The
// transform function converts our friendly inputs to the action's exact
// schema. When Composio renames an action, only this table needs updating.

export type AutomationName =
  | "calendar_event"
  | "notion_log"
  | "slack_message"
  | "discord_message"
  | "twitter_post"
  | "linkedin_post"
  | "gmail_email";

export interface AutomationInput {
  /** Calendar event */
  title?: string | undefined;
  startISO?: string | undefined;
  endISO?: string | undefined;
  notes?: string | undefined;
  location?: string | undefined;
  /** Notion */
  databaseId?: string | undefined;
  pageTitle?: string | undefined;
  properties?: Record<string, unknown> | undefined;
  /** Slack / Discord */
  channel?: string | undefined;
  text?: string | undefined;
  /** Social */
  body?: string | undefined;
  hashtags?: string[] | undefined;
  /** Gmail */
  to?: string | undefined;
  subject?: string | undefined;
}

interface AutomationMapping {
  actionName: string;
  transform: (input: AutomationInput) => Record<string, unknown>;
}

const AUTOMATION_MAP: Record<AutomationName, AutomationMapping> = {
  calendar_event: {
    actionName: "GOOGLECALENDAR_CREATE_EVENT",
    transform: (input) => {
      const out: Record<string, unknown> = {
        summary: input.title ?? "Civic deadline",
        description: input.notes ?? "",
      };
      if (input.startISO) out.start_datetime = input.startISO;
      if (input.endISO) out.end_datetime = input.endISO;
      if (input.location) out.location = input.location;
      // Composio's Google Calendar action defaults to the user's primary calendar.
      out.calendar_id = "primary";
      return out;
    },
  },
  notion_log: {
    actionName: "NOTION_INSERT_ROW_DATABASE",
    transform: (input) => ({
      database_id: input.databaseId ?? "",
      properties: input.properties ?? {
        Name: { title: [{ text: { content: input.pageTitle ?? "Civic action" } }] },
      },
    }),
  },
  slack_message: {
    actionName: "SLACK_SENDS_A_MESSAGE_TO_A_SLACK_CHANNEL",
    transform: (input) => ({
      channel: input.channel ?? "",
      text: input.text ?? "",
    }),
  },
  discord_message: {
    actionName: "DISCORD_SEND_MESSAGE",
    transform: (input) => ({
      channel_id: input.channel ?? "",
      content: input.text ?? "",
    }),
  },
  twitter_post: {
    actionName: "TWITTER_CREATION_OF_A_POST",
    transform: (input) => {
      const tags = input.hashtags && input.hashtags.length > 0
        ? "\n\n" + input.hashtags.map((t) => (t.startsWith("#") ? t : `#${t}`)).join(" ")
        : "";
      return { text: (input.body ?? input.text ?? "") + tags };
    },
  },
  linkedin_post: {
    actionName: "LINKEDIN_CREATE_LINKEDIN_POST",
    transform: (input) => ({
      commentary: input.body ?? input.text ?? "",
      visibility: "PUBLIC",
    }),
  },
  gmail_email: {
    actionName: "GMAIL_SEND_EMAIL",
    transform: (input) => ({
      recipient_email: input.to ?? "",
      subject: input.subject ?? "",
      body: input.body ?? input.text ?? "",
      is_html: false,
    }),
  },
};
