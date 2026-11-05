class_name ComputerUI
extends Control
## The home computer (Part 24): weather, contracts, contract board, equipment store, upgrades,
## bills & payments, orders, property/storage, help. Live updates, battery backup.
##
## Polish 5 §7: one layout for every app — a header (the company, its reputation, money, day and
## time), a sidebar with the apps in a fixed order, and a content area under the app's title. It
## always opens on Weather. The first time Contracts or the Contract board opens, a short form names
## the company (renamed later from Contracts). Contracts has two tabs: Active and History.

signal closed

## The apps, in sidebar order (polish 5 §7): APP_IDS are stable ids, APPS the names shown.
const APP_IDS := ["weather", "contracts", "board", "store", "upgrades", "bills", "orders", "property", "help"]
const APPS := ["Weather", "Contracts", "Contract board", "Equipment store", "Upgrades", "Bills & payments",
	"Orders", "Property & storage", "Help"]
## Apps refreshed every 2 s (time-based); the rest every 30 s, and on data signals. Polish 5 §10:
## the board too (live bidding).
const LIVE_APPS := ["contracts", "board", "bills", "weather", "orders"]

## Type sizes and spacing shared by every app (polish 5 §7).
const FS_TITLE := 30      # the app's title
const FS_SECTION := 22    # a section heading
const FS_CARD := 22       # a card's first line
const FS_BODY := 18       # text, table cells
const FS_SMALL := 16      # notes
const GAP := 12           # between the blocks of an app
const COL_GAP := 28       # between table columns
const WIN := Vector2(1640, 900)
const SIDEBAR_W := 280
const CONTRACT_TABS := ["Active", "History"]

var current := 0
var content: VBoxContainer
var scroll: ScrollContainer
var title_l: Label
var company_l: Label
var reputation_l: Label
var balance_l: Label
var clock_l: Label
var battery_l: Label
var status_l: Label
var app_buttons: Array = []
var name_edit: LineEdit           # the company-name field while the form is up
var contracts_tab := 0            # 0 Active, 1 History
var _renaming := false
var _name_err: Label
var _refresh_t := 0.0
var _bid_values: Dictionary = {}
var bid_edits: Dictionary = {}       # polish 5 §10: lid -> the typed-bid field on the board
## Polish 5 §10b: the board's cards, lid -> {card, info, status, form}, and what its header and the
## order of its listings were when it was built ("" when the board isn't what's showing).
var _board_cards: Dictionary = {}
var _board_head := ""
var _battery := 100.0


static func app_index(id: String) -> int:
	return APP_IDS.find(id)


