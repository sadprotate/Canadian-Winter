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
