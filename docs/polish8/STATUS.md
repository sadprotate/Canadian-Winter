# Polish Round 8 — status

Branch `cw-polish8-pg` from `main` (`b81e79e`, the Polish 7 merge). Brief: `POLISH_ROUND_8_PROMPT.md`.

- [x] §17 — The hint panel. A small panel at the top right (Back / Next, OK on the last page; keys
  Left / Right / X in a new "hint" context, rebindable, capped; clickable with the cursor free) that
  never freezes anything and queues; it waits under the computer, sleep, Gerry's dialogue, pause, F1
  and the summary. Gerry's how-to, the first drive of each vehicle kind (the old panel), the first
  pickup of each tool kind and the blower's first grab go through it; "Show hints" (Gameplay) turns
  it off (Gerry then says his tips as before); the Help app lists every hint. Seen hints saved
  (`game.hints_seen`, optional; old saves derive them). Tested: polish8 `test_s17_` (8 new); updated
  polish5 `test_s4_gerry_snow_tips`, `test_s7_v3_save_round_trips`, polish7
  `test_s11_help_lists_the_keys`; also run polish5 `test_s4_`, `test_s2_`, `test_s7_typing…`,
  `test_s7_every_app_fits`, `test_s13b_snowshoes`, polish7 `test_s11_`, gameplay settings / tutorial
  / mailbox / computer / keys, polish3 `test_gerry`, systems save round trip, the polish3, polish4
  and polish5 fixture tests. 3 shots (`report/s17.md`).
- [x] §15 — The garage. The player's garage shell made usable (walls inward from the old faces,
  floor, ceiling, steps); a door from the house (locked until the keys); an overhead door run from
  its button inside (blocks people, vehicles and the blade at the old face; won't close on
  something in the doorway; saved); the plowed pickup in every blade setting and the ATV / blowers
  fit, bigger vehicles stop at the door ("Too big for the garage."); a 6-slot rack (F / E; saved);
  the pad allowed on the floor (no melt, no bill); no snow inside (cells unchanged; the ground snow
  hidden with `snow_hide_c`); no roof snow inside, it melts off; a truck in the garage stays when you
  sleep; the light; the first-visit hint. Tested: polish8 `test_s15_` (11 new); updated polish5
  `test_s7_v3_save_round_trips`; also run polish8 (all), polish7 `test_pf3_`, `test_pf1_`,
  `test_s10_`, `test_s11_`, polish5 `test_s3_`, `test_s13b_`, `test_s2_`, `test_s12_`, the app fit,
  the photo, polish3 houses / menu / playthrough, polish4 photo, polish6 generator / preloads / blade,
  gameplay and systems in full, the polish3, polish4 and polish5 fixture tests; perf `--only=garage`
  (14.5 ms p95). 3 shots now, the 4th with §7 (`report/s15.md`).
- [x] §14 — Cold nights, and a colder player. Survival only. A colder player: outdoors (the
  exposure + an own loss `player_base_loss_per_hour` 5) × `player_cold_mult` 2.2 (the owner chose the
  base loss, answer 10): the measured opening (6.1–6.2 real min outdoors, done ~12:30 Dec 1) ends at
  12.7–32.9 % on five seeds (mean 22.3; was 85–94 %), never frozen; indoors unchanged. Nights on foot
  × `night_cold_mult` 1.5 (dusk to 7:00). Enclosed cabs (`heated_cabin`): engine on warms at
  `cab_warmth_per_hour` (slower than indoors), off shelters; the ATV and blowers don't; the garage
  shelters. A new `veh_engine` key (I). Hints: cold night (forecast low under `cold_night_low_c`,
  once a night, a notification with hints off) and warming up (once). Tested: polish8 `test_s14_`
  (10 new); updated systems `test_warmth_rates`; also run polish8, systems and gameplay in full,
  polish5 `test_s9_`, `test_s13b_`, `test_s2_`, the round trip, the app fit, polish7 `test_s10_`,
  `test_s11_`, `test_pf1_`, `test_pf3_`, polish6 `test_s1_`, `test_s2_`, polish3 playthrough / Gerry /
  menu / fixtures, the polish4 and polish5 fixture tests. 2 shots (`report/s14.md`).
