class_name Vehicle
extends CharacterBody3D
## Shared vehicle controller (Part 10) driven by VehicleData. Arcade handling with snow-dependent
## traction and resistance, getting stuck, snowbank collision, plows, blowers and the dump truck.
## Controls (remappable): W/S drive & brake/reverse, A/D steer, Space handbrake, LMB blade/blower
## on-off (or dump), Up/Down raise / lower the blade (polish 7 §11), Z/C blade angle / chute,
## V camera, H horn, T radio, E exit.

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _ItemUpgrades := preload("res://scripts/data/item_upgrades.gd")

var data: VehicleData
var uid := 0
var entry: Dictionary = {}
var info: Dictionary = {}
var speed := 0.0
var steer := 0.0
var occupied := false
var driver: Player = null
var tool_on := false
var blade_angle := 0.0
var chute_angle := 0.0
var bed_load := 0.0
var snow_load := 0.0
var engine_on := false
var heat := 0.0
var stuck := false
var cab_view := false
var cam_yaw := 0.0
var cam_pitch := -0.25
var wheels: Array = []
var blade_node: Node3D
var snow_mi: MeshInstance3D
var bed_snow: MeshInstance3D
var cam_pivot: Node3D
var chase_arm: SpringArm3D
var chase_cam: Camera3D
var cab_cam: Camera3D
var engine_snd: AudioStreamPlayer3D
var work_snd: AudioStreamPlayer3D
var tire_snd: AudioStreamPlayer3D
var stream_fx: CPUParticles3D
var headlights: Array = []
var interact_area: Area3D
var bed_area: Area3D
var _stream_acc := 0.0
var _stream_timer := 0.0
var _prev_pos := Vector2.ZERO
var _snow_shown := -1.0
var _bed_shown := -1.0
var _warn_timer := 0.0
var _landing: Dictionary = {}
var _land_timer := 0.0
var status_text := ""
var _status_t := 0.0
var blocked_reason := ""     # what stops the vehicle right now ("" when nothing does)
var dragging := false        # polish 7 §11: the blade down and reversing (back-drag) this frame
var _drag_side := false      # polish 7 §11: the blade last dragged (reversing) rather than pushed
var _drag_stop := Vector2.ZERO   # polish 7 §11: the blade's centre when it last dragged
var _leaving_drag := false   # polish 7 §11: driving forward off a dragged pile (see the push)
var _sunk := -1.0            # polish 7 playtest fix 1: the snow it stands in, for the bog depth (-1: not read yet)
var blade_cs: CollisionShape3D   # polish 7 playtest fix 3: the blade's solid shape (see BLADE_CLEAR)
var blade_mult := 1.0            # polish 7 playtest fix 3: the plow width upgrade the blade is built for
var blade_lamps: MeshInstance3D  # polish 7 playtest fix 3: the upgraded blade's lamp lenses (lit with the headlights)
var _blade_mi: MeshInstance3D
var _lamps_lit := false

## Polish 7 §11: back-drag (the blade down, reversing). The blade takes the snow it passes over on its
## far side and carries it toward the vehicle: Snow.blade_push with the face turned to the vehicle,
## the band the frame's reverse travel + 0.1 m (as a push's), the snow landing DRAG_CAST behind the
## blade (0.1–0.62 m with blade_push's band and draw), against its back face and clear of every
## blade vehicle's front wheels (1 m behind the blade or more). Polish 7 playtest fix 2: what lands
## there tumbles on toward the vehicle as any pushed pile does, so a big drag's pile runs out at the
## moved-snow slope toward the front wheels at once (it used to settle there over a few seconds).
const DRAG_CAST := 0.3
## Polish 7 playtest fix 2: how far ahead of the blade's face the plow's berm drag reads its pile
## (Snow.blade_push's berm_reach, m): BERM_REACH_BASE + BERM_REACH_PER_HW x the blade's half-width
## (berm_reach()). Past the first 0.65 m (all the snow, as before) only the pushed snow counts. The
## pushed pile now tumbles forward instead of stacking at the face, so the same load lies further out,
## and further for a wider blade (its pile is bigger). Read this far, a long push is no easier than
## before for any plow: 3–9 % slower on level snow (report/playtest_fix_2.md). 0.65 m before.
const BERM_REACH_BASE := 0.5
const BERM_REACH_PER_HW := 0.6
const DRAG_STATUS := "Blade down — dragging"
## Polish 7 playtest fix 3: the blade is solid. Its shape (VehicleModels' blade_box: the plate, its
## cutting edge and any lamps, not the arms behind it) follows the blade as it stands each frame — its
## width, its angle and how high it is raised — so the blade stops against whatever stops the body.
## Its bottom is the blade's, but never under BLADE_CLEAR above the ground, the only collider that low
## (curbs, sidewalks and snow have none), so it never catches on it as the vehicle settles each frame
## (2 m/s down for one step).
const BLADE_CLEAR := 0.1
## How far the raised blade stands above the lowered one (m).
const BLADE_LIFT := 0.18
## The lit lamps on the upgraded blade: the headlights' colour.
const BLADE_LAMP_LIT := Color(1.0, 0.93, 0.8)


func setup(vd: VehicleData, e: Dictionary) -> void:
	data = vd
	entry = e
	uid = int(e.get("uid", 0))
	snow_load = float(e.get("snow", 0.0))
	bed_load = float(e.get("bed", 0.0))
	blade_angle = float(e.get("blade", 0.0))


