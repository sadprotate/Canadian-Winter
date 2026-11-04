class_name ComputerUI
extends Control
## The home computer (Part 24): contract board, active contracts, equipment store, upgrades,
## bills & payments, property/storage, weather, orders, help. Live updates, battery backup.

signal closed

const APPS := ["Contract Board", "Active Contracts", "Equipment Store", "Upgrades", "Bills & Payments",
	"Property & Storage", "Weather", "Orders", "Help"]

var current := 0
var content: VBoxContainer
var scroll: ScrollContainer
var balance_l: Label
var clock_l: Label
var battery_l: Label
var status_l: Label
var app_buttons: Array = []
var _refresh_t := 0.0
var _bid_values: Dictionary = {}
var _battery := 100.0


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	UIKit.full_rect(dim)
	add_child(dim)
	var win := UIKit.center_panel(self, Vector2(1640, 900))
	win.add_theme_stylebox_override("panel", UIKit.sb(Color(0.86, 0.88, 0.92, 0.98), 12, 3, Color(0.2, 0.22, 0.3), 0))
	var outer := UIKit.vbox(0)
	win.add_child(outer)
	# Title bar
	var bar := UIKit.panel(UIKit.sb(Color(0.12, 0.2, 0.38), 0, 0, Color.TRANSPARENT, 12))
	outer.add_child(bar)
	var bh := UIKit.hbox(18)
	bar.add_child(bh)
	bh.add_child(UIKit.label("❄  SnowDesk — Business Manager", 24, Color.WHITE))
	bh.add_child(UIKit.hspacer())
	battery_l = UIKit.label("", 20, UIKit.WARN)
	bh.add_child(battery_l)
	clock_l = UIKit.label("", 20, Color(0.85, 0.9, 1.0))
	bh.add_child(clock_l)
	balance_l = UIKit.label("", 24, Color(0.7, 1.0, 0.7))
	bh.add_child(balance_l)
	bh.add_child(UIKit.button("Close  (%s)" % Settings.action_label("pause"), _close, 20))
	var body := UIKit.hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	var side := UIKit.panel(UIKit.sb(Color(0.16, 0.2, 0.3), 0, 0, Color.TRANSPARENT, 12))
	side.custom_minimum_size.x = 300
	body.add_child(side)
	var sv := UIKit.vbox(8)
	side.add_child(sv)
	for i in range(APPS.size()):
		var idx := i
		var b := UIKit.button(APPS[i], func(): _open_app(idx), 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sv.add_child(b)
		app_buttons.append(b)
	sv.add_child(UIKit.spacer(10))
	status_l = UIKit.label("", 17, Color(0.85, 0.9, 1.0))
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_l.custom_minimum_size.x = 270
	sv.add_child(status_l)
	var main := UIKit.panel(UIKit.sb(Color(0.1, 0.12, 0.19), 0, 0, Color.TRANSPARENT, 18))
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	content = UIKit.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	Contracts.changed.connect(_soft_refresh)
	Economy.orders_changed.connect(_soft_refresh)
	Economy.bills_changed.connect(_soft_refresh)
	_open_app(0)


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()


func _soft_refresh() -> void:
	_refresh_t = 0.0


func _process(delta: float) -> void:
	balance_l.text = "Balance: " + UIKit.money(Game.money)
	clock_l.text = "%s  %s" % [Clock.date_string(Clock.day_index(), true), Clock.time_string()]
	if not Survival.power_on:
		_battery = maxf(22.0, _battery - delta * 0.6)
		battery_l.text = "🔋 Battery backup %d%%" % int(_battery)
	else:
		_battery = minf(100.0, _battery + delta * 2.0)
		battery_l.text = ""
	# Live updates: rebuild on data signals, plus a slow refresh for time-based apps. Never while
	# the player is dragging a bid slider or clicking.
	_refresh_t -= delta
	if _refresh_t <= 0.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_refresh_t = 2.0 if current in [1, 4, 6, 7] else 30.0
		_rebuild(false)


func _open_app(i: int) -> void:
	current = i
	for k in range(app_buttons.size()):
		(app_buttons[k] as Button).add_theme_stylebox_override("normal", UIKit.sb(UIKit.ACCENT.darkened(0.25) if k == i else Color(0.18, 0.22, 0.33, 0.95), 9, 0, Color.TRANSPARENT, 16))
	_rebuild(true)


func _rebuild(reset_scroll: bool) -> void:
	var sv := scroll.scroll_vertical
	UIKit.clear(content)
	match current:
		0: _board()
		1: _active()
		2: _store()
		3: _upgrades()
		4: _bills()
		5: _property()
		6: _weather()
		7: _orders()
		8: _help()
	if not reset_scroll:
		scroll.set_deferred("scroll_vertical", sv)
	else:
		scroll.scroll_vertical = 0


func _h1(t: String) -> void:
	content.add_child(UIKit.label(t, 34, Color.WHITE))


func _p(t: String, color := UIKit.MUTED, font_size := 19) -> Label:
	var l := UIKit.label(t, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1200
	content.add_child(l)
	return l


func _msg(text: String, ok: bool) -> void:
	status_l.text = text
	status_l.add_theme_color_override("font_color", UIKit.GOOD if ok else UIKit.WARN)
	AudioMgr.ui("ui_money" if ok else "ui_error")


# --- Contract board ---------------------------------------------------------------
func _est_minutes(vol: float) -> String:
	var cap := Contracts.equipment_capability()
	var rate: float = [0.02, 0.06, 0.1, 0.5][cap]
	var mins: float = vol / rate / 60.0
	return "~%d real min with your best equipment" % maxi(1, int(ceil(mins)))


func _board() -> void:
	_h1("Contract Board")
	_p("Bid on jobs. Rival companies bid too; reputation, good equipment and being close to your other clients help you win. Contracts close together pay off — less travel through snowy streets. Your reputation: %d/100." % int(Game.reputation))
	if not Contracts.municipal_unlocked():
		_p("City street contracts unlock at reputation 58+ with a plow or blower vehicle.", UIKit.WARN)
	if Contracts.listings.is_empty():
		_p("No listings right now. New jobs are posted every morning at 6:00.")
	for l in Contracts.listings:
		var c := UIKit.card()
		content.add_child(c)
		var v := UIKit.vbox(6)
		c.add_child(v)
		var top := UIKit.hbox()
		v.add_child(top)
		var tname: String = {"one_time": "One-time job", "recurring": "Recurring — all winter", "municipal": "CITY CONTRACT — all winter"}[l["type"]]
		top.add_child(UIKit.label(l["address"], 26, Color.WHITE))
		top.add_child(UIKit.label("  " + tname, 20, UIKit.ACCENT))
		top.add_child(UIKit.hspacer())
		top.add_child(UIKit.label("Client budget: " + UIKit.money(l["budget"]) + (" / visit" if l["type"] != "one_time" else ""), 22, Color(0.7, 1.0, 0.7)))
		var zn := []
		for z in l["zones"]:
			zn.append(z["name"])
		v.add_child(UIKit.label("Client: %s   ·   Areas: %s" % [l["client"], ", ".join(zn)], 19, UIKit.MUTED))
		var terms := ""
		var hrs := int(Catalog.balance.contract_snowed_in_hours)
		if l["type"] == "one_time":
			terms = "Clear the marked areas within %d in-game hours or the client hires someone else. Estimated %.1f m³ now (%s)." % [hrs, l["est_volume"], _est_minutes(l["est_volume"])]
		else:
			terms = "Service every time new snow covers the property (%d cm or more). If it stays snowed in for more than %d in-game hours, the contract is lost (the clock pauses while a storm is still falling; one real hour = one game day). Typical visit ~%.1f m³." % [int(Catalog.balance.box_reopen_depth * 100.0), hrs, l["est_volume"]]
		v.add_child(UIKit.label(terms, 18, UIKit.MUTED))
		var near := Contracts.near_existing(Vector2(l["pos"][0], l["pos"][1]))
		if near:
			v.add_child(UIKit.label("✓ Close to your home / existing clients (bidding bonus)", 18, UIKit.GOOD))
		var row := UIKit.hbox(14)
		v.add_child(row)
		var lid: int = l["lid"]
		var budget: int = l["budget"]
		var cur: int = _bid_values.get(lid, budget)
		var amt_l := UIKit.label("Your bid: " + UIKit.money(cur), 22, Color.WHITE)
		amt_l.custom_minimum_size.x = 220
		var s := HSlider.new()
		s.min_value = int(budget * 0.6)
		s.max_value = int(budget * 1.4)
		s.step = 1
		s.value = cur
		s.custom_minimum_size = Vector2(420, 28)
		var odds := UIKit.label("", 18, UIKit.MUTED)
		var upd := func(x):
			_bid_values[lid] = int(x)
			amt_l.text = "Your bid: " + UIKit.money(int(x))
			var f := Contracts.bid_factors(l, int(x))
			var sc: float = f["score"]
			odds.text = "Odds: %s" % ("very good" if sc < 0.85 else ("good" if sc < 0.95 else ("fair" if sc < 1.05 else ("low" if sc < 1.15 else "very low"))))
		s.value_changed.connect(upd)
		upd.call(cur)
		row.add_child(amt_l)
		row.add_child(s)
		row.add_child(odds)
		row.add_child(UIKit.hspacer())
		row.add_child(UIKit.button("Place bid", func():
			var r := Contracts.place_bid(lid, int(_bid_values.get(lid, budget)))
			_msg(r["msg"], r["ok"])
			_rebuild(false), 20))
	if not Contracts.bids.is_empty():
		content.add_child(UIKit.label("Pending bids", 26, UIKit.ACCENT))
		for bd in Contracts.bids:
			_p("%s — %s (answer by %s)" % [bd["listing"]["address"], UIKit.money(bd["amount"]), Clock.format_time(bd["resolve_at"])], Color.WHITE)


# --- Active contracts --------------------------------------------------------------
func _active() -> void:
	_h1("Active Contracts")
	var any := false
	for c in Contracts.active:
		if c["status"] == "expired" or (c["status"] == "lost" and Clock.minutes - float(c.get("accepted", 0.0)) > 14 * 1440.0):
			continue
		any = true
		var card := UIKit.card()
		content.add_child(card)
		var v := UIKit.vbox(6)
		card.add_child(v)
		var top := UIKit.hbox()
		v.add_child(top)
		top.add_child(UIKit.label(c["address"], 26, Color.WHITE))
		var st: String = c["status"]
		var st_text: String = {"active": "In progress", "needs_service": "NEEDS CLEARING", "serviced": "Clear — waiting for snow", "completed": "Completed ✓", "lost": "LOST — client left"}.get(st, st)
		var st_col := UIKit.WARN if st == "needs_service" else (UIKit.GOOD if st == "completed" or st == "serviced" else (UIKit.BAD if st == "lost" else UIKit.ACCENT))
		top.add_child(UIKit.label("   " + st_text, 20, st_col))
		top.add_child(UIKit.hspacer())
		top.add_child(UIKit.label(UIKit.money(c["pay"]) + (" / visit" if c["type"] != "one_time" else ""), 22, Color(0.7, 1.0, 0.7)))
		var info := "Client: %s  ·  %s" % [c["client"], {"one_time": "One-time job", "recurring": "Recurring", "municipal": "City street contract"}[c["type"]]]
		if c["type"] != "one_time":
			info += "  ·  Visits: %d" % int(c.get("visits", 0))
		v.add_child(UIKit.label(info, 18, UIKit.MUTED))
		var left: float = Contracts.hours_left(c)
		if left < INF:
			var tl := UIKit.label("Snowed in — %d h left to clear it%s" % [int(ceil(maxf(left, 0.0))), "  (clock paused while the storm is falling)" if Contracts.storming() else ""], 20,
				UIKit.BAD if left <= Catalog.balance.contract_warn_hours else UIKit.WARN)
			v.add_child(tl)
		if st == "active" or st == "needs_service":
			for z in c["zones"]:
				var zr := UIKit.hbox()
				v.add_child(zr)
				var zl := UIKit.label(z["name"], 19, Color.WHITE)
				zl.custom_minimum_size.x = 260
				zr.add_child(zl)
				var pb := UIKit.progress(1.0 if z["done"] else float(z.get("progress", 0.0)), UIKit.GOOD if z["done"] else UIKit.ACCENT, 16)
				pb.custom_minimum_size.x = 500
				zr.add_child(pb)
				zr.add_child(UIKit.label("done" if z["done"] else "%d%%" % int(float(z.get("progress", 0.0)) * 100), 18, UIKit.MUTED))
			v.add_child(UIKit.label("Each area is a clearing box: clear 90% of it and it snaps to bare ground.", 16, UIKit.MUTED))
	if not any:
		_p("No contracts yet. Check the Contract Board.")
	if not Contracts.history.is_empty():
		content.add_child(UIKit.label("Completed one-time jobs", 24, UIKit.ACCENT))
		for h in Contracts.history.slice(maxi(0, Contracts.history.size() - 10)):
			_p("%s — %s  (%s)" % [h["address"], UIKit.money(h["pay"]), Clock.format_time(h["time"])], Color.WHITE, 18)


# --- Store -------------------------------------------------------------------------------
func _store_card(id: String, title: String, price: int, desc: String, stats: String) -> void:
	var c := UIKit.card()
	content.add_child(c)
	var h := UIKit.hbox(16)
	c.add_child(h)
	if Catalog.tools.has(StringName(id)):
		h.add_child(Icons.tool(id, 72))
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UIKit.label(title, 24, Color.WHITE))
	var d := UIKit.label(desc, 18, UIKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 820
	v.add_child(d)
	if stats != "":
		v.add_child(UIKit.label(stats, 17, Color(0.75, 0.85, 1.0)))
	var right := UIKit.vbox(6)
	h.add_child(right)
	right.add_child(UIKit.label(UIKit.money(price), 26, Color(0.7, 1.0, 0.7)))
	var why := Economy.can_buy(id)
	var owned := ""
	if Catalog.tools.has(StringName(id)) and Game.owns_tool(id):
		owned = "Owned"
	var b := UIKit.button("Buy" if why == "" else why, func():
		var r := Economy.buy(id)
		_msg(r["msg"], r["ok"])
		_rebuild(false), 20, 210)
	b.disabled = why != ""
	right.add_child(b)
	if owned != "":
		right.add_child(UIKit.label(owned, 16, UIKit.GOOD))


func _store() -> void:
	_h1("Northern Supply Co. — Equipment Store")
	var open := Economy.store_open()
	_p("Orders appear in the store's parking lot at %s: tools on the yellow pickup pad, vehicles in the bays. Store hours 7:00–21:00 — %s." % [Layout.building_by_id("store")["address"], "open now: your order will be ready right away" if open else "closed now: orders will be ready at 7:00"], UIKit.GOOD if open else UIKit.WARN)
	content.add_child(UIKit.label("Hand tools & machines", 26, UIKit.ACCENT))
	for t in Catalog.store_tools():
		var td: ToolData = t
		var stats := "Width %.2f m" % td.width
		match td.kind:
			ToolData.Kind.SHOVEL, ToolData.Kind.HANDS:
				stats += "  ·  load %.3f m³  ·  throw %.1f m" % [td.capacity, td.throw_distance]
			ToolData.Kind.PUSHER, ToolData.Kind.SCRAPER:
				stats += "  ·  push capacity %.2f m³%s" % [td.capacity, "  ·  angle ±%d°" % int(td.max_angle_deg) if td.angle_adjustable else ""]
			ToolData.Kind.SLEIGH:
				stats += "  ·  load %.2f m³" % td.capacity
			ToolData.Kind.ELECTRIC_SHOVEL, ToolData.Kind.WALK_BLOWER:
				stats += "  ·  %.2f m³/s  ·  throw %.0f m" % [td.rate, td.throw_distance]
		_store_card(String(td.id), td.display_name, td.price, Settings.with_keys(td.description), stats)
	content.add_child(UIKit.label("Supplies", 26, UIKit.ACCENT))
	for k in Catalog.UTILITY.keys():
		var u: Dictionary = Catalog.UTILITY[k]
		_store_card(String(k), u["name"], u["price"], Settings.with_keys(u["desc"]), "You have %d" % Game.heat_pouches)
	content.add_child(UIKit.label("Vehicles (permanent equipment)", 26, UIKit.ACCENT))
	for v in Catalog.store_vehicles():
		var vd: VehicleData = v
		var stats2 := "Top speed %d km/h  ·  ground clearance %.2f m" % [int(vd.max_speed * 3.6), vd.clearance]
		if vd.has_plow:
			stats2 += "  ·  plow %.1f m" % vd.blade_width
		if vd.has_blower:
			stats2 += "  ·  blower %.1f m, %.1f m³/s, throw %d m" % [vd.blower_width, vd.blower_rate, int(vd.blower_throw)]
		if vd.dump_capacity > 0:
			stats2 += "  ·  bed %d m³" % int(vd.dump_capacity)
		stats2 += "  ·  %s" % ("heated cab" if vd.heated_cabin else "no cab")
		_store_card(String(vd.id), vd.display_name, vd.price, Settings.with_keys(vd.description), stats2)


func _upgrades() -> void:
	_h1("Upgrades")
	_p("Physical upgrades are picked up at the store lot (a crate on the pickup pad). Apps and home services activate right away.")
	var cats := {UpgradeData.Category.TOOL: "Hand tools", UpgradeData.Category.MACHINE: "Snowblowers", UpgradeData.Category.VEHICLE: "Vehicles",
		UpgradeData.Category.CLOTHING: "Cold protection", UpgradeData.Category.WEATHER: "Weather technology", UpgradeData.Category.PROPERTY: "Property"}
	for cat in cats.keys():
		content.add_child(UIKit.label(cats[cat], 26, UIKit.ACCENT))
		for id in Catalog.UPGRADE_IDS:
			var u: UpgradeData = Catalog.upgrade(id)
			if u == null or u.category != cat:
				continue
			var desc := u.description
			if Game.has_upgrade(u.id):
				desc += "  (owned)"
			_store_card(String(u.id), u.display_name, u.price, desc, "")


func _bills() -> void:
	_h1("Bills & Payments")
	if not Game.is_survival():
		_p("Fun Mode: no hydro bills. Enjoy the snow!")
	else:
		var pw := "ON" if Survival.power_on else "OFF — the house is losing its heat (%d%% left)" % int(Survival.house_heat * 100)
		_p("Power & heating: %s" % pw, UIKit.GOOD if Survival.power_on else UIKit.BAD, 22)
		_p("The hydro/heating bill is $%d per month, due on the 15th. If it is still unpaid when the clock passes midnight into the 16th, the power is cut. Paying restores it immediately (no reconnection fee)." % Catalog.balance.hydro_bill)
		for bl in Economy.bills:
			var c := UIKit.card()
			content.add_child(c)
			var h := UIKit.hbox(16)
			c.add_child(h)
			var overdue: bool = not bl["paid"] and Clock.day_index() > int(bl["due_day"])
			h.add_child(UIKit.label("Hydro — %s" % Clock.MONTHS[int(bl["month"])], 24, Color.WHITE))
			h.add_child(UIKit.label("due %s" % Clock.date_string(int(bl["due_day"])), 20, UIKit.BAD if overdue else UIKit.MUTED))
			h.add_child(UIKit.hspacer())
			h.add_child(UIKit.label(UIKit.money(bl["amount"]), 24, Color.WHITE))
			if bl["paid"]:
				h.add_child(UIKit.label("PAID", 22, UIKit.GOOD))
			else:
				var m: int = bl["month"]
				h.add_child(UIKit.button("Pay now", func():
					var r := Economy.pay_bill(m)
					_msg(r["msg"], r["ok"])
					_rebuild(false), 20))
	content.add_child(UIKit.label("Recent transactions", 26, UIKit.ACCENT))
	var tx := Economy.transactions.duplicate()
	tx.reverse()
	for t in tx.slice(0, 25):
		_p("%s   %s   %s" % [Clock.format_time(t["time"]), UIKit.money(t["amount"]), t["text"]], Color.WHITE if t["amount"] < 0 else UIKit.GOOD, 18)


func _property() -> void:
	_h1("Property & Storage")
	_p("Home: %s. Your tools and vehicles are physical objects — this list shows where they are." % Layout.player_lot["address"])
	content.add_child(UIKit.label("Carried tools", 24, UIKit.ACCENT))
	for i in range(4):
		var id: String = Game.slots[i]
		_p("Slot %d: %s" % [i + 1, Catalog.tool(StringName(id)).display_name if id != "" else "(empty — bare hands)"], Color.WHITE, 18)
	if Game.carried != "":
		_p("Carrying in your arms: %s" % Catalog.item_name(StringName(Game.carried)), Color.WHITE, 18)
	content.add_child(UIKit.label("Tools & machines in the world", 24, UIKit.ACCENT))
	for it in Game.items:
		var p: Vector3 = it["pos"]
		var nm := Catalog.item_name(StringName(str(it["tool"]).trim_prefix("crate:")))
		_p("%s — near %s%s" % [nm, Layout.describe_point(Vector2(p.x, p.z)), " (buried)" if it.get("buried", false) else ""], Color.WHITE, 18)
	for m in Game.machines:
		var p2: Vector3 = m["pos"]
		_p("%s — near %s" % [Catalog.item_name(StringName(m["tool"])), Layout.describe_point(Vector2(p2.x, p2.z))], Color.WHITE, 18)
	if Game.has_upgrade(&"tool_rack"):
		_p("Garage tool rack: %s" % (", ".join(Game.rack.map(func(x): return Catalog.item_name(StringName(x)))) if not Game.rack.is_empty() else "empty"), Color.WHITE, 18)
	content.add_child(UIKit.label("Vehicles", 24, UIKit.ACCENT))
	for v in Game.vehicles:
		var p3: Vector3 = v["pos"]
		_p("%s — near %s" % [Catalog.item_name(StringName(v["id"])), Layout.describe_point(Vector2(p3.x, p3.z))], Color.WHITE, 18)
	content.add_child(UIKit.label("Upgrades owned", 24, UIKit.ACCENT))
	if Game.upgrades.is_empty():
		_p("None yet.")
	for id in Game.upgrades.keys():
		_p("• " + Catalog.item_name(StringName(id)), Color.WHITE, 18)
	_p("Utility: %d heating pouches%s" % [Game.heat_pouches, "  ·  Truck keys: found" if Game.flags.get("truck_keys", false) else "  ·  Truck keys: missing"], Color.WHITE, 18)


func _weather() -> void:
	_h1("Weather")
	var days := Weather.forecast_days()
	var detail := 0
	if Game.has_upgrade(&"weather_radar"):
		detail = 2
	elif Game.has_upgrade(&"weather_pro"):
		detail = 1
	_p("Now: " + Weather.current_summary(), Color.WHITE, 22)
	_p("Forecast (%d days%s). Forecasts can be wrong — storms sometimes arrive early or stronger than expected." % [days, ["", ", detailed", ", hourly radar"][detail]])
	for e in Weather.forecast(days):
		var c := UIKit.card()
		content.add_child(c)
		var h := UIKit.hbox(14)
		c.add_child(h)
		h.add_child(Icons.weather(e["cond"], 56))
		var l := UIKit.label(Weather.forecast_text(e, detail), 19, Color.WHITE)
		h.add_child(l)
	content.add_child(UIKit.label("City grader", 24, UIKit.ACCENT))
	_p("The city clears the streets every 3–4 days, whatever the weather. Next scheduled pass: %s.%s" % [Municipal.next_pass_text(), " (Passes so far this winter: %d)" % Municipal.passes], Color.WHITE)
	if not Contracts.contracted_segments().is_empty():
		_p("Streets under your city contract are skipped by the city grader: " + ", ".join(Contracts.contracted_segments()), UIKit.GOOD)
	if not Weather.alerts.is_empty():
		content.add_child(UIKit.label("Recent alerts", 24, UIKit.WARN))
		for a in Weather.alerts.slice(maxi(0, Weather.alerts.size() - 6)):
			_p("%s — %s" % [Clock.format_time(a["time"]), a["text"]], UIKit.WARN, 18)


func _orders() -> void:
	_h1("Orders")
	_p("Pick up your orders at %s (north end). Store hours 7:00–21:00." % Layout.building_by_id("store")["place"])
	if Economy.orders.is_empty():
		_p("No orders yet.")
	var list := Economy.orders.duplicate()
	list.reverse()
	for o in list:
		var status := Economy.order_status_text(o)
		if o["item"] == "pickup_plow" and o["status"] == "spawned":
			status = "Drive your pickup into the store lot to have it installed"
		var col := UIKit.GOOD if o["status"] == "spawned" or o["status"] == "ready" else (UIKit.WARN if o["status"] == "pending" else UIKit.MUTED)
		_p("#%d  %s — %s  (ordered %s)" % [o["id"], Catalog.item_name(StringName(o["item"])), status, Clock.format_time(o["placed"])], col, 20)


func _help() -> void:
	_h1("Help — Gerry's advice")
	var lines := HelpText.lines(Game.is_survival())
	for l in lines:
		_p(l, Color.WHITE, 19)
	content.add_child(UIKit.label("Controls", 26, UIKit.ACCENT))
	for a in Settings.ACTIONS.keys():
		_p("%s — %s" % [Settings.ACTIONS[a][0], Settings.action_label(a)], UIKit.MUTED, 17)
