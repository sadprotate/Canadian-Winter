# Polish 7 — playtest fix 3: a solid blade, a visible width upgrade, the truck home overnight

Brief: `docs/polish7/PLAYTEST_FIX_3.md`.

## What the code showed (confirmed)

- **The collision box** is built in `vehicle.gd._ready()`: `width × height × 0.75 × length`, centred
  on the vehicle. The blade (`blade_node`, pivot from `VehicleModels`) has no collider.
  - Straight, it reaches past the box by 0.18 m on the pickup, 0.40 m on the ATV, 0.59 m on the tractor
    and 0.46 m on the plow truck.
  - Angled 30°, it reaches 0.76 m, 0.76 m, 1.17 m and 1.29 m past the box.
  - The grader's blade sits under the body. Its ends stick out 0.55 m to each side.
  - (These are the gaps the test measured between the body and the wall, with the blade stopped
    against it.)
- **The low colliders.** The only one is the ground: a box with its top at y = 0. The porch's ramp
  starts below the ground in front of the steps. Curbs, sidewalks, driveways and snow have none.
  - The vehicle's own box starts 0.075 × its height above the ground (9–25 cm).
  - Each frame off the floor it is sent 3.3 cm down, then held at y = 0.
- **The plow width upgrade** widens the strip the snow op clears. `VehicleModels` built the blade at
  a fixed width: 2.4 m yellow on the pickup and the tractor, 1.5 m yellow on the ATV, 3.4 m dark grey
  on the plow truck, and a 3.7 m metal box on the grader.
  - `Game.upgrades_changed` is emitted on every grant (buying an immediate upgrade, collecting a
    crate, the store's plow), but nothing listened to it.
- **Sleeping** (`game_root._do_sleep()`) moved no vehicle. A CharacterBody3D's position set from a
  script reaches the physics server only at its next step (kinematic bodies). That mattered for §3,
  below.

## What changed

**§1 The blade is solid** (`vehicle.gd`, `vehicle_models.gd`):
- `VehicleModels` now returns `blade_box` for every plow: the space the plate (tilted 12°: its box),
  its cutting edge and any lamps fill in the blade's frame. The arms behind the plate aren't counted.
- Each plow vehicle gets a second box on its body, `blade_cs`. `_fit_blade_shape()` fits it to the
  blade as it stands, every physics frame before the move: its width, its angle (Z / C) and its lift.
- Its bottom is the blade's own, raised with it, but never under `BLADE_CLEAR` (0.1 m) above the
  ground. That is three times the frame's 3.3 cm drop, and below every wall's bottom (they start at the
  ground).
- Getting out never drops the player in it: `exit_vehicle()` skips an exit spot within the player's
  radius + 0.1 m of the blade's shape. The shape is checked as it stands and as it will stand once
  turned to its angle (it trails the angle keys by up to 6°). Only the grader's blade, beside its cab,
  can cover a spot: with the width upgrade, angled more than a few degrees toward that side. Everywhere
  else the spot is the same as before.
- Being the body's, it stops against what the body stops against. A wall the blade swings or turns
  into pushes the vehicle back out (the physics' recovery).
- The raised blade's 0.18 m is now the constant `BLADE_LIFT` (the same value).

**§2 The plow width upgrade shows** (`vehicle_models.gd`, `vehicle.gd`):
- `VehicleModels.build(vd, blade_mult := 1.0)`. With `blade_mult` above 1 (the upgrade's
  multiplier), the blade is:
  - `blade_mult` × as wide: the strip it clears;
  - `UPGRADED_TALL` (1.2) × as tall;
  - `UPGRADED_BLUE` (0.1, 0.36, 0.92), a clear mid blue;
  - topped by two lamp housings on brackets along its top edge.
- The lenses are a mesh of their own (`blade_lamps`). The vehicle gives them the headlights' warm
  white, emissive, while its headlights are on; otherwise they are plain glass. No light source.
- At 1 the model is the same mesh as before. The main menu, the framed photo and the city's grader
  and sidewalk plow still call `build(vd)` and are unchanged.
- The vehicle builds at its upgrade's multiplier in `_ready` (so after a load too). On
  `Game.upgrades_changed` it rebuilds the blade on the spot: the model, the lenses and the solid
  shape.

**§3 The truck goes home overnight** (`game_root.gd`, `vehicle.gd`):
- `_do_sleep()` calls `send_truck_home()` after the city's grader finishes, before the player goes to
  bed, before the night passes (`Clock.skip`) and before the save.
- The truck is the first `is_pickup()` vehicle (the lowest uid: an older save's own truck, not a plowed
  pickup the store delivered).
- `Vehicle.park_at()` puts it at `Game.truck_start()`'s position and yaw, stopped, blade raised. Its
  blade angle, load, roof snow and upgrades stay, the snow isn't touched, and the keys don't matter.
- **A vehicle (or a walk-behind machine) on the spot** moves first: to the nearest place on a 0.5 m
  grid over the player's lot and driveway, facing as it did, where its boxes stay inside them and
  0.1 m clear of everything solid (a physics query) and of the truck's spot.
- **The truck goes home two physics frames later.** Placed at once, the physics still had the other
  vehicle where it stood, on the spot, and pushed the truck off its spot in the first frame (the
  first run of the test showed it). Bodies moved here are left out of later queries, and later moves
  keep clear of where they stood and where they stand.

## Tests

The "playtest fix 3" group in `tests/test_polish7.gd`:

- `test_pf3_the_blade_stops_at_walls`. Every plow (the pickup with its plow, the ATV, the tractor,
  the plow truck, the grader) is driven at the player's garage door and at a house wall. The blade is
  up and down, straight and angled both ways, with a 3 m run-up: 60 runs.
  - Every run stops, and no point of the blade's shape is ever inside the footprint: **0.0000 m**
    (`PF3_INSIDE` allows 5 mm).
  - The blade ends 1 mm from the face. The blade met the building first in 48 runs; the 12 others
    were the grader, whose body reaches first.
  - Then each one is pressed against the garage door, blade angled, steered left and right, and its
    blade swung across: 0.0000 m inside.
  - The house wall: a tree on the player's lawn stands in front of every 4.5 m stretch of their front
    wall, so the test takes the first house with a clear stretch (11 Maple, its wall a solid box right
    at its footprint).
- `test_pf3_the_truck_starts_clear`. The truck starts at `truck_start()` overlapping nothing, also with
  the upgrade. Every plow's lowered blade shape starts 0.10 m up (the grader's 0.15 m). Every frame
  while the blade turns and lifts (down and up, straight and angled both ways), every vertex of the
  visible plate lies inside the shape, the part under `BLADE_CLEAR` aside.
- `test_pf3_getting_out_beside_the_blade`. Getting out of every plow with the width upgrade, at nine
  blade angles, the blade settled or still turning 6° behind its angle: never into the blade, as it
  settles.
  - Before the exit fix it failed for the grader at −10° and −20°.
  - Before checking the turning blade it failed for the grader at −8° while turning.
- `test_pf3_the_width_upgrade_shows`. For every plow:
  - Without the upgrade: the same mesh as before; the yellow blades yellow; no lamps; the shape as
    wide as the strip.
  - The upgrade granted, as collecting its crate does, on the vehicle already in the world:
    - the model and the shape are 2.760 / 1.725 / 2.760 / 3.910 / 4.255 m wide, equal to the strip;
    - the plate is 1.20 × as tall;
    - the blade is blue, with two lenses on top;
    - they glow at night (the headlights on) and not at noon.
  - No balance value changes. The truck parked in the driveway changes too, and save → load keeps it.
- `test_pf3_the_truck_goes_home_overnight`. The truck left on Maple Street, at the store's lot (119 m
  away) and pushed 2 m off its spot and turned, the keys found or not, its blade at 20°, then a real
  `_do_sleep()`:
  - it wakes at 7:00 at `truck_start()` (0.0000 m), facing as at the start;
  - blade raised, angle and roof snow kept;
  - the ATV left on the street hasn't moved;
  - save → load keeps it home.
