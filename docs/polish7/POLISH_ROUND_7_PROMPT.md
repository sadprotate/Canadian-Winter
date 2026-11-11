# Canadian Winter — Polish Round 7

**Round number: 7.**

## Start here: read CLAUDE.md, then follow it

1. **Read `CLAUDE.md` at the repo root, in full, before anything else.** It holds the rules for every
   round: git, questions, testing, screenshots, feature docs, the final check and the end of the
   round. It is binding, and this brief doesn't repeat it.
2. **Read `GAME.md`.** `CLAUDE.md` links it: it describes how the game is meant to play, and each
   section is checked against it.
3. **Follow `CLAUDE.md`'s *Starting a round*, steps 1–9, in order.** In particular:
   - Switch to `main`, pull, and check that `git status` is clean.
   - **Create the work branch `cw-polish7-pg` from `main`** (all lowercase). All of this round's work
     goes on it. Never commit or push to `main`.
   - If `cw-polish7-pg` already exists, locally or on GitHub, don't create, reset or replace it.
     Stop and ask the owner.
   - Save this brief as `docs/polish7/POLISH_ROUND_7_PROMPT.md`.
   - Start `docs/polish7/STATUS.md` with one checklist line per section, then the three headings
     `## Questions`, `## Check at the end` and `## Issues`.
   - Check that you can work (Godot 4.7.2, the import, `parse_all`, one suite).
   - Ask all your questions in one message, then start.
4. **Do §10, then §11.** Then do `CLAUDE.md`'s *Final check* and *End of the round*: feature docs,
   GAME.md's lines, `PLAYTEST.md`, commit and push the branch, and the report. Then stop and wait
   for the playtest. **No PR until the owner approves the playtest.**

This brief says **what** to build. It has two sections, carried over from Round 6. They keep their
Round 6 numbers, so the carried-over list stays easy to follow:

- **§10 — The plow truck from the start, good in snow**
- **§11 — Blade up/down, push and pull**

Do §10 first: §11 needs the plowed truck. The rest of Round 6's carried-over list (§7, §12–§16) is
for later rounds. Don't start any of it.

---

## Where things stand

- `main` is at `dcd0b78` or later. Round 6 was merged as PR #2 (`2f840ed`). It finished §0–§3, §8.1,
  §8.2, §9 and §8.1b, then stopped. Today's commit added `GAME.md` and rewrote `CLAUDE.md`.
- There is no `docs/features/` folder yet. This round creates the docs for the features it touches
  (see *Feature docs*).
- **Read for these sections** (not HANDOFF in full):
  - `docs/polish6/STATUS.md`, *Binding notes*:
    - **§1:** any data change goes into the generator too.
    - **§2:** a new `class_name` is reached by `preload` from older scripts. Simplest: don't add one.
    - **§3:** `Snow.blade_push` draws from `Snow.push_rng`, and the dump truck shares the generic
      vehicle path.
    - **§9:** the blade deposit spreads over `PUSH_BAND`, marks snow `soft`, makes one `push_rng`
      draw per moved cell, and has the guard and `GUARD_SETTLE_STEPS`.
  - `docs/polish5/report/s12.md`: the pickup in snow (stuck, bank, bog, shove).
  - `docs/polish5/report/s13a.md`: upgrades per item (the `front_plow` track, `GROUP`).
  - `docs/polish5/report/s2.md`: keys, the settings migration, the press cap.

## Decisions (already made — apply them)

1. **The truck starts with its plow (§10).**
   - **The truck:** a new game starts with the existing `pickup_plow` vehicle where the plain pickup
     starts now, snowed in as now. The keys are still buried by the lawn tree and still needed.
   - **Not sold:** the front plow is no longer sold anywhere.
   - **No old saves to support** (the owner). Add no conversion and no refund. Saves and test
     fixtures that hold the plain `pickup` load and play exactly as today. Don't regenerate
     fixtures.
   - **Good in snow.** The plowed truck is the same truck as the plain pickup, with a plow on it.
     - **Today it is much worse in deep snow.** Only the plain pickup gets round 5 §12's snow
       handling. The plowed pickup uses the generic vehicle path, so it gets stuck from 39 cm of snow
       under the wheels and is walled by 65 cm ahead. The plain pickup handles 60 cm under the wheels
       and 95 cm ahead with a run-up.
     - **Its wheels:** they get stuck at the plain pickup's depth (`pickup_stuck_depth`), blade up
       or down.
     - **Blade up:** it drives and shoves through snow by every rule round 5 §12 gave the plain
       pickup: the `pickup_*` balance values, the shove, the bog, the bank with a run-up, and their
       messages. It is never worse in deep snow than the plain pickup.
     - **Blade down:** it plows, as the plowed pickup does now.
     - The balance values don't change: the plowed truck reads the same `pickup_*` values.
   - **Contracts:**
     - The starting truck counts as hand tools in `Contracts.equipment_capability()`, so listing
       sizes don't change.
     - It satisfies the "plow or blower vehicle" requirement of street listings
       (`listing_needs_vehicle`). They stay locked by reputation.
     - Other plow and blower vehicles count as now.
