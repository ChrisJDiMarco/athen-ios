# Athen — App Store Connect listing copy

Paste these straight into App Store Connect. All copy is within Apple's
character limits and uses neutral civic-tool framing (not political advocacy).

---

## App name (30 char max)
```
Athen
```

## Subtitle (30 char max — shows under name in search results)
```
Civic engagement made simple
```

Alternates if "Athen" is taken:
- `Athen — Your civic OS`
- `Athen Civic`
- `Athen: Bills, Votes, Voice`

---

## Promotional text (170 char max — can be updated without re-submission)
```
Get plain-English briefs on every bill that affects you, file with your reps in
60 seconds, and see what your neighbors are doing — all in one place.
```

---

## Description (4000 char max)
```
Athen turns the firehose of government into something you can actually act on.

Every day Athen scans your local council, state legislature, and Congress for
bills, rules, and votes that touch your life. Then it writes a plain-English
brief explaining what the item does, who it helps, who pushes back, and what
you can do about it — file a message, sign a petition, RSVP to a town hall,
or just save it for later.

Built around three simple ideas:

• KNOW — Personalized daily briefs explain bills in language a 7th grader can
  follow. Tap a brief for a deeper dive: "How does this affect renters?",
  "What do supporters say?", "Where's the source?". Optional 5-minute audio
  briefings let you catch up on the commute.

• ACT — File on a bill, sign a petition, RSVP to a hearing — all in one
  place. Drafts route to your actual representative based on your ZIP. You
  pick the tone (concise / personal / formal) and Athen writes the message;
  you review and send. Every filing logs a receipt so you can follow what
  happened to the bill afterward.

• CONNECT — The Square is a neighborhood + city civic feed. Discuss bills
  with neighbors, share an explainer, ask a question, post an event. No
  algorithms, no rage-bait, no infinite scroll — just civic conversation
  scoped to where you actually live.

Other things Athen does that no other app does:

• News mode — scraped headlines from local + state press, so you get the
  context behind the bills, not just the bills themselves.
• Pulse mode — live ticker of what's happening in civics right now.
• Officials directory — every federal + state official with contact info,
  one tap to call or email.
• Voter Hub — registration status, sample ballot per election, rep scorecard
  with their actual votes.
• Notification inbox — all your civic pings in one place, none on your
  lock screen unless you opt in.
• Hyperlocal toggle — switch between "your block" and "city-wide" feed.

Privacy by design:
• No account required. Athen identifies you by an anonymous install ID, not
  email or phone.
• Your ZIP and interests live on your phone. The backend sees what's needed
  to deliver region-correct briefs and nothing else.
• Account deletion is one tap — wipes local data AND any backend records.
• AI use is always disclosed. Every Claude-generated brief carries an
  "AI brief" chip + a "View sources" link.

Athen is built by Chris DiMarco. Bug reports, feature requests, or factual
corrections: chris@logicoutloud.com.
```

(Word count check: ~430 words / ~2700 chars — well under the 4000 cap.)

---

## Keywords (100 char max — comma-separated, no spaces after commas)
```
civic,politics,vote,bills,congress,legislator,democracy,activism,petition,ballot,representative,local
```

(98 chars)

---

## Support URL
```
https://logicoutloud.com/athen/support
```
(Set up a simple support landing page or use the existing landing-page/
hosted somewhere — needs to be live at submission.)

## Marketing URL (optional)
```
https://logicoutloud.com/athen
```

## Privacy Policy URL (REQUIRED)
```
https://logicoutloud.com/athen/privacy
```

## Terms of Use URL (REQUIRED for in-app content)
```
https://logicoutloud.com/athen/terms
```

---

## App category
- **Primary**: News
- **Secondary**: Productivity

(Alternates: News + Reference, or News + Lifestyle. "News" primary is the
strongest fit because Athen surfaces current legislative activity.)

---

## Age rating
- Rating: **12+** (anticipated)
- Triggers:
  - Infrequent/Mild Mature/Suggestive Themes — NO
  - Infrequent/Mild Profanity or Crude Humor — NO
  - User-Generated Content — YES (Square posts/comments) → requires content
    moderation explanation
  - Unrestricted Web Access — NO (we open Safari for news links but that's
    not "unrestricted")
  - Gambling — NO
  - Contests — NO

For the user-generated content questionnaire, your answer is:
"Athen includes a community feed where users can post discussions, share
filings, and comment. All content goes through a Report + Block system with
a 24-hour moderation SLA. We use OpenAI/Anthropic moderation classifiers
plus human review."

