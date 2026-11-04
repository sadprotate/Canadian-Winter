class_name ComputerScreen
extends SubViewport
## Polish 4 §2: what the player's monitor shows — a small desktop in the look of the game's own
## computer UI (its palette, an icon for each app on it, a snowy wallpaper, a taskbar with the game
## time), or a lock screen until Gerry has set the computer up (derived from computer_unlocked).
##
## Rendered into this SubViewport only when something on it changes — the lock state, or the game
## minute shown by the clock — and only while the player is in the house (UPDATE_ONCE; it is
## otherwise disabled and the last picture stays on the monitor). Never every frame. Using the
## computer still opens the full computer UI as before.

const SIZE := Vector2i(540, 320)

var showing := ""             # "lock" | "desktop"
var renders := 0              # how many times it has been asked to render (tests)
var _minute := -1
var _desktop: Control
var _lock: Control
var _clock: Label
var _lock_time: Label
var _lock_date: Label


## A screen for `monitor` (a QuadMesh facing the room): the monitor shows this viewport.
static func make(parent: Node, monitor: MeshInstance3D) -> ComputerScreen:
	var s := ComputerScreen.new()
	parent.add_child(s)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = s.get_texture()
	m.albedo_color = Color(0.93, 0.95, 1.0)
	# Mirrored lots have a mirrored house transform: flip the picture back so text reads.
	if monitor.global_transform.basis.determinant() < 0.0:
		m.uv1_scale = Vector3(-1, 1, 1)
		m.uv1_offset = Vector3(1, 0, 0)
	monitor.material_override = m
	return s


func _init() -> void:
	size = SIZE
	transparent_bg = false
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED


func _ready() -> void:
	var root := Control.new()
	root.theme = UIKit.theme()
	root.size = Vector2(SIZE)
	add_child(root)
	root.add_child(_wallpaper(false))
	_desktop = _build_desktop()
	root.add_child(_desktop)
	_lock = _build_lock()
	root.add_child(_lock)
	_refresh(true)


func _process(_delta: float) -> void:
	_refresh(false)


## Re-render when the lock state or the shown minute changes, while the player is in the house.
func _refresh(force: bool) -> void:
	var pl: Node = Game.player
	var inside: bool = force or (pl != null and is_instance_valid(pl) and bool(pl.get("in_player_house")))
	if not inside:
		return
	var want := "desktop" if Game.computer_unlocked() else "lock"
	var minute := int(Clock.minutes)
	if want == showing and minute == _minute and not force:
		return
	showing = want
	_minute = minute
	_desktop.visible = want == "desktop"
	_lock.visible = want == "lock"
	var hhmm := Clock.time_string()
	_clock.text = hhmm
	_lock_time.text = hhmm
	_lock_date.text = "%s, %s" % [Clock.weekday(Clock.day_index(), Game.year), Clock.date_string(Clock.day_index())]
	render_target_update_mode = SubViewport.UPDATE_ONCE
	renders += 1


# -----------------------------------------------------------------------------
# The pictures
# -----------------------------------------------------------------------------

## A dusk sky over snowy hills and spruces, drawn procedurally.
func _wallpaper(dim: bool) -> Control:
	var w := Wallpaper.new()
	w.dim = dim
	w.size = Vector2(SIZE)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return w


