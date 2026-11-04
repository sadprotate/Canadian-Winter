extends Node
## Central game state: mode, year, money, inventory, upgrades, flags, stats and the registry of
## persistent world objects (tools lying around, walk-behind machines, vehicles).

signal money_changed(amount: int)
signal inventory_changed
signal stage_changed(stage: int)
signal upgrades_changed

enum Stage { START, LETTER_READ, NEIGHBOR_TALKED, TRAIL_DONE, COMPLETE }

var mode := "fun"
var year := 1
var money := 20
var reputation := 50.0
var stats: Dictionary = {}
var lifetime: Dictionary = {}
var flags: Dictionary = {}
var slots: Array = ["", "", "", ""]
var selected := 0
var carried := ""
var heat_pouches := 0
var upgrades: Dictionary = {}
var vehicles: Array = []
var items: Array = []
var machines: Array = []
var rack: Array = []              # tools stored on the garage rack (ids)
var player_pos := Vector3.ZERO
var player_yaw := 0.0
var camera_third := false
var next_uid := 1
var in_game := false
var dirty_since_save := false
var world: Node = null
var player: Node = null
var weather_seed := 1


## Gameplay input is live when the mouse is captured (no menu open). Automated tests set
## force_input so they can drive the real controls headless.
var force_input := false


func input_captured() -> bool:
	if force_input:
		return world == null or world.get("modal") == null
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func is_survival() -> bool:
	return mode == "survival"


func stage() -> int:
	return int(flags.get("stage", Stage.START))


func set_stage(s: int) -> void:
	if s > stage():
		flags["stage"] = s
		if s >= Stage.COMPLETE:
			flags["computer_unlocked"] = true
		stage_changed.emit(s)


func uid() -> int:
	next_uid += 1
	return next_uid


# -----------------------------------------------------------------------------
# New game / winters
# -----------------------------------------------------------------------------

func new_game(m: String, seed_override := -1) -> void:
	mode = m
	year = 1
	money = Catalog.balance.starting_money
	reputation = 50.0
	stats = {}
	lifetime = {}
	flags = {"stage": Stage.START}
	slots = ["", "", "", ""]
	selected = 0
	carried = ""
	heat_pouches = 0
	upgrades = {}
	vehicles = []
	items = []
	machines = []
	rack = []
	next_uid = 1
	camera_third = Settings.get_value("camera", "default_third", false)
	weather_seed = int(Time.get_unix_time_from_system()) % 100000 + 17 if seed_override < 0 else seed_override
	Notify.clear()
	# Forget everything from a previous game played in this session.
	# Survival Mode: the cold is on from the very first minute (polish §10); Fun Mode has no cold.
	Survival.active = m == "survival"
	Economy.reset_for_new_game()
	Contracts.reset_for_new_game()
	start_winter(1)
	# The opening: a buried small shovel beside the truck, keys lost in the front lawn.
	var lot := Layout.player_lot
	var ts := truck_start()
	vehicles.append({"uid": uid(), "id": "pickup", "pos": ts["pos"], "yaw": ts["yaw"], "snow": 0.55})
	var sh := shovel_spot()
	items.append({"uid": uid(), "tool": "small_shovel", "pos": Vector3(sh.x, 0.0, sh.y), "yaw": 0.6, "buried": true})
	# The snow over the shovel forms a slightly bigger, odd-looking oblong pile (polish §4).
	Snow.add_mound(sh + Vector2(0.05, -0.15).rotated(-0.6), Vector2(0.55, 0.95), 0.32, 0.6)
	var kp := Layout.lot_to_world(lot, Layout.gu(lot, -8.6), 4.8)
	flags["keys_pos"] = [kp.x, kp.y]
	flags["truck_keys"] = false
	flags["computer_unlocked"] = false
	dirty_since_save = true


