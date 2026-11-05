extends Node3D
## Game scene root: builds the world, spawns persistent objects, owns the UI layer and
## drives the tutorial flow, sleeping/autosave, power outages, death and winter completion.

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _Equipment := preload("res://scripts/data/equipment.gd")
const _HeatedPad := preload("res://scripts/world/heated_pad.gd")
const _ItemUpgrades := preload("res://scripts/data/item_upgrades.gd")
const _SidewalkCrew := preload("res://scripts/vehicles/sidewalk_crew.gd")
const _SpeedControl := preload("res://scripts/ui/speed_control.gd")

var builder: WorldBuilder
var refs: Dictionary = {}
var day_night: DayNight
var snow_renderer: SnowRenderer
var snow_fx: SnowFX
var weather_fx: WeatherFX
var player: Player
var neighbor: Neighbor
var grader: GraderNPC
var crew: _SidewalkCrew          # polish 5 §11: the city's sidewalk crew, following the grader
var store: Store
var zone_markers: ZoneMarkers
var box_outline: BoxOutline
var quest_outline: BoxOutline
var ui: CanvasLayer
var hud: HUD
var time_layer: CanvasLayer     # polish 5 §9: the fast-forward control, above the modals
var speed_ctrl: _SpeedControl
var modal: Control = null
var modal_kind := ""
var fade: ColorRect
var inventory_panel: Control
var interior := {}
var neighbor_interior := {}
var player_door: Door
var neighbor_door: Door
var fireplace_pos := Vector3.ZERO
var perf_overlay := false
var objects: Node3D
var light_pool: Array = []
var _light_timer := 0.0
var _dead := false
var _summary_shown := false
var _rack_node: Node3D
var _roof_timer := 0.0
var _roof_idx := 0
var _veh_snow_last := 0.0
var pad_node: _HeatedPad = null    # polish 5 §13: the heated pad where it lies (refresh_pad)


func _ready() -> void:
	Game.world = self
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	day_night = DayNight.new()
	add_child(day_night)
	builder = WorldBuilder.new()
	refs = builder.build(self)
	snow_renderer = SnowRenderer.new()
	snow_renderer.name = "SnowRenderer"
	add_child(snow_renderer)
	snow_fx = SnowFX.new()
	add_child(snow_fx)
	objects = Node3D.new()
	objects.name = "Objects"
	add_child(objects)
	_build_interiors()
	_build_photo_look()
	_set_snow_hide(true)
	_build_doors()
	_build_mailbox()
	_build_keys()
	store = Store.new()
	store.world = self
	add_child(store)
	zone_markers = ZoneMarkers.new()
	add_child(zone_markers)
	box_outline = BoxOutline.new()
	add_child(box_outline)
	# Gerry's trail is the tutorial objective: outlined all the time while the quest is on.
	quest_outline = BoxOutline.new()
	quest_outline.name = "QuestOutline"
	quest_outline.quest_fn = func() -> String: return "gerry_trail" if Game.stage() == Game.Stage.NEIGHBOR_TALKED else ""
	add_child(quest_outline)
	box_outline.skip_fn = quest_outline.quest_fn
	# Polish 5 §10: a box of one of your jobs is outlined in money green, also while you work it; its
	# persistent outline (ZoneMarkers) gives way to the work outline on the same box.
	box_outline.job_fn = func(id: String) -> bool: return ZoneMarkers.is_job_box(id)
	zone_markers.work_outline = box_outline
	grader = GraderNPC.new()
	add_child(grader)
	crew = _SidewalkCrew.new()
	crew.grader = grader
	add_child(crew)
	Municipal.world_handles_passes = true
	_spawn_player()
	_spawn_objects()
	_spawn_neighbor()
	if Game.has_upgrade(&"tool_rack"):
		build_tool_rack()
	weather_fx = WeatherFX.new()
	add_child(weather_fx)
	_light_pool_setup()
	_build_ui()
	_apply_graphics()
	Settings.changed.connect(_on_setting)
	Survival.died.connect(_on_died)
	Survival.power_changed.connect(_on_power)
	# Deferred: the signal fires inside the clock's _process; pausing the tree mid-iteration
	# makes the engine log SelfList errors when it unpauses.
	Clock.winter_ended.connect(_on_winter_end, CONNECT_DEFERRED)
	Weather.alert_issued.connect(func(_t): pass)
	Clock.hour_changed.connect(_on_hour_displays)
	_on_power(Survival.power_on)
	snow_renderer.build_all(player.global_position)
	# Polish 5 §9: fast-forward runs the world's tick once more per extra clock substep; a world
	# always starts at 1×.
	Clock.world_tick = sim_tick
	Clock.speed = 1
	Clock.drop_reason = ""
	Clock.running = true
	Game.in_game = true
	AudioMgr.set_menu_music(false)
	AudioMgr.set_ambience_enabled(true)
	_fade_in()
	# Polish 5 §13: an old save's global upgrades were carried over to every item: one notification.
	if _ItemUpgrades.pending_note != "":
		Notify.push(_ItemUpgrades.pending_note, Notify.GOOD)
		_ItemUpgrades.pending_note = ""
	if _Equipment.pending_note != "":
		Notify.push(_Equipment.pending_note, Notify.GOOD)   # polish 5 §13: jacket and parka → the coat
		_Equipment.pending_note = ""
	if Game.stage() == Game.Stage.START and Clock.day_index() == 0 and Clock.minutes < Clock.at(0, 8.0):
		_morning_line_due = true     # polish 5 §4: the door line waits for it
		get_tree().create_timer(1.5).timeout.connect(func():
			_morning_line_due = false
			subtitle("December 1. The storm is over... and everything is buried.", 5.0))
	if Clock.has_ended():
		call_deferred("_on_winter_end")


func _exit_tree() -> void:
	_set_snow_hide(false)
	Clock.running = false
	Clock.speed = 1
	if Clock.world_tick.is_valid() and Clock.world_tick.get_object() == self:
		Clock.world_tick = Callable()
	Game.in_game = false
	Municipal.world_handles_passes = false
	AudioMgr.stop_all_ambience()
	if Game.world == self:
		Game.world = null
		Game.player = null


