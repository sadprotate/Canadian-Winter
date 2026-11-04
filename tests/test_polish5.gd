extends RefCounted
## Polish pass 5 tests. Same harness as test_polish3.gd / test_polish4.gd (real game scene, real
## input actions, fixed 60 fps). Each section of the round adds its tests under its own header.

var runner
var world: Node = null

## Save-fixture folders the §0 test plays through. Each holds fun_<point>.json and
## survival_<point>.json saves (tests/make_fixtures.tscn -- --set=polish5). The version-3 set made
## at the end of the round (--set=polish5_v3) is added by listing its folder here.
const FIXTURE_DIRS := [
	"res://tests/fixtures/polish5/",
]


func _tree() -> SceneTree:
	return runner.get_tree()


func _frames(n: int) -> void:
	for i in range(n):
		await _tree().physics_frame


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


## The fixture files in a folder: {point: [fun file, survival file]} (either may be missing).
static func fixture_points(dir_path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var files := Array(dir.get_files())
	files.sort()
	for f in files:
		var name := String(f)
		if not name.ends_with(".json"):
			continue
		for mode in ["fun", "survival"]:
			if name.begins_with(mode + "_"):
				var point := name.trim_prefix(mode + "_").trim_suffix(".json")
				if not out.has(point):
					out[point] = ["", ""]
				(out[point] as Array)[0 if mode == "fun" else 1] = dir_path + name
	return out


# -----------------------------------------------------------------------------
# §0 The polish-5 save fixtures: each loads and plays — move, scoop, sleep (autosave), reload.
# (The polish-3 and polish-4 fixtures are covered by test_polish3 / test_polish4.)
# -----------------------------------------------------------------------------

func test_polish5_fixtures_load_and_play() -> void:
	for dir_path in FIXTURE_DIRS:
		var points := fixture_points(dir_path)
		runner.check(not points.is_empty(), "%s holds save fixtures (%d points)" % [dir_path, points.size()])
		for point in points.keys():
			var pair: Array = points[point]
			runner.check(pair[0] != "" and pair[1] != "", "%s%s: a fixture for both modes" % [dir_path, point])
			for path in pair:
				if path == "":
					continue
				var mode := "survival" if String(path).get_file().begins_with("survival") else "fun"
				var name := String(path).trim_prefix("res://tests/fixtures/")
				var ok: bool = await _load_save_file(path)
				runner.check(ok, "%s loads" % name)
				if not ok:
					continue
				var stage := Game.stage()
				await _spawn_world()
				var pl: Player = world.player
				var road := Layout.lot_to_world(Layout.player_lot, 0.0, -4.0)
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


# =============================================================================
# §1 Project hygiene
# =============================================================================

## The text files the §1 scan reads for references (everything under res:// except hidden
## folders: .godot/, .git/, .github/).
const S1_TEXT_EXT := ["tscn", "tres", "gd", "gdshader", "gdshaderinc", "godot", "cfg", "import", "uid"]


func _s1_files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_s1_files(dir.path_join(sub), out)


## A res:// path resolves when the file (or folder, for a path ending in "/") exists.
func _s1_exists(p: String) -> bool:
	if p.ends_with("/"):
		return DirAccess.dir_exists_absolute(p)
	return FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p)


