extends Node
## Polish 3 §0: builds the save fixtures in tests/fixtures/polish3/ with the current build, for
## both modes, at four points of a game:
##   1_opening      first night of the opening (letter not read, everything buried)
##   2_mid_trail    Gerry's trail accepted and partly cleared
##   3_contract     tutorial done, a paid contract running
##   4_midwinter    time-jumped (as the F1 menu does) to about Jan 20 with snow on the ground
## Run: godot --headless --fixed-fps 60 --path . res://tests/make_fixtures.tscn
##
## Polish 4 §0: `-- --set=polish4` builds tests/fixtures/polish4/ instead, at six points:
##   1_opening, 2_mid_trail   as above
##   3_trail_done             Gerry's trail cleared (stage TRAIL_DONE): Gerry waits at his door
##   4_contract, 5_midwinter  as 3_contract / 4_midwinter above
##   6_storm                  partway through a scheduled storm (from the weather schedule, not the
##                            F1 override), heavy snow falling
##
## Polish 5 §0: `-- --set=polish5` builds tests/fixtures/polish5/ (fun_*/survival_*), at six points,
## using the F1 developer menu's own buttons (DebugMenu, pressed in code) for money, spawns, snow
## and time jumps, the computer's store (Economy.buy) for purchases and the E-press
## (ToolItem.interact) to collect them:
##   1_contracts   tutorial done; a one-time job and a recurring contract won from the board
##                 (Contracts.force_award, what F1's "Win first listing" calls, picking the kind);
##                 listings still open on the board
##   2_upgrades    every upgrade in the catalog bought and collected (the pickup plow fitted at the
##                 store), three hand tools bought and in the slots, and a small blower (polish 5
##                 §13: the tools first, then every level of the items owned)
##   3_vehicle     keys dug up and found, the driveway cleared, an ATV with blade bought and parked
##                 in the driveway in front of the pickup
##   4_midwinter   around Jan 20: the first board from Jan 19 that lists 24 or 28 Maple Street (with
##                 seed 2024, Jan 22's: 28 Maple Street), that job won; then, as Jan 20's major event
##                 left the street deeper than the hips, on to noon after the city grader's next
##                 scheduled pass (Jan 23), +1 hour; snow on both lots
##   5_evening     8:30 p.m. on Dec 3 with listings open
##   6_winter2     winter 2, Dec 2, reputation raised as far as F1 allows (residential jobs won from
##                 the board and cleared with "Clear all snow", visits re-snowed with "Add
##                 globally", on Mar 30–31 of winter 1; recurring contracts renewed)
## A summary of every polish-5 fixture, read back from the file, is printed at the end.
## `-- --set=polish5 --verify` only prints those summaries (from the existing files).
##
## Polish 6 §0: `-- --set=polish5_v3` builds tests/fixtures/polish5_v3/ (fun_*/survival_*): the six
## polish-5 points above, made the same way with this build (version-3 saves; round 5 §17 never made
## them; 6_winter2's reputation is F1's Reputation "Set" at 100, as the board loop wins nothing at
## this build), plus one more point for polish 6 §10's migration:
##   7_keys_pickup_plow_order  tutorial done, Dec 2 (day 1): the truck keys dug up under the lawn
##                 tree and picked up; the plain pickup where a new game puts it, in the player's
##                 driveway (snowed in as it starts); the front plow (ItemUpgrades.PLOW_ID) bought from
##                 the computer's store at 10:00, its order open and not fitted ("Waiting in the
##                 store lot": the pickup never went to the store)
## `-- --set=polish5_v3 --verify` prints their summaries.
## Options: --only=<point part>  --mode=fun|survival

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _ItemUpgrades := preload("res://scripts/data/item_upgrades.gd")

var OUT := "res://tests/fixtures/polish3/"
var p5 := false
var made: Array = []

var world: Node = null


