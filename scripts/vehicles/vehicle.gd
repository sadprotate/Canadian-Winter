class_name Vehicle
extends CharacterBody3D
## Shared vehicle controller (Part 10) driven by VehicleData. Arcade handling with snow-dependent
## traction and resistance, getting stuck, snowbank collision, plows, blowers and the dump truck.
## Controls (remappable): W/S drive & brake/reverse, A/D steer, Space handbrake, LMB blade/blower
## on-off (or dump), Z/C blade angle / chute, V camera, H horn, T radio, E exit.

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
	info = VehicleModels.build(data)
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
	snow_mi = MeshInstance3D.new()
	add_child(snow_mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(data.width, data.height * 0.75, data.length)
	cs.shape = box
	cs.position = Vector3(0, data.height * 0.45, 0)
	add_child(cs)
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
	_set_camera()
	# Snowed in? Say so straight away rather than letting the wheels spin in silence.
	var wd := wheel_snow_depth()
	if wd > stuck_depth():
		Notify.push("The %s is snowed in: about %d cm of snow around the wheels. It won't move until you dig around them and clear a path." % [data.display_name.to_lower(), int(round(wd * 100.0))], Notify.WARN)
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
	var out: Vector3 = spots[0]
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


func _toggle_tool() -> void:
	if data.dump_capacity > 0.0:
		_dump()
		return
	if not (data.has_plow or data.has_blower):
		return
	tool_on = not tool_on
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
	# Plow / blower operation.
	if occupied and tool_on and data.has_plow and blade_node:
		var bp: Vector3 = global_transform * Vector3(0, 0, info["blade_z"])
		var face := fwd.rotated(deg_to_rad(blade_angle))
		var adv := maxf(travel.dot(fwd), 0.0)
		var hw := data.blade_width * 0.5 * _ItemUpgrades.mult(data.id, &"vehicle_blade_width")
		# Polish 5 §3 (Decision 12): no road rule — a plow carries yard snow over the curb.
		var r := Snow.blade_push(Vector2(bp.x, bp.z), face, hw, adv + 0.1, data.blade_floor, false, 0.6)
		player_guard(Vector2(bp.x, bp.z), fwd, hw + 0.2)
		var ratio: float = r["berm"] / (data.blade_capacity * _ItemUpgrades.mult(data.id, &"vehicle_clear_speed"))
		work_drag = 1.0 / (1.0 + ratio * ratio)
		Snow.stat_player_moved += r["moved"]
		Game.stats_add("snow_moved", r["moved"])
		work_snd.volume_db = move_toward(work_snd.volume_db, -4.0 if absf(speed) > 0.5 else -20.0, delta * 40.0)
		if r["moved"] > 0.002 and randf() < 0.4:
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
	var shove_x := 0.0
	if pickup:
		shove_x = maxf(ahead - bal.pickup_shove_floor, 0.0) / maxf(bal.pickup_bog_depth - bal.pickup_shove_floor, 0.01)
	if blade_node:
		blade_node.rotation.y = lerp_angle(blade_node.rotation.y, -deg_to_rad(blade_angle), delta * 6.0)
		blade_node.position.y = lerpf(blade_node.position.y, 0.0 if tool_on else 0.18, delta * 6.0)
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
			int(round(ahead * 100.0)), int(round(bal.pickup_bog_depth * 100.0)), Settings.action_label("veh_reverse")]
	if bank_block or bogged:
		max_fwd = 0.0
		if _warn_timer <= 0.0:
			_warn_timer = 2.0
			set_status(blocked_reason, 3.0)
	var target := throttle * (max_fwd if throttle > 0.0 else minf(data.reverse_speed, max_fwd * 0.6 + 1.0))
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
		var r := Snow.blade_push(mid, fwd.rotated(ang * s), hw, adv + 0.1, Catalog.balance.pickup_shove_floor, false, cast)
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


## Polish 5 §12: the average snow depth under the wheels (m) at which this vehicle is stuck.
## Polish 7 §10: the pickup's, for the pickup with its plow too (blade up or down).
func stuck_depth() -> float:
	if is_pickup():
		return Catalog.balance.pickup_stuck_depth
	return data.clearance * 1.15


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
	if data.has_blower:
		s += "  |  Blower %s, chute %+d°" % ["ON" if tool_on else "off", int(chute_angle)]
	if data.dump_capacity > 0.0:
		s += "  |  Bed %.1f / %.0f m³" % [bed_load, data.dump_capacity]
	if stuck:
		s += "  |  STUCK"
	s += "  |  %d km/h" % int(absf(speed) * 3.6)
	return s
