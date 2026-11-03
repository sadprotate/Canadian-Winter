extends RefCounted
## Polish pass 3 tests: save fixtures, overwrite dialog, house interior, the 90 % rule, buried
## tool pickup, Gerry's quest and mailboxes, the live main menu. Same harness as
## test_gameplay.gd (real game scene, real input actions, fixed 60 fps).

var runner
var world: Node = null

const FIXTURES := "res://tests/fixtures/polish3/"


func _tree() -> SceneTree:
	return runner.get_tree()


func _frames(n: int) -> void:
	for i in range(n):
		await _tree().physics_frame


func _load_world(mode := "fun", seed_val := 2024, hour := 10.0, day := 1) -> void:
	await _unload()
	Game.force_input = true
	Game.new_game(mode, seed_val)
	Clock.reset(Clock.at(day, hour))
	await _spawn_world()
	Clock.running = false


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


## Copy a fixture over the mode's save file and load it like the menu's Continue does.
func _load_fixture(name: String) -> bool:
	var mode := "fun" if name.begins_with("fun") else "survival"
	var src := ProjectSettings.globalize_path(FIXTURES + name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Saves.DIR))
	for p in [Saves.path_for(mode), Saves.path_for(mode) + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if DirAccess.copy_absolute(src, ProjectSettings.globalize_path(Saves.path_for(mode))) != OK:
		return false
	await _unload()
	Game.force_input = true
	return Saves.load_game(mode)


static func fixture_names() -> Array:
	var out := []
	for mode in ["fun", "survival"]:
		for point in ["1_opening", "2_mid_trail", "3_contract", "4_midwinter"]:
			out.append("%s_%s.json" % [mode, point])
	return out


# -----------------------------------------------------------------------------
# §0 Save fixtures: each loads and plays — move, scoop, sleep (autosave), reload.
# -----------------------------------------------------------------------------

func test_fixtures_load_and_play() -> void:
	for name in fixture_names():
		if not FileAccess.file_exists(FIXTURES + name):
			runner.check(false, "fixture %s exists" % name)
			continue
		var ok: bool = await _load_fixture(name)
		runner.check(ok, "%s loads" % name)
		if not ok:
			continue
		var mode := Game.mode
		var stage := Game.stage()
		var money := Game.money
		await _spawn_world()
		var pl: Player = world.player
		# Walk along the street in front of the house (the grader keeps it passable).
		var road := Layout.lot_to_world(Layout.player_lot, 0.0, -4.0)
		pl.teleport(Vector3(road.x, 0.05, road.y), PI * 0.5)
		pl.pitch = 0.0
		await _frames(2)
		var p0 := pl.global_position
		await _hold("move_forward", 40)
		var moved := Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length()
		runner.check(moved > 0.05, "%s: the player moves (%.2f m)" % [name, moved])
		# Scoop: on the front lawn, look down at the snow in front and sweep.
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
		# Sleep (autosaves) and reload.
		await world._do_sleep()
		await _frames(5)
		runner.check(Clock.hour() == 7 and Clock.minute_of_hour() == 0, "%s: sleep ends at 7:00 (%s)" % [name, Clock.format_time(Clock.minutes)])
		runner.check(Saves.has_save(mode) and not Game.dirty_since_save, "%s: sleeping autosaves" % name)
		var t_saved := Clock.minutes
		var money_saved := Game.money
		await _unload()
		runner.check(Saves.load_game(mode), "%s: the autosave reloads" % name)
		await _spawn_world()
		runner.check(absf(Clock.minutes - t_saved) < 0.01 and Game.money == money_saved and Game.stage() >= stage, "%s: reloaded at the same time, money and stage" % name)
		runner.check(world.player != null and is_instance_valid(world.player), "%s: the reloaded world has a player" % name)
		if money_saved < money - 200:
			runner.info("%s: money went from %d to %d over the night" % [name, money, money_saved])
	await _unload()


# -----------------------------------------------------------------------------
# §2 New game / save overwrite confirmation
# -----------------------------------------------------------------------------

## Logical canvas sizes the dialog is laid out in (stretch mode canvas_items / aspect expand,
## base 1920×1080): every 16:9 resolution maps to 1920×1080, 21:9 widens it. The game has no
## separate UI-scale setting.
const DIALOG_CASES := {"1280x720": Vector2(1920, 1080), "1920x1080": Vector2(1920, 1080),
	"2560x1440": Vector2(1920, 1080), "3440x1440": Vector2(2580, 1080)}


func _overwrite_text(mode: String) -> String:
	# Same wording as main_menu._new_game.
	return "Start a new %s game? Your existing save (Winter %d, %s) will be overwritten the next time you sleep." % [mode.capitalize(), 3, UIKit.money(12345)]


func test_overwrite_dialog_fits_and_centres() -> void:
	await _unload()
	for res in DIALOG_CASES.keys():
		for mode in ["fun", "survival"]:
			var host := Control.new()
			host.size = DIALOG_CASES[res]
			runner.add_child(host)
			var said := {"yes": 0, "no": 0}
			var root := Panels.confirm(host, _overwrite_text(mode), "Start new game", func(): said["yes"] += 1, func(): said["no"] += 1)
			await _frames(3)
			var p: Control = root.find_child("Dialog", true, false)
			var l: Label = root.find_child("Message", true, false)
			var h: Control = root.find_child("Buttons", true, false)
			var tag := "%s %s" % [res, mode]
			var view := Rect2(Vector2.ZERO, host.size)
			var r := p.get_global_rect()
			runner.check(view.encloses(r), "%s: the dialog is inside the screen %s" % [tag, str(r)])
			var off := r.get_center() - view.get_center()
			runner.check(absf(off.x) <= 2.0 and absf(off.y) <= 2.0, "%s: the dialog is centred (off by %s)" % [tag, str(off)])
			runner.check(l.get_line_count() == l.get_visible_line_count() and l.size.y >= l.get_minimum_size().y - 0.5 and r.encloses(l.get_global_rect()), "%s: the warning isn't clipped (%d lines)" % [tag, l.get_line_count()])
			runner.check(l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "%s: the warning is centre-aligned" % tag)
			var bs: Array = h.get_children()
			var b0: Control = bs[0]
			var b1: Control = bs[1]
			runner.check(bs.size() == 2 and absf(b0.size.x - b1.size.x) < 0.5 and absf(b0.size.y - b1.size.y) < 0.5, "%s: two buttons of the same size" % tag)
			var row := b0.get_global_rect().merge(b1.get_global_rect())
			runner.check(absf(row.get_center().x - r.get_center().x) <= 2.0 and r.encloses(row), "%s: the buttons sit in a centred row" % tag)
			var top := l.get_global_rect().position.y - r.position.y
			var bottom := r.end.y - row.end.y
			var left := minf(l.get_global_rect().position.x, row.position.x) - r.position.x
			var right := r.end.x - maxf(l.get_global_rect().end.x, row.end.x)
			runner.check(absf(top - bottom) <= 2.0 and absf(left - right) <= 2.0 and absf(top - left) <= 2.0, "%s: even padding (top %.0f bottom %.0f left %.0f right %.0f)" % [tag, top, bottom, left, right])
			runner.check(r.size.x <= 760.0 and r.size.y <= 360.0, "%s: no large empty area (%s)" % [tag, str(r.size)])
			runner.check(l.text.contains("overwritten the next time you sleep"), "%s: the overwrite warning is kept" % tag)
			# Behaviour: cancel closes and calls back only the cancel path; confirm the other.
			(b1 as Button).pressed.emit()
			await _frames(2)
			runner.check(said["no"] == 1 and said["yes"] == 0 and not is_instance_valid(root), "%s: Cancel closes the dialog and goes back" % tag)
			var root2 := Panels.confirm(host, _overwrite_text(mode), "Start new game", func(): said["yes"] += 1, func(): said["no"] += 1)
			await _frames(2)
			((root2.find_child("Buttons", true, false) as Control).get_child(0) as Button).pressed.emit()
			await _frames(2)
			runner.check(said["yes"] == 1 and said["no"] == 1 and not is_instance_valid(root2), "%s: Start new game confirms" % tag)
			host.queue_free()
			await _frames(1)


# -----------------------------------------------------------------------------
# §3 House interior
# -----------------------------------------------------------------------------

## Snow depth summed over the cells of a house's interior: every cell whose centre lies inside
## the house body (the doorway included).
func _interior_depth(lot: Dictionary) -> float:
	var r: Rect2 = Layout.house_info(lot)["body"]
	var tot := 0.0
	for z in range(Snow.cell_z(r.position.y), Snow.cell_z(r.end.y) + 1):
		for x in range(Snow.cell_x(r.position.x), Snow.cell_x(r.end.x) + 1):
			if r.has_point(Vector2((x + 0.5) * Snow.CELL, (z + 0.5) * Snow.CELL)):
				tot += Snow.depth[z * Snow.W + x]
	return tot


func test_no_snow_inside_the_houses() -> void:
	await _load_world("fun", 2024, 12.0, 1)
	var lots := [Layout.player_lot, Layout.neighbor_lot]
	for lot in lots:
		runner.check(_interior_depth(lot) == 0.0, "%s: no snow inside at the start" % lot["address"])
	# A storm and a major event on top.
	Snow.add_snowfall(0.3)
	Snow.add_snowfall(1.1)
	Snow.sync_all()
	Snow.relax_until_stable()
	var v0 := Snow.total_volume()
	var added := 0.0
	for lot in lots:
		var L := HouseBuilder.lot_transform(lot)
		var sb: float = lot["setback"]
		var door := L * Vector3(-1.5, 0, sb)
		var outside := L * Vector3(-1.5, 0, sb - 0.6)
		var d2 := Vector2(door.x, door.z)
		var o2 := Vector2(outside.x, outside.z)
		# Throw snow at the door (landing on the doorway itself and just in front of it).
		for k in range(12):
			added += Snow.deposit(d2.lerp(o2, k / 24.0), 0.08, 0.35)
		# Push a pile against it.
		var fwd := (d2 - o2).normalized()
		for k in range(40):
			Snow.blade_push(o2 - fwd * 1.2 + fwd * k * 0.04, fwd, 0.45, 0.12, 0.006, true, 0.4)
	Snow.relax_until_stable()
	for lot in lots:
		runner.check(_interior_depth(lot) == 0.0, "%s: still no snow inside after a storm, a major event, throws at the door and a pile pushed against it" % lot["address"])
	var v1 := Snow.total_volume()
	runner.check(absf(v1 - (v0 + added)) < 0.02, "…and every cubic metre is still outside (%.3f vs %.3f m3)" % [v1, v0 + added])


func test_bed_prompt_and_sleep_text() -> void:
	await _load_world("fun", 2024, 21.0, 1)
	var bed: Node = world.interior["bed"]
	var prompt: String = bed.call("interact_prompt", world.player)
	runner.check(prompt.contains("Go to sleep") and not prompt.contains("saves"), "The bed says “Go to sleep” (%s)" % prompt)
	world.open_sleep()
	await _frames(2)
	var t := ""
	for l in world.modal.find_children("*", "Label", true, false):
		t += (l as Label).text + "\n"
	runner.check(not t.contains("Sleeping ends the day") and not t.contains("saves the game"), "The sleep prompt no longer explains what sleeping does")
	var buttons := []
	for b in world.modal.find_children("*", "Button", true, false):
		buttons.append((b as Button).text)
	runner.check(buttons.size() == 2 and "Sleep until 7:00 a.m." in buttons and "Not yet" in buttons, "Still exactly: Sleep until 7:00 a.m. / Not yet %s" % str(buttons))
	world.close_modal()
	await _unload()


# -----------------------------------------------------------------------------
# §5 The 90 % rule: the HUD, contracts, the outline and the flash all follow the snap
# -----------------------------------------------------------------------------

## Leave `frac` of a box's peak snow as a uniform layer on its first rect, the rest cleared.
func _leave(b: Dictionary, peak: float, frac: float) -> void:
	var res: float = Catalog.balance.contract_residual_depth
	var r0: Rect2 = b["rects"][0]
	for rr in b["rects"]:
		Snow.set_rect(rr, 0.0)
	Snow.add_layer_rect(r0, 0.1 + res)
	var ae := Boxes.snow_volume(b, true) / 0.1
	Snow.set_rect(r0, 0.0)
	Snow.add_layer_rect(r0, peak * frac / ae + res)
	b["peak"] = peak


func test_ninety_percent_snap_updates_everything() -> void:
	await _load_world("fun", 2024, 11.0, 1)
	Clock.running = true
	var pl: Player = world.player
	var lot := Layout.player_lot
	var b := Boxes.get_box(Boxes.lot_box(lot, "driveway"))
	var peak := Boxes.snow_volume(b, true)
	# A one-time contract on this very driveway (as if a client had hired us for it).
	Contracts._add_lot_listing(lot, 0, RandomNumberGenerator.new())
	var l: Dictionary = Contracts.listings[Contracts.listings.size() - 1]
	l["zones"] = [Contracts._zone("Driveway", [b["id"]])]
	l["type"] = "one_time"
	var c := Contracts.force_award(int(l["lid"]))
	var money0 := Game.money
	# Stand in the driveway, working it.
	var mid := (b["rects"][0] as Rect2).get_center()
	pl.teleport(Vector3(mid.x, 0.05, mid.y), 0.0)
	_leave(b, peak, 0.12)
	Boxes.note_work(mid)
	await _frames(30)
	runner.check(not b["complete"] and world.hud.contract_l.text.contains("88%"), "88 %% cleared: the HUD line shows 88 %% (%s)" % world.hud.contract_l.text.replace("\n", " | "))
	runner.check(world.box_outline.visible and world.box_outline.box_id == b["id"], "…and the work outline is up")
	_leave(b, peak, 0.095)
	Boxes.note_work(mid)
	await _frames(30)
	runner.check(b["complete"], "90.5 %% cleared: the box completes on its own (near-player measuring)")
	runner.check(world.hud.contract_l.text.contains("clear ✓"), "The HUD line reads “clear ✓” (%s)" % world.hud.contract_l.text.replace("\n", " | "))
	runner.check(is_equal_approx(world.hud.contract_bar.value, 1.0), "…with a full bar")
	runner.check(c["status"] == "completed" and Game.money == money0 + int(c["pay"]), "The contract completes and pays (%s, $%d → $%d)" % [c["status"], money0, Game.money])
	runner.check(not world.box_outline.visible, "The work outline is gone")
	runner.check(world.zone_markers._flash.visible, "The completion flash plays")
	runner.check(Snow.volume_in_rect(b["rects"][0]) < 1e-5, "Bare ground: the last ≤ 10 %% of the snow is gone")
	# A recurring visit and its snowed-in clock reset at the same 90 %.
	var side := Boxes.get_box(Boxes.lot_box(lot, "sidewalk"))
	Contracts._add_lot_listing(lot, 0, RandomNumberGenerator.new())
	var l2: Dictionary = Contracts.listings[Contracts.listings.size() - 1]
	l2["zones"] = [Contracts._zone("Sidewalk", [side["id"]])]
	l2["type"] = "recurring"
	var c2 := Contracts.force_award(int(l2["lid"]))
	c2["snowed_min"] = 20.0 * 60.0
	var speak := Boxes.snow_volume(side, true)
	_leave(side, speak, 0.095)
	Boxes.measure(side, true)
	Contracts.on_hour(Clock.day_index(), Clock.hour())
	runner.check(side["complete"] and c2["status"] == "serviced" and c2["visits"] >= 1, "A recurring visit is done at 90 %% (%s, %d visits)" % [c2["status"], c2["visits"]])
	runner.check(float(c2.get("snowed_min", 0.0)) < 1.0, "…and its 48-hour snowed-in clock resets (%.0f min)" % float(c2.get("snowed_min", 0.0)))
	Clock.running = false
	await _unload()


# -----------------------------------------------------------------------------
# §6 Picking up a tool lying in snow: at 75 % exposed
# -----------------------------------------------------------------------------

func _press_event(action: String) -> void:
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


## Lower (or raise) the snow over and around a lying tool so that `frac` of its sample points
## stand above the surface.
func _expose(it: ToolItem, frac: float) -> void:
	var pts := it.sample_points()
	var hs := []
	for p in pts:
		hs.append(p.y)
	hs.sort()
	var n := pts.size()
	var covered := n - int(round(frac * n))      # the lowest `covered` points stay under the snow
	var h := 0.0
	if covered <= 0:
		h = float(hs[0]) - 0.1
	elif covered >= n:
		h = float(hs[n - 1]) + 0.2
	else:
		h = (float(hs[covered - 1]) + float(hs[covered])) * 0.5 + ToolItem.EXPOSE_TOLERANCE
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var r := Rect2(lo, hi - lo).grow(0.4)
	var g := Snow.ground_at(r.get_center().x, r.get_center().y)
	Snow.set_rect(r, maxf(h - g, 0.0))


func _shovel_item() -> ToolItem:
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).tool_id == "small_shovel":
			return c
	return null


