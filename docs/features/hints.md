# Hints

## What it does for the player

- Tips that teach how to do something open in one small panel on the right of the screen: a title,
  one or more short pages, and **Back** and **Next** (Next reads **OK** on the last page).
- Keys: Left = Back, Right = Next, X = OK (closes from any page). All three can be rebound
  (Settings → Controls → "Hint panel"). With the cursor free (the map, the TV, the letter, the
  photo) the buttons can be clicked.
- It never freezes anything: you keep walking and working, and the clock keeps running. A hint stays
  until OK.
- Settings → Gameplay → "Show hints" (on by default) turns it off. Every hint's content is also in
  the computer's Help app, under "Hints".

## How it works

- **What goes through it:**
  - Gerry's how-to at the job beat (`gerry_snow`): scoop and throw, push, the outlined trail. He
    still says "Now, two ways to move snow." in the speech box; the hint opens beside it. Talking to
    him again during the job says that line again and reopens the hint at page 1. It closes when
    the trail is done. With hints off he says all four lines in the speech box, as in round 5.
  - The first drive of each kind of vehicle (`vehicle_<kind>`): driving; the blade keys (a plow);
    back-drag (a plow); the blower; the bed (the dump truck). Once per kind, as the old first-drive
    panel. It is gated by the flag `help_vehicle_<kind>` as before (tests and shots set it to keep
    the panel off).
  - The first pickup of each kind of tool (`tool_<kind>`): the small shovel's old "You found a
    small snow shovel!" sentence (now only the hint), the one-line controls reminder's wording for
    the others; the walk-behind blower's first grab (it was a notification).
  - The first time in the garage (`garage`): the door's button, the rack (F and E). See
    [garage.md](garage.md).
  - §14 adds the cold hints.
- **What doesn't** (Decision 1): Gerry's story lines and the player's thoughts (speech box), the
  interaction prompts, status lines ("Stuck: …", "Blade down"), notifications (snowshoes and the pad
  collected, the plow fitted), the one-line controls reminder on a tool switch and in Tab.
- **The content** (`HelpText`): `GERRY_SNOW`, `vehicle_hint()`, `tool_hint()`, `hint(id, data)`,
  `hint_help()` (the Help app). Every key is an `{action}` placeholder filled by
  `Settings.with_keys()` when it shows, so a rebind shows at once.
- **The panel** (`scripts/ui/hint_panel.gd`, no `class_name`, preloaded by `game_root`): on
  `game_root.time_layer` (above the modals), anchored top-right, 376 px wide, from y 150 — clear of
  the weather panel, the notifications, the speech box (it ends at x 1520), the crosshair, the
  prompts, the status line and the hotbar at every canvas (1920×1080 for 16:9, 2580×1080 for
  3440×1440).
  - `show_hint(id, again, data)` queues it (false when hints are off or, unless `again`, it was
    seen); `drop(id)`; `back()`, `next()`, `ok()`; `is_open(id)`.
  - One at a time: the queue opens the next when the current one is closed.
  - It waits (hidden, still current or queued) while the game is paused, asleep, dead or faded,
    and under any modal other than the map, the TV, the letter and the photo (so: the computer,
    the sleep prompt, Gerry's dialogue, pause, F1, the summary).
  - Keys are read in `_input` (before the GUI: the arrows are also `ui_left` / `ui_right`), only
    while a hint shows, never while typing (`Game.typing()`), each press through
    `Settings.accept_press()`.
  - The buttons are `FOCUS_NONE` and take clicks only while the cursor is free.
- **Seen hints** (`Game.hints_seen`, save key `game.hints_seen`, version 3, optional): marked when a
  hint opens (not when queued). An older save derives them (`Game.hints_from`): past Gerry's job
  his hint; the opening done or the shovel found, the shovel's; each `help_vehicle_<kind>` flag;
  `help_blower`; every kind of tool in a slot, carried or on the rack. A tool still lying in the
  world shows its hint when picked up.

## Where it lives

- `scripts/ui/hint_panel.gd`, `scripts/ui/help_text.gd` (content), `scripts/game/game_root.gd`
  (`show_hint`, `show_vehicle_help`, `_snow_tips`, the TRAIL_DONE drop).
- Triggers: `vehicle.gd` (first drive), `tool_item.gd` (first pickup), `walk_behind.gd` (first
  grab).
- `scripts/autoload/game_state.gd` (`hints_seen`, `hint_seen`, `mark_hint_seen`, `hints_from`).
- `scripts/autoload/settings.gd` (`hint_back` / `hint_next` / `hint_ok`, the "hint" context,
  `gameplay/show_hints`), `scripts/ui/settings_menu.gd` (the toggle, the "Hint panel" group),
  `scripts/ui/computer_ui.gd` (Help's "Hints" section).

## Connects to

- [controls.md](controls.md) (the keys and their context), `Saves` (the optional key), the HUD's
  speech box (Gerry), `game_root.open_modal` (what it waits under).

## How to test

- `--only=polish8 --test=test_s17_`: the buttons (default keys, rebound, clicks), never frozen,
  the queue (two together, the computer, the sleep prompt, beside the speech box), once each (save
  → load, old fixtures), hints off (Help), Gerry, the vehicle and tool hints, the fit.
- `--only=polish5 --test=test_s4_gerry_snow_tips`, `--only=polish7 --test=test_s11_help_lists_the_keys`,
  `--only=polish5 --test=test_s7_v3_save_round_trips`.

## Decisions

- Round 8 §17: the teaching tips move into one panel (the owner's request). Keys Left / Right / X in
  a "hint" context that conflicts like a global one. It stays up over the map, TV, letter and photo
  (the click path); Gerry's hint closes with the trail; with hints off Gerry speaks his tips; the
  blower's first grab is a hint, the snowshoes / pad / plow messages stay notifications; old saves
  count owned tools as seen. (Owner's answers, STATUS.md.)

## Known issues

- With hints off the vehicle and tool tips show nowhere in play until the Help app unlocks (end of
  the tutorial).
