# Athen — Data & AI Architecture

This is how Athen turns the firehose of government activity into a personal
feed someone can actually act on, without becoming a misinformation vector.

## Two parallel pipelines, joined at the issue

```
PRIMARY: Government source ingestion (the moat)
─────────────────────────────────────────────────
1. Source registry              ← curated DB row per jurisdiction
2. Vendor connectors            ← Legistar, CivicClerk, BoardDocs, PrimeGov, etc.
3. AI translation pipeline      ← classify → translate → project → tag
4. Distribution                 ← personalize per user from cached structured data

SECONDARY: News corroboration (the trust layer)
─────────────────────────────────────────────────
1. Per-scope source allowlist   ← reputable journalism by jurisdiction
2. Firecrawl search             ← restricted to allowlist
3. Claude summarizer            ← 2–3 sentences with [n]-style citations
4. Independent firehose         ← stories not yet ingested → review queue
```

## The vendor-platform insight

~70% of U.S. municipalities run on one of six council-management platforms:

| Vendor              | Example cities         | API / scrape strategy        |
| ------------------- | ---------------------- | ---------------------------- |
| Legistar (Granicus) | Philly, NYC, LA        | REST API (`legistar.com`)    |
| CivicClerk          | Mid-size municipalities| HTML + RSS                   |
| BoardDocs           | School boards          | HTML                         |
| PrimeGov            | West Coast cities      | HTML + structured downloads  |
| Diligent Community  | County boards          | HTML                         |
| OpenGov / Granicus  | Smaller cities         | HTML + iframe agendas        |

Build six well-tested connectors and you cover thousands of jurisdictions for free.
For the long-tail 30%, fall back to per-jurisdiction Firecrawl scraping.

## AI translation pipeline

Each raw item runs through four stages, **all cached by document hash** so the
same packet isn't re-translated for every user:

### Stage A — Classify
- Is this an agenda item, a vote, a hearing, or noise?
- Jurisdiction level: federal / state / county / city / special-district
- Vote date + governing body
- Topic tags (housing, transit, education, environment, public safety, health, money)

### Stage B — Translate
- Read source docs (packet PDF, agenda text, attached resolutions)
- Emit: `title`, `summary`, three plain-English facts (`What it does`, `The cost`,
  `The timeline`), `sourceName`, `sourceDetail`
- Citations to source paragraphs, never invented

### Stage C — Project impact (cohort-level)
- For each civic item, generate per-cohort impact lines:
  - homeowner / renter / parent / commuter / flood-zone / business-owner
- Cohort lines are parameterized and cached; rendered per-user by matching their
  attributes (collected lazily — never demanded upfront)

### Stage D — Tag
- Topic set ∩ user interests determines feed ranking
- Jurisdiction scope determines visibility

## News corroboration

The trust layer that runs alongside government ingestion.

### Source allowlists (`backend/src/data/news-sources.json`)

| Scope        | Sources (starter set)                                                  |
| ------------ | ---------------------------------------------------------------------- |
| Philly local | inquirer.com, billypenn.com, whyy.org, plansphilly.com, axios.com      |
| Pennsylvania | spotlightpa.org, pennlive.com, wesa.fm, witf.org                       |
| Federal      | apnews.com, reuters.com, propublica.org, nytimes.com, washingtonpost.com, politico.com, npr.org, rollcall.com |
| Civic-specialty | routefifty.com, governing.com, bloomberg.com, smartcitiesdive.com   |

### Flow per issue

```
Issue (title, jurisdiction, scope)
    ↓
Firecrawl search constrained to allowlist
    ↓
Top 3–4 hits (titles + snippets)
    ↓
Single Claude call: "summarize in 2–3 sentences with [1]/[2]/[3] citations"
    ↓
Returned to iOS as { summary, [citation rows] }
```

This appears as a **Background reading** card in the issue detail. Trust is
explicit: every claim is numbered, every citation links out.

### Independent firehose (future)

The same crawl, scheduled hourly, watching for stories on the allowlist that
*don't* match any ingested item. These go to a review queue — they're often the
signal that the government source layer missed something (a backroom committee
vote, an emergency hearing, a quiet rulemaking).

## Why this scales

Three properties keep it efficient and trustworthy:

1. **Cache by document hash, not by user.** Translation is expensive (~$0.02–0.05
   per item with Claude Sonnet). Personalization is cheap. Run AI once per packet,
   render per-user from cached structured output.

2. **Cohort impact, not per-user impact.** "Homeowner in 19129" is a cohort of
   thousands; project once, label every user that matches.

3. **Trust = citations, not vibes.** Every fact on a card links back to a
   paragraph in the source. The background card shows the reporting. Users can
   flag inaccuracies → human review queue. This is how Athen doesn't become
   a misinformation vector.

## Production cost model

