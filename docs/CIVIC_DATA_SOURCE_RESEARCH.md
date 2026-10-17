# Civic OS Data Source Research

Research date: 2026-05-19

## Core thesis

Civic OS should not depend on one universal civic API. The reliable architecture is a source mesh:

1. Use official APIs and bulk feeds wherever they exist.
2. Use official document scraping when APIs do not exist.
3. Treat aggregators as useful accelerators, not final authority.
4. Preserve source URLs, document IDs, timestamps, citations, parser confidence, and jurisdiction scope on every item.
5. Let AI translate and route after the source record is captured.

## Source layers

| Layer | Best sources | Civic OS use |
| --- | --- | --- |
| Address and districts | Census Geocoder, TIGERweb, Google Civic Information API, Open Civic Data IDs | Resolve address to coordinates, congressional/state/local/school districts, OCD IDs, and representative scope. |
| Federal legislation | Congress.gov API, GovInfo, Congress.gov bulk/status data, unitedstates/congress-legislators | Bills, summaries, sponsors, actions, members, committees, official text, member contact metadata. |
| State legislation | OpenStates v3, LegiScan, official state data/RSS/XML when available | State bills, votes, sponsors, calendars, committee actions, legislator lookup. |
| Local legislation and meetings | Legistar API, CivicPlus public API, Granicus/CivicPlus/BoardDocs scraping, public meeting portals | City council, county commission, boards, agendas, minutes, packets, vote records. |
| Rules and regulations | Federal Register API, Regulations.gov API, eCFR, state registers/bulletins | Proposed rules, public comment deadlines, final rules, agency notices, comment workflows. |
| Money and projects | USAspending, SAM.gov opportunities/assistance listings, FEC, Socrata, CKAN/Data.gov, ArcGIS REST | Spending near the user, grants, procurements, campaign finance, permits, zoning, inspections, infrastructure work. |
| Services and local conditions | Open311, city/county open data portals, ArcGIS feature services | 311 trends, permits, property assessments, code violations, environmental/local service issues. |
| Education and districts | NCES CCD/EDGE, TIGERweb School services | School district boundaries, schools/district metadata, board relevance routing. |

## High-value official/free sources

- Census Geocoder: address to coordinates and optional geography lookup. Useful as the first pass resolver. Docs show single-record and batch endpoints returning JSON. Source: https://geocoding.geo.census.gov/geocoder/Geocoding_Services_API.html
- Census Data API: as of May 2026, Census now requires a free API key for all Census Data API queries. Keep `CENSUS_API_KEY` configurable. Source: https://www.census.gov/library/video/2026/adrm/requesting-a-census-data-api-key.html
- TIGERweb: current legal boundaries, school districts, congressional districts for the 119th Congress, and state legislative districts for the 2024 session. Source: https://tigerweb.geo.census.gov/tigerwebmain/TIGERweb_main.html
- Google Civic Information API: useful for address to OCD IDs and election/polling info, but election data is bounded by supported elections. Source: https://developers.google.com/civic-information
- Open Civic Data IDs: normalize divisions/jurisdictions/people across systems. Source: https://open-civic-data.readthedocs.io/en/latest/data/datatypes.html
- Congress.gov API: official federal legislative API, JSON/XML, API key required, v3, 5,000 requests/hour, limit up to 250. Source: https://github.com/LibraryOfCongress/api.congress.gov/
- GovInfo API: official documents from all three federal branches; requires a free api.data.gov key; exposes collections, packages, granules, PDF/HTML/XML/MODS/PREMIS. Source: https://www.govinfo.gov/features/api
- Federal Register API: rules, proposed rules, notices, presidential documents, public inspection. Source: https://www.federalregister.gov/developers/documentation/api/v1
- Regulations.gov API: documents, dockets, and comments for rulemaking; API key via api.data.gov. Source: https://open.gsa.gov/api/regulationsgov/
- eCFR: daily updated CFR; informational/unofficial legal status, bulk XML via Data.gov/GovInfo. Source: https://www.archives.gov/federal-register/cfr/about-ecfr
- USAspending API: federal awards, geographic breakdowns, agencies, recipients. Source: https://api.usaspending.gov/
- SAM.gov APIs: opportunities and assistance listings; public API keys required. Sources: https://open.gsa.gov/api/get-opportunities-public-api/ and https://open.gsa.gov/api/assistance-listings-api/
- FEC data/API: federal campaign finance; candidates, committees, filings, contributions, spending. Source: https://www.fec.gov/data/
- SEC EDGAR APIs: no auth/key; submissions and XBRL JSON. Useful for companies tied to public contracts or local development. Source: https://www.sec.gov/search-filings/edgar-application-programming-interfaces
- Socrata/SODA: many city/state/federal portals; each dataset has an API endpoint and SoQL. Source: https://dev.socrata.com/docs/endpoints
- Data.gov Catalog API: no key, JSON, replacing prior CKAN API; base URL expected to move through api.data.gov, so do not hard-code. Source: https://resources.data.gov/catalog-api/
- Open311 GeoReport v2: service request standard for 311-style issues; some cities expose official endpoints. Source: https://wiki.open311.org/GeoReport_v2/
- Legistar Web API: strong local-government connector for councils using Legistar; covers matters, events, attachments, sponsors, histories, votes, roll calls, people, bodies. Source: https://webapi.legistar.com/Help
- CivicPlus Agenda and Meeting API: public API exists for Agenda and Meeting Management Essential accounts; coverage depends on customer setup. Source: https://www.meetingsessential.civicplus.help/hc/en-us/articles/10248707089559-Public-Application-Programming-Interface-API
- NCES CCD/EDGE: national school/district metadata and annually updated school district boundaries. Sources: https://nces.ed.gov/ and https://nces.ed.gov/opengis/rest/services/School_District_Boundaries/EDGE_ADMINDATA_SCHOOLDISTRICTS_SY1819/MapServer/0

