extends Node
## Hand-digging benchmark (polish §5): an automated player clears the path-to-the-house box of
## their own property with bare hands, using the real controls.
##   godot --headless --fixed-fps 60 --path . res://tests/grind_bench.tscn [-- --secs=120 --full=1]
##   (--hands=pass1 runs it with the bare-hand values of the first polish pass, for comparison)
## Prints the snow removed per second of play, the projected time to clear the box (box_completion,
## 90 % since polish 3), and —
## with --full=1 — the measured time until the box completes, plus walking speed before / after.
## Works on builds before the polish pass too (old click-to-dig hands), for the before/after numbers.

var world: Node
var last_load := 0.0
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	await get_tree().process_frame
	if args.get("hands", "") == "pass1":
		# The bare hands as they were after the first polish pass (for before/after numbers).
		var h: ToolData = Catalog.tool(&"hands")
		h.capacity = 0.015
		h.fill_rate = 0.035
		h.bite = 0.15
		h.width = 0.34
	Game.force_input = true
	Game.new_game("fun", 2024)
	Clock.reset(Clock.at(0, 9.0))
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	for i in range(5):
		await get_tree().physics_frame
	Clock.running = false   # no new snow during the measurement
	var lot := Layout.player_lot
	var hi := Layout.house_info(lot)
	var walk: Rect2 = hi["walkway"]
	var stairs: Rect2 = hi["stairs"]
	var box_rects := [walk, stairs, hi["porch"]]
	var vol0 := _vol(box_rects)
	box_rects_g = box_rects
	var pl: Player = world.player
	var tc = pl.tools
	var new_build: bool = "pose_override" in tc
	# Wading speed along the path before clearing.
	var v_before := await _walk_speed(walk)
	# Start at the street end of the walkway, facing the house.
	var into := Vector2(0, lot["dir"])          # inward (toward the house)
	# Start on the sidewalk just short of the walkway (the new bot), or on its first cell (old bot).
	var off := -0.45 if new_build else 0.3
	var start := Vector2(walk.get_center().x, walk.position.y + off if lot["dir"] > 0 else walk.end.y - off)
	pl.teleport(Vector3(start.x, 0.05, start.y), atan2(-into.x, -into.y))
	await _frames(3)
	var secs: float = float(args.get("secs", "120"))
	var full: bool = args.get("full", "0") == "1"
	var frames := 0
	var limit := int((3600.0 if full else secs) * 60.0)
	var t_box := -1.0
	var side := 1.0
	var rate_secs := minf(secs, 120.0)
	var vol_at_rate := -1.0
	var strokes := 0
	var walk_frames := 0
	last_load = 0.0
	var next_log := 1800
	var last_vol := 1e9
	while frames < limit:
		if frames >= int(rate_secs * 60.0) and vol_at_rate < 0.0:
			vol_at_rate = _vol(box_rects)
			if not full:
				break
		if new_build:
			# Walk toward the nearest snow left when it's out of the hands' reach, else scoop it.
			var p0 := Vector2(pl.global_position.x, pl.global_position.z)
			var ns := _nearest_snow(pl, into)
			var to := Vector2(ns.x - p0.x, ns.z - p0.y)
			tracing = frames > int(float(args.get("trace_after", "1e9")) * 60.0)
			if tracing:
				print("TRACE f=%d pos=%s target=%s dist=%.2f load=%.1f L" % [frames, str(pl.global_position.snapped(Vector3.ONE * 0.01)), str(ns.snapped(Vector3.ONE * 0.01)), to.length(), last_load * 1000.0])
			var stuck := p0.distance_to(_last_walk_pos) < 0.01 and _walked_last
			_walked_last = false
			if (to.length() > 1.1 and not stuck) or to.length() < 0.12:
				# Too far: walk to it. Only snow right under you left: walk on past it (or back off).
				if to.length() < 0.12:
					to = -into if (p0 - start).dot(into) > walk.size.y else into
				elif Snow.ground_at(ns.x, ns.z) > pl.global_position.y + 0.25:
					# Up on the porch: go up the steps, not into the porch side.
					var sc: Vector2 = stairs.get_center()
					to = Vector2(sc.x, sc.y + into.y * stairs.size.y) - p0
				pl.set_yaw(atan2(-to.x, -to.y))
				pl.pitch = 0.0
				pl.head.rotation.x = 0.0
				var act := "move_forward"
				_last_walk_pos = p0
				_walked_last = true
				Input.action_press(act)
				await _frames(6)
				Input.action_release(act)
				frames += 6
				walk_frames += 6
			else:
				frames += await _stroke_new(pl, into, side)
				side = -side
				strokes += 1
		else:
			frames += await _stroke_old(pl, into, side)
			side = -side
			strokes += 1
		if args.get("log", "0") == "1" and frames >= next_log:
			next_log += 1800
			var vnow := _vol(box_rects)
			if absf(vnow - last_vol) < 0.002:
				print("STUCK: no progress in 30 s; snow left in the box:")
				_dump(box_rects, pl)
				break
			last_vol = vnow
			var pp := Vector2(pl.global_position.x, pl.global_position.z)
			print("t=%5.0fs strokes=%d box=%.2f m3 walk=%.2f along=%.1f m last_load=%.1f L" % [frames / 60.0, strokes, _vol(box_rects), _vol([walk]), (pp - start).dot(into), last_load * 1000.0])
		# Step forward when the snow just ahead is cleared down.
		var p := Vector2(pl.global_position.x, pl.global_position.z)
		var ahead := p + into * 0.55
		var step := Snow.depth_at(ahead.x, ahead.y) < 0.08 or Snow.depth_at(p.x, p.y) < 0.05 and Snow.depth_at(ahead.x, ahead.y) < 0.2
		if step and not new_build:
			pl.set_yaw(atan2(-into.x, -into.y))
			Input.action_press("move_forward")
			await _frames(6)
			Input.action_release("move_forward")
			frames += 6
			walk_frames += 6
		var bx: Node = get_node_or_null("/root/Boxes")
		if new_build and bx:
			# The clock is stopped here (no snowfall), so measure the box the way the game does
			# every 0.25 s while you stand in it.
			bx.call("measure", bx.call("get_box", bx.call("lot_box", lot, "path")), true)
		if new_build and bx and bx.call("is_complete", bx.call("lot_box", lot, "path")):
			t_box = frames / 60.0
			break
		if (p - start).dot(into) > walk.size.y + stairs.size.y - 0.2 and _vol([walk]) < 0.05:
			# Reached the steps: the stairs and porch are cleared from here (same strokes).
			pass
	if vol_at_rate < 0.0:
		vol_at_rate = _vol(box_rects)
	var removed := vol0 - vol_at_rate
	var rate := removed / rate_secs
	print("")
	print("BUILD: %s" % ("polish pass (sweep-fill hands)" if new_build else "before polish (click-dig hands)"))
	print("path box snow: %.2f m3 (walkway %.1f m2 + stairs + porch)" % [vol0, walk.get_area()])
	print("removed in the first %.0f s of play: %.3f m3  ->  %.4f m3/s" % [rate_secs, removed, rate])
	var need: float = Catalog.balance.box_completion if Catalog.balance else 0.98
	print("projected time to clear %d%% by hand: %.1f min real (%.1f game hours)" % [int(round(need * 100.0)), vol0 * need / maxf(rate, 1e-6) / 60.0, vol0 * need / maxf(rate, 1e-6) / 60.0 * 24.0 / 60.0])
	if full:
		if t_box > 0.0:
			print("MEASURED: the path box completed after %.1f min of bot play (%.1f game hours), %d scoop-and-toss strokes" % [t_box / 60.0, t_box * 0.4 / 60.0, strokes])
			var human := strokes * 1.1 + walk_frames / 60.0
			print("at a human pace (~1.1 s per scoop, turn, toss and turn back): about %.1f min real (%.1f game hours)" % [human / 60.0, human * 0.4 / 60.0])
		else:
			print("MEASURED: not completed within %.0f min" % (frames / 3600.0))
		var v_after := await _walk_speed(walk)
		print("walking along the path: %.2f m/s before, %.2f m/s after clearing" % [v_before, v_after])
	print("wading speed before: %.2f m/s" % v_before)
	# AudioMgr.quit: stop every sound before quitting, so nothing is reported leaked at exit
	# (HANDOFF §13 item 13).
	AudioMgr.quit()


