extends Node
## Visual verification helper (Part 0.6). Launch windowed (not headless):
##   godot --path . res://tests/shot.tscn -- --scene=game --out=/tmp/a.png [options]
## Options:
##   --scene=menu|game        which scene to load
##   --mode=fun|survival      game mode for a new game
##   --hour=16.5              fixed time of day (game)
##   --day=0                  day index
##   --weather=0..5           force weather condition
##   --setup=name             staging preset (cleared_drive, light, medium, heavy, blizzard, night)
##   --cam=x,y,z --look=x,y,z free camera placement (world coords)
##   --lotcam=u,v,h,lu,lv,lh  camera in player-lot local coords (u right, v inward)
##   --tp=1                   third-person player camera
##   --player=u,v             put the player at player-lot local coords
##   --tool=id                give the player a tool
##   --frames=40              frames to wait before capture
##   --ui=computer|map|inventory|pause|debug  open a UI before capture
##   --pose=hold|scoop|push|toss --load=0..1 --toss=0..1   freeze the hands / held tool in a pose
## Polish 3 additions:
##   --house=player|neighbor  house used by --hcam / --hplayer (default player)
##   --hcam=x,y,z --hlook=x,y,z   free camera in that house's frame (HouseBuilder.lot_transform;
##                            floor at y = Layout.PORCH_H, front wall at z = setback)
##   --hplayer=x,z --hlook=x,y,z  first-person player standing in the house frame, aimed at hlook
##                            (shows the interaction prompt for what is under the crosshair)
##   --ui=tv|radio|sleep      open the TV weather, play the radio forecast, open the sleep prompt
##   --ui=overwrite           (menu) the New Game overwrite confirmation over the Play panel
##   --setup=trail|trail_done Gerry's tutorial trail accepted (stage NEIGHBOR_TALKED) / cleared
##   --gerry_walk=frames      (with --setup=trail) clear the trail after spawning so Gerry walks
##                            down it; wait this many frames first
##   --gerry_invite=frames    (with --gerry_walk) once he is by the mailbox, talk to him so he
##                            invites the player in and walks up to his door; wait this many frames
##                            (run with --fixed-fps 60 so slow software rendering doesn't skip ahead)
##   --expose_shovel=f        dig the buried small shovel out to a fraction f showing and look at
##                            it from 1.3 m (first person); --shovel_h=h sets the snow surface height
##                            directly instead (like-for-like "before" shot)
##   --snow_all=d             set the snow over the whole map to depth d (m) after spawning
## Polish 4 additions:
##   --seed=N                 weather seed for the new game (default: from the clock, as before)
##   --unlock=1               tutorial complete, computer unlocked (stage COMPLETE)
##   --storm=lead|peak [--storm_tier=storm|major]  clock set into the first scheduled event of that
##                            tier (seeds searched for a major), its first hour or its heaviest hour
##   --light=h                light the scene as at hour h (DayNight override) without moving the
##                            clock (e.g. a scheduled storm at noon and at dusk)
##   --gerry_meet=frames      (with --setup=trail --gerry_walk) wait until Gerry is down by his
##                            mailbox and put the player in front of him; --meetcam=1 frames both
##   --mailcam=player|neighbor|<lot index>  camera from the street on that lot's mailbox
##   --scoop=mid|loaded|glide a real scoop with the real controls (with --tool, --player, --pitch,
##                            --tp): captured mid-sweep, loaded and aimed up (--aim_up=deg), or a
##                            glide series (--seq, --every)
##   --photo_out=path         also save the framed photograph's texture (full size) to path
##   --seq=N --every=F        capture N frames, one every F frames, to <out>_00.png, _01.png …
##   --menu_shot=k --menu_at=f   (menu) jump the background camera to shot k (0..2), fraction f
##                            of the way along it, then wait --menu_frames (default 40)
## Polish 5 additions:
##   --ui=settings [--settings_tab=n] [--settings_scroll=px]  the settings screen as opened from
##                            the pause menu, on tab n (0 Audio … 4 Controls, the default),
##                            scrolled down px
##   --ui=photo               (§4) the framed photo by the front door, large on screen (waits for
##                            the capture first)
##   --door_line=frames       (§4) the opening: the player in the hall facing the front door opens
##                            it (Interact, real input); wait this many frames (the line waits for
##                            the morning subtitle to finish); with --hour < 8 on day 0
##   --gerry_tips=k           (§4) take Gerry's job through his dialogue ($55) standing at the foot
##                            of his walk, then move his snow tips on to line k (0-3)
##   --views="x,y,z>lx,ly,lz;…"  (§5) several free-camera views in one run (world coords, camera >
##                            look-at point), each captured to <out>_00.png, _01.png …; waits
##                            --views_frames (default 20) per view; --fov as for --cam
##   --hud=0                  (§5) hide the HUD and the rest of the game's UI layer
##   --award=n                (§5) win the first n listings on the board (as F1's "Win first
##                            listing" does), so contracts show on the map
##   --slots=a,b,c,d          (§6) the four tool slots (tool ids, empty = bare hands), e.g.
##                            --slots=small_shovel,,wide_pusher, ; --selected=n selects slot n (0-3)
##   --ui=icons               (§6) every tool's icon at the hotbar's size in its slot panel (dimmed
##                            as an empty slot in the last row), at the store's and the inventory's
##                            sizes and large; waits for the rendered set
##   --comp_scroll=px         (§6) with --ui=computer: scroll the open app down px
##   --comp_state=1           (§7) a business for the computer's apps: $3,000, three listings won
##                            (one cleared, one lost: the contract history), a store order, the
##                            month's hydro bill paid; works on older builds too
##   --company=name           (§7) the company's name before the computer opens (empty: the name
##                            form shows on Contracts / Contract board)
##   --comp_apps=all|i,j,…    (§7) with --ui=computer: open each app (index into ComputerUI.APPS of
##                            the build) and capture it to <out>_NN.png (NN = the index)
##   --comp_tab=n             (§7) the Contracts app's tab (0 Active, 1 History) when it opens
##   --tv_tier=light|storm|major [--tv_hour=h]  (§8) a morning (h, default 9) whose TV shows that
##                            strength on tomorrow's or the next day's card, with as many other
##                            strengths on the other cards as can be found (forecast systems, nothing
##                            unforecast; the same moment on any build: winters 1–5 of the seed, then
##                            the next seeds); with --ui=tv or --ui=computer (opens on Weather)
##   --showcase=x,z,yaw       (§6) every tool model in a row on the ground from world (x, z), facing
##                            yaw: the hand tools standing on their blades as if held, the blowers;
##                            use with --cam/--look or --views
##   --ff=1|2|10              (§9) choose that fast-forward speed before the frames are waited (and
##                            again just before the capture); with --weather=4 (heavy snow) 10× shows
##                            its cap
##   --board_state=1          (§10) with --ui=computer: live bidding on the board — a bid winning, a
##                            bid outbid by a rival, a parking lot locked above the tier, the first
##                            rival bids on every listing (use --tab=2 to open on the board); §10b: a
##                            street section too (with --rep=85 it shows the vehicle lock)
##   --jobs=spec,…            (§10b) win these jobs outright right after the world spawns (so their
##                            outlines are laid during --frames): lot:<index>:<box kind> (driveway,
##                            path, sidewalk), area:<id> (school_lot, store_lot, church_lot),
##                            road:<segment id>, walk:<section> (A_w … D_e; this build only); works on
##                            older builds too (there: stakes, flags and the orange line)
##   --rep=N                  (§10b) set the reputation (the tier follows) before the jobs / the board

