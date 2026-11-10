# Polish round 6 — status

The brief is `docs/polish6/POLISH_ROUND_6_PROMPT.md`; section agents also read
`docs/polish6/WORKING_BRIEF.md`. This file is kept current after every section so the work can
resume from here.

## Where things stand

- **The round stopped after §8.1b** (the owner, 2026-11-10). §0–§3, §8.1, §8.2, §9 and §8.1b are
  done. Everything else is carried over to a later round: see *Round 6 stopped after §8.1b*
  below.
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
| §3 | Round 5's open items | done | `5287dfe` | `report/s3.md` |
| §8.1 | Hold to fill, not spam-click | done; its decision (the recoveries against holding) was taken by the owner (option C) and carried out in §8.1b. Two things still for the coordinator to accept: tests whose inputs changed, and shallow-snow sweeps taking more than before (see open items). Amended after two reviews | `f10a4cf` | `report/s8_1.md` |
| §8.2 | Loads twice as big | done; the coordinator accepted its open readings (*Accepted by the coordinator*, below): the standard shovel carries ×1.6 a stroke in 40 cm with the bot, not ×2 (×1.85 in 80 cm); bare hands' capacity levels +75 % each; the base large scraper passing the electric shovel by 5 %. Amended after review (the load visual) | `677c686` | `report/s8_2.md` |
| §9 | Smooth piles | done; the coordinator accepted its readings (see open items). Amended after review: emptied cells lose their marks, the band test, the perf reading corrected (the plow truck pushing a berm +13 %) | `b415fdd` | `report/s9.md` |
| §8.1b | Pause spaces throws (the owner's decision on §8.1) | **done.** The owner's second decision ("Bare hands 30% faster", open items) closed the last Done-when item: bare hands' fill rate ×1.3 (0.1105), grind_bench 0.0374–0.0378 m³/s in 120 s (within 0.5 %) and the path box in 199.1–204.9 s over five runs (mean +4.1 %; two of five over 5 %, +5.3 % and +5.7 %: accepted by the coordinator as run-to-run spread, its cause carried over); the ladder now sells one of bare hands' two capacity levels, old saves keep both. The coordinator accepted the third review's readings (open items). Amended after two reviews: a throw (not a fresh load) renews the bites; a press the cap refuses no longer cancels a waiting throw; one due indoors is kept without an error; a waiting throw lands where the release aimed (the ring stays there); a release inside the recovery with nowhere to land or indoors is refused at once; the stale "Full — release to throw." clears | `f34dfd9` | `report/s8_1b.md` |
| §10 | The plow truck from the start | not started: **carried over** to a later round (the owner, 2026-11-10) | | |
| §11 | Blade up/down, push and pull | not started: **carried over** | | |
| §7 | Weather you can see and hear | not started: **carried over** | | |
| §13 | The phone and the radar | not started: **carried over** | | |
| §12 | Every key rebindable | not started: **carried over** | | |
| §14 | Cold nights | not started: **carried over** | | |
| §15 | The garage | not started: **carried over** | | |
| §16 | The commercial property | not started: **carried over** | | |
| Part 4 | Checks, play-through, HANDOFF, report | not started: **carried over** | | |

## Round 6 stopped after §8.1b: carried over to a later round

On 2026-11-10 the owner asked to finish the work under way and start nothing new. The sections not
started move to a later polish round. In the owner's words: "finish what you are doing the tasks
you're under and don't proceed to a new tasks … we'll take whatever task you haven't done and bring
them back in a different polish."

- **Last code commit:** `f34dfd9` (§8.1b). §10's agent had begun reading when the run was stopped.
  It changed nothing, and the tree was clean afterwards.
- **Local CI at `f34dfd9`** (this PC):
  - import clean; `parse_all` 91 scripts, 0 errors
  - snow 13/13, systems 28/28, gameplay 41/41, polish4 19/19, polish5 87/87, polish6 32/32
  - polish3 20/21: the known load-dependent `test_menu_fixture_load_is_the_same_as_direct`
    failed (open items), then passed alone
  - `weather_truth` byte-identical to the baseline
- **Nothing is pushed** and there is no PR. The branch is `wc-polish6-pg`, local.

### Not started: bring back as written in `docs/polish6/POLISH_ROUND_6_PROMPT.md`

The order this round planned, top to bottom. "Brief lines" are line numbers in the brief.

| § | Title | Brief lines | Decisions | Notes for the next round |
|---|---|---|---|---|
| §10 | The plow truck from the start | 636–678 | 3 | The old-save fixture is ready: `tests/fixtures/polish5_v3/7_keys_pickup_plow_order`. Keep §9's blade deposit (spread band, `Snow.soft` marks, one `push_rng` draw per moved cell). |
| §11 | Blade up/down, push and pull | 679–709 | 4 | After §10. Back-drag through `Snow.blade_push` keeps §9's band and marks (Decision 2 includes back-drag). |
| §7 | Weather you can see and hear | 446–498 | 8 | `weather_truth` must stay byte-identical (SHA-256 `173434ae6cb718c401272e758e3875bcf9594f46c14a2a8697bde2f0ae5ee30b`). |
| §13 | The phone and the radar | 738–794 | 6, 7 | |
| §12 | Every key rebindable | 710–737 | 5 | After §11 and §13: it covers `veh_blade_up`, `veh_blade_down` and `phone`. |
| §14 | Cold nights | 800–809 | 9 | Round 5's §14 as written, plus the updates. The starting truck's cab assumes §10. |
| §15 | The garage | 810–823 | 9 | Assumes §10 and §11 (the plowed truck, back-drag from the door) and §7 (no flakes inside). |
| §16 | The commercial property | 824–835 | 9 | |
| Part 4 | Checks, play-through, screenshots, HANDOFF 9e/9f, report, PR description | 836–889 | | Much of its list assumes §7 and §10–§13. For the work done so far: HANDOFF needs its pass-6 notes. Its §7 tool table still shows round 5's values, e.g. bare hands fill 85 L/s at HANDOFF lines 218 and 339, now 110.5. The PR description is also still to write. |

### Open items to carry with them

Details are under *Open items* below.

- **Needs the owner:** RMB click-push can beat holding in deep snow (§8.1). Changing it changes
  push behaviour, which this round protects. For example, a push could start only from a held
  press.
- **Needs the owner:** pushing the two baseline tags, the `build/windows/` folder for exporting,
  and an optional `.gitattributes` line.
- **grind_bench varies run to run since §9.** The path box takes 199–205 s against the baseline's
  steady 193.9 s: mean +4.1 %, two of five runs over 5 %.
  - Likely cause: the relaxation's per-frame time budget (`Snow.process_relax(…, max_usec)`),
    which §9's costlier tiles reach more often. Not traced.
  - Worth checking whether anything besides the bench depends on frame timing.
- **The dig-out test's bot is marginal** (gameplay `test_dig_out_by_hand_after_a_major_event`).
  Its sweep rate now scales with bare hands' fill rate.
- **polish3's `test_menu_fixture_load_is_the_same_as_direct` is load-dependent.** It failed again
  in the final full run and passed alone. The fix is to wait for the start, not 30 frames.
- **§9:** an emptied cell keeps its player-moved mark until its chunk syncs (at most 3 game hours).
- **§8.1b, cosmetic:**
  - the follow-through pose after a very short stroke
  - a throw that waits spawns from the facing stored at the release
- **Upgrades app, cosmetic:** an old save with bare hands' level 2 still on order shows
  "Level 1 / 1 · Fully upgraded", without "On order.", until the crate is collected.
- **§3:**
  - F1 multi-day jumps don't relax between city passes.
  - Round 5's mid-winter save settles for about 75 s on load.

### Accepted by the coordinator (2026-11-10)

Each section left some readings "for the coordinator". They are taken as committed so the round
can stop cleanly, and any of them can be revisited.

- **§8.1:**
  - Nine tests had their inputs changed; since §8.1b, eight are back to their old inputs.
  - Shallow snow: a held sweep in 6 cm takes up to 25 % more than before.
- **§8.2:**
  - The standard shovel carries ×1.6 a stroke in 40 cm with the bot (×2 when swept until full).
  - Bare hands' capacity levels are +75 % each.
  - At base, the large scraper passes the electric shovel by 5 %.
  - The load mesh is turned half a segment.
- **§8.1b:** the path-box time's run-to-run spread (its cause is carried over, above).
- **§9 and §8.1b's third review:** the readings already listed under *Open items*.

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
- **§8.1's decision: resolved by §8.1b** (`report/s8_1b.md`; §8.1's measurements and options A–D
  are in `report/s8_1.md`, *Decision needed*).
  - **The owner's decision (option C)**, as the coordinator relayed it. It amends Decision 10's
    "after a throw it needs a recovery time before it can scoop again" and §8.1's "No scoop can start
    until it ends" / "Presses during recovery are ignored":
    the recovery after a throw only spaces out throws. In the owner's words, as agreed, after a
    throw:
    > "you can start scooping again right away, but the next throw waits until the pause is over.
    > Spam-clicking still can't beat holding, and a fast shoveller loses nothing."
  - **A human rhythm loses nothing** (§8.1's second unmet item). Snow taken in and thrown per second,
    hold 0.6 / 0.9 / 1.2 s with 0.3 s and 0.7 s between strokes, round 5's loads: −1 % to +15 %
    against the baseline, every tool and row (§8.1: down to −63 %). With §8.2's loads +50 % to
    +108 %. The claim rests on that intake: the box's "removed" figure scatters ±20 % and more (where
    thrown snow lands, and the rows run before it in the same command; the sleigh's 1 m throws land
    back on the walkway, §8.2's matter), so it is compared only within one command (second review).
    A shoveller who turns straight back to the snow after the release loses nothing either (second
    review fix: a waiting throw lands where the release aimed).
  - **Clicking still never beats holding:** no click run throws (5–50/s, every tool), and throws
    stay at least `throw_recovery_s` apart everywhere.
  - **grind_bench within 5 % (§8.1's first unmet item): with the owner's second decision (below),
    met on the 120 s rate; on the box time on average, not in every run.** Bare hands: 0.0376 (baseline) → 0.0171 (§8.1, HEAD) → 0.0331 m³/s (§8.1b, −12 %; the
    box stalled 8 L short of 90 %) → **0.0374–0.0378 m³/s (within 0.5 %), the path box in
    199.1–204.9 s against 193.9 s (+2.7 % to +5.7 %, mean 201.9 s, +4.1 %)** with bare hands' fill
    rate ×1.3, five runs. **For the coordinator:** two of the five are over 5 % on the box time; the
    bench varies run to run in this build (the baseline: 193.8–193.9 s), most likely because the
    relaxation runs to a per-frame time budget (`Snow.process_relax(…, max_usec)`) that §9's costlier
    tiles reach more often. Not changed. The rhythm costs nothing (identical with
    `--recovery=0 --hold=0`); the gap was Decision 10's lost opening bite.
  - **A throw renews the bites — accepted by the coordinator (third review).** `_release_throw()`
    clears the re-cut memory (`_cut_time.clear()`, at most once a recovery; no press clears it). It
    rewrites §8.1's "Releasing and pressing again over the same cells doesn't renew their bite
    early" for a release that throws. In §8.1 the recovery (≥ 0.5 s, longer than `RECUT_S` 0.3 s)
    renewed every bite before the next scoop could start, so this matches §8.1's behaviour. The rule
    exactly as written stalled the grind bot at 0.004 m³/s. A load dropped at your feet, or any
    later way of emptying the tool, renews nothing (binding notes, §8.1b).
- **§8.1b: the owner's second decision — resolved, carried out** (report/s8_1b.md *The owner's
  second decision*). The question the owner answered, verbatim:
  > "The test bot that clears the front path with bare hands is now 12% slower than in round 5, and
  > the brief allows 5%. Your throw pause isn't the cause: it costs the bot nothing. The cause is
  > §8.1's rule that a click no longer grabs a free half-scoop. The only fix is to make bare hands
  > fill 30% faster, but then fully upgraded hands match the small shovel, so one of the two hand
  > upgrades drops out of the store and two tests about the upgrade order must change."

  The answer, verbatim:
  > "Bare hands 30% faster"
  - Bare hands' `fill_rate` 0.085 → **0.1105** (`data/tools/hands.tres`, the generator). No balance
    value changed. grind_bench as above.
  - **The store:** the ladder that already exists sells **one** of bare hands' two capacity levels
    (two would fill 338 L/s, 1.30 × the small shovel's base, past the 15 % slack); level 1 at its old
    price ($2), shown "Level 0 / 1", then "Level 1 / 1 · Fully upgraded". Bare hands' other tracks
    (throw 2, push width 1, push power 1) and every other item's levels are unchanged. Fully
    upgraded, bare hands now carry 52.5 L and fill 193 L/s (0.52 and 0.74 of the small shovel).
  - **Old saves that own both levels keep both, and both work** (as round 5's other levels past the
    ladder do): such hands carry 92 L and fill 338 L/s, faster than the small (260) and standard
    (320 L/s) shovels' base with a smaller load. The app shows "Level 2 / 2 · Fully upgraded". A save
    with level 1 only can't buy level 2 any more.
  - `test_s82_twice_the_load` and polish5's `test_s13_the_ladder` were updated through lookups, and
    two more tests the higher rate failed: polish5's `test_s6_blades_match_the_profiles` (bare
    hands' fill in the profile table) and gameplay's `test_dig_out_by_hand_after_a_major_event`.
  - **For the coordinator: the dig-out bot is marginal.** At 0.1105 its fixed motion stalled 0.6 m
    from the porch (what it threw came back into its trench as fast as it dug; the hands now filled
    near the far end of its one-way sweep). Its input now turns the sweep faster in proportion to
    bare hands' fill rate (`DIG_SWEEP_TUNED_FILL` 0.085, `_sweep_fill(…, step)`; other callers
    unchanged): 3.3 m (3.4 m before); the check is untouched. But it was marginal before too: at
    0.085, tossing at 1.3 rad instead of 1.4 stalls at 0.6 m (1.2, 1.5, 1.6 rad dig out). A bot that throws farther aside, or
    a less brittle dig-out check, is a later section's call (report/s8_1b.md).
- **§8.1b, accepted by the coordinator as a cosmetic open item (third review):** a stroke started
  within about 0.17 s of a throw and released before 0.42 s keeps the raised follow-through pose for
  the rest of the recovery; and a throw that waits and goes after the player turned spawns from the
  stored facing. Neither loses snow. Not changed.
- **§8.1b: where a waiting throw lands — resolved (second review).** It lands where the release
  aimed, and the ring stays there; a player who turns straight back to the snow no longer throws
  the load back in (`click_bench --turnback`: the review's −29 % to −77 % rows now within 3 % of the
  bot that stays turned).
- **§8.1, for the coordinator to accept: nine tests had their inputs changed, with their
  assertions untouched.** The Done-when says they "pass unchanged".
  - Directly: `test_indicator_at_pickup_then_landing_every_tool` (polish4) waits out the recovery
    (`_s81_recovered()`) before each press, and the partial-load block of
    `test_hands_sweep_fill_full_and_partial_throws` (gameplay) sweeps for `min_scoop_hold_s`
    (15 frames) instead of a 3-frame press. Their old inputs can't pass under Decision 10: the
    first relied on throws 35 frames apart, the second on the press's opening bite.
  - Through the shared stroke helpers that wait out the recovery: `_sweep_fill` (gameplay:
    `test_shovel_throws_onto_road`, `test_bigger_scoops_and_tool_ladder`,
    `test_box_outline_follows_work`, `test_snow_refinements`,
    `test_dig_out_by_hand_after_a_major_event`), `_shovel_to_snap` (polish3's play-through) and
    `_shovel_watching_indicator` (polish4's play-through). The first, third and fourth never
    actually wait (0 frames); the others wait at most 27 frames a stroke (report/s8_1.md *Tests*).
  - **§8.1b: eight of the nine are back to their old inputs.** With the scoop free during the
    recovery, every one of them passes without the waits, and none of their releases comes inside
    a recovery (0 waiting throws; measured with the waits removed and counted, report/s8_1b.md
    *The helpers' waits*). So `_s81_recovered()` is gone: test_polish3 and test_polish4 are as at
    `9be19a6`, and test_gameplay differs from it only in the partial-load block's
    `min_scoop_hold_s` sweep, which still can't go back (it needed the press's opening bite), and
    (the owner's second decision) the dig-out test's sweep rate, scaled to bare hands' fill rate.
- **§8.1, for the coordinator to accept: shallow snow.** The footprint fallback is capped at the
  opening bite's share a load (the second review's suggested fix), but the cap rarely binds: in
  snow too shallow for the tool to fill up within a second, a held sweep takes up to about a
  quarter more than before §8.1 (the standard shovel and the sleigh at 6 cm: +25 %), from up to
  four more cells. Deep snow is unchanged or less. Narrowing the fallback to the press point's
  cells matches before §8.1 but stalls `grind_bench` by the steps; that was tried and dropped
  (report/s8_1.md *Shallow snow*). `click_bench -- --rows=shallow` measures it; rerun it in §8.2.
- **§8.1: RMB clicking can push more than holding in deep snow** (round 5 found no gain; that
  holds for bare hands only).
  - In the opening's ~0.6 m path a held push stalls against its berm (speed × 0.01), while
    clicking lets the player wade on between pushes.
  - It varies from run to run, before and after §8.1 alike. The committed run's largest case was
    the small shovel at 5/s: 0.32 against 0.0066 m³/s pushed, 0.057 m³/s out of the box. The
    amended run's was the snow scraper at 5/s: 0.021 against 0.0011 m³/s out of the box.
  - Decision 10 says spam-clicking never beats holding "with any tool", but §8.1 protects push
    behaviour. A later section needs to own it, with the owner's OK to change push, for example
    so that a push starts only from a held press.
- **polish3's `test_menu_fixture_load_is_the_same_as_direct` is load-dependent** (not §8.1; from
  §3's settling or the menu).
  - The §8.1 review saw it fail in the full polish3 suite twice at the §8.1 commit and once at
    `5287dfe` (20/21; the test took 23–26 s). For `survival_4_midwinter`, the menu Continue's start
    hook didn't fire within `_menu_start`'s fixed 30-frame wait.
  - It passes alone (15 s), and it passed in the amended §8.1 run (11.3 s, 21/21).
  - A fix would wait for the start (or the stepped settle) to finish rather than 30 frames.

- **§8.2, decision needed (coordinator): the standard shovel in 40 cm carries ×1.6 a stroke** with
  the grind_bench bot, not ×2 (×1.85 in 80 cm; every other tool ×1.7–×2.1 in 40 cm, ×1.8–×1.9 in
  80 cm), so the Done-when "about 2× per stroke in snow ≥ 40 cm" is partly met. The bot's sweep
  crosses only about 90 L of 40 cm snow, its bite (0.50) is already the whole depth there, and
  widths are frozen, so nothing within §8.2's rules raises it. A player sweeping until the load bar
  is full gets the 130 L. `test_s82_twice_per_stroke` holds it to ×1.5 in 40 cm
  (`S82_SWEEP_BOUND`), the other tools to ×1.6 (report/s8_2.md *Bites*).
- **§8.2, to accept (coordinator): bare hands' capacity levels are +75 % each** (round 5: +25 %;
  `upgrade_hands_capacity_step` 1.75) so the ladder's hands → small shovel step holds against the
  doubled small shovel. A balance change: a save that owns both levels carries ×3.06 instead of
  ×1.56, for the same $2 and $5 (report/s8_2.md *What changed*, *The ladder*). **§8.1b:** with
  bare hands' fill rate ×1.3 (the owner's second decision) the ladder sells only the first level;
  a save that owns both keeps both (92 L, 338 L/s).
- **§8.2, to accept (coordinator): the hand tools against the machines** (the path box's
  removal rate; no ladder row compares them). At base the large scraper (0.055 m³/s) passes the
  electric shovel (0.053) by 5 % and the standard shovel matches it. Fully upgraded, the standard
  shovel (0.075) passes the small blower (0.065), and the large scraper and the sleigh pass the
  electric shovel. Round 5 already had the large scraper at 0.099 and the standard shovel at 0.069
  at base. The upgrade steps weren't tuned for it (report/s8_2.md *The ladder*).
- **§8.2:** `contract_bench`'s "human pace" column (1.1 s a stroke) is optimistic since §8.1 (a
  stroke takes at least a recovery and a hold). Not changed. **§8.1b: fair again**: a 1.1 s stroke
  is longer than the shovels' 0.7 s recovery and nothing waits. It reads 1.0 / 0.8 / 7.3 / 5.8 min,
  above the bot's own 0.7 / 0.6 / 5.4 / 4.3 min (report/s8_1b.md *Contracts*).