- [ ] §7 — Weather you can see and hear
- [ ] §12 — Every key can be rebound

## Audits (the brief's "look at first")

### §17: every place that teaches how to do something

**Into the hint panel**
- Gerry's job-beat tips: `HelpText.snow_tips()`, said at the job beat and on every re-talk during
  `NEIGHBOR_TALKED`, cut at `TRAIL_DONE`. Lines 2–4 → hint `gerry_snow` (3 pages: scoop and throw,
  push, the trail); line 1 ("Now, two ways to move snow.") stays spoken.
- The first-drive panel: `vehicle.gd` (flag `help_vehicle_<kind>`) → `game_root.show_vehicle_help`
  → `Panels.vehicle_help` (a 9 s panel). → hint `vehicle_<kind>`: driving, the blade keys, back-drag
  (blower / dump pages for those). `Panels.vehicle_help` removed.
- The tool-pickup hint: `tool_item.gd` (small shovel only, `found_shovel`, a notification). → the
  first pickup of each tool kind (`tool_<kind>`); the shovel keeps its sentence, the others use the
  tool reminder's wording.
- The walk-behind blower's first grab: `walk_behind.gd` (`help_blower`, a notification). → hint
  `tool_walk_blower`.

**Left as they are** (Decision 1)
- Notifications that report an event each time: snowshoes on (`equipment.gd`, "Hold {inventory}
  and press {interact} to take them off"), the heated pad collected, the plow fitted
  (`store.gd`, old saves only); hands full, truck locked, snowed in, keys found, computer locked,
  tutorial done, pouch, cold warnings.
- Gerry's story lines (the explanation by the fire, the keys line, the TRAIL_DONE lines, the cry for
  help), the door-line thought, the subtitles (morning, new winter, radio).
- Interaction prompts (neighbour, vehicle, tool item, blower, pad, keys, the outside rack, the
  fireplace) and the speech box's "[E] next ▸".
