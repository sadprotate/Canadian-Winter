extends RefCounted
## Polish pass 4 tests: interior (chair, computer screen, lamp), the framed photograph, the snow
## tool indicator, mailboxes at the foot of the walk, hourly forecasts and storm onsets, the save
## fixtures. Same harness as test_polish3.gd (real game scene, real input actions, fixed 60 fps).

var runner
var world: Node = null

const FIX3 := "res://tests/fixtures/polish3/"
const FIX4 := "res://tests/fixtures/polish4/"


func _tree() -> SceneTree:
	return runner.get_tree()


func _frames(n: int) -> void:
	for i in range(n):
		await _tree().physics_frame


## Polish 6 §8.1: a scoop can't start until the last throw's recovery (ToolData.throw_recovery_s) is
## over; a scripted stroke waits it out before pressing, as a player's turn back to the snow does.
func _s81_recovered() -> void:
	var tc = world.player.tools
	while tc.recovery > 0.0:
		await _tree().physics_frame


func _load_world(mode := "fun", seed_val := 2024, hour := 10.0, day := 1) -> void:
	await _unload()
	Game.force_input = true
	Game.new_game(mode, seed_val)
	Clock.reset(Clock.at(day, hour))
	await _spawn_world()
	Clock.running = false


func _spawn_world() -> void:
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(3)


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


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)
	await _frames(1)


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


func _press_btn(root: Node, text: String) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text.contains(text) and not (b as Button).disabled:
			(b as Button).pressed.emit()
			return true
	return false


## A mesh instance's bounds in world space.
static func _world_aabb(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.get_aabb()


## Every box shape of the solid static bodies (layer 1: furniture, walls, doors) under `root`, as
## world AABBs. Interaction volumes (layer 2 only) are not solid and are left out.
static func _collider_boxes(root: Node) -> Array:
	var out := []
	for b in root.find_children("*", "PhysicsBody3D", true, false):
		if ((b as CollisionObject3D).collision_layer & 1) == 0:
			continue
		for cs in (b as Node).get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
				var sz: Vector3 = ((cs as CollisionShape3D).shape as BoxShape3D).size
				out.append((cs as CollisionShape3D).global_transform * AABB(-sz * 0.5, sz))
	return out


# -----------------------------------------------------------------------------
# §0 The polish-4 save fixtures: each loads and plays — move, scoop, sleep (autosave), reload.
# (The polish-3 fixtures are covered by test_polish3's test_fixtures_load_and_play.)
# -----------------------------------------------------------------------------

## Polish 6 §3: where the fixture test stands the player on the street — 4 m out from the middle of
## the player's lot, as it always did, or the first point further out whose snow is under half the
## hip height. An older save is settled on load, and in round 5's mid-winter fixture and pass 4's
## storm fixture a street bank slumps over the lane's edge there (1.4–2 m deep).
static func _road_spot() -> Vector2:
	for k in range(25):
		var p := Layout.lot_to_world(Layout.player_lot, 0.0, -4.0 - k * 0.25)
		if Snow.depth_at(p.x, p.y) < CharacterModel.HIP_HEIGHT * 0.5:
			return p
	return Layout.lot_to_world(Layout.player_lot, 0.0, -4.0)


func test_polish4_fixtures_load_and_play() -> void:
	for mode in ["fun", "survival"]:
		for point in ["1_opening", "2_mid_trail", "3_trail_done", "4_contract", "5_midwinter", "6_storm"]:
			var name := "%s_%s.json" % [mode, point]
			var ok: bool = await _load_save_file(FIX4 + name)
			runner.check(ok, "%s loads" % name)
			if not ok:
				continue
			var stage := Game.stage()
			await _spawn_world()
			var pl: Player = world.player
			var road := _road_spot()
			pl.teleport(Vector3(road.x, 0.05, road.y), PI * 0.5)
			pl.pitch = 0.0
			await _frames(2)
			var p0 := pl.global_position
			await _hold("move_forward", 40)
			var moved := Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length()
			runner.check(moved > 0.05, "%s: the player moves (%.2f m)" % [name, moved])
			var spot := Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, -5.0), 5.0)
			pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
			await _frames(2)
			pl.pitch = deg_to_rad(-50.0)
			pl.head.rotation.x = pl.pitch
			var before := Snow.volume_in_rect(Rect2(Vector2(pl.global_position.x, pl.global_position.z) - Vector2(2.5, 2.5), Vector2(5, 5)))
			Input.action_press("primary")
			var base := pl.yaw
			for k in range(30):
				pl.set_yaw(base + 0.4 * sin(k * 0.15))
				await _tree().physics_frame
			pl.set_yaw(base)
			var got: float = pl.tools.load
			Input.action_release("primary")
			await _frames(30)
			runner.check(got > 0.001 or before < 0.01, "%s: scooping picks up snow (%.1f L)" % [name, got * 1000.0])
			_release_all()
			await world._do_sleep()
			await _frames(5)
			runner.check(Clock.hour() == 7 and Clock.minute_of_hour() == 0 and Saves.has_save(mode) and not Game.dirty_since_save, "%s: sleep ends at 7:00 and autosaves (%s)" % [name, Clock.format_time(Clock.minutes)])
			var t_saved := Clock.minutes
			var money_saved := Game.money
			await _unload()
			runner.check(Saves.load_game(mode), "%s: the autosave reloads" % name)
			await _spawn_world()
			runner.check(absf(Clock.minutes - t_saved) < 0.05 and Game.money == money_saved and Game.stage() >= stage and world.player != null, "%s: reloaded at the same time, money and stage" % name)
			await _unload()
		Saves.delete_save(mode)


# -----------------------------------------------------------------------------
# §2 Interior: chair, computer screen, living-room lamp
# -----------------------------------------------------------------------------

func test_chair_on_casters_and_clear() -> void:
	await _load_world("fun", 2024, 12.0, 0)
	var chair: MeshInstance3D = world.interior["chair"]
	var L := HouseBuilder.lot_transform(Layout.player_lot)
	var floor_y := (L * Vector3(0, InteriorBuilder.FY, 0)).y
	var casters: Array = world.interior["chair_casters"]
	runner.check(casters.size() == 5, "five casters (%d)" % casters.size())
	var worst := 0.0
	for c in casters:
		worst = maxf(worst, absf((c as Vector3).y - floor_y))
	var box := _world_aabb(chair)
	runner.check(worst < 0.01 and absf(box.position.y - floor_y) < 0.01, "the casters rest on the floor (%.3f m, chair bottom %.3f m from it)" % [worst, box.position.y - floor_y])
	var hits := 0
	for b in _collider_boxes(world):
		if (b as AABB).grow(-0.002).intersects(box.grow(-0.002)):
			hits += 1
	runner.check(hits == 0, "the chair intersects no furniture, wall or door (%d overlaps)" % hits)
	var body: Rect2 = Layout.house_info(Layout.player_lot)["body"]
	var inside := body.grow(-0.06)
	runner.check(inside.has_point(Vector2(box.position.x, box.position.z)) and inside.has_point(Vector2(box.end.x, box.end.z)), "…and stays inside the room, clear of the walls")


