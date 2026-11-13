# Polish 7 — playtest fix 3: a solid blade, a visible width upgrade, the truck home overnight

This is a playtest fix for Polish 7 (`CLAUDE.md`, *After the playtest*).

- **Work on `cw-polish7-pg`.** Don't create a branch, and don't open a PR.
- **New chat?** Read `CLAUDE.md`, then `docs/polish7/STATUS.md` and `docs/features/vehicles.md`.
  Then check out `cw-polish7-pg` and pull.
- **Save this prompt** as `docs/polish7/PLAYTEST_FIX_3.md`.

## What the owner found

Fix 2 feels good. Three things to fix:

1. **The blade goes through the garage door.** The truck's body stops at the door, but its blade
   ends up inside the garage.
2. **The plow width upgrade doesn't show.** Plow power works, but width "did not seem to change".
3. **The truck can end up shoved somewhere it shouldn't be.** In the playtest, Gerry pushed it out of
   his way. The owner's answer is a soft reset: when the player sleeps, the truck goes back to its
   parking spot at home.

## Leave these alone (the owner's decisions)

- **Gerry:** don't change him. A later round will give the keys only after Gerry's walk is done by
  hand or shovel, so the truck can't be used for it.
- **The city's grader and sidewalk plow:** no changes. Don't make them stop, wait or honk. A vehicle
  in their way still gets pushed for now.
- **The Upgrades app's layout:** Bare Hands, the missing truck icon and the plain "Other items" lines
  are for the owner's upgrade redesign. Don't touch them.
- **Other vehicles' parking:** bought vehicles don't get home spots yet. They stay where the player
  leaves them.

## What the code shows (confirm it, then fix it)

- **The collision box.** It is built in `vehicle.gd._ready()` as `data.width × data.height × 0.75 ×
  data.length`, centred on the vehicle. The blade is a separate mesh (`blade_node`, pivot from
  `VehicleModels`: the plowed pickup at z −3.05 with a 6.0 m body) that sticks out in front of that
  box and has no collision of its own. Turning the blade with Z/C swings its ends out further. Every
  plow vehicle is built the same way.
- **The plow width upgrade** (`plow_width`, Blade Wing Extensions, ×1.15) widens the strip the snow
  op clears (`vehicle.gd`: `data.blade_width × ItemUpgrades.mult(…, &"vehicle_blade_width")`).
  But `VehicleModels` builds the blade at a fixed width in the base yellow
  (`Color(0.95, 0.75, 0.1)`), so it looks the same.
- **Sleeping** is `game_root._do_sleep()`. Nothing moves vehicles there.

## 1. The blade is solid

- **Which vehicles:** every plow vehicle the player drives (`data.has_plow`): the pickup with plow,
  the ATV, the tractor with blade, the plow truck and the player's grader. The city's grader and
  sidewalk plow aren't touched.
- **What it does:** the blade stops against whatever stops the vehicle's body: walls, doors and
  garage doors, buildings, posts, fences. The vehicle stops with the blade against it. **No part of
  the blade ever goes inside a building**, blade up or down, straight or angled either way.
- **How:** the solid shape follows the blade as it is at that moment: its width (with the width
  upgrade, §2), its angle (Z/C) and its height (up or down).
- **What it must not do:** the blade's shape never catches on the ground, curbs, the sidewalk or
  snow, which has no collider. Check what the low colliders are, and keep the shape above them.
- **These keep working:**
  - plowing out of the driveway (fix 1)
  - long pushes (fix 2)
  - pushing yard snow onto the road
  - back-drag from the garage door (§11): drive up with the blade up, lower it at the door, back
    away
- **The spawn spot:** the truck still spawns at `truck_start()` without overlapping anything.

## 2. The plow width upgrade shows

With `plow_width` bought, on every vehicle that has the track:

- **The size:** the blade model is as wide as the strip it clears (×1.15), and a bit taller (about
  +20 %).
- **The look:** it has **two plow lamps on top**. They are procedural lamp housings that glow
  (emissive) while the vehicle's headlights are on. Add no new light sources.
- **The colour:** it is **blue** instead of yellow. Pick a clear blue that reads against snow at noon
  and at night.
- **Without the upgrade:** the blade stays exactly as it is now.
- **When it changes:** the model and its solid shape (§1) change as soon as the upgrade takes effect,
  without a reload, and stay changed after save → load.
- **The look only:** no balance value changes (`blade_capacity`, drag and the clearing width stay as
  they are).

## 3. The truck goes home overnight

- **When the player sleeps,** the player's truck (`is_pickup()`) goes back to its home spot,
  `Game.truck_start()`, facing as it does at the start, with its blade raised.
- **What stays:** its blade angle, upgrades, roof snow and everything else stay as they were.
- **The order:** do it before the night passes, so the night's snow falls around it at home, and
  before the save.
- **The snow:** the snow at the spot isn't touched. If the player buried the spot, the truck sits in
  that snow, as any parked truck would.
- **Another vehicle on the spot:** move that vehicle just clear of it, to the nearest free place in
  the driveway or yard, never overlapping anything.
- **The rest:** other vehicles stay where they are. The truck goes home whether or not the player
  has the keys yet.

## Done when

Tests go in `tests/test_polish7.gd`, as a "playtest fix 3" group.

- **The solid blade:** for every plow vehicle, drive at the player's garage door and at a house
  wall: blade up and down, straight and angled both ways.
  - The vehicle stops.
  - No point of the blade's shape is ever inside the building's footprint.
- **No snagging:** fix 1's plow-out tests, fix 2's long-push tests,
  `test_plow_pushes_yard_snow_onto_road` and the §11 back-drag tests pass.
- **The width upgrade:**
  - With the upgrade, the blade model's width and its solid shape's width equal the cleared width,
    within 5 cm. The blade is blue and has its two lamps.
  - Without it, the blade is yellow with no lamps, and its width is as now.
  - Buying the upgrade changes the blade on the vehicle already in the world, and save → load
    keeps it.
- **The truck goes home:**
  - Park the truck on the street, at the store lot, and pushed off its spot. After sleeping, it is
    at `truck_start()`, facing as at the start, blade raised.
  - Other vehicles haven't moved, and the snow volume is unchanged by the move.
  - A vehicle parked on the spot is moved clear with no overlap.
  - Save → load keeps the truck at home.
- **Existing tests:** any test that assumes the truck stays put across a sleep is updated through
  lookups. Never loosen it.
- **Screenshots (2):** the truck stopped with its blade against the garage door, from outside; the
  upgraded blade (blue, lamps lit) at night.

## Then

- Update `docs/features/vehicles.md`: the solid blade, the upgraded blade's look, the truck going
  home overnight.
- In `GAME.md`'s "What's in the game now", add one line: the truck goes home when you sleep.
- In `docs/polish7/PLAYTEST.md`, add what to re-check:
  - Drive the truck into the garage door and a house wall, blade up, down and angled. The blade stops
    at the door.
  - Buy the plow width upgrade. The blade turns blue, grows wider and taller, and gets lamps that
    light with the headlights.
  - Leave the truck on the street and sleep. In the morning it's back in the driveway.
- Update `docs/polish7/STATUS.md`.
- Commit as `polish7: playtest fix 3 — a solid blade, a visible width upgrade, the truck home
  overnight`, and push. Then stop and wait for the owner.
