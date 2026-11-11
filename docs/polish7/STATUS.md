# Polish Round 7 — status

Branch `cw-polish7-pg` from `main` (`dcd0b78`). Brief: `POLISH_ROUND_7_PROMPT.md`.

- [x] §10 — The plow truck from the start, good in snow. A new game starts with `pickup_plow`
  (locked by the keys), with the pickup's wheels and, blade up, its snow rules; the shove's cast
  scales with width; the front plow isn't sold; it counts as hand tools for listing size but opens
  street sections; the photo and the menu show the plow. Tested: polish7 §10 (6 new), the §12 tests
  for both trucks, §13, §10/§10b, the keys end to end, the photo, menu and fixture tests
  (`report/s10.md`).
- [ ] §11 — Blade up/down, push and pull

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

## Issues

- §10 shots: three images instead of two. The menu's home shot is kept as a reference for the
  truck's look there, and it needed a retake after the shoveller moved clear of the blade.
- §10: an old save's fitted front plow no longer shows "Front plow" under the Property app's
  "Upgrades owned", because the hidden track is left out of `upgrade_groups()`. No old saves to
  support (Decision 1).
- The store's plow-fitting message (`store.gd`) names only the `veh_tool` key, not §11's blade keys.
  It is left alone as the brief asks; only an old save's order reaches it.
