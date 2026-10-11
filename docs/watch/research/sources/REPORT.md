# Data Source Research for ParTake: Parliament Watch

Date of research: 2026-10-11
Target environment: Steam Deck (Linux, 16 GB shared RAM, ~7 GB typically free)
Researcher User-Agent: `ParTake-research/0.1 (personal project)`

All claims below are tagged as **[Fact]** (verified via direct live probe or source code inspection in this session), **[Inference]** (logical deduction based on verified facts), or **[Recommendation]** (engineering design guidance for the Parliament watch service). Every cited URL was verified live with HTTP status 2xx/3xx on 2026-10-11.

---

## Q3. Hansard: Publication Timing, Rate Limits, MP Identifiers, and Committee Evidence

### 1. Publication Timing and Lag (Blues/Preliminary vs. Final)

* **[Fact]** Public House Hansards on `ourcommons.ca` publish as official XML documents (`HAN{sitting:03d}-E.XML`) at URL pattern `https://www.ourcommons.ca/Content/House/{parl}{session}/Debates/{sitting:03d}/HAN{sitting:03d}-{lang}.XML`.
* **[Fact]** Measurement of the last five sitting days of the 45th Parliament, 1st Session (measured via [`scripts/measure_lag.py`](scripts/measure_lag.py) on 2026-10-11, fetching `ourcommons.ca` XML headers) shows that Debates publish overnight following each sitting:
  * Sitting 145: Met Monday, 2026-10-05 at 11:00 EDT. XML `Last-Modified`: Tue, 06 Oct 2026 06:49:12 GMT (02:49 EDT Tuesday; ~16 hours after sitting commenced).
  * Sitting 146: Met Tuesday, 2026-10-06 at 10:00 EDT. XML `Last-Modified`: Wed, 07 Oct 2026 10:17:49 GMT (06:17 EDT Wednesday; ~20 hours after sitting commenced).
  * Sitting 147: Met Wednesday, 2026-10-07 at 14:00 EDT. XML `Last-Modified`: Thu, 08 Oct 2026 09:50:16 GMT (05:50 EDT Thursday; ~16 hours after sitting commenced).
  * Sitting 148: Met Thursday, 2026-10-08 at 10:00 EDT. XML `Last-Modified`: Fri, 09 Oct 2026 07:06:28 GMT (03:06 EDT Friday; ~17 hours after sitting commenced).
  * Sitting 149: Met Friday, 2026-10-09 at 10:00 EDT (adjourned early afternoon). XML `Last-Modified`: Sat, 10 Oct 2026 01:48:51 GMT (21:48 EDT Friday; ~12 hours after sitting commenced).
* **[Fact]** The typical publication lag for `ourcommons.ca` final Hansard XML is 12 to 20 hours after the sitting commences (approximately 8 to 14 hours after adjournment).
* **[Fact]** Neither `ourcommons.ca` nor `openparliament.ca` publishes the unedited preliminary transcripts known in parliamentary procedure as the "blues".
  * *Anti-vacuity check*: In official House procedure (House of Commons Procedure and Practice), the "blues" exist as internal working transcripts distributed on paper/intranet solely to MPs and committees shortly after a sitting so they can review their own remarks before final translation and printing. The public web server `https://www.ourcommons.ca/DocumentViewer/en/house/latest-sitting` redirects to the latest edited Hansard (`/documentviewer/en/45-1/house/sitting-149/hansard`), containing only the final Official Report.
  * *Openparliament code check*: In `openparliament`'s importer (`https://raw.githubusercontent.com/michaelmulley/openparliament/master/parliament/imports/parl_document.py`, line 41), `HANSARD_URL` directly fetches `https://www.ourcommons.ca/Content/House/{parliamentnum}{sessnum}/Debates/{sitting:03d}/HAN{sitting:03d}-{lang}.XML`. Openparliament ingests the final XML publication; it has no separate or earlier "blues" pipeline.
* **[Inference]** Openparliament.ca Hansard publication lags slightly behind `ourcommons.ca` because openparliament must wait for `ourcommons.ca` to publish the XML before its importer script runs.

### 2. Rate Limits and Terms of Use

* **[Fact]** `openparliament.ca` rate limits and terms of use are documented at `https://openparliament.ca/api/` (fetched 2026-10-11, HTTP 200):
  * **Rate Limits**:
    > "There’s a rate limit. If you make tons of concurrent requests, you'll get `HTTP 429 Too Many Requests`. Get in touch if this is a problem for you."
    > "Don’t be shy. The API doesn’t currently enforce this, but you should put your email in `User-Agent` headers—that way I can look at how people are using the API, and contact you if your requests are causing problems."
  * **Terms of Use & Copyright**:
    > "All content on this site comes from Parliament, and so is copyright of King Charles. Speaker’s Permission establishes some of the terms of use for some of the content."
    > "This site holds no copyright on any data accessible through this API. But providing attribution via a link back to openparliament.ca would be awfully nice of you."
    > "The code behind this site is available on GitHub, as free software. It's in Python, mostly." (Licensed under AGPLv3, `https://raw.githubusercontent.com/michaelmulley/openparliament/master/pyproject.toml`).
