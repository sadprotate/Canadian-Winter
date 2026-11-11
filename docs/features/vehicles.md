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
  - The blade toggle (left mouse) raises or lowers the blade.
  - The angle keys turn it.
  - Blade down, driving forward pushes the snow ahead into a berm.
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

## Decisions

- Round 5 §12: the plain pickup got its own snow handling (`pickup_*` balance values, the shove).
- Round 5 §13: the front plow became the pickup's upgrade, fitted in the store lot.
- Round 7 §10: the truck starts with its plow, locked by the keys. The front plow is no longer sold.
  - With its blade up, the plowed truck has the pickup's snow handling. Its wheels are the pickup's
    either way. Before this, it used the generic path: stuck from 39 cm and walled from 65 cm.
  - The shove's cast scales with the truck's width.
  - No balance value changed.

## Known issues

- The dump truck still uses the generic deep-snow path (stuck from 48 cm, walled from 80 cm), worse
  than the pickup (round 6 §3, left for a later round).
- With the blade down, the plowed truck's drag under the wheels is still scaled by its clearance (the
  plow path as before). Only its stuck depth is the pickup's.
