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
