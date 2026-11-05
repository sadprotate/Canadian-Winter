# Canadian Winter — instructions for every agent

A single-player, first-person snow-removal / cozy-business / winter-survival game in **Godot 4.7.2,
GDScript only, GL Compatibility renderer**. Everything is procedural: meshes (`MeshKit`), materials
(`shaders/`), sounds (`tools/audio/gen_audio.py`), icons and the photo (rendered in-engine). The
owner plays it on Windows (Godot 4.7.2 mono, GitHub Desktop) and merges every PR themselves.

## Before you change anything
1. Read this file, then `HANDOFF.md` (architecture, the snow system, boxes, weather, tools,
   balance, tests, known issues), then the current round's brief and status:
   `docs/polish<N>/POLISH_ROUND_<N>_PROMPT.md` and `docs/polish<N>/STATUS.md` (the highest N).
2. The brief's **Decisions** and **Ground rules** are binding. Do only what it lists.
3. Check you can work: `godot --version` (4.7.2), the import, `parse_all`, one suite (commands
   below). If the environment is missing something (Godot, network, `xvfb-run`, push access), tell
   the owner what to enable; don't work around it.

## Don't change the game
- Implement exactly what the current brief lists, the way the game already does things. No
  refactors, renames, reformatting, rebalancing, restyling, new dependencies, or engine and
  renderer changes. If something else looks wrong, note it in the report and leave it alone.
- Build on the existing systems (`Snow`, `Boxes`, `Clock`, `Contracts`, `Settings`, `Saves`,
  `Buildings`, `Catalog`, the computer's apps), never beside them.
- If an item can't be done without breaking something that works, revert that item and report
  it. A working game with a partly done list beats a broken one.
- Player-facing text: short and functional.

## Commands (from the repo root)
- Import (after adding or renaming a script or `class_name`):
  `godot --headless --path . --editor --quit`
- Parse check: `godot --headless --path . res://tests/parse_all.tscn` (exit 0 = clean)
- Tests: `godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn -- --only=<suite> [--test=<name part>] [--verbose]`.
  The suites are listed in `tests/test_runner.gd`. The full run takes a while, so iterate with
  `--only` / `--test`.
- Screenshots: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 res://tests/shot.tscn -- --scene=game --out=<png> [options]`.
  The options are documented at the top of `tests/shot.gd`. Look at every shot you take.
- On the owner's Windows PC there's no `xvfb-run`: run the same `godot … shot.tscn` command
  without it (a window opens briefly).
- Benches: `grind_bench`, `click_bench`, `contract_bench`, `perf`, `depth_report`, `weather_truth`,
  `forecast_audit` (`tests/*.tscn`).
- **Never run two Godot processes at once** (tests have segfaulted under concurrent runs).
  `perf.tscn` is a timing benchmark: nothing else may run while it does.

## How work is done here
- Work comes in polish rounds. One branch per round (`wc-polish<N>`) from `main`, one commit per
  section (`polish<N> §<k>: <title>`), and one report per section in `docs/polish<N>/report/`.
  Keep `docs/polish<N>/STATUS.md` current.
- A PR to `main` carries the checklist. CI (`.github/workflows/ci.yml`: clean import, parse check,
  the full suite, and the upgrade import that round 6 §2 adds) must be green before a section is ticked.
- **Never push to `main` and never merge.** The owner merges.
- Every visual change gets a before/after screenshot pair (1280 px JPEG) in
  `docs/polish<N>/shots/`.

## Rules the code depends on
- **Snow volume is conserved exactly.** The only exceptions are ledgered: box completion (the last
  ≤ 10 % at the 90 % snap), melting (`Snow.melted`), the dump truck, and setup/debug fills. Never
  loosen a tolerance to make a test pass.
- **The weather that falls is fixed.** `weather_truth` must stay identical; only the forecasts may
  change, and only when a brief says so.
- **Randomness.** Anything new that's random gets its own seeded `RandomNumberGenerator`. Never call
  the global `randf()` / `randi()` in new code, and never add or reorder draws in an existing
  stream.
- **Time.** `Clock` is the only clock; never hard-code its rate. Anything that runs on the clock
  steps inside its per-step tick, so 1×, 2× and 10× give identical results.
- **Input.** Every action is in `Settings.ACTIONS` (rebindable, conflict-checked). World-changing
  presses go through `Settings.accept_press()`. Every key shown to the player comes from
  `Settings.action_label()` / `Settings.with_keys()`. Anything that reads keys checks
  `Game.typing()`.
- **Buildings.** New buildings call `Buildings.register()`. Snow work checks
  `ToolController.can_work_at()`.
- **Saves** are version 3: migrations in `Saves`, the atomic write and `.bak` untouched, every new
  key optional with a safe default and added to the v3 round-trip test. Derive state where you can.
  Fast-forward is never saved.
- **Balance values** live in `data/balance.tres` and the defaults in
  `scripts/data/balance_data.gd`; keep them in sync. Use `tools/data_gen/generate_data.gd` only if
  it reproduces the current data exactly.
- **New scripts:** run the import so their `.uid` is generated, and commit it. A script that
  existed before a `class_name` was added refers to that class through a `preload` constant: the
  editor's class cache on the owner's PC can be stale after a pull.
- **Render-to-texture:** a `SubViewport` renders once or when its content changes, never per frame,
  with a headless fallback.
- **Quitting:** `AudioMgr.quit(code)`, never `get_tree().quit()`.
- **Tests:** new tests go in the round's suite. A test that asserts behaviour a brief deliberately
  changes is updated through lookups (layout, balance, `Clock`), never deleted, skipped or
  loosened. Don't touch unrelated tests.

## For the owner
- After a merge: close Godot, pull in GitHub Desktop, reopen. If the editor shows "not declared in
  the current scope" errors after a pull, close Godot, delete the project's `.godot` folder and
  reopen it.
- In game: **F1** is the developer menu (money, weather, time jumps). The living-room plant gives
  $1,000 per press; it's a test feature to remove before release.