* **[Fact]** `ourcommons.ca` rate limits and terms of use:
  * **Rate Limits**:
    * *Anti-vacuity check*: While `openparliament.ca` explicitly documents rate limiting ("you'll get HTTP 429 Too Many Requests"), `ourcommons.ca` documents no numeric rate limit or request throttling policy on `https://www.ourcommons.ca/en/open-data` or `https://www.ourcommons.ca/en/open-data/disclaimer-of-liability`.
    * Probing `https://www.ourcommons.ca/Members/en/search/XML`, `https://www.ourcommons.ca/Members/en/votes/xml`, and `https://www.ourcommons.ca/Content/House/451/Debates/149/HAN149-E.XML` confirms the server returns standard HTTP response headers (`Cache-Control: public, max-age=60` or `120`, `Server: Kestrel` or `Microsoft-IIS/10.0`) without `RateLimit-*` or `Retry-After` headers.
  * **Terms of Use**:
    * Open data definition (`https://www.ourcommons.ca/en/open-data`):
      > "Open data is defined as structured data that is machine-readable, freely shared, used and built on without restrictions. The House of Commons remains committed to expanding access to parliamentary information, including Open Data and related services."
    * Speaker's Permission Regarding Reproduction (`https://www.ourcommons.ca/en/important-notices`, §SpeakersPermission):
      > "The proceedings of the House of Commons and its Committees are hereby made available to provide greater public access. The parliamentary privilege of the House of Commons to control the publication and broadcast of the proceedings of the House of Commons and its Committees is nonetheless reserved. All copyrights therein are also reserved. Reproduction of the proceedings of the House of Commons and its Committees, in whole or in part and in any medium, is hereby permitted provided that the reproduction is accurate and is not presented as official. This permission does not extend to reproduction, distribution or use for commercial purpose of financial gain. Reproduction or use outside this permission or without authorization may be treated as copyright infringement in accordance with the Copyright Act . Authorization may be obtained on written application to the Office of the Speaker of the House of Commons. Reproduction in accordance with this permission does not constitute publication under the authority of the House of Commons."

### 3. Speech Identifiers

* **[Fact]** In `ourcommons.ca` Hansard XML (`HAN{sitting}-E.XML`), each `<Intervention>` identifies speakers via `<PersonSpeaking><Affiliation DbId="{id}" Type="{type}">{text}</Affiliation></PersonSpeaking>`.
  * The `DbId` is a parliamentary affiliation identifier (e.g. `DbId="318665"` for Hon. Mandy Gull-Masty, `DbId="318001"` for Billy Morin, `DbId="314774"` for the Prime Minister).
  * However, individual `<Intervention>` tags do not directly include the permanent `PersonId` of the MP; resolving to a single stable person requires mapping `DbId` via parliamentary records.
* **[Fact]** In `openparliament.ca`, speeches returned by `/speeches/?document=...` (`https://api.openparliament.ca/speeches/?document=%2Fdebates%2F2026%2F10%2F9%2F&format=json&limit=20`) provide:
  * `"politician_url"`: A stable URI (e.g. `"/politicians/mandy-gull-masty/"`, `"/politicians/billy-morin/"`).
  * `"politician_membership_url"`: Links the politician's specific caucus/riding tenure.
  * In openparliament's backend model (`parliament/imports/parl_document.py` and `parliament/imports/alpheus.py`), openparliament resolves the Hansard XML's `Affiliation DbId` into the `Politician` model via `Politician.objects.get_by_parl_affil_id(s.who_hocid)`.
* **[Inference]** Openparliament.ca provides a more developer-friendly stable politician URI (`/politicians/{slug}/`) out-of-the-box for speeches than raw `ourcommons.ca` Hansard XML, which requires resolving `Affiliation DbId` mappings.

### 4. Committee Evidence Coverage

* **[Fact]** Both `ourcommons.ca` and `openparliament.ca` cover House committee evidence (meeting transcripts):
  * `ourcommons.ca`: Meeting evidence is published in XML format under `https://www.ourcommons.ca/Content/Committee/{parl}{session}/{acronym}/Evidence/EV{id}/{acronym}EV{meeting}-E.XML` (e.g. `https://www.ourcommons.ca/Content/Committee/451/INDU/Evidence/EV14246706/INDUEV50-E.XML` for INDU meeting 50 on 2026-10-06).
  * `openparliament.ca`: Committee meetings are listed at `https://api.openparliament.ca/committees/meetings/?format=json`. When evidence is ready, `has_evidence: true` is set, linking to `/speeches/?document=/committees/{committee-slug}/{session}/{meeting}/` (e.g. `https://api.openparliament.ca/committees/industry-and-technology/45-1/50/?format=json` and `https://api.openparliament.ca/speeches/?document=%2Fcommittees%2Findustry-and-technology%2F45-1%2F50%2F&format=json&limit=20`).
