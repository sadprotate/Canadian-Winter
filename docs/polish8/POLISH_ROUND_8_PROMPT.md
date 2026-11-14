# Canadian Winter — Polish Round 8

**Round number: 8.**

## Start here: read CLAUDE.md, then follow it

1. **Read `CLAUDE.md` at the repo root, in full, before anything else.** It holds the rules for every
   round: git, questions, testing, screenshots, feature docs, the final check and the end of the
   round. It is binding, and this brief doesn't repeat it.
2. **Read `GAME.md`.** `CLAUDE.md` links it: it describes how the game is meant to play, and each
   section is checked against it.
3. **Follow `CLAUDE.md`'s *Starting a round*, steps 1–9, in order.** In particular:
   - Switch to `main`, pull, and check that `git status` is clean. **`main` must hold the Polish 7
     merge** (§10, §11 and playtest fixes 1–3). If it doesn't, stop and ask the owner.
   - **Create the work branch `cw-polish8-pg` from `main`** (all lowercase). All of this round's work
     goes on it. Never commit or push to `main`.
   - If `cw-polish8-pg` already exists, locally or on GitHub, don't create, reset or replace it.
     Stop and ask the owner.
   - Save this brief as `docs/polish8/POLISH_ROUND_8_PROMPT.md`.
   - Start `docs/polish8/STATUS.md` with one checklist line per section, then the three headings
     `## Questions`, `## Check at the end` and `## Issues`.
   - Check that you can work (Godot 4.7.2, the import, `parse_all`, one suite).
   - Ask all your questions in one message, then start.
4. **Do the five sections in this order: §17, §15, §14, §7, §12.** Then do `CLAUDE.md`'s *Final
   check* and *End of the round*: feature docs, GAME.md's lines, `PLAYTEST.md`, commit and push the
   branch, and the report. Then stop and wait for the playtest. **No PR until the owner approves the
   playtest.**

This brief says **what** to build. It has five sections. Four are carried over from Round 6 and keep
their numbers, so the carried-over list stays easy to follow. The hint panel is new and takes the
next number:

- **§17 — The hint panel** (new)
- **§15 — The garage**
- **§14 — Cold nights, and a colder player**
- **§7 — Weather you can see and hear**
- **§12 — Every key can be rebound**

**Why this order:**
- §17 first: it's the smallest, and §15 and §14 send their tips through it.
- §15 before §14: the garage is a shelter that §14's cold reads.
- §7 after §15: no flake may fall inside the garage either.
- §12 last: its scan catches every action the round adds.

**This is a big round: commit as you go.** Round 6 got through about half its list before it
stopped. After each section:
- its tests and the fixture tests pass
- `STATUS.md` is updated
- the section is committed (`polish8 §<n>: <title>`) and pushed

If the round stops early, every finished section is safe on the branch, and `STATUS.md` says where it
stopped.

---

## Where things stand

- `main` has Polish 7 merged:
  - The truck starts with its plow (`pickup_plow`), locked until the keys are found.
  - Blade up/down (`veh_blade_up` / `veh_blade_down`) and back-drag.
  - Fix 1: plowing out of the driveway. Fix 2: long pushes.
  - Fix 3:
    - the blade is solid: it stops at walls and at the garage door
    - the plow width upgrade shows
    - the truck goes back to `Game.truck_start()` when the player sleeps