func _build_desktop() -> Control:
	var d := Control.new()
	d.size = Vector2(SIZE)
	# Desktop shortcuts, one per app of the computer UI in its order (polish 5 §7), in two columns.
	for i in range(ComputerUI.APPS.size()):
		@warning_ignore("integer_division")
		var col := i / 5
		var row := i % 5
		var ic := AppIcon.new()
		ic.app = i
		ic.position = Vector2(14 + col * 94, 10 + row * 52)
		ic.size = Vector2(90, 50)
		d.add_child(ic)
	# Taskbar: start button, the apps pinned, the clock.
	var bar := ColorRect.new()
	bar.color = Color(UIKit.BG.r, UIKit.BG.g, UIKit.BG.b, 0.94)
	bar.position = Vector2(0, SIZE.y - 30)
	bar.size = Vector2(SIZE.x, 30)
	d.add_child(bar)
	var start := ColorRect.new()
	start.color = UIKit.ACCENT
	start.position = Vector2(8, SIZE.y - 25)
	start.size = Vector2(20, 20)
	d.add_child(start)
	var pinned := ["weather", "contracts", "board", "store"]
	for k in range(pinned.size()):
		var pin := AppIcon.new()
		pin.app = ComputerUI.app_index(pinned[k])
		pin.small = true
		pin.position = Vector2(40 + k * 28, SIZE.y - 28)
		pin.size = Vector2(26, 26)
		d.add_child(pin)
	_clock = UIKit.label("12:00", 15, UIKit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_clock.position = Vector2(SIZE.x - 108, SIZE.y - 27)
	_clock.size = Vector2(100, 24)
	d.add_child(_clock)
	return d


func _build_lock() -> Control:
	var l := Control.new()
	l.size = Vector2(SIZE)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.09, 0.55)
	shade.size = Vector2(SIZE)
	l.add_child(shade)
	_lock_time = UIKit.label("12:00", 64, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_lock_time.position = Vector2(0, 58)
	_lock_time.size = Vector2(SIZE.x, 80)
	l.add_child(_lock_time)
	_lock_date = UIKit.label("", 18, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_lock_date.position = Vector2(0, 138)
	_lock_date.size = Vector2(SIZE.x, 26)
	l.add_child(_lock_date)
	var pad := Padlock.new()
	pad.position = Vector2(SIZE.x * 0.5 - 16, 186)
	pad.size = Vector2(32, 38)
	l.add_child(pad)
	var hint := UIKit.label("Locked", 16, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	hint.position = Vector2(0, 230)
	hint.size = Vector2(SIZE.x, 24)
	l.add_child(hint)
	return l


class Wallpaper extends Control:
	var dim := false

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Sky: deep blue to a warm dusk glow at the horizon.
		var bands := 24
		for i in range(bands):
			var t := float(i) / (bands - 1)
			var c := Color(0.1, 0.14, 0.32).lerp(Color(0.93, 0.6, 0.42), pow(t, 1.6))
			draw_rect(Rect2(0, h * 0.7 * i / bands, w, h * 0.7 / bands + 1), c)
		# Far hills, near hills (snow), a few spruces.
		var far := PackedVector2Array([Vector2(0, h * 0.62)])
		for k in range(13):
			far.append(Vector2(w * k / 12.0, h * (0.6 + 0.05 * sin(k * 1.7))))
		far.append_array([Vector2(w, h), Vector2(0, h)])
		draw_colored_polygon(far, Color(0.62, 0.66, 0.82))
		var near := PackedVector2Array([Vector2(0, h * 0.76)])
		for k in range(13):
			near.append(Vector2(w * k / 12.0, h * (0.74 + 0.04 * sin(k * 1.1 + 2.0))))
		near.append_array([Vector2(w, h), Vector2(0, h)])
		draw_colored_polygon(near, Color(0.9, 0.92, 0.98))
		for k in range(7):
			var x := w * (0.55 + 0.06 * k + 0.02 * sin(k * 3.1))
			var base := h * (0.74 + 0.04 * sin((x / w * 12.0) * 1.1 + 2.0)) + 4.0
			var th := h * (0.12 + 0.04 * fmod(k * 0.37, 1.0))
			draw_colored_polygon(PackedVector2Array([Vector2(x - th * 0.28, base), Vector2(x + th * 0.28, base), Vector2(x, base - th)]), Color(0.12, 0.24, 0.2))
		# Moon.
		draw_circle(Vector2(w * 0.8, h * 0.16), h * 0.05, Color(1.0, 0.97, 0.88))
		if dim:
			draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.35))


class AppIcon extends Control:
	var app := 0
	var small := false

	func _draw() -> void:
		var s := minf(size.y, 26.0) if small else 30.0
		var o := Vector2((size.x - s) * 0.5, 2.0)
		draw_rect(Rect2(o, Vector2(s, s)), Color(0.18, 0.22, 0.33, 0.95))
		draw_rect(Rect2(o, Vector2(s, s)), UIKit.ACCENT.darkened(0.1), false, 1.0)
		var c := o + Vector2(s, s) * 0.5
		var u := s / 30.0
		var col := Color(0.95, 0.95, 0.97)
		match ComputerUI.APP_IDS[app]:
			"board":  # contract board: a clipboard
				draw_rect(Rect2(c + Vector2(-8, -10) * u, Vector2(16, 20) * u), col)
				draw_rect(Rect2(c + Vector2(-4, -12) * u, Vector2(8, 4) * u), UIKit.ACCENT)
				for k in range(3):
					draw_line(c + Vector2(-5, -4 + 5 * k) * u, c + Vector2(5, -4 + 5 * k) * u, Color(0.3, 0.3, 0.35), 1.5 * u)
			"contracts":  # contracts: ticks
				for k in range(3):
					var y := (-7 + 7 * k) * u
					draw_polyline(PackedVector2Array([c + Vector2(-9 * u, y), c + Vector2(-6 * u, y + 3 * u), c + Vector2(-1 * u, y - 3 * u)]), UIKit.GOOD, 2.0 * u)
					draw_line(c + Vector2(2 * u, y), c + Vector2(9 * u, y), col, 2.0 * u)
			"store":  # equipment store: a shovel
				draw_line(c + Vector2(-7, -9) * u, c + Vector2(4, 4) * u, Color(0.75, 0.55, 0.3), 2.5 * u)
				draw_colored_polygon(PackedVector2Array([c + Vector2(2, 2) * u, c + Vector2(10, 4) * u, c + Vector2(8, 11) * u, c + Vector2(0, 9) * u]), UIKit.ACCENT)
			"upgrades":  # upgrades: an up arrow
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10) * u, c + Vector2(9, 0) * u, c + Vector2(-9, 0) * u]), UIKit.GOOD)
				draw_rect(Rect2(c + Vector2(-4, 0) * u, Vector2(8, 10) * u), UIKit.GOOD)
			"bills":  # bills: a dollar sign
				draw_string(ThemeDB.fallback_font, c + Vector2(-6, 8) * u, "$", HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * u), UIKit.WARN)
			"property":  # property: a house
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10) * u, c + Vector2(10, -1) * u, c + Vector2(-10, -1) * u]), UIKit.ACCENT)
				draw_rect(Rect2(c + Vector2(-7, -1) * u, Vector2(14, 10) * u), col)
			"weather":  # weather: a snow cloud
				draw_circle(c + Vector2(-4, -2) * u, 6 * u, col)
				draw_circle(c + Vector2(4, -3) * u, 7 * u, col)
				draw_rect(Rect2(c + Vector2(-10, -2) * u, Vector2(20, 6) * u), col)
				for k in range(3):
					draw_circle(c + Vector2(-6 + 6 * k, 8) * u, 1.5 * u, Color(0.7, 0.85, 1.0))
			"orders":  # orders: a parcel
				draw_rect(Rect2(c + Vector2(-9, -7) * u, Vector2(18, 15) * u), Color(0.78, 0.6, 0.4))
				draw_line(c + Vector2(0, -7) * u, c + Vector2(0, 8) * u, Color(0.5, 0.36, 0.22), 2.0 * u)
			"help":  # help: a question mark
				draw_string(ThemeDB.fallback_font, c + Vector2(-5, 8) * u, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * u), Color(0.6, 0.8, 1.0))
		if not small:
			var app_name: String = ComputerUI.APPS[app]
			var fs := label_size(app_name, size.x)
			# A dark shadow under the name keeps it readable over the snowy hills (polish 5 §7).
			draw_string(ThemeDB.fallback_font, Vector2(1, s + 16), app_name, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(0.03, 0.05, 0.12, 0.85))
			draw_string(ThemeDB.fallback_font, Vector2(0, s + 15), app_name, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(1, 1, 1, 0.95))

	## Polish 5 §7: the name's font size, 10 px or smaller so it fits under the icon.
	static func label_size(app_name: String, width: float) -> int:
		var fs := 10
		while fs > 7 and ThemeDB.fallback_font.get_string_size(app_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			fs -= 1
		return fs


class Padlock extends Control:
	func _draw() -> void:
		var w := size.x
		draw_arc(Vector2(w * 0.5, 14), 9.0, PI, TAU, 16, Color(0.85, 0.87, 0.92), 3.5)
		draw_rect(Rect2(Vector2(2, 14), Vector2(w - 4, 22)), Color(0.85, 0.87, 0.92))
		draw_circle(Vector2(w * 0.5, 24), 3.0, Color(0.15, 0.17, 0.25))
