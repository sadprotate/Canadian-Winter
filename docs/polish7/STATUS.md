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

## Questions

None before starting. Design choices made from the brief and recorded in the section reports:
- §10: with the blade down the plowed truck keeps the plow's drag under the wheels (Decision 1
  "Blade down: it plows, as now"); only its stuck depth is the pickup's.
- §10: the starting truck is recognised by its kind (`PICKUP_PLOW`); an older save's fitted plow
  counts the same way (hand tools for listing size, opens streets).

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
  shared by every plow, and left as it is.
- Playtest fix 1: backing up onto its own track where snow has slumped back raises the bog depth by
  that snow: a few cm for the plowed truck, up to about 25 cm for the plain pickup (old saves; its
  track is narrower). A run-up carries a little further there.
- Playtest fix 1: digging out only around the wheels (not the driveway) makes the truck bog from a
  standstill against the snow ahead ("…Back up with S and take a run at it"), where without digging it
  pushes off slowly. That is round 5's dug-out case, unchanged; the bog depth counts from the snow the
  truck stands in, and dug-out wheels stand in none. Question for the owner: should dug-out wheels do
  at least as well? (`PLAYTEST.md` item 18.)
- Playtest fix 1: the pickups' snowed-in message on getting in (more than `pickup_stuck_depth` under
  the wheels, e.g. after a major event) now says "It only creeps until you dig around them…" instead of
  "It won't move…": the truck creeps there (its reverse always does), which the brief's Decision 3
  says the message must not deny. Other vehicles' message is unchanged.
- Playtest fix 1 shots: one framing from across the street wasn't kept (the pile hid the truck); the
  kept shot is from beside the driveway.
