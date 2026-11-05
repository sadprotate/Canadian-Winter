extends Node
## Contract feasibility bench (polish 5 §10): an automated player clears a typical residential path
## job and a typical driveway job, with the small shovel and with the standard shovel, using the
## real controls (look, hold the primary button to fill, turn, release to throw), and reports the
## time in real minutes and in game hours — at the bot's pace and at a human pace.
##   godot --headless --fixed-fps 60 --path . res://tests/contract_bench.tscn
##     [-- --job=path|driveway|all --tool=small_shovel|standard_shovel|all --state=storm|board
##         --limit=<bot minutes> --log=1]
##   … -- --ease=<days>     the bidding: over <days> simulated boards × 3 seeds, how often a bid at
##                          or a little under the suggested price wins a residential listing (once,
##                          or adjusting when outbid), with the real rivals (Contracts).
##   … -- --pacing=<winters> the reputation projection: a good player (bids at the suggested price on
##                          what they can clear in a day, finishes 95 % of their jobs) through whole
##                          winters with the real board, rivals, awards, due times and gains; prints
##                          when each tier is reached, the jobs per winter, and the listings within
##                          reach after every snowfall.
## "A typical job after a typical storm" (--state=storm, the default): a new game (seed 2024), every
## residential path and driveway cleared on the evening before winter 1's first storm (Dec 4, 8 p.m.),
## then the clock runs through the storm (Dec 5, 21.7 cm) and the city grader's pass to the next
## morning (Dec 6, 7 a.m.) — so each box holds that storm's snow (and the grader's windrow across
## the driveway aprons). The job is the median box of each kind among the residential lots — the
## size of listing the board offers with the starting gear (Contracts.res_cap_m3: residential jobs
## no bigger than balance.listing_res_max_m3 while your best tool is a shovel). --state=board takes
## the boxes as an untouched lot holds them that morning (the whole season's snow): a path the board
## still offers, a driveway it doesn't (too big for a shovel in a day).
## The window for a day's job: 7:00 a.m. to 9:00 p.m. = 14 game hours = 14 × 60 /
## Clock.GAME_MIN_PER_REAL_SEC real seconds (17.5 real minutes at the 30-minute day).

var world: Node
var args := {}
var box_rects_g: Array = []
var _last_walk_pos := Vector2.ZERO
var _walked_last := false
var _into := Vector2.ZERO
var results: Array = []
var _skip := {}
var _fails := {}
var _strokes_now := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	await get_tree().process_frame
	# --set=name:value,… overrides balance values for this run (tuning).
	for kv in str(args.get("set", "")).split(",", false):
		var p := kv.split(":")
		if p.size() == 2:
			var cur = Catalog.balance.get(p[0])
			if cur is PackedFloat32Array:
				Catalog.balance.set(p[0], PackedFloat32Array(Array(p[1].split("/")).map(func(x): return float(x))))
			elif cur is int:
				Catalog.balance.set(p[0], int(p[1]))
			else:
				Catalog.balance.set(p[0], float(p[1]))
	if args.has("ease"):
		_ease(int(args["ease"]))
		AudioMgr.quit()
		return
	if args.has("pacing"):
		_pacing(int(args["pacing"]))
		AudioMgr.quit()
		return
	var jobs := ["path", "driveway"] if args.get("job", "all") == "all" else [args["job"]]
	var tools := ["small_shovel", "standard_shovel"] if args.get("tool", "all") == "all" else [args["tool"]]
	for job in jobs:
		for tool in tools:
			results.append(await _run(job, tool))
	var win_s := 14.0 * 60.0 / Clock.GAME_MIN_PER_REAL_SEC
	print("")
	print("CONTRACT BENCH — state %s; the day's window 7 a.m.–9 p.m. = 14 game h = %.1f real min" % [args.get("state", "storm"), win_s / 60.0])
	print("%-9s %-16s %8s %6s %10s %10s %10s %10s %8s" % ["job", "tool", "m3", "done", "bot min", "bot game h", "human min", "human gh", "fits"])
	for r in results:
		print("%-9s %-16s %8.1f %6s %10.1f %10.1f %10.1f %10.1f %8s" % [r["job"], r["tool"], r["vol"], "yes" if r["done"] else "%d%%" % int(r["pct"]), r["bot_s"] / 60.0,
			r["bot_s"] * Clock.GAME_MIN_PER_REAL_SEC / 60.0, r["human_s"] / 60.0, r["human_s"] * Clock.GAME_MIN_PER_REAL_SEC / 60.0,
			"yes" if r["done"] and r["human_s"] <= win_s else "NO"])
	AudioMgr.quit()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