## Polish 5 §10: "Reputation 52 · Residential" — the value and the tier's name (header, board).
static func reputation_text() -> String:
	return "Reputation %d · %s" % [int(Game.reputation), Contracts.tier_name(Contracts.tier_index())]


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	UIKit.full_rect(dim)
	add_child(dim)
	var win := UIKit.center_panel(self, WIN)
	win.name = "Window"
	win.add_theme_stylebox_override("panel", UIKit.sb(Color(0.86, 0.88, 0.92, 0.98), 12, 3, Color(0.2, 0.22, 0.3), 0))
	var outer := UIKit.vbox(0)
	win.add_child(outer)
	# Header: the company and its reputation; money, day and time; close.
	var bar := UIKit.panel(UIKit.sb(Color(0.12, 0.2, 0.38), 0, 0, Color.TRANSPARENT, 14))
	bar.name = "Header"
	outer.add_child(bar)
	var bh := UIKit.hbox(20)
	bar.add_child(bh)
	company_l = UIKit.label("", 24, Color.WHITE)
	company_l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	bh.add_child(company_l)
	reputation_l = UIKit.label("", FS_BODY, Color(0.8, 0.86, 1.0))
	bh.add_child(reputation_l)
	bh.add_child(UIKit.hspacer())
	battery_l = UIKit.label("", FS_BODY, UIKit.WARN)
	bh.add_child(battery_l)
	balance_l = UIKit.label("", 24, Color(0.7, 1.0, 0.7))
	bh.add_child(balance_l)
	clock_l = UIKit.label("", 20, Color(0.85, 0.9, 1.0))
	bh.add_child(clock_l)
	bh.add_child(UIKit.button("Close  (%s)" % Settings.action_label("pause"), _close, 20))
	var body := UIKit.hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	# Sidebar: the apps in order, then the last action's message.
	var side := UIKit.panel(UIKit.sb(Color(0.16, 0.2, 0.3), 0, 0, Color.TRANSPARENT, 12))
	side.name = "Sidebar"
	side.custom_minimum_size.x = SIDEBAR_W
	body.add_child(side)
	var sv := UIKit.vbox(8)
	side.add_child(sv)
	for i in range(APPS.size()):
		var idx := i
		var b := UIKit.button(APPS[i], func(): _open_app(idx), 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.name = "App_" + APP_IDS[i]
		sv.add_child(b)
		app_buttons.append(b)
	sv.add_child(UIKit.spacer(10))
	status_l = UIKit.label("", FS_SMALL, Color(0.85, 0.9, 1.0))
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_l.custom_minimum_size.x = SIDEBAR_W - 30
	sv.add_child(status_l)
	# Content: the app's title, then its content (scrolls).
	var main := UIKit.panel(UIKit.sb(Color(0.1, 0.12, 0.19), 0, 0, Color.TRANSPARENT, 18))
	main.name = "Main"
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	var mv := UIKit.vbox(GAP)
	main.add_child(mv)
	title_l = UIKit.label("", FS_TITLE, Color.WHITE)
	mv.add_child(title_l)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(scroll)
	content = UIKit.vbox(GAP)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	Contracts.changed.connect(_soft_refresh)
	Economy.orders_changed.connect(_soft_refresh)
	Economy.bills_changed.connect(_soft_refresh)
	_update_header(0.0)
	# Polish 5 §7: every time the computer is used, it opens on Weather.
	_open_app(app_index("weather"))


func _close() -> void:
	closed.emit()
	queue_free()


## Polish 5 §7: Esc (Pause) or ui_cancel in the name field leaves the field; the next one closes
## the computer as before. Runs before the field sees the key. Polish 5 §10: the same for a typed
## bid on the board.
func _input(event: InputEvent) -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit and is_ancestor_of(f):
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			f.release_focus()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()


func _soft_refresh() -> void:
	_refresh_t = 0.0


func _process(delta: float) -> void:
	_update_header(delta)
	# Live updates: rebuild on data signals, plus a slow refresh for time-based apps. Never while
	# the player is dragging a bid slider or clicking, nor while the name form is up.
	_refresh_t -= delta
	if _refresh_t <= 0.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not form_up() and not Game.typing():
		_refresh_t = 2.0 if APP_IDS[current] in LIVE_APPS else 30.0
		_rebuild(false)


func _update_header(delta: float) -> void:
	var named := Game.company_name != ""
	company_l.text = Game.company_name if named else "Your company"
	company_l.add_theme_color_override("font_color", Color.WHITE if named else UIKit.MUTED)
	reputation_l.text = reputation_text()
	balance_l.text = UIKit.money(Game.money)
	clock_l.text = "%s %s  %s" % [Clock.weekday(Clock.day_index(), Game.year), Clock.date_string(Clock.day_index(), true), Clock.time_string()]
	if not Survival.power_on:
		_battery = maxf(22.0, _battery - delta * 0.6)
		battery_l.text = "🔋 Battery backup %d%%" % int(_battery)
	else:
		_battery = minf(100.0, _battery + delta * 2.0)
		battery_l.text = ""


func _open_app(i: int) -> void:
	if i != current:
		_renaming = false
	current = i
	for k in range(app_buttons.size()):
		(app_buttons[k] as Button).add_theme_stylebox_override("normal", UIKit.sb(UIKit.ACCENT.darkened(0.25) if k == i else Color(0.18, 0.22, 0.33, 0.95), 9, 0, Color.TRANSPARENT, 16))
	_rebuild(true)


## Polish 5 §7: the Contracts app's tab (0 Active, 1 History).
func show_contracts_tab(i: int) -> void:
	contracts_tab = clampi(i, 0, CONTRACT_TABS.size() - 1)
	_rebuild(true)


## True while the company-name form is showing.
func form_up() -> bool:
	return name_edit != null and is_instance_valid(name_edit) and name_edit.is_inside_tree()


func _rebuild(reset_scroll: bool) -> void:
	# Polish 5 §10b: a live update of the board touches only the listings that changed (rebuilding
	# its 10–14 cards on every bid took 20–49 ms in one frame).
	if not reset_scroll and _board_head != "" and APP_IDS[current] == "board" and not _renaming and _board_head == _board_head_sig() and _update_board():
		return
	var sv := scroll.scroll_vertical
	UIKit.clear(content)
	name_edit = null
	_name_err = null
	bid_edits = {}
	_board_cards = {}
	_board_head = ""
	title_l.text = APPS[current]
	var id: String = APP_IDS[current]
	if id in ["contracts", "board"] and (Game.company_name == "" or _renaming):
		_name_form()
	else:
		match id:
			"weather": _weather()
			"contracts": _contracts()
			"board": _board()
			"store": _store()
			"upgrades": _upgrades()
			"bills": _bills()
			"orders": _orders()
			"property": _property()
			"help": _help()
	if not reset_scroll:
		scroll.set_deferred("scroll_vertical", sv)
	else:
		scroll.scroll_vertical = 0


# --- Building blocks ----------------------------------------------------------------------------

func _section(t: String, color := UIKit.ACCENT) -> Label:
	var l := UIKit.label(t, FS_SECTION, color)
	content.add_child(l)
	return l


func _p(t: String, color := UIKit.MUTED, font_size := FS_BODY, parent: Node = null) -> Label:
	var l := UIKit.label(t, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parent if parent != null else content).add_child(l)
	return l


## A table: columns line up across its rows. Cells are added with _cell, row by row.
func _table(cols: int, parent: Node = null) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", COL_GAP)
	g.add_theme_constant_override("v_separation", 6)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parent if parent != null else content).add_child(g)
	return g


