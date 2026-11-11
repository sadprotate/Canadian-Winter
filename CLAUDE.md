# Canadian Winter — instructions for every agent

A single-player, first-person snow-removal / cozy-business / winter-survival game in **Godot 4.7.2,
GDScript only, GL Compatibility renderer**. Everything is procedural: meshes (`MeshKit`), materials
(`shaders/`), sounds (`tools/audio/gen_audio.py`), icons and the photo (rendered in-engine). The
owner plays it on Windows (Godot 4.7.2 mono, GitHub Desktop).

How the game is meant to play is in @GAME.md. Every change must fit it. If you notice the game
doesn't match GAME.md, don't fix it unless the brief asks. Note it under `## Issues` in STATUS.md.

Work comes in polish rounds. The goal is to get through each round quickly: test what each section
changes, not the whole game. After every round, the owner and a group of human players playtest the
game, so you don't need to playtest everything yourself.

## Git rules (always)
- Never commit or push to `main`. All work happens on the round's branch.
- Never force-push, and never discard uncommitted changes. If something in git looks wrong, stop and ask.
- Never open a PR until the owner says the playtest is approved.
- Never merge a PR or delete a branch until the owner explicitly says to.

## Starting a round
1. The owner's prompt gives the round number N. If it doesn't, ask before doing anything.
2. Switch to `main`, pull, and check that `git status` is clean. If it isn't, or the previous
   round's branch was never merged, stop and ask.
3. If the branch `cw-polish<N>-pg` already exists, locally or on GitHub, don't create, reset or
   replace it. Tell the owner what's on it and ask what to do.
4. Create `cw-polish<N>-pg` from `main` (for example `cw-polish7-pg`: all lowercase, no dash between
   "polish" and the number). Older rounds used `wc-polish<N>`; leave those as they are.
5. The brief is `docs/polish<N>/POLISH_ROUND_<N>_PROMPT.md`. If it isn't in the repo yet, save the
   owner's prompt there. Its **Decisions** and **Ground rules** are binding. Do only what it lists.
6. In `docs/polish<N>/STATUS.md`, list one checklist line per section of the brief, then three
   empty headings: `## Questions`, `## Check at the end`, `## Issues`.
7. Read every section and the code it touches. For each feature it touches, read its doc in
   `docs/features/`. For a feature with no doc yet, read only the part of `HANDOFF.md` that covers
   it; never read all of HANDOFF.md. Check each section against GAME.md.
8. Check you can work: `godot --version` (4.7.2), the import, `parse_all`, one suite (commands
   below). If the environment is missing something (Godot, network, `xvfb-run`, push access), tell
   the owner what to enable; don't work around it.
9. Ask all your questions in one message before starting: anything unclear, any design choice, and
   anything that seems to go against GAME.md. Wait for the answers, record them in STATUS.md, then
   start. If you have no questions, start right away.

## Questions during the round
- Only ask about things you can't figure out from the code, the feature docs, HANDOFF.md or
  GAME.md: design choices, how something should feel, priorities.
- If a wrong guess would be hard to undo or would affect other sections, stop and ask right away.
- Otherwise, write the question under `## Questions`, move that section to the end, and keep going.
- When all the other sections are done, ask the saved questions in one message and wait for the
  answers. Then finish those sections before the final check. Don't drop a section because it had
  a question.

## Working through the sections
- Do the sections in order, one at a time. If one depends on a later one, do that one first.
- Don't stop between sections to ask for approval. Finish one, then start the next.
- When a section is done: update the docs of the features it changed, tick it in STATUS.md with one
  line (what changed, what you tested), write its short report in `docs/polish<N>/report/`, and
  commit it all as `polish<N> §<k>: <title>`.
- If you notice something broken outside the current section, note it under `## Issues` and keep
  going, unless it blocks the next section.
- If a bug isn't fixed after 3 attempts, stop working on it. Write it under `## Issues` with what
  you tried, and move on. An attempt is a different fix that you then test; re-running the same
  check or command doesn't count.
- If a section can't be done without breaking something that works, revert that section and report
  it. A working game with a partly done list beats a broken one.

## Don't change the game
- Implement exactly what the brief lists, the way the game already does things. No refactors,
  renames, reformatting, rebalancing, restyling, new dependencies, or engine and renderer changes.
  If something else looks wrong, note it under `## Issues` and leave it alone.
- Build on the existing systems (`Snow`, `Boxes`, `Clock`, `Contracts`, `Settings`, `Saves`,
  `Buildings`, `Catalog`, the computer's apps), never beside them.
- Search for the specific function, class or signal before opening files. Read only what the
  current section needs, and don't re-read large files that haven't changed.
- Player-facing text: short and functional.

## Feature docs
- `docs/features/` has one Markdown file per feature (for example `shovel.md`, `snow.md`,
  `contracts.md`, `tutorial.md`). They're how the next round knows how each feature is supposed to
  work, so keep them accurate.
- Each doc covers: what the feature does for the player; how it's supposed to work (rules and edge
  cases); where it lives in the code; which systems it connects to; how to test it (suites and test
  names); decisions (one line per change, with the round and why); known issues.
- Describe how the feature works now. When it changes, rewrite the parts that changed rather than
  adding notes at the bottom. Keep each doc short.
- Refer to balance values by their name in `data/balance.tres`; don't copy the numbers.
- When a section changes a feature, update its doc in the same commit. If the feature has no doc
  yet, create one from the code and the part of HANDOFF.md that covers it.
