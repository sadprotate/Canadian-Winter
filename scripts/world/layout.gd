class_name Layout
extends RefCounted
## Static description of the neighborhood: roads, lots, houses, zones, landmarks.
## World units are meters; X east, Z south; all rects are axis-aligned Rect2(x, z, w, d).

const MAP_W := 192.0
const MAP_D := 224.0

# Surface codes (shared with Snow sim).
const S_LAWN := 0
const S_ROAD := 1
const S_DRIVEWAY := 2
const S_SIDEWALK := 3
const S_PORCH := 4
const S_BLOCKED := 5
const S_LOT := 6
const S_DUMP := 7
const S_BOULEVARD := 8
const S_WALKWAY := 9
const S_STAIRS := 10

const PORCH_H := 0.54
const STEP_H := 0.18

const STREET_MAPLE := "Maple Street"
const STREET_BIRCH := "Birch Avenue"
const STREET_CEDAR := "Cedar Lane"

## Polish 5 §5 — addresses. The layout is the one source: every house's number and street are its
## lot's ("24 Maple Street"), unchanged since the first build. The scheme: odd numbers on one side
## of the street and even on the other, rising along it by 4 per 28 m lot (Maple Street and Birch
## Avenue: odd on the north side, 11–31, even on the south side, 12–32, rising west to east). The
## school, the store and the church had none; they take the street their lots open onto, Cedar Lane,
## in the same scheme (rising north to south, so odd on the east side, as on the other streets where
## odd numbers are on the left going up; 4 per 28 m of frontage from the lane's north end): the store
## 11 and the school 12 at the north end, the church 40 at the south end. `place` is the one name
## the UI shows for a place (place_name()): a lot's address, "<building>, <address>" for a building
## and its parking lot, a street section's name.

static var _built := false
static var roads: Array = []        # [{name, rect, horizontal}]
static var sidewalks: Array = []    # Rect2
static var boulevards: Array = []   # Rect2
static var lots: Array = []         # Dictionary per property (see _make_lot)
static var big_areas: Array = []    # {id, name, rect, apron}
static var buildings: Array = []    # {id, name, rect, height, kind}
static var road_segments: Array = []  # municipal sections {id, name, rect, lanes:[{a,b,side}]}
static var dump_rect := Rect2()
static var store_pad := Rect2()
static var store_bays: Array = []   # Rect2 per vehicle bay
static var player_lot := {}
static var neighbor_lot := {}


static func ensure() -> void:
	if _built:
		return
	_built = true
	_build()


