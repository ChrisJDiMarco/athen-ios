# Athen Production Deploy

Step-by-step. Optimized for getting v1 live in under 2 hours.

## Prerequisites (one-time, ~30 min)

You need accounts at:
1. **Railway** (or Fly.io / Render — instructions below assume Railway): https://railway.app
2. **A domain name** you control (purchase via Cloudflare/Namecheap/etc.) — optional but recommended over `*.up.railway.app`
3. **Apple Developer Program** ($99/year): https://developer.apple.com/programs
4. **App Store Connect** access: https://appstoreconnect.apple.com

You'll also need these API keys:
- ✅ Anthropic Claude — `sk-ant-...` (you have this)
- ✅ ElevenLabs — `sk_...` (you have this)
- ✅ OpenStates — free (you have this)
- ✅ Firecrawl — `fc-...` (you have this)
- ⚠️ Google Civic API — free, get at https://developers.google.com/civic-information (15 min — required for Voter Hub)
- ⚠️ Congress.gov — free, get at https://api.congress.gov/sign-up (10 min)
- ⚠️ GovInfo — free, get at https://api.govinfo.gov/docs (10 min)
- ⚠️ OpenSecrets — free, get at https://www.opensecrets.org/api/admin/index.php (10 min)
- Optional: Composio — only if enabling user Gmail sending (defer for v1)

## Phase 1 — Deploy backend to Railway (~20 min)

1. Install Railway CLI:
   ```bash
   npm install -g @railway/cli
   railway login
   ```

2. From repo root:
   ```bash
   cd backend
   railway init    # creates new project; name it "athen-backend"
   railway up      # builds Dockerfile + deploys
   ```

3. After first deploy, set env vars in Railway dashboard (Project → Variables):
   ```
   NODE_ENV=production
   PORT=8787
   ANTHROPIC_API_KEY=sk-ant-...                         (your key)
   ANTHROPIC_MODEL=claude-sonnet-4-6
   ELEVENLABS_API_KEY=sk_...                            (your key)
   ELEVENLABS_MODEL=eleven_turbo_v2_5
   ELEVENLABS_VOICE_ID=EXAVITQu4vr4xnSDxMaL
   OPENSTATES_API_KEY=...                               (your key)
   OPENSTATES_JURISDICTIONS=Pennsylvania,New York,California  (add states you care about)
   CONGRESSGOV_API_KEY=...                              (request above)
   GOVINFO_API_KEY=...                                  (request above)
   GOOGLE_CIVIC_API_KEY=...                             (request above)
   OPENSECRETS_API_KEY=...                              (request above)
   FIRECRAWL_API_KEY=fc-...                             (your key)
   ADMIN_API_TOKEN=<openssl rand -hex 32>               (generate, keep private)
   INSTALL_AUTH_REQUIRED=true                           (REQUIRED IN PROD)
   INGEST_SCHEDULE_ENABLED=true
   INGEST_INTERVAL_MINUTES=360
   INGEST_CLIENTS=legistar:phila:21:25,legistar:nyc:14:20
   EMAIL_DRY_RUN=true                                   (keep true until Postmark wired)
   ```

4. Attach a Railway **persistent volume** to `/app/data` (Settings → Volumes → New). This is where the JSON stores live so they survive deploys. 1GB is plenty.

5. (Recommended) Add a custom domain in Railway → Settings → Networking. CNAME `api.yourdomain.com` to the Railway target.

6. Verify:
   ```bash
   curl -s https://api.yourdomain.com/healthz | jq
   # Should return {"status":"ok", ...}
   ```

7. Verify auth is on:
   ```bash
   curl -s https://api.yourdomain.com/v1/issues
   # Should return 401: install_required
   ```
   Then:
   ```bash
   curl -s https://api.yourdomain.com/v1/issues -H "X-Athen-Install: 12345678-1234-1234-1234-123456789012"
   # Should return real data
   ```

## Phase 2 — Bake backend URL into iOS Release build (~10 min)

The app currently uses `CIVIC_API_BASE_URL` env at build-time, falling back to `localhost` in DEBUG and the user's manual entry in RELEASE. For v1 we want every user to hit your production backend without any setup.

Open `CivicOS.xcodeproj` → CivicOS target → Build Settings → User-Defined → Add `CIVIC_API_BASE_URL` = `https://api.yourdomain.com` for **Release** config only.

Verify by building Release and checking that fresh installs immediately load real data without needing Settings → Backend URL.

## Phase 3 — App Store Connect setup (~30 min)

