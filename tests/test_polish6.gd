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