static func _build() -> void:
	# --- Roads (8 m wide) ---
	roads = [
		{"name": STREET_MAPLE, "rect": Rect2(0, 79, MAP_W, 8), "horizontal": true},
		{"name": STREET_BIRCH, "rect": Rect2(0, 149, MAP_W, 8), "horizontal": true},
		{"name": STREET_CEDAR, "rect": Rect2(92, 2, 8, 220), "horizontal": false},
	]
	sidewalks.clear()
	boulevards.clear()
	for r in roads:
		var rc: Rect2 = r["rect"]
		if r["horizontal"]:
			boulevards.append(Rect2(rc.position.x, rc.position.y - 1.5, rc.size.x, 1.5))
			sidewalks.append(Rect2(rc.position.x, rc.position.y - 3.0, rc.size.x, 1.5))
			boulevards.append(Rect2(rc.position.x, rc.end.y, rc.size.x, 1.5))
			sidewalks.append(Rect2(rc.position.x, rc.end.y + 1.5, rc.size.x, 1.5))
		else:
			boulevards.append(Rect2(rc.position.x - 1.5, rc.position.y, 1.5, rc.size.y))
			sidewalks.append(Rect2(rc.position.x - 3.0, rc.position.y, 1.5, rc.size.y))
			boulevards.append(Rect2(rc.end.x, rc.position.y, 1.5, rc.size.y))
			sidewalks.append(Rect2(rc.end.x + 1.5, rc.position.y, 1.5, rc.size.y))

	# --- Large areas ---
	big_areas = [
		{"id": "school_lot", "name": "Maple Ridge School parking lot", "rect": Rect2(10, 20, 79, 22), "apron": Rect2(89, 27, 3, 8)},
		{"id": "store_lot", "name": "Northern Supply Co. parking lot", "rect": Rect2(103, 20, 73, 22), "apron": Rect2(100, 27, 3, 8)},
		{"id": "church_lot", "name": "St. Andrew's Church parking lot", "rect": Rect2(52, 192, 37, 27), "apron": Rect2(89, 200, 3, 8)},
		{"id": "dump_lot", "name": "Municipal Snow Dump", "rect": Rect2(103, 192, 77, 29), "apron": Rect2(100, 202, 3, 8)},
	]
	dump_rect = Rect2(122, 196, 54, 22)
	store_pad = Rect2(114, 21, 14, 4)
	store_bays = [Rect2(132, 26, 10, 14), Rect2(143, 26, 10, 14), Rect2(154, 26, 10, 14), Rect2(165, 26, 10, 14)]
	# Polish 5 §5: every building has an address in the houses' scheme (see the note at the top).
	# number_at: where its number is [x, y, z] and the way it faces [fx, fz] — by the main entrance
	# (the front, where its name is), on the wall the street sees: the school's east end wall by
	# its front corner and flagpole, the store's front beside its name board, the church's east
	# wall (to its lot and the lane) at the tower end. AddressSigns builds them.
	buildings = [
		{"id": "school", "name": "Maple Ridge School", "rect": Rect2(16, 5, 44, 13), "height": 7.0, "kind": "school", "number": 12, "street": STREET_CEDAR,
			"number_at": [60.05, 5.0, 15.0, 1.0, 0.0]},
		{"id": "store", "name": "Northern Supply Co.", "rect": Rect2(112, 6, 30, 12), "height": 6.5, "kind": "store", "number": 11, "street": STREET_CEDAR,
			"number_at": [115.6, 5.4, 18.05, 0.0, 1.0]},
		{"id": "church", "name": "St. Andrew's Church", "rect": Rect2(20, 199, 24, 16), "height": 8.0, "kind": "church", "number": 40, "street": STREET_CEDAR,
			"number_at": [44.05, 6.2, 212.5, 1.0, 0.0]},
	]
	for b in buildings:
		b["address"] = "%d %s" % [b["number"], b["street"]]
		b["place"] = "%s, %s" % [b["name"], b["address"]]
	# Each parking lot belongs to its building and is named by its address.
	var lot_of := {"school_lot": "school", "store_lot": "store", "church_lot": "church"}
	for a in big_areas:
		var ob := building_by_id(str(lot_of.get(a["id"], "")))
		a["building"] = ob.get("id", "")
		a["address"] = ob.get("address", "")
		a["place"] = ob.get("place", a["name"])

	# --- Residential lots ---
	lots.clear()
	var west_x := [4.0, 32.0, 60.0]
	var east_x := [104.0, 132.0, 160.0]
	var row_defs := [
		{"row": "A", "z0": 48.0, "front_z": 76.0, "dir": -1, "street": STREET_MAPLE, "nums": [11, 15, 19, 23, 27, 31]},
		{"row": "B", "z0": 90.0, "front_z": 90.0, "dir": 1, "street": STREET_MAPLE, "nums": [12, 16, 20, 24, 28, 32]},
		{"row": "C", "z0": 118.0, "front_z": 146.0, "dir": -1, "street": STREET_BIRCH, "nums": [11, 15, 19, 23, 27, 31]},
		{"row": "D", "z0": 160.0, "front_z": 160.0, "dir": 1, "street": STREET_BIRCH, "nums": [12, 16, 20, 24, 28, 32]},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 271828
	var idx := 0
	for rd in row_defs:
		var xs: Array = west_x + east_x
		for li in range(6):
			var lot := _make_lot(idx, rd, xs[li], rd["nums"][li], li, rng)
			lots.append(lot)
			idx += 1
	player_lot = lot_by_address(16, STREET_MAPLE)
	neighbor_lot = lot_by_address(15, STREET_MAPLE)
	player_lot["is_player"] = true
	player_lot["setback"] = 11.0
	neighbor_lot["is_neighbor"] = true

	# --- Municipal road sections ---
	road_segments = [
		{"id": "maple_w", "name": "Maple Street (west)", "rect": Rect2(0, 79, 92, 8)},
		{"id": "maple_e", "name": "Maple Street (east)", "rect": Rect2(100, 79, 92, 8)},
		{"id": "birch_w", "name": "Birch Avenue (west)", "rect": Rect2(0, 149, 92, 8)},
		{"id": "birch_e", "name": "Birch Avenue (east)", "rect": Rect2(100, 149, 92, 8)},
		{"id": "cedar_n", "name": "Cedar Lane (north)", "rect": Rect2(92, 2, 8, 77)},
		{"id": "cedar_m", "name": "Cedar Lane (middle)", "rect": Rect2(92, 79, 8, 78)},
		{"id": "cedar_s", "name": "Cedar Lane (south)", "rect": Rect2(92, 157, 8, 65)},
	]
	for seg in road_segments:
		var rc: Rect2 = seg["rect"]
		var lanes := []
		if rc.size.x > rc.size.y:
			var zc := rc.get_center().y
			# Eastbound lane on the south half pushes south (+z), westbound pushes north.
			lanes.append({"a": Vector2(rc.position.x, zc + 1.95), "b": Vector2(rc.end.x, zc + 1.95), "push": Vector2(0, 1)})
			lanes.append({"a": Vector2(rc.end.x, zc - 1.95), "b": Vector2(rc.position.x, zc - 1.95), "push": Vector2(0, -1)})
		else:
			var xc := rc.get_center().x
			lanes.append({"a": Vector2(xc - 1.95, rc.position.y), "b": Vector2(xc - 1.95, rc.end.y), "push": Vector2(-1, 0)})
			lanes.append({"a": Vector2(xc + 1.95, rc.end.y), "b": Vector2(xc + 1.95, rc.position.y), "push": Vector2(1, 0)})
		seg["lanes"] = lanes


static func _make_lot(idx: int, rd: Dictionary, x0: float, number: int, li: int, rng: RandomNumberGenerator) -> Dictionary:
	var dir: int = rd["dir"]  # +1: lot extends toward +z from its front edge (faces north)
	var front_z: float = rd["front_z"]
	var lot_rect: Rect2
	if dir > 0:
		lot_rect = Rect2(x0, front_z, 28, 28)
	else:
		lot_rect = Rect2(x0, front_z - 28, 28, 28)
	var vacant: bool = (rd["row"] == "C" and li == 0) or (rd["row"] == "D" and li == 5)
	var lot := {
		"index": idx, "row": rd["row"], "number": number, "street": rd["street"],
		"address": "%d %s" % [number, rd["street"]], "rect": lot_rect, "dir": dir,
		"front_z": front_z, "center_x": x0 + 14.0, "vacant": vacant,
		"is_player": false, "is_neighbor": false,
	}
	# Right-hand side as seen from the street looking into the lot.
	lot["right"] = Vector2(-1, 0) if dir > 0 else Vector2(1, 0)
	lot["inward"] = Vector2(0, dir)
	lot["setback"] = rng.randf_range(9.5, 13.0)
	lot["garage_right"] = rng.randf() < 0.6
	lot["style"] = 1 if rng.randf() < 0.3 else 0  # 0 bungalow, 1 two-storey
	var palette := [Color(0.56, 0.57, 0.58), Color(0.62, 0.58, 0.52), Color(0.48, 0.53, 0.58),
		Color(0.55, 0.58, 0.52), Color(0.6, 0.55, 0.55), Color(0.66, 0.64, 0.6), Color(0.45, 0.47, 0.5)]
	lot["siding"] = palette[rng.randi() % palette.size()]
	var doors := [Color(0.5, 0.12, 0.1), Color(0.45, 0.1, 0.1), Color(0.18, 0.28, 0.42), Color(0.2, 0.32, 0.22), Color(0.55, 0.15, 0.1)]
	lot["door_color"] = doors[rng.randi() % doors.size()]
	lot["roof_color"] = Color(0.22, 0.22, 0.25) if rng.randf() < 0.7 else Color(0.32, 0.24, 0.2)
	lot["trees"] = rng.randi_range(1, 3)
	lot["tree_seed"] = rng.randi()
	if vacant:
		lot["name"] = "Vacant lot"
	return lot


## Convert lot-local (u along street to the right, v inward from the lot front edge) to world XZ.
static func lot_to_world(lot: Dictionary, u: float, v: float) -> Vector2:
	var right: Vector2 = lot["right"]
	var inward: Vector2 = lot["inward"]
	var origin := Vector2(lot["center_x"], lot["front_z"])
	return origin + right * u + inward * v


## Axis-aligned world rect from a lot-local rect (u0..u1, v0..v1).
static func lot_rect_world(lot: Dictionary, u0: float, u1: float, v0: float, v1: float) -> Rect2:
	var a := lot_to_world(lot, u0, v0)
	var b := lot_to_world(lot, u1, v1)
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(mn, mx - mn)


## Mirror u if the garage is on the left.
static func gu(lot: Dictionary, u: float) -> float:
	return u if lot["garage_right"] else -u


## Mailbox placement (lot frame), polish 4 §4: at the corner where the walk meets the sidewalk,
## on the yard side of the sidewalk and the side of the walk away from the driveway — 0.65 m
## beyond the walkway's edge (walkway u -2.1..-0.9) and 0.55 m in from the sidewalk (v -1.5..0),
## clear of both boxes, the junction itself, the driveway and its apron, and the boulevard.
const MAILBOX_U := -2.75
const MAILBOX_V := 0.55


## Key house geometry for a lot, in world space.
static func house_info(lot: Dictionary) -> Dictionary:
	var sb: float = lot["setback"]
	var deep := 9.0
	var info := {}
	info["body"] = lot_rect_world(lot, gu(lot, -9.25), gu(lot, 2.75), sb, sb + deep)
	info["garage"] = lot_rect_world(lot, gu(lot, 2.75), gu(lot, 9.25), sb - 0.5, sb + 7.0)
	info["porch"] = lot_rect_world(lot, gu(lot, -2.9), gu(lot, -0.1), sb - 1.8, sb)
	info["stairs"] = lot_rect_world(lot, gu(lot, -2.3), gu(lot, -0.7), sb - 2.4, sb - 1.8)
	info["stair_upper"] = lot_rect_world(lot, gu(lot, -2.3), gu(lot, -0.7), sb - 2.1, sb - 1.8)
	info["walkway"] = lot_rect_world(lot, gu(lot, -2.1), gu(lot, -0.9), 0.0, sb - 2.4)
	info["driveway"] = lot_rect_world(lot, gu(lot, 3.25), gu(lot, 8.75), -3.0, sb - 0.5)
	info["driveway_private"] = lot_rect_world(lot, gu(lot, 3.25), gu(lot, 8.75), 0.0, sb - 0.5)
	info["sidewalk"] = lot_rect_world(lot, -14.0, 14.0, -1.5, 0.0)
	# Polish 4 §4: the mailbox stands at the foot of the walk, where it meets the sidewalk, on the
	# side away from the driveway, its door facing the street (pass 3 had it partway up the walk,
	# facing the walk). It sits outside every clearing box, off the junction, the driveway apron and
	# the boulevard where the grader windrow lands; the letter is collected from the sidewalk or the
	# foot of the walk. mailbox_path_point is the spot on the walk beside it.
	var mb := lot_to_world(lot, gu(lot, MAILBOX_U), MAILBOX_V)
	info["mailbox"] = mb
	info["mailbox_face"] = -Vector2(lot["inward"]).normalized()
	info["mailbox_path_point"] = lot_to_world(lot, gu(lot, -1.5), MAILBOX_V)
	info["door"] = lot_to_world(lot, gu(lot, -1.5), sb)
	info["door_outside"] = lot_to_world(lot, gu(lot, -1.5), sb - 1.0)
	info["porch_center"] = lot_to_world(lot, gu(lot, -1.5), sb - 0.9)
	info["truck_spot"] = lot_to_world(lot, gu(lot, 6.0), sb - 4.2)
	info["window"] = lot_to_world(lot, gu(lot, -6.2), sb)
	info["facing"] = -Vector2(lot["inward"])  # direction the front of the house faces (toward street)
	info["setback"] = sb
	return info


## Gerry's tutorial trail: his porch steps and the walk down to his mailbox. Polish 4 §4: the
## mailbox stands at the foot of the walk by the sidewalk, so the trail is the whole walk from the
## sidewalk up plus the steps (pass 3: from a mailbox partway up the walk).
static func gerry_trail_rects() -> Array:
	var hi := house_info(neighbor_lot)
	return [hi["walkway"], hi["stairs"]]


static func lot_by_address(number: int, street: String) -> Dictionary:
	for l in lots:
		if l["number"] == number and l["street"] == street:
			return l
	return {}


static func lot_at(p: Vector2) -> Dictionary:
	for l in lots:
		if (l["rect"] as Rect2).has_point(p):
			return l
	return {}


static func is_road_point(p: Vector2) -> bool:
	for r in roads:
		if (r["rect"] as Rect2).has_point(p):
			return true
	return false


static func building_by_id(id: String) -> Dictionary:
	ensure()
	for b in buildings:
		if b["id"] == id:
			return b
	return {}


## Polish 5 §5: the name the UI shows for a contract target / box owner ("lot:9", "area:store_lot",
## "road:maple_w"), read from the layout; "" if the target is unknown.
static func place_name(target: String) -> String:
	ensure()
	if target.begins_with("lot:"):
		var idx := int(target.substr(4))
		return str(lots[idx]["address"]) if idx >= 0 and idx < lots.size() else ""
	if target.begins_with("area:"):
		for a in big_areas:
			if a["id"] == target.substr(5):
				return str(a["place"])
	if target.begins_with("road:"):
		for seg in road_segments:
			if seg["id"] == target.substr(5):
				return str(seg["name"])
	return ""


## Polish 5 §5: text saved by an older build (a history entry, a transaction) with its places named
## as they are now. Before §5 a parking lot was named "<building> parking lot"; it is now named by
## its building and address. Nothing else changes.
static func current_place(text: String) -> String:
	ensure()
	for a in big_areas:
		if a["place"] != a["name"]:
			text = text.replace(str(a["name"]), str(a["place"]))
	return text


## Human-readable location name for a point (used by map / notifications).
static func describe_point(p: Vector2) -> String:
	var l := lot_at(p)
	if not l.is_empty():
		return l["address"]
	for b in buildings:
		if (b["rect"] as Rect2).grow(1.0).has_point(p):
			return b["place"]
	for a in big_areas:
		if (a["rect"] as Rect2).has_point(p) or (a["apron"] as Rect2).has_point(p):
			return a["place"]
	for r in roads:
		if (r["rect"] as Rect2).has_point(p):
			return r["name"]
	return "Neighborhood"


static func store_info() -> Dictionary:
	return {"rect": buildings[1]["rect"], "pad": store_pad, "bays": store_bays}