func test_computer_screen_lock_then_desktop() -> void:
	await _load_world("fun", 2024, 12.0, 0)
	var scr: ComputerScreen = world.interior["screen"]
	await _frames(3)
	runner.check(world.player.in_player_house and scr.showing == "lock", "before Gerry's quest: the lock screen (%s)" % scr.showing)
	var n0 := scr.renders
	await _frames(60)
	runner.check(scr.renders == n0, "nothing changes: no re-render (%d → %d)" % [n0, scr.renders])
	Clock.minutes += 1.0
	await _frames(2)
	runner.check(scr.renders == n0 + 1, "a new game minute: one re-render for the clock (%d)" % (scr.renders - n0))
	Game.flags["mail_read"] = true
	Game.flags["computer_unlocked"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	await _frames(2)
	runner.check(scr.showing == "desktop" and scr.renders == n0 + 2, "unlocked: the desktop (%s)" % scr.showing)
	# Outdoors the screen is never re-rendered.
	var out := Layout.lot_to_world(Layout.player_lot, 0.0, 3.0)
	world.player.teleport(Vector3(out.x, 0.05, out.y))
	await _frames(3)
	var n1 := scr.renders
	Clock.minutes += 5.0
	await _frames(10)
	runner.check(not world.player.in_player_house and scr.renders == n1, "outdoors: no renders while the clock moves on")
	# Using the computer opens the full UI as before.
	world.open_computer()
	await _frames(1)
	runner.check(world.modal_kind == "computer", "using the computer opens the computer UI")
	world.close_modal()
	await _unload()


## The room's lights exactly as at the polish-4 baseline (the lamp rework touches its base only).
const ROOM_LIGHTS := [[Vector3(-6.0, 2.2, 2.5), Color(1.0, 0.8, 0.55), 1.1, 6.0], [Vector3(-6.5, 2.2, 7.2), Color(1.0, 0.8, 0.55), 1.1, 6.0], [Vector3(0.2, 2.2, 6.8), Color(1.0, 0.8, 0.55), 1.1, 6.0]]


func test_living_room_lamp_lighting_unchanged() -> void:
	await _load_world("fun", 2024, 21.0, 0)
	var L := HouseBuilder.lot_transform(Layout.player_lot)
	var sb: float = Layout.player_lot["setback"]
	var lights: Array = world.interior["lights"]
	runner.check(lights.size() == 3, "three room lights (%d)" % lights.size())
	for i in range(mini(lights.size(), 3)):
		var l: OmniLight3D = lights[i]
		var want: Array = ROOM_LIGHTS[i]
		var p: Vector3 = L * (Vector3(want[0].x, InteriorBuilder.FY + want[0].y, sb + want[0].z))
		var same := l.global_position.distance_to(p) < 0.001 and l.light_color.is_equal_approx(want[1]) and is_equal_approx(l.light_energy, want[2]) \
			and is_equal_approx(l.omni_range, want[3]) and is_equal_approx(l.omni_attenuation, 1.0) and not l.shadow_enabled
		runner.check(same, "room light %d: type, position, colour, energy, range, attenuation and shadows unchanged" % i)
	var fl: OmniLight3D = world.interior["fire_light"]
	runner.check(fl.light_color.is_equal_approx(Color(1.0, 0.55, 0.2)) and is_equal_approx(fl.omni_range, 5.0), "the fire light unchanged (its energy flickers, as before)")
	# The lamp's shade and its glow: the same emissive material and size as before.
	var found := false
	for mi in world.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null or not (m is ArrayMesh):
			continue
		for si in range(m.get_surface_count()):
			var mat := m.surface_get_material(si)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled and (mat as StandardMaterial3D).emission.is_equal_approx(Color(1.0, 0.85, 0.6)) and is_equal_approx((mat as StandardMaterial3D).emission_energy_multiplier, 1.3):
				found = true
	runner.check(found, "the lamp shade keeps its glow (emissive 1.0/0.85/0.6 at 1.3)")
	await _unload()


# -----------------------------------------------------------------------------
# §5 The framed photograph
# -----------------------------------------------------------------------------

static func _sha(v) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(var_to_bytes(v))
	return hc.finish().hex_encode()


func test_photo_on_the_wall_beside_the_door() -> void:
	await _load_world("fun", 2024, 12.0, 0)
	var all := world.find_children("*", "FramedPhoto", true, false)
	var ph: FramedPhoto = world.interior.get("photo")
	runner.check(ph != null and all.size() == 1, "one framed photo, in the player's house (%d in the world)" % all.size())
	if ph == null:
		return
	var L := HouseBuilder.lot_transform(Layout.player_lot)
	var sb: float = Layout.player_lot["setback"]
	var local := L.affine_inverse() * ph.global_transform
	var half := FramedPhoto.outer_size() * 0.5
	var x0 := local.origin.x - half.x
	var x1 := local.origin.x + half.x
	runner.check(x1 < -2.05 - 0.1 and x0 > -3.6 + 0.25, "between the door (x -2.05) and the lamp's shade (x -3.35): %.2f … %.2f" % [x0, x1])
	runner.check(absf(local.origin.z - (sb + InteriorBuilder.WALL_INNER)) < 0.02 and local.basis.z.normalized().dot(Vector3(0, 0, 1)) > 0.999, "flat on the wall's inner face, facing the room (%.3f m off)" % (local.origin.z - sb - InteriorBuilder.WALL_INNER))
	var eye := local.origin.y - InteriorBuilder.FY
	runner.check(absf(eye - 1.6) < 0.1, "at eye height (%.2f m)" % eye)
	var box := AABB()
	var first := true
	for mi in ph.find_children("*", "MeshInstance3D", true, false):
		var bb := _world_aabb(mi)
		box = bb if first else box.merge(bb)
		first = false
	var hits := 0
	for b in _collider_boxes(world):
		if (b as AABB).grow(-0.003).intersects(box.grow(-0.003)):
			hits += 1
	runner.check(hits == 0, "it intersects nothing — the door, its frame, the furniture (%d)" % hits)
	var gerry_body: Rect2 = Layout.house_info(Layout.neighbor_lot)["body"]
	runner.check(not gerry_body.has_point(Vector2(ph.global_position.x, ph.global_position.z)), "none in Gerry's house")
	runner.check(ph.texture != null and not ph.captured, "headless: the placeholder print, no capture")
	await _unload()


## The photo scene is built from the game's own models without touching the game: no vehicle,
## no Game registry entry, no notification, the snow and the boxes unchanged.
func test_photo_scene_is_isolated() -> void:
	await _load_world("fun", 2024, 12.0, 0)
	var before := {"vehicles": Game.vehicles.size(), "items": Game.items.size(), "machines": Game.machines.size(),
		"nodes": world.vehicle_nodes().size(), "notes": Notify.history.size(), "snow": _sha(Snow.serialize()), "boxes": _sha(Boxes.serialize())}
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = FramedPhoto.PHOTO
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	runner.add_child(vp)
	FramedPhoto.build_scene(vp)
	await _frames(5)
	var bodies := vp.find_children("*", "PhysicsBody3D", true, false).size()
	var after := {"vehicles": Game.vehicles.size(), "items": Game.items.size(), "machines": Game.machines.size(),
		"nodes": world.vehicle_nodes().size(), "notes": Notify.history.size(), "snow": _sha(Snow.serialize()), "boxes": _sha(Boxes.serialize())}
	runner.check(str(before) == str(after), "the photo scene leaves the game untouched (%s)" % ("same" if str(before) == str(after) else str(after)))
	runner.check(bodies == 0 and vp.find_children("*", "Vehicle", true, false).is_empty(), "the truck is a plain mesh: no physics body, no vehicle")
	vp.queue_free()
	await _frames(2)
	await _unload()


# -----------------------------------------------------------------------------
# §3 The snow tool indicator: at the pickup spot while scooping, out at the landing spot when
# loaded, gliding between them
# -----------------------------------------------------------------------------

const HAND_TOOLS := ["", "small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh"]


func test_indicator_at_pickup_then_landing_every_tool() -> void:
	await _load_world("fun", 2024, 11.0, 1)
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var lot := Layout.player_lot
	var into := Vector2(lot["inward"]).normalized()
	var side := Vector2(into.y, -into.x)
	var worst_pick := 0.0
	var worst_land := 0.0
	var worst_step := 0.0
	var n_pick := 0
	var n_land := 0
	var spot := 0
	for tool in HAND_TOOLS:
		for view in ["fp", "tp"]:
			for pitch in [-60.0, -45.0, -30.0]:
				var u := -10.0 + float(spot % 6) * 1.6
				@warning_ignore("integer_division")
				var v := 3.0 + float((spot / 6) % 3) * 2.2
				spot += 1
				var p2 := Layout.lot_to_world(lot, Layout.gu(lot, u), v)
				Snow.set_rect(Rect2(p2 - Vector2(2.5, 2.5), Vector2(5, 5)), 0.6)
				pl.teleport(Vector3(p2.x, Snow.ground_at(p2.x, p2.y) + 0.05, p2.y))
				pl.set_third_person(view == "tp")
				Game.carried = ""
				Game.slots = [tool, "", "", ""]
				Game.select_slot(0)
				pl.set_yaw(atan2(-side.x, -side.y))
				pl.pitch = deg_to_rad(pitch)
				pl.head.rotation.x = pl.pitch
				await _frames(4)
				await _s81_recovered()
				var base := pl.yaw
				var last := Vector3.INF
				var last_feet := pl.global_position
				Input.action_press("primary")
				for k in range(24):
					pl.set_yaw(base + 0.3 * sin(k * 0.25))
					await _tree().physics_frame
					var ip := tc.indicator.global_position
					if tc.indicator.visible and last.x < INF:
						var own := Vector2(pl.global_position.x - last_feet.x, pl.global_position.z - last_feet.z).length()
						worst_step = maxf(worst_step, Vector2(ip.x - last.x, ip.z - last.z).length() - own)
					last = ip if tc.indicator.visible else Vector3.INF
					last_feet = pl.global_position
					if tc.last_fill > 0.0 and tc.ind_state == "pickup" and float(tc.get("_ind_glide")) >= 1.0:
						worst_pick = maxf(worst_pick, Vector2(ip.x, ip.z).distance_to(tc.last_cut_center))
						n_pick += 1
				# Look up to throw, still holding: once the load is full the indicator goes out to
				# where a release would land.
				pl.pitch = deg_to_rad(8.0)
				pl.head.rotation.x = pl.pitch
				for k in range(40):
					await _tree().physics_frame
					var ip2 := tc.indicator.global_position
					if tc.indicator.visible and last.x < INF:
						var own2 := Vector2(pl.global_position.x - last_feet.x, pl.global_position.z - last_feet.z).length()
						worst_step = maxf(worst_step, Vector2(ip2.x - last.x, ip2.z - last.z).length() - own2)
					last = ip2 if tc.indicator.visible else Vector3.INF
					last_feet = pl.global_position
				var ring := tc.indicator.global_position
				var landing_state: bool = tc.ind_state == "landing" and float(tc.get("_ind_glide")) >= 1.0
				var n0 := world.find_children("*", "ThrownSnow", true, false).size()
				Input.action_release("primary")
				await _tree().physics_frame
				var thrown := world.find_children("*", "ThrownSnow", true, false)
				if landing_state and thrown.size() > n0:
					var lp: Vector3 = (thrown[thrown.size() - 1] as ThrownSnow).landing["pos"]
					worst_land = maxf(worst_land, Vector2(ring.x - lp.x, ring.z - lp.z).length())
					n_land += 1
				runner.check(not tc.indicator.visible, "%s %s %d°: after the release the indicator is gone" % [tool if tool != "" else "hands", view, int(pitch)])
				await _frames(30)
	runner.check(n_pick > 100 and worst_pick < 0.15, "while scooping the indicator is on the cut (worst %.3f m over %d frames)" % [worst_pick, n_pick])
	runner.check(n_land >= 36 and worst_land < 0.25, "loaded, it is where the snow then lands (worst %.3f m over %d throws)" % [worst_land, n_land])
	runner.check(worst_step < 0.36, "it glides: no frame moves it more than a glide step beyond the player's own movement (%.3f m)" % worst_step)
	pl.set_third_person(false)
	_release_all()
	await _unload()


## Polish 5 §3 (Decision 12): over the street the indicator shows the landing like any other (it was
## red there and the load was kept): released, the snow lands on the street where it showed.
func test_indicator_over_street_like_any_other() -> void:
	await _load_world("fun", 2024, 11.0, 1)
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	Game.add_tool("standard_shovel")
	Game.select_slot(Game.slots.find("standard_shovel"))
	var lot := Layout.player_lot
	var spot := Layout.lot_to_world(lot, Layout.gu(lot, -9.0), -2.2)
	Snow.set_rect(Rect2(spot - Vector2(1, 1), Vector2(2, 2.4)), 0.3)
	pl.teleport(Vector3(spot.x, 0.05, spot.y))
	pl.set_yaw(PI if float(lot["dir"]) > 0 else 0.0)
	pl.pitch = deg_to_rad(-45.0)
	pl.head.rotation.x = pl.pitch
	await _frames(3)
	Input.action_press("primary")
	for k in range(40):
		pl.set_yaw((PI if float(lot["dir"]) > 0 else 0.0) + 0.3 * sin(k * 0.2))
		await _tree().physics_frame
	pl.set_yaw(0.0 if float(lot["dir"]) > 0 else PI)   # face the street
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	await _frames(30)
	var ring := tc.indicator.global_position
	runner.check(tc.ind_state == "landing" and tc.indicator.mesh == tc._ring_ok and Snow.is_road(ring.x, ring.z), "over the street: the indicator is out at the landing spot, like any other (%s)" % tc.ind_state)
	var n0 := world.find_children("*", "ThrownSnow", true, false).size()
	Input.action_release("primary")
	await _tree().physics_frame
	await _tree().physics_frame
	var thrown := world.find_children("*", "ThrownSnow", true, false)
	var lp: Vector3 = (thrown[thrown.size() - 1] as ThrownSnow).landing["pos"] if thrown.size() > n0 else Vector3.INF
	runner.check(tc.load == 0.0 and thrown.size() > n0 and Vector2(ring.x - lp.x, ring.z - lp.z).length() < 0.25 and Snow.is_road(lp.x, lp.z), "released over the street: the snow is thrown and lands on the street where the indicator was")
	await _frames(60)
	_release_all()
	await _unload()


# -----------------------------------------------------------------------------
# §4 Mailboxes at the foot of the walk, facing the street
# -----------------------------------------------------------------------------

func test_mailboxes_at_walk_corners_facing_the_street() -> void:
	await _load_world("fun", 2024, 11.0, 0)
	var bad := []
	var n := 0
	for lot in Layout.lots:
		if lot["vacant"]:
			continue
		n += 1
		var hi := Layout.house_info(lot)
		var mb: Vector2 = hi["mailbox"]
		var addr: String = lot["address"]
		var inward := Vector2(lot["inward"]).normalized()
		var walk: Rect2 = hi["walkway"]
		var drv: Rect2 = hi["driveway"]
		var side: Rect2 = hi["sidewalk"]
		# Expected: the walk's far edge from the driveway, the sidewalk's yard edge, then 0.65 m
		# out from the walk and 0.55 m into the yard.
		var away := Vector2(signf(walk.get_center().x - drv.get_center().x), 0.0) if absf(inward.y) > 0.5 else Vector2(0.0, signf(walk.get_center().y - drv.get_center().y))
		var walk_edge := walk.get_center() + away * (absf(walk.size.x) if absf(inward.y) > 0.5 else absf(walk.size.y)) * 0.5
		var yard_edge := side.get_center() + inward * (absf(side.size.y) if absf(inward.y) > 0.5 else absf(side.size.x)) * 0.5
		var corner := Vector2(walk_edge.x, yard_edge.y) if absf(inward.y) > 0.5 else Vector2(yard_edge.x, walk_edge.y)
		var want := corner + away * 0.65 + inward * 0.55
		if mb.distance_to(want) > 0.03:
			bad.append("%s off the corner spot by %.2f m" % [addr, mb.distance_to(want)])
		var inside := []
		for b in Boxes.boxes:
			for r in b["rects"]:
				if (r as Rect2).grow(0.15).has_point(mb):
					inside.append(b["id"])
		if not inside.is_empty():
			bad.append("%s inside %s" % [addr, str(inside)])
		if (drv.grow(0.3)).has_point(mb) or walk.grow(0.3).has_point(mb):
			bad.append("%s on the driveway / the junction" % addr)
		for bl in Layout.boulevards:
			if (bl as Rect2).has_point(mb):
				bad.append("%s on the boulevard" % addr)
		var node: Node3D = world.refs["mailboxes"][lot["index"]]
		var face := -node.global_transform.basis.z
		if Vector2(face.x, face.z).normalized().dot(-inward) < 0.99:
			bad.append("%s faces %s, not the street" % [addr, str(face)])
		if node.global_position.y != 0.0 or Snow.ground_at(mb.x, mb.y) != 0.0:
			bad.append("%s not standing on the ground" % addr)
		var to_side := Vector2(clampf(mb.x, side.position.x, side.end.x), clampf(mb.y, side.position.y, side.end.y)).distance_to(mb)
		if to_side > 1.0:
			bad.append("%s %.2f m from the sidewalk" % [addr, to_side])
	runner.check(n == 22 and bad.is_empty(), "all %d mailboxes at their walk–sidewalk corner, facing the street, outside every box, reachable from the sidewalk %s" % [n, str(bad)])
	# Street lamps and the keys.
	var lamps := []
	for x in world.builder.lamp_poles():
		var pole: Vector2 = x
		for lot in Layout.lots:
			if lot["vacant"]:
				continue
			var h := Layout.house_info(lot)
			if (h["driveway"] as Rect2).has_point(pole) or (h["walkway"] as Rect2).has_point(pole) or (h["mailbox"] as Vector2).distance_to(pole) < 1.0:
				lamps.append(str(pole))
	runner.check(lamps.is_empty(), "no street lamp on a driveway apron, a walkway or a mailbox %s" % str(lamps))
	var kp: Array = Game.flags.get("keys_pos", [0, 0])
	var near := INF
	for lot in Layout.lots:
		if not lot["vacant"]:
			near = minf(near, Vector2(kp[0], kp[1]).distance_to(Layout.house_info(lot)["mailbox"]))
	runner.check(near > 2.0, "the buried keys are clear of every mailbox (%.1f m)" % near)
	# Gerry's trail: the whole walk from his mailbox at the sidewalk up, and the steps.
	var hg := Layout.house_info(Layout.neighbor_lot)
	var trail: Array = Layout.gerry_trail_rects()
	runner.check(trail.size() == 2 and (trail[0] as Rect2).is_equal_approx(hg["walkway"]) and (trail[1] as Rect2).is_equal_approx(hg["stairs"]), "Gerry's trail is his walk from the sidewalk up, plus the steps")
	var t_vol := Snow.volume_in_rect(trail[0]) + Snow.volume_in_rect(trail[1])
	var t_area := (trail[0] as Rect2).get_area() + (trail[1] as Rect2).get_area()
	var sbg: float = Layout.neighbor_lot["setback"]
	var old_walk := Layout.lot_rect_world(Layout.neighbor_lot, Layout.gu(Layout.neighbor_lot, -2.1), Layout.gu(Layout.neighbor_lot, -0.9), clampf((sbg - 2.4) * 0.4, 2.4, 4.5) - 0.6, sbg - 2.4).merge(hg["stairs"])
	runner.info("Gerry's trail at the opening: %.2f m3 of snow on %.1f m2 (pass 3: %.2f m3 on %.1f m2)" % [t_vol, t_area, Snow.volume_in_rect(old_walk), old_walk.get_area()])
	await _unload()


## Old saves: the trail is rebuilt on the new rectangles while it is being cleared (progress from
## the snow); a save at or after TRAIL_DONE keeps it done and its stage.
func test_old_saves_and_the_moved_trail() -> void:
	for name in [FIX3 + "fun_2_mid_trail.json", FIX4 + "survival_2_mid_trail.json"]:
		var ok: bool = await _load_save_file(name)
		var b := Boxes.get_box("gerry_trail")
		var want := Layout.gerry_trail_rects()
		runner.check(ok and not b.is_empty() and b["rects"].size() == want.size() and (b["rects"][0] as Rect2).is_equal_approx(want[0]) and (b["rects"][1] as Rect2).is_equal_approx(want[1]), "%s: the trail rebuilt on the new rectangles" % name.get_file())
		var v := Boxes.snow_volume(b, true)
		runner.check(not b["complete"] and float(b["progress"]) > 0.0 and float(b["peak"]) >= v, "%s: …its progress from the snow (%.0f %%)" % [name.get_file(), float(b["progress"]) * 100.0])
		runner.check(Game.stage() == Game.Stage.NEIGHBOR_TALKED, "%s: …still clearing it" % name.get_file())
	for name in [FIX4 + "fun_3_trail_done.json", FIX4 + "survival_3_trail_done.json"]:
		var ok2: bool = await _load_save_file(name)
		var b2 := Boxes.get_box("gerry_trail")
		runner.check(ok2 and Game.stage() == Game.Stage.TRAIL_DONE and not b2.is_empty() and b2["complete"], "%s: the trail stays done, the stage TRAIL_DONE" % name.get_file())
		await _spawn_world()
		await _frames(20)
		runner.check(world.neighbor != null and world.neighbor.mode == "door_wait" and Boxes.get_box("gerry_trail")["complete"] and Game.stage() == Game.Stage.TRAIL_DONE, "%s: Gerry waits at his door; nothing reopened" % name.get_file())
		await _unload()


## Copy a save file over the mode's save and load it like the menu's Continue does.
func _load_save_file(path: String) -> bool:
	var mode := "survival" if path.get_file().begins_with("survival") else "fun"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Saves.DIR))
	for p in [Saves.path_for(mode), Saves.path_for(mode) + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(Saves.path_for(mode))) != OK:
		return false
	await _unload()
	Game.force_input = true
	return Saves.load_game(mode)


