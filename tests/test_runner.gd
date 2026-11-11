extends Node
## Headless automated test runner.
## Run: godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn [-- --only=snow] [--test=name_part]
## [--verbose] (also print the checks that pass, with their measurements).
## Exit code 0 = all passed.

const SUITES := [
	"res://tests/test_snow.gd",
	"res://tests/test_systems.gd",
	"res://tests/test_gameplay.gd",
	"res://tests/test_polish3.gd",
	"res://tests/test_polish4.gd",
	"res://tests/test_polish5.gd",
	"res://tests/test_polish6.gd",
]

var passed := 0
var failed := 0
var failures: Array[String] = []
var current := ""
var verbose := false


func _ready() -> void:
	await get_tree().process_frame
	var only := ""
	var only_test := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--test="):
			only_test = a.substr(7)
		elif a == "--verbose":
			verbose = true
	var t0 := Time.get_ticks_msec()
	for path in SUITES:
		if only != "" and not path.contains(only):
			continue
		if not ResourceLoader.exists(path):
			continue
		var script = load(path)
		if script == null or not (script as GDScript).can_instantiate():
			current = path.get_file()
			_fail("load " + path)
			continue
		var suite = script.new()
		suite.set("runner", self)
		for m in suite.get_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if only_test != "" and not mname.contains(only_test):
				continue
			current = path.get_file() + "::" + mname
			var before := failed
			var t := Time.get_ticks_msec()
			await suite.call(mname)
			var ms := Time.get_ticks_msec() - t
			if failed == before:
				passed += 1
				print("  PASS  %s (%d ms)" % [current, ms])
			else:
				print("  FAIL  %s (%d ms)" % [current, ms])
		if suite is Node:
			suite.queue_free()
	print("")
	print("==== %d passed, %d failed (%.1f s) ====" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	for f in failures:
		print("  - " + f)
	# AudioMgr.quit: stop every sound before quitting, so nothing is reported leaked at exit
	# (HANDOFF §13 item 13).
	AudioMgr.quit(1 if failed > 0 else 0)


func check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	elif verbose:
		print("    ✓ " + msg)
	return cond


func near(a: float, b: float, tol: float, msg: String) -> bool:
	return check(absf(a - b) <= tol, "%s (got %.6f expected %.6f ±%.6f)" % [msg, a, b, tol])


func _fail(msg: String) -> void:
	failed += 1
	failures.append(current + ": " + msg)
	printerr("    ✗ " + msg)


func info(msg: String) -> void:
	print("      " + msg)
