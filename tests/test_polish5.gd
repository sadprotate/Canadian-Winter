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


# =============================================================================
# §3 The house, and where snow can go
# =============================================================================

const S3_HAND_TOOLS := ["", "small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh", "electric_shovel"]
const S3_BLOWERS := ["small_blower", "large_blower"]


## A game on Dec 2 at noon with the tutorial done (Gerry is home, out of the way), the clock stopped
## and every chunk's snowfall applied, so the snow changes only when something moves it.
func _s3_world(mode := "fun") -> void:
	await _unload()
	Game.force_input = true
	Game.new_game(mode, 2024)
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	Clock.reset(Clock.at(1, 12.0))
	await _spawn_world()
	Clock.running = false
	Snow.sync_all()
	Snow.relax_until_stable()


## A point of a house's frame (HouseBuilder: x along the street, z inward, y up) in the world.
static func _s3_h(lot: Dictionary, x: float, y: float, z: float) -> Vector3:
	return HouseBuilder.lot_transform(lot) * Vector3(x, y, z)


## A house-frame direction in the world (XZ, normalized).
static func _s3_dir(lot: Dictionary, x: float, z: float) -> Vector2:
	var d := HouseBuilder.lot_transform(lot).basis * Vector3(x, 0, z)
	return Vector2(d.x, d.z).normalized()


## The world rect of a house-frame rect (x0..x1, z0..z1).
static func _s3_rect(lot: Dictionary, xa: float, xb: float, za: float, zb: float) -> Rect2:
	return HouseBuilder._world_rect(HouseBuilder.lot_transform(lot), xa, xb, za, zb)


## The yaw that faces a world XZ direction.
static func _s3_yaw(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


## Put the player at `at` (world) looking at `look`.
func _s3_stand(at: Vector3, look: Vector3, pitch_deg := INF) -> void:
	var pl: Player = world.player
	pl.teleport(at + Vector3(0, 0.05, 0))
	var d := Vector2(look.x - at.x, look.z - at.z)
	pl.set_yaw(_s3_yaw(d))
	var eye_y := at.y + Player.HEAD_H
	pl.pitch = deg_to_rad(pitch_deg) if pitch_deg < INF else atan2(look.y - eye_y, d.length())
	pl.head.rotation.x = pl.pitch


## Snapshot of the depths in a world rect (to diff against).
static func _s3_snap(r: Rect2) -> Dictionary:
	var x0 := Snow.cell_x(r.position.x)
	var z0 := Snow.cell_z(r.position.y)
	var x1 := Snow.cell_x(r.end.x)
	var z1 := Snow.cell_z(r.end.y)
	var d := PackedFloat32Array()
	d.resize((x1 - x0 + 1) * (z1 - z0 + 1))
	var k := 0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			d[k] = Snow.depth[z * Snow.W + x]
			k += 1
	return {"x0": x0, "z0": z0, "x1": x1, "z1": z1, "d": d}


## What changed since a snapshot (m3): the net change, the snow added (with its centroid, the part
## added inside a building and on the street) and the snow removed.
static func _s3_diff(s: Dictionary) -> Dictionary:
	var d: PackedFloat32Array = s["d"]
	var k := 0
	var net := 0.0
	var added := 0.0
	var removed := 0.0
	var inside := 0.0
	var road := 0.0
	var c := Vector2.ZERO
	for z in range(int(s["z0"]), int(s["z1"]) + 1):
		for x in range(int(s["x0"]), int(s["x1"]) + 1):
			var i := z * Snow.W + x
			var dd := float(Snow.depth[i]) - float(d[k])
			k += 1
			if dd == 0.0:
				continue
			net += dd
			if dd > 0.0:
				var p := Vector2((x + 0.5) * Snow.CELL, (z + 0.5) * Snow.CELL)
				added += dd
				c += p * dd
				if Snow.surf[i] == Snow.S_BLOCKED:
					inside += dd
				if Snow.surf[i] == Snow.S_ROAD:
					road += dd
			else:
				removed -= dd
	var a := Snow.CELL_AREA
	return {"net": net * a, "added": added * a, "removed": removed * a, "inside": inside * a, "road": road * a,
		"centroid": c / added if added > 0.0 else Vector2.INF}


## Snow lying inside any building's footprint — there must never be any.
static func _s3_indoor_snow() -> float:
	var v := 0.0
	for b in Buildings.all():
		v += Snow.volume_in_rect(b["rect"])
	return v


## Re-baseline every clearing box in `r` to the snow it holds now (as if this much had fallen), so
## laying thin test snow doesn't put a box past the 90 % rule (whose snap removes snow).
static func _s3_rebase_boxes(r: Rect2) -> void:
	for b in Boxes.boxes:
		for rr in b["rects"]:
			if (rr as Rect2).intersects(r):
				if b["complete"]:
					for r2 in b["rects"]:
						Snow.set_hold_rect(r2, false)
					b["complete"] = false
				b["peak"] = Boxes.snow_volume(b, true)
				b["vol"] = b["peak"]
				b["progress"] = 0.0
				break


## Wait until every clump of thrown snow has landed (a release throws on the next frame).
func _s3_settle() -> void:
	await _frames(3)
	for i in range(240):
		if world.find_children("*", "ThrownSnow", true, false).is_empty():
			break
		await _tree().physics_frame
	await _frames(2)


# --- §3 Walls -----------------------------------------------------------------------------------

## The probes that pass through a gap in a hollow house's interior: along each wall just in front of
## it, across every wall it meets at an interior corner (at the floor, at eye height, under the
## ceiling); down through every wall-to-floor seam and up through every wall-to-ceiling seam, and
## across the wall just above the floor and just below the ceiling. Each must hit the house's mesh.
## `faces`: the house's interior triangles in world space (_s3_house_faces).
static func s3_seam_gaps(faces: PackedVector3Array, lot: Dictionary) -> Array:
	var xf := Transform3D()
	var tris := PackedVector3Array()
	tris.resize(faces.size())
	var grid := {}
	@warning_ignore("integer_division")
	for t in range(faces.size() / 3):
		var a := xf * faces[t * 3]
		var b := xf * faces[t * 3 + 1]
		var c := xf * faces[t * 3 + 2]
		tris[t * 3] = a
		tris[t * 3 + 1] = b
		tris[t * 3 + 2] = c
		var mn := a.min(b).min(c)
		var mx := a.max(b).max(c)
		for gx in range(floori(mn.x * 2.0), floori(mx.x * 2.0) + 1):
			for gz in range(floori(mn.z * 2.0), floori(mx.z * 2.0) + 1):
				var key := Vector2i(gx, gz)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(t)
	var L := HouseBuilder.lot_transform(lot)
	var sb: float = lot["setback"]
	var fy := Layout.PORCH_H
	var wh := 3.0
	var z0 := sb
	var z1 := sb + HouseBuilder.DEPTH
	var f := HouseBuilder.IN_FACE
	var xl := HouseBuilder.BODY_X0 + f
	var xr := HouseBuilder.BODY_X1 - f
	var zf := z0 + f
	var zb := z1 - f
	var pz := z0 + 5.0
	var xw := -2.8
	var probes := []   # [name, a (house frame), b (house frame)]
	# Interior corners [name, x, z, into the room along x, along z].
	var corners := [["living front-left", xl, zf, 1, 1], ["living front-right", xr, zf, -1, 1], ["office back-right", xr, zb, -1, -1],
		["office back-left", xw + 0.06, zb, 1, -1], ["living by the partition", xl, pz - 0.06, 1, -1],
		["bedroom front-left", xl, pz + 0.06, 1, 1], ["bedroom front-right", xw - 0.06, pz + 0.06, -1, 1],
		["bedroom back-right", xw - 0.06, zb, -1, -1], ["bedroom back-left", xl, zb, 1, -1]]
	for c in corners:
		var cx: float = c[1]
		var cz: float = c[2]
		var sx: float = c[3]
		var sz: float = c[4]
		for y in [fy + 0.05, fy + 1.3, wh - 0.05]:
			probes.append(["%s corner, along the x wall, y %.2f" % [c[0], y], Vector3(cx + sx * 0.02, y, cz + sz * 0.3), Vector3(cx + sx * 0.02, y, cz - sz * 0.3)])
			probes.append(["%s corner, along the z wall, y %.2f" % [c[0], y], Vector3(cx + sx * 0.3, y, cz + sz * 0.02), Vector3(cx - sx * 0.3, y, cz + sz * 0.02)])
	# Wall faces [name, fixed coordinate axis, value, room normal, samples along].
	var walls := [["front", "z", zf, 1.0, [-8.5, -3.0, 1.8]], ["back", "z", zb, -1.0, [-8.5, -4.5, -1.8, 1.5]],
		["left", "x", xl, 1.0, [z0 + 1.0, z0 + 4.0, z0 + 8.5]], ["right", "x", xr, -1.0, [z0 + 1.0, z0 + 4.5, z0 + 8.0]],
		["partition (living)", "z", pz - 0.06, -1.0, [-8.0, -5.0, -3.0]], ["partition (bedroom)", "z", pz + 0.06, 1.0, [-8.0, -5.0, -3.0]],
		["bedroom wall (bedroom)", "x", xw - 0.06, -1.0, [pz + 1.0, pz + 3.0]], ["bedroom wall (office)", "x", xw + 0.06, 1.0, [pz + 1.0, pz + 3.0]]]
	for w in walls:
		for s in w[4]:
			var p: Vector3
			var n: Vector3
			if w[1] == "z":
				p = Vector3(s, 0, w[2])
				n = Vector3(0, 0, w[3])
			else:
				p = Vector3(w[2], 0, s)
				n = Vector3(w[3], 0, 0)
			var tag := "%s wall at %.1f" % [w[0], s]
			probes.append([tag + ": floor seam", p + n * 0.02 + Vector3(0, fy + 0.03, 0), p + n * 0.02 + Vector3(0, fy - 0.08, 0)])
			probes.append([tag + ": wall foot", p + n * 0.1 + Vector3(0, fy + 0.01, 0), p - n * 0.1 + Vector3(0, fy + 0.01, 0)])
			probes.append([tag + ": ceiling seam", p + n * 0.02 + Vector3(0, wh - 0.03, 0), p + n * 0.02 + Vector3(0, wh + 0.08, 0)])
			probes.append([tag + ": wall top", p + n * 0.1 + Vector3(0, wh - 0.01, 0), p - n * 0.1 + Vector3(0, wh - 0.01, 0)])
	var gaps := []
	for pr in probes:
		var a: Vector3 = L * (pr[1] as Vector3)
		var b: Vector3 = L * (pr[2] as Vector3)
		var mn := a.min(b)
		var mx := a.max(b)
		var hit := false
		var seen := {}
		for gx in range(floori(mn.x * 2.0), floori(mx.x * 2.0) + 1):
			for gz in range(floori(mn.z * 2.0), floori(mx.z * 2.0) + 1):
				var key := Vector2i(gx, gz)
				if hit or not grid.has(key):
					continue
				for t in grid[key]:
					if seen.has(t):
						continue
					seen[t] = true
					if Geometry3D.segment_intersects_triangle(a, b, tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2]) != null:
						hit = true
						break
		if not hit:
			gaps.append(pr[0])
	return gaps


