# Vehicles

## What it does for the player

- **Your truck.** A new game starts with your pickup truck and its front plow in the driveway, nose to
  the street. It's locked until you find the keys, which are buried by the tree on the front lawn. On
  the first morning it stands in about 80 cm of snow, but it isn't snowed in: it backs up, and it gets
  out to the street on its own.
  - Blade down (the main way), it plows its way out.
  - Blade up, it pushes off slowly, bogs in the driveway's snow, and gets out with run-ups from the
    garage.
- **Driving** (all keys rebindable): drive forward and brake/reverse, steer, handbrake, the camera,
  the horn, the radio forecast, and get out.
- **In deep snow, blade up,** the truck handles like a pickup:
  - It drives through storm snow, slower the deeper it is.
  - It shoves deeper snow ahead and out to the sides.
  - It bogs down in snow too deep to push from a standstill. Back up and take a run at it.
  - A bank above the grille is a wall.
  - The status line says what is in the way, with the numbers.
- **Plows** (your truck, the ATV, the tractor with blade, the plow truck, the grader):
  - Down lowers the blade and Up raises it. The blade toggle (left mouse) does either.
  - The angle keys turn it.
  - Blade down, driving forward pushes the snow ahead into a pile. The pile tumbles: snow rolls down
    its front and off both ends of the blade into ridges along the lane, and nothing sticks up out of
    it. It reaches its full size within 10–20 m (about 1.5 m tall in 30 cm of snow) and then stays that
    size; the rest goes into the ridges. Stopping leaves one rounded mound. The truck feels the load.
  - **Blade down, reversing drags the snow back with you (back-drag).** Drive up to a garage door or
    a wall with the blade up, lower it, and back away: the snow comes away with the blade. Raise the
    blade or drive forward and it stays where it is as a pile, which you can then push away. The status
    line reads "Blade down — dragging".
- **Blowers** (the tractor with blower, the rotary blower) throw the snow through a turnable chute. The
  **dump truck** dumps its bed at the municipal snow dump or anywhere else.
- The store sells the other vehicles. Your truck and its plow are your own: neither the plow nor the
  truck is for sale.

## How it works

- One controller, `Vehicle` (`scripts/vehicles/vehicle.gd`), runs every vehicle the player drives. It
  reads its data from `VehicleData` (`data/vehicles/*.tres`). The city's grader (`grader_npc.gd`) and
  the sidewalk crew are separate.
