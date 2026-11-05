extends Node
## City crews (Part 11). Polish 5 §11: every Monday and Friday — nothing on other days — at the hour
## the grader has always used (drawn once a winter, 4–8 a.m.; a pass begins at the top of the hour
## after it, when on_hour runs it), the city grader drives its route and the city's sidewalk crew
## follows it, clearing every sidewalk box to bare pavement (its snow onto the strip between the
## sidewalk and the street, see Snow.sidewalk_clear) except those the player holds a job on. The
## grader's pass itself is unchanged. While the world is loaded a visible grader and a sidewalk
## plow do the work; during time skips (or without a world) the same operations run as a batch.

signal pass_started(lanes: Array)
signal pass_finished

## Polish 5 §11: the crews' days (Clock.weekday_index: 0 = Monday … 6 = Sunday).
const CREW_DAYS := [0, 4]

var next_pass := 0.0
var last_pass := -1.0
var passes := 0
var in_progress := false
var pending_lanes: Array = []
## Polish 5 §11: the sidewalk boxes the crew still has to do this pass, in the order it does them
## (the grader's route), and what it did with each so far this pass ("cleared" / "skipped").
var crew_pending: Array = []
var crew_log: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var world_handles_passes := false   # set by the game world when a grader NPC exists
var _minute_key := Vector2i(-1, -1)
var _minute := 420.0
var _runs: Array = []


func start_winter() -> void:
	_rng.seed = Game.weather_seed * 3 + Game.year
	# Polish 5 §11: the same two draws as before — the first pass's day (Dec 3 or 4; the days are
	# Mondays and Fridays now) and the grader's time of day, which stays (pass_minute()).
	_rng.randi_range(2, 3)
	_rng.randf_range(4.0, 8.0)
	last_pass = -1.0
	passes = 0
	in_progress = false
	pending_lanes = []
	crew_pending = []
	crew_log = {}
	next_pass = next_crew_time(Clock.minutes)


# -----------------------------------------------------------------------------
# Polish 5 §11: the schedule — Mondays and Fridays at the grader's hour
# -----------------------------------------------------------------------------

## The time of day the crews start (game minutes after midnight): the top of the hour after the
## time the grader has always been given for the winter (a draw of 4–8 a.m. from the winter's
## seed, made the same way as before), which is when the hourly tick has always started its pass.
## Derived, not saved: the same for a save as for the game that made it.
func pass_minute() -> float:
	var key := Vector2i(Game.weather_seed, Game.year)
	if key != _minute_key:
		var r := RandomNumberGenerator.new()
		r.seed = Game.weather_seed * 3 + Game.year
		r.randi_range(2, 3)
		var t := r.randf_range(4.0, 8.0) * 60.0
		_minute = ceilf((t - 0.01) / 60.0) * 60.0
		_minute_key = key
	return _minute


func is_crew_day(day: int) -> bool:
	return Clock.weekday_index(day, Game.year) in CREW_DAYS


## A crew start: a Monday or Friday at the crews' hour.
func is_crew_start(t: float) -> bool:
	var day := int(floor(t / 1440.0))
	return t >= 0.0 and is_crew_day(day) and absf(t - Clock.at(day, 0.0) - pass_minute()) < 0.01


## The first crew start strictly after `after` (game minutes) — from the schedule alone.
func next_crew_time(after: float) -> float:
	var d := maxi(int(floor(after / 1440.0)), 0)
	for k in range(9):
		var t := Clock.at(d + k, 0.0) + pass_minute()
		if t > after + 1e-6 and is_crew_day(d + k):
			return t
	return Clock.at(d + 7, 0.0) + pass_minute()


## When the crews come next, computed from the schedule and the clock now (never a stored date,
## so it can't go stale when the clock is set directly): "Mon 7 a.m." (polish 5 §11; was the
## grader's stored date and time, "Dec 18 07:33").
func next_pass_text() -> String:
	var t := next_crew_time(Clock.minutes)
	return "%s %s" % [Clock.weekday(int(floor(t / 1440.0)), Game.year), Contracts.clock_text(t)]


## The line the TV, the radio and the computer show: "City crews: Mon 7 a.m."
func crew_line() -> String:
	return "City crews: " + next_pass_text()


## Lanes for the next pass, skipping streets the player holds a municipal contract for.
func route_lanes() -> Array:
	var skip := Contracts.contracted_segments()
	var lanes := []
	for seg in Layout.road_segments:
		if seg["id"] in skip:
			continue
		for li in range(seg["lanes"].size()):
			var ln: Dictionary = seg["lanes"][li]
			lanes.append({"a": ln["a"], "b": ln["b"], "push": ln["push"], "segment": seg["id"], "lane": li})
	return lanes


func on_hour(_day: int, _hour: int) -> void:
	if in_progress:
		return
	# Polish 5 §11: a pass more than an hour overdue means the clock was set past it without running
	# through it (tests and screenshots set the time directly; play, sleep and the F1 jumps step
	# through every hour): back on the schedule from now, rather than a pass at an odd hour.
	if next_pass < Clock.minutes - 60.01:
		next_pass = next_crew_time(Clock.minutes - 0.01)
	if Clock.minutes + 0.01 >= next_pass:
		_begin_pass()


func _begin_pass() -> void:
	passes += 1
	last_pass = Clock.minutes
	next_pass = next_crew_time(Clock.minutes)
	var lanes := route_lanes()
	crew_pending = crew_route()
	crew_log = {}
	if world_handles_passes and not Clock.skipping:
		in_progress = true
		pending_lanes = lanes
		pass_started.emit(lanes)
		Notify.push("The city crews are clearing the streets and sidewalks.", Notify.INFO)
		_check_done()
	else:
		run_batch(lanes)