# -----------------------------------------------------------------------------
# §1 Weather: the truth, the storm onset, the forecast model, the TV and the radio
# -----------------------------------------------------------------------------

const WeatherTruth := preload("res://tests/weather_truth.gd")
const FC_SEEDS := [2024, 1, 7, 42, 99]


func _gen(seed_val: int, y: int) -> void:
	Weather.generate(y, seed_val + y * 13)


## The weather that actually falls is the pass-3 schedule: for seed 2024 and 20 other seeds,
## winters 1–5, the same events, tiers, totals, start and end, first and last snowy hour, the same
## per-winter totals, and the same alerts hour by hour.
func test_weather_truth_unchanged() -> void:
	await _unload()
	var f := FileAccess.open(FIX4 + "weather_truth_baseline.json", FileAccess.READ)
	var base: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var now := WeatherTruth.dump()
	var winters := 0
	var n := 0
	var bad := []
	var bad_tot := []
	for k in now.keys():
		winters += 1
		var a: Dictionary = base.get(k, {})
		var b: Dictionary = now[k]
		if a.is_empty() or (a["events"] as Array).size() != (b["events"] as Array).size():
			bad.append("%s: event count" % k)
			continue
		if absf(float(a["total"]) - float(b["total"])) > 0.002:
			bad_tot.append("%s %.3f→%.3f" % [k, float(a["total"]), float(b["total"])])
		for i in range((b["events"] as Array).size()):
			n += 1
			var ea: Array = a["events"][i]
			var eb: Array = b["events"][i]
			var same := str(ea[3]) == str(eb[3])
			for j in [0, 1, 2, 4, 5, 6]:
				same = same and absf(float(ea[j]) - float(eb[j])) < 0.001
			if not same:
				bad.append("%s #%d %s → %s" % [k, i, str(ea), str(eb)])
	runner.check(winters == 105 and n > 3000 and bad.is_empty(), "the weather that falls is unchanged: %d winters, %d events (same tier, condition, total, start, end, first and last snowy hour)%s" % [winters, n, "" if bad.is_empty() else " — " + str(bad.slice(0, 3))])
	runner.check(bad_tot.is_empty(), "…and every winter's total snowfall%s" % ("" if bad_tot.is_empty() else " — " + str(bad_tot.slice(0, 3))))
	var al := WeatherTruth.alerts_dump()
	var al_bad := []
	var al_n := 0
	for k in al.keys():
		var a2: Array = base["alerts"].get(k, [])
		var b2: Array = al[k]
		al_n += b2.size()
		if a2.size() != b2.size():
			al_bad.append("%s: %d → %d alerts" % [k, a2.size(), b2.size()])
			continue
		for i in range(b2.size()):
			if int(a2[i][0]) != int(b2[i][0]) or str(a2[i][1]) != str(b2[i][1]):
				al_bad.append("%s: %s → %s" % [k, str(a2[i]), str(b2[i])])
	runner.check(al_n > 50 and al_bad.is_empty(), "the alerts are the same, hour by hour (%d alerts over %d winters)%s" % [al_n, al.size(), "" if al_bad.is_empty() else " — " + str(al_bad.slice(0, 3))])


