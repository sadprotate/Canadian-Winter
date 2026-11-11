class_name Player
extends CharacterBody3D
## Player controller (Part 5): WASD + mouse look, sprint, jump, crouch, slopes/stairs,
## first- and third-person cameras, snow-depth movement resistance read from the snow sim.

signal interact_target_changed(prompt: String)

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _Equipment := preload("res://scripts/data/equipment.gd")

const HEAD_H := 1.62
const CROUCH_HEAD := 1.05
const RADIUS := 0.3
const VM_SCALE := 0.12

var state := "foot"          # foot, vehicle, machine, frozen
var third_person := false
var model: CharacterModel
var head: Node3D
var fp_cam: Camera3D
var tp_arm: SpringArm3D
var tp_cam: Camera3D
var viewmodel: Node3D
var tools: ToolController
var collision: CollisionShape3D
var capsule: CapsuleShape3D
var yaw := 0.0
var pitch := 0.0
var crouching := false
var snow_depth := 0.0
var _wade_acc := 0.0
var speed_mult_tool := 1.0
var current_speed := 0.0
var vehicle: Node = null
var machine: Node = null
var focus: Node = null
var focus_prompt := ""
var indoors := false
var in_player_house := false
var in_neighbor_house := false
var freecam := false
var _step_acc := 0.0
var _bob := 0.0
var _sens := 0.25
var _inv_x := false
var _inv_y := false
var _blocked_timer := 0.0
## Polish 5 §13: snowshoes. Your feet stand on the snow under you — trodden down by snowshoes_sink
## of its depth as you walk (Snow.wade: the track) — this high above the ground; the model, the
## camera and the hip rule start from there. The body's capsule stays on the ground, so walls, roofs
## and the map's edge stop you as before.
var shoe_lift := 0.0
var _head_base := HEAD_H
var _shoe_trodden: Dictionary = {}    # cells the last few wades on snowshoes trod (Snow.wade)
var _shoe_wades := 0
var _shoes_shown := false


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 3)
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.35
	collision = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = 1.78
	collision.shape = capsule
	collision.position.y = 0.89
	add_child(collision)
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	model.build()
	head = Node3D.new()
	head.name = "Head"
	head.position.y = HEAD_H
	add_child(head)
	fp_cam = Camera3D.new()
	fp_cam.name = "FPCamera"
	fp_cam.near = 0.02
	fp_cam.far = 600.0
	head.add_child(fp_cam)
	tp_arm = SpringArm3D.new()
	tp_arm.name = "TPArm"
	tp_arm.spring_length = 3.6
	tp_arm.collision_mask = 1
	tp_arm.margin = 0.2
	tp_arm.add_excluded_object(get_rid())
	head.add_child(tp_arm)
	tp_cam = Camera3D.new()
	tp_cam.name = "TPCamera"
	tp_cam.near = 0.05
	tp_cam.far = 600.0
	tp_arm.add_child(tp_cam)
	# First-person arms and tools live in a viewmodel scaled down toward the camera: they look
	# identical (uniform scale about the eye) but sit closer than any wall, bank or the ground can
	# ever get, so they never clip into the world (polish §1).
	viewmodel = Node3D.new()
	viewmodel.name = "Viewmodel"
	fp_cam.add_child(viewmodel)
	viewmodel.scale = Vector3.ONE * VM_SCALE
	tools = ToolController.new()
	tools.name = "Tools"
	add_child(tools)
	tools.setup(self)
	refresh_equipment()
	Game.inventory_changed.connect(refresh_equipment)
	apply_camera_settings()
	Settings.changed.connect(func(s, _k): if s == "camera": apply_camera_settings())
	set_third_person(Game.camera_third)


## Polish 5 §13: the coat on the model and the first-person sleeves (Survival only — Fun Mode shows
## no coat), the snowshoes on the model while they're on outdoors.
func refresh_equipment() -> void:
	var coat := _Equipment.coat_worn()
	if coat != model.coat_on:
		model.set_coat(coat)
	if tools and tools.arms:
		tools.arms.set_coat(coat)


## Snowshoes are on your feet and working: on foot (or at the computer) and outdoors.
func shoes_active() -> bool:
	return _Equipment.snowshoes_on() and not indoors and (state == "foot" or state == "frozen")