func _vol(rects: Array) -> float:
	var v := 0.0
	for r in rects:
		v += Snow.volume_in_rect(r, 0.01)
	return v


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _walk_speed(walk: Rect2) -> float:
	var pl: Player = world.player
	var lot := Layout.player_lot
	var into := Vector2(0, lot["dir"])
	var a := Vector2(walk.get_center().x, walk.position.y + 0.6 if lot["dir"] > 0 else walk.end.y - 0.6)
	pl.teleport(Vector3(a.x, 0.05, a.y), atan2(-into.x, -into.y))
	await _frames(3)
	var p0 := pl.global_position
	Input.action_press("move_forward")
	await _frames(90)
	Input.action_release("move_forward")
	await _frames(2)
	return Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length() / 1.5


## New controls: look down at the snow ahead, hold LMB and sweep side to side until the hands are
## full, turn to the lawn, release to toss, turn back.
func _stroke_new(pl: Player, into: Vector2, side: float) -> int:
	var tc = pl.tools
	var base := atan2(-into.x, -into.y)
	# Look at the nearest snow left in the box within reach, the way a player aims the crosshair.
	var aim := _nearest_snow(pl, into)
	var eye: Vector3 = pl.fp_cam.global_position
	var to := Vector2(aim.x - eye.x, aim.z - eye.z)
	var yaw0 := atan2(-to.x, -to.y) if to.length() > 0.05 else base
	# Aim a little below the top so the crosshair lands on the snow, not grazing past its edge.
	var aim_y := maxf(Snow.ground_at(aim.x, aim.z), aim.y - 0.2)
	var pitch0 := -atan2(eye.y - aim_y, maxf(to.length(), 0.05))
	pl.set_yaw(yaw0)
	pl.pitch = pitch0
	pl.head.rotation.x = pl.pitch
	Input.action_press("primary")
	var n := 0
	var cap: float = tc._capacity()
	while n < 40 and tc.load < cap - 1e-6:
		pl.set_yaw(yaw0 + 0.3 * sin(n * 0.2))
		await get_tree().physics_frame
		n += 1
		if n == 5 and tracing:
			var ap: Vector2 = tc._aim_point()
			print("   aim=%s depth=%.2f filling=%s pitch=%.0f yaw=%.2f fwd=%s" % [str(ap), Snow.depth_at(ap.x, ap.y), str(tc.filling), rad_to_deg(pl.pitch), pl.yaw, str(pl.forward2())])
	last_load = tc.load
	# Turn to the lawn and toss at about eye level (a little up for distance). If neither side
	# lands well clear of the box (on the porch, say), carry the snow back down the path first.
	var carried := 0
	var best_yaw := base + side * 1.5
	while carried < 150:
		var pp := Vector2(pl.global_position.x, pl.global_position.z)
		var best_c := -INF
		for off in [1.5, -1.5, 1.2, -1.2, 1.9, -1.9]:
			var yy: float = base + float(off) * side
			var c := _toss_clearance(pp, yy)
			if c > best_c + 0.05:
				best_c = c
				best_yaw = yy
		if best_c >= 1.0:
			break
		pl.set_yaw(atan2(into.x, into.y))
		pl.pitch = 0.0
		pl.head.rotation.x = 0.0
		Input.action_press("move_forward")
		await _frames(6)
		Input.action_release("move_forward")
		carried += 6
	pl.set_yaw(best_yaw)
	pl.pitch = deg_to_rad(4.0)
	pl.head.rotation.x = pl.pitch
	await _frames(4)
	Input.action_release("primary")
	await _frames(4)
	return n + 8 + carried