## Stand 1.3 m from the tool's middle, facing it, crosshair on the snow pile over it.
func _face_item(it: ToolItem) -> void:
	var pl: Player = world.player
	var pts := it.sample_points()
	var mid := Vector3.ZERO
	for p in pts:
		mid += p
	mid /= float(pts.size())
	var away := Vector2(1.3, 0).rotated(it.rotation.y + 0.9)
	var stand := Vector2(mid.x, mid.z) + away
	pl.teleport(Vector3(stand.x, Snow.ground_at(stand.x, stand.y) + 0.05, stand.y))
	var d := Vector2(mid.x, mid.z) - stand
	pl.set_yaw(atan2(-d.x, -d.y))
	await _frames(2)
	var aim := Vector3(mid.x, Snow.surface_height(mid.x, mid.z), mid.z)
	var e := pl.head.global_position
	pl.pitch = -atan2(e.y - aim.y, Vector2(aim.x - e.x, aim.z - e.z).length())
	pl.head.rotation.x = pl.pitch
	await _frames(4)


func test_shovel_pickup_at_75_percent() -> void:
	await _load_world("fun", 2024, 11.0, 0)
	var sh := _shovel_item()
	if not runner.check(sh != null, "the small shovel lies beside the truck"):
		return
	var pl: Player = world.player
	runner.check(sh.sample_points().size() >= 12 and sh.sample_points().size() <= 20, "exposure is measured at 12–20 points (%d)" % sh.sample_points().size())
	# Fully buried under the odd pile: no pickup.
	runner.check(sh.exposure() < 0.05, "fully buried at the start (%.0f %% exposed)" % (sh.exposure() * 100.0))
	await _face_item(sh)
	await _press_event("interact")
	runner.check(not ("small_shovel" in Game.slots), "fully buried: E does nothing")
	# About 60 % exposed: still no.
	_expose(sh, 0.6)
	await _face_item(sh)
	runner.check(sh.exposure() > 0.5 and sh.exposure() < 0.7, "about 60 %% exposed (%.0f %%)" % (sh.exposure() * 100.0))
	await _press_event("interact")
	runner.check(not ("small_shovel" in Game.slots), "60 %% exposed: no pickup (prompt: %s)" % pl.focus_prompt)
	runner.check(pl.focus_prompt == "" or pl.focus_prompt.contains("Dig") or pl.focus_prompt.contains("dig"), "…at most a short hint")
	# 75–80 %: picked up with real input, the crosshair on the pile.
	_expose(sh, 0.78)
	await _face_item(sh)
	var e := sh.exposure()
	runner.check(e >= 0.75 and e <= 0.85, "75–80 %% exposed (%.0f %%)" % (e * 100.0))
	var v0 := Snow.total_volume()
	runner.check(pl.focus_prompt.contains("Pick up"), "the pickup prompt shows (%s)" % pl.focus_prompt)
	await _press_event("interact")
	runner.check("small_shovel" in Game.slots, "75–80 %% exposed: E picks it up")
	runner.check(absf(Snow.total_volume() - v0) < 1e-4, "picking it up changes no snow")
	await _unload()