func _ready() -> void:
	await get_tree().process_frame
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var modes := ["fun", "survival"]
	var points := ["1_opening", "2_mid_trail", "3_contract", "4_midwinter"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			modes = [a.substr(7)]
		if a == "--set=polish4":
			OUT = "res://tests/fixtures/polish4/"
			points = ["1_opening", "2_mid_trail", "3_trail_done", "4_contract", "5_midwinter", "6_storm"]
		if a == "--set=polish5":
			OUT = "res://tests/fixtures/polish5/"
			points = P5_POINTS
			p5 = true
		if a == "--set=polish5_v3":
			OUT = "res://tests/fixtures/polish5_v3/"
			points = P5_POINTS + P6_POINTS
			p5 = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var verify_only := OS.get_cmdline_user_args().has("--verify")
	for mode in modes:
		for point in points:
			if only == "" or point.contains(only):
				if verify_only:
					made.append(OUT + "%s_%s.json" % [mode, point])
				else:
					await _make(mode, point)
	if p5:
		await _verify_all()
	print("FIXTURES DONE")
	# AudioMgr.quit: stop every sound before quitting, so nothing is reported leaked at exit
	# (HANDOFF §13 item 13).
	AudioMgr.quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _make(mode: String, point: String) -> void:
	if world and is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	Game.force_input = true
	Game.new_game(mode, 2024)
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await _frames(3)
	if p5:
		await _p5_setup(point)
	match ("" if p5 else point):
		"1_opening":
			Clock.skip(Clock.at(0, 21.0) - Clock.minutes)
		"2_mid_trail":
			Game.flags["mail_read"] = true
			Game.set_stage(Game.Stage.LETTER_READ)
			Contracts.create_tutorial_contract(50)
			Game.set_stage(Game.Stage.NEIGHBOR_TALKED)
			# Clear the first part of the trail: the walkway end nearest the porch steps.
			var b := Boxes.get_box("gerry_trail")
			var r: Rect2 = b["rects"][0]
			Snow.set_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45)), 0.0)
			Boxes.measure(Boxes.get_box("gerry_trail"))
			Clock.skip(Clock.at(0, 13.0) - Clock.minutes)
		"3_trail_done":
			Game.flags["mail_read"] = true
			Game.set_stage(Game.Stage.LETTER_READ)
			Contracts.create_tutorial_contract(50)
			Game.set_stage(Game.Stage.NEIGHBOR_TALKED)
			for c in Contracts.active:
				if c.get("tutorial", false):
					for z in c["zones"]:
						for ra in z["rects"]:
							Snow.set_rect(Contracts.a_to_rect(ra), 0.004)
						Contracts.measure_zone(c, z)
			Clock.skip(Clock.at(0, 14.0) - Clock.minutes)
		"6_storm":
			world.debug_complete_tutorial()
			# The first scheduled storm after Jan 1, joined 40 % of the way in.
			var ev: Dictionary = {}
			for e in Weather.events:
				if Weather.tier_of(e) == "storm" and float(e["start"]) > 31 * 24:
					ev = e
					break
			var target := (float(ev["start"]) + (float(ev["end"]) - float(ev["start"])) * 0.4) * 60.0
			while Clock.minutes < target - 0.5:
				if Game.is_survival():
					Game.money = maxi(Game.money, 1500)
					for bl in Economy.unpaid_bills():
						Economy.pay_bill(int(bl["month"]))
					Survival.warmth = 100.0
				Clock.skip(minf(1440.0, target - Clock.minutes))
			print("storm fixture: event %.1f-%.1f h, %.1f cm, now %s, condition %s, %.2f cm/h" % [float(ev["start"]), float(ev["end"]), float(ev["total"]), Clock.time_string(), Weather.NAMES[Weather.condition()], Weather.snow_rate()])
		"4_contract", "3_contract":
			world.debug_complete_tutorial()
			Clock.skip(Clock.at(0, 10.0) - Clock.minutes)
			var lid := -1
			for l in Contracts.listings:
				if str(l.get("target", "")).begins_with("lot:"):
					lid = int(l["lid"])
					break
			if lid < 0 and not Contracts.listings.is_empty():
				lid = int(Contracts.listings[0]["lid"])
			if lid >= 0:
				Contracts.force_award(lid)
			Clock.skip(60.0)
		"4_midwinter", "5_midwinter":
			world.debug_complete_tutorial()
			# F1 day jumps, a day at a time. A Survival player who jumps this far would have earned
			# the money for the hydro bills and kept warm indoors; do that so the run can't freeze.
			var target := Clock.at(Clock.day_of(1, 20), 12.0)
			while Clock.minutes < target - 0.5:
				if Game.is_survival():
					Game.money = maxi(Game.money, 1500)
					for bl in Economy.unpaid_bills():
						Economy.pay_bill(int(bl["month"]))
					Survival.warmth = 100.0
				Clock.skip(minf(1440.0, target - Clock.minutes))
	await _frames(5)
	var ok := Saves.save_game()
	var src := ProjectSettings.globalize_path(Saves.path_for(mode))
	var dst := ProjectSettings.globalize_path(OUT + "%s_%s.json" % [mode, point])
	var err := DirAccess.copy_absolute(src, dst)
	print("fixture %s %s: saved=%s copy=%d  day %d %s  stage %d  contracts %d  snow %.1f m3" % [mode, point, str(ok), err,
		Clock.day_index(), Clock.time_string(), Game.stage(), Contracts.active.size(), Snow.total_volume()])
	if p5:
		made.append(OUT + "%s_%s.json" % [mode, point])