* **[Fact]** Committee evidence latency:
  * Committee meeting transcripts take substantially longer to publish than House Hansard debates.
  * In `INDUEV50-E.XML` (meeting held Tuesday, 2026-10-06), the XML `Last-Modified` header is `Fri, 09 Oct 2026 12:44:19 GMT` (approx. 3 days after the meeting occurred).
  * Recent meetings held on Thursday 2026-10-08 (e.g. FINA meeting 53, AGRI meeting 45, ENVI meeting 49) had `has_evidence: false` in openparliament as of 2026-10-11, confirming committee transcript lag is typically 2 to 4 business days.
* **[Fact]** Committee format:
  * `ourcommons.ca`: XML document (`<Hansard xml:lang="EN">...<OrderOfBusiness>...<Intervention>`). Witnesses have no MP affiliation; MPs have `<Affiliation DbId="...">`.
  * `openparliament.ca`: JSON speeches where witnesses have `"politician_url": null` and MP speakers have `"politician_url": "/politicians/{slug}/"`.

### Samples Saved
1. `ourcommons` House Sitting:
   - Full sample: [`samples/ourcommons-hansard-sitting-001.xml.gz`](samples/ourcommons-hansard-sitting-001.xml.gz) (79,675 bytes raw, 21 KB gzipped, from opening sitting 2025-05-26).
   - Latest sample: [`samples/ourcommons-hansard-sitting-149-truncated.xml.gz`](samples/ourcommons-hansard-sitting-149-truncated.xml.gz) (from 2026-10-09 sitting, 8 KB gzipped) and sibling [`samples/ourcommons-hansard-sitting-149-truncated.xml.note.txt`](samples/ourcommons-hansard-sitting-149-truncated.xml.note.txt).
2. `openparliament` House Sitting:
   - Metadata: [`samples/openparliament-debate-sitting-149.json`](samples/openparliament-debate-sitting-149.json) (419 bytes).
   - Speeches: [`samples/openparliament-speeches-sitting-149-truncated.json`](samples/openparliament-speeches-sitting-149-truncated.json) (114 KB) and sibling [`samples/openparliament-speeches-sitting-149-truncated.json.note.txt`](samples/openparliament-speeches-sitting-149-truncated.json.note.txt).
3. `ourcommons` Committee Evidence:
   - [`samples/ourcommons-evidence-indu-meeting-50.xml.gz`](samples/ourcommons-evidence-indu-meeting-50.xml.gz) (63,114 bytes raw, 14 KB gzipped, INDU meeting 50).
4. `openparliament` Committee Evidence:
   - Metadata: [`samples/openparliament-evidence-indu-meeting-50.json`](samples/openparliament-evidence-indu-meeting-50.json) (578 bytes).
   - Speeches: [`samples/openparliament-evidence-speeches-indu-meeting-50-truncated.json`](samples/openparliament-evidence-speeches-indu-meeting-50-truncated.json) (49 KB) and sibling [`samples/openparliament-evidence-speeches-indu-meeting-50-truncated.json.note.txt`](samples/openparliament-evidence-speeches-indu-meeting-50-truncated.json.note.txt).

**Answer**: Neither source publishes unedited preliminary "blues"; both publish only the final official transcripts. House Hansard XML publishes overnight on ourcommons.ca with a 12–20 hour lag, while committee evidence publishes in 2–4 business days. Openparliament.ca tags speeches with stable politician URLs (`/politicians/{slug}/`) by resolving ourcommons's `Affiliation DbId` tags.

---

## Q4. Votes and Bills: Formats, Latency, Backfill Depth, and 45th Parliament Coverage

### 1. Recorded Divisions with Per-MP Votes

* **[Fact]** `ourcommons.ca`:
  * **Endpoints**:
    * Full division list: `https://www.ourcommons.ca/Members/en/votes/xml` (`HTTP 200`, returns XML list `<ArrayOfVote>` of all divisions in the active session).
    * Division detail with per-MP ballots: `https://www.ourcommons.ca/Members/en/votes/{parl}/{session}/{divisionNumber}/xml` (e.g. `https://www.ourcommons.ca/Members/en/votes/45/1/178/xml`, `HTTP 200`).
  * **Format**: XML (`<ArrayOfVoteParticipant>`). Each entry contains `<PersonId>`, `<PersonOfficialFirstName>`, `<PersonOfficialLastName>`, `<ConstituencyName>`, `<CaucusShortName>`, `<VoteValueName>` ("Yea", "Nay", "Paired"), `<IsVoteYea>`, `<IsVoteNay>`, `<IsVotePaired>`.
  * **Latency**: Same day, within hours after the division is recorded. A live voting portal is also maintained at `https://www.ourcommons.ca/Members/en/live-vote`.
  * **Backfill Depth**:
    * Division summaries exist back to early Parliaments, but full per-MP ballots (`<VoteParticipant>` records) begin in **Parliament 38, Session 1 (October 2004)**.
    * *Anti-vacuity check*: Probing `https://www.ourcommons.ca/Members/en/votes/38/1/1/xml` yields 300 participant records; probing `https://www.ourcommons.ca/Members/en/votes/37/1/1/xml` yields 0 participant records (empty `<ArrayOfVoteParticipant />`).