## Where your feet are (world y): the ground under you, raised by the snow under snowshoes.
func feet_y() -> float:
	return global_position.y + shoe_lift


func apply_camera_settings() -> void:
	_sens = float(Settings.get_value("camera", "sensitivity", 0.25))
	_inv_x = bool(Settings.get_value("camera", "invert_x", false))
	_inv_y = bool(Settings.get_value("camera", "invert_y", false))
	var fov := float(Settings.get_value("camera", "fov", 75.0))
	fp_cam.fov = fov
	tp_cam.fov = fov
	tp_arm.spring_length = float(Settings.get_value("camera", "tp_distance", 3.6))
	tp_arm.position = Vector3(float(Settings.get_value("camera", "tp_shoulder", 0.5)), 0.15, 0)


func set_third_person(on: bool) -> void:
	third_person = on
	Game.camera_third = on
	if state == "vehicle":
		return
	fp_cam.current = not on
	tp_cam.current = on
	model.visible = on
	viewmodel.visible = not on
	tools.refresh_visuals()


func active_camera() -> Camera3D:
	return tp_cam if third_person else fp_cam


func set_yaw(y: float) -> void:
	yaw = y
	rotation.y = yaw


func _unhandled_input(event: InputEvent) -> void:
	if state == "frozen" or not Game.input_captured():
		return
	if event is InputEventMouseMotion:
		var m: InputEventMouseMotion = event
		var dx := m.relative.x * (-1.0 if _inv_x else 1.0)
		var dy := m.relative.y * (-1.0 if _inv_y else 1.0)
		var k := _sens * 0.0075
		if state == "vehicle" and vehicle:
			vehicle.look(dx * k, dy * k)
			return
		yaw -= dx * k
		pitch = clampf(pitch - dy * k, deg_to_rad(-85), deg_to_rad(80))
		rotation.y = yaw
		head.rotation.x = pitch


func _physics_process(delta: float) -> void:
	_update_location_flags()
	if state == "vehicle":
		if shoe_lift != 0.0:
			shoe_lift = 0.0
			model.position.y = 0.0
		return
	if freecam:
		_freecam(delta)
		return
	var input := Vector2.ZERO
	if state != "frozen":
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var b: BalanceData = Catalog.balance
	crouching = state == "foot" and Input.is_action_pressed("crouch") and state != "frozen"
	# Snow resistance from the actual snow simulation.
	snow_depth = 0.0 if indoors else Snow.depth_at(global_position.x, global_position.z)
	# Polish 5 §13: on snowshoes you stand on the snow you have trodden down (the track: sunk in
	# snowshoes_sink of the way, _wade_trench).
	var shoes := shoes_active()
	var sink := clampf(b.snowshoes_sink, 0.0, 1.0)
	shoe_lift = move_toward(shoe_lift, snow_depth if shoes else 0.0, delta * 3.0)
	model.position.y = shoe_lift
	if shoes != _shoes_shown:
		_shoes_shown = shoes
		model.set_snowshoes(shoes)
	var target_head := CROUCH_HEAD if crouching else HEAD_H
	_head_base = lerpf(_head_base, target_head, delta * 10.0)
	head.position.y = _head_base + shoe_lift
	capsule.height = lerpf(capsule.height, 1.2 if crouching else 1.78, delta * 10.0)
	collision.position.y = capsule.height * 0.5
	var base := b.walk_speed
	if crouching:
		base = b.crouch_speed
	elif Input.is_action_pressed("sprint") and state == "foot" and not tools.is_engaged():
		base = b.sprint_speed
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0.0
	if dir.length() > 1.0:
		dir = dir.normalized()
	# Resistance comes from the snow you're stepping into (polish 2 §5: your own trench behind
	# you is easy going, fresh snow ahead is not).
	var resist_d := snow_depth
	if dir.length() > 0.01 and not indoors:
		var ahead := global_position + dir.normalized() * 0.35
		resist_d = maxf(snow_depth, Snow.depth_at(ahead.x, ahead.z))
	# On snowshoes you wade only through the snow you sink into: much faster.
	var mult := snow_speed_mult(resist_d * sink if shoes else resist_d) * speed_mult_tool
	if state == "machine" and machine:
		mult *= machine.speed_mult()
	var want := dir * base * mult
	# Wading (polish §6): snow up to hip height can be waded through (slower the deeper it is);
	# snow above the hips is a wall — dig through it. A walk-behind blower eats its way through.
	if want.length() > 0.01 and not indoors and state != "machine":
		if not can_wade_into(global_position + want.normalized() * (RADIUS + 0.12)):
			want = Vector3.ZERO
			_blocked_timer = 0.4
	_blocked_timer -= delta
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, want.x, accel * delta * maxf(base, 1.0))
	velocity.z = move_toward(velocity.z, want.z, accel * delta * maxf(base, 1.0))
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	elif Input.is_action_just_pressed("jump") and state == "foot" and (snow_depth * sink if shoes else snow_depth) < 0.35 and not crouching:
		velocity.y = b.jump_velocity * (1.0 - (snow_depth * sink if shoes else snow_depth))
	var before := global_position
	move_and_slide()
	current_speed = Vector2(velocity.x, velocity.z).length()
	_wade_trench(before)
	# Keep out of the void.
	if global_position.y < -5.0:
		global_position = Game.bedroom_spawn()
	Game.player_pos = global_position
	Game.player_yaw = yaw
	_footsteps(delta)
	_animate(delta)
	if state != "frozen":
		_update_focus()


