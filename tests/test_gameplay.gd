extends RefCounted
## Gameplay integration tests (Parts 30.1–30.7) with the real game scene, real player, tools,
## vehicles, store, grader, UI and audio. Gameplay input is driven through the actual InputMap
## actions (Game.force_input lets the controls run without a captured mouse in headless mode).
## Run with --fixed-fps 60 so physics time is deterministic.

var runner
var world: Node = null


func _tree() -> SceneTree:
	return runner.get_tree()


func _frames(n: int) -> void:
	for i in range(n):
		await _tree().physics_frame


func _load_world(mode := "fun", seed_val := 2024, hour := 10.0, day := 1) -> void:
	await _unload()
	Game.force_input = true
	Game.new_game(mode, seed_val)
	Clock.reset(Clock.at(day, hour))
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(3)
	# Freeze the clock so weather doesn't add snow under the measurements (tests that need
	# time to pass turn it back on).
	Clock.running = false


func _unload() -> void:
	if world and is_instance_valid(world):
		_tree().paused = false
		world.queue_free()
		await _tree().process_frame
		await _tree().process_frame
	world = null


func _lot_pt(u: float, v: float, lot := {}) -> Vector2:
	var l: Dictionary = Layout.player_lot if lot.is_empty() else lot
	return Layout.lot_to_world(l, Layout.gu(l, u), v)


func _place(p2: Vector2, yaw: float) -> void:
	var pl: Player = world.player
	pl.teleport(Vector3(p2.x, 0.05, p2.y), yaw)
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)
	await _frames(1)


func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)


## Hold the primary action and sweep the aim point side to side through the snow in front.
func _sweep_fill(frames: int, amp := 0.5) -> void:
	var pl: Player = world.player
	var base := pl.yaw
	Input.action_press("primary")
	for k in range(frames):
		pl.set_yaw(base + amp * sin(k * 0.12))
		await _tree().physics_frame
	pl.set_yaw(base)


func _look_down(deg: float) -> void:
	var pl: Player = world.player
	pl.pitch = deg_to_rad(deg)
	pl.head.rotation.x = pl.pitch


## Look at the nearest snow in front (within the hands' reach), the way a player aims the
## crosshair at what they want to scoop; straight down the reach if nothing is in the way.
func _look_at_snow_ahead() -> void:
	var pl: Player = world.player
	var eye := pl.fp_cam.global_position
	var fw := pl.forward2()
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	var dist := 0.9
	var target_y := Snow.surface_height(p.x + fw.x * dist, p.y + fw.y * dist)
	var a := 0.4
	while a <= 1.1:
		var q := p + fw * a
		if Snow.depth_at(q.x, q.y) > 0.05:
			dist = a
			target_y = maxf(Snow.ground_at(q.x, q.y), Snow.surface_height(q.x, q.y) - 0.2)
			break
		a += 0.1
	pl.pitch = -atan2(eye.y - target_y, dist)
	pl.head.rotation.x = pl.pitch


func _release_all() -> void:
	for a in Settings.ACTIONS.keys():
		Input.action_release(a)


func _flying() -> float:
	var v := 0.0
	for c in world.get_children():
		if c is ThrownSnow:
			v += (c as ThrownSnow).volume
	return v


## Snow thrown onto roofs joins the simplified roof layer (Part 8.9) — count it for conservation.
func _roof_vol() -> float:
	var v := 0.0
	for k in Snow.roof_extra.keys():
		v += float(Snow.roof_extra[k]) * 160.0
	return v


func _find_button(root: Node, text: String) -> Button:
	if root == null or not is_instance_valid(root):
		return null
	if root is Button and (root as Button).text.contains(text) and not (root as Button).disabled:
		return root
	for c in root.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null


func _press(root: Node, text: String) -> bool:
	var b := _find_button(root, text)
	if b == null:
		return false
	b.pressed.emit()
	return true


# -----------------------------------------------------------------------------

func test_main_menu_and_play_panel() -> void:
	var m: Node = load("res://scenes/main_menu.tscn").instantiate()
	runner.add_child(m)
	await _frames(5)
	runner.check(_find_button(m, "PLAY") != null and _find_button(m, "SETTINGS") != null and _find_button(m, "EXIT") != null, "Main menu has PLAY, SETTINGS, EXIT")
	_press(m, "PLAY")
	await _frames(2)
	runner.check(_find_button(m, "New Game") != null, "Play panel offers New Game")
	runner.check(_find_button(m, "Back") != null, "Play panel has Back")
	_press(m, "SETTINGS")
	await _frames(2)
	var s := _find_settings(m)
	runner.check(s != null, "Settings menu opens from the main menu")
	if s:
		s.queue_free()
	m.queue_free()
	await _frames(2)


func _find_settings(root: Node) -> Node:
	if root is SettingsMenu:
		return root
	for c in root.get_children():
		var r := _find_settings(c)
		if r:
			return r
	return null


func test_world_loads_player_moves_indoors() -> void:
	await _load_world("fun")
	runner.check(world.player != null and world.snow_renderer != null, "Game scene built")
	runner.check(Layout.lots.size() >= 20, "Neighbourhood has %d properties" % Layout.lots.size())
	var pl: Player = world.player
	await _frames(4)
	runner.check(pl.in_player_house, "New game starts inside the player's house")
	var p0 := pl.global_position
	await _hold("move_back", 40)
	var moved := Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length()
	runner.check(moved > 0.8, "Player walks indoors (%.2f m)" % moved)
	pl.set_third_person(true)
	runner.check(pl.tp_cam.current and pl.model.visible, "Third-person camera")
	pl.set_third_person(false)
	runner.check(pl.fp_cam.current, "First-person camera")


func test_snow_depth_slows_and_blocks() -> void:
	await _load_world("fun")
	var pl: Player = world.player
	# Cleared pavement vs medium snow vs deep snow.
	var spot := _lot_pt(-9.0, 6.0)
	var results := []
	for d in [0.0, 0.3, 1.0]:
		Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 9)), d)
		if d >= 1.0:
			Snow.set_rect(Rect2(spot - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), 0.0)
		_place(spot, PI)   # face +z (into the lot)
		await _frames(2)
		var p0 := pl.global_position
		await _hold("move_forward", 60)
		results.append(Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length())
	runner.info("distance in 1 s: clear %.2f, 30 cm %.2f, 1 m wall %.2f" % results)
	runner.check(results[0] > 3.0, "Normal speed on cleared ground")
	runner.check(results[1] < results[0] * 0.8, "Medium snow slows the player")
	runner.check(results[2] < 0.6, "A metre of snow is impassable without digging")


func test_walking_does_not_clear_snow() -> void:
	await _load_world("fun")
	var spot := _lot_pt(-9.0, 6.0)
	Snow.set_rect(Rect2(spot - Vector2(2, 2), Vector2(4, 8)), 0.25)
	var vol0 := Snow.volume_in_rect(Rect2(spot - Vector2(2, 2), Vector2(4, 8)))
	_place(spot, PI)
	await _hold("move_forward", 90)
	Snow.relax_until_stable()
	var vol1 := Snow.volume_in_rect(Rect2(spot - Vector2(2, 2), Vector2(4, 8)))
	runner.near(vol1, vol0, 0.002, "Walking moves no snow out of the area (volume %.3f -> %.3f m3)" % [vol0, vol1])


func test_hands_dig_moves_real_snow() -> void:
	await _load_world("fun")
	var pl: Player = world.player
	var spot := _lot_pt(-9.0, 6.0)
	var region := Rect2(spot - Vector2(5, 5), Vector2(10, 10))
	Snow.set_rect(Rect2(spot - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), 0.0)
	Snow.relax_until_stable()
	var before := Snow.volume_in_rect(region)
	var ahead := spot + Vector2(0, 0.6)
	var d0 := Snow.depth_at(ahead.x, ahead.y)
	_place(spot, PI)
	_look_down(-45.0)
	await _frames(2)
	# Digging in place (no sweep): one bite per cycle, a visible dent each time.
	Input.action_press("primary")
	await _frames(40)
	var tc: ToolController = pl.tools
	var held := tc.load
	Input.action_release("primary")
	await _frames(60)
	Snow.relax_until_stable()
	var after := Snow.volume_in_rect(region)
	var d1 := Snow.depth_at(ahead.x, ahead.y)
	runner.info("hands: depth ahead %.3f -> %.3f, held %.1f L, moved %.4f m3" % [d0, d1, held * 1000.0, Snow.stat_player_moved])
	runner.check(held > 0.004, "Hands hold a real load (%.1f L)" % (held * 1000.0))
	runner.check(Snow.stat_player_moved <= Catalog.tool(&"hands").capacity + 1e-5, "…no more than the hands can carry")
	runner.near(after + _flying(), before, 0.002, "Hand digging conserves volume")


