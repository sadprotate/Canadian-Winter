class_name SettingsMenu
extends Control
## Unified settings screen used by both the main menu and the pause menu (Part 21).

signal closed

var tabs: TabContainer
var _waiting_action := ""
var _waiting_button: Button
var _msg: Label


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	UIKit.full_rect(dim)
	add_child(dim)
	var p := UIKit.center_panel(self, Vector2(1180, 820))
	var v := UIKit.vbox(12)
	p.add_child(v)
	var head := UIKit.hbox()
	v.add_child(head)
	head.add_child(UIKit.label("SETTINGS", 40, Color.WHITE))
	head.add_child(UIKit.hspacer())
	head.add_child(UIKit.button("Back", _close, 22, 140))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	_msg = UIKit.label("", 18, UIKit.WARN)
	v.add_child(_msg)
	_audio_tab()
	_gameplay_tab()
	_camera_tab()
	_graphics_tab()
	_controls_tab()


func _close() -> void:
	_waiting_action = ""
	closed.emit()
	queue_free()


func _page(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := UIKit.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := UIKit.hbox(16)
	var l := UIKit.label(text, 22)
	l.custom_minimum_size.x = 420
	h.add_child(l)
	parent.add_child(h)
	return h


func _slider(parent: Control, text: String, section: String, key: String, mn: float, mx: float, step: float, fmt := "%d%%", mult := 100.0) -> void:
	var h := _row(parent, text)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.custom_minimum_size = Vector2(380, 28)
	s.value = float(Settings.get_value(section, key))
	h.add_child(s)
	var val := UIKit.label(fmt % (s.value * mult), 20, UIKit.MUTED)
	h.add_child(val)
	s.value_changed.connect(func(x):
		val.text = fmt % (x * mult)
		Settings.set_value(section, key, x))


func _check(parent: Control, text: String, section: String, key: String) -> void:
	var h := _row(parent, text)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(section, key))
	h.add_child(c)
	c.toggled.connect(func(on): Settings.set_value(section, key, on))


func _option(parent: Control, text: String, section: String, key: String, items: Array, values: Array = []) -> OptionButton:
	var h := _row(parent, text)
	var o := OptionButton.new()
	o.custom_minimum_size.x = 300
	for it in items:
		o.add_item(str(it))
	var cur = Settings.get_value(section, key)
	var vals := values if not values.is_empty() else range(items.size())
	o.selected = maxi(0, vals.find(cur))
	h.add_child(o)
	o.item_selected.connect(func(i): Settings.set_value(section, key, vals[i]))
	return o


func _audio_tab() -> void:
	var v := _page("Audio")
	_slider(v, "Master volume", "audio", "master", 0.0, 1.0, 0.01)
	_slider(v, "Music volume", "audio", "music", 0.0, 1.0, 0.01)
	_slider(v, "Ambience volume", "audio", "ambient", 0.0, 1.0, 0.01)
	_slider(v, "Sound effects volume", "audio", "sfx", 0.0, 1.0, 0.01)


func _gameplay_tab() -> void:
	var v := _page("Gameplay")
	_check(v, "Show interaction prompts", "gameplay", "show_prompts")
	_check(v, "Show notifications", "gameplay", "show_notifications")
	_check(v, "Show contract progress near zones", "gameplay", "show_contract_hud")
	_check(v, "Show throw landing indicator", "gameplay", "show_landing_indicator")
	_check(v, "Head bob (first person)", "gameplay", "head_bob")
	_check(v, "Show hints", "gameplay", "show_hints")   # polish 8 §17: the hint panel