- `docs/features/` has `vehicles.md`, `controls.md` and `contracts.md` (Polish 7).
- **Read for these sections** (not HANDOFF in full):
  - `docs/polish7/STATUS.md`, `docs/features/vehicles.md` and `docs/features/controls.md`.
  - `docs/polish6/STATUS.md`, *Binding notes*:
    - **§1:** any data change goes into the generator too.
    - **§2:** a new `class_name` is reached by `preload` from older scripts. Simplest: don't add one.
  - Round 5's reports:
    - `docs/polish5/report/s2.md`: keys, the settings migration, the press cap.
    - `s3.md`: `Buildings`. The house garage is already registered.
    - `s4.md`: Gerry's lines and their `"tip"`, `"thought"` and `"unless_flag"` keys.
    - `s9.md`: the rate audit (world vs felt rates) and the fast-forward hooks.
    - `s13b.md`: equipment (the coat's `Equipment.cold_mult()`, the heated pad, `Heating.sources()`).
  - **For background only,** the older briefs for these sections. **This brief replaces them**
    where they differ:
    - `docs/polish5/POLISH_ROUND_5_PROMPT.md`: §14 and §15
    - `docs/polish6/POLISH_ROUND_6_PROMPT.md`: §7, §12, §14 and §15

## Decisions (already made — apply them)

1. **The hint panel (§17).**
   - **What goes through it:** tips that teach the player how to do something. They go through one
     small panel with **Back**, **Next** and **OK**.
   - **The setting:** "Show hints" turns it off. It's on by default.
   - **It never freezes** the player or the world.
   - **These stay as they are:**
     - Gerry's story lines and the player's thoughts, in the speech box
     - interaction prompts under the crosshair
     - status lines ("Stuck: …", "Blade down")
     - notifications
     - the one-line controls reminder on a tool switch and in Tab
2. **The garage (§15).**
   - **Where:** the player's house already has a garage shell. It becomes usable. No new building.
   - **The house door:** the door from the house into the garage is locked until the truck keys
     are found (GAME.md).
   - **The overhead door:** it opens and closes only from its button inside the garage (round 5
     Decision 11).
   - **What it holds:** the plowed pickup, four-wheelers, the walk-behind blowers and the heated pad.
     It also has a tool rack.
   - **Climate:** it's sheltered, not heated.
3. **The truck's parking spot.**
   - **Fix 3 stays:** when the player sleeps, the truck goes back to `Game.truck_start()`.
   - **New:** a truck parked inside the garage is home too. Sleeping leaves it where it is.
   - **The opening is unchanged:** `truck_start()` stays where it is.
   - **Other vehicles:** they still stay where the player leaves them.
4. **Cold (§14). Survival Mode only.** Fun Mode still has no cold.
   - **A colder player, not colder weather.**
     - The player loses warmth faster at every temperature, through one balance multiplier on warmth
       loss.
     - Tune it so that by the time the opening's quests are done, the player is almost too cold to
       stay out (the target is in §14).
     - The weather, the temperatures and the exposure curve's shape don't change.
   - **Cold nights** (round 5 §14):
     - Outdoors at night, exposure is multiplied by a balance value.
     - Enclosed cabs: with the engine on, the player warms up; with it off, the cab shelters.
     - Open machines don't shelter. The garage shelters.
   - **No upgrades:** the ATV's heated-cab upgrade stays unwired.
5. **Weather you can see is visual and audio only (§7).**
   - What falls stays bit-identical (`weather_truth`).
   - Nothing new reads the truth ahead of the current hour.
   - Wind gusts are visual and audio only. Exposure still reads the hourly wind.
6. **Every key (§12).**
   - Every action the game reads is in `Settings.ACTIONS`. Each one can be rebound in the settings
     menu, in every context, with the conflict check.
   - **The exceptions,** listed in `docs/features/controls.md`:
     - Godot's `ui_*` built-ins (menu navigation, Esc to back out of a field)
     - F1, the developer menu

## On hold (the owner's decisions — don't start any of it)

- **Items and upgrades.** These come with the commercial property and the computer update, in a
  later round:
  - the phone (Round 6 §13)
  - snow chains and engine power for the truck
  - snow boots
  - removing the hand upgrades
  - the tool progression
  - the Upgrades app's layout

  Don't add, remove or change any item, upgrade or price.
- **§16 The commercial property.** A later round.
- **The tutorial rework,** including the keys coming only after Gerry's walk. §17 moves the existing
  tips into the panel. It doesn't change the tutorial's steps or Gerry's sequence.
- **Vehicles, parking and the city plows.** These are undecided:
  - how the city grader and sidewalk plow treat parked vehicles
  - home spots for vehicles other than the truck
- **Packed snow and grading.** Four-wheelers and tractors will pack snow into hills, after the
  garage and the commercial property. Don't build any of it. Where this round touches snow, don't
  add anything that assumes snow can only be loose or settled.

## Known before you start (don't ask about these)

- **GAME.md differences the owner already knows about:** GAME.md says bidding isn't built, and it
  calls the neighbour Jerry (the game says Gerry). Note them under `## Issues` only if your sections
  run into them.
- **A known flaky test:** polish3's `test_menu_fixture_load_is_the_same_as_direct` fails under load
  and passes alone. If it fails in the final check, run it alone and note the result under
  `## Issues`. Don't fix it.
- **Out of scope:**
  - **The Snow Dump Truck:** its deep-snow handling is still weak. Leave it.
  - **Round 6's other open items:** right-click pushing vs holding, the dig-out bot, relaxation
    speed vs the PC, and the cosmetic list.
- **A performance run is needed** this round: §7 adds particles, and §15 adds a building the player
  can be inside.
  - The budgets: relaxation 2.5 ms and chunk rebuilds 3.5 ms per frame, and every `perf.tscn`
    scenario under 16.7 ms at p95.
  - The stress scenario (4 m map + a major event at 20×) already sits at the line. Compare it back
    to back with the baseline build.
- **Suite times on the owner's PC:** polish5 takes about 20 min and polish6 5–12 min. Run them in the
  background.
- **Fixtures:**
  - Don't regenerate them. The polish3, polish4, polish5 and polish5_v3 saves (they hold the plain
    pickup) load and play as today.
  - If a test needs a save with the garage in use, build it in the test.