func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = 1 | (1 << 2) | (1 << 3)
	floor_snap_length = 0.5
	blade_mult = _ItemUpgrades.mult(data.id, &"vehicle_blade_width")   # polish 7 playtest fix 3: its model shows it
	info = VehicleModels.build(data, blade_mult)
	var mi := MeshInstance3D.new()
	mi.mesh = info["mesh"]
	add_child(mi)
	for w in info["wheels"]:
		var wm := MeshInstance3D.new()
		wm.mesh = w["mesh"]
		wm.position = w["pos"]
		add_child(wm)
		wheels.append(wm)
	if info.has("blade_mesh"):
		blade_node = Node3D.new()
		blade_node.position = info["blade_pivot"]
		add_child(blade_node)
		var bm := MeshInstance3D.new()
		bm.mesh = info["blade_mesh"]
		blade_node.add_child(bm)
		_blade_mi = bm
		_add_blade_lamps()
	snow_mi = MeshInstance3D.new()
	add_child(snow_mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(data.width, data.height * 0.75, data.length)
	cs.shape = box
	cs.position = Vector3(0, data.height * 0.45, 0)
	add_child(cs)
	# Polish 7 playtest fix 3: the blade's solid shape, and its model and shape change with the upgrade.
	if blade_node:
		blade_cs = CollisionShape3D.new()
		blade_cs.shape = BoxShape3D.new()
		add_child(blade_cs)
		_fit_blade_shape()
		Game.upgrades_changed.connect(_on_upgrades_changed)
	# Interaction area around the vehicle (driver door).
	interact_area = Area3D.new()
	interact_area.collision_layer = 1 << 1
	interact_area.collision_mask = 0
	var ics := CollisionShape3D.new()
	var ibox := BoxShape3D.new()
	ibox.size = Vector3(data.width + 0.6, data.height, data.length * 0.8)
	ics.shape = ibox
	ics.position = Vector3(0, data.height * 0.5, 0)
	interact_area.add_child(ics)
	add_child(interact_area)
	interact_area.set_script(null)
	interact_area.set_meta("vehicle", self)
	if info["bed"] != Rect2():
		bed_area = Area3D.new()
		bed_area.collision_layer = 1 << 7
		bed_area.collision_mask = 0
		bed_area.set_meta("dump_bed", self)
		var bcs := CollisionShape3D.new()
		var bb := BoxShape3D.new()
		bb.size = Vector3(2.3, 1.4, 4.2)
		bcs.shape = bb
		bcs.position = info["bed_center"] + Vector3(0, 0.6, 0)
		bed_area.add_child(bcs)
		add_child(bed_area)
		bed_snow = MeshInstance3D.new()
		add_child(bed_snow)
	# Cameras
	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0, data.height * 0.75, 0)
	add_child(cam_pivot)
	chase_arm = SpringArm3D.new()
	chase_arm.spring_length = data.length * 0.9 + 3.0
	chase_arm.collision_mask = 1
	chase_arm.add_excluded_object(get_rid())
	cam_pivot.add_child(chase_arm)
	chase_cam = Camera3D.new()
	chase_cam.far = 600.0
	chase_arm.add_child(chase_cam)
	cab_cam = Camera3D.new()
	cab_cam.position = info["cab_cam"]
	cab_cam.far = 600.0
	cab_cam.near = 0.05
	add_child(cab_cam)
	# Audio
	engine_snd = AudioMgr.make_loop(String(data.engine_sound), self, -80.0)
	work_snd = AudioMgr.make_loop("plow_scrape" if data.has_plow else "blower_large", self, -80.0)
	tire_snd = AudioMgr.make_loop("tires_snow", self, -80.0)
	if data.has_blower:
		stream_fx = SnowFX.make_stream(self)
	for s in [-1.0, 1.0]:
		var sl := SpotLight3D.new()
		sl.spot_range = 28.0
		sl.spot_angle = 32.0
		sl.light_energy = 2.2
		sl.light_color = Color(1.0, 0.93, 0.8)
		sl.position = Vector3(s * 0.7, 1.0, -data.length * 0.5 - 0.1)
		sl.visible = false
		add_child(sl)
		headlights.append(sl)
	_refresh_snow_visual(true)
	_prev_pos = Vector2(global_position.x, global_position.z)


## Polish 7 §10: the player's own truck: the pickup with its plow (a new game's) or the plain pickup
## (older saves). The truck keys lock it, and it has round 5 §12's snow handling.
func is_pickup() -> bool:
	return data.kind == VehicleData.Kind.PICKUP or data.kind == VehicleData.Kind.PICKUP_PLOW


func interact_prompt(_p: Player) -> String:
	if is_pickup() and not Game.flags.get("truck_keys", false):
		return "[E] Pickup truck (locked)"
	return "[E] Drive %s" % data.display_name


func interact(p: Player) -> void:
	if is_pickup() and not Game.flags.get("truck_keys", false):
		AudioMgr.play_at("truck_locked", global_position, -2.0)
		Notify.push("The truck is locked and the keys are missing. You had them before the storm — they must be out there somewhere.", Notify.INFO)
		return
	enter_vehicle(p)


func enter_vehicle(p: Player) -> void:
	Clock.drop_to_1x("vehicle")   # polish 5 §9: no fast-forward in a vehicle
	driver = p
	occupied = true
	p.state = "vehicle"
	p.vehicle = self
	p.visible = false
	p.collision.disabled = true
	p.tools.indicator.visible = false
	engine_on = true
	cam_yaw = 0.0
	_sunk = -1.0     # polish 7 playtest fix 1: getting in reads the snow it stands in, as a load does
	_set_camera()
	# Snowed in? Say so straight away rather than letting the wheels spin in silence.
	# Polish 7 playtest fix 1: the truck still creeps (its reverse always does), so it says that.
	var wd := wheel_snow_depth()
	if wd > stuck_depth():
		Notify.push("The %s is snowed in: about %d cm of snow around the wheels. %s until you dig around them and clear a path." % [data.display_name.to_lower(), int(round(wd * 100.0)), "It only creeps" if is_pickup() else "It won't move"], Notify.WARN)
	AudioMgr.play_at("engine_start", global_position, -3.0)
	AudioMgr.play_at("door_close", global_position, -8.0, 1.3)
	engine_snd.play()
	work_snd.play()
	tire_snd.play()
	for hl in headlights:
		hl.visible = Game.world and Game.world.has_method("is_night") and Game.world.is_night()
	var key := "help_vehicle_%d" % data.kind
	if not Game.flags.get(key, false):
		Game.flags[key] = true
		if Game.world and Game.world.has_method("show_vehicle_help"):
			Game.world.show_vehicle_help(self)
	if entry.has("order_id") and int(entry["order_id"]) > 0:
		Economy.mark_order(int(entry["order_id"]), "collected")
		entry.erase("order_id")


