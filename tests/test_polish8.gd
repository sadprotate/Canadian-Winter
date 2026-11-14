extends RefCounted
## Polish pass 8 tests. Same harness as test_polish7.gd (the runner calls every test_* method;
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


## A new game (seed 2024) on Dec 2 at `hour`, the tutorial done, the keys found, the clock
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
	await _faded_in()


## The game's fade-in done (hints and the speed control wait for it).
func _faded_in() -> void:
	for k in range(150):
		if world.fade.color.a <= 0.05:
			break
		await _tree().process_frame


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


## Press and release a key as a keyboard sends it.
func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await _frames(2)
	await _frames(2)


func _bound(action: String) -> Key:
	var e := Settings.decode(String(Settings.bindings[action][0]))
	return (e as InputEventKey).physical_keycode


## A left click at a control's centre (canvas coordinates → the window's).
func _click(c: Control) -> void:
	var at: Vector2 = _tree().root.get_final_transform() * (c.get_global_transform_with_canvas() * (c.size * 0.5))
	for down in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = down
		m.position = at
		m.global_position = at
		Input.parse_input_event(m)
		await _frames(2)
	await _frames(2)


## The settings file as it is (or null), to put back after a test that writes it.
func _backup() -> Variant:
	if not FileAccess.file_exists(Settings.PATH):
		return null
	return FileAccess.get_file_as_bytes(Settings.PATH)


