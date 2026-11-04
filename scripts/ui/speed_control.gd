class_name SpeedControl
extends Control
## Polish 5 §9: fast-forward beside the HUD clock — 1×, 2× and 10×, the speed the clock runs at
## highlighted (the one chosen outlined when a cap or a hold keeps the clock slower), clickable
## whenever the cursor is free (at the computer, the map, the TV …), with the cycle key beside them.
## A line under them says why the clock runs slower than chosen (the frame budget's cap, a scripted
## mover nearby) and, for a few seconds, why it went back to 1× on its own. It lives on a layer
## above the modals (game_root.time_layer), so it hides itself under the fade, dialogs and menus.

const NOTE_S := 4.0
## Why fast-forward went back to 1× on its own (Clock.drop_to_1x reasons), as shown.
const DROP_TEXT := {"alert": "weather alert", "contract": "contract warning", "bid": "bid result",
	"cold": "you're getting cold", "work": "working the snow", "vehicle": "vehicle", "machine": "machine"}
const HOLD_TEXT := {"grader": "grader passing", "gerry": "Gerry walking"}

var world: Node
var hud: HUD
var panel: PanelContainer
var buttons: Array = []
var key_l: Label
var note_l: Label
var _note := ""
var _note_t := 0.0
var _look := ""                 # what the buttons show now (restyled only when it changes)
var _st_on: StyleBoxFlat
var _st_chosen: StyleBoxFlat
var _st_off: StyleBoxFlat


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.6), 12, 0, Color.TRANSPARENT, 10))
	panel.name = "SpeedPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var v := UIKit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var row := UIKit.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	for s in Clock.SPEEDS:
		var sp: int = s
		var b := Button.new()
		b.name = "Speed%d" % sp
		b.text = "%d×" % sp
		b.focus_mode = Control.FOCUS_NONE      # never takes the keyboard (Space, Enter)
		b.custom_minimum_size = Vector2(56, 32)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func(): _choose(sp))
		row.add_child(b)
		buttons.append(b)
	key_l = UIKit.shadow_label("", 16, UIKit.MUTED)
	key_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(key_l)
	note_l = UIKit.label("", 14, UIKit.WARN)
	v.add_child(note_l)
	_st_on = UIKit.sb(UIKit.ACCENT.darkened(0.1), 9, 2, UIKit.ACCENT, 10)
	_st_chosen = UIKit.sb(Color(0.18, 0.22, 0.33, 0.95), 9, 2, UIKit.ACCENT, 10)
	_st_off = UIKit.sb(Color(0.18, 0.22, 0.33, 0.85), 9, 1, Color(1, 1, 1, 0.08), 10)
	for st in [_st_on, _st_chosen, _st_off]:
		st.content_margin_top = 3
		st.content_margin_bottom = 3
	Clock.speed_changed.connect(_on_speed_changed)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _choose(sp: int) -> void:
	AudioMgr.ui("ui_click")
	if not Clock.set_speed(sp):
		refused()


## The key or a click was refused (fast-forward isn't available here).
func refused() -> void:
	_note = "Fast-forward: on foot, indoors or at the computer"
	_note_t = 3.0
	AudioMgr.ui("ui_error")


func _on_speed_changed(sp: int, reason: String) -> void:
	if sp == 1 and DROP_TEXT.has(reason):
		_note = "Back to 1× · %s" % DROP_TEXT[reason]
		_note_t = NOTE_S
	elif reason == "":
		_note_t = 0.0


## Shown with the HUD while the game runs; hidden under the fade (sleep), dialogs and menus.
func shown() -> bool:
	if world == null or hud == null or not is_instance_valid(hud) or not hud.visible:
		return false
	if not Clock.running or get_tree().paused or bool(world.get("_dead")):
		return false
	var fd: ColorRect = world.get("fade")
	if fd != null and fd.color.a > 0.05:
		return false
	return bool(world.call("ff_modal_ok"))


func _update(delta: float) -> void:
	visible = shown()
	if not visible:
		return
	# Top-aligned beside the clock, as short as its content: it stays clear of the computer's window
	# (which starts 90 px down the 1080-px canvas) even with the note line showing.
	var cp: Control = hud.clock_panel
	if cp != null:
		panel.position = Vector2(cp.position.x + cp.size.x + 10.0, cp.position.y)
	var ok := Clock.unavailable_reason() == ""
	var eff := Clock.effective_speed() if ok else 1
	var chosen := Clock.speed
	var free := not Game.input_captured()     # the cursor is free (a modal is open)
	var look := "%d %d %s %s" % [eff, chosen, ok, free]
	if look != _look:
		_look = look
		for i in range(buttons.size()):
			var b: Button = buttons[i]
			var sp: int = Clock.SPEEDS[i]
			b.disabled = not ok and sp > 1
			b.mouse_filter = Control.MOUSE_FILTER_STOP if free else Control.MOUSE_FILTER_IGNORE
			var style := _st_on if sp == eff else (_st_chosen if sp == chosen else _st_off)
			for st in ["normal", "hover", "pressed", "disabled"]:
				b.add_theme_stylebox_override(st, style)
			b.add_theme_color_override("font_color", Color.WHITE if sp == eff else UIKit.TEXT)
			b.add_theme_color_override("font_disabled_color", Color(0.5, 0.52, 0.58))
	key_l.text = "[%s]" % Settings.action_label("fast_forward")
	_note_t -= delta
	var line := ""
	if ok and chosen > 1:
		var hold := Clock.hold_reason()
		if hold != "":
			line = "Held at 1× · %s" % HOLD_TEXT.get(hold, hold)
		elif Clock.speed_cap() < chosen:
			line = "Max %d× · %s" % [Clock.speed_cap(), Clock.cap_reason()]
	if line == "" and _note_t > 0.0:
		line = _note
	note_l.text = line
	if note_l.visible != (line != ""):
		note_l.visible = line != ""
		panel.reset_size()