func exit_vehicle() -> void:
	if not occupied:
		return
	var p := driver
	occupied = false
	driver = null
	tool_on = false
	engine_on = false
	Survival.vehicle_heat = 0.0
	engine_snd.stop()
	work_snd.stop()
	tire_snd.stop()
	if stream_fx:
		stream_fx.emitting = false
	for hl in headlights:
		hl.visible = false
	var side := -global_transform.basis.x
	var spots := [global_position + side * (data.width * 0.5 + 0.8), global_position - side * (data.width * 0.5 + 0.8), global_position + global_transform.basis.z * (data.length * 0.5 + 1.0)]
	# Polish 7 playtest fix 3: never into the blade's solid shape (the grader's, beside its cab, with
	# the width upgrade and angled).
	spots = spots.filter(func(s: Vector3) -> bool: return not _in_blade(s, p.capsule.radius + 0.1))
	var out: Vector3 = spots[0] if not spots.is_empty() else global_position + global_transform.basis.z * (data.length * 0.5 + 1.0)
	for s in spots:
		if Snow.depth_at(s.x, s.z) < 0.7:
			out = s
			break
	p.teleport(Vector3(out.x, 0.05, out.z))
	p.visible = true
	p.collision.disabled = false
	p.state = "foot"
	p.vehicle = null
	p.set_third_person(p.third_person)
	AudioMgr.play_at("door_close", global_position, -6.0)
	save_entry()


func look(dx: float, dy: float) -> void:
	cam_yaw -= dx
	cam_pitch = clampf(cam_pitch - dy, -1.2, 0.5)


func _set_camera() -> void:
	if not occupied:
		return
	cab_cam.current = cab_view
	chase_cam.current = not cab_view


func _unhandled_input(event: InputEvent) -> void:
	if not occupied or not Game.input_captured():
		return
	if event.is_action_pressed("camera_toggle"):
		cab_view = not cab_view
		_set_camera()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("veh_tool"):
		if Settings.accept_press("veh_tool"):   # polish 5 §2: capped per second
			_toggle_tool()
	elif event.is_action_pressed("veh_horn"):
		AudioMgr.play_at("horn", global_position, 0.0)
	elif event.is_action_pressed("veh_radio"):
		AudioMgr.play("radio_jingle", -6.0)
		Notify.push("Radio: " + Weather.radio_bulletin(), Notify.INFO)


## Polish 7 §11: the blade keys (Up / Down by default) are read here, before the GUI: the arrows are
## also Godot's ui_up / ui_down, which a focused control would take as a focus move.
func _input(event: InputEvent) -> void:
	if not occupied or not has_blade() or not Game.input_captured() or Game.typing():
		return
	var down := event.is_action_pressed("veh_blade_down")
	if not down and not event.is_action_pressed("veh_blade_up"):
		return
	get_viewport().set_input_as_handled()
	if Settings.accept_press("veh_blade_down" if down else "veh_blade_up"):   # capped per second
		set_blade(down)


## Polish 7 §11: a blade the player raises and lowers (a plow; the dump truck's veh_tool dumps).
func has_blade() -> bool:
	return data.has_plow and data.dump_capacity <= 0.0


## Polish 7 §11: lower (true) or raise the blade; a press that changes nothing does nothing.
func set_blade(down: bool) -> void:
	if has_blade() and tool_on != down:
		_toggle_tool()


func _toggle_tool() -> void:
	if data.dump_capacity > 0.0:
		_dump()
		return
	if not (data.has_plow or data.has_blower):
		return
	tool_on = not tool_on
	_drag_side = false           # polish 7 §11: a blade lowered starts as a push (standing still: as before)
	_leaving_drag = false
	AudioMgr.play_at("ui_click", global_position, -4.0, 0.7)
	if data.has_plow:
		set_status("Blade down" if tool_on else "Blade up")
	else:
		set_status("Blower running" if tool_on else "Blower off")