## A table cell. `wide` cells take the rest of the row and wrap.
func _cell(g: Control, t: String, color := UIKit.TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, wide := false, font_size := FS_BODY) -> Label:
	var l := UIKit.label(t, font_size, color, align)
	if wide:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(l)
	return l


func _msg(text: String, ok: bool) -> void:
	status_l.text = text
	status_l.add_theme_color_override("font_color", UIKit.GOOD if ok else UIKit.WARN)
	AudioMgr.ui("ui_money" if ok else "ui_error")


# --- The company name (polish 5 §7) -------------------------------------------------------------

func _name_form() -> void:
	title_l.text = "Rename your company" if _renaming and Game.company_name != "" else "Name your company"
	_p("Your company's name, %d to %d characters." % [1, Game.COMPANY_NAME_MAX])
	var row := UIKit.hbox(14)
	row.name = "NameForm"
	content.add_child(row)
	name_edit = LineEdit.new()
	name_edit.name = "CompanyName"
	name_edit.text = Game.company_name if Game.company_name != "" else Game.suggested_company_name()
	name_edit.max_length = Game.COMPANY_NAME_MAX
	name_edit.custom_minimum_size = Vector2(520, 0)
	name_edit.add_theme_font_size_override("font_size", 24)
	name_edit.context_menu_enabled = false
	name_edit.keep_editing_on_text_submit = true
	name_edit.text_submitted.connect(func(_t): _submit_name())
	row.add_child(name_edit)
	row.add_child(UIKit.button("OK", _submit_name, 22, 120))
	if _renaming and Game.company_name != "":
		row.add_child(UIKit.button("Cancel", func():
			_renaming = false
			_rebuild(true), 22, 120))
	_name_err = UIKit.label("", FS_BODY, UIKit.BAD)
	content.add_child(_name_err)
	_focus_name.call_deferred()


func _focus_name() -> void:
	if form_up():
		name_edit.grab_focus()
		name_edit.select_all()


func _submit_name() -> void:
	if not form_up():
		return
	var was := Game.company_name
	if not Game.set_company_name(name_edit.text):
		_name_err.text = "Use 1 to %d characters." % Game.COMPANY_NAME_MAX
		AudioMgr.ui("ui_error")
		name_edit.grab_focus()
		name_edit.edit()
		return
	_renaming = false
	name_edit.release_focus()
	_msg(("Company named: %s" if was == "" else "Company renamed: %s") % Game.company_name, true)
	_rebuild(true)


# --- Contracts: Active and History (polish 5 §7) -------------------------------------------------

const KIND_NAMES := {"one_time": "One-time job", "recurring": "Recurring", "municipal": "City contract"}


func _contracts() -> void:
	var head := UIKit.hbox(20)
	content.add_child(head)
	head.add_child(UIKit.label(Game.company_name, FS_CARD, Color.WHITE))
	head.add_child(UIKit.label(reputation_text(), FS_BODY, Color(0.8, 0.86, 1.0)))
	# Polish 5 §10: progress to the next tier.
	var nt := Contracts.next_tier()
	if not nt.is_empty():
		var pb := UIKit.progress(float(nt["frac"]), UIKit.ACCENT, 14)
		pb.custom_minimum_size.x = 200
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pb.name = "TierProgress"
		head.add_child(pb)
		head.add_child(UIKit.label("%s at %d" % [nt["name"], int(nt["need"])], FS_SMALL, UIKit.MUTED))
	head.add_child(UIKit.hspacer())
	head.add_child(UIKit.button("Rename", func():
		_renaming = true
		_rebuild(true), FS_BODY))
	var tabs := UIKit.hbox(8)
	tabs.name = "Tabs"
	content.add_child(tabs)
	var counts := [_shown_active().size(), Contracts.job_history.size()]
	for i in range(CONTRACT_TABS.size()):
		var k := i
		var b := UIKit.button("%s (%d)" % [CONTRACT_TABS[i], counts[i]], func(): show_contracts_tab(k), FS_BODY, 160)
		b.add_theme_stylebox_override("normal", UIKit.sb(UIKit.ACCENT.darkened(0.25) if i == contracts_tab else Color(0.18, 0.22, 0.33, 0.95), 9, 0, Color.TRANSPARENT, 16))
		tabs.add_child(b)
	if contracts_tab == 0:
		_active()
	else:
		_history()


## The contracts the Active tab lists: those running (completed and missed jobs are in History).
func _shown_active() -> Array:
	var out := []
	for c in Contracts.active:
		if c["status"] in ["active", "needs_service", "serviced"]:
			out.append(c)
	return out


