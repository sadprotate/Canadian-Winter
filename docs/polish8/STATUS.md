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
- [ ] §15 — The garage
- [ ] §14 — Cold nights, and a colder player
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

## Check at the end

## Issues
