extends Node
## Polish 5 §0.2: a run of the real main scene, for the Godot output (every error and warning) of
## menu → New Game → a minute of play → sleep → back to the menu → Exit.
##
## Headless:  godot --headless --fixed-fps 60 --path . res://tests/run_log.tscn [-- --mode=survival]
## Windowed:  xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . res://tests/run_log.tscn [-- --mode=survival]
## Options:   --mode=fun|survival (default fun)   --play=<seconds of play> (default 60)
##            --timeout=<real seconds> (default 1800: a watchdog quits with code 3 if the run hangs)
##            --emit=1  press buttons by emitting `pressed` from the driver's coroutine (resumed on
##                      process_frame) instead of clicking them
##            --emit=physics  the same, resumed on physics_frame (as the tests' _press_btn after
##                      `await _frames(n)` does)
##
## What it does, through the game's own scenes, buttons and input actions (no test hooks):
##  1. changes to scenes/main_menu.tscn (the real main scene), waits for its background;
##  2. PLAY → the mode's card → New Game (and "Start new game" if a save exists): the menu's own
##     change_scene_to_file to scenes/game.tscn;
##  3. about a minute of play (the game's own delta time, so 24 game minutes on the clock): a few
##     steps in the bedroom, then — the house has no path-finding for a bot — it hops to the hall
##     inside the front door, opens the door with Interact, walks out (move_forward) into the yard,
##     scoops twice (hold primary while sweeping the view with mouse motion, release to throw) and
##     walks about the yard;
##  4. sleeps through the bed: hops to the bedroom, aims at the bed with mouse motion, steps up to
##     it until its prompt shows, presses Interact, then "Sleep until 7:00 a.m." (the path of
##     HANDOFF §13 item 12; at the polish-5 baseline `p_elem->_root` prints with --emit=physics,
##     not with a real click), and waits for the autosave and the fade-in;
##  5. Esc (the `pause` action) → EXIT TO MAIN MENU (→ "Exit" if it asks) → the real main menu;
##  6. presses EXIT: the menu's own `get_tree().quit()` (HANDOFF §13 item 13's leak report).
## Buttons are clicked with a real mouse click at their centre (InputEventMouseButton); if the
## click doesn't reach the button the driver says so and emits `pressed` instead. Looking uses
## InputEventMouseMotion; walking and scooping use the input actions. Headless builds can't capture
## the mouse, so there (only) the driver sets `Game.force_input` like the tests do, so gameplay
## input is live while no menu is open. Every step prints a "[run_log]" line, so the engine output
## around it can be attributed. A step that never completes prints "[run_log] FAILED …" and quits
## with code 2 (so a broken run never looks like a clean one).

var is_driver := false
var mode := "fun"
var play_seconds := 60.0
var _phase := ""
var _phase_t0 := 0
var timeout_s := 1800.0
var emit_buttons := false
var emit_in_physics := false
var _t_start := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_driver:
		_run.call_deferred()
		return
	# Launcher: start a driver outside the current scene (so it survives scene changes) and hand
	# over to the real main scene.
	var d: Node = (get_script() as GDScript).new()
	d.name = "RunLogDriver"
	d.set("is_driver", true)
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred(ProjectSettings.get_setting("application/run/main_scene"))


func _process(_delta: float) -> void:
	if is_driver and _t_start > 0 and (Time.get_ticks_msec() - _t_start) / 1000.0 > timeout_s:
		_say("FAILED: still running after %.0f s (stuck during '%s')" % [timeout_s, _phase])
		_t_start = 0
		get_tree().quit(3)


func _say(t: String) -> void:
	print("[run_log] %s" % t)


func _step(name: String) -> void:
	_phase = name
	_phase_t0 = Time.get_ticks_msec()
	_say("== %s (game %s)" % [name, Clock.format_time(Clock.minutes) if Game.in_game else "-"])


func _fail(why: String) -> void:
	_say("FAILED during '%s': %s" % [_phase, why])
	_release_all()
	get_tree().quit(2)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## Wait `seconds` of the game's own time (summed frame deltas while the tree isn't paused).
func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()