## The triangles HouseBuilder builds for a hollow house's walls, floor, ceiling and interior finish
## (the game's own builder, run again: a headless renderer keeps no mesh data to read back).
static func _s3_house_faces(lot: Dictionary) -> PackedVector3Array:
	var kit := MeshKit.new()
	var sb: float = lot["setback"]
	HouseBuilder._hollow_walls(kit, HouseBuilder.lot_transform(lot), Mats.siding(lot["siding"]), 3.0, sb, sb + HouseBuilder.DEPTH, lot)
	var out := PackedVector3Array()
	for key in kit._order:
		var arr: Array = (kit._st[key] as SurfaceTool).commit_to_arrays()
		out.append_array(arr[Mesh.ARRAY_VERTEX])
	return out


## The house-frame points of this house's roof-snow pillows (drawn at roof depth `depth`) that lie
## inside its rooms: between the walls' inner faces, under the ceiling.
static func _s3_roof_snow_inside(h: Dictionary, lot: Dictionary, depth: float) -> Array:
	var rs: RoofSnow = h["roof_snow"]
	var inv: Transform3D = (h["L"] as Transform3D).affine_inverse()
	var kit := MeshKit.new()
	RoofSnow.build(kit, rs.planes, depth)
	var sb: float = lot["setback"]
	var lo := Vector3(HouseBuilder.BODY_X0 + 0.165, 0.3, sb + 0.165)
	var hi := Vector3(HouseBuilder.BODY_X1 - 0.165, 3.0, sb + HouseBuilder.DEPTH - 0.165)
	var out := []
	for key in kit._order:
		var arr: Array = (kit._st[key] as SurfaceTool).commit_to_arrays()
		for v in arr[Mesh.ARRAY_VERTEX]:
			var p: Vector3 = inv * v
			if p.x > lo.x and p.x < hi.x and p.y > lo.y and p.y < hi.y and p.z > lo.z and p.z < hi.z:
				out.append(p.snapped(Vector3.ONE * 0.01))
	return out


## Both enterable houses: no gap at any interior corner or wall-to-floor / wall-to-ceiling seam (the
## bedroom's two corner slots are closed), the walls carry the finished material with the old
## paint's average colour, and there are baseboards and casings.
func test_s3_walls_closed_and_finished() -> void:
	await _s3_world()
	for lot in [Layout.player_lot, Layout.neighbor_lot]:
		var h: Dictionary = world.refs["houses"][lot["index"]]
		var mi: MeshInstance3D = h["mesh"]
		var gaps := s3_seam_gaps(_s3_house_faces(lot), lot)
		runner.check(gaps.is_empty(), "§3 %s: every interior corner and wall-to-floor / wall-to-ceiling seam is closed %s" % [lot["address"], str(gaps)])
		var poke := []
		for depth in [0.2, 0.6, 1.5]:
			poke.append_array(_s3_roof_snow_inside(h, lot, depth))
		runner.check(poke.is_empty(), "§3 %s: the garage's and the porch's roof snow stays outside the rooms at any depth %s" % [lot["address"], str(poke.slice(0, 3))])
		var wall_mat: ShaderMaterial = null
		var trim_found := false
		for si in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(si)
			if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path == "res://shaders/interior_wall.gdshader":
				wall_mat = m
			if m == Mats.interior_trim():
				trim_found = true
		runner.check(wall_mat != null and trim_found, "§3 %s: the interior walls are finished (drywall / wallpaper) with baseboards and casings" % lot["address"])
		if wall_mat:
			var pr: Vector4 = wall_mat.get_shader_parameter("paper_rect")
			var bed := _s3_rect(lot, HouseBuilder.BODY_X0, -2.8, float(lot["setback"]) + 5.0, float(lot["setback"]) + HouseBuilder.DEPTH)
			runner.check(pr.is_equal_approx(Vector4(bed.position.x, bed.position.y, bed.end.x, bed.end.y)), "§3 %s: the wallpaper is the bedroom's" % lot["address"])
	# The paint's average is the plain colour the walls had (the lighting test of pass 4 runs as is).
	var sh: Shader = load("res://shaders/interior_wall.gdshader")
	runner.check(sh.code.contains("vec3 albedo : source_color = vec3(0.86, 0.8, 0.7)") and sh.code.contains("float roughness_v = 0.9"), "§3 the wall finish averages the old paint (0.86, 0.8, 0.7), roughness 0.9")
	await _unload()


# --- §3 No snow work from inside ------------------------------------------------------------------

## Snow a blower took in but hadn't thrown yet when it stopped (it carries it to its next run).
var _s3_held := 0.0


func _s3_blower(tool: String, at: Vector3) -> WalkBehind:
	var e := {"uid": Game.uid(), "tool": tool, "pos": at, "yaw": 0.0}
	Game.machines.append(e)
	return world.spawn_machine_node(e)


## Work the snow with `tool` for `frames` from where the player stands: LMB swept (then released:
## any load is thrown), then RMB (standing, or walking if `walk`); a blower is run instead. Returns
## whether the indicator showed at any point.
func _s3_work(tool: String, frames: int, walk := false, wb: WalkBehind = null) -> bool:
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var seen := false
	_s3_held = 0.0
	var base := pl.yaw
	if wb != null:
		wb.interact(pl)
		await _frames(2)
		Input.action_press("primary")
		for k in range(frames):
			await _tree().physics_frame
			seen = seen or tc.indicator.visible
		_release_all()
		await _frames(2)
		_s3_held = wb._acc
		wb.release()
		await _s3_settle()
		return seen
	Game.carried = ""
	Game.slots = [tool, "", "", ""]
	Game.select_slot(0)
	await _frames(2)
	Input.action_press("primary")
	for k in range(frames):
		pl.set_yaw(base + 0.3 * sin(k * 0.25))
		await _tree().physics_frame
		seen = seen or tc.indicator.visible
	pl.set_yaw(base)
	Input.action_release("primary")
	await _frames(6)
	seen = seen or tc.indicator.visible
	await _s3_settle()
	Input.action_press("secondary")
	if walk:
		Input.action_press("move_forward")
	for k in range(frames):
		await _tree().physics_frame
		seen = seen or tc.indicator.visible
	_release_all()
	await _frames(3)
	return seen


