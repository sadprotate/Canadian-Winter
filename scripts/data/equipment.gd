class_name Equipment
extends RefCounted
## Polish 5 §13: equipment that isn't a tool — the insulated coat, snowshoes and the heated pad.
## Sold in the Equipment store (Catalog.EQUIPMENT; prices and effects in balance "Equipment"),
## ordered and picked up at the store like any order (a crate on the pickup pad, collected with
## Interact), never in a tool slot. One of each. What the player has picked up lives in
## Game.equipment (saved, version 3 — an optional key, {} by default):
##   insulated_coat: {}            worn from the moment it's picked up (Survival only, Decision 9)
##   snowshoes: {"on": bool}       on by default once picked up; hold Tab and press Interact to toggle
##   heated_pad: {}                in your arms (Game.carried == "heated_pad"), or
##               {"pos": [x, y, z], "yaw": f}   put down on your own property (a world object)
## Owning one follows the pattern of ItemUpgrades.owns: picked up, a crate waiting at the store, or
## on order. The coat replaces the old jacket and parka upgrades (migrate()).

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _Buildings := preload("res://scripts/world/buildings.gd")

const IDS: Array[StringName] = [&"insulated_coat", &"snowshoes", &"heated_pad"]
const COAT := &"insulated_coat"
const SHOES := &"snowshoes"
const PAD := &"heated_pad"
## The pad on the ground (m): across × along the way you face when you put it down. It lies square
## to the snow grid (its yaw snapped to a quarter turn), so it heats exactly 5 × 10 cells.
const PAD_SIZE := Vector2(1.25, 2.5)
## How far in front of your feet its centre goes when you put it down.
const PAD_AHEAD := 1.9

## The one notification after an old save's jacket or parka became the coat (game_root shows it).
static var pending_note := ""
## Polish 5 §16 hook: more ground that is yours (world rects), e.g. the commercial property once it
## is bought. The pad may be put down on the player's lot and on these.
static var extra_property: Array = []


static func is_equipment(id) -> bool:
	return Catalog.EQUIPMENT.has(StringName(str(id)))


static func price(id) -> int:
	var e: Dictionary = Catalog.EQUIPMENT.get(StringName(str(id)), {})
	return int(Catalog.balance.get(str(e.get("price_key", "")))) if not e.is_empty() else 0


## Sold in this mode? The coat only in Survival (Fun Mode has no cold: no coat at all).
static func shown(id) -> bool:
	return StringName(str(id)) != COAT or Game.is_survival()


## Picked up (worn, on your feet or in the bag, carried, or put down).
static func has(id) -> bool:
	return Game.equipment.has(String(id))


## Yours: picked up, a crate waiting on the store's pad, or on order (one of each).
static func owns(id) -> bool:
	var s := String(id)
	if has(s) or Game.carried == s or Economy.has_open_order(s):
		return true
	for it in Game.items:
		if str(it.get("tool", "")) == "crate:" + s:
			return true
	if StringName(s) == COAT:
		# An old jacket or parka still on order or waiting: it becomes the coat when collected.
		for r in Catalog.RETIRED_UPGRADE_IDS:
			if Economy.has_open_order(String(r)):
				return true
	return false


## Why it can't be bought now ("" if it can — money aside: Economy.can_buy).
static func why_not(id) -> String:
	if not shown(id):
		return "Survival Mode only."
	if owns(id):
		return "Already owned."
	return ""


## The store's line under a card: what it does, in numbers.
static func store_stats(id) -> String:
	var b: BalanceData = Catalog.balance
	match StringName(str(id)):
		COAT:
			return "Warmth lost outdoors −%d %%" % roundi(b.coat_cold_protection * 100.0)
		SHOES:
			return "You sink in %d %% of the way (a track that deep)" % roundi(b.snowshoes_sink * 100.0)
		PAD:
			return "%.2f × %.2f m  ·  melts %d cm an hour  ·  power: up to $%.2f an hour while melting" % [PAD_SIZE.x, PAD_SIZE.y, roundi(b.pad_melt_cm_h), b.pad_melt_cm_h / 100.0 * PAD_SIZE.x * PAD_SIZE.y * b.melt_cost_per_m3]
	return ""


