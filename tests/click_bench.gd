extends "res://tests/grind_bench.gd"
## Auto-clicker benchmark (polish 5 §2, every tool since polish 6 §8.1): LMB, RMB, E and G pressed at
## a fixed rate through the real input map (key / mouse events from the current bindings, half of
## each period held down), next to the grind_bench bot that holds and sweeps, on the player's path
## box.
##   godot --headless --fixed-fps 60 --path . res://tests/click_bench.tscn [-- --secs=30
##   --rates=5,10,20,50 --tools=hands|all|<id>,<id>… --rhythm=0.6,0.9,1.2 --gap=0.3 --keys=1
##   --rows=sweep,place,rhythm,click,machine,push --recovery=<s> --hold=<s> (grind_bench's overrides)
##   --cap=<presses per second; 0 = no cap> --fps=<frame rate the events are batched at, default 60:
##   20 hands the engine three frames' presses at once> --trace=<rate>
##   --rows=shallow --depths=0.06,0.12,0.25,0.6 (only when named in --rows)
##   --rows=strokes --stroke_depths=0.2,0.4,0.8 --strokes=15 (only when named in --rows)]
## Prints per tool and scenario: the snow removed from the box per second (after everything thrown
## has landed), the snow scooped / pushed per second, presses sent and registered, throws (per
## second and the shortest gap between two), m³ per registered press, what the frame a press
## registers scoops ("bite on press"), and the tools counted before and after the E and G bursts.
## Hands and the shovel-type tools: the grind_bench bot (hold + sweep), holding in place, a human
## rhythm (hold and sweep a set time, turn, release, turn back), LMB clicked in place and clicked
## while sweeping, RMB held or clicked walking up the path. The electric shovel strafes along the
## path facing the lawn and the walk-behind blowers walk up it, LMB held or clicked. `shallow`: one
## held sweep of a hand or shovel-type tool in flat snow of each depth (run_shallow). `strokes`
## (polish 6 §8.2): the grind_bench bot's strokes in flat snow of each depth, what each throw
## carries, how many a minute, and what limited the fill (run_strokes).
## tests/test_polish5.gd (§2) and tests/test_polish6.gd (§8.1) use the same bots: instantiated as a
## child of another scene this node does nothing on its own.

const ALL_TOOLS := ["hands", "small_shovel", "standard_shovel", "wide_pusher", "snow_scraper",
	"large_scraper", "snow_sleigh", "electric_shovel", "small_blower", "large_blower"]

var lot: Dictionary
var walk_r: Rect2
var stairs_r: Rect2
var start_p := Vector2.ZERO
var into_d := Vector2.ZERO
var snap: Dictionary = {}
var throws := 0
var batch_frames := 1          # events are handed to the engine every this many physics frames
var _queue: Array = []         # [time, action, down] waiting for the next batch
## The tool the bots use (polish 6 §8.1): "hands", a slot tool, or a walk-behind blower's id.
var tool := "hands"
var blower: Node = null
var _blower_e: Dictionary = {}
## The run monitor (polish 6 §8.1): registered presses, what their first frame scooped, throw frames.
var _mon := false
var _m_on := false
var _m_moved := 0.0
var _m_reg := 0
var _m_bite := 0.0
var _m_throw_frames: Array = []
## The stroke monitor (polish 6 §8.2, run_strokes): each throw's volume and each fill frame's limit.
var _s82_on := false
var _s82: Dictionary = {}


