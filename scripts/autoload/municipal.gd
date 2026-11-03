extends Node
## City grader schedule (Part 11): a pass every 3–4 days regardless of weather, first pass on
## Dec 3 or 4. While the world is loaded a visible NPC grader drives the route and displaces
## real snow; during time skips (or without a world) the same lanes run as batched operations.

signal pass_started(lanes: Array)
signal pass_finished

var next_pass := 0.0
var last_pass := -1.0
var passes := 0
var in_progress := false
var pending_lanes: Array = []
var _rng := RandomNumberGenerator.new()
var world_handles_passes := false   # set by the game world when a grader NPC exists


func start_winter() -> void:
	_rng.seed = Game.weather_seed * 3 + Game.year
	next_pass = Clock.at(_rng.randi_range(2, 3), _rng.randf_range(4.0, 8.0))
	last_pass = -1.0
	passes = 0
	in_progress = false
	pending_lanes = []


## Lanes for the next pass, skipping streets the player holds a municipal contract for.
func route_lanes() -> Array:
	var skip := Contracts.contracted_segments()
	var lanes := []
	for seg in Layout.road_segments:
		if seg["id"] in skip:
			continue
		for ln in seg["lanes"]:
			lanes.append({"a": ln["a"], "b": ln["b"], "push": ln["push"], "segment": seg["id"]})
	return lanes


func on_hour(_day: int, _hour: int) -> void:
	if Clock.minutes + 0.01 >= next_pass and not in_progress:
		_begin_pass()


func _begin_pass() -> void:
	passes += 1
	last_pass = Clock.minutes
	var gap_days := 3 if _rng.randf() < 0.5 else 4
	next_pass = next_pass + gap_days * 1440.0
	var lanes := route_lanes()
	if world_handles_passes and not Clock.skipping:
		in_progress = true
		pending_lanes = lanes
		pass_started.emit(lanes)
		Notify.push("The city grader is clearing the streets.", Notify.INFO)
	else:
		run_batch(lanes)


## Batched pass: same lane operation as the NPC, applied at once.
func run_batch(lanes: Array) -> void:
	Snow.hot_mode = false
	for ln in lanes:
		Snow.grader_lane(ln["a"], ln["b"], ln["push"], 3.4, 0.03, int(Clock.minutes) + passes * 17)
	Snow.hot_mode = true
	in_progress = false
	pending_lanes = []
	pass_finished.emit()


## Called by the NPC grader when it finishes a lane.
func lane_done(lane: Dictionary) -> void:
	pending_lanes.erase(lane)
	if pending_lanes.is_empty():
		in_progress = false
		pass_finished.emit()


## Called when the player sleeps while the NPC is mid-route: finish the rest as a batch.
func finish_now() -> void:
	if in_progress:
		run_batch(pending_lanes.duplicate())


func next_pass_text() -> String:
	return Clock.format_time(next_pass)


func serialize() -> Dictionary:
	return {"next_pass": next_pass, "last_pass": last_pass, "passes": passes, "rng": _rng.state}


func deserialize(d: Dictionary) -> void:
	next_pass = float(d.get("next_pass", Clock.at(3, 6)))
	last_pass = float(d.get("last_pass", -1.0))
	passes = int(d.get("passes", 0))
	if d.has("rng"):
		_rng.state = int(d["rng"])
	in_progress = false
	pending_lanes = []
