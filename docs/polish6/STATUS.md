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
| §2 | The Godot errors after pulling | done | `c17cbe5` | `report/s2.md` |
| §3 | Round 5's open items | done | this commit (`polish6 §3: Round 5's open items`) | `report/s3.md` |
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
- **Older saves settle once on load (§3), and a mid-winter one takes a while.** A save from before
  §3 has no relaxation queue, so it is settled on load. The polish5_v3 mid-winter fixture takes
  ~5 s; round 5's `polish5/*_4_midwinter.json` (built with F1 multi-day jumps) ~75 s headless,
  ~63 s windowed. The menu shows "Settling the snow…" and stays responsive. Settled, that fixture's
  Maple Street lanes fill in (V-shaped, ~0.9 m of snow in the lanes in front of the house): its 6 m
  cliffs come down at load instead of at the first nearby snow work. Every suite that loads those
  two fixtures is ~75 s slower per load (report/s3.md). Tell the owner in the PR description.
- **F1 multi-day jumps run several city passes with no relaxation between them** (`Clock.skip`
  never relaxes): that, as well as the lost queue, built the round-5 fixture's 6 m cliffs. Not
  changed (§3 saves the queue; a skip still relaxes only afterwards). A later section could relax
  after each batch pass during a skip.
- **Tools dropped into deep snow in an older save** are lifted onto the snow on load (§3). Before,
  a dropped tool was placed on the ground under the snow with its grip showing.
- The FPS overlay line (Settings → graphics) is long enough to run under the map's left edge at
  16:9 (seen in §3's shots; pre-existing, not changed). On a 4:3 screen (1920 × 1440 canvas) the
  clock panel, and the fast-forward control under it, overlap the map's frame: pre-existing for
  the clock. §3 checked the four resolutions round 5 uses (16:9 and 21:9).

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

**From §3 (round 5's open items):**
- **Saves (version 3, optional, inside `snow`):** `"relax": {"hot": [tile…], "cold": [tile…]}`,
  the relaxation still pending in the order it runs (the hot list from its read index, then the
  cold stack), and `"push_rng"`, blade_push's stream state **as a string** (a 64-bit value: a JSON
  number would lose bits). Both come from `Snow.serialize_pending()`, merged into the save's snow
  by `Saves.save_game()`. `Snow.serialize()` itself is unchanged (tests hash it). Both are in the
  v3 round-trip test (`test_s7_v3_save_round_trips`). New snow state that must survive a reload
  goes the same way.
- **A save without `"relax"` is a pre-§3 save.** `Snow.deserialize` sets `Snow.settle_on_load`,
  and `Saves.load_game` (after the boxes' held cells are back) settles the whole map:
  `Snow.settle_all()`, or `Snow.settle_begin()` when `Saves.settle_later` is set (the main menu
  then steps it with `Snow.settle_step(usec)` behind "Settling the snow…"). The settle is the
  game's own relaxation rule and order; only its requeue threshold differs (`Snow.SETTLE_MOVED_MIN`,
  1 mm per tile: the sub-millimetre tail is left to the game's relaxation). The same marker lifts
  old saves' dropped tools onto the snow. A later migration keyed on "older than §3" can use it.
- **Settling costs** ~18,000–26,000 tile visits/s headless on this PC (measured with
  `--only=polish6`: `settle_all` in `Saves.load_game`, the load included, 1,122,600 tiles in
  61.4 s on `polish5/fun_4_midwinter.json` and 101,227 in 3.9 s on
  `polish5_v3/fun_4_midwinter.json`; the menu's stepped settle 25,500 tiles/s on the latter). A
  mid-winter save with cliffs to bring down can take a minute. Never settle the whole map in a
  frame or a test loop without need. A test that loads `polish5/*_4_midwinter.json` pays
  ~60–75 s per load.
- **The main menu starts one game at a time:** `_start` returns at once while a start is under way
  (`_starting`, cleared only if the load fails) and releases the keyboard focus, so Enter or Space
  can't load and settle a save a second time behind the loading screen
  (`test_s3_menu_starts_once_while_settling`). A new way to start a game from the menu goes
  through `_start`.
- **`Snow.blade_push` draws from `Snow.push_rng`** (seeded `PUSH_SEED + year` in
  `reset_for_winter`, `PUSH_SEED` at start and for old saves; saved). No snow op reads or advances
  the global RNG any more. A test that wants a known push seeds `Snow.push_rng`: seeding the global
  RNG does nothing for pushes now. §9's and §11's blade work (smooth piles, back-drag) draws from
  `push_rng` or its own seeded stream, never the global one, and keeps blade_push's one draw per
  moved cell.
- **Weather cards:** `Weather.held_dry(h)` is true for the hour now when a forced condition
  (`Weather.force`, F1) holds the sky dry. A today card's system that is due to be snowing now
  while the sky is held dry moves its start to the next hour (`forecast_day`). In play (no
  override) it changes no card (0 of 6,581 today cards, 5 seeds × winters 1–3). **§13's radar must
  agree with the moved start time:** its "now" frame shows what is falling now
  (`Weather.condition()` / `snow_rate()`, override included), it shows no echo over the town before
  the today card's start time, and past frames show what fell. §7's visuals likewise read
  `Weather.condition()` / `snow_rate()`.
- **Store text:** `ToolData.store_description()` is the store's tool text (`{width}` from the
  profile, e.g. "1.0 m", then the bound keys). §13's phone store uses it (one implementation with
  the computer's). A description may name its blade with `{width}`; nothing else replaces it.
- **Tools lying in the world:** `ToolItem.rest_height(id)` puts each model's lowest point on the
  item's origin (the pose is unchanged: tilted `LIE_TILT_DEG` 28°, grip end up). A tool put down
  rests on the snow: `game_root.spawn_tool_item` sets `pos.y = Snow.surface_height()`, and so do
  the store pad and F1's spawn. **New code that creates a tool item** (§15's garage, §16) sets
  `pos.y` to the surface, or `"buried": true` with `y` on the ground. The 75 % exposure rule is
  unchanged; the opening's shovel now lies on the ground, so it is dug out ~0.45 m deeper.
- **The fast-forward control** sits beside the clock unless that spot is taken (the map is open,
  or the box line reaches it); then it sits under the clock, below the objective and FPS lines,
  its note wrapped to the buttons' width (`SpeedControl._beside_taken`, `_place`). **§13:** the
  phone is a fast-forward modal. If its frame covers the spot beside the clock, add it to
  `_beside_taken`, and add the phone to `test_s3_ff_control_overlaps_nothing`'s screens.
- **For §10: the dump truck shares the pickup-with-plow's code path.** In
  `Vehicle._physics_process` only `Kind.PICKUP` takes round 5's §12 branch
  (`pickup := data.kind == VehicleData.Kind.PICKUP`: `pickup_stuck_depth` 0.60, `pickup_bank_max`
  0.95, the bog and the shove). Every other vehicle, `PICKUP_PLOW` and `DUMP_TRUCK` alike, uses the
  generic path: stuck above `clearance × 1.15`, a wall above `clearance × 1.9`, drag from depth ÷
  clearance, no shove. The pickup with plow (clearance 0.34, blade up) is stuck from 39 cm and
  walled from 65 cm; the dump truck (0.42) from 48 / 80 cm. A fix that extends the PICKUP branch to
  `PICKUP_PLOW` leaves the dump truck out unless it names it too.
- `shot.gd` options: `--win=WxH` (the canvas a W × H screen gives, letterboxed in the window; the
  shot window can't be resized on this PC), `--load=path` (a save instead of a new game),
  `--street_scoop=1` (§3's scoop by Maple Street's curb, then settled).
- **Tests §3 updated through lookups:**
  - The polish 4 and polish 5 fixture tests stand the player with `_road_spot()`: 4 m out from
    the lot as before, unless a settled bank covers it (pass 4's storm and round 5's mid-winter
    fixtures). Then they use the first point further out under half the hip height.
  - `test_hidden_shovel_beside_truck` digs to the height the shovel rests at, the ground.
  - A later change to where the player or the opening's shovel stands updates these the same way.
- **Suite times after §3:** polish5 ~1,050 s (was ~840 s); polish6 ~160–180 s, of which §3's
  settling test is ~140–175 s and the menu's one-start test ~5 s.