## Residential lots a listing can name (not the player's, not Gerry's, not vacant).
static func residential_lots() -> Array:
	var out := []
	for lot in Layout.lots:
		if not (lot["vacant"] or lot["is_player"] or lot["is_neighbor"]):
			out.append(lot)
	return out


func _run(job: String, tool: String) -> Dictionary:
	if world and is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	Game.force_input = true
	Game.new_game("fun", 2024)
	Game.flags["mail_read"] = true
	Game.flags["computer_unlocked"] = true
	Game.flags["truck_keys"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	var state: String = args.get("state", "storm")
	Clock.skip(Clock.at(3, 20.0) - Clock.minutes)
	if state == "storm":
		for lot in residential_lots():
			for kind in ["path", "driveway"]:
				var b := Boxes.get_box(Boxes.lot_box(lot, kind))
				for r in b["rects"]:
					Snow.set_rect(r, 0.0)
				Boxes.measure(b, true)
	Clock.skip(Clock.at(5, 7.0) - Clock.minutes)
	# The median box of this kind among the residential lots.
	var cand := []
	for lot in residential_lots():
		var b := Boxes.get_box(Boxes.lot_box(lot, job))
		cand.append([Boxes.snow_volume(b, true), lot])
	cand.sort_custom(func(x, y): return x[0] < y[0])
	var pick: Array = cand[cand.size() / 2]
	var lot: Dictionary = pick[1]
	var box := Boxes.get_box(Boxes.lot_box(lot, job))
	Boxes.measure(box, true)
	print("%s / %s: %s's %s, %.1f m3 (median of %d; %.1f–%.1f m3), %s" % [job, tool, lot["address"], job, pick[0], cand.size(), cand[0][0], cand[-1][0], Clock.format_time(Clock.minutes)])
	Game.slots = [tool, "", "", ""]
	Game.selected = 0
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await _frames(5)
	Clock.running = false   # no new snow during the measurement
	var pl: Player = world.player
	box_rects_g = box["rects"]
	var hi := Layout.house_info(lot)
	var main_r: Rect2 = hi["walkway"] if job == "path" else hi["driveway"]
	_into = Vector2(lot["inward"])
	# Start just inside the street end of the box, facing up it.
	var start := Vector2(main_r.get_center().x, main_r.position.y + 0.3 if lot["dir"] > 0 else main_r.end.y - 0.3)
	pl.teleport(Vector3(start.x, Snow.surface_height(start.x, start.y) + 0.05, start.y), atan2(-_into.x, -_into.y))
	await _frames(3)
	var vol0 := Boxes.snow_volume(box, true)
	_skip.clear()
	_fails.clear()
	_strokes_now = 0
	var limit := int(float(args.get("limit", "45")) * 3600.0)
	var frames := 0
	var strokes := 0
	var walk_frames := 0
	var t_done := -1.0
	var side := 1.0
	var next_log := 3600
	while frames < limit:
		var p0 := Vector2(pl.global_position.x, pl.global_position.z)
		var ns := _nearest_snow(pl)
		var to := Vector2(ns.x - p0.x, ns.z - p0.y)
		var stuck := p0.distance_to(_last_walk_pos) < 0.01 and _walked_last
		_walked_last = false
		if (to.length() > 0.75 and not stuck) or to.length() < 0.12:
			if to.length() < 0.12:
				to = -_into if (p0 - start).dot(_into) > main_r.size.y * 0.5 else _into
			elif Snow.ground_at(ns.x, ns.z) > pl.global_position.y + 0.25 and job == "path":
				var sc: Vector2 = (hi["stairs"] as Rect2).get_center()
				to = Vector2(sc.x, sc.y - _into.y * 0.6) - p0
			pl.set_yaw(atan2(-to.x, -to.y))
			pl.pitch = 0.0
			pl.head.rotation.x = 0.0
			_last_walk_pos = p0
			_walked_last = true
			Input.action_press("move_forward")
			await _frames(6)
			Input.action_release("move_forward")
			frames += 6
			walk_frames += 6
		else:
			if stuck:
				_skip[_cell_key(ns)] = strokes + 120
			var d0 := Snow.depth_at(ns.x, ns.z)
			frames += await _stroke(pl, side, tool)
			side = -side
			strokes += 1
			# A cell the scoop doesn't get at (a sliver against the wall, behind the stairs): leave it
			# for later, so the bot doesn't keep scooping the same spot.
			var k := _cell_key(ns)
			if Snow.depth_at(ns.x, ns.z) > d0 - 0.002:
				_fails[k] = int(_fails.get(k, 0)) + 1
				if int(_fails[k]) >= 3:
					_skip[k] = strokes + 120
					_fails.erase(k)
			else:
				_fails.erase(k)
			_strokes_now = strokes
		Boxes.measure(box, true)
		if box["complete"]:
			t_done = frames / 60.0
			break
		if args.get("log", "0") == "1" and frames >= next_log:
			next_log += 3600
			print("  t=%4.0fs strokes=%d left %.2f m3 (%d %%)" % [frames / 60.0, strokes, Boxes.snow_volume(box, true), int(float(box["progress"]) * 100.0)])
	var bot_s := frames / 60.0
	# At a human pace: ~1.1 s per stroke (fill, turn, throw, turn back) plus the walking, as
	# tests/grind_bench.gd counts it.
	var human_s := strokes * 1.1 + walk_frames / 60.0
	var pct := float(box["progress"]) * 100.0
	print("  %s: %d strokes, %.1f min of bot play (%.1f game h); at a human pace %.1f min (%.1f game h)" % ["done" if t_done > 0.0 else "NOT done (%d %%)" % int(pct), strokes, bot_s / 60.0,
		bot_s * Clock.GAME_MIN_PER_REAL_SEC / 60.0, human_s / 60.0, human_s * Clock.GAME_MIN_PER_REAL_SEC / 60.0])
	Input.action_release("primary")
	return {"job": job, "tool": tool, "vol": vol0, "done": t_done > 0.0, "pct": pct, "bot_s": bot_s, "human_s": human_s, "strokes": strokes, "address": lot["address"]}


static func _cell_key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x * 4.0)), int(floor(p.z * 4.0)))