var args := {}
var game: Node = null
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var scene: String = args.get("scene", "game")
	if scene == "menu":
		var m: Node = load("res://scenes/main_menu.tscn").instantiate()
		add_child(m)
		await _wait(int(args.get("frames", "40")))
		if args.has("menu_shot"):
			m.call("jump_to", int(args["menu_shot"]), float(args.get("menu_at", "0.5")))
			await _wait(int(args.get("menu_frames", "40")))
		if args.has("ui") and args["ui"] in ["play", "overwrite"]:
			m.call("_show_play")
			await _wait(5)
			if args["ui"] == "overwrite":
				# The overwrite warning as it appears when a save exists for the mode.
				m.call("_new_game", str(args.get("mode", "fun")), {"year": 1, "money": 1234, "time": 600.0})
				await _wait(5)
		if args.has("seq"):
			await _capture_seq()
		_capture()
		return
	Game.new_game(str(args.get("mode", "fun")), int(args.get("seed", "-1")))
	_setup_world_state()
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _wait(3)
	await _setup_after_spawn()
	await _wait(3)
	if args.has("grid"):
		await _grid()
		get_tree().quit()
		return
	await _apply_pose()
	if args.has("scoop"):
		await _scoop_shot()
		return
	if args.has("ff"):
		Clock.set_speed(int(args["ff"]))   # polish 5 §9
	if args.has("work"):
		# Keep "working" in the box while the frames go by (the outline fades when work stops).
		var bb := Boxes.get_box(Boxes.lot_box(Layout.player_lot, str(args["work"])))
		for i in range(int(args.get("frames", "40"))):
			Boxes.note_work((bb["rects"][0] as Rect2).get_center())
			await get_tree().process_frame
	else:
		await _wait(int(args.get("frames", "40")))
	if args.has("award"):
		# Polish 5 §5: contracts on the board, won outright (F1's "Win first listing").
		for k in range(int(args["award"])):
			if Contracts.listings.is_empty():
				break
			Contracts.force_award(int(Contracts.listings[0]["lid"]))
	if args.get("hud", "1") == "0":
		game.ui.visible = false
		if game.get("time_layer") != null:
			game.time_layer.visible = false   # §10b: the fast-forward control too (§9's layer)
	if args.has("ui"):
		await _open_ui(str(args["ui"]))
		await _wait(int(args.get("ui_frames", "6")))
	if args.has("ff") and Clock.speed != int(args["ff"]):
		Clock.set_speed(int(args["ff"]))
		await _wait(4)
	if args.has("comp_apps") and game.modal_kind == "computer":
		await _capture_apps(game.modal)
		get_tree().quit()
		return
	if args.has("views"):
		await _capture_views()
		get_tree().quit()
		return
	if args.has("photo_out") and game.interior.has("photo"):
		# Polish 4 §5: the photograph's own texture, saved at full size.
		var ph = game.interior["photo"]
		for i in range(240):
			if ph.captured:
				break
			await get_tree().process_frame
		var pim: Image = ph.texture.get_image()
		pim.save_png(str(args["photo_out"]))
		print("saved ", args["photo_out"], " ", pim.get_size(), " capture %d ms" % ph.capture_ms)
	if args.has("seq"):
		await _capture_seq()
	_capture()


