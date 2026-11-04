extends Node
## CPU frame-time benchmark of the game's script-side systems (Part 0.4 / 27.4).
## Run: godot --headless --fixed-fps 60 --path . res://tests/perf.tscn
## Scenarios: the main menu background, idle in the yard, indoors in the living room (polish 4:
## the computer screen and the framed photo in view, the screen re-rendering on each game minute),
## shovelling during a blizzard (snow chunk syncs + relaxation + throws), a plow truck pushing a
## long berm, the 4 m deep map under a major event (25 cm/h, and polish 4: the highest hourly
## rate any major event reaches after the storm-onset reshaping) and a time skip. Reports avg /
## p95 / max of the wall-clock CPU frame time (scripts + physics; rendering is a dummy in headless
## mode). Polish 5 §9 (last, in a fresh world): fast-forward at 2× and 10× on foot in the yard in
## clear weather, light snow, a storm's heaviest hour and a major event's peak, measured uncapped
## and then as the game runs them (with the caps), a big pile settling, and the grader's pass away
## from the player and from the yard; the caps are printed.
##   -- --only=ff   runs just the world, idle outdoors and the fast-forward scenarios (quicker repeats)
##   -- --ff_sweep=10:0.5,1,2.5  instead measures one speed (uncapped) at each snowfall rate (cm/h),
##      on the normal map and on the 4 m deep map — how Clock.SPEED_CAPS were set

## Polish 4 §1: the highest hourly snowfall of any major event (seed 2024 and 20 other seeds,
## winters 1–5) once storms open with a lead-in (pass 3: 52.2 cm/h). Measured at the game's own
## speed: at Clock.GAME_MIN_PER_REAL_SEC (0.8 game min per real second since polish 5 §9; 0.4
## before) that is 1.46 cm of snow per real second (0.73 before), while the stress cases at 25 cm/h
## drop 3.3 cm per real second.
const PEAK_MAJOR_CM_H := 109.6
## The stress cases ("exaggerated blizzard", "4 m deep map + major event") run the clock at this many
## game minutes per real second — 20× the game's speed before polish 5 §9, so they stay the same
## load as in earlier passes (the debug time scale is derived from the clock's rate).
const STRESS_GAME_MIN_PER_S := 8.0
## Polish 5 §9: the fast-forward scenarios' snowfall (cm per game hour): clear weather, a light
## snowfall's steady hour (light snowfalls drop 2.5–5 cm in 3–9 h), a storm's heaviest hour (storms
## peak at 2.5 cm/h on average, 5.5 at most) and a major event's peak.
const FF_LIGHT_CM_H := 0.9
const FF_STORM_CM_H := 5.5

var world: Node
var menu: Node
var samples: Array = []
var only := ""
var sweep := ""


