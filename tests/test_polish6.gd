extends RefCounted
## Polish pass 6 tests. Same harness as test_polish5.gd (the runner calls every test_* method;
## runner.check / near / info). Each section of the round adds its tests under its own header.

var runner


# =============================================================================
# §1 What round 5 never pushed
# =============================================================================

## The data generator (tools/data_gen/generate_data.gd; preloaded, so this suite never depends on
## the editor's class cache for it).
const _S1DataGen := preload("res://tools/data_gen/generate_data.gd")
## Where the §1 test writes the generator's output (removed afterwards). Never res://data/.
const S1_GEN_DIR := "user://polish6_s1_data_gen"


## Every .tres under a folder, as paths relative to it ("tools/hands.tres"), sorted.
func _s1_tres(root: String, rel := "") -> Array:
	var out := []
	var d := DirAccess.open(root.path_join(rel))
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tres"):
			out.append(rel.path_join(f) if rel != "" else f)
	for sub in d.get_directories():
		out.append_array(_s1_tres(root, rel.path_join(sub) if rel != "" else sub))
	out.sort()
	return out


func _s1_remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_s1_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


## Every stored property of a and b that differs ("name: a ≠ b"); counts the values compared in n[0].
func _s1_diff(a: Resource, b: Resource, n: Array) -> Array:
	var out := []
	for p in a.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var key: String = p["name"]
		var va = a.get(key)
		var vb = b.get(key)
		n[0] += 1
		if va is Object or vb is Object:
			var pa: String = va.resource_path if va is Resource else str(va)
			var pb: String = vb.resource_path if vb is Resource else str(vb)
			if pa != pb:
				out.append("%s: %s ≠ %s" % [key, pa, pb])
		elif typeof(va) != typeof(vb) or va != vb:
			out.append("%s: %s ≠ %s" % [key, var_to_str(va), var_to_str(vb)])
	return out


## The generator reproduces data/ value for value (polish 6 §1): run into a scratch folder, its
## files are exactly data/'s .tres files, and every stored value of each equals data/'s. A change
## to a data file goes into the generator too.
func test_s1_data_generator_reproduces_data() -> void:
	_s1_remove_tree(S1_GEN_DIR)
	var failed: int = _S1DataGen.generate(S1_GEN_DIR)
	runner.check(failed == 0, "§1 the generator saved every file (%d failed)" % failed)
	var gen := _s1_tres(S1_GEN_DIR)
	var data := _s1_tres("res://data")
	runner.check(data.size() >= 40, "§1 data/ holds %d .tres files" % data.size())
	for f in data:
		runner.check(f in gen, "§1 the generator writes data/%s" % f)
	for f in gen:
		runner.check(f in data, "§1 the generator's %s is in data/" % f)
	var n := [0]
	var bad := []
	for f in data:
		if not f in gen:
			continue
		var a: Resource = ResourceLoader.load(S1_GEN_DIR.path_join(f), "", ResourceLoader.CACHE_MODE_IGNORE)
		var b: Resource = ResourceLoader.load("res://data".path_join(f), "", ResourceLoader.CACHE_MODE_IGNORE)
		if not runner.check(a != null and b != null, "§1 %s loads (generated and data/)" % f):
			continue
		for d in _s1_diff(a, b, n):
			bad.append("%s %s" % [f, d])
	runner.check(n[0] > 900, "§1 %d values compared" % n[0])
	runner.check(bad.is_empty(), "§1 every generated value equals data/ (%d differ)%s" % [bad.size(),
		"" if bad.is_empty() else ": " + ", ".join(bad.slice(0, 8))])
	runner.info("§1 generator vs data/: %d files, %d values, %d differ" % [data.size(), n[0], bad.size()])
	_s1_remove_tree(S1_GEN_DIR)
	runner.check(not DirAccess.dir_exists_absolute(S1_GEN_DIR), "§1 the scratch folder is removed")


## data/balance.tres holds BalanceData's defaults (scripts/data/balance_data.gd), value for value:
## the two are kept in sync, and the generator writes the defaults.
func test_s1_balance_defaults_equal_data() -> void:
	var data: Resource = ResourceLoader.load("res://data/balance.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	if not runner.check(data is BalanceData, "§1 data/balance.tres loads as BalanceData"):
		return
	var n := [0]
	var bad := _s1_diff(BalanceData.new(), data, n)
	runner.check(n[0] > 100, "§1 %d balance values compared" % n[0])
	runner.check(bad.is_empty(), "§1 balance.tres equals the defaults (%d differ)%s" % [bad.size(),
		"" if bad.is_empty() else ": " + ", ".join(bad.slice(0, 8))])


## export_presets.cfg (polish 6 §1): the Windows preset exports inside the repo, to the ignored
## build/ folder, and holds no secrets (Godot keeps keys in .godot/export_credentials.cfg).
func test_s1_export_preset() -> void:
	var cfg := ConfigFile.new()
	if not runner.check(cfg.load("res://export_presets.cfg") == OK, "§1 export_presets.cfg loads"):
		return
	runner.check(cfg.get_value("preset.0", "platform", "") == "Windows Desktop", "§1 preset.0 is Windows Desktop")
	var path: String = cfg.get_value("preset.0", "export_path", "")
	runner.check(path == "build/windows/CanadianWinter.exe", "§1 export path is relative inside the repo (%s)" % path)
	var secrets := []
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			if "key" in key.to_lower() or "password" in key.to_lower() or "secret" in key.to_lower():
				secrets.append("%s/%s" % [section, key])
	runner.check(secrets.is_empty(), "§1 no key, password or secret in the preset %s" % str(secrets))
	var ignored := false
	for line in FileAccess.get_file_as_string("res://.gitignore").split("\n"):
		if line.strip_edges() == "/build/":
			ignored = true
	runner.check(ignored, "§1 .gitignore ignores /build/")


# =============================================================================
# §2 The Godot errors after pulling
# =============================================================================

## The nine class_names polish 5 added, and their scripts.
const S2_CLASSES := {
	"AddressSigns": "res://scripts/world/address_signs.gd",
	"Buildings": "res://scripts/world/buildings.gd",
	"Equipment": "res://scripts/data/equipment.gd",
	"HeatedPad": "res://scripts/world/heated_pad.gd",
	"Heating": "res://scripts/world/heating.gd",
	"ItemUpgrades": "res://scripts/data/item_upgrades.gd",
	"SidewalkCrew": "res://scripts/vehicles/sidewalk_crew.gd",
	"SpeedControl": "res://scripts/ui/speed_control.gd",
	"ToolIcons": "res://scripts/ui/tool_icons.gd",
}
## The scripts that refer to those classes through preload constants (polish 6 §2): every script
## that existed before polish 5 and names one of them (21), and the polish-5 scripts those preloads
## load that name one (4: Equipment → Buildings, Heating → Equipment, HeatedPad → Equipment and
## Heating, ToolIcons → itself). With an editor class cache from before polish 5 (a pull with an
## old .godot/), a global name the cache doesn't know is a parse error.
const S2_HARDENED := [
	"res://scripts/autoload/boxes.gd", "res://scripts/autoload/catalog.gd",
	"res://scripts/autoload/clock.gd", "res://scripts/autoload/economy.gd",
	"res://scripts/autoload/game_state.gd", "res://scripts/autoload/survival.gd",
	"res://scripts/game/game_root.gd", "res://scripts/player/player.gd",
	"res://scripts/player/tool_controller.gd", "res://scripts/tools/throw.gd",
	"res://scripts/ui/computer_ui.gd", "res://scripts/ui/icons.gd", "res://scripts/ui/panels.gd",
	"res://scripts/vehicles/vehicle.gd", "res://scripts/vehicles/walk_behind.gd",
	"res://scripts/world/house_builder.gd", "res://scripts/world/store.gd",
	"res://scripts/world/tool_item.gd", "res://scripts/world/world_builder.gd",
	"res://tests/make_fixtures.gd", "res://tests/test_systems.gd",
	"res://scripts/data/equipment.gd", "res://scripts/world/heating.gd",
	"res://scripts/world/heated_pad.gd", "res://scripts/ui/tool_icons.gd",
]
## A polish-5 class named by its global name (not a member, a node path or part of a longer name).
const S2_NAME_RE := "(?<![\\w.$%@&^])(AddressSigns|Buildings|Equipment|HeatedPad|Heating|ItemUpgrades|SidewalkCrew|SpeedControl|ToolIcons)\\b"


## A script's lines with comments and string literals blanked out and its class_name line left
## out: only code is checked (no triple-quoted strings in these files; the test checks that).
static func _s2_code(src: String) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in src.split("\n"):
		var line := raw.trim_suffix("\r")
		if line.begins_with("class_name"):
			out.append("")
			continue
		var code := ""
		var q := ""
		var i := 0
		while i < line.length():
			var c := line[i]
			if q != "":
				if c == "\\":
					i += 2
					continue
				if c == q:
					q = ""
				i += 1
				continue
			if c == "#":
				break
			if c == "\"" or c == "'":
				q = c
				code += " "
			else:
				code += c
			i += 1
		out.append(code)
	return out


## The nine polish-5 classes are where S2_CLASSES says (the global class list agrees), and a
## preload of the path is the class itself (one script, the same statics).
func test_s2_round5_class_paths() -> void:
	var by_name := {}
	for c in ProjectSettings.get_global_class_list():
		by_name[String(c["class"])] = String(c["path"])
	for k in S2_CLASSES:
		runner.check(by_name.get(k, "") == S2_CLASSES[k], "§2 %s is %s (%s)" % [k, S2_CLASSES[k], by_name.get(k, "not a global class")])
		var s := load(S2_CLASSES[k]) as Script
		runner.check(s != null and s.get_global_name() == StringName(k), "§2 %s loads as class %s" % [S2_CLASSES[k], k])
	runner.check(load(S2_CLASSES["Equipment"]) == Equipment and load(S2_CLASSES["ItemUpgrades"]) == ItemUpgrades
		and load(S2_CLASSES["ToolIcons"]) == ToolIcons, "§2 a preloaded path and the global name are the same script")


## Every script in S2_HARDENED names the polish-5 classes only through its preload constants
## (`const _Equipment := preload(…)`), and each such constant is the class at its path.
func test_s2_round5_classes_by_preload() -> void:
	var re := RegEx.create_from_string(S2_NAME_RE)
	var total := 0
	for path in S2_HARDENED:
		var src := FileAccess.get_file_as_string(path)
		if not runner.check(src != "", "§2 %s reads" % path):
			continue
		runner.check(not src.contains("\"\"\"") and not src.contains("'''"), "§2 %s has no triple-quoted string" % path)
		var lines := _s2_code(src)
		var bare := []
		for k in lines.size():
			for m in re.search_all(lines[k]):
				bare.append("%d: %s" % [k + 1, m.get_string(1)])
		runner.check(bare.is_empty(), "§2 %s names no polish-5 class by its global name %s" % [path, str(bare)])
		var consts := (load(path) as Script).get_script_constant_map()
		var n := 0
		for key in consts:
			var cls := String(key).substr(1)
			if String(key).begins_with("_") and S2_CLASSES.has(cls):
				n += 1
				var s = consts[key]
				runner.check(s is Script and s == load(S2_CLASSES[cls]) and (s as Script).get_global_name() == StringName(cls),
					"§2 %s: %s is %s" % [path.get_file(), key, S2_CLASSES[cls]])
		runner.check(n > 0, "§2 %s has a preload constant for a polish-5 class" % path)
		total += n
	runner.check(total == 40, "§2 %d preload constants in %d scripts (40 expected)" % [total, S2_HARDENED.size()])
	runner.info("§2 %d scripts, %d preload constants" % [S2_HARDENED.size(), total])



# =============================================================================
# §3 Round 5's open items
# =============================================================================

var world: Node = null

## The mid-winter save fixtures (Jan 20, made with sleeps and F1 jumps before the relaxation queue
## was saved): their street edges built up into 5–6 m cliffs, pass after pass.
const S3_MIDWINTER := [
	"res://tests/fixtures/polish5/fun_4_midwinter.json",
	"res://tests/fixtures/polish5/survival_4_midwinter.json",
	"res://tests/fixtures/polish5_v3/fun_4_midwinter.json",
	"res://tests/fixtures/polish5_v3/survival_4_midwinter.json",
]
## The four resolutions round 5 checks its screens at, as the 1080-px-high canvas each one gives
## (canvas_items, expand): 16:9 is 1920 × 1080 at any size, 21:9 2580 × 1080.
const S3_CANVASES := {"1280x720": Vector2(1920, 1080), "1920x1080": Vector2(1920, 1080),
	"2560x1440": Vector2(1920, 1080), "3440x1440": Vector2(2580, 1080)}
const S3_TOOLS := ["small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh", "electric_shovel"]


func _s3_frames(n: int) -> void:
	for i in range(n):
		await runner.get_tree().physics_frame


func _s3_spawn() -> void:
	world = load("res://scenes/game.tscn").instantiate()
	runner.add_child(world)
	await _s3_frames(3)


func _s3_unload() -> void:
	if world and is_instance_valid(world):
		runner.get_tree().paused = false
		world.queue_free()
		await runner.get_tree().process_frame
		await runner.get_tree().process_frame
	world = null


## A new game at Dec 2 `hour`, the tutorial done, the computer unlocked, the world spawned.
func _s3_world(mode := "fun", hour := 12.0) -> void:
	await _s3_unload()
	Game.force_input = true
	Game.new_game(mode, 2024)
	Game.flags["mail_read"] = true
	Game.flags["computer_unlocked"] = true
	Game.set_stage(Game.Stage.COMPLETE)
	Clock.reset(Clock.at(1, hour))
	await _s3_spawn()


## Copy a save file over the mode's save and load it as the menu's Continue does.
func _s3_load(path: String) -> bool:
	var mode := "survival" if path.get_file().begins_with("survival") else "fun"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Saves.DIR))
	for p in [Saves.path_for(mode), Saves.path_for(mode) + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(Saves.path_for(mode))) != OK:
		return false
	await _s3_unload()
	Game.force_input = true
	return Saves.load_game(mode)


## A save file's text without its "saved_at" stamp (the only thing two saves of one state differ in).
static func _s3_save_text(mode: String) -> String:
	var re := RegEx.create_from_string("\"saved_at\":\"[^\"]*\",?")
	return re.sub(FileAccess.get_file_as_string(Saves.path_for(mode)), "", true)


