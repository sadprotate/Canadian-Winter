# Polish Round 7 — status

Branch `cw-polish7-pg` from `main` (`dcd0b78`). Brief: `POLISH_ROUND_7_PROMPT.md`.

- [x] §10 — The plow truck from the start, good in snow. A new game starts with `pickup_plow`
  (locked by the keys), with the pickup's wheels and, blade up, its snow rules; the shove's cast
  scales with width; the front plow isn't sold; it counts as hand tools for listing size but opens
  street sections; the photo and the menu show the plow. Tested: polish7 §10 (6 new), the §12 tests
  for both trucks, §13, §10/§10b, the keys end to end, the photo, menu and fixture tests
  (`report/s10.md`).
- [x] §11 — Blade up/down, push and pull. `veh_blade_up` / `veh_blade_down` (Up / Down, capped,
  read before the GUI) on every blade vehicle; back-drag with the existing blade op (face to the
  vehicle, §9's band, marks and draws, volume exact); standing still the blade holds the side it
  last worked and driving forward leaves the pile; dragging slows the reverse like a push. Tested:
  polish7 (8 new, 14 in all), the §2 key tests, the push and §3/§9 blade tests, the snow suite; a
  review pass (4 findings fixed) (`report/s11.md`).
- [x] Playtest fix 1 — the truck gets out of the driveway (`PLAYTEST_FIX_1.md`). `pickup_stuck_depth`
  0.6 → 0.9 (above the opening's deepest), and round 5 §12's bog depth counts from the snow the truck
  stands in (the lower wheel of each axle; read on getting in and while it moves, held while it
  stands still); the pickups' snowed-in message says the truck only creeps. From a new game with
  nothing shovelled, the truck backs up, plows out blade down in 1 pass (8.9 s), and gets out blade up
  with run-ups (5 pushes, 42.6 s), for 3 seeds in both modes. Tested: polish7 `test_pf1_` (7 new),
  `test_s10_`, `test_s11_`; polish5 `test_s12_` (both trucks, the opening test updated), `s3_road_rule`;
  gameplay `vehicle_plow`, `plow_pushes`, `truck_keys` (updated); polish6 `test_s9_`, the generator
  test; a review pass (4 problems fixed) (`report/playtest_fix_1.md`).
- [x] Playtest fix 2 — pushed snow tumbles instead of spiking (`PLAYTEST_FIX_2.md`). `Snow.blade_push`
  rolls whatever would stand over the moved-snow step on down the pile in the same op (`_roll`:
  steepest descent, the blade and the guarded strip behind it walls, the curb only where the push
  stops at it, no draws, volume exact), for every plow, back-drag and hand pushes; the pickup's shove
  keeps its old placement. The plows' berm drag reads the pushed pile out to `berm_reach(hw)` so a
  long push is no easier (3–9 % slower). The pile while pushing went from 2.2 m with cells 0.45 m over
  the step to 1.56 m with none (30 cm), 4.1 → 2.3 m in the opening; the same after 50 m and 100 m (the
  owner's call). Tested: polish7 `test_pf2_` (4 new: the op alone exact to 1e-6 m, straight and
  angled; the long pushes; the opening, 3 seeds in both modes; every blade), `test_pf1_`, `test_s11_`,
  `test_s10_`; polish5 `test_s12_`, `test_s11_grader_pass_unchanged`, `s3_`, `test_s13b_melting_ledger`;
  polish6 `test_s9_`, `test_s3_blade`; the snow suite; systems `test_snow_ceiling_at_lamp_height`;
  polish3 `test_no_snow_inside_the_houses`; gameplay `plow`, `push`, `truck_keys`, `wading`; perf's
  plow scenarios before and after; a review workflow (findings fixed) (`report/playtest_fix_2.md`).

## Questions

None before starting. Design choices made from the brief and recorded in the section reports:
- §10: with the blade down the plowed truck keeps the plow's drag under the wheels (Decision 1
  "Blade down: it plows, as now"); only its stuck depth is the pickup's.
- §10: the starting truck is recognised by its kind (`PICKUP_PLOW`); an older save's fitted plow
  counts the same way (hand tools for listing size, opens streets).

Playtest fix 2 (asked during the fix, with the measurements):
- With pushed snow rolling down the pile, the plow's pile stops growing after 10–20 m and settles at
  the moved-snow slope, about 1.3–1.7 m tall on 20–40 cm of level snow (the pickup's blade is
  0.83 m), the same after 50 m and 100 m; the rest rolls off the blade's ends into ridges. The brief
  expected about blade height and a pile longer and wider after 100 m. Owner: **keep it as built**.
  The tests check that it never spikes, stays under its measured height, and is no taller (the same
  size) after 100 m than after 50 m.

## Check at the end

- §10: `Contracts.equipment_capability()` / `listing_needs_vehicle()` changed (contracts are global
  game state). Their tests passed; the full suite covers the rest. The menu's shoveller moved after
  the menu tests ran (visual only): the full suite reruns them.
- §11: `Vehicle._physics_process`'s plow branch (shared by every blade vehicle) and
  `Settings.ACTIONS` (two new actions; every test that loops over the actions) changed. The push
  path runs with the same arguments as before unless the vehicle has just back-dragged; the full
  suite covers the rest (perf's plow scenario isn't rerun: no new kind of work per frame, as the
  brief says).
- The review fixes changed `test_s13_ownership_and_the_front_plow` and `test_s13_upgrades_app` after
  the §10 commit (committed with §11).
- Playtest fix 2: `Snow.blade_push` (shared by every plow, back-drag and every hand tool's push; the
  pickup's shove passes `tumble = false`) and the plows' berm drag changed. The fix's tests, the snow
  suite, round 6's §9, §10/§11, round 5's §3/§12/§13b, fix 1's, the ceiling, the houses and the
  gameplay plow/push/keys/wading tests passed; the full suite runs in CI on the PR.

**Final check (after §11):** import clean (exit 0, no errors); parse check 92 scripts, 0 errors;
the full suite once: **255 passed, 0 failed** (1,979 s), no engine errors or warnings in the log. It
covers every item above (the menu tests after the shoveller moved, every test looping over the
actions, the push and blade tests, all fixture suites). Weather untouched: `weather_truth` not
needed. The known flaky `test_menu_fixture_load_is_the_same_as_direct` passed in the full run.

## Issues

- §10 shots: three images instead of two. The menu's home shot is kept as a reference for the
  truck's look there, and it needed a retake after the shoveller moved clear of the blade.
- §10: an old save's fitted front plow no longer shows "Front plow" under the Property app's
  "Upgrades owned", because the hidden track is left out of `upgrade_groups()`. No old saves to
  support (Decision 1).
- The store's plow-fitting message (`store.gd`) names only the `veh_tool` key, not §11's blade keys.
  It is left alone as the brief asks; only an old save's order reaches it.
- §11 shots: besides the two kept, a too-close first framing and a top-down probe (to check which
  side of the blade the snow was on) were taken and not kept.
- §11: a plow's cleared lane keeps the blade's 1.5 cm floor (`blade_floor`), which renders as a light
  speckled film; behind a back-drag it can read as snow still at the door in a screenshot. Same as a
  push's lane; not changed.
- Lowering the blade at a standstill right against a settled pile (raise after a drag, then lower
  again without moving) still runs the standstill push as before the round, which can throw the
  pile's nearest row forward. Left as it was ("Standing still adds nothing new"); noted for the
  playtest.
- Playtest fix 1: two texts still describe the old opening, and were left as they are (the brief keeps
  the keys unchanged; the owner's call):
  - the Help app (`help_text.gd`: "…room to drive: dig the snow from around the wheels and clear the
    driveway");
  - the keys message (`buried_keys.gd`: "(The truck still can't drive through deep snow.)").
- Playtest fix 1: blade down, the truck plows out in one pass, and the driveway's snow ends up as a
  pile up to about 3.9 m high on the street in front of the blade. That is the plow path's tuning,
  shared by every plow, and left as it is. (Playtest fix 2: about 2.3 m now; the pile tumbles over the
  curb.)
- Playtest fix 1: backing up onto its own track where snow has slumped back raises the bog depth by
  that snow: a few cm for the plowed truck, up to about 25 cm for the plain pickup (old saves; its
  track is narrower). A run-up carries a little further there.
- Playtest fix 1: digging out only around the wheels (not the driveway) makes the truck bog from a
  standstill against the snow ahead ("…Back up with S and take a run at it"), where without digging it
  pushes off slowly. That is round 5's dug-out case, unchanged; the bog depth counts from the snow the
  truck stands in, and dug-out wheels stand in none. Asked the owner whether dug-out wheels should do
  at least as well: **leave it as is** (`PLAYTEST.md` item 18 still asks the testers how it feels).
- Playtest fix 1: the pickups' snowed-in message on getting in (more than `pickup_stuck_depth` under
  the wheels, e.g. after a major event) now says "It only creeps until you dig around them…" instead of
  "It won't move…": the truck creeps there (its reverse always does), which the brief's Decision 3
  says the message must not deny. Other vehicles' message is unchanged.
- Playtest fix 1 shots: one framing from across the street wasn't kept (the pile hid the truck); the
  kept shot is from beside the driveway.
- Playtest fix 2: the plows' drag is a little harder than before the fix, never easier: 3–9 % slower on
  a long straight push in 30 cm, the opening's first 15 m in 11.3 s instead of 10.2 s (fix 1's
  scripted blade-down plow-out: still 1 pass, 9.8 s instead of 8.9 s). No single reading matches every
  plow's old drag, which depended on how high its own spike stood.
- Playtest fix 2: hand pushes keep their 0.65 m drag reading. Most walk within 3 % of before, the wide
  pusher in 15 cm 6 % and the large scraper 12 % faster (their pile lies a little further out). And in
  deep snow the wide pusher no longer walls the player in. Before the fix its pile stood above the hips
  in front of it after about 2 m of 30 cm (the wading rule stopped you); now it tumbles away and you keep
  pushing, slowly. `PLAYTEST.md` item 23 asks the testers.
- Playtest fix 2: a back-drag's pile now runs out toward the front wheels at once (it used to settle
  there over a few seconds). §11's tests pass (never stuck by its own pile); `PLAYTEST.md` item 24 asks
  the testers to watch for it, the ATV especially.
- Playtest fix 2: while a blade passes, the edge of the lane it cuts stands steep for a moment just
  past its guard (2 m), until the relaxation settles it: 0.35–0.48 m over the moved-snow step, the same
  as before the fix. The per-frame checks stop 1.5 m behind the blade; everything is checked once
  settled.
- Playtest fix 2: the roll costs time. One `blade_push` call takes about 0.27 ms for the pickup's plow
  and 1.05 ms for the plow truck (0.06 and 0.18 ms before). In `perf.tscn`'s plow scenario (three
  before/after pairs alternated, this PC busy with other programs), the frame went from 7.1 to 8.0 ms
  on average (11.3 to 13.3 ms at p95). Relaxation went from 2.69 to 3.16 ms at p95, and chunk meshes
  from 5.4 to 5.9 ms. The brief's 2.5 ms / 3.5 ms weren't met on this PC before the fix either. The
  hand push is 0.2 ms more a frame. Cutting more (merging shares that land on one cell) would change
  where snow lands, so it was left out.
- Playtest fix 2: `HANDOFF.md` still says the RMB push "Stops at the curb"; pushes carry
  snow over it since round 5 §3. Left as it is: not part of this fix.
- Playtest fix 2 shots: six taken, two kept. The brief's "from the driver's seat" was tried with the
  truck's cab view, but its camera sits inside the cab's own box: before and after, it shows only the
  dark inside of the cab across the windshield, not the pile. The kept pair uses the game's driving
  camera behind the truck. The cab view itself is left as it is (not part of this fix).