## Every reference in the project resolves (polish 5 §1): ext_resource paths and uids in scenes
## and resources, every uid:// anywhere, the .uid files beside scripts and shaders, the .import
## files, every res:// path written out in a script, scene, resource or project.godot, every .svg
## reference, and the project icon, which also has to read at 16 px.
func test_s1_project_references_resolve() -> void:
	var files := []
	_s1_files("res://", files)
	var text_files := []
	for f in files:
		if (f as String).get_extension() in S1_TEXT_EXT:
			text_files.append(f)
	runner.check(text_files.size() > 100, "§1 scan: %d text files of %d" % [text_files.size(), files.size()])
	var re_ext := RegEx.create_from_string("\\[ext_resource[^\\]]*\\]")
	var re_path := RegEx.create_from_string("path=\"([^\"]*)\"")
	var re_uid_attr := RegEx.create_from_string("uid=\"(uid://[0-9a-z]+)\"")
	var re_uid := RegEx.create_from_string("uid://[0-9a-z]+")
	var re_res := RegEx.create_from_string("\"\\*?(res://[^\"%]*)\"")
	var re_svg := RegEx.create_from_string("\"([^\"]*\\.svg)\"")
	var bad := []
	var n_ext := 0
	var n_uid := 0
	var n_res := 0
	var n_svg := 0
	for f in text_files:
		var path: String = f
		var t := FileAccess.get_file_as_string(path)
		var ext := path.get_extension()
		# ext_resource: the path exists; a uid, if given, is registered for that same file.
		if ext in ["tscn", "tres"]:
			for m in re_ext.search_all(t):
				n_ext += 1
				var line := m.get_string()
				var pm := re_path.search(line)
				var p := pm.get_string(1) if pm else ""
				if p == "" or not ResourceLoader.exists(p):
					bad.append("%s: ext_resource path %s" % [path, p])
				var um := re_uid_attr.search(line)
				if um:
					var id := ResourceUID.text_to_id(um.get_string(1))
					if not ResourceUID.has_id(id) or ResourceUID.get_id_path(id) != p:
						bad.append("%s: ext_resource %s is %s, not %s" % [path, um.get_string(1), ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else "unregistered", p])
		# Every uid:// is registered and names a file that exists.
		for m in re_uid.search_all(t):
			n_uid += 1
			var id := ResourceUID.text_to_id(m.get_string())
			if not ResourceUID.has_id(id) or not FileAccess.file_exists(ResourceUID.get_id_path(id)):
				bad.append("%s: %s doesn't resolve" % [path, m.get_string()])
		# Every res:// path written out (not a format string) exists.
		if ext in ["tscn", "tres", "gd", "gdshader", "gdshaderinc", "godot", "cfg"]:
			for m in re_res.search_all(t):
				n_res += 1
				if not _s1_exists(m.get_string(1)):
					bad.append("%s: %s is missing" % [path, m.get_string(1)])
			for m in re_svg.search_all(t):
				var s := m.get_string(1)
				if s.begins_with("res://"):
					n_svg += 1
					if not FileAccess.file_exists(s):
						bad.append("%s: %s is missing" % [path, s])
		# A .uid file sits beside its file and is that file's registered uid.
		if ext == "uid":
			var src := path.get_basename()
			var id := ResourceUID.text_to_id(t.strip_edges())
			if not FileAccess.file_exists(src):
				bad.append("%s: orphan (no %s)" % [path, src.get_file()])
			elif not ResourceUID.has_id(id) or ResourceUID.get_id_path(id) != src:
				bad.append("%s: %s is registered for %s" % [path, t.strip_edges(), ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else "nothing"])
		# A .import file sits beside its source and imported.
		if ext == "import":
			if not FileAccess.file_exists(path.get_basename()):
				bad.append("%s: orphan (no %s)" % [path, path.get_basename().get_file()])
			if t.contains("valid=false"):
				bad.append("%s: the import failed" % path)
		# Scripts and shaders carry their uid in a .uid file beside them.
		if ext in ["gd", "gdshader", "gdshaderinc"] and not FileAccess.file_exists(path + ".uid"):
			bad.append("%s: no .uid file" % path)
	runner.check(bad.is_empty(), "§1 every reference resolves: %d ext_resource, %d uid://, %d res:// paths, %d .svg %s" % [n_ext, n_uid, n_res, n_svg, str(bad)])
	runner.check(n_ext > 40 and n_uid > 80 and n_res > 30 and n_svg >= 1, "§1 the scan found the references (%d / %d / %d / %d)" % [n_ext, n_uid, n_res, n_svg])
	# The main scene and the project icon.
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	runner.check(main_scene != "" and ResourceLoader.exists(main_scene), "§1 the main scene exists (%s)" % main_scene)
	var icon: String = ProjectSettings.get_setting("application/config/icon", "")
	runner.check(icon.ends_with(".svg") and FileAccess.file_exists(icon), "§1 the project icon exists (%s)" % icon)
	runner.check(ResourceLoader.exists(icon) and load(icon) is Texture2D, "§1 the icon is imported as a texture")
	var svg := FileAccess.get_file_as_string(icon)
	runner.check(svg.contains("Generated by tools/icon/gen_icon.py") and FileAccess.file_exists("res://tools/icon/gen_icon.py"), "§1 the icon is written by tools/icon/gen_icon.py")
	runner.check(not svg.contains("<image") and not svg.contains("data:"), "§1 the icon is vector only (no embedded raster)")
	var big := Image.new()
	var err := big.load_svg_from_string(svg, 1.0)
	runner.check(err == OK and big.get_width() >= 128 and big.get_width() == big.get_height(), "§1 the icon loads as SVG (%d, %dx%d)" % [err, big.get_width(), big.get_height()])
	# At 16 px: transparent rounded corners, and the white snow and the orange window still show.
	var small := Image.new()
	small.load_svg_from_string(svg, 16.0 / maxf(big.get_width(), 1.0))
	var whites := 0
	var oranges := 0
	for y in range(small.get_height()):
		for x in range(small.get_width()):
			var c := small.get_pixel(x, y)
			if c.a > 0.9 and c.r > 0.85 and c.g > 0.85 and c.b > 0.85:
				whites += 1
			if c.a > 0.9 and c.r > 0.8 and c.g > 0.4 and c.g < 0.8 and c.b < 0.5:
				oranges += 1
	runner.check(small.get_width() == 16 and small.get_pixel(0, 0).a < 0.5 and small.get_pixel(8, 8).a > 0.99, "§1 at 16 px: a rounded tile (corner alpha %.2f)" % small.get_pixel(0, 0).a)
	runner.check(whites >= 10 and oranges >= 2, "§1 at 16 px the snow and the lit window still read (%d white, %d orange px)" % [whites, oranges])


# =============================================================================
# §2 Controls
# =============================================================================