func _active() -> void:
	var list := _shown_active()
	if list.is_empty():
		_p("No contracts yet. Bid on the Contract board.")
		return
	_p("Clear 90 % of a box and it snaps to bare ground.", UIKit.MUTED, FS_SMALL)
	for c in list:
		var card := UIKit.card()
		content.add_child(card)
		var v := UIKit.vbox(6)
		card.add_child(v)
		var top := UIKit.hbox(16)
		v.add_child(top)
		top.add_child(UIKit.label(c["address"], FS_CARD, Color.WHITE))
		top.add_child(UIKit.label(KIND_NAMES.get(c["type"], c["type"]), FS_BODY, UIKit.ACCENT))
		var st: String = c["status"]
		var st_text: String = {"active": "In progress", "needs_service": "Needs clearing", "serviced": "Clear — waiting for snow", "completed": "Completed ✓", "lost": "Lost — client left"}.get(st, st)
		var st_col := UIKit.WARN if st == "needs_service" else (UIKit.GOOD if st == "completed" or st == "serviced" else (UIKit.BAD if st == "lost" else UIKit.TEXT))
		top.add_child(UIKit.label(st_text, FS_BODY, st_col))
		top.add_child(UIKit.hspacer())
		top.add_child(UIKit.label(UIKit.money(c["pay"]) + (" / visit" if c["type"] != "one_time" else ""), FS_CARD, Color(0.7, 1.0, 0.7)))
		var info := "Client: %s" % c["client"]
		if c["type"] != "one_time":
			info += "  ·  Visits: %d" % int(c.get("visits", 0))
		v.add_child(UIKit.label(info, FS_SMALL, UIKit.MUTED))
		# Polish 5 §10: the due time (was the 48-hour snowed-in clock).
		var dt := Contracts.due_text(c)
		if dt != "":
			var left: float = Contracts.hours_left(c)
			var dl := "Due %s" % dt
			if left < INF:
				dl += "  ·  %d h left" % int(ceil(maxf(left, 0.0)))
			if bool(c.get("ext", false)):
				dl += "  ·  a storm added a day"
			v.add_child(UIKit.label(dl, FS_BODY, UIKit.BAD if left <= Catalog.balance.contract_warn_hours else UIKit.WARN))
		if st == "active" or st == "needs_service":
			var g := _table(3, v)
			for z in c["zones"]:
				var zl := _cell(g, z["name"], Color.WHITE)
				zl.custom_minimum_size.x = 240
				var pb := UIKit.progress(1.0 if z["done"] else float(z.get("progress", 0.0)), UIKit.GOOD if z["done"] else UIKit.ACCENT, 16)
				pb.custom_minimum_size.x = 480
				pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				g.add_child(pb)
				_cell(g, "done" if z["done"] else "%d %%" % int(float(z.get("progress", 0.0)) * 100), UIKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)


func _history() -> void:
	var h: Array = Contracts.job_history
	if h.is_empty():
		_p("No jobs finished yet. Completed and missed jobs are listed here.")
		return
	var year := -1
	var g: GridContainer = null
	for k in range(h.size() - 1, -1, -1):
		var e: Dictionary = h[k]
		if int(e.get("year", 1)) != year:
			year = int(e.get("year", 1))
			_section("Winter %d" % year, UIKit.ACCENT)
			g = _table(5)
			for col in ["Date", "Address", "Job", "Result", "Pay / reputation"]:
				_cell(g, col, UIKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT if col.begins_with("Pay") else HORIZONTAL_ALIGNMENT_LEFT, false, FS_SMALL)
		var res: String = e.get("result", "completed")
		var kind := "One-time job" if e.get("type", "") == "one_time" else ("Visit · city" if e.get("type", "") == "municipal" else "Visit · recurring")
		_cell(g, Clock.format_time(float(e.get("time", 0.0))))
		_cell(g, e.get("address", ""), Color.WHITE)
		_cell(g, kind)
		_cell(g, {"completed": "Completed", "missed": "Missed", "cancelled": "Cancelled"}.get(res, res),
			UIKit.GOOD if res == "completed" else (UIKit.BAD if res == "missed" else UIKit.MUTED))
		var amount := "—"
		if res == "completed":
			amount = UIKit.money(int(e.get("pay", 0)))
		elif res == "missed":
			amount = "%s reputation" % _signed(float(e.get("rep", 0.0)))
		_cell(g, amount, UIKit.GOOD if res == "completed" else (UIKit.BAD if res == "missed" else UIKit.MUTED), HORIZONTAL_ALIGNMENT_RIGHT)


static func _signed(v: float) -> String:
	var n := snappedf(v, 0.1)
	var s := str(int(absf(n))) if is_equal_approx(n, roundf(n)) else str(absf(n))
	return ("-" if n < 0.0 else "+") + s


# --- Contract board ---------------------------------------------------------------------------------

