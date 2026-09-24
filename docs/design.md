# ParTake — design

A personal viewer for ParlVU (https://parlvu.parl.gc.ca), the Canadian House of
Commons video site, for Windows, macOS and Android. Settled in a design
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
| Distribution | CI builds APK + Windows + macOS artifacts per tag into GitHub Releases. Android updates via Obtainium; desktop checks GitHub Releases on launch and prompts. |

### Player

| Decision | Choice |
|---|---|
| Default audio | Floor. English / French interpretation switchable per video. |
| Captions | On by default, toggleable. Source: ParlVU `ccItems`. |
| Background audio | Yes (Android media session; desktop keeps playing when minimised). |
| Picture-in-picture | Yes. Android native PiP; desktop is an always-on-top mini window. |
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
is set. How to resolve those is an open question.

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

**Video.** HLS, H.264 + AAC, 10 s MPEG-TS segments, single 854x480 rendition
observed. No DRM, no tokens or signed URLs. The CDN returns
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

## Open questions

1. DVR window length on live streams: measure it from a live manifest during a
   sitting. Live hosts: `parlvuvideo02` (chamber) and `parlvuvideo04`
   (committees), failover `01` / `03`.