## The fixture's snow and boxes put back as a build before polish 6 §3 loaded them: the relaxation
## it had pending lost, nothing settled (what round 5 found).
func _s3_load_unsettled(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var snow: Dictionary = d["snow"]
	var sd := snow.duplicate()
	sd["data"] = Marshalls.base64_to_raw(str(snow.get("data", "")))
	sd["loose"] = Marshalls.base64_to_raw(str(snow.get("loose", ""))) if snow.has("loose") else PackedByteArray()
	sd["w"] = int(snow.get("w", 0))
	sd["h"] = int(snow.get("h", 0))
	sd["size"] = int(snow.get("size", 0))
	sd["fmt"] = int(snow.get("fmt", 1))
	sd.erase("relax")
	Snow.deserialize(sd)
	Boxes.deserialize(d["boxes"])
	Snow.settle_on_load = false


## Where the player's lot meets Maple Street, straight out from its middle: the last cell before
## the curb (boulevard side) and the direction to the street.
static func _s3_curb() -> Dictionary:
	var lot := Layout.player_lot
	var inward: Vector2 = lot["inward"]
	var p := Layout.lot_to_world(lot, 0.0, 0.0)
	var last := p
	for k in range(80):
		var q := p - inward * (k * 0.125)
		var i := Snow.cell_z(q.y) * Snow.W + Snow.cell_x(q.x)
		if Snow.surf[i] == Snow.S_ROAD:
			break
		last = q
	return {"at": last, "out": -inward}


## Maple Street's road cells: depth by index.
static func _s3_street_depths() -> Dictionary:
	var r: Rect2 = Layout.roads[0]["rect"]
	var out := {}
	for z in range(Snow.cell_z(r.position.y), Snow.cell_z(r.end.y - 0.01) + 1):
		for x in range(Snow.W):
			var i := z * Snow.W + x
			if Snow.surf[i] == Snow.S_ROAD:
				out[i] = Snow.depth[i]
	return out


## Maple Street in front of the player's house (12 m either side of the curb point straight out
## from the lot's middle): the tallest snow on its edge cells (the last metre at each curb), and
## the mean depth of its two lanes (1.5 m around the middle of each half, where the grader drives).
static func _s3_street_profile() -> Dictionary:
	var r: Rect2 = Layout.roads[0]["rect"]
	var cx: float = (_s3_curb()["at"] as Vector2).x
	var edge := 0.0
	var lane := 0.0
	var n := 0
	for z in range(Snow.cell_z(r.position.y), Snow.cell_z(r.end.y - 0.01) + 1):
		var zc := (z + 0.5) * Snow.CELL
		var from_edge := minf(zc - r.position.y, r.end.y - zc)
		for x in range(Snow.cell_x(cx - 12.0), Snow.cell_x(cx + 12.0) + 1):
			var d := Snow.depth[z * Snow.W + x]
			if from_edge < 1.0:
				edge = maxf(edge, d)
			elif absf(zc - (r.position.y + r.size.y * 0.25)) < 0.75 or absf(zc - (r.position.y + r.size.y * 0.75)) < 0.75:
				lane += d
				n += 1
	return {"edge": edge, "lane": lane / maxf(n, 1)}


## A shovel's scoop on the boulevard just short of the curb in front of the player's house, then
## the relaxation it queues run until nothing moves (or `cap` tiles): {tiles, far (Maple Street
## cells more than 6 m along the street from it that changed by over a cm), moved (m³ of street
## snow that changed hands), scooped (m³)}.
func _s3_scoop_by_the_street(cap: int) -> Dictionary:
	var c := _s3_curb()
	var at: Vector2 = c["at"]
	var out: Vector2 = c["out"]
	var before := _s3_street_depths()
	var r := Snow.scoop(at - out * 0.5, out, 0.46, 0.45, 0.065)
	var tiles := 0
	while Snow.relax_pending() > 0 and tiles < cap:
		tiles += Snow.process_relax(64)
	var far := 0
	var moved := 0.0
	for i in before.keys():
		var dd := absf(Snow.depth[i] - float(before[i]))
		moved += dd * Snow.CELL_AREA * 0.5
		if dd > 0.01 and absf((int(i) % Snow.W + 0.5) * Snow.CELL - at.x) > 6.0:
			far += 1
	return {"tiles": tiles, "far": far, "moved": moved, "scooped": float(r["volume"]), "done": Snow.relax_pending() == 0}


## Settling isn't saved (round 5's most important open item): a game saved right after a sleep
## lost the relaxation the city's pass had queued, so the mid-winter fixtures reload with 5–6 m
## cliffs at the street's edges that collapse along the street at the first snow work nearby.
## For each mid-winter fixture (saves from before the queue was saved):
## - as a build without the fix loaded it (the pending relaxation lost, nothing settled), a scoop
##   by the curb sets off a collapse along the street (measured over its first 20,000 tiles);
## - loaded now, it is settled once on load, and the same scoop is a local slump;
## - save → load → save is bit-exact (everything but the time stamp);
## - with relaxation pending (a scoop just made), the save holds it in its order with
##   blade_push's stream, save → load → save is still bit-exact, and the reload settles exactly as
##   the game went on without it.
func test_s3_settling_saved_midwinter_fixtures() -> void:
	for path in S3_MIDWINTER:
		var name := String(path).trim_prefix("res://tests/fixtures/")
		var mode := "survival" if String(path).get_file().begins_with("survival") else "fun"
		var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		runner.check(not (src["snow"] as Dictionary).has("relax"), "§3 %s is a save from before the relaxation queue was saved" % name)
		# As before the fix: the pending relaxation lost, nothing settled.
		await _s3_unload()
		_s3_load_unsettled(path)
		var raw := _s3_street_profile()
		var old := _s3_scoop_by_the_street(20000)
		# Loaded now: settled once.
		var t0 := Time.get_ticks_msec()
		if not runner.check(await _s3_load(path), "§3 %s loads" % name):
			continue
		var ms := Time.get_ticks_msec() - t0
		runner.check(not Snow.settle_on_load and not Snow.settling and Snow.relax_pending() == 0, "§3 %s: settled on load (%d tiles visited), nothing pending" % [name, Snow.settle_visits])
		var settled := _s3_street_profile()
		# Save → load → save.
		runner.check(Saves.save_game(), "§3 %s: saved" % name)
		var a := _s3_save_text(mode)
		runner.check(Saves.load_game(mode) and not Snow.settling and Saves.save_game(), "§3 %s: loaded (nothing to settle) and saved again" % name)
		var b := _s3_save_text(mode)
		runner.check(a == b and a.length() > 100000, "§3 %s: save → load → save is bit-exact (%d bytes)" % [name, a.length()])
		if a != b:
			_s3_first_diff(a, b)
		# The scoop by the curb, settled.
		var v0 := Snow.total_volume()
		var now := _s3_scoop_by_the_street(400000)
		runner.info("§3 %s: settling on load %d ms (%d tiles); in front of the house the street's edge %.2f m, its lanes %.2f m as saved → %.2f / %.2f m settled; a scoop by the curb (%.0f L): unsettled %s%d tiles, %d street cells changed more than 6 m away, %.1f m³ of street snow moved → settled %d tiles, %d cells, %.3f m³" % [
			name, ms, Snow.settle_visits, raw["edge"], raw["lane"], settled["edge"], settled["lane"], now["scooped"] * 1000.0, "" if old["done"] else "≥ ", old["tiles"], old["far"], old["moved"], now["tiles"], now["far"], now["moved"]])
		runner.check(raw["edge"] > 3.0 and old["far"] > 100, "§3 %s: unsettled, the street's edge stands %.1f m and a scoop by the curb collapses it along the street (%d cells more than 6 m away)" % [name, raw["edge"], old["far"]])
		runner.check(now["far"] == 0 and now["moved"] < 0.01 and now["tiles"] < float(old["tiles"]) / 10.0, "§3 %s: settled, the scoop by the curb is a local slump (%d tiles, %.4f m³ of street snow, no street cell more than 6 m away changes by a centimetre)" % [name, now["tiles"], now["moved"]])
		runner.check(absf(Snow.total_volume() + now["scooped"] - v0) < 1e-4, "§3 %s: the scoop and its slump conserve the snow" % name)
		# Relaxation pending: a scoop by the street, saved at once.
		var c := _s3_curb()
		Snow.scoop((c["at"] as Vector2) - (c["out"] as Vector2) * 0.5 + Vector2(3.0, 0.0), c["out"], 0.46, 0.45, 0.065)
		Snow.hot_mode = false
		Snow.deposit((c["at"] as Vector2) - (c["out"] as Vector2) * 2.0 - Vector2(3.0, 0.0), 0.3, 0.5)
		Snow.hot_mode = true
		Snow.push_rng.randf()
		var pending := Snow.relax_pending()
		runner.check(pending > 1 and Saves.save_game(), "§3 %s: saved with %d tiles of relaxation pending" % [name, pending])
		var want: Dictionary = Snow.serialize_pending()
		var a2 := _s3_save_text(mode)
		# The game going on without a reload…
		while Snow.relax_pending() > 0:
			Snow.process_relax(16)
		var went_on := Snow.serialize()
		# …and after one.
		runner.check(Saves.load_game(mode), "§3 %s: reloads" % name)
		var got: Dictionary = Snow.serialize_pending()
		runner.check(JSON.stringify(got) == JSON.stringify(want) and Snow.relax_pending() == pending and not Snow.settle_on_load, "§3 %s: the pending relaxation is back in its order (%d tiles, hot and cold) with blade_push's stream" % [name, Snow.relax_pending()])
		runner.check(Saves.save_game() and _s3_save_text(mode) == a2, "§3 %s: …and save → load → save is bit-exact with it pending" % name)
		while Snow.relax_pending() > 0:
			Snow.process_relax(16)
		var reloaded := Snow.serialize()
		runner.check(reloaded["data"] == went_on["data"] and reloaded["loose"] == went_on["loose"], "§3 %s: the reload settles exactly as the game went on without it (every cell's snow and loose snow)" % name)
		Saves.delete_save(mode)


## Where two save texts first differ (for a failed bit-exact check).
func _s3_first_diff(a: String, b: String) -> void:
	var n := mini(a.length(), b.length())
	for i in range(n):
		if a[i] != b[i]:
			runner.info("first difference at %d: …%s… / …%s…" % [i, a.substr(maxi(i - 80, 0), 160), b.substr(maxi(i - 80, 0), 160)])
			return
	runner.info("lengths differ: %d / %d" % [a.length(), b.length()])


## blade_push draws from its own seeded stream (Snow.push_rng): the same push from the same snow
## lands the same wherever the engine's global generator stands, and leaves that generator alone.
func test_s3_blade_push_own_stream() -> void:
	await _s3_unload()
	Game.new_game("fun", 2024)
	var at := Vector2(40.0, 120.0)
	var area := Rect2(at - Vector2(4, 4), Vector2(8, 8))
	var results := []
	for k in range(3):
		Snow.set_rect(area, 0.0)
		Snow.set_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), 0.4)
		Snow.relax_until_stable()
		Snow.push_rng.seed = Snow.PUSH_SEED + 5
		seed(k * 7919 + 3)        # the global generator somewhere else each time…
		for j in range(k * 5):
			randf()
		var g0 := randf()
		seed(k * 7919 + 3)
		for j in range(k * 5):
			randf()
		var r := Snow.blade_push(at, Vector2(0, -1), 0.6, 0.6, 0.0, false, 0.4)
		var g1 := randf()          # …and blade_push takes nothing from it
		var cells := PackedFloat32Array()
		for z in range(Snow.cell_z(area.position.y), Snow.cell_z(area.end.y)):
			for x in range(Snow.cell_x(area.position.x), Snow.cell_x(area.end.x)):
				cells.append(Snow.depth[z * Snow.W + x])
		results.append([cells, float(r["moved"])])
		runner.check(g0 == g1, "§3 run %d: blade_push leaves the global generator where it was" % k)
	runner.check(float(results[0][1]) > 0.05 and results[0][0] == results[1][0] and results[0][0] == results[2][0], "§3 the same push lands the same snow in the same cells whatever the global generator did (%.3f m³ moved)" % float(results[0][1]))
	var s0 := Snow.push_rng.state
	Snow.push_rng.randf()
	runner.check(Snow.push_rng.state != s0, "§3 the push stream moves on with each draw")
	Game.new_game("fun", 2024)
	runner.check(Snow.push_rng.state == _s3_seeded_state(Snow.PUSH_SEED + 1), "§3 a new winter seeds it (winter 1: PUSH_SEED + 1)")
	randomize()


static func _s3_seeded_state(s: int) -> int:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r.state


## The computer's Weather app at 11:14 a.m. said "Light snow … from about 10 a.m." under a clear
## sky (round 5's shot, its sky forced clear). A today card whose start time has passed while none
## of that snow is falling moves to the new expected start, the next hour; the TV and the computer
## read the same card. The schedule always snows through a system's hours, so in play no card's
## start passes without snow beyond the "about" of a time shown to the hour: checked over 5 seeds
## × winters 1–3.
func test_s3_weather_card_start_moves() -> void:
	await _s3_world("fun", 11.0 + 14.0 / 60.0)
	Clock.running = false
	var ev: Dictionary = Weather.events[0]
	runner.check(float(ev["start"]) == 34.0, "§3 the winter's first snow starts Dec 2 at 10 a.m. (%.2f)" % float(ev["start"]))
	var card: Dictionary = Weather.forecast(1)[0]
	runner.check(Weather.condition() >= Weather.C.LIGHT and str(Weather.card_text(card)["when"]).begins_with("from about 10 a.m."), "§3 11:14, snowing: \"%s\"" % Weather.card_line(card))
	Weather.force(Weather.C.CLEAR, 48.0)
	card = Weather.forecast(1)[0]
	var line := Weather.card_line(card)
	runner.check(str(Weather.card_text(card)["when"]).begins_with("from about noon"), "§3 11:14, the sky held clear: the start moves to the next hour (\"%s\")" % line)
	world.open_tv()
	await _s3_frames(2)
	var tv := _s3_texts(world.modal)
	runner.check(tv.contains("from about noon") and not tv.contains("from about 10 a.m."), "§3 the TV's today card says so")
	world.close_modal()
	await _s3_frames(2)
	world.open_computer()
	await _s3_frames(2)
	var comp := _s3_texts(world.modal)
	runner.check(comp.contains(line) and not comp.contains("from about 10 a.m."), "§3 the computer's Weather app says so")
	world.close_modal()
	Clock.reset(Clock.at(1, 12.25))
	runner.check(str(Weather.card_text(Weather.forecast(1)[0])["when"]).begins_with("from about 1 p.m."), "§3 12:15, still clear: from about 1 p.m.")
	Weather.override_cond = -1
	runner.check(str(Weather.card_text(Weather.forecast(1)[0])["when"]).begins_with("from about 10 a.m."), "§3 the sky back to the schedule: snowing since 10 a.m. as before")
	await _s3_unload()
	# In play: no today card shows a start that has passed while none of that day's snow has fallen.
	var bad := 0
	var cards := 0
	for s in [7, 2024, 31337, 555, 90210]:
		for y in [1, 2, 3]:
			Weather.generate(y, s + y * 13)
			Weather.override_cond = -1
			for e in Weather.events:
				for h in range(maxi(int(e["start"]) - 6, 0), mini(int(ceil(float(e["end"]))) + 2, Weather.HOURS)):
					@warning_ignore("integer_division")
					var day := h / 24
					var c: Dictionary = Weather.forecast_day(day, h)
					if float(c["from_h"]) < 0.0:
						continue
					cards += 1
					if roundf(float(c["from_h"])) < float(h):
						var fell := 0.0
						for hh in range(day * 24, h + 1):
							fell += Weather.rate[hh]
						if fell <= 0.0:
							bad += 1
	runner.check(cards > 5000 and bad == 0, "§3 in play no start passes without snow: %d of %d today cards (5 seeds × winters 1–3, around every system)" % [bad, cards])
	Game.new_game("fun", 2024)