## A real key or mouse-button event for an action's current binding (what the keyboard or the
## mouse would send), so the tests go through the input map.
func _s2_event(action: String, down: bool) -> InputEvent:
	var lst: Array = Settings.bindings.get(action, [])
	if lst.is_empty():
		return null
	var e := Settings.decode(String(lst[0]))
	if e is InputEventKey:
		(e as InputEventKey).keycode = (e as InputEventKey).physical_keycode
		(e as InputEventKey).pressed = down
	elif e is InputEventMouseButton:
		(e as InputEventMouseButton).pressed = down
	return e


## Press and release an action's bound key / button.
func _s2_key(action: String) -> void:
	var d := _s2_event(action, true)
	if d == null:
		return
	Input.parse_input_event(d)
	await _frames(2)
	Input.parse_input_event(_s2_event(action, false))
	await _frames(2)


## The settings file as it is (or null), to put back after a test that writes it.
func _s2_backup() -> Variant:
	if not FileAccess.file_exists(Settings.PATH):
		return null
	return FileAccess.get_file_as_bytes(Settings.PATH)


func _s2_restore(saved: Variant) -> void:
	if saved == null:
		if FileAccess.file_exists(Settings.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()
	Settings.load_controls()


## A settings file as the game wrote it before polish 5: every action bound (the old game saves
## them all), drop on Q, use_pouch on G, no store action, no [meta] section; `custom` overrides.
func _s2_old_cfg(custom: Dictionary) -> ConfigFile:
	var c := ConfigFile.new()
	c.set_value("audio", "music", 0.6)
	for a in Settings.ACTIONS.keys():
		if a == "store":
			continue
		var codes: Array = (Settings.ACTIONS[a][2] as Array).duplicate()
		if a == "drop":
			codes = ["key:%d" % KEY_Q]
		elif a == "use_pouch":
			codes = ["key:%d" % KEY_G]
		c.set_value("controls", a, custom.get(a, codes))
	return c


func _s2_k(k: int) -> Array:
	return ["key:%d" % k]


## The new defaults (Decision 2): drop G, store F, use_pouch H, interact E — in the defaults, the
## live bindings and the engine's input map; Q is left free.
func test_s2_key_defaults() -> void:
	Settings.restore_default_controls()
	var want := {"drop": KEY_G, "store": KEY_F, "use_pouch": KEY_H, "interact": KEY_E}
	for a in want.keys():
		runner.check(Settings.ACTIONS.has(a) and Settings.ACTIONS[a][2] == _s2_k(want[a]), "§2 default %s = %s" % [a, OS.get_keycode_string(want[a])])
		runner.check(Settings.bindings[a] == _s2_k(want[a]), "§2 %s is bound to %s" % [a, OS.get_keycode_string(want[a])])
		runner.check(Settings.action_label(a) == OS.get_keycode_string(want[a]), "§2 %s shows as %s (%s)" % [a, OS.get_keycode_string(want[a]), Settings.action_label(a)])
		var ev := InputEventKey.new()
		ev.physical_keycode = want[a]
		runner.check(InputMap.has_action(a) and InputMap.event_is_action(ev, a, true), "§2 the input map sends %s to %s" % [OS.get_keycode_string(want[a]), a])
	runner.check(Settings.ACTIONS["store"][1] == "foot", "§2 store is an on-foot action")
	var q_users := []
	for a in Settings.bindings.keys():
		if "key:%d" % KEY_Q in Settings.bindings[a]:
			q_users.append(a)
	runner.check(q_users.is_empty(), "§2 Q is no longer bound to anything (%s)" % str(q_users))
	runner.check("store" in Settings.RATE_LIMITED and Catalog.balance.input_max_presses_per_s > 0.0, "§2 store is a capped press (for the rack, §15)")


## user://settings.cfg from before polish 5: bindings still at an old default move, the player's own
## bindings stay, a move that would collide with a player's binding doesn't happen (the moved action
## keeps its old key), a version-2 file isn't migrated again, and Reset gives the new defaults.
func test_s2_settings_migration() -> void:
	var G := _s2_k(KEY_G)
	var Q := _s2_k(KEY_Q)
	var H := _s2_k(KEY_H)
	var F := _s2_k(KEY_F)
	# Everything at the old defaults (a player who never rebound anything).
	var b: Dictionary = Settings.controls_from(_s2_old_cfg({}))
	runner.check(b["drop"] == G and b["use_pouch"] == H and b["store"] == F and b["interact"] == _s2_k(KEY_E), "§2 old defaults migrate: drop %s, use_pouch %s, store %s" % [b["drop"], b["use_pouch"], b["store"]])
	var others_same := true
	for a in Settings.ACTIONS.keys():
		if a not in ["drop", "use_pouch", "store"] and b[a] != Settings.ACTIONS[a][2]:
			others_same = false
	runner.check(others_same, "§2 …and every other binding is unchanged")
	# A custom binding is kept; the other moves.
	b = Settings.controls_from(_s2_old_cfg({"drop": _s2_k(KEY_K)}))
	runner.check(b["drop"] == _s2_k(KEY_K) and b["use_pouch"] == H and b["store"] == F, "§2 a custom drop (K) stays, use_pouch still moves to H")
	b = Settings.controls_from(_s2_old_cfg({"use_pouch": _s2_k(KEY_P)}))
	runner.check(b["use_pouch"] == _s2_k(KEY_P) and b["drop"] == G, "§2 a custom use_pouch (P) stays, drop moves to the freed G")
	# Collisions: the custom binding wins, the moved action keeps its old key.
	b = Settings.controls_from(_s2_old_cfg({"jump": H}))
	runner.check(b["jump"] == H and b["use_pouch"] == G and b["drop"] == Q, "§2 collision: jump on H (custom) keeps H; use_pouch keeps G, so drop keeps Q (%s / %s / %s)" % [b["jump"], b["use_pouch"], b["drop"]])
	b = Settings.controls_from(_s2_old_cfg({"use_pouch": _s2_k(KEY_P), "sprint": G}))
	runner.check(b["sprint"] == G and b["use_pouch"] == _s2_k(KEY_P) and b["drop"] == Q, "§2 collision: sprint on G (custom) keeps G, drop keeps Q")
	b = Settings.controls_from(_s2_old_cfg({"crouch": F}))
	runner.check(b["crouch"] == F and b["store"].is_empty() and b["drop"] == G and b["use_pouch"] == H, "§2 collision: crouch on F (custom) keeps F; the new store action starts unbound")
	var c_un := ConfigFile.new()
	for a in b.keys():
		c_un.set_value("controls", a, b[a])
	c_un.set_value("meta", "controls_version", Settings.CONTROLS_VERSION)
	var b2: Dictionary = Settings.controls_from(c_un)
	runner.check(b2["store"].is_empty() and b2["crouch"] == F, "§2 …and saved that way it stays unbound (no F conflict on the next start)")
	# A binding in another context doesn't block a move (the horn is on H in vehicles only).
	runner.check(Settings.ACTIONS["veh_horn"][2] == H and Settings.controls_from(_s2_old_cfg({}))["use_pouch"] == H, "§2 the vehicle horn on H doesn't block use_pouch (different context)")
	# A file already at version 2 isn't migrated again: Q chosen after the move stays.
	var c2 := _s2_old_cfg({})
	c2.set_value("meta", "controls_version", Settings.CONTROLS_VERSION)
	c2.set_value("controls", "store", F)
	b = Settings.controls_from(c2)
	runner.check(b["drop"] == Q and b["use_pouch"] == G, "§2 a version-%d file keeps drop on Q / use_pouch on G (the player's choice)" % Settings.CONTROLS_VERSION)
	# No file: the new defaults.
	b = Settings.controls_from(ConfigFile.new())
	runner.check(b["drop"] == G and b["use_pouch"] == H and b["store"] == F, "§2 no settings file: the new defaults")
	# The real file: write an old one, load it as the game does at start, read back what was saved.
	var saved: Variant = _s2_backup()
	var old := _s2_old_cfg({"jump": _s2_k(KEY_J)})
	old.save(Settings.PATH)
	Settings.load_controls()
	runner.check(Settings.bindings["drop"] == G and Settings.bindings["use_pouch"] == H and Settings.bindings["store"] == F and Settings.bindings["jump"] == _s2_k(KEY_J), "§2 user://settings.cfg migrates on load (custom jump on J kept)")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	runner.check(InputMap.event_is_action(ev, "drop", true), "§2 …and G drops in the input map")
	var back := ConfigFile.new()
	runner.check(back.load(Settings.PATH) == OK and int(back.get_value("meta", "controls_version", 1)) == Settings.CONTROLS_VERSION and back.get_value("controls", "drop") == G and back.get_value("controls", "store") == F and back.get_value("audio", "music") == 0.6, "§2 …and the migrated file is written back (version %d, other settings kept)" % int(back.get_value("meta", "controls_version", 1)))
	Settings.load_controls()
	runner.check(Settings.bindings["drop"] == G and Settings.bindings["jump"] == _s2_k(KEY_J), "§2 …and loading it again changes nothing")
	# Reset to defaults gives the new defaults.
	var e := InputEventKey.new()
	e.physical_keycode = KEY_K
	Settings.rebind("drop", e)
	e.physical_keycode = KEY_P
	Settings.rebind("use_pouch", e)
	e.physical_keycode = KEY_O
	Settings.rebind("store", e)
	runner.check(Settings.bindings["drop"] == _s2_k(KEY_K) and Settings.bindings["store"] == _s2_k(KEY_O), "§2 drop / store rebind")
	Settings.restore_default_controls()
	var all_default := true
	for a in Settings.ACTIONS.keys():
		if Settings.bindings[a] != Settings.ACTIONS[a][2]:
			all_default = false
	runner.check(all_default and Settings.bindings["drop"] == G and Settings.bindings["store"] == F and Settings.bindings["use_pouch"] == H, "§2 Reset to defaults gives the new defaults")
	back.load(Settings.PATH)
	runner.check(back.get_value("controls", "drop") == G and back.get_value("controls", "use_pouch") == H, "§2 …and saves them")
	_s2_restore(saved)
	Settings.restore_default_controls()


## The conflict check in every place (on foot, in a vehicle, at a walk-behind machine, at the
## computer, in menus), then the keys themselves: on foot H uses a pouch, G drops, F does nothing
## yet; at the computer and in the pause menu none of them does anything; in a vehicle H is the
## horn, not a pouch.
func test_s2_no_conflict_in_any_context() -> void:
	Settings.restore_default_controls()
	for place in Settings.PLACES:
		var live := Settings.live_actions(place)
		var c: Array = Settings.conflicts(place)
		runner.check(not live.is_empty() and c.is_empty(), "§2 no conflict %s (%d actions live) %s" % [place, live.size(), str(c)])
	for a in ["drop", "store", "use_pouch", "interact"]:
		runner.check(Settings.holder(Settings.bindings, a, Settings.bindings[a][0]) == "", "§2 the rebinding rule finds nothing else on %s's key" % a)
	runner.check("drop" in Settings.live_actions("foot") and not ("drop" in Settings.live_actions("vehicle")) and not ("use_pouch" in Settings.live_actions("machine")), "§2 the places hold what's read there")
	# The keys in the game, as real key events.
	Game.force_input = true
	Game.new_game("survival", 2024)
	Clock.reset(Clock.at(0, 11.0))
	Game.flags["computer_unlocked"] = true
	Game.flags["truck_keys"] = true
	await _spawn_world()
	var pl: Player = world.player
	var lot := Layout.player_lot
	var spot := Layout.lot_to_world(lot, Layout.gu(lot, -5.0), 4.0)
	Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), 0.0)
	pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
	Game.slots = ["standard_shovel", "", "", ""]
	Game.selected = 0
	Game.heat_pouches = 3
	await _frames(4)
	var items0 := Game.items.size()
	pl.tools.hint = ""
	var n0 := Notify.history.size()
	var prompt0 := pl.focus_prompt
	await _s2_key("store")
	await _frames(2)
	runner.check(Game.slots[0] == "standard_shovel" and Game.items.size() == items0 and Notify.history.size() == n0 and pl.tools.hint == "" and pl.focus_prompt == prompt0, "§2 on foot: F (store) does nothing and shows nothing yet (hint '%s', %d new notifications)" % [pl.tools.hint, Notify.history.size() - n0])
	await _s2_key("use_pouch")
	runner.check(Game.heat_pouches == 2, "§2 on foot: H uses a heating pouch (%d left)" % Game.heat_pouches)
	# The computer: every key of the player's is UI only there.
	world.open_computer()
	await _frames(2)
	runner.check(world.modal_kind == "computer", "§2 the computer is open")
	for a in ["drop", "store", "use_pouch", "interact", "tool_angle", "slot_2", "map", "camera_toggle"]:
		await _s2_key(a)
	runner.check(Game.slots[0] == "standard_shovel" and Game.selected == 0 and Game.heat_pouches == 2 and Game.items.size() == items0 and world.modal_kind == "computer" and not pl.third_person, "§2 at the computer: G, F, H, E, R, 2, M and V change nothing")
	await _s2_key("pause")
	runner.check(world.modal == null, "§2 Esc closes the computer")
	# The pause menu (the tree is paused).
	world._open_pause()
	await _frames(2)
	for a in ["drop", "store", "use_pouch", "interact"]:
		await _s2_key(a)
	runner.check(Game.slots[0] == "standard_shovel" and Game.heat_pouches == 2 and world.modal_kind == "pause", "§2 in the pause menu: G, F, H and E change nothing")
	await _tree().process_frame   # unpause from a process frame (HANDOFF §13 item 12)
	world.close_modal()
	await _tree().process_frame
	await _frames(2)
	# On foot again: G drops.
	await _s2_key("drop")
	await _frames(2)
	runner.check(Game.slots[0] == "" and Game.items.size() == items0 + 1, "§2 on foot: G drops the shovel")
	# In the truck: H is the horn, G does nothing, E gets out.
	var truck: Vehicle = world.vehicle_nodes()[0]
	truck.enter_vehicle(pl)
	await _frames(3)
	var items1 := Game.items.size()
	await _s2_key("use_pouch")
	await _s2_key("drop")
	await _s2_key("store")
	runner.check(pl.state == "vehicle" and Game.heat_pouches == 2 and Game.items.size() == items1, "§2 in the truck: H (the horn), G and F use no pouch and drop nothing")
	await _s2_key("interact")
	await _frames(3)
	runner.check(pl.state == "foot", "§2 in the truck: E gets out")
	_release_all()
	await _unload()


