extends Node
## Clearing boxes (polish §7). Every clearable area of the map is divided into boxes: per lot the
## driveway, the path to the house (walkway, stairs and porch) and the sidewalk; each parking lot;
## each municipal street section. Contract zones are made of boxes (see Contracts).
##
## Completion rule: a box tracks the most snow it has held since it last opened ("peak", above the
## residual depth). When the player has cleared box_completion (90 %, polish 3; was 98 %) of that
## snow, the box completes: the remaining snow inside it — up to 10 % of the peak — is removed (an
## explicit, documented exception to volume conservation, like the old contract clean-up) and the
## box shows bare ground. Completed boxes
## hold their edges (relaxation won't slump outside snow into them). New snow reopens a box once
## its average depth reaches box_reopen_depth. State is saved with the game.

signal box_completed(id: String)
signal box_reopened(id: String)
signal changed

const TINY := 0.0004            # m3: a box with less snow than this counts as empty
## Big boxes (streets, parking lots) are measured from a sample of their cells; once the sample
## says they are within this much of box_completion they are counted exactly, so they complete at
## an exact 90 % and never on an estimate (with 90 %: exact counting from an estimated 85 %).
const EXACT_MARGIN := 0.05
## …and while the sample says it is past box_completion - RECHECK_MARGIN, it is also counted exactly
## at most every RECHECK_MS (real time), in case the sample overrates what's left.
const RECHECK_MARGIN := 0.4
const RECHECK_MS := 1500

var boxes: Array = []           # Dictionaries, see _make()
var by_id: Dictionary = {}
var _cursor := 0
var _near_timer := 0.0
var _built := false
# The box the player is taking snow from right now (polish 2 §3: the work outline). Every
# scoop / push / intake that moves snow out of a box bumps work_serial.
var work_box := ""
var work_serial := 0


func _ready() -> void:
	build()


func build() -> void:
	boxes.clear()
	by_id.clear()
	Layout.ensure()
	for lot in Layout.lots:
		var idx: int = lot["index"]
		var lot_owner := "lot:%d" % idx
		var hi := Layout.house_info(lot)
		if not lot["vacant"]:
			_add("lot%d_driveway" % idx, "driveway", "Driveway", lot_owner, [hi["driveway"]], lot["address"])
			_add("lot%d_path" % idx, "path", "Path to the house", lot_owner, [hi["walkway"], hi["stairs"], hi["porch"]], lot["address"])
		_add("lot%d_sidewalk" % idx, "sidewalk", "Sidewalk", lot_owner, [hi["sidewalk"]], lot["address"])
	for a in Layout.big_areas:
		if a["id"] == "dump_lot":
			continue
		_add("area_" + str(a["id"]), "parking", "Parking lot", "area:" + str(a["id"]), [a["rect"], a["apron"]], a["place"])
	for seg in Layout.road_segments:
		_add("road_" + str(seg["id"]), "street", "Street", "road:" + str(seg["id"]), [seg["rect"]], seg["name"])
	_built = true


func _add(id: String, kind: String, box_name: String, owner_id: String, rects: Array, place: String, dynamic := false) -> Dictionary:
	var area := 0.0
	var big := false
	for r in rects:
		area += (r as Rect2).get_area()
	big = area > 300.0
	var b := {"id": id, "kind": kind, "name": box_name, "owner": owner_id, "rects": rects, "place": place,
		"area": area, "big": big, "dynamic": dynamic,
		"complete": false, "peak": 0.0, "vol": 0.0, "progress": 0.0, "since": -1.0}
	boxes.append(b)
	by_id[id] = b
	return b


## A box defined at runtime (e.g. Gerry's trail). Saved with the game.
func add_dynamic(id: String, kind: String, box_name: String, owner_id: String, rects: Array, place: String) -> Dictionary:
	if by_id.has(id):
		return by_id[id]
	var b := _add(id, kind, box_name, owner_id, rects, place, true)
	measure(b, true)
	return b


func get_box(id: String) -> Dictionary:
	return by_id.get(id, {})


func lot_box(lot: Dictionary, kind: String) -> String:
	return "lot%d_%s" % [int(lot["index"]), kind]


func for_owner(owner_id: String) -> Array:
	var out := []
	for b in boxes:
		if b["owner"] == owner_id and not b["dynamic"]:
			out.append(b)
	return out


