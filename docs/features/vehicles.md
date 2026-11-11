# Vehicles

## What it does for the player

- **Your truck.** A new game starts with your pickup truck and its front plow in the driveway, nose to
  the street. It's locked until you find the keys, which are buried by the tree on the front lawn. On
  the first morning it's snowed in: dig the snow from around its wheels and clear the driveway.
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
  - Blade down, driving forward pushes the snow ahead into a berm.
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
    blade up or down. The snowed-in message on getting in uses the same limit.
  - **Round 5 §12's snow rules,** with the blade up:
    - the drag under the wheels scaled by `pickup_drag_depth`;
    - the shove (`_shove`): a V of two `Snow.blade_push` arms at the front, floor `pickup_shove_floor`;
    - the push-back: `pickup_bog_depth`, `pickup_shove_drag`, and below `pickup_shove_min_speed` it
      bogs;
    - the wall at `pickup_bank_max`;
    - their messages ("Stuck…", "Snowbank ahead…", "…from a standstill… Back up with <reverse key>").
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
  - The `vehicle_blade_width` and `vehicle_clear_speed` upgrades (`ItemUpgrades.mult`) widen the blade
    and lower its drag.
- **Back-drag** (blade down, reversing: `speed < 0` and the frame's travel backward):
  - `back_drag()` calls `Snow.blade_push` with the face turned toward the vehicle.
  - The band is the frame's reverse travel + 0.1 m, the same rule as a push's.
  - The snow lands `DRAG_CAST` (0.3 m) behind the blade: 0.1–0.62 m with blade_push's band and its
    draw. That keeps it against the back face and clear of every blade vehicle's front wheels, which
    stand 1 m or more behind the blade.
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
  plowed truck (`S12_TRUCKS`).
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
- Pushing unchanged: `--only=gameplay --test=vehicle_plow`, `--test=plow_pushes`,
  `--only=snow --test=test_blade_push`, `--only=polish6 --test=test_s3_blade`, `--test=test_s9_`.
- Shots: `tests/shot.gd --back_drag=frames [--drag_lift=1]`.

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

## Known issues

- The dump truck still uses the generic deep-snow path (stuck from 48 cm, walled from 80 cm), worse
  than the pickup (round 6 §3, left for a later round).
- With the blade down, the plowed truck's drag under the wheels is still scaled by its clearance (the
  plow path as before). Only its stuck depth is the pickup's.