# -----------------------------------------------------------------------------
# Polish 5 §0 fixtures
# -----------------------------------------------------------------------------

const P5_POINTS := ["1_contracts", "2_upgrades", "3_vehicle", "4_midwinter", "5_evening", "6_winter2"]
## Polish 6 §0: the extra point of the polish5_v3 set.
const P6_POINTS := ["7_keys_pickup_plow_order"]
## 24 and 28 Maple Street (polish 5 decision 10 merges them).
const P5_LOTS := [[24, Layout.STREET_MAPLE], [28, Layout.STREET_MAPLE]]


## Press a button of the F1 developer menu (the real DebugMenu, opened for the one press).
## `prep` fills its fields first (it gets the menu); `row` picks the row by its title when the
## label isn't unique ("Set" is in both the Money and the Warmth rows).
func _f1(label: String, prep := Callable(), row := "") -> void:
	var d := DebugMenu.new()
	d.world = world
	world.ui.add_child(d)
	if prep.is_valid():
		prep.call(d)
	var found := false
	for b in d.find_children("*", "Button", true, false):
		if (b as Button).text != label:
			continue
		if row != "":
			var first: Node = b.get_parent().get_child(0)
			if not (first is Label) or (first as Label).text != row:
				continue
		(b as Button).pressed.emit()
		found = true
		break
	if not found:
		push_error("F1 has no button \"%s\"" % label)
	d.queue_free()
	await get_tree().process_frame


## F1 money "Add".
func _f1_money(amount: int) -> void:
	await _f1("Add", func(d): d.money_e.text = str(amount), "Money")


## A Survival player who jumps far ahead would have earned the money for the hydro bills and kept
## warm indoors: do that (F1 money and warmth, the computer's bill payment) before each day.
func _survival_care() -> void:
	if not Game.is_survival():
		return
	if Game.money < 1500:
		await _f1_money(1500 - Game.money)
	for bl in Economy.unpaid_bills():
		Economy.pay_bill(int(bl["month"]))
	if Survival.warmth < 100.0:
		await _f1("Set", func(d): d.warm_e.text = "100", "Warmth")


## Jump to a game time with F1: "+1 day" while a day or more is left, then "Set hour".
func _f1_jump_to(target: float) -> void:
	while Clock.minutes < target - 0.5 and not Clock.has_ended():
		await _survival_care()
		if target - Clock.minutes >= 1440.0:
			await _f1("+1 day")
		else:
			var h := fmod(target, 1440.0) / 60.0
			await _f1("Set hour", func(d): d.hour_e.text = str(h))
			if Clock.minutes < target - 0.5:     # Set hour is "today or tomorrow"; shouldn't happen
				Clock.skip(target - Clock.minutes)
	await _survival_care()


