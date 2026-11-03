extends Node
## Contracts (Part 15): board listings, bidding against simulated rivals, active contracts with
## zones made of clearing boxes (90% rule), recurring service visits, municipal street contracts
## and the 48-hour snowed-in rule.

signal changed

const RIVALS := [
	{"name": "Frost Brothers Snow Removal", "edge": 0.0},
	{"name": "Polar Plow Co.", "edge": 0.04},
	{"name": "Northern Shovelers", "edge": -0.03},
	{"name": "Great White Property Care", "edge": 0.02},
]
const CLIENT_FIRST := ["Linda", "Marc", "Priya", "Gord", "Nathalie", "Wei", "Sandra", "Tom", "Amélie", "Raj",
	"Doris", "Kevin", "Isabelle", "Ahmed", "Brenda", "Luc", "Fiona", "Dave", "Mei", "Yves", "Carol", "Jacques"]
const CLIENT_LAST := ["Tremblay", "MacDonald", "Singh", "Roy", "Chen", "Gagnon", "Wilson", "Côté", "Patel", "Martin",
	"Bouchard", "Campbell", "Leblanc", "Nguyen", "Morin", "Stewart"]

var listings: Array = []
var bids: Array = []
var active: Array = []
var history: Array = []
var _next_id := 1
var rival_wins := 0


func reset_for_new_game() -> void:
	listings = []
	bids = []
	active = []
	history = []
	_next_id = 1
	rival_wins = 0


func start_winter() -> void:
	# Recurring contracts expire at winter's end unless renewed (renewals handled in the summary).
	var keep := []
	for c in active:
		if c.get("renewed", false):
			c["renewed"] = false
			c["status"] = "serviced"
			c["visits"] = 0
			c["last_service"] = 0.0
			c["snowed_min"] = 0.0
			c["warned"] = 0
			keep.append(c)
	active = keep
	bids = []
	listings = []
	_generate_listings(0, true)
	changed.emit()