- If a doc and the code disagree, note it under `## Issues`.

## Testing after each section (most important rule)
Test only what the section touched:
1. The parse check (run the import first if you added or renamed a script or `class_name`).
2. The suite for each system you changed, using `--only=<suite>` and `--test=<name part>`.
3. Code that directly calls or shares what you edited. Find it by searching for the functions,
   classes or signals you changed, and run its tests too.
4. A screenshot only if the section changes how something looks and a test can't check it (see
   Screenshots).

Don't re-run a test that already passed unless the code it covers has changed since. Sections that
touch the same code can be done together and tested once.

Between sections, do NOT:
- run the full suite, or push and wait for CI
- run a bench unless the section is about what that bench measures
- re-test systems the section didn't touch (the tutorial, vehicles, menus…)
- play through the game

Example: a section increases the snow picked up by the shovel → run the shovel and snow tests. Don't
test the truck, bike or tutorial unless they share that code.

### Risky changes
If a section changes shared or core code (`Snow`, `Saves`, `Clock`, weather, scene loading, global
game state):
- If later sections in this round build on that change, test the affected systems right away, so a
  bug doesn't spread into later work.
- Otherwise, test only the parts that use what you changed, and add a line under
  `## Check at the end` saying what changed and what it could affect.

## Screenshots
Screenshots are slow. Prefer tests, and leave most visual checking to the human playtest.
- Take a screenshot only when you need to see the result: a new or moved object, a UI layout, a
  visual effect. Never to check logic, numbers or behaviour a test can check.
- One "after" shot is usually enough. Take a before/after pair only when the point of the section
  is to change how something looks.
- No more than 2 shots per section. If you really need more, write why in STATUS.md.
- Don't re-take a shot unless the code it shows has changed. Look at every shot you take.
- Keep a shot in `docs/polish<N>/shots/` (1280 px JPEG) only if it's worth keeping as a reference
  for later rounds. Don't commit the rest.

## Commands (from the repo root)
- Import (after adding or renaming a script or `class_name`):
  `godot --headless --path . --editor --quit`
- Parse check: `godot --headless --path . res://tests/parse_all.tscn` (exit 0 = clean)
- Tests: `godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn -- --only=<suite> [--test=<name part>] [--verbose]`.
  The suites are listed in `tests/test_runner.gd`. The full run takes a while, so iterate with
  `--only` / `--test`.
- Screenshots: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 res://tests/shot.tscn -- --scene=game --out=<png> [options]`.
  The options are documented at the top of `tests/shot.gd`.
- On the owner's Windows PC there's no `xvfb-run`: run the same `godot … shot.tscn` command
  without it (a window opens briefly).
- Benches: `grind_bench`, `click_bench`, `contract_bench`, `perf`, `depth_report`, `weather_truth`,
  `forecast_audit` (`tests/*.tscn`).
- **Never run two Godot processes at once** (tests have segfaulted under concurrent runs).
  `perf.tscn` is a timing benchmark: nothing else may run while it does.

## Final check (once, after every section is done)
1. Clean import, parse check, then the full suite, once.
2. If the round touched weather, run `weather_truth` (it must stay identical).
3. Test everything listed under `## Check at the end`.
4. Fix only problems this round caused. After each fix, re-run only the tests related to that fix.
   Problems that were already there go under `## Issues`. The 3-attempt limit applies here too.

Don't play through the whole game. The human playtesters do that next.

## End of the round
1. If this round added or changed a feature, update its line in "What's in the game now" in
   GAME.md, with a link to its doc. Don't change any other section of GAME.md without asking.
2. Write a playtest checklist to `docs/polish<N>/PLAYTEST.md`: a short list of specific things for
   the human testers to try, based on what changed. Example: "Shovel a full driveway and check that
   each scoop picks up more snow than before."
3. Commit and push the branch.
4. In your final message, report: sections completed and any not finished (with why), files and
   systems changed, what was tested and what couldn't be, known bugs or risks (everything under
   `## Issues`), and the playtest checklist.
5. Stop and wait for the playtest results.

## After the playtest
If the owner reports bugs from the playtest: fix them on the same branch, test each fix, update the
feature docs if needed, commit, push, and update PLAYTEST.md with what to re-check.

When the owner says the playtest is approved:
1. Open a PR from the round's branch to `main`, titled `Polish <N>`, carrying the STATUS.md
   checklist and your end-of-round report.
2. Wait for CI (`.github/workflows/ci.yml`: clean import, parse check, the full suite, and the
   upgrade import that round 6 §2 adds). If it fails, fix it on the branch, push, and wait again.
   If it still fails after 3 attempts, stop and tell the owner.
3. Tell the owner the PR is ready and whether CI passed, then stop.

When the owner says to merge: merge the PR, switch to `main`, pull, and confirm `git status` is
clean. Keep the round's branch unless the owner says to delete it.

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

## Honesty
Never say something was tested unless a test was actually run.

## For the owner
- After a merge: close Godot, pull in GitHub Desktop, reopen. If the editor shows "not declared in
  the current scope" errors after a pull, close Godot, delete the project's `.godot` folder and
  reopen it.
- In game: **F1** is the developer menu (money, weather, time jumps). The living-room plant gives
  $1,000 per press; it's a test feature to remove before release.