func _wait(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _setup_world_state() -> void:
	var day := int(args.get("day", "0"))
	var hour := float(args.get("hour", "16.4"))
	Clock.reset(Clock.at(day, hour))
	var setup: String = args.get("setup", "")
	var lot := Layout.player_lot
	var hi := Layout.house_info(lot)
	match setup:
		"light":
			Snow.clear_all()
			Snow.add_layer_rect(Rect2(0, 0, Layout.MAP_W, Layout.MAP_D), 0.08)
			Snow.roof_depth = 0.12
		"medium":
			Snow.clear_all()
			Snow.add_layer_rect(Rect2(0, 0, Layout.MAP_W, Layout.MAP_D), 0.35)
			Snow.roof_depth = 0.45
		"heavy", "":
			pass
	if setup == "showroom":
		# Every vehicle and machine lined up in the store lot (model check).
		var ids := ["pickup_plow", "atv_blade", "tractor_blade", "tractor_blower", "grader", "plow_truck", "rotary_blower", "dump_truck"]
		for k in range(ids.size()):
			Game.vehicles.append({"uid": Game.uid(), "id": ids[k], "pos": Vector3(108 + k * 8.5, 0, 36), "yaw": 0.0, "snow": 0.15})
		var tids := ["small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh", "electric_shovel"]
		for k in range(tids.size()):
			Game.items.append({"uid": Game.uid(), "tool": tids[k], "pos": Vector3(115 + k * 1.6, 0, 23), "yaw": 0.0})
		for k in range(2):
			Game.machines.append({"uid": Game.uid(), "tool": ["small_blower", "large_blower"][k], "pos": Vector3(127 + k * 1.8, 0, 23.5), "yaw": 0.0})
	if setup in ["cleared_drive", "light", "medium"]:
		var drv: Rect2 = hi["driveway_private"]
		var inner := drv.grow_individual(-0.5, 0, -0.5, 0)
		var vol := Snow.volume_in_rect(inner)
		Snow.set_rect(inner, 0.0)
		# Throw it onto both sides like a player would: many shovel-sized splats, then slump.
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var n := int(vol / 0.03)
		for k in range(n):
			var side_x := drv.position.x - rng.randf_range(0.6, 2.4) if k % 2 == 0 else drv.end.x + rng.randf_range(0.6, 2.4)
			var z := rng.randf_range(drv.position.y + 3.2, drv.end.y - 0.3)
			Snow.deposit(Vector2(side_x, z), vol / n, rng.randf_range(0.3, 0.6))
		Snow.relax_until_stable()
	# --- Polish pass staging presets -------------------------------------------------
	match setup:
		"drive_done", "strokes":
			# Clear the player's driveway box like a player would: shovel-width lanes, several bites
			# per spot down to the blade's floor, snow thrown well onto the lawn on both sides. Then
			# the box rule finishes it ("drive_done") or a partly cleared drive shows its strokes.
			var dbox := Boxes.get_box(Boxes.lot_box(lot, "driveway"))
			var drv2: Rect2 = dbox["rects"][0]
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = 11
			var x := drv2.position.x + 0.23
			var lane := 0
			var stop_x := drv2.end.x if setup == "drive_done" else drv2.position.x + drv2.size.x * 0.55
			while x < stop_x:
				var z := drv2.position.y
				while z < drv2.end.y:
					for bite_i in range(6):
						var cells := Snow.cells_in_obb(Vector2(x, z), Vector2(0, 1), 0.46, 0.5)
						var bites := PackedFloat32Array()
						bites.resize(cells.size())
						bites.fill(0.25)
						var floor_d: float = [0.004, 0.009, 0.006][lane % 3]
						var got: Dictionary = Snow.cut(cells, bites, floor_d, 1.0)
						if float(got["volume"]) < 0.001:
							break
						var side_x := drv2.position.x - rng2.randf_range(1.6, 3.4) if x < drv2.get_center().x else drv2.end.x + rng2.randf_range(1.6, 3.4)
						Snow.deposit(Vector2(side_x, z + rng2.randf_range(-0.3, 0.3)), got["volume"], rng2.randf_range(0.4, 0.7))
					z += 0.45
				x += 0.42
				lane += 1
				Snow.relax_until_stable()
			if setup == "drive_done":
				Boxes.measure(dbox, true)
		"major":
			# A major event: 1.1 m on top of the opening snow (with the walkway dug out first).
			for r3 in [hi["walkway"], hi["stairs"]]:
				Snow.set_rect(r3, 0.0)
			Snow.add_snowfall(1.1)
			Snow.roof_depth = minf(Snow.roof_depth + 1.1, 2.4)
			Snow.sync_all()
		"trail_bank":
			# A tall street bank along the curb (as the grader leaves it), with a hand-dug trail.
			var front := Layout.lot_to_world(lot, Layout.gu(lot, -1.5), -1.5)
			Snow.set_rect(Rect2(front.x - 14.0, 79.0, 28.0, 8.0), 0.03)
			# The grader windrow: loose snow heaped along the curb, slumped to its angle of repose.
			var bx := front.x - 14.0
			while bx < front.x + 14.0:
				Snow.deposit(Vector2(bx, 88.6), 1.15, 1.1)
				bx += 0.5
			Snow.relax_until_stable()
			# Dig a trail through it by hand: cut a strip, toss the snow aside, let the walls slump, repeat.
			for k in range(60):
				var cells := Snow.cells_in_obb(Vector2(front.x, 86.4), Vector2(0, 1), 0.9, 4.6)
				var bites := PackedFloat32Array()
				bites.resize(cells.size())
				bites.fill(0.3)
				var got: Dictionary = Snow.cut(cells, bites, 0.02, 100.0)
				if float(got["volume"]) < 0.005:
					break
				var side := -1.0 if k % 2 == 0 else 1.0
				Snow.deposit(Vector2(front.x + side * 3.2, 90.6), got["volume"], 0.8)
				Snow.relax_until_stable()
		"lamp_bank":
			# Late winter: plow banks along the street edge built up close to the street lamps.
			Snow.add_snowfall(1.6)
			Snow.sync_all()
			var lp := Vector2(64.0, 75.5)   # the lamp at x 64 stands on the north side of Maple St
			for k in range(40):
				Snow.deposit(lp + Vector2(randf_range(-9, 9), randf_range(-1.5, 1.5)), 6.0, 2.0)
			Snow.relax_until_stable()
			Snow.set_rect(Rect2(0, 79, Layout.MAP_W, 8), 0.05)
		"mound":
			# Push a mound with flat palms along a line (real blade_push steps).
			var c0 := Layout.lot_to_world(lot, Layout.gu(lot, -3.0), 1.0)
			Snow.set_rect(Rect2(c0 - Vector2(3, 2), Vector2(6, 8)), 0.22)
			for pass_i in range(3):
				var pz := c0.y
				while pz < c0.y + 3.6:
					Snow.blade_push(Vector2(c0.x, pz), Vector2(0, 1), 0.25, 0.12, 0.006, true, 0.3)
					pz += 0.06
				Snow.relax_until_stable()
	if setup == "truck_out":
		Game.flags["truck_keys"] = true
		var drv3: Rect2 = Boxes.get_box(Boxes.lot_box(lot, "driveway"))["rects"][0]
		Snow.set_rect(drv3, 0.02)
		Snow.set_rect(Rect2(drv3.position.x - 2.0, 79.0, drv3.size.x + 4.0, 8.0), 0.03, true)
		Boxes.measure(Boxes.get_box(Boxes.lot_box(lot, "driveway")), true)
	if setup in ["trail", "trail_done"]:
		# Polish 3: Gerry's tutorial trail accepted (and, for trail_done, cleared by the box rule).
		Game.flags["mail_read"] = true
		Game.set_stage(Game.Stage.LETTER_READ)
		Contracts.create_tutorial_contract(50)
		Game.set_stage(Game.Stage.NEIGHBOR_TALKED)
		if setup == "trail_done":
			var tb := Boxes.get_box("gerry_trail")
			for r4 in tb["rects"]:
				Snow.set_rect(r4, 0.0)
			Boxes.measure(tb, true)
			for c in Contracts.active:
				if c.get("tutorial", false):
					for z in c["zones"]:
						Contracts.measure_zone(c, z)
			Game.set_stage(Game.Stage.TRAIL_DONE)
	if args.has("weather"):
		Weather.force(int(args["weather"]), 48.0)
	if args.get("unlock", "0") == "1":
		# Polish 4 §2: the tutorial done, the computer unlocked.
		Game.flags["mail_read"] = true
		Game.flags["computer_unlocked"] = true
		Game.set_stage(Game.Stage.COMPLETE)
	if args.has("comp_state"):
		_comp_state()
	if args.has("storm"):
		_storm_clock()
	if args.has("tv_tier"):
		_tv_tier_clock()
	if Game.is_survival():
		Survival.activate()


func _setup_after_spawn() -> void:
	var w = game
	var lot := Layout.player_lot
	if args.has("rep"):
		Game.reputation = clampf(float(args["rep"]), 0.0, 100.0)   # §10b (quietly: no tier notification)
		if "tier_noted" in Contracts:
			Contracts.set("tier_noted", Contracts.call("tier_index"))
	if args.has("jobs"):
		_win_jobs(str(args["jobs"]))
	if args.has("tool"):
		Game.add_tool(str(args["tool"]))
	if args.has("slots"):
		# Polish 5 §6: fill the hotbar.
		var sl := str(args["slots"]).split(",")
		for k in range(4):
			Game.slots[k] = sl[k] if k < sl.size() else ""
		Game.selected = clampi(int(args.get("selected", "0")), 0, 3)
		Game.inventory_changed.emit()
	if args.has("showcase"):
		_showcase(w)
	if args.has("player"):
		var p := str(args["player"]).split(",")
		var pp := Layout.lot_to_world(lot, Layout.gu(lot, float(p[0])), float(p[1]))
		w.player.teleport(Vector3(pp.x, Snow.surface_height(pp.x, pp.y) + 0.05, pp.y))
		if p.size() > 2:
			w.player.set_yaw(float(p[2]))
	if args.has("playerw"):
		var pw := str(args["playerw"]).split(",")
		w.player.teleport(Vector3(float(pw[0]), Snow.ground_at(float(pw[0]), float(pw[1])) + 0.05, float(pw[1])))
		if pw.size() > 2:
			w.player.set_yaw(float(pw[2]))
	if args.has("drive"):
		# Polish 2 §4: keys found, driveway dug out, in the truck and driving out to the street.
		Game.force_input = true
		var v: Vehicle = w.vehicle_nodes()[0]
		v.enter_vehicle(w.player)
		Input.action_press("veh_accelerate")
		await _wait(int(args["drive"]))
		Input.action_release("veh_accelerate")
	if args.has("light"):
		w.day_night.override_hour = float(args["light"])
	if args.get("tp", "0") == "1":
		w.player.set_third_person(true)
	if args.has("pitch"):
		w.player.pitch = deg_to_rad(float(args["pitch"]))
		w.player.head.rotation.x = w.player.pitch
	if args.has("gerry_walk"):
		# Polish 3 §4: Gerry's trail just finished — he walks down it to meet the player.
		var tb := Boxes.get_box("gerry_trail")
		if not tb.is_empty():
			for r5 in tb["rects"]:
				Snow.set_rect(r5, 0.0)
			for c in Contracts.active:
				if c.get("tutorial", false):
					for z in c["zones"]:
						Contracts.measure_zone(c, z)
		Clock.running = true
		await _wait(int(args["gerry_walk"]))
		if args.has("gerry_meet"):
			# Polish 4 §4: once he is down by his mailbox, the player walks up to him there.
			for i in range(4000):
				if w.neighbor and w.neighbor.mode == "meet":
					break
				await get_tree().process_frame
			var g: Node3D = w.neighbor
			var out := -Vector2(Layout.neighbor_lot["inward"]).normalized()
			var at := Vector2(g.global_position.x, g.global_position.z) + out * 1.8
			w.player.teleport(Vector3(at.x, Snow.ground_at(at.x, at.y) + 0.05, at.y))
			var to := Vector2(g.global_position.x, g.global_position.z) - at
			w.player.set_yaw(atan2(-to.x, -to.y))
			await _wait(int(args["gerry_meet"]))
		if args.has("gerry_invite"):
			# Talk to him by the mailbox: he invites the player in and walks back up to his door.
			for i in range(3000):
				if w.neighbor and w.neighbor.mode == "meet":
					break
				await get_tree().process_frame
			w.neighbor_dialogue(w.neighbor)
			await _wait(int(args["gerry_invite"]))
	if args.has("door_line"):
		await _door_line_shot(w)
	if args.has("gerry_tips"):
		await _gerry_tips_shot(w)
	if args.has("snow_all"):
		Snow.set_rect(Rect2(0, 0, Layout.MAP_W, Layout.MAP_D), float(args["snow_all"]))
	if args.has("expose_shovel") or args.has("shovel_h"):
		await _expose_shovel(w)
	if args.has("hplayer"):
		var L := _house_xf()
		var hp := str(args["hplayer"]).split(",")
		var at := L * Vector3(float(hp[0]), Layout.PORCH_H, float(hp[1]))
		w.player.teleport(at + Vector3(0, 0.05, 0))
		if args.has("hlook"):
			var tgt := L * _v3(args["hlook"])
			var d: Vector3 = tgt - w.player.head.global_position
			w.player.set_yaw(atan2(-d.x, -d.z))
			w.player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
			w.player.head.rotation.x = w.player.pitch
	if args.has("meetcam") and w.neighbor:
		# Beside and in front of the meeting spot, so Gerry and the player are both in view.
		var gp := Vector2(w.neighbor.global_position.x, w.neighbor.global_position.z)
		var out2 := -Vector2(Layout.neighbor_lot["inward"]).normalized()
		var side := Vector2(out2.y, -out2.x)
		var c3 := gp + out2 * 5.0 + side * 3.2
		args["cam"] = "%f,2.2,%f" % [c3.x, c3.y]
		args["look"] = "%f,0.9,%f" % [gp.x + out2.x * 0.9, gp.y + out2.y * 0.9]
	if args.has("mailcam"):
		# --mailcam=player|neighbor|<lot index>: the mailbox at the foot of that lot, from the street.
		var ml: Dictionary = Layout.player_lot if args["mailcam"] == "player" else (Layout.neighbor_lot if args["mailcam"] == "neighbor" else Layout.lots[int(args["mailcam"])])
		var mb: Vector2 = Layout.house_info(ml)["mailbox"]
		var inw := Vector2(ml["inward"]).normalized()
		var sd := Vector2(inw.y, -inw.x)
		var c4 := mb - inw * 7.5 + sd * 4.0
		args["cam"] = "%f,3.0,%f" % [c4.x, c4.y]
		args["look"] = "%f,0.7,%f" % [mb.x + inw.x * 2.0, mb.y + inw.y * 2.0]
	if args.has("cam") or args.has("lotcam") or args.has("hcam"):
		_cam = Camera3D.new()
		_cam.fov = float(args.get("fov", "62"))
		_cam.far = 500.0
		add_child(_cam)
		var cpos := Vector3.ZERO
		var look := Vector3.ZERO
		if args.has("lotcam"):
			var q := str(args["lotcam"]).split(",")
			var c2 := Layout.lot_to_world(lot, Layout.gu(lot, float(q[0])), float(q[1]))
			var l2 := Layout.lot_to_world(lot, Layout.gu(lot, float(q[3])), float(q[4]))
			cpos = Vector3(c2.x, float(q[2]), c2.y)
			look = Vector3(l2.x, float(q[5]), l2.y)
		elif args.has("hcam"):
			var L2 := _house_xf()
			cpos = L2 * _v3(args["hcam"])
			look = L2 * _v3(args.get("hlook", "0,1,0"))
			_cam.near = 0.03
		else:
			cpos = _v3(args["cam"])
			look = _v3(args.get("look", "96,0,112"))
		_cam.global_position = cpos
		_cam.look_at(look)
		_cam.current = true
		w.snow_renderer.build_all(cpos)


## --pose=hold|scoop|push|toss [--load=0.5] [--toss=0.5]: freeze the hands / tool in a pose.
func _apply_pose() -> void:
	if not args.has("pose") and not args.has("load"):
		return
	var tc: ToolController = game.player.tools
	tc.pose_override = str(args.get("pose", "hold"))
	tc.toss_override = float(args.get("toss", "0.5"))
	tc.load = tc._capacity() * float(args.get("load", "0"))
	if args.has("work"):
		# Polish 2 §3: pretend the player just scooped from this box so its outline shows.
		var bid := Boxes.lot_box(Layout.player_lot, str(args["work"]))
		var bb := Boxes.get_box(bid)
		if not bb.is_empty():
			Boxes.note_work((bb["rects"][0] as Rect2).get_center())
	if args.has("marker"):
		# Show the throw landing marker for the current aim (amber when it lands back in the box).
		for i in range(3):
			await get_tree().physics_frame
			tc.landing = tc._landing(tc._throw_dist() * tc._pitch_factor(), tc.data.throw_angle_deg)
			tc._show_indicator(tc.landing)
	if tc.pose_override == "toss" and tc.load > 0.0:
		# Mid-throw: let the snow go (it flies for a few frames; use a small --frames).
		tc._release_throw()


func _open_ui(which: String) -> void:
	var w = game
	match which:
		"computer":
			Game.flags["computer_unlocked"] = true
			if args.has("company"):
				Game.set("company_name", str(args["company"]))   # §7 (no such state on older builds)
			if args.has("board_state"):
				_board_state()
			w.open_computer()
			if args.has("tab"):
				var c = w.modal
				c.call("_open_app", int(args["tab"]))
				if args.has("comp_tab") and c.has_method("show_contracts_tab"):
					c.call("show_contracts_tab", int(args["comp_tab"]))
			if args.has("comp_scroll"):
				for i in range(4):
					await get_tree().process_frame
				(w.modal as ComputerUI).scroll.scroll_vertical = int(args["comp_scroll"])
			await _wait_icons()
		"map":
			var m := MapUI.new()
			w.ui.add_child(m)
			w.open_modal(m, "map")
		"inventory":
			w.inventory_panel = Panels.inventory(w.hud)
		"pause":
			w._open_pause()
		"debug":
			var d := DebugMenu.new()
			d.world = w
			w.ui.add_child(d)
			w.open_modal(d, "debug")
		"letter":
			w.open_mailbox()
		"tv":
			w.open_tv()
		"radio":
			w.radio_forecast()
		"sleep":
			w.open_sleep()
		"icons":
			await _icons_sheet(w)
		"photo":
			var ph = w.interior.get("photo")
			for i in range(240):
				if ph == null or ph.captured or DisplayServer.get_name() == "headless":
					break
				await get_tree().process_frame
			w.open_photo()
		"settings":
			w._open_pause()
			var sm := SettingsMenu.new()
			w.ui.add_child(sm)
			sm.tabs.current_tab = int(args.get("settings_tab", "4"))
			if args.has("settings_scroll"):
				_scroll_settings(sm, int(args["settings_scroll"]))


## --settings_scroll: once the page is laid out, scroll the open settings tab down.
func _scroll_settings(sm: SettingsMenu, px: int) -> void:
	for i in range(3):
		await get_tree().process_frame
	var sc := sm.tabs.get_current_tab_control() as ScrollContainer
	if sc:
		sc.scroll_vertical = px


## --ui=icons (polish 5 §6): every icon of the set in the hotbar's slot panel at its size (70 px),
## the last row dimmed as an empty slot is; then at the store's (72), the inventory's (48) and a large
## size, on the computer's dark page colour.
func _icons_sheet(w: Node) -> void:
	var root := Control.new()
	root.theme = UIKit.theme()
	UIKit.full_rect(root)
	w.ui.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.19)
	UIKit.full_rect(bg)
	root.add_child(bg)
	var v := UIKit.vbox(16)
	v.position = Vector2(40, 30)
	root.add_child(v)
	var list := _icon_ids()
	for dim in [false, true]:
		var row := UIKit.hbox(10)
		v.add_child(row)
		for id in list:
			var p := UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.65), 10, 2, Color(1, 1, 1, 0.12), 6))
			p.custom_minimum_size = Vector2(98, 86)
			row.add_child(p)
			var ov := Control.new()
			p.add_child(ov)
			var ic := Icons.tool(id, 70)
			ic.position = Vector2(8, 2)
			ov.add_child(ic)
			if dim:
				ic.modulate.a = 0.35 if id == "" else 1.0
	for px in [72, 48, 128]:
		var row2 := UIKit.hbox(14)
		v.add_child(row2)
		for id in list:
			var c := UIKit.card()
			row2.add_child(c)
			c.add_child(Icons.tool(id, px))
	var names := UIKit.label("  ".join(list.map(func(x): return "hands" if x == "" else x)), 16, UIKit.MUTED)
	v.add_child(names)
	await _wait_icons()


