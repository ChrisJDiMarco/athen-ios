# Athen — Your Civic Operating System

**Stay informed. Get help. Act together.**

Athen is a civic engagement app for people who are tired of being told to "get involved" without being told how. It pulls every bill, vote, election, and government program that affects you into one place, explains it in plain English, and gives you one-tap tools to actually do something about it.

---

## The App Store Pitch

> Athen turns civic life into something you can actually keep up with.
>
> Type your ZIP. Get a feed of the bills, votes, and elections that affect *you* — federal, state, and local — explained without the jargon. Tap any item to see who pays, who benefits, what both sides argue, and what happens if you do nothing. Press one button to email your rep, sign a petition, or start one of your own. Ask Athen anything in plain English and get a personalized civic plan in seconds.
>
> Plus: real-time election deadlines, sample ballots with neutral pro/con briefs, a master directory of every elected official in the United States, and an AI assistant trained on every bill in your jurisdiction.
>
> No ads. No outrage cycle. No partisan filter. Just the information and the buttons.

**Tagline options:**
- *See what power is doing. Act for the public good.*
- *Civic life, one ZIP code at a time.*
- *Your government, finally readable.*

---

## Who Athen is for

**Athen is for people who:**
- Want to stay informed but don't have time to read 800-page bills
- Want to contact their reps but never know what to say
- Care about local government but can't figure out when meetings happen or what's on the agenda
- Are voting for the first time and want a real sample ballot — not just a list of names
- Just had a major life event (job loss, new baby, illness, eviction, move) and need to know what programs they qualify for
- Want to know what their senator actually voted on last week
- Want to organize a group of neighbors around a single ask, without learning Excel

If you've ever opened the news, felt rage or helplessness, and closed the tab — Athen is the app that gives you somewhere to put that energy.

---

## What's in the app

Athen is organized into six top-level surfaces. Each one does one thing well.

### 1. Home — your civic dashboard

The first thing you see when you open Athen. Personalized to your ZIP and your interests.

- **Smart hero** — a time-of-day greeting (morning briefing, afternoon check-in, evening recap) that tells you what's most important *right now*
- **Pulse strip** — three at-a-glance chips: your civic streak, what changed since your last visit, and the next deadline on your radar
- **AI Brief of the day** — the single most important item in your feed, with a "Listen" button to hear it read aloud (more on Read Aloud below)
- **Conditional cards** that appear only when relevant: next election countdown, federal vote of the week, what changed in bills you bookmarked, source health
- **Life Event front door** — a single button: *"Tell Athen what's happening"*
- **Tiles** for Petitions, Voter Hub, Officials Directory, and your saved feed

### 2. Brief — the AI civic editor

