class_name ItemUpgrades
extends RefCounted
## Polish 5 §13 (Decision 8): upgrades belong to an item type. Bare hands, each hand tool, the
## electric shovel, each walk-behind blower and each vehicle has its own tracks, built here at load
## time (Catalog._ready → build) from one table, TRACKS, and the item data — the effects each item
## used before: a hand tool gets capacity (and fill), throw, push width and push power; the electric
## shovel throw, push width and push power; a blower intake and chute; a plow vehicle plow width and
## plow power; a blower vehicle its blower; the pickup the front plow; a vehicle without a cab a
## heated cab. Each level is one of the old global upgrades (data/upgrades/*.tres, kept as the
## levels' templates): the same effect, its price scaled with the item's price (balance "Upgrades").
## A level is an id "<item>:<track>:<level>" in Game.upgrades (the save key the global upgrades
## used), bought in the Upgrades app and collected as a crate, as before.
##
## The ladder (HANDOFF §7's order, ladder()): a track's levels for sale stop where the item would
## pass the next item's base value of what the track improves (QTY) by more than
## balance.upgrade_ladder_slack — unless the item is already ahead there at base (the next item is
## another kind of tool). Old saves: each old global level goes to every item it used to affect
## (migrate), even past that item's ladder: nothing the player paid for is lost.

## The tracks: name, the stat the game reads, the old global upgrades that are its levels, what it
## improves (QTY, for the ladder) and the text of a level (+N %).
const TRACKS := {
	&"capacity": {"name": "Capacity", "stat": &"shovel_capacity", "levels": [&"shovel_capacity_1", &"shovel_capacity_2"],
		"q": ["capacity", "fill"], "text": "+%d%% load and fill speed"},
	&"throw": {"name": "Throw", "stat": &"throw_distance", "levels": [&"throw_1", &"throw_2"],
		"q": ["throw"], "text": "+%d%% throw distance"},
	&"push_width": {"name": "Push width", "stat": &"blade_width", "levels": [&"blade_width_1"],
		"q": ["push_width"], "text": "+%d%% push width"},
	&"push": {"name": "Push power", "stat": &"push_speed", "levels": [&"clear_speed_1"],
		"q": ["push_strength"], "text": "+%d%% push strength and speed"},
	&"intake": {"name": "Intake", "stat": &"blower_rate", "levels": [&"blower_intake_1"],
		"q": ["intake"], "text": "+%d%% intake"},
	&"chute": {"name": "Chute", "stat": &"blower_throw", "levels": [&"blower_throw_1"],
		"q": ["throw"], "text": "+%d%% throw distance"},
	&"front_plow": {"name": "Front plow", "stat": &"pickup_plow", "levels": [&"pickup_plow"],
		"q": [], "text": "A 2.4 m angling plow. Drive the pickup to the store lot to fit it."},
	&"plow_width": {"name": "Plow width", "stat": &"vehicle_blade_width", "levels": [&"vehicle_width_1"],
		"q": ["push_width"], "text": "+%d%% plow width"},
	&"plow_power": {"name": "Plow power", "stat": &"vehicle_clear_speed", "levels": [&"vehicle_speed_1"],
		"q": ["push_strength"], "text": "+%d%% plow strength (less drag)"},
	&"blower": {"name": "Blower", "stat": &"vehicle_blower", "levels": [&"vehicle_blower_1"],
		"q": ["intake", "throw"], "text": "+%d%% blower intake and throw"},
	# One new level (no old upgrade): its price is balance.upgrade_cab_price, scaled.
	&"cab": {"name": "Heated cab", "stat": &"heated_cab", "levels": [], "q": [],
		"text": "An enclosed cab with a heater (Survival)"},
}
## What a track improves, in the units the ladder compares (m³, m³/s, m).
const QTY := {"capacity": "load (m³)", "fill": "fill speed (m³/s)", "throw": "throw (m)",
	"push_width": "push width (m)", "push_strength": "push strength (m³)", "intake": "intake (m³/s)"}
## The pickup's front plow (bought once; fitted when the pickup drives into the store lot). Its old
## id, "pickup_plow", is also the id of the plowed pickup vehicle: the store sold it as a vehicle.
const PLOW_ID := &"pickup:front_plow:1"
## In the Upgrades app the plowed pickup's tracks show on the pickup's card (one truck).
const GROUP := {&"pickup_plow": &"pickup"}

static var _tracks: Dictionary = {}    # item -> Array of track ids, in TRACKS order
static var _ids: Dictionary = {}       # item -> {track: Array of level ids (String)}
static var _max: Dictionary = {}       # item -> {track: levels for sale (the ladder)}
static var _legacy: Dictionary = {}    # old global upgrade id (String) -> [track, level]
static var _ladder: Array = []
## The one notification after an old save's global upgrades were carried over (game_root shows it).
static var pending_note := ""