## Storms and major events open with at least a game hour of light-to-moderate snow, below the
## peak, then build; each event still drops exactly its total. Light snowfalls keep their shape.
func test_storm_onset_lead_in() -> void:
	await _unload()
	var onset: float = Catalog.balance.storm_onset_cm_h
	var n := 0
	var bad := []
	var tot_bad := 0
	for s in FC_SEEDS:
		for y in range(1, 6):
			_gen(s, y)
			for ev in Weather.events:
				var hrs: Dictionary = ev["hours"]
				var sum := 0.0
				var peak := 0.0
				for h in hrs.keys():
					sum += float(hrs[h])
					peak = maxf(peak, float(hrs[h]))
				if absf(sum - float(ev["total"])) > 0.001:
					tot_bad += 1
				if Weather.tier_of(ev) == "light":
					continue
				n += 1
				var st: float = ev["start"]
				var lead_top := 0.0
				var lead_len := 0.0
				var ok := true
				for h in range(int(st), int(ceil(st + 1.0 - 0.001))):
					var r := float(hrs.get(h, 0.0))
					var hc: int = ev["hcond"].get(h, Weather.C.CLEAR)
					lead_top = maxf(lead_top, r)
					lead_len += minf(float(h + 1), maxf(st + 1.0, float(h + 1))) - maxf(float(h), st)
					ok = ok and r <= onset + 0.0001 and (hc == Weather.C.LIGHT or hc == Weather.C.MODERATE)
				# …and it builds from there: the first hour after the lead-in is no lighter.
				var after := float(hrs.get(int(ceil(st + 1.0 - 0.001)), 0.0))
				ok = ok and lead_len >= 0.999 and lead_top < peak * 0.75 and after >= lead_top * 0.999
				if not ok:
					bad.append("%d/%d %s at %.1f h: lead %.2f cm/h over %.2f h, peak %.2f" % [s, y, Weather.tier_of(ev), st, lead_top, lead_len, peak])
	runner.check(n > 100 and bad.is_empty(), "%d storms and major events open with ≥1 game hour of light-to-moderate snow (≤ %.1f cm/h, below the peak)%s" % [n, onset, "" if bad.is_empty() else " — " + str(bad.slice(0, 3))])
	runner.check(tot_bad == 0, "…and every event, light ones included, drops exactly its total")


## The TV's text and the radio's bulletin for one moment of a storm are the same whether the time
## got there in real time, by sleeping, or by saving and loading (polish-4 mid-storm fixtures).
func test_forecast_same_in_real_time_after_sleep_and_reload() -> void:
	for mode in ["fun", "survival"]:
		var path: String = FIX4 + str(mode) + "_6_storm.json"
		var ok: bool = await _load_save_file(path)
		await _spawn_world()
		Clock.running = false
		var m0 := Clock.minutes
		var target: float = floor(m0 / 60.0) * 60.0 + 75.0
		runner.check(ok and Weather.is_snowing(), "%s: the storm fixture loads mid-storm (%s, %.1f cm/h)" % [mode, Clock.time_string(), Weather.snow_rate()])
		# Real time (sped up with the debug time scale, the clock still advancing frame by frame).
		Clock.time_scale = 40.0
		Clock.running = true
		var guard := 0
		while Clock.minutes < target and guard < 6000:
			await _frames(1)
			guard += 1
		Clock.running = false
		Clock.time_scale = 1.0
		var ta := Clock.minutes
		var a: Dictionary = await _weather_texts()
		await _unload()
		# Sleep skip to the same moment.
		await _load_save_file(path)
		await _spawn_world()
		Clock.running = false
		Clock.skip(ta - Clock.minutes)
		var b: Dictionary = await _weather_texts()
		# Save there and load it again.
		var saved := Saves.save_game()
		await _unload()
		var ok3 := Saves.load_game(mode)
		await _spawn_world()
		Clock.running = false
		var c: Dictionary = await _weather_texts()
		await _unload()
		runner.check(absf(ta - Clock.minutes) < 0.1 and a["radio"] == b["radio"] and b["radio"] == c["radio"], "%s: the radio says the same at %s in real time, after sleeping and after reloading: \"%s\"" % [mode, Clock.format_time(ta), a["radio"]])
		runner.check(a["tv"] == b["tv"], "%s: the TV shows the same in real time and after sleeping" % mode)
		runner.check(saved and ok3 and _no_alert(b["tv"]) == _no_alert(c["tv"]), "%s: …and after saving and loading (alert banner aside: recent alerts aren't saved, as before)" % mode)
		runner.check(str(a["tv"]).contains("Forecast updated %s" % Weather.hour_name(int(ta / 60.0))), "%s: the TV says when the forecast was updated" % mode)


