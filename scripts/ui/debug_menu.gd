class_name DebugMenu
extends Control
## Developer menu (Part 29), F1. Uses the same game systems (real snow data, real objects).

signal closed

var world: Node
var out_l: Label
var money_e: LineEdit
var hour_e: LineEdit
var date_m: OptionButton
var date_d: SpinBox
var snow_e: LineEdit
var warm_e: LineEdit
var rep_e: LineEdit


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var p := UIKit.panel(UIKit.sb(Color(0.05, 0.06, 0.1, 0.94), 10, 2, Color(0.4, 1.0, 0.5), 16))
	p.position = Vector2(20, 20)
	p.custom_minimum_size = Vector2(980, 1040)
	add_child(p)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(950, 1000)
	p.add_child(sc)
	var v := UIKit.vbox(8)
	sc.add_child(v)
	var head := UIKit.hbox()
	v.add_child(head)
	head.add_child(UIKit.label("DEBUG MENU (%s)" % Settings.action_label("debug"), 28, Color(0.5, 1.0, 0.6)))
	head.add_child(UIKit.hspacer())
	head.add_child(UIKit.button("Close", _close, 18))
	out_l = UIKit.label("", 17, Color(0.7, 1.0, 0.7))
	v.add_child(out_l)
	# Money
	var r := _row(v, "Money")
	money_e = _edit(r, "1000")
	r.add_child(_b("Add", func(): Game.add_money(int(money_e.text)); _say("Money: %d" % Game.money)))
	r.add_child(_b("Set", func(): Game.money = int(money_e.text); Game.money_changed.emit(Game.money); _say("Money set")))
	# Weather
	r = _row(v, "Weather")
	for i in range(6):
		var c := i
		var hrs := 4.0 if c == Weather.C.BLIZZARD else 6.0
		r.add_child(_b(Weather.NAMES[i], func(): Weather.force(c, hrs); _say("Weather forced: %s for %d h" % [Weather.NAMES[c], int(hrs)])))
	r = _row(v, "")
	r.add_child(_b("Storm (≈25 cm in 12 h)", func(): Weather.force(Weather.C.HEAVY, 12.0, 2.1); _say("Storm!")))
	r.add_child(_b("Major event (≈1 m in 4 h)", func(): Weather.force(Weather.C.BLIZZARD, 4.0, 25.0); _say("Major snow event!")))
	r.add_child(_b("Clear override", func(): Weather.override_cond = -1; _say("Weather back to schedule")))
	# Time
	r = _row(v, "Time of day")
	hour_e = _edit(r, "12")
	r.add_child(_b("Set hour", func():
		var h := clampf(float(hour_e.text), 0.0, 23.99)
		var target := Clock.at(Clock.day_index(), h)
		if target < Clock.minutes:
			target += 1440.0
		Clock.skip(target - Clock.minutes)
		_say("Time: " + Clock.time_string())))
	r.add_child(_b("+1 hour", func(): Clock.skip(60.0); _say(Clock.format_time(Clock.minutes))))
	r.add_child(_b("+6 hours", func(): Clock.skip(360.0); _say(Clock.format_time(Clock.minutes))))
	r.add_child(_b("+1 day", func(): _skip_days(1)))
	r.add_child(_b("+7 days", func(): _skip_days(7)))
	# Polish 5 §10: just before bidding closes / jobs fall due (simulated, like every jump).
	r.add_child(_b("8:59 p.m.", func():
		var t := Clock.at(Clock.day_index(), 20.0 + 59.0 / 60.0)
		if t <= Clock.minutes:
			t += 1440.0
		Clock.skip(t - Clock.minutes)
		_say("Time: " + Clock.time_string())))
	# Polish 5 §11: half an hour before the city crews' next Monday (simulated, like every jump).
	r.add_child(_b("Next Monday", func():
		var d := Clock.day_index() + 1
		while Clock.weekday_index(d, Game.year) != 0:
			d += 1
		_jump_to(d, (Municipal.pass_minute() - 30.0) / 60.0)
		_say("Now: %s %s · %s" % [Clock.weekday(Clock.day_index(), Game.year), Clock.format_time(Clock.minutes), Municipal.crew_line()])))
	r = _row(v, "Jump to date")
	date_m = OptionButton.new()
	for m in ["December", "January", "February", "March", "April"]:
		date_m.add_item(m)
	r.add_child(date_m)
	date_d = SpinBox.new()
	date_d.min_value = 1
	date_d.max_value = 31
	date_d.value = 15
	r.add_child(date_d)
	r.add_child(_b("Jump (simulated)", func(): _jump(false)))
	r.add_child(_b("Mar 31 20:00", func(): _jump_to(Clock.day_of(3, 31), 20.0)))
	r.add_child(_b("Apr 1", func(): _jump_to(121, 0.0)))
	# Snow
	r = _row(v, "Snow (m)")
	snow_e = _edit(r, "0.1")
	r.add_child(_b("Add globally", func():
		Snow.add_snowfall(float(snow_e.text))
		Snow.sync_all()
		_say("Added %.2f m of snowfall everywhere" % float(snow_e.text))))
	r.add_child(_b("Add at crosshair", func():
		var p2: Vector3 = Game.player.crosshair_point(30.0) if Game.player else Vector3.ZERO
		Snow.add_layer_rect(Rect2(p2.x - 2, p2.z - 2, 4, 4), float(snow_e.text))
		_say("Added snow at %s" % str(Vector2(p2.x, p2.z)))))
	r.add_child(_b("Clear all snow", func(): Snow.clear_all(); _say("All snow cleared")))
	# Spawn
	r = _row(v, "Spawn tool")
	for id in Catalog.TOOL_IDS:
		if id == &"hands":
			continue
		var tid := String(id)
		r.add_child(_b(tid.replace("_", " "), func(): _spawn(tid, false)))
		if r.get_child_count() > 5:
			r = _row(v, "")
	r = _row(v, "…at store lot")
	r.add_child(_b("standard shovel", func(): _spawn("standard_shovel", true)))
	r.add_child(_b("small blower", func(): _spawn("small_blower", true)))
	r = _row(v, "Spawn vehicle")
	for id2 in Catalog.VEHICLE_IDS:
		var vid := String(id2)
		r.add_child(_b(vid.replace("_", " "), func(): _spawn_vehicle(vid, false)))
		if r.get_child_count() > 5:
			r = _row(v, "")
	r = _row(v, "…at store bay")
	r.add_child(_b("tractor blade", func(): _spawn_vehicle("tractor_blade", true)))
	r.add_child(_b("dump truck", func(): _spawn_vehicle("dump_truck", true)))
	# Teleport
	r = _row(v, "Teleport")
	r.add_child(_b("Home (inside)", func(): _tp(Game.bedroom_spawn())))
	r.add_child(_b("Home driveway", func():
		var hi := Layout.house_info(Layout.player_lot)
		var d: Rect2 = hi["driveway"]
		_tp(Vector3(d.get_center().x, 0.1, d.get_center().y))))
	r.add_child(_b("Store", func(): _tp(Vector3(Layout.store_pad.get_center().x, 0.1, Layout.store_pad.end.y + 3.0))))
	r.add_child(_b("Neighbour", func():
		var hi2 := Layout.house_info(Layout.neighbor_lot)
		var pc: Vector2 = hi2["porch_center"]
		_tp(Vector3(pc.x, Layout.PORCH_H + 0.1, pc.y))))
	r = _row(v, "")
	r.add_child(_b("School lot", func(): var c: Vector2 = (Layout.big_areas[0]["rect"] as Rect2).get_center(); _tp(Vector3(c.x, 0.1, c.y))))
	r.add_child(_b("Church lot", func(): var c: Vector2 = (Layout.big_areas[2]["rect"] as Rect2).get_center(); _tp(Vector3(c.x, 0.1, c.y))))
	r.add_child(_b("Snow dump", func(): var c: Vector2 = Layout.dump_rect.get_center(); _tp(Vector3(c.x, 0.1, c.y))))
	r = _row(v, "Address")
	var addr := OptionButton.new()
	for lot in Layout.lots:
		addr.add_item(lot["address"])
	r.add_child(addr)
	r.add_child(_b("Go", func():
		var lot2: Dictionary = Layout.lots[addr.selected]
		var p3 := Layout.lot_to_world(lot2, 0, -0.5)
		_tp(Vector3(p3.x, 0.1, p3.y))))
	# Polish 5 §10: reputation (the tiers unlock as it passes their thresholds).
	r = _row(v, "Reputation")
	rep_e = _edit(r, "65")
	r.add_child(_b("Set", func(): _set_rep(float(rep_e.text))))
	for ti in range(Catalog.balance.rep_tier_thresholds.size()):
		var th: float = Catalog.balance.rep_tier_thresholds[ti]
		r.add_child(_b("%s (%d)" % [Catalog.balance.rep_tier_names[ti], int(th)], func(): _set_rep(th)))
	# Survival
	r = _row(v, "Warmth")
	warm_e = _edit(r, "50")
	r.add_child(_b("Set", func(): Survival.warmth = clampf(float(warm_e.text), 0, 100); _say("Warmth %d" % int(Survival.warmth))))
	r.add_child(_b("Toggle invulnerable", func(): Survival.invulnerable = not Survival.invulnerable; _say("Invulnerable: %s" % Survival.invulnerable)))
	r.add_child(_b("Toggle heating", func():
		if Survival.power_on:
			Survival.cut_power()
		else:
			Survival.restore_power()
		_say("Power: %s" % Survival.power_on)))
	r.add_child(_b("Activate cold", func(): Survival.activate(); _say("Cold system active")))
	# Systems
	r = _row(v, "Systems")
	r.add_child(_b("Grader pass now", func():
		Municipal.next_pass = Clock.minutes
		Municipal.on_hour(Clock.day_index(), Clock.hour())
		_say("City grader dispatched")))
	r.add_child(_b("Complete tutorial", func():
		if world:
			world.debug_complete_tutorial()
		_say("Tutorial complete")))
	r.add_child(_b("New listings", func(): Contracts._generate_listings(Clock.day_index() + 50, true); _say("Board refreshed")))
	r.add_child(_b("Win first listing", func():
		if not Contracts.listings.is_empty():
			var c2 := Contracts.force_award(int(Contracts.listings[0]["lid"]))
			_say("Won: %s" % c2.get("address", "?"))))
	r = _row(v, "View")
	r.add_child(_b("Performance overlay", func():
		if world:
			world.perf_overlay = not world.perf_overlay
		_say("Perf overlay toggled")))
	r.add_child(_b("Free-fly camera", func():
		if Game.player:
			Game.player.freecam = not Game.player.freecam
			Game.player.collision.disabled = Game.player.freecam
			var mv := "%s%s%s%s" % [Settings.action_label("move_forward"), Settings.action_label("move_left"), Settings.action_label("move_back"), Settings.action_label("move_right")]
			_say("Free camera: %s (%s, %s/%s, %s fast)" % [Game.player.freecam, mv, Settings.action_label("jump"), Settings.action_label("crouch"), Settings.action_label("sprint")])))
	r.add_child(_b("Save now", func(): _say("Saved: %s" % Saves.save_game())))