## Every item type in the ladder's order (HANDOFF §7): bare hands and the hand tools by tier, the
## electric shovel, the walk-behind blowers, then the vehicles.
static func ladder() -> Array:
	return _ladder


## Build every item's tracks and levels into the catalog (cat = Catalog, during its _ready).
static func build(cat: Node) -> void:
	_tracks.clear()
	_ids.clear()
	_max.clear()
	_legacy.clear()
	_ladder = []
	_ladder.append_array(cat.TOOL_IDS)
	_ladder.append_array(cat.VEHICLE_IDS)
	for t in TRACKS.keys():
		var lv: Array = TRACKS[t]["levels"]
		for k in range(lv.size()):
			_legacy[String(lv[k])] = [t, k + 1]
	for item in ladder():
		var list := _tracks_from_data(cat, item)
		if list.is_empty():
			continue
		_tracks[item] = list
		_ids[item] = {}
		_max[item] = {}
		for t in list:
			var temps := _templates(cat, item, t)
			var ids := []
			var values := []
			for k in range(temps.size()):
				var tm: Dictionary = temps[k]
				var u := UpgradeData.new()
				u.id = StringName("%s:%s:%d" % [item, t, k + 1])
				u.item = item
				u.track = t
				u.level = k + 1
				u.category = _category(cat, item)
				u.display_name = "%s: %s%s" % [_item_label(cat, item), TRACKS[t]["name"], " %d" % (k + 1) if temps.size() > 1 else ""]
				u.price = tm["price"]
				u.description = tm["desc"]
				u.stat = TRACKS[t]["stat"]
				u.value = tm["value"]
				u.requires = StringName(ids[k - 1]) if k > 0 else &""
				u.requires_pickup = tm["pickup"]
				cat.upgrades[u.id] = u
				ids.append(String(u.id))
				values.append(u.value)
			_ids[item][t] = ids
			_max[item][t] = _ladder_max(cat, item, t, values)


## The tracks an item gets: from the effects it used (polish 5 before §13: Game.stat_value).
static func _tracks_from_data(cat: Node, item: StringName) -> Array:
	var out := []
	if cat.tools.has(item):
		var td: ToolData = cat.tools[item]
		if td.is_shovel_type():
			out = [&"capacity", &"throw", &"push_width", &"push"]
		elif td.kind == ToolData.Kind.ELECTRIC_SHOVEL:
			out = [&"throw", &"push_width", &"push"]
		elif td.kind == ToolData.Kind.WALK_BLOWER:
			out = [&"intake", &"chute"]
	elif cat.vehicles.has(item):
		var vd: VehicleData = cat.vehicles[item]
		if vd.kind == VehicleData.Kind.PICKUP:
			out.append(&"front_plow")
		if vd.has_plow:
			out.append_array([&"plow_width", &"plow_power"])
		if vd.has_blower:
			out.append(&"blower")
		if not vd.heated_cabin:
			out.append(&"cab")
	return out


## The levels of a track for an item: [{value, price, desc, pickup}].
static func _templates(cat: Node, item: StringName, t: StringName) -> Array:
	var out := []
	var b: BalanceData = cat.balance
	if t == &"cab":
		out.append({"value": 1.0, "price": nice_price(b.upgrade_cab_price * _item_price(cat, item) / b.upgrade_price_ref_vehicle),
			"desc": TRACKS[t]["text"], "pickup": false})
		return out
	for lid in TRACKS[t]["levels"]:
		var old: UpgradeData = cat.upgrades.get(lid)
		if old == null:
			continue
		var text: String = TRACKS[t]["text"]
		var desc := text % roundi((old.value - 1.0) * 100.0) if text.contains("%d") else text
		# The front plow keeps its price (the pickup itself has none); every other level scales.
		var price := old.price if t == &"front_plow" else nice_price(old.price * _item_price(cat, item) / _ref_price(cat, item))
		out.append({"value": old.value, "price": price, "desc": desc, "pickup": old.requires_pickup})
	return out


static func _item_price(cat: Node, item: StringName) -> float:
	if item == &"hands":
		return (cat.balance as BalanceData).upgrade_hands_price
	if cat.tools.has(item):
		return float((cat.tools[item] as ToolData).price)
	if cat.vehicles.has(item):
		return float((cat.vehicles[item] as VehicleData).price)
	return 0.0


static func _ref_price(cat: Node, item: StringName) -> float:
	var b: BalanceData = cat.balance
	if cat.vehicles.has(item):
		return b.upgrade_price_ref_vehicle
	if cat.tools.has(item) and (cat.tools[item] as ToolData).kind == ToolData.Kind.WALK_BLOWER:
		return b.upgrade_price_ref_machine
	return b.upgrade_price_ref_tool