## Where the pickup stands on the first morning: in the driveway, its tailgate to the garage
## (pos, yaw). Polish 5 §4: the framed photo places the shovel from this and shovel_spot().
func truck_start() -> Dictionary:
	var lot := Layout.player_lot
	var sb: float = lot["setback"]
	var truck := Layout.lot_to_world(lot, Layout.gu(lot, 6.0), sb - 4.4)
	var face := Layout.lot_to_world(lot, Layout.gu(lot, 6.0), sb) - truck
	return {"pos": Vector3(truck.x, 0, truck.y), "yaw": atan2(face.x, face.y)}


## Where the small shovel lies buried: beside the truck, on its far side from the house.
func shovel_spot() -> Vector2:
	var lot := Layout.player_lot
	var sb: float = lot["setback"]
	return Layout.lot_to_world(lot, Layout.gu(lot, 8.35), sb - 4.6)


## The home computer stays locked until Gerry's tutorial is complete (polish §11).
func computer_unlocked() -> bool:
	return bool(flags.get("computer_unlocked", false)) or stage() >= Stage.COMPLETE


func start_winter(y: int) -> void:
	year = y
	stats = {"money_earned": 0, "contracts_completed": 0, "visits_completed": 0, "snow_moved": 0.0,
		"snowfall_cm": 0.0, "equipment": [], "bills_paid": 0, "missed_deadlines": 0, "contracts_lost": 0}
	Snow.reset_for_winter(y)
	Weather.generate(y, weather_seed + y * 13)
	Clock.reset(Clock.at(0, 7.5))
	Boxes.start_winter()
	Economy.start_winter()
	Contracts.start_winter()
	Municipal.start_winter()
	Survival.start_winter()
	player_pos = bedroom_spawn()
	player_yaw = 0.0
	flags["player_inside"] = true


## Called when April 1 is reached and the player confirms the next winter.
func next_winter() -> void:
	# Keep money, equipment, vehicles, upgrades, reputation and contracts that were renewed.
	start_winter(year + 1)
	# Equipment stays where it was; vehicles get the new winter's snow load.
	for v in vehicles:
		v["snow"] = 0.2
	Notify.push("Winter %d begins. Good luck out there!" % year, Notify.GOOD)
	dirty_since_save = true


func bedroom_spawn() -> Vector3:
	var lot := Layout.player_lot
	var L := HouseBuilder.lot_transform(lot)
	var sb: float = lot["setback"]
	return L * Vector3(-3.8, Layout.PORCH_H + 0.05, sb + 7.4)   # beside the bed, facing the bedroom door


# -----------------------------------------------------------------------------
# Money / stats
# -----------------------------------------------------------------------------

func add_money(amount: int, _reason := "") -> void:
	money += amount
	if amount > 0:
		stats_add("money_earned", amount)
	money_changed.emit(money)
	dirty_since_save = true


func spend(amount: int) -> bool:
	if amount > money:
		return false
	money -= amount
	money_changed.emit(money)
	dirty_since_save = true
	return true


func stats_add(key: String, v) -> void:
	stats[key] = stats.get(key, 0) + v
	lifetime[key] = lifetime.get(key, 0) + v


func add_equipment_stat(stat: String) -> void:
	var eq: Array = stats.get("equipment", [])
	eq.append(stat)
	stats["equipment"] = eq


func adjust_reputation(delta: float) -> void:
	reputation = clampf(reputation + delta, 0.0, 100.0)


# -----------------------------------------------------------------------------
# Upgrades
# -----------------------------------------------------------------------------

func has_upgrade(id: StringName) -> bool:
	return upgrades.has(String(id))


func grant_upgrade(id: StringName) -> void:
	upgrades[String(id)] = true
	upgrades_changed.emit()
	dirty_since_save = true


## Combined value of a stat from owned upgrades: multipliers multiply; forecast_days takes the max.
func stat_value(stat: StringName, default := 1.0) -> float:
	var v := default
	var is_max := stat == &"forecast_days"
	for id in upgrades.keys():
		var u: UpgradeData = Catalog.upgrade(StringName(id))
		if u == null or u.stat != stat:
			continue
		if is_max:
			v = maxf(v, u.value)
		else:
			v *= u.value
	return v


# -----------------------------------------------------------------------------
# Inventory (4 tool slots + utility items)
# -----------------------------------------------------------------------------

