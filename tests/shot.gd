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
	if args.has("work"):
		# Keep "working" in the box while the frames go by (the outline fades when work stops).
		var bb := Boxes.get_box(Boxes.lot_box(Layout.player_lot, str(args["work"])))
		for i in range(int(args.get("frames", "40"))):
			Boxes.note_work((bb["rects"][0] as Rect2).get_center())
			await get_tree().process_frame
	else:
		await _wait(int(args.get("frames", "40")))
	if args.has("ui"):
		_open_ui(str(args["ui"]))
		await _wait(int(args.get("ui_frames", "6")))
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
	if args.has("storm"):
		_storm_clock()
	if Game.is_survival():
		Survival.activate()


func _setup_after_spawn() -> void:
	var w = game
	var lot := Layout.player_lot
	if args.has("tool"):
		Game.add_tool(str(args["tool"]))
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
			w.open_computer()
			if args.has("tab"):
				var c = w.modal
				c.call("_open_app", int(args["tab"]))
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