func test_hands_sweep_fill_full_and_partial_throws() -> void:
	await _load_world("fun")
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var spot := _lot_pt(-9.0, 5.0)
	var region := Rect2(spot - Vector2(7, 7), Vector2(14, 14))
	Snow.set_rect(Rect2(spot - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), 0.0)
	Snow.relax_until_stable()
	var before := Snow.volume_in_rect(region)
	_place(spot, PI)
	_look_down(-40.0)
	await _frames(2)
	var cap := tc._capacity()
	# Gradual pickup while sweeping.
	Input.action_press("primary")
	var samples := []
	var base := pl.yaw
	for k in range(90):
		pl.set_yaw(base + 0.5 * sin(k * 0.12))
		await _tree().physics_frame
		if k in [2, 6, 12]:
			samples.append(tc.load)
	pl.set_yaw(base)
	runner.info("hands load while sweeping: %s L, cap %.1f L" % [str(samples.map(func(x): return snappedf(x * 1000.0, 0.1))), cap * 1000.0])
	runner.check(samples[0] > 0.0 and samples[0] < samples[2], "The load fills gradually while sweeping")
	runner.near(tc.load, cap, 1e-6, "The load stops at the hands' capacity")
	var on_ground := Snow.volume_in_rect(region)
	runner.near(on_ground + tc.load, before, 0.002, "The ground lost exactly what the hands hold")
	# Full load: release throws it all forward where the player faces.
	pl.set_yaw(0.4)
	await _frames(2)
	var full := tc.load
	Input.action_release("primary")
	await _frames(2)
	runner.check(tc.load == 0.0 and _flying() > full * 0.99, "Releasing throws the full load (%.1f L in flight)" % (_flying() * 1000.0))
	await _frames(90)
	Snow.relax_until_stable()
	runner.near(Snow.volume_in_rect(region), before, 0.002, "Thrown snow lands; volume conserved")
	# Partial load: a short sweep, then release early.
	pl.set_yaw(PI)
	await _frames(2)
	Input.action_press("primary")
	await _frames(3)
	var part := tc.load
	runner.check(part > 0.0 and part < cap * 0.95, "A short sweep gives a partial load (%.1f L)" % (part * 1000.0))
	pl.set_yaw(0.4)
	await _frames(1)
	Input.action_release("primary")
	await _frames(2)
	runner.check(tc.load == 0.0 and absf(_flying() - part) < 1e-6 + part * 0.5, "Releasing early throws the partial load")
	await _frames(90)
	Snow.relax_until_stable()
	runner.near(Snow.volume_in_rect(region), before, 0.002, "Partial throw conserves volume")
	# Bare pavement: sweeping fills nothing.
	var bare := Rect2(spot - Vector2(3, 3), Vector2(6, 6))
	Snow.set_rect(bare, 0.0)
	pl.set_yaw(PI)
	await _sweep_fill(40)
	runner.near(tc.load, 0.0, 1e-7, "Sweeping a bare surface fills nothing")
	Input.action_release("primary")
	await _frames(2)


func test_shovel_load_grows_and_throws_farther() -> void:
	await _load_world("fun")
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	Game.add_tool("small_shovel")
	await _frames(2)
	var spot := _lot_pt(-9.0, 5.0)
	Snow.set_rect(Rect2(spot - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), 0.0)
	_place(spot, PI)
	_look_down(-35.0)
	await _frames(2)
	Input.action_press("primary")
	var l1 := 0.0
	var base := pl.yaw
	for k in range(60):
		pl.set_yaw(base + 0.5 * sin(k * 0.12))
		await _tree().physics_frame
		if k == 4:
			l1 = tc.load
	runner.check(l1 > 0.0 and l1 < tc.load, "Shovel load grows while sweeping (%.1f → %.1f L)" % [l1 * 1000.0, tc.load * 1000.0])
	runner.check(tc.load <= Catalog.tool(&"small_shovel").capacity + 1e-6, "Shovel load limited by capacity")
	runner.check(tc.load_fp.visible or pl.third_person, "The load shows on the blade")
	pl.set_yaw(0.5)
	_look_down(0.0)
	await _frames(4)
	var land: Dictionary = tc.landing
	var dist := Vector2(land["pos"].x - pl.global_position.x, land["pos"].z - pl.global_position.z).length()
	runner.check(dist > Catalog.tool(&"hands").throw_distance * 1.5, "The shovel throws much farther than hands (%.1f m)" % dist)
	Input.action_release("primary")
	await _frames(100)


func test_shovel_refuses_to_throw_on_road() -> void:
	await _load_world("fun")
	var pl: Player = world.player
	Game.add_tool("standard_shovel")
	await _frames(2)
	# On the boulevard, facing the street (north = -z for the player's lot).
	var spot := _lot_pt(-9.0, -2.2)
	Snow.set_rect(Rect2(spot - Vector2(1, 1), Vector2(2, 2)), 0.3)
	Snow.set_rect(Rect2(spot - Vector2(1, -0.2), Vector2(2, 2)), 0.3)
	var road := Rect2(spot.x - 8, 79, 16, 8)
	var road_before := Snow.volume_in_rect(road)
	_place(spot, PI)
	_look_down(-45.0)
	await _frames(2)
	await _sweep_fill(30, 0.3)
	var tc: ToolController = pl.tools
	var l0 := tc.load
	runner.check(l0 > 0.0, "Scooped boulevard snow")
	pl.set_yaw(0.0)   # face the street
	_look_down(0.0)
	await _frames(10)
	runner.check(not tc.landing.get("valid", true), "Landing indicator is red over the street")
	var l1 := tc.load
	Input.action_release("primary")
	await _frames(60)
	runner.near(tc.load, l1, 1e-6, "Releasing over the street keeps the snow in the shovel")
	runner.near(Snow.volume_in_rect(road), road_before, 1e-5, "No snow deposited on the road")
	dump_safely(tc)


func dump_safely(tc: ToolController) -> void:
	tc.dump_at_feet(true)


func test_pusher_stops_at_curb() -> void:
	await _load_world("fun")
	Game.add_tool("wide_pusher")
	await _frames(2)
	var hi := Layout.house_info(Layout.lots[9])
	var drv: Rect2 = hi["driveway"]
	Snow.set_rect(drv, 0.08)
	var road := Rect2(drv.position.x - 3, 79, drv.size.x + 6, 8)
	Snow.set_rect(Rect2(0, 79, Layout.MAP_W, 8), 0.0)   # whole street clear (no road-to-road slump)
	var start := Vector2(drv.get_center().x, drv.end.y - 1.5)
	_place(start, 0.0)   # facing north, toward the street
	await _frames(2)
	Input.action_press("secondary")
	Input.action_press("move_forward")
	await _frames(600)
	_release_all()
	await _frames(2)
	runner.check(Snow.stat_player_moved > 0.05, "Pusher moved %.3f m3" % Snow.stat_player_moved)
	runner.near(Snow.volume_in_rect(road), 0.0, 0.0005, "Pushed snow stops at the curb (road stays clear)")
	var curb_band := Rect2(drv.position.x - 1, 87.0, drv.size.x + 2, 1.5)
	runner.check(Snow.volume_in_rect(curb_band) > 0.1, "A berm piles up at the curb line")
	var strip := Rect2(start.x - 0.3, drv.position.y + 2.0, 0.6, drv.size.y - 5.0)
	runner.check(Snow.volume_in_rect(strip) < 0.06, "The pusher cleared its strip down the driveway (%.3f m3 left, 1 cm scrape residue)" % Snow.volume_in_rect(strip))


func test_scraper_angle_cycles() -> void:
	await _load_world("fun")
	var pl: Player = world.player
	Game.add_tool("snow_scraper")
	await _frames(2)
	var tc: ToolController = pl.tools
	await _tap("tool_angle")
	var a1 := tc.blade_angle
	await _tap("tool_angle")
	var a2 := tc.blade_angle
	await _tap("tool_angle")
	runner.check(a1 > 0.0 and a2 < 0.0 and tc.blade_angle == 0.0, "R cycles the scraper blade right / left / straight")


func test_store_order_spawns_and_is_collected() -> void:
	await _load_world("fun", 2024, 10.0)
	Game.money = 200
	var r := Economy.buy("standard_shovel")
	runner.check(r["ok"], "Order placed on the computer")
	await _frames(3)
	var item: ToolItem = null
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).tool_id == "standard_shovel":
			item = c
	runner.check(item != null, "The shovel appears as a real object")
	if item == null:
		return
	runner.check(Layout.store_pad.grow(1.0).has_point(Vector2(item.global_position.x, item.global_position.z)), "…on the store's pickup pad")
	runner.check(not ("standard_shovel" in Game.slots), "Not magically in the inventory")
	# Walk up to it and look at it.
	var p := Vector2(item.global_position.x, item.global_position.z + 1.6)
	_place(p, 0.0)
	world.player.pitch = deg_to_rad(-35)
	world.player.head.rotation.x = world.player.pitch
	await _frames(4)
	runner.check(world.player.focus == item, "Looking at the shovel shows its prompt (%s)" % world.player.focus_prompt)
	await _tap("interact")
	await _tree().process_frame
	await _frames(2)
	if "standard_shovel" not in Game.slots:
		item.interact(world.player)
	runner.check("standard_shovel" in Game.slots, "Picked up into a tool slot")
	var collected := false
	for o in Economy.orders:
		if o["item"] == "standard_shovel" and o["status"] == "collected":
			collected = true
	runner.check(collected, "Order marked collected")


func test_after_hours_order_appears_at_7() -> void:
	await _load_world("fun", 2024, 22.0)
	Game.money = 200
	Economy.buy("wide_pusher")
	await _frames(3)
	var count := func() -> int:
		var n := 0
		for c in world.objects.get_children():
			if c is ToolItem and (c as ToolItem).tool_id == "wide_pusher":
				n += 1
		return n
	runner.check(count.call() == 0, "After-hours order is not in the lot yet")
	Clock.skip(Clock.at(2, 7.05) - Clock.minutes)
	await _frames(3)
	runner.check(count.call() == 1, "It appears at 7:00 when the store opens")


func test_walk_behind_blower() -> void:
	await _load_world("fun", 2024, 10.0)
	Game.money = 2000
	Economy.buy("small_blower")
	await _frames(3)
	var wb: WalkBehind = null
	for c in world.objects.get_children():
		if c is WalkBehind:
			wb = c
	runner.check(wb != null, "Snowblower appears in the store lot")
	if wb == null:
		return
	var pl: Player = world.player
	var spot := _lot_pt(-9.0, 4.0)
	Snow.set_rect(Rect2(spot - Vector2(2, 1), Vector2(4, 8)), 0.25)
	_place(spot, PI)
	wb.interact(pl)
	runner.check(pl.state == "machine" and wb.grabbed, "Grabbed the blower")
	var region := Rect2(spot - Vector2(14, 14), Vector2(28, 28))
	Snow.relax_until_stable()
	var before := Snow.volume_in_rect(region) + _roof_vol()
	Input.action_press("primary")
	Input.action_press("move_forward")
	await _frames(180)
	_release_all()
	await _frames(90)
	runner.check(Snow.stat_player_moved > 0.1, "Blower moved %.3f m3" % Snow.stat_player_moved)
	Snow.relax_until_stable()
	var lost := before - Snow.volume_in_rect(region) - _flying() - _roof_vol()
	runner.check(absf(lost) < 0.01, "Blower discharge lands in the world (Δ %.4f)" % lost)
	# Chute aimed at the street from the boulevard: discharge is blocked.
	# On the boulevard walking east, chute turned left (north): the 8 m throw would land on the street.
	var b2 := _lot_pt(-9.0, -2.0)
	_place(b2, -PI * 0.5)
	wb.chute_angle = -90.0
	Snow.set_rect(Rect2(b2 - Vector2(1, 1), Vector2(2, 2)), 0.25)
	var road := Rect2(b2.x - 10, 79, 20, 8)
	var rb := Snow.volume_in_rect(road)
	Input.action_press("primary")
	await _frames(60)
	_release_all()
	await _frames(60)
	runner.check(not wb._landing.get("valid", true), "Chute aimed at the street is refused")
	runner.check(Snow.volume_in_rect(road) <= rb + 1e-4, "No blower snow on the road")
	wb.release()
	runner.check(pl.state == "foot", "Released the blower")