## Picked up at the store (its crate): the coat is worn, the snowshoes are on, the pad is in your
## arms. False — and nothing changes — when the pad can't be carried (your arms are full).
static func collect(id) -> bool:
	var s := String(id)
	match StringName(s):
		COAT:
			Game.equipment[s] = {}
		SHOES:
			Game.equipment[s] = {"on": true}
		PAD:
			if Game.carried != "":
				return false
			Game.equipment[s] = {}
			Game.carried = s
		_:
			return false
	Game.inventory_changed.emit()
	Game.dirty_since_save = true
	return true


## Text for the collection notification.
static func collected_text(id) -> String:
	match StringName(str(id)):
		COAT:
			return "You put on the insulated coat." if Game.is_survival() else "Collected the insulated coat."
		SHOES:
			return Settings.with_keys("Snowshoes on. Hold {inventory} and press {interact} to take them off.")
		PAD:
			return Settings.with_keys("You're carrying the heated pad. Put it down on your own lot with {drop}.")
	return "Collected %s." % Catalog.item_name(StringName(str(id)))


# -----------------------------------------------------------------------------
# The coat (Survival only)
# -----------------------------------------------------------------------------

static func coat_worn() -> bool:
	return Game.is_survival() and has(COAT)


## Its factor on the warmth lost outdoors and in a cold house: 1 − coat_cold_protection, or 1.
## §14's cold nights read the same factor.
static func cold_mult() -> float:
	return 1.0 - Catalog.balance.coat_cold_protection if coat_worn() else 1.0


## Old saves: the Insulated Work Jacket and the Arctic Parka (retired upgrades) become the coat —
## one coat (no two overlapping coats), its protection the two together (×0.6), so nothing paid for
## is lost. One notification (Survival, where the coat is worn). True if anything moved.
static func migrate(ups: Dictionary, equip: Dictionary, survival: bool) -> bool:
	var found := false
	for r in Catalog.RETIRED_UPGRADE_IDS:
		if ups.has(String(r)):
			ups.erase(String(r))
			found = true
	if not found:
		return false
	if not equip.has(String(COAT)):
		equip[String(COAT)] = {}
	if survival:
		pending_note = "Your jacket and parka are now one insulated coat: the same warmth, worn as before."
	return true


# -----------------------------------------------------------------------------
# Snowshoes
# -----------------------------------------------------------------------------

static func snowshoes_on() -> bool:
	return has(SHOES) and bool((Game.equipment[String(SHOES)] as Dictionary).get("on", true))


## Take them off or put them on (the Tab overview). False if you have none.
static func toggle_snowshoes() -> bool:
	if not has(SHOES):
		return false
	var e: Dictionary = Game.equipment[String(SHOES)]
	e["on"] = not bool(e.get("on", true))
	Game.inventory_changed.emit()
	Game.dirty_since_save = true
	return true


# -----------------------------------------------------------------------------
# The heated pad
# -----------------------------------------------------------------------------

static func pad_carried() -> bool:
	return Game.carried == String(PAD)


static func pad_placed() -> bool:
	return has(PAD) and (Game.equipment[String(PAD)] as Dictionary).has("pos")


static func pad_pos() -> Vector3:
	return Game.v3((Game.equipment.get(String(PAD), {}) as Dictionary).get("pos", [0, 0, 0]))


static func pad_yaw() -> float:
	return float((Game.equipment.get(String(PAD), {}) as Dictionary).get("yaw", 0.0))


## The pad's footprint (world XZ rect, on the snow grid) for a centre and a yaw (a quarter turn
## decides whether its long side runs along x or z).
static func pad_rect_at(center: Vector2, yaw: float) -> Rect2:
	var along_z := absf(cos(yaw)) >= absf(sin(yaw))
	var sz := Vector2(PAD_SIZE.x, PAD_SIZE.y) if along_z else Vector2(PAD_SIZE.y, PAD_SIZE.x)
	var corner := ((center - sz * 0.5) / Snow.CELL).round() * Snow.CELL
	return Rect2(corner, sz)


## The footprint of the pad lying where it is (an empty rect when it isn't down).
static func pad_rect() -> Rect2:
	if not pad_placed():
		return Rect2()
	var p := pad_pos()
	return pad_rect_at(Vector2(p.x, p.z), pad_yaw())


