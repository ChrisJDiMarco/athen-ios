# Athen — Roadmap

Source of truth for what's done, what's next, and what's deferred. Updated as work lands.

---

## ✅ Shipped (private build, runs on simulator + Railway-ready)

### Core architecture
- 5 tabs: Home · Brief · Square · Assistant · You
- Local-first iOS storage (UserDefaults) for profile, bookmarks, filings, posts, comments, settings
- Node.js / Fastify backend with Docker + Railway deploy script
- BackendOfflineBanner everywhere — graceful degradation when backend is unreachable

### Real AI
- Claude per-issue brief generation (date-aware, cached by source fingerprint)
- Audio briefings (Claude script + ElevenLabs TTS, on-device TTS fallback)
- Filing tone selector (5 voice variants per filing)
- Streaming chat assistant with profile + filing + service context

### Real ingestion
- Legistar (Philadelphia City Council)
- OpenStates (PA bills, expanded to abstracts + sponsorships + actions)
- Federal Register (rules + proposed rules with comment-period deadlines)
- Auto-seed on first launch
- Parallel orchestrator with per-source timeouts

### Real social
- Empty Square (no fake seed personas)
- Compose / edit / delete own posts with context menus
- Real comment threads with composer, edit, delete
- Three civic reactions: File too / Help me / Disagree (replaces generic likes)
- Auto-share filing receipts to Square (opt-in)

### Onboarding
- 7-step flow: intro × 3 → ZIP → interests → factors → notifications
- Notification permission ask happens in context, not mid-refresh
- Cohort matching works from minute one

### Production prep
- Privacy Policy (docs/PRIVACY.md)
- Terms of Service (docs/TERMS.md)
- Railway deploy script with env-var sync
- Bootstrap script for first-run config
- Brand-consistent ("Athen") across all user-visible strings

### Magic moments (sprint complete — May 2026)
- **Diff intelligence** — every refresh compares bookmarked-bill snapshots and emits CivicDiffEvents when title / summary / vote date moves
- **"Since you last visited" home card** — top of Home shows the diff events + new Square posts since previous launch
- **Explain-for-me picker** — Brief detail view rewrites the brief for I'm 12 / parent / landlord / 30-second / legal angle, one-shot Claude call
- **Civic streak** — calendar-day-based counter prominently shown in You tab with filed / saved / tracked-changes stats
- **Smart-default tone** — DraftFilingSheet pre-selects the filing voice that matches the user's strongest civic factor for this issue's topic
- **Undo Send toast** — Send button queues with a 5-second undo window; cancel before window closes; sheet locks while pending
- **Ballot photo scanner** — PhotosPicker → on-device Vision OCR → Claude `/v1/ballot/analyze` returns per-item plain-English "what YES / what NO" briefs (neutral, never advice)
- **Group letter foundation** — co-signed letters live in each crew: pick issue, draft once, gather signatures from group members, mark sent
- **Ambient morning briefing** — opt-in: AVAudioSession route monitor detects AirPods / CarPlay / BT headset coming online between 5am–11am and auto-plays the briefing once per day

---

## 🚧 Tier B — Magic features (next major sprint)

These take the app from "good" to "the app you can't put down." All code, ~1 week.

### iOS-native moments
- [ ] **Live Activity for vote countdowns** — bookmarked items show countdown on Lock Screen + Dynamic Island. Tap to file directly.
- [ ] **Home Screen widget** — "next deadline: 18h" / "3 items moving this week"
- [ ] **App Intents + Siri** — "Hey Siri, civic brief today" opens Assistant pre-queued
- [ ] **Spotlight integration** — search "broadband" from iPhone home → finds issues in Athen alongside Notes / Mail
- [ ] **ShareLink → backend ingestion** — share a URL from Safari → backend Firecrawl-ingests → appears as personalized Brief

### Smarter Brief
- [x] **Watch + diff for bookmarks** — local-only version shipped (May 2026). Backend cron version deferred to Tier C.
- [ ] **Compare cards** — "PA's broadband bill vs. NY's last year" using OpenStates cross-state data
- [ ] **Topic explainers on demand** — "What is the Tax Reform Code of 1971?" → Claude writes a primer when a brief cites unfamiliar statute
- [ ] **Quiz cards** — civic literacy quizzes auto-generated from this week's bills
- [ ] **Co-pilot mode** — long-press an item → Claude generates a 30-second "what would you ask me about this" prep card