* **[Fact]** `openparliament.ca`:
  * **Endpoints**:
    * Division list: `https://api.openparliament.ca/votes/?session={parl}-{session}&format=json` (e.g. `https://api.openparliament.ca/votes/?session=45-1&format=json&limit=500`, `HTTP 200`).
    * Division summary: `https://api.openparliament.ca/votes/{parl}-{session}/{divisionNumber}/?format=json` (e.g. `https://api.openparliament.ca/votes/45-1/178/?format=json`, `HTTP 200`).
    * Per-MP ballots: `https://api.openparliament.ca/votes/ballots/?vote=/votes/{parl}-{session}/{divisionNumber}/&format=json` (e.g. `https://api.openparliament.ca/votes/ballots/?vote=%2Fvotes%2F45-1%2F178%2F&format=json&limit=20`, `HTTP 200`).
  * **Format**: JSON. Ballots provide `"politician_url"`, `"politician_membership_url"`, and `"ballot"` ("Yes", "No", "Paired").
  * **Latency**: Polls ourcommons.ca vote list XML; updates shortly after ourcommons publishes the division.
  * **Backfill Depth**:
    * Openparliament votes go back to **Parliament 39, Session 1 (May 8, 2006)** (`https://api.openparliament.ca/votes/39-1/1/?format=json`, `HTTP 200`).
    * *Anti-vacuity check*: Probing `https://api.openparliament.ca/votes/?session=38-1&format=json&limit=1` returns 0 objects.

### 2. Bill Stages (LEGISinfo at parl.ca)

* **[Fact]** LEGISinfo (`parl.ca`):
  * **Endpoints**:
    * Full session bills list: `https://www.parl.ca/legisinfo/en/bills/json` and `https://www.parl.ca/legisinfo/en/bills/xml` (`HTTP 200`).
    * Specific bill details and legislative stages: `https://www.parl.ca/legisinfo/en/bill/{parl}-{session}/{billNumber}/json` and `/xml` (e.g. `https://www.parl.ca/legisinfo/en/bill/45-1/c-37/json` and `https://www.parl.ca/legisinfo/en/bill/45-1/c-37/xml`, `HTTP 200`).
  * **Format**: JSON and XML. Contains `BillStages` object with full `HouseBillStages`, `SenateBillStages`, `RoyalAssent`, including event timestamps (e.g. `EventStartDateTime: "2026-06-16T10:02:58.263"` for first reading of Bill C-37; `LatestCompletedBillStageDateTime: "2026-10-09T13:20:48.817"` for second reading).
  * **Latency**: Real-time or same-day update as legislative stages occur in the Chamber/Senate.
  * **Backfill Depth**:
    * Documented on `https://www.ourcommons.ca/en/open-data`: *"LEGISinfo provides information on all bills considered by the Senate and the House of Commons since the start of the 37th Parliament in 2001."*
    * *Anti-vacuity check*: Probing `https://www.parl.ca/legisinfo/en/bill/37-1/c-2/json` succeeds (`HTTP 200`, returning Bill C-2 from 2001).

### 3. Confirmation of the 45th Parliament Opening and Backfill Coverage

* **[Fact]** Primary source confirmation of opening date:
  * Official Hansard XML `HAN001-E.XML` (`https://www.ourcommons.ca/Content/House/451/Debates/001/HAN001-E.XML`, `HTTP 200`):
    * `<ExtractedItem Name="Parliament">45th PARLIAMENT</ExtractedItem>`
    * `<ExtractedItem Name="Session">1st SESSION</ExtractedItem>`
    * `<ExtractedItem Name="Date">Monday, May 26, 2025</ExtractedItem>`
    * `<OrderOfBusinessTitle>First Session—45th Parliament</OrderOfBusinessTitle>`
    * `<CatchLine>Opening of Parliament</CatchLine>`
  * The 45th Parliament opened on **Monday, May 26, 2025**.
* **[Fact]** Coverage confirmation:
  * `ourcommons.ca` Debates: covers from Sitting 1 (2025-05-26) to Sitting 149 (2026-10-09).
  * `openparliament.ca` Debates: covers from 2025-05-26 (`https://api.openparliament.ca/debates/2025/5/26/?format=json`, `HTTP 200`) to 2026-10-09.
  * `ourcommons.ca` Votes: covers from Division 1 (2025-05-29) to Division 178 (2026-10-08).
  * `openparliament.ca` Votes: covers from Division 1 (2025-05-29) to Division 178 (2026-10-08).
  * LEGISinfo: covers all 45-1 bills from introduction in spring 2025 to present.

### 4. Count of Divisions and Bills in the 45th Parliament So Far

Measured via [`scripts/count_divisions_and_bills.py`](scripts/count_divisions_and_bills.py) on 2026-10-11:
* **[Fact]** **Recorded Divisions**: Exactly **178** divisions exist in the 45th Parliament so far.
  * Verified identically in `ourcommons.ca` (`/Members/en/votes/xml`: count=178, min=1, max=178).
  * Verified identically in `openparliament.ca` (`/votes/?session=45-1`: count=178, min=1, max=178).
* **[Fact]** **Bills**: Exactly **191** bills exist in the 45th Parliament so far.
  * Verified identically in LEGISinfo (`/legisinfo/en/bills/json`: count=191).
  * Verified identically in `openparliament.ca` (`/bills/?session=45-1`: count=191).