static func _s3_texts(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	elif n is RichTextLabel:
		out += (n as RichTextLabel).text + "\n"
	for c in n.get_children():
		out += _s3_texts(c)
	return out


## The large scraper's store text gave its blade as 1.2 m (its push width); the blade is the
## profile's 1.0 m, and the store reads it from the profile.
func test_s3_large_scraper_text() -> void:
	var td: ToolData = Catalog.tool(&"large_scraper")
	var txt := td.store_description()
	runner.check(txt.begins_with("A 1.0 m steel blade") and not txt.contains("1.2") and not txt.contains("{"), "§3 the store text: \"%s\"" % txt.left(40))
	var w0 := td.width
	td.width = 1.25
	runner.check(td.store_description().begins_with("A 1.25 m steel blade"), "§3 …read from the profile (width 1.25 → \"%s\")" % td.store_description().left(22))
	td.width = w0
	await _s3_world("fun")
	world.open_computer()
	await _s3_frames(2)
	var comp: ComputerUI = world.modal
	comp._open_app(ComputerUI.app_index("store"))
	await _s3_frames(2)
	runner.check(_s3_texts(comp).contains(txt), "§3 the computer's store shows it")
	world.close_modal()
	await _s3_unload()


## The lowest point of a lying tool's model, in the world.
static func _s3_lowest(it: ToolItem) -> float:
	var lo := INF
	var xf := it.mesh.global_transform
	for s in range(it.mesh.mesh.get_surface_count()):
		for v in (it.mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			lo = minf(lo, (xf * v).y)
	return lo


## The newest tool of that kind lying in the world (the opening's buried shovel is a small shovel too).
func _s3_item(id: String) -> ToolItem:
	var found: ToolItem = null
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).tool_id == id and not c.is_queued_for_deletion():
			found = c
	return found


## Lower the snow over and around a lying tool so that `frac` of its sample points stand above it
## (as polish 3's test does).
static func _s3_expose(it: ToolItem, frac: float) -> void:
	var pts := it.sample_points()
	var hs := []
	for p in pts:
		hs.append(p.y)
	hs.sort()
	var n := pts.size()
	var covered := n - int(round(frac * n))
	var h := (float(hs[covered - 1]) + float(hs[covered])) * 0.5 + ToolItem.EXPOSE_TOLERANCE
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var r := Rect2(lo, hi - lo).grow(0.4)
	Snow.set_rect(r, maxf(h - Snow.ground_at(r.get_center().x, r.get_center().y), 0.0))


## Tools lying in the world floated 0.5–0.95 m (the model at a fixed 0.95 m, every tool): now each
## rests on the snow or on the ground — put down on bare ground, put down on snow, and the
## opening's buried shovel on the ground under its pile — and the 75 % exposure pickup still works.
func test_s3_tools_rest_on_snow_or_ground() -> void:
	await _s3_world("fun")
	var lot := Layout.player_lot
	var spot := Layout.lot_to_world(lot, Layout.gu(lot, -5.0), 9.0)
	for id in S3_TOOLS:
		for depth in [0.0, 0.5]:
			Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), depth)
			Snow.relax_until_stable()
			world.spawn_tool_item(id, Vector3(spot.x, 0.0, spot.y), 0.3)
			await _s3_frames(2)
			var it := _s3_item(id)
			if not runner.check(it != null, "§3 %s put down" % id):
				continue
			var surface := Snow.surface_height(spot.x, spot.y)
			var lo := _s3_lowest(it)
			runner.check(absf(lo - surface) < 0.01 and it.exposure() == 1.0 and it.can_pick_up(), "§3 %s on %s: rests on it (lowest point %+.3f m from the surface; it floated %.2f m), all of it showing" % [
				id, "bare ground" if depth == 0.0 else "%.1f m of snow" % depth, lo - surface, ToolItem.OLD_GRIP_Y - ToolItem.rest_height(id)])
			Game.items.erase(it.entry)
			it.queue_free()
			await _s3_frames(1)
	# The opening's shovel: on the ground under the snow and its pile; 60 % out: no; 78 %: yes.
	await _s3_unload()
	Game.force_input = true
	Game.new_game("fun", 2024)
	Clock.reset(Clock.at(0, 11.0))
	await _s3_spawn()
	var sh := _s3_item("small_shovel")
	if not runner.check(sh != null and bool(sh.entry.get("buried", false)), "§3 the opening's small shovel lies buried"):
		await _s3_unload()
		return
	var g := Snow.ground_at(sh.global_position.x, sh.global_position.z)
	runner.check(absf(_s3_lowest(sh) - g) < 0.01 and sh.exposure() < 0.05, "§3 …on the ground (lowest point %+.3f m), out of sight (%.0f %% showing)" % [_s3_lowest(sh) - g, sh.exposure() * 100.0])
	_s3_expose(sh, 0.6)
	runner.check(not sh.can_pick_up(), "§3 …60 %% showing: not yet (%.0f %%)" % (sh.exposure() * 100.0))
	_s3_expose(sh, 0.78)
	runner.check(sh.can_pick_up() and sh.exposure() >= ToolItem.PICKUP_EXPOSURE, "§3 …78 %% showing: it can be picked up (%.0f %%)" % (sh.exposure() * 100.0))
	await _s3_unload()
	# A save from before (no relaxation queue in it): a tool that was put down on deep snow lay on
	# the ground under it; loaded now it lies on top, and the buried shovel stays buried.
	var path := "res://tests/fixtures/polish5_v3/fun_3_vehicle.json"
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var yard := Layout.lot_to_world(lot, Layout.gu(lot, -5.0), 9.0)
	(d["game"]["items"] as Array).append({"uid": 9999, "tool": "standard_shovel", "pos": [yard.x, 0.0, yard.y], "yaw": 0.3})
	var f := FileAccess.open("user://polish6_s3_old_items.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	runner.check(await _s3_load("user://polish6_s3_old_items.json"), "§3 an older save with a tool put down on the snow loads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://polish6_s3_old_items.json"))
	var dropped: Dictionary = {}
	var buried: Dictionary = {}
	for it in Game.items:
		if int(it.get("uid", 0)) == 9999:
			dropped = it
		elif bool(it.get("buried", false)):
			buried = it
	var surf := Snow.surface_height(yard.x, yard.y)
	runner.check(not dropped.is_empty() and surf > 0.3 and absf((dropped["pos"] as Vector3).y - surf) < 0.002, "§3 …its tool lies on the snow (%.2f m up, the snow's surface %.2f m)" % [(dropped.get("pos", Vector3.ZERO) as Vector3).y, surf])
	runner.check(not buried.is_empty() and (buried["pos"] as Vector3).y == 0.0, "§3 …and the buried shovel is still on the ground under it")
	Saves.delete_save("fun")


## A text's box on screen, drawn with draw_string at `baseline` (its left end).
static func _s3_text_rect(font: Font, text: String, fs: int, baseline: Vector2) -> Rect2:
	return Rect2(baseline - Vector2(0, font.get_ascent(fs)), font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs))


## What the map draws at canvas `vs` around its edges (MapUI._draw's geometry): its frame, the
## grid's column letters and row numbers, the legend column.
static func _s3_map_rects(m: MapUI, vs: Vector2) -> Array:
	m.labels(vs)
	var out := []
	var map_r := Rect2(m.origin, Vector2(Layout.MAP_W, Layout.MAP_D) * m.scale_px)
	out.append(["the map", map_r.grow(10)])
	var font := m._font()
	var cols := "ABCDEFGHIJKL"
	for i in range(12):
		var x := m.origin.x + i * 16.0 * m.scale_px
		out.append(["column %s" % cols[i], _s3_text_rect(font, cols[i], 16, Vector2(x + 16.0 * m.scale_px * 0.5 - 5, map_r.position.y - 16))])
	for j in range(14):
		var y := m.origin.y + j * 16.0 * m.scale_px
		out.append(["row %d" % (j + 1), _s3_text_rect(font, str(j + 1), 16, Vector2(map_r.position.x - 34, y + 16.0 * m.scale_px * 0.5 + 6))])
	var ly := map_r.position.y + 90.0
	out.append(["the legend", Rect2(map_r.end.x + 40, ly - 24, 460, vs.y - (ly - 24))])
	return out


## The fast-forward control covered the map's column letters A–B. With the map open it sits under
## the clock (its note wrapped to the buttons' width), and at each of the four resolutions it
## overlaps nothing — on foot (the box line at its longest), at the computer, the map, the TV, the
## letter and the photo — with the longest note it shows, and stays on the screen.
func test_s3_ff_control_overlaps_nothing() -> void:
	await _s3_world("fun")
	Clock.running = true
	Weather.force(Weather.C.CLEAR, 48.0)
	await _s3_frames(80)          # the world fades in (the control shows after it)
	var sc: SpeedControl = world.speed_ctrl
	var hud: HUD = world.hud
	var here: Vector2 = hud.get_global_rect().size
	runner.info("§3 the HUD's canvas in this run: %s" % str(here))
	# The longest box line: any box as one of your jobs, with the longest due time
	# (Contracts.due_text while the snow is still falling).
	var longest := ""
	var font := hud.contract_l.get_theme_font("font")
	var fs := hud.contract_l.get_theme_font_size("font_size")
	for b in Boxes.boxes:
		var l := "Your contract · %s — %s 100%% · due 9 p.m. the day after the snow stops" % [b["place"], b["name"]]
		if font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > font.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x:
			longest = l
	var kinds := ["foot", "foot, the longest box line", "computer", "map", "tv", "letter", "photo"]
	var bad := []
	for kind in kinds:
		match kind:
			"foot, the longest box line":
				hud._t = 1e9          # the HUD keeps the line (its 0.2 s refresh off)
				hud.contract_l.text = longest
				hud._fit_contract_panel()
				hud.contract_panel.visible = true
			"computer":
				world.open_computer()
			"map":
				var m := MapUI.new()
				m.closed.connect(world.close_modal)
				world.ui.add_child(m)
				world.open_modal(m, "map")
			"tv":
				world.open_tv()
			"letter":
				world.open_mailbox()
			"photo":
				world.open_modal(Panels.photo(hud, ImageTexture.create_from_image(Image.create(12, 8, false, Image.FORMAT_RGB8))), "photo")
		await _s3_frames(3)
		sc.refused()                  # the longest note it shows
		await _s3_frames(3)
		var pr := sc.panel.get_global_rect()
		runner.check(sc.visible and sc.note_l.visible, "§3 %s: the control shows, with its note" % kind)
		var obstacles := []           # [name, rect at this run's canvas, how it moves with the canvas]
		obstacles.append(["the clock", hud.clock_panel.get_global_rect(), "left"])
		if hud.contract_panel.visible:
			obstacles.append(["the box line", hud.contract_panel.get_global_rect(), "top"])
		match kind:
			"computer":
				obstacles.append(["the computer's window", (world.modal as Node).find_child("Window", true, false).get_global_rect(), "centre"])
			"tv":
				obstacles.append(["the TV", (world.modal as Node).find_child("TV", true, false).get_global_rect(), "centre"])
			"letter":
				var lp: Control = null
				for c in (world.modal as Node).get_children():
					if c is PanelContainer:
						lp = c
				obstacles.append(["the letter", lp.get_global_rect(), "centre"])
			"photo":
				obstacles.append(["the photo", (world.modal as Node).find_child("Photo", true, false).get_global_rect(), "centre"])
		for res in S3_CANVASES.keys():
			var vs: Vector2 = S3_CANVASES[res]
			var shift := vs - here
			var rects := []
			for o in obstacles:
				var r: Rect2 = o[1]
				match o[2]:
					"top":
						r.position.x += shift.x * 0.5
					"centre":
						r.position += shift * 0.5
				rects.append([o[0], r])
			if kind == "map":
				rects.append_array(_s3_map_rects(world.modal, vs))
			if not Rect2(Vector2.ZERO, vs).encloses(pr):
				bad.append("%s %s: off the screen %s" % [res, kind, str(pr)])
			for o in rects:
				if (o[1] as Rect2).intersects(pr):
					bad.append("%s %s: over %s" % [res, kind, o[0]])
		runner.info("§3 %s: the control at %s" % [kind, str(pr)])
		if kind == "foot, the longest box line":
			runner.check(pr.position.y > hud.clock_panel.get_global_rect().end.y, "§3 the longest box line (%d px) takes the spot beside the clock: the control goes under it" % int(hud.contract_panel.size.x))
			hud._t = 0.0
		elif kind == "map":
			runner.check(absf(pr.position.x - hud.clock_panel.get_global_rect().position.x) < 1.0 and pr.position.y > hud.clock_panel.get_global_rect().end.y, "§3 with the map open it sits under the clock")
		elif kind in ["computer", "tv", "foot"]:
			runner.check(pr.position.x >= hud.clock_panel.get_global_rect().end.x and absf(pr.position.y - hud.clock_panel.get_global_rect().position.y) < 1.0, "§3 %s: beside the clock, as before" % kind)
		if world.modal != null:
			world.close_modal()
		await _s3_frames(3)
	runner.check(bad.is_empty(), "§3 at 1280×720, 1920×1080, 2560×1440 and 3440×1440 the control overlaps nothing %s" % str(bad))
	Weather.override_cond = -1
	await _s3_unload()


## Push a key's press and release to the viewport, as the keyboard does.
static func _s3_key(vp: Viewport, key: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = down
		vp.push_input(ev)


## An older save settles behind the menu's loading screen ("Settling the snow…", up to a minute
## and more). The loading screen blocks only the mouse, and the Continue button kept the keyboard
## focus, so Enter or Space started a second load that settled the save again. One start at a
## time: starting takes the focus off the menu's buttons, and a start while one is under way is
## ignored. PLAY → Fun → Continue with the keyboard on the polish5_v3 mid-winter fixture; while it
## settles, Enter and Space, and the Continue button pressed again, start nothing.
func test_s3_menu_starts_once_while_settling() -> void:
	var path := "res://tests/fixtures/polish5_v3/fun_4_midwinter.json"
	await _s3_unload()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Saves.DIR))
	for p in [Saves.path_for("fun"), Saves.path_for("fun") + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if not runner.check(DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(Saves.path_for("fun"))) == OK, "§3 menu: the mid-winter fixture is the Fun save"):
		return
	var m: Node = load("res://scenes/main_menu.tscn").instantiate()
	runner.add_child(m)
	for i in range(4):
		await runner.get_tree().process_frame
	var vp := m.get_viewport()
	var starts := []
	m.set("start_hook", func(md: String, fresh: bool): starts.append({"mode": md, "fresh": fresh, "settling": Snow.settling, "visits": Snow.settle_visits, "at": Time.get_ticks_msec()}))
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).text == "PLAY":
			(b as Button).pressed.emit()
	for i in range(2):
		await runner.get_tree().process_frame
	var cont: Button = null
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).text == "Continue" and cont == null:
			cont = b    # the Fun card's (the cards are Fun, then Survival)
	if not runner.check(cont != null and not cont.disabled, "§3 menu: Fun's Continue is offered"):
		m.queue_free()
		return
	# Continue with the keyboard: the button has the focus, Enter presses it.
	cont.grab_focus()
	_s3_key(vp, KEY_ENTER)
	var loading: Control = m.get("loading")
	runner.check(loading != null, "§3 menu: Enter on Continue starts the load (the loading screen is up)")
	var owner := vp.gui_get_focus_owner()
	runner.check(owner == null or not (owner is BaseButton), "§3 menu: no button keeps the keyboard focus behind the loading screen (%s)" % (owner.name if owner else "none"))
	var frames := 0
	while not Snow.settling and starts.is_empty() and frames < 600:
		await runner.get_tree().process_frame
		frames += 1
	var t0 := Time.get_ticks_msec()
	var label := ""
	for l in loading.find_children("*", "Label", true, false):
		label = (l as Label).text
	runner.check(Snow.settling and label == "Settling the snow…", "§3 menu: the save settles behind the loading screen (\"%s\")" % label)
	# While it settles: Tab and Down (no button takes the focus back), Enter, Space, and the button
	# pressed again (any way of reaching it).
	var visits := Snow.settle_visits
	_s3_key(vp, KEY_TAB)
	_s3_key(vp, KEY_DOWN)
	await runner.get_tree().process_frame
	owner = vp.gui_get_focus_owner()
	runner.check(owner == null or not (owner is BaseButton), "§3 menu: Tab and Down give no button the focus while it settles (%s)" % (owner.name if owner else "none"))
	_s3_key(vp, KEY_ENTER)
	await runner.get_tree().process_frame
	_s3_key(vp, KEY_SPACE)
	await runner.get_tree().process_frame
	_s3_key(vp, KEY_KP_ENTER)
	await runner.get_tree().process_frame
	cont.pressed.emit()
	# A second load would settle again from the start: the tiles visited would go back to 0.
	var last := visits
	var restarted := 0
	frames = 0
	while starts.is_empty() and frames < 1200:
		await runner.get_tree().process_frame
		frames += 1
		if Snow.settle_visits < last:
			restarted += 1
		last = Snow.settle_visits
	for i in range(30):
		await runner.get_tree().process_frame
	runner.check(restarted == 0, "§3 menu: the settle goes on where it was, never started again (%d restarts, %d → %d tiles)" % [restarted, visits, last])
	var screens := 0
	for c in (m.get("root_ui") as Node).get_children():
		if c is ColorRect and is_equal_approx((c as ColorRect).color.a, 1.0):
			screens += 1
	runner.check(m.get("loading") == loading and screens == 1, "§3 menu: one loading screen (%d)" % screens)
	runner.check(starts.size() == 1, "§3 menu: the game starts once (%d)" % starts.size())
	if not starts.is_empty():
		var s: Dictionary = starts[0]
		var ms := int(s["at"]) - t0
		runner.check(s["mode"] == "fun" and not s["fresh"] and not s["settling"] and Snow.relax_pending() == 0, "§3 menu: …from the Fun save, settled, nothing pending")
		# The rate: from the first frame that saw the settle under way (one step already done) to
		# the start.
		runner.info("§3 menu: settled %d tiles behind the loading screen; %d of them in the last %d ms (%.0f tiles/s)" % [int(s["visits"]), int(s["visits"]) - visits, ms, float(int(s["visits"]) - visits) * 1000.0 / maxf(ms, 1.0)])
	m.queue_free()
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	Saves.delete_save("fun")