Every bill, vote, and rule in your feed gets a deep brief written by Claude (Anthropic's most capable model). Each brief includes:

- **Headline + subhead + lead** — what's happening and why it matters
- **Key facts** — five bullet points you can quote in a conversation
- **Both sides** — the strongest argument from supporters and critics, side by side
- **Fiscal impact** — who pays, who benefits, real dollar figures when available
- **Timeline** — when it happens, with each milestone dated
- **Cohort projection** — *"How this affects you"* tailored to your profile (homeowner / renter / parent / small business / etc.)

**Power features on every brief:**
- *Read aloud* — Athen reads the brief to you using ElevenLabs' Speech Engine. Eyes-free.
- *Explain it for…* — re-render the brief for a 12-year-old, your parents, your landlord, or a neighbor
- *Translate this* — inline translation popover, any language
- *Ask Athen* — open the chat with the brief pre-loaded as context

Briefs are cached per-bill so they're instant once generated, and re-generated when the underlying bill changes.

### 3. Square — the social side

The civic feed, but social. Not Twitter, not Reddit — purpose-built for civic activity.

- **Posts** — real activity from real users in your area: filings sent, petitions signed, action taken
- **Three reactions** — Stand with, Concerned about, Want to learn more
- **Threaded comments** with proper civility moderation
- **Auto-share filings** (opt-in) — when you email your rep, Athen can post your stance to Square so neighbors can rally with you
- **Empty by default** on fresh installs — no fake personas, no astroturfing

### 4. Voter Hub — everything election

A dedicated rail for the parts of civic life that have hard deadlines.

- **Election hero** — day-count to the next election with urgency gradient (green → amber → red)
- **Polling place lookup** — drop your ZIP, get your assigned polling place with hours and Maps directions
- **Sample ballot** — every contest on your upcoming ballot with a Claude-written neutral brief for each (Pro / Con / What YES means / What NO means). Mark each contest with *Lean YES / Lean NO / Plan to support / Skip* to build your printable plan.
- **Voter registration** — state-by-state portal with deadlines, online/same-day/automatic-at-DMV flags, ID requirements
- **Rep scorecard** — see how your federal + state reps voted on the bills you filed about. Per-rep alignment %, topic breakdown, mismatches, pending votes.
- **Money trail** — top campaign-finance industries for each rep, via OpenSecrets
- **Election Day mode** — a focused view on voting day: polling place, hours, what to bring, your ballot plan

### 5. Petitions — collective action, end-to-end

Anyone can start a petition. Athen handles delivery.

- **Browse** by ZIP, topic, status (open / delivered / expired), or "Mine"
- **Sign** with one tap — your signer count and ZIP heatmap update live
- **Create** with Claude-assisted drafting: paste the issue, get a polished petition with a title, ask, and body
- **Auto-target** — Athen picks the right official to send to based on the topic + your jurisdiction
- **Auto-deliver** — when the threshold or deadline hits, Athen sends a Claude-written cover letter + signature roll via Gmail (your account, via Composio) or a backend dispatcher. You see the delivery receipt in the petition's detail view.
- **Signer wall** — first 40 signers with ZIP prefixes, plus a "+N more" count

### 6. Life Events — the "I don't know where to start" front door

This is the feature you didn't know you needed.

Type (or speak) what's happening:
- *"I just lost my job"*
- *"My mom needs help paying for her medications"*
- *"I'm being evicted in 30 days"*
- *"My toddler isn't getting services they were promised"*
- *"I just moved to a new state — what do I need to register for?"*

Athen returns a structured civic plan with:
- **Do today** — urgent actions with one-tap shortcuts (call X, visit URL Y, file form Z)
- **This week + month** — medium-priority steps
- **Longer term** — strategic follow-ups
- **Qualifying programs** — federal/state/local programs you may be eligible for, with apply URLs
- **Civic asks** — bills, petitions, or officials you should contact about the systemic issue
- **Notes** — anything Athen flagged as a watch-item

Plans are saved to your profile and can be revisited from Home. The full plan can be read aloud.

---

## Beyond the six surfaces

### Officials Directory

A constantly-updated master directory of every elected official in the United States.

- **Federal** (always loaded): President, VP, all 100 senators, all 435 representatives, 6 non-voting delegates
- **State** (loaded when you enter a ZIP): governors, lieutenant governors, state senators, state representatives
- **Search** by name, jurisdiction, party, chamber
- **Per-official detail**:
  - Bio, photo, party, district, term dates
  - Contact info (offices, phone numbers, click-to-call, click-to-map)
  - Social accounts (X, Facebook, Instagram, YouTube, LinkedIn, TikTok)
  - External links: Wikipedia, Ballotpedia, OpenSecrets, Bioguide
  - **Your filings with this official** — auto-pulled from your filing history
  - **Read aloud** the profile
  - **Bookmark** to your "My reps" section

Data sources: `unitedstates/congress-legislators` (YAML), Bioguide for photos, OpenStates for state legislators.

### Filings — one-tap letters to your reps

The original Athen feature. Tap *Endorse* or *Oppose* on any bill:

- Athen drafts a personalized letter based on your profile (homeowner, parent, small-business owner, etc.) with a tone you pick (warm / firm / measured / urgent)
- **Smart-default tone** based on the issue — Athen picks the most effective tone for that bill type, you can override
- **Draft variants** — see two or three alternative drafts side-by-side and pick the one that sounds like you
- **Undo Send** — countdown timer after you tap Send so you can pull back if you regret it
- **Where it goes** — sent via Gmail (your account, via Composio) so it looks like real constituent mail. If Gmail isn't connected, falls back to a backend dispatcher with the right contact-form for the right office.
- **Channel-aware dispatch** — Athen knows which offices accept email vs require a web form; routes correctly per representative
- **Receipt persists** in your filing history forever — searchable, exportable, viewable per-rep
- **Automation hooks** at send-time: log to Notion, post to Slack/Discord, share to X/LinkedIn, add a calendar event for follow-up

### Group Letters

Coordinate a letter with neighbors. One letter, many signers. Same delivery pipeline as petitions but with a shorter timeline and a single ask.

### Ballot Photo Scanner

Snap a photo of your mail-in ballot or sample ballot. Athen OCRs the contests and looks up the Claude-written brief for each one. Useful when you're handed a ballot in a coffee shop and want a fast read.

### Translate this + Explain it for…

Two distinct intelligence buttons on every brief:

**Translate this** — inline popover that converts the brief into any language. Useful for multilingual households, recent immigrants, ESL voters, or sending a brief to family abroad.

**Explain it for…** — keeps the brief in English but re-renders it for a different audience:
- *A 12-year-old* — shorter sentences, no jargon
- *Your parents* — practical framing, what to actually do
- *Your landlord* — implications for property owners
- *A neighbor* — kitchen-table language

Useful when you want to forward a bill to someone who doesn't read policy.

### Athen Assistant (Chat)

A chat tab with Claude trained on every bill, brief, and source in your jurisdiction. Ask:
- *"What's the most important bill this week?"*
- *"Did Senator [X] vote on the housing bill?"*
- *"Who do I contact about a pothole in my neighborhood?"*
- *"Explain the new tax change in one paragraph"*

Markdown rendering, threaded responses, suggested follow-ups.

### Read Aloud + Audio Briefings (Powered by ElevenLabs Speech Engine)

Athen reads any brief, petition, plan, or official profile aloud — high-quality natural voice, not robotic TTS. Falls back gracefully to on-device speech when ElevenLabs is unreachable.

**Read Aloud** — a *Listen* pill on:
- Brief detail (headline + subhead + key facts + both sides + fiscal in one stream)
- Petition detail (title + ask + body)
- Official detail (name + role + bio + jurisdiction)
- Life Event plans (situation + do today + this week + longer term + qualifying programs)

**Audio Briefing** — a separate, longer-form feature. Tap the audio card on Home and Athen:
1. Picks the top 4–6 items in your feed (federal + state + local, ranked by urgency × your interests)
2. Writes a ~5-minute spoken script with Claude (news-anchor cadence, no fluff, transitions between items)
3. Synthesizes it with ElevenLabs (voice "Sarah", model `eleven_turbo_v2_5`)
4. Streams the MP3 with proper audio-session backgrounding so it keeps playing when you leave the app

Great for commutes, walks, or making coffee.

### What Changed (Diff Intelligence)

Athen watches every bill you bookmark. When the text, vote date, or sponsor list changes, you see a *"What Changed"* card on Home explaining the diff in plain English.

### Civic Streak

A daily streak counter. Engage with any civic action (read a brief, sign a petition, file a letter, attend a hearing) and you keep your streak. Visual on Home and in You.

### Connections (Composio Integrations)

Connect your tools so Athen can amplify your actions.

- **Gmail** — send filings from your own address (more legitimate to your rep's office)
- **Google Calendar** — bookmark a hearing or vote, get a calendar event auto-added
- **Notion** — log every civic action to your personal Notion database
- **Slack** — post your filings to a team or community channel
- **Discord** — same for Discord servers
- **X (Twitter)** — auto-post your stance with a generated thread
- **LinkedIn** — post a longer-form take

Each integration is per-user via OAuth (Composio handles auth) and toggleable per-event-type. Nothing fires without your explicit setup.

### Smart Notifications + Ambient Briefing

Athen can send you a daily morning briefing notification at a time you pick. Quiet on quiet days. Loud when there's a real deadline.

- **Vote-day alerts** — when a bill you care about hits the floor
- **Deadline warnings** — registration cutoffs, comment periods closing, hearing tomorrow
- **What changed** — when a bookmarked bill is amended
- **Ambient morning briefing** — auto-fires at your set time, opens to the audio briefing card

### Source intelligence + ingestion

Athen runs an ingestion orchestrator that pulls fresh data from every source in parallel:

- **40-second per-connector timeout** with one-shot retry + 750ms backoff — flaky federal endpoints don't take down the whole refresh
- **ZIP-aware routing** — when you change ZIPs, the right Legistar city is picked automatically and stale caches are invalidated with a banner prompting refresh
- **Source pulse** — a Home card shows which sources updated recently and which are stale
- **Sources panel** — toggle individual sources on/off (e.g. mute a city council if you don't care)
- **Refresh button** on Home runs the whole orchestrator and reports back: *X new items, Y updated, Z sources hit*

### Robust AI output

The Claude integration is built to not fail you mid-generation:

- **Large token budgets** on every AI surface (briefs, plans, drafts, chat) so you don't get cut off mid-JSON
- **JSON salvage** — if Claude truncates a brief or plan response, Athen walks the partial JSON back to the last safe structural boundary and recovers it instead of failing
- **GovInfo enrichment** — federal bill briefs get the actual bill text injected into the Claude prompt, so analysis cites real provisions, not summaries
- **Cached briefs** by source fingerprint — instant on second view, regenerated when the bill changes

---

## Behind the scenes — sources & honesty

Athen is only as good as its sources. We use:

**Federal bills + votes**
- Congress.gov API (bills, actions, roll-call references)
- GovInfo (full bill text — injected into Claude prompts so briefs cite real provisions)
- Federal Register (proposed rules + comment periods)

**State bills + votes**
- OpenStates v3 (bills, vote events with per-member outcomes, legislators across all 50 states)
- State-specific registration portals (deadlines, online flags, ID requirements)

**Local government**
- Legistar (13 major cities: Philadelphia, NYC, Chicago, Boston, LA, DC, Seattle, Portland, SF, Detroit, Houston, Austin, Minneapolis — expanding to 25+ by end of summer)
- Socrata (open data catalogs across NYC, Chicago, LA, Austin, Seattle, SF)
- Open311 (city service requests — what your neighbors are reporting)
- Firecrawl-powered news + civic site ingestion (for sources without an API)

**Elections**
- Google Civic Information API (polling places, sample ballots, election lookup)
- State-level static registration data tables (covers all 50 states + DC)

**Officials directory**
- unitedstates/congress-legislators (YAML, refreshed on a schedule — 536 federal legislators)
- Bioguide (high-resolution official photos)
- OpenStates `/people` endpoint (state legislators, lazily loaded per state)
- Static seed data: POTUS, VPOTUS, 15+ governors

**Campaign finance**
- OpenSecrets (`candIndustry` — top industries funding each member of Congress)

**Vote intelligence**
- Per-vote store keyed by bill external ID + canonicalized official name
- Background worker (30-min poller) keeps the vote store warm
- Rep scorecard cross-references your filings with these votes to compute alignment %

**AI**
- Anthropic Claude (Sonnet 4.6 — bill analysis, deep briefs, life-event plans, drafted filings, chat assistant, audio-briefing scripts, petition cover letters)
- ElevenLabs Speech Engine (`eleven_turbo_v2_5` model, Sarah voice — read-aloud across the app + audio briefings)

Every brief, plan, and letter is **AI-generated but source-attributed** — you can always tap through to the original government source. We try hard not to hallucinate: when Athen doesn't know something, it says so.

---

## Privacy + posture

- **Your ZIP, your profile, your bookmarks** live on-device by default
- **Filings** are sent through your own Gmail when Gmail is connected — they look like real constituent mail, because they are
- **No ad tracking**. We don't sell or share your engagement
- **No partisan lean.** Both sides on every brief. Neutral framing on sample-ballot contests. We let the source data speak.
- **Open source data** — every source is publicly documented government data. Athen doesn't scrape anything you couldn't see by hand.

---

## How to use Athen (5-minute quickstart)

1. **Open the app and enter your ZIP.** Athen uses it to find your district, your state legislature, your city council, your polling place, your reps.
2. **Pick your interests** (housing, climate, education, healthcare, etc.) — this filters the feed so you see what matters to you.
3. **Read the AI Brief of the day** on Home, or tap any item in your feed for the full brief. Try the *Listen* button.
4. **Open the Voter Hub** and check your next election. If you're not registered, the registration card walks you through your state's process.
5. **Try a Life Event plan** — even if nothing's happening right now, type *"I'm thinking about buying a house"* or *"My elderly parent might need help"* to see what Athen can do.
6. **Connect Gmail** (Profile → Connections) so your filings go from your real address.
7. **File your first letter** on any bill you care about. It takes 30 seconds.
8. **Browse the Officials Directory** — bookmark your reps so they're one tap away.

That's it. Use Athen as often as feels right. Some users open it daily for the morning brief; others use it on demand when they want to take action.

---

## What Athen is not

- **Not a news app.** Athen indexes government data and explains it. We don't write news.
- **Not a campaign tool.** We don't tell you who to vote for.
- **Not a chat bot wrapper.** The AI is in service of structured civic data, not the other way around.
- **Not a social network you'll lose hours in.** Square exists, but it's for action — not engagement metrics.
- **Not free of opinion when it counts.** When a bill would clearly hurt the people it claims to help, the brief will say so — with sources. We will not be a both-sides-of-fascism app.

---

## Roadmap (next 90 days)

In active development:
- **Civic Deadline Tracker** — a personal kanban of every deadline (vote, hearing, comment period, registration cutoff, filing window) auto-populated from your feed
- **Hearing recordings** — Whisper-transcribed local government meetings with key-moment timestamps
- **Coalition mode** — turn a successful petition into a sustained advocacy group
- **State expansion** — full local coverage in 25+ cities by end of summer
- **Spanish + 5 more languages** — full UI translation, not just brief translation
- **Apple Watch glance** — your next deadline + civic streak on your wrist
- **Live election night** — real-time results with Athen-written context

---

## Credits

Athen is built on the work of countless open data projects, journalists, civic technologists, and the people who pushed for transparent government:

- The [unitedstates/congress-legislators](https://github.com/unitedstates/congress-legislators) project
- [OpenStates](https://openstates.org) (Plural Policy / Open States Foundation)
- [GovInfo](https://www.govinfo.gov) (U.S. Government Publishing Office)
- [OpenSecrets](https://www.opensecrets.org)
- [Google Civic Information API](https://developers.google.com/civic-information)
- The 13 city Legistar instances we ingest
- [Anthropic Claude](https://www.anthropic.com) for the brain
- [ElevenLabs](https://elevenlabs.io) for the voice
- [Firecrawl](https://firecrawl.dev) for the web spine
- [Composio](https://composio.dev) for the integrations

And the operator: you.

---

**Athen** — *See what power is doing. Act for the public good.*