func _weather_texts() -> Dictionary:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	runner.add_child(host)
	var root := Panels.tv(host, func(): pass)
	await _frames(1)
	var tv := []
	for l in root.find_children("*", "Label", true, false):
		tv.append((l as Label).text)
	host.queue_free()
	return {"tv": tv, "radio": Weather.radio_bulletin()}


static func _no_alert(tv: Array) -> Array:
	return tv.filter(func(t): return not str(t).begins_with("Latest alert"))


## Displays read the forecast model, not the hourly truth ahead of the current hour: scrambling
## the snowfall still to come changes neither the TV nor the radio.
func test_displays_dont_read_the_truth_ahead() -> void:
	await _load_world("fun", 2024, 10.0, 1)
	var ev: Dictionary = {}
	for e in Weather.events:
		if Weather.tier_of(e) == "storm" and not e["surprise"]:
			ev = e
			break
	Clock.minutes = (floor(float(ev["start"])) - 2.0) * 60.0 + 20.0
	var a: Dictionary = await _weather_texts()
	var issued := Weather.issued_hour()
	var keep := [Weather.rate.duplicate(), Weather.cond.duplicate(), Weather.temp.duplicate(), Weather.wind.duplicate()]
	for h in range(issued + 1, Weather.HOURS):
		Weather.rate[h] = 9.0
		Weather.cond[h] = Weather.C.BLIZZARD
		if h > issued + 1:   # the "now" temperature eases toward the next hour's, as before
			Weather.temp[h] = -40.0
			Weather.wind[h] = 99.0
	var b: Dictionary = await _weather_texts()
	Weather.rate = keep[0]
	Weather.cond = keep[1]
	Weather.temp = keep[2]
	Weather.wind = keep[3]
	runner.check(a["tv"] == b["tv"] and a["radio"] == b["radio"], "the TV and the radio don't read the hourly truth ahead of the current hour (2 h before a storm: \"%s\")" % a["radio"])
	await _unload()


## Forecast error shrinks as the target gets closer — hour by hour over the radio's range and the
## day ahead, day by day for the TV's cards — the radio's next hour beats the TV's three-day call,
## a forecast is revised every hour and converges, and a higher skill lowers the error.
func test_forecast_accuracy() -> void:
	await _unload()
	var leads := [1, 2, 3, 6, 12, 24]
	var derr := [0.0, 0.0, 0.0, 0.0]
	var dn := 0
	var err := {}
	for L in leads:
		err[L] = 0.0
	var cnt := 0
	var radio_hit := 0
	var tv_hit := 0
	var radio_err := 0.0
	var tv_err := 0.0
	var hits := 0
	var conv_bad := []
	var revised := 0
	for s in FC_SEEDS:
		for y in range(1, 4):
			_gen(s, y)
			for i in range(Weather.events.size()):
				var ev: Dictionary = Weather.events[i]
				var hrs: Dictionary = ev["hours"]
				for hv in hrs.keys():
					var h: int = hv
					if h < 80:
						continue
					hits += 1
					var truth := Weather.rate[h]
					var rf: Dictionary = Weather.fc_hour(h, h - 1, true)
					var tf: Dictionary = Weather.fc_hour(h, h - 60)
					radio_err += absf(float(rf["rate"]) - truth)
					tv_err += absf(float(tf["rate"]) - truth)
					radio_hit += 1 if int(rf["cond"]) == Weather.cond[h] else 0
					tv_hit += 1 if int(tf["cond"]) == Weather.cond[h] else 0
					if ev["surprise"] and Weather.tier_of(ev) == "major":
						continue
					cnt += 1
					for L in leads:
						err[L] += absf(float(Weather.fc_hour(h, h - L)["rate"]) - truth) / maxf(truth, 0.2)
					if Weather.fc_hour(h, h - 30)["rate"] != Weather.fc_hour(h, h - 29)["rate"]:
						revised += 1
				# Convergence: the event's amount and timing errors only shrink as it gets closer.
				pass
				if ev["surprise"]:
					continue
				var st: float = ev["start"]
				var pa := INF
				var ps := INF
				for back in [96, 72, 48, 36, 24, 12, 6, 3, 1]:
					var iss: int = int(floor(st)) - int(back)
					if iss < 0:
						continue
					var view: Dictionary = Weather._fc_view(i, iss, st - float(iss), false)
					var da := absf(float(view["scale"]) - 1.0)
					var ds := absf(float(view["shift"]))
					if da > pa + 1e-6 or ds > ps + 1e-6:
						conv_bad.append("%d/%d #%d at %d h before" % [s, y, i, back])
					pa = da
					ps = ds
			# The TV's day cards: a snowy day's total, called 3, 2, 1 and 0 days ahead.
			for d in range(4, 121):
				var day_total := 0.0
				for h in range(d * 24, d * 24 + 24):
					day_total += Weather.rate[h]
				if day_total < 1.0:
					continue
				dn += 1
				for k in range(4):
					var fcs := 0.0
					for h in range(d * 24, d * 24 + 24):
						fcs += float(Weather.fc_hour(h, d * 24 - 24 * k)["rate"])
					derr[k] += absf(fcs - day_total) / day_total
	var m := {}
	for L in leads:
		m[L] = err[L] / maxf(cnt, 1)
	var mono: bool = m[1] < m[2] and m[2] < m[3] and m[3] < m[6] and m[6] < m[12] and m[12] < m[24]
	runner.check(cnt > 1000 and mono, "the hourly error grows with lead (mean relative error of the rate: 1 h %.2f, 2 h %.2f, 3 h %.2f, 6 h %.2f, 12 h %.2f, 1 day %.2f; %d snowy hours)" % [m[1], m[2], m[3], m[6], m[12], m[24], cnt])
	for k in range(4):
		derr[k] /= maxf(dn, 1)
	runner.check(dn > 100 and derr[0] < derr[1] and derr[1] < derr[2] and derr[2] < derr[3], "a day's snow is called better as it gets closer (mean relative error today %.2f, 1 day ahead %.2f, 2 days %.2f, 3 days %.2f; %d snowy days)" % [derr[0], derr[1], derr[2], derr[3], dn])
	@warning_ignore("integer_division")
	runner.check(radio_err < tv_err and radio_hit > tv_hit, "the radio's next hour is more right than the TV's three-day call (condition right %d%% vs %d%%, rate off %.2f vs %.2f cm/h)" % [100 * radio_hit / maxi(hits, 1), 100 * tv_hit / maxi(hits, 1), radio_err / maxf(hits, 1), tv_err / maxf(hits, 1)])
	runner.check(conv_bad.is_empty(), "a forecast event's amount and timing errors only shrink as it approaches (converges)%s" % ("" if conv_bad.is_empty() else " — " + str(conv_bad.slice(0, 3))))
	@warning_ignore("integer_division")
	runner.check(revised > cnt / 2, "the forecast is revised every hour (%d of %d snowy hours changed between consecutive issues)" % [revised, cnt])
	# Skill: scales the error down and the surprise horizon up.
	var b: BalanceData = Catalog.balance
	var e1 := Weather.fc_error(48.0)
	var h1 := Weather.surprise_horizon_h()
	_gen(2024, 1)
	var sk1 := 0.0
	for ev in Weather.events:
		for hv in (ev["hours"] as Dictionary).keys():
			sk1 += absf(float(Weather.fc_hour(int(hv), int(hv) - 48)["rate"]) - Weather.rate[int(hv)])
	b.forecast_skill = 2.0
	var e2 := Weather.fc_error(48.0)
	var h2 := Weather.surprise_horizon_h()
	var sk2 := 0.0
	for ev in Weather.events:
		for hv in (ev["hours"] as Dictionary).keys():
			sk2 += absf(float(Weather.fc_hour(int(hv), int(hv) - 48)["rate"]) - Weather.rate[int(hv)])
	b.forecast_skill = 1.0
	runner.check(is_equal_approx(b.forecast_skill, 1.0) and e2 < e1 and h2 > h1 and sk2 < sk1, "a higher forecast skill lowers the error (2-day error %.2f → %.2f, total rate error %.0f → %.0f) and lengthens the radio's horizon (%.1f → %.1f h)" % [e1, e2, sk1, sk2, h1, h2])


