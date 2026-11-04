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