## The auto-clicker against the cap (polish 5 §2), with the real controls and bare hands on the
## player's path box (tests/click_bench.gd): at 20 and 50 presses/s no more presses register than
## the cap allows and no more snow comes off the box than clicking at the cap rate; without the cap
## 20/s would be far ahead. The hold-and-sweep bot's rate is measured alongside and reported: each
## press still opens with an in-place bite (how a scoop starts its cut, left as it is), so clicking
## at the cap rate stays ahead of sweeping (see docs/polish5/report/s2.md).
func test_s2_autoclick_capped() -> void:
	var bench: Node = load("res://tests/click_bench.gd").new()
	runner.add_child(bench)
	await bench.setup(runner)
	world = bench.world
	var cap: float = Catalog.balance.input_max_presses_per_s
	var secs := 20.0
	var sw: Dictionary = await bench.run_sweep(secs)
	var at_cap: Dictionary = await bench.run_click_primary(cap, secs)
	var r_sw: float = sw["removed"] / sw["secs"]
	var r_cap: float = at_cap["removed"] / at_cap["secs"]
	runner.info("hold + sweep: %.4f m3/s; clicking at the cap (%.0f/s): %.4f m3/s, %.1f registered/s, %.1f L per press" % [r_sw, cap, r_cap, at_cap["registered"] / at_cap["secs"], at_cap["moved"] / maxf(at_cap["registered"], 1) * 1000.0])
	for rate in [20.0, 50.0]:
		var d: Dictionary = await bench.run_click_primary(rate, secs)
		var r: float = d["removed"] / d["secs"]
		runner.info("clicking at %.0f/s: %.4f m3/s (x%.2f the cap rate, x%.2f hold + sweep), %d sent, %d registered" % [rate, r, r / maxf(r_cap, 1e-6), r / maxf(r_sw, 1e-6), d["sent"], d["registered"]])
		runner.check(float(d["registered"]) <= cap * d["secs"] + 1.0, "§2 clicking LMB at %.0f/s: at most %.0f presses register per second (%d in %.1f s)" % [rate, cap, d["registered"], d["secs"]])
		runner.check(r <= r_cap * 1.12 + 0.002, "§2 clicking LMB at %.0f/s removes no more snow per second than clicking at the cap rate (%.4f vs %.4f m3/s)" % [rate, r, r_cap])
		runner.check(d["throws"] == d["registered"], "§2 …one throw per registered press, none per ignored one (%d / %d)" % [d["throws"], d["registered"]])
	# The cap is what holds it: without it, 20/s registers and removes far more.
	Catalog.balance.input_max_presses_per_s = 0.0
	var free20: Dictionary = await bench.run_click_primary(20.0, secs)
	Catalog.balance.input_max_presses_per_s = cap
	var r_free: float = free20["removed"] / free20["secs"]
	runner.info("without the cap, clicking at 20/s: %.4f m3/s, %d registered" % [r_free, free20["registered"]])
	runner.check(r_free > r_cap * 1.4 and float(free20["registered"]) > cap * free20["secs"] * 1.3, "§2 without the cap, 20/s would remove %.1fx as much" % (r_free / maxf(r_cap, 1e-6)))
	# RMB: pushing gives no per-press gain; capped presses don't push more than holding.
	var hold_push: Dictionary = await bench.run_push(0.0, 8.0)
	var tap_push: Dictionary = await bench.run_push(50.0, 8.0)
	runner.check(tap_push["registered"] <= cap * 8.0 + 1 and tap_push["moved"] <= hold_push["moved"] * 1.05 + 0.002, "§2 clicking RMB at 50/s: %d presses register, pushes %.3f m3 (holding: %.3f)" % [tap_push["registered"], tap_push["moved"], hold_push["moved"]])
	_release_all()
	await _unload()
	bench.queue_free()