const JOB_NAMES := {"path": "Path job", "driveway": "Driveway job", "parking": "Parking lot", "street": "Street", "sidewalk": "Sidewalks"}


## Polish 5 §10: the board — every listing (locked above your tier), live bidding until 9 p.m.
func _board() -> void:
	_board_head = _board_head_sig()
	var who := UIKit.hbox(20)
	content.add_child(who)
	who.add_child(UIKit.label("Bidding as %s" % Game.company_name, FS_CARD, Color.WHITE))
	who.add_child(UIKit.label(reputation_text(), FS_BODY, Color(0.8, 0.86, 1.0)))
	_p("Bid until 9 p.m.; the lowest bid wins at 9:01 p.m. (a tie goes to you). Jobs are due by 9 p.m. the next day.", UIKit.MUTED, FS_SMALL)
	if Contracts.listings.is_empty():
		_p("No listings right now. New jobs are posted every morning at 6:00.")
	for l in Contracts.listings:
		_listing_card(l)


## Polish 5 §10b: what decides the board's header and its cards' order (a change rebuilds the board).
func _board_head_sig() -> String:
	return "%s|%s|%s" % [Game.company_name, reputation_text(), ",".join(Contracts.listings.map(func(l): return str(l["lid"])))]


## What decides a card's controls: its lock line, bidding closed, your bid or none (Place bid /
## Change bid and Withdraw), the suggested price and its range. Anything else is updated in place.
func _card_form(l: Dictionary) -> String:
	return "%s|%s|%s|%d" % [Contracts.listing_lock_text(l), str(bool(l.get("closed", false))), str(int(l.get("bid", 0)) > 0), int(l["budget"])]


## The card's second line: client, boxes and area, the snow, when bidding closes, the number of bids.
func _listing_info(l: Dictionary) -> String:
	var zn := []
	var area := 0.0
	for z in l["zones"]:
		zn.append(z["name"])
		area += Contracts.zone_area(z)
	var snow := float(l.get("now_volume", l["est_volume"]))
	var nb := Contracts.bid_count(l)
	return "%s  ·  %s, %d m²  ·  about %.1f m³ of snow  ·  closes %s  ·  %d bid%s" % [l["client"], ", ".join(zn), int(round(area)), snow,
		Contracts.when_text_rel(float(l["closes"])), nb, "" if nb == 1 else "s"]


## Your status on a listing and its colour: "Winning" / "Outbid · lowest bid $X" / "No bid yet".
static func _status_look(l: Dictionary) -> Array:
	var st := Contracts.bid_status(l)
	return [st["text"] if st["text"] != "" else "No bid yet", UIKit.GOOD if st["winning"] else (UIKit.BAD if st["mine"] > 0 else UIKit.MUTED)]


## Polish 5 §10b: bring the board's cards up to date without rebuilding it: a card whose controls
## change is rebuilt alone in its place; otherwise only its status and its second line change. False
## when a card is missing (the board is rebuilt).
func _update_board() -> bool:
	for l in Contracts.listings:
		if not _board_cards.has(int(l["lid"])):
			return false
	for l in Contracts.listings:
		var lid := int(l["lid"])
		var e: Dictionary = _board_cards[lid]
		if e["form"] != _card_form(l):
			var old: Control = e["card"]
			var at := old.get_index()
			_listing_card(l)
			content.move_child(_board_cards[lid]["card"], at)
			content.remove_child(old)
			old.queue_free()
			continue
		var info: Label = e["info"]
		var it := _listing_info(l)
		if info.text != it:
			info.text = it
		var st_l: Label = e["status"]
		if st_l != null:
			var look := _status_look(l)
			if st_l.text != look[0]:
				st_l.text = look[0]
				st_l.add_theme_color_override("font_color", look[1])
	return true


