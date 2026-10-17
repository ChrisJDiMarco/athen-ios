# Naming And Upstream Civic OS Research

Research date: 2026-05-19

## Short answer

The app should be renamed before public launch.

`Civic OS` is already used by an active organization/product with a public website, GitHub organization, AGPL-licensed repository, and a trademark application for software-related services. Even if there may be a technical path to coexistence, the brand is crowded enough that keeping the same public name creates avoidable confusion.

## What the existing Civic OS is

- Website: `civic-os.org`
- GitHub: `github.com/civic-os/civic-os`
- Product: low/no-code app framework for governments and nonprofits.
- Positioning: self-hosted/open-source tools for agencies and mission-driven organizations.
- Stack: Angular 20, PostgREST, PostgreSQL 17/PostGIS, Keycloak, Tailwind/DaisyUI, Leaflet, JointJS.
- License: `AGPL-3.0-or-later`.

This is adjacent to our market, but not the same app. Their project is closer to a municipal/internal database app generator. Our app is a consumer-facing civic intelligence, action, and social layer.

## Trademark / naming risk

Preliminary research found a `CIVIC OS` trademark application with serial number `98912296` for software design/development services. This should be verified in official USPTO TSDR before any public launch or filing decision.

Practical risk level: high enough to rename.

Reasons:

- Same exact words.
- Same broad software/government/civic territory.
- Existing public website and GitHub organization.
- Existing mission overlap around government, open data, and civic technology.

This is not legal advice. Before committing to a final public name, run a proper clearance pass: USPTO, App Store, Google Play, GitHub org/package names, domains, social handles, and a general web search.

## Can we use their app somehow?

Yes, but carefully.

Best uses:

1. Reference architecture only.
   - Learn from their metadata-driven UI model, PostGIS usage, permissions, and government/nonprofit examples.
   - This is the safest path.

2. Connector target.
   - If municipalities deploy upstream Civic OS, our app could ingest their public APIs as another source type.
   - This lets us be compatible without embedding their code.

3. Optional municipal back-office experiment.
   - Their app could be tested as an internal admin/source-management portal for a pilot city or nonprofit.
   - Keep it separate unless we explicitly accept AGPL obligations.

Risky uses:

- Copying source files into our app.
- Forking and modifying it as part of our backend/frontend without planning around AGPL.
- Branding our app as affiliated with their Civic OS project without permission.

AGPL note: AGPL code can be powerful, but if we modify or offer a modified network service based on it, we should assume source availability obligations. Keep any direct reuse behind a conscious licensing decision.

## Naming implication

Avoid names that are already visibly crowded in this space:

- `Civic OS`
- `CivicScope`
- `CivicWire`
- `Civic Signal`
- `CivicLens`
- `CiviQ`
- `Civvy`
- `GovRadar`
- `Public Pulse`
- `CityBrief`

The safest naming direction is less "government operating system" and more "personal civic radar / action layer."

## Initial name directions

Names worth deeper clearance:

- `DocketLight` — suggests government documents made understandable.
- `CouncilSignal` — clear local-government signal, but "Signal" has messaging-app baggage.
- `AgendaLight` — agenda packets made readable; a little utilitarian.
- `TownSignal` — friendly/local, but may feel smaller than state/federal coverage.
- `PublicPath` — emphasizes guided action, softer and broader.
- `CivicRelay` would have been good, but already appears taken.

My current recommendation: keep `Civic OS` as an internal codename for the repo until we pick a final name, then rename public-facing strings first. Do not rename package/class names until the public brand is chosen, unless we want a full project identity migration.

## Rename implementation plan once a name is chosen

1. Public display name: Xcode build setting `INFOPLIST_KEY_CFBundleDisplayName`.
2. User-facing Swift strings: onboarding, dashboard, share text, about/legal copy, AI copy.
3. Backend visible strings: email sender name, system prompts, logs, README/deploy docs.
4. Deep links and bundle ID: decide whether `civicos://` and `com.chrisdimarco.CivicOS` change now or later.
5. Docs and screenshots.
6. App Store/website/social/domain identity.

Recommended sequencing:

- Phase 1: Public copy/display rename only.
- Phase 2: Bundle/deep-link rename before external beta.
- Phase 3: Repo/module/class rename only if needed for cleanliness.

## Sources

- Existing Civic OS website: https://civic-os.org/about/
- Existing Civic OS GitHub repo: https://github.com/civic-os/civic-os
- Existing Civic OS vision repo: https://github.com/civic-os/vision
- `CIVIC OS` trademark listing, serial `98912296`: https://trademarks.justia.com/989/12/civic-98912296.html
- USPTO guidance for checking status in TSDR: https://www.uspto.gov/trademarks/apply/check-status-view-documents