2. **Blade up/down and back-drag (§11).**
   - **The keys:** two new vehicle actions, `veh_blade_up` (Up arrow) and `veh_blade_down`
     (Down arrow).
   - **Which vehicles:** every vehicle with a blade that the player drives (`data.has_plow`): the
     pickup with plow, the ATV, the tractor with blade, the plow truck, and the grader the store
     sells. The city's grader (`grader_npc.gd`) is not touched.
   - **The blade:** it keeps its two positions, up and down. The existing `veh_tool` toggle (left
     mouse) stays as it is.
   - **Pull means back-dragging:** with the blade down and the vehicle reversing, the blade drags
     snow back with it. Lifting the blade leaves the snow as a pile. It uses the existing blade op
     (`Snow.blade_push`), and volume is conserved exactly.

## Known before you start (don't ask about these)

- **GAME.md differences the owner already knows about:** GAME.md says bidding isn't built (round 5
  built it), and it calls the neighbour Jerry (the game says Gerry). Note them under `## Issues` only
  if your sections run into them.
- **A known flaky test:** polish3's `test_menu_fixture_load_is_the_same_as_direct` fails under load
  and passes alone (Round 6). If it fails in the final check, run it alone and note the result under
  `## Issues`. Don't fix it this round.
- **The Snow Dump Truck** (the store's $38,000 truck) shares the generic deep-snow path with the
  plowed pickup today (Round 6 §3). This round makes only the plowed pickup good in snow. Leave the
  dump truck as it is.
- **No performance run** is needed: neither section adds a new kind of work per frame. Back-drag is
  the same blade op a push already runs.
- **Suite times on the owner's PC:** polish5 takes about 20 min and polish6 5–12 min. Run them in the
  background.

---

## §10. The plow truck from the start, good in snow

> Start with a snowplow on the truck and not a purchase from equipement. if the player finds the key
> he as asscess to the truck to push pull snow.

One package, three parts:

- **(a)** The truck starts with its plow, locked until the keys are found.
- **(b)** The front plow isn't sold.
- **(c)** The plowed truck is as good in snow as the plain pickup.

**Look at first** (search, don't read whole files):

- `Game.new_game()`: it appends `"pickup"`. `Game.truck_start()` and `Game.shovel_spot()` are the
  single sources for where the truck and the shovel are.
- `vehicle.gd`:
  - The keys lock checks only `Kind.PICKUP` (`interact_prompt`, `interact`).
  - The round 5 §12 branch (`var pickup := data.kind == VehicleData.Kind.PICKUP` in
    `_physics_process`), `stuck_depth()` and `_shove()`.
- The front plow:
  - `ItemUpgrades`: the `front_plow` track is added for `Kind.PICKUP` in `tracks`, along with
    `PLOW_ID`, `GROUP` and `why_not`.
  - `store.gd`: the order that fits the plow in the store lot.
  - `computer_ui.gd`: the "Fitted" and "drive the pickup to the store" lines.
  - `Catalog.store_vehicles()` already leaves out both pickups.
- `Contracts.equipment_capability()`, `listing_needs_vehicle()` and how listing size reads the
  capability (`EQUIP_RATE`).
- Showing the truck:
  - `framed_photo.gd`: the photo builds `Catalog.vehicle(&"pickup")`.
  - `main_menu.gd`: the home shot builds the plain pickup and computes its own copy of the truck's
    position.
- The first-drive help panel (`game_root.show_vehicle_help`, `panels.gd`), and the truck lines in
  `help_text.gd` (the truck line and Gerry's keys line).

**Build:**

- **A new game spawns `pickup_plow` at `truck_start()`**, snowed in as now. The shovel and the keys
  are unchanged.
  - Check that the blade fits in the driveway: clear of the sidewalk, the shovel spot, the mailbox
    and the keys.
  - If it doesn't fit, move the truck toward the garage only as far as needed, through
    `truck_start()`. Make the menu shot use the same place.
- **The keys lock the plowed truck.** Without the keys its prompt reads "(locked)" and E gives the
  locked message, exactly as the plain pickup does now.
- **(c) Good in snow** (Decision 1):
  - **Its wheels:** the plowed truck gets stuck at `pickup_stuck_depth`, blade up or down.
  - **Blade up:** every one of round 5 §12's snow rules applies to it, as to the plain pickup: the
    drag, the shove, the bog, the bank with a run-up, and their messages. In
    `vehicle.gd._physics_process` those rules are behind
    `var pickup := data.kind == VehicleData.Kind.PICKUP`, and `stuck_depth()` has the same check.
  - **The shove:** with the blade up, check that the shoved snow lands ahead of the raised blade
    and clear of the truck's path, as the plain pickup's does.
  - **Blade down:** the plow path, as now.
  - Change no balance value.
- **The front plow isn't sold.**
  - It is gone from the Equipment store and from the Upgrades app.
  - The Upgrades app still shows the truck's own tracks (plow width, plow power) on one card, as
    `GROUP` does now. Nothing says "Fit the front plow first."
  - Leave the store's existing plow-fitting code alone. Only an order that a fixture already holds
    can reach it, and that fixture must still load.
- **Contracts** follow Decision 1. With the starting truck, `equipment_capability()` is what it would
  be with no vehicle at all, and a street listing isn't locked for "Needs a plow or a blower
  vehicle".
- **The truck shows its plow:**
  - in the framed photo (round 5 §4), which still shows the shovel where it lies buried
  - in the main menu's home shot
- **Text:** reword the help line about the truck, or Gerry's keys line, only where they read wrong
  for a truck that already has its plow. The first-drive help panel gets §11's keys (see §11).

**Done when** (new tests in `tests/test_polish7.gd`, suite `polish7` added to
`tests/test_runner.gd`, set up the way `test_polish6.gd` is):

- A new game owns `pickup_plow` and no plain pickup.
- The keys end-to-end test runs with the plowed truck:
  - it's locked without the keys
  - the keys are found
  - it drives out with the blade up through the driveway windrow
  - it lowers the blade and plows

  (`test_truck_keys_end_to_end` updated through lookups.)
- **Good in snow:**
  - Round 5's §12 tests (`test_s12_*` in test_polish5) pass for the plowed truck with the blade up,
    as well as for the plain pickup. Use a lookup over both ids.
  - The plowed truck, blade up or down, isn't stuck in 50 cm of snow under the wheels (the plain
    pickup's 60 cm limit applies). Today it is stuck from 39 cm.
  - With the blade up, it gets through a bank as deep as the plain pickup does with the same run-up.
    Today it is walled from 65 cm.
- The front plow isn't offered in the store or in Upgrades (`test_s13_ownership_and_the_front_plow`
  updated through lookups).
- On day one, the listing sizes for a seed are the same as with no vehicle. A street listing isn't
  vehicle-locked with the starting truck (`test_s10b_street_needs_a_vehicle` updated through
  lookups).
- These pass: the photo tests (`test_photo_on_the_wall_beside_the_door`,
  `test_photo_scene_is_isolated`, `test_s4_photo_hint_and_view`), the menu tests, and the fixture
  tests (polish3, polish4, polish5 and polish5_v3 saves, which hold the plain pickup).
- **Screenshots (2):** the opening's driveway with the plowed truck, and the framed photo.

**Tests this section deliberately changes** (update through lookups, never delete, skip or loosen):

- the new-game vehicle id
- the front-plow purchase
- the plowed truck's deep-snow limits
- the contract lock for street listings

---

## §11. Blade up/down, push and pull

> have the snow plow be able to push and pull. have a up and down for the blade with up and down
> arrow.

**Build:**

- **The actions.** Add them to `Settings.ACTIONS` in the vehicle context:
  - `veh_blade_up`: "Raise the blade", Up arrow
  - `veh_blade_down`: "Lower the blade", Down arrow

  Add both to `RATE_LIMITED`, and send their presses through `Settings.accept_press()`. The
  settings menu lists them in its Vehicle group, with the conflict check. Existing players get the
  new defaults through the existing migration (no `CONTROLS_VERSION` bump).
- **What they do.**
  - On every vehicle in Decision 2, Down lowers the blade (`tool_on = true`) and Up raises it.
  - A press that changes nothing does nothing.
  - On a vehicle without a blade (the plain pickup, the blower vehicles, the dump truck) the keys do
    nothing.
  - `veh_tool` (left mouse) still toggles the blade.
  - The blade already animates between its two heights; keep that.
- **The arrows are also Godot's `ui_up` / `ui_down`.** Check that a press still reaches the vehicle
  after the player has clicked a HUD button (for example the fast-forward buttons). A focused
  control must not swallow it.
- **Push** (blade down, driving forward): unchanged.
- **Pull, or back-drag** (blade down, reversing):
  - **How it works:** the blade takes the snow it passes over on its far side and carries it toward
    the truck. Use `Snow.blade_push` with the face turned toward the truck, the band set by the
    reverse travel, and the guard on the uncovered side.
  - **While reversing:** the dragged snow stays against the blade's back face.
  - **Leaving the pile:** raise the blade (Up or left mouse) or drive forward, and the snow stays
    where it is as a pile, which can then be pushed away.
  - **Today:** with the blade down, the push runs whatever the direction (`adv + 0.1`). Reversing
    must back-drag instead. Standing still adds nothing new.
  - **It keeps §9's rules:** the spread band, the `soft` marks, and one `push_rng` draw per moved
    cell. No global `randf()` touches where snow lands.
  - **Driving:** it slows the vehicle like a push, the vehicle isn't blocked by its own pile, and
    volume is conserved exactly.
  - **Typical use:** drive up to a wall or a garage door with the blade up, lower it, back away.
- **Status and help.**
  - The status line reads "Blade down" and "Blade up", and "Blade down — dragging" while
    back-dragging. `hud_text()` shows it too.
  - The first-drive help panel (`panels.gd`) and Help list the Up and Down keys beside the existing
    blade keys.
  - Every key label comes from `Settings.action_label()`.

**Done when** (tests in `tests/test_polish7.gd`):

- Up and Down raise and lower the blade on every vehicle in Decision 2. They are ignored on the plain
  pickup, the blower vehicles and the dump truck.
- After rebinding both actions, the new keys work and the old ones do nothing. The defaults conflict
  with nothing in the vehicle context.
- A press reaches the vehicle with a HUD control focused.
- **The back-drag test:**
  - setup: snow piled against a wall (the house wall or a garage door), the blade lowered at the
    wall, 3 m of reversing
  - the snow moves away from the wall into a pile, and volume is exact
  - the moved snow is marked `soft` and spread over the band (one draw per moved cell)
  - after the blade is raised and the snow settles, the pile is still away from the wall
- Pushing is unchanged. These pass: `test_vehicle_plow_and_stuck_pickup`,
  `test_plow_pushes_yard_snow_onto_road`, the snow suite's `test_blade_push_*`, and polish6's §3 and
  §9 blade tests.
- Polish5's key tests (`test_s2_*`) pass. The key defaults change only by the two new actions
  (lookups).
- **Screenshots (2):** back-dragging away from the garage door or house wall, and the pile left
  after the blade lifts.

---

## Feature docs

Create these in `docs/features/`, short, as `CLAUDE.md` describes, from the code and only the part of
`HANDOFF.md` that covers each one:

- **`vehicles.md`:** the truck (keys, driving in snow, its plow), plows, the blade keys, back-drag.
- **`controls.md`:** the actions, their contexts, the press cap, the settings migration.
- **`contracts.md`:** how the player's equipment counts for listing size and the street lock. Keep
  it to that unless you read more of contracts for this round.

In `GAME.md`, "What's in the game now" is empty. Add only the lines for what this round touched (the
truck and its plow, the blade keys), each with a link to its doc.

## For PLAYTEST.md

Include at least these:

- Start a new game. The truck in the driveway has its plow, and it's locked until you find the keys.
- Find the keys and start the truck. Drive through the driveway windrow with the blade up.
- Drive the truck into deep snow and a bank with the blade up. It should go as far as the old plain
  pickup did, and back up and take a run at what it can't push from a standstill.
- Press Down to lower the blade and push a windrow. Press Up to raise it.
- Drive up to the garage door. Lower the blade and back away: the snow comes with you. Raise the
  blade: the pile stays.
- The Equipment store and the Upgrades app no longer offer a front plow.
- Rebind the blade keys in Settings and use them.
- Survival Mode: the same truck checks.