## The rendered icon set's script (polish 5 §6), looked up at run time so this helper also runs on
## builds from before it (the "before" shots), where it is null.
func _icon_script() -> Script:
	var p := "res://scripts/ui/tool_icons.gd"
	return load(p) if ResourceLoader.exists(p) else null


func _icon_ids() -> Array:
	var ti := _icon_script()
	if ti:
		return ti.call("ids")
	var out := [""]
	for id in Catalog.TOOL_IDS:
		if id != &"hands":
			out.append(String(id))
	return out


## Wait (a few seconds at most) for the rendered tool icons.
func _wait_icons() -> void:
	var ti := _icon_script()
	if ti == null:
		return
	ti.call("request")
	for i in range(600):
		if ti.get("state") != "rendering":
			break
		await get_tree().process_frame
	print("tool icons: %s, %d ms (stage %d ms, read back and cut %d ms), %d frames drawn, image %s" % [ti.get("state"), ti.get("render_ms"), ti.get("build_ms"), ti.get("cut_ms"), ti.get("render_frames"), ti.get("image_px")])
	await _wait(3)


## --comp_state=1 (polish 5 §7): a business for the computer's apps, made with the game's own calls
## (they exist on older builds too): money, three listings won (the first cleared by the box rule,
## the second lost), a store order, the month's hydro bill paid.
func _comp_state() -> void:
	Game.money = 3000
	var won := []
	for k in range(3):
		if Contracts.listings.is_empty():
			break
		won.append(Contracts.force_award(int(Contracts.listings[0]["lid"])))
	if won.size() > 0:
		for z in won[0]["zones"]:
			for id in z["boxes"]:
				var bx := Boxes.get_box(id)
				for r in bx["rects"]:
					Snow.set_rect(r, 0.0)
				Boxes.measure(bx, true)
	if won.size() > 1:
		Contracts._lose(won[1])
	Economy.buy("standard_shovel")
	for bl in Economy.bills.duplicate():
		Economy.pay_bill(int(bl["month"]))