static func _stress_scale() -> float:
	return STRESS_GAME_MIN_PER_S / Clock.GAME_MIN_PER_REAL_SEC


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--ff_sweep="):
			sweep = a.substr(11)
			only = "ff"
	# Headless runs in low-processor mode (sleeps ~7 ms per frame); measure real work instead.
	OS.low_processor_usage_mode = false
	await get_tree().process_frame
	if only != "ff":
		# Polish 3 §1: the main menu's live background (camera path, falling snow, figures).
		var mt := Time.get_ticks_msec()
		menu = load("res://scenes/main_menu.tscn").instantiate()
		add_child(menu)
		while not bool(menu.get("_built")):
			await get_tree().process_frame
		print("Menu background build: %d ms" % (Time.get_ticks_msec() - mt))
		await _measure("main menu", 240, func(_i): pass)
		menu.queue_free()
		await get_tree().process_frame
		menu = null
	Game.force_input = true
	Game.new_game("fun", 77)
	Clock.reset(Clock.at(1, 10.0))
	var t0 := Time.get_ticks_msec()
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	print("World load: %d ms" % (Time.get_ticks_msec() - t0))
	var pl: Player = world.player
	var lot := Layout.player_lot
	var p := Layout.lot_to_world(lot, Layout.gu(lot, -9.0), 5.0)
	pl.teleport(Vector3(p.x, 0.05, p.y), PI)
	await _measure("idle outdoors", 240, func(_i): pass)
	if sweep != "":
		await _ff_sweep(pl, p)
		AudioMgr.quit()
		return
	if only == "ff":
		await _fast_forward(pl, p)
		AudioMgr.quit()
		return
	# Polish 4: indoors, the desk with the computer screen and the photo by the door in view.
	var L := HouseBuilder.lot_transform(lot)
	var inside := L * Vector3(-6.0, InteriorBuilder.FY + 0.05, 17.5)
	var aim := L * Vector3(-1.0, InteriorBuilder.FY + 1.4, 13.5)
	pl.teleport(inside, atan2(-(aim.x - inside.x), -(aim.z - inside.z)))
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	Clock.running = true
	await _measure("indoors (screen + photo)", 300, func(_i): pass)
	print("  indoors: in the house %s, screen re-renders %d" % [str(pl.in_player_house), int(world.interior["screen"].renders) if world.get("interior") and world.interior.has("screen") else -1])
	pl.teleport(Vector3(p.x, 0.05, p.y), PI)
	await get_tree().process_frame
	Weather.force(Weather.C.BLIZZARD, 10.0, 12.0)   # exaggerated snowfall rate: worst case syncs
	Clock.time_scale = _stress_scale()
	Game.add_tool("standard_shovel")
	pl.pitch = deg_to_rad(-40.0)
	pl.head.rotation.x = pl.pitch
	var base_yaw := pl.yaw
	await _measure("blizzard + shovelling", 600, func(i):
		# Hold and sweep to fill, turn, release to throw (the polish-pass controls).
		var ph: int = int(i) % 50
		if ph == 0:
			Input.action_press("primary")
		if ph < 32:
			pl.set_yaw(base_yaw + 0.4 * sin(ph * 0.2))
		elif ph == 32:
			pl.set_yaw(base_yaw + 1.3)
		elif ph == 36:
			Input.action_release("primary")
		elif ph == 44:
			pl.set_yaw(base_yaw))
	Input.action_release("primary")
	Game.select_slot(1)
	await _measure("hand push (RMB) in deep snow", 300, func(i):
		if i == 0:
			Input.action_press("secondary")
			Input.action_press("move_forward")
		if i % 60 == 59:
			pl.set_yaw(pl.yaw + PI))
	Input.action_release("secondary")
	Input.action_release("move_forward")
	Clock.time_scale = 1.0
	Weather.override_cond = -1
	var e := {"uid": Game.uid(), "id": "plow_truck", "pos": Vector3(10, 0, 85.0), "yaw": -PI * 0.5, "snow": 0.0}
	Game.vehicles.append(e)
	var v: Vehicle = world.spawn_vehicle_node(e)
	await get_tree().physics_frame
	v.enter_vehicle(pl)
	Snow.set_rect(Rect2(0, 79, 192, 8), 0.25)
	v._toggle_tool()
	Input.action_press("veh_accelerate")
	await _measure("plow truck pushing a berm", 480, func(_i): pass)
	Input.action_release("veh_accelerate")
	# Late winter: 4 m of snow over the whole map (near the lamp-height ceiling) and a major event.
	Snow.add_layer_rect(Rect2(0, 0, Layout.MAP_W, Layout.MAP_D), 4.0)
	Snow.set_rect(Rect2(0, 79, 192, 8), 0.3)
	v.global_position = Vector3(10, 0, 83.0)
	Weather.force(Weather.C.BLIZZARD, 4.0, 25.0)
	Clock.time_scale = _stress_scale()
	Input.action_press("veh_accelerate")
	await _measure("4 m deep map + major event", 480, func(_i): pass)
	# Polish 4: the same, at the highest hourly rate a major event now reaches, at the game's own
	# speed (the stress scenario above drops snow ~2× faster per real second than this does).
	Clock.time_scale = 1.0
	Weather.force(Weather.C.BLIZZARD, 4.0, PEAK_MAJOR_CM_H)
	await _measure("4 m map + peak major (1x)", 480, func(_i): pass)
	Input.action_release("veh_accelerate")
	Clock.time_scale = 1.0
	Weather.override_cond = -1
	v.exit_vehicle()
	var ts := Time.get_ticks_msec()
	Clock.skip(3 * 1440.0)
	print("3-day time skip: %d ms" % (Time.get_ticks_msec() - ts))
	var ss := Time.get_ticks_msec()
	Saves.save_game()
	@warning_ignore("integer_division")
	print("Save: %d ms (file %d KB)" % [Time.get_ticks_msec() - ss, FileAccess.get_file_as_bytes(Saves.path_for("fun")).size() / 1024])
	var ls := Time.get_ticks_msec()
	Saves.load_game("fun")
	print("Load: %d ms" % (Time.get_ticks_msec() - ls))
	Saves.delete_save("fun")
	# Polish 5 §9: fast-forward, last and in a fresh world on the normal map (so every scenario
	# above runs as in earlier passes).
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Game.new_game("fun", 77)
	Clock.reset(Clock.at(1, 10.0))
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	pl = world.player
	await _measure("idle outdoors (fresh world)", 120, func(_i): pass)
	await _fast_forward(pl, p)
	# AudioMgr.quit: stop every sound before quitting, so nothing is reported leaked at exit
	# (HANDOFF §13 item 13).
	AudioMgr.quit()