## Look at the nearest snow left in the box, hold the primary button and sweep until the tool is
## full, then turn to the side that throws the load well clear of the box, and release.
func _stroke(pl: Player, side: float, tool: String) -> int:
	var tc = pl.tools
	var aim := _nearest_snow(pl)
	var eye: Vector3 = pl.fp_cam.global_position
	var to := Vector2(aim.x - eye.x, aim.z - eye.z)
	var base := atan2(-_into.x, -_into.y)
	var yaw0 := atan2(-to.x, -to.y) if to.length() > 0.05 else base
	var aim_y := maxf(Snow.ground_at(aim.x, aim.z), aim.y - 0.2)
	pl.set_yaw(yaw0)
	pl.pitch = -atan2(eye.y - aim_y, maxf(to.length(), 0.05))
	pl.head.rotation.x = pl.pitch
	Input.action_press("primary")
	var n := 0
	var cap: float = tc._capacity()
	while n < 40 and tc.load < cap - 1e-6:
		pl.set_yaw(yaw0 + 0.3 * sin(n * 0.2))
		await get_tree().physics_frame
		n += 1
	# Throw sideways, to whichever side lands farthest clear of the box (where the game's own throw
	# would land: walls stop it, §3); carry it out first if neither does (the head of the driveway
	# against the garage, the porch).
	var carried := 0
	var best_yaw := base + side * PI * 0.5
	pl.pitch = deg_to_rad(4.0)
	pl.head.rotation.x = pl.pitch
	while carried < 150:
		var best_c := -INF
		for off in [1.57, -1.57, 1.2, -1.2, 1.9, -1.9, 2.4, -2.4]:
			var yy: float = base + float(off) * side
			pl.set_yaw(yy)
			var l: Dictionary = tc._landing(tc._throw_dist() * tc._pitch_factor(), tc.data.throw_angle_deg)
			if not l.get("valid", false):
				continue
			var lp: Vector3 = l["pos"]
			var c := _clearance(Vector2(lp.x, lp.z))
			if c > best_c + 0.05:
				best_c = c
				best_yaw = yy
		if best_c >= 0.8:
			break
		pl.set_yaw(atan2(_into.x, _into.y))
		pl.pitch = 0.0
		pl.head.rotation.x = 0.0
		Input.action_press("move_forward")
		await _frames(6)
		Input.action_release("move_forward")
		carried += 6
		pl.pitch = deg_to_rad(4.0)
		pl.head.rotation.x = pl.pitch
	pl.set_yaw(best_yaw)
	pl.pitch = deg_to_rad(4.0)
	pl.head.rotation.x = pl.pitch
	await _frames(4)
	Input.action_release("primary")
	await _frames(4)
	return n + 8 + carried