# -----------------------------------------------------------------------------
# Building
# -----------------------------------------------------------------------------

func _build_interiors() -> void:
	var root := Node3D.new()
	root.name = "Interiors"
	add_child(root)
	interior = InteriorBuilder.build_player(self, root, Layout.player_lot)
	fireplace_pos = interior["fireplace_pos"]
	neighbor_interior = InteriorBuilder.build_neighbor(root, Layout.neighbor_lot)


## Polish 5 §4: "[E] Look at the photo" on the picture by the front door — the shovel in it is a
## hint, too small to make out on the wall. The box lies flat over the frame, within 3.5 cm of the
## wall, so nothing stands in front of the picture.
func _build_photo_look() -> void:
	var ph: FramedPhoto = interior.get("photo")
	if ph == null:
		return
	var n := ph.global_transform.basis.z.normalized()
	var sz := FramedPhoto.outer_size()
	Interactable.make(self, ph.global_position + n * 0.0175, Vector3(sz.x, sz.y, 0.035),
		func(_p): return "[E] Look at the photo", func(_p): open_photo(), atan2(n.x, n.z))


## No ground-snow mesh is drawn inside the two houses with interiors (see snow_ground.gdshader).
static func _set_snow_hide(on: bool) -> void:
	var names := ["snow_hide_a", "snow_hide_b"]
	var lots := [Layout.player_lot, Layout.neighbor_lot]
	for k in range(2):
		var v := Vector4.ZERO
		if on and not (lots[k] as Dictionary).is_empty():
			# The footprint is the walls' centre line; the walls stand 5.5 cm proud of it, so the
			# hidden area reaches 5 cm out (still inside every wall) to cover the door's gaps too.
			var r: Rect2 = (Layout.house_info(lots[k])["body"] as Rect2).grow(0.05)
			v = Vector4(r.position.x, r.position.y, r.end.x, r.end.y)
		RenderingServer.global_shader_parameter_set(names[k], v)


func _build_doors() -> void:
	for which in ["player", "neighbor"]:
		var lot: Dictionary = Layout.player_lot if which == "player" else Layout.neighbor_lot
		var L := HouseBuilder.lot_transform(lot)
		var sb: float = lot["setback"]
		var c := L * Vector3(-1.5, Layout.PORCH_H, sb)
		var fwd := (L * Vector3(-1.5, 0, sb - 1.0)) - (L * Vector3(-1.5, 0, sb))
		var yaw := atan2(fwd.x, fwd.z)
		var d := Door.make(self, Transform3D(Basis(Vector3.UP, yaw + PI), c), lot["door_color"], "front door")
		if which == "player":
			player_door = d
		else:
			neighbor_door = d
			d.locked_fn = func():
				# You can always let yourself out; you can go in once Gerry has invited you.
				if player and player.in_neighbor_house:
					return ""
				if neighbor and is_instance_valid(neighbor) and neighbor.invited:
					return ""
				return "Gerry's door (nobody answers)" if Game.stage() >= Game.Stage.COMPLETE else "The door is locked."


func _build_mailbox() -> void:
	var mb: Node3D = refs["mailboxes"][Layout.player_lot["index"]]
	Interactable.make(self, mb.global_position + Vector3(0, 1.3, 0), Vector3(0.5, 0.5, 0.8),
		func(_p): return "[E] Open mailbox" if not Game.flags.get("mail_read", false) else "[E] Mailbox (re-read letter)",
		func(_p): open_mailbox(), mb.global_rotation.y)


func _build_keys() -> void:
	if Game.flags.get("truck_keys", false) or not Game.flags.has("keys_pos"):
		return
	var kp: Array = Game.flags["keys_pos"]
	var keys := BuriedKeys.new()
	keys.position = Vector3(kp[0], 0, kp[1])
	objects.add_child(keys)


func build_tool_rack() -> void:
	if _rack_node:
		return
	var lot := Layout.player_lot
	var L := HouseBuilder.lot_transform(lot)
	var sb: float = lot["setback"]
	_rack_node = Node3D.new()
	add_child(_rack_node)
	var kit := MeshKit.new()
	kit.box(Mats.wood(Color(0.5, 0.35, 0.22), 0.5), L * Transform3D(Basis(), Vector3(1.6, 1.6, sb - 0.12)), Vector3(2.0, 0.12, 0.1))
	kit.box(Mats.wood(Color(0.5, 0.35, 0.22), 0.5), L * Transform3D(Basis(), Vector3(1.6, 0.6, sb - 0.12)), Vector3(2.0, 0.08, 0.1))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	_rack_node.add_child(mi)
	Interactable.make(_rack_node, L * Vector3(1.6, 1.1, sb - 0.3), Vector3(2.0, 1.4, 0.5),
		func(_p): return _rack_prompt(), func(p): _rack_use(p))
	_refresh_rack()


func _rack_prompt() -> String:
	var id := Game.current_tool_id()
	if id != "":
		return "[E] Hang %s on the rack" % Catalog.tool(StringName(id)).display_name
	if not Game.rack.is_empty():
		return "[E] Take %s from the rack" % Catalog.tool(StringName(Game.rack[Game.rack.size() - 1])).display_name
	return "Tool rack (empty)"


func _rack_use(p: Player) -> void:
	var id := Game.current_tool_id()
	if id != "":
		if Game.rack.size() >= 8:
			Notify.push("The rack is full.", Notify.WARN)
			return
		p.tools.dump_at_feet(true)
		Game.take_selected()
		Game.rack.append(id)
	elif not Game.rack.is_empty():
		var t: String = Game.rack.pop_back()
		if not Game.add_tool(t):
			Game.rack.append(t)
	AudioMgr.play_at("pickup_item", p.global_position, -4.0)
	_refresh_rack()