func _ready() -> void:
	if get_tree().current_scene != self:
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	await get_tree().process_frame
	await setup(self)
	_overrides(args)
	if args.has("cap") and "input_max_presses_per_s" in Catalog.balance:
		Catalog.balance.input_max_presses_per_s = float(args["cap"])
	var cap_s := "no cap in this build"
	if "input_max_presses_per_s" in Catalog.balance:
		cap_s = "cap %.1f presses/s" % Catalog.balance.input_max_presses_per_s
	if "min_scoop_hold_s" in Catalog.balance:
		cap_s += ", min scoop hold %.2f s" % Catalog.balance.min_scoop_hold_s
	batch_frames = maxi(1, roundi(60.0 / float(args.get("fps", "60"))))
	var secs := float(args.get("secs", "30"))
	var rates: Array = []
	for r in String(args.get("rates", "5,10,20,50")).split(","):
		rates.append(float(r))
	var rhythm: Array = []
	for r in String(args.get("rhythm", "0.6,0.9,1.2")).split(","):
		if r != "":
			rhythm.append(float(r))
	var gap := float(args.get("gap", "0.3"))
	var tools: Array = []
	var ts := String(args.get("tools", "hands"))
	for t in (ALL_TOOLS if ts == "all" else Array(ts.split(","))):
		tools.append(String(t))
	print("click_bench: %s, %d s per run, events batched every %d frame(s); keys: primary %s, secondary %s, interact %s, drop %s" % [cap_s, int(secs), batch_frames,
		Settings.action_label("primary"), Settings.action_label("secondary"), Settings.action_label("interact"), Settings.action_label("drop")])
	print("path box: walkway %.2f x %.2f m, %.2f m3 of snow" % [walk_r.size.x, walk_r.size.y, _vol(box_rects_g)])
	for id in tools:
		tool = id
		var d: ToolData = Catalog.tool(StringName(id))
		var rec := "-"
		if "throw_recovery_s" in d:
			rec = "%.2f s" % float(d.get("throw_recovery_s"))
		print("")
		print("== %s (capacity %.0f L, fill rate %.3f m3/s, cycle %.2f s, rate %.3f m3/s, throw recovery %s)" % [id, d.capacity * 1000.0, d.fill_rate, d.cycle_time, d.rate, rec])
		if d.is_shovel_type():
			if _rows(["sweep"]):
				_row("LMB hold + sweep (grind_bench bot)", await run_sweep(secs))
			if _rows(["place"]):
				_row("LMB hold in place, release when full", await run_hold_in_place(secs))
				_row("LMB hold + sweep at the feet, release when full", await run_hold_in_place(secs, true))
			if _rows(["rhythm"]):
				for h in rhythm:
					_row("LMB human rhythm: hold %.1f s, %.1f s between" % [h, gap], await run_rhythm(h, secs, gap))
			if _rows(["click"]):
				for r in rates:
					_row("LMB auto-click %d/s" % int(r), await run_click_primary(r, secs))
				for r in rates:
					_row("LMB auto-click %d/s, sweeping" % int(r), await run_click_primary(r, secs, true))
			if args.has("rows") and _rows(["shallow"]):
				for dp in String(args.get("depths", "0.06,0.12,0.25,0.6")).split(","):
					for w in [0.2, 0.07]:
						var s := await run_shallow(float(dp), w)
						var mk: Dictionary = s["marks"]
						print("LMB held sweep, flat snow %.2f m, sweep %.2f rad/frame: load L @15 %.1f @30 %.1f @45 %.1f @60 %.1f, cells cut %d" % [s["depth"], w,
							mk[15] * 1000.0, mk[30] * 1000.0, mk[45] * 1000.0, mk[60] * 1000.0, s["cells"]])
			if args.has("rows") and _rows(["strokes"]):
				for dp in String(args.get("stroke_depths", "0.2,0.4,0.8")).split(","):
					_strokes_row(await run_strokes(float(dp), int(args.get("strokes", "15"))))
		elif _rows(["machine"]):
			var how := "strafing along the path" if d.kind == ToolData.Kind.ELECTRIC_SHOVEL else "walking up the path"
			_row("LMB hold, %s" % how, await run_machine(0.0, secs * 0.6))
			for r in rates:
				_row("LMB auto-click %d/s, %s" % [int(r), how], await run_machine(r, secs * 0.6))
		if d.uses_slot and _rows(["push"]):
			_row("RMB hold, walking up the path", await run_push(0.0, secs * 0.5))
			for r in rates:
				_row("RMB auto-click %d/s, walking" % int(r), await run_push(r, secs * 0.5))
	tool = "hands"
	if args.get("keys", "1") == "1":
		print("")
		for r in rates:
			var e := await run_tool_presses("interact", r, 100)
			print("E   x100 at %2d/s on a shovel on the ground: registered %d pickups+drops, tools %d -> %d (in slots %d, on the ground %d)" % [int(r), e["changes"], e["tools0"], e["tools1"], e["slots"], e["ground"]])
		for r in rates:
			var g := await run_tool_presses("drop", r, 100)
			print("G   x100 at %2d/s with a shovel in hand: registered %d drops, tools %d -> %d (in slots %d, on the ground %d)" % [int(r), g["changes"], g["tools0"], g["tools1"], g["slots"], g["ground"]])
		for r in rates:
			var eg := await run_tool_presses("both", r, 100)
			print("E+G x100 each at %2d/s, alternating, at the shovel: registered %d changes, tools %d -> %d (in slots %d, on the ground %d)" % [int(r), eg["changes"], eg["tools0"], eg["tools1"], eg["slots"], eg["ground"]])
	AudioMgr.quit()


## --rows=sweep,place,rhythm,click,machine,push (default: all of them).
func _rows(which: Array) -> bool:
	if not args.has("rows"):
		return true
	for w in which:
		if w in String(args["rows"]).split(","):
			return true
	return false


func _row(label: String, d: Dictionary) -> void:
	var s := "%-48s removed %.4f m3/s  scooped/pushed %.4f m3/s" % [label, d["removed"] / d["secs"], d["moved"] / d["secs"]]
	if d.has("sent"):
		s += "  presses %d sent, %d registered (%.1f/s)" % [d["sent"], d["registered"], d["registered"] / d["secs"]]
	elif d.has("registered"):
		s += "  presses %d registered" % d["registered"]
	if d.has("throws"):
		s += "  throws %d (%.2f/s" % [d["throws"], d["throws"] / d["secs"]]
		if d.get("throw_gap", -1.0) >= 0.0:
			s += ", >= %.2f s apart, at most %d in a second" % [d["throw_gap"], d["throws_1s"]]
		s += ")"
	if d.get("registered", 0) > 0 and d.has("throws"):
		s += "  %.1f L per press" % (d["moved"] / d["registered"] * 1000.0)
	if d.has("press_bite") and d.get("registered", 0) > 0:
		s += "  bite on press %.1f L" % (d["press_bite"] / d["registered"] * 1000.0)
	if d.has("strokes"):
		s += "  strokes %d" % d["strokes"]
	if d.get("load_left", 0.0) > 0.0:
		s += "  %.1f L left in the tool (in 'removed')" % (d["load_left"] * 1000.0)
	print(s)


## Load the game the way grind_bench does (Fun, seed 2024, Dec 1 9:00, clock stopped: no snowfall).
func setup(parent: Node) -> void:
	Game.force_input = true
	Game.new_game("fun", 2024)
	Clock.reset(Clock.at(0, 9.0))
	world = load("res://scenes/game.tscn").instantiate()
	parent.add_child(world)
	for i in range(5):
		await get_tree().physics_frame
	Clock.running = false
	lot = Layout.player_lot
	var hi := Layout.house_info(lot)
	walk_r = hi["walkway"]
	stairs_r = hi["stairs"]
	box_rects_g = [walk_r, stairs_r, hi["porch"]]
	into_d = Vector2(0, lot["dir"])
	start_p = Vector2(walk_r.get_center().x, walk_r.position.y - 0.45 if lot["dir"] > 0 else walk_r.end.y + 0.45)
	world.child_entered_tree.connect(_on_child)
	snap = Snow.serialize()