## Pennsylvania and Philadelphia starting points

- Philadelphia Legistar is already the best local legislative source for Council matters, agendas, attachments, histories, and votes.
- Philadelphia open data includes 311 requests, property assessments, and other datasets via OpenDataPhilly/Data.Phila. Source: https://www.phila.gov/programs/open-data-program/
- PA General Assembly data downloads include bill history back to 1969 as XML ZIP archives, with current session updated hourly. Source: https://www.palegis.us/data
- PA General Assembly also exposes RSS/data surfaces from the same data page. Source: https://www.palegis.us/data

## Gaps and risks

- No universal local government data standard. Local councils use Legistar, Granicus, CivicPlus, BoardDocs, custom PDFs, Word docs, or bare HTML.
- Local officials and special districts are the weakest layer. Google Civic helps with divisions, but local boards, authorities, commissions, and contact channels usually need source-specific directories and boundary files.
- Agendas often post late, update silently, and include attachments/PDF packets where the actual impact lives.
- State legislative quality varies. OpenStates and LegiScan are helpful, but official state sources should remain the source of record when available.
- City open data portals expose permits, finance, 311, property, and inspections, but schema names and refresh cadence vary heavily.
- Regulations are strong federally, weak at the state level. State registers/bulletins often require RSS/PDF/HTML scraping.
- Public comment submission is not standardized. Some systems have APIs for discovery but not for filing. The app should draft and guide unless there is a verified submission channel.
- Anti-bot protections and terms matter. Prefer official APIs, bulk feeds, RSS, sitemaps, and low-rate scrapers with caching.

## Implementation roadmap

### 1. Geography resolver

Build a layered resolver:

1. Census Geocoder: normalize address and get coordinates.
2. TIGERweb: attach congressional district, state legislative districts, county, municipality, school districts.
3. Google Civic Information API: attach OCD division IDs and election metadata when available.
4. Local boundary overlays: council districts, wards, transit districts, water/utility boards, school board regions.

### 2. Connector registry expansion

Extend `civic-sources.json` with:

- `provider`: `legistar`, `congress`, `govinfo`, `federal-register`, `regulations-gov`, `socrata`, `arcgis`, `open311`, `civicplus`, `scrape`, `rss`, `bulk-xml`.
- `authority`: `official`, `official-aggregate`, `trusted-aggregate`, `news`, `community`.
- `auth`: `none`, `api-key`, `session`, `manual`.
- `cadence`: realtime/hourly/daily/weekly/manual.
- `parserProfile`: agenda, bill, rulemaking, permit, 311, budget, meeting-video, PDF-packet.
- `coverage`: level, geography, known gaps.

### 3. Connector build order

1. Congress.gov + GovInfo federal legislation.
2. Federal Register + Regulations.gov comment deadlines.
3. PA General Assembly XML/RSS.
4. Socrata discovery/query for Philly permits, assessments, 311, contracts.
5. ArcGIS REST feature service connector for boundaries and planning datasets.
6. Open311 connector where official endpoints exist.
7. CivicPlus agenda connector.
8. Granicus/BoardDocs scraper profiles.

### 4. AI extraction pattern

For every source document:

1. Fetch raw source and store immutable source snapshot metadata.
2. Classify document type and jurisdiction.
3. Extract structured issue JSON with citations and confidence.
4. Cross-check against official metadata when available.
5. Deduplicate by official ID, canonical URL, date/body/action, and document hash.
6. Score impact by deadline, geography, issue topic, monetary amount, public comment opportunity, and user profile.
7. Surface as a feed item with "why this matters", exact source links, and next action.

### 5. Product ideas this unlocks

- "Comment before it closes": rules, hearings, board agendas, zoning, utilities, school boards.
- "Money near me": grants, awards, contracts, capital projects tied to ZIP/district.
- "Permit radar": demolitions, zoning variances, construction, street closures, environmental notices.
- "Rep activity": sponsored bills, votes, committee actions, public statements, donation context.
- "Local board watch": school board, transit authority, zoning board, water/rate board, planning commission.
- "Evidence mode": every AI summary shows source paragraphs, confidence, parser warnings, and official document links.
- "Watch agents": user follows topics/places; Civic OS monitors sources and posts new explainers into the feed.

