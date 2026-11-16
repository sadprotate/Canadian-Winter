# Controls

## What it does for the player

- Every key and mouse button the game reads is an action the player can rebind in Settings →
  Controls (the few exceptions are listed below). The actions are grouped "On foot", "General",
  "Vehicles & machines" and "Hint panel". A key that would do two things anywhere the new action is
  read is refused, with the name of the action that holds it.
- Restore defaults gives the current defaults.
- Every key the game shows (hints, prompts, the Help app's Controls table, messages) is the one
  bound now.
- World-changing presses are capped per second, so autoclickers and key spam don't do more than
  steady tapping.

## How it works

- **`Settings.ACTIONS`** (`scripts/autoload/settings.gd`): `action → [label, context, default
  events]`.
  - Contexts are `"foot"`, `"vehicle"`, `"global"` and `"hint"` (round 8 §17: the hint panel's
    keys, live on foot, in vehicles and at machines). The context is the menu's group.
  - Defaults are encoded as `"key:<physical keycode>"` or `"mouse:<button>"`.
  - The order of `ACTIONS` is the order in the settings menu and the Help app.
- **Places** (`PLACES`: foot, vehicle, machine, computer, menu): `live_actions(place)` lists every
  action read there.
  - On foot: the foot, global and hint actions.
  - A vehicle: the vehicle, global and hint actions, and the slot keys (`SLOT_ACTIONS`: game_root
    reads them in a vehicle too).
  - A walk-behind machine: `MACHINE_ACTIONS` (movement, primary, the slots, the chute keys), the
    global and hint actions, and fast-forward.
  - The computer: Pause, fast-forward and F1 (`debug`). A menu: Pause.
- **Conflicts** (round 8 §12): `shares(a, b)` is true when some place reads both; it is the one rule
  `rebind()`, `holder()` and the migration use.
  - `rebind(action, event)` refuses a code held by an action it shares with, and returns the holder.
    So Move forward can't take the chute's Z (both read at a walk-behind), nor the horn a slot key
    (both read in a vehicle).
  - `conflicts(place)` lists the pairs on one key in a place; the tests run it on every place.
  - A foot action and a vehicle action that are never read together may share a key: H is the pouch
    on foot and the horn in a vehicle.
- **The press cap:**
  - `accept_press(action)` accepts at most `input_max_presses_per_s` presses of one action per sliding
    second, counted in physics frames, and at most one per physics frame.
  - Extra presses are ignored, never queued. Callers ask once, on the press edge.
  - The capped actions are listed in `RATE_LIMITED`: primary, secondary, interact, drop, store,
    use_pouch, tool_angle, veh_tool, fast_forward, veh_blade_up, veh_blade_down, hint_back,
    hint_next, hint_ok, veh_engine.
  - Movement, the camera, the map, Tab, slots, horn, radio, F1 and UI clicks aren't capped.
- **Saved bindings and migration** (`controls_from`, `load_controls`), with `CONTROLS_VERSION` 2:
  - A stored binding is kept. From version 2, `[]` means unbound.
  - A missing action gets its default, unless a stored binding it shares with already holds that
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
- **The snowshoes toggle** (hold Inventory, press Interact) reads those two actions
  (`game_root`: `inventory` held opens the overview, `interact` while it's open toggles them), so it
  follows their bindings. No action of its own.
- **F1** is the `debug` action: rebindable and conflict-checked like any other (it opens only when
  `Settings.debug_enabled()`).

## Exceptions

Reads that aren't a rebindable action (Decision 6), each on purpose:

- **Godot's `ui_*` built-ins** — menu and form navigation, not game actions: a focused button takes
  `ui_accept` (Enter, Space) and focus moves (`ui_focus_next` Tab, the arrows); a LineEdit submits on
  Enter; the computer leaves a focused field on `ui_cancel` (Esc) as well as Pause
  (`computer_ui.gd` `_input`); a focused slider steps on `ui_left` / `ui_right`. The game's own keys
  that are also `ui_*` keys (the blade keys, the hint keys) are read in `_input` and marked handled
  first.
- **The settings menu's Esc** (`KEY_ESCAPE`, `settings_menu.gd` `_input`): cancels a waiting rebind
  (so Esc can be given only to Pause there).
- **The computer's left-button poll** (`Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)`,
  `computer_ui.gd` `_process`): holds the apps' live refresh while you click or drag (Godot's GUI
  clicks are always the left button).
- **The mouse look** (`InputEventMouseMotion`, `player.gd`): not a key; sensitivity and invert are in
  Settings → Camera.
- **The F1 developer menu's fields** (`debug_menu.gd`): Godot's own text and number fields.

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
  `hint_panel.gd`, `map_ui.gd`, `computer_ui.gd`, `settings_menu.gd` (the capture).

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
- `--only=polish8 --test=test_s12_`: every action name read is an action (or an exception) and is
  in the menu under its group; no hard-coded key outside Settings and the exceptions; every action
  rebound from the menu works with its new key; Restore defaults; no conflict in any place and the
  place-based refusals; the migration; the snowshoes toggle with rebound keys; the menu fits and
  scrolls.

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
- Round 8 §14: `veh_engine` "Engine on / off" on I (vehicle context, capped), read in
  `Vehicle._unhandled_input`. No version bump.
- Round 8 §12: the conflict check follows every place an action is read (the owner's answer 9): it
  refuses a few more rebinds, never fewer; no default or saved binding changes. The snowshoes toggle
  keeps reading Inventory + Interact (no new action). The exceptions are listed above.

## Known issues

- The hotbar's slot labels are fixed "1"–"4", not the bound slot keys.
- Gerry's scripted dialogue (the job offer) is answered with the mouse or Godot's `ui_accept` on its
  focused button, not with Interact.
- While a binding waits, the mouse wheel or a click is taken as the new binding (refused when it
  clashes).
