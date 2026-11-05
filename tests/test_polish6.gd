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
