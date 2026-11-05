extends Node3D
## Main menu (Part 20; polish 3 §1): the game title and PLAY / SETTINGS / EXIT over a live view of
## the neighbourhood — a slow camera gliding along the snowy streets in three crossfaded shots,
## light snow falling, a neighbour shovelling his driveway and Gerry on his porch, lamps and
## windows lit at dusk. PLAY -> Fun / Survival -> New Game / Continue (unchanged).
##
## Isolation: the background is a static snapshot. The snow is filled once (no relaxation, no
## snowfall accumulation, no box measurement: Snow.auto_process is off while the menu runs), the
## clock does not run, nothing is registered in Game, no notification is queued and nothing is
## saved. What the menu sets on the autoloads (Snow.auto_process, the weather override) is put back
## when it starts a game and when it leaves the tree; New Game and Continue then reset or load
## everything else as they always did (Game.new_game / Saves.load_game).

const SHOT_FADE := 1.4        # seconds of crossfade between shots
const CAM_SPEED := 0.85       # metres per second along a shot

var day_night: DayNight
var cam: Camera3D
var ui: CanvasLayer
var root_ui: Control
var main_box: VBoxContainer
var play_panel: Control
var loading: Control
var fade: ColorRect            # behind the menu UI: dark while the background builds, then crossfades
var figure: CharacterModel
var gerry: CharacterModel
var _shovel: MeshInstance3D
var _weather_fx: WeatherFX
var _sr: SnowRenderer
var _refs: Dictionary = {}
var _lights: Array = []
var _light_t := 0.0
var _t := 0.0
var _built := false
var _shots: Array = []         # [{pos: Curve3D, look: Curve3D, len: float}]
var _shot := 0
var _shot_d := 0.0
var _fade_a := 1.0
var _saved_auto := true
var _holding := false
var _paused := false
var _starting := false         # a start under way (polish 6 §3: one at a time)
var _snow_fx: SnowFX
## Tests: called instead of quitting / changing scene.
var quit_hook: Callable
var start_hook: Callable
var seed_override := -1        # tests: a fixed weather seed for New Game


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Clock.running = false
	_build_ui()
	AudioMgr.set_menu_music(true)
	# The UI shows at once; the neighbourhood builds behind a short fade.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_background()


func _exit_tree() -> void:
	_release_autoloads()


## The background holds the snow still and keeps a light snowfall showing.
func _hold_autoloads() -> void:
	if not _holding:
		_saved_auto = Snow.auto_process
	_holding = true
	Snow.auto_process = false
	Weather.override_cond = Weather.C.LIGHT
	Weather.override_rate = 0.6
	Weather.override_until = 1e12


## Put back what the menu set on the autoloads (before starting a game, and on leaving the tree).
func _release_autoloads() -> void:
	if not _holding:
		return
	_holding = false
	Snow.auto_process = _saved_auto
	Weather.override_cond = -1
	Weather.override_rate = -1.0
	Weather.override_until = -1.0


## Stop (or restart) everything the background runs per frame.
func _pause_background(on: bool) -> void:
	_paused = on
	for n in [_sr, _weather_fx, _snow_fx]:
		if n != null and is_instance_valid(n):
			(n as Node).process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT


func _build_background() -> void:
	Layout.ensure()
	Snow.reset_for_winter(2)
	Snow.add_snowfall(0.08)
	Weather.generate(1, 7)
	_hold_autoloads()
	Clock.reset(Clock.at(1, 17.5))
	day_night = DayNight.new()
	day_night.override_hour = 17.5    # blue hour: windows lit, lamps on, the sky still holding colour
	day_night.override_weather = Weather.C.CLOUDY   # dusk sky shows through; gentle snow still falls
	add_child(day_night)
	var wb := WorldBuilder.new()
	_refs = wb.build(self)
	_sr = SnowRenderer.new()
	add_child(_sr)
	_weather_fx = WeatherFX.new()
	add_child(_weather_fx)
	_snow_fx = SnowFX.new()
	add_child(_snow_fx)
	_stage_home()
	_stage_gerry()
	_light_pool()
	_build_shots()
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 500.0
	add_child(cam)
	cam.current = true
	_place_camera(0.0)
	_sr.build_all(cam.global_position)
	_apply_graphics()
	if not Settings.changed.is_connected(_on_setting):
		Settings.changed.connect(_on_setting)
	_built = true


