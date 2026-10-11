# Research Report: ParlVU Caption Extraction and Speaker Identification on Steam Deck

Date of research: 2026-10-11
Target machine: Steam Deck (Linux x86_64, 16 GB unified RAM, ~7 GB typically free, user session)

---

## Q1. Live Captions on the Steam Deck

### 1.1 Headless Caption Extraction Feasibility
- **Fact** (2026-10-11, local execution): `/usr/bin/ffmpeg` version `n7.1.1` is installed on the host system. It includes the built-in EIA-608 / CEA-708 closed caption decoder (`cc_dec`, codec `eia_608`).
- **Fact** (2026-10-11, local execution): Two distinct headless approaches successfully extract CEA-608 closed captions continuously from ParlVU HLS streams on the Steam Deck:
  1. **Method 1 (Pure FFmpeg via `lavfi` movie filter)**:
     FFmpeg decodes video frames internally and exposes the embedded CEA-608 SEI user data on the filter pad `subcc`, muxing it directly to SRT, WebVTT, or ASS without any external tools.
     Working command:
     ```bash
     ffmpeg -f lavfi -i "movie='<hls_playlist_url>'[out0+subcc]" -map 0:1 -c:s srt output.srt
     ```
     *Note on syntax*: Colons in URLs must be escaped as `\:` within the `movie=` filter argument (e.g., `https\://...` and `mp4\:azrhoc02`).
  2. **Method 2 (FFmpeg Stream Copy piped to Lightweight Annex B SEI Extractor)**:
     FFmpeg copies the compressed H.264 video stream without decoding (`-c:v copy`), piping raw Annex B NAL units to a lightweight Python script ([`extract_608_annexb.py`](scripts/extract_608_annexb.py)). The extractor scans only NAL header start codes (`00 00 01`), filters for SEI NAL units (`nal_unit_type == 6`), extracts ATSC A/53 (GA94) user data (`payloadType == 4`), and decodes the CEA-608 CC1 byte pairs.
     Working command:
     ```bash
     ffmpeg -v error -i "<hls_playlist_url>" -map 0:v -c:v copy -f h264 - | python3 docs/watch/research/captions/scripts/extract_608_annexb.py
     ```

### 1.2 Performance Measurements (CPU % and Peak RSS)
Measurements were conducted inside dedicated transient systemd user units (`systemd-run --user --slice=aiorch-agents.slice -p MemoryMax=1500M --wait --collect`) on House chamber Sitting No. 149 (event 45735) for 180 seconds (3 minutes) of stream duration.

| Approach | Stream Rendition | Media Duration | Service Runtime | CPU Time Consumed | Realtime CPU Load (1x) | Memory Peak (RSS) |
|---|---|---|---|---|---|---|
| **Method 1: FFmpeg lavfi `movie`** | SD (854x480, `PV750`) | 180 s | 12.41 s | 6.846 s | **3.80% of 1 core** | **122.4 MB** |
| **Method 1: FFmpeg lavfi `movie`** | HD (1920x1080, `PVHD`) | 180 s | 18.97 s | 27.943 s | **15.52% of 1 core** | **111.4 MB** |
| **Method 2: `-c:v copy` + Extractor** | SD (854x480, `PV750`) | 180 s | 6.90 s | 0.569 s | **0.32% of 1 core** | **45.2 MB** |
| **Method 2: `-c:v copy` + Extractor** | HD (1920x1080, `PVHD`) | 180 s | 9.88 s | 0.789 s | **0.44% of 1 core** | **50.8 MB** |

- **Fact** (2026-10-11, local execution): Method 2 consumes **11.9x less CPU** than Method 1 on SD (0.32% vs 3.80%) and **35.4x less CPU** on HD (0.44% vs 15.52%), because it avoids decoding H.264 video frames. Peak RSS is also reduced by 63% (45.2 MB vs 122.4 MB).
- **Fact** (2026-10-11, local execution): Sample extracted captions for 3 minutes of Sitting No. 149 are saved in [`samples/hoc_149_3min_lavfi.srt`](samples/hoc_149_3min_lavfi.srt) (Method 1) and [`samples/hoc_149_3min_annexb.txt`](samples/hoc_149_3min_annexb.txt) (Method 2).