func test_vehicle_plow_and_stuck_pickup() -> void:
	await _load_world("fun", 2024, 10.0)
	var pl: Player = world.player
	# The starting pickup is locked.
	var truck: Vehicle = world.vehicle_nodes()[0]
	runner.check(truck.interact_prompt(pl).contains("locked"), "Starting truck is locked")
	truck.interact(pl)
	runner.check(pl.state != "vehicle", "Locked truck can't be entered")
	Game.flags["truck_keys"] = true
	truck.interact(pl)
	runner.check(pl.state == "vehicle", "With keys the truck can be entered")
	var p0 := truck.global_position
	Input.action_press("veh_accelerate")
	await _frames(120)
	_release_all()
	var moved := truck.global_position.distance_to(p0)
	runner.check(moved < 2.0, "Truck is stuck in the opening's deep snow (moved %.2f m)" % moved)
	truck.exit_vehicle()
	await _frames(2)
	# A plow truck on Maple Street.
	var e := {"uid": Game.uid(), "id": "pickup_plow", "pos": Vector3(20, 0, 83 + 2.0), "yaw": -PI * 0.5, "snow": 0.0}
	Game.vehicles.append(e)
	var v: Vehicle = world.spawn_vehicle_node(e)
	await _frames(2)
	v.enter_vehicle(pl)
	var lane := Rect2(24, 84.0, 10, 2.0)   # a stretch the blade has fully passed
	Snow.set_rect(Rect2(10, 79, 50, 8), 0.12)
	var lane_before := Snow.volume_in_rect(lane)
	v._toggle_tool()
	runner.check(v.tool_on, "Blade down")
	Input.action_press("veh_accelerate")
	await _frames(240)
	_release_all()
	await _frames(10)
	runner.info("plow moved %.2f m3, lane %.2f -> %.2f, truck x %.1f" % [Snow.stat_player_moved, lane_before, Snow.volume_in_rect(lane), v.global_position.x])
	runner.check(v.global_position.x > 30.0, "Plow truck drives along the street")
	runner.check(Snow.volume_in_rect(lane) < lane_before * 0.5, "Plow clears the travel lane")
	runner.check(pl.state == "vehicle" and Survival.vehicle_heat > 0.0, "Heated cabin warms the driver")
	v.exit_vehicle()
	runner.check(pl.state == "foot", "Exited the vehicle")


func test_plow_cannot_push_yard_snow_onto_road() -> void:
	await _load_world("fun", 2024, 10.0)
	var pl: Player = world.player
	var hi := Layout.house_info(Layout.lots[9])
	var drv: Rect2 = hi["driveway"]
	Snow.set_rect(Rect2(drv.position.x - 4, 87, drv.size.x + 8, 20), 0.2)
	var road := Rect2(drv.position.x - 6, 79, drv.size.x + 12, 8)
	Snow.set_rect(Rect2(0, 79, Layout.MAP_W, 8), 0.0)
	var e := {"uid": Game.uid(), "id": "atv_blade", "pos": Vector3(drv.get_center().x, 0, drv.end.y - 1.0), "yaw": 0.0, "snow": 0.0}
	Game.vehicles.append(e)
	var v: Vehicle = world.spawn_vehicle_node(e)
	await _frames(2)
	v.enter_vehicle(pl)
	v._toggle_tool()
	Input.action_press("veh_accelerate")
	await _frames(300)
	_release_all()
	await _frames(5)
	runner.check(Snow.stat_player_moved > 0.2, "ATV blade pushed snow (%.2f m3)" % Snow.stat_player_moved)
	runner.near(Snow.volume_in_rect(road), 0.0, 0.001, "Yard snow stops at the curb, never on the street")
	v.exit_vehicle()


func test_grader_npc_clears_road_and_windrows() -> void:
	await _load_world("fun", 2024, 10.0, 2)
	var road := Rect2(0, 79, 92, 8)
	Snow.set_rect(Rect2(0, 79, 192, 8), 0.3)
	var before := Snow.volume_in_rect(road)
	Municipal.next_pass = Clock.minutes
	Municipal.on_hour(Clock.day_index(), Clock.hour())
	await _frames(2)
	runner.check(world.grader.active and world.grader.visible, "The city grader drives out")
	var g0: Vector3 = world.grader.global_position
	await _frames(120)
	runner.check(world.grader.global_position.distance_to(g0) > 5.0, "Grader follows the road")
	world.finish_grader_now()
	runner.check(not Municipal.in_progress, "Pass finished")
	var after := Snow.volume_in_rect(road)
	runner.check(after < before * 0.75, "Road snow reduced (%.1f -> %.1f m3)" % [before, after])
	runner.check(after > before * 0.05, "…but the city leaves ridges and patches")


func test_mailbox_letter_and_cry_for_help() -> void:
	await _load_world("survival", 2024, 9.0, 0)
	var pl: Player = world.player
	var mb: Vector2 = Layout.house_info(Layout.player_lot)["mailbox"]
	Snow.set_rect(Rect2(mb - Vector2(1.5, 0.2), Vector2(3, 3)), 0.0)
	_place(mb + Vector2(0, 1.4), 0.0)
	pl.pitch = deg_to_rad(-25)
	pl.head.rotation.x = pl.pitch
	await _frames(4)
	runner.check(pl.focus_prompt.contains("mailbox"), "Mailbox prompt shown (%s)" % pl.focus_prompt)
	pl.try_interact()
	await _frames(2)
	runner.check(world.modal_kind == "letter", "Letter shown on screen")
	runner.check(_find_button(world.modal, "Close") != null, "Letter can be closed")
	var body_text := _all_text(world.modal)
	runner.check(body_text.contains("15th") and body_text.contains("$85") and body_text.to_lower().contains("hydro"), "Hydro letter: the $85 hydro bill is due on the 15th")
	for word in ["computer", "online", "website", "bank", "cheque", "phone"]:
		runner.check(not body_text.to_lower().contains(word), "The letter doesn't say how to pay (%s)" % word)
	_press(world.modal, "Close")
	await _frames(60)
	runner.check(Game.stage() == Game.Stage.LETTER_READ, "Closing the letter advances the opening")
	runner.check(world.neighbor.label.text.to_lower().contains("help"), "Neighbour calls \"Hey, help!\"")
	runner.check(Survival.enabled(), "Survival: the cold is already on before the neighbour")


func _all_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += (n as Label).text + "\n"
	for c in n.get_children():
		s += _all_text(c)
	return s


func test_tutorial_negotiation_trail_and_explanation() -> void:
	await _load_world("survival", 2024, 11.0, 0)
	var pl: Player = world.player
	Game.set_stage(Game.Stage.LETTER_READ)
	world.neighbor_dialogue(world.neighbor)
	await _frames(1)
	runner.check(world.modal_kind == "dialogue", "Neighbour dialogue opens")
	_press(world.modal, "Continue")
	_press(world.modal, "Continue")
	await _frames(1)
	runner.check(_press(world.modal, "$55"), "Negotiation offers price choices")
	await _frames(1)
	while _press(world.modal, "Continue"):
		await _frames(1)
	await _frames(2)
	runner.check(Game.stage() == Game.Stage.NEIGHBOR_TALKED, "Contract agreed")
	var tut: Dictionary = {}
	for c in Contracts.active:
		if c.get("tutorial", false):
			tut = c
	runner.check(not tut.is_empty() and int(tut["pay"]) == 55, "Tutorial contract for $55")
	runner.check(world.zone_markers != null, "Zone markers exist")
	var money0 := Game.money
	for z in tut["zones"]:
		for ra in z["rects"]:
			Snow.set_rect(Contracts.a_to_rect(ra), 0.004)
		Contracts.measure_zone(tut, z)
	runner.check(Game.stage() == Game.Stage.TRAIL_DONE and Game.money == money0 + 55, "Trail complete, Gerry pays")
	# Polish 3 §4: Gerry comes down the trail to meet you, invites you in, and walks in ahead of
	# you; you follow him through his door (no teleport, no freeze).
	Clock.running = true
	var g: Neighbor = world.neighbor
	var guard := 0
	while g.mode != "meet" and guard < 900:
		await _frames(1)
		guard += 1
	world.neighbor_dialogue(g)
	await _frames(2)
	runner.check(g.invited and world.modal == null, "Gerry invites you in")
	var door := Neighbor.door_point()
	var out := Vector2(door.x, door.z) - Vector2(Layout.neighbor_lot["inward"]) * 2.4
	pl.teleport(Vector3(out.x, Snow.ground_at(out.x, out.y) + 0.05, out.y))
	var to := Vector2(door.x, door.z) - out
	pl.set_yaw(atan2(-to.x, -to.y))
	guard = 0
	while not world.neighbor_door.open and guard < 900:
		await _frames(1)
		guard += 1
	Input.action_press("move_forward")
	guard = 0
	while not pl.in_neighbor_house and guard < 400:
		await _frames(1)
		guard += 1
	Input.action_release("move_forward")
	runner.check(pl.in_neighbor_house, "Player follows Gerry inside to warm up")
	guard = 0
	while Game.stage() != Game.Stage.COMPLETE and guard < 4000:
		await _frames(20)
		if world.is_gerry_talking() and world._talk_started:
			world._talk_next()
		guard += 20
	runner.check(Survival.active, "Cold system on (since the start of the game)")
	runner.check(Game.stage() == Game.Stage.COMPLETE, "Tutorial complete")
	runner.check(world.neighbor != null and world.neighbor.mode in ["inside", "computer", "to_computer"], "Gerry stays in his house")
	# After this game he isn't seen again: a reloaded tutorial-complete game has no Gerry.
	Clock.running = false
	Saves.save_game()
	await _unload()
	Saves.load_game("survival")
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(3)
	Clock.running = false
	runner.check(world.neighbor == null, "Gerry is not seen again")