func _physics_process(delta: float) -> void:
	var pos2 := Vector2(global_position.x, global_position.z)
	var travel := pos2 - _prev_pos
	_prev_pos = pos2
	_warn_timer -= delta
	if _status_t > 0.0:
		_status_t -= delta
		if _status_t <= 0.0:
			status_text = ""
	var fwd3 := -global_transform.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	# Snow under the wheels and ahead of the bumper.
	var d_sum := 0.0
	for w in info["wheels"]:
		var wp: Vector3 = global_transform * (w["pos"] as Vector3)
		d_sum += Snow.depth_at(wp.x, wp.z)
	var d_wheels := d_sum / maxf(info["wheels"].size(), 1)
	var c := data.clearance
	var front := pos2 + fwd * (data.length * 0.5 + 0.35)
	var ahead := maxf(Snow.depth_at(front.x, front.y), maxf(Snow.depth_at(front.x + right.x * data.width * 0.35, front.y + right.y * data.width * 0.35), Snow.depth_at(front.x - right.x * data.width * 0.35, front.y - right.y * data.width * 0.35)))
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := false
	if occupied and Game.input_captured():
		throttle = Input.get_axis("veh_reverse", "veh_accelerate")
		steer_in = Input.get_axis("veh_right", "veh_left")
		handbrake = Input.is_action_pressed("veh_brake")
		if Input.is_action_pressed("veh_aim_left"):
			_aim(-1.0, delta)
		if Input.is_action_pressed("veh_aim_right"):
			_aim(1.0, delta)
	# Resistance: deep snow slows and eventually stops the vehicle.
	# Polish 5 §12: the plain pickup reads its snow handling from the balance data.
	# Polish 7 §10: so does the pickup with its plow while the blade is up; with the blade down it
	# plows as before. Its wheels are the pickup's either way (stuck_depth()).
	var truck := is_pickup()
	var pickup := truck and not (tool_on and data.has_plow)
	var bal: BalanceData = Catalog.balance
	var max_fwd := data.max_speed
	var sink := d_wheels / (bal.pickup_drag_depth if pickup else c)
	var drag := 1.0 / (1.0 + sink * sink * 2.5)
	var stuck_at := stuck_depth()
	stuck = d_wheels > stuck_at
	if stuck:
		drag *= clampf(1.0 - (d_wheels - stuck_at) / (c * 0.5), 0.0, 1.0) * 0.25
	max_fwd *= drag
	var accel := data.acceleration * lerpf(0.35, 1.0, data.traction) * (1.0 / (1.0 + sink))
	var work_drag := 1.0
	dragging = false
	# Plow / blower operation.
	if occupied and tool_on and data.has_plow and blade_node:
		var bp: Vector3 = global_transform * Vector3(0, 0, info["blade_z"])
		var face := fwd.rotated(deg_to_rad(blade_angle))
		var adv := maxf(travel.dot(fwd), 0.0)
		var hw := data.blade_width * 0.5 * _ItemUpgrades.mult(data.id, &"vehicle_blade_width")
		# Polish 7 §11: reversing, the blade drags the snow back; driving forward it pushes. Standing
		# still adds nothing new: the blade holds the side it last worked (a push's band as before, or
		# a drag's on the ground it uncovered, so a dragged pile stays against its back face).
		var back := maxf(-travel.dot(fwd), 0.0)
		if speed < 0.0 and back > 0.0:
			_drag_side = true
		elif adv > 0.0 and _drag_side:
			_drag_side = false
			_leaving_drag = true
		dragging = _drag_side and back > 0.0
		var r: Dictionary
		if _drag_side:
			r = back_drag(Vector2(bp.x, bp.z), face, fwd, hw, back)
			_drag_stop = Vector2(bp.x, bp.z)
			if dragging and status_text in ["", "Blade down", DRAG_STATUS]:     # a blocked reason stays first
				set_status(DRAG_STATUS, 0.5)
		else:
			# Polish 7 §11: driving off a dragged pile, the blade takes only the ground it has crossed
			# since it stopped dragging, half a cell clear of that line (the cell on it holds some of the
			# pile), not the pile behind it; once it is a push's margin past, it pushes as always.
			var band := adv + 0.1
			if _leaving_drag:
				var gone := (Vector2(bp.x, bp.z) - _drag_stop).dot(fwd) - Snow.CELL * 0.5
				if gone >= band:
					_leaving_drag = false
				else:
					band = maxf(gone, 0.0)
			# Polish 5 §3 (Decision 12): no road rule — a plow carries yard snow over the curb.
			r = Snow.blade_push(Vector2(bp.x, bp.z), face, hw, band, data.blade_floor, false, 0.6, true, berm_reach(hw))
			# Polish 7 §11: leaving a drag, the guard reaches a cell past the face, so the pile's front
			# can't slump into the gap the blade opens (and be carried off with it).
			player_guard(Vector2(bp.x, bp.z) + (fwd * Snow.CELL if _leaving_drag else Vector2.ZERO), fwd, hw + 0.2)
		var ratio: float = r["berm"] / (data.blade_capacity * _ItemUpgrades.mult(data.id, &"vehicle_clear_speed"))
		work_drag = 1.0 / (1.0 + ratio * ratio)
		Snow.stat_player_moved += r["moved"]
		Game.stats_add("snow_moved", r["moved"])
		work_snd.volume_db = move_toward(work_snd.volume_db, -4.0 if absf(speed) > 0.5 else -20.0, delta * 40.0)
		if not _drag_side and r["moved"] > 0.002 and randf() < 0.4:
			var side := Vector2(face.x, face.y).rotated(deg_to_rad(90.0 * signf(blade_angle))) if blade_angle != 0.0 else face
			SnowFX.burst(Vector3(bp.x, 0.6, bp.z) + Vector3(side.x, 0, side.y) * hw * 0.6, 10, 1.2, Vector3(side.x, 1.0, side.y).normalized())
		ahead = minf(ahead, c * 1.5)   # the plow cuts through banks (with drag)
	elif occupied and tool_on and data.has_blower:
		_blow(delta, fwd)
		ahead = minf(ahead, c * 1.5)
		work_drag = 0.55
	else:
		work_snd.volume_db = move_toward(work_snd.volume_db, -80.0, delta * 60.0)
		if pickup and speed > 0.05 and ahead > bal.pickup_shove_floor:
			_shove(fwd, travel)
	# Polish 5 §12: how hard the snow ahead pushes back on the pickup — its depth above the shove
	# floor as a fraction of the bog depth's (1 = as hard as the engine pulls).
	# Polish 7 playtest fix 1: the bog depth counts from the snow the truck stands in (_axle_depth())
	# — its depth above the shove floor adds to it. On bare ground or its own shoved track it is
	# pickup_bog_depth, as before. It is read when the driver gets in and while the truck moves, and
	# kept while it stands still, so snow that slumps in under a stopped truck doesn't lift it out
	# of a bog.
	if truck and (_sunk < 0.0 or absf(speed) > 0.05):
		_sunk = maxf(_axle_depth() - bal.pickup_shove_floor, 0.0)
	var shove_x := 0.0
	var bog_at := bal.pickup_bog_depth + maxf(_sunk, 0.0)
	if pickup:
		shove_x = maxf(ahead - bal.pickup_shove_floor, 0.0) / maxf(bog_at - bal.pickup_shove_floor, 0.01)
	if blade_node:
		blade_node.rotation.y = lerp_angle(blade_node.rotation.y, -deg_to_rad(blade_angle), delta * 6.0)
		blade_node.position.y = lerpf(blade_node.position.y, 0.0 if tool_on else BLADE_LIFT, delta * 6.0)
		_fit_blade_shape()     # polish 7 playtest fix 3: before the move, so the blade stops it too
		if blade_lamps:
			var lit: bool = not headlights.is_empty() and (headlights[0] as Node3D).visible
			if lit != _lamps_lit:
				_light_blade_lamps(lit)
	max_fwd *= work_drag
	# Snowbanks are solid for vehicles without a plow down.
	var bank_block := ahead > (bal.pickup_bank_max if pickup else c * 1.9) and throttle > 0.0
	# Polish 5 §12: the pickup in snow deeper than the bog depth only goes on while it has speed.
	var bogged := pickup and not bank_block and shove_x >= 1.0 and throttle > 0.0 and speed < bal.pickup_shove_min_speed
	# Say exactly what's in the way (polish 2 §4) instead of just not moving.
	blocked_reason = ""
	if stuck:
		blocked_reason = "Stuck: %d cm of snow under the wheels — this %s only clears about %d cm. Dig around the wheels and clear a path." % [
			int(round(d_wheels * 100.0)), data.display_name.to_lower(), int(round(bal.pickup_stuck_depth * 100.0)) if truck else int(round(c * 115.0))]
	elif bank_block and pickup:
		blocked_reason = "Snowbank ahead: %d cm deep — too much to drive through (about %d cm at most, with a run-up). Clear it or back up." % [
			int(round(ahead * 100.0)), int(round(bal.pickup_bank_max * 100.0))]
	elif bank_block:
		blocked_reason = "Snowbank ahead: %d cm deep — too much to drive through (about %d cm at most). Clear it or back up." % [
			int(round(ahead * 100.0)), int(round(c * 190.0))]
	elif bogged:
		blocked_reason = "Snowbank ahead: %d cm deep — too much to push from a standstill (about %d cm). Back up with %s and take a run at it, or clear it." % [
			int(round(ahead * 100.0)), int(round(bog_at * 100.0)), Settings.action_label("veh_reverse")]
	if bank_block or bogged:
		max_fwd = 0.0
		if _warn_timer <= 0.0:
			_warn_timer = 2.0
			set_status(blocked_reason, 3.0)
	var rev_max := minf(data.reverse_speed, max_fwd * 0.6 + 1.0)
	if dragging:
		rev_max = minf(rev_max, data.reverse_speed * work_drag)   # polish 7 §11: the dragged snow slows it as a berm slows a push
	var target := throttle * (max_fwd if throttle > 0.0 else rev_max)
	if stuck and absf(throttle) > 0.0:
		target *= 0.15
		if _warn_timer <= 0.0:
			_warn_timer = 2.5
			set_status(blocked_reason, 3.0)
	if handbrake:
		speed = move_toward(speed, 0.0, data.brake * 1.5 * delta)
	elif throttle != 0.0 and signf(throttle) != signf(speed) and absf(speed) > 0.3:
		speed = move_toward(speed, 0.0, data.brake * delta)
	else:
		speed = move_toward(speed, target, (accel if absf(target) > absf(speed) else data.brake * 0.4) * delta)
	if (bank_block or bogged) and speed > 0.0:
		speed = 0.0
	# Polish 5 §12: the snow the pickup shoves pushes back — as hard as the engine pulls at the bog
	# depth, plus a part that grows with the square of the speed.
	if shove_x > 0.0 and speed > 0.0:
		speed = maxf(speed - (accel * shove_x + bal.pickup_shove_drag * shove_x * speed * speed) * delta, 0.0)
	steer = move_toward(steer, steer_in, delta * 2.5)
	var turn := steer * data.turn_rate * clampf(absf(speed) / 3.0, 0.0, 1.0) * signf(speed) * lerpf(1.0, 0.55, clampf(absf(speed) / data.max_speed, 0, 1))
	rotate_y(turn * delta)
	var v := -global_transform.basis.z * speed
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = -2.0 if not is_on_floor() else 0.0
	move_and_slide()
	if get_slide_collision_count() > 0 and absf(speed) > 2.0:
		speed *= 0.6
	global_position.y = maxf(global_position.y, 0.0)
	# Wheels spin
	for w in wheels:
		(w as Node3D).rotate_object_local(Vector3.RIGHT, -speed * delta / 0.45)
	# Sound
	if occupied:
		engine_snd.volume_db = -4.0
		engine_snd.pitch_scale = data.engine_pitch * (0.75 + 0.7 * clampf(absf(speed) / data.max_speed, 0, 1) + (0.15 if stuck and absf(throttle) > 0 else 0.0))
		tire_snd.volume_db = lerpf(-40.0, -6.0, clampf(absf(speed) / 6.0 * clampf(d_wheels * 8.0, 0.2, 1.0), 0, 1))
		# Polish 5 §13 → §14: a cab bought for a vehicle without one is ItemUpgrades.has_heated_cab(id).
		heat = minf(1.0, heat + delta / Catalog.balance.vehicle_heat_warmup_s) if data.heated_cabin else 0.0
		Survival.vehicle_heat = heat
		Game.player_pos = global_position
		_update_camera(delta)
		if driver:
			driver.global_position = global_position + Vector3(0, 1.0, 0)
		# Driving sheds the snow load on the roof.
		if absf(speed) > 4.0 and snow_load > 0.0:
			snow_load = maxf(0.0, snow_load - delta * 0.04)
	else:
		heat = maxf(0.0, heat - delta / 60.0)
	_refresh_snow_visual(false)