## The player's house: the truck in a dug-out driveway, a neighbour shovelling beside it.
func _stage_home() -> void:
	var lot := Layout.player_lot
	for dl in [Layout.player_lot, Layout.neighbor_lot]:
		# The two enterable houses get their real doors in game; here they are just props.
		var L := HouseBuilder.lot_transform(dl)
		var dsb: float = dl["setback"]
		var dc := L * Vector3(-1.5, Layout.PORCH_H, dsb)
		var dfw := (L * Vector3(-1.5, 0, dsb - 1.0)) - (L * Vector3(-1.5, 0, dsb))
		Door.make(self, Transform3D(Basis(Vector3.UP, atan2(dfw.x, dfw.z) + PI), dc), dl["door_color"], "front door")
	var hi := Layout.house_info(lot)
	var sb: float = lot["setback"]
	var truck_p := Layout.lot_to_world(lot, Layout.gu(lot, 6.0), sb - 4.4)
	var face := Layout.lot_to_world(lot, Layout.gu(lot, 6.0), sb) - truck_p
	var vd: VehicleData = Catalog.vehicle(&"pickup")
	var info := VehicleModels.build(vd)
	var truck := Node3D.new()
	add_child(truck)
	truck.global_position = Vector3(truck_p.x, 0, truck_p.y)
	truck.rotation.y = atan2(face.x, face.y)   # backed in: nose to the street
	var tm := MeshInstance3D.new()
	tm.mesh = info["mesh"]
	truck.add_child(tm)
	for w in info["wheels"]:
		var wm := MeshInstance3D.new()
		wm.mesh = w["mesh"]
		wm.position = w["pos"]
		truck.add_child(wm)
	var sk := MeshKit.new()
	for s in info["snow"]:
		sk.pillow(Mats.snow_soft(), s[0], s[1].x, s[1].y, 0.3, 0.1, 8, 2.6)
	var smi := MeshInstance3D.new()
	smi.mesh = sk.commit()
	truck.add_child(smi)
	# A cleared driveway (bare pavement between fresh banks): filled once, then frozen.
	var drv: Rect2 = hi["driveway"]
	var vol := Snow.volume_in_rect(drv.grow_individual(-0.6, 0, -0.6, 0))
	Snow.set_rect(drv.grow_individual(-0.6, 0, -0.6, 0), 0.0)
	var side := Rect2(drv.position.x - 2.2, drv.position.y, 2.0, drv.size.y)
	Snow.add_layer_rect(side, vol / (side.size.x * side.size.y) * 0.5)
	var side2 := Rect2(drv.end.x + 0.2, drv.position.y, 2.0, drv.size.y)
	Snow.add_layer_rect(side2, vol / (side2.size.x * side2.size.y) * 0.5)
	Snow.relax_until_stable()
	figure = CharacterModel.new()
	add_child(figure)
	figure.build()
	var fp := Layout.lot_to_world(lot, Layout.gu(lot, 4.6), 3.0)
	figure.global_position = Vector3(fp.x, 0, fp.y)
	figure.rotation.y = truck.rotation.y + 0.9
	var shovel := MeshInstance3D.new()
	shovel.mesh = ToolModels.mesh_for("small_shovel")
	figure.hand_r.add_child(shovel)
	_shovel = shovel
	figure.set_pose("dig")