## Wading through deep snow treads a trench (Snow.wade: trodden down, shouldered aside, volume
## conserved) every 20 cm or so.
func _wade_trench(before: Vector3) -> void:
	if state != "foot" or indoors or not is_on_floor():
		_wade_acc = 0.0
		return
	var step := Vector2(global_position.x - before.x, global_position.z - before.z)
	_wade_acc += step.length()
	if _wade_acc < 0.2:
		return
	_wade_acc = 0.0
	var p := Vector2(global_position.x, global_position.z)
	if Snow.depth_at(p.x, p.y) < Snow.WADE_MIN:
		return
	# Only the snow you're actually in (up to your hips) is trodden down; a taller wall stays a wall.
	# Polish 5 §13: on snowshoes, from where your feet are, and a much shallower trench — one pass
	# treads each cell of the track once (the wades overlap: Snow.wade skips what the last few trod),
	# down by snowshoes_sink of its depth.
	var v := 0.0
	if shoes_active():
		_shoe_wades += 1
		if _shoe_trodden.size() > 400:
			for k in _shoe_trodden.keys():
				if _shoe_wades - int(_shoe_trodden[k]) > Snow.RECENT_WADES:
					_shoe_trodden.erase(k)
		var keep := 1.0 - clampf(Catalog.balance.snowshoes_sink, 0.0, 0.99)
		v = Snow.wade(p, Vector2(velocity.x, velocity.z), 0.26, feet_y() + CharacterModel.HIP_HEIGHT, keep, _shoe_trodden, _shoe_wades)
	else:
		v = Snow.wade(p, Vector2(velocity.x, velocity.z), 0.26, global_position.y + CharacterModel.HIP_HEIGHT)
	if v > 0.01 and randf() < 0.5:
		SnowFX.puff(Vector3(p.x, Snow.surface_height(p.x, p.y) + 0.1, p.y), 0.25)


## Can the player step into the snow at this point? Only if the snow surface there is no higher
## than their hips above their feet (polish 5 §13: on snowshoes the feet are on the snow).
func can_wade_into(probe: Vector3) -> bool:
	var ahead := Snow.max_depth_in_radius(probe.x, probe.z, 0.12)
	var top := Snow.ground_at(probe.x, probe.z) + ahead
	return top - feet_y() <= CharacterModel.HIP_HEIGHT


## Speed multiplier for wading through snow of depth d (m): 1 on bare ground, a crawl at the hips.
static func snow_speed_mult(d: float) -> float:
	var hip := CharacterModel.HIP_HEIGHT
	var pts := [[0.0, 1.0], [0.03, 1.0], [0.12, 0.85], [0.3, 0.58], [0.5, 0.38], [0.7, 0.24],
		[hip - 0.1, 0.15], [hip, 0.09], [hip + 3.0, 0.06]]
	for i in range(pts.size() - 1):
		var a: Array = pts[i]
		var bb: Array = pts[i + 1]
		if d <= bb[0]:
			return lerpf(a[1], bb[1], (d - a[0]) / (bb[0] - a[0]))
	return 0.06


