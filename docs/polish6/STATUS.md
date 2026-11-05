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
| §0 | Agent setup, the round-6 brief, baseline | done | `aabe73c` | `report/s0.md` |
| §1 | What round 5 never pushed | done | `7abcd57` | `report/s1.md` |
| §2 | The Godot errors after pulling | done | this commit (`polish6 §2: The Godot errors after pulling`) | `report/s2.md` |
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
  §1 rebuilt `docs/polish5/STATUS.md` from the brief's §1/§3 lists, the git history and the
  round-5 reports (it says so at the top). If the owner attaches the original, it replaces it.
- Tags `polish5-baseline` (`15be65a`, created locally in §1) and `polish6-baseline` (`1b38f4a`)
  are not pushed (local work only, for now). With the owner's OK:
  `git push origin polish5-baseline polish6-baseline`.
- **Exporting:** `export_presets.cfg` now exports to `build/windows/CanadianWinter.exe` (ignored
  by `/build/`). Godot doesn't create the folder: until `build/windows/` exists the export fails
  with "Prepare Template: The given export path doesn't exist." The owner makes the folder once
  (or with the export dialog's file browser). Tell the owner in the PR description (report/s1.md).
- The suites, `run_log` and `make_fixtures` use the owner's real `user://`
  (`%APPDATA%/Godot/app_userdata/Canadian Winter/`: `saves/fun.json`, `saves/survival.json`,
  `settings.cfg`) and overwrite or delete them, as they always have. The owner should know before
  playing between test runs (report/s0.md). Not changed.
- `icon.svg.import` (and, in a fresh checkout, all 74 `*.import` files) is rewritten with LF by
  every import: line endings only (`core.autocrlf=true`, no `.gitattributes`). **§2 decided: no
  `.gitattributes`, nothing to commit.** Staging them records no change, and they aren't the
  cause of the errors (report/s2.md). If the owner wants GitHub Desktop's list quiet, one line
  `*.import text eol=lf` in a `.gitattributes` would do it: the owner's call.
- **The CI upgrade-import step (§2) has never run on GitHub.** Its shell ran here in six scenarios
  (report/s2.md). The first PR run is the real check (about 1–2 min). If it fails on GitHub only,
  look first at the fetch of the base by SHA and at `$RUNNER_TEMP`.
- **PR description:** §2's user note (delete `.godot` after errors, close Godot before pulling) is
  in report/s2.md, ready to paste.

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

**From §1 (what round 5 never pushed):**
- **`tools/data_gen/generate_data.gd` reproduces `data/` value for value** (40 files, 920 script
  values; `--only=polish6 --test=s1_data_generator`). Any section that changes a data file
  (`data/tools/*.tres`, `data/vehicles/*.tres`, `data/upgrades/*.tres`, `data/balance.tres`) or a
  `BalanceData` default makes the same change in the generator (`_tools()`, `_vehicles()`,
  `_upgrades()`; balance keys come from `balance_data.gd`'s defaults, so a new balance key needs
  only the default and the `.tres` line). A new `.tres` under `data/` needs a generator entry, or
  the test fails. §8's `throw_recovery_s` / capacities and §3's large-scraper text are the first.
- **`data/balance.tres` equals `BalanceData`'s defaults** (115 stored values,
  `--test=s1_balance_defaults`). Keep both in sync, as `CLAUDE.md` says.
- **Never run the generator against `data/`** to check it: run it with
  `-- --out=<scratch dir>` (or let the test do it in `user://polish6_s1_data_gen`, removed after).
  Into `data/` it rewrites `balance.tres` without the lines equal to their defaults and gives the
  two `heated_*.tres` new ext_resource ids: churn, no value change.
- The generator is a `SceneTree` script with static `build()` (path → Resource) and
  `generate(out_dir)`; `tests/test_polish6.gd` reaches it through `const _S1DataGen := preload(…)`.
- `tests/test_polish6.gd` exists (suite `polish6` in `tests/test_runner.gd`), `extends RefCounted`
  with `var runner`, no world of its own; each section adds its tests under a
  `# ====` `§N` header, helpers prefixed `_sN_`.

**From §2 (the Godot errors after pulling):**
- **The cause:** after a pull, the editor's class list (`.godot/global_script_class_cache.cfg`) is
  the old one until its first scan. Before that scan the editor compiles `icons.gd` (it looks up a
  type named `Icons`), and any class name the old list lacks is a parse error there. CI's clean
  import never sees it; the new CI step (*Upgrade import*, after the suite) does.
- **Rule for every later section** (stricter than `CLAUDE.md`'s line, which is necessary but not
  enough): a **new `class_name`** added in this round is referred to through
  `const _<Class> := preload("res://…")` by every script that existed before it, and also by every
  script such a preload loads. That includes the new class's own file if it names itself (write
  `_<Class>.new()`, as `tool_icons.gd` does, not `<Class>.new()`). A preload compiles what it loads,
  so a global name anywhere along the chain fails the same way (report/s2.md: 3 errors became 16
  when only the old scripts were changed). Simplest: don't add a `class_name` unless needed. If you
  do, never use its global name outside its own file, and not inside it either.
- **Round 5's nine classes** (`AddressSigns`, `Buildings`, `Equipment`, `HeatedPad`, `Heating`,
  `ItemUpgrades`, `SidewalkCrew`, `SpeedControl`, `ToolIcons`) are reached by preload in the 25
  scripts listed in `S2_HARDENED` (`tests/test_polish6.gd`). `test_s2_round5_classes_by_preload`
  fails if one of those scripts names one of the nine by its global name in code. When you edit
  those scripts, use the `_Equipment`, `_ItemUpgrades`, … constant already at the top (add one if
  the script lacks it). Other scripts (new in round 5 or 6) may use the global names: every cache
  since `1b38f4a` has them.
- **Checking an upgrade locally:** in a scratch clone, import the base, `git checkout -f <head>`
  keeping `.godot/`, import again. The step's `run:` block is plain bash (`bash -eo pipefail`),
  with `BASE_SHA` and `RUNNER_TEMP` set. Set `APPDATA` to a scratch folder for `run_log`, so the
  owner's saves are left alone.
- The `.import` files' LF rewrite is not a change (staging records nothing): never commit it as
  one, and don't add a `.gitattributes` without the owner.