func test_keys_buried_in_lawn() -> void:
	await _load_world("fun", 2024, 11.0, 0)
	var kp: Array = Game.flags["keys_pos"]
	var keys: BuriedKeys = null
	for c in world.objects.get_children():
		if c is BuriedKeys:
			keys = c
	runner.check(keys != null, "Truck keys are buried in the front lawn")
	if keys == null:
		return
	runner.check(keys.interact_prompt(world.player) == "", "Not visible under deep snow")
	Snow.set_rect(Rect2(Vector2(kp[0], kp[1]) - Vector2(0.6, 0.6), Vector2(1.2, 1.2)), 0.0)
	runner.check(keys.interact_prompt(world.player).contains("keys"), "Dug out: keys can be picked up")
	keys.interact(world.player)
	runner.check(Game.flags.get("truck_keys", false), "Keys found")


func test_hidden_shovel_beside_truck() -> void:
	await _load_world("fun", 2024, 11.0, 0)
	var sh: ToolItem = null
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).tool_id == "small_shovel":
			sh = c
	runner.check(sh != null, "Exactly one small shovel is on the property")
	if sh == null:
		return
	var truck: Vehicle = world.vehicle_nodes()[0]
	var door: Vector2 = Layout.house_info(Layout.player_lot)["door"]
	var tp := Vector2(truck.global_position.x, truck.global_position.z)
	var sp := Vector2(sh.global_position.x, sh.global_position.z)
	runner.check(sp.distance_to(door) > tp.distance_to(door), "Shovel is on the far side of the truck")
	runner.check(sh.interact_prompt(world.player).contains("buried"), "Buried: must dig it out")
	# The snow over it forms a slightly bigger, odd-looking pile.
	var over := Snow.depth_at(sp.x, sp.y)
	var around := 0.0
	for a in range(8):
		var q := sp + Vector2(2.4, 0).rotated(a * TAU / 8.0)
		around += Snow.depth_at(q.x, q.y) / 8.0
	runner.check(over > around + 0.15, "An odd pile sits over the shovel (%.2f m vs %.2f m around)" % [over, around])
	runner.check(sp.distance_to(tp) < 3.0, "The shovel lies right beside the truck (%.1f m)" % sp.distance_to(tp))
	Snow.set_rect(Rect2(sp - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), 0.1)
	await _frames(100)
	sh.interact(world.player)
	runner.check("small_shovel" in Game.slots, "Found the shovel")


func test_sleep_saves_and_advances() -> void:
	await _load_world("fun", 2024, 20.0, 1)
	Saves.delete_save("fun")
	world.open_sleep()
	await _frames(1)
	runner.check(world.modal_kind == "sleep", "Bed offers sleeping")
	var t := _all_text(world.modal)
	runner.check(_find_button(world.modal, "Sleep until 7:00 a.m.") != null and _find_button(world.modal, "Not yet") != null, "Exactly two choices: sleep until 7:00 a.m. / not yet")
	var buttons := 0
	for b in world.modal.find_children("*", "Button", true, false):
		buttons += 1
	runner.check(buttons == 2, "No multi-day options (%d buttons)" % buttons)
	var leaks := []
	for w in Clock.MONTHS + Clock.MONTH_SHORT + Weather.NAMES + ["°", "forecast", "snow expected"]:
		if t.contains(w):
			leaks.append(w)
	runner.check(leaks.is_empty(), "The sleep prompt shows no date, weather or forecast %s" % str(leaks))
	_press(world.modal, "Sleep until 7:00 a.m.")
	await _frames(70)
	var shown := _all_text(world.fade)
	var leaks2 := []
	for w in Clock.MONTHS + Weather.NAMES + ["°"]:
		if shown.contains(w):
			leaks2.append(w)
	runner.check(leaks2.is_empty(), "The sleep transition screen shows no date or weather %s" % str(leaks2))
	await _frames(200)
	runner.check(Saves.has_save("fun"), "Sleeping autosaves")
	runner.check(Clock.day_index() == 2 and Clock.hour() == 7 and Clock.minute_of_hour() == 0, "Evening sleep ends at 7:00 the next morning (%s)" % Clock.format_time(Clock.minutes))
	runner.check(world.player.in_player_house, "Wakes up in the bedroom")
	# After midnight and in the morning.
	for start in [[3, 1.5, 3], [4, 9.0, 5], [5, 6.95, 5]]:
		Clock.reset(Clock.at(start[0], start[1]))
		world._do_sleep()
		await _frames(260)
		runner.check(Clock.day_index() == start[2] and Clock.hour() == 7 and Clock.minute_of_hour() == 0, "Sleep at day %d %.2f h ends at 7:00 on day %d (%s)" % [start[0], start[1], start[2], Clock.format_time(Clock.minutes)])


func test_power_outage_house_and_ups_computer() -> void:
	await _load_world("survival", 2024, 12.0, 15)
	Game.set_stage(Game.Stage.COMPLETE)
	Survival.activate()
	Survival.cut_power()
	await _frames(3)
	runner.check(not (world.interior["fire_mesh"] as Node3D).visible, "Fireplace off during the outage")
	runner.check(not (world.interior["tv_screen"] as Node3D).visible, "TV off")
	var any_light := false
	for l in world.interior["lights"]:
		any_light = any_light or (l as Light3D).visible
	runner.check(not any_light, "House lights off")
	world.open_computer()
	await _frames(2)
	runner.check(world.modal_kind == "computer", "Computer still works on battery backup")
	var c: ComputerUI = world.modal
	await _tree().process_frame
	runner.check(c.battery_l.text.contains("Battery"), "Battery indicator shown")
	Game.money = 300
	c._open_app(4)
	await _frames(1)
	var paid := _press(c, "Pay now")
	await _frames(2)
	runner.check(paid and Survival.power_on, "Paying from the computer restores power")
	runner.check(Game.money == 215, "No reconnection fee")
	world.close_modal()


func test_computer_apps_and_map_pause_debug() -> void:
	await _load_world("survival", 2024, 12.0, 4)
	Game.set_stage(Game.Stage.COMPLETE)
	world.open_computer()
	await _frames(1)
	var c: ComputerUI = world.modal
	for i in range(ComputerUI.APPS.size()):
		c._open_app(i)
		await _frames(1)
		runner.check(c.content.get_child_count() > 0, "Computer app '%s' renders" % ComputerUI.APPS[i])
	c._open_app(6)
	var t := _all_text(c)
	runner.check(t.contains("grader"), "Weather app shows the city grader schedule")
	c._open_app(0)
	var bid_ok := _find_button(c, "Place bid") != null
	runner.check(bid_ok, "Contract board has bid buttons")
	world.close_modal()
	var m := MapUI.new()
	world.ui.add_child(m)
	world.open_modal(m, "map")
	await _frames(2)
	runner.check(is_instance_valid(m) and m.visible, "Map opens")
	world.close_modal()
	world._open_pause()
	await _frames(1)
	runner.check(_tree().paused and world.modal_kind == "pause", "ESC pause freezes the game")
	var m0 := Clock.minutes
	await _tree().process_frame
	await _tree().process_frame
	runner.near(Clock.minutes, m0, 1e-6, "Clock stops while paused")
	runner.check(_find_button(world.modal, "RESUME") != null and _find_button(world.modal, "QUIT") != null, "Pause menu buttons")
	_press(world.modal, "SETTINGS")
	await _tree().process_frame
	var s := _find_settings(world.ui)
	runner.check(s != null, "Settings opens from pause")
	if s:
		s.queue_free()
	_press(world.modal, "RESUME")
	await _frames(1)
	runner.check(not _tree().paused and world.modal == null, "Resume")
	var d := DebugMenu.new()
	d.world = world
	world.ui.add_child(d)
	world.open_modal(d, "debug")
	await _frames(1)
	var n0: int = world.objects.get_child_count()
	d._spawn("large_scraper", false)
	await _frames(1)
	runner.check(world.objects.get_child_count() == n0 + 1, "Debug spawn creates a real tool object")
	d._spawn_vehicle("tractor_blower", true)
	await _frames(1)
	runner.check(world.vehicle_nodes().size() >= 2, "Debug spawns a vehicle")
	world.close_modal()


func test_settings_rebinding() -> void:
	var old: Array = Settings.bindings["jump"].duplicate()
	var e := InputEventKey.new()
	e.physical_keycode = KEY_J
	runner.check(Settings.rebind("jump", e) == "", "Rebinding works")
	runner.check(InputMap.action_has_event("jump", e), "Input map updated")
	var e2 := InputEventKey.new()
	e2.physical_keycode = KEY_W
	runner.check(Settings.rebind("jump", e2) == "move_forward", "Conflicting binding refused")
	Settings.restore_default_controls()
	runner.check(Settings.bindings["jump"] == old, "Restore defaults")
	Settings.set_value("audio", "music", 0.0)
	runner.check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Music volume 0 mutes the bus")
	Settings.set_value("audio", "music", 0.6)
	runner.check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Volume applies immediately")