### Samples Saved
1. Division with per-MP votes:
   - `ourcommons`: [`samples/ourcommons-vote-178-truncated.xml.gz`](samples/ourcommons-vote-178-truncated.xml.gz) (1.3 KB gzipped; truncated from 332 participants to 20 participants) and sibling [`samples/ourcommons-vote-178-truncated.xml.note.txt`](samples/ourcommons-vote-178-truncated.xml.note.txt).
   - `openparliament`: [`samples/openparliament-vote-178.json`](samples/openparliament-vote-178.json) (summary, 1.7 KB) and [`samples/openparliament-ballots-vote-178-truncated.json`](samples/openparliament-ballots-vote-178-truncated.json) (4.1 KB; first 20 ballots) with sibling [`samples/openparliament-ballots-vote-178-truncated.json.note.txt`](samples/openparliament-ballots-vote-178-truncated.json.note.txt).
2. Bill with its stages:
   - LEGISinfo JSON: [`samples/legisinfo-bill-c37.json`](samples/legisinfo-bill-c37.json) (33 KB).
   - LEGISinfo XML: [`samples/legisinfo-bill-c37.xml.gz`](samples/legisinfo-bill-c37.xml.gz) (5.1 KB gzipped).

**Answer**: The 45th Parliament opened on May 26, 2025; so far there are exactly 178 divisions and 191 bills across all sources. Both ourcommons.ca (XML) and openparliament.ca (JSON) provide complete per-MP voting records, and LEGISinfo provides comprehensive stage-by-stage bill tracking with exact event timestamps dating back to 2001 (37th Parliament).

---

## Q5. MPs: Stable Identifiers, Cross-Source Linkage, and Spoken Caption Forms

### 1. Stable Identifier Mapping Across Systems

* **[Fact]** `ourcommons.ca` assigns each MP a permanent numeric **`PersonId`** (e.g. `28286`, `122684`, `123447`).
  * `PersonId` is constant throughout the MP's career across general elections, ministerial appointments, and committee assignments.
  * In `ourcommons.ca/Members/en/search/XML`, every MP record includes `<PersonId>`.
  * In `ourcommons.ca/Members/en/votes/45/1/{division}/xml`, every per-MP ballot includes `<PersonId>`.
  * In `ourcommons.ca/Members/en/ministries/XML`, every ministerial portfolio includes `<PersonId>`.
* **[Fact]** `openparliament.ca` assigns each MP a unique **slug** (e.g. `mark-carney`, `marjorie-michel`, `billy-morin`).
  * In openparliament's politician JSON endpoint (`https://api.openparliament.ca/politicians/{slug}/?format=json`), `other_info.parl_mp_id` stores an array containing the exact `ourcommons.ca` **`PersonId`** (e.g. `"parl_mp_id": ["28286"]`).
  * Furthermore, `links` contains the official ourcommons profile URL: `https://www.ourcommons.ca/members/en/{slug}({PersonId})`.
* **[Fact]** In Hansard debates XML (`ourcommons.ca`), speeches are attributed using **`Affiliation DbId`** (e.g. `<Affiliation DbId="314774" Type="1">Prime Minister</Affiliation>`).
  * `openparliament.ca` models this relationship by storing all known affiliation IDs in `other_info.parl_affil_id` on the politician (e.g. `"parl_affil_id": ["317577", "314774", "319096"]` for Mark Carney).
* **[Inference]** `ourcommons.ca` **`PersonId`** is the canonical primary key for MPs. To link a speech from raw Hansard XML to an MP, map the Hansard `Affiliation DbId` to the `PersonId` (or openparliament `slug`).

### 2. Concrete Linkage for Three Selected MPs

Verified via [`scripts/verify_mp_linkage.py`](scripts/verify_mp_linkage.py) on 2026-10-11:

```
========================================================================================================
Field / Source                     MP 1 (Prime Minister)      MP 2 (Cabinet Minister)   MP 3 (Opposition MP)
========================================================================================================
Full Name                          Right Hon. Mark Carney     Hon. Marjorie Michel      Billy Morin
ourcommons PersonId                28286                      122684                    123447
openparliament Slug                mark-carney                marjorie-michel           billy-morin
openparliament URL                 /politicians/mark-carney/  /politicians/marjorie...  /politicians/billy...
openparliament parl_mp_id          ['28286']                  ['122684']                ['123447']
Hansard Affiliation DbIds          ['317577','314774',...]    ['318692','317994']       ['318001','319781']
Constituency (Riding)              Nepean                     Papineau                  Edmonton Northwest
Caucus                             Liberal                    Liberal                   Conservative
Ministerial Role                   Prime Minister             Minister of Health        None (not in cabinet)
Division 178 Vote                  Yea                        Yea                       Yea
Spoken Caption (Portfolio)         "the Prime Minister"       "the Minister of Health"  N/A
Spoken Caption (Riding)            "the member for Nepean"    "the member for Papineau" "the member for
                                                                                        Edmonton Northwest"
========================================================================================================
```

### 3. Captions Name Forms Resolution