1. Sign in to https://appstoreconnect.apple.com → My Apps → +
2. **Bundle ID**: `com.chrisdimarco.Athen`
3. **SKU**: `athen-v1`
4. **Primary language**: English (U.S.)

### App Information
- **Name**: Athen
- **Subtitle**: "See what power is doing." (max 30 chars)
- **Category**: Primary: News, Secondary: Reference
- **Content Rights**: I have rights, no third-party content

### Pricing & Availability
- Free
- All territories (or your target list)

### App Privacy
Use the data from `PRIVACY-NUTRITION-LABELS.md`. Key answers:
- Data Used to Track You: **NO**
- Data Linked to You: **NO**
- Data Not Linked to You:
  - Device ID (App Functionality)
  - Other Data → ZIP code, civic interests, filing history (App Functionality)

### App Review Information
- **Sign-in required**: No
- **Demo account**: N/A (no login)
- **Contact**: chris@logicoutloud.com
- **Notes**: Paste contents of `APP-STORE-REVIEWER-NOTES.md`
- **Attachments**: Upload `APP-STORE-REVIEWER-NOTES.md` and `PRIVACY-NUTRITION-LABELS.md`

### Age Rating
Walk the questionnaire. Answer truthfully:
- Unrestricted Web Access: No
- Frequent/Intense Political/Social Commentary: **Yes** (this gives 12+)

## Phase 4 — Screenshots (~30 min)

Apple requires screenshots at these sizes:
- **6.9" (iPhone 16 Pro Max)** — required
- **6.5" (iPhone 14 Plus)** — required
- **5.5" (iPhone 8 Plus)** — required
- **iPad 12.9" 6th gen** — required if you ship an iPad version

Use the in-repo `scripts/screenshots.sh` (if present) or:
```bash
xcrun simctl boot "iPhone 16 Pro Max"
open -a Simulator
# Launch Athen, navigate to each screen, take screenshots manually:
# 1. Home (smart hero + AI Brief)
# 2. Brief detail with Listen pill visible
# 3. Voter Hub
# 4. Officials Directory
# 5. Petitions list
# 6. Life Event Plan result
```

Save to `assets/screenshots/`. Upload via App Store Connect → App Store tab.

## Phase 5 — Build + Submit (~15 min)

1. In Xcode: Product → Archive
2. Window → Organizer → Distribute App → App Store Connect → Upload
3. Wait for processing email (5-10 min)
4. Back in App Store Connect → App Store tab → Build → select the upload
5. Fill remaining required fields
6. Submit for Review

Apple's median review is 24-48 hours. Be available for review questions.

## Optional: Crash reporting (post-v1)

Add Sentry:
```bash
# In Xcode: File → Add Package Dependencies
# URL: https://github.com/getsentry/sentry-cocoa
```

Then in `CivicOSApp.swift`:
```swift
import Sentry
SentrySDK.start { options in
    options.dsn = "YOUR_DSN_HERE"
    options.tracesSampleRate = 0.1
    options.environment = "production"
}
```

DSN from https://sentry.io/settings/your-org/projects/athen/keys/

## Optional: Postmark email (post-v1)

When you're ready to actually deliver filings to officials:
1. Sign up for Postmark, verify a sending domain
2. Add to Railway env:
   ```
   POSTMARK_SERVER_TOKEN=...
   EMAIL_FROM_ADDRESS=filings@yourdomain.com
   EMAIL_FROM_NAME=Athen
   EMAIL_DRY_RUN=false
   ```
3. In `CivicOSStore.swift::confirmSend`, remove the `recordedLocal` branch so all filings go through the dispatcher.

## Cost expectations (v1, ~1,000 weekly active users)

| Service | Estimated cost |
|---|---|
| Railway | $5-20/mo (hobby plan covers small launch) |
| Anthropic Claude (Sonnet 4.6) | $40-150/mo depending on usage |
| ElevenLabs | $5-30/mo (Starter $5/mo includes 30k chars) |
| Firecrawl | $0 free tier, ~$20/mo if heavy |
| Domain + DNS | $12/yr |
| Apple Developer Program | $99/yr |
| **Total v1 monthly** | ~$60-220/mo |

The daily quotas in [backend/src/lib/dailyQuota.ts](backend/src/lib/dailyQuota.ts) are sized to keep per-user Claude + ElevenLabs spend bounded.

## What's left after launch

- v1.1: Postmark wiring + Composio onboarding for actual filing delivery
- v1.1: SQLite migration (replace JSON stores)
- v1.2: Ballot scanner finish + Group letters delivery
- v1.2: 25-city Legistar coverage
- v1.3: Apple Watch glance