### 1.3 Three Concurrent Streams: Extrapolation vs Measurement
- **Fact** (2026-10-11, local execution): Three concurrent streams were directly **measured** running simultaneously inside a single transient cgroup unit for 120 seconds each (HoC Sitting 149 English SD, HoC Sitting 149 French SD, and FINA Meeting 53 English SD; benchmark script [`scripts/benchmark_concurrent.sh`](scripts/benchmark_concurrent.sh)):
  - **Method 2 (copy + extractor, 3 concurrent streams)**:
    - **Measured Service Runtime**: 7.33 s
    - **Measured Combined CPU Time**: 1.402 s across all 3 streams over 120 s of media
    - **Measured Realtime CPU Load**: **1.17% of 1 core** (1.402 s / 120 s)
    - **Measured Peak RSS**: **111.0 MB** total for all 3 concurrent processes
    - **Comparison to 3x single-stream extrapolation**: Single-stream extrapolation predicted 3 * 0.316% = 0.95% CPU and 3 * 45.2 MB = 135.6 MB RSS. Measured CPU (1.17%) and RSS (111.0 MB) match the extrapolation closely, with slight CPU variance due to concurrent process spawning.
  - **Method 1 (FFmpeg lavfi, 3 concurrent streams)**:
    - **Measured Service Runtime**: 8.10 s
    - **Measured Combined CPU Time**: 16.998 s across all 3 streams over 120 s of media
    - **Measured Realtime CPU Load**: **14.16% of 1 core** (16.998 s / 120 s)
    - **Measured Peak RSS**: **174.6 MB**
    - **Comparison to 3x single-stream extrapolation**: Single-stream extrapolation predicted 3 * 3.80% = 11.4% CPU. Measured CPU was 14.16% due to concurrent multi-threaded decoding overhead.

### 1.4 Lowest-Bitrate Rendition (SD vs HD)
- **Fact** (2026-10-11, curl [`hoc_149_sd_master_playlist.m3u8`](samples/hoc_149_sd_master_playlist.m3u8), [`hoc_149_hd_master_playlist.m3u8`](samples/hoc_149_hd_master_playlist.m3u8)): Both SD (854x480, `BANDWIDTH=1062476`) and HD (1920x1080, `BANDWIDTH=2358849`) master playlists declare identical caption tracks: `#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID="cc",NAME="English",AUTOSELECT=YES,LANGUAGE="en",INSTREAM-ID="CC1"`.
- **Fact** (2026-10-11, local execution): Captions extracted from the lowest-bitrate SD rendition (`hoc_149_3min_lavfi.srt`) and the HD rendition (`hoc_149_3min_hd_lavfi.srt`) over the same 180-second window are textually identical (verified via `diff`).
- **Recommendation**: The lowest-bitrate rendition (SD, `PV750`, ~1.06 Mbps) is completely sufficient for caption extraction. Using SD instead of HD saves 55% network bandwidth (1.06 Mbps vs 2.36 Mbps) and reduces CPU usage by 28% under Method 2 and 75% under Method 1.