## An unforecast major event is never on the TV before it starts; the radio picks it up no earlier
## than its surprise horizon; while an advisory is out the radio doesn't call clear skies for it.
func test_surprises_and_the_radio_horizon() -> void:
	await _load_world("fun", 2024, 10.0, 1)
	var hz := Weather.surprise_horizon_h()
	var n := 0
	var bad := []
	var said_bad := []
	var adv_bad := []
	for s in FC_SEEDS:
		for y in range(1, 6):
			_gen(s, y)
			for i in range(Weather.events.size()):
				var ev: Dictionary = Weather.events[i]
				if not (ev["surprise"] and Weather.tier_of(ev) == "major"):
					continue
				n += 1
				var st: float = ev["start"]
				var first := -1
				for iss in range(int(st) - 48, int(st) + 1):
					if float(iss) >= st:
						break
					if Weather._fc_view(i, iss, st - float(iss), false)["visible"]:
						bad.append("%d/%d TV at %d h before" % [s, y, int(st) - iss])
					if first < 0 and Weather._fc_view(i, iss, st - float(iss), true)["visible"]:
						first = iss
				if first >= 0 and float(first) < st - hz - 0.001:
					bad.append("%d/%d radio %.1f h early" % [s, y, st - float(first)])
				# What the displays actually say an hour before the radio's horizon.
				Clock.minutes = (floor(st - hz) - 1.0) * 60.0 + 15.0
				for e in Weather.forecast(3):
					for fe in e["events"]:
						if int(fe["cond"]) == Weather.C.BLIZZARD and absf(float(fe["start"]) - st) < 8.0:
							bad.append("%d/%d on the TV's day list" % [s, y])
				var quiet := true
				for other in Weather.events:
					if other != ev and float(other["end"]) > st - 12.0 and float(other["start"]) < st + 6.0:
						quiet = false
				if quiet:
					var early := Weather.radio_bulletin()
					Clock.minutes = (ceil(st - hz)) * 60.0 + 15.0
					var near := Weather.radio_bulletin()
					if early.contains("snow") or not near.contains("snow"):
						said_bad.append("%d/%d: \"%s\" / \"%s\"" % [s, y, early, near])
			# Advisories: while one is out, no radio hour inside the storm says clear or cloudy.
			for i in range(Weather.events.size()):
				var ev2: Dictionary = Weather.events[i]
				if int(ev2["fc_cond"]) < Weather.C.HEAVY:
					continue
				var st2: float = ev2["start"]
				for iss in range(int(ceil(st2 - 9.0)), int(ceil(st2))):
					for k in range(1, 4):
						var h := iss + k
						if float(h) >= st2 + 1.0 and float(h) < float(ev2["end"]) - 1.0:
							var fc: Dictionary = Weather.fc_hour(h, iss, true)
							if int(fc["cond"]) < Weather.C.LIGHT:
								adv_bad.append("%d/%d %d h" % [s, y, h])
	runner.check(n >= 3 and bad.is_empty(), "%d unforecast major events: never on the TV before they start, on the radio no earlier than %.1f h before%s" % [n, hz, "" if bad.is_empty() else " — " + str(bad.slice(0, 3))])
	runner.check(said_bad.is_empty(), "…the radio says nothing of one before its horizon and calls it once inside%s" % ("" if said_bad.is_empty() else " — " + str(said_bad.slice(0, 2))))
	runner.check(adv_bad.is_empty(), "while a severe-weather advisory is out the radio never calls a clear hour inside that storm%s" % ("" if adv_bad.is_empty() else " — " + str(adv_bad.slice(0, 3))))
	await _unload()


## The radio's bulletin: the next three game hours, each with the hour, the condition and the
## temperature; the rate when it's heavy; "right now" once it is snowing.
func test_radio_bulletin_reads_the_next_three_hours() -> void:
	await _load_world("fun", 2024, 10.0, 1)
	var ev: Dictionary = {}
	for e in Weather.events:
		if Weather.tier_of(e) == "storm":
			ev = e
			break
	var st: float = ev["start"]
	Clock.minutes = (floor(st) - 1.0) * 60.0 + 10.0
	var before := Weather.radio_bulletin()
	var h0 := Weather.issued_hour()
	var ok := true
	for k in range(1, 4):
		ok = ok and before.to_lower().contains(Weather.hour_name(h0 + k) + " ")
	runner.check(ok and before.contains("°") and before.count(".") >= 3 and not before.begins_with("Right now"), "before the storm: three hours, each with a condition, and the temperature: \"%s\"" % before)
	var peak_h := -1
	var pr := 0.0
	for hv in (ev["hours"] as Dictionary).keys():
		if float(ev["hours"][hv]) > pr:
			pr = float(ev["hours"][hv])
			peak_h = int(hv)
	Clock.minutes = float(int(ceil(st))) * 60.0 + 10.0
	var during := Weather.radio_bulletin()
	runner.check(during.begins_with("Right now: ") and during.contains("snow"), "once it's snowing the radio says what's happening now: \"%s\"" % during)
	Clock.minutes = float(peak_h - 2) * 60.0 + 10.0
	var heavy := Weather.radio_bulletin()
	runner.check(heavy.contains("cm an hour"), "heavy hours come with a snowfall rate: \"%s\"" % heavy)
	await _unload()


## Every bulletin fits the subtitle box and the fullest TV fits its screen, at 1280×720,
## 1920×1080, 2560×1440 and 3440×1440 (logical canvases 1920×1080 and 2580×1080).
func test_weather_text_fits() -> void:
	await _load_world("fun", 2024, 10.0, 1)
	var longest := ""
	var full_at := -1.0
	var full_score := -1
	for y in range(1, 6):
		_gen(2024, y)
		for ev in Weather.events:
			if Weather.tier_of(ev) == "light":
				continue
			for h in range(int(ev["start"]) - 3, mini(int(ceil(float(ev["end"]))) + 1, Weather.HOURS)):
				Clock.minutes = h * 60.0 + 20.0
				var t: String = world.radio_text()   # polish 5 §11: its crews' line read from the game
				if t.length() > longest.length():
					longest = t
	# The fullest TV: the moment of winter 1 with the most snow lines on its cards and an alert up.
	_gen(2024, 1)
	for ev in Weather.events:
		if Weather.tier_of(ev) == "light":
			continue
		for h in range(int(ev["start"]) - 30, int(ev["start"]) + 2, 4):
			Clock.minutes = h * 60.0 + 20.0
			var score := 0
			for e in Weather.forecast(3):
				score += 1 if Weather.snow_range_text(e) != "" else 0
			if score > full_score:
				full_score = score
				full_at = Clock.minutes
	Clock.minutes = full_at
	Weather.alerts.append({"time": Clock.minutes, "text": "WEATHER ALERT: an unforecast storm is dumping snow at 41 cm an hour — stay indoors!"})
	var hud: HUD = world.hud
	for res in ["1280x720", "1920x1080", "2560x1440", "3440x1440"]:
		var logical: Vector2 = {"1280x720": Vector2(1920, 1080), "1920x1080": Vector2(1920, 1080), "2560x1440": Vector2(1920, 1080), "3440x1440": Vector2(2580, 1080)}[res]
		hud.size = logical
		hud.subtitle(longest, 5.0)
		await _frames(2)
		var view := Rect2(hud.global_position, logical)
		var box := hud.subtitle_box.get_global_rect()
		var l := hud.subtitle_l
		runner.check(view.encloses(box) and box.end.y <= view.end.y - 249.0 and box.position.y > view.get_center().y + 60.0, "%s: the longest bulletin's box is on screen, above the hotbar, clear of the crosshair (%s)" % [res, str(box)])
		runner.check(l.get_line_count() == l.get_visible_line_count() and box.encloses(l.get_global_rect()), "%s: …and every line of it shows (%d lines, %d characters)" % [res, l.get_line_count(), longest.length()])
		var host := Control.new()
		host.size = logical
		runner.add_child(host)
		var root := Panels.tv(host, func(): pass)
		await _frames(3)
		var scr: Control = root.find_child("Screen", true, false)
		var content: Control = root.find_child("Content", true, false)
		var sr := scr.get_global_rect()
		var inside := true
		for lab in content.find_children("*", "Label", true, false):
			if (lab as Control).is_visible_in_tree() and not sr.encloses((lab as Control).get_global_rect()):
				inside = false
		var tvr: Control = root.find_child("TV", true, false)
		var upd: Control = root.find_child("Updated", true, false)
		var alert_l: Control = null
		for lab in content.find_children("*", "Label", false, false):
			if (lab as Label).text.begins_with("Latest alert"):
				alert_l = lab
		# Pass 3's TV grows by the alert line when one is up; the "updated" line adds nothing.
		var grow := sr.size.y - Panels.TV_SCREEN.y
		var allowed := 0.5 + (alert_l.size.y + float(content.get_theme_constant("separation")) if alert_l else 0.0)
		runner.check(Rect2(Vector2.ZERO, logical).encloses(tvr.get_global_rect()) and grow <= allowed and inside and upd != null and sr.encloses(upd.get_global_rect()), "%s: the fullest TV (%d snow lines, an alert) fits its screen, every line inside it (screen %s, %.0f px taller for the alert as in pass 3)" % [res, full_score, str(sr.size), grow])
		host.queue_free()
		await _frames(1)
	hud.subtitle("", 0.0)
	Weather.alerts.clear()
	await _unload()