func _listing(pred: Callable) -> Dictionary:
	for l in Contracts.listings:
		if pred.call(l):
			return l
	return {}


static func _p5_lot_indices() -> Array:
	var out := []
	for a in P5_LOTS:
		out.append(int(Layout.lot_by_address(a[0], a[1])["index"]))
	return out


## Collect everything the store has put out for this player's orders (the E press on each).
func _collect_orders() -> void:
	await _frames(3)
	for c in world.objects.get_children():
		if c is ToolItem and (c as ToolItem).entry.has("order_id") and not c.is_queued_for_deletion():
			(c as ToolItem).interact(world.player)
	await _frames(3)


func _vehicle_node(id: String) -> Vehicle:
	for v in world.vehicle_nodes():
		if String((v as Vehicle).data.id) == id and not (v as Node).is_queued_for_deletion():
			return v
	return null


func _park(v: Vehicle, p: Vector2, yaw: float) -> void:
	v.global_position = Vector3(p.x, 0.0, p.y)
	v.rotation.y = yaw
	v.velocity = Vector3.ZERO
	v.save_entry()


func _p5_setup(point: String) -> void:
	var lot := Layout.player_lot
	match point:
		"1_contracts":
			await _f1("Complete tutorial")
			# Day 1 on (the day-0 board is one-time jobs only): the first board that has both kinds.
			await _f1_jump_to(Clock.at(1, 10.0))
			var one := {}
			var rec := {}
			for tries in range(6):
				if one.is_empty():
					var l1 := _listing(func(l): return l["type"] == "one_time" and str(l["target"]).begins_with("lot:"))
					if not l1.is_empty():
						one = Contracts.force_award(int(l1["lid"]))
				if rec.is_empty():
					var l2 := _listing(func(l): return l["type"] != "one_time")
					if not l2.is_empty():
						rec = Contracts.force_award(int(l2["lid"]))
				if not one.is_empty() and not rec.is_empty() and not Contracts.listings.is_empty():
					break
				await _f1_jump_to(Clock.at(Clock.day_index() + 1, 10.0))
			await _f1("+1 hour")
		"2_upgrades":
			await _f1("Complete tutorial")
			await _f1_jump_to(Clock.at(1, 10.0))   # store hours: orders are ready at once
			await _f1_money(60000)
			# Polish 5 §13: upgrades belong to an item, and only owned items can be upgraded: the
			# tools come first. (At the baseline build "pickup_plow" was also a vehicle id, so the store
			# sold the plow as a vehicle — a second truck in a bay; the polish5 fixtures hold one.)
			for t in ["standard_shovel", "wide_pusher", "snow_scraper", "small_blower"]:
				Economy.buy(t)
			await _collect_orders()
			# Upgrades that require another one can only be bought once that one is installed.
			var done := {}
			var up_ids: Array = Catalog.upgrade_ids()
			for rounds in range(4):
				var bought := 0
				for id in up_ids:
					if not done.has(id) and Economy.can_buy(String(id)) == "":
						if Economy.buy(String(id))["ok"]:
							bought += 1
							done[id] = true
				await _collect_orders()
				# The front plow is fitted when the pickup is driven into the store lot.
				if Economy.has_open_order(String(_ItemUpgrades.PLOW_ID)) and _vehicle_node("pickup"):
					var pk := _vehicle_node("pickup")
					var home := Vector2(pk.global_position.x, pk.global_position.z)
					var yaw := pk.rotation.y
					var sl: Rect2 = Layout.big_areas[1]["rect"]
					_park(pk, sl.get_center(), 0.0)
					for k in range(30):
						await _frames(1)
						if _vehicle_node("pickup_plow"):
							break
					var pp := _vehicle_node("pickup_plow")
					if pp:
						await _frames(2)
						_park(pp, home, yaw)
				if bought == 0:
					break
			await _f1("+1 hour")
		"3_vehicle":
			await _f1("Complete tutorial")
			await _f1_jump_to(Clock.at(1, 10.0))
			# The keys: dug out of the lawn, then picked up.
			for c in world.objects.get_children():
				if c is BuriedKeys:
					var kp := Vector2((c as Node3D).global_position.x, (c as Node3D).global_position.z)
					Snow.set_rect(Rect2(kp - Vector2(0.6, 0.6), Vector2(1.2, 1.2)), 0.0)
					await _frames(2)
					(c as BuriedKeys).interact(world.player)
			# The driveway, cleared (the box snaps to bare ground).
			var db := Boxes.get_box(Boxes.lot_box(lot, "driveway"))
			for r in db["rects"]:
				Snow.set_rect(r, 0.004)
			Boxes.measure(db, true)
			# An ATV with blade from the store, parked in the driveway in front of the pickup.
			await _f1_money(7000)
			var res := Economy.buy("atv_blade")
			await _frames(3)
			var atv := _vehicle_node("atv_blade")
			var pk := _vehicle_node("pickup")
			if res["ok"] and atv and pk:
				_park(atv, Layout.lot_to_world(lot, Layout.gu(lot, 6.0), 1.7), pk.rotation.y)
				for o in Economy.orders:
					if o["item"] == "atv_blade":
						Economy.mark_order(int(o["id"]), "collected")
			await _f1("+1 hour")
		"4_midwinter":
			await _f1("Complete tutorial")
			var want := _p5_lot_indices()
			var targets := ["lot:%d" % want[0], "lot:%d" % want[1]]
			var won := {}
			# The boards from Jan 19 on, at noon: the first that lists 24 or 28 Maple Street.
			for day in range(Clock.day_of(1, 19), Clock.day_of(1, 23) + 1):
				await _f1_jump_to(Clock.at(day, 12.0))
				var l := _listing(func(x): return str(x["target"]) in targets)
				if not l.is_empty():
					won = Contracts.force_award(int(l["lid"]))
					break
			# After Jan 20's major event the street is deeper than the hips until the city grader's
			# next scheduled pass: wait for it (to noon that day), so the street can be walked.
			var road := Layout.lot_to_world(Layout.player_lot, 0.0, -4.0)
			var deep := Snow.depth_at(road.x, road.y)
			var grader := Municipal.next_pass
			if deep > 0.6:
				await _f1_jump_to(maxf(Clock.at(int(grader / 1440.0), 12.0), grader + 60.0))
			print("midwinter: contract on 24/28 Maple Street: %s; the street in front of home %.2f m deep then, grader %s, %.2f m now (%s)" % [("%s (%s), won %s" % [won["address"], won["type"], Clock.format_time(float(won["accepted"]))]) if not won.is_empty() else "none offered Jan 19-23", deep, Clock.format_time(grader), Snow.depth_at(road.x, road.y), Clock.format_time(Clock.minutes)])
			await _f1("+1 hour")
		"5_evening":
			await _f1("Complete tutorial")
			await _f1_jump_to(Clock.at(2, 20.5))
		"6_winter2":
			await _f1("Complete tutorial")
			await _f1_jump_to(Clock.at(Clock.day_of(3, 30), 8.0))
			await _p5_raise_reputation()
			# Clear up so nothing is left snowed in, then F1 "Apr 1": the winter ends.
			await _f1("Clear all snow")
			await _f1("+1 hour")
			await _survival_care()
			await _f1("Apr 1")
			for k in range(120):
				await _frames(1)
				if world.modal_kind == "summary":
					break
			# The summary: every recurring contract is ticked for renewal; BEGIN WINTER 2.
			# A real click arrives outside the physics step; unpausing between the physics server's query
			# flush and its step makes the engine print `p_elem->_root` (HANDOFF §13 item 12).
			await get_tree().process_frame
			for b in (world.modal.find_children("*", "Button", true, false) if world.modal else []):
				if (b as Button).text.begins_with("BEGIN WINTER"):
					(b as Button).pressed.emit()
			for k in range(600):
				await _frames(1)
				if Game.year == 2 and Clock.running:
					break
			await _f1_jump_to(Clock.at(1, 12.0))
		"7_keys_pickup_plow_order":
			await _f1("Complete tutorial")
			await _f1_jump_to(Clock.at(1, 10.0))   # store hours
			# The keys: dug out of the lawn, then picked up (as 3_vehicle). The driveway and the pickup
			# are left as a new game has them.
			for c in world.objects.get_children():
				if c is BuriedKeys:
					var kp := Vector2((c as Node3D).global_position.x, (c as Node3D).global_position.z)
					Snow.set_rect(Rect2(kp - Vector2(0.6, 0.6), Vector2(1.2, 1.2)), 0.0)
					await _frames(2)
					(c as BuriedKeys).interact(world.player)
			# The front plow, bought from the computer's store with its price added by F1 first (the
			# money is left as it was): an open order, never fitted (the pickup doesn't drive into the
			# store lot).
			var plow := String(_ItemUpgrades.PLOW_ID)
			await _f1_money(Economy.price_of(plow))
			var res := Economy.buy(plow)
			print("keys/pickup/plow order: keys %s, buy %s: %s" % [str(Game.flags.get("truck_keys", false)), str(res["ok"]), res["msg"]])
			await _f1("+1 hour")


