# Vote-call measurement (23 archived House sittings)

Source: `/home/deck/.local/share/partake-watch/watch.db`, SQLite `mode=ro`.
Command: `python3 -m watch.alerts measure --db /home/deck/.local/share/partake-watch/watch.db --limit 40`.

Before: events=23 called=20 matched=11 divisions_in_window=31 recall=0.354839 precision=0.550000.
After: events=23 called=17 matched=16 divisions_in_window=31 recall=0.806452 precision=0.941176.
Recall gains include the scoring corrections below, as well as detector changes.

## Detection

Triggers (case insensitive, joined across up to eight caption lines):
- “call in the members”, including “now, call in the members”.
- “The ten-minute period for (members) voting electronically has (now) started”; also “electronic voting”, “ten minute”, “10-minute”, and caption “has start”.
- “The electronic voting has (now) started”.
- “The House will now wait for the electronic voting period to end”.
- “[Calling of Recorded Vote]”, allowing spaces inside brackets.

Attribution uses the latest question/motion marker within five minutes before the
trigger, not an earlier debated bill. Its text must explicitly name a bill number
(e.g. C-5, Bill C-39; also caption forms Bill C39 / Bill c minus 25), before the
invitation to request a recorded division. Adjournment, closure, time allocation,
government-business disposal orders and “stands deferred” questions are excluded.
The first qualifying trigger anchors a 15-minute same-bill cluster, per event.
Later triggers in that cluster do not alert; stored alerts preserve dedupe across
polls/restarts. Distinct bills named in stacked deferred questions each alert once.
The old false-positive regression now requires silence; its positive control remains.

## Measurement

Only bill divisions timestamped inside each event's caption span enter the denominator.
An alert matches the same bill in that span from 30 minutes before to 90 minutes after
its call; previously the lead was two minutes. Read-only inspection found C-232's
19:57 call stamped 19:35, and C-218's 19:49 call stamped 19:45.
One alert may match several divisions on the same bill: every division is credited
once per event, while `matched` counts successful alerts for precision. Stacked
sessions require a separately attributed alert for each bill; one bill cannot cover
another. The old scorer credited only the first matching division. All residuals
are now emitted, rather than truncating each list to ten. This is bill/time matching,
not proof of identical motion wording; rounded timestamps limit that precision.

## Residuals (caption context checked read-only)

- False 45549, C-16 at 01:02:42: “Call in the members” is corrected immediately afterward: “Forgive me, not calling the members”; live detection cannot know a future correction.
- Miss 45-1/161, C-9: empty result-time context; later question allocates five further hours, so this time-allocation vote is intentionally excluded.
- Miss 45-1/155, C-14: question says “not more than five hours shall be allocated”; intentionally excluded time allocation.
- Miss 45-1/154, C-25: empty result-time context; later question allots five further hours, intentionally excluded time allocation.
- Miss 45-1/142, C-20: empty result-time context; later question allots five further hours, intentionally excluded time allocation.
- Miss 45-1/140, C-33: result-time context is adjournment debate; earlier C33 question applies previous results by unanimous consent, without a new call trigger.
- Miss 45-1/134, C-16: empty result-time context; later question allots one further sitting day/five hours, intentionally excluded time allocation.

## Verification

Baseline: 206 tests passed; final full suite: 216 tests passed.
Full-suite mutation drills: removing electronic triggers made 4 tests fail; restoring
the 30-minute any-bill lookback made 4 fail. Original restored byte for byte; 24 alert tests passed.
Fixtures are real English archive rows, extracted through `mode=ro`, each under 20 KB.
