# Polish 7 — playtest fix 1: the truck gets out of the driveway

Brief: `docs/polish7/PLAYTEST_FIX_1.md`.

## Measured first

**The snow** (new game, the keys found, nothing shovelled). The numbers below are the same for seeds
2024, 7 and 31337 in both modes. The opening's noise is seeded by the year, not the game seed, and Dec 1
is always dry: the first storm starts at hour 34.

- **The truck:** parked at (40, 96.6), facing the street (−z).
- **Under the wheels:**
  - front left 0.813, front right 0.776;
  - rear left 0.838, rear right 0.754;
  - average **0.795 m**.
- **Behind it:** reversing hits the garage after 0.90 m.
- **From the nose to the road,** every 0.5 m, at the left blade edge, the centre and the right blade
  edge (±1.2 m):

| from the nose | surface | left | centre | right |
|---|---|---|---|---|
| 0.0 m | driveway | 0.822 | 0.776 | 0.749 |
| 0.5 | driveway | 0.839 | 0.775 | 0.773 |
| 1.0 | driveway | 0.837 | 0.751 | 0.760 |
| 1.5 | driveway | 0.850 | 0.772 | 0.736 |
| 2.0 | driveway | 0.844 | 0.777 | 0.754 |
| 2.5 | driveway | 0.837 | 0.776 | 0.786 |
| 3.0 | driveway | 0.834 | 0.797 | 0.821 |
| 3.5 | driveway | 0.850 | 0.827 | 0.850 |
| 4.0 | sidewalk | 0.859 | 0.835 | 0.831 |
| 4.5 | sidewalk | 0.856 | 0.814 | 0.836 |
| 5.0 | sidewalk | 0.849 | 0.813 | 0.818 |
| 5.5 | driveway (boulevard) | 0.822 | 0.815 | 0.802 |
| 6.0 | driveway (boulevard) | 0.807 | 0.775 | 0.777 |
| 6.5 | driveway (boulevard) | 0.764 | 0.730 | 0.772 |
| 7.0 – 10.0 | road | 0.535 – 0.541 | 0.531 – 0.554 | 0.534 – 0.555 |

All four wheels are on the road once the truck has moved about 11.1 m.

**The owner's run**, reproduced before the fix: a new game, the keys found, the real controls, 12 s
each.

| case | moved | top speed | what stops it |
|---|---|---|---|
| forward, blade up | 0.00 m | 0 | the stuck rule ("Stuck: 80 cm…"); the bog rule too (ahead 0.84, push-back 1.34× the engine) |
| forward, blade down | 0.00 m | 0 | the stuck rule |
| reverse | −0.90 m | 0.15 m/s (0.5 km/h) | the stuck creep, then the garage (a collision) |
| cleared lane, blade up / down | out to the road | 38 km/h | nothing: no collision with the curb or the sidewalk edge |

**The reading of the code in the brief:**

- *The starting snow, 0.70–0.88 m on the driveway:* **confirmed.** It is 0.73–0.86 m on the path,
  0.75–0.84 m under the wheels, and 0.53–0.55 m on the road.
- *The wheels: stuck at 0.60; the truck only creeps at 15 % either way:* **corrected.**
  - Forward doesn't creep at all. The stuck factor is clamp(1 − (0.80 − 0.60) / (0.34 × 0.5)) × 0.25,
    which is 0 for anything deeper than 0.77 m, so the forward limit is exactly 0.
  - Reverse creeps only because the reverse limit has a +1 m/s floor: 0.15 × 1.0 = 0.15 m/s.
- *Forward, blade up: above the bog depth, bogged from a standstill; with a run-up, the push-back
  stops it:* **confirmed.** The front probe reads 0.84 (shove_x 1.34).
  - There is also no room for a run-up: 0.9 m to the garage.
  - The snow under the parked truck is just as deep, so the speed is capped at 1.27 m/s there.
- *Forward, blade down: the wheels still stuck; the clearance-scaled drag means it barely creeps
  until its wheels reach the plowed ground:* **corrected.**
  - It doesn't creep at all: the stuck factor is 0.
  - The clearance-scaled drag (0.068 at 0.80 m) only slows it.
  - The berm doesn't stop it either: blade_push's berm is a volume (×CELL_AREA), about 1.5 m³ against
    the 2.8 capacity at the start.
- *A collision:* **none** on the way out (the cleared-lane runs above).

## What changed

- **`pickup_stuck_depth` 0.6 → 0.9**, in `data/balance.tres`, the default in `balance_data.gd` and the
  generator.
  - It is now above the opening's deepest (`opening_max_depth`), so the first morning's snow never
    holds the wheels, and a major event's still does.
  - The "snowed in" message on getting in and the "Stuck…" message read the same value.
