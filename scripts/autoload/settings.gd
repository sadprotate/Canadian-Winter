extends Node
## Unified persistent settings (Part 21) shared by the main menu and pause menu.
## Also owns the input map: default bindings, rebinding, conflict checks, restore defaults.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

## action -> [label, context, default events]. Context: "foot", "vehicle", "global".
## Events are encoded as "key:<keycode>", "mouse:<button>".
## Polish 5 §2: drop Q -> G, the new store action on F (the garage rack, §15), use_pouch G -> H.
const ACTIONS := {
	"move_forward": ["Move forward", "foot", ["key:%d" % KEY_W]],
	"move_back": ["Move back", "foot", ["key:%d" % KEY_S]],
	"move_left": ["Move left", "foot", ["key:%d" % KEY_A]],
	"move_right": ["Move right", "foot", ["key:%d" % KEY_D]],
	"jump": ["Jump", "foot", ["key:%d" % KEY_SPACE]],
	"sprint": ["Sprint", "foot", ["key:%d" % KEY_SHIFT]],
	"crouch": ["Crouch", "foot", ["key:%d" % KEY_CTRL]],
	"primary": ["Scoop snow (hold) / throw (release)", "foot", ["mouse:%d" % MOUSE_BUTTON_LEFT]],
	"secondary": ["Push snow (hold)", "foot", ["mouse:%d" % MOUSE_BUTTON_RIGHT]],
	"tool_angle": ["Angle scraper blade", "foot", ["key:%d" % KEY_R]],
	"slot_1": ["Tool slot 1", "foot", ["key:%d" % KEY_1]],
	"slot_2": ["Tool slot 2", "foot", ["key:%d" % KEY_2]],
	"slot_3": ["Tool slot 3", "foot", ["key:%d" % KEY_3]],
	"slot_4": ["Tool slot 4", "foot", ["key:%d" % KEY_4]],
	"slot_next": ["Next tool", "foot", ["mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN]],
	"slot_prev": ["Previous tool", "foot", ["mouse:%d" % MOUSE_BUTTON_WHEEL_UP]],
	"drop": ["Drop tool", "foot", ["key:%d" % KEY_G]],
	"store": ["Put on the rack", "foot", ["key:%d" % KEY_F]],
	"use_pouch": ["Use heating pouch", "foot", ["key:%d" % KEY_H]],
	"interact": ["Interact / enter / exit", "global", ["key:%d" % KEY_E]],
	"camera_toggle": ["Switch camera", "global", ["key:%d" % KEY_V]],
	"map": ["Map", "global", ["key:%d" % KEY_M]],
	"inventory": ["Inventory overview", "global", ["key:%d" % KEY_TAB]],
	"fast_forward": ["Fast-forward 1× / 2× / 10×", "foot", ["key:%d" % KEY_T]],
	"pause": ["Pause", "global", ["key:%d" % KEY_ESCAPE]],
	"debug": ["Debug menu", "global", ["key:%d" % KEY_F1]],
	"veh_accelerate": ["Drive forward", "vehicle", ["key:%d" % KEY_W]],
	"veh_reverse": ["Brake / reverse", "vehicle", ["key:%d" % KEY_S]],
	"veh_left": ["Steer left", "vehicle", ["key:%d" % KEY_A]],
	"veh_right": ["Steer right", "vehicle", ["key:%d" % KEY_D]],
	"veh_brake": ["Handbrake", "vehicle", ["key:%d" % KEY_SPACE]],
	"veh_tool": ["Blade / blower on-off", "vehicle", ["mouse:%d" % MOUSE_BUTTON_LEFT]],
	"veh_aim_left": ["Blade angle / chute left", "vehicle", ["key:%d" % KEY_Z]],
	"veh_aim_right": ["Blade angle / chute right", "vehicle", ["key:%d" % KEY_C]],
	"veh_horn": ["Horn", "vehicle", ["key:%d" % KEY_H]],
	"veh_radio": ["Vehicle radio forecast", "vehicle", ["key:%d" % KEY_T]],
}

const DEFAULTS := {
	"audio": {"master": 0.8, "music": 0.6, "ambient": 0.8, "sfx": 0.85},
	"gameplay": {"show_prompts": true, "show_notifications": true, "show_contract_hud": true, "show_landing_indicator": true, "head_bob": true},
	"camera": {"default_third": false, "sensitivity": 0.25, "fov": 75.0, "invert_x": false, "invert_y": false, "tp_distance": 3.6, "tp_shoulder": 0.5},
	"graphics": {"fullscreen": false, "resolution": "1600x900", "vsync": true, "preset": 1, "shadows": 2, "snow_detail": 1, "particles": 1, "draw_distance": 1, "msaa": 1, "fps_overlay": false},
	"debug": {"enabled": true},
}

const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440"]

## Polish 5 §2: version of the default bindings, saved as [meta] controls_version (absent = 1).
## OLD_DEFAULTS[v] holds the actions whose default changed after version v, with that old default:
## on load, a binding still at its old default moves to the new one, unless another action already
## uses that key (a binding the player set wins; the moved action then keeps its old key).
const CONTROLS_VERSION := 2
const OLD_DEFAULTS := {
	1: {"drop": ["key:%d" % KEY_Q], "use_pouch": ["key:%d" % KEY_G]},
}

## Polish 5 §2: where actions are live together, for the conflict check (conflicts()). "foot" and
## "vehicle" are the ACTIONS contexts plus the global ones. A walk-behind machine ("machine") is
## steered on foot with the chute keys (the slot tool is stowed: the foot tool actions, jump,
## sprint, crouch and the wheel do nothing there). At the computer and in menus the player is
## frozen or the game paused: only Pause (close) is read; the rest is UI.
const MACHINE_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "primary",
	"slot_1", "slot_2", "slot_3", "slot_4", "veh_aim_left", "veh_aim_right"]
const PLACES := ["foot", "vehicle", "machine", "computer", "menu"]

## Polish 5 §2: world-changing presses, capped per action at Catalog.balance.input_max_presses_per_s
## (accept_press). UI clicks, F1, movement, the camera, map, Tab, slots, horn and radio aren't.
## Polish 5 §9: the fast-forward key (it changes the clock's speed) is capped too.
const RATE_LIMITED := ["primary", "secondary", "interact", "drop", "store", "use_pouch", "tool_angle", "veh_tool", "fast_forward"]

var cfg := ConfigFile.new()
var bindings: Dictionary = {}   # action -> Array of encoded events
var _presses: Dictionary = {}   # action -> physics frames of the presses accepted in the last second


func _ready() -> void:
	load_controls()
	call_deferred("apply_all")


## (Re)read user://settings.cfg and its bindings, migrating old ones (polish 5 §2); a migrated file
## is written back at once (a fresh install writes nothing until something is changed).
func load_controls() -> void:
	cfg.clear()
	cfg.load(PATH)
	var ver := int(cfg.get_value("meta", "controls_version", 1))
	bindings = controls_from(cfg)
	apply_input()
	if ver < CONTROLS_VERSION and cfg.has_section("controls"):
		save()


## The bindings stored in a settings file, migrated to the current defaults (polish 5 §2): every
## action not stored gets its default; then each action still at an old default moves to its new
## one if no other action it shares a context with holds that key, repeated until nothing moves
## (so use_pouch leaves G before drop takes it, whatever the order). An action stored unbound ([],
## which only the migration below produces) stays unbound.
static func controls_from(c: ConfigFile) -> Dictionary:
	var out := {}
	var ver := int(c.get_value("meta", "controls_version", 1))
	for a in ACTIONS.keys():
		var saved = c.get_value("controls", a) if c.has_section_key("controls", a) else null
		if saved is Array and (not saved.is_empty() or ver >= 2):   # [] = unbound from version 2 on
			out[a] = (saved as Array).duplicate()
		else:
			out[a] = (ACTIONS[a][2] as Array).duplicate()
	if not c.has_section("controls"):
		return out
	for v in range(ver, CONTROLS_VERSION):
		var old: Dictionary = OLD_DEFAULTS.get(v, {})
		var moved := true
		while moved:
			moved = false
			for a in old.keys():
				var want: Array = ACTIONS[a][2]
				if out[a] == old[a] and out[a] != want and holder(out, a, want[0]) == "":
					out[a] = want.duplicate()
					moved = true
	# A new action whose default key a player's binding already holds starts unbound.
	for a in ACTIONS.keys():
		if not c.has_section_key("controls", a):
			var code: String = (ACTIONS[a][2] as Array)[0]
			if holder(out, a, code) != "":
				out[a] = []
	return out


## True when two actions can be live at the same time (the rule rebind() refuses conflicts by).
static func shares(a: String, b: String) -> bool:
	var ca: String = ACTIONS[a][1]
	var cb: String = ACTIONS[b][1]
	return ca == cb or ca == "global" or cb == "global"


## The action other than `action` that shares a context with it and is bound to `code`, or "".
static func holder(binds: Dictionary, action: String, code: String) -> String:
	for other in ACTIONS.keys():
		if other != action and shares(action, other) and code in binds.get(other, []):
			return other
	return ""


## The actions read in a place (PLACES).
static func live_actions(place: String) -> Array:
	var out := []
	for a in ACTIONS.keys():
		var ctx: String = ACTIONS[a][1]
		match place:
			"foot":
				if ctx == "foot" or ctx == "global":
					out.append(a)
			"vehicle":
				if ctx == "vehicle" or ctx == "global":
					out.append(a)
			"machine":
				if a in MACHINE_ACTIONS or ctx == "global":
					out.append(a)
			"computer":
				# Polish 5 §9: fast-forward works at the computer too.
				if a == "pause" or a == "fast_forward":
					out.append(a)
			"menu":
				if a == "pause":
					out.append(a)
	return out


## Pairs of actions live in the same place that share a key or button: [[a, b, label], ...].
func conflicts(place: String) -> Array:
	var out := []
	var live := live_actions(place)
	for i in range(live.size()):
		for j in range(i + 1, live.size()):
			for code in bindings.get(live[i], []):
				if code in bindings.get(live[j], []):
					out.append([live[i], live[j], code_label(code)])
	return out


func get_value(section: String, key: String, fallback = null):
	var def = DEFAULTS.get(section, {}).get(key, fallback)
	return cfg.get_value(section, key, def)


func set_value(section: String, key: String, value) -> void:
	cfg.set_value(section, key, value)
	save()
	changed.emit(section, key)
	_apply_one(section, key)


func save() -> void:
	for a in bindings.keys():
		cfg.set_value("controls", a, bindings[a])
	cfg.set_value("meta", "controls_version", CONTROLS_VERSION)
	cfg.save(PATH)


# -----------------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------------

static func decode(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "key":
		var e := InputEventKey.new()
		e.physical_keycode = int(parts[1])
		return e
	if parts[0] == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(parts[1])
		return m
	return null


static func encode(e: InputEvent) -> String:
	if e is InputEventKey:
		var k: InputEventKey = e
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return "key:%d" % code
	if e is InputEventMouseButton:
		return "mouse:%d" % (e as InputEventMouseButton).button_index
	return ""


static func code_label(code: String) -> String:
	var parts := code.split(":")
	if parts.size() != 2:
		return "?"
	if parts[0] == "key":
		return OS.get_keycode_string(int(parts[1]))
	match int(parts[1]):
		MOUSE_BUTTON_LEFT: return "Left Mouse"
		MOUSE_BUTTON_RIGHT: return "Right Mouse"
		MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
		MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
	return "Mouse %s" % parts[1]


func apply_input() -> void:
	for a in ACTIONS.keys():
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		InputMap.action_erase_events(a)
		for code in bindings[a]:
			var e := decode(code)
			if e:
				InputMap.action_add_event(a, e)


func action_label(action: String) -> String:
	var lst: Array = bindings.get(action, [])
	if lst.is_empty():
		return "—"
	return code_label(lst[0])


## Text with {action} placeholders replaced by the keys bound to those actions (polish 5 §2: every
## key shown is read from the input map), e.g. "Press {use_pouch} to use one".
func with_keys(text: String) -> String:
	if not text.contains("{"):
		return text
	for a in ACTIONS.keys():
		text = text.replace("{%s}" % a, action_label(a))
	return text


## Polish 5 §2: a world-changing press of `action`. False (ignore it, don't queue it) when this
## action already had input_max_presses_per_s presses accepted in the last second, or one in this
## physics frame. Actions outside RATE_LIMITED, and a cap of 0, are never limited. Holding a button
## isn't affected: callers ask once, on the press, and act for as long as it is held.
func accept_press(action: String) -> bool:
	if action not in RATE_LIMITED:
		return true
	var cap := 6.0
	if Catalog.balance and "input_max_presses_per_s" in Catalog.balance:
		cap = float(Catalog.balance.input_max_presses_per_s)
	if cap <= 0.0:
		return true
	var now := Engine.get_physics_frames()
	var window := Engine.physics_ticks_per_second
	var lst: Array = _presses.get(action, [])
	while not lst.is_empty() and now - int(lst[0]) >= window:
		lst.pop_front()
	if lst.size() >= int(cap) or (not lst.is_empty() and int(lst[-1]) == now):
		return false
	lst.append(now)
	_presses[action] = lst
	return true


## Rebind an action. Returns "" or the name of the conflicting action (binding refused).
func rebind(action: String, e: InputEvent) -> String:
	var code := encode(e)
	if code == "":
		return "invalid"
	var ctx: String = ACTIONS[action][1]
	for other in ACTIONS.keys():
		if other == action:
			continue
		var octx: String = ACTIONS[other][1]
		var shares := ctx == octx or ctx == "global" or octx == "global"
		if shares and code in bindings[other]:
			return other
	bindings[action] = [code]
	apply_input()
	save()
	return ""


func restore_default_controls() -> void:
	for a in ACTIONS.keys():
		bindings[a] = (ACTIONS[a][2] as Array).duplicate()
	apply_input()
	save()


# -----------------------------------------------------------------------------
# Apply
# -----------------------------------------------------------------------------

func apply_all() -> void:
	for section in ["audio", "graphics"]:
		for key in DEFAULTS[section].keys():
			if key != "preset":
				_apply_one(section, key)


func _apply_one(section: String, key: String) -> void:
	match section:
		"audio":
			AudioMgr.apply_volumes()
		"graphics":
			match key:
				"fullscreen", "resolution":
					_apply_window()
				"vsync":
					DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("graphics", "vsync") else DisplayServer.VSYNC_DISABLED)
				"msaa":
					get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(get_value("graphics", "msaa")), 0, 2)]
				"preset":
					_apply_preset(int(get_value("graphics", "preset")))


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if get_value("graphics", "fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var res: String = get_value("graphics", "resolution")
		var p := res.split("x")
		if p.size() == 2:
			var size := Vector2i(int(p[0]), int(p[1]))
			var screen := DisplayServer.screen_get_size()
			size = size.min(screen)
			DisplayServer.window_set_size(size)
			@warning_ignore("integer_division")
			DisplayServer.window_set_position((screen - size) / 2)


func _apply_preset(p: int) -> void:
	# Presets only set the individual options; the user can still fine-tune afterwards.
	var vals: Dictionary = [
		{"shadows": 0, "snow_detail": 0, "particles": 0, "draw_distance": 0, "msaa": 0},
		{"shadows": 2, "snow_detail": 1, "particles": 1, "draw_distance": 1, "msaa": 1},
		{"shadows": 3, "snow_detail": 2, "particles": 2, "draw_distance": 2, "msaa": 2},
	][clampi(p, 0, 2)]
	for k in vals.keys():
		cfg.set_value("graphics", k, vals[k])
		changed.emit("graphics", k)
	save()
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(vals["msaa"]), 0, 2)]


func debug_enabled() -> bool:
	return bool(get_value("debug", "enabled", true))