## How far the toss to one side lands from the box (m); negative inside it.
func _toss_clearance(pp: Vector2, yaw: float) -> float:
	var land := pp + Vector2(-sin(yaw), -cos(yaw)) * 1.7
	var best := INF
	for r in box_rects_g:
		var rr: Rect2 = r
		var dx := maxf(maxf(rr.position.x - land.x, land.x - rr.end.x), 0.0)
		var dz := maxf(maxf(rr.position.y - land.y, land.y - rr.end.y), 0.0)
		var d := Vector2(dx, dz).length()
		if rr.has_point(land):
			d = -1.0
		best = minf(best, d)
	return best


var box_rects_g: Array = []
var tracing := false
var _last_walk_pos := Vector2.ZERO
var _walked_last := false


## Nearest point inside the box that still has snow on it and that the hands can reach (not
## right at your feet); snow at your feet only if nothing else is left.
func _nearest_snow(pl: Player, into: Vector2) -> Vector3:
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	var best := Vector3.ZERO
	var best_d := INF
	var near := Vector3.ZERO
	var near_d := INF
	for r in box_rects_g:
		var rr: Rect2 = r
		# The same cells the box measures: those whose centres lie inside the rect.
		for cz in range(roundi(rr.position.y * 4.0), roundi(rr.end.y * 4.0)):
			var z := (cz + 0.5) * 0.25
			for cx in range(roundi(rr.position.x * 4.0), roundi(rr.end.x * 4.0)):
				var x := (cx + 0.5) * 0.25
				if Snow.depth_at(x, z) > 0.011:
					var q := Vector2(x, z)
					var d := q.distance_to(p)
					# Prefer what's ahead (work up the path, then clean up behind).
					var score := d + (0.6 if (q - p).dot(into) < -0.2 else 0.0)
					var hit := Vector3(x, Snow.surface_height(x, z), z)
					if d >= 0.15 and score < best_d:
						best_d = score
						best = hit
					elif d < 0.15 and d < near_d:
						near_d = d
						near = hit
	if best_d < INF:
		return best
	if near_d < INF:
		return near
	var q2 := p + into * 0.9
	return Vector3(q2.x, Snow.surface_height(q2.x, q2.y), q2.y)


