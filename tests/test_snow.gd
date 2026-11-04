extends RefCounted
## Snow simulation tests (Part 30.2): existence, removal, conservation, road rule, relaxation,
## snowfall, persistence, performance.

var runner


func _region_volume(center: Vector2, half: float) -> float:
	return Snow.volume_in_rect(Rect2(center - Vector2(half, half), Vector2(half * 2, half * 2)))


func _player_lot_point(u: float, v: float) -> Vector2:
	return Layout.lot_to_world(Layout.player_lot, u, v)


func test_static_map() -> void:
	Layout.ensure()
	runner.check(Snow.is_road(50.0, 83.0), "Maple Street centre is road")
	runner.check(not Snow.is_road(50.0, 92.0), "Player front yard is not road")
	var hi := Layout.house_info(Layout.player_lot)
	var body: Rect2 = hi["body"]
	runner.check(Snow.surface_at(body.get_center().x, body.get_center().y) == Snow.S_BLOCKED, "House body blocks snow")
	var porch: Rect2 = hi["porch"]
	runner.near(Snow.ground_at(porch.get_center().x, porch.get_center().y), Layout.PORCH_H, 0.001, "Porch ground height")
	runner.check(Layout.lots.size() == 24, "24 properties (22 houses + 2 vacant)")
	runner.info("player lot: %s, neighbor: %s" % [Layout.player_lot["address"], Layout.neighbor_lot["address"]])


func test_initial_fill_year1() -> void:
	Snow.reset_for_winter(1)
	var p := _player_lot_point(-6.0, 5.0)
	var d := Snow.depth_at(p.x, p.y)
	runner.check(d > 0.75 and d < 1.15, "Front lawn ~0.9 m on Dec 1 (got %.2f)" % d)
	var road_d := Snow.depth_at(50.0, 83.0)
	runner.check(road_d > 0.45 and road_d < 0.7, "Street ~0.55 m (got %.2f)" % road_d)
	runner.check(Snow.surface_height(p.x, p.y) > 0.7, "Surface height reflects snow")


func test_scoop_and_deposit_conserve_volume() -> void:
	Snow.reset_for_winter(1)
	var src := _player_lot_point(-6.0, 6.0)
	var dst := _player_lot_point(-11.0, 6.0)
	var region_c := (src + dst) * 0.5
	var before := _region_volume(region_c, 6.0)
	var r: Dictionary = Snow.scoop(src, Vector2(0, 1), 0.46, 0.5, 0.04)
	runner.near(r["volume"], 0.04, 0.0005, "Scoop takes the shovel's capacity from deep snow")
	var mid := _region_volume(region_c, 6.0)
	runner.near(before - mid, r["volume"], 1e-4, "Source lost the scooped volume")
	Snow.deposit(dst, r["volume"], 0.5)
	Snow.relax_until_stable()
	var after := _region_volume(region_c, 6.0)
	runner.near(after, before, 1e-3, "Volume conserved after deposit + relaxation")


func test_shallow_scoop_takes_all() -> void:
	Snow.reset_for_winter(1)
	var p := _player_lot_point(-6.0, 6.0)
	Snow.set_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), 0.02)
	var r: Dictionary = Snow.scoop(p + Vector2(0, -0.2), Vector2(0, 1), 0.46, 0.5, 0.04, 0.0)
	runner.check(r["volume"] < 0.04 and r["volume"] > 0.0, "Shallow scoop takes what is there (%.4f)" % r["volume"])
	runner.check(Snow.depth_at(p.x, p.y) < 0.001, "Scooped cell is clean")


## Polish 5 §3 (Decision 12): the road rule is gone for snow the player moves (it was "deposit never
## on road"): a player's deposit (allow_road = true, what thrown snow passes now) at the curb line
## lands on the street where it was aimed, volume conserved. Relaxation is unchanged: yard snow
## still doesn't slump over the curb on its own.
func test_deposit_lands_on_road_where_aimed() -> void:
	Snow.reset_for_winter(1)
	var road_rect := Rect2(40, 79, 20, 8)
	var area := Rect2(40, 75, 20, 18)
	var road_before := Snow.volume_in_rect(road_rect)
	var before := Snow.volume_in_rect(area)
	# Throw right at the curb line from the boulevard side.
	Snow.deposit(Vector2(50.0, 87.2), 0.5, 1.2, true)
	var road_after := Snow.volume_in_rect(road_rect)
	runner.check(road_after > road_before + 0.1, "The street side of the splat lands on the road where it was aimed (+%.3f m3)" % (road_after - road_before))
	runner.near(Snow.volume_in_rect(area), before + 0.5, 1e-4, "Volume conserved")
	# A pile thrown just on the yard side of the curb stays there: the curb is still a wall for slumping.
	Snow.reset_for_winter(1)
	var road0 := Snow.volume_in_rect(road_rect)
	Snow.deposit(Vector2(50.0, 87.8), 0.5, 0.6, true)
	runner.near(Snow.volume_in_rect(road_rect), road0, 1e-5, "A splat on the yard side puts nothing on the road")
	Snow.relax_until_stable()
	runner.near(Snow.volume_in_rect(road_rect), road0, 1e-5, "…and its slump doesn't cross the curb (relaxation unchanged)")


