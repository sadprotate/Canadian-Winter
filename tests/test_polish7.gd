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


# =============================================================================
# §11 Blade up/down, push and pull
# =============================================================================

## The vehicles with a blade the player drives (Decision 2), and those without one.
const S11_BLADES := ["pickup_plow", "atv_blade", "tractor_blade", "plow_truck", "grader"]
const S11_NO_BLADE := ["pickup", "tractor_blower", "rotary_blower", "dump_truck"]


## A real key press and release (through the viewport: _input, the GUI, _unhandled_input), then a
## pause that keeps the presses under the per-second cap (Settings.accept_press).
func _s11_key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await _frames(2)
	await _frames(12)


func _s11_action(action: String, down: bool) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = down
	return e


## The key an action is bound to now (its first binding).
func _s11_bound(action: String) -> Key:
	var e := Settings.decode(String(Settings.bindings[action][0]))
	return (e as InputEventKey).physical_keycode


## The settings file as it is (or null), to put back after a test that writes it (rebind saves).
func _s11_backup() -> Variant:
	if not FileAccess.file_exists(Settings.PATH):
		return null
	return FileAccess.get_file_as_bytes(Settings.PATH)


func _s11_restore(saved: Variant) -> void:
	if saved == null:
		if FileAccess.file_exists(Settings.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()
	Settings.load_controls()


## The actions: in the vehicle context right after the blade toggle, Up and Down by default, capped,
## no conflict anywhere; their labels from the input map.
func test_s11_the_actions() -> void:
	var keys: Array = Settings.ACTIONS.keys()
	var at := keys.find("veh_tool")
	runner.check(keys[at + 1] == "veh_blade_up" and keys[at + 2] == "veh_blade_down"
		and Settings.ACTIONS["veh_blade_up"][0] == "Raise the blade" and Settings.ACTIONS["veh_blade_down"][0] == "Lower the blade"
		and Settings.ACTIONS["veh_blade_up"][1] == "vehicle" and Settings.ACTIONS["veh_blade_down"][1] == "vehicle"
		and Settings.ACTIONS["veh_blade_up"][2] == ["key:%d" % KEY_UP] and Settings.ACTIONS["veh_blade_down"][2] == ["key:%d" % KEY_DOWN],
		"§11 \"Raise the blade\" (Up) and \"Lower the blade\" (Down), vehicle actions beside the blade toggle")
	runner.check(Settings.RATE_LIMITED.has("veh_blade_up") and Settings.RATE_LIMITED.has("veh_blade_down"), "§11 …both capped per second (accept_press)")
	var bad := []
	for place in Settings.PLACES:
		if not Settings.conflicts(place).is_empty():
			bad.append("%s %s" % [place, str(Settings.conflicts(place))])
	runner.check(bad.is_empty() and Settings.live_actions("vehicle").has("veh_blade_up") and Settings.live_actions("vehicle").has("veh_blade_down"),
		"§11 …live in a vehicle, no conflict anywhere %s; shown as \"%s\" / \"%s\"" % [str(bad), Settings.action_label("veh_blade_up"), Settings.action_label("veh_blade_down")])


## Down lowers and Up raises the blade on every vehicle with one; a press that changes nothing does
## nothing; the blade toggle still works; the keys do nothing on the vehicles without a blade.
func test_s11_up_and_down() -> void:
	await _world()
	var up := _s11_bound("veh_blade_up")
	var dn := _s11_bound("veh_blade_down")
	var bad := []
	for id in S11_BLADES:
		var v := await _truck(id, 40.0)
		v.set_status("", 0.0)
		await _s11_key(dn)
		var lowered: bool = v.tool_on and v.status_text == "Blade down"
		v.set_status("", 0.0)
		await _s11_key(dn)
		var again: bool = v.tool_on and v.status_text == ""
		var hud_down := v.hud_text()
		await _s11_key(up)
		var raised: bool = not v.tool_on and v.status_text == "Blade up"
		v.set_status("", 0.0)
		await _s11_key(up)
		var again2: bool = not v.tool_on and v.status_text == ""
		Input.parse_input_event(_s11_action("veh_tool", true))
		await _frames(2)
		Input.parse_input_event(_s11_action("veh_tool", false))
		await _frames(12)
		var toggled: bool = v.tool_on
		runner.info("%s: %s" % [id, hud_down])
		if not (lowered and again and raised and again2 and toggled and hud_down.contains("Blade DOWN")):
			bad.append("%s %s" % [id, str([lowered, again, raised, again2, toggled])])
		await _drop(v)
	runner.check(bad.is_empty(), "§11 Down lowers the blade (\"Blade down\"), Up raises it (\"Blade up\"), a second press does nothing, the blade toggle still toggles, on %s %s" % [str(S11_BLADES), str(bad)])
	var bad2 := []
	for id in S11_NO_BLADE:
		var v := await _truck(id, 40.0)
		v.bed_load = 3.0 if v.data.dump_capacity > 0.0 else 0.0
		await _s11_key(dn)
		await _s11_key(up)
		await _s11_key(dn)
		if v.tool_on or (v.data.dump_capacity > 0.0 and not is_equal_approx(v.bed_load, 3.0)):
			bad2.append(id)
		await _drop(v)
	runner.check(bad2.is_empty(), "§11 …ignored on %s (the dump truck keeps its load) %s" % [str(S11_NO_BLADE), str(bad2)])
	await _unload()


## Rebound, the new keys work and the old ones do nothing.
func test_s11_rebinding() -> void:
	var saved: Variant = _s11_backup()
	await _world()
	var old_up := _s11_bound("veh_blade_up")
	var old_dn := _s11_bound("veh_blade_down")
	var e_up := InputEventKey.new()
	e_up.physical_keycode = KEY_PAGEUP
	var e_dn := InputEventKey.new()
	e_dn.physical_keycode = KEY_PAGEDOWN
	var c1 := Settings.rebind("veh_blade_up", e_up)
	var c2 := Settings.rebind("veh_blade_down", e_dn)
	var v := await _truck("pickup_plow", 40.0)
	await _s11_key(old_dn)
	var old_dn_nothing := not v.tool_on
	await _s11_key(KEY_PAGEDOWN)
	var new_dn := v.tool_on
	await _s11_key(old_up)
	var old_up_nothing := v.tool_on
	await _s11_key(KEY_PAGEUP)
	var new_up := not v.tool_on
	runner.check(c1 == "" and c2 == "" and old_dn_nothing and new_dn and old_up_nothing and new_up and Settings.action_label("veh_blade_down") == OS.get_keycode_string(KEY_PAGEDOWN),
		"§11 rebound to %s / %s: they raise and lower the blade, %s and %s do nothing now" % [Settings.action_label("veh_blade_up"), Settings.action_label("veh_blade_down"), OS.get_keycode_string(old_up), OS.get_keycode_string(old_dn)])
	await _drop(v)
	_s11_restore(saved)
	runner.check(Settings.bindings["veh_blade_down"] == ["key:%d" % old_dn], "§11 …the settings file put back")
	await _unload()


## The arrows are also ui_up / ui_down: a focused control (one that would move its focus down)
## doesn't take the press from the vehicle.
func test_s11_press_reaches_with_a_control_focused() -> void:
	await _world()
	var box := VBoxContainer.new()
	world.hud.add_child(box)
	var b1 := Button.new()
	b1.text = "One"
	var b2 := Button.new()
	b2.text = "Two"
	box.add_child(b1)
	box.add_child(b2)
	await _frames(2)
	var vp := _tree().root.get_viewport()
	b1.grab_focus()
	await _s11_key(_s11_bound("veh_blade_down"))
	var on_foot_moved := vp.gui_get_focus_owner() == b2      # on foot the arrow moves the focus
	var v := await _truck("pickup_plow", 40.0)
	b1.grab_focus()
	await _frames(1)
	await _s11_key(_s11_bound("veh_blade_down"))
	var lowered := v.tool_on
	var kept := vp.gui_get_focus_owner() == b1
	await _s11_key(_s11_bound("veh_blade_up"))
	runner.check(on_foot_moved and lowered and kept and not v.tool_on,
		"§11 a HUD button focused (on foot Down moves its focus: %s): in the vehicle Down still lowers the blade (%s), the focus stays put (%s), Up raises it" % [on_foot_moved, lowered, kept])
	await _drop(v)
	box.queue_free()
	await _unload()


## One frame of back-drag on open ground: the snow on the blade's far side within the band moves to
## its back (toward the vehicle), spread over several rows, none left beyond the face; one push_rng
## draw per moved cell; marked player-moved; the volume exact.
func test_s11_back_drag_one_step() -> void:
	await _world()
	var v := await _truck("pickup_plow", 40.0)
	v.exit_vehicle()
	await _frames(2)
	var at := Vector2(40.0, 120.0)
	var fwd := Vector2(0, 1)          # the vehicle faces +z: its far side is +z, its back face −z
	var hw := 1.2
	var back := 0.65
	var band := back + 0.1
	var area := Rect2(at - Vector2(2.0, 1.5), Vector2(4.0, 3.0))
	Snow.set_rect(area, 0.0)
	Snow.set_rect(Rect2(at.x - 1.5, at.y, 3.0, 1.0), 0.2)
	Snow.relax_until_stable()
	var sx0 := Snow.cell_x(area.position.x)
	var sz0 := Snow.cell_z(area.position.y)
	var before := PackedFloat32Array()
	var cells := 0
	var marked := 0
	for z in range(sz0, Snow.cell_z(area.end.y)):
		for x in range(sx0, Snow.cell_x(area.end.x)):
			var i := z * Snow.W + x
			before.append(Snow.depth[i])
			marked += Snow.soft[i]
			var c := Vector2((x + 0.5) * Snow.CELL, (z + 0.5) * Snow.CELL) - at
			if absf(c.x) <= hw and c.y >= 0.0 and c.y <= band and Snow.surf[i] != Snow.S_BLOCKED and Snow.depth[i] > v.data.blade_floor:
				cells += 1
	var v0 := Snow.volume_in_rect(area)
	Snow.push_rng.seed = Snow.PUSH_SEED + 7
	var ref := RandomNumberGenerator.new()
	ref.seed = Snow.PUSH_SEED + 7
	for k in range(cells):
		ref.randf()
	var r := v.back_drag(at, fwd, fwd, hw, back)
	var rows := {}
	var beyond := 0.0
	var unmarked := 0
	var k2 := 0
	for z in range(sz0, Snow.cell_z(area.end.y)):
		for x in range(sx0, Snow.cell_x(area.end.x)):
			var i := z * Snow.W + x
			var add := Snow.depth[i] - before[k2]
			k2 += 1
			if add <= 1e-6:
				continue
			if (z + 0.5) * Snow.CELL - at.y >= 0.0:
				beyond += add
			rows[z] = true
			if Snow.soft[i] != 1:
				unmarked += 1
	runner.check(marked == 0 and cells > 20 and Snow.push_rng.state == ref.state, "§11 back-drag: one draw from push_rng per moved cell (%d cells, none marked before)" % cells)
	runner.check(rows.size() >= 2 and beyond <= 0.0 and unmarked == 0, "§11 …the snow lands behind the blade (toward the vehicle) over %d rows, none beyond its face, all of it marked player-moved (%d unmarked)" % [rows.size(), unmarked])
	runner.check(float(r["moved"]) > 0.1 and absf(Snow.volume_in_rect(area) - v0) < 1e-5, "§11 …%.3f m³ moved, the volume exact (%.6f → %.6f m³)" % [float(r["moved"]), v0, Snow.volume_in_rect(area)])
	Game.vehicles.erase(v.entry)
	v.queue_free()
	await _unload()


## The typical use: the truck up to the garage door, the blade lowered at the door, 3 m in reverse.
## The snow piled against the door comes away with the blade (volume exact, marked player-moved),
## slowing the truck as a push does, never stuck. Standing still or driving forward with the blade
## down leaves the pile where it is; raised, the blade leaves it as a pile, which stays away from the
## door once settled.
func test_s11_back_drag_from_the_garage_door() -> void:
	await _world()
	var hi := Layout.house_info(Layout.player_lot)
	var drv: Rect2 = hi["driveway"]
	var garage: Rect2 = hi["garage"]
	var door_z := garage.position.y
	var cx := drv.get_center().x
	var region := Rect2(drv.position.x - 3.0, door_z - 14.0, drv.size.x + 6.0, 14.0)
	Snow.set_rect(region, 0.0)
	# The truck the game started with is parked here: out of the way.
	var parked: Vehicle = world.vehicle_nodes()[0]
	Game.vehicles.erase(parked.entry)
	parked.queue_free()
	await _frames(2)
	var near := Rect2(cx - 1.2, door_z - 1.0, 2.4, 1.0)           # the metre at the door, the blade's width
	var vd: VehicleData = Catalog.vehicle(&"pickup_plow")
	var info := VehicleModels.build(vd)
	var reach := -float(info["blade_z"])                           # the blade's centre ahead of the truck's
	# The same reverse on bare ground, blade up: the speed to beat.
	var bare_speed := 0.0
	var v0 := await _truck("pickup_plow", cx, door_z - 0.15 - reach, PI)
	var p0 := v0.global_position
	Input.action_press("veh_reverse")
	for f in range(600):
		await _frames(1)
		bare_speed = minf(bare_speed, v0.speed)
		if v0.global_position.distance_to(p0) >= 3.0:
			break
	Input.action_release("veh_reverse")
	await _drop(v0)
	# Snow against the door: 1.4 m out (the front wheels stand 1.5 m behind the blade), 0.8 m deep.
	Snow.set_rect(Rect2(cx - 1.0, door_z - 1.4, 2.0, 1.4), 0.8)
	Snow.relax_until_stable()
	var vol0 := Snow.volume_in_rect(region)
	var near0 := Snow.volume_in_rect(near)
	# Up to the door, its blade's face 15 cm from it, the blade lowered (Down).
	var v := await _truck("pickup_plow", cx, door_z - 0.15 - reach, PI)
	Snow.push_rng.seed = Snow.PUSH_SEED + 12
	await _s11_key(_s11_bound("veh_blade_down"))
	var start := v.global_position
	var moved0 := Snow.stat_player_moved
	var stuck := 0
	var saw_status := false
	var saw_hud := false
	var drag_speed := 0.0
	Input.action_press("veh_reverse")
	for f in range(600):
		await _frames(1)
		stuck += 1 if v.stuck else 0
		saw_status = saw_status or v.status_text == Vehicle.DRAG_STATUS
		saw_hud = saw_hud or v.hud_text().contains("dragging")
		drag_speed = minf(drag_speed, v.speed)
		if v.global_position.distance_to(start) >= 3.0:
			break
	Input.action_release("veh_reverse")
	Input.action_press("veh_brake")           # stopped (still dragging while it slows)
	for f in range(120):
		await _frames(1)
		if absf(v.speed) < 0.01:
			break
	Input.action_release("veh_brake")
	await _frames(2)
	var dist := v.global_position.distance_to(start)
	var near1 := Snow.volume_in_rect(near)
	var hw := vd.blade_width * 0.5
	# Where the snow in the blade's swath is now: its centre (weighted by depth) along the drive,
	# from the door. (Snow that slumps past the blade's ends is left beside its path, as a plow's.)
	var centre := func() -> float:
		var s := 0.0
		var w := 0.0
		for z in range(Snow.cell_z(region.position.y), Snow.cell_z(region.end.y)):
			for x in range(Snow.cell_x(cx - hw), Snow.cell_x(cx + hw)):
				var d: float = Snow.depth[z * Snow.W + x]
				s += d * (door_z - (z + 0.5) * Snow.CELL)
				w += d
		return s / maxf(w, 1e-9)
	var c1: float = centre.call()
	var bz := v.global_position.z + reach                          # the blade's centre now
	var blade_out := door_z - bz
	var soft_pile := 0
	var pile_cells := 0
	for z in range(Snow.cell_z(bz - 1.0), Snow.cell_z(bz)):
		for x in range(Snow.cell_x(cx - 1.0), Snow.cell_x(cx + 1.0)):
			var i := z * Snow.W + x
			if Snow.depth[i] > 0.05:
				pile_cells += 1
				soft_pile += Snow.soft[i]
	# The ground the blade uncovered (its swath between the blade and the door, past the blade's cell).
	var far := Rect2(cx - hw, bz + Snow.CELL, hw * 2.0, door_z - bz - Snow.CELL)
	var far0 := Snow.volume_in_rect(far)
	var spill := Snow.volume_in_rect(Rect2(cx - 4.0, bz, 8.0, door_z - bz)) - Snow.volume_in_rect(Rect2(cx - hw, bz, hw * 2.0, door_z - bz))
	runner.info("bare reverse %.1f km/h, dragging %.1f km/h; moved %.2f m; near the door %.3f → %.3f m³; the swath's snow centre %.2f m from it, the blade %.2f m; %.3f m³ left past the blade's ends" % [-bare_speed * 3.6, -drag_speed * 3.6, dist, near0, near1, c1, blade_out, spill])
	runner.check(dist >= 3.0 and stuck == 0 and saw_status and saw_hud, "§11 back-drag from the garage door: 3 m in reverse (%.2f m), never stuck by its own pile, \"%s\" on the status line and the HUD" % [dist, Vehicle.DRAG_STATUS])
	runner.check(near1 < near0 * 0.15 and far0 < far.get_area() * 0.03 and c1 > blade_out and Snow.stat_player_moved > moved0 + 0.5,
		"§11 …the snow comes away from the door with the blade: %.2f → %.2f m³ in its last metre, %.3f m³ left in the blade's swath (its floor, blade_floor), the swath's snow centred %.2f m out, behind the blade (%.2f m out)" % [near0, near1, far0, c1, blade_out])
	runner.near(Snow.volume_in_rect(region), vol0, 1e-4, "§11 …the volume exact (%.6f → %.6f m³)" % [vol0, Snow.volume_in_rect(region)])
	runner.check(pile_cells > 0 and soft_pile == pile_cells and -drag_speed < -bare_speed * 0.95, "§11 …the pile against the blade's back is player-moved snow (%d of %d cells), and it slows the truck as a push does (%.1f km/h, %.1f bare)" % [soft_pile, pile_cells, -drag_speed * 3.6, -bare_speed * 3.6])
	# Standing still with the blade down adds nothing: the pile stays against the blade's back.
	await _frames(60)
	runner.check(v.tool_on and Snow.volume_in_rect(far) <= far0 + 0.1 and v.global_position.distance_to(start) - dist < 0.05,
		"§11 …then a second standing still, the blade still down: the ground it uncovered stays clear (%.3f → %.3f m³: only the windrows beside it settling; the blade sends none of its pile back)" % [far0, Snow.volume_in_rect(far)])
	# Driving forward with the blade down leaves the pile where it is: the blade takes the ground it
	# crosses, not the pile behind the line where it stopped dragging.
	var behind := Rect2(cx - hw, bz - 2.0, hw * 2.0, 2.0)
	var ahead_r := Rect2(cx - hw, bz, hw * 2.0, door_z - bz)
	var behind0 := Snow.volume_in_rect(behind)
	var ahead0 := Snow.volume_in_rect(ahead_r)
	var p1 := v.global_position
	Input.action_press("veh_accelerate")
	for f in range(240):
		await _frames(1)
		if v.global_position.distance_to(p1) >= 1.0:
			break
	Input.action_release("veh_accelerate")
	Input.action_press("veh_brake")
	for f in range(120):
		await _frames(1)
		if absf(v.speed) < 0.01:
			break
	Input.action_release("veh_brake")
	runner.info("forward %.2f m, blade down: behind the drag's stop %.3f → %.3f m³, ahead of it %.3f → %.3f m³" % [v.global_position.distance_to(p1), behind0, Snow.volume_in_rect(behind), ahead0, Snow.volume_in_rect(ahead_r)])
	runner.check(v.tool_on and v.global_position.distance_to(p1) >= 1.0 and Snow.volume_in_rect(ahead_r) <= ahead0 + 0.15 and Snow.volume_in_rect(behind) >= behind0 - 0.05,
		"§11 …driving forward 1 m, the blade still down: the pile stays where it is (%.3f → %.3f m³ behind where the drag stopped; %.3f → %.3f m³ ahead of it: the windrows beside the swath settling)" % [behind0, Snow.volume_in_rect(behind), ahead0, Snow.volume_in_rect(ahead_r)])
	# Raise the blade (Up): the pile stays; settled, it is still away from the door.
	await _s11_key(_s11_bound("veh_blade_up"))
	var raised := not v.tool_on and v.status_text == "Blade up"
	await _frames(60)
	Snow.relax_until_stable()
	var c2: float = centre.call()
	runner.check(raised and Snow.volume_in_rect(near) < near0 * 0.15 and c2 > blade_out - 0.5, "§11 …the blade raised (\"%s\"), the snow settles as a pile away from the door: %.2f m³ in its last metre, the swath's snow centred %.2f m out" % [v.status_text, Snow.volume_in_rect(near), c2])
	runner.near(Snow.volume_in_rect(region), vol0, 1e-4, "§11 …settled, the volume still exact")
	await _drop(v)
	await _unload()


## Driving forward off a dragged pile with the blade still down leaves the pile where it is: the
## blade takes the ground it crosses, not the pile behind the line where it stopped dragging. Where
## the drag stops against the 25 cm grid decides whether the pile's nearest row lies within a push's
## 10 cm margin, so the drag starts from five offsets across a cell.
func test_s11_driving_off_the_pile() -> void:
	await _world()
	var hi := Layout.house_info(Layout.player_lot)
	var drv: Rect2 = hi["driveway"]
	var door_z: float = (hi["garage"] as Rect2).position.y
	var cx := drv.get_center().x
	var region := Rect2(drv.position.x - 3.0, door_z - 14.0, drv.size.x + 6.0, 14.0)
	var parked: Vehicle = world.vehicle_nodes()[0]
	Game.vehicles.erase(parked.entry)
	parked.queue_free()
	await _frames(2)
	var vd: VehicleData = Catalog.vehicle(&"pickup_plow")
	var reach := -float(VehicleModels.build(vd)["blade_z"])
	var hw := vd.blade_width * 0.5
	var bad := []
	var runs := []
	for k in range(5):
		Snow.set_rect(region, 0.0)
		Snow.set_rect(Rect2(cx - 1.0, door_z - 1.4, 2.0, 1.4), 0.8)
		Snow.relax_until_stable()
		Snow.push_rng.seed = Snow.PUSH_SEED + 20 + k
		var vol0 := Snow.volume_in_rect(region)
		var v := await _truck("pickup_plow", cx, door_z - 0.15 - reach - 0.05 * k, PI)
		v.set_blade(true)
		var start := v.global_position
		Input.action_press("veh_reverse")
		for f in range(600):
			await _frames(1)
			if v.global_position.distance_to(start) >= 2.0:
				break
		Input.action_release("veh_reverse")
		Input.action_press("veh_brake")
		for f in range(120):
			await _frames(1)
			if absf(v.speed) < 0.01:
				break
		Input.action_release("veh_brake")
		await _frames(2)
		var bz := v.global_position.z + reach
		var behind := Rect2(cx - hw, bz - 2.0, hw * 2.0, 2.0)
		var behind0 := Snow.volume_in_rect(behind)
		var p1 := v.global_position
		Input.action_press("veh_accelerate")
		for f in range(240):
			await _frames(1)
			if v.global_position.distance_to(p1) >= 1.0:
				break
		Input.action_release("veh_accelerate")
		Input.action_press("veh_brake")
		for f in range(120):
			await _frames(1)
			if absf(v.speed) < 0.01:
				break
		Input.action_release("veh_brake")
		var behind1 := Snow.volume_in_rect(behind)
		runs.append("%.2f→%.2f" % [behind0, behind1])
		if not v.tool_on or behind1 < behind0 - 0.01 or absf(Snow.volume_in_rect(region) - vol0) > 1e-4:
			bad.append("offset %.2f m: %.3f → %.3f m³" % [0.05 * k, behind0, behind1])
		await _drop(v)
	runner.check(bad.is_empty(), "§11 driving forward off the dragged pile, the blade down, from five starts across a cell: the pile behind where the drag stopped stays (m³ %s) %s" % [str(runs), str(bad)])
	await _unload()


## The first-drive help lists the blade keys from the input map beside the blade toggle.
## Polish 8 §17: the first-drive panel is the vehicle's hint now (pages: driving, the blade keys,
## back-drag); the lines are read from its pages, one page at a time on the hint panel.
func test_s11_help_lists_the_keys() -> void:
	await _world()
	for f in range(150):      # hints wait for the game's fade-in
		if world.fade.color.a <= 0.05:
			break
		await _tree().process_frame
	Game.flags.erase("help_vehicle_%d" % VehicleData.Kind.PICKUP_PLOW)
	var v := await _truck("pickup_plow", 40.0)
	await _frames(2)
	var hp = world.hint_panel
	var pages := []
	for k in range(8):
		if not hp.is_open():
			break
		pages.append(hp.text_l.text)
		hp.next()
		await _frames(2)
	var lines := []
	var page_of := []
	for i in range(pages.size()):
		for l in str(pages[i]).split("\n"):
			lines.append(l)
			page_of.append(i)
	var i_tool := lines.find(Settings.action_label("veh_tool") + "  lower / raise the blade")
	var i_keys := lines.find("%s / %s  raise / lower the blade" % [Settings.action_label("veh_blade_up"), Settings.action_label("veh_blade_down")])
	var i_drag := lines.find("%s, blade down  drag the snow back" % Settings.action_label("veh_reverse"))
	runner.check(i_tool >= 0 and i_keys == i_tool + 1 and i_drag > i_keys and page_of[i_drag] == page_of[i_keys] + 1, "§11 the first-drive panel lists the blade keys under the blade toggle, then back-drag: %s" % str(lines.slice(maxi(i_tool, 0), i_drag + 1)))
	world.show_hint(HelpText.vehicle_hint_id(VehicleData.Kind.PICKUP_PLOW), true, v.data)
	await _frames(2)
	var box: Control = hp.box
	var screen: Rect2 = world.hud.get_global_rect()
	runner.check(hp.is_open() and screen.encloses(box.get_global_rect()), "§11 …the panel fits on the screen (%s in %s)" % [str(box.get_global_rect()), str(screen)])
	hp.ok()
	await _drop(v)
	await _unload()


# =============================================================================
# Playtest fix 1: the truck gets out of the driveway
# =============================================================================

## The new games the playtest fix 1 tests run over: three seeds in both modes.
const PF1_GAMES := [["fun", 2024], ["fun", 7], ["fun", 31337], ["survival", 2024], ["survival", 7], ["survival", 31337]]


## A new game as it starts (Dec 1, 7:30), the keys found and nothing shovelled; the clock stopped.
func _pf1_world(mode: String, sd: int) -> void:
	await _unload()
	Game.force_input = true
	Game.new_game(mode, sd)
	Game.flags["truck_keys"] = true
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(3)
	Clock.running = false
	world.snow_renderer.relax_usec = 0


## Walk to the driver's door and get in with the interact key. Returns the truck.
func _pf1_get_in() -> Vehicle:
	var truck: Vehicle = world.vehicle_nodes()[0]
	var pl: Player = world.player
	var tp := Vector2(truck.global_position.x, truck.global_position.z)
	var tfwd := Vector2(-truck.global_transform.basis.z.x, -truck.global_transform.basis.z.z).normalized()
	var door := tp - Vector2(-tfwd.y, tfwd.x) * (truck.data.width * 0.5 + 1.0)
	pl.teleport(Vector3(door.x, 0.05, door.y), 0.0)
	await _frames(2)
	var to := tp - door
	pl.set_yaw(atan2(-to.x, -to.y))
	pl.pitch = deg_to_rad(-12.0)
	pl.head.rotation.x = pl.pitch
	await _frames(4)
	Notify.history.clear()
	Input.parse_input_event(_s11_action("interact", true))
	await _frames(2)
	Input.parse_input_event(_s11_action("interact", false))
	await _frames(3)
	return truck


## How many of the truck's wheels stand on the road.
func _pf1_on_road(v: Vehicle) -> int:
	var n := 0
	for w in v.info["wheels"]:
		var wp: Vector3 = v.global_transform * (w["pos"] as Vector3)
		if Snow.surface_at(wp.x, wp.z) == Snow.S_ROAD:
			n += 1
	return n


func _pf1_along(v: Vehicle, p0: Vector3, fwd: Vector3) -> float:
	return (v.global_position - p0).dot(fwd)


## Hold an action up to `frames` (or until all four wheels are on the road); with `stop_slow`, stop
## once it has been under `stop_slow` m/s for 40 frames. Counts the frames, the frames stuck, the
## top speed and the blocked reasons in `r`.
func _pf1_hold(v: Vehicle, action: String, frames: int, stop_slow: float, r: Dictionary) -> void:
	Input.action_press(action)
	var slow := 0
	for f in range(frames):
		await _tree().physics_frame
		r["frames"] += 1
		r["top"] = maxf(r["top"], absf(v.speed))
		r["stuck"] += 1 if v.stuck else 0
		if v.blocked_reason != "" and not (r["reasons"] as Array).has(v.blocked_reason):
			r["reasons"].append(v.blocked_reason)
		if _pf1_on_road(v) == 4:
			break
		slow = slow + 1 if stop_slow > 0.0 and absf(v.speed) < stop_slow and f > 45 else 0
		if slow > 40:
			break
	Input.action_release(action)


## The scripted way out from where the truck is parked, within `limit_s` seconds of driving.
## "down" plows: the blade lowered (Down), forward until the berm stalls it; then the blade raised
## (Up), back up 1.5 s, brake, lower it, angle it the other way (Z / C), forward again.
## "up" takes run-ups: forward until it stops, back up until it stops (the garage), brake, again.
## Returns {out, secs, passes, first (m forward in the first pass), stuck, top, reasons, vol, log}.
func _pf1_plow_out(v: Vehicle, style: String, limit_s := 180.0) -> Dictionary:
	var fwd := -v.global_transform.basis.z
	var p0 := v.global_position
	var vol0 := Snow.total_volume() + Snow.melted
	var r := {"frames": 0, "stuck": 0, "top": 0.0, "reasons": [], "passes": 0, "first": 0.0, "log": []}
	var limit := int(limit_s * 60.0)
	var f0 := Engine.get_physics_frames()     # every frame counts: the keys, the angling, the braking
	var aim := "veh_aim_left"
	while Engine.get_physics_frames() - f0 < limit and _pf1_on_road(v) < 4:
		r["passes"] += 1
		if style == "down":
			if not v.tool_on:
				await _s11_key(_s11_bound("veh_blade_down"))
			if r["passes"] > 1:
				Input.action_press(aim)
				await _frames(50)
				Input.action_release(aim)
				aim = "veh_aim_right" if aim == "veh_aim_left" else "veh_aim_left"
		var a0 := _pf1_along(v, p0, fwd)
		await _pf1_hold(v, "veh_accelerate", maxi(limit - (Engine.get_physics_frames() - f0), 1), 0.4, r)
		if r["passes"] == 1:
			r["first"] = _pf1_along(v, p0, fwd)
		r["log"].append("%d: %+.1f→%+.1f m at %.0f s" % [r["passes"], a0, _pf1_along(v, p0, fwd), (Engine.get_physics_frames() - f0) / 60.0])
		if _pf1_on_road(v) == 4 or Engine.get_physics_frames() - f0 >= limit:
			break
		if style == "down":
			await _s11_key(_s11_bound("veh_blade_up"))
			await _pf1_hold(v, "veh_reverse", 90, 0.0, r)
		else:
			await _pf1_hold(v, "veh_reverse", 240, 0.05, r)
		Input.action_press("veh_brake")
		await _frames(20)
		Input.action_release("veh_brake")
	r["out"] = _pf1_on_road(v) == 4
	r["secs"] = (Engine.get_physics_frames() - f0) / 60.0
	r["vol"] = Snow.total_volume() + Snow.melted - vol0
	return r


func _pf1_said(word: String) -> bool:
	for n in Notify.history:
		if str(n.get("text", n)).contains(word):
			return true
	return false


## Getting in on the first morning: the opening's snow doesn't hold the wheels (no "snowed in"), and
## from where it's parked the truck backs up (the old 15 % creep made 0.15 m in a second).
func test_pf1_getting_in_and_backing_up() -> void:
	var b: BalanceData = Catalog.balance
	for g in PF1_GAMES:
		var tag := "PF1 %s seed %d:" % g
		await _pf1_world(g[0], g[1])
		var v := await _pf1_get_in()
		var wd := v.wheel_snow_depth()
		runner.check(world.player.state == "vehicle" and v.engine_on, tag + " in the truck with the interact key")
		runner.check(wd < b.pickup_stuck_depth and b.opening_max_depth < b.pickup_stuck_depth and not _pf1_said("snowed in") and not v.stuck,
			tag + " %d cm under the wheels, the opening at most %d cm, stuck from %d cm: getting in doesn't say it's snowed in" % [int(round(wd * 100.0)), int(round(b.opening_max_depth * 100.0)), int(round(b.pickup_stuck_depth * 100.0))])
		var fwd := -v.global_transform.basis.z
		var p0 := v.global_position
		var r := {"frames": 0, "stuck": 0, "top": 0.0, "reasons": []}
		await _pf1_hold(v, "veh_reverse", 60, 0.0, r)
		var back := _pf1_along(v, p0, fwd)
		runner.check(back < -0.3 and r["stuck"] == 0,
			tag + " …reverse moves it from where it's parked: %.2f m in 1 s, up to %.1f km/h, never stuck" % [back, r["top"] * 3.6])
	await _unload()


## Blade down, the main way: from where it's parked, a scripted plow-out (lower the blade, push,
## raise it, back up, lower it, angle it, push again…) gets all four wheels onto the road within
## 3 minutes of driving, never stuck, the snow holding it under half its top speed; volume exact.
func test_pf1_plow_out_blade_down() -> void:
	for g in PF1_GAMES:
		var tag := "PF1 %s seed %d:" % g
		await _pf1_world(g[0], g[1])
		var v := await _pf1_get_in()
		var r := await _pf1_plow_out(v, "down")
		runner.info(tag + " blade down: out %s in %.1f s, %d passes %s, top %.1f km/h, %s" % [r["out"], r["secs"], r["passes"], str(r["log"]), r["top"] * 3.6, str(r["reasons"])])
		runner.check(r["first"] > 0.5, tag + " blade down, forward moves it from where it's parked (%.1f m in the first pass)" % r["first"])
		runner.check(r["out"] and r["secs"] <= 180.0 and r["stuck"] == 0,
			tag + " …it plows its way out: all four wheels on the road in %.1f s of driving, %d passes, never stuck" % [r["secs"], r["passes"]])
		runner.check(r["top"] < v.data.max_speed * 0.5, tag + " …the snow and the berm hold it to %.1f km/h (its top speed: %.0f km/h)" % [r["top"] * 3.6, v.data.max_speed * 3.6])
		runner.check(absf(r["vol"]) < 1e-4, tag + " …the snow volume is conserved (%.6f m³)" % r["vol"])
	await _unload()


## Blade up, the slower way: from where it's parked it pushes off, bogs in the driveway's snow
## ("…from a standstill… Back up with <reverse>"), and with run-ups gets all four wheels onto the
## road within 3 minutes of driving, never stuck; volume exact.
func test_pf1_run_ups_blade_up() -> void:
	for g in PF1_GAMES:
		var tag := "PF1 %s seed %d:" % g
		await _pf1_world(g[0], g[1])
		var v := await _pf1_get_in()
		var r := await _pf1_plow_out(v, "up")
		runner.info(tag + " blade up: out %s in %.1f s, %d pushes %s, top %.1f km/h" % [r["out"], r["secs"], r["passes"], str(r["log"]), r["top"] * 3.6])
		var bogged := false
		for t in r["reasons"]:
			bogged = bogged or (str(t).begins_with("Snowbank ahead") and str(t).contains("standstill") and str(t).contains("Back up with %s" % Settings.action_label("veh_reverse")))
		runner.check(r["first"] > 0.5 and not v.tool_on, tag + " blade up, forward moves it from where it's parked (%.1f m in the first push)" % r["first"])
		runner.check(bogged and r["passes"] > 1, tag + " …it bogs in the driveway's snow and says so: %s" % str(r["reasons"]).substr(0, 140))
		runner.check(r["out"] and r["secs"] <= 180.0 and r["stuck"] == 0,
			tag + " …with run-ups it gets all four wheels onto the road in %.1f s of driving, %d pushes, never stuck" % [r["secs"], r["passes"]])
		runner.check(absf(r["vol"]) < 1e-4, tag + " …the snow volume is conserved (%.6f m³)" % r["vol"])
	await _unload()


## Still snow: a bank deeper than pickup_bank_max stops the truck with the blade up and says so,
## with a run-up on Maple Street, and from where it's parked in the opening's snow.
func test_pf1_a_bank_above_the_limit_stops_it() -> void:
	var b: BalanceData = Catalog.balance
	var h := b.pickup_bank_max + 0.05
	var wall := "too much to drive through (about %d cm at most, with a run-up)" % int(round(b.pickup_bank_max * 100.0))
	await _world()
	_s10_bank(30.0, h)
	Snow.relax_until_stable()
	var half: float = Catalog.vehicle(&"pickup_plow").length * 0.5
	var v := await _truck("pickup_plow", 29.5 - 4.0 - half)    # a 4 m run-up
	var r := await _s10_drive(v, 600, "veh_accelerate", 40.0)
	runner.check(r["front"] < 30.0 and str(r["reasons"]).contains(wall),
		"PF1 a %d cm bank on Maple Street, 4 m run-up, blade up: stopped before it (front at x %.1f), %s" % [int(round(h * 100.0)), r["front"], str(r["reasons"]).substr(0, 120)])
	await _drop(v)
	# The new game's truck in the opening's snow, the same bank across the driveway 1.5 m ahead.
	await _pf1_world("fun", 2024)
	var t := await _pf1_get_in()
	var f3 := -t.global_transform.basis.z
	var f2 := Vector2(f3.x, f3.z).normalized()
	var s2 := Vector2(-f2.y, f2.x)
	var c := Vector2(t.global_position.x, t.global_position.z) + f2 * (half + 1.5)
	var mn := c + s2 * 2.0
	var mx := mn
	for p in [c - s2 * 2.0, c + s2 * 2.0 + f2 * 2.0, c - s2 * 2.0 + f2 * 2.0]:
		mn = mn.min(p)
		mx = mx.max(p)
	Snow.set_rect(Rect2(mn, mx - mn), h)
	var p0 := t.global_position
	var rr := {"frames": 0, "stuck": 0, "top": 0.0, "reasons": []}
	await _pf1_hold(t, "veh_accelerate", 600, 0.05, rr)
	var went := _pf1_along(t, p0, f3)
	var said := false
	for x in rr["reasons"]:
		said = said or str(x).contains(wall)
	runner.check(went > 0.5 and went < 1.5 and said and rr["stuck"] == 0,
		"PF1 parked in the opening's snow, a %d cm bank across the driveway 1.5 m ahead: it pushes up to it (%.2f m) and stops: %s" % [int(round(h * 100.0)), went, str(rr["reasons"]).substr(0, 120)])
	await _unload()


## Getting in reads the snow the truck stands in: driven on a bare street, parked, then left standing
## in snow above the bog depth (as after storms), it pushes off from a standstill when the driver gets
## back in, as in the opening and as after a save and load.
func test_pf1_getting_back_in_reads_the_snow() -> void:
	var b: BalanceData = Catalog.balance
	await _world()
	Snow.set_rect(Rect2(0, 79, 92, 8), 0.03)
	var v := await _truck("pickup_plow", 10.0)
	await _s10_drive(v, 60)                       # on the bare street: nothing under its wheels
	Input.action_press("veh_brake")
	await _frames(60)
	Input.action_release("veh_brake")
	v.exit_vehicle()
	await _frames(2)
	var d := b.pickup_bog_depth + 0.05
	Snow.set_rect(Rect2(v.global_position.x - 4.0, 79, 20.0, 8), d)
	v.enter_vehicle(world.player)
	await _frames(2)
	var r := await _s10_drive(v, 240)
	runner.check(r["dist"] > 0.5 and r["stuck"] == 0 and not str(r["reasons"]).contains("standstill"),
		"PF1 parked, then %d cm under it and ahead (the bog depth: %d cm): getting back in, it pushes off from a standstill (%.1f m) %s" % [int(round(d * 100.0)), int(round(b.pickup_bog_depth * 100.0)), r["dist"], str(r["reasons"]).substr(0, 100)])
	await _drop(v)
	await _unload()


## Still snow: with more than pickup_stuck_depth around its wheels, getting in says it's snowed in,
## with the depth, and that it only creeps; and it does, back and forth.
func test_pf1_snowed_in_still_says_so() -> void:
	var b: BalanceData = Catalog.balance
	await _world()
	Snow.set_rect(Rect2(0, 79, 92, 8), 0.03)
	for id in S10_TRUCKS:
		var v := await _truck(id, 20.0)
		v.exit_vehicle()
		await _frames(2)
		var tp := Vector2(v.global_position.x, v.global_position.z)
		var span := Vector2.ONE * (v.data.length * 0.5 + 0.5)
		Snow.set_rect(Rect2(tp - span, span * 2.0), b.pickup_stuck_depth + 0.05)
		Notify.history.clear()
		v.enter_vehicle(world.player)
		await _frames(2)
		var wd := v.wheel_snow_depth()
		var msg := ""
		for n in Notify.history:
			if str(n.get("text", n)).contains("snowed in"):
				msg = str(n.get("text", n))
		runner.check(wd > b.pickup_stuck_depth and msg.contains("about %d cm" % int(round(wd * 100.0))) and msg.contains("only creeps"),
			"PF1 %s: %d cm around the wheels (stuck from %d cm), getting in says: '%s'" % [id, int(round(wd * 100.0)), int(round(b.pickup_stuck_depth * 100.0)), msg])
		var rb := await _s10_drive(v, 120, "veh_reverse")
		var rf := await _s10_drive(v, 120)
		runner.check(rb["stuck"] > 0 and rb["dist"] < -0.05 and rb["dist"] > -0.5 and rf["dist"] < 0.5 and str(rb["reasons"]).contains("only clears about %d cm" % int(round(b.pickup_stuck_depth * 100.0))),
			"PF1 %s: …and it only creeps: %.2f m back and %.2f m forward in 2 s each, '%s'" % [id, rb["dist"], rf["dist"], str(rb["reasons"]).substr(0, 90)])
		await _drop(v)
	await _unload()


## Round 5 §12's long stretch at the bog depth with a 13 m run-up, at four places across the street
## (a cell's width): each truck bogs, and stays bogged with the throttle held while snow slumps in
## under it. The plain pickup's 2 m shove leaves one wheel line in the untouched snow at some of them.
func test_pf1_a_long_stretch_bogs_anywhere_across_the_street() -> void:
	var b: BalanceData = Catalog.balance
	await _world()
	var runs := []
	var bad := []
	for id in S10_TRUCKS:
		for z in [84.80, 84.86, 84.90, 84.98]:
			Snow.set_rect(Rect2(0, 79, 20, 8), 0.03)
			Snow.set_rect(Rect2(20, 79, 72, 8), b.pickup_bog_depth)
			Snow.relax_until_stable()
			var v := await _truck(id, 4.0, z)
			Input.action_press("veh_accelerate")
			var bogged := false
			for f in range(900):
				await _tree().physics_frame
				bogged = bogged or v.blocked_reason.contains("standstill")
				if v.global_position.x + v.data.length * 0.5 > 52.0:
					break
			Input.action_release("veh_accelerate")
			var into := v.global_position.x + v.data.length * 0.5 - 20.0
			var held := bogged and absf(v.speed) < 0.05 and into < 25.0
			runs.append("%s z %.2f: %s %.1f m in" % [id, z, "bogged" if held else "NOT held", into])
			if not held:
				bad.append(runs[-1])
			await _drop(v)
	runner.check(bad.is_empty(), "PF1 %d cm untouched (the bog depth), a 13 m run-up, at four places across the street: every truck bogs and stays bogged %s %s" % [int(round(b.pickup_bog_depth * 100.0)), str(runs), str(bad)])
	await _unload()


# =============================================================================
# Playtest fix 2: pushed snow tumbles instead of spiking
# =============================================================================

## The level snow of the long pushes (m).
const PF2_DEPTH := 0.3
## The highest the pickup's pile may stand while it pushes PF2_DEPTH of level snow, once it has
## stopped and once it has settled (m). Measured (report/playtest_fix_2.md): 1.54–1.58 m while
## pushing, 1.50–1.52 m stopped, 1.22 m settled; before the fix 2.19 m and 1.93 m.
const PF2_TOP := 1.7
## The same through the opening (a new game's driveway, ~80 cm, and the street's snow). Measured:
## 2.27 m (every seed and mode alike); before the fix 4.11 m, snow stacked against the curb.
const PF2_TOP_OPENING := 2.6
## How far a cell of pushed snow may stand over the moved-snow step while the relaxation runs (m). The
## push itself leaves none, straight or angled (test_pf2_the_push_alone_never_spikes, to 1e-6 m); the
## relaxation then moves snow one edge at a time and rounds the tops, so a cell can be a little over
## the step until its next pass (measured: at most 1.5 cm with a straight blade, the plow truck; 2.4 cm
## with the pickup's blade angled 30°). Before the fix the pile stood up to 0.45 m over it (the pickup,
## 30 cm) and 0.82 m (the plow truck).
const PF2_SPIKE := 0.03
## "Not taller" after 100 m than after 50 m: the tops may differ by this much (m), a snapshot's rounding.
const PF2_SAME := 0.05
## How far behind the blade the checks look (m): inside the strip its guard holds (2 m). Further back,
## the edge of the lane it has cut settles by the relaxation once the guard has passed, as before the
## fix (report/playtest_fix_2.md).
const PF2_BEHIND := 1.5
## The pickup's mean speed pushing PF2_DEPTH once its pile has formed, before the fix (km/h): a long
## push may not get easier.
const PF2_KMH_BEFORE := 20.9


## Maple Street and its sidewalks under `d` m of level snow, in the test world (noon, the clock
## stopped, the sky clear, relaxation by tile count), push_rng reseeded: the same every run.
func _pf2_road(d: float) -> void:
	await _world()
	Snow.set_rect(Rect2(0, 77, Layout.MAP_W, 12), d)
	Snow.relax_until_stable()
	Snow.push_rng.seed = Snow.PUSH_SEED


## The blade's middle (world XZ).
func _pf2_blade(v: Vehicle) -> Vector2:
	var p: Vector3 = v.global_transform * Vector3(0, 0, v.info["blade_z"])
	return Vector2(p.x, p.z)


## The player-moved snow around a blade whose face's middle is at `at`, travelling along `fwd`, `hw` m
## to either side: the cells from a0 to a1 m along fwd and up to `side` m across. Returns {top, spike,
## spike_at, len, wid, carried, spill}:
## - spike: the most any player-moved cell's loose snow stands above moved_repose over a neighbour it
##   could slide onto — not a building, a completed box from outside or the guarded strip behind a
##   blade; with `curb`, not the street from the property side (as for the relaxation); with `blade`,
##   not the cells behind the face across the blade's width (the blade, as for the push itself; the
##   face is `face`, or fwd) (m); spike_at: where (m ahead, m aside, along fwd);
## - top: the deepest player-moved cell (m);
## - len, wid: how far the player-moved snow standing over 5 cm above `d0` reaches along and across fwd
##   from a cell behind the face on: the pile in front of the blade (m);
## - carried: that pile's snow above d0; spill: the player-moved snow above d0 behind the face and past
##   the blade's ends, what rolled off them (m³).
func _pf2_scan(at: Vector2, fwd: Vector2, hw: float, d0: float, a0: float, a1: float, side: float, curb := true, blade := false, face := Vector2.ZERO) -> Dictionary:
	var tang := Vector2(-fwd.y, fwd.x)
	var bf := face if face != Vector2.ZERO else fwd
	var bt := Vector2(-bf.y, bf.x)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for c in [at + fwd * a0 + tang * side, at + fwd * a0 - tang * side, at + fwd * a1 + tang * side, at + fwd * a1 - tang * side]:
		mn = mn.min(c)
		mx = mx.max(c)
	var W := Snow.W
	var ms := Snow.moved_repose
	var g := Snow.guard_ttl > 0
	var r := {"top": 0.0, "spike": 0.0, "spike_at": Vector2.ZERO, "carried": 0.0, "spill": 0.0}
	var amin := INF
	var amax := -INF
	var lmin := INF
	var lmax := -INF
	for z in range(clampi(Snow.cell_z(mn.y), 1, Snow.H - 2), clampi(Snow.cell_z(mx.y), 1, Snow.H - 2) + 1):
		for x in range(clampi(Snow.cell_x(mn.x), 1, W - 2), clampi(Snow.cell_x(mx.x), 1, W - 2) + 1):
			var i := z * W + x
			if Snow.soft[i] != 1 or Snow.surf[i] == Snow.S_BLOCKED:
				continue
			var c := Vector2((x + 0.5) * Snow.CELL, (z + 0.5) * Snow.CELL) - at
			var ah := c.dot(fwd)
			var al := c.dot(tang)
			if ah < a0 or ah > a1 or absf(al) > side or (blade and c.dot(bf) <= 0.0 and absf(c.dot(bt)) <= hw):
				continue
			var d: float = Snow.depth[i]
			r["top"] = maxf(r["top"], d)
			var ex := maxf(d - d0, 0.0)
			if ah >= -Snow.CELL:
				r["carried"] += ex * Snow.CELL_AREA
				if ex > 0.05:
					amin = minf(amin, ah)
					amax = maxf(amax, ah)
					lmin = minf(lmin, al)
					lmax = maxf(lmax, al)
			elif absf(al) > hw:
				r["spill"] += ex * Snow.CELL_AREA
			var h: float = Snow.ground[i] + d
			for e in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: int = i + e.x + e.y * W
				var sn: int = Snow.surf[n]
				if sn == Snow.S_BLOCKED or (Snow.hold[n] == 1 and Snow.hold[i] == 0) or (g and Snow._guarded(n)):
					continue
				if curb and sn == Snow.S_ROAD and Snow.surf[i] != Snow.S_ROAD:
					continue
				if blade:
					var cn := c + Vector2(e.x, e.y) * Snow.CELL
					if cn.dot(bf) <= 0.0 and absf(cn.dot(bt)) <= hw:
						continue
				var sl := minf(h - Snow.ground[n] - Snow.depth[n] - ms, Snow.loose[i])
				if sl > r["spike"]:
					r["spike"] = sl
					r["spike_at"] = Vector2(snappedf(ah, 0.01), snappedf(al, 0.01))
	r["len"] = amax - amin if amax > amin else 0.0
	r["wid"] = lmax - lmin if lmax > lmin else 0.0
	return r


## Drive the truck `v` with its blade lowered (its key) — and with `aim`, angled by holding that key
## 0.75 s — at full throttle until the blade has gone `dist` m; every frame, the pile in front of the
## blade and what rolls off its ends (_pf2_scan from PF2_BEHIND behind the blade on, the blade itself
## a wall). Then braked to a stop (scanned again), and left: the blade raised (its key),
## backed off, out of the truck, the guard run out and the snow settled (the whole path scanned, no
## blade). The truck is then removed. Returns {gone, secs, spike, spike_at, top, kmh (the mean speed
## once the blade is past half way), angle, stopped, left, vol}.
func _pf2_push(v: Vehicle, dist: float, d0: float, limit_s := 60.0, aim := "") -> Dictionary:
	var fwd3 := -v.global_transform.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var hw: float = v.data.blade_width * 0.5
	var vol0 := Snow.total_volume() + Snow.melted
	await _s11_key(_s11_bound("veh_blade_down"))
	if aim != "":
		Input.action_press(aim)
		await _frames(45)
		Input.action_release(aim)
		await _frames(2)
	var face := fwd.rotated(deg_to_rad(v.blade_angle))
	var b0 := _pf2_blade(v)
	var r := {"spike": 0.0, "spike_at": Vector2.ZERO, "top": 0.0, "kmh": 0.0, "angle": v.blade_angle}
	var n := 0
	var f := 0
	var gone := 0.0
	Input.action_press("veh_accelerate")
	while f < int(limit_s * 60.0) and gone < dist:
		await _tree().physics_frame
		f += 1
		var bp := _pf2_blade(v)
		gone = (bp - b0).dot(fwd)
		var s := _pf2_scan(bp, fwd, hw, d0, -PF2_BEHIND, 12.0, 6.0, true, true, face)
		r["top"] = maxf(r["top"], s["top"])
		if s["spike"] > r["spike"]:
			r["spike"] = s["spike"]
			r["spike_at"] = s["spike_at"]
		if gone > dist * 0.5:
			r["kmh"] += absf(v.speed) * 3.6
			n += 1
	Input.action_release("veh_accelerate")
	r["kmh"] /= maxf(n, 1)
	r["gone"] = gone
	r["secs"] = f / 60.0
	Input.action_press("veh_brake")
	await _frames(60)
	Input.action_release("veh_brake")
	var bp1 := _pf2_blade(v)
	r["stopped"] = _pf2_scan(bp1, fwd, hw, d0, -PF2_BEHIND, 12.0, 6.0, true, true, face)
	await _s11_key(_s11_bound("veh_blade_up"))
	Input.action_press("veh_reverse")
	await _frames(60)
	Input.action_release("veh_reverse")
	Input.action_press("veh_brake")
	await _frames(30)
	Input.action_release("veh_brake")
	v.exit_vehicle()
	await _frames(60)      # the guard runs out and its tiles are queued (Snow.GUARD_SETTLE_STEPS)
	Snow.relax_until_stable()
	r["left"] = _pf2_scan(bp1, fwd, hw, d0, -(gone + 3.0), 12.0, 6.0)
	r["vol"] = Snow.total_volume() + Snow.melted - vol0
	Game.vehicles.erase(v.entry)
	v.queue_free()
	await _frames(2)
	return r


func _pf2_pile(s: Dictionary) -> String:
	return "top %.2f m, %.1f m long x %.1f m wide, %.2f m³ above the level snow" % [s["top"], s["len"], s["wid"], s["carried"]]


## The op itself (Snow.blade_push), with no relaxation in between: a plow's blade (2.4 m, cast 0.6 m),
## straight and angled 30°, a hand tool's (0.9 m, 0.38 m) and the plow back-dragging (its face toward
## the vehicle, Vehicle.DRAG_CAST) each step 5 cm at a time, 15 m along Maple Street's 30 cm of level
## snow, the guard set behind the blade as the vehicles do (a box along the travel). After every step no player-moved cell stands over the
## moved-snow step above a neighbour its snow could roll onto (1e-6 m; the street open to it: these
## pushes carry snow over the curb); one push_rng draw per moved cell; the snow conserved. Before the
## fix a plow's pile stood 0.5 m over the step within a few metres.
func test_pf2_the_push_alone_never_spikes() -> void:
	await _unload()
	Game.world = null
	Game.player = null
	for blade in [["plow", 1.2, 0.1, 0.6, 1.0, 0.0], ["plow angled 30°", 1.2, 0.1, 0.6, 1.0, 30.0], ["hand tool", 0.45, 0.07, 0.38, 1.0, 0.0], ["back-drag", 1.2, 0.1, Vehicle.DRAG_CAST, -1.0, 0.0]]:
		Game.new_game("fun", 2024)
		var hw: float = blade[1]
		var fwd := Vector2(float(blade[4]), 0.0)
		var face := fwd.rotated(deg_to_rad(float(blade[5])))
		var tang := Vector2(-face.y, face.x)
		var area := Rect2(0, 76, 60, 14)
		Snow.set_rect(area, 0.0)
		Snow.set_rect(Rect2(0, 79, 60, 8), PF2_DEPTH)
		var v0 := Snow.volume_in_rect(area)
		Snow.push_rng.seed = Snow.PUSH_SEED + 11
		var ref := RandomNumberGenerator.new()
		ref.seed = Snow.PUSH_SEED + 11
		var at := Vector2(15.0 if face.x > 0.0 else 45.0, 83.0)
		var worst := 0.0
		var worst_at := ""
		var draws_ok := true
		var top := 0.0
		for k in range(300):
			at += fwd * 0.05
			var band: float = 0.05 + float(blade[2])
			# The cells the step lifts: each gets one draw.
			var cells := 0
			for z in range(Snow.cell_z(at.y - hw - band - 0.5), Snow.cell_z(at.y + hw + band + 0.5) + 1):
				for x in range(Snow.cell_x(at.x - hw - band - 0.5), Snow.cell_x(at.x + hw + band + 0.5) + 1):
					var c := Vector2((x + 0.5) * Snow.CELL, (z + 0.5) * Snow.CELL) - at
					var ah := c.dot(face)
					var i := z * Snow.W + x
					if absf(c.dot(tang)) <= hw and ah <= 0.0 and ah >= -band and Snow.surf[i] != Snow.S_BLOCKED and Snow.depth[i] > 0.0:
						cells += 1
			Snow.blade_push(at, face, hw, band, 0.0, false, float(blade[3]))
			for j in range(cells):
				ref.randf()
			draws_ok = draws_ok and Snow.push_rng.state == ref.state
			# The guard behind the blade, as Vehicle.player_guard sets it (along the travel, not the face).
			var back := at - fwd * 2.0
			Snow.set_blade_guard(Rect2(Vector2(minf(at.x, back.x), at.y - hw - 0.2), Vector2(2.0, 2.0 * (hw + 0.2))))
			var s := _pf2_scan(at, fwd, hw, PF2_DEPTH, -PF2_BEHIND, 4.0, 3.5, false, true, face)
			top = maxf(top, s["top"])
			if s["spike"] > worst:
				worst = s["spike"]
				worst_at = "%.2f m along, %s" % [k * 0.05, str(s["spike_at"])]
		var dv := Snow.volume_in_rect(area) - v0
		runner.check(worst <= 1e-6, "PF2 the push alone, %s: after every 5 cm step no player-moved cell over the moved-snow step (%.2f m) above a neighbour it could roll onto (the most %.7f m %s); the pile's top %.2f m" % [blade[0], Snow.moved_repose, worst, worst_at, top])
		runner.check(draws_ok and absf(dv) < 1e-5, "PF2 the push alone, %s: one push_rng draw per moved cell, the volume exact (%+.7f m³)" % [blade[0], dv])


## Done-when: the pickup with its plow pushes 50 m and 100 m of PF2_DEPTH level snow, blade down,
## straight, with its keys. Every frame no cell of the pile in front of the blade or of what rolls off
## its ends stands over the moved-snow step (PF2_SPIKE: the relaxation's passes), and the top stays
## under PF2_TOP. Stopped, it leaves one mound; settled, every cell at the step. After 100 m the mound
## is the same as after 50 m, not taller (the owner's call: the extra snow goes into the ridges past the
## blade's ends). The truck still feels it: no faster than before the fix. Volume exact.
func test_pf2_long_pushes_tumble() -> void:
	var piles := {}
	for dist in [50.0, 100.0]:
		await _pf2_road(PF2_DEPTH)
		var v := await _truck("pickup_plow", 6.0, 83.0)
		var r := await _pf2_push(v, dist, PF2_DEPTH)
		var st: Dictionary = r["stopped"]
		var lf: Dictionary = r["left"]
		var tag := "PF2 %.0f m through %d cm:" % [dist, int(round(PF2_DEPTH * 100.0))]
		runner.info(tag + " stopped: %s; left: %s, %.1f m³ rolled off the blade's ends" % [_pf2_pile(st), _pf2_pile(lf), lf["spill"]])
		runner.check(r["gone"] >= dist, tag + " the blade went %.1f m in %.1f s" % [r["gone"], r["secs"]])
		runner.check(r["spike"] <= PF2_SPIKE, tag + " every frame no cell of the pile over the moved-snow step by more than %.2f m (the most %.4f m, at %s)" % [PF2_SPIKE, r["spike"], str(r["spike_at"])])
		runner.check(r["top"] < PF2_TOP and st["top"] < PF2_TOP and lf["top"] < PF2_TOP, tag + " the pile's top under %.2f m: %.2f m while pushing, %.2f m stopped, %.2f m settled" % [PF2_TOP, r["top"], st["top"], lf["top"]])
		runner.check(lf["spike"] <= 1e-4 and st["len"] > 1.0 and st["wid"] > 2.4, tag + " …one mound in front of the blade (%.1f x %.1f m), every cell at the step once settled (%.6f m over)" % [st["len"], st["wid"], lf["spike"]])
		runner.check(r["kmh"] <= PF2_KMH_BEFORE, tag + " the truck still feels it: %.1f km/h over the second half (before the fix %.1f)" % [r["kmh"], PF2_KMH_BEFORE])
		runner.check(absf(r["vol"]) < 1e-4, tag + " the snow volume is conserved (%+.7f m³)" % r["vol"])
		piles[dist] = [st, lf]
	# The same mound, not taller: within PF2_SAME of the top (where the truck stops on the 25 cm grid
	# moves a snapshot's top by a cell's rounding: 2 cm measured; a pile that kept growing would differ
	# by tens of cm), its size within two cells, stopped and settled.
	var same := true
	var txt := []
	for k in range(2):
		var a: Dictionary = piles[50.0][k]
		var b: Dictionary = piles[100.0][k]
		same = same and b["top"] <= a["top"] + PF2_SAME and absf(b["len"] - a["len"]) <= 0.5 and absf(b["wid"] - a["wid"]) <= 0.5
		txt.append("%s: %s / %s" % [["stopped", "settled"][k], _pf2_pile(b), _pf2_pile(a)])
	runner.check(same, "PF2 after 100 m the mound is the same as after 50 m, not taller %s" % str(txt))
	await _unload()


## The opening: from where a new game's truck is parked (the driveway's ~80 cm, nothing shovelled),
## blade down, 15 m out over the curb into the street. The same rules every frame; the top under
## PF2_TOP_OPENING (no stack against the curb: the pile tumbles over it); volume exact. Three seeds in
## both modes.
func test_pf2_the_opening() -> void:
	for g in PF1_GAMES:
		var tag := "PF2 opening %s seed %d:" % g
		await _pf1_world(g[0], g[1])
		Snow.push_rng.seed = Snow.PUSH_SEED
		var v := await _pf1_get_in()
		var r := await _pf2_push(v, 15.0, Catalog.balance.initial_road_depth_year1, 60.0)
		runner.info(tag + " %.1f m in %.1f s, stopped: %s" % [r["gone"], r["secs"], _pf2_pile(r["stopped"])])
		runner.check(r["gone"] >= 15.0 and r["spike"] <= PF2_SPIKE,
			tag + " 15 m blade down (in %.1f s); every frame no cell of the pile over the moved-snow step by more than %.2f m (the most %.4f m at %s)" % [r["secs"], PF2_SPIKE, r["spike"], str(r["spike_at"])])
		runner.check(r["top"] < PF2_TOP_OPENING and r["left"]["spike"] <= 1e-4 and absf(r["vol"]) < 1e-4,
			tag + " …the top %.2f m (under %.2f), every cell at the step once settled (%.6f m over), the volume exact (%+.7f m³)" % [r["top"], PF2_TOP_OPENING, r["left"]["spike"], r["vol"]])
	await _unload()


## Every blade the player uses: every plow (30 m through PF2_DEPTH; the pickup's and the plow truck's
## also angled, the review's case: the guard's box reaches past an angled face), a hand push (RMB,
## walking 5 s) with bare hands, the standard shovel and the wide pusher, and the pickup's plow
## back-dragging (reversing 3 s, blade down). Every frame no cell of the snow they move stands over the moved-snow
## step by more than PF2_SPIKE; settled, none at all; volume exact.
func test_pf2_every_blade_tumbles() -> void:
	var bad := []
	var tops := []
	for id in S11_BLADES:
		await _pf2_road(PF2_DEPTH)
		var v := await _truck(id, 6.0, 83.0)
		var r := await _pf2_push(v, 30.0, PF2_DEPTH)
		tops.append("%s %.2f m" % [id, r["top"]])
		if not (r["gone"] >= 30.0 and r["spike"] <= PF2_SPIKE and r["left"]["spike"] <= 1e-4 and absf(r["vol"]) < 1e-4):
			bad.append("%s: %.1f m, over the step %.4f at %s, settled %.6f, volume %+.7f" % [id, r["gone"], r["spike"], str(r["spike_at"]), r["left"]["spike"], r["vol"]])
	# Angled (Z / C held): the snow rolls off the trailing end into a ridge, no stack there.
	for a in [["pickup_plow", "veh_aim_left"], ["plow_truck", "veh_aim_right"]]:
		await _pf2_road(PF2_DEPTH)
		var v := await _truck(a[0], 6.0, 83.0)
		var r := await _pf2_push(v, 30.0, PF2_DEPTH, 60.0, a[1])
		tops.append("%s angled %+.0f° %.2f m" % [a[0], r["angle"], r["top"]])
		if not (absf(r["angle"]) > 20.0 and r["gone"] >= 30.0 and r["spike"] <= PF2_SPIKE and r["top"] < PF2_TOP and r["left"]["spike"] <= 1e-4 and absf(r["vol"]) < 1e-4):
			bad.append("%s angled %+.0f°: %.1f m, top %.2f, over the step %.4f at %s, settled %.6f, volume %+.7f" % [a[0], r["angle"], r["gone"], r["top"], r["spike"], str(r["spike_at"]), r["left"]["spike"], r["vol"]])
	runner.check(bad.is_empty(), "PF2 every plow, 30 m through %d cm, straight and angled: no spike (tops %s) %s" % [int(round(PF2_DEPTH * 100.0)), str(tops), str(bad)])
	# By hand: RMB held, walking 5 s along the street.
	var hand_bad := []
	for t in [["", 0.15], ["standard_shovel", 0.15], ["wide_pusher", PF2_DEPTH]]:
		await _pf2_road(float(t[1]))
		var pl: Player = world.player
		Game.slots = [t[0], "", "", ""]
		Game.selected = 0
		Game.inventory_changed.emit()
		await _frames(2)
		pl.teleport(Vector3(20.0, Snow.surface_height(20.0, 83.0) + 0.05, 83.0), -PI * 0.5)
		pl.pitch = deg_to_rad(-30.0)
		pl.head.rotation.x = pl.pitch
		await _frames(2)
		var td: ToolData = pl.tools.data
		var hw := td.push_width * 0.5
		var lead := 0.5 if td.kind == ToolData.Kind.HANDS else 0.62
		var vol0 := Snow.total_volume() + Snow.melted
		var p0 := pl.global_position
		var worst := 0.0
		Input.action_press("secondary")
		Input.action_press("move_forward")
		for f in range(300):
			await _tree().physics_frame
			var at := Vector2(pl.global_position.x + lead, pl.global_position.z)
			worst = maxf(worst, _pf2_scan(at, Vector2(1, 0), hw, float(t[1]), -Snow.CELL, 4.0, 3.0)["spike"])
		Input.action_release("move_forward")
		Input.action_release("secondary")
		await _frames(60)
		Snow.relax_until_stable()
		var walked := pl.global_position.x - p0.x
		var settled: float = _pf2_scan(Vector2(pl.global_position.x + lead, pl.global_position.z), Vector2(1, 0), hw, float(t[1]), -(walked + 2.0), 4.0, 3.0)["spike"]
		var dv := Snow.total_volume() + Snow.melted - vol0
		runner.info("PF2 by hand, %s in %d cm: walked %.1f m in 5 s" % [t[0] if t[0] != "" else "bare hands", int(round(float(t[1]) * 100.0)), walked])
		if not (walked > 1.0 and worst <= PF2_SPIKE and settled <= 1e-4 and absf(dv) < 1e-4):
			hand_bad.append("%s: walked %.1f m, over the step %.4f, settled %.6f, volume %+.7f" % [t[0], walked, worst, settled, dv])
	runner.check(hand_bad.is_empty(), "PF2 by hand (bare hands, the standard shovel, the wide pusher): no spike while pushing or once settled, volume exact %s" % str(hand_bad))
	# Back-drag: the pickup's plow lowered, reversing 3 s through the level snow: the snow comes toward
	# the truck against the blade's back face (the "front" of a drag is the truck's side).
	await _pf2_road(PF2_DEPTH)
	var v2 := await _truck("pickup_plow", 40.0, 83.0)
	await _s11_key(_s11_bound("veh_blade_down"))
	var fwd3 := -v2.global_transform.basis.z
	var back := -Vector2(fwd3.x, fwd3.z).normalized()
	var vol1 := Snow.total_volume() + Snow.melted
	var b0 := _pf2_blade(v2)
	var worst2 := 0.0
	var top2 := 0.0
	Input.action_press("veh_reverse")
	for f in range(180):
		await _tree().physics_frame
		var s := _pf2_scan(_pf2_blade(v2), back, v2.data.blade_width * 0.5, PF2_DEPTH, -Snow.CELL, 6.0, 4.0)
		worst2 = maxf(worst2, s["spike"])
		top2 = maxf(top2, s["top"])
	Input.action_release("veh_reverse")
	var dragged := (_pf2_blade(v2) - b0).dot(back)
	Input.action_press("veh_brake")
	await _frames(30)
	Input.action_release("veh_brake")
	runner.check(dragged > 2.0 and worst2 <= PF2_SPIKE and absf(Snow.total_volume() + Snow.melted - vol1) < 1e-4,
		"PF2 back-drag: %.1f m in 3 s, every frame no cell of the dragged pile over the moved-snow step by more than %.2f m (the most %.4f m), its top %.2f m, the volume exact" % [dragged, PF2_SPIKE, worst2, top2])
	await _drop(v2)
	await _unload()



# =============================================================================
# Playtest fix 3: a solid blade, a visible width upgrade, the truck home overnight
# =============================================================================

## How far a point of the blade's solid shape may stand inside a building's footprint (m): none, to
## the physics' contact margin.
const PF3_INSIDE := 0.005
## A run-up of this much (m) from the vehicle's front to the wall it is driven at (the grader's rear
## then stands on the sidewalk in front of the house).
const PF3_RUN := 3.0
const PF3_YELLOW := Color(0.95, 0.75, 0.1)


## The bottom of a solid box (a vehicle's CollisionShape3D) as points on the ground (world XZ): 11
## along its width by 3 through its depth, the corners among them.
func _pf3_points(cs: CollisionShape3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	var size := (cs.shape as BoxShape3D).size
	var xf := cs.global_transform
	for i in range(11):
		for j in range(3):
			var p := xf * Vector3((i / 10.0 - 0.5) * size.x, -size.y * 0.5, (j / 2.0 - 0.5) * size.z)
			out.append(Vector2(p.x, p.z))
	return out


## The vehicle's body box (its solid shape other than the blade's).
func _pf3_body(v: Vehicle) -> CollisionShape3D:
	for c in v.get_children():
		if c is CollisionShape3D and c != v.blade_cs:
			return c
	return null


## How deep the deepest of `pts` stands inside `r` (m; 0 when none is).
static func _pf3_inside(pts: PackedVector2Array, r: Rect2) -> float:
	var deepest := 0.0
	for p in pts:
		if r.has_point(p):
			deepest = maxf(deepest, minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y)))
	return deepest


