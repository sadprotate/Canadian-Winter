class_name UIKit
extends RefCounted
## UI helpers and the shared theme (readable, minimal, matching the cozy winter art style).

const BG := Color(0.07, 0.09, 0.15, 0.88)
const BG_LIGHT := Color(0.13, 0.16, 0.25, 0.92)
const ACCENT := Color(0.98, 0.55, 0.18)
const TEXT := Color(0.95, 0.95, 0.97)
const MUTED := Color(0.7, 0.74, 0.82)
const GOOD := Color(0.45, 0.9, 0.55)
const WARN := Color(1.0, 0.78, 0.3)
const BAD := Color(1.0, 0.4, 0.35)

static var _theme: Theme


static func sb(color: Color, radius := 10, border := 0, border_color := Color.TRANSPARENT, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	t.set_stylebox("panel", "PanelContainer", sb(BG, 14, 1, Color(1, 1, 1, 0.08), 18))
	t.set_stylebox("panel", "Panel", sb(BG, 14, 1, Color(1, 1, 1, 0.08), 18))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.57, 0.62))
	t.set_stylebox("normal", "Button", sb(Color(0.18, 0.22, 0.33, 0.95), 9, 1, Color(1, 1, 1, 0.08), 16))
	t.set_stylebox("hover", "Button", sb(Color(0.26, 0.31, 0.46, 1.0), 9, 2, ACCENT, 16))
	t.set_stylebox("pressed", "Button", sb(ACCENT.darkened(0.15), 9, 2, ACCENT, 16))
	t.set_stylebox("disabled", "Button", sb(Color(0.14, 0.15, 0.2, 0.8), 9, 0, Color.TRANSPARENT, 16))
	t.set_stylebox("focus", "Button", sb(Color(0, 0, 0, 0), 9, 2, ACCENT.lightened(0.2), 16))
	t.set_stylebox("normal", "LineEdit", sb(Color(0.05, 0.06, 0.1, 0.95), 8, 1, Color(1, 1, 1, 0.15), 10))
	t.set_stylebox("panel", "TooltipPanel", sb(Color(0.05, 0.06, 0.1, 0.95), 6, 1, ACCENT, 8))
	t.set_stylebox("background", "ProgressBar", sb(Color(0.05, 0.06, 0.1, 0.9), 6, 0, Color.TRANSPARENT, 0))
	t.set_stylebox("fill", "ProgressBar", sb(ACCENT, 6, 0, Color.TRANSPARENT, 0))
	t.set_stylebox("slider", "HSlider", sb(Color(0.05, 0.06, 0.1, 0.9), 4, 0, Color.TRANSPARENT, 4))
	t.set_stylebox("grabber_area", "HSlider", sb(ACCENT.darkened(0.2), 4, 0, Color.TRANSPARENT, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(ACCENT, 4, 0, Color.TRANSPARENT, 4))
	t.set_stylebox("panel", "TabContainer", sb(BG_LIGHT, 10, 0, Color.TRANSPARENT, 14))
	t.set_stylebox("tab_selected", "TabContainer", sb(ACCENT.darkened(0.1), 8, 0, Color.TRANSPARENT, 14))
	t.set_stylebox("tab_unselected", "TabContainer", sb(Color(0.15, 0.18, 0.27, 0.95), 8, 0, Color.TRANSPARENT, 14))
	t.set_stylebox("tab_hovered", "TabContainer", sb(Color(0.25, 0.3, 0.45, 0.95), 8, 0, Color.TRANSPARENT, 14))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_stylebox("normal", "OptionButton", sb(Color(0.18, 0.22, 0.33, 0.95), 9, 1, Color(1, 1, 1, 0.08), 14))
	t.set_stylebox("hover", "OptionButton", sb(Color(0.26, 0.31, 0.46, 1.0), 9, 2, ACCENT, 14))
	t.set_stylebox("panel", "PopupMenu", sb(Color(0.08, 0.1, 0.16, 0.98), 8, 1, ACCENT, 8))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	_theme = t
	return t


static func label(text: String, size := 22, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func shadow_label(text: String, size := 22, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func button(text: String, cb: Callable, size := 22, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(func(): AudioMgr.ui("ui_click"))
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): AudioMgr.ui("ui_hover"))
	return b


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(style: StyleBox = null) -> PanelContainer:
	var p := PanelContainer.new()
	if style:
		p.add_theme_stylebox_override("panel", style)
	return p


static func card() -> PanelContainer:
	return panel(sb(Color(0.15, 0.18, 0.27, 0.95), 10, 1, Color(1, 1, 1, 0.06), 14))


static func spacer(h := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func hspacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func progress(value: float, color := ACCENT, h := 14) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(120, h)
	p.add_theme_stylebox_override("fill", sb(color, 6, 0, Color.TRANSPARENT, 0))
	return p


static func clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


static func center_panel(parent: Control, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.position = -size * 0.5
	parent.add_child(p)
	return p


static func full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


static func money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var n := s.length()
	for i in range(n):
		out += s[i]
		var rem := n - i - 1
		if rem > 0 and rem % 3 == 0:
			out += ","
	return ("-$" if v < 0 else "$") + out