## How far a point is from the box (m); negative inside it.
func _clearance(land: Vector2) -> float:
	var best := INF
	for r in box_rects_g:
		var rr: Rect2 = r
		if rr.has_point(land):
			return -1.0
		var dx := maxf(maxf(rr.position.x - land.x, land.x - rr.end.x), 0.0)
		var dz := maxf(maxf(rr.position.y - land.y, land.y - rr.end.y), 0.0)
		best = minf(best, Vector2(dx, dz).length())
	return best


## Nearest point inside the box that still has snow on it (the cells the box measures), not right
## at your feet; snow at your feet only if nothing else is left. Work up the box from the street.
func _nearest_snow(pl: Player) -> Vector3:
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	var best := Vector3.ZERO
	var best_d := INF
	var near := Vector3.ZERO
	var near_d := INF
	var res: float = Catalog.balance.contract_residual_depth + 0.001
	for r in box_rects_g:
		var rr: Rect2 = r
		for cz in range(roundi(rr.position.y * 4.0), roundi(rr.end.y * 4.0)):
			var z := (cz + 0.5) * 0.25
			for cx in range(roundi(rr.position.x * 4.0), roundi(rr.end.x * 4.0)):
				var x := (cx + 0.5) * 0.25
				if Snow.depth_at(x, z) > res and int(_skip.get(Vector2i(cx, cz), -1)) < _strokes_now:
					var q := Vector2(x, z)
					var d := q.distance_to(p)
					var score := d + (0.6 if (q - p).dot(_into) < -0.2 else 0.0)
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
	if not _skip.is_empty():
		_skip.clear()
		return _nearest_snow(pl)
	var q2 := p + _into * 0.9
	return Vector3(q2.x, Snow.surface_height(q2.x, q2.y), q2.y)


# -----------------------------------------------------------------------------
# --ease: how often a bid at the suggested price wins
# -----------------------------------------------------------------------------

const EASE_STRATS := [["bid 100 % once", 1.0, false], ["bid 95 % once", 0.95, false], ["bid 90 % once", 0.9, false],
	["bid 100 %, adjust when outbid", 1.0, true]]


func _ease(days: int) -> void:
	var tally := {}
	for st in EASE_STRATS:
		tally[st[0]] = [0, 0]
	var replies := [0, 0]
	for sd in [2024, 7, 99]:
		Game.new_game("fun", sd)
		Clock.running = false
		for d in range(1, days + 1):
			Contracts.listings.clear()
			Clock.minutes = Clock.at(d % 120, 6.0)
			Contracts._generate_listings(d % 120, false)
			var base := Contracts.listings.duplicate(true)
			for st in EASE_STRATS:
				Contracts.listings = base.duplicate(true)
				Contracts._sync_bids()
				var res := _ease_board(float(st[1]), bool(st[2]), replies)
				tally[st[0]][0] += res[0]
				tally[st[0]][1] += res[1]
			Notify.clear()
	print("")
	print("EASE — residential listings at reputation %d, %d boards × 3 seeds (rivals %d–%d per listing, floor %d %%)" % [int(Game.reputation), days,
		Catalog.balance.rival_count_min, Catalog.balance.rival_count_max, int(Catalog.balance.bid_floor_frac * 100.0)])
	for st in EASE_STRATS:
		var t: Array = tally[st[0]]
		print("  %-32s won %4d of %4d = %5.1f %%" % [st[0], t[0], t[1], 100.0 * t[0] / maxf(t[1], 1.0)])
	print("  rival answers to an undercut: %d of %d chances" % [replies[0], replies[1]])


