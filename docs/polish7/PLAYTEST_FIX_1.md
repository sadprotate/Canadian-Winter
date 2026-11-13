# Polish 7 — playtest fix 1: the truck gets out of the driveway

This is a playtest fix for Polish 7 (`CLAUDE.md`, *After the playtest*).

- **Work on `cw-polish7-pg`.** Don't create a branch, and don't open a PR.
- **New chat?** Read `CLAUDE.md`, then `docs/polish7/STATUS.md` and `docs/features/vehicles.md`.
  Then check out `cw-polish7-pg` and pull.
- **Save this prompt** as `docs/polish7/PLAYTEST_FIX_1.md`.

## What the owner found

These work: the photo shows the truck with its plow, the keys are hidden and found, Up/Down raise and
lower the blade, and Z/C angle it.

**The problem:** on the first morning the truck can't be used. In the starting snow it backs up, but
it won't go forward. It can't get out of the driveway to the street.

> I'm able to go backward with the truck, but not forward in that amount of snow.
> I want the truck to be able to go forward and into the street. […] Can we make the truck better
> in the snow? It needs to be able to get out of the driveway so we can use it.

## Decisions (apply them)

1. **The starting snow stays as it is.** Fix the truck, not the snow. Leave these unchanged:
   - `initial_depth_year1` (0.82), `opening_max_depth` (0.88) and `initial_road_depth_year1` (0.55)
   - the keys, the tutorial and the shovel
2. **The target: the truck can drive from the driveway to the street on the first morning.** That
   means:
   - the keys are found and nothing is shovelled
   - it works in both modes, with the real controls, from where the truck is parked
   - **The truck moves both ways.** From where it's parked, forward and reverse both move it.
   - **Blade down, the main way:** the truck plows its own way out. The player lowers the blade,
     drives forward, backs up and goes again, angling the blade (Z/C) to throw snow aside. It
     reaches the street in a few passes.
   - **Blade up, the slower way:** it also gets through the starting snow, taking run-ups as needed,
     and reaches the street.
   - **Never stuck for good:** at no point in the starting snow is it stuck for good, blade up or
     down.
3. **Still snow, not a tank.**
   - Deeper snow is slower, and pushing a big berm slows the plow.
   - When something does stop the truck, its message says what is in the way.
   - The bank limit with a run-up (`pickup_bank_max`, 95 cm) stays, unless the measurement shows it
     must move to meet Decision 2. If it moves, report why.
   - Reversing stays at least as easy as now.
   - The "snowed in" message on entering the truck appears only when the truck really can't move.
4. **Only the player's truck changes:** `is_pickup()`, which covers the plowed truck and an old save's
   plain pickup. Other vehicles, the city's grader and the sidewalk crew stay as they are.
5. **Balance values** go in `data/balance.tres`, in the defaults in
   `scripts/data/balance_data.gd`, and in the generator (Round 6 §1).
   - Change the `pickup_*` values, or add new ones for the truck. Choose whichever changes less.
   - The plain pickup exists only in old saves.

## Measure first, and write the numbers in the report

- **The snow:** in a new game, with 3 seeds:
  - the snow depth under each of the parked truck's wheels
  - the depth along its path from the nose to the road (the driveway, the sidewalk, the boulevard):
    every 0.5 m, at the centre and at both blade edges
- **The owner's run:** reproduce it with the real controls, from a new game after the keys. Run
  three cases: forward with the blade up, forward with the blade down, and reverse.
  - For each, record the speed reached and what stops it: the stuck rule, the bog rule, the bank
    wall, the shove's push-back, the plow's berm drag, or a collision.
- **Check this reading of the code** (confirm it or correct it):
  - **The starting snow:** it is about 0.70–0.88 m on the driveway.
  - **The wheels:** `pickup_stuck_depth` is 0.60, so they count as stuck. The truck only creeps at
    15% either way, which is enough to back up slowly.
  - **Forward, blade up:** the front probe reads about 0.8 m, which is above `pickup_bog_depth`
    (0.70). From a standstill the truck is "bogged" and `max_fwd` is 0. With a run-up, the shove's
    push-back at that depth is stronger than the engine, so the truck stops.
  - **Forward, blade down:** the wheels still count as stuck. The drag under them is scaled by the
    clearance (0.34) instead of `pickup_drag_depth`, so the truck barely creeps before its wheels
    reach the ground the blade has plowed.
  - **A collision:** check also that the raised blade and the longer body don't catch on anything on
    the way out (the curb, the sidewalk edge).

## Build

- Make Decisions 2–3 hold, changing as little as possible.
- Work inside round 5 §12's rules and the plow path. Don't add a parallel system.
- Snow volume stays exact.
- Keep the shove's and the blade's snow landing as they are now (§10's cast, §9's band, the marks,
  one `push_rng` draw per moved cell).

## Done when

Tests go in `tests/test_polish7.gd`, as a "playtest fix 1" group.

- **The new-game test.** Run it with ≥ 3 seeds, in both modes. Set the keys flag and shovel nothing.
  Drive with the actions (throttle, reverse, blade, Z/C), never by setting speed.
  - From the parked spot, forward and reverse both move the truck.
  - **Blade down:** a scripted plow-out (forward, back up, forward…, angling as needed) gets all four
    wheels onto the road within 3 minutes of driving. Report the time and the number of passes.
  - **Blade up:** with run-ups, it gets all four wheels onto the road within 3 minutes. Report the
    time.
  - Volume is exact throughout.
- **Still snow:** a bank deeper than `pickup_bank_max` still stops the truck with the blade up, and
  its message shows.
- **Existing tests:** these still pass:
  - the §12 tests for both trucks
  - the §10 and §11 tests
  - `test_truck_keys_end_to_end`
  - the plow tests (`test_vehicle_plow_and_stuck_pickup`, `test_plow_pushes_yard_snow_onto_road`)

  If a test's numbers move because a balance value changed, update it through lookups. Never
  loosen it.
- **Screenshots (≤ 2):** the truck on the street after plowing out on the first morning, with the
  plowed path behind it.

## Then

- Update `docs/features/vehicles.md` with the new numbers and what stops the truck.
- In `docs/polish7/PLAYTEST.md`, add what to re-check:
  - On the first morning, find the keys and plow out of the driveway to the street, blade down.
  - Do it again with the blade up, using run-ups.
  - Make sure it still feels like deep snow.
- Update `docs/polish7/STATUS.md`.
- Commit as `polish7: playtest fix 1 — the truck gets out of the driveway`, and push. Then stop and
  wait for the owner.
