class_name SidewalkCrew
extends Node3D
## Polish 5 §11: the city's sidewalk crew — a small sidewalk plow (the ATV of the vehicle kit in the
## city's orange, its blade angled to cast the snow toward the street, with the grader's beacons)
## that follows the grader on its Monday and Friday pass. It drives Municipal.crew_runs() — for each
## street lane of the grader's route, the sidewalk on the side that lane pushes its snow to, the way
## the lane is driven — staying LAG metres behind the grader on that lane, and clears each sidewalk
## box to bare pavement as its blade passes (Snow.sidewalk_clear, every half metre), then completes
## the box (Municipal.clear_sidewalk). A box the player holds a job on is driven past with the blade
## up. It runs on the city's clock like the grader: its step runs once per clock substep under
## fast-forward (game_root.sim_tick), right after the grader's. Sleep or a skip finishes the rest of
## the pass as a batch (game_root.finish_grader_now → Municipal.run_batch, the same operation), and
## the crew stops when the pass is over (Municipal.pass_finished).

const SPEED := 5.5         # m/s at 1×
const LAG := 15.0          # metres behind the grader on the same lane
const APPLY_STEP := 0.5    # the blade clears the sidewalk behind it every half metre
const BLADE_AHEAD := 1.7   # the blade's edge ahead of the vehicle's centre (the ATV's blade_z)
const COLOR := Color(0.93, 0.47, 0.07)

var runs: Array = []
var run_i := 0
var s := 0.0
var applied_s := 0.0
var clearing := false      # the box being driven is cleared (not one of the player's jobs)
var active := false
var grader: GraderNPC
var model: Node3D
var blade: MeshInstance3D
var body: AnimatableBody3D
var engine: AudioStreamPlayer3D
var beacons: Array = []
var _wait := 0.0


func _ready() -> void:
	name = "SidewalkCrew"
	var vd: VehicleData = (Catalog.vehicle(&"atv_blade") as VehicleData).duplicate()
	vd.body_color = COLOR
	var info := VehicleModels.build(vd)
	model = Node3D.new()
	add_child(model)
	var mi := MeshInstance3D.new()
	mi.mesh = info["mesh"]
	model.add_child(mi)
	if info.has("blade_mesh"):
		blade = MeshInstance3D.new()
		blade.mesh = info["blade_mesh"]
		blade.position = info["blade_pivot"]
		model.add_child(blade)
	for w in info["wheels"]:
		var wm := MeshInstance3D.new()
		wm.mesh = w["mesh"]
		wm.position = w["pos"]
		model.add_child(wm)
	for x in [-0.3, 0.3]:
		var b := MeshInstance3D.new()
		var k := MeshKit.new()
		k.box(Mats.emissive(Color(1.0, 0.6, 0.05), 4.0), Transform3D(), Vector3(0.16, 0.12, 0.16))
		b.mesh = k.commit()
		b.position = Vector3(x, 1.45, 0.55)
		model.add_child(b)
		beacons.append(b)
	# A light mast for the beacons behind the seat.
	var mk := MeshKit.new()
	mk.box(Mats.std(Color(0.15, 0.15, 0.16), 0.6), Transform3D(Basis(), Vector3(0, 1.2, 0.55)), Vector3(0.8, 0.06, 0.06))
	for x in [-0.38, 0.38]:
		mk.box(Mats.std(Color(0.15, 0.15, 0.16), 0.6), Transform3D(Basis(), Vector3(x, 1.0, 0.55)), Vector3(0.05, 0.45, 0.05))
	var mast := MeshInstance3D.new()
	mast.mesh = mk.commit()
	model.add_child(mast)
	body = AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.3, 2.8)
	cs.shape = box
	cs.position = Vector3(0, 0.65, -0.3)
	body.add_child(cs)
	add_child(body)
	engine = AudioMgr.make_loop("engine_small", self, -6.0)
	engine.pitch_scale = 1.3
	visible = false
	Municipal.pass_started.connect(start)
	Municipal.pass_finished.connect(stop)


## The pass began (after the grader's own start): the boxes still to do, in the crew's order.
func start(_lanes: Array) -> void:
	runs = Municipal.crew_runs().filter(func(e): return e["box"] in Municipal.crew_pending)
	run_i = 0
	s = 0.0
	applied_s = 0.0
	_wait = 0.0
	active = not runs.is_empty()
	visible = active
	if active:
		engine.play()
		_begin_box()
		_place()


func stop() -> void:
	Boxes.busy.clear()
	if not active and not visible:
		return
	active = false
	visible = false
	engine.stop()


func _physics_process(delta: float) -> void:
	sim_step(delta)


