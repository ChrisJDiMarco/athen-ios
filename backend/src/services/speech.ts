import { config } from "../config.js";

// Lightweight ElevenLabs TTS wrapper. Caller passes already-written text;
// no Claude prompt-shaping here. Used for "read aloud" buttons on brief,
// petition, official, and life-event surfaces.

export interface SpeechRequest {
  text: string;
  voiceId?: string;
  modelId?: string;
  stability?: number;
  similarityBoost?: number;
  style?: number;
  speakerBoost?: boolean;
}

export type SpeechResult =
  | {
      provider: "elevenlabs";
      contentType: "audio/mpeg";
      base64: string;
      bytes: number;
      voiceId: string;
      modelId: string;
    }
  | { provider: "client-fallback"; reason: string };

// ElevenLabs caps a single request at 5,000 characters on most plans.
// Trim defensively and let the iOS layer chunk if it ever needs more.
const MAX_CHARS = 4_800;

export class SpeechService {
  async synthesize(request: SpeechRequest): Promise<SpeechResult> {
    if (!config.ELEVENLABS_API_KEY) {
      return { provider: "client-fallback", reason: "ELEVENLABS_API_KEY is not set" };
    }
    const text = request.text.trim();
    if (!text) {
      return { provider: "client-fallback", reason: "Empty text" };
    }

    const trimmed = text.length > MAX_CHARS ? `${text.slice(0, MAX_CHARS).trimEnd()}…` : text;
    const voiceId = (request.voiceId ?? config.ELEVENLABS_VOICE_ID).trim();
    const modelId = (request.modelId ?? config.ELEVENLABS_MODEL).trim();

    const url = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceId)}`;

    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          Accept: "audio/mpeg",
          "Content-Type": "application/json",
          "xi-api-key": config.ELEVENLABS_API_KEY,
        },
        body: JSON.stringify({
          text: trimmed,
          model_id: modelId,
          voice_settings: {
            stability: request.stability ?? 0.5,
            similarity_boost: request.similarityBoost ?? 0.75,
            style: request.style ?? 0.2,
            use_speaker_boost: request.speakerBoost ?? true,
          },
        }),
        signal: AbortSignal.timeout(45_000),
      });

      if (!res.ok) {
        const body = await res.text().catch(() => "");
        return {
          provider: "client-fallback",
          reason: `ElevenLabs HTTP ${res.status}: ${body.slice(0, 200)}`,
        };
      }

      const buf = Buffer.from(await res.arrayBuffer());
      return {
        provider: "elevenlabs",
        contentType: "audio/mpeg",
        base64: buf.toString("base64"),
        bytes: buf.byteLength,
        voiceId,
        modelId,
      };
    } catch (err) {
      return {
        provider: "client-fallback",
        reason: err instanceof Error ? err.message : "ElevenLabs request failed",
      };
    }
  }

  async listVoices(): Promise<SpeechVoice[]> {
    if (!config.ELEVENLABS_API_KEY) return [];
    try {
      const res = await fetch("https://api.elevenlabs.io/v1/voices", {
        headers: { "xi-api-key": config.ELEVENLABS_API_KEY, Accept: "application/json" },
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) return [];
      const json = (await res.json()) as { voices?: RawVoice[] };
      return (json.voices ?? [])
        .filter((v) => v.voice_id && v.name)
        .map((v) => ({
          id: v.voice_id,
          name: v.name,
          category: v.category ?? "generated",
          description: v.description ?? null,
          previewUrl: v.preview_url ?? null,
        }));
    } catch {
      return [];
    }
  }
}

export interface SpeechVoice {
  id: string;
  name: string;
  category: string;
  description: string | null;
  previewUrl: string | null;
}

interface RawVoice {
  voice_id: string;
  name: string;
  category?: string;
  description?: string | null;
  preview_url?: string | null;
}

export const speechService = new SpeechService();