func _restore(saved: Variant) -> void:
	if saved == null:
		if FileAccess.file_exists(Settings.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()
	Settings.load_controls()


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


func _stand(at: Vector3, look: Vector3) -> void:
	var pl: Player = world.player
	pl.teleport(at + Vector3(0, 0.05, 0))
	var d := Vector2(look.x - at.x, look.z - at.z)
	pl.set_yaw(atan2(-d.x, -d.y))
	var eye_y := at.y + Player.HEAD_H
	pl.pitch = atan2(look.y - eye_y, d.length())
	pl.head.rotation.x = pl.pitch


# =============================================================================
# §17 The hint panel
# =============================================================================

func _hp():
	return world.hint_panel


## A hint with several pages, up on the panel (Gerry's, asked for again).
func _s17_open_gerry() -> void:
	world.show_hint("gerry_snow", true)
	await _frames(2)


## Back, Next and OK with the default keys, with rebound keys and by clicking (the cursor free
## over the letter); Back off on the first page; Next is OK on the last; OK closes from any page.
func test_s17_buttons() -> void:
	var saved: Variant = _backup()
	Settings.restore_default_controls()
	await _world()
	var hp = _hp()
	await _s17_open_gerry()
	runner.check(hp.is_open("gerry_snow") and hp.page == 0 and hp.back_b.disabled and hp.next_b.text.ends_with("Next"), "§17 a hint opens on its first page, Back off (%s / %s)" % [hp.back_b.text, hp.next_b.text])
	await _key(KEY_RIGHT)
	var p1: int = hp.page
	await _key(KEY_RIGHT)
	var p2: int = hp.page
	var last_ok: bool = hp.next_b.text.ends_with("OK") and not hp.back_b.disabled
	await _key(KEY_LEFT)
	var p3: int = hp.page
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	var p4: int = hp.page
	runner.check(p1 == 1 and p2 == 2 and last_ok and p3 == 1 and p4 == 0, "§17 the default keys: Right → page %d, %d (Next reads OK: %s), Left → %d, Left on the first page stays %d" % [p1 + 1, p2 + 1, last_ok, p3 + 1, p4 + 1])
	await _key(KEY_X)
	runner.check(not hp.is_open() and hp.current.is_empty(), "§17 X (OK) closes it from the first page")
	await _s17_open_gerry()
	for i in range(3):
		await _key(KEY_RIGHT)
	runner.check(not hp.is_open(), "§17 Next on the last page closes it (OK)")
	# Rebound: the new keys work, the old ones do nothing, the buttons show the new keys.
	var codes := {"hint_back": KEY_COMMA, "hint_next": KEY_PERIOD, "hint_ok": KEY_SLASH}
	var refused := []
	for a in codes.keys():
		var e := InputEventKey.new()
		e.physical_keycode = codes[a]
		var c := Settings.rebind(a, e)
		if c != "":
			refused.append("%s: %s" % [a, c])
	await _s17_open_gerry()
	await _key(KEY_RIGHT)
	var old_next: bool = hp.page == 0
	await _key(KEY_PERIOD)
	var new_next: bool = hp.page == 1
	await _key(KEY_LEFT)
	var old_back: bool = hp.page == 1
	await _key(KEY_COMMA)
	var new_back: bool = hp.page == 0
	var shows: bool = hp.next_b.text.contains("[%s]" % OS.get_keycode_string(KEY_PERIOD)) and hp.ok_l.text.contains(OS.get_keycode_string(KEY_SLASH))
	await _key(KEY_X)
	var old_ok: bool = hp.is_open()
	await _key(KEY_SLASH)
	var new_ok: bool = not hp.is_open()
	runner.check(refused.is_empty() and old_next and new_next and old_back and new_back and old_ok and new_ok and shows,
		"§17 rebound to , . /: they work, the arrows and X do nothing, the panel shows the new keys %s" % str(refused))
	Settings.restore_default_controls()
	# Clicks, with the cursor free (the letter open: the hint stays up over it).
	var letter := Panels.letter(world.hud, "Test", "A letter.", func(): world.close_modal())
	world.open_modal(letter, "letter")
	await _s17_open_gerry()
	var up_over: bool = hp.is_open() and not Game.input_captured()
	await _click(hp.next_b)
	var c1: int = hp.page
	await _click(hp.back_b)
	var c2: int = hp.page
	await _click(hp.next_b)
	await _click(hp.next_b)
	await _click(hp.next_b)
	var closed: bool = not hp.is_open()
	runner.check(up_over and c1 == 1 and c2 == 0 and closed and world.modal_kind == "letter", "§17 the cursor free over the letter: click Next → page %d, Back → page %d, Next ×3 closes it (%s); the letter stays open" % [c1 + 1, c2 + 1, closed])
	world.close_modal()
	_restore(saved)
	await _unload()


## A hint never freezes anything: the player walks and scoops while it's up, and the clock runs.
func test_s17_never_frozen() -> void:
	await _world()
	var hp = _hp()
	var pl: Player = world.player
	var lot := Layout.player_lot
	var spot := Layout.lot_to_world(lot, Layout.gu(lot, -5.0), 4.0)
	Snow.set_rect(Rect2(spot - Vector2(4, 4), Vector2(8, 8)), 0.25)
	Snow.sync_all()
	pl.teleport(Vector3(spot.x, Snow.surface_height(spot.x, spot.y) + 0.05, spot.y), 0.0)
	Game.slots = ["standard_shovel", "", "", ""]
	Game.selected = 0
	Game.inventory_changed.emit()
	pl.pitch = deg_to_rad(-55.0)
	pl.head.rotation.x = pl.pitch
	await _frames(6)
	await _s17_open_gerry()
	var m0 := Clock.minutes
	Clock.running = true
	var p0 := pl.global_position
	Input.action_press("move_back")
	await _frames(40)
	Input.action_release("move_back")
	await _frames(2)
	var walked := pl.global_position.distance_to(p0)
	Input.action_press("primary")
	await _frames(40)
	var load: float = pl.tools.load
	Input.action_release("primary")
	await _frames(30)
	Clock.running = false
	runner.check(hp.is_open() and walked > 0.5 and load > 0.0 and Clock.minutes > m0 and pl.state == "foot" and world.modal == null and Game.input_captured(),
		"§17 with a hint up the player walks %.2f m and scoops (%.3f m³), the clock runs (+%.1f game min), nothing frozen" % [walked, load, Clock.minutes - m0])
	_release_all()
	await _unload()


## Hints queue: two fired together show one after the other. None opens over the computer or the
## sleep prompt (one up hides under them and comes back after). None covers Gerry's speech box.
func test_s17_queue() -> void:
	await _world()
	var hp = _hp()
	var a: bool = world.show_hint("gerry_snow", true)
	var tool_id := HelpText.tool_hint_id(ToolData.Kind.PUSHER)
	var b: bool = world.show_hint(tool_id)
	await _frames(2)
	var first: bool = hp.is_open("gerry_snow") and hp.queue.size() == 1
	hp.ok()
	await _frames(2)
	var second: bool = hp.is_open(tool_id)
	hp.ok()
	await _frames(2)
	runner.check(a and b and first and second and not hp.is_open(), "§17 two hints fired together: Gerry's first (the other waiting), then the pusher's")
	# The computer: a hint fired then waits; one already up hides and comes back.
	world.open_computer()
	await _frames(2)
	world.show_hint("gerry_snow", true)
	await _frames(3)
	var hidden_c: bool = world.modal_kind == "computer" and not hp.box.visible
	world.close_modal()
	await _frames(3)
	var back_c: bool = hp.is_open("gerry_snow")
	# The sleep prompt.
	world.open_sleep()
	await _frames(3)
	var hidden_s: bool = world.modal_kind == "sleep" and not hp.box.visible
	world.close_modal()
	await _frames(3)
	var back_s: bool = hp.is_open("gerry_snow")
	runner.check(hidden_c and back_c and hidden_s and back_s, "§17 no hint over the computer (%s, then back: %s) or the sleep prompt (%s, then back: %s)" % [hidden_c, back_c, hidden_s, back_s])
	# Beside Gerry's speech box, never over it.
	world.say_gerry([{"speaker": "Gerry", "text": "A long line, to make the speech box as tall as it gets. ".repeat(4)}])
	await _frames(3)
	var sb: Rect2 = world.hud.speech_box.get_global_rect()
	var hb: Rect2 = hp.box.get_global_rect()
	runner.check(world.hud.speech_box.visible and hp.is_open() and not sb.intersects(hb), "§17 the hint (%s) beside Gerry's speech box (%s), not over it" % [str(hb), str(sb)])
	world.say_gerry([])
	hp.ok()
	await _unload()


## Each hint shows once per save; save → load keeps the hints seen; an old save past the opening
## starts with the opening's hints seen (Gerry's, the shovel's), so they don't replay.
func test_s17_once_each() -> void:
	await _world()
	var hp = _hp()
	var id := HelpText.tool_hint_id(ToolData.Kind.SCRAPER)
	var once: bool = world.show_hint(id)
	await _frames(2)
	var opened: bool = hp.is_open(id) and Game.hint_seen(id)
	hp.ok()
	await _frames(2)
	var twice: bool = world.show_hint(id)
	await _frames(2)
	runner.check(once and opened and not twice and not hp.is_open(), "§17 a hint shows once (seen when it opens; asked again it doesn't)")
	runner.check(Saves.save_game(), "§17 saved")
	Game.hints_seen = {}
	await _unload()
	runner.check(Saves.load_game("fun") and Game.hint_seen(id) and Game.hints_seen.size() == 1, "§17 …loaded: the hints seen kept (%s)" % str(Game.hints_seen.keys()))
	Saves.delete_save("fun")
	# Old fixtures (no hints_seen key): past Gerry's job, his hint and the shovel's are seen.
	var bad := []
	for path in ["res://tests/fixtures/polish4/fun_2_mid_trail.json", "res://tests/fixtures/polish4/survival_3_trail_done.json",
			"res://tests/fixtures/polish5/fun_1_contracts.json", "res://tests/fixtures/polish5_v3/survival_4_midwinter.json",
			"res://tests/fixtures/polish3/fun_1_opening.json"]:
		if not await _load_save_file(path):
			bad.append("%s doesn't load" % path)
			continue
		var st := Game.stage()
		var want_gerry := st >= Game.Stage.NEIGHBOR_TALKED
		var want_shovel := st >= Game.Stage.COMPLETE or bool(Game.flags.get("found_shovel", false)) or "small_shovel" in Game.slots
		if Game.hint_seen("gerry_snow") != want_gerry or Game.hint_seen(HelpText.tool_hint_id(ToolData.Kind.SHOVEL)) != want_shovel:
			bad.append("%s (stage %d): %s" % [path.get_file(), st, str(Game.hints_seen.keys())])
		runner.info("§17 %s, stage %d: %s" % [path.trim_prefix("res://tests/fixtures/"), st, str(Game.hints_seen.keys())])
		Saves.delete_save(Game.mode)
	runner.check(bad.is_empty(), "§17 old saves derive the hints seen from the stage and flags: past the job, Gerry's and the shovel's don't replay; a save at the opening keeps them %s" % str(bad))
	await _unload()


## With "Show hints" off nothing opens (the first drive, a pickup, Gerry), Gerry says his tips in
## the speech box as before, and the Help app still has every hint's content.
func test_s17_hints_off() -> void:
	var saved: Variant = _backup()
	Settings.set_value("gameplay", "show_hints", false)
	await _world()
	var hp = _hp()
	var none: bool = not world.show_hint("gerry_snow", true) and not world.show_hint(HelpText.tool_hint_id(ToolData.Kind.SLEIGH))
	Game.flags.erase("help_vehicle_%d" % VehicleData.Kind.PICKUP_PLOW)
	var v := await _truck("pickup_plow", 40.0)
	await _frames(3)
	var drive_none: bool = not hp.is_open()
	await _drop(v)
	# Help: every hint's title and pages, with the keys bound now.
	var c: ComputerUI = null
	world.open_computer()
	await _frames(2)
	c = world.modal as ComputerUI
	c._open_app(ComputerUI.app_index("help"))
	await _frames(3)
	var text := ""
	for l in c.find_children("*", "Label", true, false):
		text += (l as Label).text + "\n"
	var missing := []
	for h in HelpText.hint_help():
		if not text.contains(str(h[0])) or not text.contains(str(h[1])):
			missing.append(h[0])
	for id in ["gerry_snow", HelpText.vehicle_hint_id(VehicleData.Kind.PICKUP_PLOW), HelpText.tool_hint_id(ToolData.Kind.SHOVEL), HelpText.tool_hint_id(ToolData.Kind.WALK_BLOWER)]:
		for p in HelpText.hint(id)["pages"]:
			for line in Settings.with_keys(str(p)).split("\n"):
				if not text.contains(line):
					missing.append("%s: %s" % [id, line])
	world.close_modal()
	runner.check(none and drive_none and not hp.is_open() and hp.queue.is_empty(), "§17 hints off: none opens (asked for, the first drive)")
	runner.check(missing.is_empty() and text.contains(Settings.action_label("primary")), "§17 …and the Help app has every hint's content, with the keys %s" % str(missing))
	_restore(saved)
	await _unload()


## Gerry: the job beat opens his hint with the bound keys (his first line still spoken); talking
## to him again during the job opens it again; with hints off he says it all, as before.
func test_s17_gerry() -> void:
	var saved: Variant = _backup()
	for off in [false, true]:
		Settings.set_value("gameplay", "show_hints", not off)
		await _unload()
		Game.force_input = true
		Game.new_game("survival", 2024)
		Clock.reset(Clock.at(0, 11.0))
		world = load("res://scenes/game.tscn").instantiate()
		runner.add_child(world)
		await _frames(3)
		await _faded_in()
		var hp = _hp()
		Game.flags["mail_read"] = true
		Game.set_stage(Game.Stage.LETTER_READ)
		world.neighbor_dialogue(world.neighbor)
		await _frames(1)
		var guard := 0
		while world.modal_kind == "dialogue" and guard < 20:
			var pressed := false
			for b in world.modal.find_children("*", "Button", true, false):
				if (b as Button).text.contains("$55") or (b as Button).text.contains("Continue"):
					(b as Button).pressed.emit()
					pressed = true
					break
			if not pressed:
				break
			await _frames(1)
			guard += 1
		await _frames(2)
		var said: String = world.hud.speech_text.text
		if not off:
			var page: String = hp.text_l.text if hp.is_open("gerry_snow") else ""
			runner.check(Game.stage() == Game.Stage.NEIGHBOR_TALKED and said == "Now, two ways to move snow." and world._talk.size() == 1 and page.contains("Hold [%s]" % Settings.action_label("primary")) and page.contains("throw"),
				"§17 the job beat: Gerry says \"%s\" and his hint opens with the bound key (%s)" % [said, page])
			hp.ok()
			await _frames(2)
			world.neighbor_dialogue(world.neighbor)
			await _frames(2)
			runner.check(hp.is_open("gerry_snow") and hp.page == 0 and world.hud.speech_text.text == said, "§17 talking to him again during the job re-opens it")
			hp.ok()
		else:
			runner.check(said == "Now, two ways to move snow." and world._talk.size() == 4 and not hp.is_open(), "§17 hints off: he says all four lines in the speech box, as before (%d)" % world._talk.size())
	_restore(saved)
	await _unload()


## The first drive of a kind of vehicle opens its hint (driving, the blade keys, back-drag), once;
## the first pickup of each kind of tool opens its hint, once; the blower's first grab too.
func test_s17_vehicle_and_tools() -> void:
	await _world("fun", 21.0)
	var hp = _hp()
	Game.flags.erase("help_vehicle_%d" % VehicleData.Kind.PICKUP_PLOW)
	var v := await _truck("pickup_plow", 40.0)
	await _frames(2)
	var vid := HelpText.vehicle_hint_id(VehicleData.Kind.PICKUP_PLOW)
	var pages: int = (hp.current.get("pages", []) as Array).size()
	var first: bool = hp.is_open(vid) and pages == 3 and hp.title_l.text.ends_with("controls")
	hp.ok()
	await _drop(v)
	v = await _truck("pickup_plow", 40.0)
	await _frames(2)
	var again: bool = hp.is_open()
	await _drop(v)
	runner.check(first and not again, "§17 the first drive opens the vehicle hint (%d pages: driving, the blade keys, back-drag), the second doesn't" % pages)
	# The first pickup of each kind of tool.
	var pl: Player = world.player
	var lot := Layout.player_lot
	var spot := Layout.lot_to_world(lot, Layout.gu(lot, -5.0), 4.0)
	Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), 0.0)
	pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
	var kinds := {}
	for t in Catalog.tools.values():
		var td := t as ToolData
		if td.kind in [ToolData.Kind.HANDS, ToolData.Kind.WALK_BLOWER] or kinds.has(td.kind):
			continue
		kinds[td.kind] = String(td.id)
	var bad := []
	for kind in kinds.keys():
		for n in range(2):
			Game.slots = ["", "", "", ""]
			Game.carried = ""
			world.spawn_tool_item(kinds[kind], Vector3(spot.x, 0, spot.y - 0.8), 0.0)
			await _frames(2)
			var it: ToolItem = null
			for c in world.find_children("*", "ToolItem", true, false):
				if (c as ToolItem).tool_id == kinds[kind] and not c.is_queued_for_deletion():
					it = c
			if it == null:
				bad.append("%s: no item" % kinds[kind])
				break
			it.interact(pl)
			await _frames(3)
			var hid := HelpText.tool_hint_id(kind)
			var up: bool = hp.is_open(hid)
			if (n == 0) != up:
				bad.append("%s pickup %d: open %s" % [kinds[kind], n + 1, up])
			if up:
				runner.info("§17 %s: \"%s\" — %s" % [kinds[kind], hp.title_l.text, hp.text_l.text.replace("\n", " | ")])
			hp.ok()
			await _frames(1)
	# The blower's first grab.
	var me := {"uid": Game.uid(), "tool": "small_blower", "pos": Vector3(spot.x + 1.5, 0, spot.y), "yaw": 0.0}
	Game.machines.append(me)
	var m: WalkBehind = world.spawn_machine_node(me)
	Game.slots = ["", "", "", ""]
	await _frames(2)
	m.interact(pl)
	await _frames(3)
	var blower_up: bool = hp.is_open(HelpText.tool_hint_id(ToolData.Kind.WALK_BLOWER))
	runner.check(bad.is_empty() and kinds.size() >= 4 and blower_up, "§17 the first pickup of each kind of tool opens its hint, the second doesn't (%d kinds); the blower's first grab too (%s) %s" % [kinds.size(), blower_up, str(bad)])
	hp.ok()
	m.release()
	await _unload()