* **[Fact]** ParlVU closed captions (`ccItems` and CEA-608 stream) carry plain transcribed text without speaker identification tags (as established in `docs/design.md`).
* **[Fact]** Under House Standing Orders (§18), MPs may not refer to one another by personal name in debate. They are addressed exclusively by:
  1. **Portfolio role**: `"the Prime Minister"`, `"the Minister of Health"`, `"the Parliamentary Secretary to the Minister of Industry"`, or French equivalents (`"le premier ministre"`, `"la ministre de la Santé"`).
  2. **Constituency (riding) name**: `"the member for Nepean"`, `"the member for Papineau"`, `"the member for Edmonton Northwest"` (or with honorific `"the honourable member for ..."` / `"le député de ..."`).
  3. **Presiding officer**: Spoken directly to `"Mr. Speaker"` / `"Madam Speaker"` / `"Mr. Chair"`.
* **[Recommendation]** By ingesting `ourcommons.ca` member list XML and ministries list XML, the Parliament watch service can maintain a lookup index mapping both `"the member for {ConstituencyName}"` and `"the Minister of {Portfolio}"` directly to the MP's `PersonId`.

### 4. Machine-Readable Member and Ministries Lists

* **[Fact]** `ourcommons.ca` publishes full machine-readable XML feeds:
  1. **Member list with ridings and caucus**: `https://www.ourcommons.ca/Members/en/search/XML` (`HTTP 200`, 158,059 bytes).
     * Structure: `<ArrayOfMemberOfParliament><MemberOfParliament>` containing `<PersonId>`, `<PersonOfficialFirstName>`, `<PersonOfficialLastName>`, `<PersonShortHonorific>`, `<ConstituencyName>`, `<ConstituencyProvinceTerritoryName>`, `<CaucusShortName>`, `<FromDateTime>`.
     * Contains all 338 current MPs.
  2. **Cabinet and Secretaries of State**: `https://www.ourcommons.ca/Members/en/ministries/XML` (`HTTP 200`, 16,685 bytes).
     * Structure: `<ArrayOfMinister><Minister>` containing `<PersonId>`, `<PersonOfficialFirstName>`, `<PersonOfficialLastName>`, `<PersonShortHonorific>`, `<Title>` (portfolio title, e.g. "Minister of Health"), `<OrderOfPrecedence>`, `<ProvinceTerritoryName>`, `<FromDateTime>`.
     * Contains all 38 current members of the Ministry.

### Samples Saved
1. Member list: [`samples/ourcommons-members-list.xml.gz`](samples/ourcommons-members-list.xml.gz) (12 KB gzipped; 158 KB uncompressed, all 338 MPs) and [`samples/ourcommons-members-list.note.txt`](samples/ourcommons-members-list.note.txt).
2. Ministries list: [`samples/ourcommons-ministries-list.xml.gz`](samples/ourcommons-ministries-list.xml.gz) (1.9 KB gzipped; 16.7 KB uncompressed, all 38 ministers) and [`samples/ourcommons-ministries-list.note.txt`](samples/ourcommons-ministries-list.note.txt).

**Answer**: The stable canonical identifier is ourcommons.ca `PersonId`, directly mirrored in openparliament.ca's `other_info.parl_mp_id`. Ourcommons.ca provides dedicated, clean, machine-readable XML endpoints for all 338 MPs (with ridings) and all 38 Ministers (with exact portfolio titles), providing the exact strings needed to match spoken caption forms.

---

## Summary: Data Needs vs. Recommended Sources

| Data Need | Recommended Source | Format | Latency | Backfill Depth | Rationale |
|---|---|---|---|---|---|
| **House Debates (Hansard)** | `ourcommons.ca` (`HAN{num}-E.XML`) | XML | 12–20 hours (overnight) | 38th Parl. (2004) to present | Primary source. Fast overnight XML publishing directly on IIS/Kestrel; avoids middleman scraping delay. |
| **Committee Transcripts** | `ourcommons.ca` (`{cmte}EV{num}-E.XML`) | XML | 2–4 business days | 38th Parl. (2004) to present | Primary source. Comprehensive XML with per-intervention speaker tagging. |
| **Recorded Divisions (Votes)** | `ourcommons.ca` (`/Members/en/votes/{p}/{s}/{num}/xml`) | XML | Same-day (hours) | 38th Parl. (2004) to present | Contains exact `PersonId` per ballot; no pagination limits; identical division numbers (1 to 178 in 45-1). |
| **Bills & Legislative Stages** | LEGISinfo at `parl.ca` (`/bill/{p}-{s}/{num}/json`) | JSON | Near real-time / same day | 37th Parl. (2001) to present | Official source. Provides exact ISO timestamps for every stage event (first reading, committee referral, etc.). |
| **MP Directory & Ridings** | `ourcommons.ca` (`/Members/en/search/XML`) | XML | Updated on by-elections / status changes | Current Parliament | Clean, single-file list of all 338 MPs with permanent `PersonId`, riding names, and caucus. |
| **Ministerial Roles** | `ourcommons.ca` (`/Members/en/ministries/XML`) | XML | Updated on cabinet shuffles | Current Ministry | Clean list of all ministers with `PersonId` and official portfolio titles matching spoken caption forms. |