## Polish 7 playtest fix 3: the blade's solid shape where the blade stands now (see BLADE_CLEAR).
func _fit_blade_shape() -> void:
	if blade_cs == null:
		return
	var b: AABB = info["blade_box"]
	var y := blade_node.position.y                 # how high the blade stands (raised: BLADE_LIFT)
	var lo := maxf(b.position.y + y, BLADE_CLEAR)
	var hi := b.end.y + y
	var size := Vector3(b.size.x, hi - lo, b.size.z)
	var box := blade_cs.shape as BoxShape3D
	if not box.size.is_equal_approx(size):
		box.size = size
	var mid := blade_node.basis * Vector3(b.get_center().x, 0.0, b.get_center().z)
	var xf := Transform3D(blade_node.basis, Vector3(blade_node.position.x, (lo + hi) * 0.5, blade_node.position.z) + mid)
	if not blade_cs.transform.is_equal_approx(xf):
		blade_cs.transform = xf


## Polish 7 playtest fix 3: whether a point on the ground is within `margin` of the blade's solid shape
## (seen from above), as the blade stands or once it has turned to its angle (it trails the angle keys).
func _in_blade(p: Vector3, margin: float) -> bool:
	if blade_cs == null:
		return false
	var b: AABB = info["blade_box"]
	var lp0 := global_transform.affine_inverse() * p
	for rot in [blade_node.rotation.y, -deg_to_rad(blade_angle)]:
		var basis := Basis(Vector3.UP, rot)
		var mid := Vector3(blade_node.position.x, 0.0, blade_node.position.z) + basis * Vector3(b.get_center().x, 0.0, b.get_center().z)
		var lp := basis.inverse() * (lp0 - mid)
		if absf(lp.x) < b.size.x * 0.5 + margin and absf(lp.z) < b.size.z * 0.5 + margin:
			return true
	return false