func test_freezing_death_screen() -> void:
	await _load_world("survival", 2024, 12.0, 6)
	Survival.activate()
	_place(_lot_pt(-9.0, 4.0), 0.0)
	await _frames(2)
	Saves.save_game()
	Survival.warmth = 0.4
	Weather.force(Weather.C.BLIZZARD, 5.0)
	Clock.running = true
	await _frames(90)
	runner.check(Survival.dead and world._dead, "Player froze to death")
	runner.check(Saves.has_save("survival"), "The save is not erased")
	runner.check(_all_text(world.ui).to_lower().contains("froze"), "Death screen says you froze")
	Weather.override_cond = -1
	# Don't let the 6 s timer swap scenes under the test runner.
	await _unload()
	Survival.dead = false
	Survival.warmth = 100.0


func test_winter_summary_and_new_year() -> void:
	await _load_world("fun", 2024, 23.95, 120)
	Game.money = 999
	Clock.running = true
	Clock.time_scale = 20.0
	await _frames(60)
	Clock.time_scale = 1.0
	runner.check(Clock.has_ended(), "April 1 reached")
	await _frames(2)
	runner.check(world.modal_kind == "summary", "Seasonal summary shown")
	runner.check(_all_text(world.modal).to_lower().contains("winter 1"), "Summary names the winter survived")
	# A real click arrives outside the physics step; unpausing between the physics server's query
	# flush and its step makes the engine print `p_elem->_root` (HANDOFF §13 item 12).
	await _tree().process_frame
	var ok := _press(world.modal, "WINTER 2")
	if not ok:
		ok = _press(world.modal, "Next")
	runner.check(ok, "Next winter button")
	await _frames(200)
	runner.check(Game.year == 2 and Clock.day_index() == 0, "Winter 2 begins December 1")
	runner.check(Game.money == 999, "Money carried over")


func test_audio_files_exist_for_every_sound() -> void:
	var names := ["ui_error", "ui_click", "snow_land_big", "pickup_item", "radio_jingle", "ui_money", "truck_locked",
		"snow_land", "push_scrape", "paper", "horn", "engine_start", "door_close", "ui_notify", "ui_hover", "ui_alert",
		"tires_snow", "step_snow_1", "step_hard_1", "step_deep_1", "shovel_throw", "shovel_scrape", "rattle", "power_on",
		"power_off", "plow_scrape", "neighbor_talk_1", "mailbox", "keys_jingle", "help_call", "gust_whistle",
		"engine_diesel", "engine_truck", "engine_small", "electric_motor", "door_open", "death_sting", "blower_discharge",
		"blower_small", "blower_large", "hand_dig", "shovel_scoop", "wind_light", "wind_strong", "blizzard",
		"fire_crackle", "furnace_hum", "room_tone", "music_calm", "music_snow", "shiver", "heartbeat",
		"hand_scoop_1", "hand_scoop_2", "hand_scoop_3", "shovel_fill_1", "shovel_fill_2", "shovel_fill_3",
		"hand_toss", "push_snow", "box_complete"]
	var missing := []
	for n in names:
		if not AudioMgr.has_sound(n):
			missing.append(n)
	runner.check(missing.is_empty(), "Every referenced sound exists (missing: %s)" % str(missing))
	for n in ["wind_light", "music_calm", "push_scrape", "push_snow"]:
		var s := AudioMgr.stream(n)
		runner.check(s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % n)


# -----------------------------------------------------------------------------
# Polish pass: push, tool profiles, wading, boxes, snowfall, computer lock
# -----------------------------------------------------------------------------

func test_push_builds_a_mound_conserving_volume() -> void:
	await _load_world("fun")
	var spot := _lot_pt(-9.0, 4.0)
	var area := Rect2(spot - Vector2(4, 1), Vector2(8, 12))
	Snow.set_rect(area, 0.2)
	Snow.relax_until_stable()
	var region := area.grow(3.0)
	var before := Snow.volume_in_rect(region)
	var h0 := 0.0
	var pile0 := 0.0
	var ahead := Rect2(spot + Vector2(-1.0, 0.4), Vector2(2.0, 4.5))
	for k in range(2):
		# Two overlapping strips pushed into the same spot.
		_place(spot + Vector2(-0.2 if k == 0 else 0.2, 0), PI)
		await _frames(2)
		Input.action_press("secondary")
		Input.action_press("move_forward")
		await _frames(150)
		_release_all()
		await _frames(20)
		if k == 0:
			Snow.relax_until_stable()
			h0 = _max_depth(ahead)
			pile0 = _pile(ahead, 0.21)
	Snow.relax_until_stable()
	var h1 := _max_depth(ahead)
	var pile1 := _pile(ahead, 0.21)
	runner.info("hand push: mound %.2f m / %.3f m3 after one push, %.2f m / %.3f m3 after two (base 0.20 m)" % [h0, pile0, h1, pile1])
	runner.check(h0 > 0.3, "Pushing with flat palms builds a mound ahead (%.2f m)" % h0)
	runner.check(pile1 > pile0 * 1.2, "Pushing into the same spot again makes the pile bigger (%.3f → %.3f m3)" % [pile0, pile1])
	runner.check(h1 > 0.3, "…and relaxation leaves it a mound, not flattened (%.2f m)" % h1)
	runner.near(Snow.volume_in_rect(region), before, 0.002, "Pushing conserves volume")


## Volume of snow piled above a base depth inside a rect (the mound).
func _pile(r: Rect2, base: float) -> float:
	var v := 0.0
	var y := r.position.y
	while y < r.end.y:
		var x := r.position.x
		while x < r.end.x:
			v += maxf(Snow.depth_at(x, y) - base, 0.0) * 0.0625
			x += 0.25
		y += 0.25
	return v


func _max_depth(r: Rect2) -> float:
	var m := 0.0
	var y := r.position.y
	while y < r.end.y:
		var x := r.position.x
		while x < r.end.x:
			m = maxf(m, Snow.depth_at(x, y))
			x += 0.25
		y += 0.25
	return m


func test_tool_profiles_have_specialties() -> void:
	var t := func(id: String) -> ToolData: return Catalog.tool(StringName(id))
	var hands: ToolData = t.call("hands")
	var shovel: ToolData = t.call("small_shovel")
	var pusher: ToolData = t.call("wide_pusher")
	var lscr: ToolData = t.call("large_scraper")
	var sleigh: ToolData = t.call("snow_sleigh")
	for id in ["hands", "small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh"]:
		var d: ToolData = t.call(id)
		runner.check(d.is_shovel_type() and d.capacity > 0.0 and d.fill_rate > 0.0 and d.throw_distance > 0.0 and d.push_width > 0.0 and d.push_strength > 0.0,
			"%s has a full profile (fill, throw and push)" % id)
	runner.check(hands.throw_distance >= 1.0 and hands.throw_distance <= 2.0, "Hands toss a metre or two (%.1f m)" % hands.throw_distance)
	runner.check(hands.push_strength < shovel.push_strength and hands.capacity < shovel.capacity, "Hands are weak at both")
	runner.check(shovel.throw_distance > pusher.throw_distance and shovel.throw_distance > sleigh.throw_distance and shovel.throw_distance > lscr.throw_distance, "The small shovel is the best early thrower")
	runner.check(pusher.push_strength > shovel.push_strength * 3.0, "The pusher pushes much harder than the small shovel")
	runner.check(pusher.throw_distance < shovel.throw_distance * 0.6, "…but throws much worse")
	runner.check(lscr.throw_distance > pusher.throw_distance and lscr.throw_distance < shovel.throw_distance and lscr.push_strength > pusher.push_strength, "The large scraper sits between shovel and pusher")
	runner.check(sleigh.push_strength > pusher.push_strength and sleigh.throw_distance < hands.throw_distance, "The sleigh pushes hardest and barely throws")
	runner.check(not t.call("small_blower").uses_slot and not t.call("large_blower").uses_slot, "Blowers keep their machine controls (automatic chute)")
	# Behaviour: the same push with a pusher moves far more snow than with bare hands.
	var moved := {}
	for id in ["", "wide_pusher"]:
		await _load_world("fun")
		if id != "":
			Game.add_tool(id)
		await _frames(2)
		var spot := _lot_pt(-9.0, 4.0)
		Snow.set_rect(Rect2(spot - Vector2(4, 1), Vector2(8, 12)), 0.2)
		_place(spot, PI)
		await _frames(2)
		var m0 := Snow.stat_player_moved
		Input.action_press("secondary")
		Input.action_press("move_forward")
		await _frames(150)
		_release_all()
		moved[id] = Snow.stat_player_moved - m0
	runner.info("pushed in 2.5 s: hands %.3f m3, wide pusher %.3f m3" % [moved[""], moved["wide_pusher"]])
	runner.check(moved["wide_pusher"] > moved[""] * 3.0, "The pusher pushes far more snow than hands")