## The panel fits at 1280×720, 1920×1080, 2560×1440 and 3440×1440 (their canvases): on the
## screen, clear of the crosshair, the prompt, the status line, the speech box, the notifications,
## the weather panel and the hotbar, with the longest hint up.
const S17_CANVASES := {"1280x720": Vector2(1920, 1080), "1920x1080": Vector2(1920, 1080),
	"2560x1440": Vector2(1920, 1080), "3440x1440": Vector2(2580, 1080)}


func test_s17_fit() -> void:
	await _world()
	var hp = _hp()
	var hud: HUD = world.hud
	world.show_hint("gerry_snow", true)
	await _frames(2)
	var bad := []
	var vd := Catalog.vehicle(&"plow_truck")
	var ids := [["gerry_snow", null], [HelpText.vehicle_hint_id(int(vd.kind)), vd], [HelpText.tool_hint_id(ToolData.Kind.SCRAPER), null]]
	for res in S17_CANVASES.keys():
		var logical: Vector2 = S17_CANVASES[res]
		hud.size = logical
		hp.size = logical
		world.say_gerry([{"speaker": "Gerry", "text": "A long line, to make the speech box as tall as it gets. ".repeat(4)}])
		Notify.push("A notification, to fill the notification box with a long line of text.", Notify.INFO)
		for e in ids:
			hp.ok()
			hp.show_hint(str(e[0]), true, e[1])
			await _frames(1)
			var screen := Rect2(Vector2.ZERO, logical)
			for k in range(6):
				var hb: Rect2 = hp.box.get_global_rect()
				var others := {"speech": hud.speech_box.get_global_rect(), "crosshair": hud.crosshair.get_global_rect(),
					"prompt": hud.prompt_l.get_global_rect(), "status": hud.hint_l.get_global_rect(),
					"notifications": hud.notif_box.get_global_rect(), "hotbar": hud.hotbar.get_global_rect(),
					"weather": (hud.weather_icon.get_parent().get_parent() as Control).get_global_rect()}
				if not screen.encloses(hb):
					bad.append("%s %s p%d: off the screen %s" % [res, e[0], hp.page + 1, str(hb)])
				for n in others.keys():
					if (others[n] as Rect2).intersects(hb):
						bad.append("%s %s p%d: over the %s %s / %s" % [res, e[0], hp.page + 1, n, str(hb), str(others[n])])
				if hp.text_l.get_line_count() != hp.text_l.get_visible_line_count():
					bad.append("%s %s p%d: text cut" % [res, e[0], hp.page + 1])
				if hp.current.is_empty() or hp.page >= (hp.current["pages"] as Array).size() - 1:
					break
				hp.next()
				await _frames(1)
		runner.info("§17 %s: the hint at %s" % [res, str(hp.box.get_global_rect())])
	world.say_gerry([])
	hp.ok()
	runner.check(bad.is_empty(), "§17 the panel fits at 1280×720, 1920×1080, 2560×1440 and 3440×1440, clear of the HUD %s" % str(bad))
	await _unload()