## Raise the reputation with F1: win every residential job the board offers ("New listings";
## parking lots are left alone, their big boxes only complete on an exact count), clear the snow
## ("Clear all snow", +1 hour: one-time jobs +2, first visits +1), then re-snow ("Add globally"
## 0.1 m, +1 hour) and clear again for more visits (+1 each), until 100 or nothing more to gain.
func _p5_raise_reputation() -> void:
	var dry := 0
	for k in range(25):
		await _f1("New listings")
		var n := 0
		for l in Contracts.listings.duplicate():
			if str(l["target"]).begins_with("lot:"):
				Contracts.force_award(int(l["lid"]))
				n += 1
		dry = dry + 1 if n == 0 else 0
		if dry >= 3:
			break
	await _f1("Clear all snow")
	await _f1("+1 hour")
	print("reputation after the board: %.1f (%d contracts)" % [Game.reputation, Contracts.active.size()])
	for k in range(30):
		if Game.reputation >= 100.0:
			break
		var before := Game.reputation
		await _survival_care()
		await _f1("Add globally", func(d): d.snow_e.text = "0.1")
		await _f1("+1 hour")
		await _f1("Clear all snow")
		await _f1("+1 hour")
		if Game.reputation <= before:
			break
	# Polish 6 §0: from polish 5 §10 on, F1 has a Reputation row, and the board is refilled only up to
	# its daily size (so the loop above wins nothing on a full board): "as high as F1 allows" is its
	# Set, at 100.
	var probe := DebugMenu.new()
	var has_rep := "rep_e" in probe
	probe.free()
	if Game.reputation < 100.0 and has_rep:
		await _f1("Set", func(d): d.rep_e.text = "100", "Reputation")
	print("reputation raised to %.1f by %s" % [Game.reputation, Clock.format_time(Clock.minutes)])


