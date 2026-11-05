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