## How far the nearest of `pts` stands from `r` (m; 0 inside).
static func _pf3_gap(pts: PackedVector2Array, r: Rect2) -> float:
	var g := INF
	for p in pts:
		var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
		g = minf(g, Vector2(dx, dz).length())
	return g


## Hold `keys` until the vehicle has stood still for 45 frames (at most `frames`); every frame, how
## deep its blade's shape stands inside `r`. Returns {inside, stopped, blade (its gap to r at the end),
## body (the body's)}.
func _pf3_press(v: Vehicle, r: Rect2, keys: Array, frames := 600) -> Dictionary:
	var inside := 0.0
	var still := 0
	var last := v.global_position
	for k in keys:
		Input.action_press(k)
	var f := 0
	while f < frames and still < 45:
		await _tree().physics_frame
		f += 1
		inside = maxf(inside, _pf3_inside(_pf3_points(v.blade_cs), r))
		still = still + 1 if f > 30 and v.global_position.distance_to(last) < 0.0005 else 0
		last = v.global_position
	for k in keys:
		Input.action_release(k)
	for i in range(3):
		await _tree().physics_frame
		inside = maxf(inside, _pf3_inside(_pf3_points(v.blade_cs), r))
	return {"inside": inside, "stopped": still >= 45, "blade": _pf3_gap(_pf3_points(v.blade_cs), r), "body": _pf3_gap(_pf3_points(_pf3_body(v)), r)}