## Gerry on his porch across the street, now and then waving.
func _stage_gerry() -> void:
	gerry = CharacterModel.new()
	gerry.jacket_color = Color(0.62, 0.14, 0.12)
	gerry.toque_color = Color(0.2, 0.32, 0.25)
	gerry.pants_color = Color(0.25, 0.27, 0.35)
	gerry.scarf_color = Color(0.85, 0.82, 0.7)
	gerry.skin = Color(0.9, 0.74, 0.62)
	add_child(gerry)
	gerry.build()
	var hi := Layout.house_info(Layout.neighbor_lot)
	var pc: Vector2 = hi["porch_center"]
	gerry.global_position = Vector3(pc.x, Layout.PORCH_H, pc.y)
	var f: Vector2 = hi["facing"]
	gerry.rotation.y = atan2(-f.x, -f.y)
	gerry.set_pose("idle")


## A few real lights for the street lamps nearest the camera (as in the game).
func _light_pool() -> void:
	for i in range(3):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.5)
		l.light_energy = 1.6
		l.omni_range = 12.0
		add_child(l)
		_lights.append(l)


func _update_lights() -> void:
	var pts: Array = _refs.get("streetlights", [])
	if pts.is_empty() or cam == null:
		return
	var cp := cam.global_position
	var sorted := pts.duplicate()
	sorted.sort_custom(func(a, b): return (a as Vector3).distance_squared_to(cp) < (b as Vector3).distance_squared_to(cp))
	for i in range(_lights.size()):
		var l: OmniLight3D = _lights[i]
		l.visible = i < sorted.size()
		if l.visible:
			l.global_position = sorted[i]


## Three slow shots, crossfaded in a loop. Each is a gentle path down the middle of a street at
## 2.4–3.2 m (above the banks, below the lamp heads and the boulevard trees' branches, which start
## at 3.6 m), never closer than a few metres to a house, a tree or the map edge.
func _build_shots() -> void:
	var maple_z := _street_z(Layout.STREET_MAPLE)
	var birch_z := _street_z(Layout.STREET_BIRCH)
	var gp: Vector2 = Layout.house_info(Layout.neighbor_lot)["porch_center"]
	# 1. West down Maple Street past the houses on both sides, ending on Gerry on his porch (from
	#    a spot where no boulevard tree stands between the camera and him).
	var end_x := gp.x + _clear_view_offset(gp, maple_z + 1.0)
	_add_shot([Vector3(150, 3.0, maple_z + 0.6), Vector3(120, 3.2, maple_z + 0.2), Vector3(90, 3.0, maple_z - 0.3), Vector3(end_x, 2.8, maple_z + 1.0)],
		[Vector3(138, 2.0, maple_z + 9.0), Vector3(108, 2.0, maple_z + 4.0), Vector3(78, 1.9, maple_z - 5.0), Vector3(gp.x, 1.6, gp.y)])
	# 2. Across the street from home, easing sideways past the yard: the truck in the dug-out
	#    driveway and the neighbour shovelling beside it (the old static menu view, now moving).
	var lot := Layout.player_lot
	var sb: float = lot["setback"]
	var hp := []
	var hl := []
	for k in range(3):
		var u: float = -8.0 + 8.0 * k
		var c := Layout.lot_to_world(lot, Layout.gu(lot, u), -9.0)
		var l := Layout.lot_to_world(lot, Layout.gu(lot, u * 0.4 + 1.5), sb * 0.55)
		hp.append(Vector3(c.x, 2.4 + 0.25 * k, c.y))
		hl.append(Vector3(l.x, 1.5, l.y))
	_add_shot(hp, hl)
	# 3. East along Birch Avenue.
	_add_shot([Vector3(24, 3.0, birch_z), Vector3(56, 2.9, birch_z + 0.4), Vector3(90, 3.1, birch_z - 0.2), Vector3(122, 3.0, birch_z + 0.3)],
		[Vector3(38, 1.9, birch_z - 8.0), Vector3(70, 1.9, birch_z + 6.0), Vector3(104, 2.0, birch_z - 6.0), Vector3(136, 2.0, birch_z + 5.0)])