## Polish 5 §3 (Decision 12): a player's push (player_rule = false, what every tool and vehicle
## passes now) carries the berm over the curb onto the street (it was "respects curb").
func test_blade_push_moves_berm_over_the_curb() -> void:
	Snow.reset_for_winter(1)
	var hi := Layout.house_info(Layout.player_lot)
	var drv: Rect2 = hi["driveway"]
	Snow.set_rect(drv, 0.06)
	var road_rect := Rect2(drv.position.x - 2, 79, drv.size.x + 4, 8)
	var road_before := Snow.volume_in_rect(road_rect)
	var area := drv.grow(3.0)
	var before := Snow.volume_in_rect(area)
	# Push from the garage toward the street (−z for the player lot).
	var x := drv.get_center().x
	var z := drv.end.y - 0.6
	var moved := 0.0
	var steps := 0
	while z > drv.position.y - 1.0:
		var r: Dictionary = Snow.blade_push(Vector2(x, z), Vector2(0, -1), 0.45, 0.06, 0.0, false)
		moved += r["moved"]
		z -= 0.05
		steps += 1
	Snow.relax_until_stable()
	var after := Snow.volume_in_rect(area)
	var road_after := Snow.volume_in_rect(road_rect)
	runner.check(moved > 0.05, "Blade moved snow (%.3f m3 over %d steps)" % [moved, steps])
	runner.near(after, before, 2e-3, "Push conserves volume")
	runner.check(road_after > road_before + 0.05, "Pushed snow carried over the curb onto the road (%.4f -> %.4f)" % [road_before, road_after])
	var street_d := Snow.depth_at(x, 85.6)
	runner.check(street_d > 0.1, "The berm ends up on the street, where it was pushed (%.2f m)" % street_d)
	var cleared := Snow.depth_at(x, drv.get_center().y)
	runner.check(cleared < 0.01, "Driveway path cleared to pavement (%.3f m)" % cleared)


func test_road_snow_can_be_pushed_off_road() -> void:
	Snow.reset_for_winter(1)
	var lane := Rect2(40, 79, 20, 8)
	Snow.set_rect(Rect2(20, 79, 60, 8), 0.05)
	var before := Snow.volume_in_rect(lane.grow(4))
	var road_before := Snow.volume_in_rect(lane)
	var z := 83.0
	for k in range(120):
		Snow.blade_push(Vector2(50.0, z), Vector2(0, 1), 0.6, 0.06, 0.0, true)
		z += 0.05
	Snow.relax_until_stable()
	runner.check(Snow.volume_in_rect(lane) < road_before, "Road snow pushed off the road")
	runner.near(Snow.volume_in_rect(lane.grow(4)), before, 2e-3, "Conserved")


func test_relaxation_angle_of_repose() -> void:
	Snow.reset_for_winter(1)
	var p := _player_lot_point(-9.0, 3.0)
	Snow.set_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), 0.0)
	var before := _region_volume(p, 6.0)
	Snow.deposit(p, 2.0, 0.3)
	var peak := Snow.depth_at(p.x, p.y)
	var t := Time.get_ticks_usec()
	Snow.relax_until_stable()
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	var after := _region_volume(p, 6.0)
	runner.near(after, before + 2.0, 2e-3, "Relaxation conserves volume")
	var peak2 := Snow.depth_at(p.x, p.y)
	runner.check(peak2 < peak and peak2 > 0.6, "Tall pile slumped into a mound (%.2f -> %.2f m)" % [peak, peak2])
	# Check max slope between neighbours.
	var worst := 0.0
	for dz in range(-12, 13):
		for dx in range(-12, 12):
			var a := Snow.surface_height(p.x + dx * 0.25, p.y + dz * 0.25)
			var b := Snow.surface_height(p.x + (dx + 1) * 0.25, p.y + dz * 0.25)
			worst = maxf(worst, absf(a - b))
	runner.check(worst <= Snow.repose + 0.06, "Slopes within repose (%.3f m per cell)" % worst)
	runner.info("relaxing a 2 m3 dump took %.1f ms" % ms)