# =============================================================================
# §8.1 Hold to fill, not spam-click
# =============================================================================

## Every tool §8.1 measures: bare hands, the six shovel-type tools, the electric shovel and the two
## walk-behind blowers.
const S81_TOOLS := ["hands", "small_shovel", "standard_shovel", "wide_pusher", "snow_scraper",
	"large_scraper", "snow_sleigh", "electric_shovel", "small_blower", "large_blower"]
const S81_RATES := [5.0, 10.0, 20.0, 50.0]


## The click bench (tests/click_bench.gd) on its own new game: Fun, seed 2024, Dec 1 9:00, the clock
## stopped, the player's path box.
func _s81_bench() -> Node:
	await _s3_unload()
	var bench: Node = load("res://tests/click_bench.gd").new()
	runner.add_child(bench)
	await bench.setup(runner)
	world = bench.world
	return bench


func _s81_done(bench: Node) -> void:
	bench._release_inputs()
	for a in Settings.ACTIONS.keys():
		Input.action_release(a)
	await _s3_unload()
	bench.queue_free()


func _s81_flying() -> float:
	var v := 0.0
	for c in world.get_children():
		if c is ThrownSnow and not c.is_queued_for_deletion():   # a queued one has landed
			v += (c as ThrownSnow).volume
	return v


## Every tool has a throw rhythm (ToolData.throw_recovery_s): the hand tools from bare hands' 0.5 s
## to the sleigh's 1 s; the machines' chute interval. The minimum hold is a balance value, shorter
## than any recovery, and the press cap is unchanged.
func test_s81_throw_rhythm_data() -> void:
	var lo := INF
	var hi := 0.0
	for id in S81_TOOLS:
		var t: ToolData = Catalog.tool(StringName(id))
		if not runner.check(t != null and t.throw_recovery_s > 0.0, "§8.1 %s has a throw recovery (%.2f s)" % [id, t.throw_recovery_s if t else 0.0]):
			continue
		if t.is_shovel_type():
			lo = minf(lo, t.throw_recovery_s)
			hi = maxf(hi, t.throw_recovery_s)
			runner.check(t.throw_recovery_s >= 0.5 - 1e-6 and t.throw_recovery_s <= 1.0 + 1e-6, "§8.1 %s: recovery %.2f s, between bare hands' 0.5 s and the sleigh's 1 s" % [id, t.throw_recovery_s])
	runner.check(is_equal_approx(Catalog.tool(&"hands").throw_recovery_s, lo) and is_equal_approx(Catalog.tool(&"snow_sleigh").throw_recovery_s, hi), "§8.1 bare hands recover fastest (%.2f s), the sleigh slowest (%.2f s)" % [lo, hi])
	var mh: float = Catalog.balance.min_scoop_hold_s
	runner.check(mh > 0.0 and mh < lo, "§8.1 min_scoop_hold_s %.2f s, shorter than any recovery" % mh)
	runner.check(is_equal_approx(Catalog.balance.input_max_presses_per_s, 6.0), "§8.1 the press cap stays at 6 per second")


## The Done-when table (click_bench): at 5, 10, 20 and 50 clicks per second, clicked in place and
## clicked while sweeping, every tool removes no more snow per second than holding and sweeping with
## the same tool, within noise; it never throws more often than once per throw_recovery_s; and a
## press takes nothing in its first frame beyond one frame's intake (no opening bite, no start-up
## lump). The machines are held or clicked walking through the snow.
func test_s81_clicking_never_beats_holding() -> void:
	var bench: Node = await _s81_bench()
	var secs := 12.0
	var lines := []
	for id in S81_TOOLS:
		bench.set("tool", id)
		var t: ToolData = Catalog.tool(StringName(id))
		var rec := t.throw_recovery_s
		var hold: Dictionary
		var runs := []
		if t.is_shovel_type():
			hold = await bench.run_sweep(secs)
			for r in S81_RATES:
				runs.append(["%d/s" % int(r), await bench.run_click_primary(r, secs)])
				runs.append(["%d/s sweeping" % int(r), await bench.run_click_primary(r, secs, true)])
		else:
			hold = await bench.run_machine(0.0, secs * 0.6)
			for r in S81_RATES:
				runs.append(["%d/s" % int(r), await bench.run_machine(r, secs * 0.6)])
		var r_hold: float = hold["removed"] / hold["secs"]
		var m_hold: float = hold["moved"] / hold["secs"]
		var worst := 0.0
		var line := "%s: hold %.4f m3/s" % [id, r_hold]
		for e in runs:
			var d: Dictionary = e[1]
			# Snow still in the tool at the end was never put anywhere: not counted as removed.
			var r: float = (d["removed"] - d.get("load_left", 0.0)) / d["secs"]
			worst = maxf(worst, r)
			line += ", %s %.4f" % [e[0], r]
			runner.check(r <= r_hold * 1.05 + 0.002, "§8.1 %s clicked at %s removes no more than holding and sweeping (%.4f vs %.4f m3/s)" % [id, e[0], r, r_hold])
			runner.check(d["moved"] / d["secs"] <= m_hold * 1.05 + 0.001, "§8.1 %s clicked at %s takes in no more than holding (%.4f vs %.4f m3/s)" % [id, e[0], d["moved"] / d["secs"], m_hold])
			var gap: float = d["throw_gap"]
			runner.check(gap < 0.0 or gap >= rec - 1.0 / 60.0 - 1e-4, "§8.1 %s clicked at %s: throws at least %.2f s apart (shortest gap %.3f s, %d throws)" % [id, e[0], rec, gap, d["throws"]])
			runner.check(float(d["throws_1s"]) <= ceilf(1.0 / rec) + 1e-6, "§8.1 %s clicked at %s: at most %d throws in any second (%d)" % [id, e[0], int(ceilf(1.0 / rec)), d["throws_1s"]])
			var one_frame := (t.rate if not t.is_shovel_type() else 0.0) / 60.0
			if int(d["registered"]) > 0:
				runner.check(float(d["press_bite"]) / int(d["registered"]) <= one_frame * 1.01 + 1e-6, "§8.1 %s clicked at %s: a press's first frame takes %.2f L (one frame's intake: %.2f L)" % [id, e[0], float(d["press_bite"]) / int(d["registered"]) * 1000.0, one_frame * 1000.0])
		line += " (worst x%.2f)" % (worst / maxf(r_hold, 1e-6))
		lines.append(line)
		var hgap: float = hold["throw_gap"]
		runner.check(hgap < 0.0 or hgap >= rec - 1.0 / 60.0 - 1e-4, "§8.1 %s held: throws at least %.2f s apart (%.3f s)" % [id, rec, hgap])
	for l in lines:
		runner.info("§8.1 " + l)
	bench.set("tool", "hands")
	await _s81_done(bench)


## The scoop's rules with bare hands and a standard shovel, in the clicking bot's stance (on the path,
## facing the lawn, looking down at the snow by the feet):
## - a press without movement, released before one cycle_time, removes no snow (no opening bite);
##   held still, the first bite comes after one full cycle, not on the press;
## - after a throw, a press and release inside the recovery throws nothing, loses nothing, and isn't
##   queued;
## - a release sooner than min_scoop_hold_s after its press throws nothing and the load stays; the
##   next press goes on filling it and keeps the re-cut memory;
## - a press held through the end of the recovery starts the scoop then, without a new press.
func test_s81_scoop_rules() -> void:
	var bench: Node = await _s81_bench()
	var mh: float = Catalog.balance.min_scoop_hold_s
	var mh_f := ceili(mh * 60.0)
	for id in ["hands", "standard_shovel"]:
		bench.set("tool", id)
		await bench.reset()
		var pl: Player = world.player
		var tc: ToolController = pl.tools
		var t: ToolData = Catalog.tool(StringName(id))
		var cyc_f := roundi(t.cycle_time * 60.0)
		var rec_f := roundi(t.throw_recovery_s * 60.0)
		await bench._wade_on(pl, 0.9)
		bench._face_side(pl, 1.0)
		await _s3_frames(2)
		var yaw0 := pl.yaw
		var total0 := _s81_total(tc)
		var m0 := Snow.stat_player_moved
		var th0: int = bench.get("throws")
		# Held still for one frame less than a cycle: nothing.
		Input.action_press("primary")
		await _s3_frames(cyc_f - 1)
		runner.check(tc.filling and tc.load == 0.0 and Snow.stat_player_moved == m0, "§8.1 %s: held still for %d frames (a cycle is %d), nothing is cut (%.2f L)" % [id, cyc_f - 1, cyc_f, tc.load * 1000.0])
		Input.action_release("primary")
		await _s3_frames(3)
		runner.check(tc.load == 0.0 and Snow.stat_player_moved == m0 and int(bench.get("throws")) == th0, "§8.1 %s: a press without movement, released before one cycle, removes no snow and throws nothing" % id)
		runner.near(_s81_total(tc), total0, 1e-6, "§8.1 %s: …the snow is untouched" % id)
		# Held still: the first bite comes after one full cycle; released (past the minimum hold), it
		# is thrown and the recovery starts.
		Input.action_press("primary")
		await _s3_frames(cyc_f - 1)
		var before_bite := tc.load
		await _s3_frames(3)
		runner.check(before_bite == 0.0 and tc.load > 0.0, "§8.1 %s: held still, the first bite comes after one full cycle (%.2f L after %d frames, %.2f L after %d)" % [id, before_bite * 1000.0, cyc_f - 1, tc.load * 1000.0, cyc_f + 2])
		Input.action_release("primary")
		await _s3_frames(1)
		runner.check(tc.load == 0.0 and int(bench.get("throws")) == th0 + 1 and tc.recovery > 0.0, "§8.1 %s: held %d frames (min hold %d), the release throws; recovery %.2f s left" % [id, cyc_f + 2, mh_f, tc.recovery])
		var th1: int = bench.get("throws")
		# Inside the recovery: a press and a release (longer than the minimum hold, sweeping) throw
		# nothing, lose nothing and aren't queued.
		var v_rec := _s81_total(tc)
		var hold_in := mini(mh_f + 2, rec_f - 6)
		Input.action_press("primary")
		var filled := 0
		for k in range(hold_in):
			pl.set_yaw(yaw0 + 0.3 * sin(k * 0.2))
			await _s3_frames(1)
			if tc.filling:
				filled += 1
		var rec_left := tc.recovery
		Input.action_release("primary")
		await _s3_frames(rec_f)
		pl.set_yaw(yaw0)
		runner.check(filled == 0 and rec_left > 0.0 and tc.load == 0.0 and int(bench.get("throws")) == th1, "§8.1 %s: pressed and released inside the recovery (%d frames held, %.2f s left): no scoop, no throw" % [id, hold_in, rec_left])
		runner.check(not tc.filling and not tc.get("_fill_pressed") and tc.recovery == 0.0, "§8.1 %s: …and the press isn't queued: nothing starts when the recovery ends" % id)
		await _s3_frames(90)
		runner.near(_s81_total(tc), v_rec, 2e-4, "§8.1 %s: …nothing is lost (the throw has landed)" % id)
		# A short press while sweeping: the load grows, but its release (before the minimum hold)
		# throws nothing and the load stays. The next press goes on filling it.
		var v_load := _s81_total(tc)
		Input.action_press("primary")
		for k in range(mh_f - 4):
			pl.set_yaw(yaw0 + 0.3 * sin(k * 0.2))
			await _s3_frames(1)
		var first := tc.load
		Input.action_release("primary")
		await _s3_frames(3)
		runner.check(first > 0.0 and is_equal_approx(tc.load, first) and int(bench.get("throws")) == th1 and _s81_flying() == 0.0, "§8.1 %s: released %d frames after its press (min hold %d), nothing is thrown and the load stays (%.2f L)" % [id, mh_f - 4, mh_f, tc.load * 1000.0])
		var cut_n := tc._cut_time.size()
		Input.action_press("primary")
		for k in range(mh_f - 4):
			pl.set_yaw(yaw0 - 0.3 * sin(k * 0.2))
			await _s3_frames(1)
		runner.check(cut_n > 0 and tc._cut_time.size() >= cut_n, "§8.1 %s: a new press keeps the re-cut memory (%d cells, was %d)" % [id, tc._cut_time.size(), cut_n])
		var second := tc.load
		Input.action_release("primary")
		await _s3_frames(3)
		pl.set_yaw(yaw0)
		runner.check(second > first and is_equal_approx(tc.load, second) and int(bench.get("throws")) == th1, "§8.1 %s: …the next short press goes on filling it (%.2f → %.2f L), still nothing thrown" % [id, first * 1000.0, second * 1000.0])
		runner.near(_s81_total(tc), v_load, 1e-6, "§8.1 %s: …and nothing is lost" % id)
		# Held through the end of the recovery: the scoop starts then, without a new press.
		await bench._next_spot(pl, {"side": 1.0})
		yaw0 = pl.yaw
		Input.action_press("primary")
		for k in range(mh_f + 30):
			pl.set_yaw(yaw0 + 0.3 * sin(k * 0.2))
			await _s3_frames(1)
		Input.action_release("primary")
		await _s3_frames(1)
		var th2: int = bench.get("throws")
		Input.action_press("primary")
		var started := -1
		var reg := 0
		var was := false
		for k in range(rec_f + 30):
			pl.set_yaw(yaw0 + 0.3 * sin(k * 0.2))
			await _s3_frames(1)
			if tc.get("_fill_pressed") and not was:
				reg += 1
			was = tc.get("_fill_pressed")
			if tc.filling and started < 0:
				started = k + 1
		var load3 := tc.load
		Input.action_release("primary")
		await _s3_frames(2)
		pl.set_yaw(yaw0)
		runner.check(th2 > th1 and started >= rec_f - 2 and started <= rec_f + 1 and reg == 1 and load3 > 0.0, "§8.1 %s: pressed right after a throw and held, the scoop starts when the recovery ends (frame %d of a %d-frame recovery), one press, %.1f L" % [id, started, rec_f, load3 * 1000.0])
		await _s3_frames(rec_f + 60)
	bench.set("tool", "hands")
	await _s81_done(bench)


