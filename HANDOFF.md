# Canadian Winter — Handoff

A complete single-player snow-removal / cozy business / winter-survival game in **Godot 4.7.2,
GDScript only, GL Compatibility renderer**. Everything (models, textures, sounds, music) is
generated procedurally by code in this project. This file is for future polish sessions.
Section 9 lists everything the first polish pass changed, section 9b the second (polish pass 2),
section 9c the third (polish pass 3), section 9d the fourth (polish pass 4). All 122 automated tests
pass (`tests/test_runner.tscn`, §11).

## 1. How to run

1. Open Godot 4.7.2 (the mono build works too — the project uses no C#), *Import* →
   select `project.godot` in this folder → *Import & Edit*. The first import takes a minute
   (it imports the generated WAV files).
2. Press **F5** (main scene: `scenes/main_menu.tscn`). PLAY → Fun Mode / Survival Mode → New Game.
3. **F1** opens the developer menu in-game (money, weather, storm / major-event triggers, time
   jumps, spawns, teleports, …).

## 2. Controls (on foot)

| Action (rebindable in Settings) | Default | What it does |
|---|---|---|
| `primary` — *Scoop snow (hold) / throw (release)* | Left mouse | **Hold** and sweep the crosshair through the snow: the hands / blade fill from the snow the sweep cuts through (deep snow fills fast, bare pavement fills nothing). The 3D load grows in the cupped hands or on the blade. **Release** throws the load (full or partial) forward where you face; look down for a short drop, level or up for the full distance. One marker on the snow shows where the snow goes next (pass 4): on the snow being cut while you scoop, then — loaded, looking up — where a release will land; red over the street (the snow stays in your hands), amber inside the box you're clearing. |
| `secondary` — *Push snow (hold)* | Right mouse | Hold and walk: the hands (flat palms) or the blade push the snow ahead into a growing berm. Stops at the curb. |
| `tool_angle` — *Angle scraper blade* | R | Scrapers: straight → right → left. |
| `drop`, `use_pouch`, slots 1–4 / wheel | Q, G, 1–4 | unchanged |

The electric shovel keeps its hold-LMB intake that throws automatically (RMB pushes). Walk-behind
blowers and vehicles keep their controls (blowers throw through the chute; plows push).
Every tool switch shows a one-line reminder with the current bindings; Tab shows it too.

## 3. Architecture overview

Autoload singletons (all in `scripts/autoload/`, registered in `project.godot`):

| Autoload | Role |
|---|---|
| `Settings` | Persistent settings (`user://settings.cfg`), input map with rebinding + conflicts + defaults, applies audio/graphics |
| `Catalog` | Loads all data resources from `data/` (tools, vehicles, upgrades, balance) |
| `Notify` | Notification queue; HUD shows them, history kept |
| `Clock` | The single game clock: 1 real min = 24 game min. Calendar (Dec 1 – Mar 31). Calls every system in a fixed order per step; hour/day hooks; time skips use the same code in 30-min steps |
| `Weather` | Deterministic hourly schedule per winter built from **storm tiers** (§6); **one forecast model** (pass 4: `fc_hour(target, issued)`, a pure function of the seed, the hour it's issued and the hour it's for, with an error that shrinks with lead time) behind the TV, the radio and the computer; surprise storms + alerts; feeds snowfall to `Snow` |
| `Snow` | **The snow simulation** (§4) |
| `Boxes` | **Clearing boxes** (§5): every driveway, path, sidewalk, parking lot and street section; 90 % rule (pass 3), snap to bare ground, reopening |
| `Game` | Mode, year, money, reputation, 4 tool slots, carried item, upgrades, flags (tutorial stage, keys, computer lock…), stats, registry of persistent world objects |
| `Economy` | Purchases → store orders (store hours 7–21), hydro bills, power cut at midnight into the 16th |
| `Contracts` | Contract board, bidding vs. simulated rivals, contracts whose zones are groups of boxes, recurring visits, municipal street contracts, the **48-hour snowed-in rule** |
| `Municipal` | City grader schedule (every 3–4 days, first on Dec 3/4); batched passes during skips |
| `Survival` | Warmth (on from minute one in Survival Mode, never in Fun Mode), cold states, house heat, outage cooling, heating pouches, death |
| `AudioMgr` | Buses, pooled one-shots, weather ambience + music crossfades, indoor low-pass |
| `Saves` | One save per mode in `user://saves/`, written on sleep. JSON + zstd-compressed snow, atomic temp→rename, `.bak`, **version 2** (version-1 saves are migrated) |

Scenes: `scenes/main_menu.tscn` (`scripts/ui/main_menu.gd`) and `scenes/game.tscn`
(`scripts/game/game_root.gd`: builds the world, UI layer, tutorial flow, sleeping/autosave, computer
lock, outages, death, winter end).

World building (`scripts/world/`): `layout.gd` (static map: 3 streets, 24 lots incl. 2 vacant,
school/store/church lots, snow dump, municipal road sections), `world_builder.gd`, `house_builder.gd`,
`interior_builder.gd`, `props.gd`, `mesh_kit.gd`, `mats.gd`, `day_night.gd`, `weather_fx.gd`,
`snow_renderer.gd`, `roof_snow.gd`, `store.gd`, `tool_item.gd`, `door.gd`, `interactable.gd`,
`buried_keys.gd`, `zone_markers.gd` (contract stakes/outlines + the box-complete flash).

Player & tools: `scripts/player/player.gd` (controller, FP/TP cameras, hip-height wading, scaled
viewmodel), `character_model.gd` (procedural animated character; `HIP_HEIGHT`, glove colour),
`fp_arms.gd` (**first-person arms**: sleeves, mittens with hinged fingers/thumb, cupped-snow mound),
`tool_controller.gd` (every hand tool: fill/throw/push, viewmodel and third-person poses).
`scripts/tools/tool_models.gd` builds tools as one mesh (third person, world items) or as separate
handle + blade parts (first person, so the blade lies flat on the snow at any shaft angle).
Vehicles: `scripts/vehicles/`. NPC: `scripts/npc/neighbor.gd` (Gerry). UI: `scripts/ui/`.

## 4. The snow system (scripts/autoload/snow_sim.gd + scripts/world/snow_renderer.gd)

* **Representation:** one heightfield over the whole 192 × 224 m map, 0.25 m cells (768 × 896).
  Per cell: snow depth, **loose-snow depth** (the part on top that was thrown, pushed or slid),
  static ground height (porches/stairs), surface type, and a **hold** flag (inside a completed box).
* **Operations (all conserve volume):** `scoop`, **`cut`** (the sweep of hands / shovel-type tools:
  each swept cell loses up to the tool's bite off its top, capped by the fill rate — leaves a
  trench), `deposit` (cone splat), `blade_push`, `intake`, `grader_lane`. Thrown snow is a
  `ThrownSnow` node carrying its volume until it lands. Explicit non-conserving exceptions:
  **box completion** (the last ≤ 2 % inside a box is removed), dump-truck disposal, setup/debug.
* **Ceiling:** the snow surface never rises above `snow_ceiling` (6.0 m, the street-lamp head
  height). Snowfall stops adding at the ceiling; operations spill the excess outward ring by ring
  into the nearest cells with room (`_spill`), blades keep what doesn't fit in front of the blade,
  grader windrows spill too — volume is conserved.
* **Road rule:** player operations never put snow into ROAD cells unless it came from ROAD cells.
  Throws refuse a landing on the road (red ring, load kept); blades stop at the curb; relaxation
  treats the curb as a wall.
* **Relaxation (cohesion + angle of repose):** 8 × 8-cell tiles queued by every operation. *Loose*
  snow on a higher cell slides at the angle of repose (`repose_max_diff` 0.23 m per 25 cm ≈ 43°);
  undisturbed snow keeps near-vertical cut walls (only gives way past `repose_cut` 1.6 m per cell).
  So trenches and cleared boxes have crisp walls, while thrown/pushed piles slump into cones and
  berms (and stay as mounds — they don't flatten). Completed boxes (held cells) and the strip just
  behind an engaged blade act as retaining walls for slumping snow, like the curb. Time-budgeted
  (2.5 ms/frame) with a fast stable-tile reject.
* **Snowfall:** a global cumulative counter (`fall_total`) applied lazily per 16 m chunk —
  identical results for real time and skips. Per-cell multipliers give drifts near walls and
  shelter under porch roofs. **Settling is off** (`settle_rate_per_day = 0`): it used to compact
  deep snow by 2 %/day of the depth above 0.3 m, which quietly cancelled most new snowfall on deep
  yards (a 3-day skip could lose more than it gained) — that was the "snow isn't added on top" bug.
* **Rendering:** 168 chunk meshes, dirty sub-rectangles only, 3 LODs with skirts, 3.5 ms/frame
  budget. Bare cells (< 2 mm) drop below the ground, so cleared ground shows the pavement shader.
* **Collision / wading:** the player can wade through snow up to `CharacterModel.HIP_HEIGHT`
  (0.95 m, the hip pivot of the model) measured from their feet, slower the deeper it is (a crawl
  near the hips); a snow surface above the hips in the direction of travel is a wall — dig through.
  Vehicles use clearance / bank checks as before.
* **Persistence:** depth and loose depth quantised to 1 mm, delta-encoded, zstd-compressed;
  restored bit-exactly. Box state is saved by `Boxes`.
* Roofs and vehicles use a simplified layer (roof snow now keeps what falls, up to 2.4 m).

## 5. Clearing boxes (scripts/autoload/boxes.gd)

Layout (78 static boxes + dynamic ones):

| Box | Per | Rects |
|---|---|---|
| `lotN_driveway` "Driveway" | each built lot | the driveway incl. its apron across the boulevard/sidewalk |
| `lotN_path` "Path to the house" | each built lot | walkway + stairs + porch |
| `lotN_sidewalk` "Sidewalk" | every lot (vacant too) | the 28 m sidewalk strip in front |
| `area_school_lot` / `area_store_lot` / `area_church_lot` "Parking lot" | 3 | lot + apron |
| `road_<section>` "Street" | 7 municipal road sections | the section |
| `gerry_trail` (dynamic) | tutorial | Gerry's whole walk from the sidewalk up (his mailbox stands at its foot, pass 4) + his stairs (`Layout.gerry_trail_rects()`) |

* **Completion:** each box tracks its **peak** (most snow it held since it opened, above the 1 cm
  residual). When `1 − snow/peak ≥ box_completion` (**0.90** since polish pass 3,
  `data/balance.tres`) the box completes: the remaining snow inside — **at most 10 % of its peak** —
  is removed (the documented conservation exception; it was ≤ 2 % at 98 %), its cells are held (no
  slump inflow → clean edges against the surrounding snow), a chime (`box_complete`) plays and a
  bright outline flashes around it. The same rule for paths, driveways, sidewalks, streets, parking
  lots and Gerry's trail; contracts, recurring visits and the 48-hour clock follow the box.
* **Reopening:** a completed box reopens when its average depth reaches `box_reopen_depth` (2 cm) —
  any snowfall of an inch or more, a grader windrow, or snow thrown onto it.
* **Measuring:** boxes within 4 m of the player every 0.25 s (HUD progress), one box per frame
  round-robin, completed boxes every hour during skips. Streets and parking lots are sampled (every
  4th cell) and counted exactly once the sample says they are within 5 points of the threshold
  (an estimated **85 %**, `Boxes.EXACT_MARGIN`); while the estimate is past 50 %
  (`RECHECK_MARGIN`) they are also counted exactly at most every 1.5 s (`RECHECK_MS`), so a strip
  the sample overrates can't hold a street just under 90 %. A big box only ever completes on an
  exact count.
* **HUD:** the box you stand in shows "place — name  73 %" (or "clear ✓") with a bar; for contract
  boxes also the snowed-in time left. The map colours your own and your contracts' boxes.
* **Contracts are built on boxes:** a contract zone is a list of box ids; the zone is done when all
  its boxes are complete.

### 48-hour rule (Contracts)
A contract's property is **snowed in** while any of its boxes is incomplete. Snowed-in time
accumulates in game hours, **paused while a storm or blizzard (heavy snow or worse) is still
falling**; it resets to zero when every box is complete. After `contract_snowed_in_hours` (48) the
contract is lost (reputation −6). Warnings at 12 h and 3 h left (notification + HUD alert line);
time left is shown in the HUD, the computer's contracts app and on the map. One-time jobs start
snowed in when awarded; recurring/city contracts need a visit whenever their boxes reopen and are
paid when all boxes are complete again. Gerry's tutorial trail has no timer.

## 6. Storm tiers and the winter

| Tier | Amount | Duration | Weather | Frequency |
|---|---|---|---|---|
| Light snowfall | 1–2 in (2.5–5 cm) | 3–9 h | light / moderate | the bulk of every winter (~22) |
| Storm | 6 in – 1 ft (15–30 cm) | 8–18 h | heavy (25 % arrive stronger than forecast) | ~4 in winter 1 → ~9 by winter 5 |
| Major event | 3–4 ft (90–120 cm) | 3–6 h | blizzard; half forecast, half unforecast surprise | 0–1 in winter 1 (40 % chance) → ~3.5 by winter 5 |

Each winter's mix is a shuffled bag (`Weather._tier_bag`): event count and tier counts grow with
`difficulty` (0 → `difficulty_cap` 1.0 at winter 5, then capped). The first two events of winter 1
are always light. Hourly rates are normalised so every event drops exactly its total.

**Onset (pass 4).** A storm or major event opens with a light-to-moderate lead-in — the partial
hour it starts in and the next full hour, at up to `storm_onset_cm_h` (1.0 cm/h) and at most
`storm_onset_mean_frac` (0.5) × its mean rate — then builds along its bell to the peak; the rest of
its total is renormalised over the remaining hours, so totals, starts and ends are unchanged (light
snowfalls are unchanged). The first hour of snow alone no longer tells a light snowfall from the
start of something bigger. Peaks rise where the same snow now falls in fewer hours: major events
average 45 cm/h at their peak (32 before), at most 110 cm/h (52); storms 2.5 cm/h (unchanged), at
most 5.5 (5.1).

**Forecasts (pass 4).** `Weather.fc_hour(target, issued, radio)` is the only forecast: the TV's
and the computer's day cards (`Weather.forecast(days)`) and the radio's three-hour bulletin all
read it. It's deterministic (seed, issue hour, target hour; nothing saved), revised every game hour,
and converges: each event carries one fixed amount error and its timing error, scaled by the lead
(`fc_error_base` + `fc_error_per_day` × days; timing `fc_timing_h_per_day` per day; temperatures
`fc_temp_error_per_day` per day; all divided by `forecast_skill`). Forecast events stay forecast;
storms that turn out stronger stay under-called until close; an unforecast major event is never on
the TV before it starts, and the radio picks it up only within `radio_surprise_horizon_h` (1 game
hour) of its start. Measured over 5 seeds × winters 1–3: the hourly rate is off by 3 % one hour
ahead, 16 % six hours ahead, 85 % a day ahead; a day's snow by 18 % on the day, 37 % / 51 % / 62 %
one, two, three days ahead. The alerts are as before.

**Measured depth curves** (`tests/depth_report.tscn`, seed 2024, whole winters simulated with
time skips: snowfall + the city grader, no player; "yard" = an untouched back yard, "bank" = the
tallest snow along Birch Avenue's boulevards/sidewalks, where the grader windrows):

| Date | Winter 1: yard | Winter 1: street bank | Winter 5: yard | Winter 5: street bank |
|---|---|---|---|---|
| Dec 1 | 0.81 m | 0.87 m | 0.48 m | 0.55 m |
| Dec 15 | 1.28 m | 4.22 m | 0.80 m | 2.51 m |
| Jan 1 | 1.41 m | 4.79 m | 1.24 m | 4.35 m |
| Jan 15 | 1.62 m | 5.93 m | 3.63 m | 6.00 m (ceiling) |
| Feb 1 | 3.04 m | 6.00 m | 4.14 m | 6.00 m |
| Feb 15 | 3.16 m | 6.00 m | 4.45 m | 6.00 m |
| Mar 1 | 3.29 m | 6.00 m | 5.92 m | 6.00 m |
| Mar 15 | 3.59 m | 6.00 m | 6.00 m (ceiling) | 6.00 m |
| Mar 31 | 3.71 m | 6.00 m | 6.00 m | 6.00 m |

(Re-run in pass 4 on the pass-3 build and the pass-4 build: every value is identical before and
after the onset change. A few street-bank values differ from the ones this table showed before,
which had not been re-run since pass 2.)

Events: **winter 1** — 27 events, 22 light, 4 storms (15–26 cm), 1 major (109 cm in 3.8 h on
Jan 20), 281 cm in all. **Winter 5** — 35 events, 21 light, 10 storms, 4 majors (104–119 cm in 4–6 h,
two of them unforecast), 735 cm in all. Over 20 seeds the averages are: winter 1 ≈ 22 light /
3.9 storms / 0.5 majors (227 cm); winter 2 ≈ 1.2 majors (319 cm); winter 3 ≈ 1.9 (431 cm);
winter 4 ≈ 2.8 (555 cm); winter 5+ ≈ 3.6 majors and 9 storms (≈ 660 cm, capped).
Winter 1's big jump (late January) is its major event; by late winter 5 untouched snow reaches the
lamp-height ceiling everywhere, which is what makes the big machines necessary.

## 7. Tool profiles (data/tools/*.tres, mirrored in tools/data_gen/generate_data.gd)

| Tool | Capacity | Fill rate | Bite | Scoop width | Throw | Push width | Push strength | Specialty |
|---|---|---|---|---|---|---|---|---|
| Bare hands | **30 L** (was 15) | **85 L/s** (35) | 26 cm (15) | 0.40 m (0.34) | 1.8 m | 0.50 m | 0.035 m³ | weak at both: a toss of a metre or two, a short push that stalls quickly |
| Small shovel | **50 L** (28) | 130 L/s (75) | 26 cm (20) | 0.34 m | 4.2 m | 0.36 m | 0.09 m³ | all-rounder, best early thrower |
| Standard shovel | **65 L** (38) | 160 L/s (95) | 28 cm (22) | 0.46 m | 5.2 m | 0.48 m | 0.14 m³ | bigger loads, longest hand throw |
| Wide pusher | **45 L** (26) | 90 L/s (50) | 15 cm (12) | 0.90 m | 2.2 m | 0.90 m | 0.50 m³ | strong pusher, clumsy thrower |
| Snow scraper | **50 L** (30) | 100 L/s (55) | 15 cm (12) | 0.75 m | 2.8 m | 0.75 m | 0.60 m³ | pushes hard, scrapes to bare pavement, angles (R) |
| Large scraper | **80 L** (45) | 160 L/s (90) | 20 cm (15) | 1.00 m | 3.4 m | 1.20 m | 0.95 m³ | between shovel and pusher: decent throw, very strong push |
| Snow sleigh | **400 L** (260) | 320 L/s (200) | 36 cm (30) | 0.80 m | 1.0 m | 0.80 m | 1.40 m³ | huge loads but barely throws (tips out in front); strongest hand pusher |
| Electric shovel | intake **50 L/s** (24) | — | — | 0.32 m | 5.0 m (auto) | 0.34 m | 0.08 m³ | hold to chew and throw automatically |
| Walk-behind blowers | intake 65 / 140 L/s | — | — | 0.56 / 0.78 m | 8 / 12.5 m (chute) | — | — | unchanged machines |
| Plows / grader | — | — | — | — | — | 1.5–3.7 m | 1.3–9 m³ | strongest pushers (vehicles, unchanged) |

(Values in brackets: before polish pass 2.) Throw distances and push values are unchanged — pass 2
is about how much each scoop takes, not how far it goes. The ladder holds: every shovel-type tool
carries at least 1.5× and fills faster than bare hands; small → standard shovel is +30 %; the
scrapers step up; the sleigh carries by far the most.

*Push strength* is the berm volume at which the tool slows to half speed. Upgrades: capacity +
fill speed (`shovel_capacity`), throw distance (`throw_distance`), push width (`blade_width`) and
push strength/speed (`push_speed`) apply to hands and every shovel-type tool.

## 8. Where balancing values live

* `data/balance.tres` (script `scripts/data/balance_data.gd` — its defaults are what a data reset
  writes): economy (starting money **$50**, hydro bill, store hours, contract pricing), contracts
  (48 h, warning hours, reputation loss), boxes (90 % since pass 3, 1 cm residual, 2 cm reopen), snow (opening
  depth 0.82 m capped softly at 0.88 m so the opening stays below the hips, repose 0.23, settling 0,
  ceiling 6.0 m), weather (events per winter 26 → 34, tier amounts, storms 4 → 9, majors 0.4 → 3.5,
  difficulty +0.25/winter to cap 1.0, debug override rates), survival (**exposure curve**: warmth-%
  lost per hour by wind chill, interpolated: −2 °C 2 %/h, −8 °C 6 %/h, −17 °C 19 %/h, −25 °C 28 %/h,
  −40 °C 41 %/h; weather multipliers; warm-up; pouches), player speeds. Pass 4: the storm onset
  (`storm_onset_cm_h` 1.0, `storm_onset_mean_frac` 0.5) and the forecast model (`fc_error_base`
  0.06 and `fc_error_per_day` 0.22 — the error-vs-lead curve, as a fraction of the amount, also the
  ± range shown; `fc_timing_h_per_day` 2.5; `fc_temp_error_per_day` 1.6 °C; the radio's
  `radio_surprise_horizon_h` 1.0 game hour; `forecast_skill` 1.0, which divides the errors and
  multiplies the horizon — wired and tested, no upgrade uses it yet).
* `data/tools/*.tres` — §7. `data/vehicles/*.tres`, `data/upgrades/*.tres` as before.
* `tools/data_gen/generate_data.gd` regenerates all of the above
  (`godot --headless --path . --script res://tools/data_gen/generate_data.gd`).
* Hip height: `CharacterModel.HIP_HEIGHT` (0.95 m). Viewmodel scale: `Player.VM_SCALE` (0.12).

## 9. Polish pass — what changed

**Hands & tools (§1–§3).** First-person arms (sleeves + mittens) with idle, cupped (holding),
scooping, flat-palm push and forward-toss poses; snow mound in the cupped hands scales with the
load. Every hand tool is visible in first person held in both hands (right hand on the grip, left
down the shaft); looking down, the tool is anchored to the body so the blade rests on and sweeps
through the snow at the aim point, and the blade lies flat whatever the shaft angle. The viewmodel
is scaled 0.12× toward the eye (near plane 0.02 m) so it can never clip into walls, banks or the
ground. Third-person poses match (hands_scoop / hands_hold / hands_push / hands_toss, dig / carry /
throw / push), with the load shown in the hands or on the blade. New control scheme (§2 table),
tool profiles (§7). Fixed: the shovel/pusher/electric-shovel handle mesh pointed up and away from
its blade (handles now meet the blades).

**Opening (§4).** The small shovel lies beside the truck under an odd oblong pile (+0.32 m). The
hydro letter reminds you the bill is due on the 15th and that unpaid accounts are disconnected, but
not how to pay. Starting money is $50, so with Gerry's $40–55 the first $85 bill can always be paid
(the computer unlocks with Gerry). Gerry still cries "Hey… help!" after the letter (new, less
robotic voice: rough breathy source, pitch scoops, vibrato, a second voice layer, more reverb).

**Hand progress (§5).** Hands: 0.8 L click-digs → 15 L sweep-fills that cut 15 cm per pass.
Measured with `tests/grind_bench.tscn` (a bot clears your own path-to-the-house box with bare
hands through the real controls: aim at the nearest snow, hold LMB and sweep, turn, release to toss
level; carries porch snow down the steps first):

| | Before the polish pass | After |
|---|---|---|
| Snow in the box at the start | 9.48 m³ | 8.51 m³ (opening depth now capped below the hips) |
| Bare-hands removal rate | 0.0010 m³/s (0.8 L click-digs) | 0.0204 m³/s (15 L sweep-fills) |
| Time to clear the box | ~161 min of play (≈ 64 game hours), projected | **7.5 min of bot play (3.0 game hours, 725 strokes), measured** — about **13–14 min at a human pace** (≈ 5.4 game hours) |
| Walking the path | 0 m/s (blocked: snow > 0.6 m) | 0.63 m/s wading → **4.17 m/s** on the bare path |

The box snaps to bare ground at 98 % (90 % since polish pass 3); the faster walk is the immediate reward.

**Wading (§6).** Hip-height rule (above). Opening snow ≤ 0.88 m (below the hips): door → mailbox →
Gerry's door is wadeable from the first minute. A major event can bury you in; digging out with
bare hands always works (the throw is lifted over trench walls, and thrown snow that lands on top
of an undisturbed wall stays there instead of collapsing the wall).

**Boxes (§7), snowfall/tiers/ceiling (§8), contracts (§9)** — sections 4–6 above.

**Cold (§10).** Fun Mode: no cold ever. Survival Mode: cold from minute one, driven by the weather
(the exposure curve above): early December barely matters, cold snaps, wind and blizzards hurt.

**Computer (§11).** Locked until Gerry's quest is complete; using it shows why and what to do
("Gerry … has the password"). Nothing before the quest needs it. The lock is saved (flag
`computer_unlocked`, also derived from the tutorial stage).

**Sleep (§12).** Two choices: "Sleep until 7:00 a.m." / "Not yet"; always wakes at the next 7:00.
No date, weather or forecast on the prompt, the black "Z z z" transition, or the wake message.
Everything that runs during a skip still runs (snowfall, grader, cooling, outages, bills, contract
timers, autosave). F1 time jumps remain.

**Polish (§13).** New sounds: `hand_scoop_1..3`, `shovel_fill_1..3`, `hand_toss`, `push_snow`
(loop), `box_complete`; new `help_call`. UI text, Help app, tool-pickup hint, contract terms, map
legend and settings labels updated to the new controls; controls reminder on tool switch and in Tab.
F1: "Storm (≈25 cm)" and "Major event (≈1 m in 4 h)" buttons. Save format version 2 with
migration (contract zones → boxes, box state from the snow, Survival cold on, computer lock from the
stage). Fixes found in the screenshot review: snow sparkles lined up in dotted rows (fract-hash
precision at large world coordinates → new `cw_hash_cell` in `shaders/noise.gdshaderinc`); shovel
blade had a 40 cm back plate that hid the scoop and its load (now a 20 cm back with side walls);
pushing blades were yawed with the shaft instead of square to the walking direction; deep roof
snow drew metre-high lobes on the small porch gable (pillows are now capped by plane size).

## 9b. Polish pass 2 — what changed

**Both hands on every tool (§1).** Every hand tool is now held in both hands in every pose
(idle, scooping, holding a load, throwing, pushing), at every look angle, in first and third
person. Grip points live on the tool model (`ToolController._grip_frames()`): the top (right) hand
closes over the T-grip, the lower (left) hand wraps the shaft 42–52 % of the way down, palm up;
the sleigh is held overhand on its crossbar with both hands. Each mitten is placed so the bar runs
through its closed fist (`GRIP_IN_HAND`), so nothing floats, gaps or passes through the shaft.
*First person:* the mittens follow the viewmodel tool exactly. *Third person:* the tool is set
against the body for the pose (top grip at the right hip, shaft running across the front of the
body like a real shoveller), then both arms reach it with two-bone IK
(`CharacterModel.reach()`; the shoulder slides forward up to 10 cm on a long reach, and the lower
hand slides up the shaft if a pose would put it out of the left arm's reach). Standing still with
a tool uses a new `tool_idle` pose (tool held in both hands instead of hanging from one).
Checked by `test_both_hands_grip_every_tool` (7 tools × 5 poses × 5 look angles × FP/TP = 700
hand placements, worst 2.7 cm FP / 1.0 cm TP from the bar) and the screenshot grid
(`shot.tscn -- --grid=<dir>`, 160 shots).

**Bigger scoops (§2).** Hands carry a double handful (30 L, filling at 85 L/s) and every other
tool carries 1.5–1.8× more (the electric shovel chews 2× faster), keeping the ladder and the specialties (new table in §7; throw and
push values unchanged, the hand toss is still 1.8 m). The snow in the cupped hands and on the
blades grows with the bigger loads (a full load heaps visibly above the blade). Measured with
`tests/grind_bench.tscn -- --full=1` (bot clears the path-to-the-house box with bare hands through
the real controls):

| | Polish pass 1 | Polish pass 2 |
|---|---|---|
| Bare-hands removal rate (first 120 s) | 0.0204 m³/s | **0.0376 m³/s** |
| Path box cleared (bot) | 7.5 min, 725 strokes (3.0 game h) | **3.6 min, 380 strokes (1.4 game h)** |
| Same, at a human pace (~1.1 s per stroke) | ≈ 13–14 min (5.4 game h) | **≈ 7 min (2.8 game h)** |

With the real controls, the same 12 scoop-and-toss strokes remove ×2.0 the snow with the new hand
values (`test_bigger_scoops_and_tool_ladder`). The benchmark bot itself was also made smarter
(cell-exact nearest-snow targeting, carries porch snow down the steps, measures the box every
pass), so it no longer gets stuck on the porch or stairs.

**Work outline (§3).** While you take snow out of a clearing box — scooping or pushing with hands
or any tool, the electric shovel, or a walk-behind blower — a thin, pale-blue line traces that
box's whole outer boundary on top of the snow (`scripts/world/box_outline.gd`, fed by
`Boxes.note_work()` / `Boxes.work_box`). Only the box being worked is outlined; the line drapes
over the snow (re-laid every 0.35 s as you dig), stays while you work, fades 3 s after you stop
(1 s fade) or as soon as you walk 6 m away, and vanishes when the box completes (the completion
flash takes over). It's dimmed at night so it stays a quiet hint; on streets and parking lots only
the 30 m around you is drawn. The throw landing ring turns **amber** when the throw would land back
inside the box you're clearing (red over the street is unchanged and takes priority).

**Keys and truck (§4).** Played through with real input in both modes: dig up the keys in the lawn,
walk to the truck, E to get in, start, drive out of the driveway (`test_truck_keys_end_to_end`,
plus a screenshot of the truck leaving the driveway). Fixes: you can get in when you're beside
and facing the truck even if the crosshair ray hits the snow heaped on it (snow on the truck
never blocks entry); without the keys: "The truck is locked and the keys are missing. You had them
before the storm — they must be out there somewhere."; getting into a snowed-in truck says so at
once with the depth around the wheels; when it can't move the HUD says exactly why ("Stuck: N cm
of snow under the wheels — this pickup truck only clears about M cm. Dig around the wheels and clear
a path.", "Snowbank ahead: N cm deep — too much to drive through…"); status lines clear themselves
after a few seconds. Found keys survive save → load (tested in both modes).

**Snow refinements (§5, HANDOFF items 1–4).**
1. *Wading leaves a trench.* Every ~20 cm of walking through snow deeper than 15 cm
   (`Snow.wade()`), the snow under your body is trodden down to ~40 % of its depth and the rest is
   shouldered to both sides as loose snow, volume conserved (snow in a completed box is left alone;
   yard snow never lands on the road; snow above your hips is never trodden down — it stays a wall
   to dig through). Walking speed now uses the snow you're stepping into, so walking back along your own
   trench is easier. (The old footprint compression, which wasn't volume-conserving, is gone.)
2. *Scoop at your feet.* Looking steeply down, the aim comes back to your boots, so the strip under
   your feet can be scooped.
3. *Blade hidden in deep snow.* First-person tool parts and their load use clip shaders
   (`shaders/viewmodel_clip.gdshader`, `viewmodel_snow.gdshader`, globals `vm_eye` / `vm_snow_y`):
   whatever part of the blade is below the real snow surface isn't drawn, so a blade pushed into
   deep snow disappears into it. Held up in view (looking ahead), nothing is clipped.
4. *Loose snow hardens.* Thrown / pushed / slid snow sinters into cohesive snow with a 30-game-hour
   time constant (`balance.loose_harden_hours`): about half is firm after a day, almost all after
   three, so old banks hold steep cut faces.
Soft powder puffs (`SnowFX.puff`) where snow is scooped, where thrown snow lands and as you wade.
Item 11 (Blender models / a true 3D snow volume) left out as instructed.

**World and UI pass (§6) — change list.**
* Street lamps were placed every 26 m with no regard for lots: one stood in the middle of the
  player's driveway apron (in the truck's way). Lamps now shift along the curb to avoid driveway
  aprons, walkways and mailboxes on every street.
* HUD weather panel is pinned to the right edge and grows leftward, so long readings
  ("-14 °C (feels -29)") never run off-screen.
* The hand-tool hotbar is hidden while driving (it read "Bare hands" under the vehicle line).
* Empty tool slots are dimmed (a row of four empty slots read as four pairs of mittens); the
  selected slot still shows the mitten.
* Interaction prompts show the key actually bound to Interact instead of a hard-coded [E].
* Help app: amber landing ring, the work outline, wading trench / scooping at your feet, what the
  truck needs.
* Work outline dimmed at night (it's unshaded and glowed).
* Store: the yellow "ORDER PICKUP" and "VEHICLE BAY n" lettering floated in the air; each now sits
  on a sign board on a post.
* Walked the streets (Maple, Birch, Cedar, school/store, church/dump) at noon, dusk, night and in a
  blizzard: no other floating/sunken props, gaps or z-fighting found. Far-away street lamps can
  look unlit in long shots because only the lamps nearest the player get real lights (by design,
  for performance); their bulbs still glow.

**Unchanged on purpose.** Survival cold from minute one, the wadeable opening and the 48-hour clock
pausing during storms (decisions a–c). Save format unchanged (version 2): no new saved state —
`loose` depth was already saved, the work outline is transient. Conservation tests pass exactly
(wading included); the road rule is untouched.

## 9c. Polish pass 3 — what changed

Order of work: §2 → §3 → §5 → §6 → §4 → §1, each checked with the parse check, its suites and the
save fixtures before the next. Save format unchanged (**version 2, no new keys**): every new piece of
state is derived (Gerry's walk from the tutorial stage, the moved mailboxes and the new trail from
the layout, tool exposure from the snow). Old saves and the eight `tests/fixtures/polish3/` saves
load and play.

**Main menu (§1).** The menu is the game title and PLAY / SETTINGS / EXIT over a live view of the
real neighbourhood at blue hour (`scripts/ui/main_menu.gd`): the world is built with the game's own
builders behind a short fade (the buttons are up at once), light snow falls (`WeatherFX`), and the
camera glides along three `Curve3D` shots, crossfading (a dip to dusk) between them — west down
Maple Street ending on Gerry on his porch, a slow sideways dolly across from home (the truck in the
dug-out driveway and a neighbour shovelling beside it), and east along Birch Avenue. The paths run
down the middle of the streets at 2.4–3.2 m (below the lamp heads and the boulevard trees'
branches), the end of the Maple shot is chosen so no tree stands between the camera and Gerry, and
the three nearest street lamps get real lights; windows are lit by the time of day. Lower graphics
settings shorten the view, thin the flakes, lower snow detail and shadows and drop Gerry; settings
apply live over the running background.
*Isolation:* the snow is a still snapshot — filled once, `Snow.auto_process` off (no relaxation, no
syncing, no accumulation), no boxes, the clock stopped, nothing in `Game`, no notifications, no
saves. What the menu sets on autoloads (`Snow.auto_process`, the weather override) is put back
before New Game / Continue (the background stops first) and when the menu leaves the tree; New Game
and Continue reset or load everything else as before. Tested: a game started after two minutes of
menu is identical (snow, money, date and time, weather, contracts, economy, municipal, survival,
boxes, notifications) to one started at once and to one started with no menu at all; the same for
loading a fixture; and after playing, returning to the menu and starting again.
*Text:* the tagline is gone; the single-player / procedural credit line moved from the bottom of the
top screen into the Play panel's footer; the mode cards keep one functional line each (Fun: no cold,
warmth meter or bills; Survival: cold, warmth, the hydro bill amount from balance data, freezing
sends you back to your last sleep). EXIT still calls `get_tree().quit()` (tests use `quit_hook`).

**New-game overwrite dialog (§2).** `Panels.confirm()` sizes the dialog to its content: the message
wraps at ≤ 620 px (min 380), the box hugs it with even padding, the text and the button row are
centred, and the dialog is centred on screen at every resolution (16:9 maps to the 1920×1080 canvas;
21:9 widens it). Same text, including "will be overwritten the next time you sleep".

**House interior (§3).**
* Bed: "[E] Go to sleep"; the sleep prompt lost "Sleeping ends the day and saves the game." (still
  exactly *Sleep until 7:00 a.m.* / *Not yet*).
* TV weather: a 16:9 screen (1280×720 on the 1920×1080 canvas) in a bezel, centred, with large type:
  current conditions with a big icon, three forecast cards (date, icon, condition, high/low, snow
  expected), the next grader pass.
* Bedroom lamp: base, stem, fabric shade and a warm bulb (`_table_lamp`). Living-room plant:
  terracotta pot, soil and nine leafy stems (`_house_plant`). Coat rack: rail with four pegs, a parka,
  toque and scarf hanging on them (`_coat_rack`).
* Radio: the forecast is read out in the HUD's subtitle box, which is now centred, word-wrapped at
  1100 px and grows with the text (`hud.subtitle_box`).
* Snow at the front door. Diagnosis: the sim never put snow inside (house cells are walls), but
  (1) the renderer draws the snow next to a wall up to the wall's centre line, which put a sliver of
  porch snow through the doorway; (2) the 1.0 m leaf in a 1.1 m opening left gaps that showed the snow
  outside; (3) falling flakes are world-space and fell through the roof. Fixes, all visual:
  `snow_ground.gdshader` discards ground snow inside the two enterable houses' footprints (+5 cm;
  global uniforms `snow_hide_a/b`, set by `game_root`), door stops on the outer half of the opening
  cover the gaps, and weather flakes are hidden whenever the camera is inside a house. Conservation
  and outdoor snow untouched (`test_no_snow_inside_the_houses`).
* Door window: a real opening in the leaf with a lightly tinted, see-through pane (its own
  transparent mesh, frost in the corners) and trim on both faces.

**Gerry, the trail and mailboxes (§4).**
* No flags or stakes on the tutorial trail (zone markers skip tutorial contracts). The trail's blue
  outline (`BoxOutline` in quest mode) is up from the moment the job is agreed until it's done, never
  fades, dims a little at night; the objective reads "Clear the outlined path at Gerry's". Working
  another box shows its usual work outline alongside.
* Mailboxes: on every built lot (all 22 — none skipped) the mailbox now stands beside the house
  walk, partway up it, on the side away from the driveway, facing the walk (`Layout.MAILBOX_U`,
  `mailbox_v()`, `house_info` keys `mailbox`, `mailbox_face`, `mailbox_path_point`). Each is outside
  every box, reachable from the path box, off the windrow; lamps were re-checked (none on an apron,
  walkway or mailbox); the keys are not near one.
* `gerry_trail` is now the walk from his mailbox up plus the stairs (`Layout.gerry_trail_rects()`),
  no connector. Old saves rebuild it from the new rects with peak and progress taken from the snow,
  and the tutorial contract's zone rects follow (tested with the mid-trail fixture).
* Gerry's sequence (`neighbor.gd` modes, `game_root._update_tutorial`): when the trail is done he
  walks down it (walk animation, smooth height on the steps) to meet you by his mailbox; talk to him
  and he thanks you and invites you in (a HUD speech line — no modal, you're never frozen), walks back
  up to his door and waits there, turned towards you and waving, for as long as it takes; he opens
  the door and goes in once you come close (or if you're already inside), and walks to the fire. The
  objective reads "Follow Gerry inside". Inside, his explanation runs line by line on the HUD (each
  line timed by its length, 4–14 s, or advanced with Interact); for the computer part he walks over to
  his computer, and the line says what it's for and that yours is now unlocked. Payment ($40–55 at
  completion of the trail), `computer_unlocked`, the stage advance and warming up indoors are
  unchanged. Loading at TRAIL_DONE puts him at his door, waiting. He's never repositioned in view.

**90 % rule (§5).** `box_completion` 0.98 → **0.90** (`data/balance.tres`, `BalanceData`,
`generate_data.gd`). At 90 % the remaining ≤ 10 % is removed (the documented conservation
exception) and the box is 100 % — paths, driveways, sidewalks, streets, parking lots and Gerry's
trail alike; the HUD line, the contract, recurring visits and the 48-hour clock, the outline and the
flash all follow. Sampled big boxes are counted exactly from an estimated 85 % (`EXACT_MARGIN`), and
also re-counted exactly every 1.5 s once the estimate passes 50 % (`RECHECK_*`), so a strip the
sample overrates can't hold a street just under 90 %. Texts say 90 %. `grind_bench --full=1`: the
bot clears the path box by hand in 3.2 min of play, 349 strokes, 1.3 game hours (3.6 min, 380
strokes, 1.4 h at 98 %) — about 6.4 min at a human pace.

**Buried shovel pickup (§6).** `ToolItem.exposure()` compares 17 points along the shaft and blade
with the snow surface (2 cm tolerance); at ≥ 75 % the tool can be picked up (below that a short
"dig it out" hint). The pickup no longer needs the crosshair on the tool: looking at the snow over it
within 1.7 m while facing it works (`Player._nearby_pickup`). A tool on bare ground is picked up
as before; one buried by a later snowfall needs digging out to 75 % like the shovel.

**Also fixed (found at baseline).** A burst of more than five notifications in one frame (a long F1
jump, a bad night's sleep) looped forever in `hud._on_notify` and ran out of memory; it now prunes
only the notices still showing.

## 9d. Polish pass 4 — what changed

Order of work: §0 baseline → §2 → §5 → §3 → §4 → §1, each checked with the parse check, its suites
and the save fixtures (polish 3 and polish 4) before the next, with a backup after each section.
**Save format: version 2, no new keys.** Everything new is derived: forecasts are a function of the
weather seed, the hour they're issued and the hour they're for; the mailboxes, Gerry's trail and
meeting spot come from the layout; the monitor's lock screen from `computer_unlocked`; the photo is
rendered when the world is built. Old saves, the eight `tests/fixtures/polish3/` saves and the twelve
new `tests/fixtures/polish4/` saves load and play.

**Interior (§2).**
* Office chair (`InteriorBuilder._chair_base`, its own mesh "OfficeChair"): the seat and back as
  before, now on a mechanism plate, a chrome gas-lift column in a sleeve, a hub, five spokes and
  twin-wheel casters resting on the floor. Same position and height; no collider (as before). Tested:
  every caster within 1 cm of the floor, nothing intersects the desk, walls or other furniture.
  Gerry's house has no office chair, and his computer is a separate builder — left unchanged.
* The monitor shows a screen (`scripts/world/computer_screen.gd`, `ComputerScreen`, a 540×320
  SubViewport): a lock screen (big time, date, padlock, "Locked") until Gerry has set the computer up,
  then a desktop in the computer UI's look — a dusk wallpaper with hills, spruces and a moon, an icon
  and name for each of its apps, a taskbar with pinned apps and the game-time clock. It renders only
  when the lock state or the shown game minute changes and only while the player is in the house
  (`UPDATE_ONCE`, otherwise disabled — never per frame, nothing outdoors); headless builds work.
  Unshaded, so it reads at night without lighting the room. Using the computer opens the computer UI
  as before.
* Peripherals: a keyboard with key rows and a space bar, a mouse on a mouse pad, two speakers with
  cones, the monitor's foot; the tower under the desk got a front bezel, drive bays, a power button
  with a blue light and an intake grille.
* The living-room lamp (the floor lamp beside the front door — not pass 3's `_table_lamp`, which is
  the bedroom lamp): new base only (`_floor_lamp_base`): a wide, heavy turned foot, a rounded body,
  a neck narrowing to the stem, a socket under the shade. The shade and its glow are untouched; the
  floor lamp has no light of its own, and the room's lights (type, position, colour, energy, range,
  attenuation, shadows) are asserted unchanged by a test.

**The photograph (§5).** `scripts/world/framed_photo.gd` (`FramedPhoto`): on the wall beside the
front door of the player's house only, between the door opening and the floor lamp, centred in the
free wall at eye height (1.6 m), flat on the wall's inner face. A wooden moulding, an off-white mat,
the print and a hint of glass. The print is the player's character standing by the front of the
pickup, facing the camera, the small shovel leaning against the passenger door (the pickup is
left-hand drive: passenger side = +X in the truck's frame), on a sunny snowy day — three-quarter
front view from the passenger side, a white border, a slight warm tint and a soft vignette, no text.
It is rendered once, from the game's own models (`CharacterModel`, `VehicleModels`, `ToolModels`,
`Props.evergreen`), in a SubViewport with its own World3D, sky, sun and camera, when the world is
built (behind the fade), copied to a static texture, and the viewport is freed. The scene is plain
meshes — no vehicle node, physics, registration or roof snow — and touches no autoload (tested:
no extra vehicles, registry entries or notifications; snow and box checksums unchanged). Headless:
a grey placeholder. The print is a normal shaded material, so it darkens with the room at night.

**The scoop indicator (§3).** Diagnosis (`tests/indicator_report.tscn`, bare hands and every
shovel-type tool, three pitches, first and third person): the cut was always where it should be —
at the crosshair's point on the snow within reach, 0.6–1.9 m ahead — and a release landed exactly on
the ring. The mismatch was the marker: while scooping, the only marker on the snow was the landing
ring, drawn 1.2–4.2 m out (0.1–2.5 m beyond the snow actually being cut), so the "where it's going"
marker read as "where it's taking from". Fix (indicator only, the scoop is untouched): one indicator
(`ToolController.indicator`, states `pickup` / `landing` / `preview`):
* while the tool is cutting: on the snow at the pickup — the centre of the cells cut that frame
  (`last_cut_center`, from the same `_fill` that decides the cut), sized to the scoop width, neutral
  white;
* loaded and no longer cutting (look up): it glides over 0.25 s to the landing — the same
  calculation `ThrownSnow` uses (trench lift included) — and follows the aim; red over the street
  (the release is refused and the load kept), amber inside the box being worked;
* back into snow with room in the load: it glides back to the pickup;
* after a release: gone until the next scoop (it shows while the scoop button is held, or while a
  refused load is kept);
* it never jumps (a smooth glide between states, an 18 m/s cap) and dims at night like the work
  outline (`0.3 × night` transparency). The crosshair fades to 15 % while the indicator is busy and
  comes back for prompts.
Push, blowers, vehicles and the electric shovel (it throws continuously, so its landing marker is
already where the snow goes next) are unchanged. `grind_bench` is within noise.

**Mailboxes and Gerry (§4).** All 22 mailboxes now stand at the corner of the walk and the sidewalk:
on the yard side of the sidewalk, on the side of the walk away from the driveway, 0.65 m out from the
walk and 0.55 m into the yard (`Layout.MAILBOX_U` −2.75, `MAILBOX_V` 0.55), facing the street, on
the ground, outside every box with clearance, off the junction, the driveway and its apron and the
boulevard, reachable from the sidewalk and the foot of the walk. None had to be skipped. Junction
paving and box rects are unchanged. `house_info["mailbox_path_point"]` is now the foot of the walk
beside the mailbox.
* Gerry's trail (`Layout.gerry_trail_rects()`) is his whole walk from the sidewalk up, plus his
  steps. At the opening it holds 6.88 m³ of snow on 10.5 m² (pass 3: 7.01 m³ on 9.6 m²).
* He meets the player at his mailbox (`Neighbor.meet_point()` from the layout); the rest of his
  sequence is unchanged.
* Old saves: while the trail is being cleared it is rebuilt on the new rects with peak and progress
  from the snow; a save at or after TRAIL_DONE keeps the trail done and the stage (stage wins). Tested
  with the mid-trail and Gerry-waiting fixtures of both passes, both modes.
* Lamps re-checked (none on an apron, walk or mailbox), the buried keys are clear of every mailbox,
  and the main menu's Maple Street shot still ends on Gerry with nothing between (mailboxes count as
  obstacles for its clear-view check).

**Weather (§1).**
*Audit (before any change).* The schedule is drawn per winter from its own seeded streams (events,
tier bag, temperatures, cloudy days); saves keep only the year, the seed and each event's
alerted/warned flags, so it is regenerated on load. Forecasts were per day: a timing shift of
`fc_shift × (0.5 k + 0.5)` hours (±2 h even for today), an amount range of ±(15 + 8k) %, the shown
condition the forecast one until the event started; but the day's high, low and wind read the true
hourly values (an unforecast blizzard's cold and wind leaked into the forecast), unforecast major
events showed as a 4 cm light snowfall, and the radio read the current conditions plus tomorrow's
card. Alerts: an advisory 9 h before forecast heavy/blizzard events, onset alerts at the first top of
the hour after a surprise or blizzard starts, extreme-cold warnings at 6:00. Majors opened at full
blizzard rates (their first hour ~25–30 % of the total); storms mostly opened moderate but their
first full hour could already be heavy. The sky, light and fog changed at the top of each hour in
one step (ambience already crossfades over a few seconds).
*The truth.* Unchanged except the onset of storms and major events: the partial hour an event
starts in and the next full hour (1–2 game hours) fall at a light-to-moderate lead-in rate —
at most `storm_onset_cm_h` (1.0 cm/h), at most `storm_onset_mean_frac` (0.5) × the event's mean rate,
below the first hour after it — then the original bell builds to the peak, renormalised so every
event drops exactly its total; start and end hours unchanged. Light snowfalls are unchanged.
Tested over seed 2024 and 20 other seeds, winters 1–5 (105 winters, 3217 events): the same events,
tiers, totals, start and end, first and last snowy hour, per-winter totals and alerts hour by hour;
`depth_report` gives identical depth curves. The look of the weather (sky, light, fog, falling
flakes) now eases from the previous hour's over the first 6 game minutes of an hour; the snow that
falls and every reading are the hour's own; the falling-flake look itself is unchanged.
*One forecast model* (`Weather.fc_hour(target, issued, radio)` → condition, rate, temperature,
wind; `Weather.forecast(days)` builds the TV's and the computer's day cards from it; the radio's
bulletin reads it hour by hour). No display reads the hourly truth ahead of the current hour (hours
already gone today are what happened). It is a deterministic function of the seed, the issue hour
and the target hour — nothing saved. Each event carries one fixed amount error (its own seeded
stream) and its `fc_shift` timing error, scaled by the lead time (`fc_error_base` +
`fc_error_per_day` × days ahead; timing up to `fc_timing_h_per_day` per day ahead; temperatures by
up to `fc_temp_error_per_day`), so the call is revised every game hour and converges as the event
approaches. Kept: forecast events stay forecast; storms that arrive stronger than forecast stay
under-called (the weaker system, a few cm) until close; an unforecast major event is never on the
TV before it starts — the radio picks it up only within `radio_surprise_horizon_h` (1 game hour)
of its start; the alerts are exactly as before. `forecast_skill` (1.0) divides the error and
multiplies the horizon (wired and tested, no upgrade or UI yet).
*TV:* the pass-3 layout; three day cards from the model (icon, condition, high/low, expected snow as
a range that narrows as the day gets closer, e.g. "Snow 2–6 cm"), and one small "Forecast updated
2 p.m." line in the screen's bottom margin (the TV's size is unchanged).
*Radio:* same interaction and subtitle box. "Radio: " then, while it's snowing, what's happening now
("Right now: moderate snow, heavy snow developing."), then the next three game hours, one short
phrase each — the hour, the condition, the temperature on the first hour and whenever it changes,
the snowfall rate when it's heavy, "wind picking up" — and the grader line as before, e.g. "Radio:
Midnight light snow, −7°, wind picking up. 1 a.m. moderate snow. 2 a.m. heavy snow, 1 to 2 cm an
hour. City grader expected Dec 18 07:33." The radio can't be left on (pass 3's interaction is kept),
so there are no unprompted hourly bulletins. The truck's radio reads the same bulletin.
*Ripples:* `storming()` is unchanged (heavy or worse), so the 48-hour clock now pauses a little
later in a storm: storms reach heavy +0.12 h later on average (80 of 679 an hour later), major
events 2 h later (their lead-in). Survival's weather multipliers follow the hourly condition, so the
lead-in hours count as light/moderate. The peak hourly rate of major events rises (the same snow in
fewer hours): mean 32.0 → 45.0 cm/h, highest 52.2 → 109.6 cm/h; storms 2.55 → 2.54 mean, 5.14 →
5.52 highest; light snowfalls unchanged. The grader, the first two light events of winter 1 and the
F1 storm buttons (which use the override) are unchanged.

## 10. Assets

* **Models:** procedural meshes built at runtime with `MeshKit`. No Blender (not reachable from
  the build environment); the spec's fallback is used.
* **Textures/materials:** shaders in `shaders/`.
* **Audio:** `tools/audio/gen_audio.py` (numpy/scipy) synthesises every sound into `assets/audio/`.
  Rerun with `python3 tools/audio/gen_audio.py [name filters…]` from the project root, then let
  Godot reimport.

## 11. Automated tests and tools

* `godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn` — all suites
  (`-- --only=snow|systems|gameplay|polish3|polish4`, `--test=name_part`, `--verbose` to print the
  passing checks with their measurements too). Exit code 0 = pass.
  * `tests/test_snow.gd` — heightfield ops, conservation, road rule, relaxation, snowfall stays on
    top, exact save round-trip, grader lane, op timings.
  * `tests/test_systems.gd` — clock, weather shape, skip == real time, grader, windrows, store,
    contracts on boxes, **90 % snap (pass 3; was 98 %)**, recurring visits / reopening, bidding, **cold from
    minute one / Fun no cold**, warmth rates by weather, bills, saves, winter end, difficulty cap,
    **48-hour rule (kept at 47, lost after 48, reset on completion, paused in storms)**, **storm
    tiers by winter**, **lamp-height ceiling with volume conserved**, upgrades.
  * `tests/test_gameplay.gd` — the real game scene with real input actions, including **sweep
    fill → full cap → full and partial release throws, bare pavement fills nothing**, shovel load
    growth and range, road refusal, **RMB push building a mound (volume conserved)**, **tool
    specialties**, pusher at the curb, scraper angle (R), **odd pile over the buried shovel**,
    **letter without payment instructions**, cry for help, **wading from the start in both modes,
    speed vs depth, hip block, banks below/above the hips, digging out after a major event**,
    **boxes (separate driveway/path, reopen on snow, save/load)**, **snowfall on top of a yard / a
    cleared driveway / a bank in real time, sleep and F1 skips**, **computer lock + save/load**,
    **sleep to 7:00 from evening / after midnight / morning with no date or weather**, and the
    previous coverage (store, blowers, vehicles, grader, tutorial, keys, outage, UI, death, summary,
    audio files). Pass 2 added: **both hands on the shaft for every tool / pose / look angle / view
    (700 placements)**, **bigger scoops + tool ladder + ×2 hand removal with the real controls**,
    **work outline (appears on work, outer edge of only that box, fades after work stops, comes
    back, gone on completion, amber landing ring in the box only)**, **snow refinements (wading trench conserving volume, faster
    back along it, scoop at your feet, blade clip under the snow, loose snow hardening)** and **the
    truck end to end with real input in both modes (locked + missing-keys message, keys found and
    saved/loaded, entry despite snow on the truck, "what's blocking" message, dig out, drive onto
    the street)**.
  * `tests/test_polish3.gd` (pass 3) — **save fixtures** (`tests/fixtures/polish3/`, both modes ×
    opening / mid Gerry trail / after the tutorial with a contract / mid-winter: load, move, scoop,
    sleep, autosave, reload), **overwrite dialog fits and centres** (4 resolutions), **no snow inside
    the houses** (storm, major event, throws at the door, a pushed pile), **bed prompt and sleep
    text**, **90 % snap updates the HUD, contract, recurring visit, 48-hour clock, outline and flash**,
    **shovel pickup at 75 % with real input** (not at 0 % / 60 %), **pickup fully exposed and after
    a snowfall**, **Gerry's trail outlined without flags** (still up after 10 s idle, gone on
    completion, alongside another box's outline), **Gerry walks in and the player follows** (both
    modes, real input, no jumps while visible, player never frozen, computer intro, unlock, paid
    once), **Gerry waits if you don't follow / lets you in first**, **Gerry's sequence survives save
    and load**, **mailboxes beside paths, lamps clear**, **mid-trail fixture uses the new trail**,
    and the main menu: **top level is exactly title / PLAY / SETTINGS / EXIT**, **EXIT quits (hook)**,
    **PLAY → mode → New Game / Continue in both modes**, **two minutes of menu leave no trace**,
    **fixture load after the menu = direct**, **back to the menu and start again is clean**,
    **graphics settings apply over the background**; and **a play-through from the menu with real
    input in both modes** (letter, shovel at 75 %, Gerry's outlined trail, follow him in, computer
    intro and unlock, bid and win a contract, path and driveway to the 90 % snap, sleep in the bed,
    reload).
  * `test_systems.gd`: the 98 % test became **`test_box_90_percent_snap`** (path, driveway, sidewalk,
    street, parking lot, Gerry's trail: 89 % stays open, 90.1 % completes to bare ground, snow outside untouched) plus
    **`test_street_completes_at_exact_90_through_sampling`**. `test_gameplay.gd`'s tutorial test
    follows the new Gerry flow.
  * `tests/test_polish4.gd` (pass 4) — **polish-4 save fixtures** (`tests/fixtures/polish4/`, both
    modes × opening night / mid Gerry trail / trail done with Gerry waiting / after the tutorial with
    a contract / mid-winter (Jan 20) / partway through a scheduled storm in heavy snow: load, move,
    scoop, sleep, autosave, reload); **office chair on casters** (every caster within 1 cm of the
    floor, nothing intersecting); **computer screen** (lock screen, desktop once unlocked, no
    re-render when nothing changes, headless); **living-room lighting unchanged** (every room light's
    type, position, colour, energy, range, attenuation and shadows asserted); **the photo** (player's
    house only, between the door and the lamp, flat within 2 cm, intersects nothing; its scene is
    isolated: no vehicles, registry entries or notifications, snow and box checksums unchanged;
    headless placeholder); **the scoop indicator** (real input, every hand tool × 3 pitches × first
    and third person: within 15 cm of the cut while scooping, within 25 cm of the landing when
    loaded, never more than a glide step plus the player's own movement in a frame, gone after the
    release; red over the street, amber in the box); **mailboxes** (all 22 at their walk–sidewalk
    corner within 3 cm, facing the street, outside every box, on the ground, reachable from the
    sidewalk; lamps and keys clear; Gerry's trail = his walk from the sidewalk + steps; old saves and
    the moved trail, stage wins); **weather** (the truth unchanged for seed 2024 + 20 seeds × winters
    1–5 against the pass-3 dump in `tests/fixtures/polish4/weather_truth_baseline.json`, alerts hour
    by hour; the storm onset; TV and radio the same in real time, after a sleep skip and after
    save → load with the mid-storm fixtures; no display reads the truth ahead; accuracy: error vs
    lead by the hour and by the day, the radio's next hour vs the TV's three-day call, revised hourly,
    converging, forecast skill; unforecast majors never on the TV before they start, on the radio no
    earlier than its horizon, advisories never contradicted; the radio's phrasing; the longest
    bulletin and the fullest TV fit at 1280×720, 1920×1080, 2560×1440 and 3440×1440); and **a
    play-through from the menu with real input in both modes** (the letter from the moved mailbox,
    the shovel, the lock screen, Gerry's trail from the sidewalk outlined without flags, Gerry meets
    you at his mailbox, follow him in, the computer intro, the desktop, a contract, your path cleared
    with the indicator on the cut and then at the landing, the TV and the radio, the start of a
    scheduled storm watched indoors with the radio before and during, the photo in view, sleep,
    reload, the same TV and radio).
  * Pass 4 changed one existing test: `test_gameplay.gd`'s wading test walks to the layout's
    `mailbox_path_point` instead of a hard-coded offset from the mailbox.
* `godot --headless --path . res://tests/make_fixtures.tscn [-- --only=<point> --mode=<mode>]` —
  rebuilds the polish-3 save fixtures; `-- --set=polish4` the polish-4 ones.
* `godot --headless --path . res://tests/weather_truth.tscn -- --out=<file.json>` — dumps the
  weather that falls (every event, every winter total, the alerts hour by hour) for seed 2024 and 20
  other seeds, winters 1–5; run it on another build and compare.
* `godot --headless --fixed-fps 60 --path . res://tests/indicator_report.tscn` — the pass-4 scoop
  diagnosis: per hand tool, pitch and view, where the cut is, the crosshair, the hands, the
  indicator, and the indicator vs where a release lands.
* `godot --headless --path . res://tests/parse_all.tscn` — parse check of every script.
* `godot --headless --fixed-fps 60 --path . res://tests/perf.tscn` — CPU frame-time benchmark.
* `godot --headless --fixed-fps 60 --path . res://tests/grind_bench.tscn -- --full=1` — a bot
  clears the path-to-the-house box with bare hands (works on older builds too, for comparisons).
* `godot --headless --path . res://tests/depth_report.tscn -- --years=1,5` — winter depth curves.
* Screenshots: `godot --path . res://tests/shot.tscn -- --scene=game --out=shot.png
  [--setup=heavy|medium|light|cleared_drive|drive_done|strokes|major|trail_bank|lamp_bank|mound]
  [--pose=hold|scoop|push|toss --load=0..1] [--tool=id] [--tp=1] [--player=u,v,yaw] [--pitch=deg]
  [--hour=h] [--lotcam=u,v,h,lu,lv,lh | --cam=x,y,z --look=x,y,z] [--ui=…]`. Pass 2 added
  `--grid=<dir>` (every tool × pose × FP/TP × pitch in one run), `--playerw=x,z,yaw` (world
  position), `--work=path|driveway` (keeps the outline up), `--marker=1` (landing ring),
  `--setup=truck_out --drive=frames` (keys found, driveway dug, truck driving out). Pass 3 added
  (documented at the top of `tests/shot.gd`): `--house=player|neighbor` with `--hcam=x,y,z
  --hlook=x,y,z` (free camera in the house frame) or `--hplayer=x,z --hlook=…` (first-person player
  indoors, with the prompt under the crosshair); `--ui=tv|radio|sleep` (game) and
  `--ui=play|overwrite` (menu); `--ui_frames=n`; `--setup=trail|trail_done` (Gerry's job taken /
  trail cleared); `--gerry_walk=frames` (clear the trail after spawning so he walks down) and
  `--gerry_invite=frames` (talk to him by the mailbox so he walks back up to his door);
  `--seq=N --every=F` (a series of frames); `--menu_shot=k --menu_at=f --menu_frames=n` (jump the
  menu camera along its path); `--expose_shovel=f` / `--shovel_h=h` (the buried shovel dug out to a
  fraction, seen from 1.3 m); `--snow_all=d`. Use `--fixed-fps 60` on the godot command line for
  the menu path and Gerry series, so slow software rendering doesn't skip ahead. Pass 4 added (also
  at the top of `tests/shot.gd`): `--seed=N`; `--unlock=1` (tutorial complete, computer unlocked);
  `--storm=lead|peak [--storm_tier=storm|major]` (the clock in the first hour or the heaviest hour of
  a scheduled event); `--light=h` (light the scene as at hour h without moving the clock);
  `--gerry_meet=frames [--meetcam=1]` (Gerry down at his mailbox, the player in front of him);
  `--mailcam=player|neighbor|<lot>` (a street view of a mailbox); `--scoop=mid|loaded|glide
  [--aim_up=deg]` (a real scoop, captured mid-sweep, loaded and aimed up, or as a glide series);
  `--photo_out=path` (also save the photo's texture at full size).

## 12. Performance (measured)

`tests/perf.tscn` on the build VM's CPU (headless, so GPU cost is not included; budgets unchanged:
relaxation 2.5 ms/frame, chunk rebuilds 3.5 ms/frame, both time-capped). Pass 2 was measured on the
same VM with nothing else running; differences of ±1 ms between runs are VM noise. Pass 3: the
median of three runs, with the pass-2 build (the pass-3 baseline) re-run three times alongside it on
the same VM — its numbers are in brackets; the two builds are within run-to-run noise of each other.
Pass 4: the same method (three runs of each build, alternating, nothing else running; medians;
the pass-3 build in brackets).

| Scenario | Before the polish pass | Polish pass 1 | Polish pass 2 | Polish pass 3 [pass-2 build re-run] | Polish pass 4 [pass-3 build re-run] |
|---|---|---|---|---|---|
| **Main menu** (live background, new in pass 3) | — | — | — | 0.28 ms avg, 0.28 ms p95; background built in 0.86 s behind the fade | 0.32 ms avg, 0.39 ms p95; built in 1.01 s [0.30 / 0.38; 0.93 s] |
| World load | ≈ 0.9 s | 1.0 s | 0.78 s | 0.66 s [0.82 s] | 0.70 s [0.67 s] (headless: no photo render; see below) |
| Idle outdoors | 0.7 ms avg | 0.9 ms avg, 1.4 ms p95 | 0.68 ms avg, 1.07 ms p95 | 1.29 ms avg, 2.14 ms p95 [1.15 / 1.86] | 1.16 ms avg, 2.05 ms p95 [1.00 / 1.92] |
| **Indoors** (new in pass 4: the living room with the computer screen and the photo in view) | — | — | — | — | 1.04 ms avg, 1.77 ms p95 (the screen re-rendered 4 times in 5 s) |
| Shovelling in an exaggerated blizzard (20× time) | 4.5 ms avg, 11 ms p95 | 6.4 ms avg, 12.5 ms p95 | 5.8 ms avg, 11.0 ms p95 (bigger scoops, work outline, puffs) | 6.9 ms avg, 13.0 ms p95 [6.6 / 12.4] | 6.49 ms avg, 11.63 ms p95 (the new indicator) [6.41 / 12.22] |
| Hand push (RMB) in deep snow | — | 6.9 ms avg, 13.4 ms p95 | 6.1 ms avg, 11.4 ms p95 | 7.1 ms avg, 13.0 ms p95 [6.7 / 12.6] | 6.26 ms avg, 11.90 ms p95 [6.34 / 12.12] |
| Plow truck pushing a berm | 5 ms avg, 9 ms p95 | 5.6 ms avg, 10.1 ms p95 | 4.3 ms avg, 8.5 ms p95 | 5.6 ms avg, 9.7 ms p95 [5.3 / 9.7] | 4.75 ms avg, 7.76 ms p95 [4.51 / 8.63] |
| **Stress:** 4 m deep map + a major event at 20× time | — | 12.1 ms avg, 17.8 ms p95 | 10.5 ms avg, 15.1 ms p95 (relax queue of 165 tiles) | 11.8 ms avg, 16.9 ms p95 (runs: 15.4–16.9) [11.2 / 16.9; runs 15.6–17.3] | 10.64 ms avg, 16.61 ms p95 (runs 15.4–16.8) [11.19 / 15.85; runs 15.6–17.4] |
| **Peak major event** (new in pass 4): the 4 m map, the plow, 110 cm/h at game speed | — | — | — | — | 8.79 ms avg, 13.17 ms p95 |
| 3-day sleep skip | 0.3 s | 1.05 s | 0.81 s (now includes loose-snow hardening) | 0.87 s [0.81 s] | 0.82 s [0.84 s] |
| Save / load | 0.23 s / 0.07 s (0.9 MB) | 0.33 s / 0.08 s (1.0 MB) | 0.29 s / 0.06 s (0.96 MB, format unchanged) | 0.31 s / 0.07 s (0.96 MB, still version 2) [0.29 / 0.07] | 0.29 s / 0.07 s (0.98 MB, still version 2, no new keys) [0.33 / 0.07] |

Pass 2's numbers came from a quieter VM: on this one the same build measures 0.5–1.8 ms higher.
Every everyday scenario stays well inside a 16.7 ms frame at p95; the artificial stress case sits
right at the line on this VM in both builds (it was 15.1 ms on the pass-2 VM). The menu's
script-side cost is tiny: the snow is a still snapshot (no relaxation or syncing), so per frame it's
the camera path, two animated figures, three lamp lights and the falling flakes; it renders the same
world as outdoors in game. Pass-3 costs in game are small and bounded: the quest outline is the
existing outline in a persistent mode, the tool-pickup check looks at ≤ 17 points of the few tools
within reach, big boxes add an exact count at most every 1.5 s once they're past 50 %.

Pass 4: the two builds are within run-to-run noise in every shared scenario; every scenario stays
under 16.7 ms at p95 (the stress case at the line as before). Indoors, the monitor's SubViewport
renders only when the shown minute or the lock state changes (once per 2.5 real seconds at the
game's speed) and only while you're in the house. The photo is rendered once when the world is
built (headless runs skip it, so "World load" above doesn't include it): on this VM's software
renderer the capture took 1.6 s — up to 5.5 s while other jobs were running — for one 720×480
render plus a read-back (on a GPU it's a frame or two), behind the fade-in. The highest hourly rate a major event now reaches (110 cm/h) measured at
the game's own speed stays well inside the budget (13.2 ms p95). For reference, the same 110 cm/h
at the stress case's 20× time — 14.7 cm of new snow per real second, which nothing in the game
produces — measured 16.5 ms avg / 21.7 ms p95; the stress case at 25 cm/h × 20 (3.3 cm/s) is
already ~4.5× the real-time snowfall of the new peak (0.73 cm/s), so the lead-in was not
shortened.

## 13. Known issues / suggested improvements (prioritised)

Fixed in polish pass 4: the scoop marker that sat out at the landing while you were still scooping,
the mailboxes partway up the walks (old item 17), the TV and radio forecasts that read the true
weather ahead (an unforecast blizzard's cold and wind leaked into the cards), storms and major
events that opened at full strength, and the sky snapping at the top of each hour (see §9d).

Fixed in polish pass 3: the snow seen inside the front door, the door window, the tutorial flags,
Gerry vanishing after his trail, the 98 % grind at the end of every box, and the shovel that couldn't
be picked up until it was completely uncovered (see §9c).

Fixed in polish pass 2 (were items 1–4): wading now treads a (volume-conserving) trench; you can
scoop the snow at your own feet; the first-person blade disappears into deep snow instead of being
drawn over it; loose snow hardens over a day or two.

1. **Viewmodel clip line is level.** The first-person tool is cut at one snow height (the surface
   under the blade), so on a steep bank face the cut line is horizontal rather than following the
   slope. Rarely noticeable (the blade is small on screen when it's in the snow).
2. **Trench walls are cell-sized.** The wading trench is carved on the 25 cm snow grid, so in very
   deep snow its walls are a little stepped; the shouldered snow is loose and slumps to 43° until
   it hardens.
3. **Third-person lower hand slides on the shaft.** In the high throw and carry poses the left
   hand moves up the shaft (toward the top hand) when the usual spot is out of the arm's reach; it
   always stays on the shaft.
4. **Outline on big boxes.** Streets and parking lots only draw the outline within 30 m of the
   player (the full boundary of a 200 m street would be noise).
5. **Spec interpretations — confirmed in pass 2, kept as is.** (a) Survival cold runs from minute
   one (polish §10) instead of the original Part 17.2 timing. (b) The opening snow is wadeable
   (§4/§6), which shortens the original 2–3 day "dig yourself out" opening. (c) The 48-hour
   snowed-in clock pauses while it is storming (heavy snow or worse); drop `storming()` in
   contracts.gd if that ever needs to change.
6. **Big boxes are sampled.** Streets and parking lots estimate their snow every few cells and
   count exactly from an estimated 85 % (and every 1.5 s past 50 %, pass 3); on a very uneven lot
   the HUD % can still jump by a few points when the exact count takes over.
7. **The ceiling spill moves snow sideways.** Snow that would rise past 6.0 m is placed on the
   nearest cell with room (ring search up to the map edge), so a huge pile against a wall can grow
   outward a long way. Volume is conserved; it just may land further than a player expects.
8. **Hand tossing is short by design (1.8 m).** Clearing a long walkway by hand builds a ridge
   along both sides; toss level or slightly up (pitch decides the distance) or loose snow from a
   ridge built too close slides back into the trench.
9. **Porches by hand.** A porch floor sits below the surrounding yard snow, so loose snow tossed
   just past its edge slides back onto it. With bare hands (1.8 m toss) carry porch snow down the
   steps before tossing it (the benchmark bot does this); any shovel throws far enough.
10. **Third-person tool in deep snow.** In third person the tool and hands are partly hidden
   inside hip-deep snow (correct, but you can't see the load until you've dug down a bit).
11. **Big items from the previous HANDOFF still open:** Blender models and a true 3D snow volume
    (not attempted, per the polish brief).

Added in polish pass 3 (nothing from the list above was in this pass's scope):

12. **Engine error lines when you sleep via the bed.** Pressing Interact on the bed and then
    "Sleep until 7:00 a.m." prints `Condition "p_elem->_root" is true` twice (an engine-internal
    list check; nothing breaks, the sleep, save and wake-up are correct). Present at the polish-3
    baseline too (found by the new play-through test); opening the sleep prompt by other means
    doesn't print it. Worth a look with a debug build of the engine.
13. **Leaks reported at exit.** Quitting prints "N ObjectDB instances were leaked" / "resources
    still in use" — the same counts as at the baseline (EXIT from the menu: 4 / 2).
14. **Play panel over the title.** On the main menu the Play panel (unchanged position) overlaps the
    lower half of "WINTER" at 16:9; it was like this before the pass.
15. **Menu background build.** The menu shows its buttons at once, then builds the whole
    neighbourhood in one frame behind the fade (0.86 s on the build VM); the buttons don't respond
    during that frame. Building only what the camera sees would shorten it.
16. **Gerry walks fixed waypoints.** He doesn't path-find or avoid the player: stand in his way on
    the walk or in the doorway and he walks through you (the trail is cleared, so the route itself
    is always free).
17. **Mailboxes at the foot of the walk (pass 4).** All 22 stand at the walk–sidewalk corner, on the
    yard side of the sidewalk and the side of the walk away from the driveway, facing the street.
    A pass-3 save with Gerry's trail half cleared rebuilds the trail on the whole walk (its progress
    comes from the snow, so it reads lower than it did).

Added in polish pass 4 (nothing from the list above was in this pass's scope, except item 17):

18. **Major events peak harder.** The lead-in moves 1–2 hours of a 3–6 hour major event to light
    snow, and the rest of its 90–120 cm falls in the remaining hours: peaks average 45 cm/h (32 before),
    up to 110 cm/h for a 3-hour event that starts just after the hour. Frame time at game speed is
    fine (§12); if it feels too abrupt, cap the lead-in at a fraction of the event's duration
    (`_fill_hours` in weather.gd) — the brief asked for at least a game hour, so it wasn't.
19. **The 48-hour clock pauses later in a storm.** `storming()` (heavy snow or worse) is unchanged,
    so the lead-in delays the pause: by 2 h for every major event, by an hour for 80 of 679 storms.
20. **Recent alerts aren't saved.** After loading, the TV's "Latest alert" banner and the computer's
    alert list are empty until the next alert (as before this pass). Everything else on the TV and
    the radio is the same after a reload.
21. **Hourly forecast error flattens beyond two days.** Timing errors grow with lead, so for one
    particular hour two or three days out the forecast is about as often wrong as right (relative
    error ~1.2–1.3); the TV shows days, whose totals keep improving day by day (62 % → 18 %).
22. **The radio can't be left on.** It reads its bulletin when you use it (pass 3's interaction), so
    there are no unprompted hourly bulletins; a toggle and an hourly `hour_changed` bulletin would be
    the place to add it.
23. **Gerry's computer and chair.** His house has its own simpler desk and monitor (a different
    builder: a plain glowing panel) and no office chair; they were left as they were.
24. **Photo capture on software renderers.** The framed photo renders its 720×480 scene once when
    the world is built; on a software GL renderer (the build VM) that one frame takes a few seconds
    behind the fade-in. On a GPU it is one frame.
25. **`forecast_skill` has no upgrade yet.** The multiplier is wired (errors divided, the radio's
    surprise horizon multiplied) and tested; nothing in the game raises it.
