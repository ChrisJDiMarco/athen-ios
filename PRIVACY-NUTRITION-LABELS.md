# Athen — App Store Privacy Nutrition Labels

This document maps directly to the App Store Connect privacy questionnaire. Each section corresponds to a question in the App Privacy form.

## Data Used to Track You

**Answer: No data collected for tracking.**

Athen does not use the Apple Advertising Identifier (IDFA), does not share data with data brokers, does not display third-party advertising, and does not link user data across other apps or websites owned by other companies.

## Data Linked to You

**Answer: No data linked to user identity.**

Athen does not require an account, does not collect a name, email, phone number, or any identifier that could link app activity to a real person. The per-install UUID (used for rate-limiting and abuse prevention) is generated client-side, persists only on-device in UserDefaults, and is not linked to any other identifier we hold.

## Data Not Linked to You

These items are collected by Athen but **not linked to user identity**:

### Identifiers
- **Device ID** (per-install UUID, generated client-side, never reset by us)
  - Purpose: App Functionality, Analytics (rate-limiting per install)

### Diagnostics
- **Crash Data** (if Sentry is wired in v1.1; not collected at v1 launch)
  - Purpose: App Functionality

### Other Data
- **ZIP code** (entered by user during onboarding)
  - Purpose: App Functionality (look up the user's elected representatives, polling place, sample ballot, state-specific civic data)
- **Civic interests** (user-selected categories like Housing, Climate, Healthcare)
  - Purpose: App Functionality (rank content in feed)
- **Civic factors** (user-selected role tags like "renter", "parent", "small-business owner")
  - Purpose: App Functionality (personalize cohort projections in briefs and life-event plans)
- **Filing history** (record of bills the user has stated a position on)
  - Purpose: App Functionality (Profile → History view, Rep Scorecard alignment math)
  - Storage: On-device by default. Sent to backend only when the user opts in to Gmail delivery via Composio.
- **Petition signatures** (when a user signs a petition)
  - Purpose: App Functionality (signer count, ZIP heatmap)
  - Stored on backend with signer ZIP prefix only; full ZIP never stored.

## Data Collection Detail (per Apple's categories)

| Apple Category | Specific Item | Collected? | Linked to You? | Purpose | Stored Where |
|---|---|---|---|---|---|
| Contact Info | Name | No | — | — | — |
| Contact Info | Email | No | — | — | — |
| Contact Info | Phone | No | — | — | — |
| Contact Info | Physical Address | Partial (ZIP only) | No | App Functionality | On-device + backend (anonymized) |
| Health & Fitness | All | No | — | — | — |
| Financial Info | All | No | — | — | — |
| Location | Precise | No | — | — | — |
| Location | Coarse (ZIP) | Yes | No | App Functionality | On-device + backend |
| Sensitive Info | All | No | — | — | — |
| Contacts | All | No | — | — | — |
| User Content | Photos | Optional (user attaches to a post) | No | App Functionality | On-device (attached to a Square post) |
| User Content | Audio | No (mic for speech-to-text only, audio not stored) | — | — | — |
| User Content | Other user content | Yes (Square posts, petition text, life-event prompts) | No | App Functionality | On-device + backend |
| Browsing History | All | No | — | — | — |
| Search History | All | No | — | — | — |
| Identifiers | User ID | No (no login) | — | — | — |
| Identifiers | Device ID | Yes (per-install UUID) | No | App Functionality, Analytics | On-device + backend |
| Purchases | All | No (no IAP) | — | — | — |
| Usage Data | Product Interaction | Optional (only if Sentry/PostHog wired in v1.1) | No | Analytics | Third-party (Sentry/PostHog) |
| Usage Data | Advertising Data | No | — | — | — |
| Diagnostics | Crash Data | Optional (v1.1) | No | App Functionality | Third-party (Sentry) |
| Diagnostics | Performance Data | Optional (v1.1) | No | Analytics | Third-party (Sentry) |
| Diagnostics | Other Diagnostic Data | No | — | — | — |
| Surroundings | All | No | — | — | — |
| Body | All | No | — | — | — |
| Other Data | All | No | — | — | — |

## Third-Party Data Processors

When a user takes action, Athen may send the minimum required data to:

| Processor | Data Shared | Why |
|---|---|---|
| Anthropic (Claude API) | User's stated stance + bill summary + user's civic factors (anonymized) | Drafting letters, generating briefs, life-event plans |
| ElevenLabs | Brief/petition/plan text (no user identifiers) | Voice synthesis for Read Aloud |
| Firecrawl | Public URLs being scraped | Web ingestion of government sites without APIs |
| Composio | User's OAuth token (per-app) | User-initiated Gmail send, Calendar add, Notion log, etc. |
| Google Civic API | ZIP code | Polling place + sample ballot lookup |
| OpenStates | State + jurisdiction | Bill + vote data |
| Congress.gov | Bill IDs | Federal bill text + actions |

All third-party calls are server-side proxied from the Athen backend; the iOS app never embeds third-party API keys.

## Data Retention

| Data Type | Retention |
|---|---|
| Bills, votes, elections from official sources | Cached on backend, refreshed on schedule |
| User filing history | On-device indefinitely; user can delete |
| Petition signatures | Until petition is delivered or expires (max 90 days), then archived |
| Life-event plans | On-device indefinitely; user can delete |
| Sentry crash data (when added) | 90 days |
| AI generation logs | Not retained — Claude requests are streamed and discarded |

## Children

Athen is rated **12+** due to political content. We do not knowingly collect data from children under 13.

## Right to Delete

Athen does not maintain a user account, so there is no account to delete. Users can:
- Clear all on-device data by deleting the app
- Revoke any Composio OAuth grant in their Composio account
- Request deletion of any backend-stored petition signatures by emailing chris@logicoutloud.com

## Contact

For privacy questions: chris@logicoutloud.com