# =============================================================================
# §15 The garage
# =============================================================================

const _GarageS := preload("res://scripts/world/garage.gd")


## A world (fun, Dec 2 noon, the tutorial done, keys found), the new game's truck taken away, the yard,
## the driveway and the street in front bare.
func _s15_world(mode := "fun") -> void:
	await _world(mode)
	var lot := Layout.player_lot
	var hi := Layout.house_info(lot)
	for v in world.vehicle_nodes():
		Game.vehicles.erase((v as Vehicle).entry)
		(v as Node).queue_free()
	await _frames(2)
	Snow.set_rect((lot["rect"] as Rect2).merge(hi["driveway"]).grow(6.0), 0.0)
	Snow.sync_all()


## The garage's door set at once (open or closed).
func _s15_door(open: bool) -> void:
	var g = world.garage
	g.opening = open
	g.t = 1.0 if open else 0.0
	g._place_door()
	Game.garage["door_open"] = open
	await _frames(2)


## A point in the garage's frame (x across from the house wall, z inward from the setback) in the world.
static func _s15_at(x: float, z: float, y := 0.0) -> Vector3:
	var lot := Layout.player_lot
	return HouseBuilder.lot_transform(lot) * Vector3(x, y, float(lot["setback"]) + z)


## The yaw that drives a vehicle into the garage (toward its back wall).
static func _s15_yaw_in() -> float:
	var inward := Vector2(Layout.player_lot["inward"]).normalized()
	return atan2(-inward.x, -inward.y)


## Hold `keys` until `done` says so or the vehicle has stood still 45 frames (at most `frames`).
func _s15_hold(v: Node3D, keys: Array, done: Callable, frames := 900) -> bool:
	for k in keys:
		Input.action_press(k)
	var still := 0
	var last := v.global_position
	var ok := false
	for f in range(frames):
		await _tree().physics_frame
		if done.call():
			ok = true
			break
		still = still + 1 if f > 30 and v.global_position.distance_to(last) < 0.0005 else 0
		last = v.global_position
		if still >= 45:
			break
	for k in keys:
		Input.action_release(k)
	await _frames(3)
	return ok or done.call()