func _rng_for(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = Game.weather_seed * 131 + Game.year * 7 + salt
	return r


# -----------------------------------------------------------------------------
# Zones (made of clearing boxes) & the snowed-in rule
# -----------------------------------------------------------------------------
#
# A contract zone is a named group of clearing boxes (see Boxes). A zone is done when all of its
# boxes are complete (90 % rule, then the box snaps to bare ground).
#
# "Snowed in": a contract's property is snowed in while at least one of its boxes is incomplete.
# Snowed-in time accumulates in game hours, except while a storm or blizzard (heavy snow or worse)
# is still falling — nobody expects the driveway cleared mid-storm. When every box is complete the
# clock resets to zero. A contract whose property stays snowed in for more than
# contract_snowed_in_hours (48 h) is lost. Gerry's tutorial trail has no timer.

static func rect_to_a(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


static func a_to_rect(a: Array) -> Rect2:
	return Rect2(a[0], a[1], a[2], a[3])


func _ready() -> void:
	Boxes.box_completed.connect(_on_box_changed)
	Boxes.box_reopened.connect(_on_box_changed)


func zone_area(z: Dictionary) -> float:
	var a := 0.0
	for ra in z["rects"]:
		a += float(ra[2]) * float(ra[3])
	return a


## Quick estimate used when posting listings (large lots would otherwise stall a frame).
func zone_estimate(z: Dictionary) -> float:
	var res: float = Catalog.balance.contract_residual_depth
	var v := 0.0
	for ra in z["rects"]:
		var r := a_to_rect(ra)
		v += Snow.estimate_volume(r, res, 1 if r.get_area() < 60.0 else 4)
	return v


func zone_required(z: Dictionary) -> float:
	var v := 0.0
	for id in z.get("boxes", []):
		var b := Boxes.get_box(id)
		if not b.is_empty() and not b["complete"]:
			v += Boxes.snow_volume(b, true)
	return v


## Update a zone from its boxes. Returns its progress 0..1.
func measure_zone(c: Dictionary, z: Dictionary, exact := true) -> float:
	var ids: Array = z.get("boxes", [])
	if ids.is_empty():
		return 1.0
	var sum := 0.0
	var all_done := true
	for id in ids:
		var b := Boxes.get_box(id)
		if b.is_empty():
			continue
		Boxes.measure(b, exact)
		sum += float(b["progress"])
		if not b["complete"]:
			all_done = false
	z["progress"] = 1.0 if all_done else sum / ids.size()
	z["done"] = all_done
	return z["progress"]


func contract_boxes(c: Dictionary) -> Array:
	var out := []
	for z in c["zones"]:
		for id in z.get("boxes", []):
			out.append(id)
	return out


func is_snowed_in(c: Dictionary) -> bool:
	for id in contract_boxes(c):
		if not Boxes.is_complete(id):
			return true
	return false


func _live(c: Dictionary) -> bool:
	var st: String = c["status"]
	return st == "active" or st == "needs_service" or st == "serviced"


## Hours left before the contract is lost (INF when not snowed in or no timer).
func hours_left(c: Dictionary) -> float:
	if c.get("tutorial", false) or not _live(c) or c["status"] == "serviced":
		return INF
	return Catalog.balance.contract_snowed_in_hours - float(c.get("snowed_min", 0.0)) / 60.0


func _on_box_changed(id: String) -> void:
	for c in active:
		if not _live(c):
			continue
		if not (id in contract_boxes(c)):
			continue
		_refresh(c)


## Re-evaluate a contract's zones and status after its boxes changed.
func _refresh(c: Dictionary) -> void:
	var all_done := true
	for z in c["zones"]:
		measure_zone(c, z, false)
		if not z["done"]:
			all_done = false
	var st: String = c["status"]
	if c["type"] == "one_time":
		if st == "active" and all_done:
			_finish(c)
	else:
		if all_done and st == "needs_service":
			_finish(c)
		elif not all_done and st == "serviced":
			c["status"] = "needs_service"
			c["snowed_min"] = 0.0
			c["warned"] = 0
			Notify.push("%s needs clearing — new snow on the property." % c["address"], Notify.INFO)
			changed.emit()


func _finish(c: Dictionary) -> void:
	var b: BalanceData = Catalog.balance
	var quick := float(c.get("snowed_min", 0.0)) <= 24.0 * 60.0
	match c["type"]:
		"one_time":
			var pay: int = c["pay"]
			c["status"] = "completed"
			_pay(c, pay, "Contract completed")
			Game.stats_add("contracts_completed", 1)
			Game.adjust_reputation(2.0)
			history.append({"id": c["id"], "address": c["address"], "pay": pay, "time": Clock.minutes})
			if c.get("tutorial", false):
				Game.set_stage(Game.Stage.TRAIL_DONE)
		_:
			c["status"] = "serviced"
			c["visits"] = int(c.get("visits", 0)) + 1
			c["last_service"] = Clock.minutes
			_pay(c, int(c["pay"]), "Service visit")
			Game.stats_add("visits_completed", 1)
			Game.adjust_reputation(1.0 if quick else 0.3)
	c["snowed_min"] = 0.0
	c["warned"] = 0
	Notify.push("%s — all clear." % c["address"], Notify.GOOD)
	changed.emit()


func _lose(c: Dictionary) -> void:
	var b: BalanceData = Catalog.balance
	c["status"] = "lost"
	Game.adjust_reputation(-b.contract_lost_reputation)
	Game.stats_add("contracts_lost", 1)
	Game.stats_add("missed_deadlines", 1)
	Notify.push("CONTRACT LOST: %s stayed snowed in for over %d hours — %s hired someone else." % [c["address"], int(b.contract_snowed_in_hours), c["client"]], Notify.BAD)
	changed.emit()
	Game.dirty_since_save = true


func _pay(c: Dictionary, amount: int, what: String) -> void:
	Game.add_money(amount)
	Economy.log_tx("%s: %s" % [what, c["address"]], amount)
	Notify.push("Payment received: $%d from %s." % [amount, c["client"]], Notify.GOOD)


## Active contract zone the player is in or near (for the HUD).
func zone_near(p: Vector2, radius := 6.0) -> Dictionary:
	for c in active:
		if c["status"] != "active" and c["status"] != "needs_service":
			continue
		for z in c["zones"]:
			if z["done"]:
				continue
			for ra in z["rects"]:
				if a_to_rect(ra).grow(radius).has_point(p):
					return {"contract": c, "zone": z}
	return {}


## Contract (if any) that owns a box.
func contract_for_box(id: String) -> Dictionary:
	for c in active:
		if _live(c) and id in contract_boxes(c):
			return c
	return {}


# -----------------------------------------------------------------------------
# Time hooks
# -----------------------------------------------------------------------------

func storming() -> bool:
	return Weather.condition() >= Weather.C.HEAVY and Weather.is_snowing()


func on_advance(step: float) -> void:
	var b: BalanceData = Catalog.balance
	var paused := storming()
	for c in active:
		if not _live(c) or c.get("tutorial", false):
			continue
		if c["status"] == "serviced":
			c["snowed_min"] = 0.0
			continue
		if not is_snowed_in(c):
			continue
		if not paused:
			c["snowed_min"] = float(c.get("snowed_min", 0.0)) + step
		var left := hours_left(c)
		var warned := int(c.get("warned", 0))
		if left <= 0.0:
			_lose(c)
		elif left <= b.contract_last_warn_hours and warned < 2:
			c["warned"] = 2
			Notify.push("URGENT: %s is lost in %d hours unless it's cleared!" % [c["address"], int(ceil(left))], Notify.BAD)
		elif left <= b.contract_warn_hours and warned < 1:
			c["warned"] = 1
			Notify.push("%s has been snowed in a long time — %d hours left to clear it." % [c["address"], int(ceil(left))], Notify.WARN)


func on_hour(day: int, hour: int) -> void:
	_resolve_bids()
	for c in active:
		if _live(c):
			_refresh(c)
	if hour == 6:
		_generate_listings(day, false)
	changed.emit()


func on_day(_day: int) -> void:
	pass


# -----------------------------------------------------------------------------
# Board / bidding
# -----------------------------------------------------------------------------

func _occupied_targets() -> Dictionary:
	var used := {}
	for c in active:
		used[str(c["target"])] = true
	for l in listings:
		used[str(l["target"])] = true
	for bd in bids:
		used[str(bd["listing"]["target"])] = true
	return used


func _client_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [CLIENT_FIRST[rng.randi() % CLIENT_FIRST.size()], CLIENT_LAST[rng.randi() % CLIENT_LAST.size()]]


func municipal_unlocked() -> bool:
	if Game.reputation < 58.0:
		return false
	for v in Game.vehicles:
		var vd: VehicleData = Catalog.vehicle(StringName(v["id"]))
		if vd and (vd.has_plow or vd.has_blower):
			return true
	return false


func big_jobs_unlocked() -> bool:
	return Game.reputation >= 52.0 or Game.owns_tool("small_blower") or Game.owns_tool("large_blower") or Game.vehicles.size() > 1


func _price(volume: float, recurring: bool) -> int:
	var b: BalanceData = Catalog.balance
	var growth := 1.0 + b.contract_value_growth_per_year * (Game.year - 1)
	var v := b.contract_base_fee + b.contract_price_per_m3 * pow(maxf(volume, 0.5), 0.75)
	if recurring:
		v *= b.recurring_visit_factor
	return int(round(v * growth))


func _generate_listings(day: int, initial: bool) -> void:
	var rng := _rng_for(day * 17 + 5)
	# Drop expired listings.
	var keep := []
	for l in listings:
		if int(l["expires"]) > day:
			keep.append(l)
	listings = keep
	var used := _occupied_targets()
	var want := 6 if initial else 5
	var tries := 0
	while listings.size() < want and tries < 40:
		tries += 1
		var roll := rng.randf()
		if roll < 0.12 and municipal_unlocked():
			var seg: Dictionary = Layout.road_segments[rng.randi() % Layout.road_segments.size()]
			if used.has("road:" + seg["id"]):
				continue
			_add_municipal_listing(seg, day, rng)
			used["road:" + seg["id"]] = true
			continue
		if roll < 0.24 and big_jobs_unlocked():
			var areas := [Layout.big_areas[0], Layout.big_areas[1], Layout.big_areas[2]]
			var a: Dictionary = areas[rng.randi() % areas.size()]
			if used.has("area:" + a["id"]):
				continue
			_add_area_listing(a, day, rng)
			used["area:" + a["id"]] = true
			continue
		var lot: Dictionary = Layout.lots[rng.randi() % Layout.lots.size()]
		if lot["vacant"] or lot["is_player"] or lot["is_neighbor"]:
			continue
		var key := "lot:%d" % lot["index"]
		if used.has(key):
			continue
		_add_lot_listing(lot, day, rng)
		used[key] = true
	changed.emit()


func _zone(name: String, box_ids: Array) -> Dictionary:
	var ra := []
	for id in box_ids:
		var b := Boxes.get_box(id)
		for r in b.get("rects", []):
			ra.append(rect_to_a(r))
	return {"name": name, "boxes": box_ids.duplicate(), "rects": ra, "done": false, "progress": 0.0}


func _add_lot_listing(lot: Dictionary, day: int, rng: RandomNumberGenerator) -> void:
	var drive := Boxes.lot_box(lot, "driveway")
	var path := Boxes.lot_box(lot, "path")
	var side := Boxes.lot_box(lot, "sidewalk")
	var choice := rng.randi() % 5
	var zones := []
	match choice:
		0:
			zones = [_zone("Driveway", [drive])]
		1:
			zones = [_zone("Path to the house", [path])]
		2:
			zones = [_zone("Driveway", [drive]), _zone("Path to the house", [path])]
		3:
			zones = [_zone("Path to the house", [path]), _zone("Sidewalk", [side])]
		4:
			zones = [_zone("Sidewalk", [side])]
	var recurring := rng.randf() < 0.45 and day > 0
	var vol := 0.0
	var area := 0.0
	for z in zones:
		vol += zone_estimate(z)
		area += zone_area(z)
	var est := vol if not recurring else area * 0.07
	var budget := _price(est, recurring)
	listings.append({"lid": _next_id, "target": "lot:%d" % lot["index"], "address": lot["address"],
		"client": _client_name(rng), "type": "recurring" if recurring else "one_time", "zones": zones,
		"est_volume": est, "budget": budget, "expires": day + rng.randi_range(2, 4), "pos": [lot["center_x"], lot["front_z"]]})
	_next_id += 1


func _add_area_listing(a: Dictionary, day: int, rng: RandomNumberGenerator) -> void:
	var r: Rect2 = a["rect"]
	var zones := [_zone("Parking lot", ["area_" + str(a["id"])])]
	var recurring := rng.randf() < 0.5
	var vol := zone_estimate(zones[0])
	var est := vol if not recurring else zone_area(zones[0]) * 0.07
	var budget := int(_price(est, recurring) * 1.25)
	listings.append({"lid": _next_id, "target": "area:" + a["id"], "address": a["name"], "client": a["name"].split(" parking")[0],
		"type": "recurring" if recurring else "one_time", "zones": zones, "est_volume": est, "budget": budget,
		"expires": day + rng.randi_range(2, 4), "pos": [r.get_center().x, r.get_center().y], "large": true})
	_next_id += 1


func _add_municipal_listing(seg: Dictionary, day: int, rng: RandomNumberGenerator) -> void:
	var zones := [_zone("Road section", ["road_" + str(seg["id"])])]
	var est := zone_area(zones[0]) * 0.06
	var budget := int(_price(est, true) * 1.4)
	listings.append({"lid": _next_id, "target": "road:" + seg["id"], "address": seg["name"], "client": "City of Maple Ridge",
		"type": "municipal", "zones": zones, "est_volume": est, "budget": budget,
		"expires": day + 3, "pos": [seg["rect"].get_center().x, seg["rect"].get_center().y],
		"segment": seg["id"], "large": true})
	_next_id += 1


func listing_by_id(lid: int) -> Dictionary:
	for l in listings:
		if int(l["lid"]) == lid:
			return l
	return {}


## Proximity to existing clients or home (clustering bonus).
func near_existing(pos: Vector2) -> bool:
	var b: BalanceData = Catalog.balance
	var home := Layout.lot_to_world(Layout.player_lot, 0, 10)
	if pos.distance_to(home) < b.proximity_radius:
		return true
	for c in active:
		var p: Array = c.get("pos", [0, 0])
		if Vector2(p[0], p[1]).distance_to(pos) < b.proximity_radius:
			return true
	return false


## Player's chance factors for display. Returns {score, factors[]}.
func bid_factors(l: Dictionary, amount: int) -> Dictionary:
	var b: BalanceData = Catalog.balance
	var factors := []
	var mult := 1.0
	var rep := (Game.reputation - 50.0) / 400.0
	mult -= rep
	factors.append("Reputation %d" % int(Game.reputation))
	var p: Array = l["pos"]
	if near_existing(Vector2(p[0], p[1])):
		mult -= b.proximity_bid_bonus
		factors.append("Nearby client bonus")
	var cap := equipment_capability()
	if l.get("large", false) and cap < 2:
		mult += 0.12
		factors.append("Equipment too small for this job")
	elif cap >= 2:
		mult -= 0.04
		factors.append("Good equipment")
	return {"score": float(amount) / float(l["budget"]) * mult, "factors": factors}


## 0 hands/shovel, 1 pushers/sleigh, 2 blowers, 3 vehicles with plow/blower.
func equipment_capability() -> int:
	var cap := 0
	for v in Game.vehicles:
		var vd: VehicleData = Catalog.vehicle(StringName(v["id"]))
		if vd and (vd.has_plow or vd.has_blower):
			cap = 3
	if cap < 3 and (Game.owns_tool("small_blower") or Game.owns_tool("large_blower")):
		cap = 2
	if cap < 2:
		for t in ["wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh", "electric_shovel"]:
			if Game.owns_tool(t):
				cap = 1
	return cap


func place_bid(lid: int, amount: int) -> Dictionary:
	var l := listing_by_id(lid)
	if l.is_empty():
		return {"ok": false, "msg": "Listing no longer available."}
	if l["type"] == "municipal" and not municipal_unlocked():
		return {"ok": false, "msg": "The city requires a reputation of 58+ and a plow or blower vehicle."}
	listings.erase(l)
	var rng := _rng_for(lid * 3 + int(Clock.minutes))
	bids.append({"listing": l, "amount": amount, "resolve_at": Clock.minutes + rng.randf_range(60.0, 180.0)})
	Notify.push("Bid of $%d submitted for %s." % [amount, l["address"]], Notify.INFO)
	changed.emit()
	Game.dirty_since_save = true
	return {"ok": true, "msg": "Bid submitted. You'll hear back within a few hours."}


func _resolve_bids() -> void:
	var still := []
	for bd in bids:
		if Clock.minutes < float(bd["resolve_at"]):
			still.append(bd)
			continue
		var l: Dictionary = bd["listing"]
		var amount: int = bd["amount"]
		var mine: float = bid_factors(l, amount)["score"]
		var rng := _rng_for(int(l["lid"]) * 11)
		var best := INF
		var best_name := ""
		var n := 2 + rng.randi() % 2
		for k in range(n):
			var rv: Dictionary = RIVALS[(int(l["lid"]) + k) % RIVALS.size()]
			var s: float = rng.randf_range(0.86, 1.14) + float(rv["edge"])
			if s < best:
				best = s
				best_name = rv["name"]
		if mine <= best:
			_award(l, amount)
			Notify.push("Bid accepted! %s — %s." % [l["address"], "recurring service" if l["type"] != "one_time" else "one-time job"], Notify.GOOD)
		else:
			rival_wins += 1
			Notify.push("Bid rejected for %s — %s won the job." % [l["address"], best_name], Notify.WARN)
	bids = still


func _award(l: Dictionary, amount: int) -> Dictionary:
	var c := {"id": _next_id, "target": l["target"], "address": l["address"], "client": l["client"],
		"type": l["type"], "zones": l["zones"].duplicate(true), "pay": amount, "status": "active", "visits": 0,
		"pos": l["pos"], "accepted": Clock.minutes, "segment": l.get("segment", ""), "snowed_min": 0.0, "warned": 0}
	_next_id += 1
	if c["type"] != "one_time":
		c["status"] = "needs_service"
	var all_done := true
	for z in c["zones"]:
		measure_zone(c, z, false)
		if not z["done"]:
			all_done = false
	if c["type"] != "one_time" and all_done:
		c["status"] = "serviced"
	active.append(c)
	changed.emit()
	Game.dirty_since_save = true
	return c


## Debug / tests: win a listing outright.
func force_award(lid: int, amount := -1) -> Dictionary:
	var l := listing_by_id(lid)
	if l.is_empty():
		return {}
	listings.erase(l)
	return _award(l, amount if amount > 0 else int(l["budget"]))


## Tutorial contract created by the neighbor's negotiation: one dynamic box from his porch steps
## down the walk to his mailbox (Layout.gerry_trail_rects). No snowed-in timer.
func create_tutorial_contract(pay: int) -> Dictionary:
	var lot := Layout.neighbor_lot
	Boxes.add_dynamic("gerry_trail", "path", "Trail to the mailbox", "lot:%d" % lot["index"], Layout.gerry_trail_rects(), lot["address"])
	var zone := _zone("Trail to the mailbox", ["gerry_trail"])
	var c := {"id": _next_id, "target": "lot:%d" % lot["index"], "address": lot["address"], "client": "Gerry (neighbour)",
		"type": "one_time", "zones": [zone], "pay": pay, "status": "active", "visits": 0,
		"pos": [lot["center_x"], lot["front_z"]], "accepted": Clock.minutes, "tutorial": true, "snowed_min": 0.0, "warned": 0}
	_next_id += 1
	measure_zone(c, zone)
	active.append(c)
	changed.emit()
	if zone["done"]:
		_refresh(c)
	return c


func contracted_segments() -> Array:
	var out := []
	for c in active:
		if c["type"] == "municipal" and c["status"] != "expired":
			out.append(c["segment"])
	return out


func active_count() -> int:
	var n := 0
	for c in active:
		if _live(c):
			n += 1
	return n


## End of winter: recurring contracts expire unless renewed.
func end_winter(renew_ids: Array) -> void:
	for c in active:
		if c["type"] != "one_time" and c["status"] != "lost" and int(c["id"]) in renew_ids:
			c["renewed"] = true
		elif c["status"] != "completed" and c["status"] != "lost":
			c["status"] = "expired"


func serialize() -> Dictionary:
	return {"listings": listings, "bids": bids, "active": active, "history": history, "next_id": _next_id, "rival_wins": rival_wins}


func deserialize(d: Dictionary) -> void:
	listings = d.get("listings", [])
	bids = d.get("bids", [])
	active = d.get("active", [])
	history = d.get("history", [])
	_next_id = int(d.get("next_id", 1))
	rival_wins = int(d.get("rival_wins", 0))
	for c in active:
		c["id"] = int(c["id"])
		c["warned"] = int(c.get("warned", 0))
		c["snowed_min"] = float(c.get("snowed_min", 0.0))
		for z in c["zones"]:
			if not z.has("boxes"):
				z["boxes"] = _migrate_zone_boxes(c, z)
			if c.get("tutorial", false):
				# Polish 3 §4: the trail's rectangles follow the moved mailbox (old saves too).
				var tb := Boxes.get_box("gerry_trail")
				if not tb.is_empty():
					var ra := []
					for r in tb["rects"]:
						ra.append(rect_to_a(r))
					z["rects"] = ra
	for l in listings:
		l["lid"] = int(l["lid"])
		for z in l["zones"]:
			if not z.has("boxes"):
				z["boxes"] = _migrate_zone_boxes(l, z)
	changed.emit()


## Save version 1 zones were plain rects: map them onto the matching clearing boxes.
func _migrate_zone_boxes(c: Dictionary, z: Dictionary) -> Array:
	var target: String = str(c.get("target", ""))
	var zname: String = str(z.get("name", ""))
	if c.get("tutorial", false):
		var lot := Layout.neighbor_lot
		Boxes.add_dynamic("gerry_trail", "path", "Trail to the mailbox", "lot:%d" % lot["index"], Layout.gerry_trail_rects(), lot["address"])
		return ["gerry_trail"]
	if target.begins_with("lot:"):
		var idx := int(target.substr(4))
		if zname.begins_with("Driveway"):
			return ["lot%d_driveway" % idx]
		if zname.begins_with("Sidewalk"):
			return ["lot%d_sidewalk" % idx]
		return ["lot%d_path" % idx]
	if target.begins_with("area:"):
		return ["area_" + target.substr(5)]
	if target.begins_with("road:"):
		return ["road_" + target.substr(5)]
	return []