## One board, one way of bidding: the player bids at a seeded time of the day on every open
## residential listing; returns [won, listings].
func _ease_board(f: float, adjust: bool, replies: Array) -> Array:
	var mine := []
	for l in Contracts.listings:
		if Contracts.listing_locked(l) or str(l.get("tier", "")) != "residential":
			continue
		var r := RandomNumberGenerator.new()
		r.seed = hash([int(l["lid"]), "player"])
		var t := r.randf_range(float(l["posted"]) + 30.0, float(l["closes"]) - 120.0)
		mine.append([t, l])
	mine.sort_custom(func(a, b): return a[0] < b[0])
	var close_t := 0.0
	for e in mine:
		var l: Dictionary = e[1]
		Clock.minutes = float(e[0])
		Contracts._rivals_step(Clock.minutes)
		Contracts.place_bid(int(l["lid"]), maxi(int(round(float(l["budget"]) * f)), Contracts.bid_floor(l)))
		close_t = maxf(close_t, float(l["closes"]))
	if adjust and not mine.is_empty():
		var h := float(mine[0][0])
		while h < close_t - 15.0:
			h += 60.0
			Clock.minutes = minf(h, close_t - 15.0)
			Contracts._rivals_step(Clock.minutes)
			for e in mine:
				var l: Dictionary = e[1]
				var st := Contracts.bid_status(l)
				if int(st["mine"]) > 0 and not st["winning"]:
					Contracts.place_bid(int(l["lid"]), maxi(int(st["lowest"]) - 1, Contracts.bid_floor(l)))
	Clock.minutes = close_t
	Contracts._rivals_step(close_t)
	var won := 0
	for e in mine:
		var l: Dictionary = e[1]
		if Contracts.bid_status(l)["winning"]:
			won += 1
		for rv in l["rivals"]:
			replies[1] += int(rv["replies"])
			if int(rv["bid"]) > 0 and int(rv["bid"]) < int(rv["open"]):
				replies[0] += 1
	return [won, mine.size()]


# -----------------------------------------------------------------------------
# --pacing: the reputation projection
# -----------------------------------------------------------------------------

const PACE_DONE := 0.97       # the share of their jobs a good player finishes in time
## …and they keep no more recurring clients than a storm's snow on all of them (25 cm) takes a day
## and a half of their work to clear.
const PACE_STORM_M := 0.25
const PACE_STORM_DAYS := 1.5


## What the player's equipment clears in a day (7 a.m.–9 p.m.), m³.
static func _day_capacity() -> float:
	return Contracts.EQUIP_RATE[Contracts.equipment_capability()] * 14.0 * 60.0 / Clock.GAME_MIN_PER_REAL_SEC