static func _category(cat: Node, item: StringName) -> UpgradeData.Category:
	if cat.vehicles.has(item):
		return UpgradeData.Category.VEHICLE
	if cat.tools.has(item) and (cat.tools[item] as ToolData).kind == ToolData.Kind.WALK_BLOWER:
		return UpgradeData.Category.MACHINE
	return UpgradeData.Category.TOOL


static func _item_label(cat: Node, item: StringName) -> String:
	if cat.tools.has(item):
		return (cat.tools[item] as ToolData).display_name
	if cat.vehicles.has(item):
		return (cat.vehicles[item] as VehicleData).display_name
	return String(item)


## A price to two significant figures ($4, $96, $230, $1,800), at least $1.
static func nice_price(p: float) -> int:
	if p < 10.0:
		return maxi(1, roundi(p))
	var mag := pow(10.0, floorf(log(p) / log(10.0)) - 1.0)
	return int(roundf(p / mag) * mag)


# -----------------------------------------------------------------------------
# The ladder
# -----------------------------------------------------------------------------

## An item's base value of a ladder quantity (QTY), or -1 if it has none.
static func quantity(cat: Node, item: StringName, q: String) -> float:
	if cat.tools.has(item):
		var t: ToolData = cat.tools[item]
		if t.is_shovel_type():
			match q:
				"capacity": return t.capacity
				"fill": return t.fill_rate
				"throw": return t.throw_distance
				"push_width": return t.push_width
				"push_strength": return t.push_strength
		elif t.kind == ToolData.Kind.ELECTRIC_SHOVEL:
			match q:
				"throw": return t.throw_distance
				"push_width": return t.push_width
				"push_strength": return t.push_strength
				"intake": return t.rate
		elif t.kind == ToolData.Kind.WALK_BLOWER:
			match q:
				"intake": return t.rate
				"throw": return t.throw_distance
	elif cat.vehicles.has(item):
		var v: VehicleData = cat.vehicles[item]
		if v.has_plow:
			match q:
				"push_width": return v.blade_width
				"push_strength": return v.blade_capacity
		if v.has_blower:
			match q:
				"intake": return v.blower_rate
				"throw": return v.blower_throw
	return -1.0


## The next item after `item` in the ladder that has quantity q ("" if none).
static func next_with(cat: Node, item: StringName, q: String) -> StringName:
	var order := ladder()
	for k in range(order.find(item) + 1, order.size()):
		if quantity(cat, order[k], q) > 0.0:
			return order[k]
	return &""


static func _ladder_max(cat: Node, item: StringName, t: StringName, values: Array) -> int:
	var n_max := values.size()
	var slack: float = (cat.balance as BalanceData).upgrade_ladder_slack
	for q in TRACKS[t]["q"]:
		var base := quantity(cat, item, q)
		var nxt := next_with(cat, item, q)
		if base <= 0.0 or nxt == &"":
			continue
		var ref := quantity(cat, nxt, q)
		if base >= ref:
			continue    # already ahead of the next item there: the upgrade keeps the order
		var m := 1.0
		var n := 0
		for v in values:
			m *= float(v)
			if base * m > ref * (1.0 + slack) + 1e-9:
				break
			n += 1
		n_max = mini(n_max, n)
	return n_max


## The ladder, quantity by quantity: [{item, track, q, base, max, levels, next, next_base}] —
## every item's base and fully upgraded value (the levels for sale) against the next item's base.
static func ladder_rows() -> Array:
	var out := []
	for item in ladder():
		for t in tracks(item):
			for q in TRACKS[t]["q"]:
				var base := quantity(Catalog, item, q)
				if base <= 0.0:
					continue
				var n := max_level(item, t)
				var m := 1.0
				for k in range(n):
					m *= (Catalog.upgrades[StringName(_ids[item][t][k])] as UpgradeData).value
				var nxt := next_with(Catalog, item, q)
				out.append({"item": item, "track": t, "q": q, "base": base, "max": base * m, "levels": n,
					"next": nxt, "next_base": quantity(Catalog, nxt, q) if nxt != &"" else -1.0})
	return out


# -----------------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------------

## Items that have upgrades, in ladder order.
static func items() -> Array:
	return ladder().filter(func(i): return _tracks.has(i))


static func tracks(item: StringName) -> Array:
	return _tracks.get(item, [])


## The track's level ids, level 1 first.
static func ids(item: StringName, t: StringName) -> Array:
	return (_ids.get(item, {}) as Dictionary).get(t, [])


