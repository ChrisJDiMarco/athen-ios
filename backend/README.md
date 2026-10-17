# Athen Backend

Node + TypeScript service that turns the iOS prototype's mock filing call and mock issue feed into real infrastructure.

Core pipelines:

1. **Address verification** — U.S. Census Geocoder (`onelineaddress`).
2. **Official lookup** — Philadelphia district GeoJSON, Open States, and static federal rosters.
3. **Message draft** — Anthropic Claude (`claude-sonnet-4-6`) writes a formal constituent message.
4. **Filing** — Postmark email or a federal contact-form queue.
5. **Issue intelligence** — trusted source registry → Firecrawl scrape/discovery → Claude JSON extraction → durable upsert with citations, parser confidence, and trust score.
6. **Resident help matching** — public-service catalog → eligibility/document matching → app-ready next steps for the Help tab and assistant.
7. **Evidence vault + Athen Briefs** — official API/source sweeps → durable source records → feed-ready plain-English briefs.
8. **Voice tools** — server-signed ElevenLabs sessions plus REST tools for daily briefs, issue explanation, service matching, draft filing, and readback.

## Setup

```sh
cd backend
npm install
cp .env.example .env
# Fill in ANTHROPIC_API_KEY, POSTMARK_SERVER_TOKEN, EMAIL_FROM_ADDRESS,
# EMAIL_DRY_RUN_RECIPIENT, and ADMIN_API_TOKEN. Optional keys enable:
# FIRECRAWL_API_KEY, OPENSTATES_API_KEY, CONGRESSGOV_API_KEY, GOVINFO_API_KEY,
# REGULATIONS_API_KEY, SOCRATA_APP_TOKEN, ELEVENLABS_API_KEY, ELEVENLABS_AGENT_ID.
npm run fetch:districts   # downloads Philly council district boundaries (~50KB)
```

Edit [`src/data/philly-officials.json`](src/data/philly-officials.json) to replace the
placeholder district names and emails with the current Philadelphia City Council roster
before disabling dry-run mode.

## Run

```sh
npm run dev          # tsx watch on src/server.ts
# or
npm run build && npm start
```

`GET /healthz` confirms the service is live and reports whether dry-run is enabled.

## Issue intelligence

Trusted civic sources live in [`src/data/civic-sources.json`](src/data/civic-sources.json).
The admin routes are default-deny: set `ADMIN_API_TOKEN`, then call them with
`Authorization: Bearer <token>`.

```sh
# List registered official sources and issue-store stats.
curl -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  http://localhost:8787/v1/admin/sources

# Ingest one official URL, persist it into data/issues.json, and expose it via /v1/issues.
curl -X POST -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://phila.legistar.com/","sourceId":"phila-legistar"}' \
  http://localhost:8787/v1/admin/ingest-url

# Refresh a registered source. Legistar sources use the Legistar API; web sources use
# Firecrawl discovery constrained to the source's allowed hosts, then Claude extraction.
curl -X POST -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sourceId":"phila-legistar","lookaheadDays":21,"limit":25}' \
  http://localhost:8787/v1/admin/ingest-source

# Sweep federal/state/local open-data APIs into the evidence vault.
curl -X POST -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"connectors":["congress","regulations","openstates","socrata"],"daysBack":7,"limit":10}' \
  http://localhost:8787/v1/admin/source-sweep
```

`GET /v1/issues` returns the app-ready feed, including `trustScore`,
`extractionConfidence`, `sourceHost`, `sourceType`, `citations`, and `ingestedAt`
when available. The response also includes a `brief` object with active/urgent
counts, source health, top next moves, and service matches for the Home screen.

```sh
curl "http://localhost:8787/v1/issues?stateCode=PA&zip=19129&needs=food,housing&signals=lowIncome,renter&documents=photoID,proofOfAddress&language=spanish"
```

`GET /v1/services` exposes the same resident help matcher directly. It accepts
`category`, `needs`, `signals`, `documents`, `language`, and `limit` query params.

```sh
curl "http://localhost:8787/v1/services?needs=food&signals=lowIncome,parentOrGuardian&documents=photoID&language=spanish&limit=3"
```

## Evidence, briefs, and voice

`GET /v1/evidence` returns the evidence vault. `GET /v1/issues/:id/evidence`
returns source snippets tied to one issue.

`GET /v1/briefs` returns source-backed Athen Briefs for the social feed:

```sh
curl "http://localhost:8787/v1/briefs?stateCode=PA&zip=19129&limit=6"
```

`GET /v1/voice/session` mints an ElevenLabs signed session when
`ELEVENLABS_API_KEY` and `ELEVENLABS_AGENT_ID` are set. Without them it returns
`native-fallback`, so the iOS app can still use speech recognition and readback.

Voice tool endpoints:

- `GET /v1/voice/tools/daily-brief`
- `GET /v1/voice/tools/explain-issue?issueId=<uuid>`
- `GET /v1/voice/tools/service-match`
- `POST /v1/voice/tools/draft-filing`
- `POST /v1/voice/tools/read-draft-back`

## Request shape

```http
POST /v1/file
Content-Type: application/json

{
  "action": "endorse",
  "address": "242 W Tulpehocken St, Philadelphia, PA 19129",
  "issue": {
    "id": "5A56986F-...",
    "title": "Broad Street Re-Zoning",
    "category": "Land Use",
    "jurisdiction": "Philadelphia City Council",
    "sourceName": "Resolution 260418",
    "summary": "Council will vote on a corridor rezoning package…",
    "facts": [
      { "label": "What it does", "value": "Allows multi-family housing…" }
    ],
    "voteDateISO": "2026-05-19T14:30:00Z"
  }
}
```

Response:

```json
{
  "receipt": {
    "action": "endorse",
    "sentAt": "2026-05-18T22:30:00.000Z",
    "officialName": "Councilmember District 4",
    "confirmationCode": "COS-K7X3PA",
    "messagePreview": "I am a verified Philadelphia resident in District 4 …"
  },
  "delivery": {
    "providerMessageId": "abc-123",
    "deliveredTo": "ops@example.com",
    "dryRun": true
  },
  "verifiedAddress": "242 W TULPEHOCKEN ST, PHILADELPHIA, PA, 19129"
}
```

## Safety

`EMAIL_DRY_RUN=true` is the default — every email is rerouted to `EMAIL_DRY_RUN_RECIPIENT`,
prefixed `[DRY RUN]`, and includes the would-be recipient in the body. Set
`EMAIL_DRY_RUN=false` only after you have constituent consent, verified deliverability,
and the real officials directory loaded.