## Polish 2 §2: bigger bites. Hands carry and remove about twice as much as before (15 L handfuls,
## 35 L/s fill), every shovel-type tool stays clearly ahead of them, and the ladder holds.
func test_bigger_scoops_and_tool_ladder() -> void:
	var t := func(id: String) -> ToolData: return Catalog.tool(StringName(id))
	var hands: ToolData = t.call("hands")
	runner.check(hands.capacity >= 0.028 and hands.capacity <= 0.032, "A handful is about twice the old 15 L (%.0f L)" % (hands.capacity * 1000.0))
	runner.check(hands.fill_rate >= 0.065, "Hands fill about twice as fast (%.0f L/s)" % (hands.fill_rate * 1000.0))
	runner.check(hands.throw_distance <= 2.0, "…but still only toss a metre or two")
	runner.check(t.call("small_shovel").capacity > hands.capacity * 1.4 and t.call("standard_shovel").capacity > t.call("small_shovel").capacity * 1.2, "Hands → small shovel → standard shovel: each step carries clearly more")
	for id in ["small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh"]:
		var d: ToolData = t.call(id)
		runner.check(d.capacity > hands.capacity * 1.3 and d.fill_rate > hands.fill_rate, "%s stays clearly ahead of bare hands (%.0f L, %.0f L/s)" % [id, d.capacity * 1000.0, d.fill_rate * 1000.0])
	runner.check(t.call("large_scraper").capacity > t.call("snow_scraper").capacity and t.call("snow_sleigh").capacity > t.call("large_scraper").capacity * 3.0, "Scrapers step up, the sleigh carries by far the most")
	runner.check(t.call("electric_shovel").rate > 0.04, "The electric shovel chews faster too")
	# Removal rate with the real controls, against the same hands with the old values.
	var rates := {}
	var old := {"capacity": 0.015, "fill_rate": 0.035, "bite": 0.15}
	var new_vals := {"capacity": hands.capacity, "fill_rate": hands.fill_rate, "bite": hands.bite}
	for which in ["old", "new"]:
		var vals: Dictionary = old if which == "old" else new_vals
		for k in vals.keys():
			hands.set(k, vals[k])
		await _load_world("fun", 2024, 10.0, 0)
		var pl: Player = world.player
		var tc: ToolController = pl.tools
		var spot := _lot_pt(-8.0, 2.0)
		Snow.set_rect(Rect2(spot - Vector2(1, 1), Vector2(10, 6)), 0.7)
		var carried := 0.0
		# A row of scoop-and-toss strokes, each into fresh snow (a step sideways between strokes),
		# as a player working along the face of the snow does.
		for k in range(12):
			_place(spot + Vector2(k * 0.6, 0.0), PI)
			await _frames(1)
			var base := pl.yaw
			_look_down(-55.0)
			await _sweep_fill(30, 0.35)
			carried += tc.load
			pl.set_yaw(base + 1.5)
			_look_down(3.0)
			await _frames(2)
			Input.action_release("primary")
			await _frames(4)
		_release_all()
		rates[which] = carried / (12.0 * 36.0 / 60.0)
	for k in new_vals.keys():
		hands.set(k, new_vals[k])
	runner.info("hands removal with the real controls: old %.1f L/s, new %.1f L/s (x%.2f)" % [rates["old"] * 1000.0, rates["new"] * 1000.0, rates["new"] / maxf(rates["old"], 1e-6)])
	runner.check(rates["new"] > rates["old"] * 1.7, "Bare-hand removal rate roughly doubles")


## Polish 2 §1: both hands on every hand tool, in every pose, at every look angle, first and third
## person: the top hand closes around the grip, the other hand around the shaft lower down (both on
## the crossbar for the sleigh), never floating off it or past its ends.
func test_both_hands_grip_every_tool() -> void:
	await _load_world("fun", 2024, 10.0, 0)
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	_place(_lot_pt(-6.0, 3.0), PI)
	var bad := []
	var checked := 0
	var worst_fp := 0.0
	var worst_tp := 0.0
	for id in ["small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh", "electric_shovel"]:
		Game.slots[Game.selected] = id
		Game.inventory_changed.emit()
		await _frames(3)
		var sleigh := tc.data.kind == ToolData.Kind.SLEIGH
		var a := Vector3(-0.24, 0, 0) if sleigh else Vector3.ZERO
		var b := Vector3(0.24, 0, 0) if sleigh else ToolModels.tip(id)
		for tp in [false, true]:
			pl.set_third_person(tp)
			for pitch in [-60.0, -45.0, -20.0, 0.0, 25.0]:
				pl.pitch = deg_to_rad(pitch)
				pl.head.rotation.x = pl.pitch
				for pose in ["idle", "scoop", "hold", "push", "toss"]:
					tc.pose_override = pose
					tc.toss_override = 0.55
					tc.load = tc._capacity() * (0.8 if pose in ["hold", "toss"] else (0.4 if pose == "scoop" else 0.0))
					await _frames(14)
					var hands := []
					var seg := []
					if tp:
						var xf: Transform3D = tc.held_tp.global_transform
						seg = [xf * a, xf * b]
						for fore in [pl.model.forearm_l, pl.model.forearm_r]:
							hands.append((fore as Node3D).global_transform * Vector3(0, -0.33, -0.01))
					else:
						var xf2: Transform3D = tc.held_fp.transform
						seg = [xf2 * a, xf2 * b]
						for h in [tc.arms.hand_l, tc.arms.hand_r]:
							var hx: Transform3D = (h as Node3D).transform
							hands.append(hx.origin + hx.basis * ToolController.GRIP_IN_HAND)
					for k in range(2):
						var p: Vector3 = hands[k]
						var q := Geometry3D.get_closest_point_to_segment(p, seg[0], seg[1])
						var d := p.distance_to(q)
						# Third person: mitten centre on the bar (the fist is 13 cm across). First
						# person: the fist's closing point on the bar (real-scale viewmodel units).
						var lim := 0.06 if tp else 0.03
						if tp:
							worst_tp = maxf(worst_tp, d)
						else:
							worst_fp = maxf(worst_fp, d)
						checked += 1
						if d > lim:
							bad.append("%s %s %s pitch %d %s hand %.2f m off" % [id, "TP" if tp else "FP", pose, int(pitch), "left" if k == 0 else "right", d])
					if tp and not tc.tp_grip_ok:
						bad.append("%s TP %s pitch %d: left arm can't reach the shaft" % [id, pose, int(pitch)])
	tc.pose_override = ""
	pl.set_third_person(false)
	runner.info("grip check: %d hand placements, worst %.3f m FP / %.3f m TP" % [checked, worst_fp, worst_tp])
	runner.check(bad.is_empty(), "Both hands on the shaft for every tool, pose, look angle and view%s" % ("" if bad.is_empty() else ": " + ", ".join(bad.slice(0, 6))))


## Polish 2 §3: the outline of the box being worked on.
func test_box_outline_follows_work() -> void:
	await _load_world("fun", 2024, 10.0, 0)
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var ol: BoxOutline = world.box_outline
	var lot := Layout.player_lot
	var path_id := Boxes.lot_box(lot, "path")
	var drv_id := Boxes.lot_box(lot, "driveway")
	var hi := Layout.house_info(lot)
	var walk: Rect2 = hi["walkway"]
	runner.check(not ol.visible, "No outline before any work")
	# Scoop from the walkway with bare hands.
	var at := Vector2(walk.get_center().x, walk.position.y + 2.0)
	_place(at, 0.0)
	pl.set_yaw(atan2(0.0, -float(lot["dir"])))
	_look_down(-50.0)
	await _sweep_fill(30, 0.3)
	await _frames(3)
	runner.check(ol.visible and ol.box_id == path_id and ol.alpha > 0.5, "Scooping on the path outlines the path box (%s, %.2f)" % [ol.box_id, ol.alpha])
	# Outer boundary only, and only this box.
	var segs := Boxes.outline_segments(path_id)
	var total := 0.0
	var inner_edges := 0
	var foreign := 0
	for i in range(0, segs.size(), 2):
		var a: Vector2 = segs[i]
		var c: Vector2 = segs[i + 1]
		total += a.distance_to(c)
		var m := (a + c) * 0.5
		var n := Vector2(-(c - a).y, (c - a).x).normalized() * 0.125
		var in1 := Boxes.box_has_point(path_id, m + n)
		var in2 := Boxes.box_has_point(path_id, m - n)
		if in1 and in2:
			inner_edges += 1
		if not in1 and not in2:
			foreign += 1
	runner.check(inner_edges == 0 and foreign == 0, "The outline runs only along the box's outer edge (inner %d, stray %d)" % [inner_edges, foreign])
	runner.check(total > 20.0 and total < 60.0, "…all the way round the walkway, stairs and porch (%.1f m)" % total)
	runner.check(not Boxes.outline_segments(drv_id).is_empty() and ol.box_id != drv_id, "The driveway next to it isn't outlined")
	# Throw marker: back into the box is amber, out onto the lawn is fine.
	await _sweep_fill(20, 0.3)
	pl.set_yaw(atan2(0.0, -float(lot["dir"])))
	_look_down(5.0)
	await _frames(8)
	runner.check(tc.landing_back_in_box, "Aiming a throw down the path tints the landing marker (lands back in the box)")
	pl.set_yaw(atan2(0.0, -float(lot["dir"])) + PI * 0.5)
	await _frames(8)
	runner.check(not tc.landing_back_in_box and tc.landing.get("valid", false), "Aiming onto the lawn doesn't")
	Input.action_release("primary")
	await _frames(4)
	# Stop working: the outline fades after a few seconds.
	await _frames(int((BoxOutline.HOLD_S + BoxOutline.FADE_S + 0.6) * 60.0))
	runner.check(not ol.visible and ol.box_id == "", "The outline fades a few seconds after work stops")
	# Work again, then finish the box: the outline goes and the completion flash plays.
	_look_down(-50.0)
	pl.set_yaw(atan2(0.0, -float(lot["dir"])))
	await _sweep_fill(20, 0.3)
	_release_all()
	await _frames(2)
	runner.check(ol.visible, "Working again brings it back")
	var pb := Boxes.get_box(path_id)
	for r in pb["rects"]:
		Snow.set_rect(r, 0.004)
	Boxes.measure(pb, true)
	await _frames(2)
	runner.check(pb["complete"] and not ol.visible, "When the box completes the outline goes away")


