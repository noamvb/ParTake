# Analysis report: partake-polls-sources

- Category: research
- Schema: analysis-report/v1

## Summary

Analysis of automated data sources for a Canadian federal seat projection hobby app (45th Parliament, Oct 2026). Identifies Wikipedia, 338Canada, CBC Canopy API, and Elections Canada official results formats, assesses riding poll scarcity, and synthesizes 338Canada and CBC projection methodologies.

## Findings

### 1. [verified_fact] Wikipedia Federal Polling Structure, Retrieval Methods, and Licensing

The active Wikipedia polling article is titled 'Opinion polling for the 46th Canadian federal election' (to which 'Opinion polling for the next Canadian federal election' redirects). The main 'Table of polls' records ONLY national voting intention rows and lacks regional rows for Atlantic, Quebec, Ontario, Prairies, Alberta, or BC. Regional polling is located under a separate 'Regional polls' section with standalone provincial tables for Quebec (10 polls), Ontario (6 polls), Manitoba (6 polls), Alberta (8 polls), and British Columbia (7 polls); Atlantic Canada and Saskatchewan/Prairies have no regional tables. Per-row fields in the national table comprise Polling firm, Last date of polling (end date only, not full field dates), Link (reference citation), party percentages (LPC, CPC, BQ, NDP, GPC, PPC, Others), Margin of error, Sample size, Polling method, and Lead. Machine retrieval can use the MediaWiki Action API (action=parse with prop=sections to get section indices, then prop=text or prop=wikitext for the table section) or the REST API. Parsing HTML via Python's standard library html.parser is preferable to raw wikitext because numbers and data-sort-value dates are already evaluated, avoiding complex MediaWiki template parsing (e.g., {{dts}}, {{efn}}). The text is dual-licensed under Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0) and GFDL. Attribution requires linking to the source URL/revision, providing the license link, indicating modifications, and licensing derivative works under CC BY-SA 4.0.

Evidence:
- url <https://en.wikipedia.org/wiki/Opinion_polling_for_the_46th_Canadian_federal_election> (accessed 2026-10-12, primary source) — Main article containing National polls table and sparse Regional polls section (Quebec, Ontario, Manitoba, Alberta, BC).
- url <https://en.wikipedia.org/w/api.php?action=parse&page=Opinion_polling_for_the_46th_Canadian_federal_election&prop=sections&format=json> (accessed 2026-10-12, primary source) — MediaWiki API showing section hierarchy and index numbers for targeted section parsing.

### 2. [verified_fact] Machine-Readable Poll Sources, Data Feeds, and Terms of Use

Direct Canadian pollsters (Abacus Data, Léger, Mainstreet Research, Liaison Strategies) do not provide public CSV or JSON feeds, publishing exclusively via narrative blog posts, infographics, and PDF reports. Nanos Research publishes weekly tracking in free summary PDFs, but detailed regional cross-tabs and seat modeling are behind a $50/month paywalled subscriber portal. For aggregators: (1) 338Canada (338canada.com) embeds structured polling data directly in the HTML of https://338canada.com/polls.htm as a JavaScript object (window.demopoll_TABLE_DATA) containing full national and regional breakdowns ('National', 'ATL', 'QC', 'ON', 'PR', 'AB', 'BC') with 149 to 231 rows per region, including pollster, poll_link, date, sample size, rolling indicators, and party vote shares. 338Canada has no dedicated public API or terms page, but its data is proprietary and monetized via Substack/ads. (2) CBC Poll Tracker uses an internal Next.js client that pulls live JSON feeds from CBC's Canopy API: https://canopy.cbc.ca/live/poll-tracker/v2024/CAN (model statistics, blurbs, and settings) and https://canopy.cbc.ca/live/poll-tracker/v2024/CAN/pollsters (a 310-poll dataset with pollster, report_link, start_date, end_date, sample_size, margin_of_error, method, model weight, and party percentages). (3) CBC/Radio-Canada Digital Terms of Use (https://cbc.radio-canada.ca/en/vision/governance/terms-of-use-digital-services) strictly limit access to personal, non-commercial use and explicitly prohibit unauthorized reproduction, commercial exploitation, and automated scraping/harvesting without prior written consent (specifically banning automated extraction for AI model training).