# -----------------------------------------------------------------------------
# §7 A play-through from the menu with real input, both modes
# -----------------------------------------------------------------------------

const P3 := preload("res://tests/test_polish3.gd")


## Real shovel strokes along a box that is mostly dug out (like pass 3's), watching the indicator
## on every stroke: on the cut while scooping, out at the landing once loaded and looking up, gone
## after the release. Returns {strokes, pick, pick_bad, land, land_bad, after_bad}.
func _shovel_watching_indicator(h, b: Dictionary, away: Vector2, avoid: Vector2, avoid_r: float, frac: float) -> Dictionary:
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var peak := Boxes.snow_volume(b, true)
	h._leave(b, peak, frac)
	Boxes.measure(b, true)
	var r0: Rect2 = b["rects"][0]
	var long_x := r0.size.x > r0.size.y
	var half := (r0.size.y if long_x else r0.size.x) * 0.5
	var side := away.normalized() * maxf(half - 0.8, 0.0)
	var out := {"strokes": 0, "pick": 0, "pick_bad": 0, "land": 0, "land_bad": 0, "after_bad": 0}
	for k in range(30):
		if b["complete"]:
			break
		var f := (float(k % 15) + 0.5) / 15.0
		var at := r0.get_center() + side
		if long_x:
			at.x = r0.position.x + r0.size.x * f
		else:
			at.y = r0.position.y + r0.size.y * f
		if at.distance_to(avoid) < avoid_r:
			continue
		var along := Vector2(1, 0) if long_x else Vector2(0, 1)
		if k >= 15:
			along = -along
		pl.teleport(Vector3(at.x, Snow.ground_at(at.x, at.y) + 0.05, at.y))
		pl.set_yaw(atan2(-along.x, -along.y))
		pl.pitch = deg_to_rad(-50.0)
		pl.head.rotation.x = pl.pitch
		await _frames(3)
		await _s81_recovered()
		var base := pl.yaw
		Input.action_press("primary")
		for s in range(30):
			pl.set_yaw(base + 0.35 * sin(s * 0.2))
			await _tree().physics_frame
			if tc.last_fill > 0.0 and tc.ind_state == "pickup" and float(tc.get("_ind_glide")) >= 1.0:
				out["pick"] += 1
				var ip := tc.indicator.global_position
				if Vector2(ip.x, ip.z).distance_to(tc.last_cut_center) > 0.15:
					out["pick_bad"] += 1
		pl.set_yaw(atan2(-away.x, -away.y))
		pl.pitch = deg_to_rad(5.0)
		pl.head.rotation.x = pl.pitch
		await _frames(20)
		# Loaded and no longer cutting: out at the landing. (Turned towards a bank the blade can
		# still be biting snow — then it is rightly still on the cut.)
		if tc.load > 0.0:
			out["land"] += 1
			var want := "pickup" if tc.last_fill > 0.0 else "landing"
			if not (tc.indicator.visible and tc.ind_state == want):
				out["land_bad"] += 1
		Input.action_release("primary")
		await _frames(2)
		if tc.indicator.visible and tc.load <= 0.0:
			out["after_bad"] += 1
		await _frames(22)
		out["strokes"] += 1
	return out


## The TV's text (alert banner aside) and the radio's subtitle, opened with real input.
func _use_tv_and_radio(h) -> Dictionary:
	var hi := Layout.house_info(Layout.player_lot)
	var res := {"tv": [], "radio": "", "tv_open": false}
	var tvi: Node3D = world.interior["tv"]
	var tp := Vector2(tvi.global_position.x, tvi.global_position.z)
	var into := Vector2(hi["body"].get_center()) - tp
	await h._stand_at(tp + into.normalized() * 1.6, tvi.global_position)
	await _press_event("interact")
	await _frames(2)
	if world.modal_kind == "tv":
		res["tv_open"] = true
		for l in world.modal.find_children("*", "Label", true, false):
			if not (l as Label).text.begins_with("Latest alert"):
				res["tv"].append((l as Label).text)
		_press_btn(world.modal, "Turn off TV")
		await _frames(3)
	var rp: Vector3 = world.interior["radio_pos"]
	var r2 := Vector2(rp.x, rp.z)
	var rin := Vector2(hi["body"].get_center()) - r2
	await h._stand_at(r2 + rin.normalized() * 1.2, rp)
	await _press_event("interact")
	await _frames(3)
	res["radio"] = world.hud.subtitle_l.text if world.hud.subtitle_box.visible else ""
	return res