## 100 presses of G with a tool in hand (and a load of snow in it), at 20 and 50 a second, and
## E/G bursts that arrive several to a frame (a slow frame), never duplicate or lose a tool, a
## carried item or any snow.
func test_s2_drop_presses_lose_and_duplicate_nothing() -> void:
	var bench: Node = load("res://tests/click_bench.gd").new()
	runner.add_child(bench)
	await bench.setup(runner)
	world = bench.world
	for rate in [20.0, 50.0]:
		var g: Dictionary = await bench.run_tool_presses("drop", rate, 100)
		runner.check(g["tools0"] == g["tools1"] and g["slots"] == 0 and g["changes"] == 1, "§2 100 x G at %.0f/s with a shovel in hand: dropped once, tools %d -> %d" % [rate, g["tools0"], g["tools1"]])
	for frames in [1, 3]:
		bench.batch_frames = frames
		var eg: Dictionary = await bench.run_tool_presses("both", 50.0, 100)
		runner.check(eg["tools0"] == eg["tools1"] and eg["slots"] + eg["ground"] == eg["tools1"], "§2 100 x E and G alternating at 50/s, %d frame(s) per batch of events: tools %d -> %d" % [frames, eg["tools0"], eg["tools1"]])
		var e: Dictionary = await bench.run_tool_presses("interact", 50.0, 100)
		runner.check(e["tools0"] == e["tools1"] and e["slots"] == 1, "§2 100 x E at 50/s at a shovel, %d frame(s) per batch: picked up once, tools %d -> %d" % [frames, e["tools0"], e["tools1"]])
	bench.batch_frames = 1
	# A load in the shovel and a carried item: G at 50/s drops the carried item, then the shovel
	# (its load falls at your feet), then nothing; every tool and every litre of snow accounted for.
	await bench.reset()
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var lot := Layout.player_lot
	var spot := Layout.lot_to_world(lot, Layout.gu(lot, -5.0), 4.0)
	pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
	Game.slots = ["standard_shovel", "small_shovel", "wide_pusher", "snow_scraper"]
	Game.selected = 0
	await _frames(4)
	pl.pitch = deg_to_rad(-50.0)
	pl.head.rotation.x = pl.pitch
	Input.action_press("primary")
	var base := pl.yaw
	for k in range(25):
		pl.set_yaw(base + 0.4 * sin(k * 0.2))
		await _tree().physics_frame
	var load0 := tc.load
	Game.carried = "large_scraper"
	Game.inventory_changed.emit()
	await _frames(2)
	var c0: Dictionary = bench.tool_count()
	var v0 := Snow.total_volume() + tc.load
	var st := {"next": 0.0, "sent": 0}
	var t := 0.0
	while int(st["sent"]) < 100:
		bench._clicker("drop", 50.0, t, st)
		await _tree().physics_frame
		t += 1.0 / 60.0
	await _frames(10)
	# Measured with LMB still held (the bare hands go on scooping; nothing is thrown).
	var c1: Dictionary = bench.tool_count()
	var v1 := Snow.total_volume() + tc.load
	runner.check(load0 > 0.005, "§2 the shovel held a load before G (%.1f L)" % (load0 * 1000.0))
	runner.check(c0["total"] == c1["total"] and Game.carried == "" and Game.slots[0] == "" and Game.slots[1] == "small_shovel" and c1["ground"] == c0["ground"] + 2, "§2 100 x G at 50/s: the carried item, then the shovel, dropped once each; tools %d -> %d" % [c0["total"], c1["total"]])
	runner.near(v1, v0, 1e-4, "§2 …and the load fell at your feet, volume conserved")
	Input.action_release("primary")
	bench._release_inputs()
	await _frames(30)
	_release_all()
	await _unload()
	bench.queue_free()