---

## §17. The hint panel

> When we prompt something to the player — you need to hold the right mouse button, tutorial
> things, tips — I want a little hint menu to pop up, and we say everything through it. The player
> can press Next, Back or OK. In the settings, we can disable the hint menu.

**Look at first:**
- **Every place that teaches the player how to do something today.** At least:
  - Gerry's `"tip"` lines (round 5 §4: scoop and throw vs push, with the keys)
  - the first-drive help panel (`game_root.show_vehicle_help`, `panels.gd`)
  - the tool-pickup hint
  - anything else in `hud.gd`, `game_root.gd` or the tutorial flow that explains controls or
    mechanics
- **The Help app (`help_text.gd`).** It stays the reference.
- **How things queue today:** the HUD's speech box, notifications and modals, so the panel fits in
  with them.

List what you find in `STATUS.md`, each with where it goes: into the panel, or left as it is
(Decision 1).

**Build:**
- **The panel.**
  - **On screen:** a small panel, clear of the crosshair, the scoop indicator, the speech box and
    the HUD's lines. It's readable at 1280×720 to 3440×1440, at every UI scale, at noon and at night.
  - **Content:** a hint has a title and one or more short pages.
  - **Buttons:**
    - **Back** and **Next** move between pages, and **OK** closes the hint.
    - On the first page, Back is off. On the last page, Next becomes OK.
  - **Keys:**
    - three new actions in `Settings.ACTIONS`, for example `hint_back`, `hint_next` and `hint_ok`
    - in a context that works on foot and in a vehicle
    - presses through `Settings.accept_press()`, and `Game.typing()` checked
    - When the cursor is free, the buttons can be clicked too.
    - Pick defaults that conflict with nothing in any context, and name them in your questions
      message. The Left and Right arrows are a candidate: check them against the vehicle context.
  - **Key names:** every key in a hint's text comes from `Settings.with_keys()`, so a rebind shows
    at once.
  - **It never freezes:** the player keeps moving and working, and the world keeps running. A hint
    stays on screen until OK.
  - **One at a time:** hints queue.
    - A hint waits while the computer, the sleep prompt or a dialog is open.
    - With Gerry's speech, it shows alongside, never covering the speech box.
  - **Once each:** a hint shows once per save, by id. The exceptions:
    - hints that come back on an occasion, such as §14's cold-night hint
    - a hint the player asks for again, such as Gerry's (below)
- **The setting.**
  - "Show hints" in Settings, on by default.
  - It's saved in `settings.cfg` through the existing migration.
  - **Off:** no hint opens. Nothing is lost: every hint's content is also in Help. §14 says what its
    warning does with hints off.
- **What goes through the panel** (Decision 1):
  - **Gerry's tips.** At the beat where he gives the trail job, his how-to lines become one hint.
    - Its pages: scoop and throw; push; the outlined trail.
    - His spoken lines around it stay in the speech box.
    - Talking to him again during the job opens the hint again. (Today, it repeats the tip.)
  - **The first-drive help:** it becomes a hint the first time the player drives. Its pages:
    driving, the blade keys, back-drag.
  - **The tool-pickup hint:** it shows the first time each kind of tool is picked up.
  - **Anything else** the audit finds that teaches how to do something.
  - **The wording stays.** Split it into pages only where it's long. Add no new tutorial content
    beyond §15's and §14's hints.