func _on_child(n: Node) -> void:
	if n is ThrownSnow:
		throws += 1
		if _mon:
			_m_throw_frames.append(Engine.get_physics_frames())
		if _s82_on:
			(_s82["vols"] as Array).append((n as ThrownSnow).volume)


## Back to the starting snow, the bench's tool in hand (bare hands by default), nothing in flight,
## the player at the foot of the path.
func reset() -> void:
	_release_inputs()
	await _settle()
	_mon = false
	_drop_blower()
	Snow.deserialize(snap)
	var pl: Player = world.player
	pl.tools.load = 0.0
	pl.tools.load_road = 0.0
	if tool != "hands":
		var d: ToolData = Catalog.tool(StringName(tool))
		Game.carried = ""
		Game.slots = [tool if d.uses_slot else "", "", "", ""]
		Game.select_slot(0)
	pl.teleport(Vector3(start_p.x, 0.05, start_p.y), atan2(-into_d.x, -into_d.y))
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	await _frames(5)
	# Polish 6 §8.1: no throw recovery and no press history (the per-second cap) carried over from
	# the run before.
	if "recovery" in pl.tools:
		pl.tools.set("recovery", 0.0)
	if "_presses" in Settings:
		(Settings.get("_presses") as Dictionary).clear()
	throws = 0
	_queue.clear()


func _drop_blower() -> void:
	if blower == null:
		return
	if is_instance_valid(blower):
		blower.call("release")
		blower.queue_free()
	Game.machines.erase(_blower_e)
	blower = null
	_blower_e = {}


## Wait until everything thrown has landed.
func _settle() -> void:
	for i in range(240):
		var flying := false
		for c in world.get_children():
			if c is ThrownSnow:
				flying = true
		if not flying:
			return
		await get_tree().physics_frame


func _release_inputs() -> void:
	for a in Settings.ACTIONS.keys():
		if Input.is_action_pressed(a):
			_send(a, false)
		Input.action_release(a)


## One real input event for an action's current binding (a key or a mouse button).
func _send(action: String, down: bool) -> void:
	var lst: Array = Settings.bindings.get(action, [])
	if lst.is_empty():
		return
	var e := Settings.decode(String(lst[0]))
	if e is InputEventKey:
		var k: InputEventKey = e
		k.keycode = k.physical_keycode
		k.pressed = down
	elif e is InputEventMouseButton:
		var m: InputEventMouseButton = e
		m.pressed = down
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if (down and m.button_index == MOUSE_BUTTON_LEFT) else 0
		var c := get_viewport().get_visible_rect().size * 0.5
		m.position = c
		m.global_position = c
	Input.parse_input_event(e)


## An auto-clicker: presses at t0 + k / rate, each released half a period later. Call every physics
## frame with the time since the clicker started; events go out in batches (batch_frames).
func _clicker(action: String, rate: float, t: float, state: Dictionary) -> void:
	var period := 1.0 / rate
	while float(state["next"]) <= t + 1e-9:
		_queue.append([float(state["next"]), action, true])
		_queue.append([float(state["next"]) + period * 0.5, action, false])
		state["next"] = float(state["next"]) + period
		state["sent"] = int(state["sent"]) + 1
	if int(state.get("frame", 0)) % batch_frames == 0:
		_queue.sort_custom(func(a, b): return a[0] < b[0])
		while not _queue.is_empty() and float(_queue[0][0]) <= t + 1e-9:
			var ev: Array = _queue.pop_front()
			_send(ev[1], ev[2])
	state["frame"] = int(state.get("frame", 0)) + 1


# -----------------------------------------------------------------------------
# The run monitor (polish 6 §8.1). It runs before the world in each physics frame, so it sees what
# the frame before did.
# -----------------------------------------------------------------------------

## Is the tool working from an accepted press: a scoop under way (hands, shovel-type tools), the
## electric shovel's intake, the blower running.
func _scoop_on() -> bool:
	if blower != null and is_instance_valid(blower):
		return bool(blower.get("running"))
	var tc = world.player.tools
	if tc.data != null and tc.data.kind == ToolData.Kind.ELECTRIC_SHOVEL:
		return tc.filling
	return tc._fill_pressed


func _mon_begin() -> void:
	_m_on = _scoop_on()
	_m_moved = Snow.stat_player_moved
	_m_reg = 0
	_m_bite = 0.0
	_m_throw_frames = []
	_mon = true


func _physics_process(_delta: float) -> void:
	if _s82_on:
		_s82_frame()
	if not _mon:
		return
	var on := _scoop_on()
	var moved := Snow.stat_player_moved
	if on and not _m_on:
		_m_reg += 1
		_m_bite += moved - _m_moved
	_m_on = on
	_m_moved = moved


## Ends the monitor and adds its numbers to a run's result: registered presses (unless the run
## counts its own), the scoop in their first frames, the shortest gap between two throws and the
## most throws in any one second.
func _mon_end(d: Dictionary) -> Dictionary:
	_mon = false
	if not d.has("registered"):
		d["registered"] = _m_reg
	d["press_bite"] = _m_bite
	d["throws"] = throws
	var tps := Engine.physics_ticks_per_second
	var gap := -1
	var most := 0
	var tf := _m_throw_frames
	for k in range(tf.size()):
		if k > 0 and (gap < 0 or int(tf[k]) - int(tf[k - 1]) < gap):
			gap = int(tf[k]) - int(tf[k - 1])
		var n := 0
		for j in range(k, tf.size()):
			if int(tf[j]) - int(tf[k]) < tps:
				n += 1
		most = maxi(most, n)
	d["throw_gap"] = float(gap) / tps if gap >= 0 else -1.0
	d["throws_1s"] = most
	d["throw_frames"] = tf.duplicate()
	return d


# -----------------------------------------------------------------------------
# The bots
# -----------------------------------------------------------------------------