Evidence:
- url <https://338canada.com/polls.htm> (accessed 2026-10-12, primary source) — Contains embedded window.demopoll_TABLE_DATA JSON object with National, ATL, QC, ON, PR, AB, and BC regional poll arrays.
- url <https://canopy.cbc.ca/live/poll-tracker/v2024/CAN/pollsters> (accessed 2026-10-12, primary source) — Live CBC Canopy API returning JSON array of 310 polls with start_date, end_date, sample_size, method, weight, and party data.
- url <https://cbc.radio-canada.ca/en/vision/governance/terms-of-use-digital-services> (accessed 2026-10-12, primary source) — CBC/Radio-Canada Terms of Use prohibiting commercial use and automated scraping.

### 3. [verified_fact] 2025 Riding Results Files, Boundary Map Stability, and By-Election Flips

Official voting results for the 45th General Election (April 28, 2025) are hosted by Elections Canada at https://www.elections.ca/res/rep/off/ovrGE45/home.html with raw data downloads indexed at https://www.elections.ca/content.aspx?section=res&dir=rep/off/45gedata&document=index&lang=e. Poll-by-poll results are provided in two CSV formats: Format 1 ('pollbypoll_bureauparbureau', wide table with candidates as columns) and Format 2 ('pollresults_resultatsbureau', tidy/long format with candidate metadata, party, incumbency Y/N, elected Y/N, and vote counts per row). Both formats are downloadable as Canada-wide ZIP archives (https://www.elections.ca/res/rep/off/ovrGE45/62/data_donnees/pollbypoll_bureauparbureauCanada.zip and pollresults_resultatsbureauCanada.zip) and per-riding CSV files. Summary tables (e.g. table_tableau02.csv for electors/polls and table_tableau04.csv for turnout) are under the same directory. The 2025 ridings are identical to the current federal map: the 2025 election enacted the 2023 Representation Order (343 ridings), and under the Electoral Boundaries Readjustment Act redistribution occurs decennially; no redistribution has occurred since April 2025. Between 28 April 2025 and 12 October 2026, 7 by-elections were held: Battle River—Crowfoot (CPC hold), University—Rosedale (LPC hold), Scarborough Southwest (LPC hold), Terrebonne (LPC hold after Supreme Court-mandated rerun), North Vancouver—Capilano (LPC hold), Beaches—East York (LPC hold), and Chicoutimi—Le Fjord (31 Aug 2026), where Liberal Daniel Gobeil won, flipping the seat previously held by Conservative Richard Martel. Exactly one seat changed party hands.

Evidence:
- url <https://www.elections.ca/res/rep/off/ovrGE45/home.html> (accessed 2026-10-12, primary source) — Elections Canada official 45th General Election results portal.
- url <https://www.elections.ca/content.aspx?section=res&dir=rep/off/45gedata&document=bypro&lang=e> (accessed 2026-10-12, primary source) — Elections Canada raw data download directory containing Canada-wide ZIPs and per-riding CSV links for Formats 1 and 2.
- url <https://en.wikipedia.org/wiki/By-elections_to_the_45th_Canadian_Parliament> (accessed 2026-10-12, secondary source) — Parliamentary by-election records verifying 7 held contests and Chicoutimi—Le Fjord as the sole seat gain.

### 4. [inference] Scarcity and Insufficiency of Riding-Level Polling for Seat Modeling

Riding-level opinion polls are not published frequently enough to form the basis of a Canadian federal seat projection model. Wikipedia's constituency tracking for the 46th election ('Opinion polling for the 46th Canadian federal election by constituency') documents only 8 ridings polled nationwide between April 2025 and October 2026 (under 2.5% of Canada's 343 seats), virtually all triggered by impending by-elections (e.g. North Vancouver—Capilano, Chicoutimi—Le Fjord, Beaches—East York) or leadership contests. Because polling individual ridings is cost-prohibitive ($2,000–$5,000+ per seat) and plagued by small sample sizes and wide error margins, over 97% of ridings receive zero public polling during inter-election periods. Consequently, seat projection models cannot rely on riding polls; both 338Canada and the CBC Poll Tracker rely instead on regional swing applied to past election baselines, using riding polls only as rare, opportunistic calibration points.

Evidence:
- url <https://en.wikipedia.org/wiki/Opinion_polling_for_the_46th_Canadian_federal_election_by_constituency> (accessed 2026-10-12, primary source) — Documents that only 8 of 343 ridings have published seat polls since the April 2025 election.
- url <https://338canada.com/about.htm> (accessed 2026-10-12, primary source) — Notes that local polling is rarely available, necessitating probabilistic demographic and regional swing modeling.