- **The bog depth counts from the snow the truck stands in** (`vehicle.gd`, round 5 §12's bog rule,
  `is_pickup()` only):
  - `bog_at = pickup_bog_depth + _sunk`. `_sunk` is the snow the truck stands in above
    `pickup_shove_floor`, and that snow (`_axle_depth()`) is the lower wheel of each axle, averaged.
    On bare ground or in its own shoved track it is 0, so §12 is unchanged there.
  - `_sunk` is read when the driver gets in (as after a load) and while the truck moves, and kept
    while it stands still. Without that, snow slumping into its lane under a stopped truck lifted the
    bog depth and un-bogged it. That made round 5's "70 cm untouched bogs down" test fail: the truck
    crept on at 2 km/h.
- **The snowed-in message** on getting in a pickup now says it "only creeps until you dig around
  them", where it said "It won't move". The truck does creep there: its reverse always does, as the
  playtest found. Other vehicles' message is unchanged.
  - The bogged message gives `bog_at` ("about N cm").
  - The wall (`pickup_bank_max`) still reads the raw snow ahead.
- **Nothing else changed:**
  - no other balance value (`pickup_bank_max` stays at 95 cm: nothing on the way out reaches it);
  - not the plow path, the shove, the snow landing or the draws;
  - not the other vehicles, the starting snow, the keys, the tutorial or the shovel.

Why both changes: the stuck depth alone fixes blade down and reverse. Blade up, the truck would still
be bogged from a standstill (84 cm ahead, bog depth 70 cm) with no room for a run-up, so it would be
stuck for good. A higher `pickup_bog_depth` (it would need more than 0.84) would change every blade-up
depth for both trucks and break round 5 §12's tests.

## After the fix

New game, the keys found, nothing shovelled, the real controls. The results are identical for the 3
seeds × 2 modes.

| case | result |
|---|---|
| getting in | no "snowed in" (0.80 m under the wheels, stuck from 0.90) |
| reverse | −0.90 m to the garage at up to 1.73 m/s (6.2 km/h); blade down 1.31 m/s, back-dragging |
| forward, blade up | 3.7 m at up to 4 km/h, then bogged once all four wheels are on its own track: "Snowbank ahead: 86 cm deep — too much to push from a standstill (about 70 cm). Back up with S…" |
| forward, blade down | 14.7 m in 10 s: 0.5–0.7 m/s while the wheels are in the deep snow, up to 12.8 km/h on the cleared lane, pushing the berm |
| **plow-out, blade down** | **all four wheels on the road in 8.9 s, 1 pass**, never stuck, top 12.8 km/h |
| **run-ups, blade up** | **all four wheels on the road in 42.6 s, 5 pushes** (to +3.7, 4.1, 4.7, 5.6 m, then out), backing up to the garage each time, never stuck |
| a 100 cm bank (`pickup_bank_max` + 5 cm) | a wall: on Maple Street with a 4 m run-up, and 1.5 m ahead of the parked truck |
| volume | conserved: under 1e-4 m³ over the whole map in every run |

Blade down, the scripted plow-out never needs a second pass. The plow path's berm drag (unchanged)
slows it, but the berm never gets big enough in the 1.6 m² window in front of the blade to stop it. The
driveway's snow ends up as a pile on the street, up to about 3.9 m high. That's for the owner to judge
(`PLAYTEST.md` item 14).

Blade up, a short back-up (1.5 s) isn't enough: the snow under where the truck was parked (0.8 m)
holds the run-up to about 2 m/s. Backing up to the garage is.

## Tests (`tests/test_polish7.gd`, "Playtest fix 1")

Each of the first three runs over 3 seeds × 2 modes (`PF1_GAMES`), from a new game as it starts. The
keys flag is set, nothing is shovelled, and the clock is stopped. The player gets in with the interact
key, the throttle, reverse and angle actions are held, and the blade moves with the real Down/Up keys.
The time counts every frame from the first press.

- `test_pf1_getting_in_and_backing_up`: in the truck with the interact key. The wheels are under the
  stuck depth, and so is the opening's deepest. No snowed-in message. Reverse moves it more than 0.3 m
  in 1 s (the old creep made 0.15 m), never stuck.
- `test_pf1_plow_out_blade_down`: the first pass moves it from the parked spot. All four wheels reach
  the road within 180 s, never stuck, under half its top speed, volume within 1e-4.
- `test_pf1_run_ups_blade_up`: the first push moves it, blade up. It bogs with "…standstill… Back up
  with <reverse key>". All four wheels reach the road within 180 s, never stuck, volume within 1e-4.
- `test_pf1_a_bank_above_the_limit_stops_it`: a bank at `pickup_bank_max` + 5 cm stops it with "too
  much to drive through (about 95 cm at most, with a run-up)", on Maple Street with a 4 m run-up and
  in front of the parked truck in the opening's snow.
- `test_pf1_getting_back_in_reads_the_snow`:
  - Setup: the truck is driven on a bare street, parked, then left standing in 75 cm (the bog depth
    + 5 cm), as after storms.
  - Getting back in, it pushes off (3.5 m) and doesn't bog.
  - Without the reset on getting in, it stays bogged at 0.0 m: checked by removing the line and
    running the test.