## The grind_bench bot for `secs`: walk to the nearest snow, hold LMB and sweep, turn, toss.
func run_sweep(secs: float) -> Dictionary:
	await reset()
	var pl: Player = world.player
	var v0 := _vol(box_rects_g)
	var m0 := Snow.stat_player_moved
	var frames := 0
	var side := 1.0
	var strokes := 0
	_walked_last = false
	_mon_begin()
	while frames < int(secs * 60.0):
		var p0 := Vector2(pl.global_position.x, pl.global_position.z)
		var ns := _nearest_snow(pl, into_d)
		var to := Vector2(ns.x - p0.x, ns.z - p0.y)
		var stuck := p0.distance_to(_last_walk_pos) < 0.01 and _walked_last
		_walked_last = false
		if (to.length() > 1.1 and not stuck) or to.length() < 0.12:
			if to.length() < 0.12:
				to = -into_d if (p0 - start_p).dot(into_d) > walk_r.size.y else into_d
			elif Snow.ground_at(ns.x, ns.z) > pl.global_position.y + 0.25:
				var sc: Vector2 = stairs_r.get_center()
				to = Vector2(sc.x, sc.y + into_d.y * stairs_r.size.y) - p0
			pl.set_yaw(atan2(-to.x, -to.y))
			pl.pitch = 0.0
			pl.head.rotation.x = 0.0
			_last_walk_pos = p0
			_walked_last = true
			Input.action_press("move_forward")
			await _frames(6)
			Input.action_release("move_forward")
			frames += 6
		else:
			frames += await _stroke_new(pl, into_d, side)
			side = -side
			strokes += 1
	await _settle()
	return _mon_end({"removed": v0 - _vol(box_rects_g), "moved": Snow.stat_player_moved - m0, "secs": frames / 60.0, "strokes": strokes})


## A human's rhythm (polish 6 §8.1) for `secs`: walk to the nearest snow the way the grind bot does;
## aim at it, hold LMB and sweep for `hold_s` (the last 0.15 s of it turning to the lawn), release,
## and wait `gap_s` (turning back) before the next press. It doesn't look at the load.
func run_rhythm(hold_s: float, secs: float, gap_s := 0.3) -> Dictionary:
	await reset()
	var pl: Player = world.player
	var v0 := _vol(box_rects_g)
	var m0 := Snow.stat_player_moved
	var frames := 0
	var side := 1.0
	var strokes := 0
	_walked_last = false
	_mon_begin()
	while frames < int(secs * 60.0):
		var p0 := Vector2(pl.global_position.x, pl.global_position.z)
		var ns := _nearest_snow(pl, into_d)
		var to := Vector2(ns.x - p0.x, ns.z - p0.y)
		var stuck := p0.distance_to(_last_walk_pos) < 0.01 and _walked_last
		_walked_last = false
		if (to.length() > 1.1 and not stuck) or to.length() < 0.12:
			if to.length() < 0.12:
				to = -into_d if (p0 - start_p).dot(into_d) > walk_r.size.y else into_d
			elif Snow.ground_at(ns.x, ns.z) > pl.global_position.y + 0.25:
				var sc: Vector2 = stairs_r.get_center()
				to = Vector2(sc.x, sc.y + into_d.y * stairs_r.size.y) - p0
			pl.set_yaw(atan2(-to.x, -to.y))
			pl.pitch = 0.0
			pl.head.rotation.x = 0.0
			_last_walk_pos = p0
			_walked_last = true
			Input.action_press("move_forward")
			await _frames(6)
			Input.action_release("move_forward")
			frames += 6
		else:
			frames += await _stroke_rhythm(pl, into_d, side, hold_s, gap_s)
			side = -side
			strokes += 1
	await _settle()
	return _mon_end({"removed": v0 - _vol(box_rects_g), "moved": Snow.stat_player_moved - m0, "secs": frames / 60.0, "strokes": strokes})


func _stroke_rhythm(pl: Player, into: Vector2, side: float, hold_s: float, gap_s: float) -> int:
	var base := atan2(-into.x, -into.y)
	var aim := _nearest_snow(pl, into)
	var eye: Vector3 = pl.fp_cam.global_position
	var to := Vector2(aim.x - eye.x, aim.z - eye.z)
	var yaw0 := atan2(-to.x, -to.y) if to.length() > 0.05 else base
	var aim_y := maxf(Snow.ground_at(aim.x, aim.z), aim.y - 0.2)
	pl.set_yaw(yaw0)
	pl.pitch = -atan2(eye.y - aim_y, maxf(to.length(), 0.05))
	pl.head.rotation.x = pl.pitch
	Input.action_press("primary")
	var hold_f := maxi(roundi(hold_s * 60.0), 10)
	var turn_f := 9
	for n in range(hold_f - turn_f):
		pl.set_yaw(yaw0 + 0.3 * sin(n * 0.2))
		await get_tree().physics_frame
	var pp := Vector2(pl.global_position.x, pl.global_position.z)
	var best_yaw := base + side * 1.5
	var best_c := -INF
	for off in [1.5, -1.5, 1.2, -1.2, 1.9, -1.9]:
		var yy: float = base + float(off) * side
		var c := _toss_clearance(pp, yy)
		if c > best_c + 0.05:
			best_c = c
			best_yaw = yy
	pl.set_yaw(best_yaw)
	pl.pitch = deg_to_rad(4.0)
	pl.head.rotation.x = pl.pitch
	await _frames(turn_f)
	Input.action_release("primary")
	var gap_f := roundi(gap_s * 60.0)
	await _frames(gap_f)
	return hold_f + gap_f


## Where the clicking bot stands: on the path, facing the lawn on one side, looking down at the
## snow by its feet (the hands scoop it there and the release tosses it onto the lawn).
func _face_side(pl: Player, side: float) -> void:
	pl.set_yaw(atan2(-into_d.x, -into_d.y) + side * PI * 0.5)
	pl.pitch = deg_to_rad(-72.0)
	pl.head.rotation.x = pl.pitch


