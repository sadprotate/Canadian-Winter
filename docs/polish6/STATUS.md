# Polish round 6 — status

The brief is `docs/polish6/POLISH_ROUND_6_PROMPT.md`; section agents also read
`docs/polish6/WORKING_BRIEF.md`. This file is kept current after every section so the work can
resume from here.

## Where things stand

- **Branch:** `wc-polish6-pg`, local on the owner's PC. The owner asked to keep the work on their
  computer, so it stands in for the brief's `wc-polish6`. Nothing is pushed until the owner says
  so, and no PR exists yet. Until then "CI green" means the same checks run locally: import,
  `parse_all` and the full test runner.
- **Baseline:** tag `polish6-baseline` = `1b38f4a` (local only, not pushed). Read-only baseline
  worktree for "before" shots and numbers:
  `C:/Users/orsin/AppData/Local/Temp/claude/8a7df22634b74fee/8cef635c-7f04-41ab-a9b1-cd462e6c7b0e/scratchpad/baseline`.
  Baseline logs go in `docs/polish6/baseline/`.

## Sections

| § | Title | Status | Commit | Report |
|---|---|---|---|---|
| §0 | Agent setup, the round-6 brief, baseline | done | this commit (`polish6 §0: agent setup, the round-6 brief`) | `report/s0.md` |
| §1 | What round 5 never pushed | not started | | |
| §2 | The Godot errors after pulling | not started | | |
| §3 | Round 5's open items | not started | | |
| §8.1 | Hold to fill, not spam-click | not started | | |
| §8.2 | Loads twice as big | not started | | |
| §9 | Smooth piles | not started | | |
| §10 | The plow truck from the start | not started | | |
| §11 | Blade up/down, push and pull | not started | | |
| §7 | Weather you can see and hear | not started | | |
| §13 | The phone and the radar | not started | | |
| §12 | Every key rebindable | not started | | |
| §14 | Cold nights | not started | | |
| §15 | The garage | not started | | |
| §16 | The commercial property | not started | | |
| Part 4 | Checks, play-through, HANDOFF, report | not started | | |

## Open items

- The round-5 coordinator's status file (`claude/POLISH_ROUND_5_STATUS.md`) isn't on this PC.
  §1 will build `docs/polish5/STATUS.md` from §3's list unless the owner attaches the original.
- Tags `polish5-baseline` (`15be65a`) and `polish6-baseline` (`1b38f4a`) are not pushed (local
  work only, for now).
- The suites, `run_log` and `make_fixtures` use the owner's real `user://`
  (`%APPDATA%/Godot/app_userdata/Canadian Winter/`: `saves/fun.json`, `saves/survival.json`,
  `settings.cfg`) and overwrite or delete them, as they always have. The owner should know before
  playing between test runs (report/s0.md). Not changed.
- `icon.svg.import` (and, in a fresh checkout, all 74 `*.import` files) is rewritten with LF by
  every import: line endings only (`core.autocrlf=true`, no `.gitattributes`). §2 decides; until
  then don't commit it.

## Binding notes

Rules that later sections must follow, added by each section as it lands: new balance keys, new
actions, function names, gotchas.

**From §0 (baseline):**
- **Baseline numbers are this PC's** (`report/s0.md`, logs in `docs/polish6/baseline/`): all six
  suites **209 passed, 0 failed** (snow 13, systems 28, gameplay 41, polish3 21, polish4 19,
  polish5 87); parse 90 scripts; no engine ERROR / WARNING / exit noise in any log; weather truth
  byte-identical to `tests/fixtures/polish5/weather_truth_baseline.json`.
- **Perf on this PC is about 2× round 5's VM: 21 of 42 `perf.tscn` scenarios are already over
  16.7 ms at p95 at baseline.** Judge a change by before → after on this PC (alternate runs with
  the baseline worktree), not by the absolute budget or round 5's numbers.
- **Time:** `--only=polish5` takes ≈ 22.5 min here and the six suites ≈ 33 min: run polish5 (and
  the full runner) with `run_in_background`, never as one 10-minute foreground command.
- **Fixtures:** `tests/fixtures/polish5_v3/` (14 version-3 saves, `make_fixtures.tscn -- --set=polish5_v3`)
  are this round's baseline fixtures. `FIXTURE_DIRS` in `tests/test_polish5.gd` lists them, so
  `--only=polish5 --test=polish5_fixtures` loads and plays every polish5 and polish5_v3 file.
  Don't regenerate them with a changed build.
- **§10's migration fixture** is `polish5_v3/{fun,survival}_7_keys_pickup_plow_order.json`:
  keys found, the plain `pickup` in the driveway, the `pickup:front_plow:1` order open with status
  `spawned` ("Waiting in the store lot"; an order bought after 9 p.m. is `pending` instead — cancel
  any status but `collected`). Fun $100, Survival $1,500 after the purchase.
- **Orientation shots** are in `docs/polish6/shots/00-orientation/`; the `shot.tscn` opening needs
  `--frames=240` to get past the fade-in.
