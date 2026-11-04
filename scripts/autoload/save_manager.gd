extends Node
## Save system (Part 26): one save per mode, written when the player sleeps.
## Atomic replace (temp file -> rename, previous kept as .bak), version number, validation.
## Missing or invalid saves never crash the game.

## Version 2 (polish pass): clearing boxes, loose-snow flags, contract snowed-in timers.
## Version 3 (polish 5 §7): game.company_name and contracts.job_history (both optional).
## Older saves are migrated on load, in order: 1 -> 2 (_migrate_v1), 2 -> 3 (_migrate_v2).
const SAVE_VERSION := 3
const MIN_VERSION := 1
const DIR := "user://saves/"

signal saved(mode: String)

var last_error := ""


func path_for(mode: String) -> String:
	return DIR + "%s.json" % mode


func has_save(mode: String) -> bool:
	return FileAccess.file_exists(path_for(mode)) and not peek(mode).is_empty()


## Small summary for the menu (or {} if no valid save).
func peek(mode: String) -> Dictionary:
	var d := _read(path_for(mode))
	if d.is_empty():
		return {}
	var g: Dictionary = d.get("game", {})
	return {"year": int(g.get("year", 1)), "money": int(g.get("money", 0)), "time": float(d.get("clock", 0.0)),
		"saved_at": str(d.get("saved_at", ""))}


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	# JSON.parse rather than JSON.parse_string: the same result, but a corrupt file is reported as
	# no save without the engine printing "Parse JSON failed" (polish 5 §1, a clean log).
	var json := JSON.new()
	if json.parse(txt) != OK:
		return {}
	var parsed = json.data
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	var ver := int(d.get("version", -1))
	if ver < MIN_VERSION or ver > SAVE_VERSION:
		return {}
	for k in ["game", "clock", "snow", "weather", "economy", "contracts", "municipal", "survival"]:
		if not d.has(k):
			return {}
	return d


func save_game() -> bool:
	if Game.world and Game.world.has_method("collect_state"):
		Game.world.collect_state()
	var snow := Snow.serialize()
	var snow_out := snow.duplicate()
	snow_out["data"] = Marshalls.raw_to_base64(snow["data"])
	snow_out["loose"] = Marshalls.raw_to_base64(snow["loose"])
	var d := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"game": Game.serialize(),
		"clock": Clock.minutes,
		"snow": snow_out,
		"weather": Weather.serialize(),
		"economy": Economy.serialize(),
		"contracts": Contracts.serialize(),
		"municipal": Municipal.serialize(),
		"survival": Survival.serialize(),
		"boxes": Boxes.serialize(),
	}
	DirAccess.make_dir_recursive_absolute(DIR)
	var final := path_for(Game.mode)
	var tmp := final + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "Cannot write %s" % tmp
		push_error(last_error)
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	# Validate what we wrote before replacing the real save.
	if _read(tmp).is_empty():
		last_error = "Save validation failed"
		push_error(last_error)
		DirAccess.remove_absolute(tmp)
		return false
	var bak := final + ".bak"
	if FileAccess.file_exists(final):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(final, bak)
	var err := DirAccess.rename_absolute(tmp, final)
	if err != OK:
		last_error = "Rename failed (%d)" % err
		push_error(last_error)
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(bak, final)
		return false
	Game.dirty_since_save = false
	saved.emit(Game.mode)
	return true


## Load a save into all systems. Returns false (and leaves state untouched) if invalid.
func load_game(mode: String) -> bool:
	var d := _read(path_for(mode))
	if d.is_empty():
		d = _read(path_for(mode) + ".bak")
		if d.is_empty():
			last_error = "No valid save for %s." % mode
			return false
	var snow: Dictionary = d["snow"]
	var sd := snow.duplicate()
	sd["data"] = Marshalls.base64_to_raw(str(snow.get("data", "")))
	sd["loose"] = Marshalls.base64_to_raw(str(snow.get("loose", ""))) if snow.has("loose") else PackedByteArray()
	sd["w"] = int(snow.get("w", 0))
	sd["h"] = int(snow.get("h", 0))
	sd["size"] = int(snow.get("size", 0))
	sd["fmt"] = int(snow.get("fmt", 1))
	Game.deserialize(d["game"])
	Weather.deserialize(d["weather"])
	Clock.reset(float(d["clock"]))
	if not Snow.deserialize(sd):
		push_warning("Snow data invalid; regenerating winter snow.")
		Snow.reset_for_winter(Game.year)
	var ver := int(d.get("version", SAVE_VERSION))
	if ver >= 2 and d.has("boxes"):
		Boxes.deserialize(d["boxes"])
	else:
		Boxes.migrate_from_snow()
	Economy.deserialize(d["economy"])
	Contracts.deserialize(d["contracts"])
	Municipal.deserialize(d["municipal"])
	Survival.deserialize(d["survival"])
	if ver < 2:
		_migrate_v1()
	if ver < 3:
		_migrate_v2()
	Game.dirty_since_save = false
	return true


## Version 1 -> 2: cold is on from the start in Survival Mode; the computer lock follows the
## tutorial stage; contract zones were already mapped onto boxes by Contracts.deserialize.
func _migrate_v1() -> void:
	if Game.is_survival():
		Survival.active = true
	if Game.stage() >= Game.Stage.COMPLETE:
		Game.flags["computer_unlocked"] = true


## Version 2 -> 3 (polish 5 §7): the company has no name yet (the computer asks for one) and an
## empty contract history (the old list of completed one-time jobs stays as it was).
func _migrate_v2() -> void:
	Game.company_name = ""
	Contracts.job_history = []


func delete_save(mode: String) -> void:
	for p in [path_for(mode), path_for(mode) + ".bak", path_for(mode) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