## A vehicle's solid boxes all outside the garage (in front of its door line).
func _s15_outside(v: Node3D) -> bool:
	var gr: Rect2 = _GarageS.footprint()
	for b in world._solid_boxes(v, v.global_transform):
		for p in world._box_corners(b[0], b[1]):
			if gr.has_point(p):
				return false
	return true


## How deep any corner of a vehicle's solid boxes stands inside the garage's footprint (0: none).
func _s15_depth_in(v: Node3D) -> float:
	var r: Rect2 = _GarageS.footprint()
	var d := 0.0
	for b in world._solid_boxes(v, v.global_transform):
		for q in world._box_corners(b[0], b[1]):
			if r.has_point(q):
				d = maxf(d, minf(minf(q.x - r.position.x, r.end.x - q.x), minf(q.y - r.position.y, r.end.y - q.y)))
	return d


## The door from the house: locked without the keys (its message), open with them, still after a
## save and a load; and the player walks from the kitchen through it, down the steps, into the garage.
func test_s15_house_door() -> void:
	await _s15_world()
	Game.flags["truck_keys"] = false
	var d: Door = world.garage_house_door
	var pl: Player = world.player
	var why: String = d.interact_prompt(pl)
	d.interact(pl)
	await _frames(2)
	runner.check(d != null and why.contains("Locked") and why.contains("keys") and not d.open, "§15 without the keys the door to the garage is locked: \"%s\"" % why)
	Game.flags["truck_keys"] = true
	var p2: String = d.interact_prompt(pl)
	d.interact(pl)
	await _frames(20)
	runner.check(d.open and p2.begins_with("[E] Open"), "§15 with the keys it opens (\"%s\")" % p2)
	# Walk through it: from the kitchen, through the door, down the steps, onto the garage floor.
	var zc := (HouseBuilder.HDOOR_Z0 + HouseBuilder.HDOOR_Z1) * 0.5
	var start := _s15_at(HouseBuilder.BODY_X1 - 1.2, zc, Layout.PORCH_H + 0.05)
	pl.teleport(start)
	var into := _s15_at(HouseBuilder.BODY_X1 + 1.0, zc)
	pl.set_yaw(atan2(-(into.x - start.x), -(into.z - start.z)))
	await _frames(3)
	var in_house := pl.in_player_house
	Input.action_press("move_forward")
	await _frames(70)
	Input.action_release("move_forward")
	var down := _s15_at(HouseBuilder.GAR_X0 + 0.5, 2.0)
	pl.set_yaw(atan2(-(down.x - pl.global_position.x), -(down.z - pl.global_position.z)))
	Input.action_press("move_forward")
	await _frames(100)
	Input.action_release("move_forward")
	await _frames(10)
	runner.check(in_house and pl.in_garage and pl.global_position.y < 0.15 and not pl.in_player_house, "§15 the player walks from the kitchen through it, down the steps, onto the garage floor (y %.2f, %s)" % [pl.global_position.y, str(pl.global_position)])
	# Saved and loaded: still unlocked (the keys flag; no save key of its own).
	world.collect_state()
	runner.check(Saves.save_game(), "§15 saved")
	await _unload()
	runner.check(Saves.load_game("fun"), "§15 …loaded")
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(3)
	var d2: Door = world.garage_house_door
	runner.check(d2.interact_prompt(world.player).begins_with("[E] Open"), "§15 …and after a load the door is still unlocked")
	Saves.delete_save("fun")
	await _unload()


## The overhead door: the button opens and closes it; closed, it stops the player and a plowed
## pickup (its blade down) at the door line; it won't close on the player; its state survives a save
## and a load, and a new game has it closed.
func test_s15_overhead_door() -> void:
	await _s15_world()
	var g = world.garage
	var pl: Player = world.player
	var closed0: bool = g.is_closed() and not bool(Game.garage.get("door_open", true))
	g.press()
	await _frames(int(_GarageS.DOOR_TIME * 60.0) + 10)
	var opened: bool = g.is_open() and bool(Game.garage["door_open"])
	g.press()
	await _frames(int(_GarageS.DOOR_TIME * 60.0) + 10)
	var closed1: bool = g.is_closed()
	runner.check(closed0 and opened and closed1, "§15 closed at first; the button opens it (%.1f s) and closes it" % _GarageS.DOOR_TIME)
	# Closed: the player inside walks into it and stays in.
	pl.teleport(_s15_at(6.0, 1.0))
	pl.set_yaw(_s15_yaw_in() + PI)
	await _frames(3)
	Input.action_press("move_forward")
	await _frames(120)
	Input.action_release("move_forward")
	await _frames(3)
	runner.check(pl.in_garage, "§15 closed, the player inside walks into it and stays in (%s)" % str(pl.global_position))
	pl.teleport(_s15_at(-3.0, -8.0))
	var gz0: float = -0.5
	var p := _s15_at(6.0, gz0 - 7.0)
	var v := await _truck("pickup_plow", p.x, p.z, _s15_yaw_in())
	v.set_blade(true)
	await _frames(90)
	var deepest := [0.0]
	await _s15_hold(v, ["veh_accelerate"], func() -> bool:
		deepest[0] = maxf(deepest[0], _s15_depth_in(v))
		return false, 600)
	runner.check(deepest[0] < 0.006, "§15 closed, a plowed pickup (blade down) driven at it stops at the door line (at most %.4f m inside)" % deepest[0])
	await _drop(v)
	# It won't close on the player standing in the doorway.
	await _s15_door(true)
	pl.teleport(_s15_at(6.0, gz0 + 0.1))
	await _frames(3)
	g.press()
	await _frames(10)
	runner.check(g.opening and _said("in the way"), "§15 it won't close on the player in the doorway (\"Something is in the way…\")")
	pl.teleport(_s15_at(-3.0, -8.0))
	await _frames(3)
	# Saved open, loaded open.
	world.collect_state()
	runner.check(Saves.save_game(), "§15 saved with the door open")
	await _unload()
	runner.check(Saves.load_game("fun"), "§15 …loaded")
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(3)
	runner.check(world.garage.is_open() and bool(Game.garage["door_open"]), "§15 …the door is open after the load")
	Saves.delete_save("fun")
	await _s15_world()
	runner.check(world.garage.is_closed(), "§15 a new game: the door closed")
	await _unload()


