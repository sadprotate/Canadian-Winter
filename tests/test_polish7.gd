extends RefCounted
## Polish pass 7 tests. Same harness as test_polish6.gd (the runner calls every test_* method;
## runner.check / near / info). Each section of the round adds its tests under its own header.

var runner
var world: Node = null


func _tree() -> SceneTree:
	return runner.get_tree()


func _frames(n: int) -> void:
	for i in range(n):
		await _tree().physics_frame


func _unload() -> void:
	if world and is_instance_valid(world):
		_tree().paused = false
		world.queue_free()
		await _tree().process_frame
		await _tree().process_frame
	world = null


func _release_all() -> void:
	for a in Settings.ACTIONS.keys():
		Input.action_release(a)


## A new game (fun, seed 2024) on Dec 2 at `hour`, the tutorial done, the keys found, the clock
## stopped, the sky clear, relaxation by tile count only (the same every run).
func _world(mode := "fun", hour := 12.0) -> void:
	await _unload()
	Game.force_input = true
	Game.new_game(mode, 2024)
	Game.flags["mail_read"] = true
	Game.flags["computer_unlocked"] = true
	Game.flags["truck_keys"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	Clock.reset(Clock.at(1, hour))
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(3)
	Clock.running = false
	Weather.force(Weather.C.CLEAR, 48.0)
	world.snow_renderer.relax_usec = 0


## A vehicle `id` at (x, z) facing `yaw` (−π/2: east along Maple Street), the player in it.
func _truck(id: String, x: float, z := 84.95, yaw := -PI * 0.5) -> Vehicle:
	var e := {"uid": Game.uid(), "id": id, "pos": Vector3(x, 0, z), "yaw": yaw, "snow": 0.0}
	Game.vehicles.append(e)
	var v: Vehicle = world.spawn_vehicle_node(e)
	await _frames(2)
	v.enter_vehicle(world.player)
	await _frames(1)
	return v


## Out of the vehicle and the vehicle gone (the next run starts in the same world).
func _drop(v: Vehicle) -> void:
	v.exit_vehicle()
	Game.vehicles.erase(v.entry)
	v.queue_free()
	await _frames(2)


func _said(word: String) -> bool:
	for n in Notify.history:
		if str(n.get("text", n)).contains(word):
			return true
	return false


# =============================================================================
# §10 The plow truck from the start, good in snow
# =============================================================================

## The ids the §10 tests run over: the plain pickup (older saves) and the pickup with its plow (a
## new game's truck).
const S10_TRUCKS := ["pickup", "pickup_plow"]


## Hold `action` up to `frames`; stop early when the front passes x = stop_x (driving east) or the
## vehicle has stood still for a second. Returns {dist, stuck (frames), blocked (frames), reasons,
## front}.
func _s10_drive(v: Vehicle, frames: int, action := "veh_accelerate", stop_x := INF) -> Dictionary:
	var p0 := v.global_position
	var fwd := -v.global_transform.basis.z
	var r := {"stuck": 0, "blocked": 0, "reasons": []}
	Input.action_press(action)
	var still := 0
	for f in range(frames):
		await _tree().physics_frame
		if v.stuck:
			r["stuck"] += 1
		if v.blocked_reason != "":
			r["blocked"] += 1
			if not (r["reasons"] as Array).has(v.blocked_reason):
				r["reasons"].append(v.blocked_reason)
		still = still + 1 if absf(v.speed) < 0.05 and f > 20 else 0
		if still > 60 or v.global_position.x + v.data.length * 0.5 > stop_x:
			break
	Input.action_release(action)
	await _frames(1)
	r["dist"] = (v.global_position - p0).dot(fwd)
	r["front"] = v.global_position.x + v.data.length * 0.5
	return r


## Round 5 §12's bank across Maple Street (west section): a flat top 2 m long at height h from x,
## with 0.5 m shoulders at half height; the rest of the section at 3 cm.
func _s10_bank(x: float, h: float) -> void:
	Snow.set_rect(Rect2(0, 79, 92, 8), 0.03)
	Snow.set_rect(Rect2(x, 79, 2.0, 8), h)
	Snow.set_rect(Rect2(x - 0.5, 79, 0.5, 8), h * 0.5)
	Snow.set_rect(Rect2(x + 2.0, 79, 0.5, 8), h * 0.5)


## A new game owns the pickup with its plow, where the plain pickup stood, and nothing else; the
## blade fits in the driveway, clear of the sidewalk, the shovel, the mailbox and the keys.
func test_s10_new_game_owns_the_plowed_truck() -> void:
	await _unload()
	for mode in ["fun", "survival"]:
		Game.new_game(mode, 2024)
		var ids := Game.vehicles.map(func(v): return str(v["id"]))
		var ts0 := Game.truck_start()
		runner.check(ids == ["pickup_plow"] and (Game.vehicles[0]["pos"] as Vector3).is_equal_approx(ts0["pos"]) and is_equal_approx(float(Game.vehicles[0]["yaw"]), float(ts0["yaw"])) and not Game.flags.get("truck_keys", true),
			"§10 %s: a new game owns the pickup with its plow and no plain pickup %s, at truck_start(), its keys still missing" % [mode, str(ids)])
	# The blade (at any angle) and the truck's body, where the truck starts.
	var vd: VehicleData = Catalog.vehicle(&"pickup_plow")
	var info := VehicleModels.build(vd)
	var ts := Game.truck_start()
	var xf := Transform3D(Basis(Vector3.UP, float(ts["yaw"])), ts["pos"])
	var pts := []
	for a in [-vd.blade_max_angle_deg, 0.0, vd.blade_max_angle_deg]:
		for s in [-1.0, 1.0]:
			for dz in [-0.15, 0.15]:     # the plate's 10 cm, tilted
				var lp: Vector3 = (info["blade_pivot"] as Vector3) + Vector3(s * vd.blade_width * 0.5, 0, dz).rotated(Vector3.UP, -deg_to_rad(a))
				pts.append(xf * lp)
	for s in [-1.0, 1.0]:
		for e in [-1.0, 1.0]:
			pts.append(xf * Vector3(s * vd.width * 0.5, 0, e * vd.length * 0.5))
	var hi := Layout.house_info(Layout.player_lot)
	var drv: Rect2 = hi["driveway"]
	var walk: Rect2 = hi["sidewalk"]
	var garage: Rect2 = hi["garage"]
	var sh: Vector2 = Game.shovel_spot()
	var mb: Vector2 = hi["mailbox"]
	var kp := Vector2(Game.flags["keys_pos"][0], Game.flags["keys_pos"][1])
	var bad := []
	var near_shovel := INF
	var near_mail := INF
	var near_keys := INF
	for p3 in pts:
		var p := Vector2(p3.x, p3.z)
		if p.x < drv.position.x or p.x > drv.end.x or p.y < walk.end.y or p.y > garage.position.y:
			bad.append(str(p))
		near_shovel = minf(near_shovel, p.distance_to(sh))
		near_mail = minf(near_mail, p.distance_to(mb))
		near_keys = minf(near_keys, p.distance_to(kp))
	runner.check(bad.is_empty() and near_shovel > 1.0 and near_mail > 3.0 and near_keys > 3.0,
		"§10 the truck and its blade (±%d°) fit in the driveway, clear of the sidewalk and the garage %s; nearest the shovel %.2f m, the mailbox %.1f m, the keys %.1f m" % [int(vd.blade_max_angle_deg), str(bad), near_shovel, near_mail, near_keys])


## The keys lock the plowed truck as they locked the plain pickup: "(locked)" and the locked message.
func test_s10_keys_lock_the_plowed_truck() -> void:
	await _world()
	Game.flags["truck_keys"] = false
	var pl: Player = world.player
	var truck: Vehicle = world.vehicle_nodes()[0]
	Notify.history.clear()
	truck.interact(pl)
	await _frames(2)
	runner.check(truck.data.id == &"pickup_plow" and truck.interact_prompt(pl) == "[E] Pickup truck (locked)" and pl.state == "foot" and _said("keys are missing"),
		"§10 without the keys: \"%s\"; E leaves you on foot and says the keys are missing" % truck.interact_prompt(pl))
	Game.flags["truck_keys"] = true
	runner.check(truck.interact_prompt(pl) == "[E] Drive %s" % truck.data.display_name, "§10 …with them: \"%s\"" % truck.interact_prompt(pl))
	await _unload()


## Its wheels are the pickup's, blade up or down: not stuck in 50 cm under the wheels (stuck from
## pickup_stuck_depth, where its clearance alone said 39 cm).
func test_s10_wheels_in_50_cm() -> void:
	var b: BalanceData = Catalog.balance
	await _world()
	for run in [["pickup", false], ["pickup_plow", false], ["pickup_plow", true]]:
		Snow.set_rect(Rect2(0, 79, 92, 8), 0.5)
		Snow.relax_until_stable()
		Snow.push_rng.seed = Snow.PUSH_SEED + 10
		var v := await _truck(run[0], 10.0)
		if run[1]:
			v._toggle_tool()
		var wd := v.wheel_snow_depth()
		var r := await _s10_drive(v, 300)
		runner.check(wd > v.data.clearance * 1.15 and v.stuck_depth() == b.pickup_stuck_depth and r["stuck"] == 0 and r["dist"] > 5.0,
			"§10 %s, blade %s: %d cm under the wheels (its clearance alone: stuck from %d cm), stuck from %d cm: never stuck, %.1f m in 5 s" % [run[0], "down" if run[1] else "up", int(round(wd * 100.0)), int(round(v.data.clearance * 115.0)), int(round(v.stuck_depth() * 100.0)), r["dist"]])
		await _drop(v)
	await _unload()


## With the blade up it gets through a bank as deep as the plain pickup does with the same run-up
## (its clearance alone made 65 cm a wall).
func test_s10_bank_with_a_run_up() -> void:
	await _world()
	var through := {}
	for h in [0.6, 0.7, 0.8, 0.9]:
		for id in S10_TRUCKS:
			_s10_bank(30.0, h)
			Snow.relax_until_stable()
			Snow.push_rng.seed = Snow.PUSH_SEED + 11
			var half: float = Catalog.vehicle(StringName(id)).length * 0.5
			var v := await _truck(id, 29.5 - 4.0 - half)     # a 4 m run-up
			var r := await _s10_drive(v, 600, "veh_accelerate", 40.0)
			through["%s %d" % [id, int(round(h * 100.0))]] = r["front"] > 40.0
			runner.info("%s, %d cm bank, 4 m run-up: front at x %.1f %s" % [id, int(round(h * 100.0)), r["front"], str(r["reasons"])])
			await _drop(v)
	var worse := []
	for k in through.keys():
		if k.begins_with("pickup ") and through[k] and not through[k.replace("pickup ", "pickup_plow ")]:
			worse.append(k)
	runner.check(worse.is_empty() and through["pickup_plow 70"] and through["pickup_plow 80"],
		"§10 blade up, 4 m run-up: through every bank the plain pickup gets through %s, 70 and 80 cm too (its clearance alone made 65 cm a wall)" % str(through))
	await _unload()


## With the blade up the shove casts its snow ahead of the raised blade and clear of the truck's
## path, as the plain pickup's does (the cast in proportion to the truck's width: 1.5 m alone left
## a quarter of it in the 2.4 m truck's path).
func test_s10_shove_lands_clear_of_the_path() -> void:
	await _world()
	var share := {}
	var behind := []
	for id in S10_TRUCKS:
		var shares := []
		for lz in [83.0, 83.05, 83.1, 83.15, 83.2]:
			Snow.set_rect(Rect2(0, 79, 92, 8), 0.0)
			var v := await _truck(id, 20.0, lz)
			v.exit_vehicle()
			await _frames(2)
			var fwd := Vector2(1, 0)
			var right := Vector2(-fwd.y, fwd.x)
			var p := Vector2(v.global_position.x, v.global_position.z)
			var hw := v.data.width * 0.5
			var front := v.data.length * 0.5
			Snow.set_rect(Rect2(p.x + front - 1.6, lz - 1.6, 1.9, 3.2), 0.6)
			var reg := Rect2(p.x - 4.0, 79.0, 14.0, 8.0)
			var before := {}
			for zi in range(int(reg.size.y * Snow.INV_CELL)):
				for xi in range(int(reg.size.x * Snow.INV_CELL)):
					var c := reg.position + Vector2(xi + 0.5, zi + 0.5) * Snow.CELL
					before[Vector2i(xi, zi)] = Snow.depth_at(c.x, c.y)
			Snow.push_rng.seed = Snow.PUSH_SEED + 3
			v._shove(fwd, fwd * 0.25)
			var landed := 0.0
			var inside := 0.0
			for k in before.keys():
				var c := reg.position + Vector2(k.x + 0.5, k.y + 0.5) * Snow.CELL
				var dd: float = Snow.depth_at(c.x, c.y) - float(before[k])
				if dd <= 1e-6:
					continue
				var lat := (c - p).dot(right)
				var ahead := (c - p).dot(fwd) - front
				# The part of the cell inside the truck's path (the grid doesn't line up with 2.4 m).
				var ov := clampf(minf(lat + Snow.CELL * 0.5, hw) - maxf(lat - Snow.CELL * 0.5, -hw), 0.0, Snow.CELL) / Snow.CELL
				landed += dd
				inside += dd * ov
				if absf(lat) < hw and ahead < 0.0:
					behind.append("%s %.2f,%.2f" % [id, ahead, lat])
			shares.append(inside / maxf(landed, 1e-9))
			Game.vehicles.erase(v.entry)
			v.queue_free()
			await _frames(2)
		share[id] = shares.reduce(func(a, x): return a + x, 0.0) / shares.size()
		runner.info("%s: share in its path by lane offset %s" % [id, str(shares.map(func(x): return snappedf(x, 0.001)))])
	runner.check(behind.is_empty() and share["pickup_plow"] < 0.05 and share["pickup"] < 0.05,
		"§10 blade up, the shove: nothing lands on or behind the raised blade %s; in its path %.1f %% (the plain pickup %.1f %%)" % [str(behind), share["pickup_plow"] * 100.0, share["pickup"] * 100.0])
	await _unload()


## Contracts: the starting truck counts as hand tools (day one's listing sizes are those with no
## vehicle) and satisfies a street section's "plow or blower vehicle".
func test_s10_starting_truck_and_contracts() -> void:
	await _world()
	var day := Clock.day_index()
	var board := func() -> Array:
		Contracts.listings.clear()
		Contracts._generate_listings(day, true)
		return Contracts.listings.map(func(l): return "%s %s %.4f %d" % [l["address"], l["job"], float(l["now_volume"]), int(l["budget"])])
	var with_truck: Array = board.call()
	var cap := Contracts.equipment_capability()
	var res_cap := Contracts.res_cap_m3()
	var kept := Game.vehicles.duplicate()
	Game.vehicles.clear()
	var without: Array = board.call()
	Game.vehicles.assign(kept)
	runner.check(cap == 0 and is_equal_approx(res_cap, Catalog.balance.listing_res_max_m3) and with_truck == without and not with_truck.is_empty(),
		"§10 day one: capability %d with the starting truck, the same %d listings as with no vehicle" % [cap, with_truck.size()])
	var th: PackedFloat32Array = Catalog.balance.rep_tier_thresholds
	Contracts.adjust_reputation(th[2] - Game.reputation)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var lr := Contracts._add_municipal_listing(Layout.road_segments[1], day, rng)
	runner.check(not Contracts.listing_needs_vehicle(lr) and Contracts.listing_lock_text(lr) == "", "§10 …and at the City tier a street section isn't locked for a vehicle (\"%s\")" % Contracts.listing_lock_text(lr))
	Game.vehicles.clear()
	runner.check(Contracts.listing_lock_text(lr) == "Needs a plow or a blower vehicle", "§10 …without it, it is (\"%s\")" % Contracts.listing_lock_text(lr))
	Game.vehicles.assign(kept)
	await _unload()