## From inside both houses — at every window and at the open door, and standing in the doorway —
## no hand tool, the electric shovel or a blower changes any snow or shows an indicator; outside,
## next to a wall, every one of them works.
func test_s3_no_snow_work_from_inside() -> void:
	await _s3_world()
	Game.money = 100000
	var pl: Player = world.player
	var fy := Layout.PORCH_H
	for lot in [Layout.player_lot, Layout.neighbor_lot]:
		var sb: float = lot["setback"]
		var z1 := sb + HouseBuilder.DEPTH
		var x0 := HouseBuilder.BODY_X0
		var door: Door = world.player_door if lot == Layout.player_lot else world.neighbor_door
		door.set_open(true)
		await _frames(40)
		# Snow outside every opening, and on the porch: [name, inside spot (x, z), look at, snow rect (house frame)]
		var spots := [
			["the living-room window", Vector2(-4.45, sb + 0.75), Vector3(-6.2, 1.6, sb), [-8.2, -4.2, sb - 2.5, sb]],
			["the bedroom window", Vector2(-5.2, sb + 8.3), Vector3(-6.3, 1.75, z1), [-8.3, -4.3, z1, z1 + 2.5]],
			["the kitchen window", Vector2(-0.5, sb + 7.9), Vector3(-0.5, 1.75, z1), [-2.5, 1.5, z1, z1 + 2.5]],
			["the bedroom side window", Vector2(x0 + 0.72, sb + 6.3), Vector3(x0, 1.75, sb + 6.3), [x0 - 2.5, x0, sb + 4.3, sb + 8.3]],
			["the open door", Vector2(-1.5, sb + 0.8), Vector3(-1.5, 0.9, sb - 1.0), [-2.9, -0.1, sb - 2.4, sb]],
			["the doorway", Vector2(-1.5, sb + 0.05), Vector3(-1.5, 0.7, sb - 1.0), [-2.9, -0.1, sb - 2.4, sb]],
		]
		for s in spots:
			var sr: Array = s[3]
			var snow_r := _s3_rect(lot, sr[0], sr[1], sr[2], sr[3])
			Snow.set_rect(snow_r, 0.45 if s[0].contains("door") else 0.8)
			Snow.relax_until_stable()
			var spot: Vector2 = s[1]
			var look: Vector3 = s[2]
			var bad := []
			var shown := []
			for tool in S3_HAND_TOOLS + S3_BLOWERS:
				var wb: WalkBehind = null
				if tool in S3_BLOWERS:
					wb = _s3_blower(tool, _s3_h(lot, spot.x, fy, spot.y))
				_s3_stand(_s3_h(lot, spot.x, fy, spot.y), _s3_h(lot, look.x, look.y, look.z), -30.0 if not s[0].contains("door") else INF)
				await _frames(3)
				var snap := _s3_snap(snow_r.grow(2.0))
				var v_before := Snow.stat_player_moved
				var seen: bool = await _s3_work(tool, 20, false, wb)
				var df := _s3_diff(snap)
				var name: String = tool if tool != "" else "hands"
				if df["added"] > 0.0 or df["removed"] > 0.0 or Snow.stat_player_moved != v_before or pl.tools.load > 0.0:
					bad.append("%s (%.4f m3 moved)" % [name, df["removed"]])
				if seen:
					shown.append(name)
				if wb:
					wb.queue_free()
				pl.tools.load = 0.0
			runner.check(bad.is_empty(), "§3 %s, inside at %s: no tool changes any snow %s" % [lot["address"], s[0], str(bad)])
			runner.check(shown.is_empty(), "§3 %s, inside at %s: no indicator %s" % [lot["address"], s[0], str(shown)])
		door.set_open(false)
		await _frames(30)
		# Outside, next to the back wall: every tool works, as before.
		var out_r := _s3_rect(lot, -9.0, -3.0, z1, z1 + 3.0)
		Snow.set_rect(out_r, 0.45)
		Snow.relax_until_stable()
		var works := []
		for tool in S3_HAND_TOOLS + S3_BLOWERS:
			var name2: String = tool if tool != "" else "hands"
			var snap2 := _s3_snap(out_r.grow(14.0))
			var seen2 := false
			if tool in S3_BLOWERS:
				# Walking along the wall, 0.9 m out, the chute away from it.
				var at := _s3_h(lot, -8.6, 0.0, z1 + 0.9)
				var wb2 := _s3_blower(tool, at)
				_s3_stand(at, _s3_h(lot, -3.0, 0.0, z1 + 0.9), 0.0)
				wb2.chute_angle = rad_to_deg(pl.forward2().angle_to(_s3_dir(lot, 0, 1)))
				seen2 = await _s3_work(tool, 30, false, wb2)
				wb2.queue_free()
			else:
				# Facing the wall from 0.6 m out, scooping the snow at its foot; then pushing along it.
				_s3_stand(_s3_h(lot, -6.0, 0.0, z1 + 0.6), _s3_h(lot, -6.0, 0.0, z1), -70.0)
				await _frames(3)
				seen2 = await _s3_work(tool, 20, false)
				_s3_stand(_s3_h(lot, -8.6, 0.0, z1 + 0.6), _s3_h(lot, -3.0, 0.0, z1 + 0.6), -30.0)
				await _frames(2)
				Input.action_press("secondary")
				Input.action_press("move_forward")
				await _frames(30)
				_release_all()
				await _frames(3)
			await _s3_settle()
			var df2 := _s3_diff(snap2)
			if df2["removed"] > 0.002 and absf(float(df2["net"]) + _s3_held) < 1e-5 and seen2:
				works.append(name2)
			else:
				runner.info("%s outside: removed %.4f, net %.6f, indicator %s" % [name2, df2["removed"], df2["net"], str(seen2)])
			pl.tools.load = 0.0
			Snow.set_rect(out_r, 0.45)
			Snow.relax_until_stable()
		runner.check(works.size() == S3_HAND_TOOLS.size() + S3_BLOWERS.size(), "§3 %s, outside next to the wall: every tool works the snow, volume conserved %s" % [lot["address"], str(works)])
	runner.check(_s3_indoor_snow() == 0.0, "§3 no snow inside any building")
	_release_all()
	await _unload()


# --- §3 Thrown snow and buildings ------------------------------------------------------------------

## Throw `vol` from `start` toward `aim` (world) the way every tool does (Throw.compute, then a
## ThrownSnow carrying the volume) and land it at once (flush runs the same landing code).
func _s3_throw(start: Vector3, aim: Vector3, dist: float, ang: float, vol: float) -> Dictionary:
	var d2 := Vector2(aim.x - start.x, aim.z - start.z).normalized()
	var land := Throw.compute(world.get_world_3d(), start, d2, dist, ang, [])
	if land.get("valid", false):
		var ts := ThrownSnow.spawn(world, start, d2, land, vol, ang, 0.35)
		ts.flush()
	return land


## What's wrong with a throw that met building `bl` (empty: nothing): it landed outside, at the foot
## of the face it came at, all of it (exactly), none inside, where its landing (the indicator) said.
static func _s3_throw_problems(land: Dictionary, df: Dictionary, vol: float, bl: Dictionary, start: Vector3, ind: Vector3) -> Array:
	var bad := []
	if not land.get("valid", false) or land.get("kind", "") != "ground":
		return ["no ground landing (%s)" % str(land.get("kind", "?"))]
	var p: Vector3 = land["pos"]
	var p2 := Vector2(p.x, p.z)
	var r: Rect2 = bl["rect"]
	var q := Vector2(clampf(p2.x, r.position.x, r.end.x), clampf(p2.y, r.position.y, r.end.y))
	var d := q.distance_to(p2)
	if not Buildings.at(p2).is_empty() or d < 0.1 or d > Buildings.FOOT_OUT + 0.15:
		bad.append("landing %.2f m from the wall" % d)
	if (p2 - q).dot(Vector2(start.x, start.z) - q) <= 0.0:
		bad.append("landed on the far side")
	if absf(float(df["added"]) - vol) > 1e-5 or absf(float(df["net"]) - vol) > 1e-5:
		bad.append("volume %.6f of %.6f" % [df["net"], vol])
	if float(df["inside"]) > 0.0:
		bad.append("%.5f m3 inside" % df["inside"])
	var c: Vector2 = df["centroid"]
	if c.x == INF or c.distance_to(Vector2(ind.x, ind.z)) > 0.25:
		bad.append("landed %.2f m from the indicator" % c.distance_to(Vector2(ind.x, ind.z)))
	return bad


