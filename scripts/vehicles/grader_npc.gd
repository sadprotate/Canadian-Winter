class_name GraderNPC
extends Node3D
## The city's grader (Part 11). Follows road lanes and really displaces snow: a single narrow
## pass per lane, ragged leftovers, and a windrow dumped onto boulevards and driveway entrances.

var lanes: Array = []
var lane_i := 0
var s := 0.0
var applied_s := 0.0
var speed := 6.5
var model: Node3D
var body: AnimatableBody3D
var engine: AudioStreamPlayer3D
var beacons: Array = []
var active := false
var _wait := 0.0
var _seed := 1


func _ready() -> void:
	var vd: VehicleData = Catalog.vehicle(&"grader")
	var info := VehicleModels.build(vd)
	model = Node3D.new()
	add_child(model)
	var mi := MeshInstance3D.new()
	mi.mesh = info["mesh"]
	model.add_child(mi)
	if info.has("blade_mesh"):
		var bm := MeshInstance3D.new()
		bm.mesh = info["blade_mesh"]
		bm.position = info["blade_pivot"]
		bm.rotation.y = deg_to_rad(-25)
		model.add_child(bm)
	for w in info["wheels"]:
		var wm := MeshInstance3D.new()
		wm.mesh = w["mesh"]
		wm.position = w["pos"]
		model.add_child(wm)
	for x in [-0.6, 0.6]:
		var b := MeshInstance3D.new()
		var k := MeshKit.new()
		k.box(Mats.emissive(Color(1.0, 0.6, 0.05), 4.0), Transform3D(), Vector3(0.2, 0.15, 0.2))
		b.mesh = k.commit()
		b.position = Vector3(x, 3.3, 1.0)
		model.add_child(b)
		beacons.append(b)
	body = AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.4, 8.5)
	cs.shape = box
	cs.position.y = 1.2
	body.add_child(cs)
	add_child(body)
	engine = AudioMgr.make_loop("engine_diesel", self, -2.0)
	engine.pitch_scale = 0.8
	visible = false
	Municipal.pass_started.connect(start)


func start(l: Array) -> void:
	lanes = l.duplicate()
	lane_i = 0
	s = 0.0
	applied_s = 0.0
	active = not lanes.is_empty()
	visible = active
	_seed = int(Clock.minutes)
	if active:
		engine.play()
		_place()


func _place() -> void:
	var ln: Dictionary = lanes[lane_i]
	var a: Vector2 = ln["a"]
	var b: Vector2 = ln["b"]
	var dir := (b - a).normalized()
	var p := a + dir * s
	global_position = Vector3(p.x, 0, p.y)
	rotation.y = atan2(-dir.x, -dir.y)


func _physics_process(delta: float) -> void:
	sim_step(delta)


## One frame of the pass. Polish 5 §9: the grader runs on the city's clock, so fast-forward runs
## it once more for every extra clock substep (through the world's tick) — away from the player it
## covers the route N× faster with the same blade steps, and the snow it leaves is the same as at
## 1×. Within Clock's hold distance of the player fast-forward is held at 1× for the pass.
func sim_step(delta: float) -> void:
	if not active:
		return
	if get_tree().paused:
		return
	for b in beacons:
		(b as Node3D).visible = fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4
	var ln: Dictionary = lanes[lane_i]
	var a: Vector2 = ln["a"]
	var b2: Vector2 = ln["b"]
	var length := a.distance_to(b2)
	var dir := (b2 - a).normalized()
	# Stop for the player (or the player's vehicle) in the way.
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	var ahead := pp - Vector2(global_position.x, global_position.z)
	if ahead.dot(dir) > 0.0 and ahead.dot(dir) < 9.0 and absf(ahead.dot(Vector2(-dir.y, dir.x))) < 2.4:
		_wait += delta
		if _wait > 0.1 and fmod(_wait, 6.0) < delta:
			AudioMgr.play_at("horn", global_position, 2.0, 0.7)
		if _wait < 10.0:
			return
	else:
		_wait = 0.0
	s += speed * delta
	# Apply the blade every half metre.
	if s - applied_s >= 0.5 or s >= length:
		var s1 := minf(s, length)
		Snow.grader_lane(a + dir * applied_s, a + dir * s1, ln["push"], 3.4, 0.03, _seed + lane_i * 101 + int(applied_s))
		applied_s = s1
	if s >= length:
		Municipal.lane_done(ln)
		lane_i += 1
		s = 0.0
		applied_s = 0.0
		if lane_i >= lanes.size():
			active = false
			visible = false
			engine.stop()
			return
	_place()


## Sleep / skip while driving: the rest of the route happens as a batch.
func finish() -> void:
	if not active:
		return
	var rest := []
	if lane_i < lanes.size():
		var ln: Dictionary = lanes[lane_i]
		var a: Vector2 = ln["a"]
		var b2: Vector2 = ln["b"]
		var dir := (b2 - a).normalized()
		rest.append({"a": a + dir * applied_s, "b": b2, "push": ln["push"]})
		for k in range(lane_i + 1, lanes.size()):
			rest.append(lanes[k])
	Municipal.run_batch(rest)
	active = false
	visible = false
	engine.stop()