func _refresh_rack() -> void:
	if _rack_node == null:
		return
	for c in _rack_node.get_children():
		if c.has_meta("rack_tool"):
			c.queue_free()
	var lot := Layout.player_lot
	var L := HouseBuilder.lot_transform(lot)
	var sb: float = lot["setback"]
	for i in range(Game.rack.size()):
		var m := MeshInstance3D.new()
		m.mesh = ToolModels.mesh_for(Game.rack[i])
		m.set_meta("rack_tool", true)
		_rack_node.add_child(m)
		m.global_transform = L * Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-30)), Vector3(0.75 + i * 0.24, 1.62, sb - 0.25))
		m.scale = Vector3.ONE * 0.85


func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	add_child(player)
	Game.player = player
	player.teleport(Game.player_pos, Game.player_yaw)
	player.interact_target_changed.connect(func(_p): pass)


func _spawn_objects() -> void:
	for e in Game.items:
		spawn_item_node(e)
	for m in Game.machines:
		spawn_machine_node(m)
	for v in Game.vehicles:
		spawn_vehicle_node(v)
	refresh_pad()


## Polish 5 §13: the heated pad's node follows Game.equipment — there when it's down, gone when
## it's in your arms (or not yours yet).
func refresh_pad() -> void:
	if pad_node != null and is_instance_valid(pad_node):
		pad_node.queue_free()
	pad_node = null
	if not _Equipment.pad_placed():
		return
	pad_node = _HeatedPad.new()
	pad_node.name = "HeatedPad"
	var p := _Equipment.pad_pos()
	pad_node.position = Vector3(p.x, Snow.ground_at(p.x, p.z), p.z)
	pad_node.rotation.y = _Equipment.pad_yaw()
	objects.add_child(pad_node)


func spawn_item_node(e: Dictionary) -> ToolItem:
	var it := ToolItem.new()
	it.setup(e)
	objects.add_child(it)
	var p: Vector3 = e["pos"]
	it.global_position = p
	it.rotation.y = float(e.get("yaw", 0.0))
	return it


func spawn_tool_item(id: String, pos: Vector3, yaw: float) -> void:
	var e := {"uid": Game.uid(), "tool": id, "pos": pos, "yaw": yaw}
	Game.items.append(e)
	spawn_item_node(e)


func spawn_machine_node(e: Dictionary) -> WalkBehind:
	var m := WalkBehind.new()
	m.setup(str(e["tool"]), e)
	objects.add_child(m)
	m.global_position = e["pos"]
	m.rotation.y = float(e.get("yaw", 0.0))
	return m


func spawn_vehicle_node(e: Dictionary) -> Vehicle:
	var vd: VehicleData = Catalog.vehicle(StringName(e["id"]))
	if vd == null:
		return null
	var v := Vehicle.new()
	v.setup(vd, e)
	objects.add_child(v)
	v.global_position = e["pos"]
	v.rotation.y = float(e.get("yaw", 0.0))
	return v


func vehicle_nodes() -> Array:
	var out := []
	for c in objects.get_children():
		if c is Vehicle:
			out.append(c)
	return out


func install_plow(v: Vehicle) -> void:
	var e := v.entry
	var was_driving := v.occupied
	var drv := v.driver
	if was_driving:
		v.exit_vehicle()
	v.save_entry()
	e["id"] = "pickup_plow"
	v.queue_free()
	var nv := spawn_vehicle_node(e)
	if was_driving and drv:
		nv.call_deferred("enter_vehicle", drv)


func _spawn_neighbor() -> void:
	if Game.stage() >= Game.Stage.COMPLETE:
		return
	neighbor = Neighbor.new()
	neighbor.world = self
	add_child(neighbor)
	neighbor.place_for_stage()
	if not Game.stage_changed.is_connected(_on_stage_changed):
		Game.stage_changed.connect(_on_stage_changed)


## The trail is done: Gerry comes down it to meet you by his mailbox (polish 3 §4).
func _on_stage_changed(s: int) -> void:
	if s == Game.Stage.TRAIL_DONE:
		_end_talk_if("tip")    # polish 5 §4: the job is done, the snow tips with it
	if s == Game.Stage.TRAIL_DONE and neighbor and is_instance_valid(neighbor):
		neighbor.come_down()


func _light_pool_setup() -> void:
	# A handful of real lights reused for the streetlights nearest the player (low-tier budget).
	for i in range(4):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.5)
		l.light_energy = 1.6
		l.omni_range = 12.0
		l.visible = false
		add_child(l)
		light_pool.append(l)


# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	hud = HUD.new()
	hud.world = self
	ui.add_child(hud)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	UIKit.full_rect(fade)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)
	# Polish 5 §9: 1× / 2× / 10× beside the HUD clock, on a layer of its own so it can be clicked
	# with the computer, the map or the TV open (it hides under the fade, dialogs and menus).
	time_layer = CanvasLayer.new()
	time_layer.layer = ui.layer + 1
	add_child(time_layer)
	speed_ctrl = _SpeedControl.new()
	speed_ctrl.world = self
	speed_ctrl.hud = hud
	time_layer.add_child(speed_ctrl)


func _ui_root() -> Control:
	return hud


func subtitle(text: String, seconds := 3.0) -> void:
	_end_talk_if("thought")      # polish 5 §4: never the door line and another line at once
	hud.subtitle(text, seconds)


func _fade_in(t := 1.2) -> void:
	fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, t)


func _fade_out(t := 0.8) -> Tween:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fade, "color:a", 1.0, t)
	return tw


func open_modal(c: Control, kind: String, pause := false) -> void:
	if not (kind in FF_MODALS):
		Clock.drop_to_1x("dialog")   # polish 5 §9: no fast-forward during a dialog or sleep
	modal = c
	modal_kind = kind
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.freeze(true)
	if pause:
		get_tree().paused = true