## Thrown snow (hands, every tool, the electric shovel, blower chutes) aimed at the walls, the
## windows, the open door and the roof of every building, from every side: it lands outside at the
## foot of the wall, volume conserved exactly, no snow inside, the indicator within 25 cm of it.
func test_s3_thrown_snow_stops_at_buildings() -> void:
	await _s3_world()
	world.player_door.set_open(true)
	world.neighbor_door.set_open(true)
	await _frames(40)
	var pl: Player = world.player
	pl.teleport(Vector3(10, 0.05, 120))      # out of the way
	var v_all0 := Snow.total_volume()
	var thrown := 0.0
	var fy := Layout.PORCH_H
	var n := 0
	var bad := []
	for lot in [Layout.player_lot, Layout.neighbor_lot]:
		var sb: float = lot["setback"]
		var z0 := sb
		var z1 := sb + HouseBuilder.DEPTH
		var x0 := HouseBuilder.BODY_X0
		var x1 := HouseBuilder.BODY_X1
		var gx1 := HouseBuilder.GAR_X1
		var body := Buildings.at(Vector2(_s3_h(lot, -4.0, 0, sb + 4.0).x, _s3_h(lot, -4.0, 0, sb + 4.0).z))
		var gar := Buildings.at(Vector2(_s3_h(lot, 6.0, 0, sb + 3.0).x, _s3_h(lot, 6.0, 0, sb + 3.0).z))
		# [name, building, start (house frame), aim (house frame), distance, angle]
		var cases := [
			["front wall", body, Vector3(-3.2, 1.3, z0 - 2.5), Vector3(-3.2, 1.3, z0), 4.0, 38.0],
			["front window", body, Vector3(-6.2, 1.5, z0 - 2.5), Vector3(-6.2, 1.5, z0), 4.0, 30.0],
			["open front door", body, Vector3(-1.5, fy + 1.2, z0 - 1.2), Vector3(-1.5, fy + 1.2, z0), 3.0, 20.0],
			["roof from the front", body, Vector3(-4.5, 1.3, z0 - 3.0), Vector3(-4.5, 1.3, z0), 9.0, 55.0],
			["garage door", gar, Vector3(6.0, 1.3, z0 - 3.0), Vector3(6.0, 1.3, z0), 4.0, 30.0],
			["back wall", body, Vector3(-8.2, 1.3, z1 + 2.5), Vector3(-8.2, 1.3, z1), 4.0, 38.0],
			["bedroom window", body, Vector3(-6.3, 1.3, z1 + 2.5), Vector3(-6.3, 1.3, z1), 4.0, 30.0],
			["kitchen window", body, Vector3(-0.5, 1.3, z1 + 2.5), Vector3(-0.5, 1.3, z1), 4.0, 30.0],
			["roof from the back", body, Vector3(-4.5, 1.3, z1 + 3.0), Vector3(-4.5, 1.3, z1), 9.0, 55.0],
			["garage back wall", gar, Vector3(6.0, 1.3, sb + 9.5), Vector3(6.0, 1.3, sb + 7.0), 4.0, 30.0],
			["side wall", body, Vector3(x0 - 2.5, 1.3, sb + 3.0), Vector3(x0, 1.3, sb + 3.0), 4.0, 38.0],
			["side window", body, Vector3(x0 - 2.5, 1.3, sb + 6.3), Vector3(x0, 1.3, sb + 6.3), 4.0, 30.0],
			["roof from the side", body, Vector3(x0 - 3.0, 1.3, sb + 4.5), Vector3(x0, 1.3, sb + 4.5), 9.0, 55.0],
			["garage side wall", gar, Vector3(gx1 + 2.5, 1.3, sb + 3.0), Vector3(gx1, 1.3, sb + 3.0), 4.0, 38.0],
			["garage roof from the side", gar, Vector3(gx1 + 3.0, 1.3, sb + 3.0), Vector3(gx1, 1.3, sb + 3.0), 9.0, 55.0],
			["house wall behind the garage", body, Vector3(x1 + 2.5, 1.3, sb + 8.2), Vector3(x1, 1.3, sb + 8.2), 4.0, 38.0],
		]
		for c in cases:
			var st := _s3_h(lot, c[2].x, c[2].y, c[2].z)
			var aim := _s3_h(lot, c[3].x, c[3].y, c[3].z)
			var bl: Dictionary = c[1]
			var snap := _s3_snap((bl["rect"] as Rect2).grow(4.0))
			var vol := 0.04
			var land := _s3_throw(st, aim, c[4], c[5], vol)
			thrown += vol if land.get("valid", false) else 0.0
			var prob := _s3_throw_problems(land, _s3_diff(snap), vol, bl, st, land.get("pos", Vector3.INF))
			n += 1
			if not prob.is_empty():
				bad.append("%s %s: %s" % [lot["address"], c[0], ", ".join(prob)])
	for b in Layout.buildings:
		var bl2 := Buildings.at((b["rect"] as Rect2).get_center())
		var r: Rect2 = b["rect"]
		var top: float = b["height"]
		var cc := r.get_center()
		# [name, start, aim]: every side's wall, and a lob onto the roof from a high bank on every side.
		var sides := [["north", Vector2(cc.x, r.position.y - 2.5), Vector2(cc.x, r.position.y)], ["south", Vector2(cc.x, r.end.y + 2.5), Vector2(cc.x, r.end.y)],
			["west", Vector2(r.position.x - 2.5, cc.y), Vector2(r.position.x, cc.y)], ["east", Vector2(r.end.x + 2.5, cc.y), Vector2(r.end.x, cc.y)]]
		for sd in sides:
			for what in ["wall", "roof"]:
				var a2: Vector2 = sd[1]
				var t2: Vector2 = sd[2]
				var st2 := Vector3(a2.x, 1.3 if what == "wall" else top + 0.6, a2.y)
				var snap2 := _s3_snap(r.grow(4.0))
				var land2 := _s3_throw(st2, Vector3(t2.x, st2.y, t2.y), 4.0 if what == "wall" else 5.0, 30.0 if what == "wall" else 60.0, 0.04)
				thrown += 0.04 if land2.get("valid", false) else 0.0
				var prob2 := _s3_throw_problems(land2, _s3_diff(snap2), 0.04, bl2, st2, land2.get("pos", Vector3.INF))
				n += 1
				if not prob2.is_empty():
					bad.append("%s %s %s: %s" % [b["id"], sd[0], what, ", ".join(prob2)])
	runner.check(bad.is_empty(), "§3 %d throws at walls, windows, open doors and roofs from every side of every building: each lands outside at the foot of the wall, all of it, none inside, where the landing said %s" % [n, str(bad)])
	Snow.relax_until_stable()
	runner.near(Snow.total_volume(), v_all0 + thrown, 1e-4, "§3 …total snow volume conserved exactly (%.3f m3 thrown)" % thrown)
	runner.check(_s3_indoor_snow() == 0.0, "§3 …and no snow inside any building")
	# With the real tools and their indicator: [tool, house-frame stand, house-frame target, load or
	# snow to work, chute direction (house frame) for a blower]
	var lot2 := Layout.player_lot
	var sb2: float = lot2["setback"]
	var tool_cases := [
		["standard_shovel", "the living-room window", Vector3(-6.2, 0, sb2 - 1.5), Vector3(-6.2, 1.6, sb2)],
		["", "the open door", Vector3(-1.5, fy, sb2 - 1.2), Vector3(-1.5, fy + 1.5, sb2)],
		["electric_shovel", "the bedroom window", Vector3(-6.3, 0, sb2 + HouseBuilder.DEPTH + 2.0), Vector3(-6.3, 1.0, sb2 + HouseBuilder.DEPTH)],
		["small_blower", "the side wall", Vector3(HouseBuilder.BODY_X0 - 3.0, 0, sb2 + 2.5), Vector3(HouseBuilder.BODY_X0 - 3.0, 0, sb2 + 8.0)],
		["large_blower", "the roof", Vector3(-6.0, 0, sb2 - 4.0), Vector3(-1.0, 0, sb2 - 4.0)],
	]
	var tbad := []
	for tc_ in tool_cases:
		var tool: String = tc_[0]
		var at := _s3_h(lot2, tc_[2].x, tc_[2].y, tc_[2].z)
		var look := _s3_h(lot2, tc_[3].x, tc_[3].y, tc_[3].z)
		var work := Rect2(Vector2(at.x, at.z) - Vector2(2.5, 2.5), Vector2(5, 5))
		var body2 := Buildings.at(Vector2(_s3_h(lot2, -4.0, 0, sb2 + 4.0).x, _s3_h(lot2, -4.0, 0, sb2 + 4.0).z))
		Snow.set_rect(work, 0.0 if tool in ["standard_shovel", ""] else 0.4)
		Snow.relax_until_stable()
		var snap3 := _s3_snap((body2["rect"] as Rect2).grow(6.0))
		# Relaxation held still while measuring: the snow is measured where it landed, before a
		# pile of it slides.
		Snow.auto_process = false
		var tcl: ToolController = pl.tools
		var inds := []
		var held := 0.0
		if tool in S3_BLOWERS:
			var wb := _s3_blower(tool, at)
			_s3_stand(at, look, 0.0)
			wb.chute_angle = rad_to_deg(pl.forward2().angle_to(_s3_dir(lot2, 1, 0) if tool == "small_blower" else _s3_dir(lot2, 0, 1)))
			wb.interact(pl)
			await _frames(2)
			Input.action_press("primary")
			for k in range(40):
				await _tree().physics_frame
				if tcl.indicator.visible and k > 10:
					inds.append(tcl.indicator.global_position)
			_release_all()
			await _frames(2)
			held = wb._acc
			wb.release()
			wb.queue_free()
		else:
			Game.carried = ""
			Game.slots = [tool, "", "", ""]
			Game.select_slot(0)
			_s3_stand(at, look, 0.0 if tool != "electric_shovel" else -20.0)
			await _frames(3)
			if tool != "electric_shovel":
				tcl.load = tcl._capacity() * 0.8
				thrown += tcl.load
			Input.action_press("primary")
			for k in range(30):
				await _tree().physics_frame
				if tcl.indicator.visible and k > 20:
					inds.append(tcl.indicator.global_position)
			Input.action_release("primary")
		await _s3_settle()
		var df3 := _s3_diff(snap3)
		Snow.auto_process = true
		Snow.relax_until_stable()
		var ind := Vector3.ZERO
		for v in inds:
			ind += v
		ind = ind / maxf(inds.size(), 1)
		var lp: Dictionary = {"valid": not inds.is_empty(), "kind": "ground", "pos": ind}
		var vol3: float = df3["added"] if tool in ["electric_shovel", "small_blower", "large_blower"] else df3["net"]
		var prob3 := _s3_throw_problems(lp, {"added": vol3, "net": vol3, "inside": df3["inside"], "centroid": df3["centroid"]}, vol3, body2, at, ind)
		if tool in ["electric_shovel", "small_blower", "large_blower"] and absf(float(df3["net"]) + held) > 1e-5:
			prob3.append("not conserved (%.6f m3)" % (float(df3["net"]) + held))
		if float(df3["added"]) < 0.005:
			prob3.append("nothing thrown")
		if not prob3.is_empty():
			tbad.append("%s at %s: %s" % [tool if tool != "" else "hands", tc_[1], ", ".join(prob3)])
		else:
			runner.info("%s at %s: %.1f L landed at the wall foot, %.2f m from the indicator" % [tool if tool != "" else "hands", tc_[1], float(df3["added"]) * 1000.0, (df3["centroid"] as Vector2).distance_to(Vector2(ind.x, ind.z))])
		pl.tools.load = 0.0
	runner.check(tbad.is_empty(), "§3 with the real tools (hands at the open door, a shovel at a window, the electric shovel, both blowers' chutes at a wall and the roof): the snow lands at the wall's foot, where the indicator showed %s" % str(tbad))
	runner.check(_s3_indoor_snow() == 0.0, "§3 …still no snow inside")
	_release_all()
	await _unload()