## A pause in a sweep adds no in-place lump. The dig cycle runs while the scoop is held, but what the
## sweep took during the cycle counts toward the cycle's one bite: sweeping for more than a cycle and
## then holding still (as a mouse does where it turns back) takes nothing extra on the still frame.
## Held still for a full cycle after that, it digs in place again. The snow sleigh: it doesn't fill
## in one cycle of sweeping, so its load has room for a lump.
func test_s81_a_pause_in_a_sweep_adds_no_lump() -> void:
	var bench: Node = await _s81_bench()
	bench.set("tool", "snow_sleigh")
	await bench.reset()
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var t: ToolData = Catalog.tool(&"snow_sleigh")
	var cyc_f := roundi(t.cycle_time * 60.0)
	var one_frame: float = tc._fill_rate() / 60.0
	await bench._wade_on(pl, 0.9)
	bench._face_side(pl, 1.0)
	await _s3_frames(2)
	var yaw0 := pl.yaw
	var most_swept := 0.0
	var most_early := 0.0
	var bite_at := -1
	var bites := 0
	var bite_v := 0.0
	Input.action_press("primary")
	# A sweep with no still frame in it (a triangle wave: the aim moves every frame), past one cycle.
	for k in range(cyc_f + 4):
		var ph := k % 20
		pl.set_yaw(yaw0 + 0.02 * float(ph if ph < 10 else 20 - ph) - 0.1)
		await _s3_frames(1)
		most_swept = maxf(most_swept, tc.last_fill)
	var swept := tc.load
	# The pause: held still, a little short of two cycles (room for one bite).
	var pause_f := 2 * cyc_f - 6
	for k in range(pause_f):
		await _s3_frames(1)
		if tc.last_fill > 2.0 * one_frame:
			bites += 1
			if bite_at < 0:
				bite_at = k
				bite_v = tc.last_fill
		elif bite_at < 0:
			most_early = maxf(most_early, tc.last_fill)
	var full := tc.load >= tc._capacity() - 1e-6
	Input.action_release("primary")
	await _s3_frames(2)
	runner.check(swept > t.fill_rate * t.cycle_time * 0.4 and most_swept <= one_frame * 1.01 + 1e-6 and not full, "§8.1 sleigh: swept %d frames (a cycle is %d), %.1f L, at most %.2f L a frame (fill rate %.2f L a frame)" % [cyc_f + 4, cyc_f, swept * 1000.0, most_swept * 1000.0, one_frame * 1000.0])
	runner.check(bite_at < 0 or bite_at >= cyc_f - 2, "§8.1 sleigh: …then held still, no lump on the pause: nothing above one frame's fill until a full cycle of stillness (first bite on still frame %d of a %d-frame cycle; at most %.2f L a frame before it)" % [bite_at, cyc_f, most_early * 1000.0])
	runner.check(most_early <= one_frame * 1.01 + 1e-6, "§8.1 sleigh: …the still frames before it take at most one frame's fill (%.2f L)" % (most_early * 1000.0))
	runner.check(bite_at >= 0 and bites == 1 and bite_v <= t.fill_rate * t.cycle_time * 0.4 + 1e-6, "§8.1 sleigh: …and held still a full cycle, it digs in place again: one bite (%.1f L, at most %.1f L), %d in %d frames" % [bite_v * 1000.0, t.fill_rate * t.cycle_time * 0.4 * 1000.0, bites, pause_f])
	await _s3_frames(120)
	bench.set("tool", "hands")
	await _s81_done(bench)


## The throw rhythm across a tool switch. A press held through a recovery, then a switch from the
## standard shovel to bare hands: the recovery runs on (two tools can't alternate to beat it), the
## hands show the rest of the follow-through, and when the recovery ends the held button starts the
## hands' scoop without a new press.
func test_s81_rhythm_across_a_tool_switch() -> void:
	var bench: Node = await _s81_bench()
	bench.set("tool", "standard_shovel")
	await bench.reset()
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var mh_f := ceili(Catalog.balance.min_scoop_hold_s * 60.0)
	await bench._wade_on(pl, 0.9)
	bench._face_side(pl, 1.0)
	await _s3_frames(2)
	var yaw0 := pl.yaw
	Input.action_press("primary")
	for k in range(mh_f + 20):
		pl.set_yaw(yaw0 + 0.3 * sin(k * 0.2))
		await _s3_frames(1)
	Input.action_release("primary")
	await _s3_frames(1)
	var th0: int = bench.get("throws")
	var rec0 := tc.recovery
	runner.check(th0 > 0 and rec0 > 0.0, "§8.1 switch: the standard shovel throws (%d), recovery %.2f s" % [th0, rec0])
	# Pressed again inside the recovery and held, then switched to bare hands (slot 2 is empty).
	Input.action_press("primary")
	await _s3_frames(6)
	var rec_before := tc.recovery
	var toss_before := tc.toss_t
	runner.check(rec_before > 0.0 and not tc.filling, "§8.1 switch: pressed inside the recovery, the press waits (%.2f s left)" % rec_before)
	Game.select_slot(1)
	await _s3_frames(1)
	runner.check(tc.data.kind == ToolData.Kind.HANDS and tc.recovery > 0.0 and tc.recovery < rec_before, "§8.1 switch: on bare hands the recovery runs on (%.2f → %.2f s)" % [rec_before, tc.recovery])
	runner.check(tc.toss_t > toss_before and tc.toss_t < 1.0, "§8.1 switch: …and the hands show the rest of the follow-through (toss %.2f → %.2f)" % [toss_before, tc.toss_t])
	var rec_f := roundi(tc.recovery * 60.0)
	var started := -1
	var toss_done := -1
	var reg := 0
	var was := false
	for k in range(rec_f + 30):
		pl.set_yaw(yaw0 + 0.3 * sin(k * 0.2))
		await _s3_frames(1)
		if tc.toss_t >= 1.0 and toss_done < 0:
			toss_done = k + 1
		if tc.get("_fill_pressed") and not was:
			reg += 1
		was = tc.get("_fill_pressed")
		if tc.filling and started < 0:
			started = k + 1
	var load1 := tc.load
	Input.action_release("primary")
	await _s3_frames(2)
	pl.set_yaw(yaw0)
	runner.check(started >= rec_f - 2 and started <= rec_f + 2 and reg == 1 and load1 > 0.0, "§8.1 switch: held through, the hands' scoop starts when the recovery ends (frame %d of %d), one press, %.1f L" % [started, rec_f, load1 * 1000.0])
	runner.check(toss_done >= rec_f - 2 and toss_done <= rec_f + 2, "§8.1 switch: …and the follow-through ends with the recovery (frame %d)" % toss_done)
	runner.check(int(bench.get("throws")) == th0 + 1, "§8.1 switch: …and its release throws (%d throws)" % int(bench.get("throws")))
	await _s3_frames(90)
	bench.set("tool", "hands")
	await _s81_done(bench)


## The footprint fallback (second review fix): where a sweep's strip comes up short (shallow snow, a
## narrow trench, cells already cut) the rest of the frame's fill comes from the scoop's footprint, at
## most the opening bite's share (fill_rate × cycle_time × 0.4) a load. Each held sweep (click_bench
## run_shallow: flat snow, the aim level, so both runs sweep the same path) runs twice, once with the
## share spent after the first frame (the strip alone). Against that, the fallback adds no more than
## the share at any frame, and cuts no cell but the footprints it cut from. A stroke that goes on
## filling a kept load gets no share, so clicking can't renew it.
func test_s81_shallow_sweep_takes_no_more_than_the_opening_bite() -> void:
	var bench: Node = await _s81_bench()
	for id in ["hands", "standard_shovel", "large_scraper", "snow_sleigh"]:
		bench.set("tool", id)
		var t: ToolData = Catalog.tool(StringName(id))
		for dw in [[0.06, 0.2], [0.06, 0.07], [0.25, 0.07]]:
			var depth: float = dw[0]
			var w: float = dw[1]
			var a: Dictionary = await bench.run_shallow(depth, w)
			var b: Dictionary = await bench.run_shallow(depth, w, 60, true)
			var share: float = world.player.tools._fill_rate() * t.cycle_time * 0.4
			var most := 0.0
			var least := INF
			var ma: Dictionary = a["marks"]
			var mb: Dictionary = b["marks"]
			for f in ma.keys():
				most = maxf(most, float(ma[f]) - float(mb[f]))
				least = minf(least, float(ma[f]) - float(mb[f]))
			var outside := 0
			var foot: PackedInt32Array = a["foot"]
			for c in a["cut"]:
				if not (c in b["cut"]) and not foot.has(int(c)):
					outside += 1
			var tag := "§8.1 %s, %.2f m of snow, sweep %.2f rad/frame" % [id, depth, w]
			runner.check(is_equal_approx(float(a["foot_left"]), share), "%s: a fresh load's fallback share is the opening bite's (%.1f L)" % [tag, float(a["foot_left"]) * 1000.0])
			runner.check(most <= share + 1e-6, "%s: the fallback adds at most that share (most %.1f L over the strip alone, share %.1f L; at 60 frames %.1f vs %.1f L)" % [tag, most * 1000.0, share * 1000.0, float(ma[60]) * 1000.0, float(mb[60]) * 1000.0])
			runner.check(outside == 0, "%s: …and cuts no cell outside the strips but the scoop's footprint (%d cells cut, %d by the strip alone, %d outside)" % [tag, int(a["cells"]), int(b["cells"]), outside])
			if depth < 0.1 and w < 0.1:
				runner.check(most > 0.0, "%s: …and in shallow snow it does make up part of the share (%.1f L, least %.1f L)" % [tag, most * 1000.0, least * 1000.0])
	# A kept load: the next stroke gets no share.
	bench.set("tool", "standard_shovel")
	await bench.reset()
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	await bench._wade_on(pl, 0.9)
	bench._face_side(pl, 1.0)
	await _s3_frames(2)
	var yaw0 := pl.yaw
	var mh_f := ceili(Catalog.balance.min_scoop_hold_s * 60.0)
	Input.action_press("primary")
	for k in range(mh_f - 4):
		pl.set_yaw(yaw0 + 0.3 * sin(k * 0.2))
		await _s3_frames(1)
	Input.action_release("primary")
	await _s3_frames(3)
	var kept := tc.load
	Input.action_press("primary")
	await _s3_frames(2)
	runner.check(kept > 0.0 and tc.filling and tc.get("_foot_left") == 0.0, "§8.1 a stroke that goes on filling a kept load (%.1f L) gets no fallback share (%.1f L)" % [kept * 1000.0, float(tc.get("_foot_left")) * 1000.0])
	Input.action_release("primary")
	await _s3_frames(90)
	bench.set("tool", "hands")
	await _s81_done(bench)


## A load kept by a release sooner than min_scoop_hold_s (review fix): the landing ring follows the
## aim, as while filling (it used to stay where the last fill frame had put it).
func test_s81_kept_load_ring_follows_the_aim() -> void:
	var bench: Node = await _s81_bench()
	bench.set("tool", "standard_shovel")
	await bench.reset()
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	await bench._wade_on(pl, 0.9)
	bench._face_side(pl, 1.0)
	await _s3_frames(2)
	var yaw0 := pl.yaw
	var mh_f := ceili(Catalog.balance.min_scoop_hold_s * 60.0)
	Input.action_press("primary")
	for k in range(mh_f - 4):
		pl.set_yaw(yaw0 + 0.3 * sin(k * 0.2))
		await _s3_frames(1)
	pl.set_yaw(yaw0)
	pl.pitch = deg_to_rad(4.0)
	pl.head.rotation.x = pl.pitch
	Input.action_release("primary")
	await _s3_frames(20)
	var r0 := tc.indicator.global_position
	runner.check(tc.load > 0.0 and tc.ind_state == "landing" and tc.indicator.visible, "§8.1 kept load (%.1f L): the ring shows the landing" % (tc.load * 1000.0))
	# Turn a quarter turn back towards the path: the ring goes with the aim.
	pl.set_yaw(yaw0 - PI * 0.5)
	await _s3_frames(30)
	var r1 := tc.indicator.global_position
	var now: Dictionary = tc._landing(tc._throw_dist() * tc._pitch_factor(), tc.data.throw_angle_deg)
	var lp: Vector3 = now["pos"]
	var off := Vector2(r1.x - lp.x, r1.z - lp.z).length()
	runner.check(tc.ind_state == "landing" and Vector2(r1.x - r0.x, r1.z - r0.z).length() > 0.5 and off < 0.25, "§8.1 …turned a quarter turn, it follows: moved %.2f m, %.2f m from where a release would land now" % [Vector2(r1.x - r0.x, r1.z - r0.z).length(), off])
	# Back to the lawn: the next press, held past the minimum, throws it.
	pl.set_yaw(yaw0)
	await _s3_frames(2)
	var th0: int = bench.get("throws")
	Input.action_press("primary")
	await _s3_frames(mh_f + 4)
	Input.action_release("primary")
	await _s3_frames(2)
	runner.check(int(bench.get("throws")) == th0 + 1 and tc.load == 0.0, "§8.1 …and the next press, held past the minimum, throws it (%d throw)" % (int(bench.get("throws")) - th0))
	await _s3_frames(90)
	bench.set("tool", "hands")
	await _s81_done(bench)


## The electric shovel's chute throws on its rhythm (throw_recovery_s), so a little intake can wait in
## it after a release (review fix): saving lands it with the rest of the snow in flight, and getting
## into a vehicle throws it out where it was going. Nothing is lost or left in the chute.
func test_s81_electric_chute_is_never_stranded() -> void:
	var bench: Node = await _s81_bench()
	bench.set("tool", "electric_shovel")
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var truck: Vehicle = null
	for c in world.objects.get_children():
		if c is Vehicle:
			truck = c
			break
	for how in ["save", "vehicle"]:
		await bench.reset()
		var waiting := await _s81_chute_waiting(bench, pl, tc)
		var total := _s81_total(tc) + tc._stream_acc
		runner.check(waiting > 0.0, "§8.1 electric (%s): released, %.1f L waits in the chute for its next beat" % [how, waiting * 1000.0])
		if how == "save":
			world.collect_state()
			runner.check(tc._stream_acc == 0.0 and _s81_flying() == 0.0, "§8.1 electric: saving empties the chute and lands it (%.1f L in the chute, %.1f L in flight)" % [tc._stream_acc * 1000.0, _s81_flying() * 1000.0])
			runner.near(_s81_total(tc), total, 1e-6, "§8.1 electric: …on the ground before the save is written")
		else:
			if not runner.check(truck != null, "§8.1 electric: a vehicle to get into"):
				continue
			truck.enter_vehicle(pl)
			await _s3_frames(1)
			runner.check(pl.state == "vehicle" and tc._stream_acc == 0.0, "§8.1 electric: getting into the %s throws what the chute held (%.1f L left in it)" % [truck.data.id, tc._stream_acc * 1000.0])
			runner.near(_s81_total(tc), total, 1e-6, "§8.1 electric: …nothing lost (%.1f L in flight)" % (_s81_flying() * 1000.0))
			await _s3_frames(120)
			truck.exit_vehicle()
			await _s3_frames(2)
			runner.near(_s81_total(tc), total, 1e-6, "§8.1 electric: …and it has landed")
	bench.set("tool", "hands")
	await _s81_done(bench)


## Hold the electric shovel strafing along the path facing the lawn (click_bench's machine bot), and
## release it a few frames after a beat of its chute, so some intake waits in it for the next one:
## returns how much (m3).
func _s81_chute_waiting(bench: Node, pl: Player, tc: ToolController) -> float:
	var into: Vector2 = bench.get("into_d")
	var walk: Rect2 = bench.get("walk_r")
	var r := Vector2(-into.y, into.x)
	var w := absf(walk.size.x * r.x) + absf(walk.size.y * r.y)
	var p: Vector2 = bench.get("start_p") + into * 0.6 - r * (w * 0.5 - 0.15)
	pl.teleport(Vector3(p.x, 0.05, p.y), atan2(-r.x, -r.y))
	pl.pitch = deg_to_rad(-30.0)
	pl.head.rotation.x = pl.pitch
	await _s3_frames(3)
	var f := pl.forward2()
	var walk_key := "move_right" if Vector2(-f.y, f.x).dot(into) > 0.0 else "move_left"
	Input.action_press(walk_key)
	Input.action_press("primary")
	for k in range(180):
		await _s3_frames(1)
		var t: float = tc.get("_stream_timer")
		if k > 30 and tc._stream_acc > 0.0 and t > 0.06 and t < 0.11:
			break
	Input.action_release("primary")
	Input.action_release(walk_key)
	await _s3_frames(1)
	return tc._stream_acc