## Wade on along the path, `dist` metres further from the foot of the path (no clicking meanwhile).
func _wade_on(pl: Player, dist := 0.35) -> int:
	_release_inputs()
	var a0 := _along(pl)
	pl.set_yaw(atan2(-into_d.x, -into_d.y))
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	Input.action_press("move_forward")
	var n := 0
	while n < 240 and _along(pl) < a0 + dist:
		await get_tree().physics_frame
		n += 1
	Input.action_release("move_forward")
	await _frames(2)
	return n + 2


func _along(pl: Player) -> float:
	return (Vector2(pl.global_position.x, pl.global_position.z) - start_p).dot(into_d)


## No snow left for the hands where the bot is aiming (the cells a scoop at the aim point cuts).
func _aim_empty(tc) -> bool:
	var p: Vector2 = tc._aim_point()
	var fwd: Vector2 = tc.player.forward2()
	for i in Snow.cells_in_obb(p - fwd * tc.data.reach * 0.5, fwd, tc.data.width, tc.data.reach):
		var c := Vector2((float(i % Snow.W) + 0.5) * Snow.CELL, (float(i / Snow.W) + 0.5) * Snow.CELL)
		if Snow.depth_at(c.x, c.y) > 0.04:
			return false
	return true


## The in-place bots: next side or next station when the snow at the aim is gone. Returns frames.
func _next_spot(pl: Player, side_state: Dictionary) -> int:
	_release_inputs()
	var n := 0
	side_state[side_state["side"]] = true
	if side_state.get(-float(side_state["side"]), false):
		n += await _wade_on(pl)
		side_state.erase(1.0)
		side_state.erase(-1.0)
	side_state["side"] = -float(side_state["side"])
	_face_side(pl, side_state["side"])
	await _frames(1)
	return n + 1


## Polish 6 §8.1: the tool is recovering from a throw (no scoop can start yet). False in builds
## without a throw recovery.
func _recovering(tc) -> bool:
	return "recovery" in tc and float(tc.get("recovery")) > 0.0


## Hold LMB without sweeping (digging in place), release when the hands are full; the same stance
## as the clicking bot. `sweep`: sweep the aim across the snow by the feet while holding.
func run_hold_in_place(secs: float, sweep := false) -> Dictionary:
	await reset()
	var pl: Player = world.player
	var tc = pl.tools
	var v0 := _vol(box_rects_g)
	var m0 := Snow.stat_player_moved
	var frames := await _wade_on(pl, 0.9)
	var ss := {"side": 1.0}
	_face_side(pl, 1.0)
	await _frames(1)
	frames += 1
	# Long enough to fill the tool digging in place (90 frames: two bites for bare hands).
	var lim := maxi(90, ceili(tc._capacity() / maxf(tc._fill_rate() * tc.data.cycle_time * 0.4, 1e-4)) * ceili(tc.data.cycle_time * 60.0) + 2)
	_mon_begin()
	while frames < int(secs * 60.0):
		if _aim_empty(tc):
			frames += await _next_spot(pl, ss)
			continue
		var yaw0 := pl.yaw
		Input.action_press("primary")
		# Polish 6 §8.1: held through the throw's recovery, the scoop starts when it ends.
		while _recovering(tc):
			await get_tree().physics_frame
			frames += 1
		var n := 0
		while n < lim and tc.load < tc._capacity() - 1e-6:
			if sweep:
				pl.set_yaw(yaw0 + 0.3 * sin(n * 0.2))
			await get_tree().physics_frame
			n += 1
		pl.set_yaw(yaw0)
		Input.action_release("primary")
		await _frames(3)
		frames += n + 3
	await _settle()
	return _mon_end({"removed": v0 - _vol(box_rects_g), "moved": Snow.stat_player_moved - m0, "secs": frames / 60.0})


## How much a held sweep cuts and where (polish 6 §8.1 review): flat snow `depth` m deep on a 5 x 5 m
## patch of the front lawn, one press held for `frames` frames while the yaw sweeps 0.3 × sin(w ×
## frame). The aim is level, so it rests at the tool's sweep reach and doesn't follow the snow's
## surface: two builds sweep exactly the same path. Returns the load after each frame ("marks"), the
## cells cut (their count and indices) and, in a build with the footprint fallback, its share at the
## start and every cell it cut from; `spend_foot` spends that share after the first frame (the strip
## alone).
## Released afterwards; nothing after that is measured.
func run_shallow(depth: float, w: float, frames := 60, spend_foot := false) -> Dictionary:
	await reset()
	var pl: Player = world.player
	var tc = pl.tools
	var into := Vector2(lot["inward"]).normalized()
	var side := Vector2(into.y, -into.x)
	var c := Layout.lot_to_world(lot, Layout.gu(lot, -10.0), 3.0)
	var r := Rect2(c - Vector2(2.5, 2.5), Vector2(5, 5))
	Snow.set_rect(r, depth)
	pl.teleport(Vector3(c.x, Snow.ground_at(c.x, c.y) + 0.05, c.y))
	pl.set_yaw(atan2(-side.x, -side.y))
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	await _frames(3)
	tc._cut_time.clear()
	if "recovery" in tc:
		tc.set("recovery", 0.0)
	var d0 := {}
	for z in range(ceili(r.position.y * Snow.INV_CELL), floori(r.end.y * Snow.INV_CELL)):
		for x in range(ceili(r.position.x * Snow.INV_CELL), floori(r.end.x * Snow.INV_CELL)):
			d0[Vector2i(x, z)] = Snow.depth_at((x + 0.5) * Snow.CELL, (z + 0.5) * Snow.CELL)
	var base := pl.yaw
	var marks := {}
	var foot := PackedInt32Array()
	var foot_left := -1.0
	Input.action_press("primary")
	for k in range(frames):
		pl.set_yaw(base + 0.3 * sin(k * w))
		await get_tree().physics_frame
		marks[k + 1] = tc.load
		if "_foot_left" in tc:
			if k == 0:
				foot_left = float(tc.get("_foot_left"))
				if spend_foot:
					tc.set("_foot_left", 0.0)
			for fc in (tc.get("_foot_cells") as PackedInt32Array):
				if not foot.has(fc):
					foot.append(fc)
	var cut: Array = []
	for cell in d0.keys():
		if float(d0[cell]) - Snow.depth_at((cell.x + 0.5) * Snow.CELL, (cell.y + 0.5) * Snow.CELL) > 1e-5:
			cut.append(cell.y * Snow.W + cell.x)
	pl.set_yaw(base)
	_release_inputs()
	await _frames(2)
	await _settle()
	return {"depth": depth, "marks": marks, "cells": cut.size(), "cut": cut, "foot": foot, "foot_left": foot_left}


