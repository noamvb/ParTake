# ParTake

A personal viewer for [ParlVU](https://parlvu.parl.gc.ca), the House of
Commons of Canada's video site: live and archived sittings and committee
meetings, with Floor / English / French audio, captions, jump-to-speaker,
caption search, resume-where-you-left-off, and Android alerts when a followed
committee goes live.

**Unofficial.** ParTake is not affiliated with or endorsed by the House of
Commons, and is not presented as an official source. It is for personal,
non-commercial use, which the House's reproduction terms permit ("provided that
the reproduction is accurate and is not presented as official"; see the
[ParlVU FAQ](https://www.ourcommons.ca/Content/Misc/parlvu-faq-e.pdf), §1.1).
Speaker times come from [openparliament.ca](https://openparliament.ca).

## Parts

| Path | What |
|---|---|
| `lib/` | Flutter app: Android (native) and web (Windows/macOS browsers). |
| `packages/parlvu/` | Dart client for ParlVU and openparliament.ca, caption-based speech alignment. |
| `server/` | Python standard-library server: serves the web build and proxies ParlVU's listing and event pages on the same origin (ParlVU sends no CORS headers). |
| `docs/design.md` | Decisions and the verified facts about ParlVU. |

## Develop

    flutter pub get && (cd packages/parlvu && dart pub get)
    flutter analyze && flutter test
    (cd packages/parlvu && dart test)
    python3 -m unittest server/test_partake_server.py

Web, locally:

    flutter build web --release
    python3 server/partake_server.py --root build/web --host 127.0.0.1 --port 8790

## Install

- **Android:** releases are signed APKs on the
  [Releases page](https://github.com/noamvb/ParTake/releases). With
  [Obtainium](https://github.com/ImranR98/Obtainium), add this repository's URL
  to get updates automatically.
- **Web:** see `server/README.md` for running the server on a home machine.