- **Saves.**
  - The seen hints are an optional v3 key with a safe default. Add it to the v3 round-trip test.
  - **Old saves:** every hint for a tutorial step the save has already passed starts as seen.
    Derive it from the tutorial stage and the flags. A game loaded past the opening doesn't replay
    the opening's tips.

**Done when** (new tests in `tests/test_polish8.gd`, suite `polish8` added to
`tests/test_runner.gd`, set up the way `test_polish7.gd` is):

- **The buttons:**
  - Back, Next and OK work with the default keys, with rebound keys, and by clicking.
  - Back is off on the first page, and OK closes the hint.
- **Never frozen:** the player moves and scoops while a hint is open, and the clock runs.
- **Queueing:**
  - two hints fired together show one after the other
  - none opens over the computer or the sleep prompt
  - none covers Gerry's speech box
- **Once each:**
  - each hint shows once
  - save → load keeps the seen hints
  - an old fixture past the opening doesn't replay the opening's hints
- **Hints off:** none opens, and Help still has the content.
- **Gerry:**
  - the job beat opens his hint, with the bound keys
  - talking to him again during the job re-opens it
  - his sequence tests otherwise pass
- **The other hints:** the first drive opens the vehicle hint, and the first pickup of each tool
  opens its hint.
- **Fit:** the panel fits at 1280×720, 1920×1080, 2560×1440 and 3440×1440.
- **Screenshots (3):**
  - Gerry's hint on its first page
  - the vehicle hint at night
  - the Settings toggle

**Tests this section deliberately changes** (update through lookups, never delete, skip or loosen):

- Gerry's tip lines (they move from the speech box to the panel)
- the first-drive help panel
- the tool-pickup hint
- the key defaults (new actions only)

---

## §15. The garage

> A door from the house into a garage, and the garage door opens with a button inside the garage.
> The garage stores tools on a wall rack and equipment you're not using, and its floor holds the
> equipment that fits. (Round 5)