## Polish 6 §8.2: what a stroke carries with the real controls. The grind_bench bot (run_sweep: walk
## to the nearest snow in the path box, hold LMB and sweep until the tool is full or for 40 frames,
## turn to the lawn, release) with the walkway, the sidewalk in front of it and the lawn 2.5 m to
## either side set flat to `depth`, until it has thrown `count` times (or `max_secs`). Returns each
## throw's volume, the strokes and frames, and what limited each frame of filling (_s82_frame).
func run_strokes(depth: float, count: int, max_secs := 60.0) -> Dictionary:
	await reset()
	var pl: Player = world.player
	var tc = pl.tools
	var sb: float = lot["setback"]
	Snow.set_rect(Layout.lot_rect_world(lot, Layout.gu(lot, -4.6), Layout.gu(lot, 1.6), -1.5, sb - 2.4), depth)
	pl.teleport(Vector3(start_p.x, Snow.ground_at(start_p.x, start_p.y) + 0.05, start_p.y), atan2(-into_d.x, -into_d.y))
	await _frames(3)
	tc._cut_time.clear()
	if "recovery" in tc:
		tc.set("recovery", 0.0)
	var frames := 0
	var side := 1.0
	var strokes := 0
	var loads := []
	_walked_last = false
	_s82 = {"prev": tc.load, "was": false, "fill": 0, "cut": 0, "none": 0, "topped": 0, "full": 0, "vols": [], "seq": "", "seqs": [], "relax": [], "chunks": []}
	_s82_on = true
	while (_s82["vols"] as Array).size() < count and frames < int(max_secs * 60.0):
		var p0 := Vector2(pl.global_position.x, pl.global_position.z)
		var ns := _nearest_snow(pl, into_d)
		var to := Vector2(ns.x - p0.x, ns.z - p0.y)
		var stuck := p0.distance_to(_last_walk_pos) < 0.01 and _walked_last
		_walked_last = false
		if (to.length() > 1.1 and not stuck) or to.length() < 0.12:
			if to.length() < 0.12:
				to = -into_d if (p0 - start_p).dot(into_d) > walk_r.size.y else into_d
			elif Snow.ground_at(ns.x, ns.z) > pl.global_position.y + 0.25:
				var sc: Vector2 = stairs_r.get_center()
				to = Vector2(sc.x, sc.y + into_d.y * stairs_r.size.y) - p0
			pl.set_yaw(atan2(-to.x, -to.y))
			pl.pitch = 0.0
			pl.head.rotation.x = 0.0
			_last_walk_pos = p0
			_walked_last = true
			Input.action_press("move_forward")
			await _frames(6)
			Input.action_release("move_forward")
			frames += 6
		else:
			frames += await _stroke_new(pl, into_d, side)
			loads.append(last_load)
			side = -side
			strokes += 1
	_s82_on = false
	await _settle()
	var out := _s82.duplicate()
	out["depth"] = depth
	out["frames"] = frames
	out["strokes"] = strokes
	out["loads"] = loads
	out["cap"] = tc._capacity()
	out["fill_rate"] = tc._fill_rate()
	return out


## run_strokes' per-frame monitor (before the world in each physics frame, so it sees what the frame
## before did): a frame that was filling took the whole fill_rate × dt ("fill"), less ("cut": the
## strip the sweep crossed, bite × width × sweep length, came up short), nothing ("none"), or topped
## the tool up ("topped"); "full" counts frames held with the tool already full.
func _s82_frame() -> void:
	var tc = world.player.tools
	# The game's own per-frame counters: relaxation µs (budget relax_usec) and chunk mesh updates
	# (budget chunk_budget).
	var sr: Node = world.get("snow_renderer")
	if sr:
		(_s82["relax"] as Array).append(int(sr.get("relax_us_last")))
		(_s82["chunks"] as Array).append(int(sr.get("updates_last_frame")))
	var ld: float = tc.load
	var prev: float = _s82["prev"]
	if bool(_s82["was"]) and ld >= prev - 1e-9:
		var cap: float = tc._capacity()
		var want: float = tc._fill_rate() / float(Engine.physics_ticks_per_second)
		var dl := ld - prev
		var key := "none"
		if prev >= cap - 1e-6:
			key = "full"
		elif ld >= cap - 1e-6 and dl > 1e-9:
			key = "topped"
		elif dl >= want * 0.98:
			key = "fill"
		elif dl > 1e-9:
			key = "cut"
		_s82[key] = int(_s82[key]) + 1
		_s82["seq"] = str(_s82["seq"]) + {"fill": "F", "cut": "c", "none": ".", "topped": "T", "full": "="}[key]
		if args.has("trace_strokes") and (_s82["seqs"] as Array).size() == int(args["trace_strokes"]):
			var ap: Vector2 = tc._aim_point()
			var pp: Vector3 = world.player.global_position
			print("  TRACE %s dl %.1f L load %.1f L aim (%.2f, %.2f) depth %.3f, %.2f m from the feet; feet (%.2f, %.2f) depth %.2f" % [key, dl * 1000.0, ld * 1000.0,
				ap.x, ap.y, Snow.depth_at(ap.x, ap.y), ap.distance_to(Vector2(pp.x, pp.z)), pp.x, pp.z, Snow.depth_at(pp.x, pp.z)])
	if not bool(tc.filling) and str(_s82["seq"]) != "":
		(_s82["seqs"] as Array).append(str(_s82["seq"]))
		_s82["seq"] = ""
	_s82["prev"] = ld
	_s82["was"] = bool(tc.filling)