## The plowed pickup drives in to the back wall, the door closes behind it, and it backs out: blade
## up and down, straight and angled both ways, with and without the width upgrade. The ATV and a
## walk-behind blower fit. A tractor stops at the open door with "Too big for the garage."
func test_s15_parking() -> void:
	await _s15_world()
	await _s15_door(true)
	var g = world.garage
	var gz0 := -0.5
	var r: Rect2 = _GarageS.footprint()
	var bad := []
	var runs := 0
	for up in [false, true]:
		if up:
			Game.grant_upgrade(StringName(ItemUpgrades.level_id(&"pickup_plow", &"plow_width", 1)))
		for down in [false, true]:
			for a in [0.0, -30.0, 30.0]:
				var p := _s15_at(6.0, gz0 - 8.0)
				var v := await _truck("pickup_plow", p.x, p.z, _s15_yaw_in())
				v.set_blade(down)
				v.blade_angle = a
				await _frames(90)
				var inside := await _s15_hold(v, ["veh_accelerate"], func() -> bool: return world.in_garage(v), 900)
				await _s15_hold(v, ["veh_accelerate"], func() -> bool: return false, 240)
				var full: bool = world.in_garage(v)
				g.press()
				await _frames(int(_GarageS.DOOR_TIME * 60.0) + 10)
				var shut: bool = g.is_closed()
				g.press()
				await _frames(int(_GarageS.DOOR_TIME * 60.0) + 10)
				var out := await _s15_hold(v, ["veh_reverse"], func() -> bool: return _s15_outside(v), 1500)
				runs += 1
				runner.info("§15 pickup_plow, %s, blade %s %+d°: in %s, at the back wall %s, the door shut behind it %s, out %s" % ["width upgrade" if up else "no upgrade", "down" if down else "up", int(a), inside, full, shut, out])
				if not (inside and full and shut and out):
					bad.append("%s %s %+d°" % ["upgraded" if up else "plain", "down" if down else "up", int(a)])
				await _drop(v)
				await _s15_door(true)
	runner.check(bad.is_empty() and runs == 12, "§15 the plowed pickup drives in to the back wall, the door closes behind it, and it backs out: blade up and down, straight and ±30°, with and without the width upgrade (%d runs) %s" % [runs, str(bad)])
	# The ATV, and a walk-behind blower pushed in by the player.
	var p2 := _s15_at(7.4, gz0 - 5.0)
	var atv := await _truck("atv_blade", p2.x, p2.z, _s15_yaw_in())
	var atv_in := await _s15_hold(atv, ["veh_accelerate"], func() -> bool: return world.in_garage(atv) and r.grow(-1.5).has_point(Vector2(atv.global_position.x, atv.global_position.z)), 900)
	await _drop(atv)
	var pl: Player = world.player
	var me := {"uid": Game.uid(), "tool": "small_blower", "pos": _s15_at(5.0, gz0 - 3.0), "yaw": _s15_yaw_in()}
	Game.machines.append(me)
	var m: WalkBehind = world.spawn_machine_node(me)
	await _frames(2)
	pl.teleport(_s15_at(5.0, gz0 - 4.2))
	pl.set_yaw(_s15_yaw_in())
	await _frames(2)
	m.interact(pl)
	await _frames(2)
	Input.action_press("move_forward")
	await _frames(150)
	Input.action_release("move_forward")
	m.release()
	await _frames(3)
	var blower_in: bool = r.has_point(Vector2(m.global_position.x, m.global_position.z))
	runner.check(atv_in and blower_in, "§15 the ATV drives in (%s) and a walk-behind blower is pushed in (%s)" % [atv_in, blower_in])
	pl.teleport(_s15_at(-3.0, -8.0))
	# A tractor stops at the door line, with its message.
	var p3 := _s15_at(6.0, gz0 - 6.0)
	var tr := await _truck("tractor_blade", p3.x, p3.z, _s15_yaw_in())
	var said := [""]
	var went_in := await _s15_hold(tr, ["veh_accelerate"], func() -> bool:
		if tr.status_text != "":
			said[0] = tr.status_text
		return _s15_depth_in(tr) > 0.01, 600)
	runner.check(not went_in and str(said[0]).contains("Too big for the garage"), "§15 a tractor stops at the open door: \"%s\"" % said[0])
	await _drop(tr)
	await _unload()


## Nothing overlaps: the truck and the ATV parked side by side inside stay apart and where they are
## through a save and a load; the player gets out of each inside, clear of them.
func test_s15_no_overlap() -> void:
	await _s15_world()
	await _s15_door(true)
	var gz0 := -0.5
	# The truck in the middle (clear of the steps at the house side), the ATV on the outer side.
	var pt := _s15_at(5.25, gz0 - 8.0)
	var t := await _truck("pickup_plow", pt.x, pt.z, _s15_yaw_in())
	await _s15_hold(t, ["veh_accelerate"], func() -> bool: return false, 700)
	t.exit_vehicle()
	await _frames(3)
	var pl: Player = world.player
	var out1: bool = pl.in_garage
	var pa := _s15_at(7.75, gz0 - 5.0)
	var a := await _truck("atv_blade", pa.x, pa.z, _s15_yaw_in())
	await _s15_hold(a, ["veh_accelerate"], func() -> bool: return false, 700)
	a.exit_vehicle()
	await _frames(3)
	var out2: bool = pl.in_garage
	var both_in: bool = world.in_garage(t) and world.in_garage(a)
	var touching: bool = not world._bodies_on(world._solid_boxes(t, t.global_transform), [t.get_rid()] as Array[RID]).is_empty()
	var where := {t.uid: t.global_position, a.uid: a.global_position}
	runner.check(both_in and not touching and out1 and out2, "§15 the pickup and the ATV parked side by side in the garage, not touching; getting out of each puts the player inside, clear of them (%s %s)" % [out1, out2])
	world.collect_state()
	runner.check(Saves.save_game(), "§15 saved")
	await _unload()
	runner.check(Saves.load_game("fun"), "§15 …loaded")
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(5)
	var moved := []
	var still_in := 0
	for v in world.vehicle_nodes():
		var u: int = (v as Vehicle).uid
		if not where.has(u):
			continue
		if (v as Node3D).global_position.distance_to(where[u]) > 0.02:
			moved.append(u)
		if world.in_garage(v):
			still_in += 1
	runner.check(moved.is_empty() and still_in == 2, "§15 …both where they were parked, inside (%d), none moved %s" % [still_in, str(moved)])
	Saves.delete_save("fun")
	await _unload()


