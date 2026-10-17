# Athen

Native SwiftUI iPhone prototype for the Local Impact Translator & Auto-Filer.

## What is built

- Dark-mode bento dashboard with three local civic impact cards.
- Personal civic radar that ranks issues by deadline, impact, profile relevance, and filing state.
- Household context tuning for renter/homeowner/parent/commuter/business/accessibility/climate sensitivity.
- Issue filters for radar, act-now, saved, and local civic items.
- Translation detail screen that turns dense civic items into plain-English facts.
- "Why this matters" and source-confidence cards on every issue.
- Issue-specific action plan with filing, outreach, follow-up, sharing, and Ask AI handoff.
- Rally crew workflow for nudging contacts and tracking who has been mobilized.
- Civic Social feed with issue-linked posts, photo attachments, likes, comment signals, shares, and seeded community examples.
- Issue detail can jump straight into a pre-attached Feed composer.
- One-tap Endorse / Oppose action bar.
- Mock routing and filing service that returns a sent confirmation.
- Official reply summary module.
- Backend-ready service boundary in `CivicFilingServicing`.

## Open and run

Open `CivicOS.xcodeproj` in Xcode and run the `CivicOS` scheme on an iPhone simulator.

Command-line build:

```sh
xcodebuild -project CivicOS.xcodeproj -scheme CivicOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Backend

Real backend lives in [`backend/`](backend/README.md). Node + TypeScript service that
verifies addresses, resolves city/state/federal officials, drafts filings with Claude,
files through Postmark or a contact-form queue, and ingests official civic sources into
the app's issue feed. The ingestion path uses a trusted source registry, Firecrawl
scraping/discovery, Claude schema extraction, durable JSON upserts, trust scoring,
citations, and admin-gated refresh endpoints.

### Run end-to-end against the real backend

```sh
# terminal 1 — backend
cd backend
npm install
cp .env.example .env   # fill in API keys; keep EMAIL_DRY_RUN=true while testing
npm run fetch:districts
npm run dev            # listens on :8787 by default

# terminal 2 — iOS
# In Xcode: Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
# Add: CIVIC_API_BASE_URL = http://localhost:8787
# Then run the CivicOS scheme on an iPhone simulator.
```

The app picks `HTTPCivicFilingService` automatically when `CIVIC_API_BASE_URL` is set,
and falls back to `MockCivicFilingService` otherwise (so previews and unconfigured runs
keep working).