## Wait until `cond` is true, up to `limit_s` of real time (generous: software rendering is slow).
func _until(cond: Callable, limit_s: float, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if (Time.get_ticks_msec() - t0) / 1000.0 > limit_s:
			_fail("timed out waiting for " + what)
			return false
		await get_tree().process_frame
	return true


func _release_all() -> void:
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _action_event(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


## Press and release an action as one key tap (for actions handled in _unhandled_input).
func _tap(action: String) -> void:
	_action_event(action, true)
	await _frames(2)
	_action_event(action, false)
	await _frames(1)


func _buttons(root: Node, text: String) -> Array:
	var out := []
	if root == null or not is_instance_valid(root):
		return out
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Control).is_visible_in_tree() and not (b as Button).disabled:
			out.append(b)
	return out


## Click a button with the mouse at its centre; fall back to emitting `pressed` (and say so).
func _click(b: Button) -> void:
	var label := b.text
	if emit_buttons:
		if emit_in_physics:
			await get_tree().physics_frame
		_say("pressing \"%s\" (emit%s)" % [label, " in a physics frame" if emit_in_physics else ""])
		b.pressed.emit()
		await _frames(1)
		return
	var fired := [false]
	var cb := func(): fired[0] = true
	b.pressed.connect(cb, CONNECT_ONE_SHOT)
	var vp := b.get_viewport()
	var pos: Vector2 = vp.get_screen_transform() * b.get_global_transform_with_canvas() * (b.size * 0.5)
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await _frames(1)
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		await _frames(1)
	await _frames(1)
	if fired[0]:
		_say("clicked \"%s\"" % label)
		return
	if is_instance_valid(b):
		if b.pressed.is_connected(cb):
			b.pressed.disconnect(cb)
		_say("the click at %s didn't reach \"%s\" — pressing it directly" % [str(pos.round()), label])
		b.pressed.emit()
		await _frames(1)


## Click the first visible button with this text under `root`; false if there is none.
func _press(root: Node, text: String, index := 0) -> bool:
	var bs := _buttons(root, text)
	if bs.size() <= index:
		return false
	await _click(bs[index])
	return true


## A mouse movement by `rel` (in the game's 1920×1080 canvas pixels, which is what the player's
## look reads), with the pointer at the centre of the screen (the crosshair: nothing in the HUD
## takes the mouse there, so the event reaches the player's look). The event itself is in window
## pixels, so it's scaled by the window's stretch.
func _motion(rel: Vector2) -> void:
	var vp := get_viewport()
	var xf := vp.get_screen_transform()
	var c: Vector2 = xf * (vp.get_visible_rect().size * 0.5)
	var ev := InputEventMouseMotion.new()
	ev.position = c
	ev.global_position = c
	ev.relative = rel * xf.get_scale()
	Input.parse_input_event(ev)


## Turn the view toward a world point with mouse motion, over `frames` frames.
func _look_at(target: Vector3, frames := 12) -> void:
	var pl: Player = Game.player
	var d := target - pl.head.global_position
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
	await _turn(wrapf(want_yaw - pl.yaw, -PI, PI), want_pitch - pl.pitch, frames)


## Turn the view by (dyaw, dpitch) radians with mouse motion, over `frames` frames.
func _turn(dyaw: float, dpitch: float, frames := 12) -> void:
	var pl: Player = Game.player
	var k := float(pl.get("_sens")) * 0.0075
	var sx := -1.0 if bool(pl.get("_inv_x")) else 1.0
	var sy := -1.0 if bool(pl.get("_inv_y")) else 1.0
	var n := maxi(frames, 1)
	for i in range(n):
		_motion(Vector2(-dyaw / k / n * sx, -dpitch / k / n * sy))
		await get_tree().process_frame


## Hold an action for `seconds` of game time.
func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _frames(1)


## One scoop: look down at the snow ahead, hold primary while sweeping the view, release.
func _scoop() -> void:
	var pl: Player = Game.player
	await _turn(0.0, deg_to_rad(-50.0) - pl.pitch, 6)
	Input.action_press("primary")
	var k := float(pl.get("_sens")) * 0.0075
	for i in range(24):
		_motion(Vector2(0.04 * cos(i * 0.26) / k, 0.0))
		await _wait(1.0 / 60.0)
	var got: float = pl.tools.load
	await _turn(0.0, deg_to_rad(5.0) - pl.pitch, 6)
	Input.action_release("primary")
	await _wait(0.6)
	_say("scoop: %.1f L in the hands, released" % (got * 1000.0))


func _scene_is(path: String) -> bool:
	var cs := get_tree().current_scene
	return cs != null and is_instance_valid(cs) and cs.scene_file_path == path


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--play="):
			play_seconds = float(a.substr(7))
		elif a.begins_with("--timeout="):
			timeout_s = float(a.substr(10))
		elif a == "--emit=1":
			emit_buttons = true
		elif a == "--emit=physics":
			emit_buttons = true
			emit_in_physics = true
	_t_start = Time.get_ticks_msec()
	_say("start: mode %s, %.0f s of play, %s (display server %s), buttons %s" % [mode, play_seconds, "headless" if DisplayServer.get_name() == "headless" else "windowed", DisplayServer.get_name(), ("emitted" + (" (physics frame)" if emit_in_physics else "")) if emit_buttons else "clicked"])
	# 1. The main menu.
	_step("main menu")
	var menu_path: String = ProjectSettings.get_setting("application/run/main_scene")
	if not await _until(func(): return _scene_is(menu_path), 60.0, "the main menu"):
		return
	var menu: Node = get_tree().current_scene
	if not await _until(func(): return bool(menu.get("_built")), 120.0, "the menu background"):
		return
	await _wait(2.0)
	# 2. PLAY → mode → New Game.
	_step("PLAY → %s → New Game" % mode)
	if not await _press(menu, "PLAY"):
		_fail("no PLAY button")
		return
	await _frames(3)
	if not await _press(menu, "New Game", 0 if mode == "fun" else 1):
		_fail("no New Game button for %s" % mode)
		return
	await _frames(3)
	if is_instance_valid(menu) and not _buttons(menu, "Start new game").is_empty():
		_say("a %s save exists: confirming the overwrite dialog" % mode)
		await _press(menu, "Start new game")
	if not await _until(func(): return _scene_is("res://scenes/game.tscn") and Game.world != null and Game.player != null, 180.0, "the game scene"):
		return
	var world: Node = Game.world
	var pl: Player = Game.player
	_step("in game")
	await _wait(1.5)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_say("the mouse can't be captured on this display (%s): Game.force_input on, as in the tests" % DisplayServer.get_name())
		Game.force_input = true
	var play_t0 := Clock.minutes
	# 3. A minute of play.
	_step("play: a few steps in the bedroom")
	var p_bed0 := pl.global_position
	await _hold("move_forward", 1.2)
	_say("walked %.2f m in the bedroom (state %s)" % [pl.global_position.distance_to(p_bed0), pl.state])
	_step("play: out of the front door")
	var lot := Layout.player_lot
	var L := HouseBuilder.lot_transform(lot)
	var sb: float = lot["setback"]
	var hall := L * Vector3(-1.5, Layout.PORCH_H + 0.05, sb + 1.1)
	pl.teleport(hall)
	await _frames(2)
	var door: Door = world.get("player_door")
	await _look_at(door.global_position + Vector3(0, 1.0, 0))
	await _frames(3)
	_say("facing the front door: \"%s\"" % pl.focus_prompt)
	if not door.open:
		await _tap("interact")
		await _wait(0.8)
	_say("front door open: %s" % str(door.open))
	await _look_at(L * Vector3(-1.5, Layout.PORCH_H + 1.0, sb - 6.0), 8)
	await _hold("move_forward", 4.0)
	_say("outside: %s, in the house %s, snow here %.2f m" % [Layout.describe_point(Vector2(pl.global_position.x, pl.global_position.z)), str(pl.in_player_house), Snow.depth_at(pl.global_position.x, pl.global_position.z)])
	_step("play: scoops")
	await _scoop()
	await _turn(deg_to_rad(70.0), 0.0, 10)
	await _scoop()
	_step("play: about the yard")
	await _turn(deg_to_rad(-140.0), 0.0, 14)
	await _hold("move_forward", 3.0)
	await _turn(deg_to_rad(160.0), 0.0, 14)
	await _hold("move_forward", 3.0)
	var played := (Clock.minutes - play_t0) / Clock.GAME_MIN_PER_REAL_SEC
	await _wait(maxf(play_seconds - played, 0.0))
	_say("played %.1f s (%.1f game minutes)" % [(Clock.minutes - play_t0) / Clock.GAME_MIN_PER_REAL_SEC, Clock.minutes - play_t0])
	# 4. Sleep through the bed.
	_step("sleep: to the bed")
	pl.teleport(Game.bedroom_spawn())
	await _frames(3)
	var bed: Node3D = world.interior["bed"]
	await _look_at(bed.global_position)
	var steps := 0
	while not pl.focus_prompt.to_lower().contains("sleep") and steps < 12:
		await _hold("move_forward", 0.15)
		await _look_at(bed.global_position, 3)
		steps += 1
	_say("at the bed: \"%s\" (%d steps)" % [pl.focus_prompt, steps])
	if not pl.focus_prompt.to_lower().contains("sleep"):
		_fail("the bed's prompt never showed")
		return
	await _tap("interact")
	if not await _until(func(): return world.get("modal_kind") == "sleep", 20.0, "the sleep prompt"):
		return
	await _frames(5)
	_step("sleep: Sleep until 7:00 a.m.")
	if not await _press(world.get("modal"), "Sleep until 7:00 a.m."):
		_fail("no \"Sleep until 7:00 a.m.\" button")
		return
	if not await _until(func(): return Clock.hour() == 7 and Saves.has_save(mode) and not Game.dirty_since_save and pl.state != "frozen", 300.0, "the wake-up and the autosave"):
		return
	_say("woke at %s, saved" % Clock.format_time(Clock.minutes))
	await _wait(2.5)
	# 5. Back to the menu through the pause menu.
	_step("pause → EXIT TO MAIN MENU")
	await _tap("pause")
	if not await _until(func(): return world.get("modal_kind") == "pause", 20.0, "the pause menu"):
		return
	await _frames(5)
	if not await _press(world.get("modal"), "EXIT TO MAIN MENU"):
		_fail("no EXIT TO MAIN MENU button")
		return
	await _frames(3)
	if is_instance_valid(world) and not _buttons(world.get("hud"), "Exit").is_empty():
		_say("it asks about unsaved progress: confirming")
		await _press(world.get("hud"), "Exit")
	if not await _until(func(): return _scene_is(menu_path), 120.0, "the main menu again"):
		return
	menu = get_tree().current_scene
	if not await _until(func(): return bool(menu.get("_built")), 120.0, "the menu background"):
		return
	await _wait(2.0)
	# 6. EXIT.
	_step("EXIT")
	_release_all()
	_say("pressing EXIT (the menu's get_tree().quit())")
	if not await _press(menu, "EXIT"):
		_fail("no EXIT button")
		return
	await _frames(30)
	_fail("still running after EXIT")