## Sleeping: a truck in the garage stays there; one on the street goes to Game.truck_start().
func test_s15_sleep() -> void:
	await _s15_world()
	var ts := Game.truck_start()
	var e := {"uid": Game.uid(), "id": "pickup_plow", "pos": _s15_at(6.0, 3.6), "yaw": _s15_yaw_in(), "snow": 0.0}
	Game.vehicles.append(e)
	var v: Vehicle = world.spawn_vehicle_node(e)
	await _frames(3)
	var at := v.global_position
	var in0: bool = world.in_garage(v)
	await world.send_truck_home()
	await _frames(3)
	runner.check(in0 and v.global_position.distance_to(at) < 0.01, "§15 a truck in the garage stays there when you sleep (moved %.3f m)" % v.global_position.distance_to(at))
	v.park_at(Vector3(60.0, 0, 84.95), -PI * 0.5)
	await _frames(3)
	await world.send_truck_home()
	await _frames(3)
	var home: Vector3 = ts["pos"]
	var off := Vector2(v.global_position.x - home.x, v.global_position.z - home.z).length()
	runner.check(off < 0.05, "§15 a truck on the street goes home to truck_start (%.3f m from it)" % off)
	await _unload()


## The rack: F hangs the tool in your hands, E takes it back into a free slot or swaps it with the one
## you hold; the item keeps its upgrades; a full rack refuses; F outside the garage does nothing; a
## save and a load keep it, its tools shown on the wall.
func test_s15_rack() -> void:
	await _s15_world()
	var g = world.garage
	var pl: Player = world.player
	pl.teleport(_s15_at(4.5, 2.0))
	await _frames(3)
	Game.grant_upgrade(StringName(ItemUpgrades.level_id(&"small_shovel", &"capacity", 1)))
	var m0 := ItemUpgrades.mult(&"small_shovel", &"shovel_capacity")
	Game.slots = ["small_shovel", "wide_pusher", "snow_scraper", "standard_shovel"]
	Game.selected = 0
	Game.inventory_changed.emit()
	await _frames(2)
	await _key(_bound("store"))
	var stored: bool = _GarageS.rack()[0] == "small_shovel" and Game.slots[0] == ""
	var kept: bool = Game.owns_tool("small_shovel") and is_equal_approx(ItemUpgrades.mult(&"small_shovel", &"shovel_capacity"), m0) and m0 > 1.0
	runner.check(stored and kept, "§15 F in the garage hangs the shovel in your hands on the rack (%s); it's still yours, its capacity upgrade kept (×%.2f)" % [str(_GarageS.rack()), m0])
	g.take(0, pl)
	await _frames(2)
	runner.check(_GarageS.rack()[0] == "" and Game.slots[0] == "small_shovel", "§15 E on it takes it back into the free slot")
	# Swap: every slot full, holding the scraper.
	Game.selected = 2
	_GarageS.rack()[2] = "snow_sleigh"
	g.take(2, pl)
	await _frames(2)
	runner.check(Game.slots[2] == "snow_sleigh" and _GarageS.rack()[2] == "snow_scraper", "§15 E with every slot full swaps the racked sleigh for the scraper in your hands")
	# A full rack refuses: the tool stays in your hands.
	var rk: Array = _GarageS.rack()
	for i in range(_GarageS.slots_n()):
		rk[i] = "wide_pusher"
	Game.selected = 0
	var why: String = g.store(pl)
	runner.check(why == "full" and Game.slots[0] == "small_shovel" and _said("The rack is full"), "§15 a full rack (%d slots) refuses: \"The rack is full.\"" % _GarageS.slots_n())
	for i in range(_GarageS.slots_n()):
		rk[i] = ""
	rk[1] = "snow_sleigh"
	rk[4] = "small_shovel"
	# F outside the garage does nothing.
	pl.teleport(_s15_at(-4.0, -6.0))
	await _frames(3)
	var before := Game.slots.duplicate()
	await _key(_bound("store"))
	runner.check(Game.slots == before and _GarageS.rack()[1] == "snow_sleigh" and not pl.in_garage, "§15 F outside the garage does nothing")
	world.collect_state()
	runner.check(Saves.save_game(), "§15 saved")
	var want := JSON.stringify(_GarageS.rack())
	await _unload()
	runner.check(Saves.load_game("fun"), "§15 …loaded")
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _frames(4)
	var shown: int = world.garage.rack_root.find_children("RackTool*", "MeshInstance3D", true, false).size()
	runner.check(JSON.stringify(_GarageS.rack()) == want and shown == 2, "§15 …the rack as saved (%s), its %d tools on the wall" % [want, shown])
	Saves.delete_save("fun")
	await _unload()


## The heated pad put down on the garage floor stays there; it isn't a heat source there (no melt,
## no power on the bill).
func test_s15_pad() -> void:
	await _s15_world("survival")
	var pl: Player = world.player
	Game.equipment[String(Equipment.PAD)] = {}
	Game.carried = String(Equipment.PAD)
	pl.teleport(_s15_at(6.0, 1.5))
	await _frames(3)
	var f3 := _s15_at(6.0, 4.0) - _s15_at(6.0, 1.5)
	var why := Equipment.put_down_pad(pl, Vector2(f3.x, f3.z), _s15_yaw_in())
	var r := Equipment.pad_rect()
	var srcs: Array = Heating.sources().map(func(s): return s["id"])
	var used0 := Economy.heat_used
	for i in range(6):
		Heating.advance(60.0)
	runner.check(why == "" and Equipment.pad_placed() and _GarageS.floor_rect().encloses(r) and not ("pad" in srcs) and Economy.heat_used == used0,
		"§15 the pad goes down on the garage floor (\"%s\") and stays; it is no heat source there %s; nothing billed (%.3f)" % [why, str(srcs), Economy.heat_used - used0])
	await _unload()