- Status lines (`hud.hint_l`: the tool controller's, the blower's, the vehicle's "Stuck…", "Blade
  down", the tutorial objective).
- The one-line controls reminder on a tool switch (`controls_hint`) and in Tab; the HUD's drop and
  pouch keys.
- The Help app (the reference: it now also lists every hint under "Hints"); the store's tool
  descriptions; the community letter.

**How things queue today:** the speech box is replaced by each `say_gerry` (no queue);
notifications stack (5 at most, 5.5 s each); modals (`open_modal`) free the cursor and freeze the
player. The hint panel queues its own hints, waits under the modals that aren't the map / TV /
letter / photo, and sits right of the speech box.

### §15: the garage before this round

- **The shell** (`house_builder.gd`, every lot the same): one solid siding box 6.5 × 7.5 × 2.9 m
  (house frame x 2.75–9.25, z sb−0.5 … sb+7; the player's lot: world Rect2(36.75, 100.5, 6.5, 7.5)),
  one solid collider, a decorative door (panel 5.1 × 2.2 m with 6 lit windows). Registered by
  `Buildings._build()` (not `register()`) as `garage_7`, counted as indoors for snow work; its cells
  `S_BLOCKED` in the snow sim (no snowfall, a wall for every operation); throws already stop at it.
- **No door from the house:** the house's right wall (x 2.75) had no opening. The house floor is at
  0.54 m, the garage's at the ground.
- **Single sources:** `Game.truck_start()` (40, 0, 96.6), nose to the street; `Game.shovel_spot()`;
  the driveway box `lot7_driveway` already ends at the garage's line (Z 100.5), so it wasn't
  extended; the keys flag `flags.truck_keys`. The photo and the menu's home shot build from them.
- **Polish 7:** the blade's solid box (`blade_cs`) stops at layer-1 colliders; the old solid face at
  Z 100.5 was the stop line its tests measure. `send_truck_home()` in `_do_sleep()` sends the first
  pickup to `truck_start()`; `_clear_place()` searched the lot and driveway (the solid garage kept it
  out).
- **`store` (F):** bound and capped since round 5 §2, read nowhere. A $90 "Garage Tool Rack" upgrade
  already exists (8 tools, outside the front wall, `Game.rack`); left as it is (answer 4).
- **The heated pad:** `put_down_pad` refused indoors and `pad_spot_problem` any building or blocked
  cell; `Heating.sources()` always listed a placed pad.
- **Vehicles:** pickup_plow 6.0 × 2.4 × 1.9 m (blade 2.4 m, 2.76 m upgraded): in the bay with
  0.28–1.10 m to spare, through the 5.1 m door with 2.3+ m; the ATV 2.6 × 1.5 × 1.2; tractors 2.6 m
  tall (the door is 2.22 m); the grader, plow truck, rotary and dump truck 7.5–8.5 m long. It fits:
  no resize.

### §14: warmth before this round

Rates are warmth-% per game hour; felt = per real minute at 1× (× 0.8: a real minute is 48 game
minutes), as round 5 §9's audit set them.

- **Outdoors** (`outdoor_loss_per_hour`): `exposure(wind chill)` on `exposure_curve` (−2 °C 1, −8 °C 3,
  −17 °C 9.5, −25 °C 14, −40 °C 20.5, −55 °C 26 per game h = 0.8 / 2.4 / 7.6 / 11.2 / 16.4 / 20.8 per
  real min), × `moderate_cold_mult` 1.15 / `heavy_cold_mult` 1.4 / `blizzard_cold_mult` 3.2 by the
  hour's condition, × the coat (`Equipment.cold_mult()` = 1 − `coat_cold_protection` 0.4 = 0.6 when
  worn), × 0.6 while a pouch lasts. No day/night difference.
- **Indoors:** Gerry's house + `warmth_recover_per_hour` 140 (112 per real min); the player's house
  `house_heat × 140 × house_warm` (× 1.4 near the fire with power) − (1 − house_heat) ×
  exposure(air) × 0.65 × coat. `house_heat` fills in an hour with power; after a cut it drains over
  a day.
- **Pouches:** +`pouch_warmth` 30 at once; for `pouch_protection_minutes` 60 (75 real s) loss × 0.6
  and +`pouch_warmth_per_hour` 10.
- **States and warnings:** Comfortable ≥ 70, Cooling ≥ 45, Cold ≥ 25, Dangerously cold ≥ 10,
  Critical; each step down from Cold on: a notification, fast-forward to 1×; while skipping, warmth
  under 30 interrupts. 0 % = frozen: the death screen for 6 s, then the main menu (unsaved progress
  lost).
- **Vehicles:** a vehicle whose data has `heated_cabin` (every one but the ATV) warmed the player as
  fast as indoors once its heat had ramped up (`vehicle_heat_warmup_s` 20 s): `heat × 140 −
  (1 − heat) × outdoor × 0.5`. There was no engine switch: the engine always ran. The ATV:
  outdoors. Walk-behind blowers: on foot, outdoors. The ATV's heated-cab upgrade
  (`ItemUpgrades.has_heated_cab`) is read by no warmth code.
- **The opening** (Survival, from New Game, at the benches' human pace; `contract_bench --job=opening`):
  measured with the bot
  (`contract_bench.gd`; the walks round the walkway's banks and the truck by its own route-finder).
  Seed 2024, real seconds:

  | leg | real s |
  |---|---|
  | bedroom → front door (indoors, estimated from the distance) | 4.4 |
  | front door → the mailbox | 11.3 |
  | the letter, read (15 characters a second) | 26.7 |
  | the mailbox → the buried shovel | 18.1 |
  | the shovel dug out by hand (52 strokes × 1.1 s) | 57.2 |
  | → Gerry (9.6 s walked; the last 29.5 m through the deep yard estimated at the game's wading pace: the bot can't thread the banks) | 48.1 |
  | Gerry's dialogue, read | 29.1 |
  | → the foot of his walk | 8.3 |
  | his trail with the small shovel (142 strokes) | 158.1 |
  | his thanks and the walk in to his fire | 14.0 |
  | **outdoors** | **370.9 (6.2 real min = 4.9 game h; done at 12:30 on Dec 1)** |

  Only the trail differs by seed (138–142 strokes). Warmth at the end, outside throughout (new
  game, no coat, by day: the night multiplier doesn't reach it):

  | seed | outdoors (real s) | Dec 1 wind chill on the way | warmth before (round 7) | after |
  |---|---|---|---|---|
  | 2024 | 370.9 | −5.6 … −9.9 °C | 85.0 % | 12.7 % |
  | 7 | 368.6 | −4.3 … −7.6 °C | 88.8 % | 21.3 % |
  | 99 | 366.4 | −5.8 … −9.6 °C | 85.4 % | 14.1 % |
  | 4242 | 366.4 | −0.8 … −4.4 °C | 93.9 % | 32.9 % |
  | 2050 | 366.4 | −1.5 … −5.4 °C | 92.9 % | 30.7 % |

  Mean after: 22.3 % (target `opening_target_warmth` 20). One multiplier couldn't put every seed near
  the target (×5.4: 2024 and 99 at ~20 %, 4242 and 2050 at 62–67 %, no warning); the owner chose a
  base loss (Questions, §14). Tuned: `player_base_loss_per_hour` 5 %/game h, `player_cold_mult` 2.2.
- **Time to danger:** real minutes at 1× from 100 % to the first cold warning (45 %) / to
  freezing, on foot outdoors, clear weather, no coat (`test_s14_time_to_danger`):

  | wind chill | day before | day after | night before | night after |
  |---|---|---|---|---|
  | −2 °C | 68.8 / 125.0 | 5.2 / 9.5 | 68.8 / 125.0 | 3.5 / 6.3 |
  | −8 °C | 22.9 / 41.7 | 3.9 / 7.1 | 22.9 / 41.7 | 2.6 / 4.7 |
  | −17 °C | 7.2 / 13.2 | 2.2 / 3.9 | 7.2 / 13.2 | 1.4 / 2.6 |
  | −25 °C | 4.9 / 8.9 | 1.6 / 3.0 | 4.9 / 8.9 | 1.1 / 2.0 |
  | −40 °C | 3.4 / 6.1 | 1.2 / 2.2 | 3.4 / 6.1 | 0.8 / 1.5 |

  The coat (× 0.6) stretches every "after" figure by 1.67. A typical path job (1 real minute of
  work, a minute's walk each way) is still done on Dec 6 with warm-up breaks indoors
  (`test_s14_path_job_survival`).
- **New felt rates:** the colder player's own loss 5 × 2.2 = 11 %/game h (8.8 %/real min) on top of
  the weather's × 2.2; at night × 1.5; a running cab +`cab_warmth_per_hour` 50 (40 %/real min;
  indoors 112); shelter: the air's exposure × the coat × 2.2, no wind, night or own loss.

## Questions

Asked before starting (one message, 2026-11-13). Answers recorded below each once given.

1. **New keys.** Hint keys: Left = Back, Right = Next (OK on the last page), X = OK, in a new "hint"
   context that conflicts like a global one (live on foot, in vehicles and at machines; waits at the
   computer and in menus), shown as its own "Hint panel" group. §14's engine switch: a new vehicle
   action `veh_engine` "Engine on / off" on I. Left, Right, X and I are bound to nothing today and no
   test sends them; Enter is out (it submits the computer's name field).
2. **The hint over the map, TV, letter and photo.** The brief makes a hint wait under the computer,
   the sleep prompt and dialogs. In play the cursor is free only while one of those screens is open,
   so the click path exists only if the hint stays up over the map, TV, letter and photo. Stay up
   there (drawn above, clickable), or hide under every screen?
3. **Teaching notifications.** The blower's first grab ("run, chute, let go", once) becomes a hint.
   Snowshoes collected, pad collected and the plow fitted report an event each time and stay
   notifications. OK?
4. **The rack.** A $90 "Garage Tool Rack" upgrade already exists (`tool_rack`: 8 tools, outside the
   front wall beside the garage, save key `rack`). Keep it as it is and give the new 6-slot garage
   rack its own optional save key (two racks; the overlap noted for the items round)? Or one rack?
5. **The colder player and the opening.** A new game starts Dec 1 at 7:30 a.m.; sunset is 4:36 p.m.
   At the benches' pace the shovel and Gerry's trail end around midday, in daylight. So the night
   multiplier won't touch the opening, and the colder-player multiplier does it alone (likely ×4–×12,
   depending on the seed). At ×7, a −25 °C wind chill gives the first warning after about 40 s outside
   (today about 5 real min), and a blizzard about 15 s. A player clearing the trail by hand (no shovel,
   allowed by GAME.md) would freeze before finishing. No save exists before the first sleep, so
   freezing in the opening loses the new game. Go ahead as the brief says (tune on the shovel opening,
   by day, report the per-seed table and time-to-danger), with by-hand players having to warm up
   partway?
6. **Enclosed cab field.** `VehicleData.heated_cabin` already exists with exactly the brief's split
   (true for every vehicle but the ATV); it drives cab warmth and the store's "heated cab / no cab".
   Add the new `enclosed_cab` field anyway, as the brief says, or reuse `heated_cabin`?
7. **Sounds.** `tools/audio/gen_audio.py` needs numpy and scipy, which this PC's Python 3.11 lacks.
   Install them (`py -m pip install numpy scipy`), or let me run that, or skip the new sounds?
8. **Perf.** On this PC 21 of 42 `perf.tscn` scenarios were already over 16.7 ms p95 in round 6
   (stress 28.6 ms). Judge by back-to-back runs against `main` (no regression, absolutes reported),
   plus one windowed run of the §7 scenarios for the real GPU particle cost?
9. **Conflict check at the walk-behind.** `rebind()` knows only foot / vehicle / global, so it
   accepts e.g. Move forward → Z, which then also turns the chute at a blower (round 5 left this on
   purpose). Make the check follow every place the actions are read (it refuses a few more rebinds,
   never fewer; no default or saved binding changes)?

Defaults taken unless the owner objects: see the questions message (hint layout and behaviour,
garage layout and gates, shelter rules, dusk, the cold-night hint, F1 windy button, outline fog).

**Owner's answer: "All your picks".** So:
1. Left / Right / X in a new "hint" context ("Hint panel" group); `veh_engine` on I.
2. The hint stays up (above, clickable) over the map, TV, letter and photo; it waits under the
   computer, sleep, Gerry's dialogue, pause, F1 and the summary.
3. The blower's first grab becomes a hint; snowshoes, pad and plow stay notifications.
4. Two racks: the `tool_rack` upgrade untouched; the garage rack has its own optional save key.
5. Tune on the shovel opening by day, as the brief says; report the per-seed and time-to-danger
   tables; by hand the player has to warm up partway.
6. Reuse `heated_cabin` as the enclosed cab (no new field).
7. numpy / scipy: the owner installs them or tells me to; checked again at §7.
8. Perf: back-to-back against `main`, plus one windowed run of the §7 scenarios.
9. The conflict check follows every place an action is read.
And every listed default.

Asked during §14 (2026-11-16):

10. **One multiplier can't hit the opening's target on every seed.** Dec 1's weather differs a lot
    by seed (wind chill −1 to −10 °C) and the exposure curve is nearly flat when mild, so ×5.4 ends
    seeds 2024 / 99 near 20 % but 4242 / 2050 at 62–67 % (no cold warning). Add a base loss (a second
    value: a flat loss outdoors whatever the weather, so every seed ends in the band), or one
    multiplier only, tuned to the coldest seeds?

**Owner's answer: "Add a base loss".** `player_base_loss_per_hour` (5 %/game h) added to the
exposure before the coat, the pouch, `player_cold_mult` (2.2) and the night multiply it; outdoors
only (shelter and indoors don't read it).

## Check at the end

- §17: `Settings.shares()` is now the one sharing rule `rebind()` uses (same three contexts plus
  "hint"); `Game.serialize()` gains `hints_seen` (every state-equality test compares it). The full
  suite reruns every test that loops over the actions or compares saves.
- §15: shared code changed — `HouseBuilder.build` (the player's garage is hollow; the menu builds it
  too), `hollow_colliders` (the player's house wall split for the door), every vehicle's collision
  mask (`VEHICLE_ONLY_LAYER`, and `GARAGE_GATE_LAYER` for the big ones), `exit_vehicle` (inside the
  garage only), `send_truck_home` / `_clear_place`, `_vehicle_snow_step`, `Game.serialize()` (the
  `garage` key), `Equipment.pad_spot_problem` / `put_down_pad`, `Heating.sources`, the
  `snow_hide_c` shader global (a new project setting: the owner's editor may need a restart). The
  full suite and the perf run (`--only=garage` back to back with `main`) cover them.

- §14: shared code changed — `Survival.outdoor_loss_per_hour` (an own loss and × `player_cold_mult`,
  × `night_cold_mult` at night: a Survival player outdoors cools 3–10× faster), `compute_rate` (the
  cab, the garage), `on_advance` (the cold-night check each step), `Weather.forecast_low` (new, reads
  the forecast model), `DayNight.sunset_hour` (new, static, `sun_angles`' formula), `Vehicle`
  (engine switch: throttle, blade and blower refused when off; the cab's heat), a new action
  `veh_engine`. Could affect any test or fixture run that keeps a Survival player outdoors for long,
  and the key-list tests. The full suite covers them; `weather_truth` must stay identical (§14 only
  reads the weather).

## Issues

- §17: with hints off, the vehicle and tool tips show nowhere in play until the Help app unlocks at
  the end of the tutorial (Gerry's tips are spoken instead).
- §15: a walk-behind blower being pushed has its collider off (round 5), so it passes through the
  garage's steps, walls and closed door like everywhere else. Not changed.
- §15: with the truck and the ATV both inside there's little floor left for the blowers and the pad
  (no resize, as the brief says).
- §15: the "Garage Tool Rack" upgrade ($90, 8 tools, outside the front wall) still exists beside the
  new garage rack (the owner's answer 4: for the items round).
- §15 shots: three now (outside by day, outside at night with the door open, inside); the brief's
  fourth, the door open in a snowfall from inside, is taken with §7 (until then flakes fall inside
  the garage). Four shots for the section (CLAUDE.md says two) because the brief lists four.
- §15: the keys' pickup message (`buried_keys.gd`) still names only the truck, not the garage door
  (GAME.md says the keys unlock both). The brief keeps the buried keys unchanged.
- §14: GAME.md step 7 says Gerry's job takes "roughly until 5 p.m. with the shovel"; at the benches'
  human pace the opening is done by about 12:30 (6 real minutes outdoors). Not changed: the brief
  tunes warmth, not the job's length.
- §14: GAME.md says a frozen player can reload that day; before the first sleep there is no save, so
  freezing in the opening loses the new game (answer 5: a by-hand player warms up partway).
- §14: the ATV's "cab" upgrade can still be bought and does nothing for warmth
  (`ItemUpgrades.has_heated_cab` stays unwired, Decision 4).
- §14: the opening bench's walk from the shovel to Gerry is partly estimated (the last 29.5 m at
  the game's wading pace): the bot can't thread the yard's sharp banks there.