| Item                       | Estimate                          |
| -------------------------- | --------------------------------- |
| Inference per ingested item| ~$0.02–0.05 (Sonnet)              |
| Firecrawl scrape           | ~$0.001–0.005 per page            |
| Background reading per view| ~$0.01 (cached for 24h)           |
| 10K items/day              | ~$200–500/day in AI               |
| 100K active users          | mostly free at the read path      |

Cheaper than one engineer's lunch budget. AI cost is not the bottleneck.

## What's wired today

### Backend (`backend/`)
- `services/newsCorroborator.ts` — Firecrawl search → Claude summarize.
  Requires `FIRECRAWL_API_KEY`. Returns null gracefully if unset.
- `services/ingestionPipeline.ts` — given a URL, Firecrawl-scrape it and run
  Claude with a strict JSON schema to produce a `CivicIssue` record with
  citations and parser confidence.
- `services/sourceRegistry.ts` + `data/civic-sources.json` — official source
  registry with allowed hosts, source type, trust tier, scope, and default
  contact target.
- `services/sourceDiscovery.ts` — Firecrawl search constrained to the source
  registry's allowed hosts, used by admin refresh for official web sources.
- `services/issueStore.ts` + `services/issueNormalizer.ts` — durable JSON
  upserts, dedupe fingerprints, trust score, source host/type, and issue-store
  stats.
- `routes/background.ts` — `POST /v1/issue/background`.
- `routes/admin.ts` — admin-gated `GET /v1/admin/sources`,
  `POST /v1/admin/ingest-url`, `POST /v1/admin/ingest-source`,
  `POST /v1/admin/ingest-jurisdiction`, scheduler status, and contact-form
  queue ops.
- `data/news-sources.json` — per-scope source allowlist.

### iOS (`CivicOS/`)
- `Models/BackgroundCitation.swift` — `BackgroundReading` + `BackgroundCitation`.
- `Services/NewsService.swift` — HTTP + Mock implementations.
- `Views/IssueDetailView.swift` — renders the **Background reading** card
  with a loading state and external-link rows.
- `Models/CivicRadar.swift` + `Views/Components/CivicRadarViews.swift` —
  ranks visible issues into a personal action radar using deadline, impact,
  profile factors, interests, and filing state.
- `Views/Components/CivicActionFlowViews.swift` — renders an issue action plan,
  issue timeline, rally crew surface, issue-specific share text, and outreach
  tracking.
- Assistant handoff — issue detail can queue a fully contextual action-plan
  prompt, switch to the Assistant tab, and send it with the user's profile,
  filing state, rally state, source confidence, and issue summary.
- `Models/SocialPost.swift` + `Views/SocialFeedView.swift` — local-first
  civic social layer with seeded posts, issue attachments, optional image data,
  likes, comment signals, shares, and a PhotosPicker composer.
- Social handoff — issue detail can queue the Feed composer with the current
  issue pre-attached, so users can post filing/rally/explainer/question updates
  without re-finding the issue.
- `Views/DashboardView.swift` — filters the radar by all items, act-now items,
  saved items, and local items.
- `Views/ProfileView.swift` — lets users tune household context such as renter,
  homeowner, parent, commuter, business owner, accessibility needs, and
  flood/climate risk.
- Deep-linking — `athen://issue/<uuid>` opens the issue as a modal sheet
  and `athen://feed` opens the social feed (legacy `civicos://` links still work; see `App/CivicOSApp.swift` +
  `Views/MainTabView.swift`).
- `Views/ShareReceiptView.swift` — share-card text includes the deep-link so
  recipients land on the same issue.

## What's deferred (future sessions)

| Feature                              | Notes                                                          |
| ------------------------------------ | -------------------------------------------------------------- |
| More vendor connectors               | Legistar is wired; add Socrata, Granicus, OpenStates bills.     |
| Universal Links (https://)           | Needs hosted `apple-app-site-association`. Pre-install routing.|
| Worker-grade ingestion + storage     | Move from in-process scheduler + JSON store to Postgres + queue.|
| Cohort-level impact projection       | Parcel/demographic joins via Census + local opendata.          |
| Voice mode + morning audio briefing  | AVFoundation + ElevenLabs streaming TTS.                       |
| Apple Watch + Home screen widget     | Separate Xcode targets.                                        |
| Open-source civic data API           | Anonymized aggregate filing stats for journalists/researchers. |

## Trust & safety guardrails

These are the things to never cut:

1. **Always show the drafted message before sending.** Edit-then-file.
2. **Cite every fact.** Sources, paragraph if possible.
3. **Tone + spam guardrails.** Rate limit per official; refuse threats.
4. **Privacy nuke.** One tap erases all profile + filing data.
5. **Verified delivery proof.** DKIM receipt + a copy of the exact message sent.
