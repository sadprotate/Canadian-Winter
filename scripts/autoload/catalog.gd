extends Node
## Equipment catalog: loads all data resources once. Balancing lives in res://data/.

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _ItemUpgrades := preload("res://scripts/data/item_upgrades.gd")

const TOOL_IDS: Array[StringName] = [&"hands", &"small_shovel", &"standard_shovel", &"wide_pusher",
	&"snow_scraper", &"large_scraper", &"snow_sleigh", &"electric_shovel", &"small_blower", &"large_blower"]
const VEHICLE_IDS: Array[StringName] = [&"pickup", &"pickup_plow", &"atv_blade", &"tractor_blade",
	&"tractor_blower", &"grader", &"plow_truck", &"rotary_blower", &"dump_truck"]
## Upgrades that aren't an item's (weather technology, property). Polish 5 §13: the heated driveway
## and heated path are property upgrades; the clothing moved to the insulated coat (equipment).
const UPGRADE_IDS: Array[StringName] = [&"weather_pro", &"weather_radar", &"furnace", &"tool_rack",
	&"heated_driveway", &"heated_path"]
## Polish 5 §13: the Insulated Work Jacket and the Arctic Parka (cold_protection ×0.8, ×0.75) are no
## longer sold: the insulated coat (Equipment) replaces both. Still loaded for old saves, orders and
## crates, which become the coat (Equipment.migrate).
const RETIRED_UPGRADE_IDS: Array[StringName] = [&"clothing_1", &"clothing_2"]
## Polish 5 §13 (Decision 8): the old global tool, machine and vehicle upgrades (and the pickup's
## plow, "pickup_plow"). No longer sold: they are the templates of every item's levels
## (ItemUpgrades.TRACKS), and still name old orders and crates, which carry over when collected.
const LEGACY_UPGRADE_IDS: Array[StringName] = [&"shovel_capacity_1", &"shovel_capacity_2", &"throw_1", &"throw_2",
	&"blade_width_1", &"clear_speed_1", &"blower_intake_1", &"blower_throw_1", &"pickup_plow",
	&"vehicle_speed_1", &"vehicle_width_1", &"vehicle_blower_1"]

## Consumable utility items sold in the store.
const UTILITY := {
	&"heat_pouches": {"name": "Heating Pouches (5 pack)", "price": 12, "count": 5,
		"desc": "Air-activated heat pouches. Press {use_pouch} to use one: quick warmth and slower cooling for a while."},
}

## Polish 5 §13: equipment sold in the Equipment store — not tools: picked up at the store like any
## order and never in a tool slot (Equipment). Prices are balance values; ids are none of a tool's,
## vehicle's or upgrade's (the pickup_plow clash).
const EQUIPMENT := {
	&"insulated_coat": {"name": "Insulated Coat", "price_key": "coat_price",
		"desc": "A long down parka with a hood and fleece cuffs. You lose warmth much more slowly outdoors (Survival). Worn as soon as you pick it up."},
	&"snowshoes": {"name": "Snowshoes", "price_key": "snowshoes_price",
		"desc": "Walk on top of deep snow instead of wading through it: you sink in only part way and leave a shallow track. On by default; to take them off or put them on, hold {inventory} and press {interact}."},
	&"heated_pad": {"name": "Heated Snow-Melting Pad", "price_key": "pad_price",
		"desc": "A rubber mat with heating cables. Put it down on your own lot ({drop}) and throw snow on it: it melts. Uses power while melting (hydro bill). Pick it up with {interact}."},
}

var tools: Dictionary = {}
var vehicles: Dictionary = {}
var upgrades: Dictionary = {}
var balance: BalanceData


func _ready() -> void:
	for id in TOOL_IDS:
		var r = load("res://data/tools/%s.tres" % id)
		if r is ToolData:
			tools[id] = r
		else:
			push_error("Missing tool data: %s" % id)
	for id in VEHICLE_IDS:
		var r = load("res://data/vehicles/%s.tres" % id)
		if r is VehicleData:
			vehicles[id] = r
		else:
			push_error("Missing vehicle data: %s" % id)
	for id in UPGRADE_IDS + LEGACY_UPGRADE_IDS + RETIRED_UPGRADE_IDS:
		var r = load("res://data/upgrades/%s.tres" % id)
		if r is UpgradeData:
			upgrades[id] = r
		else:
			push_error("Missing upgrade data: %s" % id)
	var b = load("res://data/balance.tres")
	balance = b if b is BalanceData else BalanceData.new()
	# Polish 5 §13: every item's own upgrade levels, built from the table and the data above.
	_ItemUpgrades.build(self)


func tool(id: StringName) -> ToolData:
	return tools.get(id, tools.get(&"hands"))


func vehicle(id: StringName) -> VehicleData:
	return vehicles.get(id)


func upgrade(id: StringName) -> UpgradeData:
	return upgrades.get(id)


## Polish 5 §13: every upgrade for sale — each item's levels (ladder order), then UPGRADE_IDS.
func upgrade_ids() -> Array:
	var out := []
	for item in _ItemUpgrades.items():
		for t in _ItemUpgrades.tracks(item):
			for id in _ItemUpgrades.ids(item, t):
				out.append(StringName(id))
	out.append_array(UPGRADE_IDS)
	return out


## Store listing for tools and walk-behind machines (excludes hands).
func store_tools() -> Array:
	var out := []
	for id in TOOL_IDS:
		if id == &"hands":
			continue
		out.append(tools[id])
	return out


func store_vehicles() -> Array:
	var out := []
	for id in VEHICLE_IDS:
		if id == &"pickup" or id == &"pickup_plow":
			continue
		out.append(vehicles[id])
	return out


func item_name(id: StringName) -> String:
	if tools.has(id):
		return tools[id].display_name
	if vehicles.has(id):
		return vehicles[id].display_name
	if upgrades.has(id):
		return upgrades[id].display_name
	if UTILITY.has(id):
		return UTILITY[id]["name"]
	if EQUIPMENT.has(id):
		return EQUIPMENT[id]["name"]
	return String(id)