## Batched pass: same lane operation as the NPC, applied at once — then (polish 5 §11) the sidewalk
## crew, after the grader, so the grader's snow never lands on a cleared sidewalk.
func run_batch(lanes: Array) -> void:
	in_progress = false   # the pass ends here (pass_finished once, below)
	Snow.hot_mode = false
	for ln in lanes:
		Snow.grader_lane(ln["a"], ln["b"], ln["push"], 3.4, 0.03, int(Clock.minutes) + passes * 17)
	for id in crew_pending.duplicate():
		clear_sidewalk(id)
	Snow.hot_mode = true
	pending_lanes = []
	crew_pending = []
	Boxes.busy.clear()
	pass_finished.emit()


## Called by the NPC grader when it finishes a lane.
func lane_done(lane: Dictionary) -> void:
	pending_lanes.erase(lane)
	_check_done()


## The pass is over when the grader's lanes and the sidewalk crew's boxes are all done.
func _check_done() -> void:
	if in_progress and pending_lanes.is_empty() and crew_pending.is_empty():
		in_progress = false
		pass_finished.emit()


## Called when the player sleeps while the NPC is mid-route: finish the rest as a batch.
func finish_now() -> void:
	if in_progress:
		run_batch(pending_lanes.duplicate())


# -----------------------------------------------------------------------------
# Polish 5 §11: the sidewalk crew
# -----------------------------------------------------------------------------

## The sidewalk crew's route: every sidewalk box, in the order the grader passes it — for each
## street lane of the grader's route (every road section, including one the grader skips for a
## player's street contract), the sidewalk on the side that lane pushes its snow to, in the
## direction the lane is driven. Each entry: {box, a, b (the sidewalk's centre line through the box,
## in driving order), segment, lane, out (cell step from the sidewalk toward the street)}.
func crew_runs() -> Array:
	if not _runs.is_empty():
		return _runs
	var out := []
	for seg in Layout.road_segments:
		for li in range(seg["lanes"].size()):
			var ln: Dictionary = seg["lanes"][li]
			var a: Vector2 = ln["a"]
			var b: Vector2 = ln["b"]
			var dir := (b - a).normalized()
			var push: Vector2 = ln["push"]
			var length := a.distance_to(b)
			var found := []
			for bx in Boxes.boxes:
				if bx["kind"] != "sidewalk" or bx["dynamic"]:
					continue
				var r: Rect2 = bx["rects"][0]
				var c := r.get_center()
				var off := (c - a).dot(push)
				var s := (c - a).dot(dir)
				if off < 2.0 or off > 7.0 or s < 0.0 or s > length:
					continue
				found.append([s, bx])
			found.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
			for f in found:
				var bx: Dictionary = f[1]
				var r2: Rect2 = bx["rects"][0]
				var c2 := r2.get_center()
				var half := absf((r2.size * 0.5).dot(dir))
				out.append({"box": bx["id"], "a": c2 - dir * half, "b": c2 + dir * half, "segment": seg["id"], "lane": li,
					"out": Vector2i(roundi(-push.x), roundi(-push.y))})
	_runs = out   # the layout is static
	return out


## The sidewalk box ids in the crew's order.
func crew_route() -> Array:
	return crew_runs().map(func(e): return e["box"])


## Toward the street from a sidewalk box (a cell step): away from its lot.
func crew_out(id: String) -> Vector2i:
	for e in crew_runs():
		if e["box"] == id:
			return e["out"]
	return Vector2i(0, 1)


## True when the player holds a job on the box (the crew leaves it to them).
func crew_skips(id: String) -> bool:
	return not Contracts.contract_for_box(id).is_empty()


## The sidewalk crew's work on one box: unless the player has a job on it, every cell of it to bare
## pavement and its snow onto the strip beside it (Snow.sidewalk_clear, volume conserved), and the
## box complete — 100 %, quietly (no flash or chime: the player didn't do it). Returns true when
## the box was cleared, false when it was skipped.
func clear_sidewalk(id: String) -> bool:
	crew_pending.erase(id)
	Boxes.busy.erase(id)
	var b := Boxes.get_box(id)
	var done := false
	if not b.is_empty():
		if crew_skips(id):
			crew_log[id] = "skipped"
		else:
			var o := crew_out(id)
			for r in b["rects"]:
				Snow.sidewalk_clear(r, o)
			Boxes.quiet = true
			Boxes.complete(b)
			Boxes.quiet = false
			crew_log[id] = "cleared"
			done = true
	_check_done()
	return done


func serialize() -> Dictionary:
	return {"next_pass": next_pass, "last_pass": last_pass, "passes": passes, "rng": _rng.state}


func deserialize(d: Dictionary) -> void:
	next_pass = float(d.get("next_pass", -1.0))
	last_pass = float(d.get("last_pass", -1.0))
	passes = int(d.get("passes", 0))
	if d.has("rng"):
		_rng.state = int(d["rng"])
	in_progress = false
	pending_lanes = []
	crew_pending = []
	crew_log = {}
	# Polish 5 §11: a save from before the Monday / Friday schedule (a pass every 3–4 days) — or
	# without one — goes on the schedule from the time it was saved at (Clock and Game load first).
	if not is_crew_start(next_pass):
		next_pass = next_crew_time(Clock.minutes)