**Look at first** (search, don't read whole files):

- **The garage shell** on the player's house (`house_builder.gd`, about 6.5 × 7.5 m): its footprint,
  the overhead door, its collision, and its `Buildings` registration. Round 5 s3 already registered
  it, so throws stop at it and no snow work happens from inside.
- **The single sources:**
  - `Game.truck_start()` and `Game.shovel_spot()`. The photo and the menu's home shot follow them.
  - the driveway box
  - the keys flag
- **Polish 7's code:**
  - `vehicle.gd`'s solid blade (fix 3) and back-drag (§11)
  - fix 3's sleep move in `game_root._do_sleep()`
- **The `store` action** (F): bound since round 5 §2, and it does nothing yet. Also the tool slots
  and `drop`.
- **The heated pad:** `Heating.sources()` and the pad's placement rules (`Equipment.extra_property`).
- **The doors:** `interior_builder.gd` and `door.gd`, for the door between the house and the garage.

**Build:**

- **The doors.**
  - **The house door:** a normal door (E) between the house and the garage.
    - It's locked until the truck keys are found, and a short message says so.
    - It's unlocked for good once they're found. Derive this from the keys flag: no new save key.
  - **The overhead door:** it opens and closes, animated, with a wall button inside (E).
    - Closed, it blocks people and vehicles, and the blade stops at it (fix 3).
    - Its state is saved: an optional v3 key, closed by default.
- **Parking.**
  - **The plowed pickup fits.** Check the bay's length and the door's width:
    - with the blade up and down, straight and angled both ways
    - with and without the plow width upgrade

    **If it doesn't fit, stop and ask before resizing anything.** The garage's size ripples into the
    driveway, the lamps and the house.
  - **Smaller vehicles:** four-wheelers and the walk-behind blowers fit.
  - **Bigger vehicles** stop at the door frame, and the status line says the vehicle is too big for
    the garage.
  - **No overlaps:** vehicles inside never overlap, and stay where they're parked through
    save → load.
  - **Sleeping** (Decision 3): a truck parked inside is home, so `_do_sleep()` leaves it there.
    Anywhere else, fix 3 sends it to `truck_start()`, as now.
- **The rack.**
  - **Slots:** a balance number, starting with 6, on the wall. They show the real tool models.
  - **Using it:**
    - F with a tool in your hands puts it on the rack.
    - E on a racked tool takes it into a free slot, or swaps it with the one in your hands.
  - **Upgrades:** racked tools keep their per-item upgrades. Nothing about upgrades changes; they
    follow the item type.
  - **Saved:** an optional v3 key, empty by default.
- **The floor.** The heated pad can be put down on the garage floor, and it stays there.
  `Heating.sources()` skips a pad inside the garage, so it doesn't melt snow or draw power there.
- **No snow inside.**
  - **The cells:** the garage's cells stay walls for snow (operations, spill, relaxation). The player
    can still walk and drive on them.
  - **Throws:** snow thrown at the open door stops at the doorway and falls outside (round 5 §3's
    rule).
  - **Blades:**
    - A blade pushing snow at the open door leaves it piled at the threshold.
    - Back-dragging from the closed door (§11) leaves no snow in the garage.
  - **The snow-hiding uniforms:** extend them to the garage, without changing how they work for the
    houses.
  - **Flakes:** §7 makes sure no flake falls inside.
- **Climate.**
  - Sheltered, not heated. §14 reads it.
  - A vehicle inside gathers no roof snow, and the snow it carried in melts off over a few game
    hours. (Vehicle roof snow is its own layer, not the heightfield.)
- **The look:**
  - a ceiling light, a real light only while the player is in or near the garage
  - the wall button and the rack
  - a style that matches the house
- **One hint** (§17), the first time the player enters the garage: the button, and the rack (F and E).
- **Unchanged:**
  - `truck_start()`, the shovel spot and the buried keys
  - the path, the mailbox and the lamps
  - the opening, the photo and the menu's home shot

  If the driveway box must reach the garage door, extend only its house end, and rebuild its state
  from the snow on load.

**Done when** (tests in `tests/test_polish8.gd`):

- **The house door:**
  - locked without the keys, with its message
  - open once the keys are found
  - still open after save → load
- **The overhead door:**
  - the button opens and closes it
  - closed, it stops the player, a vehicle and the blade
  - its state survives save → load
- **Parking:**
  - The plowed pickup drives in and out:
    - with the blade up and down, angled both ways
    - with and without the width upgrade
  - The ATV and a walk-behind blower fit.
  - A bigger vehicle stops at the door, with the message.
  - Nothing overlaps, and positions survive save → load.
- **Sleep:**
  - A truck in the garage stays there.
  - A truck on the street goes to `truck_start()`.
  - Fix 3's tests pass.
- **The rack:**
  - store, take and swap
  - upgrades kept
  - a full rack
  - save → load
- **The pad** on the garage floor doesn't melt snow or add to the bill.
- **Snow:** none gets inside, with volume conserved exactly, through:
  - a storm with the door open
  - throws at the doorway
  - a blade push at the open door
  - a back-drag at the closed door
- **These pass:**
  - the opening tests and the keys end-to-end test
  - the photo and menu tests
  - Polish 7's blade and back-drag tests
  - the fixture tests
- **Perf:** a `perf.tscn` scenario: inside the garage, with the truck parked and the door open in a
  snowfall.
- **Screenshots (4):**
  - outside by day
  - outside at night, door open, light on
  - inside, with tools on the rack and the truck parked
  - the door open in a snowfall, from inside

**Tests this section deliberately changes** (update through lookups, never delete, skip or loosen):

- the `store` action (it now racks a tool)
- fix 3's sleep move (a truck in the garage stays)

---

## §14. Cold nights, and a colder player

> Even on the first day, by the time you're done with the quests, you should be almost too cold to
> be outside. I'm not saying the weather should be colder: the player should be less insulated and
> lose warmth faster.

> On cold nights it's better to sleep, unless you have a heated cab. (Round 5)

**Survival Mode only** (Decision 4).

**Look at first,** and write it in `STATUS.md`:

- **How warmth is lost and regained today** (`Survival`):
  - the exposure curve and the weather multipliers
  - the coat (`Equipment.cold_mult()`)
  - indoors and house heat, and the pouches
  - the cold states, the warnings and death

  Round 5 s9's rate audit lists these as felt rates.
- **What happens to warmth in a vehicle today.**
- **The opening, measured.**
  - In Survival, from New Game: how long a human takes to find the shovel and clear Gerry's trail.
    Use the benches' human pace.
  - How much warmth is left at that point today, staying outside throughout.
  - Measure for seed 2024 and four others.
- **Time to danger:** minutes from full warmth to the first cold warning and to freezing, outdoors,
  at −2, −8, −17, −25 and −40 °C, by day and at night.

**Build:**

- **A colder player.** One balance value multiplies warmth loss outdoors. Name it to fit
  `Survival`'s names. The coat still multiplies on top.
  - **The target:** at the end of the measured opening (Gerry's trail just done, outside throughout),
    warmth is just above freezing:
    - the cold warnings are showing
    - a few more minutes outside would start to hurt

    Start the target around 20 % warmth (a balance value), and report where it lands for each seed.
  - **Still playable:**
    - A player who never goes in can finish Gerry's trail at a human pace without freezing.
    - Going indoors warms up as fast as before.
    - Gerry's fire still warms the player.
  - **Tune it with the night multiplier in place:** the opening is at night.
- **Cold nights.**
  - On foot outdoors, between dusk and 7:00 a.m., warmth loss is multiplied by a balance value.
  - A cold night costs clearly more than a cold day at the same wind chill.
- **Cabs.**
  - **Which vehicles:** each vehicle's data says whether it has an enclosed cab. It's a new field in
    vehicle data and in the generator. Check each model: the pickup and the plow truck have one; the
    ATV and the walk-behind blowers don't.
  - **Engine on:** in an enclosed cab, the player warms up, at a balance rate slower than indoors.
  - **Engine off:** the cab keeps the wind out but doesn't warm.
  - **Open machines** give no shelter.
  - **No upgrade:** the ATV's heated-cab upgrade (`ItemUpgrades.has_heated_cab`) stays unwired
    (Decision 4).
- **The garage (§15)** shelters like a cab with the engine off.
- **Hints (§17).**
  - **Cold night ahead:** "Cold night ahead. Sleep, or work from a heated cab."
    - **When:** at dusk, if the forecast low is under a balance threshold. Read the forecast model,
      never the truth.
    - **How often:** once a night.
    - **Not shown** when the player is already indoors or in a running cab.
    - **With hints off,** it comes as a notification instead. It's a warning, not just a tip.
  - **Warming up:** the first cold warning of a game also opens a one-time hint on how to warm up:
    indoors, a running cab, a heating pouch.
- **Rates:** every new rate is a felt rate, per round 5 s9's audit. Say so in its balance comment.
- **Fast-forward:** the cold warnings still drop it to 1×. Extend the 1×/2×/10× equality test to the
  night multiplier and cab warmth.
- **Unchanged:** sleeping through a cold night is as safe as before, and Fun Mode is as it is.

**Done when** (tests in `tests/test_polish8.gd`):

- **The opening target:** for each seed, warmth at the end of the measured opening is within the
  target band, and the player didn't freeze before it.
- **Nights:** at the same wind chill, night loss is greater than day loss.
- **Shelter:**
  - a running cab warms the player, and an engine-off cab shelters
  - the ATV and the blowers don't shelter
  - the garage shelters
- **The cold-night hint:**
  - once a night
  - never from the truth ahead
  - never indoors or in a running cab
  - a notification with hints off
- **The warming-up hint:** once per game.
- **Time to danger:** the table of minutes to the warning and to freezing, before and after, by day
  and at night, is in `STATUS.md`.
- **Still playable:** a typical path job (`contract_bench`) can still be finished in one December day
  in Survival, with breaks indoors.
- **Unchanged:**
  - Fun Mode: no warmth change anywhere.
  - Sleeping through a cold night: as before.
- **Screenshots (2):**
  - the cold-night hint at dusk
  - the player in the running truck at night, with warmth rising

**Tests this section deliberately changes** (update through balance lookups, never delete, skip or
loosen):

- every test that asserts today's warmth rates (for example `test_systems.gd`'s warmth-by-weather
  test)

---

## §7. Weather you can see and hear

> have weather be visible to players. so when its light snow durring the hour you see pretty snow
> flakes falling. when medium you see a lot more and get worried. heavy snow is hard to see and
> blizzard and other event can have visible winds and sound. (Round 6)

**Look at first,** and write it in `STATUS.md`. Round 6 found the following; check it still holds:

- **The flakes:** `scripts/world/weather_fx.gd` is one `GPUParticles3D` of 5 cm round dots (2,400 at
  most, following the camera).
  - Its amount is `rate / 2.5 cm/h`, so heavy snow and a blizzard look the same.
  - Wind only slants the fall.
  - Flakes are hidden entirely while the camera is indoors.
- **The fog:** `DayNight` sets it per condition (0.0035 → 0.05).
- **The sound:** `AudioMgr` crossfades the `wind_light`, `wind_strong` and `blizzard` loops by
  condition. `gust_whistle.wav` exists.

Measure the particle cost at each condition.

**Build.** Each level should read at a glance (Decision 5).
- **What it reads:** `Weather.visual_rate()`, `visual_intensity()`, `visual_wind_kmh()` and the
  6-game-minute blend.
- **Never** read the truth ahead.

- **Light:**
  - Real flakes: procedural six-armed crystals in several variants. The atlas is drawn in code, with
    no imported images.
  - Mixed sizes, drifting and fluttering slowly.
  - A few large, soft flakes pass close to the camera.
  - At night, they glint under street lamps and porch lights.
- **Moderate:** clearly more flakes, a little faster, and a light haze down the street.
- **Heavy:**
  - Dense snow, slanted by the wind.
  - Visibility drops: the far end of the street disappears, and the houses across it soften.
  - The wind sound rises.
- **Blizzard:** near whiteout, with visibility in the tens of metres.
  - Streaks are driven almost sideways.
  - Gusts come and go as visible pulses of denser snow.
  - Sheets of blowing snow race along the ground and stream off the tops of banks and roofs.
  - Trees sway.
  - A howling wind, with gust whistles timed to the visual gusts.
- **Windy hours without snowfall:** when the wind is above a balance threshold and there's snow on the
  ground, wisps of blowing snow run along the surface and off roof edges, with wind sound.
- **Indoors:** falling snow is visible through the windows and the open garage door, but no flake
  shows inside.
  - Discard flake fragments inside building footprints, the way `snow_ground.gdshader` does with its
    hide uniforms.
  - This covers every `Buildings` footprint, the garage included.
  - The muffled wind stays as it is.
- **Gameplay stays readable** in every condition, at noon and at night:
  - the scoop indicator
  - the box outlines (blue and money green)
  - the prompts and the HUD
  - the hint panel
- **Settings:** the graphics quality scales the particle counts and the ground-drift effect, as the
  current `density` does.
- **Sounds:** they come from `tools/audio/gen_audio.py`:
  - a soft hush for light snow
  - several gust variants
  - a blizzard howl layer
- **Randomness:** weather visuals and sounds may use an unseeded generator of their own, but never
  the global one.

**Done when** (tests in `tests/test_polish8.gd`):

- `weather_truth` and `depth_report` are identical to baseline.
- **A scan test:** no new script calls the global `randf()` / `randi()`.
- **No flake inside:** no flake is emitted or drawn inside a building footprint, the garage included.
  Test the uniforms and the emitter logic headless.
- **Fast-forward:** the 1×/2×/10× equality test still passes.
- **Perf:** new `perf.tscn` scenarios, each under 16.7 ms at p95. Report the particle counts.
  - light snow
  - heavy snow
  - the blizzard's peak, with ground drift
  - each at 1× and at the fast-forward caps
- **Screenshots, before and after:**
  - each of the four levels, at noon and at night
  - a windy hour without snow
  - looking out a window in a snowfall
  - looking out of the open garage door in a snowfall

---

## §12. Every key can be rebound

> make sure all keybinds are editable in settings. (Round 6)

The owner thinks most of this is already done. The audit says how much is left. If it finds nothing
missing, the section is the audit, the scan test and the screenshots.

**Look at first,** and write it in `STATUS.md`:

- every `is_action*`, `get_axis`, `get_vector` and `InputEvent` read in `scripts/`
- **every hard-coded key:**
  - `settings_menu.gd`'s `KEY_ESCAPE`
  - the snowshoes toggle (Tab + E)
  - the computer's fields
  - F1
- every action in `Settings.ACTIONS`, and whether the settings menu shows it in its group

**Build** (Decision 6):

- **Every action in the menu:** every action the game reads is in `Settings.ACTIONS`. The settings
  menu shows it under its context (On foot, Vehicle, Global, and the hint panel's context), with the
  conflict check for that context.
- **This round's new actions are included:** the hint panel's three (§17). Check that Polish 7's
  `veh_blade_up` and `veh_blade_down` are there.
- **The snowshoes toggle (Tab + E):** make it read actions, so a rebind carries over, or give it its
  own action. Do whichever changes less, and say which.
- **The menu:** it fits and scrolls at 1280×720 to 3440×1440.
- **Reset to defaults** gives this round's defaults.
- **The settings migration:**
  - it keeps custom bindings
  - it gives existing players the new defaults
  - no `CONTROLS_VERSION` bump is needed for new actions
- **The exceptions** (Decision 6) are listed in `docs/features/controls.md`.

**Done when** (tests in `tests/test_polish8.gd`):

- **A scan test:** every action name read in `scripts/` is in `Settings.ACTIONS` or is a documented
  exception.
- No key is read hard-coded outside `Settings` and the documented exceptions.
- **Every action, one by one:** it can be rebound in the menu, and it works with its new binding.
- No conflict in any context.
- **These pass:** polish5's key tests (`test_s2_*`) and Polish 7's blade-key tests.
- **Screenshots (2):** the settings key list, at the top and scrolled.

---

## Feature docs

Create or update these in `docs/features/`, short, as `CLAUDE.md` describes, from the code you read
this round:

- **New: `hints.md`:**
  - the panel and its keys
  - what goes through it and what doesn't
  - the setting
  - how seen hints are saved
- **New: `garage.md`:**
  - the doors, parking, the rack, the floor
  - no snow inside, shelter
- **New: `survival.md`:** only what this round touched and read:
  - warmth and the colder player
  - nights, cabs and shelters
  - the cold hints
- **New: `weather.md`:** the weather you see and hear. Leave the forecast model to HANDOFF unless you
  read it.
- **Update: `controls.md`:**
  - every action and its context
  - the exceptions
  - the hint keys
  - the snowshoes toggle
- **Update: `vehicles.md`:**
  - enclosed cabs and warmth
  - the garage
  - the truck staying home in the garage

In `GAME.md`'s "What's in the game now", add one line each, with a link to its doc:

- the hint panel
- the garage
- the colder player and cold nights
- weather you can see and hear
- every key can be rebound

## For PLAYTEST.md

Include at least these:

- **The opening (Survival):** start a new game and play the opening outdoors without going in.
  - By the time Gerry's trail is done, you're almost frozen.
  - Gerry's fire warms you.
- **The hint panel:**
  - Gerry's tips come up in it. Use Back, Next and OK.
  - The first time you drive, the vehicle hint opens.
  - Turn hints off in Settings: none opens.
- **The garage door from the house:** before the keys it's locked. Find the keys, and it opens.
- **The overhead door and parking:**
  - Press the button inside: the overhead door opens.
  - Drive the truck in and out, with the blade up, down and angled.
  - Sleep with the truck in the garage: it's still there in the morning.
  - Leave it on the street and sleep: it's back in the driveway.
- **The rack:** put a tool on it with F, and take it back with E.
- **No snow inside:**
  - Back-drag snow away from the closed door.
  - Push snow at the open door, and throw some at it.
  - None gets in.
- **The weather:**
  - Use F1 to go through light, moderate, heavy and blizzard.
  - Watch outdoors, from a window and from the open garage door.
  - Listen to the wind.
- **A cold night:**
  - The hint comes at dusk.
  - Stay out on foot, then sit in the truck with the engine running, then with it off.
- **Keys:** rebind one key in each context, and use it.
- **Fun Mode:**
  - no cold anywhere
  - the garage and the hints work the same
