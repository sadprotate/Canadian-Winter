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
## Polish 5 §10 (last): the computer open on the Contract board with live bidding — every listing
## bid on, the rivals bidding through the measured frames (the board redraws on each bid) — at 1×
## and at 10×.
##   -- --only=board   runs just the world and the live board
## Polish 5 §10b: the board scenario also changes one of your bids from the board every 40 frames
## (each placed and changed bid used to rebuild the whole board); and (last) active jobs all around
## the player — the stakes and orange lines before §10b, the green outlines after: standing among
## them, working one of their boxes, walking along the street past them, and in a light snowfall.
##   -- --only=jobs    runs just the world and the jobs scenario
## Polish 5 §11 (last): the city's pass by the player's house at 1× — the grader and the sidewalk
## plow behind it (the grader alone before §11) passing the player in the front yard.
##   -- --only=pass    runs just the world and the pass
## Polish 5 §12 (last): the player driving the pickup along Maple Street through a long stretch of
## 60 cm untouched snow (under its bog depth, so it keeps shoving the whole time) at 1× — two blade
## pushes a frame at the bumper, the snow cast aside settling, the chunks around the player
## re-meshed (before §12 the pickup stops at the snow's edge).
##   -- --only=pickup  runs just the world and the pickup
## Polish 5 §13b (last): heating in a storm by the player — the heated driveway and path and (this
## build) the heated pad with a pile of snow on it, melting under a storm's heaviest hour (5.5 cm/h),
## the player in the front yard beside the driveway, at 1× and at fast-forward (capped at 2× in the
## snow). On older builds the same storm without the heating (the upgrades do nothing, no pad).
##   -- --only=heat    runs just the world and the heating

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
	if only == "board":
		await _board_live(pl, p)
		AudioMgr.quit()
		return
	if only == "jobs":
		await _jobs_live(pl, p)
		AudioMgr.quit()
		return
	if only == "pass":
		await _city_pass_near(pl)
		AudioMgr.quit()
		return
	if only == "pickup":
		await _pickup_shove(pl)
		AudioMgr.quit()
		return
	if only == "heat":
		await _heated_storm(pl)
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
	await _board_live(pl, p)
	await _jobs_live(pl, p)
	await _city_pass_near(pl)
	await _pickup_shove(pl)
	await _heated_storm(pl)
	# AudioMgr.quit: stop every sound before quitting, so nothing is reported leaked at exit
	# (HANDOFF §13 item 13).
	AudioMgr.quit()


## Polish 5 §10: the computer open on the Contract board, live bidding: your bid on every open
## listing, the rivals' bids landing through the measured frames (each one redraws the board), at
## 1× and at 10× (fast-forward runs at the computer).
func _board_live(pl: Player, p: Vector2) -> void:
	pl.teleport(Vector3(p.x, 0.05, p.y), PI)
	Clock.time_scale = 1.0
	Clock.caps_on = true
	Weather.force(Weather.C.CLEAR, 48.0)
	Game.company_name = "Perf Snow Co."
	Game.flags["computer_unlocked"] = true
	await get_tree().process_frame
	for sp in [1, 10]:
		Contracts.on_advance(0.0)
		for k in range(4):
			Contracts._add_lot_listing(Contracts.residential_lots()[k], Clock.day_index(), RandomNumberGenerator.new(), "path")
		# The rivals bid over the next stretch of game time: 6.4 game minutes at 1× (480 frames), an
		# hour at 10×.
		var span := 6.0 if sp == 1 else 60.0
		var n := 0
		for l in Contracts.listings:
			for rv in l["rivals"]:
				rv["bid"] = 0
				rv["at"] = Clock.minutes + span * float(n % 12 + 1) / 13.0
				n += 1
			if not Contracts.listing_locked(l):
				Contracts.place_bid(int(l["lid"]), Contracts.bid_floor(l) + 1)
		world.open_computer()
		await get_tree().process_frame
		(world.modal as ComputerUI)._open_app(ComputerUI.app_index("board"))
		Clock.running = true
		Clock.set_speed(sp)
		var bids0 := 0
		for l in Contracts.listings:
			bids0 += Contracts.bid_count(l)
		# §10b: one of your bids changed from the board every 40 frames, as the Change bid button does.
		var mine: Array = Contracts.listings.filter(func(x): return int(x.get("bid", 0)) > 0)
		var comp: ComputerUI = world.modal
		await _measure("computer: live board (%d×)" % sp, 480, func(i):
			if int(i) % 40 == 20 and not mine.is_empty():
				var k := int(float(i) / 40.0)
				var l: Dictionary = mine[k % mine.size()]
				if Contracts.listings.has(l) and not bool(l.get("closed", false)):
					comp._bid_values[int(l["lid"])] = Contracts.bid_floor(l) + 1 + k % 3
					comp._bid(int(l["lid"])))
		var bids1 := 0
		for l in Contracts.listings:
			bids1 += Contracts.bid_count(l)
		print("  live board %d×: %d listings, bids %d → %d, clock at %d×" % [sp, Contracts.listings.size(), bids0, bids1, Clock.effective_speed()])
		Clock.set_speed(1)
		world.close_modal()
		await get_tree().process_frame


