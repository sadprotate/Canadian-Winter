extends Node
## Unified persistent settings (Part 21) shared by the main menu and pause menu.
## Also owns the input map: default bindings, rebinding, conflict checks, restore defaults.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

## action -> [label, context, default events]. Context: "foot", "vehicle", "global".
## Events are encoded as "key:<keycode>", "mouse:<button>".
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
	"drop": ["Drop tool", "foot", ["key:%d" % KEY_Q]],
	"use_pouch": ["Use heating pouch", "foot", ["key:%d" % KEY_G]],
	"interact": ["Interact / enter / exit", "global", ["key:%d" % KEY_E]],
	"camera_toggle": ["Switch camera", "global", ["key:%d" % KEY_V]],
	"map": ["Map", "global", ["key:%d" % KEY_M]],
	"inventory": ["Inventory overview", "global", ["key:%d" % KEY_TAB]],
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

var cfg := ConfigFile.new()
var bindings: Dictionary = {}   # action -> Array of encoded events


func _ready() -> void:
	cfg.load(PATH)
	for a in ACTIONS.keys():
		var saved = cfg.get_value("controls", a) if cfg.has_section_key("controls", a) else null
		if saved is Array and not saved.is_empty():
			bindings[a] = saved
		else:
			bindings[a] = (ACTIONS[a][2] as Array).duplicate()
	apply_input()
	call_deferred("apply_all")


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