## Fresh state for a new winter: every box starts open with the snow it holds now.
func start_winter() -> void:
	for b in boxes.duplicate():
		if b["dynamic"]:
			boxes.erase(b)
			by_id.erase(b["id"])
	for b in boxes:
		b["complete"] = false
		b["peak"] = 0.0
		b["progress"] = 0.0
		b["since"] = Clock.minutes
		measure(b, false)
	changed.emit()


# -----------------------------------------------------------------------------
# Measurement & completion
# -----------------------------------------------------------------------------

func snow_volume(b: Dictionary, exact: bool) -> float:
	var res: float = Catalog.balance.contract_residual_depth
	var v := 0.0
	for r in b["rects"]:
		if exact or not b["big"]:
			v += Snow.volume_in_rect(r, res)
		else:
			v += Snow.estimate_volume(r, res, 4)
	return v


func avg_depth(b: Dictionary, exact: bool) -> float:
	var v := 0.0
	for r in b["rects"]:
		if exact or not b["big"]:
			v += Snow.volume_in_rect(r, 0.0)
		else:
			v += Snow.estimate_volume(r, 0.0, 4)
	return v / maxf(float(b["area"]), 0.01)


## Measure one box and apply the completion / reopening rules. Returns its progress (0..1).
func measure(b: Dictionary, exact := true) -> float:
	var bal: BalanceData = Catalog.balance
	if b["complete"]:
		if avg_depth(b, not b["big"]) >= bal.box_reopen_depth:
			_reopen(b)
		return b["progress"]
	# Big boxes (streets, parking lots) are sampled; an exact count is only made when the sample
	# says the box is nearly done, so the completion snap is always based on the real snow.
	var v := snow_volume(b, not b["big"])
	var peak0: float = maxf(float(b["peak"]), v)
	var est_done := 1.0 - v / peak0 if peak0 > TINY else 1.0
	var near_done := peak0 > TINY and est_done >= bal.box_completion - EXACT_MARGIN
	# A sample can overrate what's left (a strip of snow along one sampled row counts four times),
	# so a box that looks well along is also counted exactly now and then: it can't get stuck just
	# under the threshold on a bad estimate.
	var recheck := false
	if b["big"] and exact and not near_done and est_done >= bal.box_completion - RECHECK_MARGIN:
		var now := Time.get_ticks_msec()
		if now - int(b.get("_exact_at", -100000)) >= RECHECK_MS:
			b["_exact_at"] = now
			recheck = true
	if b["big"] and exact and (near_done or recheck or v < TINY * 4.0):
		v = snow_volume(b, true)
	b["vol"] = v
	b["peak"] = maxf(float(b["peak"]), v)
	var peak: float = b["peak"]
	b["progress"] = 1.0 if peak <= TINY else clampf(1.0 - v / peak, 0.0, 1.0)
	if (b["progress"] >= bal.box_completion or v < TINY) and (exact or not b["big"]):
		complete(b)
	return b["progress"]


func progress_of(id: String) -> float:
	var b := get_box(id)
	return 1.0 if b.is_empty() else float(b["progress"])


func is_complete(id: String) -> bool:
	var b := get_box(id)
	return not b.is_empty() and b["complete"]


## Complete a box: remove the last snow inside it (explicit conservation exception) and show bare
## ground with clean edges.
func complete(b: Dictionary) -> void:
	for r in b["rects"]:
		Snow.set_rect(r, 0.0, true)
		Snow.set_hold_rect(r, true)
	b["complete"] = true
	b["progress"] = 1.0
	b["peak"] = 0.0
	b["vol"] = 0.0
	b["since"] = -1.0
	box_completed.emit(b["id"])
	changed.emit()
	Game.dirty_since_save = true


func _reopen(b: Dictionary) -> void:
	for r in b["rects"]:
		Snow.set_hold_rect(r, false)
	b["complete"] = false
	var v := snow_volume(b, false)
	b["vol"] = v
	b["peak"] = v
	b["progress"] = 0.0
	b["since"] = Clock.minutes
	box_reopened.emit(b["id"])
	changed.emit()


## Box containing (or within `radius` of) a world point, preferring the one the point is inside.
func box_at(p: Vector2, radius := 0.0) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b in boxes:
		for r in b["rects"]:
			var rr: Rect2 = r
			if rr.has_point(p):
				# Smallest containing box wins (a driveway over a street section, etc.).
				var d := -1.0 / maxf(float(b["area"]), 0.01)
				if d < best_d:
					best_d = d
					best = b
			elif radius > 0.0 and rr.grow(radius).has_point(p) and best_d > 0.0:
				var dd := _dist_to_rect(rr, p)
				if dd < best_d:
					best_d = dd
					best = b
	return best