func _strokes_row(s: Dictionary) -> void:
	var vols: Array = s["vols"]
	var n := vols.size()
	if n == 0:
		print("strokes, flat snow %.2f m: no throws in %.1f s" % [s["depth"], s["frames"] / 60.0])
		return
	var sorted := vols.duplicate()
	sorted.sort()
	var total := 0.0
	var full := 0
	for v in vols:
		total += float(v)
		if float(v) >= float(s["cap"]) * 0.98:
			full += 1
	var fr := int(s["fill"]) + int(s["cut"]) + int(s["none"]) + int(s["topped"])
	var pct := func(k: String) -> float: return 100.0 * float(s[k]) / maxf(float(fr), 1.0)
	var mins := float(s["frames"]) / 3600.0
	print("strokes, flat snow %.2f m: %d throws in %.1f s (%.1f a minute), %d bot strokes; per throw %.1f L mean, median %.1f, %.1f–%.1f; %d of %d full (capacity %.0f L); %.4f m3/s thrown; fill frames %d: fill rate %.0f %%, cut %.0f %%, nothing %.0f %%, topped up %.0f %%; held full %d frames" % [
		s["depth"], n, s["frames"] / 60.0, n / maxf(mins, 1e-6), s["strokes"], total / n * 1000.0, float(sorted[n >> 1]) * 1000.0,
		float(sorted[0]) * 1000.0, float(sorted[n - 1]) * 1000.0, full, n, float(s["cap"]) * 1000.0, total / maxf(float(s["frames"]) / 60.0, 1e-6),
		fr, pct.call("fill"), pct.call("cut"), pct.call("none"), pct.call("topped"), s["full"]])
	var rl: Array = (s["relax"] as Array).duplicate()
	var ch: Array = (s["chunks"] as Array).duplicate()
	if not rl.is_empty():
		rl.sort()
		ch.sort()
		var qt := func(a: Array, f: float) -> int: return int(a[mini(int(f * a.size()), a.size() - 1)])
		print("  counters: relaxation µs p50 %d / p95 %d / max %d (budget %d); chunk updates a frame p95 %d / max %d (budget %d)" % [qt.call(rl, 0.5), qt.call(rl, 0.95), rl[rl.size() - 1],
			int(world.snow_renderer.relax_usec), qt.call(ch, 0.95), ch[ch.size() - 1], int(world.snow_renderer.chunk_budget)])
	if args.get("log_strokes", "0") == "1":
		for q in s["seqs"]:
			print("  frames: " + str(q))


## An auto-clicker on LMB at `rate` presses per second, the bot in the clicking stance (it stops
## clicking while it wades on to the next spot). `sweep`: it sweeps the aim across the snow by its
## feet while it clicks.
func run_click_primary(rate: float, secs: float, sweep := false) -> Dictionary:
	await reset()
	var pl: Player = world.player
	var tc = pl.tools
	var v0 := _vol(box_rects_g)
	var m0 := Snow.stat_player_moved
	var st := {"next": 0.0, "sent": 0}
	var t := 0.0
	var registered := 0
	var was_filling := false
	var frames := await _wade_on(pl, 0.9)
	var ss := {"side": 1.0}
	_face_side(pl, 1.0)
	await _frames(1)
	frames += 1
	var yaw0 := pl.yaw
	var k := 0
	_mon_begin()
	while frames < int(secs * 60.0):
		if tc.load <= 0.0 and _aim_empty(tc):
			frames += await _next_spot(pl, ss)
			yaw0 = pl.yaw
			continue
		if sweep:
			pl.set_yaw(yaw0 + 0.3 * sin(k * 0.2))
			k += 1
		_clicker("primary", rate, t, st)
		await get_tree().physics_frame
		frames += 1
		t += 1.0 / 60.0
		if tc._fill_pressed and not was_filling:
			registered += 1
		was_filling = tc._fill_pressed
		if args.get("trace", "") == str(int(rate)) and frames % 30 == 0:
			print("TRACE f=%d along=%.2f side=%d load=%.1fL moved=%.3f throws=%d box=%.3f" % [frames, _along(pl), int(ss["side"]), tc.load * 1000.0, Snow.stat_player_moved - m0, throws, _vol(box_rects_g)])
	_release_inputs()
	await _frames(2)
	await _settle()
	return _mon_end({"removed": v0 - _vol(box_rects_g), "moved": Snow.stat_player_moved - m0, "secs": frames / 60.0,
		"sent": st["sent"], "registered": registered, "load_left": tc.load})


## Walk up the path pushing: RMB held (rate 0) or auto-clicked at `rate`.
func run_push(rate: float, secs: float) -> Dictionary:
	await reset()
	var pl: Player = world.player
	var tc = pl.tools
	var v0 := _vol(box_rects_g)
	var m0 := Snow.stat_player_moved
	var p0 := pl.global_position
	var st := {"next": 0.0, "sent": 0}
	var t := 0.0
	var registered := 0
	var was := false
	pl.set_yaw(atan2(-into_d.x, -into_d.y))
	Input.action_press("move_forward")
	if rate <= 0.0:
		_send("secondary", true)
	for f in range(int(secs * 60.0)):
		if rate > 0.0:
			_clicker("secondary", rate, t, st)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if tc.pushing and not was:
			registered += 1
		was = tc.pushing
	Input.action_release("move_forward")
	_release_inputs()
	await _frames(2)
	var d := {"removed": v0 - _vol(box_rects_g), "moved": Snow.stat_player_moved - m0, "secs": secs,
		"walked": Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length()}
	if rate > 0.0:
		d["sent"] = st["sent"]
		d["registered"] = registered
	return d


