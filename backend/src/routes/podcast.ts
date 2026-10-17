import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import type { AudioBriefingService } from "../services/audioBriefing.js";
import type { IssueStore } from "../services/issueStore.js";

/// Public RSS 2.0 feed exposing the daily audio briefing as a podcast episode.
///
/// Lets the user subscribe in Apple Podcasts / Spotify / Overcast — extends
/// Athen's reach to listeners who never open the app daily.
///
/// One episode per state per day. The MP3 is the same one the iOS app gets
/// via /v1/briefing/audio. Listed under each state's slug:
///   GET /v1/podcast/feed.xml?state=PA
///   GET /v1/podcast/feed.xml (defaults to PA for v1)
///
/// Auth: skipped — RSS readers don't send custom headers. Audio briefings
/// already have rate limits, and the data is non-personal.

export interface PodcastRouteDeps {
  audioBriefing: AudioBriefingService;
  issues: IssueStore;
}

export function podcastRoute(deps: PodcastRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/podcast/feed.xml", async (request, reply) => {
      const stateCode = ((request.query as { state?: string }).state ?? "PA").toUpperCase();
      const base = `${request.protocol}://${request.hostname}`;
      const audioURL = `${base}/v1/briefing/audio?stateCode=${encodeURIComponent(stateCode)}&limit=5`;
      const today = new Date();
      const pubDate = today.toUTCString();
      const dateLabel = today.toLocaleDateString("en-US", {
        weekday: "long",
        month: "long",
        day: "numeric",
      });

      const xml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Athen Daily — ${stateCode}</title>
    <link>${base}</link>
    <description>Your 5-minute civic briefing. Federal, state, and local bills explained in plain English. Updated daily. From Athen.</description>
    <language>en-us</language>
    <itunes:author>Athen</itunes:author>
    <itunes:summary>Your 5-minute civic briefing for ${stateCode}.</itunes:summary>
    <itunes:explicit>false</itunes:explicit>
    <itunes:category text="News">
      <itunes:category text="Politics" />
    </itunes:category>
    <itunes:type>episodic</itunes:type>
    <itunes:owner>
      <itunes:email>chris@logicoutloud.com</itunes:email>
      <itunes:name>Athen</itunes:name>
    </itunes:owner>
    <itunes:image href="${base}/static/podcast-art.png" />
    <item>
      <title>Athen Daily — ${dateLabel}</title>
      <description>Your 5-minute civic briefing for ${dateLabel}. Bills, votes, and elections for ${stateCode}.</description>
      <pubDate>${pubDate}</pubDate>
      <enclosure url="${audioURL}" type="audio/mpeg" length="0" />
      <guid isPermaLink="false">athen-${stateCode}-${today.toISOString().slice(0, 10)}</guid>
      <itunes:duration>05:00</itunes:duration>
      <itunes:explicit>false</itunes:explicit>
    </item>
  </channel>
</rss>`;

      reply.header("Content-Type", "application/rss+xml; charset=utf-8");
      return reply.send(xml);
    });
  };
}