## A lot facing inward: a vehicle's yaw driving toward its house.
static func _pf3_yaw_in(lot: Dictionary) -> float:
	var inward := Vector2(lot["inward"]).normalized()
	return atan2(-inward.x, -inward.y)


## How far ahead of its centre a vehicle reaches: its body, or its blade at its widest swing (m).
static func _pf3_reach(vd: VehicleData) -> float:
	return maxf(vd.length * 0.5, -float((VehicleModels.build(vd)["blade_pivot"] as Vector3).z) + vd.blade_width * 0.5)


## A house wall to drive at: the first lot (the player's first) and spot along its front (lot u) with
## nothing solid between the sidewalk and the wall, 4.5 m wide (the trees on the lawns stand where the
## seed puts them: one stands in front of the player's). {lot, u}, or {} if there's none.
func _pf3_clear_wall() -> Dictionary:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var lots := [Layout.player_lot]
	for l in Layout.lots:
		if not l.get("vacant", false) and l != Layout.player_lot:
			lots.append(l)
	for lot in lots:
		var sb: float = lot["setback"]
		for u in [-6.0, -5.5, -6.5, -5.0, -7.0]:
			var a := Layout.lot_to_world(lot, Layout.gu(lot, u), -1.0)
			var b := Layout.lot_to_world(lot, Layout.gu(lot, u), sb - 0.4)
			var q := PhysicsShapeQueryParameters3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(4.5, 1.9, a.distance_to(b))
			q.shape = sh
			q.transform = Transform3D(Basis(Vector3.UP, _pf3_yaw_in(lot)), Vector3((a.x + b.x) * 0.5, 1.0, (a.y + b.y) * 0.5))
			q.collision_mask = 1
			if space.intersect_shape(q, 1).is_empty():
				return {"lot": lot, "u": u}
	return {}