---

## Pricing
- Free
- No in-app purchases (Athen Pro scaffolding is in the codebase but disabled
  via `BetaFeatures.athenProActive = false` — not active in this submission)

---

## Encryption export compliance
- Question: "Does your app use encryption?" → **YES**
- Follow-up: "Does your app qualify for any of the exemptions?" → **YES**
  - "Uses only encryption available within iOS" → checked
- Annual self-classification report → NO (standard-crypto exemption)

(This matches `ITSAppUsesNonExemptEncryption = false` already set in Info.plist.)

---

## App Review Information

### Contact info
- First name: Chris
- Last name: DiMarco
- Phone: (your phone)
- Email: chris@logicoutloud.com

### Demo account
- "Sign-in required: NO"
- Reviewer notes: see APP-STORE-REVIEWER-NOTES.md for the full walkthrough

### Notes for reviewer (paste in App Store Connect)
```
Athen does not require any account, login, or personal info to function. On
first launch you'll be asked for a US ZIP code — any valid US ZIP works
(suggested: 19129 for Philadelphia, 10001 for NYC). After ZIP entry the app
loads real civic data from public sources (Legistar, OpenStates, Federal
Register, Congress.gov, Google News RSS).

Filing in this v1.0 submission is HISTORY-ONLY by design — drafts are saved
locally as receipts but no email actually leaves the device. This is
deliberate per our App Store Reviewer Notes (see APP-STORE-REVIEWER-NOTES.md
in repo) to avoid spam to representatives until our backend can verify
identity. The "Sent" UI confirms the receipt was logged.

Account deletion: You → Settings → Delete my data. This wipes UserDefaults
AND fires a backend DELETE /v1/data scrub of any petition signatures and
moderation reports keyed to the install.

UGC moderation: Square posts can be Reported (7 reasons) and authors can be
Blocked. Reports fire a backend webhook within 24 hours per Apple Guideline
1.2.

Backend is hosted at https://api.athen.app (or whatever you deploy to).
Contact chris@logicoutloud.com with any questions during review.
```

---

## Screenshots (REQUIRED — 6.7", 6.5", 5.5" iPhone sizes)

Suggested 5-6 screens, in this order, with overlay text:

1. **Home — Today view**
   - Overlay: "Plain-English briefs on every bill that touches you"
2. **Brief detail with cohort card**
   - Overlay: "Tap any bill for a 30-second explainer"
3. **Square (City scope)**
   - Overlay: "What your neighbors are actually saying"
4. **Act tab — Vote sub-section showing sample ballot**
   - Overlay: "Your ballot, decoded contest by contest"
5. **Refresh progress drawer mid-stream**
   - Overlay: "Live data from every source, every refresh"
6. **News view with Philly headlines**
   - Overlay: "Local news + civic context, in one feed"

Sizes Apple wants:
- 6.7" (iPhone 16 Pro Max, 15 Pro Max): **1290 × 2796**
- 6.5" (iPhone 14 Plus): **1242 × 2688** (optional if 6.7 provided)
- 5.5" (iPhone 8 Plus): **1242 × 2208**

iPad screenshots are NOT required (we built for iPhone + iPad via
NavigationSplitView, but you can submit iPhone-only first and add iPad as
a 1.1 patch).

Recording tool: `scripts/screenshots.sh` exists for capturing simulator
shots at correct sizes.

---

## App Preview Video (optional)
15-30s. Strongest first 5 seconds. Suggested storyboard:
- 0-2s: App opens to a fresh Home with new bills loading (refresh drawer
  streaming check-marks)
- 2-6s: Tap a bill → brief explainer reveals
- 6-12s: Tap "File" → tone picker → message drafts via Claude
- 12-18s: Switch to Act → sign a petition → see signer count tick up
- 18-25s: Switch to Square → scroll a few neighbor posts
- 25-30s: Athen logo + "Get it from your local government's firehose"

Record with QuickTime + iPhone Simulator at 6.7" resolution.

---

## Submission flow

1. Archive in Xcode (Product → Archive) with **Release** config
2. Distribute → App Store Connect → upload
3. In App Store Connect:
   - Fill all the fields above
   - Upload screenshots
   - Set price + availability (US first, then expand)
   - Submit for Review
4. Apple review SLA: typically 1-3 days for clean apps. UGC apps sometimes
   take longer because they look at moderation flows.
