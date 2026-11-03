extends Node
## Polish 3 §0: builds the save fixtures in tests/fixtures/polish3/ with the current build, for
## both modes, at four points of a game:
##   1_opening      first night of the opening (letter not read, everything buried)
##   2_mid_trail    Gerry's trail accepted and partly cleared
##   3_contract     tutorial done, a paid contract running
##   4_midwinter    time-jumped (as the F1 menu does) to about Jan 20 with snow on the ground
## Run: godot --headless --fixed-fps 60 --path . res://tests/make_fixtures.tscn
##
## Polish 4 §0: `-- --set=polish4` builds tests/fixtures/polish4/ instead, at six points:
##   1_opening, 2_mid_trail   as above
##   3_trail_done             Gerry's trail cleared (stage TRAIL_DONE): Gerry waits at his door
##   4_contract, 5_midwinter  as 3_contract / 4_midwinter above
##   6_storm                  partway through a scheduled storm (from the weather schedule, not the
##                            F1 override), heavy snow falling
## Options: --only=<point part>  --mode=fun|survival

var OUT := "res://tests/fixtures/polish3/"

var world: Node = null


func _ready() -> void:
	await get_tree().process_frame
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var modes := ["fun", "survival"]
	var points := ["1_opening", "2_mid_trail", "3_contract", "4_midwinter"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			modes = [a.substr(7)]
		if a == "--set=polish4":
			OUT = "res://tests/fixtures/polish4/"
			points = ["1_opening", "2_mid_trail", "3_trail_done", "4_contract", "5_midwinter", "6_storm"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for mode in modes:
		for point in points:
			if only == "" or point.contains(only):
				await _make(mode, point)
	print("FIXTURES DONE")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _make(mode: String, point: String) -> void:
	if world and is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	Game.force_input = true
	Game.new_game(mode, 2024)
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await _frames(3)
	match point:
		"1_opening":
			Clock.skip(Clock.at(0, 21.0) - Clock.minutes)
		"2_mid_trail":
			Game.flags["mail_read"] = true
			Game.set_stage(Game.Stage.LETTER_READ)
			Contracts.create_tutorial_contract(50)
			Game.set_stage(Game.Stage.NEIGHBOR_TALKED)
			# Clear the first part of the trail: the walkway end nearest the porch steps.
			var b := Boxes.get_box("gerry_trail")
			var r: Rect2 = b["rects"][0]
			Snow.set_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45)), 0.0)
			Boxes.measure(Boxes.get_box("gerry_trail"))
			Clock.skip(Clock.at(0, 13.0) - Clock.minutes)
		"3_trail_done":
			Game.flags["mail_read"] = true
			Game.set_stage(Game.Stage.LETTER_READ)
			Contracts.create_tutorial_contract(50)
			Game.set_stage(Game.Stage.NEIGHBOR_TALKED)
			for c in Contracts.active:
				if c.get("tutorial", false):
					for z in c["zones"]:
						for ra in z["rects"]:
							Snow.set_rect(Contracts.a_to_rect(ra), 0.004)
						Contracts.measure_zone(c, z)
			Clock.skip(Clock.at(0, 14.0) - Clock.minutes)
		"6_storm":
			world.debug_complete_tutorial()
			# The first scheduled storm after Jan 1, joined 40 % of the way in.
			var ev: Dictionary = {}
			for e in Weather.events:
				if Weather.tier_of(e) == "storm" and float(e["start"]) > 31 * 24:
					ev = e
					break
			var target := (float(ev["start"]) + (float(ev["end"]) - float(ev["start"])) * 0.4) * 60.0
			while Clock.minutes < target - 0.5:
				if Game.is_survival():
					Game.money = maxi(Game.money, 1500)
					for bl in Economy.unpaid_bills():
						Economy.pay_bill(int(bl["month"]))
					Survival.warmth = 100.0
				Clock.skip(minf(1440.0, target - Clock.minutes))
			print("storm fixture: event %.1f-%.1f h, %.1f cm, now %s, condition %s, %.2f cm/h" % [float(ev["start"]), float(ev["end"]), float(ev["total"]), Clock.time_string(), Weather.NAMES[Weather.condition()], Weather.snow_rate()])
		"4_contract", "3_contract":
			world.debug_complete_tutorial()
			Clock.skip(Clock.at(0, 10.0) - Clock.minutes)
			var lid := -1
			for l in Contracts.listings:
				if str(l.get("target", "")).begins_with("lot:"):
					lid = int(l["lid"])
					break
			if lid < 0 and not Contracts.listings.is_empty():
				lid = int(Contracts.listings[0]["lid"])
			if lid >= 0:
				Contracts.force_award(lid)
			Clock.skip(60.0)
		"4_midwinter", "5_midwinter":
			world.debug_complete_tutorial()
			# F1 day jumps, a day at a time. A Survival player who jumps this far would have earned
			# the money for the hydro bills and kept warm indoors; do that so the run can't freeze.
			var target := Clock.at(Clock.day_of(1, 20), 12.0)
			while Clock.minutes < target - 0.5:
				if Game.is_survival():
					Game.money = maxi(Game.money, 1500)
					for bl in Economy.unpaid_bills():
						Economy.pay_bill(int(bl["month"]))
					Survival.warmth = 100.0
				Clock.skip(minf(1440.0, target - Clock.minutes))
	await _frames(5)
	var ok := Saves.save_game()
	var src := ProjectSettings.globalize_path(Saves.path_for(mode))
	var dst := ProjectSettings.globalize_path(OUT + "%s_%s.json" % [mode, point])
	var err := DirAccess.copy_absolute(src, dst)
	print("fixture %s %s: saved=%s copy=%d  day %d %s  stage %d  contracts %d  snow %.1f m3" % [mode, point, str(ok), err,
		Clock.day_index(), Clock.time_string(), Game.stage(), Contracts.active.size(), Snow.total_volume()])