func test_snowfall_accumulates_lazily() -> void:
	Snow.reset_for_winter(1)
	var p := _player_lot_point(-6.0, 6.0)
	Snow.set_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), 0.0)
	Snow.add_snowfall(0.05)
	var d := Snow.depth_at(p.x, p.y)
	runner.check(d > 0.035 and d < 0.075, "Cleared cell received new snow (%.3f)" % d)
	var road := Snow.depth_at(50, 83)
	runner.check(road > 0.55, "Road received snowfall too")


func test_intake_and_settle() -> void:
	Snow.reset_for_winter(1)
	var p := _player_lot_point(-6.0, 6.0)
	var r: Dictionary = Snow.intake(p, Vector2(0, 1), 0.56, 0.35, 0.065)
	runner.near(r["volume"], 0.065, 1e-4, "Blower intake takes its rate budget")
	var d0 := Snow.depth_at(p.x - 3, p.y)
	Snow.advance_settle(1440.0 * 5)
	Snow.add_snowfall(0.05)
	Snow.sync_all()
	var d1 := Snow.depth_at(p.x - 3, p.y)
	var m := Snow.fall_mult[Snow.cell_z(p.y) * Snow.W + Snow.cell_x(p.x - 3)]
	# Polish §8: settling no longer eats the new snow — 5 days later a 5 cm fall is all still there.
	runner.near(d1, d0 + 0.05 * m, 1e-4, "New snow lands on top of deep snow and stays (%.3f -> %.3f)" % [d0, d1])


func test_serialize_roundtrip_exact() -> void:
	Snow.reset_for_winter(1)
	var p := _player_lot_point(-6.0, 6.0)
	for k in range(20):
		var r: Dictionary = Snow.scoop(p + Vector2(k * 0.1, 0), Vector2(0, 1), 0.46, 0.5, 0.04)
		Snow.deposit(p + Vector2(-4, k * 0.2), r["volume"], 0.5)
	Snow.relax_until_stable()
	Snow.add_snowfall(0.013)
	var data := Snow.serialize()
	var copy := Snow.depth.duplicate()  # serialize() snapped the live state to the saved precision
	var comp: PackedByteArray = data["data"]
	@warning_ignore("integer_division")
	runner.info("compressed snow state: %d KB (raw %d KB)" % [comp.size() / 1024, int(data["size"]) / 1024])
	Snow.reset_for_winter(1)
	runner.check(Snow.deserialize(data), "Deserialize succeeded")
	var same := Snow.depth == copy
	runner.check(same, "Snow restored bit-exactly after save/load")
	runner.check(comp.size() < 700 * 1024, "Snow save is compact")


func test_grader_lane() -> void:
	Snow.reset_for_winter(1)
	var lane: Dictionary = Layout.road_segments[0]["lanes"][0]
	var region := Rect2(0, 72, 100, 22)
	var before := Snow.volume_in_rect(region)
	var lane_rect := Rect2(10, 84.0, 70, 2.5)
	var lane_before := Snow.volume_in_rect(lane_rect)
	var moved := Snow.grader_lane(lane["a"], lane["b"], lane["push"], 3.4, 0.03, 7)
	Snow.relax_until_stable()
	var after := Snow.volume_in_rect(region)
	runner.check(moved > 10.0, "Grader moved snow (%.1f m3)" % moved)
	runner.check(Snow.volume_in_rect(lane_rect) < lane_before * 0.35, "Lane mostly cleared")
	runner.near(after, before, 0.05, "Grader conserves volume (windrow)")
	var apron := Snow.depth_at(50, 88.0)
	runner.check(apron > 0.6, "Windrow dumped on the boulevard / driveway apron (%.2f m)" % apron)


func test_performance_ops() -> void:
	Snow.reset_for_winter(1)
	var p := _player_lot_point(-6.0, 6.0)
	var t := Time.get_ticks_usec()
	for k in range(100):
		Snow.scoop(p + Vector2(k * 0.02, 0), Vector2(0, 1), 0.46, 0.5, 0.04)
	var scoop_us := (Time.get_ticks_usec() - t) / 100.0
	t = Time.get_ticks_usec()
	for k in range(100):
		Snow.blade_push(p + Vector2(0, k * 0.03), Vector2(0, 1), 0.6, 0.06, 0.0)
	var push_us := (Time.get_ticks_usec() - t) / 100.0
	Snow.add_snowfall(0.01)
	t = Time.get_ticks_usec()
	Snow.sync_chunk(30)
	var sync_us := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	Snow.process_relax(48)
	var relax_us := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	Snow.sync_all()
	var all_ms := (Time.get_ticks_usec() - t) / 1000.0
	runner.info("scoop %.0f us, push step %.0f us, chunk sync %d us, relax 48 tiles %d us, sync_all %.0f ms" % [scoop_us, push_us, sync_us, relax_us, all_ms])
	runner.check(scoop_us < 3000 and push_us < 4000, "Tool ops are cheap enough for 60 FPS")