func _footsteps(delta: float) -> void:
	if not is_on_floor() or current_speed < 0.4:
		return
	_step_acc += current_speed * delta
	var stride := 0.72 if current_speed < 5.0 else 0.95
	if _step_acc >= stride:
		_step_acc = 0.0
		var pos := global_position
		var vol := -10.0 if crouching else -4.0
		if indoors or snow_depth < 0.015:
			AudioMgr.play_at(AudioMgr.variant("step_hard", 3), pos, vol - 4.0)
		elif snow_depth > 0.3:
			AudioMgr.play_at(AudioMgr.variant("step_deep", 3), pos, vol)
		else:
			AudioMgr.play_at(AudioMgr.variant("step_snow", 4), pos, vol)
			Snow.compress_footprint(Vector2(pos.x, pos.z), 0.008)


func _animate(delta: float) -> void:
	model.animate(delta, current_speed)
	if Settings.get_value("gameplay", "head_bob", true) and not third_person and is_on_floor():
		_bob += current_speed * delta * 2.2
		fp_cam.position.y = sin(_bob) * 0.025 * clampf(current_speed / 4.0, 0, 1)
	else:
		fp_cam.position.y = 0.0


func _update_location_flags() -> void:
	var p := Vector2(global_position.x, global_position.z)
	var ph: Rect2 = Layout.house_info(Layout.player_lot)["body"]
	var nh: Rect2 = Layout.house_info(Layout.neighbor_lot)["body"]
	in_player_house = ph.has_point(p) and global_position.y > 0.3
	in_neighbor_house = nh.has_point(p) and global_position.y > 0.3
	indoors = in_player_house or in_neighbor_house
	Survival.in_player_house = in_player_house
	Survival.in_neighbor_house = in_neighbor_house
	AudioMgr.indoors = indoors
	if in_player_house:
		var fire: Vector3 = Game.world.fireplace_pos if Game.world and "fireplace_pos" in Game.world else Vector3.ZERO
		Survival.near_fire = global_position.distance_to(fire) < 3.2
	else:
		Survival.near_fire = false


# -----------------------------------------------------------------------------
# Interaction
# -----------------------------------------------------------------------------

func _update_focus() -> void:
	var cam := active_camera()
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var reach := 3.0
	if third_person:
		reach = from.distance_to(head.global_position) + 2.6
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * reach, 1 | (1 << 1) | (1 << 3))
	q.collide_with_areas = true
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var target: Node = null
	if not hit.is_empty():
		var n: Node = hit["collider"]
		while n and not n.has_method("interact"):
			n = n.get_parent()
		if n and n.has_method("interact") and hit["position"].distance_to(head.global_position) < 3.3:
			target = n
	if state == "foot" and (target == null or (target is ToolItem and not (target as ToolItem).can_pick_up())):
		# A tool dug far enough out of the snow can be picked up when you're beside it and facing
		# it, wherever the crosshair lands on the pile around it (polish 3 §6).
		var it := _nearby_pickup(fwd)
		if it != null:
			target = it
	if target == null and state == "foot":
		target = _nearby_vehicle(fwd)
	var prompt := ""
	if target and target.has_method("interact_prompt"):
		prompt = target.interact_prompt(self)
		# Prompts are written with [E]; show the key the player actually bound to Interact.
		var key := Settings.action_label("interact")
		if key != "E" and prompt.contains("[E]"):
			prompt = prompt.replace("[E]", "[%s]" % key)
	if target != focus or prompt != focus_prompt:
		focus = target
		focus_prompt = prompt
		interact_target_changed.emit(prompt)