## --board_state=1 (polish 5 §10): live bidding on the board, made with the game's own calls — every
## listing's first rival bid in, a parking lot (locked below Commercial), your bid winning on one
## residential listing and outbid on another.
func _board_state() -> void:
	if not Contracts.has_method("bid_status"):
		return
	Contracts.on_advance(0.0)   # the board posted for the time the clock was set to
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	if not Contracts.listings.any(func(l): return str(l.get("tier", "")) == "commercial"):
		Contracts._add_area_listing(Layout.big_areas[2], Clock.day_index(), rng)
	if not Contracts.listings.any(func(l): return str(l.get("target", "")).begins_with("road:")):
		# §10b: a street section too (locked by reputation, or at the City tier without a plow or a
		# blower vehicle).
		Contracts._add_municipal_listing(Layout.road_segments[1], Clock.day_index(), rng)
	for l in Contracts.listings:
		if not (l["rivals"] as Array).is_empty():
			Contracts._rival_bid(l, 0, int(l["rivals"][0]["open"]), Clock.minutes)
	var res: Array = Contracts.listings.filter(func(l): return str(l.get("tier", "")) == "residential")
	if res.size() > 0:
		var low := int(Contracts.bid_status(res[0])["lowest"])
		Contracts.place_bid(int(res[0]["lid"]), maxi(low - 2, Contracts.bid_floor(res[0])) if low > 0 else int(res[0]["budget"]))
	if res.size() > 1:
		Contracts.place_bid(int(res[1]["lid"]), int(res[1]["budget"]) + 6)
		Contracts._rival_bid(res[1], 0, int(res[1]["budget"]) - 2, Clock.minutes)
	Notify.clear()