## An x offset from `target` for a camera at depth `z` whose line of sight to it misses every tree.
func _clear_view_offset(target: Vector2, z: float) -> float:
	var trees: Array = []
	for n in ["BareTrees", "Evergreens"]:
		var mmi := find_child(n, true, false) as MultiMeshInstance3D
		if mmi and mmi.multimesh:
			for i in range(mmi.multimesh.instance_count):
				var o := mmi.multimesh.get_instance_transform(i).origin
				trees.append(Vector2(o.x, o.z))
	# The mailboxes at the foot of each walk (polish 4) must not stand in the way either.
	for lot in Layout.lots:
		if not lot.get("vacant", false):
			trees.append(Layout.house_info(lot)["mailbox"])
	for o in [7.0, 5.5, 8.5, 4.0, 10.0, 3.0, 11.5]:
		var cam_p := Vector2(target.x + o, z)
		var clear := true
		for t in trees:
			# Keep trunks well off the line of sight (and further off it near the camera, where
			# they would fill the frame).
			var need := 2.2 if t.distance_to(cam_p) < 12.0 else 1.4
			if Geometry2D.get_closest_point_to_segment(t, cam_p, target).distance_to(t) < need:
				clear = false
				break
		if clear:
			return o
	return 7.0


static func _street_z(street: String) -> float:
	for r in Layout.roads:
		if r["name"] == street:
			return (r["rect"] as Rect2).get_center().y
	return 0.0


func _add_shot(pos: Array, look: Array) -> void:
	var pc := Curve3D.new()
	var lc := Curve3D.new()
	for i in range(pos.size()):
		var p: Vector3 = pos[i]
		var tin := Vector3.ZERO
		var tout := Vector3.ZERO
		if i > 0 and i < pos.size() - 1:
			var tangent: Vector3 = (pos[i + 1] - pos[i - 1]) * 0.25
			tin = -tangent
			tout = tangent
		pc.add_point(p, tin, tout)
		var q: Vector3 = look[i]
		var lin := Vector3.ZERO
		var lout := Vector3.ZERO
		if i > 0 and i < look.size() - 1:
			var lt: Vector3 = (look[i + 1] - look[i - 1]) * 0.25
			lin = -lt
			lout = lt
		lc.add_point(q, lin, lout)
	pc.bake_interval = 0.2
	lc.bake_interval = 0.2
	_shots.append({"pos": pc, "look": lc, "len": pc.get_baked_length()})


## Camera at distance `d` (m) along the current shot; the look target moves in step.
func _place_camera(d: float) -> void:
	var s: Dictionary = _shots[_shot]
	var pc: Curve3D = s["pos"]
	var lc: Curve3D = s["look"]
	var f := clampf(d / maxf(float(s["len"]), 0.01), 0.0, 1.0)
	var p := pc.sample_baked(d, true)
	var q := lc.sample_baked(f * lc.get_baked_length(), true)
	cam.global_position = p
	cam.look_at(q)


func shot_index() -> int:
	return _shot


## Screenshots: jump to a point along a shot (0..1).
func jump_to(shot: int, f: float) -> void:
	if _shots.is_empty():
		return
	_shot = clampi(shot, 0, _shots.size() - 1)
	_shot_d = clampf(f, 0.0, 1.0) * float(_shots[_shot]["len"])
	_fade_a = 0.0
	if _sr:
		_sr._lod_timer = 0.0


