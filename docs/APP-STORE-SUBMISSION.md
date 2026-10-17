# Athen — App Store submission guide

Every command, form field, and decision you'll hit between "code builds" and "Athen is live on the App Store." Read top to bottom; nothing can be skipped.

Realistic timeline: **2-3 days wall-clock** if Apple Developer enrollment goes smoothly, **+24h for App Store review** after submission.

---

## Phase 1 — Apple Developer enrollment ($99/yr)

You can't ship to TestFlight or the App Store without this.

1. Go to [developer.apple.com/programs/enroll/](https://developer.apple.com/programs/enroll/)
2. Sign in with your Apple ID (this becomes your developer Apple ID — pick one you actually use)
3. Choose **Individual** (you, personally, are the seller) or **Organization** (LLC + D-U-N-S number required)
4. Pay $99 — Apple Card, credit card, or PayPal
5. Wait for the activation email (usually same-day, can take 48h)

Once enrolled, you can sign in to [App Store Connect](https://appstoreconnect.apple.com) and [Apple Developer](https://developer.apple.com/account).

---

## Phase 2 — Xcode signing setup (15 min)

1. Open `CivicOS.xcodeproj` in Xcode
2. Select the **CivicOS** target → **Signing & Capabilities** tab
3. Check **Automatically manage signing**
4. Set **Team** to your developer account
5. Confirm **Bundle Identifier** = `com.chrisdimarco.Athen` (or change to something you actually own — if you change it, also update [Info.plist](CivicOS/Resources/Info.plist) URL scheme name)
6. Xcode creates a provisioning profile and certificate automatically

Verify by building for a real device:
```sh
xcodebuild -project CivicOS.xcodeproj -scheme CivicOS \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -allowProvisioningUpdates archive \
  -archivePath build/Athen.xcarchive
```

Successful archive = signing works.

---

## Phase 3 — App Store Connect listing (45 min)

### 3a. Create the app

1. [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **+** → **New App**
2. Fill in:
   - **Platform:** iOS
   - **Name:** Athen
   - **Primary Language:** English (U.S.)
   - **Bundle ID:** `com.chrisdimarco.Athen` (must match Xcode)
   - **SKU:** `athen-ios-001` (arbitrary, internal)
   - **User Access:** Full Access

### 3b. App Information

| Field | Value |
|-------|-------|
| Category — Primary | News |
| Category — Secondary | Reference |
| Content Rights | "Does your app contain, show, or access third-party content?" → **Yes** (we surface government documents and AI-generated summaries) |
| Age Rating | 17+ likely (civic + political content; complete the questionnaire and follow Apple's auto-recommendation) |

### 3c. Pricing and Availability

- **Price:** Free
- **Availability:** All countries or just United States (recommend US-only at launch since our connectors are US-specific)

### 3d. App Privacy

This is the privacy nutrition label. Click **Get Started** under "App Privacy" and answer using these values (sourced from [docs/PRIVACY.md](docs/PRIVACY.md)):

**Does Athen collect data?** → **Yes**

**Data types collected:**

| Category | Specific data | Linked to user? | Used for tracking? | Purposes |
|----------|---------------|-----------------|-------------------|----------|
| Location | Coarse Location (ZIP only) | **No** | **No** | App Functionality, Personalization |
| User Content | Other User Content (filing messages, social posts, comments) | **No** | **No** | App Functionality |
| Identifiers | Device ID | **No** | **No** | App Functionality |
| Usage Data | Product Interaction (only when chatting with Assistant — Claude needs the message) | **No** | **No** | App Functionality |

**Data types NOT collected** (for everything else Apple asks): No.

**Data NOT linked to identity** for all categories — Athen has no accounts.

**No data used for tracking** across any other app or website. (We don't have ad SDKs, analytics SDKs, or any third-party tracker.)

### 3e. Version Information (the listing the user sees)

| Field | Suggested text |
|-------|----------------|
| Promotional Text (170 chars, can update without resubmitting) | "Real bills explained in plain English by Claude. File a position in 60 seconds. Local-first, no accounts." |
| Description (4000 chars max) | See draft below |
| Keywords (100 chars, comma-separated) | `civic,bill tracker,congress,state legislature,representatives,democracy,claude,ai,activism,advocacy` |
| Support URL | URL where users can email you (e.g. `https://athen.app/support` or even a Notion/Linktree page) — **required** |
| Marketing URL | Optional, your landing page if you have one |
| Privacy Policy URL | **Required.** Host [docs/PRIVACY.md](docs/PRIVACY.md) as HTML somewhere (GitHub Pages, Notion, Webflow). Cannot be in-app only. |

**Description draft** (edit freely):

```
Athen reads the bills, rules, and council agendas already moving through your government, then tells you — in plain English — what's actually happening, who it affects, and what to do about it before the window closes.

What you get:
• Brief tab — AI-written magazine of explainers for the bills closest to your zip code, generated by Claude with date-aware reasoning so nothing stale slips through
• 5-minute audio briefing — Claude writes the script, an AI voice reads it. Listen on your commute.
• Square — your block's social feed. Comment, react with "I'll file too" instead of generic hearts, share what you filed.
• Filing in 60 seconds — tap Endorse or Oppose, Claude drafts a formal message in your chosen voice (concerned constituent, parent, business owner...), you edit, you send. The message goes to your actual representative.
• Assistant — Claude chat that knows your zip, your reps, your filing history, and the bills currently on your feed. Ask "what should I act on first?" and get a real answer.

Athen is local-first. Your zip code, your bookmarks, your social posts, and your filing history live on your phone. Nothing syncs unless you explicitly send it.

Built by one person. Open about how it works. Honest about what it can't do (Claude refuses to hallucinate — if the source doesn't say it, the brief won't either).
```

### 3f. App Review Information

| Field | Value |
|-------|-------|
| Sign-In Required | **No** (Athen has no accounts) |
| Contact First Name / Last Name / Phone / Email | Yours — Apple may call if there are review questions |
| Notes | "Athen uses Claude (Anthropic) for all AI features. The backend at `<your-railway-url>` is required for live functionality; reviewers can use it as-is or point to a different one in Settings → AI backend. No demo account needed." |

### 3g. Build (uploaded in Phase 5 below)

Leave this section blank until you've uploaded a build via TestFlight.

---

## Phase 4 — Screenshots (1 hour)

```sh
./scripts/screenshots.sh
```

Walks you device-by-device (iPhone 16 Pro Max for 6.9", iPhone 16 for 6.1") and tab-by-tab (Home, Brief, Brief detail, Square, Assistant, You). Output lands in `docs/screenshots/`.

App Store requires **at least 3 screenshots per device size**, max 10. You'll want a hero shot of each top-level tab.

Optional polish: drop them into Figma, add a tagline overlay ("Real bills, plain English"), export. Tools like [Shotbot](https://shotbot.io) or [AppLaunchPad](https://theapplaunchpad.com) automate this if you want polish without Figma effort.

Upload via App Store Connect → your app → **App Store** tab → drag screenshots into each device's section.

---

## Phase 5 — TestFlight upload (30 min)

### 5a. Archive

In Xcode:
1. Select **Any iOS Device (arm64)** as destination
2. **Product** → **Archive**
3. When it finishes, the **Organizer** window opens

Or from CLI:
```sh
xcodebuild -project CivicOS.xcodeproj -scheme CivicOS \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -allowProvisioningUpdates \
  -archivePath build/Athen.xcarchive \
  archive
```

### 5b. Upload to App Store Connect

In the Organizer:
1. Select your archive → **Distribute App**
2. Choose **App Store Connect** → **Upload**
3. Accept default options (automatic signing, manage version & build numbers, etc.)
4. Click **Upload**. Takes ~5 min.

Or from CLI (after archive):
```sh
xcodebuild -exportArchive \
  -archivePath build/Athen.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export

xcrun altool --upload-app \
  --type ios \
  --file build/export/Athen.ipa \
  --apiKey YOUR_KEY_ID \
  --apiIssuer YOUR_ISSUER_UUID
```

(You'll need to create an [App Store Connect API key](https://appstoreconnect.apple.com/access/integrations/api) first for the CLI flow.)

### 5c. Wait for processing

After upload:
- App Store Connect → **TestFlight** tab → wait ~15 min for the build to appear and processing to finish
- A yellow "Missing Compliance" tag shows up on the new build

### 5d. Export compliance

Click the build → **Manage Export Compliance**:
- **Does your app use encryption?** → **Yes** (HTTPS to your backend counts)
- **Does your app only use exempt encryption?** → **Yes** ("uses or accesses HTTPS")
- **Compliance Information** → **Done**

The build is now ready for TestFlight distribution.

---

## Phase 6 — TestFlight internal beta (10 min)

1. App Store Connect → your app → **TestFlight** → **Internal Testing**
2. Create a group: **+** → "Internal" → check the build you uploaded → save
3. **Add testers** — your own email + anyone you want trying it
4. Testers get an email + TestFlight notification to install the app

Internal testing requires no review. You can iterate quickly with internal builds while you prepare the external/public submission.

---

## Phase 7 — Submit for App Store review (30 min + 24h wait)

1. App Store Connect → your app → **App Store** tab
2. Select the build under **Build** (this is why we did TestFlight first)
3. Verify every required field has a green check (left sidebar)
4. **Save** → **Add for Review** → **Submit for Review**

Apple reviews within 24-72 hours. Common rejection reasons for an app like Athen:

| Reason | Mitigation |
|--------|-----------|
| Privacy policy URL invalid | Confirm it's HTTPS, public, and matches the URL you entered |
| Nutrition label inaccurate | Re-check Phase 3d above against what app actually does |
| AI-generated content unclear | Description mentions Claude. Reviewers may ask follow-up about safety filters — answer that Claude has Anthropic's built-in safety + we have additional system prompts (see [briefAnalysis.ts](backend/src/services/briefAnalysis.ts)) |
| Filing to government officials | If reviewer asks: Athen drafts; user reviews; user sends. No autopilot. The DraftFilingSheet always presents the message for edit before sending. |
| Backend dependency | Reviewers must be able to use the app. Either: ship with a public backend URL pre-filled (recommended), OR support mock mode (we already do) |

If rejected, you'll get specific feedback. Fix the issue, reply with an explanation, resubmit.

---

## Phase 8 — Launch (after approval)

1. **Manual release** or **Automatic release** option on the version
2. **Manual:** you click "Release This Version" when you're ready
3. **Automatic:** ships immediately on approval

Once live:
- Share the App Store link
- Watch the first 24h of installs in App Store Connect → Analytics
- Monitor backend logs (`railway logs`) for traffic
- Be ready to push a fix if anything blows up

---

## Pre-flight checklist

Before clicking **Submit for Review**, confirm:

- [ ] Apple Developer enrollment active
- [ ] Bundle ID matches between Xcode and App Store Connect
- [ ] Backend deployed to Railway and `/healthz` returns 200
- [ ] Privacy Policy URL is public and accessible
- [ ] Terms of Service URL is public (linked from app's About sheet too)
- [ ] At least 3 screenshots per required device size, all from current build
- [ ] App icon is the 1024px from `CivicOS/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
- [ ] Tested the actual `.ipa` on TestFlight on a real device (not just simulator)
- [ ] Confirmed the filing flow with a real Postmark domain OR set EMAIL_DRY_RUN=true so no real emails go to officials during review
- [ ] Reviewer notes mention how to use Athen with the backend URL pre-filled
- [ ] Export compliance answered (yes/yes for HTTPS)

When all checked: submit.

---

## When to update this doc

- After your first submission, add what actually broke
- After Apple changes their nutrition label questions (they do this yearly)
- When you add a new feature that affects privacy disclosures
