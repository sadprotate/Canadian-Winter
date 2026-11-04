class_name WalkBehind
extends StaticBody3D
## Walk-behind snowblower (Part 9.7): grab with E, hold left mouse to run, Z/C turn the chute,
## E to let go. Intake removes snow in front; the chute throws it to a landing point (never the street).

var tool_id := "small_blower"
var data: ToolData
var entry: Dictionary = {}
var grabbed := false
var running := false
var player: Player = null
var chute_angle := 70.0         # degrees relative to forward (+ = right)
var mesh: MeshInstance3D
var chute: Node3D
var engine_snd: AudioStreamPlayer3D
var disc_snd: AudioStreamPlayer3D
var stream_fx: CPUParticles3D
var cs: CollisionShape3D
var _landing: Dictionary = {}
var _land_timer := 0.0
var _acc := 0.0
var _tick := 0.0
var _warn := 0.0
var _resist := 1.0
var hint := ""
var _run_was := false
var _run_ok := false


func setup(id: String, e: Dictionary) -> void:
	tool_id = id
	entry = e
	chute_angle = float(e.get("chute", 70.0))


func _ready() -> void:
	data = Catalog.tool(StringName(tool_id))
	collision_layer = 1 | (1 << 1)
	collision_mask = 0
	mesh = MeshInstance3D.new()
	mesh.mesh = ToolModels.mesh_for(tool_id)
	add_child(mesh)
	chute = Node3D.new()
	chute.position = Vector3(0, 0.62, -0.25)
	add_child(chute)
	var ck := MeshKit.new()
	ck.cylinder(Mats.std(data.primary_color, 0.5), Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-25)), Vector3.ZERO), 0.08, 0.07, 0.45, 8, false)
	var cm := MeshInstance3D.new()
	cm.mesh = ck.commit()
	chute.add_child(cm)
	cs = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(data.width + 0.1, 0.9, 1.1)
	cs.shape = box
	cs.position = Vector3(0, 0.45, 0)
	add_child(cs)
	engine_snd = AudioMgr.make_loop(String(data.loop_sound), self, -80.0)
	disc_snd = AudioMgr.make_loop("blower_discharge", self, -80.0)
	stream_fx = SnowFX.make_stream(self)


func interact_prompt(_p: Player) -> String:
	return "[E] Grab %s" % data.display_name


func interact(p: Player) -> void:
	if grabbed:
		return
	if p.state != "foot":
		return
	if Game.carried != "":
		Notify.push("Drop what you're carrying first (%s)." % Settings.action_label("drop"), Notify.INFO)
		return
	grabbed = true
	player = p
	p.state = "machine"
	p.machine = self
	cs.disabled = true
	engine_snd.play()
	disc_snd.play()
	AudioMgr.play_at("engine_start", global_position, -6.0, 1.6)
	if entry.has("order_id") and int(entry["order_id"]) > 0:
		Economy.mark_order(int(entry["order_id"]), "collected")
		entry.erase("order_id")
	if not Game.flags.get("help_blower", false):
		Game.flags["help_blower"] = true
		Notify.push("Snowblower: hold %s to run, %s / %s to turn the chute, %s to let go." % [Settings.action_label("primary"),
			Settings.action_label("veh_aim_left"), Settings.action_label("veh_aim_right"), Settings.action_label("interact")], Notify.INFO)


func release() -> void:
	if not grabbed:
		return
	grabbed = false
	running = false
	if player:
		player.state = "foot"
		player.machine = null
	player = null
	cs.disabled = false
	engine_snd.stop()
	disc_snd.stop()
	stream_fx.emitting = false
	entry["pos"] = global_position
	entry["yaw"] = rotation.y
	entry["chute"] = chute_angle


func speed_mult() -> float:
	return (data.engaged_speed_mult if running else 0.75) * _resist


func _physics_process(delta: float) -> void:
	if not grabbed or player == null:
		return
	var fwd := player.forward2()
	var pp := player.global_position
	global_position = Vector3(pp.x + fwd.x * 1.05, pp.y, pp.z + fwd.y * 1.05)
	rotation.y = player.yaw
	var ui_block := not Game.input_captured()
	if not ui_block:
		if Input.is_action_pressed("veh_aim_left"):
			chute_angle = clampf(chute_angle - 90.0 * delta, -110.0, 110.0)
		if Input.is_action_pressed("veh_aim_right"):
			chute_angle = clampf(chute_angle + 90.0 * delta, -110.0, 110.0)
	chute.rotation.y = -deg_to_rad(chute_angle)
	# Polish 5 §2: it runs from an accepted press of the primary action (capped per second).
	var run_down := not ui_block and Input.is_action_pressed("primary")
	if run_down and not _run_was:
		_run_ok = Settings.accept_press("primary")
	_run_was = run_down
	running = run_down and _run_ok
	_warn -= delta
	player.model.set_pose("push")
	if not running:
		engine_snd.volume_db = move_toward(engine_snd.volume_db, -14.0, delta * 30.0)
		disc_snd.volume_db = move_toward(disc_snd.volume_db, -80.0, delta * 60.0)
		stream_fx.emitting = false
		_resist = 1.0
		return
	engine_snd.volume_db = move_toward(engine_snd.volume_db, -2.0, delta * 30.0)
	var cd := fwd.rotated(deg_to_rad(chute_angle))
	var cp := chute.global_position + Vector3(0, 0.3, 0)
	_land_timer -= delta
	if _land_timer <= 0.0:
		_land_timer = 0.12
		_landing = Throw.compute(get_world_3d(), cp, cd, data.throw_distance * Game.stat_value(&"blower_throw", 1.0), data.throw_angle_deg, [player.get_rid(), get_rid()])
	if player.tools:
		player.tools._show_indicator(_landing)
	if not _landing.get("valid", false):
		stream_fx.emitting = false
		disc_snd.volume_db = -80.0
		hint = "The chute is aimed at the street — turn it with %s / %s." % [Settings.action_label("veh_aim_left"), Settings.action_label("veh_aim_right")]
		if _warn <= 0.0:
			_warn = 2.5
			AudioMgr.play("ui_error", -10.0)
		return
	hint = ""
	var front := Vector2(global_position.x, global_position.z) + fwd * 0.15
	var depth := Snow.depth_at(front.x + fwd.x * 0.3, front.y + fwd.y * 0.3)
	# Deep snow above the intake slows you down; the blower still chews through it.
	_resist = 1.0 / (1.0 + maxf(0.0, depth - 0.45) * 3.0)
	var r := Snow.intake(front, fwd, data.width, data.reach, data.rate * Game.stat_value(&"blower_rate", 1.0) * delta, data.scrape_floor)
	var v: float = r["volume"]
	if v > 0.0:
		Boxes.note_work(front + fwd * 0.3)
	_acc += v
	Snow.stat_player_moved += v
	Game.stats_add("snow_moved", v)
	stream_fx.emitting = v > 0.0
	stream_fx.global_position = cp
	stream_fx.direction = Vector3(cd.x, 0.9, cd.y).normalized()
	stream_fx.initial_velocity_min = sqrt(data.throw_distance * 9.8) * 0.85
	stream_fx.initial_velocity_max = sqrt(data.throw_distance * 9.8) * 1.05
	disc_snd.volume_db = move_toward(disc_snd.volume_db, -4.0 if v > 0.0 else -30.0, delta * 50.0)
	_tick -= delta
	if _tick <= 0.0 and _acc > 0.0:
		_tick = 0.18
		ThrownSnow.spawn(Game.world, cp, cd, _landing, _acc, data.throw_angle_deg, 0.5 + _acc * 3.0)
		_acc = 0.0