## Old controls (before the polish pass): face the lawn and click; each click digs a handful in
## front and tosses it forward, so the bot faces sideways and digs the path cell beside it.
func _stroke_old(pl: Player, into: Vector2, side: float) -> int:
	var base := atan2(-into.x, -into.y)
	pl.set_yaw(base + side * 1.2)
	Input.action_press("primary")
	await _frames(46)
	Input.action_release("primary")
	await _frames(2)
	return 48


func _dump(rects: Array, pl: Player) -> void:
	for r in rects:
		var rr: Rect2 = r
		# The same cells the box measures: those whose centres lie inside the rect.
		for cz in range(roundi(rr.position.y * 4.0), roundi(rr.end.y * 4.0)):
			var z := (cz + 0.5) * 0.25
			for cx in range(roundi(rr.position.x * 4.0), roundi(rr.end.x * 4.0)):
				var x := (cx + 0.5) * 0.25
				var d := Snow.depth_at(x, z)
				if d > 0.011:
					var ci: int = Snow.cell_z(z) * Snow.W + Snow.cell_x(x)
					print("  (%.2f, %.2f) depth %.3f ground %.2f surf %d hold %d  dist %.2f" % [x, z, d, Snow.ground_at(x, z), Snow.surf[ci], Snow.hold[ci], Vector2(x, z).distance_to(Vector2(pl.global_position.x, pl.global_position.z))])