## The building list behind both rules: every house and its garage (§15's garage is that one),
## the school, the store and the church, each footprint a wall for the snow; a building added with
## register() (as §16's will be) is indoors for the tools and stops thrown snow at once.
func test_s3_buildings_registry() -> void:
	await _s3_world()
	var built := 0
	for lot in Layout.lots:
		if not lot["vacant"]:
			built += 1
	var all := Buildings.all()
	runner.check(all.size() == built * 2 + Layout.buildings.size(), "§3 %d buildings: %d houses, their garages, %d others" % [all.size(), built, Layout.buildings.size()])
	var not_blocked := []
	for b in all:
		var c := (b["rect"] as Rect2).get_center()
		if Snow.surface_at(c.x, c.y) != Snow.S_BLOCKED:
			not_blocked.append(b["id"])
	runner.check(not_blocked.is_empty(), "§3 every building's footprint is a wall for the snow %s" % str(not_blocked))
	var gar: Rect2 = Layout.house_info(Layout.player_lot)["garage"]
	runner.check(Buildings.indoors(Vector3(gar.get_center().x, 0.05, gar.get_center().y)), "§3 the garage counts as indoors")
	# A new building on the empty lot at 11 Birch Avenue.
	var vac: Dictionary = Layout.lot_by_address(11, Layout.STREET_BIRCH)
	var r := Layout.lot_rect_world(vac, -4.0, 4.0, 10.0, 16.0)
	Buildings.register("s3_test_building", r, 5.0, "test")
	runner.check(Buildings.indoors(Vector3(r.get_center().x, 0.05, r.get_center().y)) and not Buildings.indoors(Vector3(r.position.x - 1.0, 0.05, r.position.y - 1.0)), "§3 a registered building is indoors inside, outdoors outside")
	var st := Vector3(r.get_center().x, 1.3, r.position.y - 2.5)
	var snap := _s3_snap(r.grow(4.0))
	var land := _s3_throw(st, Vector3(st.x, 1.3, r.position.y), 4.0, 30.0, 0.04)
	var prob := _s3_throw_problems(land, _s3_diff(snap), 0.04, Buildings.at(r.get_center()), st, land.get("pos", Vector3.INF))
	runner.check(prob.is_empty(), "§3 …and snow thrown at it stops at its wall and falls at its foot %s" % str(prob))
	Buildings.unregister("s3_test_building")
	runner.check(Buildings.at(r.get_center()).is_empty(), "§3 …unregistered again")
	await _unload()


# --- §3 The road rule removed (Decision 12) -------------------------------------------------------

## Yard snow thrown (a shovel), pushed (a pusher), blown (the electric shovel and a blower) and plowed
## (an ATV blade and the pickup's plow) lands on the street where it was aimed: volume conserved
## exactly, the indicator shows the street landing like any other and agrees with it, and the
## street's clearing box counts the snow.
func test_s3_road_rule_removed() -> void:
	await _s3_world()
	Game.money = 100000
	var pl: Player = world.player
	var tcl: ToolController = pl.tools
	var lot := Layout.player_lot
	var road_r := Rect2(0, 79, Layout.MAP_W, 8)
	var sbox := Boxes.box_at(Vector2(Layout.lot_to_world(lot, 0.0, -6.0)))
	runner.check(sbox.get("kind", "") == "street", "§3 the street in front of the house is a clearing box (%s)" % sbox.get("id", "?"))
	var res: float = Catalog.balance.contract_residual_depth
	var to_street := -Vector2(lot["inward"]).normalized()
	var along := Vector2(to_street.y, -to_street.x)
	# Thrown, blown: [tool, stand (lot u, v), snow on the yard]
	for c in [["standard_shovel", Vector2(-5.0, 1.0)], ["electric_shovel", Vector2(-9.0, 1.0)], ["small_blower", Vector2(4.0, 1.5)], ["large_blower", Vector2(-1.0, 4.5)]]:
		var tool: String = c[0]
		var uv: Vector2 = c[1]
		Snow.set_rect(road_r, res + 0.03)
		Snow.set_rect(Layout.lot_rect_world(lot, -13.0, 13.0, -3.0, 6.0), 0.3)
		Snow.relax_until_stable()
		_s3_rebase_boxes(Rect2(0, 76, Layout.MAP_W, 20))
		var at2 := Layout.lot_to_world(lot, uv.x, uv.y)
		var at := Vector3(at2.x, 0.0, at2.y)
		var win := Rect2(at2 - Vector2(16, 16), Vector2(32, 32))
		var snap := _s3_snap(win)
		var box0 := Boxes.snow_volume(sbox, true)
		var inds := []
		var ring_ok := true
		var held := 0.0
		Snow.auto_process = false     # measured where it lands, before a pile slides
		if tool in S3_BLOWERS:
			var wb := _s3_blower(tool, at)
			_s3_stand(at, at + Vector3(along.x, 0, along.y), 0.0)
			wb.chute_angle = rad_to_deg(pl.forward2().angle_to(to_street))
			wb.interact(pl)
			await _frames(2)
			Input.action_press("primary")
			for k in range(60):
				await _tree().physics_frame
				if tcl.indicator.visible and k > 10:
					inds.append(tcl.indicator.global_position)
					ring_ok = ring_ok and tcl.indicator.mesh != tcl._ring_bad
			_release_all()
			await _frames(2)
			held = wb._acc
			wb.release()
			wb.queue_free()
		else:
			Game.carried = ""
			Game.slots = [tool, "", "", ""]
			Game.select_slot(0)
			_s3_stand(at, at + Vector3(to_street.x, 0, to_street.y), -50.0)
			await _frames(3)
			Input.action_press("primary")
			var base := pl.yaw
			if tool == "standard_shovel":
				for k in range(30):
					pl.set_yaw(base + 0.3 * sin(k * 0.2))
					await _tree().physics_frame
				pl.set_yaw(base)
				pl.pitch = 0.0
				pl.head.rotation.x = 0.0
			for k in range(40):
				await _tree().physics_frame
				if tcl.indicator.visible and k > 25 and (tool != "standard_shovel" or tcl.ind_state == "landing"):
					inds.append(tcl.indicator.global_position)
					ring_ok = ring_ok and tcl.indicator.mesh != tcl._ring_bad
			Input.action_release("primary")
		await _s3_settle()
		var df := _s3_diff(snap)
		Snow.auto_process = true
		var ind := Vector3.ZERO
		for v in inds:
			ind += v
		ind /= maxf(inds.size(), 1)
		var box1 := Boxes.snow_volume(sbox, true)
		var cdist := (df["centroid"] as Vector2).distance_to(Vector2(ind.x, ind.z))
		runner.check(not inds.is_empty() and ring_ok and Snow.is_road(ind.x, ind.z), "§3 %s aimed at the street from the yard: the indicator shows the street landing like any other" % tool)
		if absf(float(df["road"]) - float(df["added"])) >= 1e-5:
			runner.info("%s: added %.5f, on the street %.5f, removed %.5f" % [tool, df["added"], df["road"], df["removed"]])
		runner.check(float(df["road"]) > 0.01 and absf(float(df["road"]) - float(df["added"])) < 1e-5 and cdist < 0.25, "§3 …the snow lands on the street where it was aimed (%.1f L, %.2f m from the indicator)" % [float(df["road"]) * 1000.0, cdist])
		runner.check(absf(float(df["net"]) + held) < 1e-5, "§3 …volume conserved exactly (%.7f m3)" % (float(df["net"]) + held))
		runner.check(absf((box1 - box0) - float(df["road"])) < 1e-4, "§3 …and the street box counts it (+%.1f L)" % ((box1 - box0) * 1000.0))
		pl.tools.load = 0.0
	# Pushed: a wide pusher walking from the lawn toward the street carries the snow over the curb.
	Snow.set_rect(road_r, res + 0.03)
	Snow.set_rect(Layout.lot_rect_world(lot, -13.0, 13.0, -3.0, 4.0), 0.08)
	Snow.relax_until_stable()
	_s3_rebase_boxes(Rect2(0, 76, Layout.MAP_W, 20))
	var p0 := Layout.lot_to_world(lot, -5.0, 2.5)
	var win2 := Rect2(p0 - Vector2(10, 14), Vector2(20, 28))
	var snap2 := _s3_snap(win2)
	var box2 := Boxes.snow_volume(sbox, true)
	Game.slots = ["wide_pusher", "", "", ""]
	Game.select_slot(0)
	_s3_stand(Vector3(p0.x, 0, p0.y), Vector3(p0.x + to_street.x, 0, p0.y + to_street.y), -30.0)
	await _frames(3)
	Input.action_press("secondary")
	Input.action_press("move_forward")
	var tz := Layout.lot_to_world(lot, -5.0, -4.5)
	for k in range(900):
		await _tree().physics_frame
		if Vector2(pl.global_position.x, pl.global_position.z).distance_to(p0) > p0.distance_to(tz):
			break
	_release_all()
	await _frames(5)
	var df2 := _s3_diff(snap2)
	var box3 := Boxes.snow_volume(sbox, true)
	var lane_x := (df2["centroid"] as Vector2)
	runner.check(float(df2["road"]) > 0.05, "§3 pushed: the pusher carries the yard snow over the curb onto the street (+%.3f m3 on the street)" % df2["road"])
	runner.check(absf(lane_x.dot(along) - p0.dot(along)) < 0.6, "§3 …in the lane it was pushed along (%.2f m off)" % absf(lane_x.dot(along) - p0.dot(along)))
	runner.check(absf(float(df2["net"])) < 1e-5 and box3 > box2 + 0.05, "§3 …volume conserved exactly (%.7f m3) and the street box counts it" % df2["net"])
	# Plowed: an ATV blade and the pickup's plow push a driveway's snow onto the street.
	for vid in ["atv_blade", "pickup_plow"]:
		var vlot: Dictionary = Layout.lots[9] if vid == "atv_blade" else Layout.lots[10]
		var drv: Rect2 = Layout.house_info(vlot)["driveway"]
		var vbox := Boxes.box_at(Vector2(drv.get_center().x, 83.0))
		Snow.set_rect(road_r, res + 0.03)
		Snow.set_rect(Rect2(drv.position.x - 4, 87, drv.size.x + 8, 20), 0.2)
		Snow.relax_until_stable()
		_s3_rebase_boxes(Rect2(0, 76, Layout.MAP_W, 34))
		var win3 := Rect2(drv.position.x - 10, 60, drv.size.x + 20, 52)
		var snap3 := _s3_snap(win3)
		var vb0 := Boxes.snow_volume(vbox, true)
		var e := {"uid": Game.uid(), "id": vid, "pos": Vector3(drv.get_center().x, 0, drv.end.y - 1.0), "yaw": 0.0, "snow": 0.0}
		Game.vehicles.append(e)
		var v: Vehicle = world.spawn_vehicle_node(e)
		await _frames(2)
		v.enter_vehicle(pl)
		v._toggle_tool()
		Input.action_press("veh_accelerate")
		for k in range(400):
			await _tree().physics_frame
			if (v.global_transform * Vector3(0, 0, float(v.info["blade_z"]))).z < 83.0:
				break      # the blade has carried the snow out to the middle of the street
		_release_all()
		await _frames(5)
		v.exit_vehicle()
		await _frames(2)
		var df3 := _s3_diff(snap3)
		var vb1 := Boxes.snow_volume(vbox, true)
		var on_lane := absf((df3["centroid"] as Vector2).x - drv.get_center().x) < drv.size.x
		runner.check(float(df3["road"]) > 0.1 and on_lane, "§3 plowed (%s): the yard snow goes over the curb onto the street in front of the driveway (+%.2f m3)" % [vid, df3["road"]])
		runner.check(absf(float(df3["net"])) < 1e-4 and vb1 > vb0 + 0.1, "§3 …volume conserved exactly (%.6f m3) and the street box counts it" % df3["net"])
		v.queue_free()
		await _frames(2)
	_release_all()
	await _unload()


