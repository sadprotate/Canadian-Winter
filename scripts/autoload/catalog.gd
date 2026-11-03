extends Node
## Equipment catalog: loads all data resources once. Balancing lives in res://data/.

const TOOL_IDS: Array[StringName] = [&"hands", &"small_shovel", &"standard_shovel", &"wide_pusher",
	&"snow_scraper", &"large_scraper", &"snow_sleigh", &"electric_shovel", &"small_blower", &"large_blower"]
const VEHICLE_IDS: Array[StringName] = [&"pickup", &"pickup_plow", &"atv_blade", &"tractor_blade",
	&"tractor_blower", &"grader", &"plow_truck", &"rotary_blower", &"dump_truck"]
const UPGRADE_IDS: Array[StringName] = [&"shovel_capacity_1", &"shovel_capacity_2", &"throw_1", &"throw_2",
	&"blade_width_1", &"clear_speed_1", &"blower_intake_1", &"blower_throw_1", &"pickup_plow",
	&"vehicle_speed_1", &"vehicle_width_1", &"vehicle_blower_1", &"clothing_1", &"clothing_2",
	&"weather_pro", &"weather_radar", &"furnace", &"tool_rack"]

## Consumable utility items sold in the store.
const UTILITY := {
	&"heat_pouches": {"name": "Heating Pouches (5 pack)", "price": 12, "count": 5,
		"desc": "Air-activated heat pouches. Press G to use one: quick warmth and slower cooling for a while."},
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
	for id in UPGRADE_IDS:
		var r = load("res://data/upgrades/%s.tres" % id)
		if r is UpgradeData:
			upgrades[id] = r
		else:
			push_error("Missing upgrade data: %s" % id)
	var b = load("res://data/balance.tres")
	balance = b if b is BalanceData else BalanceData.new()


func tool(id: StringName) -> ToolData:
	return tools.get(id, tools.get(&"hands"))


func vehicle(id: StringName) -> VehicleData:
	return vehicles.get(id)


func upgrade(id: StringName) -> UpgradeData:
	return upgrades.get(id)


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
	return String(id)