## No snow gets into the garage, the volume exact: a storm with the door open, throws at the open
## doorway, a blade pushing snow at the open door, a back-drag from the closed door.
func test_s15_no_snow_inside() -> void:
	await _s15_world()
	var gr: Rect2 = _GarageS.footprint()
	var gz0 := -0.5
	await _s15_door(true)
	var fall0 := Snow.fall_total
	Weather.force(Weather.C.HEAVY, 6.0)
	Clock.running = true
	for i in range(240):
		await _tree().physics_frame
	Clock.running = false
	runner.check(Snow.fall_total > fall0 and Snow.volume_in_rect(gr) == 0.0, "§15 a storm with the door open (%.2f cm fell): no snow in the garage" % ((Snow.fall_total - fall0) * 100.0))
	Weather.force(Weather.C.CLEAR, 48.0)
	# Throws at the open doorway, from the driveway.
	Snow.set_rect(gr.grow(6.0), 0.3)
	Snow.sync_all()
	var v0 := Snow.total_volume()
	var thrown := 0.0
	for k in range(5):
		var st := _s15_at(3.8 + k * 1.1, gz0 - 3.0, 1.4)
		var aim := _s15_at(3.8 + k * 1.1, gz0 + 3.0, 1.4)
		var d2 := Vector2(aim.x - st.x, aim.z - st.z).normalized()
		var land := Throw.compute(world.get_world_3d(), st, d2, 4.5, 25.0, [])
		if land.get("valid", false):
			var ts := ThrownSnow.spawn(world, st, d2, land, 0.05, 25.0, 0.35)
			ts.flush()
			thrown += 0.05
	var v1 := Snow.total_volume()
	runner.check(thrown > 0.0 and Snow.volume_in_rect(gr) == 0.0 and absf(v1 - v0 - thrown) < 1e-6, "§15 snow thrown at the open doorway falls outside: none inside, the volume exact (%.2f m³ thrown, %+.7f m³)" % [thrown, v1 - v0 - thrown])
	# A blade pushing snow at the open door.
	var p := _s15_at(6.0, gz0 - 9.0)
	var v := await _truck("pickup_plow", p.x, p.z, _s15_yaw_in())
	v.set_blade(true)
	await _frames(90)
	var v2 := Snow.total_volume()
	await _s15_hold(v, ["veh_accelerate"], func() -> bool: return false, 600)
	var v3 := Snow.total_volume()
	runner.check(Snow.volume_in_rect(gr) == 0.0 and absf(v3 - v2) < 1e-4, "§15 a blade pushing snow at the open door leaves it outside: none inside, the volume kept (%+.6f m³)" % (v3 - v2))
	await _drop(v)
	# A back-drag from the closed door.
	await _s15_door(false)
	Snow.set_rect(gr.grow(6.0), 0.3)
	Snow.sync_all()
	var v4 := Snow.total_volume()
	var p2 := _s15_at(6.0, gz0 - 4.0)
	var dv := await _truck("pickup_plow", p2.x, p2.z, _s15_yaw_in())
	await _s15_hold(dv, ["veh_accelerate"], func() -> bool: return false, 400)
	dv.set_blade(true)
	await _frames(60)
	await _s15_hold(dv, ["veh_reverse"], func() -> bool: return false, 300)
	var v5 := Snow.total_volume()
	runner.check(Snow.volume_in_rect(gr) == 0.0 and absf(v5 - v4) < 1e-4, "§15 back-dragging from the closed door: none inside, the volume kept (%+.6f m³)" % (v5 - v4))
	await _drop(dv)
	await _unload()


## Inside the garage a vehicle gathers no roof snow, and the snow it brought in melts off on the
## clock; the ground snow's hide rect covers the garage, the house's rect as before.
func test_s15_climate_and_hide() -> void:
	await _s15_world()
	var e := {"uid": Game.uid(), "id": "pickup_plow", "pos": _s15_at(6.0, 3.6), "yaw": _s15_yaw_in(), "snow": 0.9}
	Game.vehicles.append(e)
	var v: Vehicle = world.spawn_vehicle_node(e)
	var e2 := {"uid": Game.uid(), "id": "pickup", "pos": Vector3(60.0, 0, 84.95), "yaw": -PI * 0.5, "snow": 0.0}
	Game.vehicles.append(e2)
	var o: Vehicle = world.spawn_vehicle_node(e2)
	await _frames(3)
	world._veh_melt_last = Clock.minutes
	world._veh_snow_last = Snow.fall_total
	Snow.fall_total += 0.05
	Clock.minutes += 60.0
	world._roof_timer = 0.0
	world._vehicle_snow_step(0.1)
	var after1 := v.snow_load
	Clock.minutes += 180.0
	world._roof_timer = 0.0
	world._vehicle_snow_step(0.1)
	runner.check(is_equal_approx(after1, 0.9 - Catalog.balance.garage_snow_melt_per_hour) and v.snow_load == 0.0 and o.snow_load > 0.0,
		"§15 a vehicle in the garage gathers no roof snow and its snow melts off (0.90 → %.2f after an hour, gone after four); one outside gathers it (%.3f)" % [after1, o.snow_load])
	var hide: Dictionary = world.snow_hide_rects(true)
	var c: Vector4 = hide["snow_hide_c"]
	var a: Vector4 = hide["snow_hide_a"]
	var sh_src := FileAccess.get_file_as_string("res://shaders/snow_ground.gdshader")
	var gr: Rect2 = _GarageS.footprint()
	var body: Rect2 = (Layout.house_info(Layout.player_lot)["body"] as Rect2).grow(0.05)
	runner.check(c == Vector4(gr.position.x, gr.position.y, gr.end.x, gr.end.y) and a.is_equal_approx(Vector4(body.position.x, body.position.y, body.end.x, body.end.y)) and sh_src.contains("in_rect(snow_hide_c, v_world.xz)"),
		"§15 the ground snow is hidden inside the garage (snow_hide_c %s); the house's rect as before" % str(c))
	await _unload()


## The first time in the garage opens its hint (the button, the rack), once.
func test_s15_hint() -> void:
	await _s15_world()
	var pl: Player = world.player
	pl.teleport(_s15_at(5.0, 2.0))
	await _frames(4)
	var hp = world.hint_panel
	var first: bool = hp.is_open("garage") and hp.text_l.text.contains(Settings.action_label("interact"))
	hp.next()
	await _frames(2)
	var second: bool = hp.text_l.text.contains(Settings.action_label("store"))
	hp.ok()
	pl.teleport(_s15_at(-3.0, -8.0))
	await _frames(3)
	pl.teleport(_s15_at(5.0, 2.0))
	await _frames(4)
	runner.check(first and second and not hp.is_open(), "§15 the first time in the garage its hint opens (the button with %s, the rack with %s), once" % [Settings.action_label("interact"), Settings.action_label("store")])
	await _unload()