func current_tool_id() -> String:
	if carried != "":
		return ""
	return slots[selected]


func current_tool() -> ToolData:
	var id := current_tool_id()
	return Catalog.tool(StringName(id)) if id != "" else Catalog.tool(&"hands")


func free_slot() -> int:
	if slots[selected] == "":
		return selected
	for i in range(4):
		if slots[i] == "":
			return i
	return -1


## Put a tool in an empty slot, or carry it if all slots are full. Returns false if impossible.
func add_tool(tool_id: String) -> bool:
	var s := free_slot()
	if s >= 0:
		slots[s] = tool_id
		selected = s
		inventory_changed.emit()
		return true
	if carried == "":
		carried = tool_id
		inventory_changed.emit()
		return true
	return false


func take_selected() -> String:
	if carried != "":
		var c := carried
		carried = ""
		inventory_changed.emit()
		return c
	var id: String = slots[selected]
	slots[selected] = ""
	inventory_changed.emit()
	return id


func select_slot(i: int) -> void:
	selected = clampi(i, 0, 3)
	inventory_changed.emit()


func cycle_slot(dir: int) -> void:
	selected = (selected + dir + 4) % 4
	inventory_changed.emit()


func owns_tool(tool_id: String) -> bool:
	if tool_id in slots or carried == tool_id or tool_id in rack:
		return true
	for it in items:
		if it["tool"] == tool_id:
			return true
	for m in machines:
		if m["tool"] == tool_id:
			return true
	return false


# -----------------------------------------------------------------------------
# Persistence
# -----------------------------------------------------------------------------

static func v3(a) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO


static func a3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _pack_list(list: Array) -> Array:
	var out := []
	for e in list:
		var d: Dictionary = e.duplicate()
		if d.has("pos"):
			d["pos"] = a3(d["pos"])
		out.append(d)
	return out


func _unpack_list(list: Array) -> Array:
	var out := []
	for e in list:
		var d: Dictionary = e.duplicate()
		if d.has("pos"):
			d["pos"] = v3(d["pos"])
		if d.has("uid"):
			d["uid"] = int(d["uid"])
		out.append(d)
	return out


func serialize() -> Dictionary:
	return {"mode": mode, "year": year, "money": money, "reputation": reputation, "stats": stats,
		"lifetime": lifetime, "flags": flags, "slots": slots, "selected": selected, "carried": carried,
		"heat_pouches": heat_pouches, "upgrades": upgrades, "vehicles": _pack_list(vehicles),
		"items": _pack_list(items), "machines": _pack_list(machines), "rack": rack,
		"player_pos": a3(player_pos), "player_yaw": player_yaw, "camera_third": camera_third,
		"next_uid": next_uid, "weather_seed": weather_seed}


func deserialize(d: Dictionary) -> void:
	mode = str(d.get("mode", "fun"))
	year = int(d.get("year", 1))
	money = int(d.get("money", 20))
	reputation = float(d.get("reputation", 50.0))
	stats = d.get("stats", {})
	lifetime = d.get("lifetime", {})
	flags = d.get("flags", {"stage": Stage.START})
	flags["stage"] = int(flags.get("stage", 0))
	var sl: Array = d.get("slots", ["", "", "", ""])
	slots = ["", "", "", ""]
	for i in range(mini(4, sl.size())):
		slots[i] = str(sl[i])
	selected = int(d.get("selected", 0))
	carried = str(d.get("carried", ""))
	heat_pouches = int(d.get("heat_pouches", 0))
	upgrades = d.get("upgrades", {})
	vehicles = _unpack_list(d.get("vehicles", []))
	items = _unpack_list(d.get("items", []))
	machines = _unpack_list(d.get("machines", []))
	rack = d.get("rack", [])
	player_pos = v3(d.get("player_pos", [0, 0, 0]))
	player_yaw = float(d.get("player_yaw", 0.0))
	camera_third = bool(d.get("camera_third", false))
	next_uid = int(d.get("next_uid", 100))
	weather_seed = int(d.get("weather_seed", 1))