func test_tool_pickup_fully_exposed_and_after_snowfall() -> void:
	await _load_world("fun", 2024, 11.0, 1)
	var pl: Player = world.player
	var spot := Layout.lot_to_world(Layout.player_lot, Layout.gu(Layout.player_lot, -4.0), 1.0)
	Snow.set_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), 0.0)
	world.spawn_tool_item("standard_shovel", Vector3(spot.x, 0.0, spot.y), 0.3)
	await _frames(3)
	var it: ToolItem = null
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).tool_id == "standard_shovel":
			it = c
	if not runner.check(it != null, "a dropped standard shovel lies on bare ground"):
		return
	runner.check(is_equal_approx(it.exposure(), 1.0), "fully exposed on bare ground")
	await _face_item(it)
	await _press_event("interact")
	runner.check("standard_shovel" in Game.slots, "fully exposed: picked up as before")
	# Drop it again, let a big snowfall bury it, dig it to ~75 %.
	for k in range(4):
		if Game.slots[k] == "standard_shovel":
			Game.slots[k] = ""
	Game.inventory_changed.emit()
	world.spawn_tool_item("standard_shovel", Vector3(spot.x, 0.0, spot.y), 0.3)
	await _frames(3)
	it = null
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).tool_id == "standard_shovel":
			it = c
	Snow.add_snowfall(1.2)
	Snow.sync_all()
	await _frames(100)
	runner.check(it.exposure() < 0.3, "buried by the snowfall (%.0f %% exposed)" % (it.exposure() * 100.0))
	await _face_item(it)
	await _press_event("interact")
	runner.check(not ("standard_shovel" in Game.slots), "buried: no pickup")
	_expose(it, 0.8)
	await _face_item(it)
	await _press_event("interact")
	runner.check("standard_shovel" in Game.slots, "dug to %.0f %% exposed: picked up" % (it.exposure() * 100.0 if is_instance_valid(it) else 80.0))
	await _unload()


# -----------------------------------------------------------------------------
# §4 Gerry: the outlined trail, mailboxes, and following him inside
# -----------------------------------------------------------------------------

## Agree the trail with Gerry through his dialogue (as the tutorial test does).
func _take_gerry_job() -> void:
	Game.flags["mail_read"] = true
	Game.set_stage(Game.Stage.LETTER_READ)
	world.neighbor_dialogue(world.neighbor)
	await _frames(1)
	var guard := 0
	while world.modal_kind == "dialogue" and guard < 20:
		if not _press_btn(world.modal, "$55"):
			_press_btn(world.modal, "Continue")
		await _frames(1)
		guard += 1


func _press_btn(root: Node, text: String) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text.contains(text) and not (b as Button).disabled:
			(b as Button).pressed.emit()
			return true
	return false


func _finish_trail() -> void:
	for c in Contracts.active:
		if c.get("tutorial", false) and c["status"] == "active":
			for z in c["zones"]:
				for ra in z["rects"]:
					Snow.set_rect(Contracts.a_to_rect(ra), 0.004)
				Contracts.measure_zone(c, z)


## Watch Gerry for `frames` frames: the largest single-frame move while he's in view of the player
## (within 40 m), and whether the player could move.
func _watch_gerry(frames: int, walk_player := false) -> Dictionary:
	var g: Neighbor = world.neighbor
	var pl: Player = world.player
	var last := g.global_position
	var worst := 0.0
	var p0 := pl.global_position
	if walk_player:
		Input.action_press("move_forward")
	for k in range(frames):
		await _tree().physics_frame
		if not is_instance_valid(g):
			break
		var d := g.global_position.distance_to(last)
		if g.global_position.distance_to(pl.global_position) < 40.0:
			worst = maxf(worst, d)
		last = g.global_position
	if walk_player:
		Input.action_release("move_forward")
	return {"worst": worst, "moved": pl.global_position.distance_to(p0)}


## Stand `back` metres from `p` on the street side of Gerry's lot, facing it at chest height.
func _stand_near(p: Vector3, back: float, _face := Vector3.ZERO) -> void:
	var pl: Player = world.player
	var d := -Vector2(Layout.neighbor_lot["inward"])
	var at := Vector2(p.x, p.z) + d.normalized() * back
	pl.teleport(Vector3(at.x, Snow.ground_at(at.x, at.y) + 0.05, at.y))
	var to := Vector2(p.x - at.x, p.z - at.y)
	pl.set_yaw(atan2(-to.x, -to.y))
	var e := Snow.ground_at(at.x, at.y) + 1.6
	pl.pitch = -atan2(e - (p.y + 1.2), maxf(to.length(), 0.1))
	pl.head.rotation.x = pl.pitch