func _pacing(winters: int) -> void:
	Game.force_input = true
	Game.new_game("fun", int(args.get("seed", "2024")))
	Game.set_stage(Game.Stage.COMPLETE)
	Game.slots = ["small_shovel", "", "", ""]
	Clock.running = false
	var tier_at := {}
	var after_snow := []
	var stats := []
	for w in range(winters):
		var done := 0
		var missed := 0
		var visits := 0
		var rep0 := Game.reputation
		var reps := []
		for d in range(0, 121):
			Clock.skip(Clock.at(d, 7.0) - Clock.minutes)
			if Clock.has_ended():
				break
			var t := Contracts.tier_index()
			# A good player gets the equipment their tier calls for: a blower at Commercial, a plow
			# truck at City.
			if t >= 1 and not Game.owns_tool("small_blower"):
				Game.machines.append({"uid": Game.uid(), "tool": "small_blower", "pos": Vector3.ZERO, "yaw": 0.0})
			if t >= 2 and Contracts.equipment_capability() < 3:
				Game.vehicles.append({"uid": Game.uid(), "id": "pickup_plow", "pos": Vector3.ZERO, "yaw": 0.0})
			for k in range(t + 1):
				var key := "%d" % k
				if not tier_at.has(key):
					tier_at[key] = "winter %d, %s" % [Game.year, Clock.date_string(d, true)]
			# Work: the jobs due soonest first, as far as a day's work goes.
			var cap := _day_capacity()
			var todo := []
			for c in Contracts.active:
				if Contracts.hours_left(c) < 40.0 and not c.get("tutorial", false):
					todo.append(c)
			todo.sort_custom(func(a, b): return float(a["due"]) < float(b["due"]))
			for c in todo:
				var vol := 0.0
				for z in c["zones"]:
					vol += Contracts.zone_required(z)
				if vol > cap:
					continue
				var h := hash([int(c["id"]), int(c.get("visits", 0)), "done"])
				if float(h % 1000) / 1000.0 >= float(args.get("done", str(PACE_DONE))):
					continue
				cap -= vol
				var was_visit: bool = c["type"] != "one_time"
				for z in c["zones"]:
					for id in z["boxes"]:
						var b := Boxes.get_box(id)
						for r in b["rects"]:
							Snow.set_rect(r, 0.0)
						Boxes.measure(b, true)
				if was_visit:
					visits += 1
				else:
					done += 1
			# Bids: at the suggested price, on what tomorrow's work leaves room for.
			var room := _day_capacity()
			for c in Contracts.active:
				if Contracts.hours_left(c) < 40.0:
					for z in c["zones"]:
						room -= Contracts.zone_required(z)
			var open_res := 0
			var rec := 0.0
			for c in Contracts.active:
				if c["type"] != "one_time" and c["status"] in ["needs_service", "serviced"]:
					for z in c["zones"]:
						rec += Contracts.zone_area(z) * PACE_STORM_M
			var n_rec := 0
			for c in Contracts.active:
				if c["type"] != "one_time" and c["status"] in ["needs_service", "serviced"]:
					n_rec += 1
			var bids_left := int(args.get("jobs", "1"))
			var rec_max := int(args.get("recurring", "3")) * Game.year
			for l in Contracts.listings:
				if Contracts.listing_locked(l):
					continue
				if str(l.get("tier", "")) == "residential":
					open_res += 1
				var v := float(l.get("now_volume", l["est_volume"]))
				if l["type"] == "one_time" and bids_left <= 0:
					continue
				if l["type"] != "one_time" and n_rec >= rec_max:
					continue
				var l_area := 0.0
				for z in l["zones"]:
					l_area += Contracts.zone_area(z)
				if l["type"] != "one_time" and rec + l_area * PACE_STORM_M > PACE_STORM_DAYS * _day_capacity():
					continue
				if v <= room:
					if Contracts.place_bid(int(l["lid"]), int(l["budget"]))["ok"]:
						room -= v
						if l["type"] != "one_time":
							rec += l_area * PACE_STORM_M
							n_rec += 1
						else:
							bids_left -= 1
			if d % 15 == 0:
				reps.append("%s %.0f" % [Clock.date_string(d, true), Game.reputation])
			if open_res == 0 and _snowed_yesterday(d):
				var why := {"occupied": 0, "complete": 0, "too big": 0}
				var used := Contracts._occupied_targets()
				for lot in Contracts.residential_lots():
					if used.has("lot:%d" % lot["index"]):
						why["occupied"] += 1
					elif Boxes.is_complete(Boxes.lot_box(lot, "path")):
						why["complete"] += 1
					else:
						why["too big"] += 1
				print("  no open residential listing on %s: %s; board %s" % [Clock.date_string(d, true), str(why), str(Contracts.listings.map(func(x): return "%s/%s" % [x["tier"], x["job"]]))])
			if d > 0 and Weather.total_snow_cm >= 0.0 and _snowed_yesterday(d):
				after_snow.append(open_res)
			Notify.clear()
		missed = int(Game.stats.get("missed_deadlines", 0))
		stats.append("winter %d: %d one-time jobs and %d visits done, %d missed; reputation %.1f -> %.1f (%s)" % [Game.year, done, visits, missed, rep0, Game.reputation, Contracts.tier_name(Contracts.tier_index())])
		stats.append("  reputation: " + ", ".join(reps))
		if w + 1 < winters:
			Clock.skip(Clock.at(121, 0.0) - Clock.minutes)
			var ids := []
			for c in Contracts.active:
				if c["type"] != "one_time":
					ids.append(int(c["id"]))
			Contracts.end_winter(ids)
			Game.next_winter()
	print("")
	print("PACING — tiers at %s (%s); gains %.2f + %.3f/m³ (max %.1f, visits ×%.2f); a miss −%d" % [str(Catalog.balance.rep_tier_thresholds), ", ".join(Catalog.balance.rep_tier_names),
		Catalog.balance.rep_gain_base, Catalog.balance.rep_gain_per_m3, Catalog.balance.rep_gain_max, Catalog.balance.rep_visit_factor, int(Catalog.balance.contract_lost_reputation)])
	for k in tier_at.keys():
		print("  %s reached: %s" % [Contracts.tier_name(int(k)), tier_at[k]])
	for l in stats:
		print("  " + l)
	after_snow.sort()
	print("  open residential listings within reach on the morning after a snowfall: min %d, median %d (%d mornings)" % [after_snow[0] if not after_snow.is_empty() else -1,
		after_snow[after_snow.size() / 2] if not after_snow.is_empty() else -1, after_snow.size()])


func _snowed_yesterday(d: int) -> bool:
	for h in range((d - 1) * 24 + 7, d * 24 + 7):
		if Weather.rate[clampi(h, 0, Weather.HOURS - 1)] > 0.01:
			return true
	return false