## The player took snow from the ground at p: remember which (open) box it came from.
func note_work(p: Vector2) -> void:
	var b := box_at(p)
	if b.is_empty() or b["complete"]:
		return
	work_box = b["id"]
	work_serial += 1


## True when p lies inside any rect of the box.
func box_has_point(id: String, p: Vector2) -> bool:
	var b := get_box(id)
	if b.is_empty():
		return false
	for r in b["rects"]:
		if (r as Rect2).has_point(p):
			return true
	return false


## The box's outer boundary on the snow grid: the cell edges between cells inside the box (centre
## inside one of its rects) and cells outside it — internal edges between its rects drop out.
## Returns a PackedVector2Array of segment end points (pairs), in world metres.
func outline_segments(id: String) -> PackedVector2Array:
	var b := get_box(id)
	var out := PackedVector2Array()
	if b.is_empty():
		return out
	var cs := Snow.CELL
	var inside := {}
	for r in b["rects"]:
		var rr: Rect2 = r
		for cz in range(roundi(rr.position.y / cs), roundi(rr.end.y / cs)):
			for cx in range(roundi(rr.position.x / cs), roundi(rr.end.x / cs)):
				inside[Vector2i(cx, cz)] = true
	for c in inside.keys():
		var cc: Vector2i = c
		var ax := cc.x * cs
		var az := cc.y * cs
		if not inside.has(cc + Vector2i(0, -1)):
			out.append_array([Vector2(ax, az), Vector2(ax + cs, az)])
		if not inside.has(cc + Vector2i(0, 1)):
			out.append_array([Vector2(ax, az + cs), Vector2(ax + cs, az + cs)])
		if not inside.has(cc + Vector2i(-1, 0)):
			out.append_array([Vector2(ax, az), Vector2(ax, az + cs)])
		if not inside.has(cc + Vector2i(1, 0)):
			out.append_array([Vector2(ax + cs, az), Vector2(ax + cs, az + cs)])
	return out


static func _dist_to_rect(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dz).length()


## All boxes touching a circle (used to re-measure what the player is working on).
func boxes_near(p: Vector2, radius: float) -> Array:
	var out := []
	for b in boxes:
		for r in b["rects"]:
			if (r as Rect2).grow(radius).has_point(p):
				out.append(b)
				break
	return out


func _process(delta: float) -> void:
	sim_step(delta)


## One frame's measuring. Polish 5 §9: fast-forward runs it once more for every extra clock
## substep (Clock._process), so boxes are looked at as often per game minute as at 1×.
func sim_step(delta: float) -> void:
	if not Clock.running or get_tree().paused or not Snow.initialized:
		return
	# Boxes the player is working in: exact and frequent (HUD progress, completion snaps).
	_near_timer -= delta
	if _near_timer <= 0.0:
		_near_timer = 0.25
		var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
		for b in boxes_near(pp, 4.0):
			measure(b, true)
	# Everything else: one box per frame, round robin (reopening after snowfall, grader windrows) —
	# every box is looked at about once a second and a half, which is plenty for both.
	var n := boxes.size()
	if n > 0:
		_cursor = (_cursor + 1) % n
		measure(boxes[_cursor], false)


## Hourly during time skips: completed boxes are checked for new snow so they reopen (and contract
## timers start) on time. Open boxes only need measuring while someone is clearing them.
func on_hour(_day: int, _hour: int) -> void:
	if Clock.skipping:
		for b in boxes:
			if b["complete"]:
				measure(b, false)


## Measure every box now (tests, loading).
func measure_all(exact := false) -> void:
	for b in boxes:
		measure(b, exact)


# -----------------------------------------------------------------------------
# Persistence
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	var st := {}
	for b in boxes:
		st[b["id"]] = [b["complete"], b["peak"], b["progress"], b["since"]]
	var dyn := []
	for b in boxes:
		if b["dynamic"]:
			var ra := []
			for r in b["rects"]:
				ra.append([r.position.x, r.position.y, r.size.x, r.size.y])
			dyn.append({"id": b["id"], "kind": b["kind"], "name": b["name"], "owner": b["owner"], "place": b["place"], "rects": ra})
	return {"state": st, "dynamic": dyn}