## The machines (polish 6 §8.1), LMB held (rate 0) or auto-clicked at `rate` for `secs`. The
## electric shovel throws where you face, so it faces the lawn from the far side of the path and
## strafes up it; a walk-behind blower is grabbed at the foot of the path and walked up it, its
## chute turned to the side.
func run_machine(rate: float, secs: float) -> Dictionary:
	await reset()
	var pl: Player = world.player
	var walk_key := "move_forward"
	if tool == "electric_shovel":
		var r := Vector2(-into_d.y, into_d.x)
		var w := absf(walk_r.size.x * r.x) + absf(walk_r.size.y * r.y)
		var p := start_p + into_d * 0.6 - r * (w * 0.5 - 0.15)
		pl.teleport(Vector3(p.x, 0.05, p.y), atan2(-r.x, -r.y))
		pl.pitch = deg_to_rad(-30.0)
		pl.head.rotation.x = pl.pitch
		var f := pl.forward2()
		walk_key = "move_right" if Vector2(-f.y, f.x).dot(into_d) > 0.0 else "move_left"
	else:
		var q := start_p + into_d * 1.05
		_blower_e = {"uid": Game.uid(), "tool": tool, "pos": Vector3(q.x, 0.0, q.y), "yaw": pl.yaw}
		Game.machines.append(_blower_e)
		blower = world.spawn_machine_node(_blower_e)
		await _frames(2)
		blower.call("interact", pl)
	await _frames(3)
	var v0 := _vol(box_rects_g)
	var m0 := Snow.stat_player_moved
	var p0 := pl.global_position
	var st := {"next": 0.0, "sent": 0}
	var t := 0.0
	_mon_begin()
	Input.action_press(walk_key)
	if rate <= 0.0:
		_send("primary", true)
	for f in range(int(secs * 60.0)):
		if rate > 0.0:
			_clicker("primary", rate, t, st)
		await get_tree().physics_frame
		t += 1.0 / 60.0
	Input.action_release(walk_key)
	_release_inputs()
	# What the chute still holds goes out on its next throw (electric shovel), or stays in the
	# blower for its next run (counted as removed: it's out of the box).
	await _frames(30)
	await _settle()
	var d := {"removed": v0 - _vol(box_rects_g), "moved": Snow.stat_player_moved - m0, "secs": secs,
		"walked": Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length()}
	if rate > 0.0:
		d["sent"] = st["sent"]
	d = _mon_end(d)
	_drop_blower()
	return d


## Every tool the player has: in the slots, carried, on the ground (items + nodes), on the rack.
func tool_count() -> Dictionary:
	var slots := 0
	for s in Game.slots:
		if s != "":
			slots += 1
	if Game.carried != "":
		slots += 1
	var nodes := 0
	for c in world.objects.get_children():
		if c is ToolItem and not (c as ToolItem).is_crate() and not c.is_queued_for_deletion():
			nodes += 1
	var items := 0
	for it in Game.items:
		if it.has("tool") and not it.has("crate"):
			items += 1
	return {"slots": slots, "ground": nodes, "items": items, "rack": Game.rack.size(), "total": slots + nodes + Game.rack.size()}


## `count` presses of E ("interact"), G ("drop") or both alternating ("both"), at `rate` per second
## each, standing on cleared ground in front of a standard shovel (E) or holding it (G).
func run_tool_presses(which: String, rate: float, count: int) -> Dictionary:
	await reset()
	var pl: Player = world.player
	var p := start_p - into_d * 2.0          # on the sidewalk, cleared
	Snow.set_rect(Rect2(p - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), 0.0)
	pl.teleport(Vector3(p.x, 0.05, p.y), atan2(-into_d.x, -into_d.y))
	Game.slots = ["", "", "", ""]
	Game.carried = ""
	Game.selected = 0
	if which == "drop":
		Game.add_tool("standard_shovel")
	else:
		var q := p + into_d * 0.8
		world.spawn_tool_item("standard_shovel", Vector3(q.x, 0, q.y), 0.0)
	pl.pitch = deg_to_rad(-40.0)
	pl.head.rotation.x = pl.pitch
	await _frames(6)
	var c0 := tool_count()
	var st := {"next": 0.0, "sent": 0}
	var st2 := {"next": 0.5 / rate, "sent": 0}
	var t := 0.0
	var changes := 0
	var had: bool = Game.slots[0] != ""
	while int(st["sent"]) < count or (which == "both" and int(st2["sent"]) < count):
		if which == "both":
			if int(st["sent"]) < count:
				_clicker("interact", rate, t, st)
			if int(st2["sent"]) < count:
				_clicker("drop", rate, t, st2)
		else:
			_clicker(which, rate, t, st)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var has: bool = Game.slots[0] != ""
		if has != had:
			changes += 1
		had = has
	_release_inputs()
	await _frames(6)
	var c1 := tool_count()
	# Leave nothing behind for the next run.
	for c in world.objects.get_children():
		if c is ToolItem and String((c as ToolItem).tool_id) == "standard_shovel":
			Game.items.erase((c as ToolItem).entry)
			c.queue_free()
	Game.slots = ["", "", "", ""]
	Game.carried = ""
	await _frames(2)
	return {"changes": changes, "tools0": c0["total"], "tools1": c1["total"], "slots": c1["slots"], "ground": c1["ground"], "items": c1["items"]}