## Polish 5 §9: fast-forward on foot in the yard. Each condition at 2× and 10× uncapped (what the
## speed itself costs), then as the game runs it (Clock.SPEED_CAPS applied); then 10× in light snow
## with the grader driving its route (held at 1× while it is within reach of the player).
func _fast_forward(pl: Player, p: Vector2) -> void:
	pl.teleport(Vector3(p.x, 0.05, p.y), PI)
	Clock.time_scale = 1.0
	await get_tree().process_frame
	var caps := []
	for c in Clock.SPEED_CAPS:
		caps.append("%d× from %.1f cm/h (%s)" % [int(c["max"]), float(c["cm_h"]), c["why"]])
	print("Fast-forward caps: %s" % ("none" if caps.is_empty() else ", ".join(caps)))
	for cond in [["clear", Weather.C.CLEAR, 0.0], ["light snow", Weather.C.LIGHT, FF_LIGHT_CM_H], ["storm peak", Weather.C.HEAVY, FF_STORM_CM_H], ["major peak", Weather.C.BLIZZARD, PEAK_MAJOR_CM_H]]:
		for sp in [2, 10]:
			for capped in [false, true]:
				Weather.force(int(cond[1]), 6.0, float(cond[2]))
				Clock.caps_on = capped
				var ok := Clock.set_speed(sp)
				var lbl := "%d× %s%s" % [sp, cond[0], " (capped)" if capped else ""]
				var subs := [0]
				await _measure(lbl, 300, func(_i):
					if Clock.speed != sp:
						Clock.set_speed(sp)
					subs[0] += Clock.substeps_last_frame)
				print("  %s: speed set %s, ran at %d× (%.1f substeps a frame)" % [lbl, ok, Clock.effective_speed(), subs[0] / 300.0])
				Clock.set_speed(1)
	# Snow still slumping: a 75 m³ load dumped beside the player (a dump truck's worth, piled past
	# the ceiling), measured while it settles.
	Weather.force(Weather.C.CLEAR, 6.0)
	for ri in range(3):
		var run: Array = [[10, false], [2, false], [10, true]][ri]
		var sp: int = run[0]
		Clock.caps_on = run[1]
		Snow.relax_until_stable()
		for k in range(15):
			Snow.deposit(p + Vector2(-12.0 + ri * 9.0 + (k % 5) * 1.5, 3.0), 5.0, 1.2, true)
		var q0 := Snow.relax_pending()
		Clock.set_speed(sp)
		var lbl := "%d× snow settling%s" % [sp, " (capped)" if run[1] else ""]
		var subs := [0]
		await _measure(lbl, 240, func(_i):
			if Clock.speed != sp:
				Clock.set_speed(sp)
			subs[0] += Clock.substeps_last_frame)
		print("  %s: relax queue %d at the start, %.1f substeps a frame" % [lbl, q0, subs[0] / 240.0])
		Clock.set_speed(1)
	Clock.caps_on = true
	Snow.relax_until_stable()
	# The grader driving its whole route while the player stands in a back yard far from every
	# street (it's never within Clock's hold distance), then from the yard of the player's house.
	Clock.caps_on = true
	Weather.force(Weather.C.LIGHT, 12.0, FF_LIGHT_CM_H)
	for run in [[10, false, "away", Vector2(20.0, 20.0)], [2, false, "away", Vector2(20.0, 20.0)], [10, true, "away", Vector2(20.0, 20.0)], [10, true, "from the yard", p]]:
		var sp: int = run[0]
		var where: Vector2 = run[3]
		Clock.caps_on = run[1]
		pl.teleport(Vector3(where.x, Snow.ground_at(where.x, where.y) + 0.05, where.y), PI)
		await get_tree().process_frame
		Municipal.next_pass = Clock.minutes
		Municipal.on_hour(Clock.day_index(), Clock.hour())
		Clock.set_speed(sp)
		var held := [0, 0]
		var lbl := "%d× + grader pass, %s%s" % [sp, run[2], " (capped)" if run[1] else ""]
		await _measure(lbl, 480, func(_i):
			if Clock.speed != sp:
				Clock.set_speed(sp)
			held[1] += Clock.substeps_last_frame
			if Clock.hold_reason() != "":
				held[0] += 1)
		print("  %s: grader %s, held at 1× for %d of 480 frames (%.1f substeps a frame)" % [lbl, "still driving" if world.grader.active else "done", held[0], held[1] / 480.0])
		Clock.set_speed(1)
		world.finish_grader_now()
		for k in range(120):
			await get_tree().process_frame
	Clock.caps_on = true
	pl.teleport(Vector3(p.x, 0.05, p.y), PI)
	Weather.override_cond = -1
	await get_tree().process_frame