## The nearest tool lying within reach in front of the player that is exposed enough to pick up.
func _nearby_pickup(look: Vector3) -> ToolItem:
	if Game.world == null or not ("objects" in Game.world) or Game.world.objects == null:
		return null
	var p := Vector2(global_position.x, global_position.z)
	var f := Vector2(look.x, look.z)
	if f.length() < 0.05:
		return null
	f = f.normalized()
	var best: ToolItem = null
	var best_d := INF
	for c in Game.world.objects.get_children():
		if not (c is ToolItem) or (c as ToolItem).is_crate():
			continue
		var it: ToolItem = c
		# Distance to the closest part of the tool (it is over a metre long).
		var d := INF
		var aim := Vector2.ZERO
		for q in it.sample_points():
			var q2 := Vector2(q.x, q.z)
			var dd := q2.distance_to(p)
			if dd < d:
				d = dd
				aim = q2
		if d > 1.7 or d >= best_d:
			continue
		var to := aim - p
		if to.length() > 0.3 and to.normalized().dot(f) < 0.45:
			continue
		if not it.can_pick_up():
			continue
		best = it
		best_d = d
	return best


## A vehicle right beside the player that they're facing, even if the crosshair ray misses it
## (snow heaped on and around a parked truck, a low roof line…): you can always get in.
func _nearby_vehicle(look: Vector3) -> Node:
	if Game.world == null or not Game.world.has_method("vehicle_nodes"):
		return null
	var p := Vector2(global_position.x, global_position.z)
	var f := Vector2(look.x, look.z)
	if f.length() < 0.05:
		return null
	f = f.normalized()
	var best: Node = null
	var best_d := INF
	for v in Game.world.vehicle_nodes():
		var vn: Node3D = v
		if not is_instance_valid(vn) or not vn.has_method("interact"):
			continue
		# Distance from the player to the vehicle's footprint (an oriented box).
		var local := vn.global_transform.affine_inverse() * Vector3(p.x, vn.global_position.y, p.y)
		var hw: float = vn.data.width * 0.5
		var hl: float = vn.data.length * 0.5
		var dx := maxf(absf(local.x) - hw, 0.0)
		var dz := maxf(absf(local.z) - hl, 0.0)
		var d := Vector2(dx, dz).length()
		var to := Vector2(vn.global_position.x, vn.global_position.z) - p
		if d < 1.6 and d < best_d and (to.length() < 0.5 or to.normalized().dot(f) > 0.55):
			best = vn
			best_d = d
	return best


func try_interact() -> void:
	if state == "vehicle" and vehicle:
		vehicle.exit_vehicle()
		return
	if state == "machine" and machine:
		machine.release()
		return
	if focus and is_instance_valid(focus) and focus_prompt != "":
		focus.interact(self)


## Point on the world under the crosshair (third person aiming).
func crosshair_point(max_dist := 40.0) -> Vector3:
	var cam := active_camera()
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * max_dist, 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var snow_hit := Snow.raycast(from, fwd, max_dist)
	var best := from + fwd * max_dist
	var bd := max_dist
	if not hit.is_empty():
		best = hit["position"]
		bd = from.distance_to(best)
	if snow_hit["hit"] and from.distance_to(snow_hit["position"]) < bd:
		best = snow_hit["position"]
	return best


## Horizontal aim direction: camera yaw in FP; toward the crosshair point in TP.
func aim_dir() -> Vector2:
	if third_person:
		var p := crosshair_point()
		var d := Vector2(p.x - global_position.x, p.z - global_position.z)
		if d.length() > 0.5:
			return d.normalized()
	var f := -global_transform.basis.z
	return Vector2(f.x, f.z).normalized()


func forward2() -> Vector2:
	var f := -global_transform.basis.z
	return Vector2(f.x, f.z).normalized()


func freeze(on: bool) -> void:
	if on:
		if state == "foot" or state == "machine":
			set_meta("prev_state", state)
			state = "frozen"
	else:
		if state == "frozen":
			state = get_meta("prev_state", "foot")


func teleport(pos: Vector3, yaw_angle := INF) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	if yaw_angle != INF:
		set_yaw(yaw_angle)
	Game.player_pos = pos


func _freecam(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var up := (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	var cam_basis := fp_cam.global_transform.basis
	var v := cam_basis * Vector3(input.x, 0, input.y) + Vector3.UP * up
	var spd := 25.0 if Input.is_action_pressed("sprint") else 9.0
	global_position += v * spd * delta