func test_gerry_trail_is_outlined_without_flags() -> void:
	await _load_world("fun", 2024, 11.0, 0)
	Clock.running = true
	await _take_gerry_job()
	runner.check(Game.stage() == Game.Stage.NEIGHBOR_TALKED, "Gerry's job agreed")
	await _frames(40)
	var tut: Dictionary = {}
	for c in Contracts.active:
		if c.get("tutorial", false):
			tut = c
	var stakes := 0
	for k in world.zone_markers._stakes.keys():
		if str(k).begins_with("%d_" % int(tut["id"])):
			stakes += 1
	runner.check(stakes == 0, "No flags or stakes on Gerry's trail (%d)" % stakes)
	var qo: BoxOutline = world.quest_outline
	runner.check(qo.visible and qo.box_id == "gerry_trail", "The trail is outlined from the moment the job is agreed")
	# Ten seconds of not working (and the player far away): still outlined.
	world.player.teleport(Vector3(Game.player_pos.x, 0.05, Game.player_pos.z + 20.0))
	await _frames(600)
	runner.check(qo.visible and qo.alpha > 0.9, "…and still outlined after 10 s without working, far away")
	runner.check(world.hud.objective_l.text.contains("outlined"), "The objective points to the outlined path (%s)" % world.hud.objective_l.text)
	# Another box worked on alongside: its own work outline shows.
	var drv := Boxes.get_box(Boxes.lot_box(Layout.player_lot, "driveway"))
	Boxes.note_work((drv["rects"][0] as Rect2).get_center())
	world.player.teleport(Vector3((drv["rects"][0] as Rect2).get_center().x, 0.05, (drv["rects"][0] as Rect2).get_center().y))
	await _frames(20)
	runner.check(world.box_outline.visible and world.box_outline.box_id == drv["id"] and qo.visible, "Working another box shows its usual outline alongside")
	# Real contracts keep their stakes.
	Contracts._add_lot_listing(Layout.lots[4], 0, RandomNumberGenerator.new())
	var l: Dictionary = Contracts.listings[Contracts.listings.size() - 1]
	var rc := Contracts.force_award(int(l["lid"]))
	await _frames(40)
	var rstakes := 0
	for k in world.zone_markers._stakes.keys():
		if str(k).begins_with("%d_" % int(rc["id"])):
			rstakes += 1
	runner.check(rstakes > 0, "Real contracts still get their stakes (%d)" % rstakes)
	# Completion: the outline goes and the usual work outline behaviour returns.
	_finish_trail()
	await _frames(5)
	runner.check(Game.stage() == Game.Stage.TRAIL_DONE and not qo.visible, "On completion the trail outline is gone")
	Clock.running = false
	await _unload()


func test_gerry_walks_in_and_player_follows() -> void:
	for mode in ["fun", "survival"]:
		await _load_world(mode, 2024, 11.0, 0)
		Clock.running = true
		var pl: Player = world.player
		await _take_gerry_job()
		var money0 := Game.money
		_finish_trail()
		runner.check(Game.stage() == Game.Stage.TRAIL_DONE and Game.money == money0 + 55, "%s: trail done, Gerry pays $55" % mode)
		var g: Neighbor = world.neighbor
		# He comes down the trail to meet you by his mailbox, walking all the way.
		var w := await _watch_gerry(600)
		runner.check(g.mode == "meet" and w["worst"] < 0.06, "%s: Gerry walks down to his mailbox (largest step %.3f m)" % [mode, w["worst"]])
		var mb: Vector2 = Layout.house_info(Layout.neighbor_lot)["mailbox_path_point"]
		runner.check(Vector2(g.global_position.x, g.global_position.z).distance_to(mb) < 1.0, "%s: …and waits there" % mode)
		# Talk to him (real input): he thanks you, invites you in and heads up the trail.
		_stand_near(g.global_position, 1.4, g.global_position + Vector3(0, 1.4, 0))
		await _frames(6)
		await _press_event("interact")
		await _frames(3)
		runner.check(g.invited and world.hud.speech_box.visible and world.hud.speech_text.text.contains("Come inside"), "%s: Gerry invites you in (on the HUD)" % mode)
		runner.check(world.modal == null, "%s: …without stopping you (no modal)" % mode)
		w = await _watch_gerry(120, true)
		runner.check(w["moved"] > 0.3, "%s: the player can move while he talks and walks (%.2f m)" % [mode, w["moved"]])
		runner.check(world.hud.objective_l.text == "Follow Gerry inside", "%s: objective: Follow Gerry inside" % mode)
		# Follow him to his door: he goes in once you're close.
		w = await _watch_gerry(400)
		var door := Neighbor.door_point()
		_stand_near(door, 2.6, door + Vector3(0, 1.4, 0))
		w = await _watch_gerry(500)
		runner.check(g.mode in ["entering", "to_fire", "inside"] and world.neighbor_door.open, "%s: at his door he opens it and goes in (%s)" % [mode, g.mode])
		runner.check(w["worst"] < 0.06, "%s: no jumps on the way in (%.3f m)" % [mode, w["worst"]])
		# The player walks in through the open door.
		_stand_near(door, 1.2, door + Vector3(0, 1.4, 0))
		var guard := 0
		Input.action_press("move_forward")
		while not pl.in_neighbor_house and guard < 240:
			await _frames(1)
			guard += 1
		Input.action_release("move_forward")
		runner.check(pl.in_neighbor_house, "%s: the player follows him in through the door" % mode)
		# The explanation: line by line on the HUD, Interact moves on; the computer bit.
		guard = 0
		while g.mode != "inside" and guard < 600:
			await _frames(1)
			guard += 1
		await _frames(5)
		runner.check(world.is_gerry_talking(), "%s: by the fire, Gerry talks you through the business" % mode)
		var saw_computer := false
		var saw_unlocked := false
		var p_in := pl.global_position
		guard = 0
		while world.is_gerry_talking() and guard < 40:
			var t: String = world.hud.speech_text.text
			if t.contains("computer"):
				saw_computer = true
			if t.contains("unlocked"):
				saw_unlocked = true
			await _frames(30)
			await _press_event("interact")
			guard += 1
		runner.check(saw_computer and saw_unlocked, "%s: the computer intro says what it's for and that it's unlocked" % mode)
		runner.check(g.mode in ["to_computer", "computer"], "%s: Gerry walked over to his computer (%s)" % [mode, g.mode])
		runner.check(Game.stage() == Game.Stage.COMPLETE and Game.computer_unlocked(), "%s: tutorial complete, computer unlocked" % mode)
		runner.check(Game.money == money0 + 55, "%s: paid once ($%d)" % [mode, Game.money - money0])
		if mode == "survival":
			runner.check(Survival.active, "survival: the cold is on")
		# You let yourself out.
		runner.check(world.neighbor_door.interact_prompt(pl) == "" or not world.neighbor_door.interact_prompt(pl).contains("locked"), "%s: you can let yourself out" % mode)
		Clock.running = false
	await _unload()