func _process(delta: float) -> void:
	if not _built or _paused:
		return
	_t += delta
	# Camera: glide along the shot; crossfade into the next one near its end.
	var s: Dictionary = _shots[_shot]
	var length: float = s["len"]
	_shot_d += CAM_SPEED * delta
	var left := (length - _shot_d) / CAM_SPEED
	if _shot_d >= length:
		_shot = (_shot + 1) % _shots.size()
		_shot_d = 0.0
		_sr._lod_timer = 0.0   # the snow near the new shot sharpens over the next frames, under the fade
		left = float(_shots[_shot]["len"]) / CAM_SPEED
	_place_camera(_shot_d)
	var into := _shot_d / CAM_SPEED
	var want_fade := 0.0
	if into < SHOT_FADE:
		want_fade = 1.0 - into / SHOT_FADE
	elif left < SHOT_FADE:
		want_fade = 1.0 - left / SHOT_FADE
	_fade_a = move_toward(_fade_a, want_fade, delta * 1.5)
	fade.color.a = _fade_a * 0.92
	# The neighbour keeps shovelling; Gerry looks about and waves now and then.
	if figure:
		figure.action_t = fmod(_t * 0.6, 1.0)
		figure.animate(delta, 0.0)
		# Same grip as the player's third-person tool: shaft forward-down from the body.
		var k := sin(clampf(figure.action_t, 0.0, 1.0) * PI)
		_shovel.global_transform = Transform3D(figure.global_basis * Basis(Vector3.RIGHT, deg_to_rad(-42.0 - 10.0 * k)), figure.hand_r.global_position)
	if gerry and gerry.visible:
		gerry.set_pose("wave" if fmod(_t, 14.0) > 11.5 else "idle")
		gerry.animate(delta, 0.0)
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.5
		_update_lights()


## Graphics settings: fewer figures and flakes, shorter view distance on lower settings.
func _apply_graphics() -> void:
	if cam:
		var dd := int(Settings.get_value("graphics", "draw_distance", 1))
		cam.far = [140.0, 220.0, 350.0][clampi(dd, 0, 2)]
	if _weather_fx:
		_weather_fx.density = [0.4, 1.0, 1.5][clampi(int(Settings.get_value("graphics", "particles", 1)), 0, 2)]
	if day_night:
		day_night.set_shadow_quality(int(Settings.get_value("graphics", "shadows", 2)))
	if _sr:
		_sr.apply_detail(int(Settings.get_value("graphics", "snow_detail", 1)))
	if gerry:
		gerry.visible = int(Settings.get_value("graphics", "particles", 1)) > 0


func _on_setting(section: String, _key: String) -> void:
	if section == "graphics" and is_inside_tree():
		_apply_graphics()


# -----------------------------------------------------------------------------
# Menu UI
# -----------------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	root_ui = Control.new()
	root_ui.theme = UIKit.theme()
	UIKit.full_rect(root_ui)
	ui.add_child(root_ui)
	fade = ColorRect.new()
	fade.color = Color(0.03, 0.04, 0.08, 0.92)
	UIKit.full_rect(fade)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(fade)
	# A soft gradient on the left keeps the title and buttons readable over the moving scene.
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.04, 0.1, 0.8))
	g.set_color(1, Color(0.03, 0.04, 0.1, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.55, 0)
	grad.texture = gt
	UIKit.full_rect(grad)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(grad)
	var title := UIKit.shadow_label("CANADIAN\nWINTER", 120, Color(1.0, 0.98, 0.95))
	title.name = "Title"
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.3, 0.85))
	title.add_theme_constant_override("line_spacing", -30)
	title.position = Vector2(110, 110)
	root_ui.add_child(title)
	main_box = UIKit.vbox(18)
	main_box.name = "MainButtons"
	main_box.position = Vector2(118, 440)
	root_ui.add_child(main_box)
	main_box.add_child(UIKit.button("PLAY", _show_play, 32, 340))
	main_box.add_child(UIKit.button("SETTINGS", _show_settings, 32, 340))
	main_box.add_child(UIKit.button("EXIT", _exit, 32, 340))


func _exit() -> void:
	if quit_hook.is_valid():
		quit_hook.call()
		return
	AudioMgr.quit()


func _show_settings() -> void:
	var s := SettingsMenu.new()
	ui.add_child(s)