## The id of a level ("" if the track has no such level).
static func level_id(item: StringName, t: StringName, lvl: int) -> String:
	var l := ids(item, t)
	return l[lvl - 1] if lvl >= 1 and lvl <= l.size() else ""


## Levels for sale (the ladder's limit).
static func max_level(item: StringName, t: StringName) -> int:
	return int((_max.get(item, {}) as Dictionary).get(t, 0))


## Levels owned (from level 1 up).
static func level(item: StringName, t: StringName) -> int:
	var n := 0
	for id in ids(item, t):
		if not Game.upgrades.has(id):
			break
		n += 1
	return n


## The heated cab is sold in Survival only (Decision 9: cab heat doesn't matter in Fun Mode).
static func track_shown(_item: StringName, t: StringName) -> bool:
	return t != &"cab" or Game.is_survival()


## The combined multiplier of an item's owned levels for a stat (1.0 without any): the only place
## the game reads a per-item upgrade (tools, blowers, vehicles).
static func mult(item: StringName, stat: StringName) -> float:
	var m := 1.0
	var per: Dictionary = _ids.get(item, {})
	for t in per.keys():
		if TRACKS[t]["stat"] != stat:
			continue
		for id in per[t]:
			if not Game.upgrades.has(id):
				break
			m *= (Catalog.upgrades[StringName(id)] as UpgradeData).value
	return m


## You can only upgrade what you own: bare hands always; a tool or machine anywhere in the world,
## in your slots or arms, on the rack, or on order; a vehicle you have or have ordered.
static func owns(item: StringName) -> bool:
	if item == &"hands":
		return true
	var s := String(item)
	if Catalog.tools.has(item):
		return Game.owns_tool(s) or Economy.has_open_order(s)
	if Catalog.vehicles.has(item):
		for v in Game.vehicles:
			if str(v["id"]) == s:
				return true
		return Economy.has_open_order(s)
	return false


## Why a level can't be bought now ("" if it can — money and orders aside: Economy.can_buy).
static func why_not(u: UpgradeData) -> String:
	if not track_shown(u.item, u.track):
		return "Survival Mode only."
	if u.track == &"front_plow":
		if not owns(&"pickup"):
			return "You need your pickup truck."
	elif not owns(u.item):
		return "Fit the front plow first." if GROUP.has(u.item) else "Buy the %s first." % Catalog.item_name(u.item)
	if u.level > max_level(u.item, u.track):
		return "Fully upgraded."
	if u.level > 1 and level(u.item, u.track) < u.level - 1:
		return "Requires level %d." % (u.level - 1)
	return ""


## "Capacity 1, Throw 2" — an item's owned levels ("" if none).
static func summary(item: StringName) -> String:
	var parts := []
	for t in tracks(item):
		var n := level(item, t)
		if n > 0:
			parts.append("%s%s" % [TRACKS[t]["name"], " %d" % n if ids(item, t).size() > 1 else ""])
	return ", ".join(parts)


## Polish 5 §13 → §14: does a vehicle of this type have a heated cab — built in (VehicleData) or
## bought (the "cab" track, Survival)? The hook for §14's cab warmth: Vehicle still reads
## data.heated_cabin for its heat today.
static func has_heated_cab(vehicle_id: StringName) -> bool:
	var vd: VehicleData = Catalog.vehicle(vehicle_id)
	if vd == null:
		return false
	return vd.heated_cabin or Game.upgrades.has(level_id(vehicle_id, &"cab", 1))


# -----------------------------------------------------------------------------
# Old saves: the global upgrades (Decision 8)
# -----------------------------------------------------------------------------

## True for an old global upgrade that is now an item's level (still loaded: old orders and crates).
static func is_legacy(id: StringName) -> bool:
	return _legacy.has(String(id))


## Grant an old global level to every item it used to affect (levels 1 … its level of the track).
static func grant_legacy(id: StringName, ups: Dictionary) -> void:
	var tl: Array = _legacy.get(String(id), [])
	if tl.is_empty():
		return
	for item in _ids.keys():
		var l: Array = (_ids[item] as Dictionary).get(tl[0], [])
		for k in range(mini(int(tl[1]), l.size())):
			ups[l[k]] = true


## An old save's upgrades: each old global level goes to every item it used to affect, and leaves
## the list. True if anything was carried over (then one notification follows, pending_note).
static func migrate(ups: Dictionary) -> bool:
	var found := []
	for k in ups.keys():
		if is_legacy(StringName(str(k))):
			found.append(str(k))
	for k in found:
		ups.erase(k)
		grant_legacy(StringName(k), ups)
	if not found.is_empty():
		pending_note = "Upgrades now belong to each item. Everything you bought carries over to every item it improved."
	return not found.is_empty()