func _camera_tab() -> void:
	var v := _page("Camera")
	_check(v, "Start in third person", "camera", "default_third")
	_slider(v, "Mouse sensitivity", "camera", "sensitivity", 0.05, 1.0, 0.01, "%.2f", 1.0)
	_slider(v, "Field of view", "camera", "fov", 55.0, 100.0, 1.0, "%d°", 1.0)
	_check(v, "Invert X axis", "camera", "invert_x")
	_check(v, "Invert Y axis", "camera", "invert_y")
	_slider(v, "Third-person distance", "camera", "tp_distance", 2.0, 7.0, 0.1, "%.1f m", 1.0)
	_slider(v, "Third-person shoulder offset", "camera", "tp_shoulder", -1.0, 1.0, 0.05, "%.2f", 1.0)


func _graphics_tab() -> void:
	var v := _page("Graphics")
	_option(v, "Resolution (windowed)", "graphics", "resolution", Settings.RESOLUTIONS, Settings.RESOLUTIONS)
	_check(v, "Fullscreen", "graphics", "fullscreen")
	_check(v, "VSync", "graphics", "vsync")
	var preset := _option(v, "Quality preset", "graphics", "preset", ["Low", "Medium", "High"])
	preset.item_selected.connect(func(_i): _msg.text = "Preset applied. Individual options below were updated.")
	_option(v, "Shadows", "graphics", "shadows", ["Off", "Low", "Medium", "High"])
	_option(v, "Snow mesh detail", "graphics", "snow_detail", ["Low", "Medium", "High"])
	_option(v, "Particle density", "graphics", "particles", ["Low", "Medium", "High"])
	_option(v, "Draw distance", "graphics", "draw_distance", ["Near", "Medium", "Far"])
	_option(v, "Anti-aliasing (MSAA)", "graphics", "msaa", ["Off", "2x", "4x"])
	_check(v, "Performance overlay (FPS)", "graphics", "fps_overlay")
	v.add_child(UIKit.label("Defaults target low-tier PCs (GTX 1050 / Iris Xe). Changes apply immediately.", 18, UIKit.MUTED))


func _controls_tab() -> void:
	var v := _page("Controls")
	var top := UIKit.hbox()
	v.add_child(top)
	top.add_child(UIKit.label("Click a binding, then press a key or mouse button. Conflicts are refused.", 18, UIKit.MUTED))
	top.add_child(UIKit.hspacer())
	top.add_child(UIKit.button("Restore defaults", func():
		Settings.restore_default_controls()
		_refresh_controls(v), 18))
	_refresh_controls(v)


func _refresh_controls(v: VBoxContainer) -> void:
	for i in range(v.get_child_count() - 1, 0, -1):
		v.get_child(i).queue_free()
	var groups := {"foot": "On foot", "global": "General", "vehicle": "Vehicles & machines", "hint": "Hint panel"}
	for g in ["foot", "global", "vehicle", "hint"]:
		v.add_child(UIKit.label(groups[g], 24, UIKit.ACCENT))
		for a in Settings.ACTIONS.keys():
			if Settings.ACTIONS[a][1] != g:
				continue
			var h := _row(v, Settings.ACTIONS[a][0])
			var b := Button.new()
			b.text = Settings.action_label(a)
			b.custom_minimum_size.x = 260
			h.add_child(b)
			var act: String = a
			b.pressed.connect(func():
				_waiting_action = act
				_waiting_button = b
				b.text = "Press a key…")


func _input(event: InputEvent) -> void:
	if _waiting_action == "":
		return
	var ok := false
	if event is InputEventKey and event.pressed and not event.echo:
		ok = true
	elif event is InputEventMouseButton and event.pressed:
		ok = true
	if not ok:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE and _waiting_action != "pause":
		_waiting_button.text = Settings.action_label(_waiting_action)
		_waiting_action = ""
		return
	var conflict := Settings.rebind(_waiting_action, event)
	if conflict != "":
		_msg.text = "That input is already used by \"%s\". Choose another or rebind that first." % Settings.ACTIONS[conflict][0]
		AudioMgr.ui("ui_error")
	else:
		_msg.text = ""
	_waiting_button.text = Settings.action_label(_waiting_action)
	_waiting_action = ""