func test_gerry_waits_if_you_dont_follow_and_lets_you_in_first() -> void:
	await _load_world("fun", 2024, 21.5, 0)      # at night
	Clock.running = true
	var pl: Player = world.player
	await _take_gerry_job()
	_finish_trail()
	var g: Neighbor = world.neighbor
	await _watch_gerry(600)
	_stand_near(g.global_position, 1.4, g.global_position + Vector3(0, 1.4, 0))
	await _frames(6)
	await _press_event("interact")
	# Walk away: he goes up to his door and waits there, turned towards you, for as long as it takes.
	var far := Layout.lot_to_world(Layout.player_lot, 0.0, 6.0)
	pl.teleport(Vector3(far.x, 0.05, far.y))
	await _watch_gerry(900)
	runner.check(g.mode == "door_wait" and Game.stage() == Game.Stage.TRAIL_DONE, "Not following: Gerry waits at his door (%s)" % g.mode)
	await _frames(600)
	runner.check(g.mode == "door_wait", "…still waiting ten seconds later")
	runner.check(world.hud.objective_l.text == "Follow Gerry inside", "…with the objective up")
	await _unload()
	# Going in first: the door opens for you once you've been invited; he comes in after you.
	await _load_world("fun", 2024, 11.0, 0)
	Clock.running = true
	pl = world.player
	await _take_gerry_job()
	_finish_trail()
	g = world.neighbor
	await _watch_gerry(600)
	_stand_near(g.global_position, 1.4, g.global_position + Vector3(0, 1.4, 0))
	await _frames(6)
	await _press_event("interact")
	var door := Neighbor.door_point()
	_stand_near(door, 1.3, door + Vector3(0, 1.4, 0))
	await _frames(6)
	await _press_event("interact")
	runner.check(world.neighbor_door.open, "Going in first: you can open Gerry's door")
	var guard := 0
	Input.action_press("move_forward")
	while not pl.in_neighbor_house and guard < 240:
		await _frames(1)
		guard += 1
	Input.action_release("move_forward")
	runner.check(pl.in_neighbor_house, "…and walk in ahead of him")
	guard = 0
	while not world._talk_started and guard < 1500:
		await _frames(1)
		guard += 1
	runner.check(world._talk_started and world.is_gerry_talking() and g.mode == "inside", "He follows you in and starts talking by the fire (%s)" % g.mode)
	Clock.running = false
	await _unload()


func test_gerry_sequence_survives_save_and_load() -> void:
	await _load_world("fun", 2024, 11.0, 0)
	Clock.running = true
	await _take_gerry_job()
	_finish_trail()
	var g: Neighbor = world.neighbor
	await _watch_gerry(600)
	_stand_near(g.global_position, 1.4, g.global_position + Vector3(0, 1.4, 0))
	await _frames(6)
	await _press_event("interact")
	await _frames(60)
	runner.check(g.mode == "to_door", "Gerry is on his way to the door")
	# Save mid-sequence (as sleeping would) and load.
	runner.check(Saves.save_game(), "Saved mid-sequence")
	await _unload()
	runner.check(Saves.load_game("fun"), "Loaded")
	await _spawn_world()
	Clock.running = true
	g = world.neighbor
	var door := Neighbor.door_point()
	runner.check(g != null and g.mode == "door_wait" and g.global_position.distance_to(door) < 0.2, "On load Gerry is waiting at his door")
	await _frames(5)
	runner.check(world.hud.objective_l.text == "Follow Gerry inside", "…and the objective is back (%s)" % world.hud.objective_l.text)
	var pl: Player = world.player
	_stand_near(door, 2.6, door + Vector3(0, 1.4, 0))
	await _watch_gerry(500)
	runner.check(g.mode in ["entering", "to_fire", "inside"], "The sequence resumes: he goes in when you come")
	_stand_near(door, 1.2, door + Vector3(0, 1.4, 0))
	var guard := 0
	Input.action_press("move_forward")
	while not pl.in_neighbor_house and guard < 240:
		await _frames(1)
		guard += 1
	Input.action_release("move_forward")
	guard = 0
	while Game.stage() != Game.Stage.COMPLETE and guard < 3000:
		await _frames(30)
		if world.is_gerry_talking():
			await _press_event("interact")
		guard += 30
	runner.check(Game.stage() == Game.Stage.COMPLETE and Game.computer_unlocked(), "…through to the end: tutorial complete, computer unlocked")
	Clock.running = false
	await _unload()


func test_mailboxes_beside_paths_and_lamps_clear() -> void:
	await _load_world("fun", 2024, 11.0, 0)
	var trees: Array = world.refs["tree_points"]
	for lot in Layout.lots:
		if lot["vacant"]:
			continue
		var hi := Layout.house_info(lot)
		var mb: Vector2 = hi["mailbox"]
		var inside := []
		for b in Boxes.boxes:
			for r in b["rects"]:
				if (r as Rect2).grow(0.15).has_point(mb):
					inside.append(b["id"])
		runner.check(inside.is_empty(), "%s: the mailbox stands outside every box %s" % [lot["address"], str(inside)])
		var path := Boxes.get_box(Boxes.lot_box(lot, "path"))
		var reach := INF
		for r in path["rects"]:
			var rr: Rect2 = r
			reach = minf(reach, Vector2(clampf(mb.x, rr.position.x, rr.end.x), clampf(mb.y, rr.position.y, rr.end.y)).distance_to(mb))
		runner.check(reach < 1.0, "%s: …within reach from its path (%.2f m)" % [lot["address"], reach])
		var drv: Rect2 = hi["driveway"]
		var walk: Rect2 = hi["walkway"]
		runner.check(absf(mb.x - drv.get_center().x) > absf(walk.get_center().x - drv.get_center().x), "%s: …on the side of the path away from the driveway" % lot["address"])
		runner.check(Snow.ground_at(mb.x, mb.y) == 0.0 and (world.refs["mailboxes"][lot["index"]] as Node3D).global_position.y == 0.0, "%s: …standing on the ground" % lot["address"])
		var td := INF
		for t in trees:
			td = minf(td, mb.distance_to(t))
		runner.check(td > 1.8, "%s: …clear of trees (%.1f m)" % [lot["address"], td])
	# Gerry's trail is the walk and steps down to his mailbox, and no bigger than before.
	var trail := Layout.gerry_trail_rects()
	var mbg: Vector2 = Layout.house_info(Layout.neighbor_lot)["mailbox"]
	var near := INF
	var area := 0.0
	for r in trail:
		var rr: Rect2 = r
		area += rr.get_area()
		near = minf(near, Vector2(clampf(mbg.x, rr.position.x, rr.end.x), clampf(mbg.y, rr.position.y, rr.end.y)).distance_to(mbg))
	runner.check(near < 1.0, "Gerry's trail reaches his mailbox (%.2f m)" % near)
	var hig := Layout.house_info(Layout.neighbor_lot)
	runner.check(area <= (hig["walkway"] as Rect2).get_area() + (hig["stairs"] as Rect2).get_area(), "…and is less work than the old trail (%.1f m2)" % area)
	# Street lamps: none on a driveway apron, a walkway or a mailbox.
	var bad := []
	for x in world.builder.lamp_poles():
		var pole2: Vector2 = x
		for lot in Layout.lots:
			if lot["vacant"]:
				continue
			var h3 := Layout.house_info(lot)
			if (h3["driveway"] as Rect2).has_point(pole2) or (h3["walkway"] as Rect2).has_point(pole2) or (h3["mailbox"] as Vector2).distance_to(pole2) < 1.0:
				bad.append(str(pole2))
	runner.check(bad.is_empty(), "No street lamp stands on a driveway apron, a walkway or a mailbox %s" % str(bad))
	# The keys aren't under or next to a mailbox.
	var kp: Array = Game.flags.get("keys_pos", [0, 0])
	runner.check(Vector2(kp[0], kp[1]).distance_to(Layout.house_info(Layout.player_lot)["mailbox"]) > 2.0, "The buried keys aren't next to a mailbox")
	await _unload()


## Old saves (the mid-trail fixtures, made before the mailboxes moved) load with Gerry's trail
## rebuilt from the new rectangles, its progress taken from the snow, and still finish properly.
func test_mid_trail_fixture_uses_the_new_trail() -> void:
	for name in ["fun_2_mid_trail.json", "survival_2_mid_trail.json"]:
		var ok: bool = await _load_fixture(name)
		runner.check(ok, "%s loads" % name)
		var b := Boxes.get_box("gerry_trail")
		var want := Layout.gerry_trail_rects()
		runner.check(not b.is_empty() and b["rects"].size() == want.size() and (b["rects"][0] as Rect2).is_equal_approx(want[0]), "%s: the trail is rebuilt on the new rectangles" % name)
		var c: Dictionary = {}
		for cc in Contracts.active:
			if cc.get("tutorial", false):
				c = cc
		runner.check(not c.is_empty() and Contracts.a_to_rect(c["zones"][0]["rects"][0]).is_equal_approx(want[0]), "%s: …and the contract's zone follows" % name)
		var v := Boxes.snow_volume(b, true)
		runner.check(float(b["peak"]) >= v and float(b["progress"]) > 0.05 and not b["complete"], "%s: progress taken from the snow (%.0f %%, %.2f of %.2f m3 left)" % [name, b["progress"] * 100.0, v, b["peak"]])
		await _spawn_world()
		Clock.running = true
		await _frames(30)
		runner.check(world.quest_outline.visible and world.quest_outline.box_id == "gerry_trail", "%s: the trail is outlined" % name)
		var money0 := Game.money
		_finish_trail()
		await _frames(2)
		runner.check(Game.stage() == Game.Stage.TRAIL_DONE and Game.money == money0 + int(c["pay"]), "%s: finishing it still pays and moves the tutorial on" % name)
		Clock.running = false
	await _unload()


