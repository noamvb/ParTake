# Parliament watch: kickoff brief

Written 11 Oct 2026 at the end of a grilling session with the owner. This file
is the hand-off to the session that plans and builds the feature. Decisions
below are the owner's; do not reopen them without asking. Anything marked
**verify** is an assumption, not a fact.

## What it is

ParTake today plays ParlVU video, with captions, Hansard speaker jumps and
alerts for followed committees (see `README.md` and the codebook page
`~/Code/codebook/projects/partake.md`). Parliament watch adds a year-round
"what happened in Parliament about the things I care about" layer:

- A **Deck service** collects Parliament data, matches it against the owner's
  follows, and serves the results.
- **ParTake** (Android and web) gets a **Watch tab**, the follow editor and the
  notifications.

## Decisions (owner, 11 Oct 2026)

| Topic | Decision |
|---|---|
| Home | A new `watch/` folder in this repo, next to `server/`. The Deck runs it always-on. |
| UI | A new Watch tab in ParTake on Android and web. The Deck serves the web build as today. |
| Follows | Topics (keywords and meanings), specific bills, votes and party splits, particular MPs. |
| Editing follows | In ParTake's Following screen. The Deck stores the single list, so phone and web stay in sync. |
| Matching | Meaning-based (embeddings) from day one, not keyword-first. |
| Model | A small embedding model (about 300 MB) stays loaded while the House sits. The chat LLM stays off. |
| Text sources | Live captions from the House chamber and from committees the owner follows, then the official Hansard replaces the caption text when it publishes (usually the next morning). |
| Digest | Evening (around 7-8 pm, from captions, votes and bill moves), then a morning fix-up that swaps matches for clean Hansard text and links. |
| Live alerts | Only two: (1) a followed bill comes to a vote, (2) a followed MP is speaking. Nothing else interrupts. |
| Speaker detection | If ParlVU has no live "who is speaking" data, fall back to spotting the Speaker naming the member in the captions. |
| History | Backfill everything since the current Parliament opened (spring 2025). |
| Deadline | None. The House usually rises around mid-December, so live sittings before then are the best test bed. |

## Step 1: check the data sources (do this before planning)

Delegate this as research (an analysis contract via `bin/delegate`; see
`~/.ai-orch/docs/delegation-playbook.md`). It needs to answer, with URLs and
sample payloads saved under `docs/watch/research/`:

1. **Live captions on the Deck.** ParTake reads CEA-608 captions from the HLS
   stream in the client (hls.js on web). Can a headless Deck process (ffmpeg or
   similar) extract them continuously from one to three live streams, and what
   CPU and memory does that cost? Which ParlVU endpoints give the stream URLs?
   The `packages/parlvu` client already parses listings and event pages.
2. **Live speaker info.** Does ParlVU (event page, stream metadata, any API)
   expose who is speaking during a live sitting? If not, how reliably do the
   captions contain the Speaker's "The honourable member for ..." lines?
3. **Hansard.** openparliament.ca (already used for speaker jumps) versus
   ourcommons.ca Hansard XML: when each publishes, rate limits and terms, and
   committee evidence coverage.
4. **Votes and bills.** Sources for recorded divisions with per-MP votes
   (ourcommons.ca, openparliament.ca) and bill stages (LEGISinfo). Check
   formats, update timing and how far back they go for the backfill.
5. **MPs.** A stable ID for each MP that links the vote, Hansard and caption
   sources.
6. **Embedding model.** Which small embedding model Ollama on the Deck should
   run (check the current names, don't assume), its memory footprint, and its
   throughput on the Deck for the backfill estimate.

Resolve every URL in the report mechanically before relying on it. Research
delegates invent identifiers.

## Step 2: plan

- Write `docs/watch/PLAN.md`: phases, the API contract between the Deck
  service and ParTake (`docs/watch/api.md`), storage and the backfill job.
- Create a living checklist (`~/.ai-orch/bin/checklist create partake-watch ...`)
  and give the owner its URL.
- Get the owner's OK on the plan before implementation starts.

## Things to reuse and constraints

- **election-night** (`~/Code/election-night`) already has the recorder
  pattern: poll on a cycle, write append-only JSONL, keep raw payloads only
  when they change, and do the analysis in pure functions. Read its `PLAN.md`
  and `docs/api.md` before designing `watch/`.
- **Deck memory is tight.** It has been OOM-killed before (see
  `~/.claude/projects/-home-deck-Code/memory/remote-control-oom-drops.md`).
  Run the service and any heavy job in its own systemd unit
  (`systemd-run --user --slice=aiorch-agents.slice` for one-off jobs), never
  inside a Claude session's cgroup. Ollama is off by default on the Deck, and
  election-night turns it on only around election nights; this feature needs
  a permanent arrangement, so agree it with the owner.
- **deck-hub** (`~/Code/deck-hub/sites.json`): add a card. Ports already used
  are 7717, 7718, 8765, 8790 and 8796; pick a free one.
- **Phone:** the Galaxy Z Fold 7 reaches the Deck over Tailscale. Every screen
  must work on both the cover and inner displays. Hard rules on driving the
  phone are in `~/.ai-orch/docs/owner.md`.
- **Releases:** ParTake ships through its tag-driven GitHub Actions APK
  workflow (`android-release` skill). Pushes go through `bin/push-if-green`.
- Orchestrate, don't implement: route work per `~/.claude/CLAUDE.md`.

## Not in scope

The life dashboard, the owner's other chosen project, gets its own session
later. Notes on it are in
`~/.claude/projects/-home-deck-Code/memory/next-projects-2026-10-11.md`.