func test_playthrough_from_the_menu_both_modes() -> void:
	var h = P3.new()
	h.runner = runner
	for mode in ["fun", "survival"]:
		await _unload()
		Saves.delete_save(mode)
		var m: Node = await h._open_menu()
		var r: Dictionary = await h._menu_start(m, mode, "New Game")
		await h._close_menu(m)
		runner.check(r.get("mode", "") == mode, "%s: started from the menu" % mode)
		Game.force_input = true
		await h._spawn_world()
		world = h.world
		Clock.running = true
		var pl: Player = world.player
		var lot := Layout.player_lot
		var hi := Layout.house_info(lot)
		# 1. The letter, from the moved mailbox (standing at the foot of the walk by the sidewalk).
		var mb: Vector2 = hi["mailbox"]
		await h._stand_at(hi["mailbox_path_point"], Vector3(mb.x, Snow.ground_at(mb.x, mb.y) + 1.05, mb.y))
		runner.check(pl.focus_prompt.to_lower().contains("mailbox"), "%s: the mailbox prompt shows from the foot of the walk (%s)" % [mode, pl.focus_prompt])
		await _press_event("interact")
		runner.check(world.modal_kind == "letter", "%s: the hydro letter opens" % mode)
		_press_btn(world.modal, "Close")
		await _frames(10)
		var sh: ToolItem = h._shovel_item()
		h._expose(sh, 0.78)
		await h._face_item(sh)
		await _press_event("interact")
		runner.check(Game.slots.find("small_shovel") >= 0, "%s: the small shovel is picked up" % mode)
		# 2. Your computer before Gerry: the lock screen.
		var scr: ComputerScreen = world.interior["screen"]
		var comp: Node3D = world.interior["computer"]
		var cp := Vector2(comp.global_position.x, comp.global_position.z)
		var room := Vector2(hi["body"].get_center()) - cp
		await h._stand_at(cp + room.normalized() * 1.2, comp.global_position)
		await _frames(5)
		runner.check(pl.in_player_house and scr.showing == "lock", "%s: your computer shows its lock screen before Gerry's job (%s)" % [mode, scr.showing])
		# 3. Gerry's job: the trail from the sidewalk up, outlined, no flags.
		var g: Neighbor = world.neighbor
		h._stand_near(g.global_position, 3.0)
		await _frames(4)
		await _press_event("interact")
		await _frames(2)
		var guard := 0
		while world.modal_kind == "dialogue" and guard < 20:
			if not _press_btn(world.modal, "$55"):
				_press_btn(world.modal, "Continue")
			await _frames(1)
			guard += 1
		await _frames(20)
		var stakes := 0
		for k in world.zone_markers._stakes.keys():
			for c in Contracts.active:
				if c.get("tutorial", false) and str(k).begins_with("%d_" % int(c["id"])):
					stakes += 1
		var hg := Layout.house_info(Layout.neighbor_lot)
		var trail: Array = Boxes.get_box("gerry_trail").get("rects", [])
		var from_sidewalk: bool = not trail.is_empty() and (trail[0] as Rect2).grow(0.05).intersects(hg["sidewalk"])
		runner.check(Game.stage() == Game.Stage.NEIGHBOR_TALKED and world.quest_outline.visible and world.quest_outline.box_id == "gerry_trail" and stakes == 0 and from_sidewalk, "%s: Gerry's trail runs up from the sidewalk, outlined, no flags" % mode)
		h._finish_trail()
		# Gerry walks down to meet you at his mailbox.
		guard = 0
		while g.mode != "meet" and guard < 900:
			await _frames(1)
			guard += 1
		await _frames(120)
		var meet := Neighbor.meet_point()
		runner.check(g.mode == "meet" and Vector2(g.global_position.x - meet.x, g.global_position.z - meet.z).length() < 0.6 and Vector2(g.global_position.x, g.global_position.z).distance_to(hg["mailbox"]) < 2.0, "%s: Gerry meets you by his mailbox (%.2f m from it)" % [mode, Vector2(g.global_position.x, g.global_position.z).distance_to(hg["mailbox"])])
		h._stand_near(g.global_position, 1.4)
		await _frames(4)
		await _press_event("interact")
		await _frames(3)
		guard = 0
		while g.mode != "door_wait" and guard < 900:
			await _frames(1)
			guard += 1
		h._stand_near(Neighbor.door_point(), 1.2)
		guard = 0
		while not world.neighbor_door.open and guard < 300:
			await _frames(1)
			guard += 1
		Input.action_press("move_forward")
		guard = 0
		while not pl.in_neighbor_house and guard < 300:
			await _frames(1)
			guard += 1
		Input.action_release("move_forward")
		var saw_computer := false
		guard = 0
		while Game.stage() != Game.Stage.COMPLETE and guard < 60:
			await _frames(30)
			if world.hud.speech_text.text.contains("computer"):
				saw_computer = true
			if world.is_gerry_talking() and world._talk_started:
				await _press_event("interact")
			guard += 1
		runner.check(pl.in_player_house == false and saw_computer and Game.stage() == Game.Stage.COMPLETE, "%s: followed Gerry in; the computer intro; tutorial complete" % mode)
		# 4. Home: the desktop, and a contract from the board.
		await h._stand_at(cp + room.normalized() * 1.2, comp.global_position)
		await _frames(5)
		runner.check(scr.showing == "desktop", "%s: your computer now shows its desktop (%s)" % [mode, scr.showing])
		await _press_event("interact")
		await _frames(2)
		if world.modal_kind == "computer":
			var c: ComputerUI = world.modal
			c._open_app(ComputerUI.app_index("board"))
			await _frames(1)
			_press_btn(c.content, "OK")   # polish 5 §7: name the company (the suggestion) the first time
			await _frames(1)
			for tries in range(4):
				var sl := c.content.find_children("*", "HSlider", true, false)
				if sl.is_empty():
					break
				(sl[0] as HSlider).value = (sl[0] as HSlider).min_value
				_press_btn(c.content, "Place bid")
				await _frames(1)
			world.close_modal()
		runner.check(not Contracts.bids.is_empty(), "%s: bids placed from the contract board" % mode)
		# Polish 5 §10: bids are answered at the award, 9:01 p.m. (was: within a few hours).
		Clock.skip(Contracts.next_9pm(Clock.minutes) + Contracts.AWARD_DELAY_MIN + 1.0 - Clock.minutes)
		var won := false
		for ct in Contracts.active:
			if not ct.get("tutorial", false):
				won = true
		runner.check(won, "%s: a contract is won" % mode)
		# 5. Clear your own path, the indicator under the shovel and then at the landing.
		var drv: Rect2 = hi["driveway"]
		var walk: Rect2 = hi["walkway"]
		var away := Vector2(signf(walk.get_center().x - drv.get_center().x), 0.0)
		var truck := Vector2(Game.vehicles[0]["pos"].x, Game.vehicles[0]["pos"].z)
		var b := Boxes.get_box(Boxes.lot_box(lot, "path"))
		var st: Dictionary = await _shovel_watching_indicator(h, b, away, truck, 3.6, 0.12)
		runner.check(b["complete"], "%s: the path cleared to the 90 %% snap (%d strokes)" % [mode, st["strokes"]])
		runner.check(st["pick"] > 20 and st["pick_bad"] == 0 and st["land"] > 0 and st["land_bad"] == 0 and st["after_bad"] == 0, "%s: the indicator was on the cut while scooping (%d frames, %d off), at the landing when loaded (%d strokes, %d not), gone after each throw (%d not)" % [mode, st["pick"], st["pick_bad"], st["land"], st["land_bad"], st["after_bad"]])
		# 6. The TV and the radio.
		var heard: Dictionary = await _use_tv_and_radio(h)
		runner.check(heard["tv_open"] and str(heard["tv"]).contains("Forecast updated"), "%s: the TV's forecast, with when it was updated" % mode)
		runner.check(str(heard["radio"]).begins_with("Radio: ") and str(heard["radio"]).to_lower().contains(Weather.hour_name(Weather.issued_hour() + 1)), "%s: the radio reads the next hours: \"%s\"" % [mode, heard["radio"]])
		# 7. Wait out the start of the next scheduled storm indoors, listening to the radio.
		var ev: Dictionary = {}
		for e in Weather.events:
			if Weather.tier_of(e) == "storm" and float(e["start"]) > Clock.minutes / 60.0 + 3.0:
				ev = e
				break
		var s0: float = ev["start"]
		var target := (s0 - 1.4) * 60.0
		while Clock.minutes < target - 0.5:
			if Game.is_survival():
				Game.money = maxi(Game.money, 1500)
				for bl in Economy.unpaid_bills():
					Economy.pay_bill(int(bl["month"]))
				Survival.warmth = 100.0
			Clock.skip(minf(1440.0, target - Clock.minutes))
		var before: Dictionary = await _use_tv_and_radio(h)
		runner.check(str(before["radio"]).contains("snow") and not str(before["radio"]).contains("Right now"), "%s: before the storm the radio calls the snow coming: \"%s\"" % [mode, before["radio"]])
		var onset: float = Catalog.balance.storm_onset_cm_h
		var lead_ok := true
		var lead_seen := 0
		var during := ""
		var blend_seen := false
		Clock.time_scale = 30.0
		guard = 0
		while Clock.minutes < (s0 + 1.6) * 60.0 and guard < 3000:
			await _frames(5)
			guard += 5
			if Game.is_survival():
				Survival.warmth = maxf(Survival.warmth, 60.0)
			var hnow := Clock.minutes / 60.0
			if hnow >= s0 and hnow < floor(s0) + 1.999:
				lead_seen += 1
				lead_ok = lead_ok and Weather.condition() in [Weather.C.LIGHT, Weather.C.MODERATE] and Weather.snow_rate() <= onset + 0.0001
			if fmod(Clock.minutes, 60.0) < 4.0 and Weather.visual_mix() < 1.0 and absf(Weather.visual_rate() - Weather.snow_rate()) > 0.0001:
				blend_seen = true
			if during == "" and hnow >= s0 + 0.4:
				Clock.time_scale = 1.0
				var dr: Dictionary = await _use_tv_and_radio(h)
				during = dr["radio"]
				Clock.time_scale = 30.0
		Clock.time_scale = 1.0
		runner.check(lead_seen > 10 and lead_ok, "%s: the storm opened with light-to-moderate snow for its first hour or more (%d samples)" % [mode, lead_seen])
		runner.check(during.contains("Right now:") and during.contains("snow"), "%s: once it's snowing the radio says what's happening now: \"%s\"" % [mode, during])
		runner.check(blend_seen, "%s: the look of the weather eases into each new hour" % mode)
		# 8. The picture by the front door.
		var ph: FramedPhoto = world.interior["photo"]
		var pn := ph.global_transform.basis.z.normalized()
		await h._stand_at(Vector2(ph.global_position.x + pn.x * 1.5, ph.global_position.z + pn.z * 1.5), ph.global_position)
		var cam := pl.active_camera()
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, ph.global_position + pn * 0.04)
		q.exclude = [pl.get_rid()]
		var hit := pl.get_world_3d().direct_space_state.intersect_ray(q)
		runner.check(cam.is_position_in_frustum(ph.global_position) and hit.is_empty() and -cam.global_transform.basis.z.dot((ph.global_position - cam.global_position).normalized()) > 0.95, "%s: the photo by the door is in view, nothing in the way" % mode)
		# 9. Sleep in the bed; at 7:00 the TV and radio; reload: the same.
		var bed: Node3D = world.interior["bed"]
		var bp := Vector2(bed.global_position.x, bed.global_position.z)
		var bin := Vector2(hi["body"].get_center()) - bp
		await h._stand_at(bp + bin.normalized() * 1.5, bed.global_position)
		await _press_event("interact")
		await _frames(2)
		# A real click arrives outside the physics step; unpausing between the physics server's query
		# flush and its step makes the engine print `p_elem->_root` (HANDOFF §13 item 12).
		await _tree().process_frame
		_press_btn(world.modal, "Sleep until 7:00 a.m.")
		guard = 0
		while (not Saves.has_save(mode) or Game.dirty_since_save) and guard < 900:
			await _frames(5)
			guard += 5
		await _frames(10)
		Clock.running = false
		var t_s := Clock.minutes
		runner.check(Saves.has_save(mode) and Clock.hour() == 7, "%s: slept to 7:00, saved" % mode)
		var a: Dictionary = await _use_tv_and_radio(h)
		var saved := Saves.peek(mode)
		await h._unload()
		world = null
		var ok := Saves.load_game(mode)
		await h._spawn_world()
		world = h.world
		Clock.running = false
		Clock.minutes = t_s
		var c2: Dictionary = await _use_tv_and_radio(h)
		runner.check(ok and Game.money == int(saved.get("money", -1)) and Game.stage() == Game.Stage.COMPLETE, "%s: the save reloads" % mode)
		runner.check(a["tv"] == c2["tv"] and a["radio"] == c2["radio"] and a["radio"] != "", "%s: after the reload the TV and the radio say the same: \"%s\"" % [mode, a["radio"]])
		if mode == "survival":
			runner.check(Survival.active and not world._dead, "survival: alive, the cold on")
		_release_all()
		await h._unload()
		world = null
		Saves.delete_save(mode)