### 1.5 ParlVU Endpoints Tracing
Tracing through `packages/parlvu/lib/src/parlvu_client.dart`:
1. **Event Discovery**:
   - **Archived / On-demand (Chamber & Committee)**:
     `GET https://parlvu.parl.gc.ca/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate=YYYYMMDD&endDate=YYYYMMDD&searchTime=&searchForward=true&order=asc` (HTTP 200).
     Returns JSON containing `Weeks[].ContentEntityDatas[]` with event `Id`, `Title`, `ScheduledStart`, `EntityStatus: -1` ("Adjourned"). Sample saved in [`samples/parlvu_listing_sample.json`](samples/parlvu_listing_sample.json).
   - **Live / Upcoming (Chamber & Committee)**:
     `GET https://parlvu.parl.gc.ca/Harmony/en/api/Data/GetUpcomingEvents?lastModified=` (HTTP 200).
     Returns JSON containing `ContentEntityDatas[][]` with `EntityStatus: 1` ("Live") or `EntityStatus: 0` ("Not Started"). Sample saved in [`samples/parlvu_upcoming_sample.json`](samples/parlvu_upcoming_sample.json).
2. **Stream URL Retrieval**:
   - For all events (Chamber and Committee, Live and Archived), the event detail page URL is:
     `GET https://parlvu.parl.gc.ca/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/{Id}` (HTTP 200).
     The page embeds `var availableStreams = [...]` as inline JSON containing `Url`, `Lang` (`fl`/`en`/`fr`), `Tag`, `IsLive`, and `EnableCC`.
   - **Stream URLs (Confirmed with curl)**:
     - **House Chamber Archived (Sitting 149, Id 45735)**:
       Master SD: `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng` (HTTP 200)
       Master HD: `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PVHD/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VH.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng` (HTTP 200)
     - **Committee Meeting Archived (FINA Meeting 53, Id 45870)**:
       Master SD: `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-08/45870_FINA%20Meeting%20No.%2053_10-00-19_VL.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng` (HTTP 200)
     - **Live Chamber and Committee Endpoints**:
       The event page embeds room-specific live stream URLs configured in `settings.backupStreamMapping`:
       - Chamber Primary SD: `https://parlvuvideo02.azureedge.net/HOC-HD-RAZOR01/WB_Chamber/VL/` (Secondary: `parlvuvideo01.../HOC-HD-RAZOR03/...`)
       - Committee Primary SD (e.g., Wellington 415): `https://parlvuvideo04.azureedge.net/HOC250-DUO-64/WEL_415/VL/` (Secondary: `parlvuvideo03.../HOC250-DUO-60/...`)

**Answer**: Yes, a headless process on the Steam Deck can continuously extract CEA-608 captions from ParlVU HLS streams. Copying video (`-c:v copy`) piped to a lightweight Annex B SEI extractor takes only ~0.32% of one CPU core and 45.2 MB RSS for one stream, scaling to ~1.17% CPU and 111 MB RSS for three concurrent streams (verified by measurement). The lowest-bitrate SD rendition carries full captions identical to HD.

---

## Q2. Live Speaker Info