### 5. [verified_fact] Methodological Architecture of 338Canada and CBC Poll Tracker Models

Both leading Canadian models publicly document their architectures on their methodology pages: (1) 338Canada (https://338canada.com/about.htm): Aggregates polls using a weighted average based on sample size (larger = more weight), recency/field dates (exponential decay, accelerated during campaigns), and pollster ratings (editorial grades A+ to C/F based on past track record and transparency). It projects seats via a 'regionally adjusted proportional swing' across 6 regions (Atlantic, QC, ON, Prairies, AB, BC), modulated by Statistics Canada Census demographics (mother tongue/home language, age, income, population density, education, immigration, employment) and candidate effects (incumbent overperformance and star candidates). Projections are derived from thousands of Monte Carlo simulations to produce probabilistic seat distributions and win probabilities. (2) CBC Poll Tracker (https://newsinteractives.cbc.ca/elections/poll-tracker/canada/): Computes a weighted average of decided/leaning voters based on recency, sample size, and a 10-year pollster track record (weighted toward recent elections, normalized for election difficulty, and penalized for persistent outliers or omitting regional crosstabs). It applies proportional swing (Vote_new = Vote_base * Poll_new / Poll_base) regionally, adjusting for incumbency resistance, leader bonuses/vacancies, star candidates, and byelections. It incorporates riding polls by 50% of their divergence when available, and derives likely seat ranges from 68% and 95% confidence intervals based on historical polling errors.

Evidence:
- url <https://338canada.com/about.htm> (accessed 2026-10-12, primary source) — Official 338Canada methodology detailing polling aggregation weights, demographic proportional swing, and Monte Carlo simulations.
- url <https://newsinteractives.cbc.ca/elections/poll-tracker/canada/> (accessed 2026-10-12, primary source) — Official CBC Poll Tracker methodology detailing 10-year track record weights, regional proportional swing formulas, candidate adjustments, and 68%/95% confidence intervals.

## Coverage

Inspected:
- docs/design.md
- server/partake_server.py
- https://en.wikipedia.org/wiki/Opinion_polling_for_the_46th_Canadian_federal_election
- https://en.wikipedia.org/wiki/Opinion_polling_for_the_46th_Canadian_federal_election_by_constituency
- https://en.wikipedia.org/wiki/By-elections_to_the_45th_Canadian_Parliament
- https://338canada.com/polls.htm
- https://338canada.com/about.htm
- https://newsinteractives.cbc.ca/elections/poll-tracker/canada/
- https://canopy.cbc.ca/live/poll-tracker/v2024/CAN/pollsters
- https://cbc.radio-canada.ca/en/vision/governance/terms-of-use-digital-services
- https://www.elections.ca/res/rep/off/ovrGE45/home.html
- https://www.elections.ca/content.aspx?section=res&dir=rep/off/45gedata&document=index&lang=e
- https://www.elections.ca/content.aspx?section=res&dir=rep/off/45gedata&document=bypro&lang=e
- https://www.elections.ca/content.aspx?section=res&dir=rep/off/45gedata&document=byed&lang=e
- https://www.elections.ca/content.aspx?section=res&dir=rep/off/45gedata&document=pollbypoll&lang=e
- https://www.elections.ca/content.aspx?section=res&dir=rep/off/45gedata&document=pollresults&lang=e

Attempted failure modes:
- Attempted unauthenticated access to MediaWiki API without User-Agent header (returned HTTP 403 Forbidden; resolved by setting custom User-Agent).
- Attempted to extract regional rows from Wikipedia's national Table of polls (verified absent; Wikipedia separates regional polling into sparse provincial subsections missing Atlantic and Prairies/SK).
- Attempted to locate public CSV download endpoints on 338Canada and CBC (verified neither provides an official export button; identified embedded window.demopoll_TABLE_DATA on 338Canada and Canopy API on CBC).

Probes:
_No probes declared._

## Unknowns

- Whether commercial Canadian polling firms (e.g. Abacus, Léger, Mainstreet) offer private machine-readable APIs to paying institutional clients, as their public web presences only provide narrative articles and PDF reports.
- Exact scheduled polling dates for pending by-elections in Scarborough North, Saint-Hyacinthe—Bagot—Acton, Rosemont—La Petite-Patrie, Laurier—Sainte-Marie, Yorkton—Melville, and Brantford—Brant South (writs to be issued between December 2026 and March 2027).
