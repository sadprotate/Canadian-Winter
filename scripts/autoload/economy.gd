extends Node
## Purchases, store orders, hydro bills and transactions (Parts 16, 17.7, 17.8).
## Every purchase becomes an order at the Northern Supply Co. lot: ready immediately during
## store hours (7:00–21:00), otherwise at 7:00. The world's Store node spawns real objects.

signal orders_changed
signal bills_changed

var orders: Array = []        # {id, item, kind, price, placed, ready_at, status}
var bills: Array = []         # {month, amount, issued_day, due_day, paid}
var transactions: Array = []  # {time, text, amount}
var _next_order := 1


func reset_for_new_game() -> void:
	orders = []
	bills = []
	transactions = []
	_next_order = 1


func start_winter() -> void:
	bills = []
	if Game.is_survival():
		_issue_bill(0)
	# Orders that were never collected stay in the lot.
	bills_changed.emit()


func store_open(m: float = -1.0) -> bool:
	if m < 0.0:
		m = Clock.minutes
	var h := fmod(m, 1440.0) / 60.0
	var b: BalanceData = Catalog.balance
	return h >= b.store_open_hour and h < b.store_close_hour


func next_open_time() -> float:
	var b: BalanceData = Catalog.balance
	var day := Clock.day_index()
	var h := Clock.hour_f()
	if h < b.store_open_hour:
		return Clock.at(day, b.store_open_hour)
	return Clock.at(day + 1, b.store_open_hour)


func log_tx(text: String, amount: int) -> void:
	transactions.append({"time": Clock.minutes, "text": text, "amount": amount})
	if transactions.size() > 80:
		transactions.pop_front()


## Classify a catalog id.
func item_kind(item_id: String) -> String:
	var sid := StringName(item_id)
	if Catalog.tools.has(sid):
		var t: ToolData = Catalog.tools[sid]
		return "machine" if not t.uses_slot else "tool"
	if Catalog.vehicles.has(sid):
		return "vehicle"
	if Catalog.upgrades.has(sid):
		return "upgrade"
	if Catalog.UTILITY.has(sid):
		return "utility"
	return ""


func price_of(item_id: String) -> int:
	var sid := StringName(item_id)
	if Catalog.tools.has(sid):
		return Catalog.tools[sid].price
	if Catalog.vehicles.has(sid):
		return Catalog.vehicles[sid].price
	if Catalog.upgrades.has(sid):
		return Catalog.upgrades[sid].price
	if Catalog.UTILITY.has(sid):
		return Catalog.UTILITY[sid]["price"]
	return 0


## Upgrades that are applied immediately (software / home services) instead of collected.
func upgrade_is_immediate(u: UpgradeData) -> bool:
	return u.category == UpgradeData.Category.WEATHER or u.category == UpgradeData.Category.PROPERTY and not u.requires_pickup


func can_buy(item_id: String) -> String:
	var kind := item_kind(item_id)
	if kind == "":
		return "Unknown item."
	if kind == "upgrade":
		var u: UpgradeData = Catalog.upgrade(StringName(item_id))
		if Game.has_upgrade(u.id) or has_open_order(item_id):
			return "Already owned."
		if u.requires != &"" and not Game.has_upgrade(u.requires):
			return "Requires %s." % Catalog.item_name(u.requires)
		if u.id == &"pickup_plow" and not _owns_vehicle("pickup"):
			return "You need your pickup truck."
	if price_of(item_id) > Game.money:
		return "Not enough money."
	return ""


func _owns_vehicle(id: String) -> bool:
	for v in Game.vehicles:
		if v["id"] == id:
			return true
	return false


func has_open_order(item_id: String) -> bool:
	for o in orders:
		if o["item"] == item_id and o["status"] != "collected":
			return true
	return false


func buy(item_id: String) -> Dictionary:
	var why := can_buy(item_id)
	if why != "":
		return {"ok": false, "msg": why}
	var price := price_of(item_id)
	if not Game.spend(price):
		return {"ok": false, "msg": "Not enough money."}
	var kind := item_kind(item_id)
	var item_label := Catalog.item_name(StringName(item_id))
	log_tx("Purchase: %s" % item_label, -price)
	if kind == "upgrade":
		var u: UpgradeData = Catalog.upgrade(StringName(item_id))
		if upgrade_is_immediate(u):
			Game.grant_upgrade(u.id)
			Notify.push("%s is now active." % item_label, Notify.GOOD)
			return {"ok": true, "msg": "%s activated." % item_label}
	var open := store_open()
	var order := {"id": _next_order, "item": item_id, "kind": kind, "price": price, "placed": Clock.minutes,
		"ready_at": Clock.minutes if open else next_open_time(), "status": "ready" if open else "pending"}
	_next_order += 1
	orders.append(order)
	orders_changed.emit()
	Game.dirty_since_save = true
	if open:
		Notify.push("Order placed: %s — ready for pickup at Northern Supply Co." % item_label, Notify.GOOD)
		return {"ok": true, "msg": "%s is ready for pickup at the store lot." % item_label}
	Notify.push("Order placed: %s — ready at 7:00 when the store opens." % item_label, Notify.INFO)
	return {"ok": true, "msg": "%s will be ready at 7:00." % item_label}