## One frame of the crew's work (once per clock substep under fast-forward, after the grader's).
func sim_step(delta: float) -> void:
	if not active:
		return
	if get_tree().paused:
		return
	for b in beacons:
		(b as Node3D).visible = fmod(Time.get_ticks_msec() / 1000.0 + 0.4, 0.8) < 0.4
	var e: Dictionary = runs[run_i]
	var a: Vector2 = e["a"]
	var b2: Vector2 = e["b"]
	var length := a.distance_to(b2)
	var dir := (b2 - a).normalized()
	# Stop for the player (or the player's vehicle) in the way.
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	var ahead := pp - Vector2(global_position.x, global_position.z)
	if ahead.dot(dir) > 0.0 and ahead.dot(dir) < 6.0 and absf(ahead.dot(Vector2(-dir.y, dir.x))) < 1.4:
		_wait += delta
		if _wait > 0.1 and fmod(_wait, 6.0) < delta:
			AudioMgr.play_at("horn", global_position, -2.0, 1.3)
		if _wait < 10.0:
			return
	else:
		_wait = 0.0
	# Behind the grader on the same lane.
	var ns := minf(s + SPEED * delta, length)
	ns = minf(ns, maxf(s, _limit(e)))
	if ns <= s and s < length:
		return
	s = ns
	if clearing and (s - applied_s >= APPLY_STEP or s >= length):
		_clear_part(e, applied_s, s)
		applied_s = s
	if s >= length:
		Municipal.clear_sidewalk(str(e["box"]))
		_next_box()
		if not active:
			return
	_place()


## How far along the current box the crew may go: LAG metres behind the grader while it drives the
## same lane, nowhere before the grader starts that lane, anywhere once it's past it or doesn't
## drive it (a street under the player's contract, or the grader done).
func _limit(e: Dictionary) -> float:
	if grader == null or not is_instance_valid(grader) or not grader.active:
		return INF
	for k in range(grader.lanes.size()):
		var ln: Dictionary = grader.lanes[k]
		if str(ln.get("segment", "")) != str(e["segment"]) or int(ln.get("lane", -1)) != int(e["lane"]):
			continue
		if k < grader.lane_i:
			return INF
		if k > grader.lane_i:
			return -INF
		var la: Vector2 = ln["a"]
		var ldir := (Vector2(ln["b"]) - la).normalized()
		return grader.s - LAG - (Vector2(e["a"]) - la).dot(ldir)
	return INF


## The cells of the box the blade has passed between s0 and s1 (whole columns of cells).
func _clear_part(e: Dictionary, s0: float, s1: float) -> void:
	var b := Boxes.get_box(str(e["box"]))
	if b.is_empty():
		return
	var r: Rect2 = b["rects"][0]
	var a: Vector2 = e["a"]
	var dir := (Vector2(e["b"]) - a).normalized()
	var c0 := floori(s0 / Snow.CELL + 1e-6)
	var c1 := floori(s1 / Snow.CELL + 1e-6)
	if c1 <= c0:
		return
	var w := (c1 - c0) * Snow.CELL
	var part: Rect2
	if absf(dir.x) > 0.5:
		var x := r.position.x + c0 * Snow.CELL if dir.x > 0.0 else r.end.x - c1 * Snow.CELL
		part = Rect2(x, r.position.y, w, r.size.y)
	else:
		var z := r.position.y + c0 * Snow.CELL if dir.y > 0.0 else r.end.y - c1 * Snow.CELL
		part = Rect2(r.position.x, z, r.size.x, w)
	Snow.sidewalk_clear(part, e["out"])


func _next_box() -> void:
	run_i += 1
	while run_i < runs.size() and not (runs[run_i]["box"] in Municipal.crew_pending):
		run_i += 1
	s = 0.0
	applied_s = 0.0
	_wait = 0.0
	if run_i >= runs.size():
		stop()
		return
	_begin_box()


## A new box: the blade down unless the player has a job on it; angled to cast toward the street.
func _begin_box() -> void:
	var e: Dictionary = runs[run_i]
	clearing = not Municipal.crew_skips(str(e["box"]))
	if clearing:
		Boxes.busy[str(e["box"])] = true
	if blade:
		var dir := (Vector2(e["b"]) - Vector2(e["a"])).normalized()
		var right := Vector2(-dir.y, dir.x)
		var o: Vector2i = e["out"]
		blade.rotation.y = deg_to_rad(-22.0 if Vector2(o).dot(right) > 0.0 else 22.0)
		blade.position.y = 0.0 if clearing else 0.3


func _place() -> void:
	var e: Dictionary = runs[run_i]
	var a: Vector2 = e["a"]
	var dir := (Vector2(e["b"]) - a).normalized()
	var p := a + dir * (s - BLADE_AHEAD)
	global_position = Vector3(p.x, 0, p.y)
	rotation.y = atan2(-dir.x, -dir.y)