## Polish 7 playtest fix 3: the plow width upgrade shows as soon as it takes effect: the blade's model
## (as wide as the strip it clears, taller, blue, two lamps on top) and its solid shape.
func _on_upgrades_changed() -> void:
	var m := _ItemUpgrades.mult(data.id, &"vehicle_blade_width")
	if blade_node == null or is_equal_approx(m, blade_mult):
		return
	blade_mult = m
	var nb := VehicleModels.build(data, m)
	for k in ["blade_mesh", "blade_box", "blade_lamps"]:
		if nb.has(k):
			info[k] = nb[k]
		else:
			info.erase(k)
	_blade_mi.mesh = info["blade_mesh"]
	_add_blade_lamps()
	_fit_blade_shape()


## Polish 7 playtest fix 3: the upgraded blade's lamp lenses, on the blade (none without the upgrade).
func _add_blade_lamps() -> void:
	if blade_lamps:
		blade_lamps.free()
		blade_lamps = null
	if info.has("blade_lamps"):
		blade_lamps = MeshInstance3D.new()
		blade_lamps.mesh = info["blade_lamps"]
		blade_node.add_child(blade_lamps)
		_light_blade_lamps(_lamps_lit)


## Polish 7 playtest fix 3: the blade's lamps glow while the headlights are on (no light of their own).
func _light_blade_lamps(on: bool) -> void:
	_lamps_lit = on
	if blade_lamps:
		blade_lamps.material_override = Mats.emissive(BLADE_LAMP_LIT, 2.5) if on else null


## Polish 7 playtest fix 3: put the vehicle at `pos` facing `yaw`, stopped, its blade raised (the
## truck going home when the player sleeps). Its blade angle, load and roof snow stay; the snow
## isn't touched.
func park_at(pos: Vector3, yaw: float) -> void:
	if occupied:
		exit_vehicle()
	speed = 0.0
	steer = 0.0
	velocity = Vector3.ZERO
	tool_on = false
	dragging = false
	_drag_side = false
	_leaving_drag = false
	_sunk = -1.0
	global_position = pos
	rotation.y = yaw
	_prev_pos = Vector2(pos.x, pos.z)
	if blade_node:
		blade_node.position.y = BLADE_LIFT
		blade_node.rotation.y = -deg_to_rad(blade_angle)
		_fit_blade_shape()
	save_entry()


## Polish 5 §12: the pickup's front shoves the snow above `pickup_shove_floor` ahead and out to
## both sides — the existing blade op, once for each half of the truck's width: a fixed V with its
## point at the middle of the bumper and its arms SHOVE_SPLAY_DEG back to the front corners, each
## arm casting its snow SHOVE_CAST m along its face, ahead of the truck and clear of its path. No
## clean lane (the floor stays), no pavement, no angling. Volume is conserved (blade_push moves
## snow).
const SHOVE_SPLAY_DEG := 45.0
const SHOVE_CAST := 1.5
## Polish 7 §10: SHOVE_CAST is for the plain pickup's 2 m. The pickup with its plow (2.4 m with the
## blade raised) casts in proportion, so its snow too lands clear of its path.
const SHOVE_CAST_WIDTH := 2.0

