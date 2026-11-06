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
	"res://tests/fixtures/polish5_v3/",
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
## the cap allows, and no more snow comes off the box than clicking at the cap rate (both kept from
## round 5). Polish 6 §8.1 replaced the click behaviour this test asserted: a press no longer
## opens with an in-place bite, a release sooner than min_scoop_hold_s throws nothing and every
## throw is followed by the tool's throw_recovery_s. So clicking at the cap rate, at 20 and 50/s,
## and at 20/s with the cap off, removes no more snow per second than holding and sweeping, and
## throws no more often than the recovery allows (see docs/polish6/report/s8_1.md).
func test_s2_autoclick_capped() -> void:
	var bench: Node = load("res://tests/click_bench.gd").new()
	runner.add_child(bench)
	await bench.setup(runner)
	world = bench.world
	var cap: float = Catalog.balance.input_max_presses_per_s
	var rec: float = Catalog.tool(&"hands").throw_recovery_s
	var secs := 20.0
	var sw: Dictionary = await bench.run_sweep(secs)
	var at_cap: Dictionary = await bench.run_click_primary(cap, secs)
	var r_sw: float = sw["removed"] / sw["secs"]
	var r_cap: float = at_cap["removed"] / at_cap["secs"]
	runner.info("hold + sweep: %.4f m3/s; clicking at the cap (%.0f/s): %.4f m3/s, %.1f registered/s, %d throws, %.1f L per press" % [r_sw, cap, r_cap, at_cap["registered"] / at_cap["secs"], at_cap["throws"], at_cap["moved"] / maxf(at_cap["registered"], 1) * 1000.0])
	runner.check(r_cap <= r_sw * 1.05 + 0.002, "§2 clicking LMB at the cap rate (%.0f/s) removes no more snow per second than holding and sweeping (%.4f vs %.4f m3/s)" % [cap, r_cap, r_sw])
	for rate in [20.0, 50.0]:
		var d: Dictionary = await bench.run_click_primary(rate, secs)
		var r: float = d["removed"] / d["secs"]
		runner.info("clicking at %.0f/s: %.4f m3/s (x%.2f hold + sweep), %d sent, %d registered, %d throws" % [rate, r, r / maxf(r_sw, 1e-6), d["sent"], d["registered"], d["throws"]])
		runner.check(float(d["registered"]) <= cap * d["secs"] + 1.0, "§2 clicking LMB at %.0f/s: at most %.0f presses register per second (%d in %.1f s)" % [rate, cap, d["registered"], d["secs"]])
		runner.check(r <= r_cap * 1.12 + 0.002, "§2 clicking LMB at %.0f/s removes no more snow per second than clicking at the cap rate (%.4f vs %.4f m3/s)" % [rate, r, r_cap])
		runner.check(r <= r_sw * 1.05 + 0.002, "§2 clicking LMB at %.0f/s removes no more snow per second than holding and sweeping (%.4f vs %.4f m3/s)" % [rate, r, r_sw])
		runner.check(d["throws"] <= d["registered"] and float(d["throws"]) <= d["secs"] / rec + 1.0, "§2 …and throws no more than once per registered press and once per %.2f s recovery (%d throws, %d registered)" % [rec, d["throws"], d["registered"]])
	# The cap still limits the presses; the scoop's rule is what holds the snow now: without the cap,
	# 20/s registers far more presses and still removes no more than holding and sweeping.
	Catalog.balance.input_max_presses_per_s = 0.0
	var free20: Dictionary = await bench.run_click_primary(20.0, secs)
	Catalog.balance.input_max_presses_per_s = cap
	var r_free: float = free20["removed"] / free20["secs"]
	runner.info("without the cap, clicking at 20/s: %.4f m3/s, %d registered, %d throws" % [r_free, free20["registered"], free20["throws"]])
	runner.check(float(free20["registered"]) > cap * free20["secs"] * 1.3, "§2 without the cap, 20/s registers %d presses in %.1f s" % [free20["registered"], free20["secs"]])
	runner.check(r_free <= r_sw * 1.05 + 0.002 and float(free20["throws"]) <= free20["secs"] / rec + 1.0, "§2 …and still removes no more than holding and sweeping (%.4f vs %.4f m3/s, %d throws)" % [r_free, r_sw, free20["throws"]])
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


## A human tapping at 5 a second: every press registers (RMB pushes, E and G alternate), and holding
## is never cut short by the cap. Polish 6 §8.1: an LMB tap that short (held half of a 5/s period)
## comes before min_scoop_hold_s and, standing still, before one cycle_time: it scoops and throws
## nothing (round 5 asserted a scoop and a throw on every tap).
func test_s2_tapping_5_per_s_works() -> void:
	var bench: Node = load("res://tests/click_bench.gd").new()
	runner.add_child(bench)
	await bench.setup(runner)
	world = bench.world
	var d: Dictionary = await bench.run_click_primary(5.0, 8.0)
	var tap := 0.5 / 5.0
	var hands: ToolData = Catalog.tool(&"hands")
	var short_hold := tap < Catalog.balance.min_scoop_hold_s
	var short_dig := tap < hands.cycle_time
	runner.check(d["sent"] >= 25 and d["registered"] == d["sent"], "§2 LMB tapped at 5/s: every tap registers (%d sent, %d registered)" % [d["sent"], d["registered"]])
	runner.check(d["throws"] == (0 if short_hold else d["registered"]), "§2 …a %.2f s tap throws %s (min hold %.2f s): %d throws" % [tap, "nothing" if short_hold else "once", Catalog.balance.min_scoop_hold_s, d["throws"]])
	if short_dig:
		runner.check(d["moved"] < 1e-6, "§2 …and a %.2f s tap without a sweep scoops nothing (cycle %.2f s): %.2f L" % [tap, hands.cycle_time, d["moved"] * 1000.0])
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
		descs.append((t as ToolData).store_description())   # polish 6 §3: as the store shows it ({width})
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


# =============================================================================
# §5 House and building numbers
# =============================================================================

## Where along its street a place is, and on which side ([along, side]: side +1 = the left side going
## the way the numbers rise). A lot by its centre; a building by its property (building + parking
## lot) along the lane.
static func _s5_along(p: Vector2, street: String) -> Array:
	for r in Layout.roads:
		if r["name"] != street:
			continue
		var c := (r["rect"] as Rect2).get_center()
		if r["horizontal"]:
			return [p.x, 1.0 if p.y < c.y else -1.0]    # going east (+x), the left is north (-z)
		return [p.y, 1.0 if p.x > c.x else -1.0]         # going south (+z), the left is east (+x)
	return [0.0, 0.0]


static func _s5_property_center(b: Dictionary) -> Vector2:
	var r: Rect2 = b["rect"]
	for a in Layout.big_areas:
		if a.get("building", "") == b["id"]:
			r = r.merge(a["rect"])
	return r.get_center()


## Every place's address comes from the layout: the houses keep theirs (24 and 28 Maple Street are
## the playtest's), the school, the store and the church have one in the same scheme — on each
## street odd numbers on one side and even on the other, unique, rising along it — and place_name()
## names every contract target from it.
func test_s5_addresses_from_the_layout() -> void:
	Layout.ensure()
	var l24 := Layout.lot_by_address(24, Layout.STREET_MAPLE)
	var l28 := Layout.lot_by_address(28, Layout.STREET_MAPLE)
	runner.check(not l24.is_empty() and not l28.is_empty() and int(l24["index"]) == 9 and int(l28["index"]) == 10 and not l24["vacant"] and not l28["vacant"], "§5 24 and 28 Maple Street are lots 9 and 10, as before")
	var by_street := {}
	var bad := []
	for lot in Layout.lots:
		if lot["address"] != "%d %s" % [lot["number"], lot["street"]]:
			bad.append(lot["address"])
		var a := _s5_along(Vector2(lot["center_x"], lot["front_z"]), lot["street"])
		by_street.get_or_add(lot["street"], []).append([a[0], a[1], int(lot["number"]), str(lot["address"])])
	for b in Layout.buildings:
		if not b.has("number") or b["address"] != "%d %s" % [b["number"], b["street"]] or b["place"] != "%s, %s" % [b["name"], b["address"]]:
			bad.append(str(b["id"]))
			continue
		var a2 := _s5_along(_s5_property_center(b), b["street"])
		by_street.get_or_add(b["street"], []).append([a2[0], a2[1], int(b["number"]), str(b["address"])])
	runner.check(bad.is_empty(), "§5 every house and building has an address, number + street %s" % str(bad))
	for street in by_street.keys():
		var rows: Array = by_street[street]
		var nums := {}
		var probs := []
		for r in rows:
			if nums.has(r[2]):
				probs.append("%d twice" % r[2])
			nums[r[2]] = true
			# The left side going up is odd (Maple and Birch: the north side, as the layout has it).
			if (int(r[2]) % 2 == 1) != (float(r[1]) > 0.0):
				probs.append("%s on the wrong side" % r[3])
		for side in [1.0, -1.0]:
			var on := rows.filter(func(x): return float(x[1]) == side)
			on.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
			for k in range(1, on.size()):
				if int(on[k][2]) <= int(on[k - 1][2]):
					probs.append("%s before %s" % [on[k - 1][3], on[k][3]])
		runner.check(probs.is_empty(), "§5 %s: %d numbers, unique, odd on one side and even on the other, rising along it %s" % [street, rows.size(), str(probs)])
	runner.info("§5 the buildings: " + ", ".join(Layout.buildings.map(func(b): return "%s %s" % [b["name"], b["address"]])))
	# One name per place, from the layout.
	var names := []
	for lot in Layout.lots:
		if Layout.place_name("lot:%d" % lot["index"]) != lot["address"]:
			names.append(lot["address"])
	for a in Layout.big_areas:
		var want: String = a["name"] if a["id"] == "dump_lot" else "%s, %s" % [Layout.building_by_id(a["building"])["name"], Layout.building_by_id(a["building"])["address"]]
		if Layout.place_name("area:%s" % a["id"]) != want or a["place"] != want:
			names.append(a["id"])
	for seg in Layout.road_segments:
		if Layout.place_name("road:%s" % seg["id"]) != seg["name"]:
			names.append(seg["id"])
	runner.check(names.is_empty() and Layout.place_name("nowhere") == "", "§5 place_name() names every lot, parking lot and street section from the layout %s" % str(names))
	runner.check(Layout.current_place("Contract payment: Northern Supply Co. parking lot") == "Contract payment: Northern Supply Co., 11 Cedar Lane" and Layout.current_place("24 Maple Street") == "24 Maple Street", "§5 a parking lot's old name reads as its address now")


## The pixels a height `h` m covers at `dist` m on a 1080-line screen with the default field of view.
static func _s5_px(h: float, dist: float) -> float:
	return h / (2.0 * dist * tan(deg_to_rad(75.0) * 0.5)) * 1080.0


## Every house has its number on a plate by the front door, facing the street, readable from the
## sidewalk (in view, big enough) by day and at night (the porch lantern lights it), and on its
## mailbox's door; every other building has larger numbers by its main entrance, facing the street.
## All of them match the layout and are drawn only within reading range.
func test_s5_numbers_on_every_house_and_building() -> void:
	await _s3_world()
	var space := (world as Node3D).get_world_3d().direct_space_state
	var houses := 0
	var bad := []
	var min_px := INF
	for lot in Layout.lots:
		if lot["vacant"]:
			continue
		houses += 1
		var h: Dictionary = world.refs["houses"][lot["index"]]
		var plate: MeshInstance3D = h.get("number")
		var addr: String = lot["address"]
		if plate == null or not is_instance_valid(plate) or int(plate.get_meta("number", -1)) != int(lot["number"]) or plate.get_meta("address", "") != addr:
			bad.append("%s: no plate with its number" % addr)
			continue
		var hi := Layout.house_info(lot)
		var f: Vector2 = hi["facing"]
		var z := plate.global_transform.basis.z.normalized()
		var x := plate.global_transform.basis.x.normalized()
		if Vector2(z.x, z.z).dot(f) < 0.99 or x.cross(Vector3.UP).dot(z) < 0.99:
			bad.append("%s: the plate doesn't face the street (or is mirrored)" % addr)
		var hollow: bool = lot["is_player"] or lot["is_neighbor"]
		var L := HouseBuilder.lot_transform(lot)
		var local := L.affine_inverse() * plate.global_position
		var face := float(lot["setback"]) - (0.055 if hollow else 0.0)
		if absf(local.z - face) > 0.03 or Vector2(local.x, local.y).distance_to(Vector2(-1.5, 1.6)) > 1.2:
			bad.append("%s: not on the front wall by the door %s" % [addr, str(local)])
		# The porch lantern just above it lights it at night.
		var lamp := L * Vector3(-0.55, 2.0, float(lot["setback"]) - 0.15)
		var mats := []
		for s in plate.mesh.get_surface_count():
			mats.append(plate.mesh.surface_get_material(s))
		var lit := mats.size() == 2
		for m in mats:
			lit = lit and m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("address_plate.gdshader") and float((m as ShaderMaterial).get_shader_parameter("lamp")) > 0.0
		var to_lamp := lamp - plate.global_position
		if not lit or to_lamp.y < 0.2 or to_lamp.length() > 0.6:
			bad.append("%s: not lit by the porch lantern (%s)" % [addr, str(to_lamp)])
		if plate.visibility_range_end <= 0.0 or plate.visibility_range_end > 60.0 or plate.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			bad.append("%s: drawn at any distance" % addr)
		# From the sidewalk at the foot of the walk (eye 1.6 m over the snow there): in view, readable.
		var foot := Layout.lot_to_world(lot, Layout.gu(lot, -1.5), -0.75)
		var eye := Vector3(foot.x, Snow.surface_height(foot.x, foot.y) + 1.6, foot.y)
		var tgt := plate.global_position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, tgt - (tgt - eye).normalized() * 0.05, 1))
		var d := eye.distance_to(tgt)
		var px := _s5_px(AddressSigns.PLATE_DIGIT_H, d) * (tgt - eye).normalized().dot(-z)
		min_px = minf(min_px, px)
		if not hit.is_empty() or px < 10.0:
			bad.append("%s: not readable from the sidewalk (%s, %.1f px at %.1f m)" % [addr, "blocked" if not hit.is_empty() else "clear", px, d])
		# The mailbox's door.
		var mb: Node3D = world.refs["mailboxes"][lot["index"]]
		var mn: MeshInstance3D = mb.get_node_or_null("MailboxNumber")
		if mn == null or int(mn.get_meta("number", -1)) != int(lot["number"]) or mn.visibility_range_end <= 0.0:
			bad.append("%s: no number on the mailbox" % addr)
		elif Vector2(-mb.global_transform.basis.z.x, -mb.global_transform.basis.z.z).normalized().dot(f) < 0.99 or mn.mesh.get_surface_count() != 1:
			bad.append("%s: the mailbox's number doesn't face the street" % addr)
	runner.check(bad.is_empty(), "§5 all %d houses: the number on a plate by the front door, under the porch lantern, facing the street, readable from the sidewalk (≥ %.1f px at 1080p), and on the mailbox %s" % [houses, min_px, str(bad)])
	runner.check(world.refs["mailboxes"].size() == houses, "§5 still one mailbox per house (%d)" % world.refs["mailboxes"].size())
	# The other buildings: from the street, at the entrance to their lot.
	var bb := []
	for b in Layout.buildings:
		var l: Label3D = world.refs["building_numbers"].get(b["id"])
		if l == null or l.text != str(b["number"]) or l.get_meta("address", "") != b["address"]:
			bb.append("%s: no number" % b["id"])
			continue
		var r: Rect2 = b["rect"]
		var z2 := l.global_transform.basis.z.normalized()
		var p2 := Vector2(l.global_position.x, l.global_position.z)
		var on_wall := r.grow(0.1).has_point(p2) and not r.grow(-0.1).has_point(p2)
		var outward := not r.has_point(p2 + Vector2(z2.x, z2.z) * 0.5)
		var apron: Rect2 = Layout.big_areas.filter(func(a): return a.get("building", "") == b["id"])[0]["apron"]
		var eye2 := Vector3(apron.get_center().x, 1.6, apron.get_center().y)
		var to_eye := (eye2 - l.global_position).normalized()
		var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye2, l.global_position + to_eye * 0.1, 1))
		var px2 := _s5_px(AddressSigns.BUILDING_DIGIT_H, eye2.distance_to(l.global_position)) * to_eye.dot(z2)
		var digit_h := l.font_size * l.pixel_size * 0.72
		if not on_wall or not outward or to_eye.dot(z2) < cos(deg_to_rad(60.0)) or not hit2.is_empty() or px2 < 10.0:
			bb.append("%s: on the wall %s, outward %s, %.0f° off the street, %s, %.1f px" % [b["id"], on_wall, outward, rad_to_deg(acos(clampf(to_eye.dot(z2), -1.0, 1.0))), "blocked" if not hit2.is_empty() else "clear", px2])
		elif digit_h < 3.0 * AddressSigns.PLATE_DIGIT_H or l.visibility_range_end <= 0.0:
			bb.append("%s: not larger than a house's, or drawn at any distance" % b["id"])
		else:
			runner.info("§5 %s: %s on its %s, %.0f° off the way to its lot's entrance, %.0f px from there" % [b["name"], b["address"], "front" if absf(z2.z) > 0.5 else "end wall", rad_to_deg(acos(clampf(to_eye.dot(z2), -1.0, 1.0))), px2])
	runner.check(bb.is_empty(), "§5 the school, the store and the church: larger numbers by the main entrance, facing the street, readable from the entrance to their lot %s" % str(bb))
	await _unload()


## The same address wherever a place is named: the clearing boxes (the HUD box line), the contract
## board, contracts and their notifications, the history, the store's texts; old saves read the same.
func test_s5_same_addresses_everywhere() -> void:
	await _s3_world()
	var bad := []
	for b in Boxes.boxes:
		var want := Layout.place_name(str(b["owner"]))
		if b["place"] != want:
			bad.append("%s: %s" % [b["id"], b["place"]])
	runner.check(bad.is_empty(), "§5 every clearing box is named by its owner's address %s" % str(bad))
	# The HUD box line, in a parking lot and on a driveway.
	var pl: Player = world.player
	var spots := [[(Layout.big_areas[1]["rect"] as Rect2).get_center(), Layout.big_areas[1]["place"]],
		[(Layout.house_info(Layout.lots[9])["driveway_private"] as Rect2).get_center(), "24 Maple Street"]]
	for s in spots:
		var p: Vector2 = s[0]
		pl.teleport(Vector3(p.x, Snow.surface_height(p.x, p.y) + 0.05, p.y))
		await _frames(30)
		var t: String = world.hud.contract_l.text
		runner.check(world.hud.contract_panel.visible and t.begins_with(str(s[1]) + " — "), "§5 the HUD box line: \"%s\"" % t.split("\n")[0])
	# The board, a contract, its notifications and the history.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	Contracts._add_area_listing(Layout.big_areas[0], Clock.day_index(), rng)
	Contracts._add_lot_listing(Layout.lots[10], Clock.day_index(), rng)
	Contracts.listings[-1]["type"] = "one_time"
	var lb := []
	for l in Contracts.listings:
		if l["address"] != Layout.place_name(str(l["target"])):
			lb.append(l["address"])
	runner.check(lb.is_empty() and Contracts.listings.size() >= 2, "§5 every listing on the board is named by its address (%d) %s" % [Contracts.listings.size(), str(lb)])
	world.open_computer()
	await _frames(2)
	var comp = world.modal
	Game.company_name = "Test Snow Co."   # polish 5 §7: named, so the board shows (not the name form)
	comp._open_app(ComputerUI.app_index("board"))
	await _frames(2)
	var board := _s2_texts(comp)
	runner.check(board.contains("Maple Ridge School, 12 Cedar Lane") and board.contains("28 Maple Street"), "§5 the contract board shows them so")
	world.close_modal()
	await _frames(2)
	var la: Dictionary = Contracts.listings[Contracts.listings.size() - 2]
	Contracts.adjust_reputation(Contracts.tier_threshold(1) - Game.reputation)   # §10: parking lots are Commercial work
	var n0 := Notify.history.size()
	Contracts.place_bid(int(la["lid"]), Contracts.bid_floor(la))   # §10: nobody bids under the floor
	var c := Contracts.force_award(int(Contracts.listings[Contracts.listings.size() - 1]["lid"]))
	runner.check(c["address"] == "28 Maple Street" and Notify.history[n0]["text"].contains("Maple Ridge School, 12 Cedar Lane"), "§5 the contract and the bid's notification name the place by its address")
	for z in c["zones"]:
		for id in z["boxes"]:
			for r in Boxes.get_box(id)["rects"]:
				Snow.set_rect(r, 0.0)
			Boxes.measure(Boxes.get_box(id), true)
	await _frames(5)
	runner.check(not Contracts.history.is_empty() and Contracts.history[-1]["address"] == "28 Maple Street" and Notify.history[-1]["text"].contains("28 Maple Street"), "§5 …done: in the history and the notification by its address")
	# The store's address in the texts that say where it is.
	world.open_computer()
	await _frames(2)
	comp = world.modal
	var store_txt := ""
	for i in range(ComputerUI.APPS.size()):
		comp._open_app(i)
		await _frames(1)
		store_txt += _s2_texts(comp)
	world.close_modal()
	runner.check(store_txt.contains("parking lot at 11 Cedar Lane") and store_txt.contains("Northern Supply Co., 11 Cedar Lane"), "§5 the store and orders apps give the store's address")
	runner.check(HelpText.explanation(false).any(func(ln): return str(ln["text"]).contains("Northern Supply Co. at 11 Cedar Lane")), "§5 Gerry gives the store's address")
	await _unload()
	# An old save: its board has the store lot, saved as "Northern Supply Co. parking lot".
	var ok: bool = await _load_save_file("res://tests/fixtures/polish5/fun_1_contracts.json")
	var store_l := Contracts.listings.filter(func(l): return str(l["target"]) == "area:store_lot")
	runner.check(ok and store_l.size() == 1 and store_l[0]["address"] == "Northern Supply Co., 11 Cedar Lane", "§5 an old save's store-lot listing reads \"%s\"" % (store_l[0]["address"] if store_l.size() == 1 else "?"))
	var all_ok := true
	for x in Contracts.active + Contracts.listings:
		all_ok = all_ok and x["address"] == Layout.place_name(str(x["target"]))
	runner.check(all_ok, "§5 …and every contract and listing in it is named by its address")
	var d := Contracts.serialize().duplicate(true)
	d["history"] = [{"id": 1, "address": "St. Andrew's Church parking lot", "pay": 10, "time": 0.0}]
	Contracts.deserialize(d)
	var e := Economy.serialize().duplicate(true)
	e["tx"] = [{"time": 0.0, "text": "Contract payment: St. Andrew's Church parking lot", "amount": 10}]
	Economy.deserialize(e)
	runner.check(Contracts.history[0]["address"] == "St. Andrew's Church, 40 Cedar Lane" and Economy.transactions[0]["text"] == "Contract payment: St. Andrew's Church, 40 Cedar Lane", "§5 …its history and transactions too")
	Saves.delete_save("fun")


## The map: every house's and building's number on its lot, the street names, readable at the
## default zoom (the 1920 × 1080 canvas, and 4:3 and 21:9 screens), no label over another.
func test_s5_map_shows_every_number() -> void:
	await _s3_world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	Contracts._add_lot_listing(Layout.lots[9], Clock.day_index(), rng)
	Contracts.listings[-1]["type"] = "one_time"
	Contracts.force_award(int(Contracts.listings[-1]["lid"]))
	var m := MapUI.new()
	world.ui.add_child(m)
	world.open_modal(m, "map")
	await _frames(2)
	for vs in [Vector2(1920, 1080), Vector2(1920, 1440), Vector2(2520, 1080)]:
		var ls: Array = m.labels(vs)
		var probs := []
		for lot in Layout.lots:
			var lr := Rect2(m._to_px((lot["rect"] as Rect2).position), (lot["rect"] as Rect2).size * m.scale_px)
			var nl := ls.filter(func(l): return l["kind"] == "number" and l["key"] == str(lot["index"]))
			if nl.size() != 1 or nl[0]["text"] != str(lot["number"]) or not lr.encloses(nl[0]["rect"]) or int(nl[0]["size"]) < 18:
				probs.append(lot["address"])
			for t in ls.filter(func(l): return l["kind"] == "tag" and l["key"] == str(lot["index"])):
				if not lr.encloses(t["rect"]):
					probs.append("%s: its %s off the lot" % [lot["address"], t["text"]])
		for b in Layout.buildings:
			var br := Rect2(m._to_px((b["rect"] as Rect2).position), (b["rect"] as Rect2).size * m.scale_px)
			var al := ls.filter(func(l): return l["kind"] == "building_address" and l["key"] == b["id"])
			var nm := ls.filter(func(l): return l["kind"] == "building" and l["key"] == b["id"])
			var name_in: bool = " ".join(nm.map(func(l): return l["text"])) == b["name"] and nm.all(func(l): return br.encloses(l["rect"]) and int(l["size"]) >= 12)
			if al.size() != 1 or al[0]["text"] != b["address"] or not br.encloses(al[0]["rect"]) or not name_in or int(al[0]["size"]) < 13:
				probs.append(b["address"])
		for r in Layout.roads:
			var sl := ls.filter(func(l): return l["kind"] == "street" and l["text"] == str(r["name"]).to_upper())
			if sl.size() != 1 or not Rect2(m._to_px((r["rect"] as Rect2).position), (r["rect"] as Rect2).size * m.scale_px).encloses(sl[0]["rect"]):
				probs.append(r["name"])
		var over := []
		for i in range(ls.size()):
			for j in range(i + 1, ls.size()):
				if (ls[i]["rect"] as Rect2).intersects(ls[j]["rect"]):
					over.append("%s / %s" % [ls[i]["text"], ls[j]["text"]])
		var tags := ls.filter(func(l): return l["kind"] == "tag").map(func(l): return l["text"])
		runner.check(probs.is_empty() and over.is_empty(), "§5 the map at %dx%d: %d labels — every house number on its lot (18 px), every building's address on it, the three street names, none overlapping %s %s" % [vs.x, vs.y, ls.size(), str(probs), str(over)])
		runner.check("HOME" in tags and "vacant" in tags and tags.any(func(t): return str(t) == MapUI.due_tag(Contracts.active[-1])), "§5 …with HOME, vacant and (§10) when a contract is due under their numbers %s" % str(tags))
	world.close_modal()
	await _unload()


# =============================================================================
# §6 Tools: models and icons
# =============================================================================

const S6_TOOLS := ["small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh", "electric_shovel"]
const S6_MACHINES := ["small_blower", "large_blower"]
## The tool profiles before §6 (HANDOFF §7): [width, push width, capacity, fill rate, throw, push
## strength, intake rate]. The models changed; the profiles didn't.
const S6_PROFILES := {
	"hands": [0.4, 0.5, 0.03, 0.085, 1.8, 0.035, 0.0],
	"small_shovel": [0.34, 0.36, 0.05, 0.13, 4.2, 0.09, 0.0],
	"standard_shovel": [0.46, 0.48, 0.065, 0.16, 5.2, 0.14, 0.0],
	"wide_pusher": [0.9, 0.9, 0.045, 0.09, 2.2, 0.5, 0.0],
	"snow_scraper": [0.75, 0.75, 0.05, 0.1, 2.8, 0.6, 0.0],
	"large_scraper": [1.0, 1.2, 0.08, 0.16, 3.4, 0.95, 0.0],
	"snow_sleigh": [0.8, 0.8, 0.4, 0.32, 1.0, 1.4, 0.0],
	"electric_shovel": [0.32, 0.34, 0.03, 0.05, 5.0, 0.08, 0.05],
	"small_blower": [0.56, 0.4, 0.03, 0.05, 8.0, 0.1, 0.065],
	"large_blower": [0.78, 0.4, 0.03, 0.05, 12.5, 0.1, 0.14],
}


## The triangles of a mesh (every surface), as a flat array of vertices (three per triangle).
static func _s6_tris(m: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for si in range(m.get_surface_count()):
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if arr[Mesh.ARRAY_INDEX] != null and not (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
				out.append(v[i])
		else:
			out.append_array(v)
	return out


## Closest point to p on the triangle abc.
static func _s6_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


## How far p is from the mesh's surface (its nearest triangle).
static func _s6_dist(p: Vector3, tris: PackedVector3Array) -> float:
	var best := INF
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		# Skip triangles whose bounds are farther than the best so far.
		var lo := a.min(b).min(c) - Vector3.ONE * best
		var hi := a.max(b).max(c) + Vector3.ONE * best
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			continue
		best = minf(best, p.distance_to(_s6_on_tri(p, a, b, c)))
	return best


## Blade widths match the tool profiles (the scoop width; between it and the push width where they
## differ), which are as they were; each blade rests on the snow at the shaft's tip as before; the
## load still sits on (or, for a pusher or scraper, against) the blade; the blowers' intakes match
## their widths.
func test_s6_blades_match_the_profiles() -> void:
	var bad := []
	for id in S6_PROFILES.keys():
		var t: ToolData = Catalog.tool(StringName(id))
		var p: Array = S6_PROFILES[id]
		var now := [t.width, t.push_width, t.capacity, t.fill_rate, t.throw_distance, t.push_strength, t.rate]
		for k in range(p.size()):
			if not is_equal_approx(float(p[k]), float(now[k])):
				bad.append("%s value %d: %s -> %s" % [id, k, p[k], now[k]])
	runner.check(bad.is_empty(), "§6 the tool profiles are unchanged (width, push width, capacity, fill, throw, push strength, intake) %s" % str(bad))
	var widths := []
	for id in S6_TOOLS:
		var t: ToolData = Catalog.tool(StringName(id))
		var bm := ToolModels.blade_mesh(id)
		var ab := bm.get_aabb()
		var span: Vector2 = ToolModels.edge_span.get(id, Vector2.ZERO)
		var edge_ok := is_equal_approx(span.x, -t.width * 0.5) and is_equal_approx(span.y, t.width * 0.5)
		var lo := minf(t.width, t.push_width) - 0.015
		var hi := maxf(t.width, t.push_width) + 0.015
		var outer_ok := (ab.size.x >= t.width - 0.001 and ab.size.x <= t.width + 0.06) if t.kind == ToolData.Kind.ELECTRIC_SHOVEL else (absf(ab.size.x - t.width) <= 0.015 and ab.size.x >= lo and ab.size.x <= hi)
		widths.append("%s %.3f (profile %.2f / push %.2f)" % [id, ab.size.x, t.width, t.push_width])
		runner.check(edge_ok and outer_ok, "§6 %s: the blade is %.3f m wide, its cutting edge %.3f m — the profile's %.2f m (push %.2f m)" % [id, ab.size.x, span.y - span.x, t.width, t.push_width])
		runner.check(ab.position.y >= -0.03 and ab.position.y <= 0.005, "§6 %s: the blade rests on the snow at the shaft's tip (lowest point %.3f m)" % [id, ab.position.y])
		# The load: in the scoop for shovels and the sleigh, against the face for pushers/scrapers.
		var lp := ToolModels.blade_offset(id) - ToolModels.tip(id)
		var inside := absf(lp.x) < ab.size.x * 0.5 and lp.y > ab.position.y and lp.y < ab.end.y
		match t.kind:
			ToolData.Kind.SHOVEL, ToolData.Kind.SLEIGH:
				inside = inside and lp.z > ab.position.z and lp.z < ab.end.z
			ToolData.Kind.PUSHER, ToolData.Kind.SCRAPER:
				inside = inside and lp.z < ab.position.z + 0.01 and lp.z > ab.position.z - 0.15
		if t.kind != ToolData.Kind.ELECTRIC_SHOVEL:
			runner.check(inside, "§6 %s: the load heaps on its blade (%.2f, %.2f, %.2f in the blade's frame)" % [id, lp.x, lp.y, lp.z])
	runner.info("§6 blade widths: " + ", ".join(widths))
	for id in S6_MACHINES:
		var t: ToolData = Catalog.tool(StringName(id))
		var ab := ToolModels.mesh_for(id).get_aabb()
		var span: Vector2 = ToolModels.edge_span.get(id, Vector2.ZERO)
		runner.check(is_equal_approx(span.y - span.x, t.width) and ab.size.x >= t.width and ab.size.x <= t.width + 0.12 and ab.position.y > -0.02,
			"§6 %s: the intake is %.2f m wide (profile %.2f m), the machine %.2f m across, standing on the ground" % [id, span.y - span.x, t.width, ab.size.x])


## The models: first person keeps a separate handle and blade (both through the viewmodel clip
## shader that hides what's under the snow), the world / third-person model is the tool shader in
## several materials; both hands' grip points lie on the new grip and shaft; the 17 exposure points
## lie on the new shaft and blade; the blowers' chute is part of the model and turns at the old pivot.
func test_s6_models_grips_and_exposure_points() -> void:
	var clip := load("res://shaders/viewmodel_clip.gdshader")
	var tool_sh := load("res://shaders/tool.gdshader")
	for id in S6_TOOLS:
		var t: ToolData = Catalog.tool(StringName(id))
		var hm := ToolModels.handle_mesh(id)
		var bm := ToolModels.blade_mesh(id)
		var wm := ToolModels.mesh_for(id)
		var fp_ok := hm != bm and hm.get_surface_count() > 0 and bm.get_surface_count() > 0
		for m in [hm, bm]:
			for si in range((m as Mesh).get_surface_count()):
				var mat := (m as Mesh).surface_get_material(si)
				fp_ok = fp_ok and mat is ShaderMaterial and (mat as ShaderMaterial).shader == clip
		runner.check(fp_ok, "§6 %s: first person has its own handle (%d parts) and blade (%d), each through the clip shader" % [id, hm.get_surface_count(), bm.get_surface_count()])
		var finishes := {}
		var world_ok := true
		for si in range(wm.get_surface_count()):
			var mat2 := wm.surface_get_material(si)
			world_ok = world_ok and mat2 is ShaderMaterial and (mat2 as ShaderMaterial).shader == tool_sh
			if mat2 is ShaderMaterial:
				finishes[int((mat2 as ShaderMaterial).get_shader_parameter("finish"))] = true
		runner.check(world_ok and finishes.size() >= 3 and not finishes.has(ToolModels.FIN_PLAIN) and wm.get_surface_count() <= 9,
			"§6 %s: the model is %d draw surfaces in %d materials (finishes %s)" % [id, wm.get_surface_count(), finishes.size(), str(finishes.keys())])
		# Both hands: the grip points (ToolController._grip_frames) on the handle's geometry.
		var tc := ToolController.new()
		tc.tool_id = id
		tc.data = t
		var frames := tc._grip_frames()
		tc.free()
		var htris := _s6_tris(hm)
		var gd := []
		for f in frames:
			gd.append(_s6_dist(f["point"], htris))
		runner.check(gd.size() == 2 and float(gd[0]) <= 0.025 and float(gd[1]) <= 0.025, "§6 %s: both hands' grip points are on the grip and the shaft (%.3f / %.3f m from the surface)" % [id, gd[0], gd[1]])
		# The 17 exposure points on the shaft and the blade.
		var pts := ToolModels.sample_points(id)
		var wtris := _s6_tris(wm)
		var worst := 0.0
		for p in pts:
			worst = maxf(worst, _s6_dist(p, wtris))
		runner.check(pts.size() == 17 and worst <= 0.03, "§6 %s: its %d exposure points lie on the shaft and the blade (worst %.3f m off)" % [id, pts.size(), worst])
	for id in S6_MACHINES:
		var cm := ToolModels.chute_mesh(id)
		var ab := cm.get_aabb()
		runner.check(cm.get_surface_count() > 0 and absf(ab.get_center().x) < 0.01 and ab.position.y < -0.1 and ab.end.y > 0.2 and ab.position.z < -0.2,
			"§6 %s: the chute model rises from the housing at the pivot and its deflector points forward (%s)" % [id, str(ab)])
	# A blower in the world uses it, at the same pivot.
	await _s3_world("fun")
	var e := {"uid": Game.uid(), "tool": "small_blower", "pos": Vector3(60, 0, 83), "yaw": 0.0}
	Game.machines.append(e)
	var wb: WalkBehind = world.spawn_machine_node(e)
	await _frames(2)
	var cmi: MeshInstance3D = wb.chute.get_child(0)
	runner.check(wb.chute.position == Vector3(0, 0.62, -0.25) and cmi.mesh == ToolModels.chute_mesh("small_blower") and wb.mesh.mesh == ToolModels.mesh_for("small_blower"), "§6 the walk-behind blower wears the model and turns the model's chute at the same pivot")
	Game.machines.erase(e)
	await _unload()


## Every Icons control under n (depth first).
static func _s6_icons(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Icons:
			out.append(c)
		out.append_array(_s6_icons(c))
	return out


## One icon set: the hotbar, the store, the upgrades and the inventory use the same Icons; the rendered
## set comes from a stage with one orthographic camera (the same angle), the same lights, one model
## per icon, each framed in its own square (long tools all laid the same way); headless there is
## no render and the drawn icons stand in (no test depends on a captured image). Bare hands keep
## the mitten; empty slots stay dimmed.
func test_s6_one_icon_set() -> void:
	runner.check(DisplayServer.get_name() == "headless" and ToolIcons.texture("small_shovel") == null and ToolIcons.state == "headless", "§6 headless: no icon render; the drawn icons stand in")
	var ids := ToolIcons.ids()
	runner.check(ids.size() == Catalog.TOOL_IDS.size() and ids[0] == "" and ids.has("large_blower") and ids.has("electric_shovel"), "§6 one icon for bare hands (the mitten) and every tool and machine (%d)" % ids.size())
	var holder := Node3D.new()
	runner.add_child(holder)
	@warning_ignore("integer_division")
	var rows := (ids.size() + ToolIcons.COLS - 1) / ToolIcons.COLS
	var st := ToolIcons.build_stage(holder, ids, rows)
	var cams := holder.find_children("*", "Camera3D", true, false)
	var lights := holder.find_children("*", "DirectionalLight3D", true, false)
	runner.check(cams.size() == 1 and (cams[0] as Camera3D).projection == Camera3D.PROJECTION_ORTHOGONAL and lights.size() == 3, "§6 the icon stage: one orthographic camera (every icon seen from the same angle), the same three lights")
	var cam: Camera3D = st["camera"]
	var ci := cam.basis.inverse()
	var framed := []
	var axes := []
	for it in st["items"]:
		var cell: Vector2 = it["cell"]
		var r: Rect2 = it["rect"]
		if not Rect2(cell - Vector2(0.5, 0.5), Vector2.ONE).grow(0.001).encloses(r) or r.size.x < 0.5 and r.size.y < 0.5:
			framed.append(it["id"])
		var id: String = it["id"]
		if id != "" and Catalog.tool(StringName(id)).kind != ToolData.Kind.WALK_BLOWER:
			var g: Vector3 = ci * ((it["pose"] as Basis) * ToolModels.blade_offset(id))
			axes.append(rad_to_deg(Vector2(g.x, g.y).angle_to(ToolIcons.SCREEN_AXIS)))
	runner.check(framed.is_empty() and (st["items"] as Array).size() == ids.size(), "§6 every icon framed in its own square, filling it %s" % str(framed))
	runner.check(axes.all(func(a): return absf(a) < 1.0), "§6 the long tools all laid the same way in their icons (%s°)" % str(axes.map(func(a): return snappedf(a, 0.01))))
	holder.queue_free()
	# The hotbar: the set's icons, the mitten for bare hands, empty slots dimmed.
	await _s3_world("fun")
	Game.slots = ["small_shovel", "", "wide_pusher", ""]
	Game.selected = 1
	Game.inventory_changed.emit()
	await _frames(2)
	var hud = world.hud
	var ok := true
	for i in range(4):
		var ic: Icons = hud.slot_icons[i]
		ok = ok and ic.tool_id == Game.slots[i] and ic.is_in_group("tool_icons")
	var dim: Array = hud.slot_icons.map(func(ic): return snappedf((ic as Control).modulate.a, 0.01))
	var want_dim := [1.0, 1.0, 1.0, 0.35]
	for i in range(4):
		ok = ok and is_equal_approx(float(dim[i]), want_dim[i])
	runner.check(ok, "§6 the hotbar shows the set: the tools, the mitten in the selected empty slot, the other empty slot dimmed %s" % str(dim))
	# The store and the upgrades.
	Game.flags["computer_unlocked"] = true
	world.open_computer()
	await _tree().process_frame
	var comp: ComputerUI = world.modal
	comp._open_app(ComputerUI.app_index("store"))
	await _tree().process_frame
	var store_ids := _s6_icons(comp.content).map(func(n): return (n as Icons).tool_id)
	var want := Catalog.store_tools().map(func(td): return String((td as ToolData).id))
	runner.check(want.all(func(x): return x in store_ids), "§6 the store: every tool and machine card shows its icon from the set (%d icons)" % store_ids.size())
	comp._open_app(ComputerUI.app_index("upgrades"))
	await _tree().process_frame
	var up_ids := _s6_icons(comp.content).map(func(n): return (n as Icons).tool_id)
	# §13: upgrades belong to an item — each owned tool's card shows that tool's own icon (the mitten
	# for bare hands), in the ladder's order; vehicles have no icon.
	var want_up := []
	for g in ComputerUI.upgrade_groups():
		if ComputerUI._group_owned(g) and ComputerUI._item_icon(g[0]) != "-":
			want_up.append(ComputerUI._icon_id(String(g[0])))
	runner.check(up_ids == want_up and want_up.size() >= 3, "§6 the upgrades: each owned tool's card shows its own icon from the set %s" % str(up_ids))
	world.close_modal()
	await _tree().process_frame
	# The inventory panel.
	var inv: Control = Panels.inventory(hud)
	var inv_ids := _s6_icons(inv).map(func(n): return (n as Icons).tool_id)
	runner.check(inv_ids == Game.slots, "§6 the inventory panel uses the same icons %s" % str(inv_ids))
	inv.queue_free()
	await _unload()


# =============================================================================
# §7 The computer
# =============================================================================

## The apps the brief lists, in its order; the rest keep their old order after Orders.
const S7_ORDER := ["Weather", "Contracts", "Contract board", "Equipment store", "Upgrades", "Bills & payments", "Orders"]
const S7_REST := ["Property & storage", "Help"]
## Logical canvases (stretch canvas_items / aspect expand, base 1920×1080): the game has no separate
## UI-scale setting, so each resolution's UI scale is the one its canvas gives (as pass 3 / 4 test).
const S7_CANVASES := {"1280x720": Vector2(1920, 1080), "1920x1080": Vector2(1920, 1080),
	"2560x1440": Vector2(1920, 1080), "3440x1440": Vector2(2580, 1080)}


func _s7_open() -> ComputerUI:
	world.open_computer()
	await _frames(2)
	return world.modal as ComputerUI


## Press a button under `root` by its text (first match, enabled), from a process frame.
func _s7_press(root: Node, text: String) -> bool:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text and not (b as Button).disabled and (b as Button).is_visible_in_tree():
			await _tree().process_frame
			(b as Button).pressed.emit()
			await _frames(2)
			return true
	return false


## A real key / mouse event for an action's binding, as a keyboard sends it (with the character it
## types, for printable keys); mouse buttons at `at` (canvas coordinates).
func _s7_event(action: String, down: bool, at := Vector2.ZERO) -> InputEvent:
	var e := _s2_event(action, down)
	if e is InputEventKey:
		var k := (e as InputEventKey).keycode
		if down and ((k >= KEY_A and k <= KEY_Z) or (k >= KEY_0 and k <= KEY_9) or k == KEY_SPACE):
			(e as InputEventKey).unicode = OS.get_keycode_string(k).to_lower().unicode_at(0) if k != KEY_SPACE else 32
	elif e is InputEventMouseButton:
		var p: Vector2 = _tree().root.get_final_transform() * at
		(e as InputEventMouseButton).position = p
		(e as InputEventMouseButton).global_position = p
	return e


## What a game action could change, as text (the clock is stopped, so nothing else moves).
func _s7_state() -> String:
	var pl: Player = world.player
	return var_to_str({"game": Game.serialize(), "contracts": Contracts.serialize(), "economy": Economy.serialize(),
		"boxes": Boxes.serialize(), "state": pl.state, "tp": pl.third_person, "yaw": pl.yaw, "pitch": pl.pitch,
		"load": pl.tools.load, "notes": Notify.history.size(), "modal": world.modal_kind, "inv": world.inventory_panel != null,
		"vehicles": world.vehicle_nodes().map(func(v): return [(v as Vehicle).occupied, (v as Vehicle).global_position.snapped(Vector3(0.01, 0.01, 0.01))])})


## The app order: exactly the brief's, then the rest as before; the sidebar, the monitor's desktop
## and its taskbar follow it; one layout (header with the company, reputation, money, day and time;
## sidebar; title over the content) in every app.
func test_s7_app_order_and_layout() -> void:
	runner.check(ComputerUI.APPS == S7_ORDER + S7_REST, "§7 the apps in order: %s" % str(ComputerUI.APPS))
	runner.check(ComputerUI.APP_IDS.size() == ComputerUI.APPS.size() and ComputerUI.app_index("weather") == 0 and ComputerUI.app_index("board") == 2, "§7 each app has a stable id (%s)" % str(ComputerUI.APP_IDS))
	await _s3_world("survival")
	Game.company_name = "Layout Test Snow Co."
	var c := await _s7_open()
	var names: Array = c.app_buttons.map(func(b): return (b as Button).text)
	runner.check(names == ComputerUI.APPS, "§7 the sidebar lists them in that order %s" % str(names))
	var bad := []
	for i in range(ComputerUI.APPS.size()):
		c._open_app(i)
		await _frames(2)
		var ok: bool = c.find_child("Header", true, false) != null and c.find_child("Sidebar", true, false) != null and c.find_child("Main", true, false) != null
		ok = ok and c.title_l.text == ComputerUI.APPS[i] and c.content.get_child_count() > 0
		ok = ok and c.company_l.text == Game.company_name and c.reputation_l.text == ComputerUI.reputation_text()   # §10: with the tier
		ok = ok and c.balance_l.text == UIKit.money(Game.money) and c.clock_l.text.contains(Clock.time_string()) and c.clock_l.text.contains(Clock.date_string(Clock.day_index(), true))
		if not ok:
			bad.append(ComputerUI.APPS[i])
	runner.check(bad.is_empty(), "§7 every app: the header (company, reputation, money, day and time), the sidebar and its title over the content %s" % str(bad))
	world.close_modal()
	await _frames(2)
	# The monitor's desktop: the same apps in the same order (two columns, top to bottom), names that
	# fit under their icons, and the taskbar's pins in that order too.
	var scr: ComputerScreen = world.interior["screen"]
	var icons := []
	var pins := []
	for n in scr._desktop.get_children():
		if n.get("app") == null:
			continue
		if n.get("small"):
			pins.append(n)
		else:
			icons.append(n)
	icons.sort_custom(func(a, b): return a.position.x < b.position.x - 1.0 or (absf(a.position.x - b.position.x) <= 1.0 and a.position.y < b.position.y))
	pins.sort_custom(func(a, b): return a.position.x < b.position.x)
	var order: Array = icons.map(func(n): return ComputerUI.APPS[int(n.get("app"))])
	runner.check(order == ComputerUI.APPS, "§7 the monitor's desktop shows the same apps in the same order %s" % str(order))
	var fit := true
	for n in icons:
		var nm: String = ComputerUI.APPS[int(n.get("app"))]
		var fs: int = ComputerScreen.AppIcon.label_size(nm, (n as Control).size.x)
		fit = fit and fs >= 8 and ThemeDB.fallback_font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= (n as Control).size.x
	runner.check(fit, "§7 …each name fits under its icon")
	var pin_ids: Array = pins.map(func(n): return ComputerUI.APP_IDS[int(n.get("app"))])
	runner.check(pin_ids == ["weather", "contracts", "board", "store"], "§7 …and the taskbar pins follow the order %s" % str(pin_ids))
	await _unload()


## Weather first, every time it's used once unlocked: after another app, after closing and opening
## again, after save → load. Before Gerry's quest it stays locked, as before.
func test_s7_opens_on_weather() -> void:
	await _unload()
	Game.force_input = true
	Game.new_game("fun", 2024)
	Clock.reset(Clock.at(0, 9.0))
	await _spawn_world()
	world.open_computer()
	await _frames(2)
	runner.check(world.modal == null and not Game.computer_unlocked(), "§7 the computer is still locked before Gerry's quest")
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	var weather := ComputerUI.app_index("weather")
	var c := await _s7_open()
	runner.check(c != null and c.current == weather and c.title_l.text == "Weather", "§7 unlocked, it opens on Weather")
	for id in ["store", "contracts", "board", "help"]:
		c._open_app(ComputerUI.app_index(id))
		await _frames(1)
		world.close_modal()
		await _frames(2)
		c = await _s7_open()
		runner.check(c.current == weather and c.title_l.text == "Weather", "§7 …closed on %s, it opens on Weather again" % id)
	c._open_app(ComputerUI.app_index("orders"))
	world.close_modal()
	await _frames(2)
	runner.check(Saves.save_game(), "§7 saved")
	await _unload()
	runner.check(Saves.load_game("fun"), "§7 loaded")
	await _spawn_world()
	c = await _s7_open()
	runner.check(c != null and c.current == weather and c.title_l.text == "Weather", "§7 …and after save → load")
	world.close_modal()
	Saves.delete_save("fun")
	await _unload()


## The company's name: the form appears once, on whichever of Contracts and the Contract board comes
## first, before anything else; 1–24 characters, trimmed, never empty; a neutral suggestion; renamed
## from Contracts; saved; shown in the header, Contracts, the board, an award, the history, the map
## legend and the end-of-winter summary.
func test_s7_company_name() -> void:
	for first in ["contracts", "board"]:
		await _s3_world("fun")
		runner.check(Game.company_name == "", "§7 a new game has no company name")
		var c := await _s7_open()
		runner.check(not c.form_up(), "§7 no form on Weather")
		var idx := ComputerUI.app_index(first)
		c._open_app(idx)
		await _frames(3)
		var sugg := Game.suggested_company_name()
		runner.check(c.form_up() and c.title_l.text == "Name your company" and c.name_edit.text == sugg and c.name_edit.has_focus() and c.name_edit.max_length == Game.COMPANY_NAME_MAX,
			"§7 %s first: the form, with the suggestion \"%s\" and the focus in the field" % [first, sugg])
		var shown := _s2_texts(c.content)
		runner.check(not shown.contains("Place bid") and c.content.find_child("Tabs", true, false) == null and shown.contains("1 to 24 characters"), "§7 …before anything else of the app")
		runner.check(sugg.length() >= 1 and sugg.length() <= Game.COMPANY_NAME_MAX and not sugg.contains(Layout.player_lot["address"]), "§7 the suggestion is neutral and valid")
		for t in ["", "   ", "\t "]:
			c.name_edit.text = t
			await _s7_press(c.content, "OK")
			runner.check(Game.company_name == "" and c.form_up() and c._name_err.text != "", "§7 an empty name (\"%s\") is refused" % t.c_escape())
		c.name_edit.text = ""
		c.name_edit.text_submitted.emit("")
		await _frames(1)
		runner.check(Game.company_name == "" and c.form_up(), "§7 …also with Enter")
		runner.check(not Game.set_company_name("x".repeat(Game.COMPANY_NAME_MAX + 1)) and Game.set_company_name(" " + "y".repeat(Game.COMPANY_NAME_MAX) + " ") and Game.company_name == "y".repeat(Game.COMPANY_NAME_MAX), "§7 25 characters are refused, 24 kept (trimmed)")
		Game.company_name = ""
		c._rebuild(true)
		await _frames(2)
		c.name_edit.text = "  Polar Bear Snow  "
		await _s7_press(c.content, "OK")
		runner.check(Game.company_name == "Polar Bear Snow" and not c.form_up() and c.title_l.text == ComputerUI.APPS[idx], "§7 a name is taken trimmed (\"%s\") and the app shows" % Game.company_name)
		var other := "board" if first == "contracts" else "contracts"
		c._open_app(ComputerUI.app_index(other))
		await _frames(2)
		runner.check(not c.form_up(), "§7 …and %s doesn't ask again" % other)
		world.close_modal()
		await _frames(2)
		c = await _s7_open()
		c._open_app(idx)
		await _frames(2)
		runner.check(not c.form_up(), "§7 …nor %s when the computer is opened again (the form appears once)" % first)
		world.close_modal()
		await _frames(2)
	# Renaming, from Contracts.
	var cr := await _s7_open()
	cr._open_app(ComputerUI.app_index("contracts"))
	await _frames(2)
	runner.check(await _s7_press(cr.content, "Rename") and cr.form_up() and cr.name_edit.text == "Polar Bear Snow" and cr.title_l.text == "Rename your company", "§7 Rename (in Contracts) opens the form with the name")
	await _s7_press(cr.content, "Cancel")
	runner.check(not cr.form_up() and Game.company_name == "Polar Bear Snow", "§7 …Cancel keeps it")
	await _s7_press(cr.content, "Rename")
	cr.name_edit.text = "Maple Ridge Clearing"
	cr.name_edit.text_submitted.emit(cr.name_edit.text)
	await _frames(2)
	runner.check(Game.company_name == "Maple Ridge Clearing" and not cr.form_up(), "§7 …and renames it (Enter)")
	# Where the name shows.
	runner.check(cr.company_l.text == Game.company_name and cr.reputation_l.text == ComputerUI.reputation_text() and cr.reputation_l.text.begins_with("Reputation %d" % int(Game.reputation)), "§7 the header: the company and its reputation (§10: and its tier)")
	runner.check(_s2_texts(cr.content).contains(Game.company_name) and _s2_texts(cr.content).contains("Reputation %d" % int(Game.reputation)), "§7 Contracts: the company and its reputation")
	cr._open_app(ComputerUI.app_index("board"))
	await _frames(2)
	runner.check(_s2_texts(cr.content).contains("Bidding as Maple Ridge Clearing"), "§7 the board: \"Bidding as …\"")
	# Polish 5 §10: a bid at the floor on an open listing (nobody bids lower; a tie goes to you), and
	# the award at 9:01 p.m. (was: an answer a few hours later).
	var open_l: Array = Contracts.listings.filter(func(x): return not Contracts.listing_locked(x))
	var lid := int(open_l[0]["lid"])
	var addr: String = open_l[0]["address"]
	Contracts.place_bid(lid, Contracts.bid_floor(open_l[0]))
	Clock.minutes = float(open_l[0]["closes"]) + Contracts.AWARD_DELAY_MIN + 0.5
	Contracts.on_advance(Contracts.AWARD_DELAY_MIN + 1.0)   # a step through 9 p.m. and 9:01 p.m.
	runner.check(Notify.history[-1]["text"].contains("Maple Ridge Clearing wins " + addr), "§7 the award names it: \"%s\"" % Notify.history[-1]["text"])
	cr.show_contracts_tab(1)
	cr._open_app(ComputerUI.app_index("contracts"))
	await _frames(2)
	runner.check(cr.contracts_tab == 1 and _s2_texts(cr.content).contains(Game.company_name), "§7 the history, under the company's name")
	world.close_modal()
	await _frames(2)
	runner.check(MapUI.contracts_heading().contains(Game.company_name), "§7 the map legend: \"%s\"" % MapUI.contracts_heading())
	var sum := Panels.summary(world.hud, func(_ids): pass)
	runner.check(_s2_texts(sum).contains(Game.company_name), "§7 the end-of-winter summary")
	sum.queue_free()
	# Saved and reloaded.
	runner.check(Saves.save_game(), "§7 saved")
	Game.company_name = ""
	runner.check(Saves.load_game("fun") and Game.company_name == "Maple Ridge Clearing", "§7 the name is saved and reloaded (\"%s\")" % Game.company_name)
	Saves.delete_save("fun")
	await _unload()


## Input isolation: while the name field has the focus, every game key and mouse button (each
## action's binding, so a fast-forward key added later is included) types text or does nothing —
## nothing in the game changes; Esc leaves the field, and the next Esc closes the computer.
func test_s7_typing_fires_no_game_action() -> void:
	await _s3_world("survival")
	var pl: Player = world.player
	var lot := Layout.player_lot
	var spot := Layout.lot_to_world(lot, Layout.gu(lot, -5.0), 4.0)
	Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), 0.0)
	pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
	Game.slots = ["standard_shovel", "", "", ""]
	Game.selected = 0
	Game.heat_pouches = 3
	world.spawn_tool_item("wide_pusher", Vector3(spot.x, 0, spot.y - 0.8), 0.0)   # E would pick it up
	pl.pitch = deg_to_rad(-40.0)
	pl.head.rotation.x = pl.pitch
	await _frames(6)
	var c := await _s7_open()
	c._open_app(ComputerUI.app_index("contracts"))
	await _frames(3)
	runner.check(c.form_up() and c.name_edit.has_focus() and Game.typing(), "§7 the name field has the focus")
	await _frames(10)
	var pos0 := pl.global_position
	var s0 := _s7_state()
	var sent := []
	var inv_shown := false
	var focus_kept := true
	for a in Settings.ACTIONS.keys():
		if a == "pause":
			continue
		if not c.name_edit.has_focus():
			c.name_edit.grab_focus()      # Tab moved the focus on (UI navigation): the field takes it back
			c.name_edit.edit()
		var fr := c.name_edit.get_global_rect()
		var at := Vector2(fr.end.x - 12.0, fr.get_center().y)   # on the field, after the text
		var d := _s7_event(a, true, at)
		if d == null:
			continue
		Input.parse_input_event(d)
		await _frames(3)
		inv_shown = inv_shown or world.inventory_panel != null
		focus_kept = focus_kept and (c.name_edit.has_focus() or a == "inventory")
		Input.parse_input_event(_s7_event(a, false, at))
		await _frames(2)
		sent.append("%s=%s" % [a, Settings.action_label(a)])
	_release_all()
	await _frames(4)
	runner.info("sent: " + ", ".join(sent))
	runner.check(sent.size() >= Settings.ACTIONS.size() - 1, "§7 every bound key and mouse button was sent (%d actions)" % sent.size())
	var s1 := _s7_state()
	runner.check(s1 == s0 and pl.global_position.distance_to(pos0) < 0.01, "§7 no game action fired: nothing in the game changed")
	runner.check(world.modal_kind == "computer" and c.form_up() and c.current == ComputerUI.app_index("contracts") and not inv_shown, "§7 …the computer stays open on the form (no map, debug menu, Tab overview or app change)")
	runner.check(focus_kept, "§7 …and the field kept the focus (the mouse buttons were pressed on it)")
	var typed := c.name_edit.text
	runner.check(typed != Game.suggested_company_name() and typed.contains("1234") and typed.contains("gfhe"), "§7 the letter and number keys typed text: \"%s\"" % typed)
	runner.check(Game.company_name == "", "§7 …nothing is named until OK")
	await _s2_key("pause")
	await _frames(2)
	runner.check(not c.name_edit.has_focus() and world.modal_kind == "computer" and not Game.typing(), "§7 Esc leaves the field; the computer stays open")
	await _s2_key("pause")
	await _frames(2)
	runner.check(world.modal == null, "§7 …and the next Esc closes the computer, as before")
	await _unload()


## The contract history: completed one-time jobs and visits, missed jobs (with the reputation lost),
## cancelled entries; newest first; capped at the balance value (the same in balance.tres and the
## defaults).
func test_s7_contract_history() -> void:
	await _s3_world("fun")
	Game.company_name = "History Test Co."
	Weather.force(0, 200.0)
	runner.check(Contracts.job_history.is_empty(), "§7 a new game starts with an empty history")
	var lots := []
	for l in Layout.lots:
		if not l["vacant"] and not l["is_player"] and l["index"] != Layout.neighbor_lot["index"]:
			lots.append(l)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var made := []
	for k in range(3):
		Contracts._add_lot_listing(lots[k], Clock.day_index(), rng)
		Contracts.listings[-1]["type"] = "recurring" if k == 1 else "one_time"
		made.append(Contracts.force_award(int(Contracts.listings[-1]["lid"])))
	# 1. A one-time job, cleared: the box rule finishes it.
	for c in made.slice(0, 2):
		for z in c["zones"]:
			for id in z["boxes"]:
				var bx := Boxes.get_box(id)
				for r in bx["rects"]:
					Snow.set_rect(r, 0.0)
				Boxes.measure(bx, true)
	await _frames(3)
	var h: Array = Contracts.job_history
	runner.check(h.size() == 2 and h[0]["result"] == "completed" and h[0]["type"] == "one_time" and h[0]["pay"] == made[0]["pay"] and h[0]["address"] == made[0]["address"] and h[0]["year"] == 1,
		"§7 a completed one-time job is recorded with its pay (%s)" % (str(h[0]) if h.size() > 0 else "none"))
	runner.check(h.size() == 2 and h[1]["result"] == "completed" and h[1]["type"] == "recurring" and h[1]["pay"] == made[1]["pay"], "§7 …a recurring visit too")
	# 2. A missed job: its due time passes (polish 5 §10; was the snowed-in clock).
	var c3: Dictionary = made[2]
	var rep0 := Game.reputation
	c3["due"] = Clock.minutes + 1.0
	Clock.minutes += 5.0
	Contracts.on_advance(5.0)
	runner.check(c3["status"] == "lost" and h.size() == 3 and h[2]["result"] == "missed" and h[2]["pay"] == 0 and is_equal_approx(h[2]["rep"], -Catalog.balance.contract_lost_reputation) and is_equal_approx(Game.reputation, rep0 - Catalog.balance.contract_lost_reputation),
		"§7 a missed job is recorded with the reputation lost (%s)" % str(h.back()))
	Contracts.record_job(made[0], "cancelled", 0, 0.0)
	# 3. The History tab: newest first, aligned columns, each result in words.
	var comp := await _s7_open()
	comp._open_app(ComputerUI.app_index("contracts"))
	comp.show_contracts_tab(1)
	await _frames(3)
	var grids := comp.content.find_children("*", "GridContainer", true, false)
	var cells: Array = (grids[0] as GridContainer).get_children().map(func(n): return (n as Label).text) if not grids.is_empty() else []
	runner.check(cells.size() == 5 * 5 and cells[5 + 3] == "Cancelled" and cells[10 + 3] == "Missed" and cells[10 + 4].contains("-6") and cells[15 + 3] == "Completed" and cells[20 + 4] == UIKit.money(made[0]["pay"]),
		"§7 the History tab lists them newest first %s" % str(cells.slice(5)))
	comp.show_contracts_tab(0)
	await _frames(2)
	runner.check(_s2_texts(comp.content).contains(made[1]["address"]), "§7 the Active tab lists the running contract")
	world.close_modal()
	await _frames(2)
	# 4. The cap.
	var cap := int(Catalog.balance.contract_history_max)
	var tres: BalanceData = load("res://data/balance.tres")
	runner.check(cap >= 150 and cap <= 250 and tres.contract_history_max == cap and BalanceData.new().contract_history_max == cap, "§7 the cap is a balance value (%d), the same in balance.tres and the defaults" % cap)
	var n0 := h.size()
	for k in range(cap + 30):
		Contracts.record_job({"id": 1000 + k, "address": "x", "client": "y", "type": "one_time"}, "completed", k, 2.0)
	h = Contracts.job_history
	runner.check(h.size() == cap and int(h[0]["id"]) == 1000 + (n0 + cap + 30 - cap) - n0 and int(h[-1]["id"]) == 1000 + cap + 29, "§7 the history keeps the newest %d entries (%d, first id %d)" % [cap, h.size(), int(h[0]["id"])])
	await _unload()


## Saves move to version 3: a version-2 save (a pass-5 fixture) loads with an empty name and
## history and is written back as version 3; a version-1 save goes 1 → 2 → 3.
func test_s7_v2_save_loads_into_v3() -> void:
	runner.check(Saves.SAVE_VERSION == 3, "§7 the save format is version 3")
	var path := "res://tests/fixtures/polish5/fun_1_contracts.json"
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	runner.check(int(src["version"]) == 2 and not (src["game"] as Dictionary).has("company_name") and not (src["contracts"] as Dictionary).has("job_history"), "§7 the fixture is a version-2 save")
	Game.company_name = "Left Over Co."
	Contracts.job_history = [{"id": 1}]
	var ok: bool = await _load_save_file(path)
	runner.check(ok and Game.company_name == "" and Contracts.job_history.is_empty() and Contracts.history.size() == (src["contracts"]["history"] as Array).size(), "§7 version 2 → 3: an empty name and history (the old list of completed jobs kept)")
	await _spawn_world()
	runner.check(Saves.save_game(), "§7 saved")
	var out: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Saves.path_for("fun")))
	runner.check(int(out["version"]) == 3 and out["game"]["company_name"] == "" and (out["contracts"]["job_history"] as Array).is_empty() and Saves.peek("fun").has("year"), "§7 …written back as version 3 with both keys")
	await _unload()
	# Version 1: no boxes, no computer lock flag (both derived on load), then 2 → 3.
	var v1 := src.duplicate(true)
	v1["version"] = 1
	v1.erase("boxes")
	(v1["game"]["flags"] as Dictionary).erase("computer_unlocked")
	var f := FileAccess.open(Saves.path_for("fun"), FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Saves.path_for("fun") + ".bak"))
	Game.company_name = "Left Over Co."
	runner.check(Saves.load_game("fun") and Game.computer_unlocked() and not Boxes.boxes.is_empty() and Game.company_name == "" and Contracts.job_history.is_empty(), "§7 version 1 → 2 → 3: boxes and the computer lock derived, an empty name and history")
	await _spawn_world()
	await _frames(2)
	runner.check(world.player != null, "§7 …and it plays")
	Saves.delete_save("fun")
	await _unload()


## A version-3 save round-trips the new state exactly: the company's name and its contract history
## (every kind of job and result).
func test_s7_v3_save_round_trips() -> void:
	await _s3_world("fun")
	Game.company_name = "Round Trip Snow Co."
	var lst: Dictionary = Contracts.listings[0]
	var cc := Contracts.force_award(int(lst["lid"]))
	Contracts.record_job(cc, "completed", 123, 2.0)
	var cm := cc.duplicate()
	cm["type"] = "municipal"
	Contracts.record_job(cm, "missed", 0, -6.0)
	Contracts.record_job(cm, "cancelled", 0, 0.0)
	Clock.minutes += 61.5
	Contracts.record_job({"id": 99, "address": "St. Andrew's Church, 40 Cedar Lane", "client": "Église", "type": "recurring"}, "completed", 45, 0.3)
	# §8: the recent weather alerts (optional key, default none).
	Weather._alert("Severe weather advisory: heavy snow expected around Dec 3 14:00.")
	Clock.minutes += 30.25
	Weather._alert("WEATHER ALERT: storm strengthening — heavy snow conditions, worse than forecast!")
	var want := JSON.stringify({"name": Game.company_name, "history": Contracts.job_history, "alerts": Weather.alerts})
	# §10: the board's live bidding (your bid, the rivals' plan and bids), the due times, the tier
	# noted — optional keys of version 3.
	var bl: Dictionary = Contracts.listings.filter(func(x): return not Contracts.listing_locked(x))[0]
	Contracts.place_bid(int(bl["lid"]), int(bl["budget"]))
	Contracts._rival_bid(bl, 0, int(bl["budget"]) - 1, Clock.minutes)
	cc["ext"] = true
	var want10 := _s10_norm({"listings": Contracts.listings, "active": Contracts.active, "tier_noted": Contracts.tier_noted, "next_id": Contracts._next_id})
	# §13: the items' own upgrade levels (game.upgrades, new ids), one carried over past its item's
	# ladder, the pickup's front plow, a heated cab, and an upgrade that isn't an item's.
	for id in [ItemUpgrades.level_id(&"small_shovel", &"capacity", 1), ItemUpgrades.level_id(&"small_shovel", &"capacity", 2),
			ItemUpgrades.level_id(&"hands", &"throw", 1), String(ItemUpgrades.PLOW_ID), ItemUpgrades.level_id(&"atv_blade", &"cab", 1),
			ItemUpgrades.level_id(&"rotary_blower", &"blower", 1), "weather_pro"]:
		Game.grant_upgrade(StringName(id))
	var want13 := JSON.stringify(Game.upgrades, "", true)
	# §13b: the equipment (the coat, the snowshoes off, the pad down on the lot), heating not yet
	# billed and minutes not yet melted, a bill with its heating, the melted-volume ledger.
	var pad_at := Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, -9.0), 4.0)
	Game.equipment = {"insulated_coat": {}, "snowshoes": {"on": false}, "heated_pad": {"pos": [snappedf(pad_at.x, 0.125), 0.0, snappedf(pad_at.y, 0.125)], "yaw": 1.5}}
	Economy.heat_used = 12.375
	Economy.heat_acc = {"pad": 0.25, "heated_driveway": 7.5}
	Economy.bills.append({"month": 1, "amount": 97, "heat": 12, "issued_day": 31, "due_day": 45, "paid": false})
	Snow.melted = 3.125
	var bills_of := func() -> Array: return Economy.bills.map(func(x): return [int(x["month"]), int(x["amount"]), int(x.get("heat", 0)), int(x["due_day"]), bool(x["paid"])])
	var want13b := JSON.stringify({"eq": Game.equipment, "used": Economy.heat_used, "acc": Economy.heat_acc, "bills": bills_of.call(), "melted": Snow.melted}, "", true)
	# Polish 6 §3: the snow's relaxation still pending (hot and cold, in order) and blade_push's
	# stream — optional keys of version 3.
	Snow.deposit(pad_at + Vector2(6.0, 0.0), 0.6, 0.8)
	Snow.hot_mode = false
	Snow.deposit(pad_at + Vector2(-6.0, 3.0), 0.6, 0.8)
	Snow.hot_mode = true
	Snow.push_rng.randf()
	var want_p6 := JSON.stringify(Snow.serialize_pending())
	var pend_p6 := Snow.relax_pending()
	runner.check(Saves.save_game(), "§7 a version-3 save")
	Game.upgrades = {}
	Game.company_name = ""
	Contracts.job_history = []
	Weather.alerts.clear()
	Game.equipment = {}
	Economy.heat_used = 0.0
	Economy.heat_acc = {}
	Snow.melted = 0.0
	await _unload()
	runner.check(Saves.load_game("fun"), "§7 …loads")
	var got_p6 := JSON.stringify(Snow.serialize_pending())
	runner.check(got_p6 == want_p6 and Snow.relax_pending() == pend_p6 and pend_p6 > 0 and not Snow.settle_on_load, "§3 (polish 6) …and the snow's pending relaxation (%d tiles, hot and cold in order) and blade_push's stream exactly as saved" % pend_p6)
	if got_p6 != want_p6:
		runner.info("want %s\n got %s" % [want_p6.left(600), got_p6.left(600)])
	var got13b := JSON.stringify({"eq": Game.equipment, "used": Economy.heat_used, "acc": Economy.heat_acc, "bills": bills_of.call(), "melted": Snow.melted}, "", true)
	runner.check(got13b == want13b and Equipment.pad_placed() and not Equipment.snowshoes_on(), "§13b …and the equipment, the pad where it lies, the heating not yet billed, the bill's heating and the melted-volume ledger exactly as saved")
	if got13b != want13b:
		runner.info("want %s\n got %s" % [want13b, got13b])
	var got := JSON.stringify({"name": Game.company_name, "history": Contracts.job_history, "alerts": Weather.alerts})
	runner.check(got == want and Contracts.job_history.size() == 4 and Weather.alerts.size() == 2, "§7 …with the name, the history and (§8) the recent alerts exactly as saved (%d entries, %d alerts)" % [Contracts.job_history.size(), Weather.alerts.size()])
	if got != want:
		runner.info("want %s\n got %s" % [want, got])
	var got10 := _s10_norm({"listings": Contracts.listings, "active": Contracts.active, "tier_noted": Contracts.tier_noted, "next_id": Contracts._next_id})
	runner.check(got10 == want10 and Contracts.bids.size() == 1, "§10 …and the board (your bid, the rivals' plan and bids), the due times and the tier noted exactly as saved")
	runner.check(JSON.stringify(Game.upgrades, "", true) == want13 and Game.upgrades.size() == 7 and ItemUpgrades.pending_note == "", "§13 …and the items' upgrade levels exactly as saved (%d), no carry-over note" % Game.upgrades.size())
	if got10 != want10:
		runner.info("want %s\n got %s" % [want10.left(2000), got10.left(2000)])
	Saves.delete_save("fun")
	await _unload()


## Every app fits and lines up at 1280×720, 1920×1080, 2560×1440 and 3440×1440: the window on the
## screen at its size, every control inside it (the content's inside the content area, which only
## scrolls vertically), no label or button text clipped or cut, table columns aligned. Filled to the
## worst case: the longest name, the battery line, the name form, both Contracts tabs with history,
## a pending bid, a long alert, orders, bills and transactions.
func test_s7_every_app_fits() -> void:
	await _s3_world("survival")
	Game.money = 99999
	Game.company_name = "W".repeat(Game.COMPANY_NAME_MAX)
	Survival.cut_power()
	for k in range(3):
		if Contracts.listings.size() > 1:
			var c: Dictionary = Contracts.force_award(int(Contracts.listings[0]["lid"]))
			Contracts.record_job(c, ["completed", "missed", "cancelled"][k], 1234, -6.0)
	Contracts.record_job({"id": 77, "address": Layout.big_areas[0]["place"], "client": "x", "type": "municipal"}, "completed", 12345, 1.0)
	if not Contracts.listings.is_empty():
		Contracts.place_bid(int(Contracts.listings[0]["lid"]), int(Contracts.listings[0]["budget"]) + 99)   # §10: above the floor
	runner.info("fit: %d contracts, %d listings, %d bids, %d history entries" % [Contracts.active.size(), Contracts.listings.size(), Contracts.bids.size(), Contracts.job_history.size()])
	Weather.alerts.append({"time": Clock.minutes, "text": "WEATHER ALERT: an unforecast storm is dumping snow at 41 cm an hour — stay indoors until the worst of it has passed!"})
	Economy.buy("standard_shovel")
	Economy.orders.append({"id": 99, "item": String(ItemUpgrades.PLOW_ID), "status": "spawned", "placed": Clock.minutes})   # §13: the plow's id
	var states := []
	for i in range(ComputerUI.APPS.size()):
		states.append([ComputerUI.APP_IDS[i], i, 0, true])
	states.append(["contracts, History", ComputerUI.app_index("contracts"), 1, true])
	states.append(["name form", ComputerUI.app_index("board"), 0, false])
	var bad := []
	var checked := 0
	for res in S7_CANVASES.keys():
		var logical: Vector2 = S7_CANVASES[res]
		var host := Control.new()
		host.size = logical
		runner.add_child(host)
		var comp := ComputerUI.new()
		host.add_child(comp)
		await _frames(2)
		for st in states:
			Game.company_name = "W".repeat(Game.COMPANY_NAME_MAX) if st[3] else ""
			comp.contracts_tab = st[2]
			comp._open_app(st[1])
			for k in range(4):
				await _tree().process_frame
			var probs := _s7_fit_problems(comp, Rect2(Vector2.ZERO, logical))
			checked += 1
			for p in probs:
				bad.append("%s %s: %s" % [res, st[0], p])
			# The bottom of a long app can be scrolled to, and fits there too.
			comp.scroll.scroll_vertical = int(comp.content.size.y)
			for k in range(2):
				await _tree().process_frame
			for p in _s7_fit_problems(comp, Rect2(Vector2.ZERO, logical)):
				bad.append("%s %s (scrolled): %s" % [res, st[0], p])
		host.queue_free()
		await _frames(1)
	runner.check(bad.is_empty(), "§7 every app fits and lines up at every resolution (%d views) %s" % [checked, str(bad.slice(0, 12))])
	Game.company_name = ""
	Weather.alerts.clear()
	await _unload()


## What doesn't fit in the computer's window (empty when everything does).
func _s7_fit_problems(c: ComputerUI, view: Rect2) -> Array:
	var bad := []
	var win: Control = c.find_child("Window", true, false)
	var wr := win.get_global_rect()
	if not view.encloses(wr) or not wr.size.is_equal_approx(ComputerUI.WIN):
		bad.append("the window is %s on a %s screen" % [str(wr), str(view.size)])
	var clip := c.scroll.get_global_rect()
	if c.content.size.x > c.scroll.size.x + 0.5:
		bad.append("the content is wider than its area (%d > %d)" % [c.content.size.x, c.scroll.size.x])
	if c.content.size.y > c.scroll.size.y + 0.5 and not c.scroll.get_v_scroll_bar().visible:
		bad.append("a long app doesn't scroll")
	for n in win.find_children("*", "Control", true, false):
		var ctl := n as Control
		if not ctl.is_visible_in_tree() or ctl is ScrollBar:
			continue
		var r := ctl.get_global_rect()
		var in_scroll := ctl == c.content or c.content.is_ancestor_of(ctl)
		var box := clip if in_scroll else wr
		if r.position.x < box.position.x - 0.5 or r.end.x > box.end.x + 0.5 or (not in_scroll and (r.position.y < box.position.y - 0.5 or r.end.y > box.end.y + 0.5)):
			bad.append("%s \"%s\" sticks out (%s)" % [ctl.get_class(), _s7_text(ctl), str(r)])
		if in_scroll and (r.end.y <= clip.position.y or r.position.y >= clip.end.y):
			continue    # scrolled out of view
		if ctl is Label:
			var l := ctl as Label
			if l.text == "":
				continue
			var tw := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
			if l.autowrap_mode == TextServer.AUTOWRAP_OFF and (l.get_minimum_size().x > l.size.x + 0.5 or tw > l.size.x + 1.0):
				bad.append("\"%s\" is clipped (%d > %d)" % [l.text.left(40), tw, l.size.x])
			elif l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.get_visible_line_count() < l.get_line_count():
				bad.append("\"%s\" is cut (%d of %d lines)" % [l.text.left(40), l.get_visible_line_count(), l.get_line_count()])
		elif ctl is Button:
			var b := ctl as Button
			var bw := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x + b.get_theme_stylebox("normal").get_minimum_size().x
			if b.get_minimum_size().x > b.size.x + 0.5 or b.get_minimum_size().y > b.size.y + 0.5 or (bw > b.size.x + 1.0 and b.autowrap_mode == TextServer.AUTOWRAP_OFF):
				bad.append("button \"%s\" is clipped (%d > %d)" % [b.text, bw, b.size.x])
		elif ctl is LineEdit:
			# §10: the board's typed-bid fields are LineEdits too — they must show a 6-digit amount.
			if ctl == c.name_edit and ctl.size.x < 300.0:
				bad.append("the name field is narrow (%d)" % ctl.size.x)
			elif ctl != c.name_edit and ctl.get_theme_font("font").get_string_size("999999", HORIZONTAL_ALIGNMENT_LEFT, -1, ctl.get_theme_font_size("font_size")).x + ctl.get_theme_stylebox("normal").get_minimum_size().x > ctl.size.x + 1.0:
				bad.append("the bid field is narrow (%d)" % ctl.size.x)
	for g in c.content.find_children("*", "GridContainer", true, false):
		var cols := (g as GridContainer).columns
		var kids := (g as Node).get_children().filter(func(k): return (k as Control).visible)
		for k in range(cols, kids.size()):
			if absf((kids[k] as Control).global_position.x - (kids[k % cols] as Control).global_position.x) > 0.5:
				bad.append("a table's column %d isn't aligned" % (k % cols))
				break
	return bad


static func _s7_text(n: Control) -> String:
	if n is Label:
		return (n as Label).text.left(30)
	if n is Button:
		return (n as Button).text.left(30)
	return n.name


# =============================================================================
# §8 Weather in sync
# =============================================================================

const S8Audit := preload("res://tests/forecast_audit.gd")
const S8Truth := preload("res://tests/weather_truth.gd")
const S8_SEEDS := [2024, 1, 7, 42, 99]
## The weather that falls at the start of polish 5 (weather_truth.tscn on the baseline build).
const S8_TRUTH := "res://tests/fixtures/polish5/weather_truth_baseline.json"


## The weather that actually falls is the polish-5 baseline's, byte for byte: every event (start,
## end, condition, tier, total, first and last snowy hour, peak hourly rate, first heavy hour),
## every winter's total and every alert hour by hour, for seed 2024 and 20 other seeds, winters 1–5.
## Only the forecasts change in §8.
func test_s8_truth_unchanged() -> void:
	await _unload()
	var d := S8Truth.dump()
	d["alerts"] = S8Truth.alerts_dump()
	var now := JSON.stringify(d, "", false)
	var base := FileAccess.get_file_as_string(S8_TRUTH)
	var first := -1
	for i in range(mini(now.length(), base.length())):
		if now[i] != base[i]:
			first = i
			break
	runner.check(base.length() > 100000 and now == base, "§8 the weather that falls is the baseline's, byte for byte (%d winters, %d bytes%s)" % [d.size() - 1, now.length(), "" if now == base else ", first difference at %d: …%s…" % [first, now.substr(maxi(first - 40, 0), 80)]])


## The TV's cards name the strength of the snow in words, one mapping for every display, and for
## every forecast event the card is right from three days out (5 seeds × winters 1–5): every card
## for a day a forecast event drops at least 1 cm on, issued 3, 2, 1 and 0 days before (every 3 game
## hours of the issuing day), names the strongest system of that day (Decision 7 for surprises).
func test_s8_tier_right_from_three_days_out() -> void:
	await _unload()
	runner.check(Weather.tier_name("light") == "Light snow" and Weather.tier_name("storm") == "Snowstorm" and Weather.tier_name("major") == "Major snowstorm",
		"§8 the words: Light snow, Snowstorm, Major snowstorm")
	var r := S8Audit.audit_cards(S8_SEEDS, [1, 2, 3, 4, 5], 3)
	for k in range(3, -1, -1):
		runner.check(int(r["tier_n"][k]) > 1500 and int(r["tier_bad"][k]) == 0, "§8 %d days out: every card names the right strength (%d cards, %d wrong; %d name a system starting or ending within an hour of the day)%s" % [k, r["tier_n"][k], r["tier_bad"][k], r["tier_edge"][k], "" if int(r["tier_bad"][k]) == 0 else " — " + str((r["tier_examples"] as Array).slice(0, 3))])
	# Every tier shows up on the cards, and a card's words come from the one mapping.
	_gen_s8(2024, 5)
	var seen := {}
	for d in range(2, 118):
		var e := Weather.forecast_day(d, (d - 2) * 24 + 7)
		var ct := Weather.card_text(e)
		if e["tier"] != "":
			seen[e["tier"]] = true
			if ct["title"] != Weather.tier_name(e["tier"]) or ct["amount"] == "" or ct["when"] == "":
				seen["bad"] = "%s: %s" % [str(e["date"]), str(ct)]
	runner.check(seen.has("light") and seen.has("storm") and seen.has("major") and not seen.has("bad"), "§8 two days out, winter 5: cards with each strength, each with its word, the snow as a range and when it starts %s" % str(seen.get("bad", "")))


func _gen_s8(s: int, y: int) -> void:
	Weather.generate(y, s + y * 13)


## The accuracy targets for forecast events (5 seeds × winters 1–3): the start time shown within
## ±3 h three days out and ±1 h the day before; the range shown holds the day's snow at least 90 %
## of the time at every lead, narrowing as the day comes; the radio's next three hours right in at
## least 95 % of the calls, the rate within ±25 %. The tuned values are the same in both files.
func test_s8_accuracy_targets() -> void:
	await _unload()
	var ev := S8Audit.audit_events(S8_SEEDS, [1, 2, 3])
	runner.check(int(ev["shown_n"][3]) > 1000 and float(ev["shown_max"][3]) <= 3.0 and float(ev["start_max"][3]) <= 3.0, "§8 three days out the start time shown is within ±3 h (worst %.2f h; the model's %.2f h; %d forecasts)" % [ev["shown_max"][3], ev["start_max"][3], ev["shown_n"][3]])
	runner.check(int(ev["shown_n"][1]) > 1000 and float(ev["shown_max"][1]) <= 1.0 and float(ev["start_max"][1]) <= 1.0, "§8 the day before, within ±1 h (worst %.2f h; the model's %.2f h)" % [ev["shown_max"][1], ev["start_max"][1]])
	var mean_s := []
	var mean_t := []
	for k in range(4):
		mean_s.append(float(ev["start_abs"][k]) / maxf(ev["n"][k], 1))
		mean_t.append(float(ev["tot_rel"][k]) / maxf(ev["n"][k], 1))
	runner.check(mean_s[3] > mean_s[2] and mean_s[2] > mean_s[1] and mean_s[1] > mean_s[0] and mean_t[3] > mean_t[2] and mean_t[2] > mean_t[1] and mean_t[1] > mean_t[0],
		"§8 the time and the amount narrow as the day comes (mean start error %.2f / %.2f / %.2f / %.2f h, total %.0f / %.0f / %.0f / %.0f %%, 3 → 0 days out)" % [mean_s[3], mean_s[2], mean_s[1], mean_s[0], 100 * mean_t[3], 100 * mean_t[2], 100 * mean_t[1], 100 * mean_t[0]])
	var c := S8Audit.audit_cards(S8_SEEDS, [1, 2, 3], 3)
	var widths := []
	for k in range(3, -1, -1):
		var share := float(c["range_in"][k]) / maxf(c["range_n"][k], 1)
		widths.append(float(c["width"][k]) / maxf(c["range_n"][k], 1))
		runner.check(int(c["range_n"][k]) > 1000 and share >= 0.90, "§8 %d days out the range shown holds the day's snow %.1f %% of the time (%d days)%s" % [k, 100.0 * share, c["range_n"][k], "" if share >= 0.9 else " — " + str((c["range_examples"] as Array).slice(0, 3))])
	runner.check(widths[0] > widths[1] and widths[1] > widths[2] and widths[2] > widths[3], "§8 …and the range narrows as the day comes (width / day's snow %.2f, %.2f, %.2f, %.2f)" % widths)
	var r := S8Audit.audit_radio(S8_SEEDS, [1, 2, 3])
	var right := float(r["snowy_right"]) / maxf(r["snowy"], 1)
	var all_right := float(r["right"]) / maxf(r["calls"], 1)
	var rate_in := float(r["rate_in"]) / maxf(r["rate_n"], 1)
	runner.check(int(r["snowy"]) > 5000 and right >= 0.95 and all_right >= 0.95, "§8 the radio's next three hours: the condition right in %.1f %% of the snowy calls (%.1f %% of all %d)" % [100 * right, 100 * all_right, r["calls"]])
	runner.check(int(r["rate_n"]) > 3000 and rate_in >= 0.95, "§8 …the rate within ±25 %% in %.1f %% of the snowy hours (mean error %.1f %%)" % [100 * rate_in, 100.0 * float(r["rate_rel"]) / maxf(r["rate_n"], 1)])
	var tres: BalanceData = load("res://data/balance.tres")
	var dflt := BalanceData.new()
	var same := true
	for k in ["fc_error_base", "fc_error_per_day", "fc_timing_h_per_day", "fc_temp_error_per_day", "radio_surprise_horizon_h", "forecast_skill"]:
		same = same and is_equal_approx(float(tres.get(k)), float(dflt.get(k))) and is_equal_approx(float(Catalog.balance.get(k)), float(dflt.get(k)))
	runner.check(same and is_equal_approx(dflt.radio_surprise_horizon_h, 3.0), "§8 the forecast values are the same in balance.tres and the defaults (radio horizon %.0f h)" % dflt.radio_surprise_horizon_h)


## Decision 7. An unforecast major event is never on the TV (or the computer) before it starts, and
## the radio has it from 3 game hours ahead. A storm that arrives stronger than forecast is called at
## its real strength by 7:00 a.m. on its day, and on the radio within its window; before that it's
## still a surprise (under-called the day before).
func test_s8_surprises() -> void:
	await _load_s8()
	var n_major := 0
	var tv_bad := []
	var radio_bad := []
	var n_storm := 0
	var storm_bad := []
	var under := 0
	for s in S8_SEEDS:
		for y in range(1, 6):
			_gen_s8(s, y)
			for i in range(Weather.events.size()):
				var ev: Dictionary = Weather.events[i]
				if not ev["surprise"]:
					continue
				var st: float = ev["start"]
				var sday := int(floor(st / 24.0))
				if Weather.tier_of(ev) == "major":
					n_major += 1
					for iss in range(maxi(int(st) - 72, 0), int(st) + 1):
						if float(iss) >= st:
							break
						# The TV and the computer: no card names a major snowstorm or shows the system.
						for d in range(floori(iss / 24.0), floori(iss / 24.0) + 3):
							var e := Weather.forecast_day(d, iss)
							for fe in e["events"]:
								if absf(float(fe["start"]) - st) < 1.5 and fe["tier"] == "major":
									tv_bad.append("%d/%d %s, %.1f h before" % [s, y, Clock.format_time(st * 60.0), st - iss])
							if e["tier"] == "major" and Weather.fc_tier(i, iss) != "":
								tv_bad.append("%d/%d tier at %.1f h before" % [s, y, st - iss])
						# The radio: from 3 h ahead, the major snowstorm and its blizzard hours.
						var on_radio := Weather.fc_tier(i, iss, true) == "major"
						if on_radio != (st - float(iss) <= 3.0):
							radio_bad.append("%d/%d radio %s at %.1f h before" % [s, y, "on" if on_radio else "off", st - iss])
						if st - float(iss) <= 3.0:
							Clock.minutes = iss * 60.0 + 15.0
							var b := Weather.radio_bulletin()
							if not (b.contains("blizzard") or b.contains("Major snowstorm")):
								radio_bad.append("%d/%d \"%s\"" % [s, y, b])
				elif Weather.tier_of(ev) == "storm":
					n_storm += 1
					var call := sday * 24 + Weather.CALL_HOUR
					for iss in range(maxi(int(st) - 30, 0), int(ceil(float(ev["end"])))):
						var t := Weather.fc_tier(i, iss)
						var called := iss >= call or float(iss) >= st or st - float(iss) <= 3.0
						if called and t != "storm":
							storm_bad.append("%d/%d %s: \"%s\" at %s" % [s, y, Clock.format_time(st * 60.0), t, Clock.format_time(iss * 60.0)])
						if called and Weather.forecast_day(sday, iss)["tier"] != "storm" and float(iss) < st:
							storm_bad.append("%d/%d %s: card at %s" % [s, y, Clock.format_time(st * 60.0), Clock.format_time(iss * 60.0)])
						if not called and t == "light":
							under += 1
					# The radio inside its window: heavy where heavy falls.
					for iss in range(int(ceil(st - 3.0)), int(st)):
						for k in range(1, 4):
							var h := iss + k
							if Weather.cond[h] >= Weather.C.HEAVY and Weather.fc_hour(h, iss, true)["cond"] < Weather.C.HEAVY:
								storm_bad.append("%d/%d radio %s" % [s, y, Clock.format_time(h * 60.0)])
	runner.check(n_major >= 10 and tv_bad.is_empty(), "§8 %d unforecast major events: never on the TV or the computer before they start%s" % [n_major, "" if tv_bad.is_empty() else " — " + str(tv_bad.slice(0, 3))])
	runner.check(radio_bad.is_empty(), "§8 …and on the radio from 3 h ahead (named and its blizzard called), never earlier%s" % ("" if radio_bad.is_empty() else " — " + str(radio_bad.slice(0, 3))))
	runner.check(n_storm >= 20 and storm_bad.is_empty(), "§8 %d storms stronger than forecast: called a snowstorm from 7:00 a.m. on their day (TV, computer, radio), heavy on the radio inside its window%s" % [n_storm, "" if storm_bad.is_empty() else " — " + str(storm_bad.slice(0, 3))])
	runner.check(under > n_storm * 5, "§8 …and still a surprise before that: under-called as light snow (%d forecasts)" % under)
	await _unload()


## A world (seed 2024, Dec 2 10:00) for the tests that read the displays; the clock stopped.
func _load_s8(mode := "fun") -> void:
	await _unload()
	Game.force_input = true
	Game.new_game(mode, 2024)
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	Clock.reset(Clock.at(1, 10.0))
	await _spawn_world()
	Clock.running = false


## The true snow still to come in the event the radio follows, from now (the rest of this hour).
func _s8_remaining(ev: Dictionary) -> float:
	var issued := Weather.issued_hour()
	var hrs: Dictionary = ev["hours"]
	var r := float(hrs.get(issued, 0.0)) * (1.0 - fmod(Clock.minutes, 60.0) / 60.0)
	for hv in hrs.keys():
		if int(hv) > issued:
			r += float(hrs[hv])
	return r


## "another 8 to 12 cm" / "8 to 12 cm in all" / "up to 3 cm" → [lo, hi]; [] when there's no amount.
static func _s8_amount(b: String) -> Array:
	var rx := RegEx.new()
	rx.compile("(another (\\d+) to (\\d+) cm|, (\\d+) to (\\d+) cm in all|up to (\\d+) cm)")
	var m := rx.search(b)
	if m == null:
		return []
	if m.get_string(2) != "":
		return [int(m.get_string(2)), int(m.get_string(3))]
	if m.get_string(4) != "":
		return [int(m.get_string(4)), int(m.get_string(5))]
	return [0, int(m.get_string(6))]


## The radio from start to end: due in its window, the bulletin says what's coming, when it should
## end and how much ("Snowstorm ending around 10 p.m., 15 to 25 cm in all."); while it falls, how
## much more ("…another 8 to 12 cm."); once it's over, "Snow has ended." The three hourly phrases
## stay. Over every forecast event of 5 seeds × winters 1–3: the end within an hour, the amount
## within its range at least 90 % of the time.
func test_s8_radio_start_to_end() -> void:
	await _load_s8()
	var n := 0
	var end_bad := []
	var amt_in := 0
	var amt_n := 0
	var phrase_bad := []
	var ended_ok := 0
	var ended_n := 0
	var tiers_seen := {}
	for s in S8_SEEDS:
		for y in range(1, 4):
			_gen_s8(s, y)
			for i in range(Weather.events.size()):
				var ev: Dictionary = Weather.events[i]
				if ev["surprise"]:
					continue
				var st: float = ev["start"]
				var en: float = ev["end"]
				var word := Weather.tier_name(Weather.tier_of(ev))
				for iss in range(int(st) - 2, int(ceil(en))):
					Clock.minutes = iss * 60.0 + 20.0
					if Weather.radio_spell(iss) != i:
						continue    # another system comes first
					var b := Weather.radio_bulletin()
					n += 1
					var issued := Weather.issued_hour()
					for k in range(1, 4):
						if not b.to_lower().contains(Weather.hour_name(issued + k) + " "):
							phrase_bad.append(b)
							break
					var falling := (ev["hours"] as Dictionary).has(issued) and Weather.rate[issued] > 0.01
					if not b.contains(word + " ending around ") or (falling and not b.begins_with("Right now:")):
						phrase_bad.append(b)
						continue
					tiers_seen[word] = true
					# This system's own line (the radio may follow a second one after it).
					var line := Weather._spell_line(i, issued)
					if not b.contains(line) or not line.begins_with(word + " ending around "):
						phrase_bad.append(b)
						continue
					var sp := Weather.fc_span(i, issued, true)
					var said := Weather.hour_name(int(roundf(float(sp[1]))))
					if absf(float(sp[1]) - en) > 1.0 or not line.contains("ending around " + said):
						end_bad.append("%s: %s (ends %s)" % [Clock.format_time(Clock.minutes), b, Clock.format_time(en * 60.0)])
					var a := _s8_amount(line)
					if not a.is_empty():
						var rem := _s8_remaining(ev) if falling else float(ev["total"])
						amt_n += 1
						amt_in += 1 if float(a[0]) <= rem + 0.001 and rem <= float(a[1]) + 0.001 else 0
						if falling != (line.contains("another") or line.contains("cm more")):
							phrase_bad.append(b)
				# Once it's over (and nothing else is due): "Snow has ended."
				var after := int(ceil(en)) + 1
				var quiet := true
				for other in Weather.events:
					if other != ev and float(other["start"]) < float(after + 5) and float(other["end"]) > en - 1.0:
						quiet = false
				if quiet and after < Weather.HOURS - 4:
					ended_n += 1
					Clock.minutes = after * 60.0 + 10.0
					var b2 := Weather.radio_bulletin()
					if b2.ends_with("Snow has ended.") and not b2.begins_with("Right now"):
						ended_ok += 1
					elif phrase_bad.size() < 20:
						phrase_bad.append("after: " + b2)
	runner.check(n > 2000 and phrase_bad.is_empty(), "§8 %d bulletins from start to end: the three hourly phrases, \"right now\" while it falls, then \"<strength> ending around …\"%s" % [n, "" if phrase_bad.is_empty() else " — " + str(phrase_bad.slice(0, 3))])
	runner.check(tiers_seen.size() == 3, "§8 …in the words of the TV (%s)" % str(tiers_seen.keys()))
	runner.check(end_bad.is_empty(), "§8 …the end it gives is within an hour of the real end%s" % ("" if end_bad.is_empty() else " — " + str(end_bad.slice(0, 2))))
	runner.check(amt_n > 1500 and float(amt_in) / amt_n >= 0.9, "§8 …and the amount (still) to come is within its range %.1f %% of the time (%d)" % [100.0 * amt_in / maxi(amt_n, 1), amt_n])
	runner.check(ended_n > 100 and ended_ok == ended_n, "§8 once it's over: \"Snow has ended.\" (%d of %d)" % [ended_ok, ended_n])
	# One bulletin as the player hears it, from the radio in the house.
	_gen_s8(2024, 1)
	for ev in Weather.events:
		if Weather.tier_of(ev) == "storm" and not ev["surprise"]:
			Clock.minutes = (floor(float(ev["start"])) + 2.0) * 60.0 + 10.0
			break
	world.radio_forecast()
	await _frames(2)
	var heard: String = world.hud.subtitle_l.text
	runner.check(heard.begins_with("Radio: Right now: ") and heard.contains("Snowstorm ending around ") and heard.contains("another ") and heard.ends_with(Municipal.crew_line()), "§8 the radio in the house: \"%s\"" % heard)
	await _unload()


## The TV's cards, the computer's Weather app (the TV's cards from the same forecast), the radio,
## the HUD's weather panel and what's falling agree in every hour of 5 seeds × winters 1–3 (at
## 5, 30 and 55 minutes past): if the radio calls snow in its window the card for that day shows
## snow then, at a strength no weaker; current conditions everywhere are what's falling now. The
## only difference allowed is Decision 7's: the radio has an unforecast major event up to 3 h before
## the TV, which calls it from the hour after it starts.
func test_s8_sync_every_hour() -> void:
	await _unload()
	for minute in [5.0, 30.0, 55.0]:
		var r := S8Audit.audit_sync(S8_SEEDS, [1, 2, 3], minute)
		var bad := 0
		for k in ["radio_tv", "radio_tv_time", "strength", "spell_tier", "ended_snow", "falling_tv", "falling_radio", "hud_falling", "radio_now"]:
			bad += int(r[k])
		runner.check(int(r["hours"]) > 40000 and int(r["checked"]) > 4000 and bad == 0, "§8 :%02d past every hour: no display contradicts another or what's falling (%d hours, %d with snow on the radio or falling, %d in an unforecast major's radio lead)%s" % [int(minute), r["hours"], r["checked"], r["surprise_window"], "" if bad == 0 else " — " + str((r["examples"] as Array).slice(0, 4))])
	# The screens themselves, around every storm and major event of a winter: the TV, the computer
	# and the HUD show the same words.
	await _load_s8()
	Game.company_name = "Sync Test Snow Co."
	_gen_s8(2024, 5)
	Game.year = 5
	var hours := []
	for ev in Weather.events:
		if Weather.tier_of(ev) != "light":
			for h in [int(ev["start"]) - 30, int(ev["start"]) - 2, int(ev["start"]), int(ev["start"]) + 1, int(ceil(float(ev["end"]))) + 1]:
				if h > 0 and h < Weather.HOURS - 4:
					hours.append(h)
	var bad_ui := []
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	runner.add_child(host)
	for h in hours:
		Clock.minutes = h * 60.0 + 20.0
		var tv := Panels.tv(host, func(): pass, false)
		var comp := ComputerUI.new()
		host.add_child(comp)
		for k in range(3):
			await _tree().process_frame
		var tv_t := _s2_texts(tv)
		var comp_t := _s2_texts(comp.content)
		var hud: HUD = world.hud
		hud._t = 0.0
		await _tree().process_frame
		await _tree().process_frame
		var now := Weather.current_summary()
		var ok: bool = comp.current == ComputerUI.app_index("weather") and tv_t.contains(now) and comp_t.contains("Now: " + now) and hud.weather_l.text == Weather.NAMES[Weather.condition()]
		for e in Weather.forecast(3):
			var ct := Weather.card_text(e)
			for f in ["date", "title", "amount", "when", "temps"]:
				if str(ct[f]) != "" and not tv_t.contains(str(ct[f])):
					ok = false
			if not comp_t.contains(Weather.card_line(e)) or not comp_t.contains(str(ct["temps"])):
				ok = false
		if not ok:
			bad_ui.append(Clock.format_time(Clock.minutes))
		tv.queue_free()
		comp.queue_free()
		await _tree().process_frame
	host.queue_free()
	runner.check(hours.size() > 40 and bad_ui.is_empty(), "§8 the TV, the computer's Weather app and the HUD show the same, before, during and after every storm and major event of winter 5 (%d moments)%s" % [hours.size(), "" if bad_ui.is_empty() else " — " + str(bad_ui.slice(0, 4))])
	await _unload()


## The TV's, the computer's and the radio's text are the same in real time, after a sleep and after
## save → load (the pass-4 mid-storm fixtures; the recent alerts are saved now, so the TV's latest
## alert reads the same too). A TV left on and a radio bulletin still on screen follow the hour.
func test_s8_same_in_real_time_sleep_and_reload() -> void:
	for mode in ["fun", "survival"]:
		var path := "res://tests/fixtures/polish4/%s_6_storm.json" % mode
		var ok: bool = await _load_save_file(path)
		await _spawn_world()
		Clock.running = false
		Game.flags["computer_unlocked"] = true
		Weather._alert("Severe weather advisory: heavy snow expected around %s." % Clock.format_time(Clock.minutes + 600.0))
		var target: float = floor(Clock.minutes / 60.0) * 60.0 + 135.0
		Clock.time_scale = 40.0
		Clock.running = true
		var guard := 0
		while Clock.minutes < target and guard < 8000:
			await _frames(1)
			guard += 1
		Clock.running = false
		Clock.time_scale = 1.0
		var ta := Clock.minutes
		var a := await _s8_texts()
		var alerts_a := Weather.alerts.size()
		await _unload()
		await _load_save_file(path)
		await _spawn_world()
		Clock.running = false
		Game.flags["computer_unlocked"] = true
		Weather._alert("Severe weather advisory: heavy snow expected around %s." % Clock.format_time(Clock.minutes + 600.0))
		Clock.skip(ta - Clock.minutes)
		var b := await _s8_texts()
		runner.check(Saves.save_game(), "§8 %s: saved" % mode)
		await _unload()
		var ok3 := Saves.load_game(mode)
		await _spawn_world()
		Clock.running = false
		var c := await _s8_texts()
		runner.check(ok and ok3 and absf(ta - Clock.minutes) < 0.1 and alerts_a > 0, "§8 %s: the storm fixture at %s, in real time, by sleeping, by saving and loading (%d alerts out)" % [mode, Clock.format_time(ta), alerts_a])
		for key in ["tv", "radio", "computer"]:
			runner.check(a[key] == b[key] and b[key] == c[key], "§8 %s: the %s says the same in real time, after a sleep and after save → load%s" % [mode, key, "" if a[key] == b[key] and b[key] == c[key] else ": %s / %s / %s" % [str(a[key]).left(200), str(b[key]).left(200), str(c[key]).left(200)]])
		runner.check(str(a["tv"]).contains("Latest alert") and str(a["radio"]).contains("ending around"), "§8 %s: …the latest alert included, and the radio's start-to-end line" % mode)
		# A TV left on and the radio on screen across the hour.
		world.open_tv()
		world.radio_forecast()
		await _frames(2)
		var before_tv := _s2_texts(world.modal)
		var h0 := Weather.issued_hour()
		Clock.advance(60.0 - fmod(Clock.minutes, 60.0))
		await _frames(2)
		runner.check(Weather.issued_hour() == h0 + 1 and world.modal_kind == "tv", "§8 %s: the hour changed with the TV on" % mode)
		var host := Control.new()
		host.size = Vector2(1920, 1080)
		runner.add_child(host)
		var fresh := Panels.tv(host, func(): pass, false)
		await _frames(1)
		var on_tv := _s2_texts(world.modal)
		runner.check(on_tv == _s2_texts(fresh) and on_tv != before_tv and on_tv.contains("Forecast updated %s" % Weather.hour_name(h0 + 1)), "§8 %s: …the TV shows the new hour's forecast, as a TV turned on now would" % mode)
		runner.check(world.hud.subtitle_l.text == world.radio_text() and world.hud.subtitle_box.visible, "§8 %s: …and the radio's bulletin on screen is the new hour's" % mode)
		host.queue_free()
		world.close_modal()
		Saves.delete_save(mode)
		await _unload()


## The TV's labels, the radio's subtitle and the computer's Weather app, as text.
func _s8_texts() -> Dictionary:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	runner.add_child(host)
	var tv := Panels.tv(host, func(): pass, false)
	var comp := ComputerUI.new()
	host.add_child(comp)
	for k in range(3):
		await _tree().process_frame
	var out := {"tv": _s2_texts(tv), "radio": world.radio_text(), "computer": _s2_texts(comp.content)}
	host.queue_free()
	await _tree().process_frame
	return out


## The fullest displays fit at 1280×720, 1920×1080, 2560×1440 and 3440×1440 (their logical canvases):
## the TV with three snow cards and the longest words on them (and an alert) — every line inside its
## card and the screen, the screen no taller than pass 3's alert line makes it; the longest radio
## bulletin in the subtitle box; the computer's Weather app with every weather upgrade (eight cards
## and the radar's lines), the battery line and a long alert.
func test_s8_fullest_displays_fit() -> void:
	await _load_s8("survival")
	var best := -1
	var best_at := Vector2i(1, 0)
	var longest := ""
	for y in [1, 3, 5]:
		_gen_s8(2024, y)
		for iss in range(24, Weather.HOURS - 72, 3):
			@warning_ignore("integer_division")
			var d := iss / 24
			var score := 0
			for k in range(3):
				var ct := Weather.card_text(Weather.forecast_day(d + k, iss))
				if ct["amount"] != "":
					score += 1000 + str(ct["title"]).length() + str(ct["amount"]).length() + str(ct["when"]).length()
			if score > best:
				best = score
				best_at = Vector2i(y, iss)
			if iss % 3 == 0 and Weather.rate[iss] + Weather.rate[iss + 2] > 0.0:
				Clock.minutes = iss * 60.0 + 20.0
				var t: String = world.radio_text()
				if t.length() > longest.length():
					longest = t
	_gen_s8(2024, best_at.x)
	Game.year = best_at.x
	Clock.minutes = best_at.y * 60.0 + 20.0
	Weather.alerts.append({"time": Clock.minutes, "text": "WEATHER ALERT: an unforecast storm is dumping snow at 41 cm an hour — stay indoors!"})
	var cards := Weather.forecast(3).map(func(e): return Weather.card_line(e))
	runner.info("fullest TV: winter %d, %s: %s; longest bulletin (%d characters): %s" % [best_at.x, Clock.format_time(Clock.minutes), str(cards), longest.length(), longest])
	Game.grant_upgrade(&"weather_pro")
	Game.grant_upgrade(&"weather_radar")
	Game.company_name = "W".repeat(Game.COMPANY_NAME_MAX)
	Survival.cut_power()
	var hud: HUD = world.hud
	var bad := []
	for res in S7_CANVASES.keys():
		var logical: Vector2 = S7_CANVASES[res]
		hud.size = logical
		hud.subtitle(longest, 5.0)
		await _frames(2)
		var view := Rect2(hud.global_position, logical)
		var box := hud.subtitle_box.get_global_rect()
		var l := hud.subtitle_l
		if not (view.encloses(box) and box.end.y <= view.end.y - 249.0 and box.position.y > view.get_center().y + 60.0 and l.get_line_count() == l.get_visible_line_count()):
			bad.append("%s: the bulletin's box %s" % [res, str(box)])
		var host := Control.new()
		host.size = logical
		runner.add_child(host)
		var root := Panels.tv(host, func(): pass, false)
		await _frames(3)
		var scr: Control = root.find_child("Screen", true, false)
		var content: Control = root.find_child("Content", true, false)
		var row: Control = root.find_child("Forecast", true, false)
		var sr := scr.get_global_rect()
		var alert_l: Control = null
		for lab in content.find_children("*", "Label", false, false):
			if (lab as Label).text.begins_with("Latest alert"):
				alert_l = lab
		var grow := sr.size.y - Panels.TV_SCREEN.y
		var allowed := 0.5 + (alert_l.size.y + float(content.get_theme_constant("separation")) if alert_l else 0.0)
		if grow > allowed or not Rect2(Vector2.ZERO, logical).encloses(root.find_child("TV", true, false).get_global_rect()):
			bad.append("%s: the TV grew %.0f px (alert line %.0f)" % [res, grow, allowed])
		for card in row.get_children():
			var cr := (card as Control).get_global_rect()
			if (card as Control).size.x > 368.5 or not sr.encloses(cr):
				bad.append("%s: a card is %s" % [res, str(cr)])
			for lab in (card as Node).find_children("*", "Label", true, false):
				var lr := (lab as Control).get_global_rect()
				var tw := (lab as Label).get_theme_font("font").get_string_size((lab as Label).text, HORIZONTAL_ALIGNMENT_LEFT, -1, (lab as Label).get_theme_font_size("font_size")).x
				if not cr.encloses(lr) or tw > lr.size.x + 1.0:
					bad.append("%s: \"%s\" doesn't fit its card" % [res, (lab as Label).text])
		var comp := ComputerUI.new()
		host.add_child(comp)
		for k in range(4):
			await _tree().process_frame
		for p in _s7_fit_problems(comp, Rect2(Vector2.ZERO, logical)):
			bad.append("%s Weather: %s" % [res, p])
		comp.scroll.scroll_vertical = int(comp.content.size.y)
		for k in range(2):
			await _tree().process_frame
		for p in _s7_fit_problems(comp, Rect2(Vector2.ZERO, logical)):
			bad.append("%s Weather (scrolled): %s" % [res, p])
		var n_cards := 0
		for t in _s2_texts(comp.content).split("\n"):
			n_cards += 1 if t.contains("High ") else 0
		if n_cards != Weather.forecast_days():
			bad.append("%s: the computer shows %d cards with the radar (%d days)" % [res, n_cards, Weather.forecast_days()])
		host.queue_free()
		await _frames(1)
	runner.check(best >= 3000 and longest.contains("ending around") and bad.is_empty(), "§8 the fullest TV (three snow cards: %s, an alert), the longest bulletin (%d characters) and the computer's Weather app with the radar fit at every resolution%s" % [str(cards), longest.length(), "" if bad.is_empty() else " — " + str(bad.slice(0, 6))])
	hud.subtitle("", 0.0)
	Weather.alerts.clear()
	Game.company_name = ""
	await _unload()


# =============================================================================
# §9 Time
# =============================================================================

const S9_EVENING := "res://tests/fixtures/polish5/survival_5_evening.json"


## The clock's rate: 48 game minutes per real minute (Decision 3), a game day in REAL_MIN_PER_DAY
## real minutes; real play moves the clock by it at 1×, and 2× and 10× run exactly 2 and 10 times
## the game time per frame (clear weather, no grader: no cap or hold).
func test_s9_clock_rate() -> void:
	runner.near(Clock.GAME_MIN_PER_REAL_SEC * 60.0, 48.0, 1e-9, "§9 the clock runs 48 game minutes per real minute (%.1f)" % (Clock.GAME_MIN_PER_REAL_SEC * 60.0))
	runner.near(1440.0 / (Clock.GAME_MIN_PER_REAL_SEC * 60.0), 30.0, 1e-9, "§9 a game day lasts 30 real minutes")
	await _s9_world("fun")
	Weather.force(Weather.C.CLEAR, 12.0)
	Clock.running = true
	for sp in Clock.SPEEDS:
		runner.check(Clock.set_speed(sp), "§9 %d× can be chosen on foot" % sp)
		var m0 := Clock.minutes
		await _frames(120)
		var want: float = 120.0 / 60.0 * Clock.GAME_MIN_PER_REAL_SEC * sp
		runner.near(Clock.minutes - m0, want, 0.02 * sp, "§9 at %d× two real seconds (120 frames at 60 fps) are %.1f game minutes (%.2f)" % [sp, want, Clock.minutes - m0])
	Clock.set_speed(1)
	Weather.override_cond = -1
	await _unload()


## Felt rates are recalibrated so they feel the same per real minute at 1× as before polish 5 §9
## (the old values per game hour at 2.5 real minutes a game hour), and still run on game time;
## the values are the same in balance.tres and the defaults.
func test_s9_felt_rates() -> void:
	var b: BalanceData = Catalog.balance
	var d := BalanceData.new()
	# Before §9 (per game hour at 24 game minutes per real minute): exposure 2, 6, 19, 28, 41, 52 %/h,
	# recovery 280 %/h, the pouch +20 %/h for 30 game minutes — per real minute 0.8, 2.4, 7.6, 11.2,
	# 16.4, 20.8; 112; 8, for 75 real seconds.
	var old_exp := [0.8, 2.4, 7.6, 11.2, 16.4, 20.8]
	var ok := b.exposure_curve.size() == old_exp.size() and b.exposure_curve == d.exposure_curve
	for i in range(old_exp.size()):
		ok = ok and is_equal_approx(Survival.per_real_minute(b.exposure_curve[i].y), old_exp[i])
	runner.check(ok, "§9 the exposure curve loses the same warmth per real minute as before (%s %%/game h)" % str(Array(b.exposure_curve).map(func(v): return v.y)))
	runner.near(Survival.per_real_minute(b.warmth_recover_per_hour), 112.0, 1e-6, "§9 warming up by the heat: 112 % per real minute, as before")
	runner.near(Survival.per_real_minute(b.pouch_warmth_per_hour), 8.0, 1e-6, "§9 the heating pouch: +8 % per real minute while it lasts, as before")
	runner.near(b.pouch_protection_minutes / Clock.GAME_MIN_PER_REAL_SEC, 75.0, 1e-6, "§9 …and it lasts 75 real seconds, as before")
	runner.check(b.warmth_recover_per_hour == d.warmth_recover_per_hour and b.pouch_protection_minutes == d.pouch_protection_minutes and b.pouch_warmth_per_hour == d.pouch_warmth_per_hour and b.pouch_warmth == d.pouch_warmth, "§9 the same values in balance.tres and the defaults")
	# On game time: an hour skipped (sleep, an F1 jump) costs what the same game hour costs in play.
	var lost := []
	for how in ["play", "skip"]:
		Game.world = null
		Game.player = null
		Clock.running = false
		Game.new_game("survival", 4242)
		Clock.reset(Clock.at(1, 10.0))
		Survival.in_player_house = false
		Survival.warmth = 100.0
		Weather.force(Weather.C.CLEAR, 10.0)
		if how == "play":
			for k in range(3600):
				Clock.advance(1.0 / 60.0)
		else:
			Clock.skip(60.0)
		lost.append(100.0 - Survival.warmth)
	# (A skip steps 30 game minutes at a time, so the weather's drift within the hour is sampled
	# more coarsely: within 2 %.)
	runner.check(lost[0] > 0.5 and absf(lost[0] - lost[1]) < 0.02 * lost[0], "§9 a game hour outdoors costs the same warmth in play and skipped (%.3f / %.3f %%)" % [lost[0], lost[1]])
	Survival.warmth = 50.0
	Survival.in_player_house = true
	Survival.house_heat = 1.0
	Clock.skip(10.0)
	runner.near(Survival.warmth, minf(100.0, 50.0 + b.warmth_recover_per_hour * 10.0 / 60.0), 0.05, "§9 warming up runs on game time too")
	Weather.override_cond = -1
	# World rates keep their game-time values: a day still has 24 game hours, sleep and F1 jumps
	# move the clock in game time.
	var m0 := Clock.minutes
	Clock.skip(60.0)
	runner.near(Clock.minutes - m0, 60.0, 1e-6, "§9 an F1 '+1 hour' jump is still 60 game minutes")


## A stretch of evening play from the 8:30 p.m. fixture (Survival, on foot in the front yard): a
## storm, a bid that resolves, a contract, the grader's pass from 8:30 p.m. (near the house it is
## watched at 1×; polish 5 §11: the sidewalk crew behind it) and 9 p.m. — run at 1×, 2× and 10×, each to 11:00 p.m. Polish 5 §10: with the
## rivals' bids, the 9 p.m. close and the 9:01 p.m. award, and due times (a miss, a payment, a
## visit falling due, a storm day). They end identical: the snow (every cell's depth and loose depth), the boxes, money,
## contracts and bids, the grader, weather readings, the TV's and the radio's text, warmth,
## notifications. The relaxation's time budget is the one CPU-dependent part of the snow, so it is
## off (tile count only) in all runs.
func test_s9_fast_forward_equals_1x() -> void:
	var runs := []
	# The frame-budget caps only ever lower how many substeps a frame runs (never what one does), so
	# they are off here and 10× really runs 10× away from the grader.
	for cfg in [[1, false], [2, false], [10, false]]:
		runs.append(await _s9_stretch(int(cfg[0]), bool(cfg[1])))
	var base: Dictionary = runs[0]
	runner.info("1×: %d frames, %d substeps; storm %.1f cm, grader passes %s, bid %s, drops %s" % [base["frames"], base["substeps"], base["fell_cm"], base["passes"], base["bid"], base["drops"]])
	runner.check(base["fell_cm"] > 4.0 and base["grader_done"] and base["crossed_9pm"] and base["bid"] != "" and base["bid_was"] == 1, "§9 the stretch has a storm (%.1f cm), a whole grader pass, 9 p.m. and a bid resolved (%s)" % [base["fell_cm"], base["bid"]])
	runner.check(int(base["crew_cleared"]) + int(base["crew_skipped"]) == Municipal.crew_route().size() and int(base["crew_cleared"]) > 0 and base["crew_bare"], "§11 …and the sidewalk crew behind the grader: %d sidewalks cleared, each bare when it was done, %d left to the player's jobs" % [base["crew_cleared"], base["crew_skipped"]])
	runner.check(float(base["melted"]) > 0.3 and float(base["heat_used"]) > 0.0, "§13b …and melting on the clock: the heated driveway, path and pad melted %.2f m³ ($%.2f on the next bill)" % [base["melted"], base["heat_used"]])
	var s10: Dictionary = base["s10"]
	runner.check(s10.values().all(func(x): return x), "§10 …and on the clock: the rivals' bids, the award at 9:01 p.m., a job missed at its due time and back on the board, a job paid, a visit due once the snow stopped (a day later for the storm), a due time the storm moved %s" % str(s10))
	for k in range(1, runs.size()):
		var r: Dictionary = runs[k]
		var diff := []
		for key in base["state"].keys():
			if str(base["state"][key]) != str(r["state"][key]):
				diff.append(key)
		runner.info("%s: %d frames (%d substeps), %.0f %% of the frames at more than 1×, held %d frames, drops %s" % [r["label"], r["frames"], r["substeps"], 100.0 * r["fast_frames"] / maxf(r["frames"], 1.0), r["held"], r["drops"]])
		runner.check(r["substeps"] == base["substeps"] and r["frames"] < base["frames"], "§9 %s took the same %d clock substeps in %d frames (1×: %d)" % [r["label"], r["substeps"], r["frames"], base["frames"]])
		runner.check(diff.is_empty(), "§9 %s ends identical to 1× (snow and §13b's melting, boxes, money, contracts and bids, the grader and the sidewalk crew, weather, TV, radio, warmth, notifications)%s" % [r["label"], "" if diff.is_empty() else " — differs: %s" % str(diff)])
	runner.check(int(runs[2]["fast_frames"]) > 0 and int(runs[2]["held"]) > 0, "§9 10× ran fast away from the grader and was held at 1× while it passed the house (%d / %d frames)" % [runs[2]["fast_frames"], runs[2]["held"]])


static func _s9_sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


## One run of the stretch at a speed: the state at its end, and how it went.
func _s9_stretch(sp: int, caps: bool) -> Dictionary:
	var ok: bool = await _load_save_file(S9_EVENING)
	runner.check(ok, "§9 the evening fixture loads")
	await _spawn_world()
	world.snow_renderer.relax_usec = 0      # deterministic relaxation (tile count only), every run
	# The round-robin positions are transient (not saved) and carry over from the previous run in
	# this process: start every run from the same ones, as a fresh start of the game would.
	Boxes._cursor = 0
	Boxes._near_timer = 0.0
	Snow.sync_cursor = 0
	var notes0 := Notify.history.size()
	Clock.caps_on = caps
	var pl: Player = world.player
	var yard := Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, -6.0), 7.0)
	pl.teleport(Vector3(yard.x, 0.05, yard.y), 0.0)
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	await _frames(2)
	var day := Clock.day_index()
	var t_end := Clock.at(day, 23.0)
	# A storm now, a bid that resolves at 10 p.m., the grader starting its pass.
	Weather.force(Weather.C.HEAVY, 1.5, 3.0)
	var l: Dictionary = Contracts.listings.filter(func(x): return not Contracts.listing_locked(x))[0]
	Contracts.place_bid(int(l["lid"]), int(l["budget"]))
	var bids0 := Contracts.bids.size()
	# §10: due times on the clock — a job due at 10 p.m. that won't be done (its storm day already
	# used: missed, back on the board), a job cleared and waiting to be measured (paid), a recurring
	# client the storm reopens (its visit falls due once the snow stops, a day later for the storm),
	# a job due tomorrow the storm moves a day; the rivals bid on the open listings until 9 p.m.
	var free_lots := Contracts.residential_lots().filter(func(x): return not Contracts._occupied_targets().has("lot:%d" % x["index"]))
	var mk := func(i: int, type: String) -> Dictionary:
		var rr := RandomNumberGenerator.new()
		rr.seed = 500 + i
		var ll := Contracts._add_lot_listing(free_lots[i], day, rr, "path")
		ll["type"] = type
		return Contracts.force_award(int(ll["lid"]))
	var jm: Dictionary = mk.call(0, "one_time")
	jm["due"] = Clock.at(day, 22.0)
	jm["ext"] = true
	var jp: Dictionary = mk.call(1, "one_time")
	for id in Contracts.contract_boxes(jp):
		for r in Boxes.get_box(id)["rects"]:
			Snow.set_rect(r, 0.0)
	var jr: Dictionary = mk.call(2, "recurring")
	_s10_clear(jr)
	var je: Dictionary = mk.call(3, "one_time")
	var je_due := float(je["due"])
	var money_s10 := Game.money
	Municipal.next_pass = Clock.minutes
	Municipal.on_hour(day, Clock.hour())
	var passes0 := Municipal.passes
	var started: bool = Municipal.in_progress and world.grader.active
	var fall0 := Snow.fall_total
	# §13b: melting runs on the clock too — the heated driveway and path, and the heated pad on the
	# lawn with a pile of snow on it.
	Game.upgrades["heated_driveway"] = true
	Game.upgrades["heated_path"] = true
	var pad_at := Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, -10.0), 3.0)
	Game.equipment["heated_pad"] = {"pos": [pad_at.x, 0.0, pad_at.y], "yaw": 0.0}
	world.refresh_pad()
	Snow.deposit(pad_at, 0.8, 0.9)
	var melted0 := Snow.melted
	var crew_done := {}
	var on_done := func(id: String):
		if Boxes.quiet:
			crew_done[id] = Snow.volume_in_rect(Boxes.get_box(id)["rects"][0])
	Boxes.box_completed.connect(on_done)
	var drops := []
	var cb := func(s: int, why: String):
		if s == 1 and why != "":
			drops.append(why)
	Clock.speed_changed.connect(cb)
	var step := 1.0 / 60.0 * Clock.GAME_MIN_PER_REAL_SEC
	var frames := 0
	var substeps := 0
	var fast := 0
	var held := 0
	var crossed := false
	while Clock.minutes < t_end - 1e-9 and frames < 30000:
		var want := sp if t_end - Clock.minutes > (sp + 1) * step else 1
		if Clock.speed != want:
			Clock.set_speed(want)
		await _tree().physics_frame
		frames += 1
		substeps += maxi(Clock.substeps_last_frame, 1)
		if Clock.substeps_last_frame > 1:
			fast += 1
		if Clock.speed > 1 and Clock.hold_reason() != "":
			held += 1
		crossed = crossed or Clock.minutes >= Clock.at(day, 21.0)
	Clock.speed_changed.disconnect(cb)
	Boxes.box_completed.disconnect(on_done)
	Clock.set_speed(1)
	Clock.caps_on = true
	# What a player could see or that is saved.
	Snow.sync_all()
	var tv := Panels.tv(world.hud, func(): pass, false)
	var tv_text := _s2_texts(tv)
	tv.queue_free()
	var g: GraderNPC = world.grader
	var notes := []
	for n in Notify.history.slice(notes0):
		notes.append("%s|%s" % [str(n["time"]), str(n["text"])])
	var state := {
		"clock": var_to_str(Clock.minutes),
		"snow": _s9_sha(Snow.depth.to_byte_array() + Snow.loose.to_byte_array()) + var_to_str([Snow.fall_total, Snow.roof_depth, Snow.roof_extra, Snow.melted]),
		"boxes": var_to_str(Boxes.serialize()),
		"money": Game.money,
		"game": var_to_str(Game.serialize()),
		"contracts": var_to_str(Contracts.serialize()),
		"economy": var_to_str(Economy.serialize()),
		"grader": var_to_str([Municipal.serialize(), Municipal.in_progress, g.active, g.lane_i, g.s, g.applied_s]),
		# Polish 5 §11: the sidewalk crew behind the grader, on the same per-step tick.
		"crew": var_to_str([world.crew.active, world.crew.run_i, world.crew.s, world.crew.applied_s, Municipal.crew_pending, Municipal.crew_log]),
		"weather": var_to_str([Weather.condition(), Weather.snow_rate(), Weather.temperature(), Weather.wind_chill(), Weather.serialize()]),
		"tv": tv_text,
		"radio": world.radio_text(),
		"warmth": var_to_str(Survival.serialize()),
		"notifications": "\n".join(notes),
	}
	var out := {"label": "%d×%s" % [sp, " (caps on)" if caps else ""], "state": state, "frames": frames, "substeps": substeps,
		"fast_frames": fast, "held": held, "drops": drops, "fell_cm": (Snow.fall_total - fall0) * 100.0,
		"passes": "%d → %d" % [passes0, Municipal.passes], "grader_done": started and not Municipal.in_progress and not g.active and not world.crew.active,
		"crew_cleared": Municipal.crew_log.values().count("cleared"), "crew_skipped": Municipal.crew_log.values().count("skipped"),
		# Each sidewalk the crew cleared was bare when it completed it (the storm reopens them later).
		"crew_bare": crew_done.size() == Municipal.crew_log.values().count("cleared") and crew_done.values().all(func(v): return v < 1e-9),
		"crossed_9pm": crossed, "bid_was": bids0, "melted": Snow.melted - melted0, "heat_used": Economy.heat_used, "bid": "" if not Contracts.bids.is_empty() else ("won" if Contracts.active.any(func(c): return c["target"] == l["target"]) else "lost"),
		"s10": {"missed": jm["status"] == "lost" and Contracts.listings.any(func(x): return x["target"] == jm["target"] and x.get("relisted", false)),
			"paid": jp["status"] == "completed" and Game.money >= money_s10 + int(jp["pay"]),
			"visit": jr["status"] == "needs_service" and bool(jr["ext"]) and is_equal_approx(float(jr["due"]), Clock.at(day + 1, Contracts.DUE_HOUR) + Contracts.STORM_EXTENSION_MIN),
			"storm": bool(je["ext"]) and is_equal_approx(float(je["due"]), je_due + Contracts.STORM_EXTENSION_MIN),
			"rivals": l["rivals"].any(func(rv): return int(rv["bid"]) > 0)}}
	await _unload()
	Saves.delete_save("survival")
	return out


## A game on Dec 2 at `hour` after the tutorial (no Gerry), the clock running, the player on foot
## in the front yard of their house (on the snow, a shovel in slot 1), clear weather.
func _s9_world(mode := "fun", hour := 12.0) -> void:
	await _unload()
	Game.force_input = true
	Game.new_game(mode, 2024)
	Game.flags["mail_read"] = true
	Game.flags["computer_unlocked"] = true
	Game.flags["truck_keys"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	Clock.reset(Clock.at(1, hour))
	await _spawn_world()
	_s9_yard()
	Game.slots = ["standard_shovel", "", "", ""]
	Game.selected = 0
	Weather.force(Weather.C.CLEAR, 48.0)
	Clock.running = true
	await _frames(80)       # the world fades in over 1.2 s (the speed control shows after it)


func _s9_yard() -> void:
	var pl: Player = world.player
	var yard := Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, -6.0), 7.0)
	pl.teleport(Vector3(yard.x, 0.05, yard.y), 0.0)
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0


## Choose 10× (it must be available).
func _s9_fast() -> bool:
	return Clock.set_speed(10) and Clock.speed == 10


## Every way fast-forward goes back to 1× on its own, where it's available and where not, and the
## key (cycling, ignored while typing, the vehicle's radio in a vehicle).
func test_s9_auto_return_and_availability() -> void:
	await _s9_world("survival")
	var pl: Player = world.player
	Survival.warmth = 100.0
	Municipal.next_pass = Clock.minutes + 3.0 * 1440.0   # no grader pass during the test
	# The key: 1× → 2× → 10× → 1×, as real key events for its binding.
	runner.check(Settings.ACTIONS.has("fast_forward") and Settings.ACTIONS["fast_forward"][2] == _s2_k(KEY_T) and Settings.action_label("fast_forward") == "T", "§9 the fast-forward key defaults to T (%s)" % Settings.action_label("fast_forward"))
	runner.check("fast_forward" in Settings.RATE_LIMITED and "fast_forward" in Settings.live_actions("foot") and "fast_forward" in Settings.live_actions("computer") and not ("fast_forward" in Settings.live_actions("vehicle")), "§9 …capped like every press, read on foot and at the computer, not in a vehicle")
	var seen := []
	for k in range(3):
		await _s2_key("fast_forward")
		seen.append(Clock.speed)
	runner.check(seen == [2, 10, 1], "§9 the key cycles 1× → 2× → 10× → 1× (%s)" % str(seen))
	# A weather alert.
	_s9_fast()
	Weather._alert("Test alert.")
	runner.check(Clock.speed == 1 and Clock.drop_reason == "alert", "§9 a weather alert: back to 1× (%s)" % Clock.drop_reason)
	# A contract warning (the hook §10's deadline warnings call too).
	var l: Dictionary = Contracts.listings[0]
	var c := Contracts.force_award(int(l["lid"]))
	c["status"] = "active"
	c["type"] = "one_time"
	for z in c["zones"]:
		for id in z["boxes"]:
			Boxes.get_box(id)["complete"] = false
	var b: BalanceData = Catalog.balance
	c["due"] = Clock.minutes + b.contract_warn_hours * 60.0 + 0.5    # §10: the warning 12 h before it's due
	c["warned"] = 0
	_s9_fast()
	for k in range(60):
		await _frames(1)
		if int(c["warned"]) >= 1:
			break
	runner.check(int(c["warned"]) == 1 and Clock.speed == 1 and Clock.drop_reason == "contract", "§9 a contract warning: back to 1× (%s, warned %d)" % [Clock.drop_reason, int(c["warned"])])
	Contracts.active.erase(c)
	# A bid won or lost.
	var l2: Dictionary = Contracts.listings.filter(func(x): return not Contracts.listing_locked(x))[0]
	Contracts.place_bid(int(l2["lid"]), int(l2["budget"]))
	l2["closes"] = Clock.minutes - Contracts.AWARD_DELAY_MIN    # §10: closed, its award due now
	_s9_fast()
	var n_bids := Contracts.bids.size()
	Contracts.on_advance(0.0)
	runner.check(Contracts.bids.size() == n_bids - 1 and Clock.speed == 1 and Clock.drop_reason == "bid", "§9 a bid won or lost: back to 1× (%s)" % Clock.drop_reason)
	# A Survival cold warning.
	Survival.warmth = 45.2
	Survival._state = Survival.state()
	Weather.force(Weather.C.MODERATE, 4.0, 0.5)
	_s9_fast()
	for k in range(600):
		await _frames(1)
		if Survival.state() >= Survival.St.COLD:
			break
	await _frames(1)
	runner.check(Survival.state() == Survival.St.COLD and Clock.speed == 1 and Clock.drop_reason == "cold", "§9 a cold warning: back to 1× (%s, warmth %.1f)" % [Clock.drop_reason, Survival.warmth])
	Survival.warmth = 100.0
	Weather.force(Weather.C.CLEAR, 48.0)
	# Starting to scoop, push or throw.
	pl.pitch = deg_to_rad(-40.0)
	pl.head.rotation.x = pl.pitch
	await _frames(2)
	_s9_fast()
	Input.action_press("primary")
	await _frames(3)
	runner.check(Clock.speed == 1 and Clock.drop_reason == "work" and pl.tools.filling, "§9 starting to scoop: back to 1× (%s)" % Clock.drop_reason)
	for k in range(20):
		pl.set_yaw(0.3 * sin(k * 0.3))
		await _frames(1)
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	await _frames(2)
	runner.check(_s9_fast(), "§9 …10× can be chosen again while holding a load (%.1f L)" % (pl.tools.load * 1000.0))
	Input.action_release("primary")
	await _frames(3)
	runner.check(Clock.speed == 1 and Clock.drop_reason == "work", "§9 throwing: back to 1× (%s)" % Clock.drop_reason)
	await _s3_settle()
	_s9_fast()
	Input.action_press("secondary")
	await _frames(3)
	Input.action_release("secondary")
	runner.check(Clock.speed == 1 and Clock.drop_reason == "work", "§9 starting to push: back to 1× (%s)" % Clock.drop_reason)
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	await _frames(2)
	# Getting into a vehicle; none there, and its T is the radio.
	var truck: Vehicle = world.vehicle_nodes()[0]
	_s9_fast()
	truck.enter_vehicle(pl)
	await _frames(2)
	runner.check(Clock.speed == 1 and Clock.drop_reason == "vehicle", "§9 getting into a vehicle: back to 1× (%s)" % Clock.drop_reason)
	runner.check(not Clock.set_speed(10) and Clock.unavailable_reason() == "vehicle", "§9 …no fast-forward in a vehicle")
	var n0 := Notify.history.size()
	await _s2_key("fast_forward")
	runner.check(Clock.speed == 1 and Notify.history.size() == n0 + 1 and str(Notify.history[-1]["text"]).begins_with("Radio:"), "§9 …where %s is the radio" % Settings.action_label("fast_forward"))
	truck.exit_vehicle()
	await _frames(3)
	# At a walk-behind machine.
	var wb := _s3_blower("small_blower", pl.global_position + Vector3(1.5, 0, 0))
	await _frames(2)
	_s9_fast()
	wb.interact(pl)
	await _frames(2)
	runner.check(Clock.speed == 1 and not Clock.set_speed(10) and Clock.unavailable_reason() == "machine", "§9 at a machine: back to 1×, not available (%s)" % Clock.unavailable_reason())
	wb.release()
	await _frames(2)
	# Gerry's lines, a dialog, sleep.
	_s9_fast()
	world.say_gerry([{"speaker": "Gerry", "text": "Just a test line."}])
	await _frames(2)
	runner.check(Clock.speed == 1 and not Clock.set_speed(10) and Clock.unavailable_reason() == "gerry", "§9 during Gerry's lines: back to 1×, not available")
	while world.is_gerry_talking():
		world._talk_next()
	await _frames(1)
	for kind in ["sleep", "pause"]:
		_s9_fast()
		if kind == "sleep":
			world.open_sleep()
		else:
			world._open_pause()
		await _frames(2)
		runner.check(Clock.speed == 1 and not Clock.set_speed(10) and world.speed_ctrl.visible == false, "§9 the %s dialog: back to 1×, not available, the control hidden" % kind)
		await _tree().process_frame
		world.close_modal()
		await _tree().process_frame
		await _frames(2)
	_s9_fast()
	var sleeping := [0]
	var watch := func(_d: int, _h: int):
		if Clock.skipping and Clock.unavailable_reason() == "sleep" and not Clock.set_speed(10):
			sleeping[0] += 1
	Clock.hour_changed.connect(watch)
	await world._do_sleep()
	Clock.hour_changed.disconnect(watch)
	runner.check(Clock.speed == 1 and Clock.drop_reason == "sleep" and sleeping[0] > 10 and Clock.hour() == 7, "§9 sleeping: back to 1×, not available all night (%d hours), wake at 7:00 (%s)" % [sleeping[0], Clock.time_string()])
	await _frames(70)
	runner.check(Clock.set_speed(10), "§9 …and available again in the morning")
	Clock.set_speed(1)
	Municipal.next_pass = Clock.minutes + 3.0 * 1440.0   # no grader pass (and its cap) in what follows
	# The computer: available there, and the clock runs 10 substeps a frame.
	world.open_computer()
	await _frames(2)
	runner.check(world.modal_kind == "computer" and _s9_fast(), "§9 at the computer: fast-forward available")
	await _frames(3)
	runner.check(Clock.substeps_last_frame == 10, "§9 …the clock runs 10 substeps a frame there (%d)" % Clock.substeps_last_frame)
	# Typing in a text field: the key is ignored (the field gets the letter).
	var cu: ComputerUI = world.modal
	cu._open_app(ComputerUI.app_index("contracts"))
	await _frames(3)
	runner.check(cu.form_up() and Game.typing(), "§9 the company-name field has the focus")
	var before := cu.name_edit.text
	var d := _s7_event("fast_forward", true)
	Input.parse_input_event(d)
	await _frames(2)
	Input.parse_input_event(_s7_event("fast_forward", false))
	await _frames(2)
	runner.check(Clock.speed == 10 and cu.name_edit.text != before, "§9 while typing the key is ignored (still 10×; the field reads \"%s\")" % cu.name_edit.text)
	Clock.set_speed(1)
	world.close_modal()
	await _frames(2)
	_release_all()
	Weather.override_cond = -1
	await _unload()


## Scripted movers and the frame budget: the grader within reach holds the clock at 1× for its
## pass (the chosen speed is kept and comes back once it's gone); while it drives elsewhere, or snow
## is still settling, 10× runs at 2× (a frame's slumping per substep); snowfall from 0.5 cm/h caps
## 10× at 2×, and a major event's heaviest hours every speed at 1×. The control shows why.
func test_s9_holds_and_caps() -> void:
	await _s9_world("fun")
	var pl: Player = world.player
	var sc: SpeedControl = world.speed_ctrl
	Municipal.next_pass = Clock.minutes
	Municipal.on_hour(Clock.day_index(), Clock.hour())
	await _frames(2)
	var g: GraderNPC = world.grader
	runner.check(g.active, "§9 the grader is on its route")
	pl.teleport(Vector3(g.global_position.x + 12.0, 0.05, g.global_position.z - 6.0))   # on the sidewalk ahead
	await _frames(1)
	runner.check(_s9_fast(), "§9 10× chosen with the grader 12 m away")
	await _frames(3)
	runner.check(Clock.hold_reason() == "grader" and Clock.effective_speed() == 1 and Clock.speed == 10 and Clock.substeps_last_frame == 1, "§9 …held at 1× for the pass (chosen 10×, running %d×)" % Clock.effective_speed())
	runner.check(sc.note_l.visible and sc.note_l.text.contains("grader") and sc.buttons[0].get_theme_stylebox("normal") == sc._st_on and sc.buttons[2].get_theme_stylebox("normal") == sc._st_chosen, "§9 …the control shows 1× running, 10× chosen: \"%s\"" % sc.note_l.text)
	pl.teleport(Vector3(20.0, Snow.ground_at(20.0, 20.0) + 0.05, 20.0))
	await _frames(3)
	runner.check(Clock.hold_reason() == "" and Clock.effective_speed() == 2 and Clock.substeps_last_frame == 2 and sc.note_l.text.contains("Max 2×"), "§9 the grader elsewhere: 10× runs at 2× (\"%s\")" % sc.note_l.text)
	# The pass over: its windrows settle for a while (relaxation, real time — at 2× while each
	# substep's share is heavy), then 10× again.
	world.finish_grader_now()
	Snow.relax_until_stable()
	for k in range(3600):
		if Snow.relax_pending() == 0:
			break
		await _frames(1)
	await _frames(3)
	runner.check(not g.active and Clock.effective_speed() == 10 and Clock.substeps_last_frame == 10 and not sc.note_l.visible, "§9 the pass over: back to the chosen 10× (%d×, %d substeps, \"%s\")" % [Clock.effective_speed(), Clock.substeps_last_frame, sc.note_l.text if sc.note_l.visible else ""])
	# A big pile settling: a substep's slumping costs more than FF_RELAX_US, so 10× runs at 2×.
	var spot := Vector2(pl.global_position.x + 6.0, pl.global_position.z)
	for k in range(15):
		Snow.deposit(spot + Vector2((k % 5) * 1.5, 0.0), 5.0, 1.2, true)
	await _frames(3)
	runner.check(Clock.effective_speed() == 2 and sc.note_l.text.contains("settling"), "§9 a 75 m³ pile settling: 10× runs at 2× (\"%s\", %d µs a substep)" % [sc.note_l.text, world.snow_renderer.relax_us_last])
	Snow.relax_until_stable()
	await _frames(3)
	Weather.force(Weather.C.HEAVY, 2.0, 3.0)
	await _frames(3)
	runner.check(Clock.speed_cap() == 2 and Clock.effective_speed() == 2 and Clock.speed == 10 and sc.note_l.text.begins_with("Max 2×"), "§9 snowing hard (3 cm/h): 10× capped at 2× (\"%s\")" % sc.note_l.text)
	Weather.force(Weather.C.LIGHT, 2.0, 0.6)
	await _frames(3)
	runner.check(Clock.effective_speed() == 2, "§9 light snow (0.6 cm/h): 10× runs at 2× too")
	Weather.force(Weather.C.LIGHT, 2.0, 0.3)
	await _frames(3)
	runner.check(Clock.effective_speed() == 10, "§9 barely snowing (0.3 cm/h): 10×")
	Weather.force(Weather.C.BLIZZARD, 2.0, 50.0)   # (its warning drops to 1×: choose after it)
	Clock.set_speed(2)
	await _frames(3)
	runner.check(Clock.effective_speed() == 2, "§9 a major event (50 cm/h): 2× runs at 2×")
	Weather.force(Weather.C.BLIZZARD, 2.0, 109.6)
	Clock.set_speed(2)
	await _frames(3)
	runner.check(Clock.effective_speed() == 1 and Clock.speed == 2 and sc.note_l.text.begins_with("Max 1×"), "§9 …its heaviest hour (110 cm/h): 1× (\"%s\")" % sc.note_l.text)
	Clock.set_speed(1)
	Weather.override_cond = -1
	await _unload()


## The control beside the HUD clock: 1×, 2×, 10× and the key, the speed running highlighted; a
## real click on a button works whenever the cursor is free (at the computer, over its dim), and
## not while the mouse is captured; greyed in a vehicle.
func test_s9_speed_control() -> void:
	await _s9_world("fun")
	var sc: SpeedControl = world.speed_ctrl
	var hud: HUD = world.hud
	await _frames(2)
	var cr := hud.clock_panel.get_global_rect()
	var pr := sc.panel.get_global_rect()
	runner.check(sc.visible and pr.position.x >= cr.end.x and pr.position.x - cr.end.x < 24.0 and absf(pr.position.y - cr.position.y) < 1.0, "§9 the control sits beside the clock (%s / %s)" % [str(cr), str(pr)])
	var texts := sc.buttons.map(func(x): return (x as Button).text)
	runner.check(texts == ["1×", "2×", "10×"] and sc.key_l.text == "[%s]" % Settings.action_label("fast_forward"), "§9 it reads %s %s" % [str(texts), sc.key_l.text])
	runner.check(sc.buttons[0].get_theme_stylebox("normal") == sc._st_on and sc.buttons[1].get_theme_stylebox("normal") == sc._st_off, "§9 1× highlighted at the start")
	# Mouse captured: the buttons ignore the mouse.
	runner.check(Game.input_captured() and sc.buttons[2].mouse_filter == Control.MOUSE_FILTER_IGNORE, "§9 the buttons ignore the mouse while it's captured")
	# At the computer: a real click on 10×, then on 2×.
	world.open_computer()
	await _frames(3)
	for k in [2, 1]:
		var b: Button = sc.buttons[k]
		var at := b.get_global_rect().get_center()
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			var p: Vector2 = _tree().root.get_final_transform() * at
			e.position = p
			e.global_position = p
			Input.parse_input_event(e)
			await _tree().process_frame
		await _frames(2)
		runner.check(Clock.speed == Clock.SPEEDS[k] and sc.buttons[k].get_theme_stylebox("normal") == sc._st_on, "§9 a click on %s over the computer's dim chooses it (%d×)" % [b.text, Clock.speed])
	# With its note showing (10× capped by snowfall), the control stays clear of the computer's window.
	Clock.set_speed(10)
	Weather.force(Weather.C.HEAVY, 2.0, 3.0)
	await _frames(3)
	var win_top := (1080.0 - ComputerUI.WIN.y) * 0.5      # the window is centred on the 1080-px canvas
	var pr2 := sc.panel.get_global_rect()
	runner.check(sc.note_l.visible and pr2.end.y <= win_top, "§9 …and stays clear of the computer's window with its note showing (%.1f ≤ %.1f: \"%s\")" % [pr2.end.y, win_top, sc.note_l.text])
	Weather.force(Weather.C.CLEAR, 48.0)
	Clock.set_speed(2)
	world.close_modal()
	await _frames(2)
	# In a vehicle: greyed (and back to 1×).
	var truck: Vehicle = world.vehicle_nodes()[0]
	truck.enter_vehicle(world.player)
	await _frames(2)
	runner.check(sc.visible and sc.buttons[1].disabled and sc.buttons[2].disabled and Clock.speed == 1, "§9 in a vehicle the control is greyed")
	truck.exit_vehicle()
	await _frames(2)
	await _unload()


## Fast-forward is never saved: a save made at 10× loads at 1×, and so does a new game.
func test_s9_not_saved() -> void:
	await _s9_world("fun")
	runner.check(_s9_fast(), "§9 10× chosen")
	world.collect_state()
	runner.check(Saves.save_game(), "§9 saved at 10×")
	var txt := FileAccess.get_file_as_string(Saves.path_for("fun"))
	runner.check(not txt.contains("\"speed\"") and not txt.contains("fast_forward"), "§9 …nothing about the speed in the save")
	await _unload()
	Clock.speed = 10
	runner.check(Saves.load_game("fun") and Clock.speed == 1, "§9 a load starts at 1×")
	await _spawn_world()
	await _frames(80)
	runner.check(Clock.speed == 1 and world.speed_ctrl.visible and world.speed_ctrl.buttons[0].get_theme_stylebox("normal") == world.speed_ctrl._st_on, "§9 …and the world shows 1×")
	await _unload()
	Clock.speed = 10
	Game.new_game("fun", 7)
	runner.check(Clock.speed == 1, "§9 a new game starts at 1×")
	Saves.delete_save("fun")



## Gerry is a scripted mover too: while he walks down his trail to meet the player (they're near
## him), fast-forward is held at 1× — and resumes when he stops.
func test_s9_gerry_walk_holds() -> void:
	await _unload()
	Game.force_input = true
	Game.new_game("fun", 2024)
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.LETTER_READ)
	Contracts.create_tutorial_contract(50)
	Game.set_stage(Game.Stage.NEIGHBOR_TALKED)
	Clock.reset(Clock.at(0, 10.0))
	await _spawn_world()
	Weather.force(Weather.C.CLEAR, 12.0)
	Municipal.next_pass = Clock.minutes + 3.0 * 1440.0
	await _frames(80)
	var n: Neighbor = world.neighbor
	var foot := Vector2(Neighbor.meet_point().x, Neighbor.meet_point().z) - Vector2(Layout.neighbor_lot["inward"]).normalized() * 3.0
	world.player.teleport(Vector3(foot.x, Snow.ground_at(foot.x, foot.y) + 0.05, foot.y))
	runner.check(_s9_fast(), "§9 10× chosen by Gerry's mailbox")
	var tb := Boxes.get_box("gerry_trail")
	for r in tb["rects"]:
		Snow.set_rect(r, 0.0)
	for c in Contracts.active:
		if c.get("tutorial", false):
			for z in c["zones"]:
				Contracts.measure_zone(c, z)
	var held := 0
	var walked := 0
	for k in range(240):
		await _frames(1)
		if n.is_walking():
			walked += 1
			if Clock.speed == 10 and Clock.hold_reason() == "gerry" and Clock.substeps_last_frame <= 1:
				held += 1
	runner.check(Game.stage() == Game.Stage.TRAIL_DONE and walked > 20 and held == walked, "§9 Gerry walking down to meet the player holds the clock at 1× (%d of %d frames)" % [held, walked])
	runner.check(world.ff_hold() == "" or n.is_walking(), "§9 …and the hold ends when he stops")
	Clock.set_speed(1)
	world.close_modal()
	await _unload()


# =============================================================================
# §10 Contracts — §10a: the rules (tiers and reputation, the bidding day, due times, old saves)
# =============================================================================

## The board's card for a listing (the live one: a rebuild frees the old cards at the end of the frame).
func _s10_card(comp: ComputerUI, lid: int) -> Node:
	for n in comp.content.get_children():
		if int(n.get_meta("lid", -1)) == lid and not n.is_queued_for_deletion():
			return n
	return null


## A new game (no world), the clock stopped, simulated to `day` at `hour`, the weather clear.
func _s10_game(mode := "fun", day := 1, hour := 10.0) -> void:
	await _unload()
	Game.world = null
	Game.player = null
	Clock.running = false
	Clock.speed = 1
	Municipal.world_handles_passes = false
	Game.new_game(mode, 2024)
	Game.flags["mail_read"] = true
	Game.flags["computer_unlocked"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	Game.company_name = "Test Snow Co."
	Weather.force(Weather.C.CLEAR, 400.0)
	Clock.skip(Clock.at(day, hour) - Clock.minutes)
	Weather.force(Weather.C.CLEAR, 400.0)
	Notify.clear()


## A residential job of `kind` on the `i`-th residential lot, won outright now.
func _s10_job(i: int, kind := "path", type := "one_time") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + i
	var l := Contracts._add_lot_listing(Contracts.residential_lots()[i], Clock.day_index(), rng, kind)
	l["type"] = type
	return Contracts.force_award(int(l["lid"]))


## Clear a contract's boxes (the snow set to bare ground and measured, as a finished job).
func _s10_clear(c: Dictionary) -> void:
	for z in c["zones"]:
		for id in z["boxes"]:
			var b := Boxes.get_box(id)
			for r in b["rects"]:
				Snow.set_rect(r, 0.0)
			Boxes.measure(b, true)


func _s10_notes_since(n0: int, prefix: String) -> Array:
	return Notify.history.slice(n0).filter(func(n): return str(n["text"]).begins_with(prefix))


## JSON as a save writes and reads it (numbers as JSON has them), keys sorted.
static func _s10_norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)), "", true)


## Tiers (Decision 5): the names and thresholds are balance values (the same in balance.tres and the
## defaults); listings above the player's tier are locked ("Needs reputation N") and can't be bid on;
## reaching a tier gives one notification; reputation rises on completion (scaled with the job's
## size, harder to earn near the top) and falls on a miss by the existing amount; F1 sets it.
func test_s10_tiers_and_reputation() -> void:
	await _s10_game()
	var b: BalanceData = Catalog.balance
	var tres: BalanceData = load("res://data/balance.tres")
	var dflt := BalanceData.new()
	var same := true
	for k in ["rep_tier_names", "rep_tier_thresholds", "driveway_share_rep0", "driveway_share_commercial", "rep_gain_base", "rep_gain_per_m3",
			"rep_gain_max", "rep_visit_factor", "rep_gain_full_below", "listings_per_day", "listing_share_commercial", "listing_share_city",
			"listing_recurring_share", "listing_res_max_m3", "bid_floor_frac", "rival_count_min", "rival_count_max", "rival_open_min",
			"rival_open_max", "rival_reply_chance", "rival_replies_max", "rival_reply_step_min", "rival_reply_step_max", "contract_history_max"]:
		if str(tres.get(k)) != str(dflt.get(k)):
			same = false
			runner.info("balance %s: tres %s, default %s" % [k, str(tres.get(k)), str(dflt.get(k))])
	var th: PackedFloat32Array = b.rep_tier_thresholds
	runner.check(same and Array(b.rep_tier_names) == ["Residential", "Commercial", "City"] and th.size() == 3 and th[0] == 0.0 and th[1] > Game.reputation and th[2] > th[1],
		"§10 the tiers are balance values, the same in balance.tres and the defaults: %s at %s (the game starts at %d)" % [str(b.rep_tier_names), str(th), int(Game.reputation)])
	runner.check(is_equal_approx(b.driveway_share_rep0, 0.25) and is_equal_approx(b.driveway_share_commercial, 0.5), "§10 driveway share: a quarter at reputation 0, half at the Commercial threshold")
	runner.check(Contracts.tier_index() == 0 and Contracts.tier_index(th[1] - 0.1) == 0 and Contracts.tier_index(th[1]) == 1 and Contracts.tier_index(th[2]) == 2, "§10 the tier follows the thresholds")
	# A commercial and a city listing, locked at the start.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var la := Contracts._add_area_listing(Layout.big_areas[0], Clock.day_index(), rng)
	var lc := Contracts._add_walk_listing("B_w", Clock.day_index(), rng)
	runner.check(Contracts.listing_locked(la) and Contracts.listing_locked(lc) and not Contracts.place_bid(int(la["lid"]), int(la["budget"]))["ok"]
		and Contracts.place_bid(int(la["lid"]), int(la["budget"]))["msg"] == "Needs reputation %d." % int(th[1]), "§10 above your tier: locked, no bid (\"Needs reputation %d.\")" % int(th[1]))
	# Reaching a tier: one notification.
	var n0 := Notify.history.size()
	Contracts.adjust_reputation(th[1] - Game.reputation)
	var notes := _s10_notes_since(n0, "Commercial tier reached")
	Contracts.adjust_reputation(-1.0)
	Contracts.adjust_reputation(1.0)
	runner.check(Contracts.tier_index() == 1 and notes.size() == 1 and _s10_notes_since(n0, "Commercial tier reached").size() == 1, "§10 reaching Commercial: one notification (\"%s\")" % (notes[0]["text"] if not notes.is_empty() else "none"))
	runner.check(not Contracts.listing_locked(la) and Contracts.listing_locked(lc) and Contracts.place_bid(int(la["lid"]), int(la["budget"]))["ok"], "§10 …parking lots unlock, the city's still locked")
	Contracts.adjust_reputation(th[2] - Game.reputation)
	runner.check(Contracts.tier_index() == 2 and not Contracts.listing_locked(lc) and _s10_notes_since(n0, "City tier reached").size() == 1, "§10 …and City at %d" % int(th[2]))
	# Gains scale with size and fall off near the top; a miss costs the existing amount.
	runner.check(Contracts.rep_gain(2.0, false, 50.0) < Contracts.rep_gain(20.0, false, 50.0) and Contracts.rep_gain(20.0, false, 90.0) < Contracts.rep_gain(20.0, false, 50.0) and Contracts.rep_gain(2.0, false, 99.9) > 0.0,
		"§10 the gain grows with the job's size (%.2f for 2 m³, %.2f for 20 m³) and is harder to earn near the top (%.2f at 90)" % [Contracts.rep_gain(2.0, false, 50.0), Contracts.rep_gain(20.0, false, 50.0), Contracts.rep_gain(20.0, false, 90.0)])
	Contracts.adjust_reputation(50.0 - Game.reputation)
	var c := _s10_job(0, "path")
	var r0 := Game.reputation
	var want := Contracts.rep_gain(float(c["size"]))
	_s10_clear(c)
	runner.check(c["status"] == "completed" and is_equal_approx(Game.reputation, r0 + want) and want > 0.0, "§10 reputation rises on completion: +%.2f for a %.1f m³ path" % [want, float(c["size"])])
	var c2 := _s10_job(1, "path")
	r0 = Game.reputation
	c2["due"] = Clock.minutes + 0.5
	Clock.advance(1.0)
	runner.check(c2["status"] == "lost" and is_equal_approx(Game.reputation, r0 - b.contract_lost_reputation), "§10 …and falls by %d on a miss" % int(b.contract_lost_reputation))
	# F1: set reputation (the tier follows), jump to 8:59 p.m.
	var dm := DebugMenu.new()
	runner.add_child(dm)
	await _frames(1)
	dm._set_rep(th[1])
	var ok_rep := Contracts.tier_index() == 1 and is_equal_approx(Game.reputation, th[1])
	var pressed := false
	for bt in dm.find_children("*", "Button", true, false):
		if (bt as Button).text == "8:59 p.m.":
			(bt as Button).pressed.emit()
			pressed = true
	runner.check(ok_rep and pressed and Clock.hour() == 20 and Clock.minute_of_hour() == 59, "§10 F1: set the reputation (%d · %s), jump to 8:59 p.m. (%s)" % [int(Game.reputation), Contracts.tier_name(Contracts.tier_index()), Clock.time_string()])
	dm.queue_free()
	await _frames(1)


## Paths first (Decision 5): over many simulated boards, path jobs outnumber driveway jobs at low
## reputation and the share of driveways grows with reputation (driveways a shovel can do in a day:
## every residential box cleared before a storm). And the board never posts a residential job
## bigger than the player's equipment clears in a day: untouched driveways (a season of snow) aren't
## offered to a player with a shovel.
func test_s10_paths_first() -> void:
	await _s10_game()
	for lot in Contracts.residential_lots():
		for kind in ["path", "driveway"]:
			var bx := Boxes.get_box(Boxes.lot_box(lot, kind))
			for r in bx["rects"]:
				Snow.set_rect(r, 0.0)
			Boxes.measure(bx, true)
	Snow.add_snowfall(0.2)
	Boxes.measure_all(true)
	var shares := []
	var counts := []
	for rep in [0.0, 30.0, 50.0, Catalog.balance.rep_tier_thresholds[1]]:
		Game.reputation = rep
		var n := {"path": 0, "driveway": 0}
		for d in range(200):
			Contracts.listings.clear()
			Contracts._generate_listings(d % 120 + 1000 * int(rep), false)
			for l in Contracts.listings:
				if str(l["tier"]) == "residential":
					n[str(l["job"])] += 1
		counts.append(n)
		shares.append(float(n["driveway"]) / maxf(n["path"] + n["driveway"], 1.0))
	runner.info("driveway share by reputation 0 / 30 / 50 / %d: %s (%s)" % [int(Catalog.balance.rep_tier_thresholds[1]), str(shares.map(func(x): return snappedf(x, 0.01))), str(counts)])
	runner.check(counts[0]["path"] > counts[0]["driveway"] and counts[2]["path"] > counts[2]["driveway"], "§10 at low reputation path jobs outnumber driveway jobs (%s, %s)" % [str(counts[0]), str(counts[2])])
	runner.check(absf(shares[0] - 0.25) < 0.07 and absf(shares[3] - 0.5) < 0.08 and shares[1] > shares[0] and shares[3] > shares[2], "§10 …and the driveway share grows with reputation: %.2f at 0 → %.2f at the Commercial threshold" % [shares[0], shares[3]])
	# The untouched world: no residential listing bigger than a shovel clears in a day.
	await _s10_game("fun", 6, 7.0)
	var too_big := []
	var dw := 0
	for d in range(60):
		Contracts.listings.clear()
		Contracts._generate_listings(d + 6, false)
		for l in Contracts.listings:
			if str(l["tier"]) == "residential":
				if float(l["now_volume"]) > Contracts.res_cap_m3():
					too_big.append("%s %.0f m³" % [l["address"], float(l["now_volume"])])
				if l["job"] == "driveway":
					dw += 1
	runner.check(too_big.is_empty() and dw == 0 and is_equal_approx(Contracts.res_cap_m3(), Catalog.balance.listing_res_max_m3), "§10 untouched driveways (a season's snow) aren't offered with a shovel; nothing over %.0f m³ %s" % [Contracts.res_cap_m3(), str(too_big)])


## The bidding day: what a listing shows; place, raise, lower, withdraw; the floor; ties go to you;
## the rivals bid at seeded times and answer an undercut once or twice, never under their floor,
## the same way every time; at 9:00 p.m. bidding closes, at 9:01 p.m. the lowest bid wins, with a
## notification for each of your bids won or lost (and back to 1×).
func test_s10_bidding_day() -> void:
	await _s10_game("fun", 1, 6.5)
	var day := Clock.day_index()
	var open_l: Array = Contracts.listings.filter(func(x): return str(x["tier"]) == "residential")
	runner.check(open_l.size() >= 2, "§10 the morning board has residential listings (%d of %d)" % [open_l.size(), Contracts.listings.size()])
	var l: Dictionary = open_l[0]
	var l2: Dictionary = open_l[1]
	runner.check(is_equal_approx(float(l["closes"]), Clock.at(day, Contracts.DUE_HOUR)) and Contracts.when_text_rel(float(l["closes"])) == "9 p.m. today", "§10 posted at 6 a.m.: closes at 9 p.m. today")
	# Posted 3 h before 9 p.m. or more: today; later: tomorrow.
	runner.check(is_equal_approx(Contracts.close_for(Clock.at(day, 18.0)), Clock.at(day, 21.0)) and is_equal_approx(Contracts.close_for(Clock.at(day, 18.5)), Clock.at(day + 1, 21.0)) and is_equal_approx(Contracts.close_for(Clock.at(day, 21.0)), Clock.at(day + 1, 21.0)),
		"§10 posted by 6 p.m.: closes at 9 p.m.; after: at 9 p.m. the next day")
	# The rivals' plan: seeded times through the day, at or above the floor.
	var fl := Contracts.bid_floor(l)
	var plan_ok := not (l["rivals"] as Array).is_empty()
	for rv in l["rivals"]:
		plan_ok = plan_ok and float(rv["at"]) > float(l["posted"]) and float(rv["at"]) < float(l["closes"]) and int(rv["open"]) >= fl and int(rv["bid"]) == 0
	runner.check(plan_ok and fl == int(ceil(float(l["budget"]) * Catalog.balance.bid_floor_frac - 1e-6)), "§10 %d rivals bid at seeded times through the day, never under the floor ($%d of $%d)" % [(l["rivals"] as Array).size(), fl, int(l["budget"])])
	# Place, raise, lower, withdraw; the floor.
	var lid := int(l["lid"])
	runner.check(not Contracts.place_bid(lid, fl - 1)["ok"] and Contracts.bids.is_empty(), "§10 a bid under the floor is refused")
	runner.check(Contracts.place_bid(lid, int(l["budget"]))["ok"] and Contracts.bids.size() == 1 and int(l["bid"]) == int(l["budget"]) and Contracts.bid_count(l) == 1, "§10 place a bid")
	runner.check(Contracts.place_bid(lid, int(l["budget"]) + 10)["ok"] and int(l["bid"]) == int(l["budget"]) + 10, "§10 raise it")
	runner.check(Contracts.place_bid(lid, fl + 2)["ok"] and int(l["bid"]) == fl + 2 and Contracts.bids[0]["amount"] == fl + 2, "§10 lower it")
	runner.check(Contracts.withdraw_bid(lid)["ok"] and int(l["bid"]) == 0 and Contracts.bids.is_empty() and Contracts.bid_status(l)["text"] == "", "§10 withdraw it")
	# Live status; ties go to you.
	Contracts.place_bid(lid, int(l["budget"]))
	Contracts._rival_bid(l, 0, int(l["budget"]), Clock.minutes)
	runner.check(Contracts.bid_status(l)["winning"] and Contracts.bid_status(l)["text"] == "Winning", "§10 a tie goes to you: \"Winning\"")
	Contracts._rival_bid(l, 0, int(l["budget"]) - 3, Clock.minutes)
	runner.check(not Contracts.bid_status(l)["winning"] and Contracts.bid_status(l)["text"] == "Outbid · lowest bid $%d" % (int(l["budget"]) - 3), "§10 \"%s\"" % Contracts.bid_status(l)["text"])
	# Replies: deterministic (the rivals' own stream), never under the floor, at most twice.
	var runs := []
	for k in range(2):
		await _s10_game("fun", 1, 6.5)
		Catalog.balance.rival_reply_chance = 1.0
		var lr: Dictionary = Contracts.listings.filter(func(x): return str(x["tier"]) == "residential")[0]
		Clock.advance(float(lr["closes"]) - 330.0 - Clock.minutes)
		var steps := []
		for t in range(8):
			var st := Contracts.bid_status(lr)
			Contracts.place_bid(int(lr["lid"]), maxi(int(st["lowest"]) - 1, Contracts.bid_floor(lr)) if int(st["lowest"]) > 0 else Contracts.bid_floor(lr) + 5)
			Clock.advance(30.0)
			steps.append(var_to_str(lr["rivals"]))
		var low := int(Contracts.bid_status(lr)["lowest"])
		var replied := 0
		for rv in lr["rivals"]:
			replied += int(rv["replies"])
		runs.append({"rivals": "\n".join(steps), "low": low, "floor": Contracts.bid_floor(lr), "replies": replied, "max": int(Catalog.balance.rival_replies_max) * (lr["rivals"] as Array).size()})
		Catalog.balance.rival_reply_chance = BalanceData.new().rival_reply_chance
	runner.check(runs[0]["rivals"] == runs[1]["rivals"], "§10 the rivals' replies are the same every time (seeded)")
	runner.check(runs[0]["low"] >= runs[0]["floor"] and runs[0]["replies"] >= 1 and runs[0]["replies"] <= runs[0]["max"], "§10 they answer an undercut (%d replies, at most %d) and never go under their floor (lowest $%d, floor $%d)" % [runs[0]["replies"], runs[0]["max"], runs[0]["low"], runs[0]["floor"]])
	# Closing at 9 p.m., the award at 9:01 p.m.: the lowest bid wins.
	await _s10_game("fun", 1, 6.5)
	open_l = Contracts.listings.filter(func(x): return str(x["tier"]) == "residential")
	l = open_l[0]
	l2 = open_l[1]
	day = Clock.day_index()
	Contracts.place_bid(int(l["lid"]), Contracts.bid_floor(l))           # nobody bids lower: wins
	Contracts.place_bid(int(l2["lid"]), int(l2["budget"]) * 3)           # over every rival: loses
	Clock.advance(Clock.at(day, 20.0 + 59.0 / 60.0) - Clock.minutes)
	runner.check(not l["closed"] and Contracts.place_bid(int(l["lid"]), Contracts.bid_floor(l) + 1)["ok"] and Contracts.place_bid(int(l["lid"]), Contracts.bid_floor(l))["ok"], "§10 at 8:59 p.m. bids can still change")
	Clock.speed = 10
	var n0 := Notify.history.size()
	var act0 := Contracts.active.size()
	Clock.advance(1.0)
	runner.check(l["closed"] and not Contracts.place_bid(int(l["lid"]), Contracts.bid_floor(l) + 1)["ok"] and Contracts.listing_by_id(int(l["lid"])).size() > 0 and Contracts.active.size() == act0,
		"§10 9:00 p.m.: bidding has closed (no award yet)")
	Clock.advance(1.0)
	var won := Contracts.active.filter(func(c): return c["target"] == l["target"] and c["status"] != "lost")
	var won_notes := _s10_notes_since(n0, "Bid won!")
	var lost_notes := _s10_notes_since(n0, "Bid lost:")
	runner.check(Contracts.listing_by_id(int(l["lid"])).is_empty() and won.size() == 1 and int(won[0]["pay"]) == Contracts.bid_floor(l) and is_equal_approx(float(won[0]["accepted"]), Clock.at(day, 21.0) + 1.0),
		"§10 9:01 p.m.: the lowest bid wins (%s, $%d)" % [l["address"], int(won[0]["pay"]) if not won.is_empty() else 0])
	runner.check(won_notes.size() == 1 and str(won_notes[0]["text"]).contains(Game.company_name) and lost_notes.size() == 1 and str(lost_notes[0]["text"]).contains(l2["address"]) and Contracts.bids.is_empty(),
		"§10 a notification for the bid won and the bid lost (\"%s\" / \"%s\")" % [won_notes[0]["text"] if not won_notes.is_empty() else "", lost_notes[0]["text"] if not lost_notes.is_empty() else ""])
	runner.check(Clock.speed == 1 and Clock.drop_reason == "bid", "§10 …and fast-forward back to 1× (%s)" % Clock.drop_reason)
	runner.check(is_equal_approx(float(won[0]["due"]), Clock.at(day + 1, Contracts.DUE_HOUR)), "§10 the job won is due by 9 p.m. the next day (%s)" % Contracts.due_text(won[0]))


## Due times (Decision 4; the 48-hour tests' rules, now due times): a job done at 8:59 p.m. is paid,
## one still open at 9:00 p.m. is missed — reputation lost, no pay, in the history, back on the board
## closing at the next 9 p.m.; the warnings 12 h and 3 h before; the storm adds a day once per job;
## recurring and city visits; payment exactly once per job or visit; and the due time everywhere it
## is shown (notifications, the HUD, the computer, the map).
func test_s10_due_times() -> void:
	await _s10_game("fun", 1, 10.0)
	var b: BalanceData = Catalog.balance
	var day := Clock.day_index()
	var a := _s10_job(0, "path")
	var m := _s10_job(1, "path")
	var due := Clock.at(day + 1, Contracts.DUE_HOUR)
	runner.check(is_equal_approx(float(a["due"]), due) and Contracts.due_text(a) == "9 p.m. %s" % Clock.weekday(day + 1, Game.year), "§10 a job won today is due %s" % Contracts.due_text(a))
	var n0 := Notify.history.size()
	Clock.speed = 10
	Clock.advance(due - b.contract_warn_hours * 60.0 + 1.0 - Clock.minutes)
	var w1 := _s10_notes_since(n0, a["address"] + " is due")
	runner.check(int(a["warned"]) == 1 and w1.size() == 1 and str(w1[0]["text"]).contains("due 9 p.m.") and Clock.speed == 1 and Clock.drop_reason == "contract", "§10 the 12-hour warning names the due time (\"%s\"), back to 1×" % (w1[0]["text"] if not w1.is_empty() else ""))
	Clock.advance(due - 60.0 - Clock.minutes)
	runner.check(int(a["warned"]) == 2 and _s10_notes_since(n0, "URGENT: " + a["address"]).size() == 1, "§10 …and the 3-hour one")
	# The due time where it's shown.
	var hud_alert := "⚠ %s: due %s — %d h left" % [a["address"], Contracts.due_text(a), 1]
	await _spawn_world()
	Clock.running = false
	var pl: Player = world.player
	var mid: Vector2 = (Boxes.get_box(Boxes.lot_box(Contracts.residential_lots()[0], "path"))["rects"][0] as Rect2).get_center()
	pl.teleport(Vector3(mid.x, Snow.surface_height(mid.x, mid.y) + 0.05, mid.y))
	await _frames(20)
	var hud: HUD = world.hud
	# §10b: the box line is one line, "Your contract · ‹place› — ‹box› N% · due ‹time›" (was a second line "Due …").
	runner.check(hud.alert_l.text.contains(hud_alert) and hud.contract_l.text.ends_with(" · due %s" % Contracts.due_text(a)) and not hud.contract_l.text.contains("\n"), "§10 the HUD: \"%s\" and the box line \"%s\"" % [hud.alert_l.text.split("\n")[0], hud.contract_l.text.replace("\n", " | ")])
	var comp := await _s7_open()
	comp._open_app(ComputerUI.app_index("contracts"))
	await _frames(2)
	runner.check(_s2_texts(comp.content).contains("Due %s  ·  1 h left" % Contracts.due_text(a)), "§10 the computer's Contracts: \"Due %s  ·  1 h left\"" % Contracts.due_text(a))
	world.close_modal()
	await _frames(2)
	var mp := MapUI.new()
	world.ui.add_child(mp)
	world.open_modal(mp, "map")
	await _frames(2)
	var tags: Array = mp.labels(Vector2(1920, 1080)).filter(func(x): return x["kind"] == "tag").map(func(x): return x["text"])
	runner.check(MapUI.due_tag(a) in tags and MapUI.due_tag(a) == "due " + Clock.weekday(day + 1, Game.year), "§10 the map: \"%s\" under the house number %s" % [MapUI.due_tag(a), str(tags)])
	world.close_modal()
	await _frames(2)
	# 8:59 p.m.: done and paid; 9:00 p.m.: the other one is missed.
	Clock.advance(due - 1.0 - Clock.minutes)
	var money0 := Game.money
	var rep0 := Game.reputation
	_s10_clear(a)
	runner.check(a["status"] == "completed" and Game.money == money0 + int(a["pay"]) and Game.reputation > rep0 and Contracts.job_history[-1]["result"] == "completed", "§10 done at 8:59 p.m.: paid $%d, reputation +%.2f, in the history" % [int(a["pay"]), Game.reputation - rep0])
	money0 = Game.money
	rep0 = Game.reputation
	n0 = Notify.history.size()
	Clock.advance(1.0)
	var relisted := Contracts.listings.filter(func(x): return x["target"] == m["target"] and x.get("relisted", false))
	runner.check(m["status"] == "lost" and Game.money == money0 and is_equal_approx(Game.reputation, rep0 - b.contract_lost_reputation) and Contracts.job_history[-1]["result"] == "missed" and _s10_notes_since(n0, "MISSED: " + m["address"]).size() == 1,
		"§10 still open at 9:00 p.m.: missed — no pay, %d reputation, in the history" % -int(b.contract_lost_reputation))
	runner.check(relisted.size() == 1 and is_equal_approx(float(relisted[0]["closes"]), Clock.at(day + 2, Contracts.DUE_HOUR)) and not (relisted[0]["rivals"] as Array).is_empty(), "§10 …back on the board, closing at the next 9 p.m. (%s)" % (Clock.format_time(float(relisted[0]["closes"])) if not relisted.is_empty() else "none"))
	# Payment exactly once: measuring again, an hour, new snow on the finished job.
	money0 = Game.money
	var hist0 := Contracts.job_history.size()
	Contracts._refresh(a)
	Contracts.on_hour(Clock.day_index(), Clock.hour())
	Boxes.measure_all(true)
	for id in Contracts.contract_boxes(a):
		for r in Boxes.get_box(id)["rects"]:
			Snow.add_layer_rect(r, 0.05)
	Boxes.measure_all(true)
	Contracts.on_hour(Clock.day_index(), Clock.hour())
	runner.check(Game.money == money0 and Contracts.job_history.size() == hist0 and a["status"] == "completed", "§10 paid exactly once: measuring again or new snow on a finished job changes nothing")
	await _unload()
	# The storm: heavy snow inside the window adds a day, once per job.
	await _s10_game("fun", 1, 10.0)
	day = Clock.day_index()
	var s := _s10_job(2, "path")
	var due_s := float(s["due"])
	n0 = Notify.history.size()
	Weather.force(Weather.C.HEAVY, 1.0, 1.5)
	Clock.advance(10.0)
	runner.check(is_equal_approx(float(s["due"]), due_s + Contracts.STORM_EXTENSION_MIN) and bool(s["ext"]) and _s10_notes_since(n0, "Storm: " + s["address"]).size() == 1, "§10 heavy snow inside the job's window: due a day later, with a notification (%s)" % Contracts.due_text(s))
	Weather.force(Weather.C.HEAVY, 2.0, 1.5)
	Clock.advance(60.0)
	runner.check(is_equal_approx(float(s["due"]), due_s + Contracts.STORM_EXTENSION_MIN), "§10 …once per job")
	Weather.force(Weather.C.CLEAR, 400.0)
	# A city sidewalk contract: its first visit due tomorrow; done; new snow → due by 9 p.m. the day
	# after the snow stops; a storm-reopened visit a day later; each visit paid once.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var lw := Contracts._add_walk_listing("B_w", Clock.day_index(), rng)
	var cw := Contracts.force_award(int(lw["lid"]))
	runner.check(cw["type"] == "municipal" and cw["status"] == "needs_service" and is_equal_approx(float(cw["due"]), Clock.at(Clock.day_index() + 1, Contracts.DUE_HOUR)), "§10 a city contract (%s): its first visit due %s" % [cw["address"], Contracts.due_text(cw)])
	money0 = Game.money
	_s10_clear(cw)
	runner.check(cw["status"] == "serviced" and Game.money == money0 + int(cw["pay"]) and Contracts.hours_left(cw) == INF, "§10 the visit done: paid, nothing due until new snow")
	Weather.force(Weather.C.MODERATE, 3.0, 2.5)
	Clock.advance(60.0)
	Contracts.on_hour(Clock.day_index(), Clock.hour())     # the hourly check finds the new snow
	runner.check(cw["status"] == "needs_service" and Contracts.due_pending(cw) and Contracts.due_text(cw) == "9 p.m. the day after the snow stops", "§10 new snow reopens it: \"%s\"" % Contracts.due_text(cw))
	var t_end := Clock.minutes
	Weather.force(Weather.C.CLEAR, 400.0)
	Clock.advance(5.0)
	runner.check(is_equal_approx(float(cw["due"]), Clock.at(Contracts.day_of(t_end - 0.001) + 1, Contracts.DUE_HOUR)) and not bool(cw["ext"]), "§10 …due by 9 p.m. the day after the snow stopped (%s)" % Contracts.due_text(cw))
	money0 = Game.money
	_s10_clear(cw)
	Boxes.measure_all(true)
	runner.check(Game.money == money0 + int(cw["pay"]) and int(cw["visits"]) == 2, "§10 the second visit paid once")
	Weather.force(Weather.C.HEAVY, 3.0, 2.0)
	Clock.advance(90.0)
	Contracts.on_hour(Clock.day_index(), Clock.hour())
	Clock.advance(1.0)
	t_end = Clock.minutes
	Weather.force(Weather.C.CLEAR, 400.0)
	Clock.advance(5.0)
	runner.check(cw["status"] == "needs_service" and bool(cw["ext"]) and is_equal_approx(float(cw["due"]), Clock.at(Contracts.day_of(t_end - 0.001) + 1, Contracts.DUE_HOUR) + Contracts.STORM_EXTENSION_MIN),
		"§10 a visit a storm reopened: a day later (%s)" % Contracts.due_text(cw))


## Old saves (before due times): an active one-time job is due by 9 p.m. on the first day at least
## 24 game hours after the load; a pending recurring visit follows the rule from the load; open
## listings close at the next 9 p.m. (the rivals bid until then); a pending bid is back on the board
## with your bid on it; a job above the player's tier is kept and runs.
func test_s10_old_saves() -> void:
	var path := "res://tests/fixtures/polish5/fun_1_contracts.json"
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var ok: bool = await _load_save_file(path)
	var now := Clock.minutes
	var one := Contracts.active.filter(func(c): return c["type"] == "one_time" and c["status"] == "active" and not c.get("tutorial", false))
	var rec := Contracts.active.filter(func(c): return c["type"] == "recurring" and c["status"] == "needs_service")
	var want_due := Contracts.next_9pm(now + 1440.0 - 0.001)
	runner.check(ok and one.size() == 1 and is_equal_approx(float(one[0]["due"]), want_due) and float(one[0]["due"]) >= now + 1440.0 - 0.01 and float(one[0]["due"]) < now + 2880.0,
		"§10 an old save's one-time job is due by 9 p.m. on the first day 24 h after the load (%s, loaded %s)" % [Clock.format_time(float(one[0]["due"])) if not one.is_empty() else "?", Clock.format_time(now)])
	runner.check(rec.size() == 1 and Contracts.due_pending(rec[0]), "§10 …its recurring visit waits for the snow rule from the load")
	Contracts.on_advance(0.5)
	var rd := float(rec[0]["due"])
	runner.check(is_equal_approx(rd, Clock.at(Clock.day_index() + 1, Contracts.DUE_HOUR)) or (Weather.is_snowing() and rd < 0.0), "§10 …due by 9 p.m. the day after the snow stops (%s)" % Contracts.due_text(rec[0]))
	var lst_ok := not Contracts.listings.is_empty()
	for l in Contracts.listings:
		lst_ok = lst_ok and is_equal_approx(float(l["closes"]), Contracts.next_9pm(now)) and not (l["rivals"] as Array).is_empty() and l.has("tier")
	runner.check(lst_ok and Contracts.listings.size() == (src["contracts"]["listings"] as Array).size(), "§10 …its open listings close at the next 9 p.m., the rivals bidding until then (%d)" % Contracts.listings.size())
	await _unload()
	# The 8:30 p.m. save: its listings close at 9 p.m. that evening.
	ok = await _load_save_file("res://tests/fixtures/polish5/survival_5_evening.json")
	runner.check(ok and Contracts.listings.all(func(l): return is_equal_approx(float(l["closes"]), Clock.at(Clock.day_index(), 21.0))), "§10 the 8:30 p.m. save: its listings close at 9 p.m. that evening")
	await _unload()
	# A pending bid (before live bidding, its listing off the board) and a job above the tier.
	var d := src.duplicate(true)
	var lst: Dictionary = (d["contracts"]["listings"] as Array).pop_back()
	d["contracts"]["bids"] = [{"listing": lst, "amount": int(lst["budget"]), "resolve_at": float(d["clock"]) + 60.0}]
	var store_c: Dictionary = (d["contracts"]["active"] as Array)[0].duplicate(true)
	store_c["id"] = 999
	store_c.erase("tutorial")
	store_c.erase("due")
	store_c["target"] = "area:store_lot"
	store_c["type"] = "one_time"
	store_c["status"] = "active"
	store_c["zones"] = [{"name": "Parking lot", "boxes": ["area_store_lot"], "rects": [], "done": false, "progress": 0.0}]
	(d["contracts"]["active"] as Array).append(store_c)
	var f := FileAccess.open(Saves.path_for("fun"), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Saves.path_for("fun") + ".bak"))
	ok = Saves.load_game("fun")
	var back := Contracts.listing_by_id(int(lst["lid"]))
	var above := Contracts.active.filter(func(c): return int(c["id"]) == 999)
	runner.check(ok and not back.is_empty() and int(back["bid"]) == int(lst["budget"]) and Contracts.bids.size() == 1 and is_equal_approx(float(back["closes"]), Contracts.next_9pm(Clock.minutes)),
		"§10 a pending bid from an old save: back on the board with the bid on it, closing at the next 9 p.m.")
	runner.check(above.size() == 1 and above[0]["status"] == "active" and Contracts.tier_index() == 0 and str(above[0]["tier"]) == "commercial" and float(above[0]["due"]) > Clock.minutes, "§10 a job above the player's tier is kept and runs (due %s)" % (Contracts.due_text(above[0]) if not above.is_empty() else "?"))
	Saves.delete_save("fun")


## Integrity: save → load mid-bidding and mid-job keeps your bids, the rivals' bids (and a reply on
## its way), the due times (a job, a visit waiting for the snow to stop) — and what happens next is the
## same with or without the reload: the award at 9:01 p.m., the payments.
func test_s10_save_mid_bidding_and_mid_job() -> void:
	await _s10_game("fun", 1, 12.0)
	Catalog.balance.rival_reply_chance = 1.0
	var l: Dictionary = Contracts.listings.filter(func(x): return str(x["tier"]) == "residential")[0]
	Clock.advance(float(l["closes"]) - 240.0 - Clock.minutes)
	Contracts.place_bid(int(l["lid"]), maxi(int(Contracts.bid_status(l)["lowest"]) - 2, Contracts.bid_floor(l)) if int(Contracts.bid_status(l)["lowest"]) > 0 else int(l["budget"]))
	var job := _s10_job(3, "path")
	var vis := _s10_job(4, "path", "recurring")
	_s10_clear(vis)
	Weather.force(Weather.C.MODERATE, 3.0, 2.5)
	Clock.advance(60.0)
	var pending := Contracts.due_pending(vis)
	var replying := (l["rivals"] as Array).any(func(rv): return float(rv["next"]) >= 0.0)
	var want := _s10_norm({"c": Contracts.serialize(), "clock": Clock.minutes})
	runner.check(Saves.save_game(), "§10 saved mid-bidding and mid-job")
	var after := []
	for k in range(2):
		if k == 1:
			Contracts.reset_for_new_game()
			runner.check(Saves.load_game("fun"), "§10 …loads")
			var got := _s10_norm({"c": Contracts.serialize(), "clock": Clock.minutes})
			runner.check(got == want, "§10 …with the bids, the rivals' bids%s and the due times (a job, %s) exactly as saved" % [" (a reply on its way)" if replying else "", "a visit waiting for the snow to stop" if pending else "a visit"])
			if got != want:
				runner.info("want %s\n got %s" % [want.left(3000), got.left(3000)])
		var n0 := Notify.history.size()
		var m0 := Game.money
		Weather.force(Weather.C.CLEAR, 400.0)
		Clock.advance(float(l["closes"]) + 2.0 - Clock.minutes)
		_s10_clear(Contracts.active.filter(func(c): return int(c["id"]) == int(job["id"]))[0])
		Clock.advance(30.0)
		after.append(_s10_norm({"c": Contracts.serialize(), "money": Game.money - m0, "notes": Notify.history.slice(n0).map(func(n): return n["text"])}))
	runner.check(after[0] == after[1], "§10 …and what follows (the award at 9:01 p.m., a job paid, the visit's due time) is the same with or without the reload")
	Catalog.balance.rival_reply_chance = BalanceData.new().rival_reply_chance
	Saves.delete_save("fun")


## The board (functional, §7's layout): every listing with its address, kind, boxes and size, the
## suggested price, when bidding closes, the number of bids and your status; locked ones show "Needs
## reputation N"; place / raise / lower / withdraw from it; the status updates while it's open; an
## "Outbid" notification only with the board off screen, at most once per listing per game hour;
## typing a bid fires no game action.
func test_s10_board_live() -> void:
	await _s9_world("fun", 10.0)
	Clock.running = false
	Game.company_name = "Live Bid Co."
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var la := Contracts._add_area_listing(Layout.big_areas[0], Clock.day_index(), rng)
	var comp := await _s7_open()
	comp._open_app(ComputerUI.app_index("board"))
	await _frames(2)
	var l: Dictionary = Contracts.listings.filter(func(x): return str(x["tier"]) == "residential")[0]
	var card: Node = _s10_card(comp, int(l["lid"]))
	var txt := _s2_texts(card) if card else ""
	runner.check(card != null and txt.contains(l["address"]) and txt.contains("one-time" if l["type"] == "one_time" else "all winter") and txt.contains("Suggested " + UIKit.money(l["budget"]))
		and txt.contains("closes 9 p.m. today") and txt.contains("0 bids") and txt.contains("No bid yet") and txt.contains("m²") and txt.contains("m³"), "§10 a listing shows its address, kind, boxes and size, the suggested price, the close, the bids, your status:\n%s" % txt)
	var lcard: Node = _s10_card(comp, int(la["lid"]))
	runner.check(lcard != null and _s2_texts(lcard).contains("Needs reputation %d" % int(Contracts.tier_threshold(1))) and lcard.find_children("*", "LineEdit", true, false).is_empty(), "§10 a parking lot above your tier: \"Needs reputation %d\", no bid controls" % int(Contracts.tier_threshold(1)))
	# Place from the board (typed: Enter), then raise with the slider, then withdraw.
	var e: LineEdit = comp.bid_edits[int(l["lid"])]
	e.grab_focus()
	await _frames(1)
	var speed0 := Clock.speed
	var sel0 := Game.selected
	for act in ["fast_forward", "drop", "slot_2"]:
		Input.parse_input_event(_s7_event(act, true))
		await _frames(1)
		Input.parse_input_event(_s7_event(act, false))
		await _frames(1)
	runner.check(Game.typing() and Clock.speed == speed0 and Game.selected == sel0, "§10 typing in the bid field fires no game action (T, G, 2)")
	e.text = str(int(l["budget"]))
	e.text_changed.emit(e.text)
	e.text_submitted.emit(e.text)
	await _frames(3)
	runner.check(int(l["bid"]) == int(l["budget"]) and not Game.typing(), "§10 a typed bid placed with Enter ($%d)" % int(l["bid"]))
	card = _s10_card(comp, int(l["lid"]))
	runner.check(card != null and _s2_texts(card).contains("Winning") and _s2_texts(card).contains("Change bid") and _s2_texts(card).contains("Withdraw") and _s2_texts(card).contains("1 bid"), "§10 the card: \"Winning\", Change bid, Withdraw, 1 bid")
	# A rival undercuts while the board is open: the status updates, no notification.
	var n0 := Notify.history.size()
	Contracts._rival_bid(l, 0, int(l["budget"]) - 4, Clock.minutes)
	await _frames(3)
	card = _s10_card(comp, int(l["lid"]))
	runner.check(card != null and _s2_texts(card).contains("Outbid · lowest bid $%d" % (int(l["budget"]) - 4)) and _s10_notes_since(n0, "Outbid").is_empty(), "§10 the open board updates: \"Outbid · lowest bid $%d\", no notification" % (int(l["budget"]) - 4))
	var sl: HSlider = card.find_children("*", "HSlider", true, false)[0]
	sl.value = int(l["budget"]) - 5
	await _s7_press(card, "Change bid")
	runner.check(int(l["bid"]) == int(l["budget"]) - 5 and Contracts.bid_status(l)["winning"], "§10 lower it with the slider: winning again ($%d)" % int(l["bid"]))
	card = _s10_card(comp, int(l["lid"]))
	await _s7_press(card, "Withdraw")
	runner.check(int(l["bid"]) == 0, "§10 withdraw from the board")
	await _s7_press(_s10_card(comp, int(l["lid"])), "Place bid")
	world.close_modal()
	await _frames(2)
	# The board closed: "Outbid on …", at most once per listing per game hour.
	for rv in l["rivals"]:
		rv["bid"] = 0
	var s0 := int(l["budget"])
	Contracts.place_bid(int(l["lid"]), s0)
	n0 = Notify.history.size()
	Contracts._rival_bid(l, 0, s0 - 1, Clock.minutes)
	Contracts.place_bid(int(l["lid"]), s0 - 2)
	Contracts._rival_bid(l, 0, s0 - 3, Clock.minutes + 20.0)
	var o1 := _s10_notes_since(n0, "Outbid on " + l["address"]).size()
	Contracts.place_bid(int(l["lid"]), s0 - 4)
	Contracts._rival_bid(l, 0, s0 - 5, Clock.minutes + 61.0)
	var o2 := _s10_notes_since(n0, "Outbid on " + l["address"]).size()
	runner.check(o1 == 1 and o2 == 2, "§10 with the board closed: \"Outbid on %s\", at most once per listing per game hour (%d, then %d)" % [l["address"], o1, o2])
	await _unload()


# =============================================================================
# §10 Contracts — §10b: no flags (the jobs' green outlines), the map, the HUD box line; the board
# updated in place, and street sections need a plow or a blower vehicle
# =============================================================================

## A colour that reads green / blue (the outlines' money green / the light blue).
static func _s10b_green(c: Color) -> bool:
	return c.g > c.r * 2.0 and c.g > c.b * 1.6


static func _s10b_blue(c: Color) -> bool:
	return c.b >= c.g and c.b > c.r * 1.3


## Snow on every box of a listing (so the job has something to clear), then the job won outright.
func _s10b_win(l: Dictionary, depth := 0.2) -> Dictionary:
	for z in l["zones"]:
		for id in z["boxes"]:
			var b := Boxes.get_box(id)
			for r in b["rects"]:
				Snow.add_layer_rect(r, depth)
			Boxes.measure(b, true)
	l["type"] = "one_time" if l["type"] == "recurring" else l["type"]
	return Contracts.force_award(int(l["lid"]))


func _s10b_lot_listing(number: int, street: String, kind: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = number * 7 + kind.length()
	return Contracts._add_lot_listing(Layout.lot_by_address(number, street), Clock.day_index(), rng, kind)


func _s10b_stand(p: Vector2) -> void:
	world.player.teleport(Vector3(p.x, Snow.surface_height(p.x, p.y) + 0.05, p.y))


## A box's middle (its first rect's centre).
static func _s10b_mid(id: String) -> Vector2:
	return (Boxes.get_box(id)["rects"][0] as Rect2).get_center()


## No stakes or flags for any contract: every incomplete box of an active job near the player has the
## persistent quest-mode outline in money green (laid a few per scan, re-draped at a low rate, streets
## drawn within 30 m), far ones none; the work outline is green on a job's box (the persistent one gives
## way, so it isn't drawn twice) and blue on any other; Gerry's trail stays blue; at night the green is
## dimmed and still green; a finished box loses its outline and flashes.
func test_s10b_no_flags_green_outlines() -> void:
	await _unload()
	Game.force_input = true
	Game.new_game("fun", 2024)
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.LETTER_READ)
	Contracts.create_tutorial_contract(55)
	Game.set_stage(Game.Stage.NEIGHBOR_TALKED)   # Gerry's trail on: its blue quest outline
	Clock.reset(Clock.at(1, 12.0))
	await _spawn_world()
	Clock.running = false
	Weather.force(Weather.C.CLEAR, 48.0)
	var zm: ZoneMarkers = world.zone_markers
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var day := Clock.day_index()
	# Jobs of every kind around the player's house, and a parking lot far away.
	var jd := _s10b_win(_s10b_lot_listing(20, Layout.STREET_MAPLE, "driveway"))
	var jp := _s10b_win(_s10b_lot_listing(12, Layout.STREET_MAPLE, "path"))
	var jw := _s10b_win(Contracts._add_walk_listing("B_w", day, rng))
	var jr := _s10b_win(Contracts._add_municipal_listing(Layout.road_segments[0], day, rng))
	var jf := _s10b_win(Contracts._add_area_listing(Layout.big_areas[2], day, rng))
	var home := Layout.player_lot
	var stand := Layout.lot_to_world(home, 0.0, -6.0)    # in the street in front of the house
	_s10b_stand(stand)
	zm._t = 0.0
	await _frames(1)
	runner.check(zm.outlines.size() == ZoneMarkers.LAY_PER_SCAN, "§10b the outlines are laid a few per scan (%d after one)" % zm.outlines.size())
	await _frames(240)
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	# No stake or flag node for any contract.
	var stray := []
	for n in zm.get_children():
		if not (n is BoxOutline) and n != zm._flash:
			stray.append(n.name)
	runner.check(zm._stakes.is_empty() and stray.is_empty() and not ("_stake_mesh" in zm), "§10b no stake or flag node for any contract (stray nodes: %s)" % str(stray))
	# Every incomplete box of a job near the player: the persistent outline, money green; far: none.
	var near_ids := []
	var far_ids := []
	for c in [jd, jp, jw, jr, jf]:
		for id in Contracts.contract_boxes(c):
			if Boxes.is_complete(id):
				continue
			if ZoneMarkers._box_dist(Boxes.get_box(id), pp) <= ZoneMarkers.LAY_RADIUS:
				near_ids.append(id)
			else:
				far_ids.append(id)
	var bad := []
	for id in near_ids:
		var ol: BoxOutline = zm.outlines.get(id)
		if ol == null or not ol.visible or not ol.job or ol.alpha < 0.9 or not _s10b_green(ol.line_color()) or ol.box_id != id:
			bad.append(id)
	runner.check(near_ids.size() >= 6 and bad.is_empty() and far_ids.all(func(id): return not zm.outlines.has(id)) and zm.outlines.size() == near_ids.size(),
		"§10b every incomplete job box near the player is outlined in money green (%d: %s; wrong %s), the far ones aren't (%s)" % [near_ids.size(), str(near_ids), str(bad), str(far_ids)])
	var drv_id: String = Contracts.contract_boxes(jd)[0]
	var road_id: String = Contracts.contract_boxes(jr)[0]
	# Gerry's trail: the blue quest outline, unchanged.
	var qo: BoxOutline = world.quest_outline
	runner.check(qo.visible and qo.box_id == "gerry_trail" and not qo.job and _s10b_blue(qo.line_color()) and not zm.outlines.has("gerry_trail"), "§10b Gerry's trail keeps its blue outline (%s)" % str(qo.line_color()))
	# Streets are drawn within 30 m of the player, as before.
	var road_ol: BoxOutline = zm.outlines.get(road_id)
	var aabb: AABB = road_ol.mesh.get_aabb() if road_ol else AABB()
	runner.check(road_ol != null and aabb.size.x > 10.0 and aabb.size.x <= BoxOutline.DRAW_RADIUS * 2.0 + 1.0 and (Boxes.get_box(road_id)["rects"][0] as Rect2).size.x > aabb.size.x,
		"§10b the street's outline is drawn within %d m of the player (%.1f m of its %.0f m)" % [int(BoxOutline.DRAW_RADIUS), aabb.size.x, (Boxes.get_box(road_id)["rects"][0] as Rect2).size.x])
	# Re-draped at a low rate: often only at the box the player is at (a street or a parking lot as
	# often as the work outline re-drapes one); elsewhere at most every REDRAPE_FAR_S, once its snow changed.
	var rates_ok := true
	for id in zm.outlines.keys():
		var bx := Boxes.get_box(id)
		var near := ZoneMarkers._box_dist(bx, pp) <= ZoneMarkers.NEAR_DIST
		var want := (ZoneMarkers.REDRAPE_NEAR_BIG_S if bool(bx["big"]) else ZoneMarkers.REDRAPE_NEAR_S) if near else ZoneMarkers.REDRAPE_FAR_S
		var ol: BoxOutline = zm.outlines[id]
		rates_ok = rates_ok and is_equal_approx(ol.rebuild_s, want) and is_equal_approx(ol.redrape_depth, 0.0 if near else ZoneMarkers.REDRAPE_DEPTH)
	runner.check(rates_ok and is_equal_approx((zm.outlines[road_id] as BoxOutline).rebuild_s, ZoneMarkers.REDRAPE_NEAR_BIG_S) and is_equal_approx((zm.outlines[drv_id] as BoxOutline).rebuild_s, ZoneMarkers.REDRAPE_FAR_S)
		and zm.outlines.keys().any(func(id): return is_equal_approx((zm.outlines[id] as BoxOutline).rebuild_s, ZoneMarkers.REDRAPE_NEAR_S)),
		"§10b re-draped every %.2f s at the box the player is at (%.1f s a street), at most every %.1f s elsewhere and only once its snow changed" % [ZoneMarkers.REDRAPE_NEAR_S, ZoneMarkers.REDRAPE_NEAR_BIG_S, ZoneMarkers.REDRAPE_FAR_S])
	# Working another box (the player's own driveway): the work outline is blue.
	var own := Boxes.get_box(Boxes.lot_box(home, "driveway"))
	for r in own["rects"]:
		Snow.add_layer_rect(r, 0.2)
	Boxes.measure(own, true)
	var bo: BoxOutline = world.box_outline
	_s10b_stand(_s10b_mid(own["id"]))
	for i in range(20):
		Boxes.note_work(_s10b_mid(own["id"]))
		await _frames(1)
	runner.check(bo.visible and bo.box_id == own["id"] and not bo.job and _s10b_blue(bo.line_color()), "§10b the work outline on any other box stays blue (%s)" % str(bo.line_color()))
	# Working a job's box: the work outline is green, and the persistent one gives way to it.
	_s10b_stand(_s10b_mid(drv_id))
	for i in range(30):
		Boxes.note_work(_s10b_mid(drv_id))
		await _frames(1)
	var pol: BoxOutline = zm.outlines.get(drv_id)
	runner.check(bo.visible and bo.box_id == drv_id and bo.job and bo.alpha > 0.95 and _s10b_green(bo.line_color()) and pol != null and pol.alpha < 0.05,
		"§10b working a job's box: the work outline is money green (%s), the persistent one gives way (alpha %.2f)" % [str(bo.line_color()), pol.alpha if pol else -1.0])
	await _frames(int((BoxOutline.HOLD_S + BoxOutline.FADE_S + 0.8) * 60.0))
	runner.check(not bo.visible and pol.visible and pol.alpha > 0.95 and _s10b_green(pol.line_color()), "§10b …when the work stops the persistent green outline is back (alpha %.2f)" % pol.alpha)
	# At night: dimmed, and still clearly green on the snow.
	var day_col := pol.line_color()
	Clock.reset(Clock.at(1, 23.0))
	await _frames(10)
	var night_col := pol.line_color()
	runner.check(world.day_night.night > 0.9 and _s10b_green(night_col) and night_col.g < day_col.g and night_col.a >= 0.8 and _s10b_blue(qo.line_color()),
		"§10b at night the green is dimmed (%s → %s) and still green; the trail still blue" % [str(day_col), str(night_col)])
	# A finished box: its outline goes, the completion flash plays.
	for r in Boxes.get_box(drv_id)["rects"]:
		Snow.set_rect(r, 0.0)
	Boxes.measure(Boxes.get_box(drv_id), true)
	await _frames(2)
	var gone_now := not is_instance_valid(pol) or not pol.visible
	await _frames(40)
	runner.check(jd["status"] == "completed" and gone_now and not zm.outlines.has(drv_id) and zm._flash.visible, "§10b a finished box loses its outline at once (and the flash plays)")
	await _unload()


## The HUD box line: in a box of one of your jobs, one line — "Your contract · ‹address› — ‹box› N% · due
## ‹time›"; in any other box, and on Gerry's trail, as before.
func test_s10b_hud_box_line() -> void:
	await _s3_world()
	Weather.force(Weather.C.CLEAR, 48.0)
	var hud: HUD = world.hud
	var day := Clock.day_index()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var jd := _s10b_win(_s10b_lot_listing(20, Layout.STREET_MAPLE, "driveway"))
	var drv := Boxes.get_box(Contracts.contract_boxes(jd)[0])
	_s10b_stand(_s10b_mid(drv["id"]))
	await _frames(30)
	var want := "Your contract · %s — %s %d%% · due %s" % [drv["place"], drv["name"], int(floor(float(drv["progress"]) * 100.0)), Contracts.due_text(jd)]
	var t := hud.contract_l.text
	runner.check(hud.contract_panel.visible and t == want and t.begins_with("Your contract · 20 Maple Street — Driveway ") and t.ends_with(" · due 9 p.m. %s" % Clock.weekday(day + 1, Game.year)),
		"§10b in a box of your job: \"%s\"" % t)
	runner.check(hud.contract_l.get_line_count() == 1 and is_equal_approx(hud.contract_panel.offset_left, -hud.contract_panel.offset_right) and hud.contract_panel.size.x <= HUD.BOX_LINE_MAX_W + 0.5,
		"§10b …on one line, the panel centred (%.0f px wide)" % hud.contract_panel.size.x)
	# Any other box: as before.
	var own := Boxes.get_box(Boxes.lot_box(Layout.player_lot, "driveway"))
	_s10b_stand(_s10b_mid(own["id"]))
	await _frames(30)
	t = hud.contract_l.text
	var amount := "clear ✓" if own["complete"] else "%d%%" % int(floor(float(own["progress"]) * 100.0))
	runner.check(t == "%s — %s   %s" % [own["place"], own["name"], amount] and not t.contains("contract"), "§10b in any other box, as before: \"%s\"" % t)
	# The longest place, a parking lot: still one line, centred.
	var ja := _s10b_win(Contracts._add_area_listing(Layout.big_areas[2], day, rng))
	var lotb := Boxes.get_box(Contracts.contract_boxes(ja)[0])
	_s10b_stand(_s10b_mid(lotb["id"]))
	await _frames(30)
	t = hud.contract_l.text
	runner.check(t.begins_with("Your contract · %s — Parking lot " % Layout.big_areas[2]["place"]) and t.contains(" · due ") and hud.contract_l.get_line_count() == 1 and is_equal_approx(hud.contract_panel.offset_left, -hud.contract_panel.offset_right),
		"§10b a parking lot's line, one line, centred: \"%s\"" % t)
	# A visit waiting for its snowfall to stop; a clear box of a client waiting for snow; Gerry's trail.
	var jv := _s10b_win(_s10b_lot_listing(24, Layout.STREET_MAPLE, "path"))
	jv["type"] = "recurring"
	jv["status"] = "needs_service"
	jv["due"] = -1.0
	var pb := Boxes.get_box(Contracts.contract_boxes(jv)[0])
	runner.check(HUD.box_line(pb, jv).ends_with(" · due 9 p.m. the day after the snow stops"), "§10b a visit waiting for the snow to stop: \"%s\"" % HUD.box_line(pb, jv))
	jv["status"] = "serviced"
	var done_b := pb.duplicate()
	done_b["complete"] = true
	runner.check(HUD.box_line(done_b, jv) == "Your contract · %s — %s clear ✓" % [pb["place"], pb["name"]], "§10b a client's clear box: \"%s\"" % HUD.box_line(done_b, jv))
	var tut := Contracts.create_tutorial_contract(55)
	var tb := Boxes.get_box("gerry_trail")
	runner.check(HUD.box_line(tb, tut) == "Contract · %s — %s   %d%%" % [tb["place"], tb["name"], int(floor(float(tb["progress"]) * 100.0))], "§10b Gerry's trail as before: \"%s\"" % HUD.box_line(tb, tut))
	await _unload()


## The map: your jobs' boxes in the outlines' money green, a lot's number in green with the day it's
## due, and a parking lot's, a street's and a sidewalk section's address in green on their boxes — no
## label over another, at three screen shapes.
func test_s10b_map_jobs() -> void:
	await _s3_world()
	var day := Clock.day_index()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var jobs := [_s10b_win(_s10b_lot_listing(20, Layout.STREET_MAPLE, "driveway")), _s10b_win(_s10b_lot_listing(27, Layout.STREET_BIRCH, "path")),
		_s10b_win(Contracts._add_area_listing(Layout.big_areas[1], day, rng)), _s10b_win(Contracts._add_municipal_listing(Layout.road_segments[0], day, rng)),
		_s10b_win(Contracts._add_municipal_listing(Layout.road_segments[5], day, rng)), _s10b_win(Contracts._add_walk_listing("C_e", day, rng))]
	var m := MapUI.new()
	world.ui.add_child(m)
	world.open_modal(m, "map")
	await _frames(2)
	for vs in [Vector2(1920, 1080), Vector2(1920, 1440), Vector2(2520, 1080)]:
		var ls: Array = m.labels(vs)
		var probs := []
		for c in jobs:
			var t := str(c["target"])
			if t.begins_with("lot:"):
				var nl := ls.filter(func(l): return l["kind"] == "number" and "lot:" + str(l["key"]) == t)
				var tl := ls.filter(func(l): return l["kind"] == "tag" and "lot:" + str(l["key"]) == t)
				if nl.size() != 1 or nl[0]["color"] != BoxOutline.JOB_COLOR or tl.size() != 1 or tl[0]["text"] != MapUI.due_tag(c):
					probs.append("%s: number / due" % c["address"])
				continue
			var jl := ls.filter(func(l): return l["kind"] == "job" and l["key"] == t)
			if jl.size() != 1:
				probs.append("%s: %d labels" % [c["address"], jl.size()])
				continue
			var span := Rect2()
			var first := true
			for id in Contracts.contract_boxes(c):
				for r in Boxes.get_box(id)["rects"]:
					span = r if first else span.merge(r)
					first = false
			var sr := Rect2(m._to_px(span.position), span.size * m.scale_px)
			var lr: Rect2 = jl[0]["rect"]
			var want_txt: String = MapUI.job_address(c) + "  ·  " + MapUI.due_tag(c)
			if jl[0]["text"] != want_txt or jl[0]["color"] != BoxOutline.JOB_COLOR or int(jl[0]["size"]) < 12 or not sr.grow(minf(lr.size.x, lr.size.y) * 2.5).intersects(lr):
				probs.append("%s: \"%s\" at %s (boxes %s)" % [c["address"], jl[0]["text"], str(lr), str(sr)])
		var over := []
		for i in range(ls.size()):
			for j in range(i + 1, ls.size()):
				if (ls[i]["rect"] as Rect2).intersects(ls[j]["rect"]):
					over.append("%s / %s" % [ls[i]["text"], ls[j]["text"]])
		runner.check(probs.is_empty() and over.is_empty(), "§10b the map at %dx%d: every job's address in green by its boxes (%d labels) %s, none overlapping %s" % [vs.x, vs.y, ls.size(), str(probs), str(over)])
	var j0b := Boxes.get_box(Contracts.contract_boxes(jobs[0])[0])
	var look0: Array = MapUI.job_box_look(j0b)
	var cb := j0b.duplicate()
	cb["complete"] = true
	var look1: Array = MapUI.job_box_look(cb)
	var big_b := Boxes.get_box(Contracts.contract_boxes(jobs[2])[0])
	var look2: Array = MapUI.job_box_look(big_b)
	runner.check(not j0b["complete"] and Color(look0[0], 1.0) == BoxOutline.JOB_COLOR and look0[0].a >= 0.85 and look1[1] == BoxOutline.JOB_COLOR
		and not big_b["complete"] and Color(look2[0], 1.0) == BoxOutline.JOB_COLOR and look2[1] == BoxOutline.JOB_COLOR,
		"§10b a job's box to clear is filled with the outlines' green (a parking lot or a street lighter, with a green edge); once clear, light green with a green edge")
	world.close_modal()
	await _unload()


## Street sections need a plow or a blower vehicle as well as the City tier (the old requirement, kept for
## streets only); sidewalk sections need the reputation only. Shown on the board as a lock line with no
## bid controls; place_bid refuses it.
func test_s10b_street_needs_a_vehicle() -> void:
	await _s3_world()
	Game.company_name = "Street Co."
	var day := Clock.day_index()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var th: PackedFloat32Array = Catalog.balance.rep_tier_thresholds
	Contracts.adjust_reputation(th[2] - Game.reputation)
	var lr := Contracts._add_municipal_listing(Layout.road_segments[1], day, rng)
	var lw := Contracts._add_walk_listing("D_w", day, rng)
	var r1 := Contracts.place_bid(int(lr["lid"]), int(lr["budget"]))
	runner.check(Contracts.tier_index() == 2 and Contracts.equipment_capability() < 3 and Contracts.listing_locked(lr) and Contracts.listing_lock_text(lr) == "Needs a plow or a blower vehicle"
		and not r1["ok"] and r1["msg"] == "Needs a plow or a blower vehicle." and int(lr["bid"]) == 0, "§10b City tier, hand tools: a street section is locked, no bid (\"%s\")" % r1["msg"])
	runner.check(not Contracts.listing_locked(lw) and Contracts.place_bid(int(lw["lid"]), int(lw["budget"]))["ok"], "§10b …a sidewalk section needs the reputation only")
	var comp := await _s7_open()
	comp._open_app(ComputerUI.app_index("board"))
	await _frames(2)
	var card: Node = _s10_card(comp, int(lr["lid"]))
	var txt := _s2_texts(card) if card else ""
	runner.check(card != null and txt.contains("Needs a plow or a blower vehicle") and card.find_children("*", "LineEdit", true, false).is_empty() and not txt.contains("Place bid"),
		"§10b the board: the lock line, no bid controls:\n%s" % txt)
	# A plow (or a blower) vehicle unlocks it — at the City tier.
	var ve := {"uid": Game.uid(), "id": "plow_truck", "pos": Vector3(20, 0, 84), "yaw": 0.0, "snow": 0.0}
	Game.vehicles.append(ve)
	world.spawn_vehicle_node(ve)
	comp._rebuild(false)
	await _frames(2)
	card = _s10_card(comp, int(lr["lid"]))
	runner.check(Contracts.equipment_capability() == 3 and not Contracts.listing_locked(lr) and card != null and not card.find_children("*", "LineEdit", true, false).is_empty() and Contracts.place_bid(int(lr["lid"]), int(lr["budget"]))["ok"],
		"§10b with a plow vehicle: open, bid placed")
	world.close_modal()
	await _frames(2)
	Contracts.adjust_reputation(th[1] + 1.0 - Game.reputation)
	runner.check(Contracts.listing_lock_text(lr) == "Needs reputation %d" % int(th[2]) and not Contracts.place_bid(int(lr["lid"]), int(lr["budget"]) - 1)["ok"], "§10b …and below City it needs the reputation (\"%s\")" % Contracts.listing_lock_text(lr))
	await _unload()


## The board updates the listings that change in place: placing, changing and withdrawing a bid and a
## rival's bid don't rebuild the board (§10a rebuilt all its cards on every bid: 20–49 ms frames).
func test_s10b_board_updates_in_place() -> void:
	await _s3_world()
	Game.company_name = "In Place Co."
	Clock.running = false
	var comp := await _s7_open()
	comp._open_app(ComputerUI.app_index("board"))
	await _frames(2)
	var open_l: Array = Contracts.listings.filter(func(x): return not Contracts.listing_locked(x) and not bool(x.get("closed", false)))
	runner.check(open_l.size() >= 2, "§10b the board has listings to bid on (%d)" % open_l.size())
	var l: Dictionary = open_l[0]
	var lid := int(l["lid"])
	for rv in l["rivals"]:
		rv["bid"] = 0
	var cards := {}
	for x in Contracts.listings:
		cards[int(x["lid"])] = _s10_card(comp, int(x["lid"]))
	var at := (cards[lid] as Node).get_index()
	await _s7_press(cards[lid], "Place bid")
	var same := true
	for k in cards.keys():
		if k != lid and _s10_card(comp, k) != cards[k]:
			same = false
	var c1: Node = _s10_card(comp, lid)
	runner.check(int(l["bid"]) > 0 and same and c1 != null and c1.get_index() == at and _s2_texts(c1).contains("Winning") and _s2_texts(c1).contains("Withdraw"),
		"§10b placing a bid rebuilds only its card, in its place; every other card untouched")
	var n_children := comp.content.get_child_count()
	Contracts._rival_bid(l, 0, int(l["bid"]) - 3, Clock.minutes)
	await _frames(3)
	var c2: Node = _s10_card(comp, lid)
	var nb := Contracts.bid_count(l)
	var low := int(Contracts.bid_status(l)["lowest"])
	runner.check(c2 == c1 and low == int(l["bid"]) - 3 and _s2_texts(c2).contains("Outbid · lowest bid $%d" % low) and _s2_texts(c2).contains("%d bids" % nb) and comp.content.get_child_count() == n_children,
		"§10b a rival's bid updates the card in place: \"Outbid · lowest bid $%d\", %d bids" % [low, nb])
	var sl: HSlider = c2.find_children("*", "HSlider", true, false)[0]
	sl.value = int(l["bid"]) - 5
	await _s7_press(c2, "Change bid")
	runner.check(_s10_card(comp, lid) == c1 and _s2_texts(c1).contains("Winning") and int(l["bid"]) == int(sl.value), "§10b changing the bid: the same card, \"Winning\"")
	await _frames(int(2.5 * 60.0))
	same = true
	for k in cards.keys():
		if k != lid and _s10_card(comp, k) != cards[k]:
			same = false
	runner.check(same and _s10_card(comp, lid) == c1, "§10b the live refresh rebuilds nothing")
	await _s7_press(c1, "Withdraw")
	var c3: Node = _s10_card(comp, lid)
	runner.check(int(l["bid"]) == 0 and c3 != null and c3 != c1 and c3.get_index() == at and _s2_texts(c3).contains("Place bid"), "§10b withdrawing: its card rebuilt in its place")
	# A new listing: the board is rebuilt with it.
	var nl := _s10b_lot_listing(31, Layout.STREET_BIRCH, "path")
	Contracts.changed.emit()
	await _frames(3)
	runner.check(_s10_card(comp, int(nl["lid"])) != null, "§10b a new listing: the board is rebuilt with it")
	world.close_modal()
	await _unload()


# =============================================================================
# §11 City crews on Mondays and Fridays
# =============================================================================

## The street after a batch grader pass over the same snow — a new game (seed 2024), 20 cm more
## snow everywhere, the whole route at once at 7:30 a.m. on Dec 1 — measured on the polish-5
## baseline build (15be65a) and on the build before §11 (659b671), identical on both: SHA-256 of
## every road cell's depth and loose depth (float32, in cell order) before and after the pass, and
## of the whole map (all depths, then all loose depths) after it.
const S11_ROAD_BEFORE := "fce7278c2556d44c885181386ac51cdc167c9539593a9210435205067f12e627"
const S11_ROAD_AFTER := "88523f3352ab1a5db822fc0c40a1f74873ef2c271e52b3bdca54c0173f49b90c"
const S11_MAP_AFTER := "ca34adc4b4242fa2ef5563a3e18ef84a8ba33a99c0f86e13981cafd9312a3c55"


## A new game without the world (the city's passes run as batches), seed `sd`, winter `year`.
func _s11_fresh(sd := 2024, year := 1) -> void:
	await _unload()
	Game.world = null
	Game.player = null
	Clock.running = false
	Clock.speed = 1
	Municipal.world_handles_passes = false
	Game.new_game("fun", sd)
	if year > 1:
		Game.start_winter(year)
	Survival.in_player_house = true


func _s11_road() -> String:
	var d := PackedFloat32Array()
	for i in range(Snow.W * Snow.H):
		if Snow.surf[i] == Snow.S_ROAD:
			d.append(Snow.depth[i])
			d.append(Snow.loose[i])
	return _s9_sha(d.to_byte_array())


func _s11_map() -> String:
	return _s9_sha(Snow.depth.to_byte_array() + Snow.loose.to_byte_array())


## Every snow cell summed (m³), after bringing the snowfall up to date.
func _s11_volume() -> float:
	Snow.sync_all()
	var v := 0.0
	for i in range(Snow.W * Snow.H):
		v += Snow.depth[i]
	return v * Snow.CELL_AREA


## Zeller's congruence (Gregorian calendar), independent of Clock: 0 = Monday … 6 = Sunday.
static func _s11_zeller(y: int, m: int, d: int) -> int:
	if m < 3:
		m += 12
		y -= 1
	var k := y % 100
	@warning_ignore("integer_division")
	var j := y / 100
	@warning_ignore("integer_division")
	var h := (d + (13 * (m + 1)) / 5 + k + k / 4 + j / 4 + 5 * j) % 7
	return (h + 5) % 7


## The strip in front of a sidewalk box (the cells between it and the street, column by column)
## and the street's first 6 m beyond the curb: {strip: [rows of cell indices, from the sidewalk out],
## road: [rows from the curb out]}.
func _s11_front(id: String) -> Dictionary:
	var r: Rect2 = Boxes.get_box(id)["rects"][0]
	var o: Vector2i = Municipal.crew_out(id)
	var c := Snow._rect_cells(r)
	var strip := []
	var road := []
	var z := c.end.y if o.y > 0 else c.position.y - 1
	while Snow.surf[z * Snow.W + c.position.x + 3] != Snow.S_ROAD:
		strip.append(range(c.position.x, c.end.x).map(func(x): return z * Snow.W + x))
		z += o.y
	for k in range(24):
		road.append(range(c.position.x, c.end.x).map(func(x): return z * Snow.W + x))
		z += o.y
	return {"strip": strip, "road": road}


static func _s11_sum(cells: Array, d: PackedFloat32Array) -> float:
	var v := 0.0
	for i in cells:
		v += d[i]
	return v * Snow.CELL_AREA


## Weekdays (the game had a placeholder and no years): winter 1 starts on Tuesday, December 1,
## 2026, and later winters follow the real calendar; the game's winter has no February 29, so in a
## leap winter the day after Feb 28 is a real March 1 (two weekdays on). Every display reads them
## through Clock.weekday (checked on the displays in test_s11_displays).
func test_s11_weekdays() -> void:
	runner.check(Clock.real_date(0, 1) == Vector3i(2026, 12, 1) and Clock.weekday(0, 1) == "Tue", "§11 winter 1 starts on Tuesday, December 1, 2026 (%s %s)" % [Clock.weekday(0, 1), str(Clock.real_date(0, 1))])
	runner.check(Clock.real_date(31, 1) == Vector3i(2027, 1, 1) and Clock.real_date(120, 1) == Vector3i(2027, 3, 31) and Clock.real_date(0, 2) == Vector3i(2027, 12, 1) and Clock.real_date(90, 5) == Vector3i(2031, 3, 1),
		"§11 winter N runs from December of 2025 + N to March of 2026 + N")
	var bad := []
	for y in range(1, 9):
		for d in range(Clock.DAYS_IN_WINTER):
			var rd := Clock.real_date(d, y)
			var want: String = Clock.WEEKDAYS[_s11_zeller(rd.x, rd.y, rd.z)]
			if Clock.weekday(d, y) != want or Clock.weekday_index(d, y) != _s11_zeller(rd.x, rd.y, rd.z):
				bad.append("winter %d day %d (%s): %s, real %s" % [y, d, str(rd), Clock.weekday(d, y), want])
	runner.check(bad.is_empty(), "§11 every day of winters 1–8 has its real weekday (Zeller's congruence)%s" % ("" if bad.is_empty() else ": %s" % str(bad.slice(0, 4))))
	var dec1 := range(1, 8).map(func(y): return Clock.weekday(0, y))
	runner.check(dec1 == ["Tue", "Wed", "Fri", "Sat", "Sun", "Mon", "Wed"], "§11 Dec 1 of winters 1–7: %s" % ", ".join(dec1))
	runner.check(Clock.real_date(89, 2) == Vector3i(2028, 2, 28) and Clock.weekday(89, 2) == "Mon" and Clock.real_date(90, 2) == Vector3i(2028, 3, 1) and Clock.weekday(90, 2) == "Wed",
		"§11 the leap winter (2): Feb 28, 2028 is a Monday and the game's next day, March 1, a Wednesday (the 29th isn't played)")
	var steps := []
	for y in range(1, 9):
		for d in range(1, Clock.DAYS_IN_WINTER):
			var g := posmod(Clock.weekday_index(d, y) - Clock.weekday_index(d - 1, y), 7)
			if g != 1:
				steps.append("winter %d, %s → %s: +%d" % [y, Clock.date_string(d - 1, true), Clock.date_string(d, true), g])
	runner.check(steps == ["winter 2, Feb 28 → Mar 1: +2", "winter 6, Feb 28 → Mar 1: +2"], "§11 one weekday a day, except over the leap days of 2028 and 2032: %s" % str(steps))


## Passes on Mondays and Fridays only, over a whole winter (3 seeds; and the first week of a winter
## that starts on a Friday), at the grader's time of day: each winter's 4–8 a.m. draw as before, the pass at the top
## of the hour after it, as the hourly tick always started it. Every pass leaves every sidewalk box
## bare and complete.
func test_s11_crew_days_whole_winter() -> void:
	for run in [[2024, 1, Clock.DAYS_IN_WINTER], [7, 1, Clock.DAYS_IN_WINTER], [99, 1, Clock.DAYS_IN_WINTER], [2024, 3, 8]]:
		var sd: int = run[0]
		var y: int = run[1]
		var span: int = run[2]
		await _s11_fresh(sd, y)
		var t0 := Clock.minutes
		var times := []
		var not_bare := [0]
		var cb := func():
			times.append(Clock.minutes)
			for bx in Boxes.boxes:
				if bx["kind"] == "sidewalk" and not (bx["complete"] and Snow.volume_in_rect(bx["rects"][0]) < 1e-9):
					not_bare[0] += 1
		Municipal.pass_finished.connect(cb)
		Clock.skip(span * 1440.0)
		Municipal.pass_finished.disconnect(cb)
		var r := RandomNumberGenerator.new()
		r.seed = sd * 3 + y
		r.randi_range(2, 3)
		var drawn := r.randf_range(4.0, 8.0)
		var hour := int(ceil(drawn - 0.01 / 60.0))
		var want := []
		for d in range(Clock.DAYS_IN_WINTER):
			var t := Clock.at(d, hour)
			if Clock.weekday(d, y) in ["Mon", "Fri"] and t > t0 and t <= t0 + span * 1440.0:
				want.append(t)
		var days := {}
		for t in times:
			var k := Clock.weekday(int(t / 1440.0), y)
			days[k] = int(days.get(k, 0)) + 1
		runner.info("seed %d, winter %d: drawn %.2f h, passes at %d:00 — %s, first %s %s" % [sd, y, drawn, hour, str(days), Clock.weekday(int(times[0] / 1440.0), y), Clock.format_time(times[0])])
		runner.check(times == want and Municipal.pass_minute() == hour * 60.0, "§11 seed %d, winter %d, %d days: %d passes, on every Monday and Friday at %d a.m. (the grader's hour: drawn %.2f, started at the next hour as before) and on no other day" % [sd, y, span, times.size(), hour, drawn])
		runner.check(not_bare[0] == 0, "§11 …each leaving every sidewalk box bare and complete (%d not)" % not_bare[0])
		if y == 1:
			runner.check(Clock.date_string(int(times[0] / 1440.0), true) == "Dec 4", "§11 …the first on Friday, Dec 4 (%s)" % Clock.format_time(times[0]))


## The pass (batch, as in a skip): every sidewalk box to 100 % (bare) except a section under the
## player's city sidewalk contract; the snow onto the strip between the sidewalk and the street as a
## mound on its sidewalk side, beside the grader's windrow on its street side, volume conserved; the
## street untouched by the crew; where the strip is full, the snow goes onto the street's edge.
func test_s11_sidewalk_pass() -> void:
	await _s11_fresh(2024)
	Snow.add_snowfall(0.2)
	Snow.sync_all()
	# The player's city sidewalk contract on 11–19 Maple Street (the crew leaves it to them).
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var job := Contracts.force_award(int(Contracts._add_walk_listing("A_w", Clock.day_index(), rng)["lid"]))
	var job_boxes: Array = Contracts.contract_boxes(job)
	runner.check(job_boxes.size() == 3 and job_boxes.all(func(id): return Municipal.crew_skips(id)), "§11 a city sidewalk contract held: %s" % str(job_boxes))
	var d0 := Snow.depth.duplicate()
	var l0 := Snow.loose.duplicate()
	var h0 := Snow.hold.duplicate()
	var v0 := _s11_volume()
	# The grader alone, then (from the same snow) the grader and the crew.
	Municipal.crew_pending = []
	Municipal.run_batch(Municipal.route_lanes())
	var dg := Snow.depth.duplicate()
	var road_g := _s11_road()
	var vg := _s11_volume()
	Snow.depth = d0.duplicate()
	Snow.loose = l0.duplicate()
	Snow.hold = h0.duplicate()
	var sw := {}
	for id in Municipal.crew_route():
		sw[id] = Snow.volume_in_rect(Boxes.get_box(id)["rects"][0])
	Municipal.crew_pending = Municipal.crew_route()
	Municipal.run_batch(Municipal.route_lanes())
	var df := Snow.depth.duplicate()
	var vf := _s11_volume()
	var cleared := []
	var bad := []
	for id in Municipal.crew_route():
		var b := Boxes.get_box(id)
		var c := Snow._rect_cells(b["rects"][0])
		var top := 0.0
		for z in range(c.position.y, c.end.y):
			for x in range(c.position.x, c.end.x):
				top = maxf(top, Snow.depth[z * Snow.W + x])
		if id in job_boxes:
			if b["complete"] or absf(Snow.volume_in_rect(b["rects"][0]) - float(sw[id])) > 1e-6 or Municipal.crew_log.get(id, "") != "skipped":
				bad.append("%s (a job) touched" % id)
		elif not (b["complete"] and float(b["progress"]) == 1.0 and top == 0.0 and Municipal.crew_log.get(id, "") == "cleared"):
			bad.append("%s %.1f %% max %.4f m" % [id, 100.0 * float(b["progress"]), top])
		else:
			cleared.append(id)
	runner.check(bad.is_empty() and cleared.size() == 21, "§11 after the pass: %d sidewalk boxes at 100 %% (every cell bare, complete), the 3 under the player's contract skipped%s" % [cleared.size(), "" if bad.is_empty() else " — %s" % str(bad)])
	runner.check(_s11_road() == road_g, "§11 the street is the grader's alone (identical with and without the crew behind it)")
	runner.check(absf(vg - v0) < 1e-3 and absf(vf - v0) < 1e-3, "§11 volume conserved: %.4f m³ before, %.4f after the grader alone, %.4f with the crew (float32 rounding)" % [v0, vg, vf])
	# Where the crew's snow went: the strip in front of each cleared box gained what its sidewalk held;
	# the crew's mound on the sidewalk side of the strip, the grader's windrow on its street side.
	var moved := 0.0
	var gained := 0.0
	var crew_rows := []
	var row_rows := []
	for k in range(6):
		crew_rows.append(0.0)
		row_rows.append(0.0)
	for id in cleared:
		moved += float(sw[id])
		var fr := _s11_front(id)
		for k in range((fr["strip"] as Array).size()):
			var cells: Array = fr["strip"][k]
			gained += _s11_sum(cells, df) - _s11_sum(cells, dg)
			if k < 6:
				crew_rows[k] += _s11_sum(cells, df) - _s11_sum(cells, dg)
				row_rows[k] += _s11_sum(cells, dg) - _s11_sum(cells, d0)
	var centroid := func(rows: Array) -> float:
		var m := 0.0
		var t := 0.0
		for k in range(rows.size()):
			m += float(rows[k]) * (k + 0.5) * Snow.CELL
			t += float(rows[k])
		return m / maxf(t, 1e-9)
	var cc: float = centroid.call(crew_rows)
	var cw: float = centroid.call(row_rows)
	runner.info("§11 across the strip, from the sidewalk out (m³ over the 21 boxes): crew %s, grader's windrow %s" % [str(crew_rows.map(func(x): return snappedf(x, 0.1))), str(row_rows.map(func(x): return snappedf(x, 0.1)))])
	runner.check(absf(gained - moved) < 1e-3 and moved > 100.0, "§11 the strip gained exactly what the sidewalks held: %.3f m³ moved, %.3f m³ on the strip" % [moved, gained])
	runner.check(cc < 0.6 and cw > 0.85 and crew_rows.find(crew_rows.max()) <= 1 and row_rows.find(row_rows.max()) >= 3,
		"§11 a mound beside the windrow, not on it: the crew's snow centred %.2f m out from the sidewalk (peak in row %d), the grader's %.2f m (row %d) on the strip's street side" % [cc, crew_rows.find(crew_rows.max()), cw, row_rows.find(row_rows.max())])
	# No room on the strip: the snow goes onto the street's edge.
	await _s11_fresh(2024)
	Snow.add_snowfall(0.2)
	Snow.sync_all()
	var full_id := "lot7_sidewalk"
	var fr2 := _s11_front(full_id)
	for row in fr2["strip"]:
		for i in row:
			Snow.depth[i] = Snow.ceiling - Snow.ground[i]
	var d1 := Snow.depth.duplicate()
	var l1 := Snow.loose.duplicate()
	var hd1 := Snow.hold.duplicate()
	Municipal.crew_pending = []
	Municipal.run_batch(Municipal.route_lanes())
	var dg2 := Snow.depth.duplicate()
	Snow.depth = d1
	Snow.loose = l1
	Snow.hold = hd1
	var sw2 := Snow.volume_in_rect(Boxes.get_box(full_id)["rects"][0])
	Municipal.crew_pending = Municipal.crew_route()
	Municipal.run_batch(Municipal.route_lanes())
	var strip_diff := 0.0
	for row in fr2["strip"]:
		strip_diff += absf(_s11_sum(row, Snow.depth) - _s11_sum(row, dg2))
	var edge_gain := 0.0
	var near := 0.0
	for k in range((fr2["road"] as Array).size()):
		var g := _s11_sum(fr2["road"][k], Snow.depth) - _s11_sum(fr2["road"][k], dg2)
		edge_gain += g
		if k < 4:
			near += g
	runner.check(strip_diff < 1e-6 and absf(edge_gain - sw2) < 1e-3 and near > 0.5 * sw2 and Boxes.is_complete(full_id) and Snow.volume_in_rect(Boxes.get_box(full_id)["rects"][0]) == 0.0,
		"§11 where the strip is full (at the ceiling), the sidewalk's %.2f m³ go onto the street's edge: %.2f m³, %.0f %% of it within a metre of the curb" % [sw2, edge_gain, 100.0 * near / maxf(sw2, 1e-9)])


## The grader's pass is unchanged: over the same snow it leaves exactly the street a baseline pass
## leaves (snow checksums recorded on the baseline build and the build before §11), and the crew
## behind it changes nothing on the street.
func test_s11_grader_pass_unchanged() -> void:
	await _s11_fresh(2024)
	Snow.add_snowfall(0.2)
	Snow.sync_all()
	var before := _s11_road()
	Municipal.crew_pending = []
	Municipal.run_batch(Municipal.route_lanes())
	var road := _s11_road()
	var map := _s11_map()
	runner.check(before == S11_ROAD_BEFORE, "§11 the same snow as the baseline's (road checksum %s…)" % before.substr(0, 12))
	runner.check(road == S11_ROAD_AFTER and map == S11_MAP_AFTER, "§11 the grader's pass leaves the baseline's street (road %s…, whole map %s…)" % [road.substr(0, 12), map.substr(0, 12)])
	await _s11_fresh(2024)
	Snow.add_snowfall(0.2)
	Snow.sync_all()
	Municipal.crew_pending = Municipal.crew_route()
	Municipal.run_batch(Municipal.route_lanes())
	var road2 := _s11_road()
	runner.check(road2 == S11_ROAD_AFTER and Municipal.crew_log.values().count("cleared") == Municipal.crew_route().size(),
		"§11 …and with the sidewalk crew behind it the street is still the baseline's (%s…), every sidewalk cleared" % road2.substr(0, 12))


## Skip == real time with passes. Without the world: a crew day stepped minute by minute and the
## same stretch skipped (as a sleep) give the same passes and the same snow. With the world: the
## city's pass watched in real time (the grader driving, the sidewalk plow following it) and the
## same pass skipped (an F1 jump: a batch) leave every sidewalk bare, the player's job alone and the
## snow conserved; on the way the plow stays behind the grader, holds 1× near the player and, out
## on its own (every street under the player's contract), caps 10× at 2×.
func test_s11_skip_equals_real_time() -> void:
	var runs := []
	for real in [true, false]:
		await _s11_fresh(2024)
		Clock.skip(Clock.at(2, 20.0) - Clock.minutes)    # Thursday, Dec 3, 8 p.m.
		Weather.force(Weather.C.LIGHT, 11.0, 0.8)          # light snow through the night, until 7 a.m.
		var times := []
		var cb := func(): times.append(Clock.minutes)
		Municipal.pass_finished.connect(cb)
		var t_end := Clock.at(3, 12.0)
		if real:
			while Clock.minutes < t_end - 1e-6:
				Clock.advance(minf(0.5, t_end - Clock.minutes))
		else:
			Clock.skip(t_end - Clock.minutes)
		Municipal.pass_finished.disconnect(cb)
		Snow.sync_all()
		var bare := Boxes.boxes.filter(func(bx): return bx["kind"] == "sidewalk" and bx["complete"] and Snow.volume_in_rect(bx["rects"][0]) < 1e-3).size()
		runs.append({"times": times, "log": Municipal.crew_log.duplicate(), "depth": Snow.depth.duplicate(), "vol": _s11_volume(), "bare": bare})
	var maxd := 0.0
	for i in range(Snow.W * Snow.H):
		maxd = maxf(maxd, absf(runs[0]["depth"][i] - runs[1]["depth"][i]))
	runner.check(runs[0]["times"] == runs[1]["times"] and runs[0]["times"].size() == 1 and str(runs[0]["log"]) == str(runs[1]["log"]) and runs[0]["bare"] == 24 and runs[1]["bare"] == 24,
		"§11 a crew day stepped by half minutes and skipped: the same pass (%s), the same 24 sidewalks cleared" % str(runs[0]["times"].map(func(t): return Clock.format_time(t))))
	runner.check(maxd < 1e-4 and absf(float(runs[0]["vol"]) - float(runs[1]["vol"])) < 1e-2, "§11 …and the same snow (largest cell difference %.7f m, the snowfall's float sums; %.3f vs %.3f m³)" % [maxd, runs[0]["vol"], runs[1]["vol"]])
	# With the world: the pass in real time and skipped.
	var res := []
	for real in [true, false]:
		await _unload()
		Game.force_input = true
		Game.new_game("fun", 2024)
		Game.flags["mail_read"] = true
		Game.flags["computer_unlocked"] = true
		Game.flags["truck_keys"] = true
		Game.set_stage(Game.Stage.COMPLETE)
		Clock.reset(Clock.at(3, 7.9))          # Friday, Dec 4, 7:54 a.m.: the crews at 8
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var job := Contracts.force_award(int(Contracts._add_walk_listing("C_e", Clock.day_index(), rng)["lid"]))
		await _spawn_world()
		world.snow_renderer.relax_usec = 0
		Weather.force(Weather.C.CLEAR, 48.0)
		var pl: Player = world.player
		var spot := Vector2(112.0, 143.0)          # a front yard on Birch Avenue, by the last sidewalk the crew does
		pl.teleport(Vector3(spot.x, Snow.surface_height(spot.x, spot.y) + 0.05, spot.y), 0.0)
		await _frames(10)
		Snow.relax_until_stable()
		var v0 := _s11_volume()
		var job_vol := 0.0
		for id in Contracts.contract_boxes(job):
			job_vol += Snow.volume_in_rect(Boxes.get_box(id)["rects"][0])
		var crew: SidewalkCrew = world.crew
		var g: GraderNPC = world.grader
		var info := {"ahead": 0, "frames": 0, "held_crew": 0, "on_walk": 0, "moving": 0}
		if real:
			var t_go := Clock.at(3, 8.0)
			while Clock.minutes < t_go:
				await _frames(1)
			runner.check(Municipal.in_progress and g.active and crew.active and crew.visible, "§11 Friday 8 a.m.: the grader and the sidewalk plow are out")
			var last := crew.global_position
			var prev := [-1, 0.0]
			while Municipal.in_progress and info["frames"] < 30000:
				await _frames(1)
				info["frames"] += 1
				if crew.active:
					var e: Dictionary = crew.runs[crew.run_i]
					var lim := crew._limit(e)
					# Moving on behind the grader on the same lane: never within LAG of it (it waits at a
					# box's start until the grader is far enough ahead).
					if crew.run_i == prev[0] and crew.s > float(prev[1]) + 1e-6 and crew.s > lim + 1e-3:
						info["ahead"] += 1
					prev = [crew.run_i, crew.s]
					var cp := Vector2(crew.global_position.x, crew.global_position.z)
					if crew.s > SidewalkCrew.BLADE_AHEAD and Boxes.box_has_point(str(e["box"]), cp):
						info["on_walk"] += 1
					if crew.global_position.distance_to(last) > 0.01:
						info["moving"] += 1
					last = crew.global_position
					if world.ff_hold() == "crew":
						info["held_crew"] += 1
			runner.info("§11 real time: %d frames; the plow on a sidewalk box %d, moving %d, held 1× for it %d" % [info["frames"], info["on_walk"], info["moving"], info["held_crew"]])
			runner.check(info["ahead"] == 0 and info["on_walk"] > 3000 and info["moving"] > 3000, "§11 the plow drove the sidewalks (%d frames on them), never closer than %d m behind the grader on its lane" % [info["on_walk"], int(SidewalkCrew.LAG)])
			runner.check(info["held_crew"] > 30, "§11 the plow passing the player holds fast-forward at 1× (%d frames, \"crew\")" % info["held_crew"])
		else:
			Clock.skip(Clock.at(3, 11.0) - Clock.minutes)   # as an F1 jump
		runner.check(not crew.active and not crew.visible and not g.active, "§11 %s: the pass is over, the plow gone" % ("real time" if real else "skipped"))
		var v1 := _s11_volume()
		var job_after := 0.0
		for id in Contracts.contract_boxes(job):
			job_after += Snow.volume_in_rect(Boxes.get_box(id)["rects"][0])
		var bare := Boxes.boxes.filter(func(bx): return bx["kind"] == "sidewalk" and bx["complete"] and Snow.volume_in_rect(bx["rects"][0]) < 1e-9).map(func(bx): return bx["id"])
		res.append({"log": Municipal.crew_log.duplicate(), "bare": bare, "passes": Municipal.passes, "last": Municipal.last_pass})
		runner.check(absf(v1 - v0) < 0.01, "§11 %s: volume conserved (%.4f → %.4f m³)" % ["real time" if real else "skipped", v0, v1])
		runner.check(bare.size() == 21 and Contracts.contract_boxes(job).all(func(id): return Municipal.crew_log.get(id, "") == "skipped" and not (id in bare)) and job_after >= job_vol - 1e-6,
			"§11 %s: 21 sidewalks bare and complete, the 3 under the player's contract left to them (%.2f → %.2f m³)" % ["real time" if real else "skipped", job_vol, job_after])
		Saves.delete_save("fun")
	runner.check(str(res[0]["log"]) == str(res[1]["log"]) and res[0]["bare"] == res[1]["bare"] and res[0]["last"] == res[1]["last"],
		"§11 real time == skipped: the same pass (%s), the same sidewalks cleared and skipped" % Clock.format_time(float(res[0]["last"])))
	# Out on its own: every street under the player's contract, so the grader stays in.
	for seg in Layout.road_segments:
		var rr := RandomNumberGenerator.new()
		Contracts.force_award(int(Contracts._add_municipal_listing(seg, Clock.day_index(), rr)["lid"]))
	Municipal.next_pass = Clock.minutes
	Municipal.on_hour(Clock.day_index(), Clock.hour())
	await _frames(2)
	runner.check(not world.grader.active and world.crew.active and world.ff_cap().get("why", "") == "sidewalk crew out", "§11 the plow out alone caps 10× at 2× (\"%s\")" % str(world.ff_cap().get("why", "")))
	world.finish_grader_now()
	runner.check(not Municipal.in_progress and not world.crew.active and Municipal.crew_log.values().count("cleared") >= 21, "§11 …and a sleep finishes its sidewalks as a batch")
	await _unload()


## Displays: the TV, the radio and the computer show the next crew day ("City crews: Fri 8 a.m."),
## computed from the schedule and the clock — also when the clock is set directly, as the
## screenshots do (it used to show a stored date in the past); the weekday on the HUD clock, the TV
## and computer cards and due times; Gerry's line; F1's "Next Monday"; an old save on the schedule.
func test_s11_displays() -> void:
	await _s9_world("fun", 10.0)                 # Wednesday, Dec 2, 10 a.m.
	var wd := func(m: float) -> String: return Clock.weekday(int(floor(m / 1440.0)), Game.year)
	var at := Municipal.next_crew_time(Clock.minutes)
	var line := Municipal.crew_line()
	runner.check(line == "City crews: %s %s" % [wd.call(at), Contracts.clock_text(at)] and line == "City crews: Fri %s" % Contracts.clock_text(Clock.at(0, 0.0) + Municipal.pass_minute()) and Municipal.is_crew_start(at),
		"§11 the next crew day from the schedule: \"%s\"" % line)
	var tv := Panels.tv(world.hud, func(): pass, false)
	var tvt := _s2_texts(tv)
	tv.queue_free()
	var cards_ok := true
	for e in Weather.forecast(3):
		var ct := Weather.card_text(e)
		cards_ok = cards_ok and str(ct["date"]) == "%s %s" % [Clock.weekday(int(e["day"]), Game.year), Clock.date_string(int(e["day"]), true)] and tvt.contains(str(ct["date"]))
	runner.check(tvt.contains(line) and not tvt.contains("City grader next expected") and cards_ok, "§11 the TV: \"%s\", its cards dated with the weekday (%s …)" % [line, Weather.card_text(Weather.forecast(1)[0])["date"]])
	runner.check(world.radio_text().ends_with(" " + line), "§11 the radio ends with the crews' line")
	world.open_computer()
	await _frames(2)
	var comp: ComputerUI = world.modal
	comp._open_app(ComputerUI.app_index("weather"))
	await _frames(1)
	var ctext := _s2_texts(comp.content)
	runner.check(ctext.contains(line) and ctext.contains(str(Weather.card_text(Weather.forecast(1)[0])["date"])), "§11 the computer's Weather app: the crews' line and the cards' weekdays")
	world.close_modal()
	await _frames(2)
	var hud: HUD = world.hud
	await _frames(15)
	runner.check(hud.date_l.text.contains(Clock.weekday(Clock.day_index(), Game.year) + " ") and Contracts.when_text(Clock.at(4, 21.0)) == "9 p.m. " + Clock.weekday(4, Game.year) and Clock.weekday(4, Game.year) == "Sat",
		"§11 the weekday on the HUD clock (\"%s\") and in due times (\"%s\")" % [hud.date_l.text, Contracts.when_text(Clock.at(4, 21.0))])
	# The clock set directly (the shots do this): never a crew day in the past, and no catch-up pass.
	var passes0 := Municipal.passes
	Clock.reset(Clock.at(48, 9.0))                # Monday, Jan 18, 9 a.m. (after that morning's crews)
	var at2 := Municipal.next_crew_time(Clock.minutes)
	var tv2 := Panels.tv(world.hud, func(): pass, false)
	var tvt2 := _s2_texts(tv2)
	tv2.queue_free()
	runner.check(at2 > Clock.minutes and at2 - Clock.minutes <= 4.0 * 1440.0 and tvt2.contains(Municipal.crew_line()) and Municipal.crew_line() == "City crews: Fri %s" % Contracts.clock_text(at2) and world.radio_text().ends_with(Municipal.crew_line()),
		"§11 the clock set to Mon Jan 18, 9 a.m.: \"%s\" (%s; the stored pass was %s)" % [Municipal.crew_line(), Clock.format_time(at2), Clock.format_time(Municipal.next_pass)])
	Clock.advance(60.0)
	runner.check(Municipal.passes == passes0 and is_equal_approx(Municipal.next_pass, at2) and not Municipal.in_progress, "§11 …the next hour: no pass at 10 a.m., the city back on its schedule (%s)" % Clock.format_time(Municipal.next_pass))
	Clock.reset(Clock.at(51, 7.5))                # Thursday, Jan 21
	runner.check(Municipal.crew_line() == "City crews: Fri %s" % Contracts.clock_text(Clock.at(0, 0.0) + Municipal.pass_minute()), "§11 Thursday: \"%s\"" % Municipal.crew_line())
	# Gerry's line.
	var lines := HelpText.explanation(false).map(func(x): return str(x["text"]))
	runner.check(lines.any(func(t): return t.contains("every Monday and Friday")) and not lines.any(func(t): return t.contains("three or four days")), "§11 Gerry: the grader comes every Monday and Friday")
	# F1: the next Monday, half an hour before the crews.
	var dm := DebugMenu.new()
	runner.add_child(dm)
	await _frames(1)
	var pressed := false
	for bt in dm.find_children("*", "Button", true, false):
		if (bt as Button).text == "Next Monday":
			(bt as Button).pressed.emit()
			pressed = true
	runner.check(pressed and Clock.weekday(Clock.day_index(), Game.year) == "Mon" and is_equal_approx(fmod(Clock.minutes, 1440.0), Municipal.pass_minute() - 30.0) and Clock.day_index() == 55,
		"§11 F1 \"Next Monday\": %s %s, half an hour before the crews" % [Clock.weekday(Clock.day_index(), Game.year), Clock.format_time(Clock.minutes)])
	dm.queue_free()
	await _frames(1)
	Clock.advance(31.0)
	runner.check(Municipal.in_progress and world.grader.active and world.crew.active, "§11 …and at the crews' hour they come")
	world.finish_grader_now()
	await _unload()
	# An old save (pass 4, a pass every 3–4 days) goes on the schedule; a new one keeps its pass.
	var ok: bool = await _load_save_file("res://tests/fixtures/polish4/fun_5_midwinter.json")
	runner.check(ok and Municipal.is_crew_start(Municipal.next_pass) and is_equal_approx(Municipal.next_pass, Municipal.next_crew_time(Clock.minutes)),
		"§11 a pass-4 save: the next pass on the schedule (%s %s)" % [Clock.weekday(int(Municipal.next_pass / 1440.0), Game.year), Clock.format_time(Municipal.next_pass)])
	Saves.delete_save("fun")


# =============================================================================
# §12 The pickup truck in snow
# =============================================================================
# The targets are balance values (data/balance.tres, BalanceData "Pickup truck"); the tests read
# them, and the storm and major-event sizes from the weather's own balance values.

## The top of the pickup's front bumper (VehicleModels: the bar at 0.45 m, 0.18 m tall).
const S12_BUMPER := 0.54
## Every §12 run is the same every time (§12 fix): the snow the pickup shoves lands where
## Snow.blade_push puts it, 0–12 cm further out by a draw from the engine's global random generator
## (randf), whose state depends on whatever ran before — so each run starts from this seed. The
## world's relaxation runs by tile count only (no per-frame time budget), as in §9 and §11.
const S12_SEED := 1212


## A fresh world (fun, seed 2024, Wed Dec 2 noon, clear, the clock stopped), keys found.
func _s12_world(day := 1, hour := 12.0) -> void:
	await _unload()
	Game.force_input = true
	Game.new_game("fun", 2024)
	Game.flags["mail_read"] = true
	Game.flags["computer_unlocked"] = true
	Game.flags["truck_keys"] = true
	Game.flags["help_vehicle_0"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	Clock.reset(Clock.at(day, hour))
	await _spawn_world()
	Clock.running = false
	Weather.force(Weather.C.CLEAR, 48.0)
	world.snow_renderer.relax_usec = 0     # relaxation by tile count only: the same every run


## Leave the world, and the global random generator random again (S12_SEED seeded it).
func _s12_done() -> void:
	randomize()
	await _unload()


## A pickup at (x, z) facing `yaw` (−π/2: east along the street), with the player in it.
func _s12_truck(x: float, z := 84.95, yaw := -PI * 0.5) -> Vehicle:
	seed(S12_SEED)                         # where the shoved snow lands: the same every run
	var e := {"uid": Game.uid(), "id": "pickup", "pos": Vector3(x, 0, z), "yaw": yaw, "snow": 0.0}
	Game.vehicles.append(e)
	var v: Vehicle = world.spawn_vehicle_node(e)
	await _frames(2)
	v.enter_vehicle(world.player)
	await _frames(1)
	return v


## Out of the truck and the truck gone (to start the next run in the same world).
func _s12_drop(v: Vehicle) -> void:
	v.exit_vehicle()
	Game.vehicles.erase(v.entry)
	v.queue_free()
	await _frames(2)


## Hold `action` up to `frames`; stop early when the front passes x = stop_x (driving east) or the
## truck has stood still for a second. Returns {dist, vmax, v_from (the speed as the front reached
## x = from_x), vmin (the lowest speed after that), stuck, blocked (frames), reasons, front}.
func _s12_drive(v: Vehicle, frames: int, action := "veh_accelerate", stop_x := INF, from_x := INF) -> Dictionary:
	var p0 := v.global_position
	var fwd := -v.global_transform.basis.z
	var r := {"vmax": 0.0, "vmin": INF, "v_from": -1.0, "stuck": 0, "blocked": 0, "reasons": []}
	Input.action_press(action)
	var still := 0
	for f in range(frames):
		await _tree().physics_frame
		var front := v.global_position.x + v.data.length * 0.5
		r["vmax"] = maxf(r["vmax"], v.speed)
		if front > from_x:
			if r["v_from"] < 0.0:
				r["v_from"] = v.speed
			r["vmin"] = minf(r["vmin"], v.speed)
		if v.stuck:
			r["stuck"] += 1
		if v.blocked_reason != "":
			r["blocked"] += 1
			if not (r["reasons"] as Array).has(v.blocked_reason):
				r["reasons"].append(v.blocked_reason)
		still = still + 1 if absf(v.speed) < 0.05 and f > 20 else 0
		if still > 60 or front > stop_x:
			break
	Input.action_release(action)
	await _frames(1)
	r["dist"] = (v.global_position - p0).dot(fwd)
	r["front"] = v.global_position.x + v.data.length * 0.5
	return r


## A bank across Maple Street (west section): a flat top 2 m long at height h from x, with 0.5 m
## shoulders at half height; the rest of the section at 3 cm.
func _s12_bank(x: float, h: float) -> void:
	Snow.set_rect(Rect2(0, 79, 92, 8), 0.03)
	Snow.set_rect(Rect2(x, 79, 2.0, 8), h)
	Snow.set_rect(Rect2(x - 0.5, 79, 0.5, 8), h * 0.5)
	Snow.set_rect(Rect2(x + 2.0, 79, 0.5, 8), h * 0.5)


## After a typical storm (the weather's storm sizes, 15–30 cm) the pickup drives anywhere on the
## street — along both lanes and across it — without shoving (storm snow passes under the
## bumper), slower the deeper the snow; never stuck, never blocked.
func test_s12_street_at_storm_depth() -> void:
	var b: BalanceData = Catalog.balance
	await _s12_world()
	runner.check(b.storm_cm_max / 100.0 <= b.pickup_shove_floor and b.pickup_shove_floor < b.pickup_stuck_depth,
		"§12 storm snow (%d–%d cm) passes under the bumper (shove floor %d cm, stuck at %d cm)" % [int(b.storm_cm_min), int(b.storm_cm_max), int(round(b.pickup_shove_floor * 100.0)), int(round(b.pickup_stuck_depth * 100.0))])
	var tops := []
	for cm in [b.storm_cm_min, (b.storm_cm_min + b.storm_cm_max) * 0.5, b.storm_cm_max]:
		var d: float = cm / 100.0
		Snow.set_rect(Rect2(0, 79, 92, 8), d)
		var moved0 := Snow.stat_player_moved
		var v := await _s12_truck(6.0)
		var r := await _s12_drive(v, 360)
		runner.check(r["stuck"] == 0 and r["blocked"] == 0 and r["dist"] > 25.0 and is_equal_approx(Snow.stat_player_moved, moved0),
			"§12 %.1f cm on the street: 6 s from a standstill along the lane, %.1f m, top %.1f km/h, never stuck or blocked, nothing shoved" % [cm, r["dist"], r["vmax"] * 3.6])
		tops.append(r["vmax"])
		await _s12_drop(v)
	runner.check(tops[0] > tops[1] and tops[1] > tops[2], "§12 slower the deeper: %s km/h" % str(tops.map(func(t): return int(t * 3.6))))
	# The deepest storm: the other lane (westbound) and across the street at 30°.
	var dmax := b.storm_cm_max / 100.0
	Snow.set_rect(Rect2(0, 79, 92, 8), dmax)
	var v2 := await _s12_truck(86.0, 81.05, PI * 0.5)
	var r2 := await _s12_drive(v2, 300)
	runner.check(r2["stuck"] == 0 and r2["blocked"] == 0 and r2["dist"] > 20.0, "§12 %d cm: the westbound lane, %.1f m" % [int(b.storm_cm_max), r2["dist"]])
	await _s12_drop(v2)
	var v3 := await _s12_truck(20.0, 85.0, -PI * 0.5 + deg_to_rad(30.0))
	var z0 := v3.global_position.z
	var r3 := await _s12_drive(v3, 150)
	runner.check(r3["stuck"] == 0 and r3["blocked"] == 0 and v3.global_position.z < 83.0, "§12 %d cm: across the street at 30°, over the centre line (z %.1f → %.1f)" % [int(b.storm_cm_max), z0, v3.global_position.z])
	await _s12_drop(v3)
	await _s12_done()


## The largest typical storm, then the city's pass (grader and sidewalk crew, as a sleep runs
## it): the grader's windrow across the cleared driveway's apron — taller than the shove floor and
## than the old pickup's bank limit — and the pickup drives out of the driveway across it onto the
## street, shoving it aside, the snow's volume unchanged.
func test_s12_windrow_across_an_apron() -> void:
	var b: BalanceData = Catalog.balance
	await _s12_world()
	var drv: Rect2 = Boxes.get_box(Boxes.lot_box(Layout.player_lot, "driveway"))["rects"][0]
	Snow.set_rect(Rect2(0, 79, Layout.MAP_W, 8), 0.03)         # the street after an earlier pass
	Snow.set_rect(drv, 0.0)
	Snow.add_layer_rect(Rect2(0, 70, Layout.MAP_W, 30), b.storm_cm_max / 100.0)
	Snow.set_rect(drv, 0.0)                                      # the driveway cleared after the storm
	Municipal.crew_pending = Municipal.crew_route()
	Municipal.run_batch(Municipal.route_lanes())
	Snow.relax_until_stable()
	var cx := drv.get_center().x
	var peak := 0.0
	for k in range(40):
		peak = maxf(peak, Snow.depth_at(cx, 85.0 + k * 0.125))
	runner.check(peak > b.pickup_shove_floor and peak > 0.57, "§12 a %d cm storm and the city's pass: a windrow %d cm high across the apron (the old pickup stopped at 57 cm)" % [int(b.storm_cm_max), int(round(peak * 100.0))])
	var region := Rect2(drv.position.x - 8.0, 74.0, drv.size.x + 16.0, 30.0)
	var vol0 := Snow.volume_in_rect(region)
	var moved0 := Snow.stat_player_moved
	var truck: Vehicle = world.vehicle_nodes()[0]
	seed(S12_SEED)
	truck.enter_vehicle(world.player)
	await _frames(2)
	Input.action_press("veh_accelerate")
	var stuck := 0
	for f in range(360):
		await _tree().physics_frame
		stuck += 1 if truck.stuck else 0
		if truck.global_position.z + truck.data.length * 0.5 < 86.5:
			break
	_release_all()
	await _frames(2)
	var rear := truck.global_position.z + truck.data.length * 0.5
	runner.check(rear < 87.0 and stuck == 0, "§12 …the pickup drives out of the driveway across it: its tailgate past the curb (z %.1f < 87), never stuck" % rear)
	runner.check(Snow.stat_player_moved > moved0 + 0.05, "§12 …shoving %.2f m³ of it aside" % (Snow.stat_player_moved - moved0))
	runner.near(Snow.volume_in_rect(region), vol0, 1e-4, "§12 …the snow's volume unchanged (%.6f → %.6f m³)" % [vol0, Snow.volume_in_rect(region)])
	truck.exit_vehicle()
	await _s12_done()


## A bank about as high as the bumper: with a run-up the pickup shoves through it, slowing; a
## taller one (between the bog depth and the most it can take) stops it from a standstill with the
## message and the reverse key — backing up and taking a run at it gets it through.
func test_s12_bank_with_a_run_up() -> void:
	var b: BalanceData = Catalog.balance
	await _s12_world()
	_s12_bank(30.0, S12_BUMPER)
	var region := Rect2(0, 70, 92, 26)
	var vol0 := Snow.volume_in_rect(region)
	var v := await _s12_truck(29.5 - 15.0 - 2.7)            # a 15 m run-up
	var r := await _s12_drive(v, 600, "veh_accelerate", 40.0, 29.5)
	runner.check(r["front"] > 40.0 and r["blocked"] == 0 and r["stuck"] == 0,
		"§12 a %d cm bank (bumper high), 15 m run-up: shoved through (front at x %.1f, the bank ends at 32.5), never blocked or stuck" % [int(round(S12_BUMPER * 100.0)), r["front"]])
	runner.check(r["vmin"] < r["v_from"] * 0.9, "§12 …slowing as it goes: %.1f → %.1f km/h in the bank" % [r["v_from"] * 3.6, r["vmin"] * 3.6])
	runner.near(Snow.volume_in_rect(region), vol0, 1e-4, "§12 …volume unchanged (%.6f m³)" % vol0)
	await _s12_drop(v)
	# Taller: between the bog depth and the most the pickup takes (snow above the grille stops it).
	var h := (b.pickup_bog_depth + b.pickup_bank_max) * 0.5
	_s12_bank(30.0, h)
	var v2 := await _s12_truck(29.5 - 0.3 - 2.7)            # its bumper at the bank
	var r2 := await _s12_drive(v2, 240)
	var msg := ""
	for t in r2["reasons"]:
		if str(t).contains("standstill"):
			msg = str(t)
	runner.check(r2["front"] < 31.0 and msg.contains("%d cm" % int(round(b.pickup_bog_depth * 100.0))) and msg.contains("Back up with %s" % Settings.action_label("veh_reverse")) and msg.begins_with("Snowbank ahead"),
		"§12 a %d cm bank from a standstill: held at its face (front x %.1f), \"%s\"" % [int(round(h * 100.0)), r2["front"], msg])
	var r3 := await _s12_drive(v2, 200, "veh_reverse")
	runner.check(r3["dist"] < -9.0, "§12 …backs up %.1f m" % -r3["dist"])
	var r4 := await _s12_drive(v2, 600, "veh_accelerate", 40.0, 29.5)
	runner.check(r4["front"] > 40.0, "§12 …and takes a run at it: through (front at x %.1f, %.1f → %.1f km/h in the bank)" % [r4["front"], r4["v_from"] * 3.6, r4["vmin"] * 3.6])
	await _s12_drop(v2)
	await _s12_done()


## A long stretch of untouched snow: 10 cm under the bog depth the pickup keeps going, slowly; at
## the bog depth it bogs down after its run-up (the snow it casts aside adds a few cm in front, so
## a long stretch stops it from about 65 cm: §12 report); a major event stops it — a metre and more
## at the edge, its smallest (90 cm, under the 95 cm wall) after shoving a little way in.
func test_s12_bogging_down_in_deep_snow() -> void:
	var b: BalanceData = Catalog.balance
	await _s12_world()
	var cases := [b.pickup_bog_depth - 0.1, b.pickup_bog_depth, b.major_cm_min / 100.0, 1.0, b.major_cm_max / 100.0]
	var into_bog := INF
	for d in cases:
		Snow.set_rect(Rect2(0, 79, 20, 8), 0.03)
		Snow.set_rect(Rect2(20, 79, 72, 8), d)
		Snow.relax_until_stable()                        # nothing left settling from the run before
		var v := await _s12_truck(4.0)                   # a 13 m run-up on a bare street
		var r := await _s12_drive(v, 900, "veh_accelerate", 52.0)
		var into: float = r["front"] - 20.0
		var text := str(r["reasons"][0]) if not (r["reasons"] as Array).is_empty() else ""
		if d < b.pickup_bog_depth - 0.01:
			runner.check(into > 15.0 and r["blocked"] == 0 and r["stuck"] == 0 and absf(v.speed) > b.pickup_shove_min_speed,
				"§12 %d cm untouched (10 cm under the %d cm bog depth): keeps going — %.1f m in, still at %.1f km/h" % [int(round(d * 100.0)), int(round(b.pickup_bog_depth * 100.0)), into, v.speed * 3.6])
		elif d < b.major_cm_min / 100.0 - 0.01:
			into_bog = into
			runner.check(into > 2.0 and into < 25.0 and text.contains("standstill") and absf(v.speed) < 0.05,
				"§12 %d cm untouched: bogs down %.1f m in after its run-up (\"%s\")" % [int(round(d * 100.0)), into, text.substr(0, 60)])
		elif d < 1.0:
			# The brief's target is that a major event stops it. Snow this deep (under the wall) is
			# shoved a little way first; exactly how far depends on where the shoved snow lands
			# (blade_push's random 0–12 cm: 0.9–1.7 m over different draws), so the check is the
			# target — it stops, and sooner than at the bog depth — not one draw's distance.
			runner.check(into < into_bog and text.begins_with("Snowbank ahead") and absf(v.speed) < 0.05,
				"§12 %d cm (a major event's smallest): stopped %.1f m in, sooner than the %.1f m at the bog depth, \"%s\"" % [int(round(d * 100.0)), maxf(into, 0.0), into_bog, text])
		else:
			runner.check(into < 0.5 and absf(v.speed) < 0.05 and text.begins_with("Snowbank ahead") and text.contains("about %d cm at most, with a run-up" % int(round(b.pickup_bank_max * 100.0))),
				"§12 %d cm (a major event): a metre and more is a wall to it — stopped at the edge (%.1f m in), \"%s\"" % [int(round(d * 100.0)), into, text])
		await _s12_drop(v)
	await _s12_done()


## The shove moves snow and nothing else: the whole map's snow before and after a run through
## deep snow and a bank is the same.
func test_s12_volume_conserved() -> void:
	await _s12_world()
	Snow.set_rect(Rect2(0, 79, 20, 8), 0.03)
	Snow.set_rect(Rect2(20, 79, 15, 8), 0.6)
	_s12_bank_at(45.0, 0.75)
	Snow.sync_all()
	var before := Snow.total_volume()
	var moved0 := Snow.stat_player_moved
	var v := await _s12_truck(4.0)
	var r := await _s12_drive(v, 900, "veh_accelerate", 60.0)
	await _frames(30)
	Snow.relax_until_stable()
	var after := Snow.total_volume()
	runner.check(Snow.stat_player_moved - moved0 > 2.0, "§12 the pickup shoved %.2f m³ (%.1f m)" % [Snow.stat_player_moved - moved0, r["dist"]])
	runner.near(after, before, 1e-4, "§12 the map's snow: %.6f → %.6f m³ (%+.7f)" % [before, after, after - before])
	await _s12_drop(v)
	await _s12_done()


## A bank like _s12_bank without resetting the street around it.
func _s12_bank_at(x: float, h: float) -> void:
	Snow.set_rect(Rect2(x, 79, 2.0, 8), h)
	Snow.set_rect(Rect2(x - 0.5, 79, 0.5, 8), h * 0.5)
	Snow.set_rect(Rect2(x + 2.0, 79, 0.5, 8), h * 0.5)


## The opening, by the numbers: the truck stands in the first morning's snow, deeper than it can
## start in, so its wheels still need digging out ("Stuck: … clears about N cm" from the balance);
## dug out around the wheels only, the driveway's snow ahead is deeper than it can push from a
## standstill; with the driveway cleared it drives out.
func test_s12_opening_by_the_numbers() -> void:
	var b: BalanceData = Catalog.balance
	await _s12_world(0, 7.6)
	var truck: Vehicle = world.vehicle_nodes()[0]
	var wd := truck.wheel_snow_depth()
	runner.check(wd > b.pickup_stuck_depth and truck.stuck_depth() == b.pickup_stuck_depth,
		"§12 the opening: %d cm of snow around the wheels, the pickup is stuck from %d cm" % [int(round(wd * 100.0)), int(round(b.pickup_stuck_depth * 100.0))])
	Notify.history.clear()
	truck.enter_vehicle(world.player)
	await _frames(2)
	runner.check(_s12_notified("snowed in"), "§12 …getting in says it's snowed in")
	var r := await _s12_drive(truck, 120)
	runner.check(absf(r["dist"]) < 0.5 and str(r["reasons"]).contains("only clears about %d cm" % int(round(b.pickup_stuck_depth * 100.0))),
		"§12 …it doesn't move (%.2f m): %s" % [r["dist"], str(r["reasons"])])
	var tp := Vector2(truck.global_position.x, truck.global_position.z)
	Snow.set_rect(Rect2(tp - Vector2(1.6, 2.75), Vector2(3.2, 5.5)), 0.0)    # dug out around the wheels
	var front := tp + Vector2(0, -1).rotated(-truck.rotation.y) * 3.05
	var r2 := await _s12_drive(truck, 150)
	runner.check(Snow.depth_at(front.x, front.y) > b.pickup_bog_depth and r2["dist"] < 1.5 and str(r2["reasons"]).contains("standstill"),
		"§12 …dug out around the wheels: the driveway ahead (%d cm) is more than it pushes from a standstill (%.1f m, %s)" % [int(round(Snow.depth_at(front.x, front.y) * 100.0)), r2["dist"], str(r2["reasons"]).substr(0, 70)])
	var drv: Rect2 = Boxes.get_box(Boxes.lot_box(Layout.player_lot, "driveway"))["rects"][0]
	Snow.set_rect(drv, 0.03)
	var r3 := await _s12_drive(truck, 240)
	runner.check(truck.global_position.z < drv.position.y + 1.0 and r3["stuck"] == 0, "§12 …the driveway cleared: out onto the street (truck z %.1f), through the opening's %d cm of street snow" % [truck.global_position.z, int(round(b.initial_road_depth_year1 * 100.0))])
	truck.exit_vehicle()
	await _s12_done()


func _s12_notified(word: String) -> bool:
	for n in Notify.history:
		if str(n.get("text", n)).to_lower().contains(word):
			return true
	return false


# =============================================================================
# §13a Upgrades per item (Decision 8)
# =============================================================================
# Every item type has its own tracks (ItemUpgrades, built at load from one table and the item
# data); a level keeps the old global upgrade's effect, its price scales with the item's price;
# the ladder (HANDOFF §7's order) caps the levels for sale; old saves' global levels go to every
# item they used to affect. The heated cab's warmth is §14's.

## The tracks each item gets — the effects it used before §13 (hand tools: capacity and fill,
## throw, push width, push strength and speed; machines and vehicles theirs; a cab where none).
const S13_TRACKS := {
	"hands": ["capacity", "throw", "push_width", "push"], "small_shovel": ["capacity", "throw", "push_width", "push"],
	"standard_shovel": ["capacity", "throw", "push_width", "push"], "wide_pusher": ["capacity", "throw", "push_width", "push"],
	"snow_scraper": ["capacity", "throw", "push_width", "push"], "large_scraper": ["capacity", "throw", "push_width", "push"],
	"snow_sleigh": ["capacity", "throw", "push_width", "push"], "electric_shovel": ["throw", "push_width", "push"],
	"small_blower": ["intake", "chute"], "large_blower": ["intake", "chute"],
	"pickup": ["front_plow"], "pickup_plow": ["plow_width", "plow_power"], "atv_blade": ["plow_width", "plow_power", "cab"],
	"tractor_blade": ["plow_width", "plow_power"], "tractor_blower": ["blower"], "grader": ["plow_width", "plow_power"],
	"plow_truck": ["plow_width", "plow_power"], "rotary_blower": ["blower"], "dump_truck": [],
}


## Fill the tool (id, "" = bare hands) to the brim in deep snow on the front lawn with the real
## controls, then throw it into the yard. Returns the most it held (m³).
func _s13_fill(tool_id: String) -> float:
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	Game.slots[Game.selected] = tool_id
	Game.inventory_changed.emit()
	var spot := Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, -5.0), 5.0)
	Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), 0.7)
	pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
	await _frames(3)
	pl.pitch = deg_to_rad(-50.0)
	pl.head.rotation.x = pl.pitch
	var base := pl.yaw
	var best := 0.0
	Input.action_press("primary")
	for k in range(150):
		pl.set_yaw(base + 0.5 * sin(k * 0.15))
		await _tree().physics_frame
		best = maxf(best, tc.load)
	pl.set_yaw(base)
	pl.pitch = 0.0
	pl.head.rotation.x = 0.0
	await _frames(1)
	Input.action_release("primary")
	await _frames(20)
	_release_all()
	return best


## Buy an upgrade level during store hours and collect its crate from the store's pad with E (as a
## player does). True once it is in.
func _s13_buy_and_collect(id: String) -> bool:
	var r := Economy.buy(id)
	if not r["ok"]:
		runner.info("buy %s: %s" % [id, r["msg"]])
		return false
	await _frames(2)
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).tool_id == "crate:" + id:
			(c as ToolItem).interact(world.player)
	await _frames(1)
	return Game.has_upgrade(StringName(id))


## Every item has its own tracks, from the effects it used; each level is the old global upgrade's
## effect, priced with the item's price; an upgrade bought for one item changes that item only —
## measured with the real controls for the hand tools, through the one lookup the game reads for
## every tool, machine and vehicle (ItemUpgrades.mult).
func test_s13_upgrades_belong_to_an_item() -> void:
	await _s3_world("fun")
	Game.money = 99999
	var b: BalanceData = Catalog.balance
	# The tracks.
	var bad := []
	for item in ItemUpgrades.ladder():
		var got := ItemUpgrades.tracks(item).map(func(t): return String(t))
		if got != S13_TRACKS.get(String(item), ["?"]):
			bad.append("%s %s" % [item, str(got)])
	runner.check(bad.is_empty() and ItemUpgrades.ladder().size() == S13_TRACKS.size(), "§13 every item type has its own tracks, from the effects it used (hands and each hand tool 4, the electric shovel 3, each blower 2, each vehicle its plow, blower, front plow or cab) %s" % str(bad))
	# Each level: the old global upgrade's effect; the price scaled with the item's price.
	var eff_bad := []
	var price_bad := []
	var n_levels := 0
	for item in ItemUpgrades.items():
		var ip: float = b.upgrade_hands_price if item == &"hands" else float(Economy.price_of(String(item)))
		var ref: float = b.upgrade_price_ref_vehicle if Catalog.vehicles.has(item) else (b.upgrade_price_ref_machine if Catalog.tool(item).kind == ToolData.Kind.WALK_BLOWER else b.upgrade_price_ref_tool)
		for t in ItemUpgrades.tracks(item):
			var lv: Array = ItemUpgrades.TRACKS[t]["levels"]
			for k in range(ItemUpgrades.ids(item, t).size()):
				var u: UpgradeData = Catalog.upgrade(StringName(ItemUpgrades.ids(item, t)[k]))
				n_levels += 1
				var want_v := 1.0 if t == &"cab" else (Catalog.upgrade(lv[k]) as UpgradeData).value
				var old_p: float = b.upgrade_cab_price if t == &"cab" else float((Catalog.upgrade(lv[k]) as UpgradeData).price)
				var want_p := int(old_p) if t == &"front_plow" else ItemUpgrades.nice_price(old_p * ip / ref)
				if not is_equal_approx(u.value, want_v) or u.stat != ItemUpgrades.TRACKS[t]["stat"] or u.item != item or u.level != k + 1:
					eff_bad.append(String(u.id))
				if u.price != want_p or u.price < 1:
					price_bad.append("%s $%d (want $%d)" % [u.id, u.price, want_p])
	runner.check(eff_bad.is_empty() and n_levels > 50, "§13 each of the %d levels has the old global upgrade's effect %s" % [n_levels, str(eff_bad)])
	runner.check(price_bad.is_empty(), "§13 …and costs that upgrade's price × the item's price ÷ its family's reference (hand tools $%d, blowers $%d, vehicles $%d; bare hands as $%d) %s" % [int(b.upgrade_price_ref_tool), int(b.upgrade_price_ref_machine), int(b.upgrade_price_ref_vehicle), int(b.upgrade_hands_price), str(price_bad.slice(0, 6))])
	var sm := Catalog.upgrade(StringName(ItemUpgrades.level_id(&"small_shovel", &"capacity", 1)))
	var lg := Catalog.upgrade(StringName(ItemUpgrades.level_id(&"large_scraper", &"capacity", 1)))
	runner.check(sm.price < lg.price and Catalog.upgrade(StringName(ItemUpgrades.level_id(&"atv_blade", &"plow_width", 1))).price < Catalog.upgrade(StringName(ItemUpgrades.level_id(&"plow_truck", &"plow_width", 1))).price,
		"§13 …so the same upgrade costs more for a dearer item (capacity: small shovel $%d, large scraper $%d)" % [sm.price, lg.price])
	# One lookup, item by item: a level bought for one item changes nothing else.
	var leak := []
	var saved := Game.upgrades.duplicate()
	for item in ItemUpgrades.items():
		for t in ItemUpgrades.tracks(item):
			Game.upgrades = {}
			Game.upgrades[ItemUpgrades.level_id(item, t, 1)] = true
			var stat: StringName = ItemUpgrades.TRACKS[t]["stat"]
			var v1 := (Catalog.upgrade(StringName(ItemUpgrades.level_id(item, t, 1))) as UpgradeData).value
			if not is_equal_approx(ItemUpgrades.mult(item, stat), v1):
				leak.append("%s:%s own" % [item, t])
			for other in ItemUpgrades.ladder():
				if other != item and not is_equal_approx(ItemUpgrades.mult(other, stat), 1.0):
					leak.append("%s:%s → %s" % [item, t, other])
	Game.upgrades = saved
	runner.check(leak.is_empty(), "§13 a level of any track changes its own item's stat and no other item's %s" % str(leak.slice(0, 6)))
	# With the real controls: the small shovel's capacity, bought at the computer and collected at
	# the store; the standard shovel and bare hands carry what they did.
	var std_base := await _s13_fill("standard_shovel")
	var hands_base := await _s13_fill("")
	var cap1 := ItemUpgrades.level_id(&"small_shovel", &"capacity", 1)
	runner.check(Economy.can_buy(cap1) == "" and await _s13_buy_and_collect(cap1), "§13 the small shovel's capacity 1: bought on the computer, its crate collected at the store")
	var small := await _s13_fill("small_shovel")
	var std := await _s13_fill("standard_shovel")
	var hands := await _s13_fill("")
	var sd: ToolData = Catalog.tool(&"small_shovel")
	runner.check(absf(small - sd.capacity * 1.25) < 5e-4, "§13 …the small shovel now fills to %.1f L (base %.0f L × 1.25)" % [small * 1000.0, sd.capacity * 1000.0])
	runner.check(absf(std - std_base) < 5e-4 and absf(std - Catalog.tool(&"standard_shovel").capacity) < 5e-4 and absf(hands - hands_base) < 5e-4 and absf(hands - Catalog.tool(&"hands").capacity) < 5e-4,
		"§13 …the standard shovel (%.1f L) and bare hands (%.1f L) are unchanged" % [std * 1000.0, hands * 1000.0])
	# Two small shovels share the small shovel's upgrades.
	Game.slots = ["small_shovel", "small_shovel", "", ""]
	Game.select_slot(1)
	await _frames(2)
	var c2: float = world.player.tools._capacity()
	Game.select_slot(0)
	await _frames(2)
	runner.check(is_equal_approx(c2, world.player.tools._capacity()) and is_equal_approx(c2, sd.capacity * 1.25), "§13 two small shovels share the small shovel's upgrades (%.1f L each)" % (c2 * 1000.0))
	await _unload()


## You can only upgrade what you own (an order counts); an item's upgrades stay with its type in
## your hands, on the ground or on the rack; a level past the ladder isn't sold. The baseline bug:
## the pickup's front plow ("pickup_plow", also the plowed pickup's vehicle id) was sold as a
## vehicle — every purchase delivered another truck, and it could be bought again and again. Now
## it is the pickup's upgrade, bought once. The heated cab: Survival only, its flag per vehicle type.
func test_s13_ownership_and_the_front_plow() -> void:
	await _s3_world("fun")
	Game.money = 99999
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var lsc := ItemUpgrades.level_id(&"large_scraper", &"capacity", 1)
	runner.check(Economy.can_buy(lsc) == "Buy the Large Snow Scraper first." and not Economy.buy(lsc)["ok"], "§13 an item you don't own can't be upgraded: \"%s\"" % Economy.can_buy(lsc))
	Economy.buy("large_scraper")
	runner.check(Economy.can_buy(lsc) == "", "§13 …once it's bought (on order) it can")
	var atv := ItemUpgrades.level_id(&"atv_blade", &"plow_width", 1)
	runner.check(Economy.can_buy(atv) == "Buy the ATV with Blade first.", "§13 …a vehicle too: \"%s\"" % Economy.can_buy(atv))
	# The ladder: the small shovel's second capacity level would take it well past the standard shovel.
	var cap1 := ItemUpgrades.level_id(&"small_shovel", &"capacity", 1)
	var cap2 := ItemUpgrades.level_id(&"small_shovel", &"capacity", 2)
	var hthrow2 := ItemUpgrades.level_id(&"hands", &"throw", 2)
	runner.check(Economy.can_buy(hthrow2) == "Requires level 1.", "§13 levels in order: \"%s\"" % Economy.can_buy(hthrow2))
	Game.grant_upgrade(StringName(cap1))
	runner.check(Economy.can_buy(cap2) == "Fully upgraded." and ItemUpgrades.max_level(&"small_shovel", &"capacity") == 1, "§13 a level past the ladder isn't sold: \"%s\"" % Economy.can_buy(cap2))
	# The upgrades stay with the type: dropped, on the ground, picked up again; on the rack.
	var spot := Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, -5.0), 5.0)
	Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), 0.0)
	pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
	Game.slots = ["small_shovel", "", "", ""]
	Game.select_slot(0)
	await _frames(2)
	var held := tc._capacity()
	tc.drop_tool()
	await _frames(2)
	var lying: ToolItem = null
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).tool_id == "small_shovel" and not (c as ToolItem).entry.get("buried", false):
			lying = c
	runner.check(lying != null and ItemUpgrades.owns(&"small_shovel") and is_equal_approx(ItemUpgrades.mult(&"small_shovel", &"shovel_capacity"), 1.25), "§13 a dropped small shovel keeps its upgrades (still yours, ×%.2f)" % ItemUpgrades.mult(&"small_shovel", &"shovel_capacity"))
	lying.interact(pl)
	await _frames(2)
	runner.check(Game.current_tool_id() == "small_shovel" and is_equal_approx(tc._capacity(), held), "§13 …picked up again it carries %.1f L, as before" % (tc._capacity() * 1000.0))
	Game.slots[Game.selected] = ""
	Game.rack.append("small_shovel")
	Game.inventory_changed.emit()
	var buried := Game.items.filter(func(it): return it["tool"] == "small_shovel")
	for it in buried:
		Game.items.erase(it)
	runner.check(ItemUpgrades.owns(&"small_shovel") and Game.has_upgrade(StringName(cap1)) and Economy.can_buy(ItemUpgrades.level_id(&"small_shovel", &"throw", 1)) == "", "§13 …on the rack it's still yours, with its upgrades, and can be upgraded")
	Game.rack.erase("small_shovel")
	for it in buried:
		Game.items.append(it)
	# The front plow: the pickup's upgrade, not a vehicle.
	var plow := String(ItemUpgrades.PLOW_ID)
	runner.check(Economy.item_kind(plow) == "upgrade" and Economy.can_buy("pickup_plow") == "Not sold in the store." and not Economy.buy("pickup_plow")["ok"],
		"§13 the front plow is the pickup's upgrade; the plowed pickup isn't for sale as a vehicle (\"%s\")" % Economy.can_buy("pickup_plow"))
	var nveh := Game.vehicles.size()
	var r := Economy.buy(plow)
	await _frames(3)
	var o: Dictionary = Economy.orders[Economy.orders.size() - 1]
	runner.check(r["ok"] and o["kind"] == "upgrade" and o["status"] == "spawned" and Game.vehicles.size() == nveh, "§13 buying it orders the plow: no truck in a store bay (vehicles %d → %d), no crate" % [nveh, Game.vehicles.size()])
	runner.check(Economy.can_buy(plow) == "Already owned.", "§13 …and it can't be bought again while it waits (\"%s\")" % Economy.can_buy(plow))
	var truck: Vehicle = null
	for v in world.vehicle_nodes():
		if (v as Vehicle).data.id == &"pickup":
			truck = v
	var lot: Rect2 = Layout.big_areas[1]["rect"]
	truck.global_position = Vector3(lot.get_center().x, 0.0, lot.get_center().y)
	await _frames(4)
	var ids := Game.vehicles.map(func(v): return str(v["id"]))
	runner.check(Game.has_upgrade(ItemUpgrades.PLOW_ID) and ids == ["pickup_plow"] and o["status"] == "collected", "§13 …driven into the store lot, the pickup gets its plow: one truck, plowed %s" % str(ids))
	runner.check(Economy.can_buy(plow) == "Already owned." and Game.vehicles.size() == nveh, "§13 …and the plow is bought once (\"%s\")" % Economy.can_buy(plow))
	runner.check(Economy.can_buy(ItemUpgrades.level_id(&"pickup_plow", &"plow_width", 1)) == "", "§13 …now the plow's own upgrades are for sale")
	# The heated cab: for the ATV (no cab), Survival only; bought, it's that vehicle type's flag.
	var cab := ItemUpgrades.level_id(&"atv_blade", &"cab", 1)
	Game.vehicles.append({"uid": Game.uid(), "id": "atv_blade", "pos": Vector3(40, 0, 96), "yaw": 0.0, "snow": 0.0})
	runner.check(cab != "" and ItemUpgrades.level_id(&"tractor_blade", &"cab", 1) == "" and Economy.can_buy(cab) == "Survival Mode only." and not ItemUpgrades.track_shown(&"atv_blade", &"cab"),
		"§13 the heated cab: for vehicles without one (the ATV), not in Fun Mode (\"%s\")" % Economy.can_buy(cab))
	Game.mode = "survival"
	runner.check(Economy.can_buy(cab) == "" and not ItemUpgrades.has_heated_cab(&"atv_blade") and ItemUpgrades.has_heated_cab(&"tractor_blade"), "§13 …in Survival it's for sale; the tractor has a cab built in")
	runner.check(await _s13_buy_and_collect(cab) and ItemUpgrades.has_heated_cab(&"atv_blade"), "§13 …bought and collected: the ATV has a heated cab (§14 wires its warmth)")
	Game.mode = "fun"
	await _unload()


## Old saves: every global level goes to every item it used to affect (owned or not, even past an
## item's ladder: nothing paid for is lost), with one notification; the effects are what they were.
## The 2_upgrades fixture (every old upgrade bought; the baseline bug's second plowed pickup at the
## store) loads, plays and saves the levels per item.
func test_s13_old_global_levels_carry_over() -> void:
	for mode in ["fun", "survival"]:
		var path := "res://tests/fixtures/polish5/%s_2_upgrades.json" % mode
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var old_ups: Dictionary = raw["game"]["upgrades"]
		runner.check(await _load_save_file(path), "§13 %s_2_upgrades loads" % mode)
		# What each item had from the global upgrades before (the old rule: every upgrade with the
		# stat, multiplied).
		var bad := []
		for item in ItemUpgrades.items():
			for t in ItemUpgrades.tracks(item):
				var stat: StringName = ItemUpgrades.TRACKS[t]["stat"]
				var want := 1.0
				for lid in ItemUpgrades.TRACKS[t]["levels"]:
					if old_ups.has(String(lid)):
						want *= (Catalog.upgrade(lid) as UpgradeData).value
				var n_old: int = (ItemUpgrades.TRACKS[t]["levels"] as Array).filter(func(l): return old_ups.has(String(l))).size()
				if t != &"cab" and (ItemUpgrades.level(item, t) != n_old or not is_equal_approx(ItemUpgrades.mult(item, stat), want)):
					bad.append("%s:%s level %d (want %d)" % [item, t, ItemUpgrades.level(item, t), n_old])
		var left := Game.upgrades.keys().filter(func(k): return ItemUpgrades.is_legacy(StringName(k)))
		runner.check(bad.is_empty() and left.is_empty(), "§13 %s: every old level went to every item it used to affect, each item's effects as before %s" % [mode, str(bad.slice(0, 6))])
		runner.check(ItemUpgrades.level(&"small_shovel", &"capacity") == 2 and ItemUpgrades.max_level(&"small_shovel", &"capacity") == 1 and ItemUpgrades.level(&"large_scraper", &"throw") == 2,
			"§13 …past an item's ladder too (the small shovel keeps capacity 2; the large scraper, not owned, has throw 2)")
		# §13b: the jacket and the parka (retired upgrades) are the insulated coat now (equipment).
		var kept := ["weather_pro", "weather_radar", "furnace", "tool_rack"].all(func(k): return Game.has_upgrade(StringName(k)))
		var coat := Catalog.RETIRED_UPGRADE_IDS.all(func(k): return old_ups.has(String(k)) and not Game.has_upgrade(k)) and Equipment.has(Equipment.COAT)
		runner.check(kept and coat and Game.has_upgrade(ItemUpgrades.PLOW_ID), "§13 …the other upgrades stay as they were (the jacket and parka are the insulated coat now); the pickup's plow is its front plow")
		# The baseline bug's extra truck: kept (it was delivered; nothing is taken away), its order the
		# plow's, nothing new delivered, the plow not for sale again.
		var plows := Game.vehicles.filter(func(v): return str(v["id"]) == "pickup_plow").size()
		var po: Array = Economy.orders.filter(func(x): return str(x["item"]) == String(ItemUpgrades.PLOW_ID))
		runner.check(plows == 2 and po.size() == 1 and po[0]["kind"] == "upgrade" and po[0]["status"] == "collected" and Economy.can_buy(String(ItemUpgrades.PLOW_ID)) == "Already owned.",
			"§13 …the bug's second plowed pickup stays where it was delivered (%d plowed pickups); its order is the plow's, collected; the plow can't be bought again" % plows)
		Notify.clear()
		await _spawn_world()
		await _frames(2)
		var notes := Notify.history.filter(func(n): return str(n["text"]).begins_with("Upgrades now belong to each item"))
		runner.check(notes.size() == 1 and Game.vehicles.size() == 2 and world.vehicle_nodes().size() == 2, "§13 …one notification: \"%s\"; both trucks in the world" % (notes[0]["text"] if not notes.is_empty() else ""))
		# Plays: the store spawns nothing new; sleep, autosave, reload: the levels per item, no note.
		var want_ups := JSON.stringify(Game.upgrades, "", true)
		await world._do_sleep()
		await _frames(3)
		await _unload()
		Notify.clear()
		runner.check(Saves.load_game(mode), "§13 …the autosave reloads")
		await _spawn_world()
		await _frames(2)
		runner.check(JSON.stringify(Game.upgrades, "", true) == want_ups and Game.vehicles.size() == 2 and not Notify.history.any(func(n): return str(n["text"]).begins_with("Upgrades now belong")),
			"§13 …with the same levels per item (%d), no second notification" % Game.upgrades.size())
		await _unload()
		Saves.delete_save(mode)
	# An old order's crate, collected after the change, goes to every item too.
	await _s3_world("fun")
	Game.grant_upgrade(&"blower_throw_1")
	runner.check(Game.has_upgrade(StringName(ItemUpgrades.level_id(&"small_blower", &"chute", 1))) and Game.has_upgrade(StringName(ItemUpgrades.level_id(&"large_blower", &"chute", 1))) and not Game.has_upgrade(&"blower_throw_1"),
		"§13 an old global upgrade collected now (an old order's crate) goes to every item it improved")
	await _unload()


## The ladder (HANDOFF §7's order): at base the items keep it; every track's levels for sale take an
## item to about the next item's base of what it improves, never more than the ladder's slack past
## it (unless the item is already ahead there at base). The table goes to the report.
func test_s13_the_ladder() -> void:
	var slack: float = Catalog.balance.upgrade_ladder_slack
	# The new balance values: the same in data/balance.tres and the defaults (BalanceData).
	var defaults := BalanceData.new()
	var keys := ["upgrade_price_ref_tool", "upgrade_price_ref_machine", "upgrade_price_ref_vehicle", "upgrade_hands_price", "upgrade_cab_price", "upgrade_ladder_slack"]
	runner.check(keys.all(func(k): return is_equal_approx(float(Catalog.balance.get(k)), float(defaults.get(k)))), "§13 the Upgrades balance values are the same in balance.tres and the defaults %s" % str(keys.map(func(k): return Catalog.balance.get(k))))
	# Base order: HANDOFF §7 (bare hands, the hand tools by tier, the electric shovel, the blowers,
	# then the vehicles); tier and price rise along it.
	var order := ItemUpgrades.ladder()
	var tiers := []
	var prices := []
	for id in Catalog.TOOL_IDS:
		tiers.append(Catalog.tool(id).tier)
		prices.append(Catalog.tool(id).price)
	var rising := true
	for k in range(1, tiers.size()):
		rising = rising and tiers[k] > tiers[k - 1] and prices[k] > prices[k - 1]
	runner.check(order.slice(0, Catalog.TOOL_IDS.size()) == Array(Catalog.TOOL_IDS) and order.slice(Catalog.TOOL_IDS.size()) == Array(Catalog.VEHICLE_IDS) and rising,
		"§13 the ladder is HANDOFF §7's order: tier and price rise along it (%s)" % str(prices))
	var rows := ItemUpgrades.ladder_rows()
	var over := []
	var each_track := []
	runner.info("§13 ladder: item · track · what it improves · base → fully upgraded (levels) · next item's base (ratio)")
	for r in rows:
		var nb: float = r["next_base"]
		var ratio: float = r["max"] / nb if nb > 0.0 else -1.0
		runner.info("  %s · %s · %s · %s → %s (%d) · %s %s (%s)" % [r["item"], r["track"], ItemUpgrades.QTY[r["q"]], str(snappedf(r["base"], 0.0001)), str(snappedf(r["max"], 0.0001)), r["levels"], r["next"], str(snappedf(nb, 0.0001)), "%.2f" % ratio if nb > 0 else "—"])
		if nb > 0.0 and r["base"] < nb and r["max"] > nb * (1.0 + slack) + 1e-9:
			over.append("%s %s %.2f" % [r["item"], r["q"], ratio])
		if r["levels"] < 1:
			each_track.append("%s:%s" % [r["item"], r["track"]])
	runner.check(over.is_empty() and rows.size() > 40, "§13 fully upgraded, no item passes the next item's base by more than %d %% on what a track improves (%d rows) %s" % [int(slack * 100.0), rows.size(), str(over)])
	runner.check(each_track.is_empty(), "§13 …every track has a level for sale %s" % str(each_track))
	# About the next item's base, where the next item is the same kind of tool: bare hands → small
	# shovel → standard shovel; scraper → large scraper (load, fill speed, throw).
	var near := []
	for pair in [["hands", "capacity"], ["hands", "fill"], ["small_shovel", "capacity"], ["small_shovel", "fill"], ["small_shovel", "throw"],
			["snow_scraper", "capacity"], ["snow_scraper", "fill"], ["snow_scraper", "throw"], ["wide_pusher", "throw"], ["wide_pusher", "push_strength"]]:
		for r in rows:
			if String(r["item"]) == pair[0] and r["q"] == pair[1]:
				var ratio: float = r["max"] / r["next_base"]
				if ratio < 0.85 or ratio > 1.0 + slack:
					near.append("%s %s %.2f" % [pair[0], pair[1], ratio])
	runner.check(near.is_empty(), "§13 …and reaches about it (within 85 %%–%d %%) where the next item is the same kind of tool %s" % [int(100.0 + slack * 100.0), str(near)])
	# The levels past the ladder are the old global levels' only (carried over, never sold).
	var past := 0
	for item in ItemUpgrades.items():
		for t in ItemUpgrades.tracks(item):
			past += ItemUpgrades.ids(item, t).size() - ItemUpgrades.max_level(item, t)
	runner.info("§13 levels kept for old saves past the ladder: %d (small shovel capacity 2 / throw 2, wide pusher capacity 2 / throw 2, scraper throw 2)" % past)
	runner.check(past == 5, "§13 five levels exist past the ladder, for old saves only (%d)" % past)
	# Full-upgrade cost against the next item's price (the report's table).
	for item in ItemUpgrades.items():
		var cost := 0
		for t in ItemUpgrades.tracks(item):
			for k in range(ItemUpgrades.max_level(item, t)):
				cost += (Catalog.upgrade(StringName(ItemUpgrades.ids(item, t)[k])) as UpgradeData).price
		var nxt_i := order.find(item) + 1
		runner.info("  cost %s: %s for every level for sale; the item %s, the next %s %s" % [item, UIKit.money(cost), UIKit.money(Economy.price_of(String(item))), order[nxt_i] if nxt_i < order.size() else "—", UIKit.money(Economy.price_of(String(order[nxt_i]))) if nxt_i < order.size() else ""])


## The Upgrades app: grouped by item, the items you own first (each card with its own icon — the
## mitten for bare hands — and a row per track), then the other items, then clothing, weather and
## property; Buy orders the next level; a level carried over past the ladder shows as the top;
## Fun Mode has no heated cab; it fits and lines up at every resolution.
func test_s13_upgrades_app() -> void:
	await _s3_world("survival")
	Game.money = 99999
	Game.company_name = "W".repeat(Game.COMPANY_NAME_MAX)
	Game.slots = ["standard_shovel", "", "", ""]
	Game.machines.append({"uid": Game.uid(), "tool": "small_blower", "pos": Vector3(40, 0, 96), "yaw": 0.0})
	Game.vehicles.append({"uid": Game.uid(), "id": "atv_blade", "pos": Vector3(44, 0, 96), "yaw": 0.0, "snow": 0.0})
	Game.grant_upgrade(&"shovel_capacity_2")   # an old global level: carried over to every hand tool
	Game.grant_upgrade(&"shovel_capacity_1")
	Economy.buy(ItemUpgrades.level_id(&"standard_shovel", &"throw", 1))   # one on order
	world.open_computer()
	await _tree().process_frame
	var comp: ComputerUI = world.modal
	comp._open_app(ComputerUI.app_index("upgrades"))
	await _tree().process_frame
	var kids := comp.content.get_children()
	var heads := kids.filter(func(n): return n is Label).map(func(n): return (n as Label).text)
	var cards := kids.filter(func(n): return n.has_meta("upgrade_item")).map(func(n): return str(n.get_meta("upgrade_item")))
	var want_cards := ["hands", "small_shovel", "standard_shovel", "small_blower", "pickup", "atv_blade"]
	var i_yours := heads.find("Your items")
	var i_other := heads.find("Other items")
	# §13b: the clothing is the insulated coat now (the Equipment store): no Cold protection section.
	runner.check(cards == want_cards and i_yours >= 0 and i_other > i_yours and heads.find("Weather technology") > i_other and heads.find("Property") > i_other and not heads.has("Cold protection"),
		"§13 the Upgrades app: your items first, a card each in the ladder's order %s, then the other items, then weather and property" % str(cards))
	var first_other := kids.find(kids.filter(func(n): return n is Label and (n as Label).text == "Other items")[0])
	runner.check(kids.find(_s13_card(comp, "atv_blade")) < first_other, "§13 …every owned item's card comes before the other items")
	# Each card: the item's own icon (the mitten for bare hands; vehicles none) and its tracks.
	var bad := []
	for item in want_cards:
		var card: Node = _s13_card(comp, item)
		var icons := _s6_icons(card)
		var want_icon := ComputerUI._item_icon(StringName(item))
		if (want_icon == "-" and not icons.is_empty()) or (want_icon != "-" and (icons.size() != 1 or (icons[0] as Icons).tool_id != ComputerUI._icon_id(want_icon))):
			bad.append("%s icon" % item)
		var grid: GridContainer = card.find_children("*", "GridContainer", true, false)[0]
		var names := []
		for k in range(0, grid.get_child_count(), 5):
			names.append((grid.get_child(k) as Label).text)
		var want_names := []
		for member in [StringName(item)] + ([&"pickup_plow"] if item == "pickup" else []):
			for t in ItemUpgrades.tracks(member):
				want_names.append(ItemUpgrades.TRACKS[t]["name"])
		if names != want_names:
			bad.append("%s rows %s" % [item, str(names)])
	runner.check(bad.is_empty(), "§13 …each card shows its item's own icon (the mitten for bare hands) and a row per track %s" % str(bad))
	var txt := _s13_text(_s13_card(comp, "small_shovel"))
	runner.check(txt.contains("Level 2 / 2") and txt.contains("Fully upgraded"), "§13 …the small shovel's capacity carried over past its ladder: \"Level 2 / 2\", fully upgraded")
	var std_txt := _s13_text(_s13_card(comp, "standard_shovel"))
	runner.check(std_txt.contains("On order."), "§13 …a level on order says so")
	runner.check(_s13_text(_s13_card(comp, "atv_blade")).contains("Heated cab"), "§13 …Survival: the ATV's heated cab")
	# Buy: the next level of bare hands' throw.
	var hands_card: Node = _s13_card(comp, "hands")
	var buys := hands_card.find_children("*", "Button", true, false).filter(func(x): return (x as Button).text == "Buy" and not (x as Button).disabled)
	await _tree().process_frame
	(buys[0] as Button).pressed.emit()
	await _tree().process_frame
	runner.check(Economy.has_open_order(ItemUpgrades.level_id(&"hands", &"throw", 1)) and comp.status_l.text.contains("Bare Hands: Throw 1"), "§13 …Buy orders the next level (\"%s\")" % comp.status_l.text)
	# Fit: every resolution, top and bottom.
	world.close_modal()
	await _tree().process_frame
	var probs := []
	for res in S7_CANVASES.keys():
		var logical: Vector2 = S7_CANVASES[res]
		var host := Control.new()
		host.size = logical
		runner.add_child(host)
		var c := ComputerUI.new()
		host.add_child(c)
		await _frames(2)
		c._open_app(ComputerUI.app_index("upgrades"))
		for k in range(4):
			await _tree().process_frame
		for p in _s7_fit_problems(c, Rect2(Vector2.ZERO, logical)):
			probs.append("%s: %s" % [res, p])
		c.scroll.scroll_vertical = int(c.content.size.y)
		for k in range(2):
			await _tree().process_frame
		for p in _s7_fit_problems(c, Rect2(Vector2.ZERO, logical)):
			probs.append("%s (scrolled): %s" % [res, p])
		host.queue_free()
		await _frames(1)
	runner.check(probs.is_empty(), "§13 …it fits and lines up at every resolution %s" % str(probs.slice(0, 8)))
	# Fun Mode: no heated cab anywhere.
	Game.mode = "fun"
	world.open_computer()
	await _tree().process_frame
	var comp2: ComputerUI = world.modal
	comp2._open_app(ComputerUI.app_index("upgrades"))
	await _tree().process_frame
	runner.check(not _s13_text(comp2.content).contains("Heated cab"), "§13 Fun Mode: no heated cab (Decision 9)")
	world.close_modal()
	await _tree().process_frame
	Game.mode = "survival"
	Game.company_name = ""
	await _unload()


## An item's card in the Upgrades app (null if none).
static func _s13_card(comp: ComputerUI, item: String) -> Node:
	for n in comp.content.get_children():
		if n.has_meta("upgrade_item") and str(n.get_meta("upgrade_item")) == item and not n.is_queued_for_deletion():
			return n
	return null


## Every label and button text under a node, joined.
static func _s13_text(n: Node) -> String:
	var out := []
	for c in n.find_children("*", "", true, false):
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append((c as Button).text)
	return " | ".join(out)


# =============================================================================
# §13b Equipment (the coat, snowshoes, the heated pad), the heated driveway and path, melting
# =============================================================================
# Equipment is its own kind of item (Equipment, Catalog.EQUIPMENT): bought in the Equipment store,
# a crate on the store's pad collected with Interact, never in a tool slot. Melting (Heating, on the
# game clock) is the new ledgered exception: Snow.melted, snow + melted = before, exactly.

## A point of the player's lot (lot frame u, v) in the world.
static func _s13b_lot(u: float, v: float) -> Vector2:
	return Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, u), v)


## Buy an equipment item during store hours and collect its crate from the store's pad (Interact,
## as a player does). True once it is picked up.
func _s13b_buy_and_collect(id: String) -> bool:
	var r := Economy.buy(id)
	if not r["ok"]:
		runner.info("buy %s: %s" % [id, r["msg"]])
		return false
	await _frames(2)
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).tool_id == "crate:" + id:
			(c as ToolItem).interact(world.player)
	await _frames(1)
	return Equipment.has(id)


## Each item is bought in the Equipment store and picked up at the store like any order — its own
## kind (no id shared with a tool, vehicle or upgrade), never in a tool slot, one of each; the coat
## is sold in Survival only; the store shows the cards with their icons and keys.
func test_s13b_equipment_bought_and_collected() -> void:
	var clash := []
	for id in Catalog.EQUIPMENT.keys():
		if Catalog.tools.has(id) or Catalog.vehicles.has(id) or Catalog.upgrades.has(id) or Catalog.UTILITY.has(id):
			clash.append(id)
	runner.check(clash.is_empty() and Equipment.IDS.size() == 3 and Equipment.IDS.all(func(i): return Economy.item_kind(String(i)) == "equipment"),
		"§13b the coat, the snowshoes and the heated pad are their own kind of item (\"equipment\"), no id shared with a tool, vehicle or upgrade %s" % str(clash))
	var defaults := BalanceData.new()
	var keys := ["coat_price", "coat_cold_protection", "snowshoes_price", "snowshoes_sink", "pad_price", "pad_melt_cm_h", "heated_melt_cm_h", "melt_cost_per_m3"]
	runner.check(keys.all(func(k): return is_equal_approx(float(Catalog.balance.get(k)), float(defaults.get(k)))), "§13b the new balance values are the same in data/balance.tres and the defaults")
	await _s3_world("survival")
	Game.money = 99999
	Game.slots = ["standard_shovel", "", "", ""]
	Game.inventory_changed.emit()
	Clock.reset(Clock.at(1, 12.0))
	var slots0 := Game.slots.duplicate()
	for id in ["insulated_coat", "snowshoes", "heated_pad"]:
		runner.check(Economy.can_buy(id) == "" and Economy.price_of(id) == Equipment.price(id) and Equipment.price(id) > 0, "§13b %s: for sale ($%d)" % [id, Equipment.price(id)])
		var ok: bool = await _s13b_buy_and_collect(id)
		var o: Dictionary = Economy.orders.filter(func(x): return x["item"] == id)[0]
		runner.check(ok and o["kind"] == "equipment" and o["status"] == "collected" and Game.slots == slots0, "§13b …bought on the computer, a crate on the store's pad collected with Interact, no tool slot used")
		runner.check(Economy.can_buy(id) == "Already owned." and not Economy.buy(id)["ok"], "§13b …one of each: \"Already owned.\"")
	runner.check(Equipment.coat_worn() and Equipment.snowshoes_on() and Game.carried == "heated_pad", "§13b on pickup the coat is worn, the snowshoes are on and the pad is in your arms")
	runner.check(world.player.model.coat_on and (world.player.tools.arms.coat_sleeves as Array).all(func(n): return (n as Node3D).visible) and (world.player.tools.arms.jacket_sleeves as Array).all(func(n): return not (n as Node3D).visible),
		"§13b the coat shows on the character and on the first-person sleeves")
	# A pad crate can't be collected while your arms are full.
	Game.carried = ""
	Game.equipment.erase("heated_pad")
	world.refresh_pad()
	Game.carried = "wide_pusher"
	var e := {"uid": Game.uid(), "tool": "crate:heated_pad", "pos": Vector3(120, 0, 25), "yaw": 0.0}
	Game.items.append(e)
	var crate: ToolItem = world.spawn_item_node(e)
	crate.interact(world.player)
	await _frames(1)
	runner.check(Game.carried == "wide_pusher" and Game.items.has(e) and not Equipment.has("heated_pad"), "§13b a pad's crate stays at the store while your arms are full")
	Game.carried = ""
	crate.interact(world.player)
	await _frames(1)
	runner.check(Game.carried == "heated_pad" and not Game.items.has(e), "§13b …and is collected once they're free")
	# The store: an Equipment section, each card with its icon and the keys read from the input map.
	world.open_computer()
	await _tree().process_frame
	var comp: ComputerUI = world.modal
	comp._open_app(ComputerUI.app_index("store"))
	await _tree().process_frame
	var heads := comp.content.get_children().filter(func(n): return n is Label).map(func(n): return (n as Label).text)
	var icons := _s6_icons(comp.content).map(func(n): return (n as Icons).tool_id)
	var txt := _s13_text(comp.content)
	runner.check(heads.has("Equipment") and ["insulated_coat", "snowshoes", "heated_pad"].all(func(i): return icons.has(i)) and txt.contains("Insulated Coat") and txt.contains("Heated Snow-Melting Pad") and not txt.contains("{"),
		"§13b the Equipment store: an Equipment section, a card with its icon for each item, keys shown from the input map")
	world.close_modal()
	await _tree().process_frame
	var descs := "\n".join(Catalog.EQUIPMENT.values().map(func(x): return Settings.with_keys(x["desc"])))
	runner.check(not descs.contains("{") and descs.contains(Settings.action_label("drop")) and descs.contains(Settings.action_label("inventory")), "§13b the descriptions read their keys from the input map")
	await _unload()
	# Fun Mode: no coat (Decision 9) — not sold, and not shown even if owned.
	await _s3_world("fun")
	Game.money = 99999
	Clock.reset(Clock.at(1, 12.0))
	runner.check(Economy.can_buy("insulated_coat") == "Survival Mode only." and Economy.can_buy("snowshoes") == "" and Economy.can_buy("heated_pad") == "", "§13b Fun Mode: the coat isn't sold (\"Survival Mode only.\"); the snowshoes and the pad are")
	world.open_computer()
	await _tree().process_frame
	var comp2: ComputerUI = world.modal
	comp2._open_app(ComputerUI.app_index("store"))
	await _tree().process_frame
	var t2 := _s13_text(comp2.content)
	runner.check(not t2.contains("Insulated Coat") and t2.contains("Snowshoes"), "§13b …the Fun Mode store shows no coat")
	world.close_modal()
	await _tree().process_frame
	Game.equipment["insulated_coat"] = {}
	Game.inventory_changed.emit()
	await _frames(1)
	runner.check(not Equipment.coat_worn() and is_equal_approx(Equipment.cold_mult(), 1.0) and not world.player.model.coat_on and not (world.player.tools.arms.coat_sleeves as Array).any(func(n): return (n as Node3D).visible),
		"§13b …and a coat an old Fun save owns is neither worn nor shown (Fun Mode shows no coat)")
	await _unload()


## The coat lowers the warmth lost outdoors (and in a cold house) by its balance fraction; the old
## jacket and parka become the coat in an old save — one coat, no protection lost, one notification.
func test_s13b_the_coat() -> void:
	await _s3_world("survival")
	Weather.force(Weather.C.MODERATE, 24.0)
	var bare := Survival.outdoor_loss_per_hour()
	Equipment.collect(Equipment.COAT)
	var worn := Survival.outdoor_loss_per_hour()
	var f: float = Catalog.balance.coat_cold_protection
	runner.check(bare > 0.0 and is_equal_approx(worn, bare * (1.0 - f)), "§13b the coat: outdoor warmth loss × %.2f (%.2f → %.2f %%/h)" % [1.0 - f, bare, worn])
	Survival.in_player_house = true
	Survival.cut_power()
	Survival.house_heat = 0.0
	var cold_house := Survival.compute_rate()
	Game.equipment.erase("insulated_coat")
	var cold_house0 := Survival.compute_rate()
	Survival.in_player_house = false
	runner.check(cold_house < 0.0 and is_equal_approx(cold_house, cold_house0 * (1.0 - f)), "§13b …and in a house without heat (%.2f → %.2f %%/h)" % [cold_house0, cold_house])
	await _unload()
	# Old saves: the 2_upgrades fixture bought the Insulated Work Jacket and the Arctic Parka.
	for mode in ["fun", "survival"]:
		var path := "res://tests/fixtures/polish5/%s_2_upgrades.json" % mode
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var old_ups: Dictionary = raw["game"]["upgrades"]
		var old_mult := 1.0
		for r in Catalog.RETIRED_UPGRADE_IDS:
			if old_ups.has(String(r)):
				old_mult *= (Catalog.upgrade(r) as UpgradeData).value
		runner.check(await _load_save_file(path), "§13b %s_2_upgrades loads" % mode)
		var no_old := Catalog.RETIRED_UPGRADE_IDS.all(func(r): return not Game.has_upgrade(r))
		runner.check(old_mult < 1.0 and no_old and Equipment.has(Equipment.COAT) and is_equal_approx(Game.stat_value(&"cold_protection"), 1.0),
			"§13b %s: the jacket and the parka (×%.2f) became one insulated coat; no clothing upgrade left (no two coats)" % [mode, old_mult])
		if mode == "survival":
			runner.check(Equipment.cold_mult() <= old_mult + 1e-6, "§13b …the coat protects at least as much as they did (×%.2f ≤ ×%.2f)" % [Equipment.cold_mult(), old_mult])
		else:
			runner.check(not Equipment.coat_worn() and is_equal_approx(Equipment.cold_mult(), 1.0), "§13b …Fun Mode: owned, not worn (no cold)")
		Notify.clear()
		await _spawn_world()
		await _frames(2)
		var notes := Notify.history.filter(func(n): return str(n["text"]).begins_with("Your jacket and parka"))
		runner.check(notes.size() == (1 if mode == "survival" else 0) and world.player.model.coat_on == (mode == "survival"), "§13b …%s: %d notification, the coat %s on the character" % [mode, notes.size(), "shown" if mode == "survival" else "not shown"])
		await world._do_sleep()
		await _frames(3)
		await _unload()
		Notify.clear()
		runner.check(Saves.load_game(mode) and Equipment.has(Equipment.COAT) and Equipment.pending_note == "", "§13b …the autosave reloads with the coat, no second notification")
		await _unload()
		Saves.delete_save(mode)
	# An old jacket's crate still waiting at the store is the coat when collected.
	await _s3_world("survival")
	Game.grant_upgrade(&"clothing_1")
	runner.check(Equipment.coat_worn() and not Game.has_upgrade(&"clothing_1"), "§13b an old jacket's crate collected now is the insulated coat")
	await _unload()


## A depth of uniform snow over a patch of the front yard; the player on it facing +v (into the
## yard, away from the street), snowshoes on or off.
func _s13b_snow_patch(d: float, shoes: bool) -> Vector2:
	var spot := _s13b_lot(-9.0, 4.0)
	Snow.set_rect(Rect2(spot - Vector2(3.5, 3.5), Vector2(7.0, 14.0)), d)
	Snow.relax_until_stable()
	if shoes:
		Game.equipment["snowshoes"] = {"on": true}
	else:
		Game.equipment.erase("snowshoes")
	var pl: Player = world.player
	pl.shoe_lift = d if shoes else 0.0
	pl.teleport(Vector3(spot.x, 0.05, spot.y), 0.0)
	var into := Vector2(Layout.player_lot["inward"])
	pl.set_yaw(atan2(-into.x, -into.y))
	return spot


## Snowshoes: on or off from the Tab overview (on by default), much faster through deep snow, you
## sink in only part way, a much shallower trench (volume conserved), the hip rule from your feet,
## no roofs and no map edge, the tools as usual.
func test_s13b_snowshoes() -> void:
	await _s3_world("fun")
	var pl: Player = world.player
	var b: BalanceData = Catalog.balance
	# Speed against depth (1 s of walking, the real controls).
	var rows := []
	for d in [0.0, 0.3, 0.6, 0.85]:
		var m := []
		for shoes in [false, true]:
			_s13b_snow_patch(d, shoes)
			await _frames(30)
			var p0 := pl.global_position
			await _hold("move_forward", 60)
			m.append(Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length())
		rows.append([d, m[0], m[1]])
	runner.info("metres in 1 s, without / with snowshoes: %s" % str(rows.map(func(r): return "%.2f m: %.2f / %.2f" % r)))
	runner.check(absf(rows[0][2] - rows[0][1]) < 0.15, "§13b on bare ground snowshoes change nothing (%.2f / %.2f m)" % [rows[0][1], rows[0][2]])
	runner.check(rows[2][2] > rows[2][1] * 1.6 and rows[3][2] > rows[3][1] * 2.5 and rows[3][2] > rows[2][2] * 0.6, "§13b …in deep snow you wade much faster: 0.6 m %.2f → %.2f m/s, 0.85 m %.2f → %.2f m/s" % [rows[2][1], rows[2][2], rows[3][1], rows[3][2]])
	# The sink: a few steps onto 0.85 m of snow and stop — your feet on the snow you trod down,
	# sunk in snowshoes_sink of the depth.
	var spot := _s13b_snow_patch(0.85, true)
	await _frames(20)
	await _hold("move_forward", 30)
	await _frames(60)
	var sunk := 0.85 - pl.shoe_lift
	runner.check(absf(sunk - 0.85 * b.snowshoes_sink) < 0.03 and absf(pl.shoe_lift - Snow.depth_at(pl.global_position.x, pl.global_position.z)) < 0.01 and is_equal_approx(pl.model.position.y, pl.shoe_lift) and pl.head.position.y > Player.HEAD_H + 0.5 and pl.model.shoes_on,
		"§13b you sink in %.0f %% of the way: %.2f m of 0.85 m (balance %.2f), standing on the snow you trod down; the model and the camera with you, snowshoes on the feet" % [100.0 * sunk / 0.85, sunk, b.snowshoes_sink])
	# The trench: walk through 0.8 m with and without; volume conserved.
	var trench := []
	for shoes in [false, true]:
		var at := _s13b_snow_patch(0.8, shoes)
		await _frames(20)
		var region := Rect2(at - Vector2(3.5, 3.5), Vector2(7.0, 14.0))
		var v0 := Snow.volume_in_rect(region)
		var p0 := Vector2(pl.global_position.x, pl.global_position.z)
		await _hold("move_forward", 150 if not shoes else 60)
		var p1 := Vector2(pl.global_position.x, pl.global_position.z)
		await _frames(2)
		# The trodden depth along the track (its deepest point; the shouldered snow slumps back a little).
		var left := 0.8
		for k in range(1, 10):
			var q := p0.lerp(p1, k / 10.0)
			left = minf(left, Snow.depth_at(q.x, q.y))
		var want := maxf(0.12, 0.8 * (1.0 - b.snowshoes_sink)) if shoes else maxf(0.12, 0.8 * 0.4)
		trench.append(0.8 - left)
		Snow.relax_until_stable()
		runner.check(p0.distance_to(p1) > 0.8 and absf(left - want) < 0.04 and absf(Snow.volume_in_rect(region) - v0) < 1e-4,
			"§13b %s: the trench leaves %.2f m of 0.8 m under the feet (want %.2f), volume conserved" % ["snowshoes" if shoes else "no snowshoes", left, want])
	runner.check(trench[1] < trench[0] * 0.5, "§13b …a much shallower trench on snowshoes (%.2f m trodden vs %.2f m)" % [trench[1], trench[0]])
	# The hip rule from your feet: on 0.8 m of snow (trodden as you walk), a 1.3 m bank ahead — a wall
	# to wade into, a step up on snowshoes; a 1.7 m bank is a wall either way.
	var feet_on := 0.8 * (1.0 - b.snowshoes_sink)
	for bank in [1.3, 1.7]:
		for shoes in [false, true]:
			var sp := _s13b_snow_patch(0.8, shoes)
			var into := Vector2(Layout.player_lot["inward"])
			Snow.set_rect(Rect2(Vector2(sp.x - 3.5, sp.y + into.y * 1.5 if into.y > 0 else sp.y - 6.5), Vector2(7.0, 5.0)), bank)
			await _frames(40)
			var q0 := Vector2(pl.global_position.x, pl.global_position.z)
			await _hold("move_forward", 120)
			var went := (Vector2(pl.global_position.x, pl.global_position.z) - q0).dot(into)
			var should: bool = shoes and bank - feet_on <= CharacterModel.HIP_HEIGHT
			runner.check((went > 2.0) == should, "§13b a %.2f m bank ahead, standing on 0.8 m %s: %s (moved %.2f m in)" % [bank, "on snowshoes" if shoes else "without", "walks up onto it" if should else "a wall", went])
	# No roofs, no map edge: a 4 m drift against the front of the house and at the map's edge.
	var hi := Layout.house_info(Layout.player_lot)
	var body: Rect2 = hi["body"]
	Game.equipment["snowshoes"] = {"on": true}
	var sb: float = Layout.player_lot["setback"]
	# A drift rising from 0.3 m to 2.4 m over the 6 m up to the front wall (beside the porch).
	for k in range(24):
		var v0k := sb - 6.0 + k * 0.25
		Snow.set_rect(Layout.lot_rect_world(Layout.player_lot, Layout.gu(Layout.player_lot, -8.5), Layout.gu(Layout.player_lot, -4.0), v0k, v0k + 0.25), 0.3 + 2.1 * k / 23.0)
	var front := _s13b_lot(-6.25, sb - 7.0)
	pl.teleport(Vector3(front.x, 0.05, front.y), 0.0)
	pl.shoe_lift = 0.0
	var toward := Vector2(Layout.player_lot["inward"])
	pl.set_yaw(atan2(-toward.x, -toward.y))
	var top_feet := 0.0
	for k in range(400):
		Input.action_press("move_forward")
		await _tree().physics_frame
		top_feet = maxf(top_feet, pl.feet_y())
	Input.action_release("move_forward")
	var pp := Vector2(pl.global_position.x, pl.global_position.z)
	runner.check(top_feet > 1.0 and not body.has_point(pp) and not Buildings.indoors(pl.global_position) and pl.global_position.y < 0.5 and (pp - body.get_center()).dot(Vector2(Layout.player_lot["inward"])) < 0.0,
		"§13b up a 2.4 m drift against the house on snowshoes (feet up to %.2f m): the wall still stops you — no roofs, never inside" % top_feet)
	# The strip between the west map edge and the first lot's fence.
	Snow.set_rect(Rect2(0, 98, 3.6, 10), 3.0)
	pl.teleport(Vector3(2.8, 0.05, 103.0), 0.0)
	pl.shoe_lift = 3.0
	pl.set_yaw(PI * 0.5)    # facing -x, the map's edge
	var min_x := 8.0
	for k in range(240):
		Input.action_press("move_forward")
		await _tree().physics_frame
		min_x = minf(min_x, pl.global_position.x)
	Input.action_release("move_forward")
	runner.check(min_x < 0.8 and min_x > 0.0 and pl.feet_y() > 1.5, "§13b …and walking on 3 m of snow toward the map's edge you stop at it (x down to %.2f m, feet %.1f m up)" % [min_x, pl.feet_y()])
	# The tools as usual: scoop on snowshoes with the small shovel, the load comes out of the snow.
	var at2 := _s13b_snow_patch(0.8, true)
	Game.slots = ["small_shovel", "", "", ""]
	Game.selected = 0
	Game.inventory_changed.emit()
	await _frames(40)
	var region2 := Rect2(at2 - Vector2(3.5, 3.5), Vector2(7.0, 14.0))
	var v_before := Snow.volume_in_rect(region2)
	pl.pitch = deg_to_rad(-50.0)
	pl.head.rotation.x = pl.pitch
	var base := pl.yaw
	Input.action_press("primary")
	for k in range(90):
		pl.set_yaw(base + 0.5 * sin(k * 0.15))
		await _tree().physics_frame
	var held: float = pl.tools.load
	runner.check(held > 0.02 and absf(Snow.volume_in_rect(region2) + held - v_before) < 2e-3, "§13b the tools work as usual on snowshoes (%.0f L in the shovel, volume conserved)" % (held * 1000.0))
	Input.action_release("primary")
	await _frames(30)
	# On and off from the Tab overview: hold Tab, press Interact.
	Game.equipment.erase("snowshoes")
	Equipment.collect(Equipment.SHOES)
	runner.check(Equipment.snowshoes_on(), "§13b snowshoes are on by default once picked up")
	Input.action_press("inventory")
	await _tree().process_frame
	await _tree().process_frame
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	world._unhandled_input(ev)
	await _tree().process_frame
	var txt := _s2_texts(world.inventory_panel) if world.inventory_panel else ""
	runner.check(not Equipment.snowshoes_on() and txt.contains("Snowshoes: off"), "§13b Tab + Interact takes them off (the overview says so)")
	for k in range(12):
		await _tree().physics_frame    # the press cap (§2)
	world._unhandled_input(ev)
	await _tree().process_frame
	runner.check(Equipment.snowshoes_on(), "§13b …and puts them back on")
	Input.action_release("inventory")
	await _tree().process_frame
	await _unload()


## The heated pad, carried: put down with Drop on your own lot only (never on the street, the
## sidewalk or someone else's lot), picked up with Interact; the snow on it melts at its rate;
## it stops in a power cut; it's on the bill; it's saved with the world objects.
func test_s13b_heated_pad() -> void:
	await _s3_world("survival")
	Weather.force(Weather.C.CLEAR, 48.0)
	var pl: Player = world.player
	var b: BalanceData = Catalog.balance
	Equipment.collect(Equipment.PAD)
	await _frames(2)
	runner.check(Game.carried == "heated_pad" and world.hud.tool_name_l.text.contains("Heated Snow-Melting Pad"), "§13b the pad is carried in your arms (%s)" % world.hud.tool_name_l.text)
	var lot := Layout.player_lot
	var inward := Vector2(lot["inward"])
	var face_in := atan2(-inward.x, -inward.y)
	var spots := {"the street": [_s13b_lot(-6.0, -6.0), face_in], "the sidewalk": [_s13b_lot(-6.0, -2.6), face_in],
		"the neighbour's lot": [Layout.lot_to_world(Layout.neighbor_lot, 0.0, 4.0) - Vector2(Layout.neighbor_lot["inward"]) * Equipment.PAD_AHEAD, atan2(-Vector2(Layout.neighbor_lot["inward"]).x, -Vector2(Layout.neighbor_lot["inward"]).y)]}
	for where in spots.keys():
		var at: Vector2 = spots[where][0]
		Snow.set_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), 0.0)
		pl.teleport(Vector3(at.x, 0.05, at.y), float(spots[where][1]))
		await _frames(8)
		await _hold("drop", 2)
		runner.check(Game.carried == "heated_pad" and not Equipment.pad_placed() and pl.tools.hint != "", "§13b G on %s: refused, still carried (\"%s\")" % [where, pl.tools.hint])
	# Your own lot: down in front of you.
	var yard := _s13b_lot(-8.0, 4.0)
	Snow.set_rect(Rect2(yard - Vector2(4, 4), Vector2(8, 10)), 0.0)
	pl.teleport(Vector3(yard.x, 0.05, yard.y), face_in)
	await _frames(12)
	await _hold("drop", 2)
	await _frames(2)
	var pr := Equipment.pad_rect()
	runner.check(Equipment.pad_placed() and Game.carried == "" and world.pad_node != null and Layout.player_lot["rect"].encloses(pr) and is_equal_approx(pr.get_area(), Equipment.PAD_SIZE.x * Equipment.PAD_SIZE.y),
		"§13b G on your own lot: the pad is down in front of you (%s), a world object" % str(pr))
	# Snow on it melts at its rate (a world rate), the ledger keeps the volume exact.
	Snow.set_rect(pr, 0.5)
	Snow.relax_until_stable()
	var c := pr.get_center()
	var v0 := Snow.total_volume() + Snow.melted
	var heat0 := Economy.heat_used
	Clock.running = false
	for k in range(60):
		Clock.advance(1.0)
	var melt_cm := (0.5 - Snow.depth_at(c.x, c.y)) * 100.0
	var resid := Snow.total_volume() + Snow.melted - v0
	runner.check(absf(melt_cm - b.pad_melt_cm_h) < 0.3, "§13b in a game hour the pad melts %.1f cm of the snow on it (balance %.0f cm/h)" % [melt_cm, b.pad_melt_cm_h])
	runner.check(absf(resid) < 1e-6 and Snow.melted > 0.8, "§13b …snow + melted = before, exactly (%.10f m³; %.3f m³ melted)" % [resid, Snow.melted])
	runner.check(Economy.heat_used - heat0 > 1.0 and absf(Economy.heat_used - heat0 - Snow.melted * b.melt_cost_per_m3) < 1e-6, "§13b …and it drew power: $%.2f for the hour on the next bill ($%.2f a m³ melted)" % [Economy.heat_used - heat0, b.melt_cost_per_m3])
	# A power cut stops it.
	Survival.cut_power()
	var m1 := Snow.melted
	var h1 := Economy.heat_used
	for k in range(60):
		Clock.advance(1.0)
	runner.check(Snow.melted == m1 and Economy.heat_used == h1, "§13b a power cut stops it: nothing melts, nothing is billed")
	Survival.restore_power()
	for k in range(30):
		Clock.advance(1.0)
	runner.check(Snow.melted > m1, "§13b …and it melts again when the power is back")
	# The bill: the next hydro bill carries it.
	var used := roundi(Economy.heat_used)
	Economy._issue_bill(1)
	var bl: Dictionary = Economy.bills.filter(func(x): return int(x["month"]) == 1)[0]
	runner.check(used >= 1 and int(bl["heat"]) == used and int(bl["amount"]) == b.hydro_bill + used, "§13b the January bill: $%d hydro + $%d heating" % [b.hydro_bill, used])
	# Thrown snow on it melts too: a load dropped on the pad and the loose snow round it slumping in.
	Snow.set_rect(pr.grow(1.0), 0.0)
	Snow.deposit(c, 0.6, 0.9)
	Snow.relax_until_stable()
	var v2 := Snow.volume_in_rect(pr.grow(1.5))
	for k in range(90):
		Clock.advance(1.0)
		Snow.relax_until_stable()
	runner.check(Snow.volume_in_rect(pr.grow(1.5)) < v2 * 0.35, "§13b snow thrown on it melts away (%.3f → %.3f m³ in 1.5 game hours)" % [v2, Snow.volume_in_rect(pr.grow(1.5))])
	# Saved with the world objects → loaded where it lay.
	Game.player_pos = pl.global_position
	runner.check(Saves.save_game(), "§13b saved with the pad down")
	await _unload()
	runner.check(Saves.load_game("survival"), "§13b …loaded")
	await _spawn_world()
	await _frames(3)
	runner.check(Equipment.pad_placed() and Equipment.pad_rect() == pr and world.pad_node != null and absf(world.pad_node.global_position.x - c.x) < 0.01, "§13b …the pad lies where it was")
	# Picked up with Interact (looking at it), not while your arms are full.
	pl = world.player
	var stand := c - inward * 2.2
	pl.teleport(Vector3(stand.x, 0.05, stand.y), face_in)
	pl.pitch = deg_to_rad(-38.0)
	pl.head.rotation.x = pl.pitch
	Game.carried = "wide_pusher"
	await _frames(6)
	runner.check(pl.focus_prompt.contains("Pick up the heated pad"), "§13b looking at it: \"%s\"" % pl.focus_prompt)
	pl.try_interact()
	await _frames(2)
	runner.check(Equipment.pad_placed() and Game.carried == "wide_pusher", "§13b …not while your arms are full")
	Game.carried = ""
	await _frames(2)
	pl.try_interact()
	await _frames(2)
	runner.check(not Equipment.pad_placed() and Game.carried == "heated_pad" and world.pad_node == null, "§13b …Interact picks it up into your arms")
	Saves.delete_save("survival")
	await _unload()


## Keep the hydro bills paid (a long skip would cut the power on the 16th).
func _s13b_pay_bills() -> void:
	Game.money = maxi(Game.money, 99999)
	for bl in Economy.unpaid_bills():
		Economy.pay_bill(int(bl["month"]))


## Skip (as a sleep does) to a clock time, the bills paid on the way.
func _s13b_skip_to(t: float) -> void:
	while Clock.minutes < t - 1e-6:
		_s13b_pay_bills()
		Clock.skip(minf(t - Clock.minutes, 360.0))


## The heated driveway and heated path: Property upgrades, started at once; the two boxes melt at
## their rate — a light snowfall never reopens them, a storm does and they complete as they melt
## after it; they stop in a power cut; Bills & payments shows what they cost.
func test_s13b_heated_driveway_and_path() -> void:
	await _s3_world("survival")
	Weather.force(Weather.C.CLEAR, 3.0)
	Game.money = 99999
	var b: BalanceData = Catalog.balance
	for id in ["heated_driveway", "heated_path"]:
		var u: UpgradeData = Catalog.upgrade(StringName(id))
		runner.check(u != null and u.category == UpgradeData.Category.PROPERTY and Catalog.UPGRADE_IDS.has(StringName(id)) and Economy.can_buy(id) == "", "§13b %s: a Property upgrade ($%d)" % [id, u.price if u else 0])
		var r := Economy.buy(id)
		runner.check(r["ok"] and Game.has_upgrade(StringName(id)) and Economy.can_buy(id) == "Already owned.", "§13b …bought, at work at once")
	world.open_computer()
	await _tree().process_frame
	var comp: ComputerUI = world.modal
	comp._open_app(ComputerUI.app_index("upgrades"))
	await _tree().process_frame
	var txt := _s13_text(comp.content)
	runner.check(txt.contains("Heated Driveway") and txt.contains("Heated Path") and txt.contains("melts %.1f cm an hour" % b.heated_melt_cm_h), "§13b the Upgrades app: both in Property, with their melt rate and cost")
	world.close_modal()
	await _tree().process_frame
	var dbox := Boxes.get_box(Boxes.lot_box(Layout.player_lot, "driveway"))
	var pbox := Boxes.get_box(Boxes.lot_box(Layout.player_lot, "path"))
	for r1 in pbox["rects"]:
		Snow.set_rect(r1, 0.0)
	Boxes.measure(pbox, true)
	# The rate: 10 cm on the driveway, two game hours.
	for r2 in dbox["rects"]:
		Snow.set_rect(r2, 0.1)
	Boxes.measure(dbox, true)
	var dc: Vector2 = (dbox["rects"][0] as Rect2).get_center()
	var v0 := Snow.total_volume() + Snow.melted
	var h0 := Economy.heat_used
	var mm0 := Snow.melted
	for k in range(120):
		Clock.advance(1.0)
	var cm := (0.1 - Snow.depth_at(dc.x, dc.y)) * 100.0
	runner.check(absf(cm - 2.0 * b.heated_melt_cm_h) < 0.25 and absf(Snow.total_volume() + Snow.melted - v0) < 1e-6,
		"§13b the heated driveway melts %.2f cm in two game hours (balance %.1f cm/h); snow + melted = before, exactly" % [cm, b.heated_melt_cm_h])
	var drive_melt := 2.0 * b.heated_melt_cm_h / 100.0 * float(dbox["area"])
	runner.check(absf(Snow.melted - mm0 - drive_melt) < 0.02 and absf(Economy.heat_used - h0 - (Snow.melted - mm0) * b.melt_cost_per_m3) < 1e-6, "§13b …drawing power while it melts: $%.2f for the two hours (%.2f m³ at $%.2f; the path, bare, drew none)" % [Economy.heat_used - h0, Snow.melted - mm0, b.melt_cost_per_m3])
	# Boxes complete as they melt: measured (as the world does) until the driveway snaps.
	Clock.running = true
	var done := false
	for k in range(900):
		Clock.advance(1.0)
		Boxes.measure(dbox, true)
		if dbox["complete"]:
			done = true
			break
	Clock.running = false
	runner.check(done and Snow.volume_in_rect(dbox["rects"][0], 0.0) < 1e-6, "§13b the driveway box completes as it melts (90 %, bare)")
	for r3 in pbox["rects"]:
		Snow.set_rect(r3, 0.0)
	Boxes.measure(pbox, true)
	# A light snowfall from the schedule never reopens them (sleeping through it, as a skip does);
	# a storm does, and they complete again as they melt after it.
	var light := {}
	var storm := {}
	for i in range(Weather.events.size() - 1):
		var e: Dictionary = Weather.events[i]
		if e["start"] < Clock.minutes / 60.0 + 2.0:
			continue
		var clear_after: bool = float(Weather.events[i + 1]["start"]) - float(e["end"]) >= 3.0
		if light.is_empty() and e["tier"] == "light" and float(e["total"]) >= 4.0 and clear_after:
			light = e
		if storm.is_empty() and not light.is_empty() and e["tier"] == "storm" and float(e["start"]) > float(light["end"]):
			storm = e
	runner.check(not light.is_empty() and not storm.is_empty(), "§13b a light snowfall (%.1f cm) and a storm (%.1f cm) in the schedule" % [float(light.get("total", 0)), float(storm.get("total", 0))])
	var lawn := _s13b_lot(-8.0, 4.0)
	var reopened := []
	var on_re := func(id: String): reopened.append(id)
	Boxes.box_reopened.connect(on_re)
	await _s13b_skip_to(float(light["start"]) * 60.0 - 30.0)
	for bx in [dbox, pbox]:
		for r6 in bx["rects"]:
			Snow.set_rect(r6, 0.0)
		Boxes.measure(bx, true)
	var lawn1 := Snow.depth_at(lawn.x, lawn.y)
	reopened.clear()
	var peak := 0.0
	var t_end := float(light["end"]) * 60.0 + 60.0
	while Clock.minutes < t_end:
		_s13b_pay_bills()
		Clock.skip(30.0)
		peak = maxf(peak, Boxes.avg_depth(dbox, true))
	var fell := (Snow.depth_at(lawn.x, lawn.y) - lawn1) * 100.0
	runner.check(fell > 3.0 and not reopened.has(dbox["id"]) and not reopened.has(pbox["id"]) and dbox["complete"] and pbox["complete"] and peak < b.box_reopen_depth,
		"§13b a light snowfall (%.1f cm on the lawn): the heated driveway and path keep up — never reopened (the driveway's deepest %.1f cm)" % [fell, peak * 100.0])
	await _s13b_skip_to(float(storm["start"]) * 60.0 - 30.0)
	for bx in [dbox, pbox]:
		for r7 in bx["rects"]:
			Snow.set_rect(r7, 0.0)
		Boxes.measure(bx, true)
	reopened.clear()
	var speak := 0.0
	var lawn2 := Snow.depth_at(lawn.x, lawn.y)
	while Clock.minutes < float(storm["end"]) * 60.0:
		_s13b_pay_bills()
		Clock.skip(30.0)
		speak = maxf(speak, Boxes.avg_depth(dbox, true))
	var sfell := (Snow.depth_at(lawn.x, lawn.y) - lawn2) * 100.0
	runner.check(reopened.has(dbox["id"]) and speak > 0.03, "§13b a storm (%.1f cm on the lawn) is too much: the driveway reopens (up to %.1f cm deep)" % [sfell, speak * 100.0])
	var back := false
	for k in range(48):
		_s13b_pay_bills()
		Clock.skip(60.0)
		if dbox["complete"] and pbox["complete"]:
			back = true
			break
	Boxes.box_reopened.disconnect(on_re)
	runner.check(back, "§13b …and once it stops they melt it and complete again by themselves (during a sleep: measured hourly)")
	# A power cut stops them.
	for r4 in dbox["rects"]:
		Snow.set_rect(r4, 0.05)
	Survival.cut_power()
	var m1 := Snow.melted
	for k in range(60):
		Clock.advance(1.0)
	runner.check(Snow.melted == m1, "§13b a power cut stops them")
	Survival.restore_power()
	# Bills & payments shows the cost: the line, and the next bill.
	world.open_computer()
	await _tree().process_frame
	var comp2: ComputerUI = world.modal
	comp2._open_app(ComputerUI.app_index("bills"))
	await _tree().process_frame
	var bt := _s13_text(comp2.content)
	runner.check(bt.contains("Heating since the last bill") and bt.contains("heated driveway $") and bt.contains("heated path $"), "§13b Bills & payments: what heating used since the last bill, and each source's cost an hour")
	world.close_modal()
	await _tree().process_frame
	var used := roundi(Economy.heat_used)
	var m := Clock.month_of(Clock.day_index()) + 1
	Economy._issue_bill(m)
	var bl: Array = Economy.bills.filter(func(x): return int(x["month"]) == m)
	comp2 = null
	world.open_computer()
	await _tree().process_frame
	var comp3: ComputerUI = world.modal
	comp3._open_app(ComputerUI.app_index("bills"))
	await _tree().process_frame
	var bt2 := _s13_text(comp3.content)
	runner.check(used > 0 and not bl.is_empty() and int(bl[0]["heat"]) == used and bt2.contains("(heating %s)" % UIKit.money(used)), "§13b …the next bill: hydro + $%d heating, shown on its line" % used)
	world.close_modal()
	await _tree().process_frame
	await _unload()
	# Fun Mode: they melt too (no bills there).
	await _s3_world("fun")
	Game.upgrades["heated_driveway"] = true
	var fb := Boxes.get_box(Boxes.lot_box(Layout.player_lot, "driveway"))
	for r5 in fb["rects"]:
		Snow.set_rect(r5, 0.05)
	var fm := Snow.melted
	for k in range(60):
		Clock.advance(1.0)
	runner.check(Snow.melted > fm and Economy.heat_used == 0.0, "§13b Fun Mode: the heated driveway melts too (no hydro bill)")
	await _unload()


## Melting is ledgered: with the pad and both heated boxes at work, every snow operation run next to
## them and on them — throws, cuts, scoops, pushes, wading, the grader, the sidewalk crew,
## relaxation — keeps snow + melted = before, exactly (the tolerance of a float sum, never looser);
## without a source nothing ever melts.
func test_s13b_melting_ledger() -> void:
	await _s3_world("fun")
	Clock.running = false
	var s0 := Snow.melted
	Weather.force(Weather.C.HEAVY, 6.0, 2.0)
	for k in range(6):
		Clock.advance(30.0)
	runner.check(Snow.melted == s0 and s0 == 0.0, "§13b no heated pad, no heated box: nothing melts (ledger %.3f m³)" % Snow.melted)
	Weather.force(Weather.C.CLEAR, 48.0)
	Game.upgrades["heated_driveway"] = true
	Game.upgrades["heated_path"] = true
	var lot := Layout.player_lot
	var yard := _s13b_lot(-8.0, 4.0)
	Game.equipment["heated_pad"] = {"pos": [yard.x, 0.0, yard.y], "yaw": 0.0}
	var pr := Equipment.pad_rect()
	var dbox := Boxes.get_box(Boxes.lot_box(lot, "driveway"))
	var drv: Rect2 = dbox["rects"][0]
	Snow.sync_all()
	# The lazy snowfall keeps each chunk's share in float32 (chunk_fall) against a float64 total, so
	# a sync can add a few nm of "snowfall" that never fell (pre-existing, nothing to do with
	# melting). With the weather clear, snap the total to the chunks' value: no sync adds anything.
	Snow.fall_total = float(Snow.chunk_fall[0])
	var before := Snow.total_volume() + Snow.melted
	var worst := 0.0
	var steps := []
	var take := func(at: Vector2, vol: float) -> float:
		var cells := Snow.cells_in_obb(at, Vector2(0, 1), 1.0, 2.0)
		var bites := PackedFloat32Array()
		bites.resize(cells.size())
		bites.fill(0.3)
		return float(Snow.cut(cells, bites, 0.0, vol)["volume"])
	var ops := [
		["a throw onto the pad", func(): Snow.deposit(pr.get_center(), take.call(yard + Vector2(3.0, -1.0), 0.4), 0.7)],
		["a throw onto the driveway", func(): Snow.deposit(drv.get_center(), take.call(yard + Vector2(-2.5, -1.0), 0.3), 0.6)],
		["a cut beside the pad", func():
			var cells := Snow.cells_in_obb(pr.position - Vector2(0.6, 0), Vector2(0, 1), 0.5, 2.0)
			var bites := PackedFloat32Array()
			bites.resize(cells.size())
			bites.fill(0.2)
			var got: Dictionary = Snow.cut(cells, bites, 0.0, 1.0)
			Snow.deposit(pr.get_center(), float(got["volume"]), 0.5)],
		["a scoop off the driveway onto the lawn", func():
			var got2: Dictionary = Snow.scoop(drv.position + Vector2(1, 1), Vector2(0, 1), 0.5, 1.0, 0.2)
			Snow.deposit(yard + Vector2(2.5, 0), float(got2["volume"]), 0.5)],
		["a push across the driveway", func():
			var z := drv.position.y + 1.0
			while z < drv.end.y - 1.0:
				Snow.blade_push(Vector2(drv.get_center().x, z), Vector2(0, 1), 0.4, 0.15, 0.005, false, 0.3)
				z += 0.1],
		["wading across the pad", func():
			var p := pr.position + Vector2(-0.5, 0.5)
			for k in range(20):
				Snow.wade(p + Vector2(k * 0.15, 0.0), Vector2(1, 0), 0.26, INF, 0.4)],
		["the grader on Maple Street", func():
			Snow.grader_lane(Vector2(drv.get_center().x - 20.0, 81.05), Vector2(drv.get_center().x + 20.0, 81.05), Vector2(0, -1), 3.7, 0.02, 7)],
		["the sidewalk crew in front", func():
			var sw: Rect2 = Layout.house_info(lot)["sidewalk"]
			Snow.sidewalk_clear(sw, Vector2i(0, -1))],
		["relaxation", func(): Snow.relax_until_stable()],
	]
	# Each operation, then half an hour of melting: the operations conserve as they always have
	# (float32 cells: the existing 1e-4 m³ of the conservation tests, not loosened); what changes
	# over the melting itself is exactly what the ledger took.
	var melt_worst := 0.0
	for op in ops:
		(op[1] as Callable).call()
		var t0 := Snow.total_volume()
		var m0 := Snow.melted
		for k in range(20):
			Clock.advance(1.5)      # the pad and the boxes melt
		var mr := (Snow.total_volume() - t0) + (Snow.melted - m0)
		melt_worst = maxf(melt_worst, absf(mr))
		var r := Snow.total_volume() + Snow.melted - before
		worst = maxf(worst, absf(r))
		steps.append("%s %.9f / melt %.9f" % [op[0], r, mr])
	Snow.relax_until_stable()
	for k in range(60):
		Clock.advance(1.0)
	var final := Snow.total_volume() + Snow.melted - before
	worst = maxf(worst, absf(final))
	runner.info("ledger residual (snow + melted − before) after each, and over its melting: %s" % ", ".join(steps))
	runner.check(Snow.melted > 0.3 and worst < 1e-4, "§13b with the pad and both heated boxes melting, every operation keeps snow + melted = before (worst %.9f m³, the conservation tests' 1e-4; %.3f m³ melted)" % [worst, Snow.melted])
	runner.check(melt_worst < 1e-7, "§13b …and over the melting itself snow + melted = before exactly (worst %.10f m³: the ledger holds every m³ that melted)" % melt_worst)
	# The ledger is saved.
	var want := Snow.melted
	var d := Snow.serialize()
	Snow.melted = 0.0
	Snow.deserialize(d)
	runner.check(Snow.melted == want, "§13b …and the ledger is saved with the snow")
	Game.upgrades.erase("heated_driveway")
	Game.upgrades.erase("heated_path")
	Game.equipment.erase("heated_pad")
	await _unload()


## Melting runs on the clock: a stretch of play in small steps and the same stretch skipped (a
## sleep's 30-minute steps) run the same code (Heating.advance from Clock.advance) and melt the same.
func test_s13b_melting_in_skips_as_in_play() -> void:
	var res := []
	for skip in [false, true]:
		await _s3_world("survival")
		Clock.running = false
		Game.upgrades["heated_driveway"] = true
		var yard := _s13b_lot(-8.0, 4.0)
		Game.equipment["heated_pad"] = {"pos": [yard.x, 0.0, yard.y], "yaw": 0.0}
		var pr := Equipment.pad_rect()
		var dbox := Boxes.get_box(Boxes.lot_box(Layout.player_lot, "driveway"))
		Snow.set_rect(pr, 0.4)
		for r in dbox["rects"]:
			Snow.set_rect(r, 0.06)
		dbox["peak"] = 0.0     # the box opens on this snow (no 90 % snap within the stretch)
		Boxes.measure(dbox, true)
		Weather.force(Weather.C.CLEAR, 48.0)
		var m0 := Snow.melted
		if skip:
			Clock.skip(150.0)
		else:
			var step := 1.0 / 60.0 * Clock.GAME_MIN_PER_REAL_SEC
			var left := 150.0
			while left > 1e-9:
				Clock.advance(minf(step, left))
				left -= step
		Snow.sync_all()
		res.append({"melted": Snow.melted - m0, "pad": Snow.depth_at(pr.get_center().x, pr.get_center().y),
			"drive": Snow.depth_at((dbox["rects"][0] as Rect2).get_center().x, (dbox["rects"][0] as Rect2).get_center().y), "cost": Economy.heat_used})
		Game.upgrades.erase("heated_driveway")
		Game.equipment.erase("heated_pad")
		await _unload()
	var a: Dictionary = res[0]
	var c: Dictionary = res[1]
	# The same, up to the slice each source is still adding up (Heating.QUANTUM of depth).
	var dbox2 := Boxes.get_box(Boxes.lot_box(Layout.player_lot, "driveway"))
	var slice_v := Heating.QUANTUM * (float(dbox2["area"]) + Equipment.PAD_SIZE.x * Equipment.PAD_SIZE.y)
	var slice_cost := slice_v * Catalog.balance.melt_cost_per_m3
	runner.check(absf(float(a["melted"]) - float(c["melted"])) <= slice_v + 1e-6 and absf(float(a["pad"]) - float(c["pad"])) <= Heating.QUANTUM + 1e-4 and absf(float(a["drive"]) - float(c["drive"])) <= Heating.QUANTUM + 1e-4 and absf(float(a["cost"]) - float(c["cost"])) <= slice_cost + 0.01,
		"§13b 2.5 game hours played in frame-sized steps and slept through melt the same, up to the slice still adding up: %.4f / %.4f m³, the pad %.3f / %.3f m, the driveway %.3f / %.3f m, $%.2f / $%.2f" % [a["melted"], c["melted"], a["pad"], c["pad"], a["drive"], c["drive"], a["cost"], c["cost"]])