func _listing_card(l: Dictionary) -> void:
	var c := UIKit.card()
	c.name = "Listing_%d" % int(l["lid"])
	c.set_meta("lid", int(l["lid"]))
	content.add_child(c)
	var v := UIKit.vbox(6)
	c.add_child(v)
	var top := UIKit.hbox(16)
	v.add_child(top)
	var job: String = JOB_NAMES.get(str(l.get("job", "")), "Job")
	top.add_child(UIKit.label(l["address"], FS_CARD, Color.WHITE))
	top.add_child(UIKit.label("%s · %s" % [job, "one-time" if l["type"] == "one_time" else "all winter"], FS_BODY, UIKit.ACCENT))
	top.add_child(UIKit.hspacer())
	top.add_child(UIKit.label("Suggested " + UIKit.money(l["budget"]) + (" / visit" if l["type"] != "one_time" else ""), FS_CARD, Color(0.7, 1.0, 0.7)))
	var info := UIKit.label(_listing_info(l), FS_SMALL, UIKit.MUTED)
	info.name = "Info"
	v.add_child(info)
	var lid: int = l["lid"]
	_board_cards[lid] = {"card": c, "info": info, "status": null, "form": _card_form(l)}
	if Contracts.listing_locked(l):
		# Above your tier ("Needs reputation N"), or a street without a plow or a blower vehicle.
		var lock := UIKit.label(Contracts.listing_lock_text(l), FS_BODY, UIKit.WARN)
		lock.name = "Lock"
		v.add_child(lock)
		return
	var st := Contracts.bid_status(l)
	var look := _status_look(l)
	var st_l := UIKit.label(look[0], FS_BODY, look[1])
	st_l.name = "Status"
	st_l.custom_minimum_size.x = 300
	_board_cards[lid]["status"] = st_l
	if bool(l.get("closed", false)):
		var row0 := UIKit.hbox(14)
		v.add_child(row0)
		row0.add_child(st_l)
		row0.add_child(UIKit.label("Bidding closed — the result at 9:01 p.m.", FS_BODY, UIKit.MUTED))
		return
	var row := UIKit.hbox(14)
	v.add_child(row)
	row.add_child(st_l)
	var budget: int = l["budget"]
	var fl := Contracts.bid_floor(l)
	var cur: int = _bid_values.get(lid, st["mine"] if st["mine"] > 0 else budget)
	var e := LineEdit.new()
	e.name = "BidAmount"
	e.text = str(cur)
	e.max_length = 6
	e.custom_minimum_size = Vector2(110, 0)
	e.add_theme_font_size_override("font_size", FS_BODY)
	e.context_menu_enabled = false
	e.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bid_edits[lid] = e
	var s := HSlider.new()
	s.min_value = fl
	s.max_value = maxi(int(budget * 1.5), fl + 1)
	s.step = 1
	s.value = cur
	s.custom_minimum_size = Vector2(300, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(x):
		_bid_values[lid] = int(x)
		if not e.has_focus():
			e.text = str(int(x)))
	e.text_changed.connect(func(t):
		var n := int(t) if t.is_valid_int() else 0
		if n > 0:
			_bid_values[lid] = n
			s.set_value_no_signal(clampi(n, int(s.min_value), int(s.max_value))))
	e.text_submitted.connect(func(_t):
		e.release_focus()
		_bid(lid))
	row.add_child(UIKit.label("$", FS_BODY, Color.WHITE))
	row.add_child(e)
	row.add_child(s)
	row.add_child(UIKit.hspacer())
	row.add_child(UIKit.button("Change bid" if st["mine"] > 0 else "Place bid", func(): _bid(lid), FS_BODY))
	if st["mine"] > 0:
		row.add_child(UIKit.button("Withdraw", func():
			var r := Contracts.withdraw_bid(lid)
			_bid_values.erase(lid)
			_msg(r["msg"], r["ok"])
			_rebuild(false), FS_BODY))


func _bid(lid: int) -> void:
	var l := Contracts.listing_by_id(lid)
	if l.is_empty():
		return
	var amount := int(_bid_values.get(lid, int(l.get("bid", 0)) if int(l.get("bid", 0)) > 0 else int(l["budget"])))
	var r := Contracts.place_bid(lid, amount)
	_msg(r["msg"], r["ok"])
	_rebuild(false)


# --- Store -------------------------------------------------------------------------------

func _store_card(id: String, title: String, price: int, desc: String, stats: String, icon := "") -> void:
	var c := UIKit.card()
	content.add_child(c)
	var h := UIKit.hbox(16)
	c.add_child(h)
	if Catalog.tools.has(StringName(id)):
		h.add_child(Icons.tool(id, 72))
	elif icon != "":
		h.add_child(Icons.tool(icon, 72))
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UIKit.label(title, FS_CARD, Color.WHITE))
	_p(desc, UIKit.MUTED, FS_SMALL + 1, v)
	if stats != "":
		_p(stats, Color(0.75, 0.85, 1.0), FS_SMALL, v)
	var right := UIKit.vbox(6)
	right.custom_minimum_size.x = 230
	h.add_child(right)
	right.add_child(UIKit.label(UIKit.money(price), 24, Color(0.7, 1.0, 0.7), HORIZONTAL_ALIGNMENT_RIGHT))
	var why := Economy.can_buy(id)
	var b := UIKit.button("Buy", func():
		var r := Economy.buy(id)
		_msg(r["msg"], r["ok"])
		_rebuild(false), FS_BODY, 230)
	b.disabled = why != ""
	right.add_child(b)
	# Why it can't be bought (under the button, wrapped, so the column keeps its width), or Owned.
	if why != "":
		var wl := _p(why, UIKit.WARN, FS_SMALL, right)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if Catalog.tools.has(StringName(id)) and Game.owns_tool(id):
		right.add_child(UIKit.label("Owned", FS_SMALL, UIKit.GOOD, HORIZONTAL_ALIGNMENT_RIGHT))