- `test_pf3_a_vehicle_on_the_spot_moves_clear`. The ATV, then the tractor, parked on the spot:
  - they move 2.10 m and 2.65 m, inside the yard, overlapping neither the truck nor anything else;
  - the truck is home, still after 30 frames;
  - the snow volume is the same, and a pickup on the street hasn't moved.

## The review

A review workflow ran three reviewers (the solid blade and the look, the truck home, the tests). A
skeptical verifier then checked each finding.

- **One real finding, fixed:** getting out of the upgraded grader with its blade angled put the player
  inside the blade's shape, to be shoved off it (the exit fix above).
- **Six rejected, with reasons:**
  - The "as before" mesh check compares the new code with itself. But each part of the old look is
    also checked against fixed values: the colours, no lamps, the widths.
  - The "blade raised" check can't see a lowered blade. But a parked truck's blade is always raised:
    sleep is only from the bed.
  - The wall test only measures the shape, not the visible blade.
  - The plow truck's colour check also matches its arms.
  - The balance check can't see the ruled-out changes. No data file changed.
  - The test's yard check took the lot and driveway's bounding box.
- **Two of the rejected points were still worth taking:**
  - A new check that the shape holds the visible plate every frame. It found a real gap: raised, the
    shape's bottom sat at `BLADE_CLEAR` + the lift (0.28 m), above the plate's lowest edge (about
    0.21 m), so 1–2 cm of the raised blade wasn't solid. Fixed: the bottom is now the blade's own, raised
    with it.
  - The yard check is now the lot or the driveway, as the code does.
