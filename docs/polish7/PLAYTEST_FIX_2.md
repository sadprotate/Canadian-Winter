# Polish 7 — playtest fix 2: pushed snow tumbles instead of spiking

This is a playtest fix for Polish 7 (`CLAUDE.md`, *After the playtest*).

- **Work on `cw-polish7-pg`.** Don't create a branch, and don't open a PR.
- **New chat?** Read `CLAUDE.md`, then `docs/polish7/STATUS.md` and `docs/features/vehicles.md`.
  Then check out `cw-polish7-pg` and pull.
- **Save this prompt** as `docs/polish7/PLAYTEST_FIX_2.md`.

## What the owner found

These work well now: the blade goes up and down and side to side, and the truck gets out of the
driveway and pushes snow the way a truck would.

**The problem:** on a long push, the pile in front of the blade spikes up into the air, far too high.
It happens over 50 m, and worse over 100 m.

> If you push a long row, let's say 100 meters of snow, even 50 meters of snow, the snow spikes up.
> We need the snow not to spike up, but to tumble backwards and form a bigger pile in the back,
> like snow would.

## Decisions (apply them)

1. **The pile tumbles, it doesn't spike.**
   - Snow that reaches the top of the pile in front of a moving blade rolls down the pile's slopes,
     as loose snow does. It rolls forward over the front of the pile and out past the blade's ends.
   - Pushing farther makes the pile **bigger by getting longer and wider, not taller.**
   - Its height comes from the snow's slope (the moved-snow repose) and how much ground the pile
     covers, never from how far it has been pushed.
   - No cell ever stands as a spike above its neighbours. This must hold while pushing, not only
     after the pile has settled.
2. **Stopping leaves one big pile.** After a long push, the truck leaves one big, rounded mound where
   it stops, plus whatever rolled off the blade's ends along the way. Nothing is lost: volume is
   conserved exactly.
3. **Every blade the player uses gets the same behaviour,** because it is one op (`Snow.blade_push`):
   - the truck's plow (tune and test with it first)
   - every plow the player drives (ATV, tractor, plow truck, the player's grader)
   - hand pushes (RMB)
   - back-drag
4. **These stay as they are:**
   - the city's grader pass (`test_s11_grader_pass_unchanged`)
   - throwing and the blowers, so banks built by throwing can still grow tall
   - the 6 m ceiling
   - the crisp cut walls of undisturbed snow
   - completed boxes acting as retaining walls
   - the curb rule for hand pushes
   - the starting snow
   - the truck's driving rules from fix 1
5. **Round 6 §9's rules still hold:**
   - the spread band
   - the `soft` marks on moved snow
   - **one `push_rng` draw per moved cell.** The tumbling adds no random draws, and no global
     `randf()` touches where snow lands.

## Measure first, and write the numbers in the report

- **The pushes:** drive the truck (blade down, straight) 25, 50 and 100 m through level snow 20 cm
  and 40 cm deep, and 15 m through the opening's ~80 cm.
- **Record, during the push and after stopping:**
  - the pile's highest point
  - its length and width
  - the largest step between a cell and its neighbours
  - how much snow spilled off the blade's ends
- **What makes the spike:** the deposit, relaxation's frame budget, the blade guard, the ceiling's
  "whatever doesn't fit stays in front of the blade", or the renderer.
- **Check this reading of the code** (confirm it or correct it):
  - **The deposit:** each frame, `blade_push` lifts every cell in the band behind the face, the
    berm included, and drops it `push_dist` ahead (0.6 m for vehicles), spread over about 0.8 m
    (`PUSH_BAND`). Over a long push, all the snow collected ends up in a strip about 1 m deep in
    front of the blade.
  - **The settling:** relaxation spreads that strip only as fast as its per-frame budget allows. The
    blade refills it faster, so it stacks up toward the 6 m ceiling.
  - **The berm drag:** the vehicle's berm drag reads only the snow within 0.65 m of the face, so it
    doesn't see a pile that tall.

## Build

- **Make Decisions 1–3 hold,** changing as little as possible, inside `blade_push` and the existing
  settling. Don't add a parallel system.
- **A likely approach** (use it if the diagnosis supports it): when the blade drops snow on a cell,
  anything that would make that cell stand more than the moved-snow step above its neighbours
  rolls on in the same op, down the slope, forward and to the sides. `_spill` already does this at
  the ceiling. It is deterministic and conserves volume, so the pile's shape no longer depends on
  relaxation keeping up.
- **The plow's berm drag** (`work_drag` in `vehicle.gd`) must still slow the truck as its load
  grows. Report how the change affects it.
  - It must not make a long push easier than now. A truck pushing 100 m of snow should still feel
    it.
  - If the drag needs to read the pile differently, keep the fix 1 plow-out test passing.

## Done when

Tests go in `tests/test_polish7.gd`, as a "playtest fix 2" group.

- **Long pushes:** the truck pushes 50 m and 100 m (blade down, straight, 30 cm of snow).
  - Every frame, no player-moved cell stands more than the moved-snow step above its lower
    neighbours.
  - The pile's highest point stays below a bound taken from the measurement. Report it: it should
    be about the height a pickup's blade can push, not metres.
  - Volume is exact.
  - The pile after 100 m is longer and wider than after 50 m, not taller.
- **The opening snow:** 15 m through it holds the same rules.
- **Back-drag** still builds its pile against the blade's back face, and the pile stays when the
  blade lifts. The §11 tests pass.
- **These pass unchanged:**
  - `test_s11_grader_pass_unchanged`
  - the snow suite's conservation and `test_blade_push_*` tests
  - Round 6's §9 tests. If one asserts a shape this fix deliberately changes, update it through
    lookups and say why. Never loosen it.
  - fix 1's plow-out and blade-up tests
- **Performance:** this fix changes a snow op, so run `perf.tscn`'s plow scenarios ("plow truck
  pushing a berm", "hand push (RMB) in deep snow") before and after. Relaxation stays within
  2.5 ms and chunk rebuilds within 3.5 ms per frame. Report p95 before and after.
- **Screenshots** (one before/after pair, since the point is visual): the pile after a 50 m push,
  from the driver's seat.

## Then

- Update `docs/features/vehicles.md` (how a pushed pile forms). If you create a snow doc, keep it
  to this.
- In `docs/polish7/PLAYTEST.md`, add what to re-check:
  - Push a long row, 50 m and 100 m, with the truck. The pile tumbles and grows longer and wider,
    with no spike.
  - Stop, and check that it leaves one big rounded pile.
  - Do the same with a hand push and with back-drag.
- Update `docs/polish7/STATUS.md`.
- Commit as `polish7: playtest fix 2 — pushed snow tumbles instead of spiking`, and push. Then stop
  and wait for the owner.