func close_modal() -> void:
	if modal and is_instance_valid(modal) and not modal.is_queued_for_deletion():
		modal.queue_free()
	modal = null
	modal_kind = ""
	get_tree().paused = false
	player.freeze(false)
	if not _dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if Game.typing():
		return   # polish 5 §7: while a text field has the focus, no game action fires
	if event.is_action_pressed("fast_forward") and player.state != "vehicle":
		# Polish 5 §9: the fast-forward key cycles 1× → 2× → 10× → 1× (on foot, indoors and at the
		# computer; in a vehicle the same key is its radio).
		get_viewport().set_input_as_handled()
		if Settings.accept_press("fast_forward") and not Clock.cycle_speed() and speed_ctrl:
			speed_ctrl.refused()
		return
	if is_gerry_talking() and modal == null and event.is_action_pressed("interact") and (player.focus == null or player.focus == neighbor):
		# Interact moves Gerry on to his next line (unless you're looking at something else to use,
		# like his door).
		get_viewport().set_input_as_handled()
		_talk_next()
		return
	if modal_kind == "photo" and event.is_action_pressed("interact"):
		# Polish 5 §4: Interact (or Esc, below) puts the photo down again.
		get_viewport().set_input_as_handled()
		close_modal()
		return
	if event.is_action_pressed("debug") and Settings.debug_enabled():
		if modal_kind == "debug":
			close_modal()
		elif modal == null:
			var d := DebugMenu.new()
			d.world = self
			d.closed.connect(close_modal)
			ui.add_child(d)
			open_modal(d, "debug", false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if modal_kind == "pause":
			close_modal()
		elif modal_kind in ["computer", "map", "tv", "debug", "letter", "photo"]:
			close_modal()
		elif modal == null:
			_open_pause()
		return
	if modal != null:
		return
	if event.is_action_pressed("interact"):
		if Settings.accept_press("interact"):   # polish 5 §2: capped per second
			# Polish 5 §13: with the Tab overview up, Interact takes the snowshoes off or puts them on.
			if inventory_panel != null and _Equipment.has(_Equipment.SHOES) and player.state == "foot":
				_Equipment.toggle_snowshoes()
				AudioMgr.play("paper", -10.0)
				inventory_panel.queue_free()
				inventory_panel = Panels.inventory(hud)
			else:
				player.try_interact()
	elif event.is_action_pressed("camera_toggle") and player.state != "vehicle":
		player.set_third_person(not player.third_person)
	elif event.is_action_pressed("map"):
		var m := MapUI.new()
		m.closed.connect(close_modal)
		ui.add_child(m)
		open_modal(m, "map")
	elif event.is_action_pressed("slot_1"):
		Game.select_slot(0)
	elif event.is_action_pressed("slot_2"):
		Game.select_slot(1)
	elif event.is_action_pressed("slot_3"):
		Game.select_slot(2)
	elif event.is_action_pressed("slot_4"):
		Game.select_slot(3)
	elif event.is_action_pressed("slot_next") and player.state == "foot":
		Game.cycle_slot(1)
	elif event.is_action_pressed("slot_prev") and player.state == "foot":
		Game.cycle_slot(-1)


func _process(delta: float) -> void:
	# Tab overview (hold).
	var want_inv := Input.is_action_pressed("inventory") and modal == null and not Game.typing()
	if want_inv and inventory_panel == null:
		inventory_panel = Panels.inventory(hud)
	elif not want_inv and inventory_panel != null:
		inventory_panel.queue_free()
		inventory_panel = null
	if get_tree().paused:
		return
	_update_tutorial(delta)
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.5
		_update_lights()
	# Roof snow: one roof per frame (round robin) so a big snowfall never rebuilds all 22 roof
	# meshes in the same frame.
	var roofs: Array = refs["roof_snows"]
	if not roofs.is_empty():
		_roof_idx = (_roof_idx + 1) % roofs.size()
		(roofs[_roof_idx] as RoofSnow).refresh()
	_vehicle_snow_step(delta)
	# Interior lights follow the power.
	var on := Survival.power_on
	for l in interior["lights"]:
		(l as OmniLight3D).visible = on
	(interior["fire_light"] as OmniLight3D).visible = on
	(interior["fire_light"] as OmniLight3D).light_energy = 1.2 + sin(Time.get_ticks_msec() * 0.011) * 0.25 + sin(Time.get_ticks_msec() * 0.023) * 0.15
	(interior["fire_mesh"] as Node3D).visible = on
	(interior["tv_screen"] as Node3D).visible = on
	(interior["ups_led"] as MeshInstance3D).material_override = Mats.emissive(Color(1.0, 0.6, 0.1), 3.0) if not on and fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5 else null


## Snow accumulates on parked vehicles (once a real second).
func _vehicle_snow_step(delta: float) -> void:
	_roof_timer -= delta
	if _roof_timer <= 0.0:
		_roof_timer = 1.0
		var fall := Snow.fall_total - _veh_snow_last
		if fall > 0.0:
			for v in vehicle_nodes():
				(v as Vehicle).add_snowfall(fall)
		_veh_snow_last = Snow.fall_total
		RenderingServer.global_shader_parameter_set("snow_cover", clampf(0.45 + Snow.roof_depth * 0.9, 0.35, 1.0))


# -----------------------------------------------------------------------------
# Polish 5 §9: fast-forward
# -----------------------------------------------------------------------------

## Modals fast-forward keeps running under (the computer, the map, the TV, the letter, the photo).
## Any other — Gerry's dialogue, the sleep prompt, the pause menu, F1, the winter summary — stops it.
const FF_MODALS := ["computer", "map", "tv", "letter", "photo"]
## A scripted mover (the grader, Gerry walking) this close to the player holds fast-forward at 1×.
const FF_HOLD_DIST := 40.0

var _sleeping := false


## The world's share of one frame on the clock, run once more for every extra fast-forward
## substep (Clock._process), in the order a frame at 1× runs it: the vehicle snow, the snow's
## syncing and relaxation, then the grader and (polish 5 §11) the sidewalk crew behind it (whose
## own steps at 1× come first in the next frame, in the same order).
func sim_tick(delta: float) -> void:
	if get_tree().paused:
		return
	_vehicle_snow_step(delta)
	if snow_renderer:
		snow_renderer.sim_step()
	if grader:
		grader.sim_step(delta)
	if crew:
		crew.sim_step(delta)


## No modal, or one fast-forward keeps running under.
func ff_modal_ok() -> bool:
	return modal == null or modal_kind in FF_MODALS


## Why fast-forward isn't available now ("" when it is): on foot, indoors or at the computer only.
func ff_unavailable() -> String:
	if _dead:
		return "dead"
	if _sleeping:
		return "sleep"
	if player == null or not is_instance_valid(player):
		return "no player"
	var st: String = player.state
	if st == "frozen":
		st = str(player.get_meta("prev_state", "foot"))
	if st == "vehicle" or player.vehicle != null:
		return "vehicle"
	if st == "machine" or player.machine != null:
		return "machine"
	if not ff_modal_ok():
		return "sleep" if modal_kind == "sleep" else "dialog"
	if is_gerry_talking():
		return "gerry"
	return ""


## A substep's relaxation that took longer than this (µs) caps 10× at 2× (see ff_cap).
const FF_RELAX_US := 500


## The world's frame-budget cap on fast-forward ({} when none): while the grader drives its route,
## or snow is slumping hard enough that a substep's relaxation took over FF_RELAX_US (a big pile
## settling right after the player moved a lot of snow), 10× runs at 2× — every substep runs a
## frame's relaxation (up to 2.5 ms), so 10× could spend 25 ms a frame on it (measured in
## tests/perf.tscn: the grader's pass away from the player 28 ms a frame at 10×, 8 ms at 2×; a
## 75 m³ pile settling 30 ms at 10×, 10 ms at 2×). It takes effect within the frame (the clock
## re-reads it after every substep). Polish 5 §11: the sidewalk crew too (its mounds relax like the
## grader's windrows; it is out a little longer than the grader only when the grader skips streets).
func ff_cap() -> Dictionary:
	if grader and grader.active:
		return {"max": 2, "why": "grader on the streets"}
	if crew and crew.active:
		return {"max": 2, "why": "sidewalk crew out"}
	if snow_renderer and snow_renderer.relax_us_last > FF_RELAX_US:
		return {"max": 2, "why": "snow settling"}
	return {}


## Why fast-forward is held at 1× now ("" when it isn't): the grader, the sidewalk crew (polish 5
## §11) or Gerry moving near the player.
func ff_hold() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	var pp := Vector2(player.global_position.x, player.global_position.z)
	if grader and grader.active and Vector2(grader.global_position.x, grader.global_position.z).distance_to(pp) < FF_HOLD_DIST:
		return "grader"
	if crew and crew.active and Vector2(crew.global_position.x, crew.global_position.z).distance_to(pp) < FF_HOLD_DIST:
		return "crew"
	if neighbor and is_instance_valid(neighbor) and neighbor.is_walking() \
			and Vector2(neighbor.global_position.x, neighbor.global_position.z).distance_to(pp) < FF_HOLD_DIST:
		return "gerry"
	return ""


func is_night() -> bool:
	return day_night.night > 0.5


func _update_lights() -> void:
	var pts: Array = refs["streetlights"]
	var night := day_night.night > 0.2 or Weather.condition() >= Weather.C.HEAVY
	var pp := player.global_position
	var sorted := pts.duplicate()
	sorted.sort_custom(func(a, b): return (a as Vector3).distance_squared_to(pp) < (b as Vector3).distance_squared_to(pp))
	for i in range(light_pool.size()):
		var l: OmniLight3D = light_pool[i]
		l.visible = night and i < sorted.size()
		if l.visible:
			l.global_position = sorted[i]
	for v in vehicle_nodes():
		var veh: Vehicle = v
		if veh.occupied:
			for hl in veh.headlights:
				hl.visible = day_night.night > 0.3 or Weather.condition() >= Weather.C.HEAVY


func _apply_graphics() -> void:
	day_night.set_shadow_quality(int(Settings.get_value("graphics", "shadows", 2)))
	snow_renderer.apply_detail(int(Settings.get_value("graphics", "snow_detail", 1)))
	var dd := int(Settings.get_value("graphics", "draw_distance", 1))
	var far: float = [140.0, 220.0, 350.0][clampi(dd, 0, 2)]
	for cam in [player.fp_cam, player.tp_cam]:
		cam.far = far
	for v in vehicle_nodes():
		(v as Vehicle).chase_cam.far = far
		(v as Vehicle).cab_cam.far = far
	if weather_fx:
		weather_fx.density = [0.4, 1.0, 1.5][clampi(int(Settings.get_value("graphics", "particles", 1)), 0, 2)]
	if snow_fx:
		snow_fx.density = [0.4, 1.0, 1.6][clampi(int(Settings.get_value("graphics", "particles", 1)), 0, 2)]


func _on_setting(section: String, _key: String) -> void:
	if section == "graphics":
		_apply_graphics()


func show_vehicle_help(v: Node) -> void:
	Panels.vehicle_help(hud, v)


# -----------------------------------------------------------------------------
# Home interactions
# -----------------------------------------------------------------------------

func open_computer() -> void:
	# Polish §11: locked until Gerry's tutorial is done (nothing before it needs the computer).
	if not Game.computer_unlocked():
		AudioMgr.ui("ui_error")
		var why := "The computer is locked — Gerry across the street set it up for you and has the password. Go see if he needs a hand."
		subtitle(why, 5.0)
		Notify.push(why, Notify.WARN)
		return
	var c := ComputerUI.new()
	c.closed.connect(close_modal)
	ui.add_child(c)
	open_modal(c, "computer")
	AudioMgr.ui("ui_click")


func open_tv() -> void:
	if not Survival.power_on:
		Notify.push("No power — the TV is dead. Your computer still runs on its battery backup.", Notify.WARN)
		return
	var root := Panels.tv(hud, close_modal)
	open_modal(root, "tv")


## Polish 5 §4: the photo by the front door, large on screen, no text; Interact or Esc closes it.
func open_photo() -> void:
	var ph: FramedPhoto = interior.get("photo")
	if ph == null or modal != null:
		return
	open_modal(Panels.photo(hud, ph.texture), "photo")
	AudioMgr.play("paper", -10.0)


func radio_forecast() -> void:
	AudioMgr.play("radio_jingle", -6.0)
	# Polish 4 §1: the next three game hours, from the forecast model, and the city crews' line.
	subtitle(radio_text(), 10.0)


## Polish 5 §11: the crews' line is the next crew day ("City crews: Mon 7 a.m."; was "City grader
## expected Dec 18 07:33.").
func radio_text() -> String:
	return "Radio: %s %s" % [Weather.radio_bulletin(), Municipal.crew_line()]


## Polish 5 §8: the forecast is issued every game hour, and the displays follow it — a TV left on
## shows the new hour's forecast, and a radio bulletin still on screen is read again for the new hour.
func _on_hour_displays(_day: int, _hour: int) -> void:
	if modal_kind == "tv" and modal != null and is_instance_valid(modal):
		var old := modal
		modal = Panels.tv(hud, close_modal, false)
		old.queue_free()
	if hud != null and hud.subtitle_box.visible and hud.subtitle_l.text.begins_with("Radio: "):
		subtitle(radio_text(), maxf(hud._subtitle_t, 0.5))


func open_mailbox() -> void:
	_end_talk_if("thought")      # polish 5 §4: the letter takes over from the door line
	AudioMgr.play("mailbox", -4.0)
	var title := ""
	var body := ""
	if Game.is_survival():
		title = "Maple Ridge Hydro — Account Notice"
		body = "Dear Customer,\n\nA reminder that your residential hydro and heating service at %s must be paid every month.\n\nYour monthly hydro/heating bill of $%d is due on the 15th of every month. Unpaid accounts will be disconnected.\n\nThank you for choosing Maple Ridge Hydro. Stay warm this winter!\n\n— Customer Accounts" % [Layout.player_lot["address"], Catalog.balance.hydro_bill]
	else:
		title = "Welcome to Winter in Maple Ridge!"
		body = "Neighbours!\n\nThe Maple Ridge Community Association wishes everyone a safe and cozy winter.\n\n• Please keep snow off the streets — the city grader needs the room.\n• Check on your neighbours after big storms.\n• Northern Supply Co. at %s is open 7:00–21:00 for all your winter needs.\n\nHappy shovelling!\n— Your Community Association" % Layout.building_by_id("store")["address"]
	var first: bool = not Game.flags.get("mail_read", false)
	Game.flags["mail_read"] = true
	var root := Panels.letter(hud, title, body, func():
		close_modal()
		if first and Game.stage() == Game.Stage.START:
			Game.set_stage(Game.Stage.LETTER_READ)
			if neighbor:
				get_tree().create_timer(0.6).timeout.connect(func(): if neighbor: neighbor.call_for_help()))
	open_modal(root, "letter")


# -----------------------------------------------------------------------------
# Tutorial neighbour
# -----------------------------------------------------------------------------

func neighbor_dialogue(n: Neighbor) -> void:
	var st := Game.stage()
	if st <= Game.Stage.LETTER_READ:
		Game.set_stage(Game.Stage.LETTER_READ)
		var lines := [
			{"speaker": "Neighbour", "text": "Oh, thank goodness! I'm Gerry. I've been stuck out here since the storm — three feet of snow, and my back's no good for it."},
			{"speaker": "Gerry", "text": "My prescriptions come by mail. Could you clear me a trail from my mailbox to here? Not the whole driveway — just a path I can walk."},
			{"speaker": "Gerry", "text": "What would you charge me for that?", "choices": [
				{"text": "\"$40 is fine, neighbour.\"", "id": 40},
				{"text": "\"How about $55? It's a lot of snow.\"", "id": 55},
				{"text": "\"$70. It's a big job.\"", "id": 70}]},
		]
		var root := Panels.dialogue(hud, lines, func(id):
			match int(id):
				40:
					Game.flags["tutorial_pay"] = 40
					return [{"speaker": "Gerry", "text": "Deal! You're a lifesaver."}]
				55:
					Game.flags["tutorial_pay"] = 55
					return [{"speaker": "Gerry", "text": "Hmm... fair enough, it is a lot of snow. $55 it is."}]
				_:
					Game.flags["tutorial_pay"] = 50
					return [{"speaker": "Gerry", "text": "Seventy?! I'm on a pension, friend. I can do $50 — final offer."}, {"speaker": "You", "text": "...Alright, $50."}]
			, func():
				close_modal()
				var pay := int(Game.flags.get("tutorial_pay", 45))
				Contracts.create_tutorial_contract(pay)
				Game.set_stage(Game.Stage.NEIGHBOR_TALKED)
				Notify.push("Contract accepted: Gerry's path, %s — %s. Clear the outlined path from his steps down to his mailbox." % [Layout.neighbor_lot["address"], UIKit.money(pay)], Notify.GOOD)
				# Polish 5 §4: then, on the HUD (you keep walking), the two ways to move snow.
				say_gerry(HelpText.snow_tips()))
		open_modal(root, "dialogue")
	elif st == Game.Stage.NEIGHBOR_TALKED:
		# Polish 5 §4: talking to him again during the job repeats the tip (on the HUD, with the
		# keys bound now).
		say_gerry(HelpText.snow_tips())
	elif st == Game.Stage.TRAIL_DONE:
		# Polish 3 §4: Gerry's lines from here on are spoken on the HUD; you keep walking.
		if not n.invited:
			say_gerry([{"speaker": "Gerry", "text": "You did it! Here's your money, as promised. But look at you — you're frozen stiff! Come inside and warm up by the fire."}])
			n.go_in()
		elif not _talk_started:
			say_gerry([{"speaker": "Gerry", "text": "Come on in — it's warm by the fire!"}])
	elif st >= Game.Stage.COMPLETE and not is_gerry_talking():
		if not Game.flags.get("truck_keys", false):
			say_gerry([HelpText.keys_line()])     # polish 5 §4: until the keys are found
		else:
			say_gerry([{"speaker": "Gerry", "text": "Off you go now — and good luck with the business!"}])


# --- Gerry's lines on the HUD (non-blocking: the player keeps control) ----------------------

var _talk: Array = []
var _talk_i := 0
var _talk_t := 0.0
var _talk_done := Callable()
var _talk_on_line := Callable()
var _talk_started := false        # the indoor explanation has begun (this session)


func say_gerry(lines: Array, on_done: Callable = Callable(), on_line: Callable = Callable()) -> void:
	_talk = lines.duplicate()
	_talk_i = -1
	_talk_done = on_done
	_talk_on_line = on_line
	_talk_next()


func is_gerry_talking() -> bool:
	return not _talk.is_empty()


## Each line stays up long enough to read (timed by its length), or Interact moves on.
static func line_seconds(text: String) -> float:
	return clampf(2.0 + text.length() * 0.06, 4.0, 14.0)


func _talk_next() -> void:
	_talk_i += 1
	# Polish 5 §4: a line with "unless_flag" is skipped once that Game flag is set (the keys line).
	while _talk_i < _talk.size() and _skip_line(_talk[_talk_i]):
		_talk_i += 1
	if _talk_i >= _talk.size():
		_talk.clear()
		hud.say("", "")
		var cb := _talk_done
		_talk_done = Callable()
		if cb.is_valid():
			cb.call()
		return
	var ln: Dictionary = _talk[_talk_i]
	_talk_t = line_seconds(str(ln.get("text", "")))
	var more := false
	for k in range(_talk_i + 1, _talk.size()):
		more = more or not _skip_line(_talk[k])
	hud.say(str(ln.get("speaker", "")), str(ln.get("text", "")), more)
	if not ln.get("thought", false):     # the player's own thought (polish 5 §4) has no voice
		AudioMgr.play(AudioMgr.variant("neighbor_talk", 3), -6.0)
	if _talk_on_line.is_valid():
		_talk_on_line.call(ln)


static func _skip_line(ln: Dictionary) -> bool:
	return ln.has("unless_flag") and bool(Game.flags.get(str(ln["unless_flag"]), false))


## Polish 5 §4: stop what's being said if its current line is marked `key` ("thought": the door
## line; "tip": Gerry's snow tips once the trail is done). Nothing else runs after it.
func _end_talk_if(key: String) -> void:
	if _talk.is_empty() or _talk_i < 0 or _talk_i >= _talk.size():
		return
	if not bool((_talk[_talk_i] as Dictionary).get(key, false)):
		return
	_talk.clear()
	_talk_done = Callable()
	_talk_on_line = Callable()
	hud.say("", "")


# --- Polish 5 §4: the door line --------------------------------------------------------------

const DOOR_LINE := "Wow, that's a lot of snow. Better find my shovel."
var _door_was_open := false
var _door_line_due := false       # the door was opened: say it once the screen is free
var _door_line_done := false      # the first opening from inside has happened (this session)
var _morning_line_due := false    # the opening's "December 1…" subtitle is still to come


## A shovel in your hands, slots or on the rack (the one buried outside doesn't count).
static func has_shovel() -> bool:
	var held: Array = Game.slots + [Game.carried] + Game.rack
	for id in held:
		var t: ToolData = Catalog.tool(StringName(str(id))) if str(id) != "" else null
		if t != null and t.kind == ToolData.Kind.SHOVEL:
			return true
	return false


## The first time the player opens the front door from inside, during the opening (before the
## letter) and with no shovel, they think the line once, on the HUD: timed by its length, no modal,
## never stopped. Derived from the stage and the tools held; nothing is saved. It waits while
## another line is up (the morning's subtitle), and gives way to the letter and Gerry's cry.
func _update_door_line() -> void:
	var is_open := player_door != null and player_door.open
	if is_open and not _door_was_open and not _door_line_done and player.in_player_house:
		_door_line_done = true
		_door_line_due = true
	_door_was_open = is_open
	if not _door_line_due:
		return
	if Game.stage() != Game.Stage.START or has_shovel():
		_door_line_due = false
		return
	if modal != null or is_gerry_talking() or hud.subtitle_box.visible or _morning_line_due:
		return
	_door_line_due = false
	say_gerry([{"speaker": "You", "text": DOOR_LINE, "thought": true}])


func _update_tutorial(delta: float) -> void:
	_update_door_line()
	if not _talk.is_empty():
		_talk_t -= delta
		if _talk_t <= 0.0:
			_talk_next()
	var st := Game.stage()
	var obj := ""
	if st == Game.Stage.NEIGHBOR_TALKED:
		obj = "Clear the outlined path at Gerry's"
	elif st == Game.Stage.TRAIL_DONE and neighbor and is_instance_valid(neighbor):
		if not neighbor.invited:
			obj = "Talk to Gerry"
		elif not player.in_neighbor_house:
			obj = "Follow Gerry inside"
		# Both inside, Gerry by the fire: he talks you through the business.
		if not _talk_started and player.in_neighbor_house and neighbor.mode == "inside":
			_talk_started = true
			# Polish 5 §4: his last line sends you to your truck keys (skipped once they're found).
			say_gerry(HelpText.explanation(Game.is_survival()) + [HelpText.keys_line()], _finish_tutorial, func(ln):
				if str(ln["text"]).contains("computer") and neighbor and neighbor.mode == "inside":
					neighbor.walk(Neighbor.path_fire_to_computer(), "computer"))
	hud.set_objective(obj)


## End of Gerry's explanation: the tutorial is complete and the computer unlocks. Gerry stays by
## his computer; the player lets themselves out.
func _finish_tutorial() -> void:
	if Game.is_survival():
		Survival.activate()
	Game.set_stage(Game.Stage.COMPLETE)
	Notify.push("Gerry taught you the business. Your computer's Help app has his advice. Time to head home!", Notify.GOOD)
	Game.dirty_since_save = true


func debug_complete_tutorial() -> void:
	if Game.stage() < Game.Stage.NEIGHBOR_TALKED:
		Contracts.create_tutorial_contract(50)
	for c in Contracts.active:
		if c.get("tutorial", false) and c["status"] == "active":
			for z in c["zones"]:
				for ra in z["rects"]:
					Snow.set_rect(Contracts.a_to_rect(ra), 0.0)
				Contracts.measure_zone(c, z)
	Survival.activate()
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	if neighbor:
		neighbor.queue_free()
		neighbor = null


# -----------------------------------------------------------------------------
# Sleep, saving, pause
# -----------------------------------------------------------------------------

func open_sleep() -> void:
	var root := Panels.sleep(hud, func(days: int):
		close_modal()
		_do_sleep(days), close_modal)
	open_modal(root, "sleep", true)


## Polish 5 §3: the money plant in the living room, a testing aid (HANDOFF §13: remove or hide it
## before release). Each Interact (capped per second like every press) adds to the money only — not
## to the earnings in the stats or the end-of-winter summary.
func plant_money() -> void:
	Game.money += InteriorBuilder.PLANT_MONEY
	Game.money_changed.emit(Game.money)
	Game.dirty_since_save = true
	Notify.push("+%s" % UIKit.money(InteriorBuilder.PLANT_MONEY), Notify.GOOD)


## Sleep, a skip, the end of the winter: the rest of the city's pass as a batch — the grader's
## lanes, then (polish 5 §11) the sidewalks the crew hadn't done yet.
func finish_grader_now() -> void:
	if grader and grader.active:
		grader.finish()
	elif Municipal.in_progress:
		Municipal.finish_now()
	if crew:
		crew.stop()


## Sleeping always ends at the next 7:00 a.m. (polish §12).
static func next_wake_time(now_min: float) -> float:
	var day := int(now_min / 1440.0)
	var seven := Clock.at(day, 7.0)
	return seven if now_min < seven - 0.001 else Clock.at(day + 1, 7.0)


func _do_sleep(_days := 0) -> void:
	_sleeping = true             # polish 5 §9: no fast-forward from here to the wake-up
	Clock.drop_to_1x("sleep")
	player.freeze(true)
	var tw := _fade_out(1.0)
	await tw.finished
	_sleep_label(true)
	await get_tree().create_timer(0.7).timeout
	finish_grader_now()
	_flush_projectiles()
	var target := minf(next_wake_time(Clock.minutes), Clock.DAYS_IN_WINTER * 1440.0)
	player.teleport(Game.bedroom_spawn())
	Survival.in_player_house = true
	Clock.skip(target - Clock.minutes)
	var interrupted := Clock.interrupt_reason
	Clock.interrupt_reason = ""
	collect_state()
	var ok := Saves.save_game()
	player.freeze(false)
	_sleeping = false
	_sleep_label(false)
	_fade_in(1.2)
	if interrupted == "cold":
		Notify.push("You wake up shivering in the night — the house is freezing! Pay the hydro bill or find heat.", Notify.BAD)
	else:
		Notify.push("Good morning.", Notify.INFO)
	if not ok:
		Notify.push("Saving failed: %s" % Saves.last_error, Notify.BAD)
	else:
		Notify.push("Game saved.", Notify.GOOD)


## The sleep transition screen: black, a quiet "Zzz", no date or weather.
func _sleep_label(on: bool) -> void:
	var l: Label = fade.get_node_or_null("Zzz")
	if l == null:
		l = UIKit.label("Z z z …", 40, Color(0.8, 0.84, 0.95))
		l.name = "Zzz"
		l.set_anchors_preset(Control.PRESET_CENTER)
		l.position = Vector2(-80, -30)
		fade.add_child(l)
	l.visible = on


func _flush_projectiles() -> void:
	for c in get_children():
		if c is ThrownSnow:
			(c as ThrownSnow).flush()


## Copy live object state back into the Game registry (before saving).
func collect_state() -> void:
	_flush_projectiles()
	if player:
		Game.player_pos = player.global_position
		Game.player_yaw = player.yaw
		if player.vehicle:
			Game.player_pos = (player.vehicle as Vehicle).global_position + Vector3(2.5, 0, 0)
		player.tools.dump_at_feet(true)
	for c in objects.get_children():
		if c is Vehicle:
			(c as Vehicle).save_entry()
		elif c is WalkBehind:
			var m: WalkBehind = c
			m.entry["pos"] = m.global_position
			m.entry["yaw"] = m.rotation.y
			m.entry["chute"] = m.chute_angle
		elif c is ToolItem:
			var it: ToolItem = c
			it.entry["pos"] = it.global_position
			it.entry["yaw"] = it.rotation.y


func _open_pause() -> void:
	var root := Panels.pause(hud, close_modal, func():
		var s := SettingsMenu.new()
		ui.add_child(s), _exit_to_menu, _quit)
	open_modal(root, "pause", true)


func _exit_to_menu() -> void:
	var go := func():
		get_tree().paused = false
		AudioMgr.stop_all_ambience()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if Game.dirty_since_save:
		Panels.confirm(hud, "Exit to the main menu? Progress since your last sleep will be lost.", "Exit", go)
	else:
		go.call()


func _quit() -> void:
	if Game.dirty_since_save:
		Panels.confirm(hud, "Quit to desktop? Progress since your last sleep will be lost.", "Quit", func(): AudioMgr.quit())
	else:
		AudioMgr.quit()


# -----------------------------------------------------------------------------
# Survival events, death, winter end
# -----------------------------------------------------------------------------

func _on_power(on: bool) -> void:
	AudioMgr.play("power_on" if on else "power_off", -4.0)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	Clock.running = false
	if modal:
		close_modal()
	_dead = true
	player.freeze(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioMgr.play("death_sting", 0.0)
	Panels.death(hud)
	await get_tree().create_timer(6.0, true).timeout
	AudioMgr.stop_all_ambience()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_winter_end() -> void:
	if _summary_shown:
		return
	_summary_shown = true
	Clock.running = false
	finish_grader_now()
	if modal:
		close_modal()
	var root := Panels.summary(hud, func(ids: Array):
		Contracts.end_winter(ids)
		close_modal()
		_begin_next_winter())
	open_modal(root, "summary", true)


func _begin_next_winter() -> void:
	var tw := _fade_out(1.0)
	await tw.finished
	_flush_projectiles()
	collect_state()
	Game.next_winter()
	_summary_shown = false
	_veh_snow_last = Snow.fall_total
	player.teleport(Game.bedroom_spawn())
	snow_renderer.build_all(player.global_position)
	for rs in refs["roof_snows"]:
		(rs as RoofSnow).refresh(true)
	Saves.save_game()
	Clock.running = true
	_fade_in(1.5)
	subtitle("December 1, Winter %d. A fresh season begins." % Game.year, 5.0)