## A human tapping at 5 a second: every press registers (LMB scoops and throws on each tap, RMB
## pushes, E and G alternate), and holding is never cut short by the cap.
func test_s2_tapping_5_per_s_works() -> void:
	var bench: Node = load("res://tests/click_bench.gd").new()
	runner.add_child(bench)
	await bench.setup(runner)
	world = bench.world
	var d: Dictionary = await bench.run_click_primary(5.0, 8.0)
	runner.check(d["sent"] >= 25 and d["registered"] == d["sent"] and d["throws"] == d["registered"], "§2 LMB tapped at 5/s: every tap registers and throws (%d sent, %d registered, %d throws)" % [d["sent"], d["registered"], d["throws"]])
	runner.check(d["moved"] / maxf(d["registered"], 1) > 0.004, "§2 …and every tap scoops (%.1f L per tap)" % (d["moved"] / maxf(d["registered"], 1) * 1000.0))
	var p: Dictionary = await bench.run_push(5.0, 4.0)
	runner.check(p["registered"] == p["sent"] and p["sent"] >= 19, "§2 RMB tapped at 5/s: every tap pushes (%d / %d)" % [p["registered"], p["sent"]])
	var eg: Dictionary = await bench.run_tool_presses("both", 5.0, 20)
	runner.check(eg["changes"] >= 39 and eg["tools0"] == eg["tools1"], "§2 E and G tapped at 5/s each: every press picks up or drops (%d changes)" % eg["changes"])
	# Holding: after a burst that used up the second's presses, a held press keeps working.
	await bench.reset()
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var cap := int(Catalog.balance.input_max_presses_per_s)
	var lot := Layout.player_lot
	var spot := Layout.lot_to_world(lot, Layout.gu(lot, -5.0), 4.0)
	pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
	await _frames(70)
	pl.pitch = deg_to_rad(-50.0)
	pl.head.rotation.x = pl.pitch
	Input.action_press("secondary")
	var pushed := 0
	for k in range(180):
		await _tree().physics_frame
		if tc.pushing:
			pushed += 1
	Input.action_release("secondary")
	runner.check(pushed >= 178, "§2 RMB held for 3 s pushes every frame (%d / 180)" % pushed)
	await _frames(70)
	for k in range(cap):
		Input.action_press("primary")
		await _frames(2)
		Input.action_release("primary")
		await _frames(2)
	await _frames(4)
	Input.action_press("primary")
	await _frames(3)
	runner.check(not tc.filling, "§2 a press beyond %d in a second is ignored (no scoop)" % cap)
	Input.action_release("primary")
	await _frames(60)
	Input.action_press("primary")
	var filled := 0
	var base := pl.yaw
	for k in range(120):
		pl.set_yaw(base + 0.4 * sin(k * 0.2))
		await _tree().physics_frame
		if tc.filling:
			filled += 1
	runner.check(filled == 120 and tc.load > 0.005, "§2 LMB held for 2 s a second later scoops the whole time (%d / 120 frames, %.1f L)" % [filled, tc.load * 1000.0])
	Input.action_release("primary")
	_release_all()
	await _frames(30)
	await _unload()
	bench.queue_free()


