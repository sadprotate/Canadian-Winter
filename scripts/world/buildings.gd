class_name Buildings
extends RefCounted
## Polish 5 §3: every building as a volume — its footprint (world XZ rect) up to the top of its
## roof — for the two snow rules about buildings:
##   * no snow work from inside: hand tools, the electric shovel and the blowers act on snow only
##     when the player is outdoors (indoors() is false) and the line from their eye to the snow
##     crosses no building (blocks()) — ToolController, WalkBehind;
##   * thrown snow that would enter a building stops at its outer face and falls at the foot of that
##     wall, outside, volume conserved (entry() / foot(), used by Throw.compute).
## The list holds every built lot's house body and attached garage (the sizes HouseBuilder builds)
## and Layout.buildings (the school, the store, the church). A building added later — §16's
## commercial garage — joins with register(); §15's garage is the house garage, already listed.
## A registered footprint must also be S_BLOCKED in the snow map so no snow lies inside.

## The hollow houses' wall colliders and siding stand up to 11 cm proud of the footprint line: a
## point within this of a footprint is in its walls.
const SKIN := 0.12
## Thrown snow stopped by a wall lands this far out from the footprint line (the foot of the wall).
const FOOT_OUT := 0.25
## Heights (HouseBuilder.build): bungalow walls 3.0 m + a 2.3 m roof rise; two storeys 5.6 m +
## 2.0 m (never the hollow houses); the attached garage 2.9 m + 1.5 m.
const HOUSE_TOP := 5.3
const TWO_STOREY_TOP := 7.6
const GARAGE_TOP := 4.4

static var _list: Array = []
static var _extra: Array = []
static var _built := false


## Every building: {id, kind, rect: Rect2 (world XZ), top: float (m)}.
static func all() -> Array:
	if not _built:
		_build()
	return _list


## Add a building (§16). `top`: the highest point of its roof above the ground.
static func register(id: String, rect: Rect2, top: float, kind := "building") -> void:
	for e in _extra:
		if e["id"] == id:
			_extra.erase(e)
			break
	_extra.append({"id": id, "kind": kind, "rect": rect, "top": top})
	_built = false


## Remove a building added with register().
static func unregister(id: String) -> void:
	for e in _extra:
		if e["id"] == id:
			_extra.erase(e)
			_built = false
			return


## Rebuild the list from the layout on next use (after the layout changes).
static func reset() -> void:
	_built = false


static func _build() -> void:
	Layout.ensure()
	_list = []
	for lot in Layout.lots:
		if lot.get("vacant", false):
			continue
		var hi := Layout.house_info(lot)
		var hollow: bool = lot["is_player"] or lot["is_neighbor"]
		var two := int(lot["style"]) == 1 and not hollow
		_list.append({"id": "house_%d" % lot["index"], "kind": "house", "rect": hi["body"], "top": TWO_STOREY_TOP if two else HOUSE_TOP, "lot": lot["index"]})
		_list.append({"id": "garage_%d" % lot["index"], "kind": "garage", "rect": hi["garage"], "top": GARAGE_TOP, "lot": lot["index"]})
	for b in Layout.buildings:
		_list.append({"id": str(b["id"]), "kind": str(b["kind"]), "rect": b["rect"], "top": float(b["height"])})
	_list.append_array(_extra)
	_built = true


## The building whose footprint, grown by `skin`, holds p (world XZ) — or {}.
static func at(p: Vector2, skin := 0.0) -> Dictionary:
	for b in all():
		if (b["rect"] as Rect2).grow(skin).has_point(p):
			return b
	return {}


## Is someone standing at `feet` inside a building — within its footprint or in its walls (a
## doorway counts as inside)? Outdoors is everywhere else.
static func indoors(feet: Vector3) -> bool:
	var b := at(Vector2(feet.x, feet.z), SKIN)
	return not b.is_empty() and feet.y < float(b["top"])


## The buildings that come within `r` of the point p (world XZ): the short list a tool tests.
static func near(p: Vector2, r: float) -> Array:
	var out := []
	for b in all():
		if (b["rect"] as Rect2).grow(r).has_point(p):
			out.append(b)
	return out


## The buildings whose footprint (grown by `pad`) the 2D segment a→b touches.
static func along(a: Vector2, b: Vector2, pad := 0.5) -> Array:
	var out := []
	for bl in all():
		var r := (bl["rect"] as Rect2).grow(pad)
		if not _seg_rect(a, b, r).is_empty():
			out.append(bl)
	return out


## Does the straight line from a to b pass through a building (footprint × [ground, top])? The
## last `end_skin` metres of it (measured along the ground) are not tested, so a target pressed
## against the foot of a wall, slightly inside its line, still counts as outside. `list`: the
## buildings to test (near()), all of them if empty.
static func blocks(a: Vector3, b: Vector3, list: Array = [], end_skin := 0.0) -> bool:
	var e := b
	if end_skin > 0.0:
		var h := Vector2(b.x - a.x, b.z - a.z).length()
		if h <= end_skin:
			return false
		e = a + (b - a) * (1.0 - end_skin / h)
	for bl in (list if not list.is_empty() else all()):
		if _seg_box(a, e, bl["rect"], float(bl["top"])) >= 0.0:
			return true
	return false