### 2.1 Investigation of ParlVU Native Feeds and Metadata
- **Fact (Anti-Vacuity Probe)** (2026-10-11, curl [`DDB0E9B70F89D094071F5867745BD7BE__b9783e.js`](https://parlvu.parl.gc.ca/Harmony/javascript/DDB0E9B70F89D094071F5867745BD7BE__b9783e.js), HTTP 200): Sliq Harmony's PowerBrowser player contains full client-side logic for displaying speakers and agendas:
  - Client functions: `Data.normalizeSpeakerList(dataModel.Speakers)`, `Data.referAgendaSpeaker`, `this.initSpeakerTree(..., "people")`, `this.appendSpeakers`, `this.deleteSpeakers`.
  - In `event_45735_page.html.raw`, `dataModel` explicitly declares `Speakers: []` and `AgendaTree: []`.
  - The live polling API `/Harmony/en/api/PowerBrowserData/GetNewData` explicitly parses array indices `m[2]` and `m[4]` for speaker appends and deletions.
- **Fact (Absence in Canadian Parliament)** (2026-10-11, curl [`samples/parlvu_getnewdata_45735.json`](samples/parlvu_getnewdata_45735.json), HTTP 200; [`samples/parlvu_getnewdata_45870.json`](samples/parlvu_getnewdata_45870.json), HTTP 200):
  - In both Chamber (45735) and Committee (45870), `dataModel.Speakers` is empty (`[]`) and `dataModel.AgendaTree` is empty (`[]`).
  - Polling `GetNewData` returns `[ EventInfo, [], [], [], [], false, [], [] ]` where all speaker and agenda update lists are empty arrays.
  - The player JavaScript explicitly executes:
    ```javascript
    if (dataModel.Speakers == null || dataModel.Speakers.length == 0) {
        this.hideLayer("people");
    }
    ```
    hiding the speaker panel because no speaker data is populated by the House of Commons.
- **Fact** (2026-10-11, local execution): MPEG-TS PMT packets declare PID `0x102` with stream type `0x15` ("ID3 "), but packet analysis across segments (`media_0.ts`, `media_10.ts`) shows zero TS packets transmitted on PID `0x102`. HLS playlist tags contain only standard media sequence and segment duration tags without speaker attributes.
- **Inference**: ParlVU provides no native live or archived feed, metadata, or JSON endpoint indicating who is speaking during proceedings.

### 2.2 Speaker Recognition via Caption Text Analysis
Because ParlVU exposes no native speaker data, member recognition was measured in caption text against Hansard for House Sitting No. 149 (2026-10-09, 217 speeches in Hansard via openparliament.ca [`openparliament_speeches_sample.json`](samples/openparliament_speeches_sample.json), HTTP 200, and 8,437 caption lines):

1. **Speaker Handover Announcements**:
   - **Fact** (2026-10-11, analysis of Sitting 149 captions via [`scripts/measure_speaker_recognition.py`](scripts/measure_speaker_recognition.py)): Across the sitting, there were 143 explicit Speaker/Chair handover calls (`>> The Speaker: ... >>`):
     - **By Riding**: **80 / 143 (55.9%)** (e.g., `">> The Speaker: The honourable member for Edmonton Northwest. >>"`, `"...for Whitby"`, `"...for Beauce"`, `"...for Bow River"`).
     - **By Ministerial Portfolio / Parliamentary Role**: **45 / 143 (31.5%)** (e.g., `">> The Speaker: The Honourable Minister of Indigenous Services. >>"`, `"...The Honourable Parliamentary Secretary to the Prime Minister. >>"`).
     - **Procedural / Transition**: **7 / 143 (4.9%)** (`">> The Speaker: Orders of the day. >>"`, `">> The Speaker: Oral questions. >>"`).
     - **Direct Call / Unanimous Consent**: **11 / 143 (7.7%)** (e.g., calling just the riding `"Mount Royal"`, `"Sydney Glace Bay"`, or seeking consent).
     - **Combined Recognitions**: **128 / 143 (89.5%)** of the Speaker's interventions name the incoming member by riding or role.
2. **Identification Rate Against Hansard Member Speeches**:
   - **Fact** (2026-10-11, [`samples/speaker_identification_results.json`](samples/speaker_identification_results.json)):
     - In **Question Period (Oral Questions)**: **100% of questioners** are announced by riding or official opposition role (e.g., `Leader of the Opposition`) immediately prior to speaking.
     - In **General Debate (Bills & Motions)**: Main speeches begin with the Speaker naming the member's riding (e.g., `The Honourable Member for Edmonton Northwest`). However, during rapid 5-minute Questions & Comments exchanges, the Speaker abbreviates ministerial floor turns to simply `"The Honourable Minister?"` without naming the portfolio.
     - **Acoustic / Caption ASR Errors**: Captioning introduces phonetic transcription errors in ridings (e.g., `"Skeena bullably Skeey Valley"` for *Skeena—Bulkley Valley*; `"Niagra Falls Niagra Ontario lake"` for *Niagara Falls*; `"st. albert sunday sturgeon river"` for *St. Albert—Sturgeon River*).
3. **Committee Meetings**:
   - **Fact** (2026-10-11, curl [`fina_53_sample_captions.txt`](samples/fina_53_sample_captions.txt), HTTP 200): In committee meetings, the Chair explicitly names members by surname (e.g., *"please wait until I recognize you by name before speaking"*, then calls *"Mr. Morantz"*, *"Ms. Dzerowicz"*), rather than by riding.

**Answer**: No, ParlVU does not expose who is speaking in any live or archived feed or metadata track (the `Speakers` and `AgendaTree` models are sent empty as `[]`). In the caption stream, the Speaker names the incoming member (by riding or ministerial role) in **89.5% of floor-handover interventions** (128 / 143), including 100% of questioners during Question Period.

---

## Unknowns

1. **Live Stream DVR Edge Behavior During Active Sittings**: Because 2026-10-11 was a Sunday during a parliamentary adjournment week (proceedings resume 2026-10-19 with Sitting No. 150), no live chamber sitting occurred during this evaluation window. Live stream playlist structures were verified against the documented live capture from Sitting No. 143 (`docs/live-test-2026-09-24.md`) and verified room mappings in `settings.backupStreamMapping`. The exact latency from live speech to caption output in a live stream could not be measured directly on 2026-10-11.
2. **French Stream Caption Processing CPU Load**: French streams were verified to carry active CC1 CEA-608 tracks, and 3-stream concurrent benchmarks included a French stream. However, French caption vocabulary size and tokenization characteristics were not benchmarked in isolation from English.
3. **In-Camera Committee Closed Caption Policy**: Whether in-camera committee meetings carry closed captions was not testable, as in-camera proceedings are neither broadcast live nor archived publicly.

---

## Sources

All URLs were fetched directly using `curl` / `urllib` on 2026-10-11 with User-Agent `ParTake-research/0.1 (personal project)` and verified with HTTP status 200:

| URL | HTTP Status | Access Date | Purpose |
|---|---|---|---|
| `https://parlvu.parl.gc.ca/Harmony/en/api/Data/GetUpcomingEvents?lastModified=` | 200 | 2026-10-11 | ParlVU upcoming events listing |
| `https://parlvu.parl.gc.ca/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate=20261001&endDate=20261011&searchTime=&searchForward=true&order=asc` | 200 | 2026-10-11 | ParlVU 10-day event listing |
| `https://parlvu.parl.gc.ca/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate=20261009&endDate=20261011&searchTime=&searchForward=true&order=asc` | 200 | 2026-10-11 | ParlVU 3-day event listing for Sitting 149 |
| `https://parlvu.parl.gc.ca/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/45735` | 200 | 2026-10-11 | Event page for HoC Sitting No. 149 (Chamber) |
| `https://parlvu.parl.gc.ca/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/45870` | 200 | 2026-10-11 | Event page for FINA Meeting No. 53 (Televised Committee) |
| `https://parlvu.parl.gc.ca/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/45881` | 200 | 2026-10-11 | Event page for CC39 Meeting No. 1 (Webcast Committee) |
| `https://parlvu.parl.gc.ca/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/45873` | 200 | 2026-10-11 | Event page for upcoming HoC Sitting No. 150 |
| `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng` | 200 | 2026-10-11 | Master playlist for Sitting 149 SD English |
| `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PVHD/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VH.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng` | 200 | 2026-10-11 | Master playlist for Sitting 149 HD English |
| `https://parlvuvod01.azureedge.net/pvvodhoc-fr/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/playlist.m3u8?audioindex=0&wowzalanguage=fra` | 200 | 2026-10-11 | Master playlist for Sitting 149 SD French |
| `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-08/45870_FINA%20Meeting%20No.%2053_10-00-19_VL.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng` | 200 | 2026-10-08 | Master playlist for FINA Meeting 53 SD English |
| `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-09/45881_CC39%20Meeting%20No.%201_08-51-34_VL.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng` | 200 | 2026-10-11 | Master playlist for CC39 Meeting 1 SD English |
| `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/chunklist.m3u8?audioindex=1&wowzalanguage=eng` | 200 | 2026-10-11 | Chunklist for Sitting 149 SD English |
| `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/media_0.ts?audioindex=1&wowzalanguage=eng` | 200 | 2026-10-11 | Segment 0 for Sitting 149 SD English |
| `https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/media_10.ts?audioindex=1&wowzalanguage=eng` | 200 | 2026-10-11 | Segment 10 for Sitting 149 SD English |
| `https://parlvu.parl.gc.ca/Harmony/javascript/FEB9C08FF32668663BB3090916FA1BDA__5d4195.js` | 200 | 2026-10-11 | ParlVU player JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/javascript/9AF41513B9F8E8BCEC09051270AB9D58__1255b23.js` | 200 | 2026-10-11 | ParlVU player JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/javascript/552417ADE9C438E56FE333B463BE9D6A__b9783e.js` | 200 | 2026-10-11 | ParlVU player JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/en/api/LocalizationJS/PowerBrowserV2` | 200 | 2026-10-11 | ParlVU localization JS endpoint |
| `https://parlvu.parl.gc.ca/Harmony/javascript/F30BCCA1EE0A7021F9CF4314BB80E550__b97832.js` | 200 | 2026-10-11 | ParlVU player JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/javascript/DDB0E9B70F89D094071F5867745BD7BE__b9783e.js` | 200 | 2026-10-11 | ParlVU main player logic JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/javascript/E926926CE218AAD5579A4C89DD9FA8BB__1ce2d26.js` | 200 | 2026-10-11 | ParlVU telemetry JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/javascript/B3F896C92BDFB918E89D73E13C0AC26E__b97832.js` | 200 | 2026-10-11 | ParlVU player UI JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/javascript/47CE0AE1FF5D05189622353CFBE7DE11__1136dd2.js` | 200 | 2026-10-11 | ParlVU player video core JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/javascript/310E9D5D5F7EC5782E64F28B5CB81D08__18079c1.js` | 200 | 2026-10-11 | ParlVU player control JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/javascript/B6D24B68259C915A9025FB09A406B232__11478ca.js` | 200 | 2026-10-11 | ParlVU player auxiliary JS bundle |
| `https://parlvu.parl.gc.ca/Harmony/en/api/PowerBrowserData/GetNewData?id=45735&eventLast=&agendaLast=&speakerLast=&viewMode=0&venueId=174` | 200 | 2026-10-11 | ParlVU live polling API for Sitting 149 |
| `https://parlvu.parl.gc.ca/Harmony/en/api/PowerBrowserData/GetNewData?id=45870&eventLast=&agendaLast=&speakerLast=&viewMode=0&venueId=180` | 200 | 2026-10-11 | ParlVU live polling API for FINA Meeting 53 |
| `https://api.openparliament.ca/speeches/?document=/debates/2026/10/9/&format=json&limit=5` | 200 | 2026-10-11 | Hansard speech API sample for 2026-10-09 |
| `https://api.openparliament.ca/speeches/?document=/debates/2026/10/9/&format=json&limit=1` | 200 | 2026-10-11 | Hansard pagination probe |
| `https://api.openparliament.ca/speeches/?document=/debates/2026/10/9/&format=json&limit=100` | 200 | 2026-10-11 | Hansard speeches page 1 for 2026-10-09 |
| `https://api.openparliament.ca/speeches/?document=/debates/2026/10/9/&format=json&limit=100&offset=100` | 200 | 2026-10-11 | Hansard speeches page 2 for 2026-10-09 |
| `https://api.openparliament.ca/speeches/?document=/debates/2026/10/9/&format=json&limit=100&offset=200` | 200 | 2026-10-11 | Hansard speeches page 3 for 2026-10-09 |