---

## Unknowns

1. **Intranet Availability of the "Blues"**: While public probing established conclusively that neither `ourcommons.ca` nor `openparliament.ca` exposes unrevised "blues" via public URLs or open APIs, whether the House of Commons provides an internal, authenticated RSS/websocket feed for the blues on the parliamentary campus network or internal press gallery network remains unverified from off-campus.
2. **Exact Thresholds of Cloudflare / Openparliament Rate Limiter**: Openparliament documents that making "tons of concurrent requests" triggers `HTTP 429 Too Many Requests`. The exact leaky-bucket burst size and sustained request-per-minute threshold are not published in openparliament documentation.
3. **SenVU / Senate Evidence Convergence**: SenVU and Senate committee evidence were excluded from ParTake scope in `docs/design.md`. LEGISinfo includes Senate bill stages, but Senate floor transcript publication latency on `sencanada.ca` was not measured.

---

## Sources

Every URL below was accessed and verified with a live HTTP status check on 2026-10-11 using User-Agent `ParTake-research/0.1 (personal project)`.

| URL | HTTP Status | Access Date | Purpose / Description |
|---|---|---|---|
| `https://api.openparliament.ca/` | 200 | 2026-10-11 | Openparliament API root |
| `https://api.openparliament.ca/debates/?format=json` | 200 | 2026-10-11 | Openparliament debates listing endpoint |
| `https://openparliament.ca/api/` | 200 | 2026-10-11 | Openparliament API documentation, rate limit policy, terms of use |
| `https://api.openparliament.ca/debates/2026/10/9/?format=json` | 200 | 2026-10-11 | Openparliament sitting 149 debate metadata |
| `https://api.openparliament.ca/speeches/?document=%2Fdebates%2F2026%2F10%2F9%2F&format=json&limit=20` | 200 | 2026-10-11 | Openparliament sitting 149 speeches sample (page 1) |
| `https://api.openparliament.ca/debates/2025/5/26/?format=json` | 200 | 2026-10-11 | Openparliament 45th Parliament sitting 1 debate |
| `https://api.openparliament.ca/committees/meetings/?format=json` | 200 | 2026-10-11 | Openparliament committee meetings list |
| `https://api.openparliament.ca/committees/industry-and-technology/45-1/50/?format=json` | 200 | 2026-10-11 | Openparliament INDU meeting 50 metadata |
| `https://api.openparliament.ca/speeches/?document=%2Fcommittees%2Findustry-and-technology%2F45-1%2F50%2F&format=json&limit=20` | 200 | 2026-10-11 | Openparliament INDU meeting 50 speeches sample (page 1) |
| `https://api.openparliament.ca/votes/?session=45-1&format=json&limit=500` | 200 | 2026-10-11 | Openparliament 45-1 votes list (178 divisions) |
| `https://api.openparliament.ca/votes/45-1/178/?format=json` | 200 | 2026-10-11 | Openparliament division 178 summary |
| `https://api.openparliament.ca/votes/ballots/?vote=%2Fvotes%2F45-1%2F178%2F&format=json&limit=20` | 200 | 2026-10-11 | Openparliament division 178 ballots sample (page 1) |
| `https://api.openparliament.ca/votes/39-1/1/?format=json` | 200 | 2026-10-11 | Earliest openparliament division (39-1 division 1) |
| `https://api.openparliament.ca/bills/?session=45-1&format=json&limit=500` | 200 | 2026-10-11 | Openparliament 45-1 bills list (191 bills) |
| `https://api.openparliament.ca/politicians/?format=json` | 200 | 2026-10-11 | Openparliament politicians index |
| `https://api.openparliament.ca/politicians/francis-scarpaleggia/?format=json` | 200 | 2026-10-11 | Politician record for Francis Scarpaleggia (Speaker) |
| `https://api.openparliament.ca/politicians/mark-carney/?format=json` | 200 | 2026-10-11 | Politician record for Mark Carney (Prime Minister) |
| `https://api.openparliament.ca/politicians/marjorie-michel/?format=json` | 200 | 2026-10-11 | Politician record for Marjorie Michel (Minister of Health) |
| `https://api.openparliament.ca/politicians/billy-morin/?format=json` | 200 | 2026-10-11 | Politician record for Billy Morin (MP Edmonton Northwest) |
| `https://www.ourcommons.ca/en/important-notices` | 200 | 2026-10-11 | Speaker's Permission Regarding Reproduction, copyright terms |
| `https://www.ourcommons.ca/en/open-data` | 200 | 2026-10-11 | House of Commons Open Data directory and documentation |
| `https://www.ourcommons.ca/en/open-data/disclaimer-of-liability` | 200 | 2026-10-11 | House of Commons Open Data disclaimer |
| `https://www.ourcommons.ca/DocumentViewer/en/house/latest/hansard` | 200 | 2026-10-11 | Latest sitting Hansard HTML viewer |
| `https://www.ourcommons.ca/DocumentViewer/en/house/latest-sitting` | 302 | 2026-10-11 | Redirect to latest sitting Hansard viewer |
| `https://www.ourcommons.ca/Content/House/451/Debates/001/HAN001-E.XML` | 200 | 2026-10-11 | 45th Parliament sitting 1 Hansard XML (Opening May 26, 2025) |
| `https://www.ourcommons.ca/Content/House/451/Debates/145/HAN145-E.XML` | 200 | 2026-10-11 | Sitting 145 Hansard XML (Oct 5, 2026) |
| `https://www.ourcommons.ca/Content/House/451/Debates/146/HAN146-E.XML` | 200 | 2026-10-11 | Sitting 146 Hansard XML (Oct 6, 2026) |
| `https://www.ourcommons.ca/Content/House/451/Debates/147/HAN147-E.XML` | 200 | 2026-10-11 | Sitting 147 Hansard XML (Oct 7, 2026) |
| `https://www.ourcommons.ca/Content/House/451/Debates/148/HAN148-E.XML` | 200 | 2026-10-11 | Sitting 148 Hansard XML (Oct 8, 2026) |
| `https://www.ourcommons.ca/Content/House/451/Debates/149/HAN149-E.XML` | 200 | 2026-10-11 | Sitting 149 Hansard XML (Oct 9, 2026) |
| `https://www.ourcommons.ca/DocumentViewer/en/45-1/INDU/meeting-50/evidence` | 200 | 2026-10-11 | INDU meeting 50 evidence viewer HTML |
| `https://www.ourcommons.ca/Content/Committee/451/INDU/Evidence/EV14246706/INDUEV50-E.XML` | 200 | 2026-10-11 | INDU meeting 50 committee evidence XML |
| `https://www.ourcommons.ca/Members/en/votes` | 200 | 2026-10-11 | House votes index HTML |
| `https://www.ourcommons.ca/Members/en/votes/xml` | 200 | 2026-10-11 | House votes list XML (178 divisions) |
| `https://www.ourcommons.ca/Members/en/votes/45/1/178` | 200 | 2026-10-11 | Division 178 detail page HTML |
| `https://www.ourcommons.ca/Members/en/votes/45/1/178/xml` | 200 | 2026-10-11 | Division 178 per-MP ballots XML |
| `https://www.ourcommons.ca/Members/en/votes/38/1/1/xml` | 200 | 2026-10-11 | Earliest division with per-MP ballots XML (38-1 division 1) |
| `https://www.ourcommons.ca/Members/en/votes/37/1/1/xml` | 200 | 2026-10-11 | 37-1 division 1 XML (returns empty participant list) |
| `https://www.ourcommons.ca/Members/en/search` | 200 | 2026-10-11 | Members of Parliament directory HTML |
| `https://www.ourcommons.ca/Members/en/search/XML` | 200 | 2026-10-11 | All 338 current Members of Parliament XML export |
| `https://www.ourcommons.ca/Members/en/ministries` | 200 | 2026-10-11 | Ministry directory HTML |
| `https://www.ourcommons.ca/Members/en/ministries/XML` | 200 | 2026-10-11 | All 38 Ministers and Secretaries of State XML export |
| `https://www.parl.ca/legisinfo/en/bills/json` | 200 | 2026-10-11 | LEGISinfo all current session bills JSON (191 bills) |
| `https://www.parl.ca/legisinfo/en/bills/xml` | 200 | 2026-10-11 | LEGISinfo all current session bills XML |
| `https://www.parl.ca/legisinfo/en/bill/45-1/c-37` | 200 | 2026-10-11 | LEGISinfo Bill C-37 HTML overview |
| `https://www.parl.ca/legisinfo/en/bill/45-1/c-37/json` | 200 | 2026-10-11 | LEGISinfo Bill C-37 details and stages JSON |
| `https://www.parl.ca/legisinfo/en/bill/45-1/c-37/xml` | 200 | 2026-10-11 | LEGISinfo Bill C-37 details and stages XML |
| `https://www.parl.ca/legisinfo/en/bill/37-1/c-2/json` | 200 | 2026-10-11 | LEGISinfo 37th Parliament Bill C-2 JSON (backfill test) |
| `https://raw.githubusercontent.com/michaelmulley/openparliament/master/parliament/imports/parl_document.py` | 200 | 2026-10-11 | Openparliament Hansard importer source code |
| `https://raw.githubusercontent.com/michaelmulley/openparliament/master/parliament/imports/alpheus.py` | 200 | 2026-10-11 | Openparliament Hansard XML parser source code |
| `https://raw.githubusercontent.com/michaelmulley/openparliament/master/parliament/imports/parlvotes.py` | 200 | 2026-10-11 | Openparliament votes importer source code |
| `https://raw.githubusercontent.com/michaelmulley/openparliament/master/parliament/imports/legisinfo.py` | 200 | 2026-10-11 | Openparliament LEGISinfo importer source code |
| `https://raw.githubusercontent.com/michaelmulley/openparliament/master/parliament/imports/parl_cmte.py` | 200 | 2026-10-11 | Openparliament committee importer source code |
| `https://raw.githubusercontent.com/michaelmulley/openparliament/master/parliament/hansards/models.py` | 200 | 2026-10-11 | Openparliament Hansards Django models source code |