func _store() -> void:
	var open := Economy.store_open()
	_p("Orders wait in the store's parking lot at %s: tools on the yellow pickup pad, vehicles in the bays. Open 7:00–21:00 — %s." % [Layout.building_by_id("store")["address"], "open now" if open else "closed now: orders are ready at 7:00"], UIKit.GOOD if open else UIKit.WARN)
	_section("Hand tools & machines")
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
	_section("Supplies")
	for k in Catalog.UTILITY.keys():
		var u: Dictionary = Catalog.UTILITY[k]
		_store_card(String(k), u["name"], u["price"], Settings.with_keys(u["desc"]), "You have %d" % Game.heat_pouches)
	_section("Vehicles")
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
	_p("Crates wait on the store's pickup pad. Apps and home services start right away.")
	var cats := {UpgradeData.Category.TOOL: "Hand tools", UpgradeData.Category.MACHINE: "Snowblowers", UpgradeData.Category.VEHICLE: "Vehicles",
		UpgradeData.Category.CLOTHING: "Cold protection", UpgradeData.Category.WEATHER: "Weather technology", UpgradeData.Category.PROPERTY: "Property"}
	for cat in cats.keys():
		_section(cats[cat])
		for id in Catalog.UPGRADE_IDS:
			var u: UpgradeData = Catalog.upgrade(id)
			if u == null or u.category != cat:
				continue
			var desc := u.description
			if Game.has_upgrade(u.id):
				desc += "  (owned)"
			_store_card(String(u.id), u.display_name, u.price, desc, "", _upgrade_icon(u))


## Polish 5 §6: an upgrade's card shows the icon of the kind of item it is for (from the one tool
## icon set): the hand tools' upgrades the small shovel, the snowblowers' the small blower.
static func _upgrade_icon(u: UpgradeData) -> String:
	match u.category:
		UpgradeData.Category.TOOL:
			return "small_shovel"
		UpgradeData.Category.MACHINE:
			return "small_blower"
	return ""


# --- Bills & payments -------------------------------------------------------------------------------