- **A second review of the two fixes found one more real case, fixed.** Getting out while the
  blade is still turning: the spot was checked against the blade where it was drawn, and the blade
  then turned onto the player. Now the spot is also checked against the angle the blade settles at.
  The test reproduces it before the fix (the grader at −8° while turning).
- **Older than this fix, found while testing the exit:** getting out of a vehicle 3.2 m tall or more
  (the plow truck, the grader, the rotary blower, the dump truck) shifts it about 0.5 m and shoves the
  player about 1 m. The physics keeps the player inside the cab for one more frame, with its collision
  back on. The bladeless dump truck and rotary blower do it too. Left as it is (STATUS.md Issues).

## Tests run (all pass)

- Parse check: 92 scripts, 0 errors.
- **polish7, the whole suite, after the review's fixes: 31 passed.** That is fix 3's 6 new tests, with
  §10, §11, fix 1 and fix 2. It covers the brief's no-snagging list:
  - fix 1's plow-out tests;
  - fix 2's long pushes;
  - §11's back-drag from the garage door, which drives up blade up, lowers it at the door and backs away.
- gameplay: `vehicle_plow`, `plow_pushes` (`test_plow_pushes_yard_snow_onto_road`), `hidden_shovel`,
  `truck_keys` (before and after the review's fixes); `sleep_saves`, `computer_apps`, `snowfall_adds`
  (before).
- Every other test that drives a plow, sleeps or builds a vehicle's model, before the review's fixes
  (`test_s12_` and `test_s9_auto_return` again after them):
  - polish3 and polish4 `fixtures_load` (each sleeps);
  - polish4 `photo`;
  - polish5 `fixtures_load`, `s2_no_conflict`, `s3_road_rule`, `s4_photo`, `s6_one_icon`, `test_s9_`
    (8), `s10b_street`, `test_s11_` (6), `test_s12_` (6), `test_s13` (12);
  - polish6 `test_s81` (12), `s82_full_load`, `test_s9_` (5), `test_s3_blade`.
- After the second review's fix (getting out only): polish7 `test_pf3_` (6), `test_s11_` (8), gameplay
  `truck_keys`.
- No existing test needed changing: none assumed the truck stays put across a sleep. The sleeping
  tests either start with the truck at home, or check other things after the sleep.
- Not run: the full suite (CI runs it on the PR) and perf. The blade's shape is one more box per plow
  vehicle, refitted only while the blade moves.

## Screenshots

Three taken, two kept (`docs/polish7/shots/pf3-solid-blade/`):

- `blade_stopped_at_the_garage_door.jpg` (`--solid_blade=wall --blade_angle=30 --blade_down=1`): the
  truck driven at the garage door, blade down and angled 30°. Its leading end stopped flush with the
  door (1 mm), nothing inside.
- `upgraded_blade_at_night.jpg` (`--solid_blade=front --blade_upgrade=1 --hour=22`): the upgraded
  blade, blue, wider and taller, its two lamps lit with the headlights.
- Not kept: the same at noon, taken to check that the blue reads against the snow by day (it does;
  the lamps are unlit).