## --ff_sweep=<speed>:<cm/h>,…: one speed, uncapped, at each rate — the normal map, then the 4 m map.
func _ff_sweep(pl: Player, p: Vector2) -> void:
	var parts := sweep.split(":")
	var sp := int(parts[0])
	var rates := Array(parts[1].split(",")).map(func(x): return float(x))
	pl.teleport(Vector3(p.x, 0.05, p.y), PI)
	await get_tree().process_frame
	Clock.caps_on = false
	for deep in [false, true]:
		if deep:
			Snow.add_layer_rect(Rect2(0, 0, Layout.MAP_W, Layout.MAP_D), 4.0)
			Snow.set_rect(Rect2(0, 79, 192, 8), 0.3)
			var g := Snow.surface_height(p.x, p.y)
			pl.teleport(Vector3(p.x, g + 0.05, p.y), PI)
			for k in range(60):
				await get_tree().process_frame
		for r in rates:
			Weather.force(Weather.C.HEAVY if r < 20.0 else Weather.C.BLIZZARD, 6.0, r)
			Clock.set_speed(sp)
			await _measure("%d× %.1f cm/h%s" % [sp, r, " (4 m map)" if deep else ""], 300, func(_i):
				if Clock.speed != sp:
					Clock.set_speed(sp))
			Clock.set_speed(1)
	Clock.caps_on = true
	Weather.override_cond = -1


func _measure(label: String, frames: int, step: Callable) -> void:
	var vals: Array = []
	var chunk_updates := 0
	var last := Time.get_ticks_usec()
	for i in range(frames):
		step.call(i)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		vals.append((now - last) / 1000.0)   # wall-clock frame time (scripts + physics, no GPU)
		last = now
		chunk_updates += (world.snow_renderer if world else menu.get("_sr")).updates_last_frame
	var worst := 0
	for k in range(vals.size()):
		if vals[k] > vals[worst]:
			worst = k
	var worst_frame := worst
	vals.sort()
	var avg := 0.0
	for x in vals:
		avg += x
	avg /= vals.size()
	print("%-28s avg %5.2f ms  p95 %5.2f ms  max %6.2f ms @frame %d  (chunk mesh updates %d, relax queue %d)" % [label, avg, vals[int(vals.size() * 0.95)], vals[vals.size() - 1], worst_frame, chunk_updates, Snow.relax_pending()])