## Everything a polish-5 fixture is meant to hold, read from the autoloads.
static func p5_summary() -> String:
	var L := []
	L.append("  %s, winter %d, %s (day %d), stage %d, money $%d, reputation %.1f" % [Game.mode, Game.year, Clock.format_time(Clock.minutes), Clock.day_index(), Game.stage(), Game.money, Game.reputation])
	var tools := []
	for s in Game.slots:
		if s != "":
			tools.append(s)
	var lying := []
	for it in Game.items:
		lying.append("%s%s" % [it["tool"], " (buried)" if it.get("buried", false) else ""])
	var mach := []
	for m in Game.machines:
		mach.append("%s @ %s" % [m["tool"], Layout.describe_point(Vector2(m["pos"].x, m["pos"].z))])
	L.append("  tools in the slots %s, carried '%s', lying about %s, machines %s, rack %s" % [tools, Game.carried, lying, mach, Game.rack])
	var ups: Array = Game.upgrades.keys()
	ups.sort()
	var missing := []
	# Polish 5 §13: every upgrade of the items owned (an item's levels within its ladder), and the rest.
	var all_ids: Array = Catalog.upgrade_ids()
	var sellable := 0
	for id in all_ids:
		var u: UpgradeData = Catalog.upgrade(id)
		if u.item != &"" and (not _ItemUpgrades.owns(u.item) or u.level > _ItemUpgrades.max_level(u.item, u.track) or not _ItemUpgrades.track_shown(u.item, u.track)):
			continue
		sellable += 1
		if not Game.has_upgrade(id):
			missing.append(String(id))
	L.append("  upgrades %d (of %d for the items owned) %s%s" % [ups.size(), sellable, ups, ("  missing %s" % [missing]) if not missing.is_empty() else ""])
	var drive: Rect2 = Layout.house_info(Layout.player_lot)["driveway"]
	var veh := []
	for v in Game.vehicles:
		var p: Vector3 = v["pos"]
		veh.append("%s @ %s%s" % [v["id"], Layout.describe_point(Vector2(p.x, p.z)), " (in the player's driveway)" if drive.grow(0.3).has_point(Vector2(p.x, p.z)) else ""])
	L.append("  vehicles %s, truck keys %s, driveway box complete %s" % [veh, str(Game.flags.get("truck_keys", false)), str(Boxes.is_complete(Boxes.lot_box(Layout.player_lot, "driveway")))])
	var cs := []
	for c in Contracts.active:
		if c.get("tutorial", false):
			continue
		cs.append("#%d %s %s %s" % [int(c["id"]), c["type"], c["status"], c["address"]])
	var live := 0
	for c in Contracts.active:
		if not c.get("tutorial", false) and str(c["status"]) in ["active", "needs_service", "serviced"]:
			live += 1
	L.append("  contracts: %d running of %d %s" % [live, cs.size(), cs if cs.size() <= 8 else cs.slice(0, 8) + ["…"]])
	var ls := []
	for l in Contracts.listings:
		ls.append("%s %s (%s)" % [l["type"], l["address"], ("closes " + Clock.format_time(float(l["closes"]))) if l.has("closes") else "until day %d" % int(l.get("expires", -1))])
	L.append("  listings: %d %s; bids %d; orders %s" % [ls.size(), ls, Contracts.bids.size(), Economy.orders.map(func(o): return "%s:%s" % [o["item"], o["status"]])])
	var snow := []
	for a in P5_LOTS:
		var lot := Layout.lot_by_address(a[0], a[1])
		var parts := []
		for kind in ["driveway", "path", "sidewalk"]:
			var b := Boxes.get_box(Boxes.lot_box(lot, kind))
			if not b.is_empty():
				parts.append("%s %.2f m3 (avg %.2f m)" % [kind, Boxes.snow_volume(b, true), Boxes.avg_depth(b, true)])
		var yard := Layout.lot_to_world(lot, 0.0, float(lot["setback"]) - 4.0)
		snow.append("%s [lot %d]: %s; front yard %.2f m" % [lot["address"], int(lot["index"]), ", ".join(parts), Snow.depth_at(yard.x, yard.y)])
	L.append("  snow: " + " | ".join(snow))
	return "\n".join(L)


## Read every polish-5 fixture back from its file (as the menu's Continue does) and print what it
## holds.
func _verify_all() -> void:
	if world and is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		world = null
	print("")
	print("==== polish-5 fixtures, read back from the files ====")
	for path in made:
		var mode := "survival" if path.get_file().begins_with("survival") else "fun"
		for p in [Saves.path_for(mode), Saves.path_for(mode) + ".bak"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
		var ok := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(Saves.path_for(mode))) == OK and Saves.load_game(mode)
		print("%s: %s" % [path.get_file(), "loads" if ok else "DOES NOT LOAD (%s)" % Saves.last_error])
		if ok:
			print(p5_summary())
		Saves.delete_save(mode)