- `test_pf1_snowed_in_still_says_so`: for both trucks, 95 cm around the wheels.
  - Getting in says "…snowed in: about 95 cm of snow around the wheels. It only creeps until you dig
    around them…".
  - It does creep: −0.32 m back and 0.00 m forward in 2 s each, with "Stuck: … only clears about
    90 cm".
- `test_pf1_a_long_stretch_bogs_anywhere_across_the_street`: round 5's 70 cm stretch with a 13 m
  run-up, for both trucks at z 84.80, 84.86, 84.90 and 84.98.
  - Every run bogs and stays bogged with the throttle held, 7.7–13.9 m in.
  - Averaged over the four wheels, the plain pickup drove through at 84.86 and 84.90 (probe): one
    wheel line was in the untouched snow.

**Updated, through lookups** (they asserted the old opening, which this fix deliberately changes):

- `test_polish5.gd` `test_s12_opening_by_the_numbers` (both trucks):
  - Was: the opening's snow is above the stuck depth, "snowed in", it doesn't move.
  - Now: it is under the stuck depth (and `opening_max_depth` is too), no "snowed in", it backs up,
    and it pushes forward until it bogs on its own track with the "Back up with" message.
  - The dug-out check runs at the parked spot again, in a fresh new game, as before. It also checks
    the bog depth in the message ("about 70 cm"). The cleared-driveway check is unchanged.
- `test_gameplay.gd` `test_vehicle_plow_and_stuck_pickup`:
  - The opening's snow is checked to be under the stuck depth.
  - The stuck check itself is unchanged (moved < 2 m, wheels deeper than the stuck depth). It now runs
    with the snow around the truck set to `pickup_stuck_depth` + 5 cm, and also checks the "only clears
    about N cm" message.
- `test_gameplay.gd` `test_truck_keys_end_to_end`:
  - Was: the opening holds it, and it says "Stuck… about 60 cm".
  - Now: it backs up, then drives forward until "Snowbank ahead… cm deep… Back up with <key>" with
    `pickup_bog_depth`'s "about N cm".
  - It then backs to the garage, so the dig-out, windrow and plow part runs as before.

Run and passing:

- polish7: `test_pf1_` (7), `test_s10_` (6), `test_s11_` (8)
- polish5: `test_s12_` (6, both trucks)
- gameplay: `vehicle_plow`, `plow_pushes`, `truck_keys`
- polish5: `s3_road_rule`
- polish6: `test_s1_data_generator_reproduces_data`, `test_s9_` (5)
- the parse check (92 scripts, 0 errors)

## Screenshot (`docs/polish7/shots/pf1-plow-out/`)

- `truck_on_the_street_after_plowing_out.jpg`: the first morning, after the blade-down plow-out
  (`shot.gd --plow_out=down`).
  - The truck stands on Maple Street with its yellow blade down and the driveway's snow piled in
    front of it.
  - The plowed lane, down to the blade's floor, runs back up the driveway toward the garage.
- One earlier framing, from across the street, wasn't kept: the pile in front of the blade hid the
  truck and the lane.

## Review (four reviewers, each finding checked by a skeptic)

Eight findings were confirmed. They come down to four problems, all fixed, and the tests above were
rerun after the fixes.

1. **A stale value under a parked truck** (two findings).
   - The snow the truck stands in was held from the last time it moved. A truck parked on bare ground
     and snowed on stayed bogged from a standstill until it was moved. A save and load read the snow
     fresh, so it pushed off.
   - Fixed: getting in reads it (`_sunk = -1` in `enter_vehicle`).
   - New test: `test_pf1_getting_back_in_reads_the_snow`.
2. **"Snowed in … It won't move", while the truck creeps** (four findings).
   - Decision 3: the message only when the truck really can't move. Its reverse always creeps, so it
     never truly can't.
   - Fixed: the pickups' message says it only creeps.
   - The opening test had lost the only check that the message still shows. New test:
     `test_pf1_snowed_in_still_says_so`.
3. **The plain pickup's uncleared wheel line.**
   - Its 2 m shove ends at its wheels. At some places across a street, one wheel line stayed in the
     untouched snow, lifted the bog depth, and the pickup drove through a 70 cm stretch (probe: z 84.86
     and 84.90).
   - Fixed: the snow it stands in is the lower wheel of each axle.
   - New test: `test_pf1_a_long_stretch_bogs_anywhere_across_the_street`.
4. **The dug-out check had moved off the parked spot.**
   - Restored in `test_s12_opening_by_the_numbers`, in a fresh new game.
   - Digging around the wheels alone now bogs the truck from a standstill, where without digging it
     pushes off slowly. This is noted for the owner (STATUS, Issues).

Twelve findings were rejected by the skeptics:

- No snow falls on Dec 2 before the keys can be found.
- The plow-out in one pass is within the brief.
- The brief's Then items were already done in the working tree.
- The `truck_keys` test backs up to where it was.
- The reverse speed and a reverse tap re-reading the slumped lane are accepted and documented.
- The deeper-snow-is-easier reading misreads the rule.
- A major event's smallest still holds the truck.