func _show_play() -> void:
	if play_panel:
		play_panel.queue_free()
	play_panel = UIKit.panel()
	play_panel.name = "PlayPanel"
	play_panel.position = Vector2(500, 330)
	play_panel.custom_minimum_size = Vector2(1060, 0)
	root_ui.add_child(play_panel)
	var v := UIKit.vbox(16)
	play_panel.add_child(v)
	var head := UIKit.hbox()
	v.add_child(head)
	head.add_child(UIKit.label("Choose a mode", 34, Color.WHITE))
	head.add_child(UIKit.hspacer())
	head.add_child(UIKit.button("Back", func(): play_panel.queue_free(); play_panel = null, 20))
	var row := UIKit.hbox(22)
	v.add_child(row)
	_mode_card(row, "fun", "FUN MODE", "The same game without the cold, the warmth meter or hydro bills.")
	_mode_card(row, "survival", "SURVIVAL MODE", "Cold outdoors, a warmth meter and a %s monthly hydro bill. Freezing sends you back to your last sleep." % UIKit.money(Catalog.balance.hydro_bill))
	# The single-player / procedural note that used to sit at the bottom of the top screen.
	v.add_child(UIKit.label("Single-player · Godot 4.7 · all art, sound and music procedurally made", 15, Color(1, 1, 1, 0.45)))


func _mode_card(parent: Control, mode: String, title: String, desc: String) -> void:
	var c := UIKit.card()
	c.custom_minimum_size = Vector2(500, 300)
	parent.add_child(c)
	var v := UIKit.vbox(12)
	c.add_child(v)
	v.add_child(UIKit.label(title, 30, UIKit.ACCENT))
	var d := UIKit.label(desc, 19, UIKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(460, 56)
	v.add_child(d)
	var info := Saves.peek(mode)
	if info.is_empty():
		v.add_child(UIKit.label("No saved game.", 18, UIKit.MUTED))
	else:
		v.add_child(UIKit.label("Saved: Winter %d · %s · %s" % [info["year"], Clock.format_time(info["time"]), UIKit.money(info["money"])], 18, Color.WHITE))
	v.add_child(UIKit.button("New Game", func(): _new_game(mode, info), 24))
	var cont := UIKit.button("Continue", func(): _continue(mode), 24)
	cont.disabled = info.is_empty()
	v.add_child(cont)


func _new_game(mode: String, info: Dictionary) -> void:
	if not info.is_empty():
		Panels.confirm(root_ui, "Start a new %s game? Your existing save (Winter %d, %s) will be overwritten the next time you sleep." % [mode.capitalize(), info["year"], UIKit.money(info["money"])], "Start new game", func(): _start(mode, true))
	else:
		_start(mode, true)


func _continue(mode: String) -> void:
	_start(mode, false)


func _start(mode: String, fresh: bool) -> void:
	# Polish 6 §3: one start at a time. An older save settles behind the loading screen for up to a
	# minute; the screen blocks the mouse, and the button pressed would keep the keyboard focus
	# (Enter or Space would load the save again).
	if _starting:
		return
	_starting = true
	get_viewport().gui_release_focus()
	loading = ColorRect.new()
	(loading as ColorRect).color = Color(0.03, 0.04, 0.08, 1.0)
	UIKit.full_rect(loading)
	root_ui.add_child(loading)
	var l := UIKit.shadow_label("Loading the neighbourhood…", 36, Color.WHITE)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-250, -20)
	loading.add_child(l)
	await get_tree().process_frame
	await get_tree().process_frame
	# The background stops and everything it set on the autoloads is put back before the game
	# state is built; New Game / Continue then reset or load the rest as they always did.
	_pause_background(true)
	_release_autoloads()
	if fresh:
		Game.new_game(mode, seed_override)
	else:
		Saves.settle_later = true
		var ok := Saves.load_game(mode)
		Saves.settle_later = false
		if not ok:
			_starting = false
			loading.queue_free()
			if _built:
				_hold_autoloads()
				_pause_background(false)
			Panels.confirm(root_ui, "Could not load the save: %s" % Saves.last_error, "OK", func(): pass)
			return
		# Polish 6 §3: a save from before the snow's settling was saved settles once, here, a
		# quarter of a second at a time (a mid-winter save can take a minute).
		if Snow.settling:
			l.text = "Settling the snow…"
			while Snow.settle_step(250000):
				await get_tree().process_frame
	if start_hook.is_valid():
		start_hook.call(mode, fresh)
		return
	get_tree().change_scene_to_file("res://scenes/game.tscn")