func _close() -> void:
	closed.emit()
	queue_free()


## Polish 5 §10: set the reputation (0–100); reaching a tier announces it as play would.
func _set_rep(v: float) -> void:
	Contracts.adjust_reputation(clampf(v, 0.0, 100.0) - Game.reputation)
	_say("Reputation %d · %s" % [int(Game.reputation), Contracts.tier_name(Contracts.tier_index())])


func _row(parent: Control, title: String) -> HBoxContainer:
	var h := UIKit.hbox(8)
	var l := UIKit.label(title, 18, UIKit.ACCENT)
	l.custom_minimum_size.x = 150
	h.add_child(l)
	parent.add_child(h)
	return h


func _edit(parent: Control, txt: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = txt
	e.custom_minimum_size.x = 100
	parent.add_child(e)
	return e


func _b(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	return b


func _say(t: String) -> void:
	out_l.text = t


func _skip_days(n: int) -> void:
	if world:
		world.finish_grader_now()
	Clock.skip(n * 1440.0)
	_say("Skipped %d day(s): %s" % [n, Clock.format_time(Clock.minutes)])


func _jump(_x: bool) -> void:
	var day := Clock.day_of(date_m.selected, int(date_d.value))
	_jump_to(day, Clock.hour_f())


func _jump_to(day: int, hour: float) -> void:
	var target := Clock.at(day, hour)
	if target <= Clock.minutes:
		_say("Can only jump forward in time.")
		return
	if world:
		world.finish_grader_now()
	Clock.skip(target - Clock.minutes)
	_say("Now: %s" % Clock.format_time(Clock.minutes))


func _spawn(id: String, at_store: bool) -> void:
	if world == null or Game.player == null:
		return
	var p: Vector3 = Game.player.global_position + Vector3(Game.player.forward2().x, 0, Game.player.forward2().y) * 1.5
	if at_store:
		p = Vector3(Layout.store_pad.get_center().x, 0, Layout.store_pad.get_center().y)
	var t: ToolData = Catalog.tool(StringName(id))
	if t.uses_slot:
		p.y = Snow.surface_height(p.x, p.z)   # polish 6 §3: a tool rests on the snow
		var e := {"uid": Game.uid(), "tool": id, "pos": p, "yaw": 0.0}
		Game.items.append(e)
		world.spawn_item_node(e)
	else:
		var e2 := {"uid": Game.uid(), "tool": id, "pos": p, "yaw": Game.player.yaw}
		Game.machines.append(e2)
		world.spawn_machine_node(e2)
	_say("Spawned %s" % t.display_name)


func _spawn_vehicle(id: String, at_store: bool) -> void:
	if world == null or Game.player == null:
		return
	var p: Vector3 = Game.player.global_position + Vector3(Game.player.forward2().x, 0, Game.player.forward2().y) * 6.0
	if at_store:
		var bay: Rect2 = Layout.store_bays[randi() % Layout.store_bays.size()]
		p = Vector3(bay.get_center().x, 0, bay.get_center().y)
	var e := {"uid": Game.uid(), "id": id, "pos": Vector3(p.x, 0, p.z), "yaw": Game.player.yaw, "snow": 0.0}
	Game.vehicles.append(e)
	world.spawn_vehicle_node(e)
	_say("Spawned %s" % Catalog.item_name(StringName(id)))


func _tp(p: Vector3) -> void:
	if Game.player:
		if Game.player.vehicle:
			Game.player.vehicle.exit_vehicle()
		Game.player.teleport(p)
		_say("Teleported to %s" % Layout.describe_point(Vector2(p.x, p.z)))