func _shove(fwd: Vector2, travel: Vector2) -> void:
	var bp: Vector3 = global_transform * Vector3(0, 0, -data.length * 0.5)
	var front := Vector2(bp.x, bp.z)
	var right := Vector2(-fwd.y, fwd.x)
	var ang := deg_to_rad(SHOVE_SPLAY_DEG)
	var hw := data.width * 0.25 / cos(ang)   # each arm spans half the truck's width
	var adv := maxf(travel.dot(fwd), 0.0)
	var cast := SHOVE_CAST * data.width / SHOVE_CAST_WIDTH
	var moved := 0.0
	for s in [-1.0, 1.0]:
		var mid: Vector2 = front - fwd * (data.width * 0.25 * tan(ang)) + right * (data.width * 0.25 * s)
		# Polish 7 playtest fix 2: the shove's snow lands as before (no tumble): its driving rules stay.
		var r := Snow.blade_push(mid, fwd.rotated(ang * s), hw, adv + 0.1, Catalog.balance.pickup_shove_floor, false, cast, false)
		moved += float(r["moved"])
	# The truck's body holds back the snow that slumps around it, as the strip behind a plow's
	# blade does (player_guard).
	var tail := front - fwd * data.length
	var side := right * (data.width * 0.5 + 0.1)
	var mn := (front + side).min(front - side).min(tail + side).min(tail - side)
	var mx := (front + side).max(front - side).max(tail + side).max(tail - side)
	Snow.set_blade_guard(Rect2(mn, mx - mn))
	Snow.stat_player_moved += moved
	Game.stats_add("snow_moved", moved)
	if moved > 0.002 and randf() < 0.4:
		var s2 := -1.0 if randf() < 0.5 else 1.0
		var out := fwd.rotated(ang * 2.0 * s2)
		SnowFX.burst(Vector3(front.x, 0.5, front.y) + Vector3(right.x, 0, right.y) * (data.width * 0.45 * s2), 8, 1.0, Vector3(out.x, 0.9, out.y).normalized())


## Polish 7 playtest fix 1: the snow the truck stands in, for its bog depth: the lower wheel of each
## axle, averaged over the axles. A wheel line its shove doesn't clear (the plain pickup's 2 m V ends
## at its wheels) or a wheel off its cleared track in a turn adds nothing.
func _axle_depth() -> float:
	var ws: Array = info["wheels"]
	var sum := 0.0
	var n := 0
	for k in range(0, ws.size() - 1, 2):
		var a: Vector3 = global_transform * (ws[k]["pos"] as Vector3)
		var b: Vector3 = global_transform * (ws[k + 1]["pos"] as Vector3)
		sum += minf(Snow.depth_at(a.x, a.z), Snow.depth_at(b.x, b.z))
		n += 1
	return sum / maxf(n, 1)


## Polish 5 §12: the average snow depth under the wheels (m) at which this vehicle is stuck.
## Polish 7 §10: the pickup's, for the pickup with its plow too (blade up or down).
func stuck_depth() -> float:
	if is_pickup():
		return Catalog.balance.pickup_stuck_depth
	return data.clearance * 1.15


## Polish 7 §11: one frame of back-drag at the blade's centre `bp`: the blade's face turned toward the
## vehicle, the band the frame's reverse travel `back` + 0.1 m, the snow landing DRAG_CAST behind
## the blade (spread over blade_push's band, one push_rng draw per moved cell, marked soft); the
## ground it uncovers (the blade's far side) guarded from slumping back, as behind a push.
func back_drag(bp: Vector2, face: Vector2, fwd: Vector2, hw: float, back: float) -> Dictionary:
	var r := Snow.blade_push(bp, -face, hw, back + 0.1, data.blade_floor, false, DRAG_CAST, true, berm_reach(hw))
	player_guard(bp, -fwd, hw + 0.2)
	return r


## Polish 7 playtest fix 2: how far ahead of the face the berm drag reads, for a blade `hw` m to either
## side (BERM_REACH_BASE).
func berm_reach(hw: float) -> float:
	return BERM_REACH_BASE + BERM_REACH_PER_HW * hw


func player_guard(center: Vector2, fwd: Vector2, hw: float) -> void:
	var side := Vector2(-fwd.y, fwd.x) * hw
	var back := center - fwd * 2.0
	var mn := (center + side).min(center - side).min(back + side).min(back - side)
	var mx := (center + side).max(center - side).max(back + side).max(back - side)
	Snow.set_blade_guard(Rect2(mn, mx - mn))


func _aim(dir: float, delta: float) -> void:
	if data.has_plow and data.blade_angle_adjustable:
		blade_angle = clampf(blade_angle + dir * 40.0 * delta, -data.blade_max_angle_deg, data.blade_max_angle_deg)
		set_status("Blade angle %+d°" % int(blade_angle))
	elif data.has_blower:
		chute_angle = clampf(chute_angle + dir * 70.0 * delta, -100.0, 100.0)
		set_status("Chute %+d°" % int(chute_angle))


func _chute_dir(fwd: Vector2) -> Vector2:
	# Chute points to the side by default (right) and turns with Z/C.
	return fwd.rotated(deg_to_rad(90.0 + chute_angle))