## Every key the game shows is read from the input map: rebind them and the Help app, the tool
## reminder, Tab, the HUD, a prompt, the store's descriptions and the computer's Close button all
## show the new keys. And no player-facing string in the scripts or data names a key itself.
func test_s2_keys_shown_from_input_map() -> void:
	Settings.restore_default_controls()
	var rb := {"drop": KEY_K, "use_pouch": KEY_P, "interact": KEY_U, "tool_angle": KEY_Y, "veh_aim_left": KEY_N, "veh_aim_right": KEY_B, "pause": KEY_BACKSPACE}
	for a in rb.keys():
		var e := InputEventKey.new()
		e.physical_keycode = rb[a]
		runner.check(Settings.rebind(a, e) == "", "§2 rebind %s to %s" % [a, OS.get_keycode_string(rb[a])])
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_MIDDLE
	runner.check(Settings.rebind("primary", m) == "", "§2 rebind primary to the middle mouse button")
	var help := "\n".join(HelpText.lines(true))
	runner.check(help.contains("HOLD Middle Mouse") and help.contains("blade with Y") and not help.contains("left mouse"), "§2 the Help app shows the bound scoop and blade keys")
	var hint := ToolController.controls_hint(Catalog.tool(&"snow_scraper"))
	runner.check(hint.contains("Middle Mouse") and hint.contains("Y: angle"), "§2 the tool reminder shows the bound keys (%s)" % hint)
	var descs := []
	for t in Catalog.store_tools():
		descs.append(Settings.with_keys((t as ToolData).description))
	for v in Catalog.store_vehicles():
		descs.append(Settings.with_keys((v as VehicleData).description))
	for k in Catalog.UTILITY.keys():
		descs.append(Settings.with_keys(Catalog.UTILITY[k]["desc"]))
	var all_d := "\n".join(descs)
	runner.check(not all_d.contains("{") and all_d.contains("Y angles") and all_d.contains("Press P to use") and all_d.contains("N/B") and all_d.contains("Grab it with U, hold Middle Mouse"), "§2 the store's descriptions show the bound keys")
	Game.force_input = true
	Game.new_game("survival", 2024)
	Clock.reset(Clock.at(0, 11.0))
	Game.flags["computer_unlocked"] = true
	await _spawn_world()
	var pl: Player = world.player
	Game.heat_pouches = 2
	Game.slots = ["", "", "", ""]
	Game.carried = "wide_pusher"
	Game.inventory_changed.emit()
	await _frames(30)
	runner.check(world.hud.tool_name_l.text.contains("(K to drop)") and world.hud.pouch_l.text.contains("(P)"), "§2 the HUD shows K to drop and the pouch key P (%s / %s)" % [world.hud.tool_name_l.text, world.hud.pouch_l.text])
	var inv: Control = Panels.inventory(world.hud)
	var inv_text := _s2_texts(inv)
	inv.queue_free()
	runner.check(inv_text.contains("(K to drop)") and inv_text.contains("(P to use)"), "§2 Tab shows K to drop and P for a pouch")
	Game.carried = ""
	Game.inventory_changed.emit()
	# A prompt: look at a tool on the ground.
	var lot := Layout.player_lot
	var spot := Layout.lot_to_world(lot, Layout.gu(lot, -5.0), 4.0)
	Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), 0.0)
	world.spawn_tool_item("standard_shovel", Vector3(spot.x, 0, spot.y - 0.8), 0.0)
	pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
	pl.pitch = deg_to_rad(-40.0)
	pl.head.rotation.x = pl.pitch
	await _frames(4)
	runner.check(pl.focus_prompt.begins_with("[U] "), "§2 a prompt shows the bound interact key (%s)" % pl.focus_prompt)
	world.open_computer()
	await _frames(2)
	runner.check(world.modal != null and _s2_texts(world.modal).contains("Close  (Backspace)"), "§2 the computer's Close button shows the bound pause key")
	world.close_modal()
	await _frames(2)
	await _unload()
	Settings.restore_default_controls()
	# No player-facing string names a key itself (comments, settings.gd's own key names and the
	# "[E]" prompts, which are rewritten with the bound key when shown, aside).
	var pats := [RegEx.create_from_string("(?i)\\b(left|right|middle)[ -](mouse|click)\\b"), RegEx.create_from_string("\\b(LMB|RMB|WASD)\\b"),
		RegEx.create_from_string("\\((?:[A-Z]|Esc|Tab|F1)\\)"), RegEx.create_from_string("\\b[A-Z] ?/ ?[A-Z]\\b"),
		RegEx.create_from_string("\\b(?:[Pp]ress|[Hh]old|[Tt]ap|with) [A-Z]\\b(?!['’])"), RegEx.create_from_string("\\b[A-Z] (?:to|or) [a-zA-Z]"), RegEx.create_from_string("\\b[A-Z] (?:angles?|turns?|drops?|uses?)\\b"),
		RegEx.create_from_string("\\b(?:Esc|Tab|F1) (?:to|or)\\b")]
	var str_re := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")
	var bad := []
	var files := []
	_s1_files("res://scripts", files)
	_s1_files("res://data", files)
	for path in files:
		if not (String(path).ends_with(".gd") or String(path).ends_with(".tres")) or String(path).ends_with("settings.gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			if line.strip_edges().begins_with("#"):
				continue
			for mt in str_re.search_all(line):
				var s := mt.get_string()
				for re in pats:
					if (re as RegEx).search(s):
						bad.append("%s:%d %s" % [String(path).get_file(), n, s.left(80)])
						break
	runner.check(bad.is_empty(), "§2 no hard-coded key names in player-facing strings %s" % str(bad))


## All the text in a UI tree (labels and buttons).
func _s2_texts(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	elif n is RichTextLabel:
		out += (n as RichTextLabel).text + "\n"
	for c in n.get_children():
		out += _s2_texts(c)
	return out
