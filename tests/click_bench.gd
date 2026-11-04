extends "res://tests/grind_bench.gd"
## Auto-clicker benchmark (polish 5 §2): LMB, RMB, E and G pressed at a fixed rate through the real
## input map (key / mouse events from the current bindings, half of each period held down), next
## to the grind_bench bot that holds and sweeps, on the player's path box with bare hands.
##   godot --headless --fixed-fps 60 --path . res://tests/click_bench.tscn [-- --secs=30
##   --rates=5,10,20,50 --cap=<presses per second; 0 = no cap> --fps=<frame rate the events are
##   batched at, default 60: 20 hands the engine three frames' presses at once> --trace=<rate>]
## Prints per scenario: the snow removed from the box per second (after everything thrown has
## landed), the snow scooped / pushed per second, presses sent and registered, throws, m³ per
## registered press, and the tools counted before and after the E and G bursts.
## tests/test_polish5.gd (§2) uses the same bots: instantiated as a child of another scene this
## node does nothing on its own.

var lot: Dictionary
var walk_r: Rect2
var stairs_r: Rect2
var start_p := Vector2.ZERO
var into_d := Vector2.ZERO
var snap: Dictionary = {}
var throws := 0
var batch_frames := 1          # events are handed to the engine every this many physics frames
var _queue: Array = []         # [time, action, down] waiting for the next batch


func _ready() -> void:
	if get_tree().current_scene != self:
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	await get_tree().process_frame
	await setup(self)
	if args.has("cap") and "input_max_presses_per_s" in Catalog.balance:
		Catalog.balance.input_max_presses_per_s = float(args["cap"])
	var cap_s := "no cap in this build"
	if "input_max_presses_per_s" in Catalog.balance:
		cap_s = "cap %.1f presses/s" % Catalog.balance.input_max_presses_per_s
	batch_frames = maxi(1, roundi(60.0 / float(args.get("fps", "60"))))
	var secs := float(args.get("secs", "30"))
	var rates: Array = []
	for r in String(args.get("rates", "5,10,20,50")).split(","):
		rates.append(float(r))
	print("click_bench: %s, %d s per run, events batched every %d frame(s); keys: primary %s, secondary %s, interact %s, drop %s" % [cap_s, int(secs), batch_frames,
		Settings.action_label("primary"), Settings.action_label("secondary"), Settings.action_label("interact"), Settings.action_label("drop")])
	print("")
	var sw := await run_sweep(secs)
	_row("LMB hold + sweep (grind_bench bot)", sw)
	var hp := await run_hold_in_place(secs)
	_row("LMB hold in place, release when full", hp)
	for r in rates:
		_row("LMB auto-click %d/s" % int(r), await run_click_primary(r, secs))
	print("")
	_row("RMB hold, walking up the path", await run_push(0.0, secs * 0.5))
	for r in rates:
		_row("RMB auto-click %d/s, walking" % int(r), await run_push(r, secs * 0.5))
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


func _row(label: String, d: Dictionary) -> void:
	var s := "%-40s removed %.4f m3/s  scooped/pushed %.4f m3/s" % [label, d["removed"] / d["secs"], d["moved"] / d["secs"]]
	if d.has("sent"):
		s += "  presses %d sent, %d registered (%.1f/s)" % [d["sent"], d["registered"], d["registered"] / d["secs"]]
	if d.has("throws"):
		s += "  throws %d" % d["throws"]
	if d.get("registered", 0) > 0 and d.has("throws"):
		s += "  %.1f L per press" % (d["moved"] / d["registered"] * 1000.0)
	if d.has("strokes"):
		s += "  strokes %d" % d["strokes"]
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
	world.child_entered_tree.connect(func(n: Node): if n is ThrownSnow: throws += 1)
	snap = Snow.serialize()


## Back to the starting snow, bare hands, nothing in flight, the player at the foot of the path.
func reset() -> void:
	_release_inputs()
	await _settle()
	Snow.deserialize(snap)
	var pl: Player = world.player
	pl.tools.load = 0.0
	pl.tools.load_road = 0.0
	pl.teleport(Vector3(start_p.x, 0.05, start_p.y), atan2(-into_d.x, -into_d.y))
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	await _frames(5)
	throws = 0
	_queue.clear()


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
	return {"removed": v0 - _vol(box_rects_g), "moved": Snow.stat_player_moved - m0, "secs": frames / 60.0, "strokes": strokes}


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


## Hold LMB without sweeping (digging in place), release when the hands are full; the same stance
## as the clicking bot.
func run_hold_in_place(secs: float) -> Dictionary:
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
	while frames < int(secs * 60.0):
		if _aim_empty(tc):
			frames += await _next_spot(pl, ss)
			continue
		Input.action_press("primary")
		var n := 0
		while n < 90 and tc.load < tc._capacity() - 1e-6:
			await get_tree().physics_frame
			n += 1
		Input.action_release("primary")
		await _frames(3)
		frames += n + 3
	await _settle()
	return {"removed": v0 - _vol(box_rects_g), "moved": Snow.stat_player_moved - m0, "secs": frames / 60.0, "throws": throws}


## An auto-clicker on LMB at `rate` presses per second, the bot in the clicking stance (it stops
## clicking while it wades on to the next spot).
func run_click_primary(rate: float, secs: float) -> Dictionary:
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
	while frames < int(secs * 60.0):
		if tc.load <= 0.0 and _aim_empty(tc):
			frames += await _next_spot(pl, ss)
			continue
		_clicker("primary", rate, t, st)
		await get_tree().physics_frame
		frames += 1
		t += 1.0 / 60.0
		if tc._fill_pressed and not was_filling:
			registered += 1
		was_filling = tc._fill_pressed
		if args.get("trace", "") == str(int(rate)) and frames % 30 == 0:
			var pp := Vector2(pl.global_position.x, pl.global_position.z)
			print("TRACE f=%d along=%.2f side=%d load=%.1fL moved=%.3f throws=%d box=%.3f" % [frames, _along(pl), int(ss["side"]), tc.load * 1000.0, Snow.stat_player_moved - m0, throws, _vol(box_rects_g)])
	_release_inputs()
	await _frames(2)
	await _settle()
	return {"removed": v0 - _vol(box_rects_g), "moved": Snow.stat_player_moved - m0, "secs": frames / 60.0,
		"sent": st["sent"], "registered": registered, "throws": throws}


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