# -----------------------------------------------------------------------------
# §1 The main menu
# -----------------------------------------------------------------------------

const MENU_SEED := 4711


func _open_menu() -> Node:
	await _unload()
	var m: Node = load("res://scenes/main_menu.tscn").instantiate()
	runner.add_child(m)
	await _frames(4)
	return m


func _close_menu(m: Node) -> void:
	if m != null and is_instance_valid(m):
		m.queue_free()
	await _tree().process_frame
	await _tree().process_frame


static func _sha(v) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(var_to_bytes(v))
	return hc.finish().hex_encode()


## Everything a game starts from (all a save holds) plus the transient state a menu could leak.
func _game_sig() -> Dictionary:
	return {
		"snow": _sha(Snow.serialize()),
		"snow_auto": Snow.auto_process,
		"relax_pending": Snow.relax_pending(),
		"money": Game.money,
		"game": _sha(Game.serialize()),
		"date_time": Clock.minutes,
		"time_scale": Clock.time_scale,
		"weather": _sha(Weather.serialize()),
		"weather_override": [Weather.override_cond, Weather.override_rate, Weather.override_until],
		"contracts": _sha(Contracts.serialize()),
		"economy": _sha(Economy.serialize()),
		"municipal": _sha(Municipal.serialize()),
		"survival": _sha(Survival.serialize()),
		"boxes": _sha(Boxes.serialize()),
		"notifications": _sha(Notify.history),
	}


func _sig_diff(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	for k in a.keys():
		if str(a[k]) != str(b.get(k)):
			out.append(k)
	return out


## Save files on disk (name -> modified time), to prove the menu writes nothing.
func _save_files() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(Saves.DIR)
	if dir:
		for f in dir.get_files():
			out[f] = FileAccess.get_modified_time(Saves.DIR.path_join(f))
	return out


## PLAY -> the mode's New Game / Continue button (cards are Fun, then Survival).
func _menu_start(m: Node, mode: String, button: String) -> Dictionary:
	var got := {}
	m.set("seed_override", MENU_SEED)
	m.set("start_hook", func(md: String, fresh: bool): got["mode"] = md; got["fresh"] = fresh; got["sig"] = _game_sig())
	if not _press_btn(m, "PLAY"):
		return got
	await _frames(2)
	var btns := []
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).text == button:
			btns.append(b)
	var i := 0 if mode == "fun" else 1
	if btns.size() < 2 or (btns[i] as Button).disabled:
		got["disabled"] = true
		return got
	(btns[i] as Button).pressed.emit()
	for k in range(30):
		await _frames(1)
		if got.has("sig"):
			break
	return got


func test_menu_top_level_is_title_play_settings_exit() -> void:
	var m := await _open_menu()
	var root: Control = m.get("root_ui")
	var buttons := []
	var labels := []
	for c in root.find_children("*", "Button", true, false):
		if (c as Control).is_visible_in_tree():
			buttons.append((c as Button).text)
	for c in root.find_children("*", "Label", true, false):
		if (c as Control).is_visible_in_tree():
			labels.append((c as Label).text)
	runner.check(buttons == ["PLAY", "SETTINGS", "EXIT"], "Top level buttons are exactly PLAY, SETTINGS, EXIT (%s)" % [buttons])
	runner.check(labels == ["CANADIAN\nWINTER"], "The only text on the top level is the title (%s)" % [labels])
	runner.check(bool(m.get("_built")) and m.get("cam") != null and (m.get("cam") as Camera3D).current, "The neighbourhood background is built behind the menu")
	# The tagline and the credit line are gone from the top level; the credit line lives in Play.
	_press_btn(m, "PLAY")
	await _frames(2)
	var play_text := []
	for c in (m.get("play_panel") as Node).find_children("*", "Label", true, false):
		play_text.append((c as Label).text)
	runner.check(not str(play_text).contains("Survive the winter"), "No slogan anywhere in the Play flow")
	runner.check(str(play_text).contains("procedurally made"), "The single-player / procedural note moved into the Play panel")
	await _close_menu(m)


func test_menu_exit_quits_through_the_hook() -> void:
	var m := await _open_menu()
	var quit := [false]
	m.set("quit_hook", func(): quit[0] = true)
	runner.check(_press_btn(m, "EXIT"), "EXIT button pressed")
	await _frames(1)
	runner.check(quit[0], "EXIT quits (through the test hook in place of get_tree().quit())")
	await _close_menu(m)


func test_menu_play_mode_new_game_and_continue() -> void:
	for mode in ["fun", "survival"]:
		Saves.delete_save(mode)
		var m := await _open_menu()
		var r := await _menu_start(m, mode, "Continue")
		runner.check(r.get("disabled", false), "%s: Continue is disabled without a save" % mode)
		await _close_menu(m)
		m = await _open_menu()
		r = await _menu_start(m, mode, "New Game")
		runner.check(r.get("mode", "") == mode and r.get("fresh", false) and Game.mode == mode and Game.stage() == Game.Stage.START, "%s: PLAY -> %s -> New Game starts a fresh game" % [mode, mode.capitalize()])
		await _close_menu(m)
		# Leave a recognisable save, then Continue it from the menu.
		Game.money = 777
		Clock.reset(Clock.at(3, 13.0))
		runner.check(Saves.save_game(), "%s: save written" % mode)
		Game.new_game(mode, 1)
		m = await _open_menu()
		r = await _menu_start(m, mode, "Continue")
		runner.check(r.get("mode", "") == mode and not r.get("fresh", true) and Game.money == 777 and is_equal_approx(Clock.minutes, Clock.at(3, 13.0)), "%s: PLAY -> %s -> Continue loads the save" % [mode, mode.capitalize()])
		await _close_menu(m)
		Saves.delete_save(mode)


## The menu ran for two minutes before New Game: the game starts exactly as it does straight away
## (and as it does with no menu at all). Nothing ticks, saves or notifies while the menu is up.
func test_menu_two_minutes_leaves_no_trace() -> void:
	for mode in ["fun", "survival"]:
		Saves.delete_save(mode)
	Game.new_game("fun", MENU_SEED)
	var direct := _game_sig()
	var m := await _open_menu()
	var r := await _menu_start(m, "fun", "New Game")
	await _close_menu(m)
	runner.check(r.has("sig") and _sig_diff(direct, r["sig"]).is_empty(), "Menu -> New Game straight away = New Game with no menu (diff %s)" % [_sig_diff(direct, r.get("sig", {}))])
	# Two minutes of menu.
	m = await _open_menu()
	var notes := Notify.history.size()
	var files := _save_files()
	var minutes := Clock.minutes
	var shots := {}
	var cam: Camera3D = m.get("cam")
	var p0 := cam.global_position
	var max_jump := 0.0
	var last := p0
	var last_shot: int = m.call("shot_index")
	for i in range(7200):
		await _tree().process_frame
		var si: int = m.call("shot_index")
		shots[si] = true
		if si == last_shot:   # a change of shot is a cut under the fade; within a shot it glides
			max_jump = maxf(max_jump, cam.global_position.distance_to(last))
		last_shot = si
		last = cam.global_position
	runner.check(shots.size() >= 2, "The camera moved through %d shots in two minutes" % shots.size())
	runner.check(max_jump < 0.1, "The camera glides (largest step within a shot %.3f m/frame)" % max_jump)
	runner.check(Clock.minutes == minutes and not Clock.running, "The clock did not run behind the menu")
	runner.check(Notify.history.size() == notes, "No notifications from the menu")
	runner.check(_save_files() == files, "Nothing was saved by the menu")
	runner.check(Game.world == null and Game.player == null and not Game.in_game, "Nothing registered in Game")
	runner.check(not Snow.auto_process and Snow.relax_pending() == 0, "The background snow is a still snapshot (no relaxation)")
	r = await _menu_start(m, "fun", "New Game")
	await _close_menu(m)
	runner.check(r.has("sig") and _sig_diff(direct, r["sig"]).is_empty(), "After two minutes of menu the new game is identical (diff %s)" % [_sig_diff(direct, r.get("sig", {}))])
	runner.check(Snow.auto_process and Weather.override_cond == -1, "Snow processing and the weather are handed back to the game")
	# Survival, straight after a short menu.
	Game.new_game("survival", MENU_SEED)
	direct = _game_sig()
	m = await _open_menu()
	await _frames(240)
	r = await _menu_start(m, "survival", "New Game")
	await _close_menu(m)
	runner.check(r.has("sig") and _sig_diff(direct, r["sig"]).is_empty(), "Survival: menu -> New Game identical to no menu (diff %s)" % [_sig_diff(direct, r.get("sig", {}))])


