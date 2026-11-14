# The garage

## What it does for the player

- The house has a garage you can use: a door from the house (in the kitchen's right wall, steps
  down), an overhead door you open and close with the button inside, a tool rack on the wall, a
  concrete floor and a ceiling light.
- The door from the house is locked until the truck keys are found ("Locked: the keys are
  missing."); you can always let yourself out of the garage.
- The plowed pickup (blade up or down, angled, with the width upgrade), the plain pickup of old
  saves, the ATV and the walk-behind blowers fit. Bigger vehicles stop at the door line, and the
  status line says "Too big for the garage."
- The rack: F puts the tool in your hands on it; E on a racked tool takes it back (into a free tool
  slot), or swaps it for the one you hold. Tools keep their upgrades (they follow the item type).
- The heated pad can lie on the garage floor; it doesn't melt anything or use power there.
- No snow gets in. A vehicle inside gathers no roof snow, and what it brought in melts off.
- Sleeping with the truck in the garage leaves it there.
- The first time you go in, a hint shows the button and the rack.

## How it works

- **The shell** (`HouseBuilder`, player's lot only: `lot["is_player"]`; every other lot keeps the
  solid shell): walls built inward from the old solid garage's faces (siding outside, so it looks
  the same; paint inside), the door opening (`GAR_DOOR_X0..X1` × `GAR_DOOR_H`) framed by the old
  trim, a concrete floor, a ceiling (`GAR_CEIL`), the house wall's garage face painted, the door
  from the house (`HDOOR_Z0..Z1` in the house's right wall, `hollow_colliders(..., garage_door)`),
  two steps and a landing (`STEPS_Z0`, `LANDING_Z0..Z1`) with a ramp collider for the player.
- **Collision:** the walls are on layer 1. A block round the steps is on `VEHICLE_ONLY_LAYER` (every
  vehicle's mask has it; the player's doesn't). The doorway's gate is on `GARAGE_GATE_LAYER`: only a
  vehicle that doesn't `Vehicle.fits_garage()` (height under the door, length under 6.5 m) has it
  in its mask; touching it sets the status line.
- **The overhead door** (`scripts/world/garage.gd`, no `class_name`, made by `game_root._build_garage`):
  HouseBuilder builds its 4 sections closed (`garage_door`, so the menu shows it); the Garage node
  runs them up the tracks and under the ceiling (`place_garage_door`, `DOOR_TIME`). Its collider
  fills the opening from gz0 inward (its outer face is the old solid face: a blade stops where
  polish 7 measured) and rises with the door. The button (E) refuses to close it with the player, a
  vehicle or a walk-behind in the doorway ("Something is in the way of the garage door.").
- **The rack:** `Catalog.balance.garage_rack_slots` slots on the house-side wall, the real tool models
  (`ToolModels.mesh_for`). F is read in `game_root._unhandled_input` only on foot inside the garage
  (`Settings.accept_press("store")`); it hangs the carried tool (never the pad) or the selected one,
  on the looked-at slot if empty, else the first free one; "The rack is full." otherwise. E on a slot
  takes into a free slot, else swaps. `Game.owns_tool`, `game_root.has_shovel` and the Property app
  count it. (The Garage Tool Rack upgrade's rack outside the front wall is separate and unchanged.)
- **Saved:** `Game.garage = {door_open, rack}`, save key `game.garage` (version 3, optional; default
  closed and empty). The door from the house has no key: it follows `flags.truck_keys`.
- **Parking and sleep:** `game_root.in_garage(vehicle)` (every corner of its solid boxes in the
  footprint). `send_truck_home()` leaves a truck that is in the garage; `_clear_place()` never moves
  a vehicle into the garage or the house. Getting out inside picks a spot where the player fits
  (`Vehicle._player_fits`).
- **Snow:** the garage's cells are `S_BLOCKED` (they always were: walls for every snow operation,
  spill and relaxation; no snowfall). Throws stop at its face (round 5 §3's rule) and blade pushes
  keep the snow outside. The ground-snow mesh is hidden inside its footprint (`snow_hide_c`, as the
  houses' `snow_hide_a/b`; `game_root.snow_hide_rects()`).
- **Climate:** `Player.in_garage` / `Survival.in_garage` (the footprint; the driver too). Sheltered,
  not heated (§14 reads it). Roof snow: `game_root._vehicle_snow_step` adds none to a vehicle inside
  and melts its `snow_load` at `garage_snow_melt_per_hour` on the clock.
- **The pad:** `Equipment.pad_garage_ok(rect)` (the clear floor, off the steps) lets it down there;
  `Heating.sources()` leaves it out there.
- **The light:** an emissive fixture (off in a power cut) and an OmniLight, visible only while the
  player is inside or within `Garage.LIGHT_NEAR` (checked in the 0.5 s light pass).
- **The hint:** `garage` (HelpText.GARAGE), opened the first time `player.in_garage`.

## Where it lives

- `scripts/world/house_builder.gd` (`_usable_garage`, `_usable_garage_colliders`, `garage_door`,
  `place_garage_door`, the constants), `scripts/world/garage.gd`, `scripts/game/game_root.gd`
  (`_build_garage`, the house door in `_build_doors`, F, `in_garage`, `send_truck_home`,
  `_clear_place`, `_vehicle_snow_step`, `snow_hide_rects`), `scripts/vehicles/vehicle.gd` (masks,
  the status, `fits_garage`, `_player_fits`), `scripts/data/equipment.gd` / `scripts/world/heating.gd`
  (the pad), `scripts/autoload/game_state.gd` (`garage`), `shaders/snow_ground.gdshader`
  (`snow_hide_c`).

## Connects to

- [vehicles.md](vehicles.md) (sleep, parking), [hints.md](hints.md), [controls.md](controls.md)
  (store), `Buildings` (the garage footprint was already registered), `Saves`.

## How to test

- `--only=polish8 --test=test_s15_`: the house door, the overhead door, parking (12 pickup runs, the
  ATV, a blower, a tractor), no overlap, sleep, the rack, the pad, no snow inside, climate and the
  hide rect, the hint.
- Also: polish7 `test_pf3_` (the blade stops at the door), polish5 `test_s3_` (walls, throws, the
  registry), `test_s13b_`, the fixture tests, `perf.tscn -- --only=garage`.

## Decisions

- Round 8 §15: the existing shell made usable (no new building); the overhead door only from its
  button; the house door follows the keys flag; a second rack (the upgrade's untouched; owner's
  answer 4); sizes judged against the door and bay (tractors and bigger stop); the door won't close
  on something in the doorway; the light follows the house's power; F works anywhere inside.

## Known issues

- A walk-behind blower being pushed has its collider off, so it passes through the steps, the walls
  and the closed door like everywhere else (round 5; not changed).
- With the truck and the ATV both in, there's little room left for the blowers and the pad.