# --- §3 The money plant ---------------------------------------------------------------------------

## The living-room plant, a testing aid: "[E] Plant (+$1,000)" with the bound key; each Interact
## adds exactly $1,000 to the money (both modes), ten add $10,000, the money survives save → load,
## and the earnings (stats, lifetime, the end-of-winter summary's "Money earned") don't move.
func test_s3_money_plant() -> void:
	for mode in ["fun", "survival"]:
		await _s3_world(mode)
		var pl: Player = world.player
		var plant: Node3D = world.interior.get("plant")
		runner.check(plant != null, "§3 %s: the living-room plant is interactable" % mode)
		if plant == null:
			continue
		var lot := Layout.player_lot
		var sb: float = lot["setback"]
		var L := HouseBuilder.lot_transform(lot)
		var local := L.affine_inverse() * plant.global_position
		var clear := local.x < -4.2 and local.z < sb + 5.0 - 0.5 and local.z > sb      # in the living room
		for thing in [Vector2(-1.5, sb), Vector2(-3.7, sb + 5.0), Vector2(-2.7, sb + 0.165), Vector2(1.75, sb + 8.45), Vector2(-6.6, sb + 7.9)]:
			clear = clear and Vector2(local.x, local.z).distance_to(thing) > 1.5   # the doors, the photo, the computer, the bed
		runner.check(clear, "§3 %s: the plant stands in the living room, clear of the doors, the photo, the computer and the bed (%.2f, %.2f)" % [mode, local.x, local.z - sb])
		_s3_stand(_s3_h(lot, -7.6, Layout.PORCH_H, sb + 1.25), _s3_h(lot, InteriorBuilder.PLANT_AT.x, Layout.PORCH_H + 0.45, sb + InteriorBuilder.PLANT_AT.y))
		await _frames(4)
		var want := "[%s] Plant (+$1,000)" % Settings.action_label("interact")
		runner.check(pl.focus == plant and pl.focus_prompt == want, "§3 %s: looking at it shows \"%s\" (%s)" % [mode, want, pl.focus_prompt])
		var m0 := Game.money
		var earned0 = Game.stats.get("money_earned", 0)
		var life0 = Game.lifetime.get("money_earned", 0)
		var steps := []
		for k in range(10):
			var ev := InputEventAction.new()
			ev.action = "interact"
			ev.pressed = true
			Input.parse_input_event(ev)
			await _frames(2)
			var up := InputEventAction.new()
			up.action = "interact"
			up.pressed = false
			Input.parse_input_event(up)
			await _frames(12)     # five a second: under the press cap
			steps.append(Game.money - m0)
		var each := true
		for k in range(10):
			each = each and int(steps[k]) == 1000 * (k + 1)
		var last: Dictionary = Notify.history[Notify.history.size() - 1] if not Notify.history.is_empty() else {}
		runner.check(each and Game.money == m0 + 10000, "§3 %s: each press adds exactly $1,000; ten add $10,000 (%s)" % [mode, str(steps)])
		runner.check(str(last.get("text", "")) == "+$1,000", "§3 %s: it shows \"+$1,000\"" % mode)
		runner.check(Game.stats.get("money_earned", 0) == earned0 and Game.lifetime.get("money_earned", 0) == life0, "§3 %s: the earnings stats are unchanged" % mode)
		runner.check(Saves.save_game(), "§3 %s: saved" % mode)
		var m1 := Game.money
		await _unload()
		runner.check(Saves.load_game(mode) and Game.money == m1 and Game.stats.get("money_earned", 0) == earned0, "§3 %s: the money survives save → load ($%d)" % [mode, Game.money])
		Saves.delete_save(mode)
	await _unload()


# =============================================================================
# §4 The opening and Gerry
# =============================================================================

## A new game (stage START) at 7:30 on Dec 1 — the opening, with the morning's subtitle.
func _s4_world(mode: String, hour := 7.5) -> void:
	await _unload()
	Game.force_input = true
	Game.new_game(mode, 2024)
	Clock.reset(Clock.at(0, hour))
	await _spawn_world()


## The player in the hall, facing the front door from inside.
func _s4_face_door() -> void:
	var lot := Layout.player_lot
	var sb: float = lot["setback"]
	_s3_stand(_s3_h(lot, -1.5, Layout.PORCH_H, sb + 1.6), _s3_h(lot, -1.5, Layout.PORCH_H + 1.1, sb))
	await _frames(4)


func _s4_press(action: String) -> void:
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


## Open (or close) the front door with Interact, as the player does.
func _s4_use_door() -> void:
	await _s4_face_door()
	await _s4_press("interact")
	await _frames(15)      # past the press cap's frame window


## Frames until the speech box says `text` (or `limit` frames).
func _s4_wait_for_line(text: String, limit: int) -> int:
	for i in range(limit):
		if world.hud.speech_box.visible and world.hud.speech_text.text == text:
			return i
		await _tree().physics_frame
	return -1


## Frames until the speech box is empty (or `limit` frames).
func _s4_wait_quiet(limit: int) -> int:
	for i in range(limit):
		if not world.hud.speech_box.visible:
			return i
		await _tree().physics_frame
	return -1


# --- §4 The door line ---------------------------------------------------------------------------

## The first time the front door is opened from inside, during the opening and with no shovel, the
## thought shows once in the HUD speech box — after the morning subtitle, timed by its length, no
## modal, the player free to move — and never again; not with a shovel in hand; not on fixtures past
## the opening. Both modes.
func test_s4_door_line() -> void:
	var line: String = world_line()
	for mode in ["fun", "survival"]:
		await _s4_world(mode)
		var pl: Player = world.player
		await _s4_use_door()
		runner.check(world.player_door.open and pl.in_player_house, "§4 %s: the front door opened from inside" % mode)
		# The morning's subtitle comes first: never two lines at once.
		var both := false
		var sub_first := false
		var shown := -1
		for i in range(900):
			if world.hud.speech_box.visible and world.hud.subtitle_box.visible:
				both = true
			if world.hud.subtitle_box.visible and world.hud.subtitle_l.text.begins_with("December 1"):
				sub_first = true
			if world.hud.speech_box.visible and world.hud.speech_text.text == line:
				shown = i
				break
			await _tree().physics_frame
		runner.check(shown >= 0 and sub_first and not both, "§4 %s: the door line shows on the HUD after the morning subtitle, never with it (after %d frames)" % [mode, shown])
		runner.check(world.hud.speech_name.text == "You" and world.modal == null and pl.state != "frozen", "§4 %s: a thought — \"You\", no modal, the player not stopped" % mode)
		var t: float = world._talk_t
		var want: float = world.line_seconds(line)
		runner.check(t <= want and t > want - 0.2 and want >= 4.0 and want <= 14.0, "§4 %s: timed by its length (%.1f s)" % [mode, want])
		var p0 := pl.global_position
		await _hold("move_back", 40)
		runner.check(pl.global_position.distance_to(p0) > 0.3 and world.hud.speech_text.text == line, "§4 %s: the player walks while it shows (%.2f m)" % [mode, pl.global_position.distance_to(p0)])
		var gone := await _s4_wait_quiet(int(t * 60.0) + 30)
		runner.check(gone >= 0, "§4 %s: it goes by itself" % mode)
		# Close the door, open it again: once only.
		await _s4_use_door()
		await _s4_use_door()
		var again := await _s4_wait_for_line(line, 500)
		runner.check(world.player_door.open and again < 0, "§4 %s: opening the door again says nothing" % mode)
		# With the shovel picked up: never.
		await _s4_world(mode)
		Game.add_tool("small_shovel")
		await _s4_use_door()
		runner.check(world.player_door.open and await _s4_wait_for_line(line, 500) < 0, "§4 %s: not once a shovel has been picked up" % mode)
	# Fixtures past the opening (Gerry's job taken; the tutorial done): never.
	for path in ["res://tests/fixtures/polish4/fun_2_mid_trail.json", "res://tests/fixtures/polish4/survival_3_trail_done.json",
			"res://tests/fixtures/polish5/fun_1_contracts.json", "res://tests/fixtures/polish5/survival_4_midwinter.json"]:
		var ok: bool = await _load_save_file(path)
		runner.check(ok, "§4 %s loads" % path.get_file())
		if not ok:
			continue
		await _spawn_world()
		await _s4_use_door()
		runner.check(world.player_door.open and await _s4_wait_for_line(line, 500) < 0, "§4 %s (past the opening): no door line" % path.trim_prefix("res://tests/fixtures/"))
	await _unload()