func deserialize(d: Dictionary) -> void:
	build()
	for e in d.get("dynamic", []):
		var rects := []
		for a in e.get("rects", []):
			rects.append(Rect2(a[0], a[1], a[2], a[3]))
		# Polish 5 §5: its place is read from the layout (its owner's address), not the saved text.
		var place := Layout.place_name(str(e.get("owner", "")))
		_add(str(e["id"]), str(e.get("kind", "path")), str(e.get("name", "Box")), str(e.get("owner", "")), rects, place if place != "" else str(e.get("place", "")), true)
	# Polish 3 §4 / polish 4 §4: Gerry's mailbox moved (beside his walk, then to its foot), so his
	# trail is the steps and the walk down to it. A saved trail with older rectangles is rebuilt —
	# unless it was already done (or the tutorial is past it): the stage wins, the trail stays done
	# on the rectangles it was finished on and is never reopened by the move.
	var retrail := false
	var trail: Dictionary = by_id.get("gerry_trail", {})
	var saved_trail = d.get("state", {}).get("gerry_trail", null)
	var trail_done: bool = (saved_trail is Array and (saved_trail as Array).size() >= 1 and bool(saved_trail[0])) or Game.stage() >= Game.Stage.TRAIL_DONE
	if not trail.is_empty() and not trail_done:
		var want := Layout.gerry_trail_rects()
		if not _same_rects(trail["rects"], want):
			trail["rects"] = want
			var a := 0.0
			for r in want:
				a += (r as Rect2).get_area()
			trail["area"] = a
			retrail = true
	var st: Dictionary = d.get("state", {})
	for b in boxes:
		var s = st.get(b["id"], null)
		if s is Array and (s as Array).size() >= 4:
			b["complete"] = bool(s[0])
			b["peak"] = float(s[1])
			b["progress"] = float(s[2])
			b["since"] = float(s[3])
		else:
			b["complete"] = false
			b["peak"] = 0.0
			b["since"] = Clock.minutes
			measure(b, false)
		if b["complete"]:
			for r in b["rects"]:
				Snow.set_hold_rect(r, true)
	if retrail and not trail["complete"]:
		_rebase_from_snow(trail)
	changed.emit()


func _same_rects(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var ra: Rect2 = a[i]
		var rb: Rect2 = b[i]
		if not ra.position.is_equal_approx(rb.position) or not ra.size.is_equal_approx(rb.size):
			return false
	return true


## Peak and progress of a box whose rectangles changed, taken from the snow (as the version 1
## migration does): the peak is what the box would hold at the depth of the untouched snow right
## beside it (never less than what's in it now), so work already done still counts.
func _rebase_from_snow(b: Dictionary) -> void:
	var res: float = Catalog.balance.contract_residual_depth
	var v := snow_volume(b, true)
	var depth_sum := 0.0
	var n := 0
	for r in b["rects"]:
		var rr: Rect2 = r
		for k in range(6):
			var t := (k + 0.5) / 6.0
			for q in [Vector2(rr.position.x - 1.2, rr.position.y + rr.size.y * t), Vector2(rr.end.x + 1.2, rr.position.y + rr.size.y * t)]:
				if box_at(q).is_empty():
					depth_sum += maxf(Snow.depth_at(q.x, q.y) - res, 0.0)
					n += 1
	var cells := 0.0
	for r in b["rects"]:
		var c: Rect2i = Snow._rect_cells(r)
		cells += c.size.x * c.size.y
	var est := (depth_sum / n) * cells * Snow.CELL_AREA if n > 0 else v
	b["peak"] = maxf(v, est)
	b["vol"] = v
	b["progress"] = clampf(1.0 - v / b["peak"], 0.0, 1.0) if b["peak"] > TINY else 1.0
	b["since"] = Clock.minutes if float(b.get("since", -1.0)) < 0.0 else b["since"]
	# Not measured here: contracts load after boxes, so a completion is left to the next
	# measurement (it then pays Gerry's contract and moves the tutorial on as usual).


## Saves from before boxes existed (save version 1): derive box state from the snow itself.
func migrate_from_snow() -> void:
	build()
	var bal: BalanceData = Catalog.balance
	for b in boxes:
		b["complete"] = false
		b["peak"] = 0.0
		b["since"] = Clock.minutes
		if avg_depth(b, false) < bal.box_reopen_depth * 0.5:
			b["complete"] = true
			b["progress"] = 1.0
			b["since"] = -1.0
			for r in b["rects"]:
				Snow.set_hold_rect(r, true)
		else:
			measure(b, false)
	changed.emit()