## All the snow: on the ground, on the roofs, in flight and in the tool.
func _s81_total(tc: ToolController) -> float:
	var v := Snow.total_volume() + _s81_flying() + tc.load
	for k in Snow.roof_extra.keys():
		v += float(Snow.roof_extra[k]) * 160.0
	return v


# =============================================================================
# §8.2 Loads twice as big
# =============================================================================

## The six tools that pick up and throw (Decision 1): their base capacity and fill rate double.
const S82_TOOLS := ["small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh"]
## Their round-5 profile, before §8.2 (HANDOFF §7): [capacity m³, fill rate m³/s, bite m].
const S82_ROUND5 := {
	"small_shovel": [0.05, 0.13, 0.26], "standard_shovel": [0.065, 0.16, 0.28], "wide_pusher": [0.045, 0.09, 0.15],
	"snow_scraper": [0.05, 0.1, 0.15], "large_scraper": [0.08, 0.16, 0.2], "snow_sleigh": [0.4, 0.32, 0.36]}
## §8.2's bites: raised only where the measured sweep couldn't carry about twice as much per stroke
## in snow 40 cm deep or more (report/s8_2.md); the others keep round 5's.
const S82_BITE := {
	"small_shovel": 0.4, "standard_shovel": 0.5, "wide_pusher": 0.15,
	"snow_scraper": 0.21, "large_scraper": 0.23, "snow_sleigh": 0.9}
## The tools that don't change: [capacity, fill rate, bite, intake rate] as in round 5.
const S82_SAME := {"hands": [0.03, 0.085, 0.26, 0.0], "electric_shovel": [0.03, 0.05, 0.15, 0.05],
	"small_blower": [0.03, 0.05, 0.15, 0.065], "large_blower": [0.03, 0.05, 0.15, 0.14]}
## In 40 cm of snow the grind_bench bot's sweep crosses about 90 L with the standard shovel, its bite
## (0.50) already the whole depth, so its stroke carries ×1.6 round 5's there, not ×2 (report/s8_2.md
## *Bites*): test_s82_twice_per_stroke's floor for it in 40 cm.
const S82_SWEEP_BOUND := {"standard_shovel": 1.5}
## The capacity levels for sale in round 5 (the ladder; test_s13_the_ladder's table).
const S82_LEVELS := {"hands": 2, "small_shovel": 1, "standard_shovel": 2, "wide_pusher": 1, "snow_scraper": 2,
	"large_scraper": 2, "snow_sleigh": 2}


## Decision 1 in the data: the six tools carry and fill twice as fast as in round 5 (so a full load
## fills in the same time at the fill rate), their bites are §8.2's, and bare hands, the electric
## shovel and the blowers are unchanged. Upgrades stay multiplicative on the new base, the levels for
## sale are round 5's, and fully upgraded bare hands reach about the small shovel's new base
## (their own capacity step, balance.upgrade_hands_capacity_step).
func test_s82_twice_the_load() -> void:
	var bad := []
	for id in S82_TOOLS:
		var t: ToolData = Catalog.tool(StringName(id))
		var r: Array = S82_ROUND5[id]
		if not (is_equal_approx(t.capacity, 2.0 * float(r[0])) and is_equal_approx(t.fill_rate, 2.0 * float(r[1])) and is_equal_approx(t.bite, float(S82_BITE[id]))):
			bad.append("%s %.3f m3 %.3f m3/s bite %.2f" % [id, t.capacity, t.fill_rate, t.bite])
		elif not is_equal_approx(t.capacity / t.fill_rate, float(r[0]) / float(r[1])) or t.bite < float(r[2]) - 1e-6:
			bad.append("%s fill time or bite" % id)
	runner.check(bad.is_empty(), "§8.2 the six shovel-type tools: twice round 5's capacity and fill rate (a full load fills in the same time), §8.2's bites %s" % str(bad))
	var same := []
	for id in S82_SAME.keys():
		var t: ToolData = Catalog.tool(StringName(id))
		var r: Array = S82_SAME[id]
		if not (is_equal_approx(t.capacity, float(r[0])) and is_equal_approx(t.fill_rate, float(r[1])) and is_equal_approx(t.bite, float(r[2])) and is_equal_approx(t.rate, float(r[3]))):
			same.append(id)
	runner.check(same.is_empty(), "§8.2 bare hands, the electric shovel and the blowers are unchanged %s" % str(same))
	# Upgrades: multiplicative on the new base, the same levels for sale as in round 5.
	var ups := []
	var saved := Game.upgrades.duplicate()
	var full := {}
	for id in S82_LEVELS.keys():
		var item := StringName(id)
		var n := ItemUpgrades.max_level(item, &"capacity")
		Game.upgrades = {}
		var m := 1.0
		for k in range(n):
			var lid := ItemUpgrades.level_id(item, &"capacity", k + 1)
			Game.upgrades[lid] = true
			m *= (Catalog.upgrade(StringName(lid)) as UpgradeData).value
		var got := ItemUpgrades.mult(item, &"shovel_capacity")
		full[id] = got
		if n != int(S82_LEVELS[id]) or not is_equal_approx(got, m):
			ups.append("%s %d levels ×%.3f" % [id, n, got])
		var t: ToolData = Catalog.tool(item)
		runner.info("§8.2 %s: base %.0f L, %.0f L/s; fully upgraded (%d levels) %.0f L, %.0f L/s" % [id, t.capacity * 1000.0, t.fill_rate * 1000.0, n, t.capacity * got * 1000.0, t.fill_rate * got * 1000.0])
	Game.upgrades = saved
	runner.check(ups.is_empty(), "§8.2 upgrades stay multiplicative on the new base, with round 5's levels for sale %s" % str(ups))
	var b: BalanceData = Catalog.balance
	var hands: ToolData = Catalog.tool(&"hands")
	var small: ToolData = Catalog.tool(&"small_shovel")
	var hm: float = full["hands"]
	var rc := hands.capacity * hm / small.capacity
	var rf := hands.fill_rate * hm / small.fill_rate
	runner.check(is_equal_approx(hm, b.upgrade_hands_capacity_step * b.upgrade_hands_capacity_step) and b.upgrade_hands_capacity_step > 1.25,
		"§8.2 bare hands' two capacity levels are +%d %% each (balance.upgrade_hands_capacity_step; the hand tools' levels +25 %%)" % roundi((b.upgrade_hands_capacity_step - 1.0) * 100.0))
	runner.check(rc >= 0.85 and rc <= 1.0 + b.upgrade_ladder_slack and rf >= 0.85 and rf <= 1.0 + b.upgrade_ladder_slack,
		"§8.2 …so fully upgraded bare hands carry %.0f L and fill %.0f L/s: about the small shovel's new base (%.2f and %.2f of it)" % [hands.capacity * hm * 1000.0, hands.fill_rate * hm * 1000.0, rc, rf])
	runner.check(is_equal_approx(b.upgrade_hands_capacity_step, BalanceData.new().upgrade_hands_capacity_step), "§8.2 upgrade_hands_capacity_step is the same in balance.tres and the defaults (%.2f)" % b.upgrade_hands_capacity_step)


## Set a tool's capacity, fill rate and bite (a profile: [capacity, fill rate, bite]).
static func _s82_profile(id: String, p: Array) -> void:
	var t: ToolData = Catalog.tool(StringName(id))
	t.capacity = float(p[0])
	t.fill_rate = float(p[1])
	t.bite = float(p[2])


## The widest view a player can set: the settings' largest field of view (settings_menu.gd, vertical)
## on a screen wider than 21:9. test_s82_full_load_heaps_bigger_clear_of_the_camera checks the load
## against it.
const S82_FOV_MAX := 100.0
const S82_ASPECT_MAX := 2.4


## Round 5's mound mesh: ToolController's two spheres before §8.2 turned the big one half a segment.
static func _s82_round5_mound() -> ArrayMesh:
	var kit := MeshKit.new()
	kit.sphere(Mats.snow_soft(), Transform3D(Basis().scaled(Vector3(1.2, 0.62, 1.0)), Vector3.ZERO), 0.18, 4, 8)
	kit.sphere(Mats.snow_soft(), Transform3D(Basis().scaled(Vector3(0.8, 0.5, 0.7)), Vector3(0.06, 0.06, -0.03)), 0.12, 4, 7)
	return kit.commit()