## --jobs=spec,… (polish 5 §10b): win these jobs outright, made with the game's own calls (the same on
## older builds: a lot's listing is made, then given the one box asked for).
func _win_jobs(spec: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 10
	var day := Clock.day_index()
	for item in spec.split(","):
		var p := item.split(":")
		var n0 := Contracts.listings.size()
		match p[0]:
			"lot":
				var lt: Dictionary = Layout.lots[int(p[1])]
				Contracts.call("_add_lot_listing", lt, day, rng)
				if Contracts.listings.size() > n0:
					var kind := p[2] if p.size() > 2 else "driveway"
					var l0: Dictionary = Contracts.listings[-1]
					l0["zones"] = [Contracts._zone({"driveway": "Driveway", "path": "Path to the house", "sidewalk": "Sidewalk"}.get(kind, kind), [Boxes.lot_box(lt, kind)])]
					l0["type"] = "one_time"
					l0["job"] = kind
			"area":
				for a in Layout.big_areas:
					if str(a["id"]) == p[1]:
						Contracts.call("_add_area_listing", a, day, rng)
			"road":
				for seg in Layout.road_segments:
					if str(seg["id"]) == p[1]:
						Contracts.call("_add_municipal_listing", seg, day, rng)
			"walk":
				if Contracts.has_method("_add_walk_listing"):
					Contracts.call("_add_walk_listing", p[1], day, rng)
		if Contracts.listings.size() > n0:
			Contracts.force_award(int(Contracts.listings[-1]["lid"]))
	Notify.clear()


## --comp_apps=all|i,j,… (polish 5 §7): each app of the open computer, captured to <out>_NN.png.
func _capture_apps(c: Node) -> void:
	var names: Array = ComputerUI.APPS
	var want: Array = []
	if str(args["comp_apps"]) == "all":
		want = range(names.size())
	else:
		for s in str(args["comp_apps"]).split(","):
			want.append(int(s))
	var out: String = args.get("out", "user://shot.png")
	for i in want:
		c.call("_open_app", i)
		if args.has("comp_tab") and c.has_method("show_contracts_tab") and c.get("current") == c.call("app_index", "contracts"):
			c.call("show_contracts_tab", int(args["comp_tab"]))
		await _wait(int(args.get("ui_frames", "6")))
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := out.get_basename() + "_%02d.png" % i
		img.save_png(p)
		print("saved ", p, " ", img.get_size(), " app ", names[i])


## --showcase=x,z,yaw (polish 5 §6): every tool's model in a row on the ground.
func _showcase(w: Node) -> void:
	var p := str(args["showcase"]).split(",")
	var at := Vector3(float(p[0]), 0, float(p[1]))
	var yaw := float(p[2]) if p.size() > 2 else 0.0
	var b := Basis(Vector3.UP, yaw)
	var x := 0.0
	for id in ["small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh", "electric_shovel", "small_blower", "large_blower"]:
		var t: ToolData = Catalog.tool(StringName(id))
		var mi := MeshInstance3D.new()
		mi.mesh = ToolModels.mesh_for(id)
		w.add_child(mi)
		var half := maxf(t.width, 0.35) * 0.5 + 0.25
		x += half
		var base := at + b * Vector3(x, 0, 0)
		base.y = Snow.surface_height(base.x, base.z)
		if t.kind == ToolData.Kind.WALK_BLOWER:
			mi.global_transform = Transform3D(b, base)
			if (ToolModels as Script).get_script_method_list().any(func(md): return md["name"] == "chute_mesh"):
				var ch := MeshInstance3D.new()
				ch.mesh = (ToolModels as Script).call("chute_mesh", id)
				mi.add_child(ch)
				ch.position = Vector3(0, 0.62, -0.25)   # WalkBehind's chute pivot
				ch.rotation.y = -deg_to_rad(30.0)
		else:
			# Standing on its blade as if held: the tip at the ground, the grip up behind.
			var tp := ToolModels.tip(id)
			mi.global_transform = Transform3D(b, base - b * tp + Vector3(0, 0.02, 0))
		x += half


## --views="x,y,z>lx,ly,lz;…" (polish 5 §5): one free camera moved through several views, each
## captured to <out>_NN.png after --views_frames frames (the snow chunks around it built first).
func _capture_views() -> void:
	var cam := Camera3D.new()
	cam.fov = float(args.get("fov", "62"))
	cam.far = 500.0
	add_child(cam)
	cam.current = true
	var out: String = args.get("out", "user://shot.png")
	var views := str(args["views"]).split(";", false)
	for k in range(views.size()):
		var pair := views[k].split(">")
		var cpos := _v3(pair[0])
		cam.global_position = cpos
		cam.look_at(_v3(pair[1]))
		game.snow_renderer.build_all(cpos)
		await _wait(int(args.get("views_frames", "20")))
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := out.get_basename() + "_%02d.png" % k
		img.save_png(p)
		print("saved ", p, " ", img.get_size())


## --seq=N --every=F: a short series of frames (menu camera path, Gerry walking…).
func _capture_seq() -> void:
	var n := int(args.get("seq", "4"))
	var every := int(args.get("every", "30"))
	var out: String = args.get("out", "user://shot.png")
	for k in range(n):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := out.get_basename() + "_%02d.png" % k
		img.save_png(p)
		print("saved ", p, " ", img.get_size())
		if k < n - 1:
			await _wait(every)


## --expose_shovel=f: dig the buried small shovel out until a fraction f of it shows (snow surface
## around it set between its sample points), or --shovel_h=h: snow surface at height h (for a
## like-for-like "before" shot); then stand 1.3 m away in first person, looking at it.
func _expose_shovel(w: Node) -> void:
	var it: Node3D = null
	for c in w.objects.get_children():
		if c.get("tool_id") == "small_shovel":
			it = c
	if it == null:
		return
	var pts: Array = []
	if it.has_method("sample_points"):
		pts = it.sample_points()
	else:
		pts = [it.global_position + Vector3(0, 0.05, 0)]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var mid := Vector3.ZERO
	var hs := []
	for p in pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
		mid += p
		hs.append(p.y)
	mid /= float(pts.size())
	hs.sort()
	var h := 0.0
	if args.has("shovel_h"):
		h = float(args["shovel_h"])
	else:
		var n := hs.size()
		var covered := n - int(round(float(args["expose_shovel"]) * n))
		h = (float(hs[maxi(covered - 1, 0)]) + float(hs[mini(covered, n - 1)])) * 0.5 + 0.02
	var r := Rect2(lo, hi - lo).grow(0.6)
	if not it.has_method("sample_points"):
		r = Rect2(Vector2(it.global_position.x, it.global_position.z) - Vector2(1.2, 1.2), Vector2(2.4, 2.4))
	var g := Snow.ground_at(r.get_center().x, r.get_center().y)
	Snow.set_rect(r, maxf(h - g, 0.0))
	print("shovel snow surface h=%.3f" % h)
	if it.has_method("exposure"):
		print("shovel exposure %.2f" % it.exposure())
	var away := Vector2(1.3, 0).rotated(it.rotation.y + 0.9)
	var stand := Vector2(mid.x, mid.z) + away
	w.player.teleport(Vector3(stand.x, Snow.ground_at(stand.x, stand.y) + 0.05, stand.y))
	var d := Vector2(mid.x, mid.z) - stand
	w.player.set_yaw(atan2(-d.x, -d.y))
	await _wait(2)
	var aim := Vector3(mid.x, Snow.surface_height(mid.x, mid.z), mid.z)
	var e: Vector3 = w.player.head.global_position
	w.player.pitch = -atan2(e.y - aim.y, Vector2(aim.x - e.x, aim.z - e.z).length())
	w.player.head.rotation.x = w.player.pitch
	await _wait(4)


## --storm=lead|peak [--storm_tier=storm|major]: set the clock into the first scheduled event of
## that tier (a seed with a major event is searched for if this one has none), in its first hour
## (lead) or its heaviest hour (peak). Lighting stays at --light (default: the event's own hour).
func _storm_clock() -> void:
	var tier: String = args.get("storm_tier", "storm")
	var found: Dictionary = {}
	for k in range(60):
		for e in Weather.events:
			if Weather.tier_of(e) == tier and float(e["start"]) > 30.0:
				found = e
				break
		if not found.is_empty():
			break
		Game.weather_seed += 1
		Weather.generate(Game.year, Game.weather_seed + Game.year * 13)
	if found.is_empty():
		return
	var st: float = found["start"]
	var t := st + 0.5
	if args["storm"] == "peak":
		var best := -1.0
		for h in range(int(st), int(ceil(float(found["end"])))):
			if Weather.rate[h] > best:
				best = Weather.rate[h]
				t = h + 0.5
	Clock.reset(t * 60.0)
	print("storm shot: %s %.1f-%.1f h (%.0f cm), at %.1f h: %s, %.2f cm/h" % [tier, st, float(found["end"]), float(found["total"]), t, Weather.NAMES[Weather.condition()], Weather.snow_rate()])


## --tv_tier=light|storm|major [--tv_hour=h]: (§8) the clock at h (default 9:00) on a day whose TV
## shows that strength on one of its three cards, with as many other strengths on the others as can
## be found: forecast systems dropping at least 1 cm on each day, nothing unforecast on them — read
## from the schedule, so any build picks the same moment. Winters 1–5 of the seed are searched,
## then the next seeds.
func _tv_tier_clock() -> void:
	var hr := float(args.get("tv_hour", "9"))
	var rank := {"light": 1, "storm": 2, "major": 3}
	var want: int = rank.get(str(args["tv_tier"]), 2)
	var pick := []
	var pick_n := 0
	for k in range(20):
		for y in range(1, 6):
			Weather.generate(y, Game.weather_seed + y * 13)
			var best := []
			var odd := []
			for d in range(121):
				best.append(0)
				odd.append(false)
			for ev in Weather.events:
				var per := {}
				for hv in (ev["hours"] as Dictionary).keys():
					var d0 := int(floor(int(hv) / 24.0))
					per[d0] = float(per.get(d0, 0.0)) + float(ev["hours"][hv])
				for d1 in per.keys():
					if ev["surprise"]:
						odd[d1] = true
					elif float(per[d1]) >= 1.0:
						best[d1] = maxi(best[d1], rank[Weather.tier_of(ev)])
			for d in range(3, 118):
				if odd[d] or odd[d + 1] or odd[d + 2] or not (best[d + 1] == want or best[d + 2] == want):
					continue
				var seen := {}
				for j in range(3):
					if best[d + j] > 0:
						seen[best[d + j]] = true
				if seen.size() > pick_n:
					pick_n = seen.size()
					pick = [Game.weather_seed, y, d, [best[d], best[d + 1], best[d + 2]]]
		if pick_n >= 3 or (pick_n >= 2 and k >= 4):
			break
		Game.weather_seed += 1
	if pick.is_empty():
		return
	Game.weather_seed = int(pick[0])
	Game.year = int(pick[1])
	Weather.generate(Game.year, Game.weather_seed + Game.year * 13)
	Clock.reset(Clock.at(int(pick[2]), hr))
	print("tv_tier shot: seed %d, winter %d, %s %.1f h: %s" % [Game.weather_seed, Game.year, Clock.date_string(int(pick[2]), true), hr, str(pick[3])])


## --scoop=mid|loaded|glide [--tool=id] [--player=u,v,yaw] [--pitch=deg] [--tp=1]: a real scoop
## with the real controls, captured mid-sweep (mid), loaded and looking up to throw (loaded), or as
## a series while the aim comes up from the snow (glide, --seq/--every).
func _scoop_shot() -> void:
	Game.force_input = true
	var pl = game.player
	if args.has("tool"):
		var i: int = Game.slots.find(str(args["tool"]))
		if i >= 0:
			Game.select_slot(i)
	# Let the opening fade-in finish first (--frames, as for the other shots).
	await _wait(maxi(int(args.get("frames", "40")), 3))
	var base: float = pl.yaw
	Input.action_press("primary")
	var sweep := 14 if args["scoop"] == "mid" else 30
	for k in range(sweep):
		pl.set_yaw(base + 0.3 * sin(k * 0.2))
		await get_tree().physics_frame
	if args["scoop"] == "mid":
		await _capture_now()
		Input.action_release("primary")
		return
	pl.set_yaw(base + 0.35)
	var up := deg_to_rad(float(args.get("aim_up", "8")))
	if args["scoop"] == "glide":
		var out: String = args.get("out", "user://shot.png")
		var n := int(args.get("seq", "5"))
		for k in range(n):
			pl.pitch = lerpf(pl.pitch, up, 0.5)
			pl.head.rotation.x = pl.pitch
			await _wait(int(args.get("every", "4")))
			await _capture_now(out.get_basename() + "_%02d.png" % k)
		Input.action_release("primary")
		get_tree().quit()
		return
	pl.pitch = up
	pl.head.rotation.x = pl.pitch
	await _wait(int(args.get("frames_loaded", "30")))
	await _capture_now()
	Input.action_release("primary")


func _capture_now(path := "") -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p: String = path if path != "" else str(args.get("out", "user://shot.png"))
	img.save_png(p)
	print("saved ", p, " ", img.get_size())
	if path == "":
		get_tree().quit()


func _house_xf() -> Transform3D:
	var lot: Dictionary = Layout.neighbor_lot if args.get("house", "player") == "neighbor" else Layout.player_lot
	return HouseBuilder.lot_transform(lot)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out: String = args.get("out", "user://shot.png")
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	get_tree().quit()


## Grip check (polish 2 §1): every tool in every pose, first and third person, at several look
## angles, in one run. Third person uses a side camera so both hands on the shaft are visible.
func _grid() -> void:
	var dir: String = args["grid"]
	DirAccess.make_dir_recursive_absolute(dir)
	var tools := str(args.get("tools", "hands,small_shovel,standard_shovel,wide_pusher,snow_scraper,large_scraper,snow_sleigh,electric_shovel")).split(",")
	var poses := str(args.get("poses", "idle,scoop,hold,toss,push")).split(",")
	var views := str(args.get("views", "fp,tp")).split(",")
	var pitches := str(args.get("pitches", "-45,0")).split(",")
	var pl = game.player
	var tc: ToolController = pl.tools
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 300.0
	add_child(cam)
	for tool in tools:
		Game.slots[Game.selected] = "" if tool == "hands" else tool
		Game.inventory_changed.emit()
		await _wait(4)
		for view in views:
			pl.set_third_person(view == "tp")
			for pitch in pitches:
				pl.pitch = deg_to_rad(float(pitch))
				pl.head.rotation.x = pl.pitch
				for pose in poses:
					tc.pose_override = pose
					tc.toss_override = 0.55
					tc.load = tc._capacity() * (0.8 if pose in ["hold", "toss"] else (0.4 if pose == "scoop" else 0.0))
					if view == "tp":
						var p: Vector3 = pl.global_position
						var f := Vector3(pl.forward2().x, 0, pl.forward2().y)
						var r := f.cross(Vector3.UP)
						cam.global_position = p + r * 2.4 + f * 0.9 + Vector3(0, 1.25, 0)
						cam.look_at(p + f * 0.55 + Vector3(0, 0.75, 0))
						cam.current = true
					else:
						cam.current = false
						pl.fp_cam.current = true
					await _wait(int(args.get("frames", "12")))
					await RenderingServer.frame_post_draw
					var img := get_viewport().get_texture().get_image()
					var out := "%s/%s_%s_%s_%s.png" % [dir, tool, pose, view, str(pitch).replace("-", "m")]
					img.save_png(out)
					print("saved ", out)
	tc.pose_override = ""


## --door_line=frames (polish 5 §4): stand in the hall facing the front door, open it with
## Interact, and wait while the thought comes up on the HUD.
func _door_line_shot(w: Node) -> void:
	Game.force_input = true
	var L := HouseBuilder.lot_transform(Layout.player_lot)
	var sb: float = Layout.player_lot["setback"]
	var at := L * Vector3(-1.5, Layout.PORCH_H, sb + 1.6)
	w.player.teleport(at + Vector3(0, 0.05, 0))
	var door: Vector3 = L * Vector3(-1.5, Layout.PORCH_H + 1.2, sb)
	var d: Vector3 = door - (at + Vector3(0, 1.6, 0))
	w.player.set_yaw(atan2(-d.x, -d.z))
	w.player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	w.player.head.rotation.x = w.player.pitch
	Clock.running = true
	await _wait(4)
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(2)
	var up := InputEventAction.new()
	up.action = "interact"
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(int(args["door_line"]))
	print("door open %s, speech: %s" % [w.player_door.open, w.hud.speech_text.text])


## --gerry_tips=k (polish 5 §4): Gerry's job agreed through his dialogue, then his snow tips on the
## HUD moved on to line k, the player at the foot of his walk looking up at him.
func _gerry_tips_shot(w: Node) -> void:
	await _wait(150)      # past the fade-in and the start-up controls reminder
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.LETTER_READ)
	var g: Node3D = w.neighbor
	var out := -Vector2(Layout.neighbor_lot["inward"]).normalized()
	var at := Vector2(g.global_position.x, g.global_position.z) + out * 3.2
	w.player.teleport(Vector3(at.x, Snow.surface_height(at.x, at.y) + 0.05, at.y))
	var to := Vector2(g.global_position.x, g.global_position.z) - at
	w.player.set_yaw(atan2(-to.x, -to.y))
	w.neighbor_dialogue(g)
	await _wait(2)
	for i in range(30):
		if w.modal == null:
			break
		var pressed := false
		for b in w.modal.find_children("*", "Button", true, false):
			if (b as Button).text.contains("$55") or (b as Button).text.contains("Continue"):
				(b as Button).pressed.emit()
				pressed = true
				break
		if not pressed:
			break
		await _wait(2)
	for k in range(int(args["gerry_tips"])):
		w._talk_next()
	await _wait(3)
	print("stage %d, speech: %s" % [Game.stage(), w.hud.speech_text.text])

