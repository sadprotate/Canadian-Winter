# Controls

## What it does for the player

- Every key and mouse button the game reads is an action the player can rebind in Settings →
  Controls. The actions are grouped "On foot", "General", "Vehicles & machines" and "Hint panel". A key already used
  where the new action works is refused, with the name of the action that holds it.
- Every key the game shows (hints, prompts, the Help app's Controls table, messages) is the one
  bound now.
- World-changing presses are capped per second, so autoclickers and key spam don't do more than
  steady tapping.

## How it works

- **`Settings.ACTIONS`** (`scripts/autoload/settings.gd`): `action → [label, context, default
  events]`.
  - Contexts are `"foot"`, `"vehicle"`, `"global"` and `"hint"` (round 8 §17: the hint panel's
    keys, live on foot, in vehicles and at machines, so they conflict like a global action;
    `shares()` is the one rule `rebind()`, `holder()` and the migration use).
  - Defaults are encoded as `"key:<physical keycode>"` or `"mouse:<button>"`.
  - The order of `ACTIONS` is the order in the settings menu and the Help app.
- **Places** (`PLACES`: foot, vehicle, machine, computer, menu): `live_actions(place)` lists what works
  there.
  - A vehicle gets the vehicle and global actions.
  - A walk-behind machine gets `MACHINE_ACTIONS` plus the global ones.
  - The computer and the menu get Pause (and fast-forward at the computer).
- **Conflicts:**
  - `rebind(action, event)` refuses a code held by another action in the same context or a global
    one, and returns the holder.
  - `conflicts(place)` checks the defaults of every place; the tests run it.
  - A foot action and a vehicle action may share a key: H is the pouch on foot and the horn in a
    vehicle.
- **The press cap:**
  - `accept_press(action)` accepts at most `input_max_presses_per_s` presses of one action per sliding
    second, counted in physics frames, and at most one per physics frame.
  - Extra presses are ignored, never queued. Callers ask once, on the press edge.
  - The capped actions are listed in `RATE_LIMITED`: primary, secondary, interact, drop, store,
    use_pouch, tool_angle, veh_tool, fast_forward, veh_blade_up, veh_blade_down, hint_back,
    hint_next, hint_ok.
  - Movement, the camera, the map, Tab, slots, horn, radio, F1 and UI clicks aren't capped.
- **Saved bindings and migration** (`controls_from`, `load_controls`), with `CONTROLS_VERSION` 2:
  - A stored binding is kept. From version 2, `[]` means unbound.
  - A missing action gets its default, unless a stored binding in a shared context already holds that
    key; then it starts unbound.
  - `OLD_DEFAULTS[n]` moves bindings still at an old default when a default changes. That needs a
    version bump. A new action doesn't.
- **Labels:** `action_label(action)` gives the first binding's name ("Up", "Left Mouse").
  `with_keys(text)` replaces `{action}` in a text. No player-facing string names a key itself:
  `test_s2_keys_shown_from_input_map` scans every script and data string for hard-coded key names.
- **Typing:** anything that reads keys checks `Game.typing()`, which is true while a LineEdit or
  TextEdit has the focus.
- **The blade keys** (`veh_blade_up` "Raise the blade", Up; `veh_blade_down` "Lower the blade", Down;
  vehicle context, capped) are read in `Vehicle._input`, before the GUI.
  - The arrows are also Godot's `ui_up` / `ui_down`. A focused control would otherwise take them as
    a focus move, so the vehicle marks the press handled.
  - They work only on a vehicle with a blade the player drives. See [vehicles.md](vehicles.md).
- **HUD buttons** that stay on screen (the fast-forward buttons) take no keyboard focus
  (`FOCUS_NONE`).

## Where it lives

- `scripts/autoload/settings.gd`: `ACTIONS`, `RATE_LIMITED`, `accept_press`, `rebind`,
  `restore_default_controls`, `conflicts`, `live_actions`, `action_label`, `with_keys`,
  `controls_from`, `load_controls`, `apply_input`.
- `scripts/ui/settings_menu.gd`: the Controls tab (groups, rebinding, the conflict message, Restore
  defaults).
- `scripts/ui/computer_ui.gd`: the Help app's Controls table (every action, in order).
- `scripts/ui/hint_panel.gd`: the hint keys (`hint_back` Left, `hint_next` Right, `hint_ok` X),
  read in `_input` only while a hint shows. See [hints.md](hints.md).
- Readers: `player.gd`, `tool_controller.gd`, `vehicle.gd`, `walk_behind.gd`, `game_root.gd`,
  `speed_control.gd`.

## Connects to

- `Catalog.balance.input_max_presses_per_s`.
- The settings file `Settings.PATH` (`[controls]`, `[meta] controls_version`).

## How to test

- `--only=polish5 --test=test_s2_`: defaults, the migration, no conflict in any place, the cap, the
  keys shown from the input map.
- `--only=polish5 --test=test_s7_typing_fires_no_game_action`: every bound key into a focused text
  field fires nothing.
- `--only=gameplay --test=settings_rebinding`.
- `--only=polish7 --test=test_s11_`:
  - the blade actions;
  - Up/Down on every blade vehicle;
  - rebinding;
  - a press with a HUD control focused;
  - the first-drive hint's pages.
- `--only=polish8 --test=test_s17_buttons`: the hint keys, rebound, and clicks.

## Decisions

- Round 5 §2: drop moved to G, store on F, the pouch on H; the press cap; the version-2 migration.
- Round 8 §15: `store` (F) hangs the tool in your hands on the garage rack, read in
  `game_root._unhandled_input` only on foot inside the garage (elsewhere F does nothing). See
  [garage.md](garage.md).
- Round 5 §9: fast-forward is capped and works at the computer.
- Round 7 §11: `veh_blade_up` / `veh_blade_down` on Up / Down, capped, read before the GUI. Existing
  players get them through the migration, with no version bump.
- Round 8 §17: `hint_back` / `hint_next` / `hint_ok` on Left / Right / X in the new "hint" context
  ("Hint panel" group in Settings), capped. No version bump.

## Known issues

- `rebind()` knows only the foot, vehicle and global contexts, not the machine place (round 5 §2).