## Polish 5 §10b: active jobs all around the player (two dozen boxes: driveways and paths on the
## lots near the house, two sidewalk sections, the street, the school's lot), each with snow to clear.
func _jobs_live(pl: Player, p: Vector2) -> void:
	pl.teleport(Vector3(p.x, 0.05, p.y), PI)
	Clock.time_scale = 1.0
	Clock.set_speed(1)
	Weather.force(Weather.C.CLEAR, 48.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var day := Clock.day_index()
	var ls := []
	for li in [6, 8, 0, 2, 9, 3, 13, 14]:
		for kind in ["driveway", "path"]:
			ls.append(Contracts._add_lot_listing(Layout.lots[li], day, rng, kind))
	ls.append(Contracts._add_walk_listing("B_e", day, rng))
	ls.append(Contracts._add_walk_listing("A_e", day, rng))
	ls.append(Contracts._add_municipal_listing(Layout.road_segments[0], day, rng))
	ls.append(Contracts._add_area_listing(Layout.big_areas[0], day, rng))
	var n := 0
	for l in ls:
		if l.is_empty():
			continue
		for z in l["zones"]:
			for id in z["boxes"]:
				var b := Boxes.get_box(id)
				for r in b["rects"]:
					Snow.add_layer_rect(r, 0.2)
				Boxes.measure(b, true)
				n += 1
		l["type"] = "one_time" if l["type"] == "recurring" else l["type"]
		Contracts.force_award(int(l["lid"]))
	Clock.running = true
	var street := Vector2(p.x, 84.0)
	pl.teleport(Vector3(street.x, 0.05, street.y), PI)
	await _measure("jobs: idle among them", 480, func(_i): pass)
	var drv: Rect2 = Boxes.get_box(Boxes.lot_box(Layout.lots[8], "driveway"))["rects"][0]
	pl.teleport(Vector3(drv.get_center().x, Snow.surface_height(drv.get_center().x, drv.get_center().y) + 0.05, drv.get_center().y), PI)
	await _measure("jobs: working a driveway", 480, func(_i): Boxes.note_work(drv.get_center()))
	await _measure("jobs: walking past them", 480, func(i):
		var x := 8.0 + fmod(float(i) * 0.1, 160.0)
		pl.teleport(Vector3(x, Snow.surface_height(x, 84.0) + 0.05, 84.0), PI))
	pl.teleport(Vector3(street.x, 0.05, street.y), PI)
	Weather.force(Weather.C.MODERATE, 4.0, FF_LIGHT_CM_H)
	await _measure("jobs: light snow (1x)", 480, func(_i): pass)
	Weather.override_cond = -1
	var outl := 0
	var zm = world.get("zone_markers")
	if zm and zm.get("outlines") != null:
		outl = (zm.outlines as Dictionary).size()
	print("  jobs: %d boxes in %d jobs; outlines laid now %d" % [n, Contracts.active.size(), outl])


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


## Polish 5 §11: the city's pass by the house at 1×, the player in the front yard by the sidewalk:
## the grader on the street and the sidewalk plow behind it go by in the first seconds (both on the
## same per-step tick), then on along Maple Street.
func _city_pass_near(pl: Player) -> void:
	var lot := Layout.player_lot
	var q := Layout.lot_to_world(lot, Layout.gu(lot, -6.0), 3.0)
	pl.teleport(Vector3(q.x, Snow.surface_height(q.x, q.y) + 0.05, q.y), PI)
	Weather.force(Weather.C.CLEAR, 12.0)
	Clock.set_speed(1)
	for k in range(30):
		await get_tree().process_frame
	Municipal.next_pass = Clock.minutes
	Municipal.on_hour(Clock.day_index(), Clock.hour())
	var crew = world.get("crew")
	var seen := [0]
	await _measure("city pass by the house (1×)", 900, func(_i):
		if crew != null and crew.active and Vector2(crew.global_position.x, crew.global_position.z).distance_to(q) < 20.0:
			seen[0] += 1)
	print("  city pass: grader %s, sidewalk plow %s (within 20 m of the player for %d of 900 frames)" % ["driving" if world.grader.active else "done", "none" if crew == null else ("driving" if crew.active else "done"), seen[0]])
	world.finish_grader_now()
	Weather.override_cond = -1


## Polish 5 §12: the player in the pickup shoving through 60 cm of untouched snow on Maple Street.
func _pickup_shove(pl: Player) -> void:
	Weather.force(Weather.C.CLEAR, 12.0)
	Clock.set_speed(1)
	Game.flags["truck_keys"] = true
	Game.flags["help_vehicle_0"] = true
	Snow.set_rect(Rect2(0, 79, 24, 8), 0.03)
	Snow.set_rect(Rect2(24, 79, 68, 8), 0.6)
	var e := {"uid": Game.uid(), "id": "pickup", "pos": Vector3(8, 0, 84.95), "yaw": -PI * 0.5, "snow": 0.0}
	Game.vehicles.append(e)
	var v: Vehicle = world.spawn_vehicle_node(e)
	await get_tree().physics_frame
	await get_tree().physics_frame
	v.enter_vehicle(pl)
	Input.action_press("veh_accelerate")
	for k in range(150):        # the run-up: into the snow before measuring
		await get_tree().physics_frame
	var moved0 := Snow.stat_player_moved
	await _measure("pickup shoving deep snow (1×)", 600, func(_i): pass)
	Input.action_release("veh_accelerate")
	print("  pickup: front at x %.1f (the snow from x 24), %.2f m³ shoved while measured, %.1f km/h at the end" % [v.global_position.x + v.data.length * 0.5, Snow.stat_player_moved - moved0, v.speed * 3.6])
	v.exit_vehicle()
	Weather.override_cond = -1


## Polish 5 §13b: the heated driveway and path and the heated pad (a pile on it) melting in a storm's
## heaviest hour, the player beside the driveway; 1× and fast-forward. Looked up at run time, so the
## same scenario runs on builds without the heating (the storm alone).
func _heated_storm(pl: Player) -> void:
	var lot := Layout.player_lot
	Game.upgrades["heated_driveway"] = true
	Game.upgrades["heated_path"] = true
	var pad_at := Layout.lot_to_world(lot, Layout.gu(lot, 1.0), 4.0)
	var has_pad := "equipment" in Game
	if has_pad:
		Game.get("equipment")["heated_pad"] = {"pos": [pad_at.x, 0.0, pad_at.y], "yaw": 0.0}
		world.call("refresh_pad")
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for k in range(8):
		Snow.deposit(pad_at + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.9, 0.9)), 0.25, 0.7)
	for kind in ["driveway", "path"]:
		var b := Boxes.get_box(Boxes.lot_box(lot, kind))
		for r in b["rects"]:
			Snow.set_rect(r, 0.04)
	Snow.relax_until_stable()
	var stand := Layout.lot_to_world(lot, Layout.gu(lot, 1.5), 1.5)
	pl.teleport(Vector3(stand.x, 0.05, stand.y), PI)
	Weather.force(Weather.C.HEAVY, 12.0, FF_STORM_CM_H)
	Clock.set_speed(1)
	Clock.running = true
	for k in range(60):
		await get_tree().process_frame
	var m0: float = float(Snow.get("melted")) if "melted" in Snow else 0.0
	await _measure("heated, storm, by the player (1×)", 600, func(_i): pass)
	Clock.set_speed(10)
	await _measure("heated, storm, fast-forward", 600, func(_i):
		if Clock.speed != 10:
			Clock.set_speed(10))
	Clock.set_speed(1)
	print("  heated: %s, %.2f m³ melted while measured (speed capped at %d×)" % ["the driveway, the path and the pad" if has_pad else "no heating on this build", (float(Snow.get("melted")) if "melted" in Snow else 0.0) - m0, Clock.speed_cap()])
	Game.upgrades.erase("heated_driveway")
	Game.upgrades.erase("heated_path")
	if has_pad:
		Game.get("equipment").erase("heated_pad")
		world.call("refresh_pad")
	Weather.override_cond = -1


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