func _blow(delta: float, fwd: Vector2) -> void:
	var cd := _chute_dir(fwd)
	var cp: Vector3 = global_transform * (info["chute"] as Vector3)
	_land_timer -= delta
	if _land_timer <= 0.0:
		_land_timer = 0.15
		_landing = Throw.compute(get_world_3d(), cp, cd, data.blower_throw * _ItemUpgrades.mult(data.id, &"vehicle_blower"), 40.0, [get_rid()])
	work_snd.volume_db = move_toward(work_snd.volume_db, -3.0, delta * 40.0)
	if stream_fx:
		stream_fx.global_position = cp
		stream_fx.direction = Vector3(cd.x, 0.8, cd.y).normalized()
		stream_fx.initial_velocity_min = 8.0
		stream_fx.initial_velocity_max = 12.0
	if not _landing.get("valid", false):
		if stream_fx:
			stream_fx.emitting = false
		if _warn_timer <= 0.0:
			_warn_timer = 2.0
			var keys := "%s / %s" % [Settings.action_label("veh_aim_left"), Settings.action_label("veh_aim_right")]
			set_status("Nowhere for the snow to land — turn the chute (%s)!" % keys)
			Notify.push("The blower has nowhere to put the snow. Turn the chute with %s." % keys, Notify.WARN)
		return
	var fp := Vector2(global_position.x, global_position.z) + fwd * absf(float(info["blade_z"]))
	var r := Snow.intake(fp, fwd, data.blower_width, 0.6, data.blower_rate * _ItemUpgrades.mult(data.id, &"vehicle_blower") * delta, 0.01)
	_stream_acc += r["volume"]
	Snow.stat_player_moved += r["volume"]
	Game.stats_add("snow_moved", r["volume"])
	if stream_fx:
		stream_fx.emitting = r["volume"] > 0.0
	_stream_timer -= delta
	if _stream_timer <= 0.0 and _stream_acc > 0.0:
		_stream_timer = 0.2
		ThrownSnow.spawn(Game.world, cp, cd, _landing, _stream_acc, 40.0, 0.8 + _stream_acc)
		_stream_acc = 0.0


func _dump() -> void:
	if bed_load <= 0.01:
		set_status("The bed is empty. Blow or throw snow into it.")
		return
	var p := Vector2(global_position.x, global_position.z)
	if Layout.dump_rect.has_point(p):
		Game.stats_add("snow_hauled", bed_load)
		Notify.push("Dumped %.1f m³ of snow at the municipal snow dump." % bed_load, Notify.GOOD)
		bed_load = 0.0
		AudioMgr.play_at("snow_land_big", global_position, 0.0, 0.7)
		return
	var back := p + Vector2(global_transform.basis.z.x, global_transform.basis.z.z).normalized() * (data.length * 0.5 + 1.2)
	# Polish 5 §3 (Decision 12): no road rule — the load may be dumped on the street too.
	Snow.deposit(back, bed_load, 1.6, true)
	bed_load = 0.0
	AudioMgr.play_at("snow_land_big", global_position, 0.0, 0.7)


## Dump truck bed receives thrown / blown snow. Returns overflow volume.
func add_load(v: float) -> float:
	var space := data.dump_capacity - bed_load
	var took := minf(v, space)
	bed_load += took
	return v - took


func _update_camera(delta: float) -> void:
	if not occupied:
		return
	if not cab_view:
		cam_yaw = lerpf(cam_yaw, 0.0, delta * 0.6 if absf(speed) > 2.0 else 0.0)
		cam_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	else:
		cab_cam.rotation = Vector3(clampf(cam_pitch + 0.25, -0.8, 0.6), clampf(cam_yaw, -1.6, 1.6), 0)


func _refresh_snow_visual(force: bool) -> void:
	if not force and absf(snow_load - _snow_shown) < 0.03 and (bed_snow == null or absf(bed_load - _bed_shown) < 0.2):
		return
	_snow_shown = snow_load
	var kit := MeshKit.new()
	for s in info["snow"]:
		var xf: Transform3D = s[0]
		var sz: Vector2 = s[1]
		kit.pillow(Mats.snow_soft(), xf, sz.x, sz.y, snow_load * 0.8, 0.06 + snow_load * 0.15, 8, 2.6)
	snow_mi.mesh = kit.commit() if snow_load > 0.01 else null
	if bed_snow:
		_bed_shown = bed_load
		var bk := MeshKit.new()
		var fill := clampf(bed_load / maxf(data.dump_capacity, 1.0), 0.0, 1.0)
		if fill > 0.01:
			bk.pillow(Mats.snow_soft(), Transform3D(Basis(), info["bed_center"] + Vector3(0, -0.05, 0)), 2.3, 4.2, 0.2 + fill * 1.3, 0.05, 8, 3.0)
			bed_snow.mesh = bk.commit()
		else:
			bed_snow.mesh = null


## Snowfall accumulates on parked vehicles (simplified layer).
func add_snowfall(m: float) -> void:
	if not occupied:
		snow_load = minf(snow_load + m, 0.9)


func save_entry() -> void:
	entry["pos"] = global_position
	entry["yaw"] = rotation.y
	entry["snow"] = snow_load
	entry["bed"] = bed_load
	entry["blade"] = blade_angle
	entry["id"] = String(data.id)


## Average snow depth under the wheels (m).
func wheel_snow_depth() -> float:
	var d_sum := 0.0
	for w in info["wheels"]:
		var wp: Vector3 = global_transform * (w["pos"] as Vector3)
		d_sum += Snow.depth_at(wp.x, wp.z)
	return d_sum / maxf(info["wheels"].size(), 1)


## Show a short status line in the HUD (it clears itself after a few seconds).
func set_status(text: String, secs := 2.5) -> void:
	status_text = text
	_status_t = secs


func hud_text() -> String:
	var s := data.display_name
	if data.has_plow:
		s += "  |  Blade %s %+d°" % ["DOWN" if tool_on else "up", int(blade_angle)]
		if dragging:
			s += " — dragging"      # polish 7 §11
	if data.has_blower:
		s += "  |  Blower %s, chute %+d°" % ["ON" if tool_on else "off", int(chute_angle)]
	if data.dump_capacity > 0.0:
		s += "  |  Bed %.1f / %.0f m³" % [bed_load, data.dump_capacity]
	if stuck:
		s += "  |  STUCK"
	s += "  |  %d km/h" % int(absf(speed) * 3.6)
	return s
