# Athen Privacy Policy

**Effective date:** 2026-05-19
**Operator:** Chris DiMarco (sole developer)
**Contact:** chris@logicoutloud.com

This privacy policy describes how the Athen iOS app and the Athen backend handle your information. Athen is a civic-action tool that helps residents understand bills, rules, and government actions and file messages to their representatives. Athen is designed local-first: most of what you do stays on your phone.

If anything below conflicts with what the app actually does, that's a bug. Tell us and we'll fix the app or the policy, whichever is wrong.

## What we collect

We try to collect as little as possible. The actual data sets:

### Stays on your device only (never sent anywhere)
- Your ZIP code (used to find your representatives)
- Your civic context tags (renter, parent, business owner, etc.)
- Your topic interests (housing, transit, etc.)
- Your filing receipts (which bills you've endorsed or opposed, with confirmation codes)
- Your bookmarks
- Your social posts and comments inside the Square tab
- App preferences (refresh cadence, disabled sources, backend URL)

This data is stored in iOS UserDefaults and never leaves the device unless you explicitly perform an action that sends it (see below).

### Sent to the Athen backend when you trigger an action
- **When you tap Endorse or Oppose on an issue:** the issue identifier, your ZIP, and the message you reviewed. The backend resolves your representative and drafts the message text via Anthropic Claude. The drafted message is returned to your phone and saved to your local filing history. **In v1, Athen does not send the message to the official's office** — direct delivery is rolling out in a later release. If you have connected your Gmail account via Composio (opt-in), Athen sends from your own Gmail address on your explicit confirmation. We do not retain personal identifiers in backend logs beyond what's needed to draft the message and return a confirmation code.
- **When you use the Assistant chat:** your message text, plus a redacted snapshot of your visible feed (issue titles, scopes, vote dates, your filing history confirmation codes), is sent to Anthropic Claude through our backend. Claude's response streams back to you. The request is not retained on our servers after the response completes.
- **When you tap "Pull fresh briefs" or load the Brief tab:** the backend reads its own ingested issue cache and may call Anthropic Claude to write per-issue explainers. No personal data is sent for this — briefs are written once per issue and shared across all users.
- **When you play the 5-minute audio briefing:** the backend asks Claude to write a script using cached issue data, then calls ElevenLabs (when configured) to render speech. No personal audio is sent to ElevenLabs; only the script text.
- **When you set or test the backend URL:** the URL you entered is stored on-device and the app makes a `GET /healthz` request to it.

### Third-party services Athen uses
We forward data to these providers only as listed above:
- **Anthropic** (claude.ai) — message drafting, chat answers, brief writing, life-event plans
- **ElevenLabs** — text-to-speech for Read Aloud + audio briefings
- **Composio** — per-user OAuth bridge if you opt in to send filings via your own Gmail, log to your Notion, post to your Slack, etc. We only forward your action input; Composio holds the OAuth tokens, not Athen.
- **OpenStates** — read-only public data about state legislators and bills (no personal data sent)
- **Congress.gov, GovInfo, OpenSecrets** — read-only federal data (no personal data sent)
- **Google Civic Information API** — polling-place + sample-ballot lookup (your ZIP only)
- **Firecrawl** — read-only news corroboration + web scraping of public government sites (no personal data sent)
- **Federal Register & U.S. Census Geocoder** — read-only public data lookups (no personal data sent)
- **Postmark** — will be added in a later release for direct email delivery of filings

Each provider has its own privacy policy. Athen does not sell or share your data with advertisers, brokers, or third parties beyond the above.

### What we explicitly do not collect
- Names (you can use Athen entirely under a ZIP code)
- Phone numbers, email addresses (unless you choose to file with an official whose contact requires it)
- Precise location (we use ZIP, never GPS)
- Contacts, photos beyond what you attach to a post, biometrics, microphone audio (except briefly when you use the voice mode)
- Browser history, third-party tracking IDs, ad identifiers

## Notifications

Athen uses on-device local notifications to remind you of upcoming votes on bookmarked or interest-matched issues. These are scheduled locally on your phone and do not require us to know what you're being notified about. We do not use push notifications (APNS) or any server-side notification infrastructure.

## Data retention

- On-device data: kept until you delete the app or explicitly clear it via settings.
- Backend logs: rotated every 30 days for operational debugging. Filing confirmation codes are retained indefinitely so we can verify a message was delivered if you ask later.
- Brief cache: kept indefinitely keyed by source fingerprint so we don't re-pay Claude for the same bill. No personal data is in the cache.

## Your rights

- **See what's stored on your phone:** the You tab shows your profile, bookmarks, history.
- **Delete your data:** delete the app. There is no server-side account to delete because we don't have accounts.
- **Stop notifications:** iOS Settings → Notifications → Athen → off.
- **Stop using a backend:** open You → AI backend → Clear. The app reverts to bundled mock services.

## Children

Athen is not directed at children under 13 and we do not knowingly collect data from them. Civic action requires you to be old enough to communicate with a government official, which generally means a teenager or adult.

## Changes

If we change this policy in a way that affects what we collect, we'll surface a notice in the app on next launch.

---

*Athen is a small project. This policy is plain English on purpose. If you have questions, just email us.*