### Better filing
- [ ] **APNS push notifications** — backend-driven cross-device push for bookmarked-bill changes (currently local-only)
- [ ] **Real contact-form submission worker** — Playwright workers that actually submit queued forms (currently they're just stored)
- [ ] **Filing history detail** — show the exact message body sent, not just receipt; PDF export
- [ ] **Group letter wire-up** — current group letters are local-only; promote to actually submit through the dispatcher with all co-signers attached
- [ ] **Loop closure docket scraping** — when a bill the user filed on gets a vote, surface the result and what the user's officials did
- [ ] **Reply parsing** — when an official's office replies, parse + classify into "form letter" / "substantive" / "real answer"
- [ ] **Vote tracking** — once a bill is voted, show how each rep voted vs. how the user asked them to vote

### Assistant upgrades
- [ ] **Citation streaming** — Claude generates [1][2] inline that link to actual source paragraphs
- [ ] **Saved prompt templates** — "What's the simplest version of X?" / "Draft a text to my crew about Y"
- [ ] **Voice-first input prominent** — bigger mic, better feedback

### Magic moments — next pass
- [ ] **Live ballot scanner with multi-page stitching** — current scaffold takes one photo at a time; add PDF + multi-photo stitching
- [ ] **Ambient briefing personalization** — current opt-in plays the default audio briefing; learn which sections the user fast-forwards and reshape
- [ ] **Streak rituals** — push at risk hours to keep the streak alive
- [ ] **Group letter delivery receipts** — when the dispatcher actually sends, route delivery confirmations back to all signers

---

## 🏗️ Tier C — Real product (multiple sprints)

When more than a handful of people use it.

### Multi-user backend
- [ ] **Sign in with Apple** — anonymous device IDs break (lost phone = lost history). Required for any cross-device experience.
- [ ] **Postgres migration** — issue store, brief cache, comments, contact-form queue
- [ ] **Per-user rate limiting** — currently per-IP
- [ ] **Backend monitoring** — Sentry-style error tracking, structured log aggregation
- [ ] **GDPR/CCPA endpoints** — "delete all my data" + "export my data"

### Geographic expansion
- [ ] **State coverage beyond PA** — OpenStates handles all 50, but the source registry, Legistar clients, and cohort copy are PA-heavy. Research + curation per state.
- [ ] **Localized cohort projections** — current projections assume US contexts; international would need adaptation

### Platform expansion
- [ ] **Web version** — React + Next.js sharing the same backend. At minimum, marketing site + view-only feed.
- [ ] **Android** — Flutter or Kotlin rebuild
- [ ] **Internationalization** — NSLocalizedString pass + at minimum Spanish

### Quality engineering
- [ ] **Test suite** — currently zero unit/integration/UI tests
- [ ] **CI/CD** — GitHub Actions for backend typecheck + iOS build on PRs
- [ ] **Visual regression tests** — SwiftUI snapshot tests
- [ ] **Analytics** — privacy-respecting (Plausible-style) usage tracking

### Customer surface
- [ ] **Search inside app** — find issues, posts, filing history
- [ ] **PDF export of filings** — audit trail for users
- [ ] **Support form** — "report a bug" with attached logs
- [ ] **In-app feedback** — what feature do you want?

---

## ❌ Explicitly not doing (yet)

These come up but are deferred until clear demand exists:

- Cross-platform sync (no Sign in with Apple = no cloud state)
- Real cross-user social (Square is local-first for now)
- Web App Clip
- Custom voice in audio briefings
- Multi-language interface
- Lobbying for vendor partnerships (Phone2Action, Quorum) for guaranteed contact-form delivery
- ~~Group filings (collective letters with N constituents)~~ — foundation shipped May 2026 as local co-signed letters; backend wire-up moved to Tier B "Better filing"

---

## How this doc gets updated

When new work is decided:
1. Add it under the right tier with `[ ]` and a one-line description.
2. When it ships, move to **Shipped** with a one-line note about what landed.
3. When it gets killed, move to **Explicitly not doing** with the reason.

The point is to never lose track of what we said we'd do.