## Polish 2 §5: snow refinements.
func test_snow_refinements() -> void:
	await _load_world("fun", 2024, 10.0, 0)
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	# Wading treads a trench; nothing leaves the area.
	var spot := _lot_pt(-8.0, 2.0)
	var area := Rect2(spot - Vector2(3, 1), Vector2(6, 9))
	Snow.set_rect(area, 0.65)
	Snow.relax_until_stable()
	var v0 := Snow.volume_in_rect(area)
	_place(spot, PI)
	await _hold("move_forward", 240)
	Snow.relax_until_stable()
	var p1 := Vector2(pl.global_position.x, pl.global_position.z)
	var mid := (spot + p1) * 0.5
	var trench := Snow.depth_at(mid.x, mid.y)
	var flank := maxf(Snow.depth_at(mid.x + 0.6, mid.y), Snow.depth_at(mid.x - 0.6, mid.y))
	runner.info("waded %.1f m: trench %.2f m, flanks %.2f m (was 0.65)" % [spot.distance_to(p1), trench, flank])
	runner.check(spot.distance_to(p1) > 1.0 and trench < 0.45, "Wading leaves a trench (%.2f m deep in 0.65 m snow)" % trench)
	runner.check(flank > 0.65, "…the snow is shouldered onto the flanks")
	runner.near(Snow.volume_in_rect(area), v0, 0.002, "…and no snow is lost")
	var t0 := Time.get_ticks_msec()
	_place(p1 - Vector2(0, 0.4) * 0.0, PI)
	# Walking back along your own trench is quicker than breaking new snow.
	pl.set_yaw(0.0)
	await _frames(2)
	var back0 := Vector2(pl.global_position.x, pl.global_position.z)
	await _hold("move_forward", 60)
	var back := Vector2(pl.global_position.x, pl.global_position.z).distance_to(back0)
	runner.check(back > 0.6 * 1.0, "Walking back down your own trench is easier (%.2f m in 1 s)" % back)
	t0 = t0
	# Scooping at your own feet: look straight down.
	var s2 := _lot_pt(-3.0, 3.0)
	Snow.set_rect(Rect2(s2 - Vector2(1.5, 1.5), Vector2(3, 3)), 0.5)
	_place(s2, PI)
	await _frames(2)
	var feet := Vector2(pl.global_position.x, pl.global_position.z) + pl.forward2() * 0.1
	var d0 := Snow.depth_at(feet.x, feet.y)
	_look_down(-82.0)
	await _sweep_fill(30, 0.2)
	_release_all()
	await _frames(2)
	runner.check(tc.load > 0.005 or Snow.depth_at(feet.x, feet.y) < d0 - 0.05, "Looking straight down scoops the snow at your feet (%.0f L)" % (tc.load * 1000.0))
	tc.dump_at_feet(true)
	# A blade pushed into deep snow is hidden in it (first person), not drawn on top.
	Game.add_tool("wide_pusher")
	await _frames(3)
	var s3 := _lot_pt(-6.0, 4.0)
	Snow.set_rect(Rect2(s3 - Vector2(2, 1), Vector2(4, 6)), 0.75)
	_place(s3, PI)
	_look_down(-20.0)
	Input.action_press("secondary")
	Input.action_press("move_forward")
	await _frames(30)
	var clip_y: float = tc.vm_clip_y
	_release_all()
	runner.check(clip_y > 0.3, "Pushing into deep snow, the first-person blade is clipped at the snow surface (%.2f m)" % clip_y)
	_look_down(5.0)
	await _frames(20)
	clip_y = tc.vm_clip_y
	runner.check(clip_y < -100.0, "Just carrying the tool, nothing is clipped")
	# Old loose snow hardens: a thrown pile, left for a few days, holds a cut face.
	var s4 := _lot_pt(5.0, 3.0)
	Snow.set_rect(Rect2(s4 - Vector2(2, 2), Vector2(4, 4)), 0.0)
	Snow.deposit(s4, 0.6, 1.0)
	Snow.relax_until_stable()
	var ci := Snow.cell_z(s4.y) * Snow.W + Snow.cell_x(s4.x)
	var loose0: float = Snow.loose[ci]
	Snow.advance_settle(3.0 * 1440.0)
	Snow.sync_all()
	runner.check(loose0 > 0.05 and Snow.loose[ci] < loose0 * 0.15, "Loose snow firms up over a few days (%.2f → %.2f m loose)" % [loose0, Snow.loose[ci]])
	var top0 := Snow.depth_at(s4.x + 0.4, s4.y)
	Snow.set_rect(Rect2(s4.x - 1.0, s4.y - 1.0, 0.75, 2.0), 0.0)
	Snow.relax_until_stable()
	runner.check(Snow.depth_at(s4.x - 0.125, s4.y) > top0 * 0.6, "…so a cut into the old pile keeps a steep face")


## Walk toward a point by steering the real controls. Returns seconds taken (or -1).
func _walk_to(target: Vector2, max_frames: int, stop_dist := 0.8) -> float:
	var pl: Player = world.player
	for k in range(max_frames):
		var d := target - Vector2(pl.global_position.x, pl.global_position.z)
		if d.length() < stop_dist:
			Input.action_release("move_forward")
			return k / 60.0
		pl.set_yaw(atan2(-d.x, -d.y))
		Input.action_press("move_forward")
		await _tree().physics_frame
	Input.action_release("move_forward")
	return -1.0


func test_wading_from_the_start_in_both_modes() -> void:
	for mode in ["fun", "survival"]:
		await _load_world(mode, 2024, 9.0, 0)
		var pl: Player = world.player
		var hi := Layout.house_info(Layout.player_lot)
		var nhi := Layout.house_info(Layout.neighbor_lot)
		var door_out: Vector2 = hi["porch_center"]
		pl.teleport(Vector3(door_out.x, Layout.PORCH_H + 0.05, door_out.y), 0.0)
		await _frames(3)
		var walk: Vector2 = hi["walkway"].get_center()
		var mb: Vector2 = hi["mailbox_path_point"]   # the foot of the walk, beside the mailbox
		var t1 := await _walk_to(walk, 1200)
		var t2 := await _walk_to(mb, 2400)
		var p_mb := Vector2(pl.global_position.x, pl.global_position.z)
		var nwalk: Vector2 = nhi["walkway"].get_center()
		var ndoor: Vector2 = nhi["porch_center"]
		var t3 := await _walk_to(nwalk, 4000)
		var t4 := await _walk_to(ndoor, 2400, 2.4)   # within talking range of Gerry on his porch
		runner.info("%s: door→walkway %.1f s, →mailbox %.1f s, →Gerry's walk %.1f s, →his door %.1f s" % [mode, t1, t2, t3, t4])
		runner.check(t2 > 0.0, "%s: the player can wade from the door to the mailbox at the start" % mode)
		runner.check(t3 > 0.0 and t4 > 0.0, "%s: …and on to Gerry's door" % mode)
		var straight := p_mb.distance_to(nwalk)
		runner.check(t3 > 0.0 and straight / t3 < Catalog.balance.walk_speed * 0.45, "%s: wading through the opening snow is slow (%.2f m/s)" % [mode, straight / maxf(t3, 0.01)])


func test_wading_speed_hips_and_banks() -> void:
	await _load_world("fun")
	var pl: Player = world.player
	var spot := _lot_pt(-9.0, 6.0)
	var dists := []
	for d in [0.0, 0.3, 0.6, 0.85]:
		Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 9)), d)
		_place(spot, PI)
		await _frames(2)
		var p0 := pl.global_position
		await _hold("move_forward", 60)
		dists.append(Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length())
	runner.info("metres in 1 s at 0 / 0.3 / 0.6 / 0.85 m: %s" % str(dists.map(func(x): return snappedf(x, 0.01))))
	runner.check(dists[0] > dists[1] and dists[1] > dists[2] and dists[2] > dists[3], "Speed drops with depth")
	runner.check(dists[3] > 0.15 and dists[3] < dists[0] * 0.25, "Near hip height it's a crawl")
	# Above the hips: a wall.
	Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 9)), CharacterModel.HIP_HEIGHT + 0.1)
	Snow.set_rect(Rect2(spot - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), 0.0)
	_place(spot, PI)
	await _frames(2)
	var q0 := pl.global_position
	await _hold("move_forward", 60)
	var wall_moved := Vector2(pl.global_position.x - q0.x, pl.global_position.z - q0.z).length()
	runner.check(wall_moved < 0.25, "Snow above the hips stops the player (moved %.2f m)" % wall_moved)
	# Street banks: lower than the hips can be waded across, taller ones block.
	for h in [0.7, 1.3]:
		var p := _lot_pt(-9.0, -1.0)
		Snow.set_rect(Rect2(p.x - 3, 76, 6, 13), 0.0)
		Snow.set_rect(Rect2(p.x - 3, 77.5, 6, 1.5), h)   # a steep bank along the street edge
		_place(Vector2(p.x, 80.5), PI)                    # on the cleared road, facing the bank (north = -z)
		pl.set_yaw(0.0)
		await _frames(2)
		await _hold("move_forward", 150)
		var crossed := pl.global_position.z < 77.0
		if h < CharacterModel.HIP_HEIGHT:
			runner.check(crossed, "A %.1f m bank (below the hips) can be waded across" % h)
		else:
			runner.check(not crossed and pl.global_position.z > 78.8, "A %.1f m bank (above the hips) blocks the player" % h)


func test_dig_out_by_hand_after_a_major_event() -> void:
	await _load_world("survival", 2024, 10.0, 2)
	var pl: Player = world.player
	var hi := Layout.house_info(Layout.player_lot)
	# A major event: 1.1 m of snow in a few hours while the player is inside.
	Weather.force(Weather.C.BLIZZARD, 4.0, 27.5)
	Clock.skip(4 * 60.0)
	Weather.override_cond = -1
	Snow.sync_all()
	var porch: Vector2 = hi["porch_center"]
	var stair: Rect2 = hi["stairs"]
	var step_front := Vector2(stair.get_center().x, stair.get_center().y) + Vector2(hi["facing"]) * 1.2
	runner.info("after the storm: %.2f m on the walkway" % Snow.depth_at(step_front.x, step_front.y))
	pl.teleport(Vector3(porch.x, Layout.PORCH_H + 0.05, porch.y))
	var face: Vector2 = hi["facing"]
	pl.set_yaw(atan2(-face.x, -face.y))
	await _frames(3)
	var start := Vector2(pl.global_position.x, pl.global_position.z)
	await _hold("move_forward", 90)
	var blocked := Vector2(pl.global_position.x, pl.global_position.z).distance_to(start) < 1.6
	runner.check(blocked, "The storm buries the way out above the hips")
	# Dig with bare hands: sweep-fill in front, turn, toss aside, step forward; repeat.
	var base := pl.yaw
	var free := false
	for k in range(320):
		pl.set_yaw(base)
		_look_at_snow_ahead()
		await _sweep_fill(26, 0.35)
		pl.set_yaw(base + (1.4 if k % 2 == 0 else -1.4))
		_look_down(-5.0)
		await _frames(2)
		Input.action_release("primary")
		await _frames(2)
		pl.set_yaw(base)
		await _hold("move_forward", 20)
		if Vector2(pl.global_position.x, pl.global_position.z).distance_to(start) > 3.2:
			free = true
			break
	runner.info("dug %.1f m out from the porch" % Vector2(pl.global_position.x, pl.global_position.z).distance_to(start))
	runner.check(free, "The player can always dig out with bare hands")


