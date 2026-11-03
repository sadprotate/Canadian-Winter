extends Node
## CPU frame-time benchmark of the game's script-side systems (Part 0.4 / 27.4).
## Run: godot --headless --fixed-fps 60 --path . res://tests/perf.tscn
## Scenarios: the main menu background, idle in the yard, indoors in the living room (polish 4:
## the computer screen and the framed photo in view, the screen re-rendering on each game minute),
## shovelling during a blizzard (snow chunk syncs + relaxation + throws), a plow truck pushing a
## long berm, the 4 m deep map under a major event (25 cm/h, and polish 4: the highest hourly
## rate any major event reaches after the storm-onset reshaping) and a time skip. Reports avg /
## p95 / max of the wall-clock CPU frame time (scripts + physics; rendering is a dummy in headless
## mode).

## Polish 4 §1: the highest hourly snowfall of any major event (seed 2024 and 20 other seeds,
## winters 1–5) once storms open with a lead-in (pass 3: 52.2 cm/h). Measured at the game's own
## speed: at 0.4 game min per real second that is 0.73 cm of snow per real second, while the 20×
## stress case at 25 cm/h drops 3.3 cm per real second.
const PEAK_MAJOR_CM_H := 109.6

var world: Node
var menu: Node
var samples: Array = []


func _ready() -> void:
	# Headless runs in low-processor mode (sleeps ~7 ms per frame); measure real work instead.
	OS.low_processor_usage_mode = false
	await get_tree().process_frame
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
	Clock.time_scale = 20.0
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
	Clock.time_scale = 20.0
	Input.action_press("veh_accelerate")
	await _measure("4 m deep map + major event", 480, func(_i): pass)
	# Polish 4: the same, at the highest hourly rate a major event now reaches, at the game's own
	# speed (the 20× scenario above already drops snow ~4× faster per real second than this does).
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
	print("Save: %d ms (file %d KB)" % [Time.get_ticks_msec() - ss, FileAccess.get_file_as_bytes(Saves.path_for("fun")).size() / 1024])
	var ls := Time.get_ticks_msec()
	Saves.load_game("fun")
	print("Load: %d ms" % (Time.get_ticks_msec() - ls))
	Saves.delete_save("fun")
	get_tree().quit()


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