func test_menu_fixture_load_is_the_same_as_direct() -> void:
	for name in ["fun_3_contract.json", "survival_4_midwinter.json"]:
		var mode := "fun" if name.begins_with("fun") else "survival"
		runner.check(await _load_fixture(name), "%s loads directly" % name)
		var direct := _game_sig()
		var m := await _open_menu()
		await _frames(600)
		var r := await _menu_start(m, mode, "Continue")
		await _close_menu(m)
		runner.check(r.has("sig") and _sig_diff(direct, r["sig"]).is_empty(), "%s: Continue from the menu (after 10 s of menu) = direct load (diff %s)" % [name, _sig_diff(direct, r.get("sig", {}))])
		Saves.delete_save(mode)


## Play, return to the menu (as the pause menu does), start again: as clean as the first time.
func test_menu_return_and_start_again_is_clean() -> void:
	Saves.delete_save("fun")
	Game.new_game("fun", MENU_SEED)
	var direct := _game_sig()
	var m := await _open_menu()
	var r := await _menu_start(m, "fun", "New Game")
	await _close_menu(m)
	runner.check(r.has("sig"), "Started from the menu")
	# Play a little: the world runs, time passes, snow is moved.
	await _spawn_world()
	Clock.running = true
	runner.check(Snow.auto_process and Clock.running, "In game the snow and the clock run")
	var pl: Player = world.player
	await _hold("move_forward", 30)
	Game.money += 100
	await _frames(60)
	runner.check(Clock.minutes > Clock.at(0, 7.5), "Time passed in game")
	await _unload()
	m = await _open_menu()
	await _frames(300)
	r = await _menu_start(m, "fun", "New Game")
	await _close_menu(m)
	runner.check(r.has("sig") and _sig_diff(direct, r["sig"]).is_empty(), "Back to the menu and New Game again: identical to a first start (diff %s)" % [_sig_diff(direct, r.get("sig", {}))])
	# And the game world after that start runs normally.
	await _spawn_world()
	runner.check(world.player != null and Snow.auto_process and Weather.override_cond == -1, "The second game runs with the snow and weather live")
	await _unload()
	if pl:
		pass


## Graphics settings changed over the running background apply to it at once.
func test_menu_respects_graphics_settings() -> void:
	var m := await _open_menu()
	var before := int(Settings.get_value("graphics", "preset", 1))
	var keep := {}
	for k in ["shadows", "snow_detail", "particles", "draw_distance", "msaa"]:
		keep[k] = Settings.get_value("graphics", k)
	_press_btn(m, "SETTINGS")
	await _frames(2)
	Settings.set_value("graphics", "preset", 0)
	await _frames(2)
	var cam: Camera3D = m.get("cam")
	var fx: WeatherFX = m.get("_weather_fx")
	runner.check(is_equal_approx(cam.far, 140.0) and is_equal_approx(fx.density, 0.4) and not (m.get("gerry") as Node3D).visible, "Low preset: shorter view, fewer flakes, fewer figures (far %.0f, density %.1f)" % [cam.far, fx.density])
	Settings.set_value("graphics", "preset", 2)
	await _frames(2)
	runner.check(is_equal_approx(cam.far, 350.0) and (m.get("gerry") as Node3D).visible, "High preset: full view and every figure")
	# Put the user's settings back.
	Settings.cfg.set_value("graphics", "preset", before)
	for k in keep.keys():
		Settings.set_value("graphics", k, keep[k])
	# Back from Settings: the background keeps running.
	for sm in m.find_children("*", "SettingsMenu", true, false):
		sm.queue_free()
	await _frames(2)
	var d0 := float(m.get("_shot_d"))
	var c0 := cam.global_position
	await _frames(30)
	runner.check(float(m.get("_shot_d")) > d0 and cam.global_position.distance_to(c0) > 0.1, "Back from Settings the camera keeps gliding")
	await _close_menu(m)


# -----------------------------------------------------------------------------
# §7 A play-through from the menu with real input, both modes
# -----------------------------------------------------------------------------

## Stand at `p` (on the ground, wading if it's snowy) with the crosshair on `look`.
func _stand_at(p: Vector2, look: Vector3) -> void:
	var pl: Player = world.player
	pl.teleport(Vector3(p.x, Snow.ground_at(p.x, p.y) + 0.05, p.y))
	await _frames(2)
	var d := look - pl.head.global_position
	pl.set_yaw(atan2(-d.x, -d.z))
	pl.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	pl.head.rotation.x = pl.pitch
	await _frames(4)


## Most of a box already dug out (12 % of its peak left), then real shovel strokes along it —
## scoop, turn to `away`, throw — until the 90 % snap clears the rest. Returns the strokes used.
func _shovel_to_snap(b: Dictionary, away: Vector2, avoid: Vector2, avoid_r: float, frac := 0.12) -> int:
	var pl: Player = world.player
	var peak := Boxes.snow_volume(b, true)
	_leave(b, peak, frac)
	Boxes.measure(b, true)
	var r0: Rect2 = b["rects"][0]
	var long_x := r0.size.x > r0.size.y
	var half := (r0.size.y if long_x else r0.size.x) * 0.5
	var side := away.normalized() * maxf(half - 0.8, 0.0)
	var strokes := 0
	for k in range(30):
		if b["complete"]:
			break
		var f := (float(k % 15) + 0.5) / 15.0
		var at := r0.get_center() + side
		if long_x:
			at.x = r0.position.x + r0.size.x * f
		else:
			at.y = r0.position.y + r0.size.y * f
		if at.distance_to(avoid) < avoid_r:
			continue
		var along := Vector2(1, 0) if long_x else Vector2(0, 1)
		if k >= 15:
			along = -along
		pl.teleport(Vector3(at.x, Snow.ground_at(at.x, at.y) + 0.05, at.y))
		pl.set_yaw(atan2(-along.x, -along.y))
		pl.pitch = deg_to_rad(-50.0)
		pl.head.rotation.x = pl.pitch
		await _frames(3)
		var base := pl.yaw
		Input.action_press("primary")
		for s in range(30):
			pl.set_yaw(base + 0.35 * sin(s * 0.2))
			await _tree().physics_frame
		pl.set_yaw(atan2(-away.x, -away.y))
		pl.pitch = deg_to_rad(5.0)
		pl.head.rotation.x = pl.pitch
		await _frames(4)
		Input.action_release("primary")
		await _frames(24)
		strokes += 1
	return strokes