func test_boxes_driveway_path_reopen_and_save() -> void:
	await _load_world("fun", 2024, 10.0, 1)
	var lot := Layout.player_lot
	var drv := Boxes.get_box(Boxes.lot_box(lot, "driveway"))
	var path := Boxes.get_box(Boxes.lot_box(lot, "path"))
	runner.check(not drv.is_empty() and not path.is_empty() and drv["id"] != path["id"], "The driveway and the path to the house are separate boxes")
	runner.check(not Boxes.get_box("road_maple_w").is_empty(), "Streets are divided into boxes too")
	for r in drv["rects"]:
		Snow.set_rect(r, 0.004)
	Boxes.measure(drv, true)
	runner.check(drv["complete"] and not path["complete"], "Clearing the driveway completes only the driveway box")
	runner.check(Snow.volume_in_rect(drv["rects"][0]) < 1e-5, "…which shows bare ground")
	Saves.save_game()
	Snow.add_snowfall(0.03)
	Boxes.measure(drv, true)
	runner.check(not drv["complete"], "New snowfall reopens a completed box")
	runner.check(Saves.load_game("fun"), "Load")
	var drv2 := Boxes.get_box(Boxes.lot_box(lot, "driveway"))
	runner.check(drv2["complete"] and not Boxes.get_box(Boxes.lot_box(lot, "path"))["complete"], "Box completion state survives save/load")


func test_snowfall_adds_on_top_everywhere() -> void:
	await _load_world("fun", 2024, 10.0, 2)
	var lot := Layout.player_lot
	var hi := Layout.house_info(lot)
	var yard := _lot_pt(-9.0, 6.0)
	var drv: Rect2 = hi["driveway_private"]
	var dpt := drv.get_center()
	Snow.set_rect(drv, 0.0)
	var bank := _lot_pt(10.5, 4.0)
	Snow.deposit(bank, 1.2, 0.8)
	Snow.relax_until_stable()
	var pts := {"yard": yard, "driveway": dpt, "bank": bank}
	var how := [["real time", 0], ["sleep", 1], ["F1 skip", 2]]
	for h in how:
		var d0 := {}
		for k in pts:
			d0[k] = Snow.depth_at(pts[k].x, pts[k].y)
		var f0 := Snow.fall_total
		Weather.force(Weather.C.MODERATE, 30.0, 1.5)
		match h[1]:
			0:
				for i in range(240):
					Clock.advance(0.5)
			1:
				world._do_sleep()
				await _frames(280)
			2:
				var d := DebugMenu.new()
				d.world = world
				world.ui.add_child(d)
				d._skip_days(1)
				d.queue_free()
		Weather.override_cond = -1
		var fell := Snow.fall_total - f0
		for k in pts:
			var gain: float = Snow.depth_at(pts[k].x, pts[k].y) - d0[k]
			var m := Snow.fall_mult[Snow.cell_z(pts[k].y) * Snow.W + Snow.cell_x(pts[k].x)]
			runner.check(gain > fell * m * 0.95, "%s: snowfall adds on top of the %s (%.3f m fell, +%.3f m)" % [h[0], k, fell, gain])


func test_computer_locked_until_gerry_and_saved() -> void:
	await _load_world("survival", 2024, 10.0, 0)
	world.open_computer()
	await _frames(1)
	runner.check(world.modal == null, "The computer is locked before Gerry's quest")
	runner.check(world.hud.subtitle_l.text.to_lower().contains("gerry"), "…with a message saying why and what to do")
	Saves.save_game()
	world.debug_complete_tutorial()
	runner.check(Game.computer_unlocked(), "Completing Gerry's quest unlocks it")
	world.open_computer()
	await _frames(1)
	runner.check(world.modal_kind == "computer", "The computer opens after the quest")
	world.close_modal()
	Saves.save_game()
	_fresh_flags()
	runner.check(Saves.load_game("survival") and Game.computer_unlocked(), "Unlocked state restored by a save")
	Game.flags["computer_unlocked"] = false
	Game.flags["stage"] = Game.Stage.LETTER_READ
	Saves.save_game()
	Game.flags["computer_unlocked"] = true
	runner.check(Saves.load_game("survival") and not Game.computer_unlocked(), "Locked state restored by a save")


## Polish 2 §4: find the keys, get in and drive the truck out of the driveway, with real input,
## in both modes. Covers the no-keys message, the blocked-by-snow message and saves.
func test_truck_keys_end_to_end() -> void:
	for mode in ["fun", "survival"]:
		await _load_world(mode, 2024, 10.0, 0)
		var pl: Player = world.player
		var truck: Vehicle = world.vehicle_nodes()[0]
		var tp := Vector2(truck.global_position.x, truck.global_position.z)
		var tfwd := Vector2(-truck.global_transform.basis.z.x, -truck.global_transform.basis.z.z).normalized()
		var tright := Vector2(-tfwd.y, tfwd.x)
		# Walk up to the driver's door (snow on and around the truck stays as it is).
		var door := tp - tright * (truck.data.width * 0.5 + 1.0)
		await _face_truck(door, truck)
		runner.info("%s: at the door, prompt '%s'" % [mode, pl.focus_prompt])
		runner.check(pl.focus_prompt.contains("locked"), "%s: the truck is locked before the keys are found" % mode)
		Notify.history.clear()
		await _press_event("interact")
		await _frames(2)
		runner.check(pl.state == "foot", "%s: it can't be entered without keys" % mode)
		runner.check(_notified("keys"), "%s: trying the locked truck says the keys are missing" % mode)
		# Find the keys: dig them out of the lawn and pick them up.
		var kp: Array = Game.flags["keys_pos"]
		var k2 := Vector2(kp[0], kp[1])
		Snow.set_rect(Rect2(k2 - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), 0.0)
		_place(k2 + Vector2(0, 1.0), 0.0)
		await _frames(2)
		pl.set_yaw(atan2(-(k2 - (k2 + Vector2(0, 1.0))).x, -(k2 - (k2 + Vector2(0, 1.0))).y))
		_look_down(-55.0)
		await _frames(4)
		runner.info("%s: at the keys, prompt '%s'" % [mode, pl.focus_prompt])
		await _press_event("interact")
		await _frames(2)
		runner.check(Game.flags.get("truck_keys", false), "%s: the keys are found with E" % mode)
		Saves.save_game()
		Game.flags["truck_keys"] = false
		runner.check(Saves.load_game(mode) and Game.flags.get("truck_keys", false), "%s: the keys survive save/load" % mode)
		# Back to the truck: in, start, try to drive — the opening snow holds it.
		await _face_truck(door, truck)
		runner.info("%s: at the door with keys, prompt '%s'" % [mode, pl.focus_prompt])
		runner.check(pl.focus_prompt.contains("Drive"), "%s: with the keys the truck offers to drive (snow on it doesn't matter)" % mode)
		await _press_event("interact")
		await _frames(3)
		runner.check(pl.state == "vehicle" and truck.engine_on, "%s: in the truck with the engine running" % mode)
		var p0 := truck.global_position
		await _hold("veh_reverse", 90)
		runner.info("%s: stuck drive moved %.2f m, status '%s'" % [mode, truck.global_position.distance_to(p0), truck.status_text])
		runner.check(truck.global_position.distance_to(p0) < 1.5, "%s: deep snow holds the truck" % mode)
		runner.check(truck.status_text.contains("cm") and (truck.status_text.to_lower().contains("wheel") or truck.status_text.to_lower().contains("bank")), "%s: the game says what's blocking (%s)" % [mode, truck.status_text])
		await _press_event("interact")
		await _frames(3)
		runner.check(pl.state == "foot", "%s: out of the truck again" % mode)
		# Dig it out: clear around the truck and the driveway behind it down to the street.
		var drv: Rect2 = Boxes.get_box(Boxes.lot_box(Layout.player_lot, "driveway"))["rects"][0]
		Snow.set_rect(drv, 0.03)
		Snow.set_rect(Rect2(drv.position.x - 1.0, drv.position.y - 9.0, drv.size.x + 2.0, 9.0), 0.03, true)
		await _face_truck(door, truck)
		await _press_event("interact")
		await _frames(3)
		p0 = truck.global_position
		await _hold("veh_accelerate", 240)
		var moved := truck.global_position.distance_to(p0)
		var tz := truck.global_position.z
		runner.info("%s: dug out, drove %.1f m (truck z %.1f, driveway apron at %.1f), status '%s'" % [mode, moved, tz, drv.position.y, truck.status_text])
		runner.check(moved > 6.0, "%s: dug out, the truck drives down the driveway (%.1f m)" % [mode, moved])
		runner.check(tz < drv.position.y + 1.0, "%s: …and out onto the street" % mode)
		_release_all()
		await _press_event("interact")
		await _frames(2)



## Press and release an action as a real input event (goes through _unhandled_input like a key).
func _press_event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(1)


func _face_truck(at: Vector2, truck: Vehicle) -> void:
	var pl: Player = world.player
	_place(at, 0.0)
	await _frames(2)
	var to := Vector2(truck.global_position.x, truck.global_position.z) - at
	pl.set_yaw(atan2(-to.x, -to.y))
	_look_down(-12.0)
	await _frames(4)


func _notified(word: String) -> bool:
	for n in Notify.history:
		if str(n.get("text", n)).to_lower().contains(word):
			return true
	return false


func _fresh_flags() -> void:
	Game.flags = {"stage": Game.Stage.START}


func test_zz_cleanup() -> void:
	await _unload()
	Game.force_input = false
	_release_all()