## A mesh's vertices (its own space).
static func _s82_vertices(mesh: ArrayMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for si in range(mesh.get_surface_count()):
		out.append_array(mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
	return out


## A mesh's triangles, three vertices each (its own space).
static func _s82_triangles(mesh: ArrayMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for si in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			out.append_array(vs)
		else:
			for i in idx:
				out.append(vs[i])
	return out


## Whether a mesh (its triangles, placed by xf in camera space) shows a near-plane clip on screen:
## where it passes the camera's near plane, the cut lies inside the view. The plane cuts each
## triangle that crosses it along a segment, and none may cross the near rectangle (half extents
## `half`); nor may the rectangle lie wholly inside the mesh (a ray from its centre hits it every way).
static func _s82_cuts_view(tris: PackedVector3Array, xf: Transform3D, near: float, half: Vector2) -> bool:
	var cs := PackedVector3Array()
	cs.resize(tris.size())
	for i in range(tris.size()):
		cs[i] = xf * tris[i]
	for i in range(0, cs.size(), 3):
		var cut := PackedVector2Array()
		for e in range(3):
			var a: Vector3 = cs[i + e]
			var b: Vector3 = cs[i + (e + 1) % 3]
			var da := -a.z - near
			var db := -b.z - near
			if (da < 0.0) != (db < 0.0):
				var p := a.lerp(b, da / (da - db))
				cut.append(Vector2(p.x, p.y))
		if cut.size() == 2 and _s82_segment_meets_rect(cut[0], cut[1], half):
			return true
	var o := Vector3(0.0, 0.0, -near)
	for d in [Vector3(1, 0.013, 0.007), Vector3(-1, 0.011, -0.005), Vector3(0.009, 1, 0.013), Vector3(-0.007, -1, 0.011), Vector3(0.012, -0.006, 1), Vector3(-0.01, 0.008, -1)]:
		var hit := false
		for i in range(0, cs.size(), 3):
			if Geometry3D.ray_intersects_triangle(o, d, cs[i], cs[i + 1], cs[i + 2]) != null:
				hit = true
				break
		if not hit:
			return false
	return true


## Whether the segment p–q meets the rectangle |x| <= half.x, |y| <= half.y (Liang–Barsky).
static func _s82_segment_meets_rect(p: Vector2, q: Vector2, half: Vector2) -> bool:
	var d := q - p
	var t0 := 0.0
	var t1 := 1.0
	var ps := [-d.x, d.x, -d.y, d.y]
	var qs := [p.x + half.x, half.x - p.x, p.y + half.y, half.y - p.y]
	for k in range(4):
		var pk: float = ps[k]
		var qk: float = qs[k]
		if absf(pk) < 1e-12:
			if qk < 0.0:
				return false
			continue
		var r := qk / pk
		if pk < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return false
	return true


## The Done-when: each tool removes about twice as much per stroke in deep snow, with the real
## controls. click_bench's run_strokes (the grind_bench bot's strokes on the path box, the walkway
## and the lawn beside it flat at the depth), each tool with round 5's profile and with §8.2's, the
## same build and bot: the mean load thrown per stroke, about twice in 80 cm (×1.7 or more; 1.8–2.0
## measured) and in 40 cm ×1.6 or more (1.7–2.1 measured), except the standard shovel's ×1.5 or
## more (1.57–1.65 measured: there the bot's sweep crosses too little snow for its doubled load, its
## bite already the whole depth; S82_SWEEP_BOUND, a reading for the coordinator, report/s8_2.md).
func test_s82_twice_per_stroke() -> void:
	var bench: Node = await _s81_bench()
	var lines := []
	for id in S82_TOOLS:
		bench.set("tool", id)
		var t: ToolData = Catalog.tool(StringName(id))
		var now := [t.capacity, t.fill_rate, t.bite]
		for depth in [0.4, 0.8]:
			var per := {}
			for which in ["round 5", "§8.2"]:
				_s82_profile(id, S82_ROUND5[id] if which == "round 5" else now)
				var s: Dictionary = await bench.run_strokes(depth, 30)
				var vols: Array = s["vols"]
				var tot := 0.0
				for v in vols:
					tot += float(v)
				per[which] = {"mean": tot / maxf(vols.size(), 1.0), "n": vols.size(), "per_min": vols.size() / maxf(float(s["frames"]) / 3600.0, 1e-6)}
			_s82_profile(id, now)
			var a: Dictionary = per["round 5"]
			var c: Dictionary = per["§8.2"]
			var x: float = c["mean"] / maxf(a["mean"], 1e-6)
			lines.append("%s %.0f cm: %.0f → %.0f L a stroke (×%.2f), %.1f → %.1f strokes a minute" % [id, depth * 100.0, a["mean"] * 1000.0, c["mean"] * 1000.0, x, a["per_min"], c["per_min"]])
			# In 40 cm the standard shovel's sweep crosses only ~90 L of snow (its bite is already the
			# whole depth there): the report's reading. In 80 cm every tool carries about twice as much.
			# Relaxation runs to a per-frame time budget, so runs vary by a few per cent.
			var need: float = 1.7 if depth >= 0.8 else float(S82_SWEEP_BOUND.get(id, 1.6))
			var bound := " (the bot's sweep bounds it: S82_SWEEP_BOUND)" if depth < 0.8 and S82_SWEEP_BOUND.has(id) else ""
			runner.check(int(c["n"]) >= 25 and x >= need, "§8.2 %s in %.0f cm of snow carries ×%.2f round 5's load a stroke (%.0f → %.0f L; ×%.1f or more%s)" % [id, depth * 100.0, x, a["mean"] * 1000.0, c["mean"] * 1000.0, need, bound])
	for l in lines:
		runner.info("§8.2 " + l)
	bench.set("tool", "hands")
	await _s81_done(bench)


## The load on the blade heaps visibly bigger, and doesn't clip the camera: for each of the six tools,
## a full load (at base and fully upgraded) held, scooping or pushing, first person, stays beyond
## the camera's near plane at every look angle from -60° up, and looking straight down comes no
## more than 1 cm nearer than round 5's load did; where it passes the near plane it does so outside
## the view (no clip on screen, in the widest view a player can set); its mound is about twice round
## 5's full load, higher and longer, scaled as wide, and no wider than the blade (inside the sleigh
## tub's walls; third person too).
func test_s82_full_load_heaps_bigger_clear_of_the_camera() -> void:
	await _s3_world("fun", 11.0)
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var lot := Layout.player_lot
	var p2 := Layout.lot_to_world(lot, Layout.gu(lot, -6.0), 4.0)
	Snow.set_rect(Rect2(p2 - Vector2(3, 3), Vector2(6, 6)), 0.5)
	pl.teleport(Vector3(p2.x, Snow.ground_at(p2.x, p2.y) + 0.05, p2.y))
	await _s3_frames(3)
	var cam: Camera3D = pl.fp_cam
	var nearest := INF
	var near_at := ""
	var growth := []
	var down_bad := []
	var on_screen := []
	var on_screen5 := []
	# The near plane's rectangle in the widest view a player can set, and the mound's triangles. The
	# check finds a clip where there is one: a big mound all round the near plane's rectangle (none
	# of its cut crosses the rectangle), and a small one cut by it in the middle of the view; and
	# none a metre above the view.
	var hy := cam.near * tan(deg_to_rad(S82_FOV_MAX) * 0.5)
	var half := Vector2(hy * S82_ASPECT_MAX, hy)
	var tris := _s82_triangles(tc.load_fp.mesh as ArrayMesh)
	var verts := _s82_vertices(tc.load_fp.mesh as ArrayMesh)
	# Round 5's mound (its own mesh) for the comparisons.
	var mound5 := _s82_round5_mound()
	var tris5 := _s82_triangles(mound5)
	var verts5 := _s82_vertices(mound5)
	var wide := []
	var wide5 := []
	var widths := []
	runner.check(_s82_cuts_view(tris, Transform3D(Basis().scaled(Vector3.ONE * 4.0), Vector3(0, 0, -cam.near)), cam.near, half)
		and _s82_cuts_view(tris, Transform3D(Basis().scaled(Vector3.ONE * 0.05), Vector3(0, 0, -cam.near - 0.002)), cam.near, half)
		and not _s82_cuts_view(tris, Transform3D(Basis(), Vector3(0, 1.0, -cam.near)), cam.near, half),
		"§8.2 the near-plane check sees a clip on screen where there is one (around the camera, in the middle of the view) and none above the view")
	var saved := Game.upgrades.duplicate()
	for id in S82_TOOLS:
		Game.carried = ""
		Game.slots = [id, "", "", ""]
		Game.select_slot(0)
		await _s3_frames(2)
		var t: ToolData = Catalog.tool(StringName(id))
		# Bigger: the mound of a full load against round 5's (its capacity, and its mound: as wide as
		# the blade, heaped sqrt(capacity ÷ tray) high within 0.8–1.4 ×, ToolController.
		# _update_load_visual before §8.2). Twice the load, about twice the mound, and it grows both
		# ways first person sees it: higher, and longer along the blade (from above, its footprint).
		var vols := {}
		var w := clampf(t.width / 0.4, 0.8, 2.2)
		var lz5 := 1.6 if t.kind == ToolData.Kind.SLEIGH else 1.0
		var heap5 := clampf(sqrt(float(S82_ROUND5[id][0]) / maxf(t.width * 0.36 * 0.25, 0.01)), 0.8, 1.4)
		for tp in [false, true]:
			pl.set_third_person(tp)
			await _s3_frames(1)
			tc.pose_override = "hold"
			tc.load = tc._capacity()
			tc._update_load_visual()
			var m: MeshInstance3D = tc.load_tp if tp else tc.load_fp
			var r5 := Vector3(w, heap5, lz5 if not tp else 1.0)
			var g := Vector3(m.scale.x / r5.x, m.scale.y / r5.y, m.scale.z / r5.z)
			vols[tp] = g
			if g.x * g.y * g.z < 1.9 or g.y < 1.35 or g.z < 1.35 or absf(g.x - 1.0) > 0.01:
				growth.append("%s %s ×%.2f (width ×%.2f, height ×%.2f, length ×%.2f)" % [id, "TP" if tp else "FP", g.x * g.y * g.z, g.x, g.y, g.z])
			# No wider than the blade (inside the sleigh tub's walls): the mound's vertices across the
			# blade, in the tool's own frame, against half its width; round 5's mound for the report.
			var to_tool := (tc.held_tp.global_transform if tp else tc.blade_fp.global_transform).affine_inverse() * m.global_transform
			var hx := 0.0
			for v in verts:
				hx = maxf(hx, absf((to_tool * v).x))
			var hx5 := 0.0
			for v in verts5:
				hx5 = maxf(hx5, absf(r5.x * v.x))
			if not tp:
				widths.append("%s %.3f m (round 5 %.3f) of %.3f" % [id, hx, hx5, t.width * 0.5])
			if hx > t.width * 0.5 + 0.0005:
				wide.append("%s %s %.3f m of %.3f" % [id, "TP" if tp else "FP", hx, t.width * 0.5])
			if hx5 > t.width * 0.5 + 0.0005:
				wide5.append("%s %s %.3f" % [id, "TP" if tp else "FP", hx5])
		pl.set_third_person(false)
		var gf: Vector3 = vols[false]
		var gt: Vector3 = vols[true]
		runner.info("§8.2 %s: a full load's mound ×%.2f first person (width ×%.2f, height ×%.2f, length ×%.2f), ×%.2f third person (round 5's full load = 1)" % [id, gf.x * gf.y * gf.z, gf.x, gf.y, gf.z, gt.x * gt.y * gt.z])
		# Clear of the camera: at base and fully upgraded, in every pose a load is carried in (held,
		# scooping, pushing; the toss throws it, so a throw's follow-through never carries one) and
		# every look angle; the mound's own vertices, and round 5's mound in the same pose beside it.
		# Looking straight down at your boots (-85°) in deep snow the tool is lifted in front of the
		# face: there round 5's sleigh load already reached the near plane, hidden by the tub
		# (report/s8_2.md), so that angle is held to round 5's, the others to the near plane.
		# Where a load passes the near plane anyway (looking straight down), the cut must lie outside
		# the widest view a player can set: no clip on screen (_s82_cuts_view).
		var nr := {"§8.2": INF, "round 5": INF, "§8.2 down": INF, "round 5 down": INF}
		for up in [false, true]:
			Game.upgrades = {}
			if up:
				for k in range(ItemUpgrades.max_level(StringName(id), &"capacity")):
					Game.upgrades[ItemUpgrades.level_id(StringName(id), &"capacity", k + 1)] = true
			var heap5u := clampf(sqrt(float(S82_ROUND5[id][0]) * ItemUpgrades.mult(StringName(id), &"shovel_capacity") / maxf(t.width * 0.36 * 0.25, 0.01)), 0.8, 1.4)
			for pose in ["hold", "scoop", "push"]:
				for pitch in [-85.0, -60.0, -35.0, -10.0, 0.0, 25.0, 50.0]:
					pl.pitch = deg_to_rad(pitch)
					pl.head.rotation.x = pl.pitch
					tc.pose_override = pose
					tc.load = tc._capacity()
					await _s3_frames(14)
					for which in ["round 5", "§8.2"]:
						tc.load = tc._capacity()
						tc._update_load_visual()
						if which == "round 5":
							tc.load_fp.scale = Vector3(w, heap5u, lz5)
							tc.load_fp.position = tc._load_at
						var xf := cam.global_transform.affine_inverse() * tc.load_fp.global_transform
						var d := INF
						for v in (verts5 if which == "round 5" else verts):
							d = minf(d, -(xf * v).z)
						var key: String = which + (" down" if pitch < -80.0 else "")
						nr[key] = minf(float(nr[key]), d)
						if d < cam.near * 1.5 and _s82_cuts_view(tris5 if which == "round 5" else tris, xf, cam.near, half):
							var at := "%s %s%s pitch %d" % [id, pose, " upgraded" if up else "", int(pitch)]
							if which == "§8.2":
								on_screen.append(at)
							else:
								on_screen5.append(at)
						if which == "§8.2" and pitch >= -80.0 and d < nearest:
							nearest = d
							near_at = "%s %s%s pitch %d" % [id, pose, " upgraded" if up else "", int(pitch)]
		runner.info("§8.2 %s: a full load's nearest point %.3f m in front of the camera from -60° up (round 5's mound %.3f m), %.4f m looking straight down (round 5's %.4f m); base and fully upgraded, held, scooping and pushing" % [id, nr["§8.2"], nr["round 5"], nr["§8.2 down"], nr["round 5 down"]])
		if float(nr["§8.2 down"]) < float(nr["round 5 down"]) - 0.01:
			down_bad.append("%s %.3f against %.3f" % [id, nr["§8.2 down"], nr["round 5 down"]])
	tc.pose_override = ""
	tc.load = 0.0
	Game.upgrades = saved
	runner.check(growth.is_empty(), "§8.2 a full load heaps visibly bigger than round 5's on every tool, first and third person: about twice the mound (×1.9 or more), ×1.35 or more higher and longer, scaled as wide as round 5's %s" % str(growth))
	runner.info("§8.2 a full load's half-width across the blade, first person: %s" % ", ".join(PackedStringArray(widths)))
	runner.info("§8.2 round 5's full load reached past the blade's edges (the sleigh's: through its tub's walls): %s" % str(wide5))
	runner.check(wide.is_empty(), "§8.2 …and no wider than the blade: inside a shovel's edges and the sleigh tub's walls, first and third person %s" % str(wide))
	runner.check(nearest > cam.near * 1.5, "§8.2 a full load stays clear of the camera at every look angle from -60° up: its nearest point is %.3f m in front (near plane %.3f m), at %s" % [nearest, cam.near, near_at])
	runner.check(down_bad.is_empty(), "§8.2 …and looking straight down it comes no more than 1 cm nearer than round 5's load did %s" % str(down_bad))
	runner.info("§8.2 round 5's load cut the view at the near plane: %s" % (str(on_screen5) if not on_screen5.is_empty() else "nowhere"))
	runner.check(on_screen.is_empty(), "§8.2 …and where a load passes the near plane (looking straight down, above the view) it never cuts the view: no clip on screen at any look angle, field of view up to %d° and aspect up to %.1f %s" % [int(S82_FOV_MAX), S82_ASPECT_MAX, str(on_screen)])
	await _s3_unload()


# =============================================================================
# §9 Smooth piles
# =============================================================================
# Snow the player moves (Snow.soft: pushed by hand or by a blade, shoved, thrown) lands spread over
# a band ahead of a blade (Snow.PUSH_BAND), settles at Snow.moved_repose (balance
# moved_repose_max_diff, lower than repose's 43°) and rounds off at its tops (moved_crest); the face
# a blade leaves behind settles once the blade has gone (the guard's tiles are queued again). The
# city's windrows and the sidewalk crew's mounds aren't marked and settle as before.

const S9_TOL := 0.001     # m: the relaxation stops on sub-millimetre moves


## Whether relaxation lets snow slide from cell i onto its neighbour n (not a wall, not off the
## property onto the street, not into a completed box from outside it).
func _s9_can_slide(i: int, n: int) -> bool:
	if Snow.surf[n] == Snow.S_BLOCKED:
		return false
	if Snow.surf[n] == Snow.S_ROAD and Snow.surf[i] != Snow.S_ROAD:
		return false
	return not (Snow.hold[n] == 1 and Snow.hold[i] == 0)


## A settled pile in `area`: for each cell of player-moved loose snow (soft,
## more than a millimetre loose) and each neighbour it could slide onto that lies lower, the step
## down — `over_step`, the most any step passes the new repose step — and `over_rule`, the most a
## step passes the rule (the new repose step, less at a top or a shoulder: no more than
## 2 × moved_crest more than the step up to the cell on its other side; a wall, the curb or a
## completed box on that side supports it).
func _s9_pile(area: Rect2) -> Dictionary:
	Snow.sync_all()
	var W := Snow.W
	var H := Snow.H
	var out := {"cells": 0, "steepest": 0.0, "over_step": -1.0, "over_rule": -1.0, "at": Vector2.ZERO, "top": 0.0}
	for z in range(Snow.cell_z(area.position.y), Snow.cell_z(area.end.y) + 1):
		for x in range(Snow.cell_x(area.position.x), Snow.cell_x(area.end.x) + 1):
			var i := z * W + x
			if Snow.surf[i] == Snow.S_BLOCKED:
				continue
			if Snow.soft[i] != 1 or Snow.loose[i] <= S9_TOL:
				continue
			out["cells"] = int(out["cells"]) + 1
			out["top"] = maxf(float(out["top"]), Snow.depth[i])
			var h := Snow.ground[i] + Snow.depth[i]
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var nz: int = z + d.y
				if nx < 0 or nz < 0 or nx >= W or nz >= H:
					continue
				var n := nz * W + nx
				if not _s9_can_slide(i, n):
					continue
				var step := h - (Snow.ground[n] + Snow.depth[n])
				if step <= 0.0:
					continue
				var lim := Snow.moved_repose
				var bx: int = x - d.x
				var bz: int = z - d.y
				if bx >= 0 and bz >= 0 and bx < W and bz < H and _s9_can_slide(i, bz * W + bx):
					var b := bz * W + bx
					lim = clampf(Snow.ground[b] + Snow.depth[b] - h + 2.0 * Snow.moved_crest, 0.0, Snow.moved_repose)
				out["steepest"] = maxf(float(out["steepest"]), step)
				out["over_step"] = maxf(float(out["over_step"]), step - Snow.moved_repose)
				if step - lim > float(out["over_rule"]):
					out["over_rule"] = step - lim
					out["at"] = Vector2((x + 0.5) * Snow.CELL, (z + 0.5) * Snow.CELL)
	return out


func _s9_report(what: String, p: Dictionary, v0: float) -> void:
	runner.near(Snow.total_volume(), v0, 1e-4, "§9 %s: the snow is conserved through the work and the settling" % what)
	runner.check(int(p["cells"]) > 20 and float(p["steepest"]) > 0.1, "§9 %s: a pile of player-moved snow (%d cells of it, %.2f m deep at its deepest, slopes down to %.3f m a cell)" % [what, int(p["cells"]), float(p["top"]), float(p["steepest"])])
	runner.check(float(p["over_step"]) <= S9_TOL, "§9 %s, settled: no cell of it stands more than the new repose step (%.2f m; repose %.2f m) above a neighbour (steepest step %.3f m)" % [what, Snow.moved_repose, Snow.repose, float(p["steepest"])])
	runner.check(float(p["over_rule"]) <= S9_TOL, "§9 %s: …and its top is rounded — no step passes the step up behind it by more than 2 × %.2f m (worst %+.4f m at %s)" % [what, Snow.moved_crest, float(p["over_rule"]), str(p["at"])])


## A vehicle at (x, lane) facing east along Maple Street with the player in it; the blade down if it
## has one; driven until it has stood still for half a second (or `frames`); then the blade up,
## backed off, the player out. Returns where its front got to (x).
func _s9_drive(id: String, x: float, frames: int) -> float:
	var pl: Player = world.player
	Game.flags["truck_keys"] = true
	Game.flags["help_vehicle_0"] = true
	var e := {"uid": Game.uid(), "id": id, "pos": Vector3(x, 0, 84.95), "yaw": -PI * 0.5, "snow": 0.0}
	Game.vehicles.append(e)
	var v: Vehicle = world.spawn_vehicle_node(e)
	await _s3_frames(2)
	v.enter_vehicle(pl)
	await _s3_frames(2)
	if v.data.has_plow and not v.tool_on:
		v._toggle_tool()
	Input.action_press("veh_accelerate")
	var still := 0
	for k in range(frames):
		await _s3_frames(1)
		still = still + 1 if absf(v.speed) < 0.05 and k > 60 else 0
		if still > 30:
			break
	Input.action_release("veh_accelerate")
	var front := v.global_position.x + v.data.length * 0.5
	if v.tool_on:
		v._toggle_tool()
	Input.action_press("veh_reverse")
	await _s3_frames(60)
	Input.action_release("veh_reverse")
	v.exit_vehicle()
	await _s3_frames(60)      # the guard runs out and its tiles are queued (Snow.GUARD_SETTLE_STEPS)
	return front


## Done-when: a pile pushed by hand and by a plow, with the real controls, has no cell more than
## the new repose step above its neighbours once settled; its top is rounded; the snow is
## conserved. Before §9 the hand push left a 0.49 m cliff on its blade side (the guard's tiles were
## never looked at again) and the plow's pile a 1.1 m one, both over a one-cell ridge.
func test_s9_pushed_piles_settle_at_the_new_step() -> void:
	await _s3_world("fun", 12.0)
	Clock.running = false
	Weather.force(Weather.C.CLEAR, 48.0)
	world.snow_renderer.relax_usec = 0      # relaxation by tile count only: the same every run
	Snow.push_rng.seed = Snow.PUSH_SEED + 9
	var b: BalanceData = Catalog.balance
	runner.check(is_equal_approx(Snow.moved_repose, b.moved_repose_max_diff) and is_equal_approx(Snow.moved_crest, b.moved_crest_max_diff) and Snow.moved_repose < Snow.repose and Snow.moved_crest < Snow.moved_repose,
		"§9 player-moved snow settles at %.2f m a cell (%.0f°) and rounds off at its tops (%.2f m), other loose snow at %.2f m (%.0f°)" % [Snow.moved_repose, rad_to_deg(atan(Snow.moved_repose / Snow.CELL)), Snow.moved_crest, Snow.repose, rad_to_deg(atan(Snow.repose / Snow.CELL))])
	# By hand: the wide pusher held down (RMB) and walked 1.5 s across 30 cm of the front yard.
	var pl: Player = world.player
	var lot := Layout.player_lot
	var inward := Vector2(lot["inward"]).normalized()
	var a := Layout.lot_to_world(lot, Layout.gu(lot, -3.5), 1.2)
	var yard := Layout.lot_rect_world(lot, Layout.gu(lot, -6.5), Layout.gu(lot, -0.5), 0.2, 8.5)
	Snow.set_rect(yard, 0.30)
	Snow.relax_until_stable()
	var v0 := Snow.total_volume()
	Game.slots = ["wide_pusher", "", "", ""]
	Game.selected = 0
	Game.inventory_changed.emit()
	await _s3_frames(2)
	pl.teleport(Vector3(a.x, Snow.surface_height(a.x, a.y) + 0.05, a.y), atan2(-inward.x, -inward.y))
	pl.pitch = deg_to_rad(-30.0)
	pl.head.rotation.x = pl.pitch
	await _s3_frames(2)
	Input.action_press("secondary")
	Input.action_press("move_forward")
	await _s3_frames(90)
	Input.action_release("move_forward")
	Input.action_release("secondary")
	await _s3_frames(60)      # the guard runs out and its tiles are queued (Snow.GUARD_SETTLE_STEPS)
	Snow.relax_until_stable()
	var walked := Vector2(pl.global_position.x, pl.global_position.z).distance_to(a)
	runner.info("§9 the wide pusher walked %.2f m in 1.5 s" % walked)
	_s9_report("a berm pushed by hand (the wide pusher, 30 cm)", _s9_pile(yard), v0)
	# A plow: the pickup with its plow down, 5 s along Maple Street's south lane: 22 m of 30 cm snow,
	# then the bare street (the berm goes on with the blade until it is lifted).
	Snow.set_rect(Rect2(0, 79, 92, 8), 0.02)
	Snow.set_rect(Rect2(14, 81.5, 22, 4.5), 0.30)
	Snow.relax_until_stable()
	var v1 := Snow.total_volume()
	var front := await _s9_drive("pickup_plow", 6.0, 300)
	Snow.relax_until_stable()
	runner.info("§9 the plow's front got to x %.1f (the snow from x 14 to 36)" % front)
	_s9_report("a pile plowed by the pickup with its plow", _s9_pile(Rect2(10, 79.5, maxf(front - 4.0, 30.0), 9)), v1)
	await _s3_unload()


## The pickup's shove (polish 5 §12) and repeated throws on one spot settle the same way.
func test_s9_shoved_and_thrown_piles_settle_at_the_new_step() -> void:
	await _s3_world("fun", 12.0)
	Clock.running = false
	Weather.force(Weather.C.CLEAR, 48.0)
	world.snow_renderer.relax_usec = 0
	Snow.push_rng.seed = Snow.PUSH_SEED + 9
	# The pickup (no plow) shoving 60 cm on Maple Street, under its bog depth, as perf.tscn does.
	Snow.set_rect(Rect2(0, 79, 24, 8), 0.03)
	Snow.set_rect(Rect2(24, 79, 30, 8), 0.6)
	Snow.relax_until_stable()
	var v0 := Snow.total_volume()
	var front := await _s9_drive("pickup", 8.0, 420)
	Snow.relax_until_stable()
	runner.info("§9 the pickup shoved on to x %.1f (the snow from x 24)" % front)
	_s9_report("the pickup's shove (60 cm)", _s9_pile(Rect2(22, 78.5, 20, 10)), v0)
	# Twenty standard-shovel loads (§8.2's 130 L) landed on one spot of the front yard: the throw's
	# landing op, a third of a second apart.
	var lot := Layout.player_lot
	var at := Layout.lot_to_world(lot, Layout.gu(lot, -3.5), 5.5)
	var area := Rect2(at - Vector2(3.5, 3.5), Vector2(7.0, 7.0))
	Snow.set_rect(area, 0.10)
	Snow.relax_until_stable()
	var v1 := Snow.total_volume()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for k in range(20):
		Snow.deposit(at + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)), 0.13, 0.25 + 0.13 * 2.5, true)
		await _s3_frames(20)
	Snow.relax_until_stable()
	_s9_report("20 throws on one spot", _s9_pile(area), v1 + 20 * 0.13)
	await _s3_unload()


## The band: one blade step on flat snow spreads each cell's snow over several cells ahead of the
## face, centred where the one line used to be (push_dist + the 0–12 cm draw), never behind the
## face; one draw from push_rng per moved cell as before; the snow conserved and marked soft. Each
## distance pushes on ground of its own (no marks left by another push), with a blade as wide as
## the plows' (3 m) and a band 0.75 m deep behind it: 36 cells of 20 cm snow, each with its own draw.
func test_s9_blade_push_spreads_over_a_band() -> void:
	await _s3_unload()
	Game.new_game("fun", 2024)
	var hw := 1.5
	var band := 0.75
	var n := 0
	for pd in [0.3, 0.38, 0.6, 1.5]:      # bare hands, the hand tools, the plows, the pickup's shove
		var at := Vector2(36.0 + 6.0 * n, 120.0)
		n += 1
		var area := Rect2(at - Vector2(2.5, 1.5), Vector2(5.0, 4.5))
		Snow.set_rect(area, 0.0)
		Snow.set_rect(Rect2(at.x - 2.0, at.y - 1.0, 4.0, 1.0), 0.2)
		Snow.relax_until_stable()
		var sx0 := Snow.cell_x(area.position.x)
		var sz0 := Snow.cell_z(area.position.y)
		var before := PackedFloat32Array()
		var cells := 0
		var marked := 0
		var blocked := 0
		for z in range(sz0, Snow.cell_z(area.end.y)):
			for x in range(sx0, Snow.cell_x(area.end.x)):
				var i := z * Snow.W + x
				before.append(Snow.depth[i])
				marked += Snow.soft[i]
				if Snow.surf[i] == Snow.S_BLOCKED:
					blocked += 1
				var c := Vector2((x + 0.5) * Snow.CELL, (z + 0.5) * Snow.CELL) - at
				if absf(c.x) <= hw and c.y <= 0.0 and c.y >= -band and Snow.depth[i] > 0.0:
					cells += 1
		var v0 := Snow.volume_in_rect(area)
		Snow.push_rng.seed = Snow.PUSH_SEED + 5
		var ref := RandomNumberGenerator.new()
		ref.seed = Snow.PUSH_SEED + 5
		for k in range(cells):
			ref.randf()
		var r := Snow.blade_push(at, Vector2(0, 1), hw, band, 0.0, false, pd)
		var rows := {}
		var sum := 0.0
		var wsum := 0.0
		var behind := 0.0
		var unmarked := 0
		var k2 := 0
		for z in range(sz0, Snow.cell_z(area.end.y)):
			for x in range(sx0, Snow.cell_x(area.end.x)):
				var i := z * Snow.W + x
				var add := Snow.depth[i] - before[k2]
				k2 += 1
				if add <= 1e-6:
					continue
				var ahead := (z + 0.5) * Snow.CELL - at.y
				if ahead <= 0.0:
					behind += add
				rows[z] = true
				sum += add
				wsum += add * ahead
				if Snow.soft[i] != 1:
					unmarked += 1
		var mean := wsum / maxf(sum, 1e-9)
		var want := cells * 0.2 * Snow.CELL_AREA
		runner.check(blocked == 0 and marked == 0 and cells == 36 and Snow.push_rng.state == ref.state, "§9 push %.2f m, on open ground with no marks (%d blocked cells, %d marked): one draw from push_rng per moved cell (%d cells)" % [pd, blocked, marked, cells])
		runner.check(rows.size() >= 3 and behind <= 0.0 and absf(mean - (pd + 0.06)) < 0.05, "§9 push %.2f m: the snow lands over %d rows ahead of the face (round 5: one line), none behind it, centred %.3f m ahead, within 5 cm of where the line was (%.2f–%.2f)" % [pd, rows.size(), mean, pd, pd + 0.12])
		runner.check(unmarked == 0 and absf(Snow.volume_in_rect(area) - v0) < 1e-5 and absf(float(r["moved"]) - want) < 1e-4, "§9 push %.2f m: %.3f m³ moved (all of the band's %.3f), conserved, all of it marked player-moved (%d cells unmarked)" % [pd, float(r["moved"]), want, unmarked])


## The city's snow isn't player-moved: the grader's windrows and the sidewalk crew's mounds settle as
## before (round 5 Decision 6). Player-moved snow stops being so once it has hardened. A save keeps
## the marks; an older save, without them, has none.
func test_s9_whose_snow_is_marked() -> void:
	await _s3_unload()
	Game.world = null
	Game.player = null
	Municipal.world_handles_passes = false
	Game.new_game("fun", 2024)
	Snow.add_snowfall(0.2)
	Snow.sync_all()
	Municipal.crew_pending = Municipal.crew_route()
	Municipal.run_batch(Municipal.route_lanes())
	var city := Snow.soft.count(1)
	var wind := 0
	for i in range(Snow.W * Snow.H):
		if Snow.loose[i] > 0.01:
			wind += 1
	runner.check(city == 0 and wind > 1000, "§9 the grader's windrows and the sidewalk crew's mounds (%d cells of loose snow) aren't player-moved snow: %d cells marked" % [wind, city])
	Game.new_game("fun", 2024)
	var p := Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, -6.0), 6.0)
	Snow.deposit(p, 0.4, 0.5)
	Snow.relax_until_stable()
	var thrown := Snow.soft.count(1)
	var d := Snow.serialize()
	d.merge(Snow.serialize_pending())
	var want := Snow.soft.duplicate()
	Snow.soft.fill(0)
	Snow.deserialize(d.duplicate())
	runner.check(thrown > 10 and Snow.soft == want, "§9 a throw's snow is marked (%d cells) and a save keeps the marks" % thrown)
	var old := d.duplicate()
	old.erase("soft")
	Snow.deserialize(old)
	runner.check(Snow.soft.count(1) == 0, "§9 …and a save without them (older than §9) loads with none: its loose snow settles as before")
	Snow.deserialize(d.duplicate())
	Snow.advance_settle(1440.0 * 10.0)       # ten days: the loose snow has hardened
	Snow.sync_all()
	runner.check(Snow.soft.count(1) == 0, "§9 once its loose snow has hardened, it is no longer player-moved snow (%d cells left marked)" % Snow.soft.count(1))