## The door line as the game has it.
func world_line() -> String:
	return (load("res://scripts/game/game_root.gd") as Script).get_script_constant_map()["DOOR_LINE"]


# --- §4 Gerry: the two ways to move snow ---------------------------------------------------------

## Take Gerry's job through his dialogue ($55), standing in front of him.
func _s4_take_job() -> void:
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.LETTER_READ)
	var g: Neighbor = world.neighbor
	var out := -Vector2(Layout.neighbor_lot["inward"]).normalized()
	var at := Vector2(g.global_position.x, g.global_position.z) + out * 2.2
	_s3_stand(Vector3(at.x, Snow.surface_height(at.x, at.y), at.y), g.global_position + Vector3(0, 1.2, 0))
	await _frames(4)
	await _s4_press("interact")
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


## Read Gerry's lines as they come (Interact moves on), up to `n` lines.
func _s4_read_lines(n: int) -> Array:
	var out := []
	var last := ""
	for k in range(n * 8):
		if not world.is_gerry_talking():
			break
		var t: String = world.hud.speech_text.text
		if t != last:
			out.append(t)
			last = t
			if out.size() >= n:
				break
		await _s4_press("interact")
		await _frames(12)
	return out


## When Gerry gives you his trail he adds the two ways to move snow, with the keys from the input
## map; on the HUD (timed, Interact moves on, the player walking throughout); talking to him again
## during the job repeats it; rebound keys show; the tips end with the job.
func test_s4_gerry_snow_tips() -> void:
	var saved: Variant = _s2_backup()
	Settings.restore_default_controls()
	for mode in ["fun", "survival"]:
		await _s4_world(mode, 11.0)
		Clock.running = true
		var pl: Player = world.player
		await _s4_take_job()
		runner.check(Game.stage() == Game.Stage.NEIGHBOR_TALKED and world.modal == null, "§4 %s: Gerry's job agreed" % mode)
		var first: String = world.hud.speech_text.text
		runner.check(world.is_gerry_talking() and world.hud.speech_box.visible and first == "Now, two ways to move snow.", "§4 %s: then on the HUD: \"%s\"" % [mode, first])
		var t: float = world._talk_t
		var want: float = world.line_seconds(first)
		runner.check(t <= want and t > want - 0.2 and want >= 4.0 and want <= 14.0, "§4 %s: each line timed by its length (%.1f s)" % [mode, want])
		# The player walks while he talks; the line moves on by itself.
		var p0 := pl.global_position
		await _hold("move_back", int(t * 60.0) + 20)
		runner.check(pl.global_position.distance_to(p0) > 1.0 and pl.state != "frozen" and world.modal == null, "§4 %s: the player can move throughout (%.1f m)" % [mode, pl.global_position.distance_to(p0)])
		var second: String = world.hud.speech_text.text
		runner.check(second != first and world.is_gerry_talking(), "§4 %s: the next line comes by itself (%s)" % [mode, second])
		runner.check(second.contains("[%s]" % Settings.action_label("primary")) and second.contains("fill") and second.contains("throw"), "§4 %s: scoop and throw, with the bound key (%s)" % [mode, second])
		# Interact moves him on (looking at him).
		await _s4_take_job_stand()
		var rest := await _s4_read_lines(3)
		var third: String = rest[1] if rest.size() > 1 else ""
		var fourth: String = rest[2] if rest.size() > 2 else ""
		runner.check(third.contains("[%s]" % Settings.action_label("secondary")) and third.contains("push"), "§4 %s: pushing, with the bound key (%s)" % [mode, third])
		runner.check(fourth.contains("blue line") and fourth.contains("sidewalk") and fourth.contains("door"), "§4 %s: and where: %s" % [mode, fourth])
		await _frames(int(world.line_seconds(fourth) * 60.0) + 30)
		runner.check(not world.is_gerry_talking() and not world.hud.speech_box.visible, "§4 %s: then he's done" % mode)
		# Talking to him again during the job repeats the tip (no modal).
		await _s4_press("interact")
		await _frames(2)
		runner.check(world.modal == null and world.hud.speech_text.text == first, "§4 %s: talking to him again repeats the tip (%s)" % [mode, world.hud.speech_text.text])
		# Rebound keys: the lines show the new ones.
		var k := InputEventKey.new()
		k.physical_keycode = KEY_J
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_MIDDLE
		runner.check(Settings.rebind("primary", k) == "" and Settings.rebind("secondary", m) == "", "§4 %s: scoop rebound to J, push to the middle button" % mode)
		world.neighbor_dialogue(world.neighbor)
		await _frames(1)
		var lines := await _s4_read_lines(4)
		var all := "\n".join(lines)
		runner.check(lines.size() == 4 and all.contains("Hold [J]") and all.contains("hold [Middle Mouse]") and not all.contains("Left Mouse") and not all.contains("Right Mouse"), "§4 %s: with rebound keys he says [J] and [Middle Mouse] (%s)" % [mode, all.replace("\n", " | ")])
		Settings.restore_default_controls()
		# The tips end with the job: Gerry's sequence goes on as before.
		world.neighbor_dialogue(world.neighbor)
		await _frames(1)
		runner.check(world.is_gerry_talking(), "§4 %s: (talking again)" % mode)
		for c in Contracts.active:
			if c.get("tutorial", false) and c["status"] == "active":
				for z in c["zones"]:
					for ra in z["rects"]:
						Snow.set_rect(Contracts.a_to_rect(ra), 0.004)
					Contracts.measure_zone(c, z)
		await _frames(2)
		runner.check(Game.stage() == Game.Stage.TRAIL_DONE and not world.is_gerry_talking() and not world.hud.speech_box.visible, "§4 %s: the trail done, the tips stop" % mode)
		Clock.running = false
	_s2_restore(saved)
	await _unload()


## Stand in front of Gerry again (he's on his porch during the job), looking at him.
func _s4_take_job_stand() -> void:
	var g: Neighbor = world.neighbor
	var out := -Vector2(Layout.neighbor_lot["inward"]).normalized()
	var at := Vector2(g.global_position.x, g.global_position.z) + out * 2.2
	_s3_stand(Vector3(at.x, Snow.surface_height(at.x, at.y), at.y), g.global_position + Vector3(0, 1.2, 0))
	await _frames(4)


# --- §4 Gerry's last line: the keys --------------------------------------------------------------

## Gerry inside by his fire with the player, the trail done: his explanation starts.
func _s4_gerry_inside(mode: String, keys_found: bool) -> void:
	await _s4_world(mode, 11.0)
	Clock.running = true
	Game.flags["truck_keys"] = keys_found
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.LETTER_READ)
	Contracts.create_tutorial_contract(50)
	Game.set_stage(Game.Stage.NEIGHBOR_TALKED)
	for c in Contracts.active:
		if c.get("tutorial", false) and c["status"] == "active":
			for z in c["zones"]:
				for ra in z["rects"]:
					Snow.set_rect(Contracts.a_to_rect(ra), 0.004)
				Contracts.measure_zone(c, z)
	await _frames(2)
	var g: Neighbor = world.neighbor
	g.invited = true
	g._path.clear()
	g._set_pos(g.fire_spot())
	g.mode = "inside"
	var inside := Neighbor._h(-3.0, 3.6)
	_s3_stand(inside, g.global_position + Vector3(0, 1.2, 0))
	await _frames(4)


## Every line of the explanation, Interact moving it on, to the end.
func _s4_explanation() -> Array:
	var out := []
	var last := ""
	for k in range(200):
		if not world.is_gerry_talking():
			break
		var t: String = world.hud.speech_text.text
		if t != last:
			out.append(t)
			last = t
		world._talk_next()
		await _frames(2)
	return out


## After his heat and computer lines Gerry's last line sends you to your truck keys under the tree
## on your front lawn — skipped once they're found, said again when you talk to him before then.
func test_s4_gerry_keys_line() -> void:
	var keys_text: String = HelpText.keys_line()["text"]
	for mode in ["fun", "survival"]:
		await _s4_gerry_inside(mode, false)
		runner.check(world.player.in_neighbor_house and world._talk_started and world.is_gerry_talking(), "§4 %s: by the fire, Gerry talks you through the business" % mode)
		var lines := await _s4_explanation()
		var i_keys := lines.find(keys_text)
		var i_comp := -1
		var i_heat := -1
		for k in range(lines.size()):
			if str(lines[k]).contains("computer"):
				i_comp = k
			if str(lines[k]).contains("heat") or str(lines[k]).contains("warm"):
				i_heat = maxi(i_heat, k)
		runner.check(i_keys == lines.size() - 1 and i_keys > i_comp and i_comp >= 0 and i_keys > i_heat, "§4 %s: the keys line comes last, after the heat and computer lines (%d of %d; heat %d, computer %d)" % [mode, i_keys + 1, lines.size(), i_heat, i_comp])
		runner.check(keys_text.contains("tree") and keys_text.contains("front lawn") and keys_text.contains("keys"), "§4 %s: \"%s\"" % [mode, keys_text])
		runner.check(Game.stage() == Game.Stage.COMPLETE and Game.computer_unlocked(), "§4 %s: the tutorial completes as before" % mode)
		# Talking to him again before the keys are found: the line again (each time).
		for n in range(2):
			world.neighbor_dialogue(world.neighbor)
			await _frames(1)
			runner.check(world.hud.speech_text.text == keys_text and world.modal == null, "§4 %s: talking to him again (%d) repeats it" % [mode, n + 1])
			await _s4_explanation()
		# Found: he doesn't say it again.
		Game.flags["truck_keys"] = true
		world.neighbor_dialogue(world.neighbor)
		await _frames(1)
		runner.check(world.hud.speech_text.text != keys_text and world.hud.speech_text.text.contains("Off you go"), "§4 %s: once they're found he just sees you off (%s)" % [mode, world.hud.speech_text.text])
		await _s4_explanation()
		# Keys already found before the explanation: no keys line.
		await _s4_gerry_inside(mode, true)
		var lines2 := await _s4_explanation()
		runner.check(not lines2.has(keys_text) and lines2.size() == lines.size() - 1 and str(lines2[lines2.size() - 1]).contains("That's about it"), "§4 %s: keys already found: no keys line (%d lines, last: %s)" % [mode, lines2.size(), str(lines2[lines2.size() - 1]).left(40)])
		runner.check(Game.stage() == Game.Stage.COMPLETE, "§4 %s: …and the tutorial still completes" % mode)
		Clock.running = false
	await _unload()