## Where the step a→b (3D) first enters one of `list`'s buildings (footprint grown by SKIN, from the
## ground to its top): {"b": building, "t": 0..1 along the step}, or {}.
static func entry(a: Vector3, b: Vector3, list: Array) -> Dictionary:
	var best := {}
	for bl in list:
		var t := _seg_box(a, b, (bl["rect"] as Rect2).grow(SKIN), float(bl["top"]))
		if t >= 0.0 and (best.is_empty() or t < float(best["t"])):
			best = {"b": bl, "t": t}
	return best


## The foot of the wall a throw from `start` along `dir2` meets on building `bl`: the outer face its
## path crosses into the footprint (or, if it starts inside, the nearest face), kept off the
## corners. Returns {face: Vector2 (on the wall's outer face, SKIN out), foot: Vector2 (FOOT_OUT out),
## s: distance along dir2 from start to the face, normal: Vector2 (outward)}.
static func foot(bl: Dictionary, start: Vector2, dir2: Vector2) -> Dictionary:
	var r: Rect2 = bl["rect"]
	var g := r.grow(SKIN)
	var d := dir2.normalized()
	var hit := _ray_rect(start, d, g)
	var e: Vector2
	var n: Vector2
	var s := 0.0
	if hit.is_empty():
		# Starting inside (or the path misses): the nearest face.
		var dl := start.x - g.position.x
		var dr := g.end.x - start.x
		var dt := start.y - g.position.y
		var db := g.end.y - start.y
		var m := minf(minf(dl, dr), minf(dt, db))
		if m == dl:
			n = Vector2(-1, 0)
		elif m == dr:
			n = Vector2(1, 0)
		elif m == dt:
			n = Vector2(0, -1)
		else:
			n = Vector2(0, 1)
		e = Vector2(clampf(start.x, g.position.x, g.end.x), clampf(start.y, g.position.y, g.end.y))
		if n.x != 0.0:
			e.x = g.position.x if n.x < 0.0 else g.end.x
		else:
			e.y = g.position.y if n.y < 0.0 else g.end.y
	else:
		e = start + d * float(hit["s"])
		n = hit["n"]
		s = hit["s"]
	# Along the face, stay 15 cm in from the corners (the snow lands beside this wall, not around it).
	var k := 0.15
	var f := e
	if n.x != 0.0:
		f.y = clampf(e.y, r.position.y + k, r.end.y - k)
		f.x = (r.position.x if n.x < 0.0 else r.end.x) + n.x * FOOT_OUT
	else:
		f.x = clampf(e.x, r.position.x + k, r.end.x - k)
		f.y = (r.position.y if n.y < 0.0 else r.end.y) + n.y * FOOT_OUT
	return {"face": e, "foot": f, "s": s, "normal": n}


## First crossing of the ray p + s·d (s ≥ 0) into rect r from outside: {s, n (outward normal)} or {}.
static func _ray_rect(p: Vector2, d: Vector2, r: Rect2) -> Dictionary:
	if r.has_point(p):
		return {}
	var tmin := -INF
	var tmax := INF
	var n := Vector2.ZERO
	for ax in range(2):
		var o: float = p[ax]
		var v: float = d[ax]
		var lo: float = r.position[ax]
		var hi: float = r.end[ax]
		if absf(v) < 1e-9:
			if o < lo or o > hi:
				return {}
			continue
		var t1 := (lo - o) / v
		var t2 := (hi - o) / v
		var nn := Vector2.ZERO
		nn[ax] = -1.0
		if t1 > t2:
			var tt := t1
			t1 = t2
			t2 = tt
			nn[ax] = 1.0
		if t1 > tmin:
			tmin = t1
			n = nn
		tmax = minf(tmax, t2)
	if tmin > tmax or tmin < 0.0:
		return {}
	return {"s": tmin, "n": n}


## 2D segment vs rect: {t} of the first point of a→b inside r (0 if a is inside), or {}.
static func _seg_rect(a: Vector2, b: Vector2, r: Rect2) -> Dictionary:
	if r.has_point(a):
		return {"t": 0.0}
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for ax in range(2):
		var o: float = a[ax]
		var v: float = d[ax]
		var lo: float = r.position[ax]
		var hi: float = r.end[ax]
		if absf(v) < 1e-9:
			if o < lo or o > hi:
				return {}
			continue
		var u1 := (lo - o) / v
		var u2 := (hi - o) / v
		if u1 > u2:
			var uu := u1
			u1 = u2
			u2 = uu
		t0 = maxf(t0, u1)
		t1 = minf(t1, u2)
		if t0 > t1:
			return {}
	return {"t": t0}


## 3D segment a→b vs the box footprint r × [-1, top]: the parameter (0..1) where it first is inside
## (0 when a already is), or -1.
static func _seg_box(a: Vector3, b: Vector3, r: Rect2, top: float) -> float:
	var lo := Vector3(r.position.x, -1.0, r.position.y)
	var hi := Vector3(r.end.x, top, r.end.y)
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for ax in range(3):
		var o: float = a[ax]
		var v: float = d[ax]
		if absf(v) < 1e-9:
			if o < lo[ax] or o > hi[ax]:
				return -1.0
			continue
		var u1: float = (lo[ax] - o) / v
		var u2: float = (hi[ax] - o) / v
		if u1 > u2:
			var uu := u1
			u1 = u2
			u2 = uu
		t0 = maxf(t0, u1)
		t1 = minf(t1, u2)
		if t0 > t1:
			return -1.0
	return t0
