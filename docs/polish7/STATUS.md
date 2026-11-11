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