## Marks (Snow.soft) within a rect.
func _s9_marks(r: Rect2) -> int:
	var n := 0
	for z in range(Snow.cell_z(r.position.y), Snow.cell_z(r.end.y) + 1):
		for x in range(Snow.cell_x(r.position.x), Snow.cell_x(r.end.x) + 1):
			n += Snow.soft[z * Snow.W + x]
	return n


## On a fresh map, a bare 8 m square of the front yard; with `marked`, a throw's player-moved snow
## in the middle of it; then `how` empties the middle (a completed box's snap and hold, the heated
## pad's melting, a floor-0 scraper pass on past it), the chunk syncs, and snow that isn't the
## player's (wading's flank) lands on the same spot and settles. Without `marked` the same steps on
## ground that was never marked: the reference.
func _s9_emptied(how: String, marked: bool) -> Dictionary:
	Game.new_game("fun", 2024)
	var lot := Layout.player_lot
	var p := Layout.lot_to_world(lot, Layout.gu(lot, -6.0), 6.0)
	var e := Rect2(p - Vector2(1.5, 1.5), Vector2(3.0, 3.0))
	var c := Rect2(p - Vector2(1.25, 1.25), Vector2(2.5, 2.5))
	Snow.set_rect(e.grow(2.5), 0.0)
	Snow.relax_until_stable()
	var out := {"thrown": 0, "elsewhere": 0}
	if marked:
		Snow.deposit(p, 0.3, 0.5)       # a throw
		Snow.relax_until_stable()
		out["thrown"] = _s9_marks(e)
		out["elsewhere"] = Snow.soft.count(1) - int(out["thrown"])
	match how:
		"a completed box's snap":       # Boxes.complete
			Snow.set_rect(e, 0.0, true)
			Snow.set_hold_rect(e, true)
		"melting":                      # the heated pad
			Snow.melt_rect(e, 1.0)
		"a floor-0 scrape":             # the snow scraper, row by row, on past the spot
			for k in range(16):
				Snow.blade_push(Vector2(p.x, e.position.y + k * 0.25), Vector2(0, 1), 1.6, 0.3, 0.0, false, 0.38)
	Snow.relax_until_stable()
	out["after_op"] = _s9_marks(e)
	Snow.advance_settle(1.0)            # the chunk's next sync
	Snow.sync_all()
	out["after_sync"] = _s9_marks(e)
	Snow.deposit(p, 0.3, 0.4, false, false)     # wading's flank: not the player's snow
	Snow.relax_until_stable()
	out["after_flank"] = _s9_marks(e)
	var hs := PackedFloat32Array()
	var steepest := 0.0
	for z in range(Snow.cell_z(c.position.y), Snow.cell_z(c.end.y) + 1):
		for x in range(Snow.cell_x(c.position.x), Snow.cell_x(c.end.x) + 1):
			var i := z * Snow.W + x
			hs.append(Snow.depth[i])
			if Snow.loose[i] <= S9_TOL:
				continue
			for d in [1, -1, Snow.W, -Snow.W]:
				var nb: int = i + d
				if _s9_can_slide(i, nb):
					steepest = maxf(steepest, Snow.ground[i] + Snow.depth[i] - Snow.ground[nb] - Snow.depth[nb])
	out["heights"] = hs
	out["steepest"] = steepest
	return out


## A mark lasts only while its cell holds player-moved loose snow. A marked cell emptied some other
## way loses it — a completed box's snap at once (set_rect), melting and a floor-0 scrape at the
## chunk's next sync (before, the mark stayed for the rest of the winter) — so snow that isn't the
## player's landing there afterwards settles by the original rule (43°), exactly as on ground that
## was never marked, and marks nothing.
func test_s9_emptied_cells_lose_their_marks() -> void:
	await _s3_unload()
	Game.world = null
	Game.player = null
	Municipal.world_handles_passes = false
	for how in ["a completed box's snap", "melting", "a floor-0 scrape"]:
		var ref := _s9_emptied(how, false)
		var got := _s9_emptied(how, true)
		var hr: PackedFloat32Array = ref["heights"]
		var hg: PackedFloat32Array = got["heights"]
		var diff := 0.0
		for k in range(hr.size()):
			diff = maxf(diff, absf(hg[k] - hr[k]))
		runner.check(int(got["thrown"]) > 10 and int(got["elsewhere"]) == 0, "§9 %s: a throw's snow marked %d cells, all on the spot emptied" % [how, int(got["thrown"])])
		if how == "a completed box's snap":
			runner.check(int(got["after_op"]) == 0, "§9 %s: the emptied cells lose their marks at once (%d left)" % [how, int(got["after_op"])])
		else:
			runner.info("§9 %s: %d marks on the emptied cells until the chunk syncs" % [how, int(got["after_op"])])
		runner.check(int(got["after_sync"]) == 0, "§9 %s: once the chunk has synced, none of the emptied cells is marked (%d)" % [how, int(got["after_sync"])])
		runner.check(int(got["after_flank"]) == 0 and int(ref["after_flank"]) == 0 and diff <= 1e-6 and float(got["steepest"]) > Snow.moved_repose + 0.01,
			"§9 %s: wading's snow landing there afterwards is not marked (%d cells) and settles as on ground never marked (heights within %.6f m), at the original step (steepest %.3f m; player-moved snow %.2f, other loose snow %.2f)" % [how, int(got["after_flank"]), diff, float(got["steepest"]), Snow.moved_repose, Snow.repose])