## §1: every plow vehicle driven at the player's garage door and at a house's front wall, its blade
## up and down, straight and angled both ways: it stops against the building, and no point of the
## blade's solid shape is ever inside the building's footprint (before the fix the body stopped and the
## blade went on into the garage). Then, pressed against the garage door with the blade angled,
## steered both ways and the blade swung across: still nothing goes in.
func test_pf3_the_blade_stops_at_walls() -> void:
	await _world()
	var lot := Layout.player_lot
	var hi := Layout.house_info(lot)
	var sb: float = hi["setback"]
	# The truck the game started with is parked in the driveway: out of the way. The yard bare.
	var parked: Vehicle = world.vehicle_nodes()[0]
	Game.vehicles.erase(parked.entry)
	parked.queue_free()
	await _frames(2)
	Snow.set_rect((lot["rect"] as Rect2).merge(hi["driveway"]).grow(3.0), 0.0)
	var wall := _pf3_clear_wall()
	if not runner.check(not wall.is_empty(), "PF3 a house with nothing between the sidewalk and its front wall: %s %s, u %.1f" % [str(wall.get("lot", {}).get("number", "")), str(wall.get("lot", {}).get("street", "")), float(wall.get("u", NAN))]):
		await _unload()
		return
	var wl: Dictionary = wall["lot"]
	var whi := Layout.house_info(wl)
	Snow.set_rect((wl["rect"] as Rect2).grow(3.0), 0.0)
	# [what, its footprint, the lot, along its front (u), its face (v)]
	var targets := [["the garage door", hi["garage"], lot, 6.0, sb - 0.5], ["the house wall", whi["body"], wl, float(wall["u"]), float(whi["setback"])]]
	var worst := 0.0
	var bad := []
	var runs := 0
	var blade_first := 0
	for t in targets:
		var r: Rect2 = t[1]
		for id in S11_BLADES:
			var vd: VehicleData = Catalog.vehicle(StringName(id))
			for down in [false, true]:
				for a in [0.0, -vd.blade_max_angle_deg, vd.blade_max_angle_deg]:
					var p := Layout.lot_to_world(t[2], Layout.gu(t[2], t[3]), t[4] - _pf3_reach(vd) - PF3_RUN)
					var v := await _truck(id, p.x, p.y, _pf3_yaw_in(t[2]))
					v.set_blade(down)
					v.blade_angle = a
					await _frames(90)          # the blade settles where it is set
					var res: Dictionary = await _pf3_press(v, r, ["veh_accelerate"])
					runs += 1
					worst = maxf(worst, res["inside"])
					blade_first += 1 if res["blade"] < res["body"] else 0
					runner.info("PF3 %s, %s, blade %s %+d°: inside %.4f m, stopped %s, blade %.3f m from it, body %.3f m" % [t[0], id, "down" if down else "up", int(a), res["inside"], str(res["stopped"]), res["blade"], res["body"]])
					if res["inside"] > PF3_INSIDE or not res["stopped"] or minf(res["blade"], res["body"]) > 0.15:
						bad.append("%s %s %s %+d°" % [t[0], id, "down" if down else "up", int(a)])
					await _drop(v)
	runner.check(bad.is_empty() and runs == 60,
		"PF3 every plow vehicle driven at the garage door and the house wall (%d runs: blade up and down, straight and angled both ways) stops against it, the blade's shape never more than %.3f m inside the footprint (the most %.4f m; the blade met it first %d times) %s" % [runs, PF3_INSIDE, worst, blade_first, str(bad)])
	# Pressed against the garage door, the blade angled, steering both ways, then the blade swung across.
	var bad2 := []
	var worst2 := 0.0
	for id in S11_BLADES:
		var vd: VehicleData = Catalog.vehicle(StringName(id))
		var p := Layout.lot_to_world(lot, Layout.gu(lot, 6.0), sb - 0.5 - _pf3_reach(vd) - 1.0)
		var v := await _truck(id, p.x, p.y, _pf3_yaw_in(lot))
		v.set_blade(true)
		v.blade_angle = vd.blade_max_angle_deg
		await _frames(90)
		var w := 0.0
		for keys in [["veh_accelerate"], ["veh_accelerate", "veh_left"], ["veh_accelerate", "veh_right"]]:
			var res: Dictionary = await _pf3_press(v, hi["garage"], keys, 600 if keys.size() == 1 else 90)
			w = maxf(w, res["inside"])
		v.blade_angle = -vd.blade_max_angle_deg
		var res3: Dictionary = await _pf3_press(v, hi["garage"], ["veh_accelerate"], 120)
		w = maxf(w, res3["inside"])
		worst2 = maxf(worst2, w)
		runner.info("PF3 %s pressed against the garage door, steered and swung: inside %.4f m" % [id, w])
		if w > PF3_INSIDE:
			bad2.append(id)
		await _drop(v)
	runner.check(bad2.is_empty(), "PF3 …pressed against the garage door, steered both ways and the blade swung across: never more than %.3f m inside (the most %.4f m) %s" % [PF3_INSIDE, worst2, str(bad2)])
	await _unload()