func _bills() -> void:
	if not Game.is_survival():
		_p("Fun Mode: no hydro bills.")
	else:
		var pw := "On" if Survival.power_on else "Off — the house is losing its heat (%d %% left)" % int(Survival.house_heat * 100)
		_p("Power & heating: %s" % pw, UIKit.GOOD if Survival.power_on else UIKit.BAD, FS_SECTION)
		_p("Hydro & heating: $%d a month, due on the 15th. Still unpaid at midnight into the 16th, the power is cut until you pay (no reconnection fee)." % Catalog.balance.hydro_bill)
		if not Economy.bills.is_empty():
			var g := _table(4)
			for bl in Economy.bills:
				var overdue: bool = not bl["paid"] and Clock.day_index() > int(bl["due_day"])
				_cell(g, "Hydro — %s" % Clock.MONTHS[int(bl["month"])], Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false, FS_CARD)
				_cell(g, "due %s" % Clock.date_string(int(bl["due_day"])), UIKit.BAD if overdue else UIKit.MUTED)
				_cell(g, UIKit.money(bl["amount"]), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, false, FS_CARD)
				if bl["paid"]:
					_cell(g, "Paid", UIKit.GOOD)
				else:
					var m: int = bl["month"]
					g.add_child(UIKit.button("Pay now", func():
						var r := Economy.pay_bill(m)
						_msg(r["msg"], r["ok"])
						_rebuild(false), FS_BODY))
	_section("Recent transactions")
	var tx := Economy.transactions.duplicate()
	tx.reverse()
	if tx.is_empty():
		_p("None yet.")
		return
	var g2 := _table(3)
	for t in tx.slice(0, 25):
		var col := Color.WHITE if t["amount"] < 0 else UIKit.GOOD
		_cell(g2, Clock.format_time(t["time"]), col)
		_cell(g2, UIKit.money(t["amount"]), col, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(g2, t["text"], col, HORIZONTAL_ALIGNMENT_LEFT, true)


# --- Property & storage -----------------------------------------------------------------------------

func _property() -> void:
	_p("Home: %s. Your tools and vehicles are where you left them." % Layout.player_lot["address"])
	_section("Carried tools")
	var g := _table(2)
	for i in range(4):
		var id: String = Game.slots[i]
		_cell(g, "Slot %d" % (i + 1), UIKit.MUTED)
		_cell(g, Catalog.tool(StringName(id)).display_name if id != "" else "empty — bare hands", Color.WHITE if id != "" else UIKit.MUTED)
	if Game.carried != "":
		_cell(g, "In your arms", UIKit.MUTED)
		_cell(g, Catalog.item_name(StringName(Game.carried)), Color.WHITE)
	_section("Tools & machines in the world")
	if Game.items.is_empty() and Game.machines.is_empty():
		_p("None.")
	else:
		var g2 := _table(2)
		for it in Game.items:
			var p: Vector3 = it["pos"]
			_cell(g2, Catalog.item_name(StringName(str(it["tool"]).trim_prefix("crate:"))), Color.WHITE)
			_cell(g2, "near %s%s" % [Layout.describe_point(Vector2(p.x, p.z)), " (buried)" if it.get("buried", false) else ""], UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		for m in Game.machines:
			var p2: Vector3 = m["pos"]
			_cell(g2, Catalog.item_name(StringName(m["tool"])), Color.WHITE)
			_cell(g2, "near %s" % Layout.describe_point(Vector2(p2.x, p2.z)), UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	if Game.has_upgrade(&"tool_rack"):
		_p("Garage tool rack: %s" % (", ".join(Game.rack.map(func(x): return Catalog.item_name(StringName(x)))) if not Game.rack.is_empty() else "empty"), Color.WHITE)
	_section("Vehicles")
	var g3 := _table(2)
	for v in Game.vehicles:
		var p3: Vector3 = v["pos"]
		_cell(g3, Catalog.item_name(StringName(v["id"])), Color.WHITE)
		_cell(g3, "near %s" % Layout.describe_point(Vector2(p3.x, p3.z)), UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	_section("Upgrades owned")
	if Game.upgrades.is_empty():
		_p("None yet.")
	else:
		_p(", ".join(Game.upgrades.keys().map(func(id): return Catalog.item_name(StringName(id)))), Color.WHITE)
	_p("Heating pouches: %d   ·   Truck keys: %s" % [Game.heat_pouches, "found" if Game.flags.get("truck_keys", false) else "missing"], Color.WHITE)


# --- Weather ----------------------------------------------------------------------------------------

func _weather() -> void:
	# Polish 5 §8: the TV's cards from the same forecast (at least the TV's three days; the weather
	# apps add days, the wind and the radar's systems hour by hour).
	var days := maxi(3, Weather.forecast_days())
	var detail := 0
	if Game.has_upgrade(&"weather_radar"):
		detail = 2
	elif Game.has_upgrade(&"weather_pro"):
		detail = 1
	_p("Now: " + Weather.current_summary(), Color.WHITE, FS_SECTION)
	_p("Next %d days%s  ·  forecast updated %s" % [days, ["", ", detailed", ", hourly radar"][detail], Weather.hour_name(Weather.issued_hour())], UIKit.MUTED, FS_SMALL)
	for e in Weather.forecast(days):
		var c := UIKit.card()
		content.add_child(c)
		var h := UIKit.hbox(14)
		c.add_child(h)
		h.add_child(Icons.weather(e["cond"], 56))
		var l := _p(Weather.forecast_text(e, detail), Color.WHITE, FS_BODY, h)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Polish 5 §11: Mondays and Fridays — the next crew day from the schedule.
	_section("City crews")
	_p("%s — the grader, then the sidewalk crew   ·   Passes this winter: %d" % [Municipal.crew_line(), Municipal.passes], Color.WHITE)
	if not Contracts.contracted_segments().is_empty():
		_p("Streets under your city contract are skipped by the city grader: " + ", ".join(Contracts.contracted_segments()), UIKit.GOOD)
	if not Weather.alerts.is_empty():
		_section("Recent alerts", UIKit.WARN)
		var g := _table(2)
		for a in Weather.alerts.slice(maxi(0, Weather.alerts.size() - 6)):
			_cell(g, Clock.format_time(a["time"]), UIKit.WARN)
			_cell(g, a["text"], UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true)


# --- Orders -----------------------------------------------------------------------------------------

func _orders() -> void:
	_p("Pick up at %s. Open 7:00–21:00." % Layout.building_by_id("store")["place"])
	if Economy.orders.is_empty():
		_p("No orders yet.")
		return
	var list := Economy.orders.duplicate()
	list.reverse()
	var g := _table(4)
	for col in ["#", "Item", "Status", "Ordered"]:
		_cell(g, col, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false, FS_SMALL)
	for o in list:
		var status := Economy.order_status_text(o)
		if o["item"] == "pickup_plow" and o["status"] == "spawned":
			status = "Drive your pickup into the store lot to have it installed"
		var col := UIKit.GOOD if o["status"] == "spawned" or o["status"] == "ready" else (UIKit.WARN if o["status"] == "pending" else UIKit.MUTED)
		_cell(g, "%d" % o["id"], col)
		_cell(g, Catalog.item_name(StringName(o["item"])), col)
		_cell(g, status, col, HORIZONTAL_ALIGNMENT_LEFT, true)
		_cell(g, Clock.format_time(o["placed"]), col)


# --- Help -------------------------------------------------------------------------------------------

func _help() -> void:
	_p("Gerry's advice", UIKit.MUTED, FS_SMALL)
	for l in HelpText.lines(Game.is_survival()):
		_p(l, Color.WHITE)
	_section("Controls")
	var g := _table(2)
	for a in Settings.ACTIONS.keys():
		_cell(g, Settings.ACTIONS[a][0], UIKit.MUTED)
		_cell(g, Settings.action_label(a), Color.WHITE)
