# ParTake — design

A personal viewer for ParlVU (https://parlvu.parl.gc.ca), the Canadian House of
Commons video site: a native Android app, plus a web app for Windows and
macOS browsers served from a home machine. Settled in a design
interview on 2026-09-23.

Unofficial and non-commercial. The House permits reproduction of its
proceedings "provided that the reproduction is accurate and is not presented as
official", and not for commercial purpose or financial gain
(`ourcommons.ca/Content/Misc/parlvu-faq-e.pdf` §1.1). The app must not use
official branding or present itself as a House of Commons product.

## Decisions

### Scope

| Decision | Choice |
|---|---|
| Audience | Just the owner. Public GitHub repo, README states unofficial / non-commercial. |
| Coverage | House of Commons chamber + committees (everything ParlVU carries). Senate (SenVU) out of scope. |
| Platforms | Android (native app) and a web app for Windows/macOS browsers. Changed 2026-09-23: native Windows/macOS apps dropped (no Xcode locally; owner prefers the browser). |
| Stack | Flutter, one codebase. `media_kit` (libmpv) for playback, `audio_service` for background audio, `workmanager` / exact alarms for alerts. |
| Backend | Android: none, scraping on-device. Web: a small Python standard-library server on the Pixelbook (ChromeOS Linux, `ssh pixelbook`) serves the built web app and proxies ParlVU's listing and event pages on the same origin (ParlVU sends no CORS headers). Video (CDN) and openparliament.ca are fetched directly by the browser (both send `access-control-allow-origin: *`). |
| History / resume | Per device only, no sync. |
| Distribution | A `v*` tag makes CI build signed per-ABI APKs plus a web tarball into GitHub Releases. Android updates via Obtainium; the web app is redeployed to the home server. |

### Player

| Decision | Choice |
|---|---|
| Default audio | Floor. English / French interpretation switchable per video. |
| Captions | On by default, toggleable. Source: ParlVU `ccItems`. |
| Background audio | Yes (Android media session; a browser tab keeps playing in the background). |
| Picture-in-picture | Yes. Android native PiP; on the web, a PiP button where the browser supports it (Chrome, Edge, Safari). Android auto-enters PiP on leaving the app while video (not audio-only) plays. |
| Live DVR | Pause, rewind and "go to live" within whatever window the live stream offers. Fall back to live-edge only if the window is tiny. |
| Speaker jumps | Speaker list from Hansard via openparliament.ca, House and committees. Hansard times are 5-minute buckets, so each speech is placed by matching its opening words against the timed captions (see [Speech alignment](#speech-alignment)). Available once Hansard publishes (~next day). |
| Text search | Search the closed captions of any event, including same-day, and jump to the match. |

### App

| Decision | Choice |
|---|---|
| Home screen | Live now, then Continue watching (resume points), then today's schedule. Calendar one tap away. |
| Following | Follow the chamber and individual committees. |
| Alerts | Android only. See [Alerts](#alerts). |

## Alerts

1. A periodic background sync (~every 15 min, Android's minimum; more often is not
   needed) fetches upcoming events for followed categories and stores each one's
   `ScheduledStart`.
2. For each followed event, schedule an exact alarm at `ScheduledStart`.
3. When it fires, check the event's status. If live: post a "now live"
   notification and stop. If not: schedule the next check as another exact
   alarm (chained alarms, no foreground service, no ongoing notification).
   Under Doze these can be spaced ~9 min apart; that lag is accepted.
4. Stop after 60 minutes past `ScheduledStart`, or earlier if ParlVU marks the
   event cancelled / in camera / ended.

The sync in step 1 also catches events added the same day and rescheduled
start times.

## What ParlVU exposes (research, 2026-09-23)

ParlVU is a server-rendered ASP.NET MVC 4 app, "Harmony" by Sliq Media
Technologies. There is no documented public API. The endpoints below are
internal and may change without notice; the scraper must fail loudly, not
silently, when their shape changes.

**Listing.** `GET /Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate=YYYYMMDD&endDate=YYYYMMDD&searchTime=&searchForward=true&order=asc`
returns JSON, ~10 KB for a whole day. `categoryId` filters to one committee;
ids come from `GET /Harmony/en/api/Data/GetCategoryList` (~250 KB tree, e.g.
HESA=901, PACP=904 in the 45th Parliament, 1st session). Row sample:

```json
{"Title":"HESA Meeting No. 35-2","ScheduledStart":"2026-09-23T16:30:00","ForeignKey":null,"Id":45806}
```

`ForeignKey` is the event page id (`fk=`), but is sometimes `null`
(in-progress multi-part meetings, some Question Period sub-rows) while `Id`
is set. Resolved: the path form `PowerBrowserV2/-1/-1/{Id}` works for every row
(see below), so the app always uses `Id`.

**Event page.** `GET /Harmony/en/PowerBrowser/PowerBrowserV2?fk=<id>` embeds
inline JS holding:

- `availableStreams`: one entry per language, each with `Url`, `Lang`
  (`fl` / `en` / `fr`), `Tag`, `EnableCC`.
- `timeTags.STARTTIME.timestamp`: wall-clock recording start, e.g.
  `2019-05-01T14:01:31.0000000`.
- `ccItems`: caption lines with wall-clock `Begin` / `End` and `Content`,
  no speaker attribution.
- `AgendaTree` and `Speakers`: present in the model but empty in every sample
  checked (2019, 2022, 2026). Do not rely on them.
- Live status: `meetingStatus > 0` means live; the player has a live-rewind mode.
  The listing's live status comes from `GetUpcomingEvents` (see the live test
  findings below).

**Video.** HLS, H.264 + AAC, 10 s MPEG-TS segments, one rendition per
stream (854x480 on the VOD samples; live HD streams are 1920x1080). No DRM, no tokens or signed URLs. The CDN returns
`access-control-allow-origin: *`.

- VOD host: `parlvuvod01.azureedge.net`. Each language is a separate URL
  (`pvvodhoc-fl` / `-en` / `-fr` paths plus an `audioindex` param), not audio
  groups within one manifest. Switching language means switching URL at the
  same position.
- Live host: `parlvuvideo02.azureedge.net` (primary) and `parlvuvideo01`
  (secondary / failover), per-room paths such as `HOC-HD-RAZOR01/WB_Chamber/VH/`.

**Speaker alignment.** `video_offset = speech_time - STARTTIME`.
openparliament.ca gives per-speech times
(`https://api.openparliament.ca/speeches/?document=/debates/2019/5/1/`,
`"time": "2019-05-01 14:00:00"`). Hansard XML only has 5-minute
`<Timestamp>` markers. The 2019 sample matched ParlVU's `STARTTIME` within a
minute.

**Archive.** Public web access since 2004-02-02.

## Findings from the second research pass (2026-09-23)

Research run `20260923-213446-agy-64907`, spot-checked by hand; the fixtures in
`packages/parlvu/test/fixtures/` are the evidence.

- **Listing shape**: `{"NextTime", "PreviousTime", "Weeks": [{"WeekStart",
  "ContentEntityDatas": [row, ...]}]}`. `EntityStatus`: 0 not started, 1 live,
  2 paused, -1 ended ("Adjourned"), -3 cancelled, -4 opened, 101 in camera.
- **Every event opens by `Id`**: `/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/{Id}`
  works for all rows, including `ForeignKey: null`. `?fk={Id}` redirects to
  `NoEvent`.
- **Inline JSON**: `var availableStreams = [...];`, `\tEventInfo:{...},` and
  `\tccItems:{...},` each parse as JSON on their own; the enclosing
  `var dataModel` does not.
- **Video offset** = wall clock − `STARTTIME` + `PreRoll` (30 s). The media
  file name carries the file start (`…_16-30-09_VL.mp4` for STARTTIME
  16:30:39).
- **Streams**: per language a `Video`, sometimes a `Video SD`, and an `Audio`
  variant. Non-televised committees have only `Audio` streams and no captions.
- **Captions** exist for televised committees as well as the chamber, in
  English and French, timed in wall clock.
- **Language switching**: fl/en/fr playlists have identical segment counts and
  durations (House Sitting 142: 1,855 segments, 18,614.862 s each).

### Speech alignment

openparliament.ca `time` values (House and committees) are Hansard's
5-minute markers, not speech starts. `alignSpeeches` places each speech in
two passes:

1. Match: for speeches with at least 8 words, find the first 8 in the English
   caption word stream within [bucket − 60 s, bucket + 7 min] and not before
   the previous match; accept 5 of 8 words in order.
2. Place the rest proportionally through their bucket by word count, clamped
   between the neighbouring matches.

Simulated on ETHI meeting 49: 25 of 108 speeches matched exactly; all
hand-checked anchors land exactly. Short speeches ("I have a point of order")
are never matched, because they recur and cause false matches.

## Findings from the live test (2026-09-24)

Measured on HoC Sitting No. 143 while it was live; raw evidence in
`docs/live-test-2026-09-24.md`.

- **Listing**: `GetListViewData` returns only started recordings. Live,
  in-camera and not-started events come from
  `GET /Harmony/en/api/Data/GetUpcomingEvents?lastModified=` (empty value, or
  the 17-digit `yyyyMMddHHmmssfff` of `LastModifiedTime` for a delta), shape
  `{"ContentEntityDatas": [[row, ...], ...], "LastModifiedTime": ...}` - a
  list of groups (Outstanding / Today / This week / Upcoming) of listing
  rows. The app merges it by `Id` for today and later days, upcoming rows
  winning.
- **Live event page**: `ccItems:null`, `PreRoll` 0 on every stream, `IsLive`
  true, `ENDTIME` null. Live audio has its own host (`parlvuaudio02`,
  `HOC230-Dante-7/WB_Chamber/AL/..`).
- **DVR window**: a sliding window of 4,680 x 10.01 s segments (46,801 s,
  about 13 h), `EXT-X-TARGETDURATION:12`, no `EXT-X-PLAYLIST-TYPE`. The
  chunklist carries `#STARTTIME:` (wall clock of the window start), which on
  the test day was about 11 h before the sitting started: position 0 is not
  the sitting start. Live wall-clock offset = wall clock - chunklist
  `#STARTTIME`, not `STARTTIME` + `PreRoll`. Nothing in the app uses live
  offsets today (no captions list, no speakers, no resume while live).
- **Live playback**: hls.js opens a live stream 34-44 s behind the edge.
  Seeking to the exact edge stalls (3.5 s); 12 s short stalls repeatedly;
  36 s short (three segments) plays cleanly. "Go live" lands 36 s short and
  shows only when more than 60 s behind.
- **Live captions**: CEA-608 inside the English and French video segments
  (`EnableCC:true`), exposed by hls.js as text track `CC1`. The Floor streams
  carry none (`EnableCC:false`). Captions exist only for segments the player
  has loaded, so there is no caption search while live.
- **Spoken language**: openparliament paragraphs carry
  `data-originallang="en|fr"` (from Hansard's `<FloorLanguage>`); captions
  carry interpreter markers (`[Speaking in French]`, `Voice of Interpretor`,
  `[End of Interpretation]`, `(voix de l'interprète)`). Research run
  `20260924-123105-agy-60116`.

## Open questions

1. ~~DVR window length on live streams~~ Answered 2026-09-24: about 13 h,
   sliding (see above). Committee live hosts (`parlvuvideo04`, failover `03`)
   not yet measured.