## The solid things a vehicle's boxes overlap (not itself).
func _pf3_touching(v: Vehicle) -> Array:
	var out := []
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var skip: Array[RID] = [v.get_rid()]
	for b in world._solid_boxes(v, v.global_transform):
		for h in space.intersect_shape(world._box_query(b, 0.0, 1 | (1 << 2) | (1 << 3), skip)):
			out.append("%s: %s" % [v.data.id, str(h["collider"])])
	return out


## §1: the truck still starts at truck_start() overlapping nothing, its blade solid, with the plow
## width upgrade as well; every plow vehicle's blade has its solid shape, BLADE_CLEAR above the ground
## with the blade lowered.
func test_pf3_the_truck_starts_clear() -> void:
	await _world()
	var truck: Vehicle = world.vehicle_nodes()[0]
	var ts := Game.truck_start()
	var at_start := truck.global_position.distance_to(ts["pos"]) < 0.001 and is_equal_approx(truck.rotation.y, float(ts["yaw"]))
	var h0 := _pf3_touching(truck)
	runner.check(truck.blade_cs != null and at_start and h0.is_empty(), "PF3 the truck starts at truck_start() with a solid blade, overlapping nothing %s" % str(h0))
	Game.grant_upgrade(StringName(ItemUpgrades.level_id(&"pickup_plow", &"plow_width", 1)))
	await _frames(3)
	var h1 := _pf3_touching(truck)
	runner.check(h1.is_empty() and truck.global_position.distance_to(ts["pos"]) < 0.001, "PF3 …with the plow width upgrade too (its wider blade) %s" % str(h1))
	var low := []
	var outside := []
	for id in S11_BLADES:
		var vd: VehicleData = Catalog.vehicle(StringName(id))
		var v := await _truck(id, 30.0)
		v.set_blade(true)
		await _frames(90)
		var cs := v.blade_cs
		var bottom := cs.global_position.y - (cs.shape as BoxShape3D).size.y * 0.5 - v.global_position.y if cs else -1.0
		runner.info("PF3 %s: the lowered blade's shape from %.3f m up" % [id, bottom])
		if cs == null or bottom < Vehicle.BLADE_CLEAR - 1e-4:
			low.append(id)
		# The shape holds the blade as it stands: the plate's every vertex inside it (below BLADE_CLEAR
		# only under it), blade down and up, straight and angled both ways, as the blade turns and lifts.
		for down in [true, false]:
			for a in [0.0, -vd.blade_max_angle_deg, vd.blade_max_angle_deg]:
				v.set_blade(down)
				v.blade_angle = a
				var worst := 0.0
				for f in range(40):
					await _tree().physics_frame
					worst = maxf(worst, _pf3_plate_outside(v, id))
				if worst > 0.001:
					outside.append("%s %s %+d°: %.3f m" % [id, "down" if down else "up", int(a), worst])
		await _drop(v)
	runner.check(low.is_empty(), "PF3 every plow vehicle's blade is solid, its shape at least %.2f m above the ground with the blade lowered %s" % [Vehicle.BLADE_CLEAR, str(low)])
	runner.check(outside.is_empty(), "PF3 …and its shape holds the visible plate every frame as the blade turns and lifts (down and up, straight and angled both ways) %s" % str(outside))
	await _unload()