- **§8.2:** looking straight down (−85°) in deep snow, the body-anchored pose lifts the tool to eye
  level, and two full loads pass the camera's near plane there, above the top of the view: the
  sleigh's (0.006 m behind the camera's plane; round 5 0.003 m in front) and the large scraper's
  (0.013 m in front; round 5 0.021 m). Both cut it outside the view: the test checks no cut
  reaches the view (up to a 100° field of view; none found up to 135°), and the shots show no
  clipping. Pre-existing pose, not changed.
- **§8.2, for the coordinator:** the load's mound mesh (round 5's) is turned half a segment so a
  flat side faces the blade's edges: at its widest it is the blade's width, no longer 8 % wider
  (round 5's corner poked 3.2 cm through the sleigh tub's walls, visible from the third-person
  camera looking down). Same volume, every tool's mound 8 % narrower at its widest
  (report/s8_2.md *What changed*).
- **HANDOFF §7's tool table** shows round 5's capacities, fill rates and bites (§8.2 changed
  them); Part 4 updates HANDOFF.

- **§9, accepted by the coordinator** (the review's readings):
  - **A pushed berm slumps back** at 37° onto the end of the cleared strip 0.75 s after the blade
    lifts (`Snow.GUARD_SETTLE_STEPS`; before, it kept a cliff on its blade side until it hardened).
  - **Pushing goes a little further.** Before, the wide pusher in 30 cm stopped dead after 1.5 m:
    its one-cell ridge reached hip height (0.99 m) and became a wall, though the push drag still
    allowed 42 %. Now it stops at 2.25 m (the berm, spread, against the blade). Plows and the
    pickup go as far as before (report/s9.md *Push behaviour*).
  - **Small hand mounds are lower:** bare hands in 20 cm leave a 33 cm mound (a 53 cm one-cell
    spike before); `test_push_builds_a_mound_conserving_volume` (> 30 cm) passes unchanged. The
    rounding, `moved_crest_max_diff` 0.08, was set for it: 0.03 gives big piles true domes but that
    mound 28 cm (report/s9.md *Choosing the values*).
  - **Grader windrows landing on unhardened player-moved snow** settle with it as player-moved
    snow. The grader's lane op and `test_s11_grader_pass_unchanged` are untouched.
- **§9, the cost (corrected after review):** relaxing a tile that holds player-moved snow costs
  ×1.25–×1.7 (work bench); other tiles are unchanged. The frame budget is unchanged, so big pushed
  piles take longer to settle (a 75 m³ dump: about twice the work). perf.tscn, the review's
  alternating pairs (`677c686` → §9): the plow truck pushing a berm avg 5.86 / 5.79 → 6.62 / 6.58 ms
  (+13 %), p95 9.19 / 8.97 → 10.20 / 9.89 ms, relaxation p95 2,540 / 2,521 → 2,688 / 2,686 µs (the
  2,500 µs budget, checked between tiles, was already passed before), chunk updates 1,055 / 1,049 →
  1,137 / 1,135; 10× snow settling p95 34.4 / 35.3 → 36.7 / 36.3 ms; the pickup shoving p95 9.62 /
  9.54 → 8.27 / 8.28 ms; 9 → 8 scenarios over 16.7 ms at p95. No exact, cheap change recovers the
  plow berm's cost: 93 % of its soft-pass time is tiles that move snow (report/s9.md *Perf*).
  The review's fix (emptied cells lose their marks) measured nothing worse beyond noise.
- **§9: an emptied cell keeps its mark until its chunk syncs** (`sync_chunk`: every 3 game hours
  at most, 3¾ min at 1×, sooner while snow falls), except where `set_rect` empties it (a box's
  snap: at once). Snow that isn't the player's landing on it before then (wading's flanks, the
  crew, the grader) settles as player-moved snow until it hardens.

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

**From §8.1 (hold to fill, not spam-click):**
- **`ToolData.throw_recovery_s`** (s), in every `data/tools/*.tres` and the generator's `_tools()`:
  bare hands 0.5, small and standard shovel 0.7, pusher and both scrapers 0.8, sleigh 1.0; the
  electric shovel 0.15 and both blowers 0.18 (their chute's throw interval, which was a constant).
  §8.2 doubles capacities and fill rates but leaves these alone.
- **Balance `min_scoop_hold_s` = 0.25** (`balance.tres`, `BalanceData` default, generator record).
- **ToolController (hands, shovel-type tools):** no opening bite (`_dig_timer = cycle_time` at a
  stroke's start; `_cut_time` is no longer cleared per stroke). The dig cycle runs while held,
  sweeping or not, but what the sweep took during the cycle (`_cycle_swept`) counts toward the
  cycle's one in-place bite: a still frame after sweeping takes no lump. A sweep cuts the strip it
  crossed; only when the strip comes up short does the rest of the frame's fill come from the
  scoop's footprint where it is now (the in-place cells, `_foot_cells`), **at most the opening
  bite's size `fill_rate × cycle_time × 0.4` in all for a load** (`_foot_left`), and only for a
  load's first stroke (a stroke that goes on filling a kept load gets none, so a click can't renew
  it). `_cut_cells()` does each cut. Don't narrow it to the press point's cells or to the snow the
  press point held: both were tried in the second review. The grind bot then stalls at the top of
  the walkway (`grind_bench --full=1`: not completed, stuck with 0.9 m³ left by the steps), and the
  second also fails the bare-hands dig-out (0.6 m of 3.2 m). A release
  throws only `min_scoop_hold_s` after the physical press (`_hold_t`); a throw sets `recovery`
  (public, seconds left) and the follow-through (`toss_t`) lasts `max(0.42, throw_recovery_s)`.
  **§8.1b replaced the blocking:** a press during `recovery` scoops at once (`_press_wait` is gone),
  and a release inside it waits to throw (*From §8.1b*). The recovery runs on across tool switches
  (the new tool's next throw waits for it), and a hand or shovel-type tool switched to mid-recovery
  shows the rest of the follow-through (`toss_t = 1 − recovery / _toss_len`) unless a scoop had
  already ended it. A load kept by a release sooner than the minimum (`_kept_short`) shows its
  landing ring where the aim is now, recomputed as while filling; after a refused throw the ring
  stays where it was, as before §8.1.
- **Electric shovel:** `_stream_beat()` throws what the chute holds at most once per
  `throw_recovery_s`, held or not (a release no longer throws at once; a tool switch flushes it).
  So up to one interval's intake can wait in `_stream_acc` after a release. It is thrown on the
  first frame off foot (a vehicle, a blower), and `game_root.collect_state()` calls
  `ToolController.flush_chute()` before `_flush_projectiles()`, so a save lands it. **New code that
  saves, or takes the player off foot, by another path** must do the same.
- **Scripted strokes in tests and bots** hold at least `min_scoop_hold_s` before releasing.
  (§8.1b: they no longer wait out the recovery before pressing; *From §8.1b* says what a stroke
  inside the recovery does. A test that needs its release to throw at once waits for
  `tools.recovery` to reach 0 before the release, or for `tools.throw_waiting` to clear after it.)
- (§8.1b: the old rule here, "keep shovel-type recoveries above `ToolController.RECUT_S`", no longer
  applies. A throw clears the re-cut memory (`_release_throw()`; no press does), so a press right
  after a throw finds fresh bites; grind_bench is identical with `--recovery=0 --hold=0`.)
- **click_bench** (`--tools=all`, `--rows=`, `--rhythm=`, `--gap=`; grind_bench's `--recovery=`,
  `--hold=`, `--fill=` overrides for measuring) and `test_s81_clicking_never_beats_holding` (every
  tool, 5/10/20/50 per second, in place and sweeping, 12 s runs, ~90 s) are §8.2's rerun.
  `--rows=shallow [--depths=0.06,0.12,0.25,0.6]` (only when named) runs one held sweep per depth in
  flat snow with the aim level (`run_shallow`), so two builds sweep the same path: how much a stroke
  cuts and where. §8.2's doubled loads and fill rates make the strip come up short more often;
  rerun it there.
- **§8.1's tests** in test_polish6: `test_s81_throw_rhythm_data`, `…_clicking_never_beats_holding`,
  `…_scoop_rules`, `…_a_pause_in_a_sweep_adds_no_lump`, `…_rhythm_across_a_tool_switch`,
  `…_shallow_sweep_takes_no_more_than_the_opening_bite`, `…_kept_load_ring_follows_the_aim`,
  `…_electric_chute_is_never_stranded`. A change to the dig cycle, the footprint fallback or
  `_sync_tool()` must keep them passing. `_s81_flying()` counts only ThrownSnow not yet queued for
  deletion (a flushed one has landed but stays in the tree until the frame ends).
- `shot.gd`: `--scoop=thrown --after=F [--switch=S]` (a real throw, captured F frames after the
  release; S frames after it, switch to bare hands).
- Suite times here: polish6 ~335–700 s depending on the PC's load (§8.1's bench tests ~95–250 s;
  §3's settling test 150–390 s).

**From §8.1b (pause spaces throws: the owner's decision):**
- **The rule** (it amends Decision 10 and §8.1; the owner's words are in *Open items*): the recovery
  after a throw only spaces out throws. A press scoops at once, during the recovery too. A release
  after `min_scoop_hold_s` (counted from the press) throws at once outside the recovery; inside it,
  it sets **`ToolController.throw_waiting`** (public) and the throw goes, through
  `_release_throw(true)`, on the first frame the recovery has run out, **where the release aimed**
  (second review fix; it used to go where the aim was when it went): the release stores its facing,
  aim and distance (`_wait_fwd`, `_wait_aim`, `_wait_dist` = `_throw_dist() × _pitch_factor()`), and
  `_waiting_landing()` throws from where the player stands with them. The landing ring stays on that
  spot meanwhile (recomputed every 0.06 s only for where the player stands), whatever the player
  turns to. A release inside the recovery whose throw can't go there (nowhere to land, or indoors)
  is refused at once, as any release is: no throw waits. A waiting release clears the fill's "Full —
  release to throw." hint (`_full_hint()`). A press before then cancels it: the load stays, kept,
  and the press goes on filling it (its next release aims afresh). A press the cap refuses is
  ignored and cancels nothing (review fix: the cancel follows `_scoop_press()` and checks
  `_fill_pressed`).
- **Nothing is lost when a waiting throw is interrupted:** `_sync_tool()` (a tool switch) and
  `dump_at_feet()` (saving, the rack, dropping the tool) clear it, and the load goes to your feet as
  any load does; off foot (a vehicle, a blower, the player frozen by a screen) and with the mouse
  freed (`ui_block`) it is cancelled and the load stays in the tool, kept (the next release on foot
  throws it). Due indoors (`not work_ok`), it doesn't go either: the load stays, kept, without the
  error sound or hint (review fix); the next release outside throws it. The pause menu pauses the
  tree, so the wait resumes with the game. **New code that takes the load away** goes through
  `dump_at_feet()`, or clears `throw_waiting` itself.
- **A throw renews the bites** (accepted by the coordinator, third review): `_release_throw()`
  clears `_cut_time` (review fix; the first version cleared it at a fresh load's first stroke). Without it a press right after a throw found the cells
  just cut used up for as long as the sweep went over them (grind_bench 0.004 m³/s). No press clears
  the memory, and a load emptied any other way (`dump_at_feet()`: a switch, saving, the rack) keeps
  it, so a click can't renew a bite and only a throw does, at most once a `throw_recovery_s`. A new
  way of throwing that should renew them goes through `_release_throw()`.
- **The follow-through gives way to a scoop** once `ToolController.TOSS_MIN_S` (0.42 s, round 5's
  toss) has played since the throw (`toss_t = 1`, `_toss_cut`); not scooping, it plays out over the
  recovery as in §8.1. A tool switch doesn't bring back a follow-through a scoop ended.
- **Unchanged:** `throw_recovery_s` per tool, `min_scoop_hold_s`, the press cap, the electric
  shovel's chute beat and the blowers' interval, the dig cycle, the footprint fallback, push. No
  balance or save change.
- **The owner's second decision (data):** bare hands' **`fill_rate` = 0.1105** (round 5's 0.085
  × 1.3) in `data/tools/hands.tres` and the generator's `_tools()`. With it §8.2's ladder sells
  **one** of bare hands' two capacity levels (`ItemUpgrades.max_level(&"hands", &"capacity")` = 1;
  level 1 $2, +75 %); `hands:capacity:2` exists only for old saves, which keep it and its effect
  (`ItemUpgrades.mult` counts every owned level; the Upgrades app shows `max(for sale, owned)`).
  Bare hands' other tracks are unchanged (throw 2, push width 1, push power 1). A later change to
  bare hands' fill rate or capacity step, or the small shovel's base, moves this: the tests compute
  it from the data (`_s81b_hands_levels()` in test_polish6, `_p6_hands_capacity_levels()` in
  test_polish5).
- **Benches** key on `"throw_waiting" in tc`, so they still run the baseline and §8.1 builds as
  before: grind_bench's and contract_bench's bots no longer hold through the recovery before
  sweeping, and after the release they wait (up to 120 frames) while a throw waits, turned to it.
  click_bench: `_recovering(tc)` is false in a §8.1b build; `_throw_waits(tc)` makes the in-place
  bots wait for a waiting throw before pressing again; the human-rhythm bot keeps its fixed rhythm
  (a press that comes first cancels the waiting throw, as a hurried player's would).
  `shot.gd --scoop=thrown --repress=R [--rethrow=H]` (press again R frames after the release,
  sweeping; H frames into it, aim up and release). Shots in
  `docs/polish6/shots/08-pause-spaces-throws/`.
- **Numbers to compare against:** grind_bench `--full=1` **0.0378 m³/s** in 120 s, the path box
  completed after **3.3–3.4 min (199.1–204.9 s by the report's probe line, mean 201.9; it varies
  run to run), 343–351 strokes** (baseline 0.0376, 193.9 s, 349); before the second decision 0.0331 and not completed. contract_bench bot 0.7 / 0.6
  / 5.4 / 4.3 min (human pace 1.0 / 0.8 / 7.3 / 5.8; small and standard shovel only, not rerun).
  click_bench bare hands, held: 0.0477 m³/s taken in, 0.0315 out of the box, 52 throws; clicked
  0.0027–0.0043, 0 throws.
- **§8.1b's tests** in test_polish6: `test_s81b_a_waiting_throw_goes_when_the_pause_ends`,
  `…_a_press_cancels_the_waiting_throw`, `…_an_interrupted_waiting_throw_loses_nothing`,
  `…_bare_hands_one_capacity_level_old_saves_keep_two` (the second decision: the store and the
  polish5_v3 `fun_2_upgrades.json` fixture; `S81B_HANDS_FILL_X` 1.3);
  `test_s81_scoop_rules` and `test_s81_rhythm_across_a_tool_switch` were updated to the rule. A
  change to the release, the recovery or `_sync_tool()` must keep them passing. After review they
  also check that a throw empties the re-cut memory and a load dropped at your feet keeps it, that a
  press the cap refuses leaves the throw waiting (they fill `Settings._presses["primary"]`), and that
  a waiting throw due indoors stays in the tool without the error hint. After the second review:
  turned back to the snow (along the path, looking down) before it goes, the ring's spot stays and
  the throw lands on it, not where the aim is then; the fill's hint is gone once released; a release
  indoors inside the recovery is refused at once.
- **`click_bench --rows=rhythm --turnback=N`** (the second review's experiment, now in the bench):
  the rhythm bot turns back to the snow N frames after its release and presses at the end of the
  gap; each row also prints the strokes whose throw still waited at the press and the throws that
  landed back in the box. With the landing fixed at the release it matches the bot that stays turned
  (report/s8_1b.md *After the second review*). The rhythm rows' labels print two decimals now.

**From §8.2 (loads twice as big):**
- **The six shovel-type tools that throw** (small and standard shovel, wide pusher, both scrapers,
  sleigh) have twice round 5's capacity and fill rate. Bites were raised only where the measured
  sweep fell short, and widths are unchanged. In `data/tools/*.tres` and the generator:
  - small shovel 100 L, 260 L/s, bite 0.40;
  - standard shovel 130 L, 320 L/s, bite 0.50;
  - pusher 90 L, 180 L/s, bite 0.15;
  - snow scraper 100 L, 200 L/s, bite 0.21;
  - large scraper 160 L, 320 L/s, bite 0.23;
  - sleigh 800 L, 640 L/s, bite 0.90.
  Bare hands, the electric shovel and the blowers are unchanged (§8.1b, the owner's second decision:
  bare hands' fill rate ×1.3, 0.1105). `test_s82_twice_the_load` holds the table (`S82_ROUND5`,
  `S82_BITE`, `S82_SAME`, `S81B_HANDS_FILL_X`); a later change to these values updates it.
- **New balance key `upgrade_hands_capacity_step` = 1.75**: each of bare hands' two capacity levels.
  `ItemUpgrades.level_value(cat, item, track, old_value)` gives a level's effect (the old global
  upgrade's, except this one). Every other level keeps its old upgrade's +25 %. A test that checks
  a level's effect reads `level_value` (as `test_s13_upgrades_belong_to_an_item` now does).
- **The load visual** (`ToolController._update_load_visual`): twice round 5's mound for twice its
  load. The height is `sqrt(capacity ÷ tray)` clamped to `HEAP_MIN` 1.131 – `HEAP_MAX` 1.98 (round
  5 0.8–1.4, both ×√2); the length along the blade `LOAD_LENGTH` 1.414 × round 5's, growing forward
  from where round 5's began on a blade (`_load_at`, the shift `ahead`) and both ways in the
  sleigh's tub; the width scale is round 5's. The mesh's big sphere is turned half a segment
  (`setup`), so at its widest the mound is the blade's width (inside the sleigh tub's walls);
  `LOAD_HALF_LEN` 0.1663 is its half-length (0.18 × cos 22.5°).
  `test_s82_full_load_heaps_bigger_clear_of_the_camera` checks the full load: ×1.9 or more round
  5's mound, ×1.35 or more higher and longer, scaled as wide, no wider than the blade, first and
  third person; and at base and fully upgraded, held, scooping and pushing (against round 5's
  own mesh, `_s82_round5_mound`):
  - from −60° up, its vertices stay beyond 1.5 × the camera's near plane;
  - looking straight down (−85°), it comes no more than 1 cm nearer than round 5's load did.
    There the body-anchored pose lifts the tool to eye level in deep snow, and the sleigh's load
    passed the near plane already in round 5, hidden in its tub. The fully upgraded shovels are
    0.4 mm inside this rule (the others 1.4–3.7 mm), so a pose change that lifts loads at −85°
    will trip it;
  - at every angle, where it passes the near plane the cut lies outside the view
    (`_s82_cuts_view`, against the widest view a player can set: `S82_FOV_MAX` 100°,
    `S82_ASPECT_MAX` 2.4). A new field-of-view maximum in the settings must be copied there.
  A later change to the poses or the viewmodel must keep it passing.
- **Benches:**
  - `click_bench -- --rows=strokes [--stroke_depths= --strokes= --log_strokes=1 --trace_strokes=N]`
    (`run_strokes`, `_s82_frame`): the grind bot's strokes in flat snow. It reports the load per
    throw, throws a minute, what limited each frame of filling, and the game's relaxation and
    chunk counters.
  - `--tool_set=<id>.<key>=<value>;…` (grind_bench's `_overrides`, so click_bench too) sets one
    tool value, for "before" profiles in the same build.
  - **`contract_bench`'s bot now holds through §8.1's recovery and the minimum hold.** Its numbers
    before this commit and after aren't comparable for §8.1's build.
- **`shot.gd --load`**: a number is the `--pose` load fraction, anything else a save to load (§3).
- **§8.2's tests** in test_polish6:
  - `test_s82_twice_the_load` (data, upgrades, the ladder for bare hands);
  - `test_s82_twice_per_stroke` (the stroke bench, round 5's profile against §8.2's in the same
    build, 30 strokes: ≥ ×1.7 in 80 cm; in 40 cm ≥ ×1.6, the standard shovel ≥ ×1.5,
    `S82_SWEEP_BOUND`; ~100–150 s);
  - `test_s82_full_load_heaps_bigger_clear_of_the_camera`.
  Updated through lookups: `test_s6_blades_match_the_profiles` (`S6_LOAD_X`) and
  `test_s13_upgrades_belong_to_an_item` and `test_s13_old_global_levels_carry_over`
  (`ItemUpgrades.level_value`).
- **Shots:** `docs/polish6/shots/08-loads-twice-as-big/` (`--setup=cleared_drive --player=6,5,0
  --pitch=0 --pose=hold --load=1`; `_down` at `--pitch=-30`, every tool).

**From §9 (smooth piles):**
- **Player-moved snow is `Snow.soft`** (a byte per cell): loose snow pushed by any blade or hand
  tool (`blade_push`), thrown or dumped (`deposit`, default `moved = true`, and its ceiling overflow
  through `_spill(…, moved)`), or slid off such snow. Not marked: the grader (`grader_lane`), the
  sidewalk crew, wading (`deposit(…, false, false)`), `set_rect`/`add_layer_rect` fills. It clears
  whenever the cell holds no more than 2 mm of loose snow, whatever took it (hardening, a box's
  snap, melting, a scrape, a slump, the save's rounding): at the chunk's next `sync_chunk` (a pass
  of its own over the chunk's tiles that hold marks, by `soft_tiles`; keep the sync's cell loop
  free of it, a check there cost the 10× snowfall scenarios 5–8 %), and at once in `set_rect`.
  Until that sync an emptied cell keeps its mark. **Every write goes through `_set_soft(i)` /
  `_clear_soft(i)`**: they keep `soft_tiles` (soft cells per relaxation tile) exact, and a tile with
  none runs the original relaxation loop. New code that writes `soft` directly breaks that.
- **Its rules** (`_relax_tile_soft`): it slumps past `moved_repose_max_diff` (0.19 m a cell, 37°;
  other loose snow keeps `repose_max_diff` 0.23), and a cell stands at most `2 × moved_crest_max_diff`
  (0.16 m) more above its lower neighbour than below its other neighbour on that axis — a wall, the
  map's edge, the curb from the property side, a completed box from outside, or the guarded strip
  there supports it instead. New balance keys `moved_repose_max_diff` 0.19 and
  `moved_crest_max_diff` 0.08 (defaults and `balance.tres`).
- **`blade_push` spreads each cell's snow over `PUSH_BAND`** (five points `min(0.2, push_dist / 3)`
  apart, centred at push_dist + the 0–12 cm draw), still **one `push_rng` draw per moved cell**.
  **§11's back-drag** uses `blade_push`, so its snow is marked and spread too; keep the draw count.
  The dirty/relax rectangle now covers every cell the band reaches.
- **The blade guard's tiles are queued again** once it no longer covers them, and all of them
  `Snow.GUARD_SETTLE_STEPS` (45) relaxation steps after it expires without being set again
  (`guard_tiles`, `guard_settle`, `_release_guard`). The wait keeps RMB clicking from pushing more
  than holding (`test_s2_autoclick_capped`): don't shorten it without rerunning that test. A new
  blade calls `set_blade_guard` every frame as before and gets this for free. A test or bench that
  wants a pushed pile settled waits ≥ 50 frames after the push before `relax_until_stable()` (which
  doesn't step the guard while the queue is empty).
- **Saves:** `serialize_pending()` has `"soft"` (zstd bytes, base64); a save without it has no
  marks (older saves settle as before). In the v3 round-trip test (`test_s7_v3_save_round_trips`).
- **`SnowRenderer.mesh_us_last`** (µs of chunk mesh updates last frame) and perf.tscn's
  "snow counters" line after each scenario (relaxation and mesh µs p95/max, updates a frame).
- **`shot.gd --pile=hand|plow|pickup|throws [--pile_frames=n]`** (with `--setup=medium
  --fixed-fps 60`); shots in `docs/polish6/shots/09-smooth-piles/`.
- **§9's tests** in test_polish6: `test_s9_pushed_piles_settle_at_the_new_step` (hand and plow, the
  Done-when), `test_s9_shoved_and_thrown_piles_settle_at_the_new_step`,
  `test_s9_blade_push_spreads_over_a_band` (each push distance on fresh ground, 36 cells),
  `test_s9_whose_snow_is_marked`, `test_s9_emptied_cells_lose_their_marks` (a box's snap, melting,
  a floor-0 scrape; wading's snow there afterwards settles exactly as on ground never marked). A
  change to the blade deposit, the relaxation, the guard or the marks must keep them passing;
  `_s9_pile` mirrors the rule.