- **The truck:** `is_pickup()` is true for `Kind.PICKUP` (the plain pickup, kept by older saves) and
  `Kind.PICKUP_PLOW` (`pickup_plow`, a new game's truck). For both:
  - **The keys:** without `Game.flags.truck_keys` the prompt reads "(locked)" and E gives the locked
    message.
  - **The wheels:** it is stuck with more than `pickup_stuck_depth` under the wheels (`stuck_depth()`),
    blade up or down. The snowed-in message on getting in uses the same limit. It is above the first
    morning's deepest snow (`opening_max_depth`; Dec 1 is always dry), so the opening never holds the
    wheels; a major event's snow does.
  - **Round 5 §12's snow rules,** with the blade up:
    - the drag under the wheels scaled by `pickup_drag_depth`;
    - the shove (`_shove`): a V of two `Snow.blade_push` arms at the front, floor `pickup_shove_floor`;
    - the push-back: `pickup_bog_depth`, `pickup_shove_drag`, and below `pickup_shove_min_speed` it
      bogs;
    - the wall at `pickup_bank_max`;
    - their messages ("Stuck…", "Snowbank ahead…", "…from a standstill (about N cm)… Back up with
      <reverse key>").
  - **The bog depth counts from the snow the truck stands in** (playtest fix 1). That snow
    (`_axle_depth()`) is the lower wheel of each axle, averaged over the axles. Its depth above
    `pickup_shove_floor` (`_sunk`) adds to `pickup_bog_depth`. On bare ground or in its own shoved
    track it adds nothing, so round 5 §12 is unchanged there.
    - Parked in the opening's 80 cm, the snow ahead (84 cm) pushes back less than the engine pulls,
      so it moves off slowly. Once both axles are in its own shoved track, the driveway's snow ahead
      is above the bog depth again and it bogs, as §12 intends.
    - The lower wheel of each axle: a wheel line its shove doesn't clear doesn't count. The plain
      pickup's 2 m V ends at its wheels, so at some places across a street one of its wheel lines
      runs in the untouched snow. A wheel off its cleared track in a turn doesn't count either.
    - `_sunk` is read when the driver gets in (as after a load) and while the truck moves, and kept
      while it stands still. Snow that slumps into its lane under a stopped truck (the body's guard is
      only renewed while it shoves) doesn't lift it out of a bog.
    - The bogged message gives this bog depth ("about N cm").
    - The wall (`pickup_bank_max`) reads the raw snow ahead, whatever the wheels stand in.
  - **Snowed in:** getting in with more than `pickup_stuck_depth` under the wheels says so with the
    depth, and that it only creeps until you dig around the wheels. It does creep: its reverse always
    does (the stuck rule's 15 %), and forward until half the clearance deeper. Other vehicles' message
    still says they won't move.
  - **The shove's cast** is `SHOVE_CAST` for the plain pickup's 2 m (`SHOVE_CAST_WIDTH`), in
    proportion for a wider truck (the plowed truck's 2.4 m). That keeps the snow ahead of the raised
    blade and clear of the truck's path.
  - **Blade down,** the plowed truck plows exactly as a plow does (below); only its stuck depth is the
    pickup's.
- **Other vehicles:**
  - stuck above `clearance × 1.15`;
  - a bank above `clearance × 1.9` is a wall;
  - the drag under the wheels is scaled by the clearance.
  The dump truck still uses this generic path.
- **Plowing** (blade down, `tool_on`), each physics frame:
  - one `Snow.blade_push` at the blade (`blade_z`), face along the travel direction turned by the blade
    angle;
  - band = the frame's advance + 0.1 m, cast 0.6 m, floor `blade_floor`, no road rule;
  - `player_guard` keeps the 2 m behind the blade from slumping back;
  - the berm ahead slows the vehicle (`blade_capacity`), and caps the bank check (`clearance × 1.5`).
    The berm is the snow across the blade (playtest fix 2; before, all of it within 0.65 m):
    - all of it within 0.65 m ahead of the face (`Snow.BERM_FACE`), as before;
    - plus, out to `berm_reach(hw)` = `BERM_REACH_BASE` + `BERM_REACH_PER_HW` × the blade's half-width,
      the pushed snow there (player-moved, loose): the pile the blade drives, not untouched snow it
      hasn't reached. That is 0.95 m for the ATV, 1.22 m for the pickup and the tractor, 1.52 m for
      the plow truck, and 1.61 m for the grader.
    - Back-drag reads the same. Hand pushes read 0.65 m, as before.
    - Only the reading reaches further: the push works on, marks and relaxes the same cells as before.
  - The `vehicle_blade_width` and `vehicle_clear_speed` upgrades (`ItemUpgrades.mult`) widen the blade
    and lower its drag.
- **How a pushed pile forms** (playtest fix 2; `Snow.blade_push` and `Snow._roll`, the same op for
  every plow, back-drag and hand pushes):
  - Each lifted cell's snow lands spread over round 6 §9's band ahead of the face, as before (one
    `push_rng` draw per moved cell, marked `soft`).
  - A share doesn't stack where it lands. Whatever would make a cell stand more than `moved_repose`
    above its lowest open neighbour rolls on to that neighbour, and on down the pile (steepest descent,
    up to `ROLL_STEPS` cells), in the same op: over the pile's front and out past the blade's ends.
    Ties go to the neighbour furthest ahead of the blade, then furthest out, so the pile forms the same
    whichever way the blade faces. No random draws; volume exact (what the cells store is counted).
  - Walls for the roll: buildings, a completed box from outside, off the map, the blade (the cells
    behind its face across its width), and the guarded strip behind the face. The curb stops it only
    where it stops the push (`player_rule`): every plow and hand tool carries its snow over the curb,
    so its pile tumbles over it too. The relaxation still treats the curb as a wall.
  - The 6 m ceiling still caps every cell; what finds no room stays in front of the blade (`kept`).
  - So the pile's height comes from the moved-snow slope and the ground it covers. On level snow the
    pile in front stops growing after 10–20 m: the snow rolling off the blade's ends balances what the
    blade takes in (about two thirds of a 100 m push ends up in the ridges).
  - The relaxation then rounds the tops as before (round 6 §9's `moved_crest`), a few millimetres at a
    time. The edge of the lane the blade cut settles once the guard has passed, as before.
  - The pickup's shove (blade up) passes `tumble = false`: its snow lands as before, so its driving
    rules (round 5 §12, playtest fix 1) don't change.
- **Back-drag** (blade down, reversing: `speed < 0` and the frame's travel backward):
  - `back_drag()` calls `Snow.blade_push` with the face turned toward the vehicle.
  - The band is the frame's reverse travel + 0.1 m, the same rule as a push's.
  - The snow lands `DRAG_CAST` (0.3 m) behind the blade: 0.1–0.62 m with blade_push's band and its
    draw, against the back face. It tumbles on toward the vehicle as any pushed pile does (playtest
    fix 2), so a big drag's pile runs out toward the front wheels at once (before, it settled there
    over a few seconds).
  - `player_guard` guards the ground it uncovers, on the blade's far side.
  - Polish 6 §9's rules hold: the spread band, `soft` marks, one `push_rng` draw per moved cell.
    Volume is exact.
  - The berm (the dragged pile) slows it like a push: while dragging, the reverse limit is also capped
    at `reverse_speed × work_drag`.
  - Snow the blade's ends don't cover stays beside its path, as a plow's windrow does.
  - `dragging` is true for the frame, for the status line and the HUD line ("— dragging").
- **Standing still** with the blade down, the blade holds the side it last worked (`_drag_side`):
  - After a push, it is the push's 0.1 m band, as before. Lowering the blade starts there.
  - After a back-drag, it is the drag's band on the uncovered ground, so the pile stays against the
    blade's back and nothing goes back through it.
- **Driving forward off a dragged pile** (blade down, `_leaving_drag`):
  - The push takes only the ground the blade has crossed since it stopped dragging (`_drag_stop`),
    half a cell clear of that line, because the cell on the line holds some of the pile.
  - Its guard reaches a cell past the face, so the pile's front can't slump into the gap and be
    carried off.
  - Once the blade is a push's margin past the line, it pushes as always. The pile stays where it
    was.
- **Blade keys:** `veh_blade_up` / `veh_blade_down` (see [controls.md](controls.md)), read in `_input`
  before the GUI.
  - `set_blade(down)` changes the blade only when it isn't already that way, then `_toggle_tool()`
    gives the click and "Blade down" / "Blade up".
  - `has_blade()` is a plow with no dump bed. On the plain pickup, the blower vehicles and the dump
    truck the keys do nothing.
  - `veh_tool` still toggles: it raises or lowers a blade, runs a blower, dumps a bed.
- **Volume** is conserved: every snow move is `Snow.blade_push` (or the blowers' intake and thrown
  snow). Only the dump truck's dump at the municipal lot removes snow (ledgered).
- **The front plow upgrade** (`ItemUpgrades.PLOW_ID`, the `front_plow` track) is no longer sold:
  - `track_shown` hides it and `why_not` says "No longer sold."
  - The track stays in the catalog, so old saves keep their granted plow.
  - The store still fits the plow to a plain pickup driven into its lot when a save holds an open plow
    order.
  - The Upgrades app shows the truck's own tracks (plow width, plow power) on one card.
- **First drive:** the controls panel (`Panels.vehicle_help`) shows once per vehicle kind
  (`help_vehicle_<kind>`).

## Where it lives

- `scripts/vehicles/vehicle.gd`: driving, snow handling, plow, blower, dump, status and HUD line.
- `scripts/vehicles/vehicle_models.gd`: models, wheels, `blade_pivot`, `blade_z`.
- `data/vehicles/*.tres`, mirrored in `tools/data_gen/generate_data.gd` (`_vehicles()`).
- `scripts/autoload/game_state.gd`: `new_game()` (spawns `pickup_plow` at `truck_start()`),
  `truck_start()`, `shovel_spot()`.
- `scripts/game/game_root.gd`: `spawn_vehicle_node`, `install_plow`, `show_vehicle_help`.
- `scripts/data/item_upgrades.gd`: `front_plow`, `PLOW_ID`, `GROUP`, `track_shown`, `why_not`.
- `scripts/world/store.gd`: fitting an old order's plow.
- `scripts/world/framed_photo.gd`, `scripts/ui/main_menu.gd`: the truck with its raised blade in the
  photo and the menu's home shot.

## Connects to

- `Snow`: `blade_push`, `push_rng` (one draw per moved cell), `soft` marks, `set_blade_guard`,
  `depth_at`.
- `Catalog.balance`: the `pickup_*` values.
- `Settings`: the vehicle actions, `accept_press`, `action_label`.
- `Contracts`: see [contracts.md](contracts.md).
- Saves: vehicle entries `{uid, id, pos, yaw, snow, bed, blade}`. The blade's up/down isn't saved: it
  is up after a load.

## How to test

- `--only=polish7 --test=test_s10_`:
  - a new game's truck and where its blade fits;
  - the keys lock;
  - 50 cm under the wheels, blade up and down;
  - a bank with a run-up;
  - where the shove lands;
  - contracts.
- `--only=polish5 --test=test_s12_`: round 5's pickup-in-snow tests, for the plain pickup and the
  plowed truck (`S12_TRUCKS`). `test_s12_opening_by_the_numbers`: the opening's snow under the stuck
  depth, no snowed-in message, it backs up and pushes forward until it bogs on its own track.
- `--only=polish7 --test=test_pf1_` (playtest fix 1).
  - From a new game, over 3 seeds in both modes, with the keys found, nothing shovelled and the real
    controls:
    - getting in (interact) says nothing about being snowed in, and reverse moves it;
    - blade down, a scripted plow-out (push, raise, back up, lower, angle, again) gets all four
      wheels onto the road within 3 minutes, never stuck, under half its top speed, volume exact;
    - blade up, run-ups from the garage get it out within 3 minutes, bogging on the way, never stuck.
  - A bank above `pickup_bank_max` still stops it with its message, on the street with a run-up and
    from the parked spot.
  - On Maple Street:
    - parked after driving on bare ground, then left in snow above the bog depth: getting back in, it
      pushes off;
    - with more than `pickup_stuck_depth` around the wheels, both trucks say they're snowed in and
      only creep, and they do;
    - a long stretch at `pickup_bog_depth` bogs both trucks, and holds them, at four places across
      the street.
- `--only=gameplay --test=truck_keys`: the keys end to end, then out through a windrow across the apron
  with the blade up, then the blade lowered, plowing.
- `--only=gameplay --test=vehicle_plow`, `--test=plow_pushes`.
- `--only=polish5 --test=test_s13_`: the front plow isn't sold; the Upgrades card.
- `--only=polish4 --test=photo`, `--only=polish5 --test=s4_photo`: the photo.
- `--only=polish7 --test=test_s11_`:
  - the blade keys on every vehicle;
  - one back-drag step: the draws, the band, the marks, the volume;
  - back-drag from the garage door: the snow away from the door, the volume exact, the slowdown,
    standing still, driving forward, the pile left after the blade lifts;
  - driving off the pile from five starts across a cell.
- `--only=polish7 --test=test_pf2_` (playtest fix 2):
  - the op alone (no relaxation between steps), for a plow straight and angled, a hand tool and
    back-drag: after every step no player-moved cell over the moved-snow step (1e-6 m), one draw per
    moved cell, the volume exact;
  - the pickup pushing 50 m and 100 m of 30 cm: no cell over the step every frame (`PF2_SPIKE`, the
    relaxation's passes), the top under `PF2_TOP`, one mound, the same after 100 m as after 50 m, no
    faster than before the fix, the volume exact;
  - the opening, 15 m blade down, 3 seeds in both modes;
  - every plow (straight; the pickup's and the plow truck's also angled), hand pushes, back-drag.
- Pushing unchanged: `--only=gameplay --test=vehicle_plow`, `--test=plow_pushes`,
  `--only=snow --test=test_blade_push`, `--only=polish6 --test=test_s3_blade`, `--test=test_s9_`.
- Shots: `tests/shot.gd --back_drag=frames [--drag_lift=1]`; `--plow_out=down|up` (the way out on the
  first morning); `--long_push=m [--push_depth=d]` (the pile after a long push, from the driving camera;
  `--cab=1` the cab view, which shows only the inside of the cab).

## Decisions

- Round 5 §12: the plain pickup got its own snow handling (`pickup_*` balance values, the shove).
- Round 5 §13: the front plow became the pickup's upgrade, fitted in the store lot.
- Round 7 §10: the truck starts with its plow, locked by the keys. The front plow is no longer sold.
  - With its blade up, the plowed truck has the pickup's snow handling. Its wheels are the pickup's
    either way. Before this, it used the generic path: stuck from 39 cm and walled from 65 cm.
  - The shove's cast scales with the truck's width.
  - No balance value changed.
- Round 7 §11: Up and Down raise and lower the blade.
  - Back-drag uses the existing blade op, with the face turned toward the vehicle.
  - Standing still, the blade holds the side it last worked. Otherwise a stopped truck's push would
    send the dragged pile back through the blade.
  - Driving off a dragged pile, the blade leaves the pile: the brief's "drive forward, and the snow
    stays where it is".
  - Dragging caps the reverse speed by the berm's drag: the old reverse limit hid it below about 3 m³.
- Round 7 playtest fix 1: the truck gets out of the driveway on the first morning. In the playtest it
  couldn't go forward at all: the opening's 80 cm was above `pickup_stuck_depth`, so deep that the
  stuck rule's creep factor was 0, and reverse only crept at 0.15 m/s.
  - `pickup_stuck_depth` went up to above the opening's deepest.
  - The bog depth counts from the snow the truck stands in: the lower wheel of each axle, read when
    the driver gets in and while it moves, and held while it stands still.
  - The pickups' snowed-in message says the truck only creeps, which is what it does.
  - Nothing else changed: no other value, the plow path, the shove, the other vehicles.
- Round 7 playtest fix 2: pushed snow tumbles instead of spiking. In the playtest the pile in front of
  a long push spiked: each frame the blade dropped a row of its own pile back onto the pile, and the
  relaxation couldn't keep up (cells up to 0.45 m over the moved-snow step at 30 cm, 0.8 m for the
  plow truck; the pile's top 2.2 m, 4.1 m in the opening against the curb).
  - The blade op rolls what would stand over the step on down the pile (`_roll`), for every blade.
  - The owner's call: keep the pile as it comes out, a steady mound at the moved-snow slope (the same
    after 50 m and 100 m), not one held to the blade's height that keeps growing longer.
  - The pile's roll crosses the curb where the push does.
  - The plows' berm drag reads further ahead (`berm_reach()`), so a long push is no easier.
  - The shove keeps its old placement (its driving rules stay).

## Known issues

- The dump truck still uses the generic deep-snow path (stuck from 48 cm, walled from 80 cm), worse
  than the pickup (round 6 §3, left for a later round).
- With the blade down, the plowed truck's drag under the wheels is still scaled by its clearance (the
  plow path as before). Only its stuck depth is the pickup's.
- On the first morning the blade-down truck plows out of the driveway. Since playtest fix 2 its pile
  stands about 2.3 m at most (3.9–4.1 m before, stacked against the curb).
- Playtest fix 2's drag reading is a little harder than before for every plow: 3–9 % slower on level
  30 cm snow, the opening's first 15 m about 11 s (10 s before). No single reading matches each
  plow's old drag, which depended on how high its spike stood, so it was set so that none is easier.
  With the plow width upgrade the pickup is 16 % slower (15 km/h in 30 cm, 18 before): its wider
  blade's pile is bigger, and a shorter reach barely changes it.
- Hand pushes keep their 0.65 m berm reading. Most walk within 3 % of before; the wide pusher in 15 cm
  is 6 % and the large scraper 14 % faster (their pile lies a little further out).
  But in deep snow the wide pusher no longer walls you in: before playtest fix 2 its pile stood above
  the hips in front of it after about 2 m (the wading rule stopped you); now it tumbles away and you
  keep pushing, slowly.
- While the blade passes, the edge of the lane it cuts stands steep for a moment just past its guard
  (the guard holds 2 m), until the relaxation settles it, as before the fix.
- The roll costs time inside the push: one `blade_push` call takes about 0.27 ms for the pickup's
  plow and 1.05 ms for the plow truck, against 0.06 ms and 0.18 ms before playtest fix 2. In
  `perf.tscn`'s plow scenario that is about 1 ms more per frame on average, and 0.5 ms more
  relaxation at p95.
- Backing up onto its own track where snow has slumped back in raises the bog depth by that snow (a
  few cm for the plowed truck; up to about 25 cm for the plain pickup, whose track is narrower), so
  a run-up carries a little further there.
- Digging out only around the wheels makes the truck bog from a standstill against the snow ahead,
  where without digging it pushes off slowly. That is round 5's dug-out case, unchanged, and the
  message says to back up and take a run. The Help app and the keys message still tell the player
  to dig around the wheels.
- The stuck rule keeps round 5's creep: from `pickup_stuck_depth` to half the clearance deeper the
  truck creeps forward, and its reverse always creeps. The status line still says "Stuck…".