## How far the furthest vertex of the blade's plate (its first surface of its own colour: blue with the
## width upgrade) stands outside the blade's solid shape (m), the part under BLADE_CLEAR aside.
func _pf3_plate_outside(v: Vehicle, id: String) -> float:
	var mesh: Mesh = v._blade_mi.mesh
	var si := _pf3_surface(mesh, VehicleModels.UPGRADED_BLUE if v.blade_mult > 1.0 else _pf3_base_colour(id))
	if si < 0:
		return INF
	var to_box := v.blade_cs.global_transform.affine_inverse() * v._blade_mi.global_transform
	var half := (v.blade_cs.shape as BoxShape3D).size * 0.5
	var out := 0.0
	for p in (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var w := v._blade_mi.global_transform * p
		var lp := to_box * p
		var dy := maxf(lp.y - half.y, 0.0) if w.y - v.global_position.y < Vehicle.BLADE_CLEAR else maxf(absf(lp.y) - half.y, 0.0)
		out = maxf(out, maxf(maxf(absf(lp.x) - half.x, absf(lp.z) - half.z), dy))
	return out


## Whether a point on the ground is within `margin` of the blade's solid shape (seen from above).
static func _pf3_in_blade(v: Vehicle, p: Vector3, margin: float) -> bool:
	var lp := v.blade_cs.global_transform.affine_inverse() * p
	var half := (v.blade_cs.shape as BoxShape3D).size * 0.5
	return absf(lp.x) < half.x + margin and absf(lp.z) < half.z + margin


## §1: getting out of a plow vehicle never puts the player in its solid blade (to be shoved off it):
## every plow with the width upgrade (the grader's blade stands beside its cab), at every angle, the
## blade settled or still turning to its angle (it settles beside the player).
## (The tall vehicles' shift on getting out is older: see STATUS.md Issues.)
func test_pf3_getting_out_beside_the_blade() -> void:
	await _world()
	var bad := []
	for id in S11_BLADES:
		var vd: VehicleData = Catalog.vehicle(StringName(id))
		Game.grant_upgrade(StringName(ItemUpgrades.level_id(vd.id, &"plow_width", 1)))
		var m := vd.blade_max_angle_deg
		for a in [-m, -20.0, -10.0, -8.0, 0.0, 8.0, 10.0, 20.0, m]:
			for turning in ([false, true] if a != 0.0 else [false]):
				var v := await _truck(id, 30.0)
				v.blade_angle = a
				await _frames(60)
				if turning:     # still turning to its angle, 6° behind it (as while Z / C is held)
					v.blade_node.rotation.y = -deg_to_rad(a - 6.0 * signf(a))
					v._fit_blade_shape()
				v.exit_vehicle()
				var at: Vector3 = world.player.global_position
				# The blade as it settles (at its angle), the vehicle where it stood. (Waiting for it
				# would mix in the tall vehicles' shift on getting out, which is older: STATUS.md.)
				v.blade_node.rotation.y = -deg_to_rad(a)
				v._fit_blade_shape()
				if _pf3_in_blade(v, at, world.player.capsule.radius):
					bad.append("%s %+d°%s" % [id, int(a), " (turning)" if turning else ""])
				await _drop(v)
	runner.check(bad.is_empty(), "PF3 getting out of every plow with the width upgrade, at every blade angle: never into the blade %s" % str(bad))
	await _unload()


## The first surface of `mesh` whose material is colour `c` (a prop shader's albedo or a standard
## material's colour), or -1.
static func _pf3_surface(mesh: Mesh, c: Color) -> int:
	for i in range(mesh.get_surface_count()):
		var m := mesh.surface_get_material(i)
		var col: Variant = null
		if m is ShaderMaterial:
			col = (m as ShaderMaterial).get_shader_parameter("albedo")
		elif m is StandardMaterial3D:
			col = (m as StandardMaterial3D).albedo_color
		if col is Color and (col as Color).is_equal_approx(c):
			return i
	return -1


## The box a surface's vertices fill.
static func _pf3_surface_box(mesh: Mesh, i: int) -> AABB:
	var verts: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
	var box := AABB(verts[0], Vector3.ZERO)
	for p in verts:
		box = box.expand(p)
	return box


## Whether two meshes are the same: their surfaces' materials and vertices.
static func _pf3_same_mesh(a: Mesh, b: Mesh) -> bool:
	if a.get_surface_count() != b.get_surface_count():
		return false
	for i in range(a.get_surface_count()):
		if a.surface_get_material(i) != b.surface_get_material(i) or a.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] != b.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			return false
	return true


