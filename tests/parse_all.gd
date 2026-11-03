extends Node
## Loads every script and scene in the project so parse/compile errors are reported (with autoloads).

func _ready() -> void:
	var errors := 0
	var files := []
	_collect("res://scripts", files)
	_collect("res://tests", files)
	for f in files:
		var r = load(f)
		if r == null:
			errors += 1
			printerr("FAILED: ", f)
		elif r is GDScript and not (r as GDScript).can_instantiate():
			errors += 1
			printerr("CANNOT INSTANTIATE: ", f)
	print("Parsed %d scripts, %d errors" % [files.size(), errors])
	get_tree().quit(1 if errors > 0 else 0)


func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_collect(dir + "/" + sub, out)