func order_status_text(o: Dictionary) -> String:
	match o["status"]:
		"ready":
			return "Ready for pickup"
		"pending":
			return "Ready at 7:00"
		"spawned":
			return "Waiting in the store lot"
		"collected":
			return "Collected"
	return str(o["status"])


func mark_order(order_id: int, status: String) -> void:
	for o in orders:
		if int(o["id"]) == order_id:
			o["status"] = status
	orders_changed.emit()
	Game.dirty_since_save = true


func ready_orders() -> Array:
	var out := []
	for o in orders:
		if o["status"] == "ready":
			out.append(o)
	return out


func on_hour(_day: int, hour: int) -> void:
	var b: BalanceData = Catalog.balance
	if hour == b.store_open_hour:
		var any := false
		for o in orders:
			if o["status"] == "pending":
				o["status"] = "ready"
				any = true
				Notify.push("%s is ready for pickup at the store." % Catalog.item_name(StringName(o["item"])), Notify.GOOD)
		if any:
			orders_changed.emit()


# -----------------------------------------------------------------------------
# Hydro bills (Survival only)
# -----------------------------------------------------------------------------

func _issue_bill(month: int) -> void:
	var b: BalanceData = Catalog.balance
	for bl in bills:
		if int(bl["month"]) == month:
			return
	var issued: int = Clock.MONTH_START[month]
	bills.append({"month": month, "amount": b.hydro_bill, "issued_day": issued,
		"due_day": Clock.day_of(month, b.hydro_due_day), "paid": false})
	bills_changed.emit()
	if month > 0:
		Notify.push("New hydro bill: $%d due %s." % [b.hydro_bill, Clock.date_string(Clock.day_of(month, b.hydro_due_day))], Notify.INFO)


func unpaid_bills() -> Array:
	var out := []
	for bl in bills:
		if not bl["paid"]:
			out.append(bl)
	return out


func pay_bill(month: int) -> Dictionary:
	for bl in bills:
		if int(bl["month"]) == month and not bl["paid"]:
			var amt: int = bl["amount"]
			if not Game.spend(amt):
				return {"ok": false, "msg": "Not enough money to pay the bill."}
			bl["paid"] = true
			Game.stats_add("bills_paid", 1)
			log_tx("Hydro bill (%s)" % Clock.MONTHS[month], -amt)
			bills_changed.emit()
			Notify.push("Hydro bill paid ($%d)." % amt, Notify.GOOD)
			var overdue := false
			for o in bills:
				if not o["paid"] and Clock.day_index() > int(o["due_day"]):
					overdue = true
			if not Survival.power_on and not overdue:
				Survival.restore_power()
			return {"ok": true, "msg": "Bill paid."}
	return {"ok": false, "msg": "No unpaid bill for that month."}


func on_day(day: int) -> void:
	if not Game.is_survival():
		return
	var b: BalanceData = Catalog.balance
	var m := Clock.month_of(day)
	var dom := Clock.day_of_month(day)
	if dom == 1 and m <= 3:
		_issue_bill(m)
	# The clock just passed midnight from the 15th into the 16th: unpaid bills cut the power.
	if dom == b.hydro_due_day + 1:
		for bl in bills:
			if not bl["paid"] and int(bl["due_day"]) < day:
				Survival.cut_power()
				break
	if dom == b.hydro_due_day - 2 or dom == b.hydro_due_day:
		for bl in bills:
			if not bl["paid"] and int(bl["month"]) == m:
				Notify.push("Reminder: hydro bill of $%d is due %s." % [bl["amount"], Clock.date_string(bl["due_day"])], Notify.WARN)


func serialize() -> Dictionary:
	return {"orders": orders, "bills": bills, "tx": transactions, "next_order": _next_order}


func deserialize(d: Dictionary) -> void:
	orders = d.get("orders", [])
	for o in orders:
		o["id"] = int(o["id"])
	bills = d.get("bills", [])
	for bl in bills:
		bl["month"] = int(bl["month"])
		bl["due_day"] = int(bl["due_day"])
	transactions = d.get("tx", [])
	_next_order = int(d.get("next_order", 1))
	orders_changed.emit()
	bills_changed.emit()