## The base colour of each plow vehicle's blade (VehicleModels).
static func _pf3_base_colour(id: String) -> Color:
	match id:
		"plow_truck":
			return Color(0.15, 0.15, 0.16)
		"grader":
			return Color(0.3, 0.3, 0.32)
	return PF3_YELLOW


## §2: without plow_width every plow vehicle's blade is exactly as before (the same mesh: the yellow
## blades yellow), no lamps, its solid shape as wide as the strip it clears. Granted (as collecting its
## crate does) on the vehicle already in the world: the blade model and its solid shape are as wide as
## the strip it now clears (within 5 cm), the plate about 20 % taller, blue, with two lamps on top that
## glow while the headlights are on (at night) and not by day. No balance value changes. The truck
## parked in the driveway changes too, and save → load keeps it.
func test_pf3_the_width_upgrade_shows() -> void:
	await _world()
	var blue := VehicleModels.UPGRADED_BLUE
	var bad := []
	var lens := MeshKit.new()
	lens.box(Mats.std(VehicleModels.LAMP_LENS, 0.3), Transform3D(), Vector3.ONE)
	var one_lens: int = lens.commit().surface_get_array_len(0)
	var bal := var_to_str(inst_to_dict(Catalog.balance))
	for id in S11_BLADES:
		var vd: VehicleData = Catalog.vehicle(StringName(id))
		var v := await _truck(id, 30.0)
		var base: Dictionary = VehicleModels.build(vd)
		var mesh0: Mesh = v._blade_mi.mesh
		var cleared0 := vd.blade_width * ItemUpgrades.mult(vd.id, &"vehicle_blade_width")
		var w0 := (v.blade_cs.shape as BoxShape3D).size.x
		var as_before := _pf3_same_mesh(mesh0, base["blade_mesh"]) and v.blade_lamps == null and _pf3_surface(mesh0, blue) < 0
		var colour := _pf3_surface(mesh0, _pf3_base_colour(id)) >= 0
		runner.info("PF3 %s without: as before %s, its colour %s, the shape %.3f m wide, the strip %.3f m" % [id, str(as_before), str(colour), w0, cleared0])
		if not (as_before and colour and absf(w0 - cleared0) <= 0.05):
			bad.append("%s without" % id)
		Game.grant_upgrade(StringName(ItemUpgrades.level_id(vd.id, &"plow_width", 1)))
		await _frames(2)
		var mesh1: Mesh = v._blade_mi.mesh
		var cleared := vd.blade_width * ItemUpgrades.mult(vd.id, &"vehicle_blade_width")
		var si := _pf3_surface(mesh1, blue)
		var plate1 := _pf3_surface_box(mesh1, si) if si >= 0 else AABB()
		var si0 := _pf3_surface(base["blade_mesh"], _pf3_base_colour(id))
		var plate0 := _pf3_surface_box(base["blade_mesh"], si0) if si0 >= 0 else AABB()
		var w1 := (v.blade_cs.shape as BoxShape3D).size.x
		var taller := plate1.size.y / maxf(plate0.size.y, 1e-6)
		var lamps: bool = v.blade_lamps != null and v.blade_lamps.mesh.surface_get_array_len(0) == one_lens * 2
		var lamp_box: AABB = v.blade_lamps.mesh.get_aabb() if v.blade_lamps else AABB()
		var on_top: bool = lamps and lamp_box.position.y >= plate1.end.y - 0.15 and lamp_box.size.x > plate1.size.x * 0.4
		runner.info("PF3 %s with: the model %.3f m wide, the shape %.3f m, the strip %.3f m; the plate %.2f x as tall; blue %s; two lamps %s, on top %s" % [id, plate1.size.x, w1, cleared, taller, str(si >= 0), str(lamps), str(on_top)])
		if not (si >= 0 and absf(plate1.size.x - cleared) <= 0.05 and absf(w1 - cleared) <= 0.05 and taller > 1.15 and taller < 1.25 and lamps and on_top and cleared > cleared0 + 0.1):
			bad.append("%s with" % id)
		# The lamps glow with the headlights: at night, and not by day.
		Clock.reset(Clock.at(1, 23.0))
		await _frames(45)          # the game sets the lights every 0.5 s
		var lit: bool = v.headlights[0].visible and v.blade_lamps != null and v.blade_lamps.material_override is StandardMaterial3D and (v.blade_lamps.material_override as StandardMaterial3D).emission_enabled
		Clock.reset(Clock.at(1, 12.0))
		await _frames(45)
		var unlit: bool = not v.headlights[0].visible and v.blade_lamps != null and v.blade_lamps.material_override == null
		if not (lit and unlit):
			bad.append("%s lamps (lit at night %s, unlit by day %s)" % [id, str(lit), str(unlit)])
		await _drop(v)
	runner.check(bad.is_empty(), "PF3 the width upgrade shows on every plow vehicle in the world as it is granted: the blade and its shape as wide as the strip it clears (5 cm), about 20 %% taller, blue, two lamps lit with the headlights; without it the blade as before %s" % str(bad))
	runner.check(var_to_str(inst_to_dict(Catalog.balance)) == bal, "PF3 …no balance value changes")
	# The truck parked in the driveway changed too, and keeps it through save → load.
	var truck: Vehicle = world.vehicle_nodes()[0]
	var cleared_t := truck.data.blade_width * ItemUpgrades.mult(truck.data.id, &"vehicle_blade_width")
	var wide_now := truck.blade_lamps != null and _pf3_surface(truck._blade_mi.mesh, blue) >= 0 and absf((truck.blade_cs.shape as BoxShape3D).size.x - cleared_t) <= 0.05
	runner.check(Saves.save_game(), "PF3 saved")
	await _unload()
	runner.check(Saves.load_game("fun"), "PF3 loaded")
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(3)
	Clock.running = false
	var t2: Vehicle = world.vehicle_nodes()[0] if not world.vehicle_nodes().is_empty() else null
	var kept := t2 != null and t2.blade_lamps != null and _pf3_surface(t2._blade_mi.mesh, blue) >= 0 and absf((t2.blade_cs.shape as BoxShape3D).size.x - cleared_t) <= 0.05
	runner.check(wide_now and kept, "PF3 the truck parked in the driveway changed too, and save → load keeps its upgraded blade (%.2f m)" % cleared_t)
	Saves.delete_save("fun")
	await _unload()


