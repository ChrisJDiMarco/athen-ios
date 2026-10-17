# Athen — Quickstart

Get the app running end-to-end in the iOS simulator in ~3 minutes.

## Prerequisites

- macOS with **Xcode 16+** (`xcodebuild -version`)
- **Node 20+** (`node -v`)
- An **Anthropic API key** — [console.anthropic.com](https://console.anthropic.com/settings/keys)

Optional but recommended:
- **OpenStates** (free) — real state legislators in the You tab. [openstates.org/accounts/profile/](https://openstates.org/accounts/profile/)
- **Firecrawl** — "Background reading" cards on each issue. [firecrawl.dev](https://firecrawl.dev)

## 1. Bootstrap the backend

```sh
./bootstrap.sh
```

The script will:
1. Verify Node + Xcode
2. Prompt you for each API key (the script never prints them back)
3. Write `backend/.env` with sane defaults (dry-run email mode is on by default)
4. `npm install` the backend
5. Fetch congressional district boundaries (first run only)

Skip any optional key by pressing **ENTER**.

## 2. Start the backend

```sh
./bootstrap.sh --start
```

The Fastify server listens on **http://localhost:8787**. Leave this running in its own terminal. Verify it's healthy:

```sh
curl -s http://localhost:8787/healthz | jq .
```

You should see `"status":"ok"` plus a feature matrix telling you which integrations are wired.

## 3. Open the iOS app

```sh
open CivicOS.xcodeproj
```

In Xcode:
1. Select any **iPhone 16** simulator from the destination dropdown
2. Hit **⌘R**

## 4. Connect the app to the backend

When the simulator boots:

1. Walk through onboarding — enter a ZIP code (try **19129** for Philadelphia or **10001** for NYC)
2. Tap the **You** tab at the bottom-right
3. Scroll to **Settings** → tap **AI backend**
4. Tap **Use localhost** → **Save & test**

The status chip should flip from `Mock mode` (amber) to **`Connected`** (green). The status sheet shows which features are live: model, email mode, OpenStates, Firecrawl, voice.

## 5. Verify the AI works

- **Assistant tab** → ask *"what should I act on first?"* → the response streams in token-by-token from Claude
- Pick any issue on **Home** → **Endorse** → the draft sheet shows a Claude-written formal message you can edit before sending
- **Issue detail** → "Background reading" card appears with a Claude summary + citations (requires Firecrawl key)

## What's actually running

| Tab | What you see | Where it lives |
|-----|--------------|----------------|
| Home | Civic radar — issues ranked by deadline/impact/profile match | `/v1/issues` + bundled samples |
| Help | Public service matcher (housing, food, health, ID) | `/v1/services` |
| Feed | Social feed with AI briefs of each issue | `/v1/briefs` |
| Assistant | Streaming Claude chat that knows your reps + issues + filing history | `/v1/chat` (SSE stream) |
| You | Profile, reps, bookmarks, filing history, settings | `/v1/profile/resolve` |

Filing flow: **issue → endorse/oppose → Claude draft → edit → send → official lookup** lives in `/v1/file/draft` and `/v1/file/send`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Status chip stays amber | App hasn't been pointed at the backend | You tab → AI backend → Use localhost → Save & test |
| Status chip is red | Backend not running | `./bootstrap.sh --start` in another terminal |
| Assistant returns generic mock copy | Backend offline OR `ANTHROPIC_API_KEY` missing | `./bootstrap.sh --check` to see what's set |
| "No representatives mapped" in You tab | First run hasn't fetched districts yet | `cd backend && npm run fetch:districts` |
| Backend won't start | Required env missing or wrong | `./bootstrap.sh --check`, then re-run `./bootstrap.sh` |
| Filing draft fails with 401/403 | Claude key invalid | Rotate at [console.anthropic.com](https://console.anthropic.com) and re-run bootstrap |

## Where the data lives

- Profile, bookmarks, filing receipts, groups → `UserDefaults` on-device (no cloud sync)
- Issues, services, evidence, contact-form queue → `backend/data/*.json` (durable JSON store)
- Backend secrets → `backend/.env` (chmod 600, gitignored)

## Safety defaults

- `EMAIL_DRY_RUN=true` until you set a real Postmark token — filings are logged, never sent
- Drafts are always shown for **edit-then-file** review before any send
- Claude is constrained by a strict drafting system prompt: no invented stats, no placeholders, no threats
- Backend re-resolves the recipient server-side on every send — the iOS client can't redirect mail

## Useful commands

| Command | What it does |
|---------|-------------|
| `./bootstrap.sh` | First-time or re-config setup |
| `./bootstrap.sh --start` | Start backend on :8787 |
| `./bootstrap.sh --check` | Show which keys are configured (without printing them) |
| `cd backend && npm run typecheck` | Verify backend compiles |
| `xcodebuild -project CivicOS.xcodeproj -scheme CivicOS -destination 'platform=iOS Simulator,name=iPhone 16' build` | Headless iOS build |
| `curl -s http://localhost:8787/healthz \| jq .` | Backend status snapshot |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full data + AI pipeline overview, [backend/README.md](backend/README.md) for backend internals, and [docs/DEPLOY.md](docs/DEPLOY.md) for moving from localhost to Railway.