## The ground that is yours: your lot (from the front edge of the lot, so not the sidewalk, the
## boulevard or the street) and (§16) the commercial property once it's bought (extra_property).
static func property_rects() -> Array:
	var out := [Layout.player_lot["rect"]]
	out.append_array(extra_property)
	return out


## Can the pad go down on this footprint? "" if it can, otherwise why not.
static func pad_spot_problem(r: Rect2) -> String:
	var inside := false
	for pr in property_rects():
		if (pr as Rect2).grow(0.001).encloses(r):
			inside = true
			break
	var pts := [r.get_center(), r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]
	for p in pts:
		var q: Vector2 = (p as Vector2).lerp(r.get_center(), 0.02)
		if Snow.is_road(q.x, q.y) or Layout.is_road_point(q):
			return "Not on the street: put the pad down on your own lot."
	if not inside:
		return "Put the pad down on your own lot."
	var c := Snow._rect_cells(r)
	for z in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			var s := Snow.surf[z * Snow.W + x]
			if s == Snow.S_BLOCKED or s == Snow.S_STAIRS:
				return "There's no room for the pad there."
	for p in pts:
		if not _Buildings.at(p as Vector2).is_empty():
			return "There's no room for the pad there."
	return ""


## Where the pad would go if you put it down now: {rect, yaw, centre}.
static func pad_spot(pl: Node3D, fwd: Vector2, yaw: float) -> Dictionary:
	var feet := Vector2(pl.global_position.x, pl.global_position.z)
	var y := snappedf(yaw, PI * 0.5)
	var c := feet + fwd.normalized() * PAD_AHEAD
	var r := pad_rect_at(c, y)
	return {"rect": r, "yaw": y, "center": r.get_center()}


## Put the pad down in front of the player (Drop). "" when it's down, otherwise why not (it stays
## in your arms).
static func put_down_pad(pl: Node3D, fwd: Vector2, yaw: float) -> String:
	if not pad_carried():
		return "You aren't carrying the pad."
	if _Buildings.indoors(pl.global_position):
		return "Put the pad down outside, on your own lot."
	var sp := pad_spot(pl, fwd, yaw)
	var why := pad_spot_problem(sp["rect"])
	if why != "":
		return why
	var c: Vector2 = sp["center"]
	Game.carried = ""
	Game.equipment[String(PAD)] = {"pos": Game.a3(Vector3(c.x, Snow.ground_at(c.x, c.y), c.y)), "yaw": float(sp["yaw"])}
	Game.inventory_changed.emit()
	Game.dirty_since_save = true
	return ""


## Pick the pad up (Interact on it): into your arms if they're free. "" when done, otherwise why not.
static func pick_up_pad() -> String:
	if not pad_placed():
		return "The pad isn't down."
	if Game.carried != "":
		return Settings.with_keys("Your arms are full. Put down what you're carrying first ({drop}).")
	Game.equipment[String(PAD)] = {}
	Game.carried = String(PAD)
	Game.inventory_changed.emit()
	Game.dirty_since_save = true
	return ""


## The equipment lines of the Tab overview (with its keys) and the Property app (keys = false):
## only what you have.
static func overview_lines(keys := true) -> Array:
	var out := []
	if has(COAT) and Game.is_survival():
		out.append("Coat: insulated coat (worn)")
	if has(SHOES):
		var k := "  (%s to %s)" % [Settings.action_label("interact"), "take them off" if snowshoes_on() else "put them on"]
		out.append("Snowshoes: %s%s" % ["on" if snowshoes_on() else "off", k if keys else ""])
	if pad_placed():
		var p := pad_pos()
		out.append("Heated pad: down at %s" % Layout.describe_point(Vector2(p.x, p.z)))
	elif pad_carried() and not keys:
		out.append("Heated pad: in your arms")   # (the overview's "Carrying:" line says so already)
	return out


## Serialize helper: Game.equipment as saved (copies; vectors as arrays already).
static func pack(equip: Dictionary) -> Dictionary:
	var out := {}
	for k in equip.keys():
		if is_equipment(k):
			out[str(k)] = (equip[k] as Dictionary).duplicate(true) if equip[k] is Dictionary else {}
	return out