## The truck keys are buried beside the tree on the player's front lawn (the layout's own trees).
func test_s4_keys_beside_the_front_lawn_tree() -> void:
	await _s4_world("fun", 11.0)
	var lot := Layout.player_lot
	var sb: float = lot["setback"]
	var hi := Layout.house_info(lot)
	var kp: Array = Game.flags["keys_pos"]
	var keys := Vector2(kp[0], kp[1])
	var origin := Vector2(lot["center_x"], lot["front_z"])
	var lawn_trees := []
	for p in world.refs["tree_points"]:
		var pp: Vector2 = p
		var v := (pp - origin).dot(lot["inward"])
		if (lot["rect"] as Rect2).has_point(pp) and v > 0.0 and v < sb:
			lawn_trees.append(pp)
	var nearest := INF
	for p in lawn_trees:
		nearest = minf(nearest, (p as Vector2).distance_to(keys))
	var kv := (keys - origin).dot(lot["inward"])
	runner.check(not lawn_trees.is_empty(), "§4 a tree stands on the player's front lawn (%d)" % lawn_trees.size())
	runner.check((lot["rect"] as Rect2).has_point(keys) and kv > 0.0 and kv < sb and not (hi["walkway"] as Rect2).has_point(keys) and not (hi["driveway"] as Rect2).has_point(keys), "§4 the keys are in the front lawn (%.1f m in from the sidewalk)" % kv)
	runner.check(nearest < 2.5, "§4 the keys lie within a couple of metres of that tree (%.2f m)" % nearest)
	await _unload()


# --- §4 The photo --------------------------------------------------------------------------------

## The photo is a hint: the small shovel (the game's own model) stands where it lies buried, at the
## same side and end of the truck; the character faces the camera; both are in the picture and the
## shovel isn't hidden. The print reads the right way round on the (mirrored) wall. The capture
## draws only after a frame has gone by. "[E] Look at the photo" shows it large, no text; E and Esc
## close it.
func test_s4_photo_hint_and_view() -> void:
	await _s4_world("fun", 12.0)
	Clock.running = false
	# The scene.
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = FramedPhoto.PHOTO
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	runner.add_child(vp)
	FramedPhoto.build_scene(vp)
	await _frames(2)
	var sh: MeshInstance3D = vp.find_child("Shovel", true, false)
	var cam: Camera3D = vp.find_child("Camera", true, false)
	var ch: Node3D = vp.find_child("Character", true, false)
	var truck: Node3D = vp.find_child("Truck", true, false)
	runner.check(sh != null and cam != null and ch != null and truck != null and truck.transform == Transform3D.IDENTITY, "§4 the photo scene: the truck, the character, the shovel, the camera")
	if sh != null and cam != null and ch != null:
		runner.check(sh.mesh == ToolModels.mesh_for("small_shovel"), "§4 the shovel in the photo is the small shovel's own model")
		# Where it lies buried, in the truck's frame (the game's truck and shovel start spots).
		var ts: Dictionary = Game.truck_start()
		var sp: Vector2 = Game.shovel_spot()
		var want := Basis(Vector3.UP, float(ts["yaw"])).inverse() * (Vector3(sp.x, 0, sp.y) - (ts["pos"] as Vector3))
		var mound := Game.shovel_spot() + Vector2(0.05, -0.15).rotated(-0.6)
		var want_m := Basis(Vector3.UP, float(ts["yaw"])).inverse() * (Vector3(mound.x, 0, mound.y) - (ts["pos"] as Vector3))
		var blade := sh.transform * ToolModels.tip("small_shovel")
		runner.check(Vector2(blade.x - want.x, blade.z - want.z).length() < 0.05, "§4 it stands where it lies buried: (%.2f, %.2f) in the truck's frame, want (%.2f, %.2f)" % [blade.x, blade.z, want.x, want.z])
		runner.check(signf(blade.x) == signf(want_m.x) and signf(blade.z) == signf(want_m.z) and absf(want.x) > 1.0, "§4 …the same side (%s) and end (%s) of the truck as the oblong pile" % ["driver's" if want_m.x < 0.0 else "passenger", "front" if want_m.z < 0.0 else "back"])
		var shaft := (sh.transform.basis * ToolModels.tip("small_shovel")).normalized()
		runner.check(shaft.dot(Vector3.DOWN) > cos(deg_to_rad(10.0)), "§4 …standing upright (%.0f° off vertical)" % rad_to_deg(acos(clampf(shaft.dot(Vector3.DOWN), -1.0, 1.0))))
		var low := INF
		var aabb: AABB = sh.mesh.get_aabb()
		for k in range(8):
			low = minf(low, (sh.transform * aabb.get_endpoint(k)).y)
		runner.check(low < 0.0 and low > -0.1, "§4 …planted in the snow (%.2f m)" % low)
		var to_cam := cam.global_position - ch.global_position
		var facing := -ch.global_transform.basis.z
		runner.check(Vector2(facing.x, facing.z).normalized().dot(Vector2(to_cam.x, to_cam.z).normalized()) > 0.95, "§4 the character faces the camera")
		runner.check(Vector2(ch.position.x, ch.position.z).distance_to(Vector2(blade.x, blade.z)) < 3.0 and absf(ch.position.x) < 2.5, "§4 …beside the truck, near the shovel")
		var fr := Rect2(Vector2.ZERO, Vector2(FramedPhoto.PHOTO))
		var s_top := cam.unproject_position(sh.global_position)
		var s_bot := cam.unproject_position(sh.global_transform * ToolModels.tip("small_shovel"))
		var c_mid := cam.unproject_position(ch.global_position + Vector3(0, 0.9, 0))
		runner.check(fr.has_point(s_top) and fr.has_point(s_bot) and fr.has_point(c_mid) and not cam.is_position_behind(sh.global_position), "§4 the shovel and the character are in the picture")
		runner.check(absf(s_top.x - c_mid.x) > 80.0 and absf(s_bot.x - c_mid.x) > 80.0, "§4 the shovel isn't hidden behind the character (%.0f px apart)" % minf(absf(s_top.x - c_mid.x), absf(s_bot.x - c_mid.x)))
	vp.queue_free()
	await _frames(2)
	# The print on the wall: flipped back on a mirrored house transform.
	var ph: FramedPhoto = world.interior["photo"]
	var mirrored := ph.global_transform.basis.determinant() < 0.0
	runner.check(mirrored and ph._print_mat.uv1_scale.x == -1.0 and ph._print_mat.uv1_offset.x == 1.0, "§4 the player's house is mirrored and the print is flipped back (it hung mirror-reversed)")
	# The capture: drawing off while the scene is put in place, on once a frame has gone by.
	ph._capture()
	var cvp: SubViewport = null
	for c in ph.get_children():
		if c is SubViewport:
			cvp = c
	runner.check(cvp != null and cvp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "§4 the photo is built with drawing off")
	await _tree().process_frame
	await _tree().process_frame
	runner.check(not is_instance_valid(cvp) or cvp.render_target_update_mode != SubViewport.UPDATE_DISABLED, "§4 …and drawn once a frame has gone by")
	for i in range(10):
		await _tree().process_frame
	runner.check(ph.texture != null and not ph.captured, "§4 headless: the placeholder print stays")
	# Look at it.
	var pl: Player = world.player
	var n := ph.global_transform.basis.z.normalized()
	var at := ph.global_position + n * 1.5
	_s3_stand(Vector3(at.x, Layout.PORCH_H, at.z), ph.global_position)
	await _frames(4)
	var want_p := "[%s] Look at the photo" % Settings.action_label("interact")
	runner.check(pl.focus_prompt == want_p, "§4 from 1.5 m: \"%s\" (%s)" % [want_p, pl.focus_prompt])
	await _s4_press("interact")
	await _frames(2)
	var big: Control = world.modal
	var tr: TextureRect = big.find_child("Print", true, false) if big else null
	runner.check(world.modal_kind == "photo" and tr != null and tr.texture == ph.texture and tr.size.x >= 1100.0, "§4 Interact shows the photo large on screen (%s)" % (str(tr.size) if tr else "none"))
	runner.check(big != null and _s2_texts(big).strip_edges() == "", "§4 …with no text")
	await _frames(15)
	await _s4_press("interact")
	await _frames(2)
	runner.check(world.modal == null and pl.state != "frozen", "§4 Interact puts it down")
	await _frames(15)
	await _s4_press("interact")
	await _frames(2)
	runner.check(world.modal_kind == "photo", "§4 (looking again)")
	await _s4_press("pause")
	await _frames(2)
	runner.check(world.modal == null and not _tree().paused, "§4 Esc puts it down too")
	await _unload()