func test_playthrough_from_the_menu_both_modes() -> void:
	for mode in ["fun", "survival"]:
		Saves.delete_save(mode)
		# The menu: PLAY -> mode -> New Game, then the game scene as the menu would load it.
		var m := await _open_menu()
		var r := await _menu_start(m, mode, "New Game")
		await _close_menu(m)
		runner.check(r.get("mode", "") == mode, "%s: started from the menu" % mode)
		Game.force_input = true
		await _spawn_world()
		Clock.running = true
		var pl: Player = world.player
		var lot := Layout.player_lot
		var hi := Layout.house_info(lot)
		# 1. The opening: the letter in the mailbox, the small shovel dug out to 75 %.
		var mb: Vector2 = hi["mailbox"]
		await _stand_at(hi["mailbox_path_point"], Vector3(mb.x, Snow.ground_at(mb.x, mb.y) + 1.05, mb.y))
		runner.check(pl.focus_prompt.to_lower().contains("mailbox"), "%s: the mailbox prompt shows from the path (%s)" % [mode, pl.focus_prompt])
		await _press_event("interact")
		runner.check(world.modal_kind == "letter", "%s: the hydro letter opens" % mode)
		_press_btn(world.modal, "Close")
		await _frames(10)
		runner.check(Game.stage() == Game.Stage.LETTER_READ, "%s: the letter is read" % mode)
		var sh := _shovel_item()
		_expose(sh, 0.78)
		await _face_item(sh)
		await _press_event("interact")
		var slot := Game.slots.find("small_shovel")
		runner.check(slot >= 0, "%s: the small shovel is picked up at %.0f %% exposed" % [mode, sh.exposure() * 100.0 if is_instance_valid(sh) else 78.0])
		# 2. Gerry's job: talk to him on his porch, agree the price; the trail is outlined, no flags.
		var g: Neighbor = world.neighbor
		_stand_near(g.global_position, 3.0)
		await _frames(4)
		await _press_event("interact")
		await _frames(2)
		var guard := 0
		while world.modal_kind == "dialogue" and guard < 20:
			if not _press_btn(world.modal, "$55"):
				_press_btn(world.modal, "Continue")
			await _frames(1)
			guard += 1
		runner.check(Game.stage() == Game.Stage.NEIGHBOR_TALKED, "%s: Gerry's job agreed" % mode)
		await _frames(20)
		var stakes := 0
		for k in world.zone_markers._stakes.keys():
			for c in Contracts.active:
				if c.get("tutorial", false) and str(k).begins_with("%d_" % int(c["id"])):
					stakes += 1
		runner.check(world.quest_outline.visible and world.quest_outline.box_id == "gerry_trail" and stakes == 0, "%s: the trail has the blue outline and no flags" % mode)
		var money0 := Game.money
		_finish_trail()
		runner.check(Game.stage() == Game.Stage.TRAIL_DONE and Game.money == money0 + 55, "%s: trail cleared, Gerry pays" % mode)
		# 3. Follow Gerry inside; the computer intro.
		guard = 0
		while g.mode != "meet" and guard < 900:
			await _frames(1)
			guard += 1
		_stand_near(g.global_position, 1.4)
		await _frames(4)
		await _press_event("interact")
		await _frames(3)
		runner.check(g.invited, "%s: Gerry invites you in" % mode)
		guard = 0
		while g.mode != "door_wait" and guard < 900:
			await _frames(1)
			guard += 1
		var door := Neighbor.door_point()
		_stand_near(door, 1.2)
		guard = 0
		while not world.neighbor_door.open and guard < 300:
			await _frames(1)
			guard += 1
		Input.action_press("move_forward")
		guard = 0
		while not pl.in_neighbor_house and guard < 300:
			await _frames(1)
			guard += 1
		Input.action_release("move_forward")
		runner.check(pl.in_neighbor_house, "%s: you follow him in" % mode)
		var saw_computer := false
		guard = 0
		while Game.stage() != Game.Stage.COMPLETE and guard < 60:
			await _frames(30)
			if world.hud.speech_text.text.contains("computer"):
				saw_computer = true
			if world.is_gerry_talking() and world._talk_started:
				await _press_event("interact")
			guard += 1
		runner.check(saw_computer and Game.stage() == Game.Stage.COMPLETE, "%s: the computer intro, tutorial complete" % mode)
		# 4. Home: the computer is unlocked.
		var comp: Node3D = world.interior["computer"]
		var cp := Vector2(comp.global_position.x, comp.global_position.z)
		var room := Vector2(hi["body"].get_center()) - cp
		await _stand_at(cp + room.normalized() * 1.2, comp.global_position)
		await _press_event("interact")
		await _frames(2)
		runner.check(world.modal_kind == "computer", "%s: your computer opens (unlocked)" % mode)
		# 6. Take a contract on the board (lowest bid on the first listings), hear back later.
		var won := false
		if world.modal_kind == "computer":
			var c: ComputerUI = world.modal
			c._open_app(0)
			await _frames(1)
			for tries in range(4):
				var sl := c.content.find_children("*", "HSlider", true, false)
				if sl.is_empty():
					break
				(sl[0] as HSlider).value = (sl[0] as HSlider).min_value
				_press_btn(c.content, "Place bid")
				await _frames(1)
			runner.check(not Contracts.bids.is_empty(), "%s: bids placed from the contract board" % mode)
			world.close_modal()
		Clock.skip(240.0)
		for ct in Contracts.active:
			if not ct.get("tutorial", false):
				won = true
		runner.check(won, "%s: a contract is won (%d active)" % [mode, Contracts.active.size()])
		# 5. Clear your own path and driveway: the 90 % snap.
		var walk: Rect2 = hi["walkway"]
		var drv: Rect2 = hi["driveway"]
		var away_x := signf(walk.get_center().x - drv.get_center().x)
		var truck := Vector2(Game.vehicles[0]["pos"].x, Game.vehicles[0]["pos"].z)
		for which in ["path", "driveway"]:
			var b := Boxes.get_box(Boxes.lot_box(lot, which))
			var away := Vector2(away_x if which == "path" else -away_x, 0.0)
			# Most of it already dug: 12 % of the path's peak left, 10.5 % of the (much bigger) driveway's.
			var n := await _shovel_to_snap(b, away, truck, 3.6, 0.12 if which == "path" else 0.105)
			runner.check(b["complete"], "%s: %s cleared with the shovel — the 90 %% snap (%d strokes)" % [mode, which, n])
			var left := 0.0
			for rr in b["rects"]:
				left += Snow.volume_in_rect(rr)
			runner.check(left < 1e-4, "%s: …and the %s is bare (%.4f m³ left)" % [mode, which, left])
		# 7. Sleep in your bed.
		var bed: Node3D = world.interior["bed"]
		var bp := Vector2(bed.global_position.x, bed.global_position.z)
		var bin := Vector2(hi["body"].get_center()) - bp
		await _stand_at(bp + bin.normalized() * 1.5, bed.global_position)
		runner.check(pl.focus_prompt.contains("Go to sleep"), "%s: the bed says Go to sleep (%s)" % [mode, pl.focus_prompt])
		await _press_event("interact")
		await _frames(2)
		runner.check(world.modal_kind == "sleep", "%s: the sleep prompt" % mode)
		_press_btn(world.modal, "Sleep until 7:00 a.m.")
		guard = 0
		while (not Saves.has_save(mode) or Game.dirty_since_save) and guard < 600:
			await _frames(5)
			guard += 5
		await _frames(30)
		runner.check(Saves.has_save(mode) and Clock.hour() == 7, "%s: slept to 7:00, saved" % mode)
		# 8. Reload.
		Clock.running = false
		var saved := Saves.peek(mode)
		var money_s := int(saved.get("money", -1))
		var t_s := float(saved.get("time", -1.0))
		var n_active := Contracts.active.size()
		await _unload()
		runner.check(Saves.load_game(mode), "%s: the save reloads" % mode)
		var t_l := Clock.minutes
		await _spawn_world()
		runner.check(Game.money == money_s and absf(t_l - t_s) < 0.01 and Contracts.active.size() == n_active and Game.stage() == Game.Stage.COMPLETE and Game.computer_unlocked() and Game.owns_tool("small_shovel"), "%s: reloaded with the money, time, contracts, tutorial and shovel ($%d/$%d, %.1f/%.1f, %d/%d contracts, stage %d, slots %s)" % [mode, Game.money, money_s, Clock.minutes, t_s, Contracts.active.size(), n_active, Game.stage(), str(Game.slots)])
		if mode == "survival":
			runner.check(Survival.active and not world._dead, "survival: alive, the cold on")
		_release_all()
		await _unload()
		Saves.delete_save(mode)