## Where the truck may be left before a sleep: on Maple Street, at the store's lot, and pushed off its
## spot in the driveway (sideways and turned).
func _pf3_parkings() -> Array:
	var store := Rect2()
	for a in Layout.big_areas:
		if a["id"] == "store_lot":
			store = a["rect"]
	var ts := Game.truck_start()
	var off: Vector3 = ts["pos"] + Vector3(1.6, 0, -1.2)
	return [["on the street", Vector3(30.0, 0, 84.95), -PI * 0.5], ["at the store lot", Vector3(store.get_center().x, 0, store.get_center().y), 0.4],
		["pushed off its spot", off, float(ts["yaw"]) + 0.45]]


## §3: left on the street, at the store lot or pushed off its spot (its blade angled 20°, the keys
## found or not), after a sleep the truck is at truck_start(), facing as at the start, its blade raised,
## its blade angle and roof snow as they were; the ATV on the street hasn't moved. Save → load keeps it
## at home.
func test_pf3_the_truck_goes_home_overnight() -> void:
	await _world()
	var truck: Vehicle = world.vehicle_nodes()[0]
	var ts := Game.truck_start()
	var atv := await _truck("atv_blade", 60.0)
	atv.exit_vehicle()
	await _frames(5)
	var atv_at := atv.global_transform
	var bad := []
	var k := 0
	for p in _pf3_parkings():
		Game.flags["truck_keys"] = k % 2 == 0
		truck.global_position = p[1]
		truck.rotation.y = p[2]
		truck.blade_angle = 20.0
		truck.snow_load = 0.3
		await _frames(30)
		runner.check(truck.global_position.distance_to(ts["pos"]) > 1.0, "PF3 the truck is %s (%.1f m from its spot)" % [p[0], truck.global_position.distance_to(ts["pos"])])
		await world._do_sleep()
		await _frames(2)
		var home := truck.global_position.distance_to(ts["pos"]) < 0.001 and absf(wrapf(truck.rotation.y - float(ts["yaw"]), -PI, PI)) < 1e-4
		var raised := not truck.tool_on and is_equal_approx(truck.blade_node.position.y, Vehicle.BLADE_LIFT)
		var kept := is_equal_approx(truck.blade_angle, 20.0) and truck.snow_load >= 0.3 - 1e-6
		runner.info("PF3 %s: home %s (%.4f m), the blade raised %s, its angle and the roof snow kept %s, %s" % [p[0], str(home), truck.global_position.distance_to(ts["pos"]), str(raised), str(kept), Clock.format_time(Clock.minutes)])
		if not (home and raised and kept and Clock.hour() == 7):
			bad.append(p[0])
		k += 1
	runner.check(bad.is_empty(), "PF3 after a sleep the truck is home at truck_start(), facing as at the start, its blade raised, its blade angle and roof snow kept, keys or no keys %s" % str(bad))
	runner.check(atv.global_transform.is_equal_approx(atv_at), "PF3 …the ATV left on the street hasn't moved")
	await _unload()
	runner.check(Saves.load_game("fun"), "PF3 the sleep's save loads")
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(5)
	Clock.running = false
	var t2: Vehicle = null
	for v in world.vehicle_nodes():
		if (v as Vehicle).is_pickup():
			t2 = v
	runner.check(t2 != null and t2.global_position.distance_to(ts["pos"]) < 0.001 and absf(wrapf(t2.rotation.y - float(ts["yaw"]), -PI, PI)) < 1e-4,
		"PF3 save → load keeps the truck at home")
	Saves.delete_save("fun")
	await _unload()


## §3: a vehicle standing on the truck's spot moves just clear of it, within the driveway or yard,
## overlapping nothing (nor does the truck at home); the move leaves the snow as it was and moves
## nothing else.
func test_pf3_a_vehicle_on_the_spot_moves_clear() -> void:
	await _world()
	var truck: Vehicle = world.vehicle_nodes()[0]
	var ts := Game.truck_start()
	var lot := Layout.player_lot
	var yard: Rect2 = lot["rect"]
	var drive: Rect2 = Layout.house_info(lot)["driveway"]
	var bad := []
	for id in ["atv_blade", "tractor_blade"]:
		truck.global_position = Vector3(30.0, 0, 84.95)
		truck.rotation.y = -PI * 0.5
		await _frames(5)
		var tp: Vector3 = ts["pos"]
		var o := await _truck(id, tp.x + 0.4, tp.z - 0.6, float(ts["yaw"]) + 0.2)
		o.exit_vehicle()
		var other := await _truck("pickup", 50.0)       # elsewhere: stays put
		other.exit_vehicle()
		await _frames(5)
		var o_at := o.global_position
		var other_at := other.global_transform
		var vol := Snow.total_volume()
		await world.send_truck_home()
		var vol_same := absf(Snow.total_volume() - vol) < 1e-6
		await _frames(30)                                 # and stays so once the physics has caught up
		var moved := o.global_position.distance_to(o_at)
		var overlap := false
		for a in world._solid_boxes(o, o.global_transform):
			for b in world._solid_boxes(truck, truck.global_transform):
				if not Geometry2D.intersect_polygons(world._box_corners(a[0], a[1]), world._box_corners(b[0], b[1])).is_empty():
					overlap = true
		var hit := _pf3_touching(o) + _pf3_touching(truck)
		var inside := true
		for b in world._solid_boxes(o, o.global_transform):
			for c in world._box_corners(b[0], b[1]):
				inside = inside and (yard.has_point(c) or drive.has_point(c))
		var home := truck.global_position.distance_to(ts["pos"]) < 0.001
		runner.info("PF3 %s on the spot: moved %.2f m, overlapping the truck %s, touching %s, in the yard %s, the truck home %s, the snow the same %s" % [id, moved, str(overlap), str(hit), str(inside), str(home), str(vol_same)])
		if not (home and moved > 0.3 and moved < 6.0 and not overlap and hit.is_empty() and inside and vol_same and other.global_transform.is_equal_approx(other_at)):
			bad.append(id)
		for v in [o, other]:
			Game.vehicles.erase((v as Vehicle).entry)
			(v as Vehicle).queue_free()
		await _frames(2)
	runner.check(bad.is_empty(), "PF3 a vehicle on the truck's spot moves just clear of it (under 6 m), within the driveway or yard, overlapping nothing; the truck home; the snow and the other vehicles as they were %s" % str(bad))
	await _unload()

