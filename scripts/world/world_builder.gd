class_name WorldBuilder
extends RefCounted
## Builds the static neighborhood procedurally from Layout. Returns references to key objects.

var root: Node3D
var refs: Dictionary = {}
var rng := RandomNumberGenerator.new()


func build(parent: Node3D, minimal := false) -> Dictionary:
	Layout.ensure()
	rng.seed = 2024
	root = Node3D.new()
	root.name = "World"
	parent.add_child(root)
	refs = {"houses": {}, "roof_snows": [], "mailboxes": {}, "streetlights": [], "tree_points": []}
	_ground()
	_pavement()
	_houses(minimal)
	_vegetation()
	_fences()
	_streetlights()
	_commercial()
	_boundary()
	return refs


# -----------------------------------------------------------------------------
func _ground() -> void:
	var kit := MeshKit.new()
	var lawn := Mats.lawn()
	kit.quad(lawn, Vector3(-4, -0.02, -4), Vector3(Layout.MAP_W + 4, -0.02, -4), Vector3(Layout.MAP_W + 4, -0.02, Layout.MAP_D + 4), Vector3(-4, -0.02, Layout.MAP_D + 4), Vector3.UP)
	kit.instance(root, "Lawn", false)
	# Ground collision (flat world at y = 0).
	var sb := StaticBody3D.new()
	sb.name = "GroundBody"
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(Layout.MAP_W + 200, 1.0, Layout.MAP_D + 200)
	cs.shape = box
	sb.add_child(cs)
	root.add_child(sb)
	sb.position = Vector3(Layout.MAP_W * 0.5, -0.5, Layout.MAP_D * 0.5)


func _flat(kit: MeshKit, mat: Material, r: Rect2, y: float) -> void:
	kit.quad(mat, Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y), Vector3.UP)


func _pavement() -> void:
	var kit := MeshKit.new()
	var asphalt := Mats.asphalt()
	var conc := Mats.concrete()
	var drive := Mats.driveway()
	var lot_m := Mats.lot_asphalt()
	for r in Layout.roads:
		_flat(kit, asphalt, r["rect"], 0.0)
	for s in Layout.sidewalks:
		_flat(kit, conc, s, 0.006)
	for a in Layout.big_areas:
		_flat(kit, lot_m, a["rect"], 0.004)
		_flat(kit, lot_m, a["apron"], 0.004)
	var paint := Mats.std(Color(0.85, 0.85, 0.8), 0.6)
	var yellow := Mats.std(Color(0.9, 0.75, 0.15), 0.6)
	# Parking stall lines in the school, store and church lots.
	for a in Layout.big_areas:
		if a["id"] == "dump_lot":
			continue
		var r: Rect2 = a["rect"]
		var x := r.position.x + 3.0
		while x < r.end.x - 2.0:
			_flat(kit, paint, Rect2(x, r.position.y + 1.0, 0.12, 5.0), 0.009)
			_flat(kit, paint, Rect2(x, r.end.y - 6.0, 0.12, 5.0), 0.009)
			x += 3.0
	# Store pickup pad.
	var pad := Layout.store_pad
	for e in [Rect2(pad.position.x, pad.position.y, pad.size.x, 0.15), Rect2(pad.position.x, pad.end.y - 0.15, pad.size.x, 0.15),
			Rect2(pad.position.x, pad.position.y, 0.15, pad.size.y), Rect2(pad.end.x - 0.15, pad.position.y, 0.15, pad.size.y)]:
		_flat(kit, yellow, e, 0.012)
	for bay in Layout.store_bays:
		var b: Rect2 = bay
		_flat(kit, yellow, Rect2(b.position.x, b.position.y, 0.15, b.size.y), 0.012)
		_flat(kit, yellow, Rect2(b.end.x - 0.15, b.position.y, 0.15, b.size.y), 0.012)
	for lot in Layout.lots:
		if lot["vacant"]:
			continue
		var hi := Layout.house_info(lot)
		_flat(kit, drive, hi["driveway"], 0.008)
		_flat(kit, conc, hi["walkway"], 0.007)
	# Sidewalk crossings over driveways stay concrete (painted after driveways).
	for s in Layout.sidewalks:
		for lot in Layout.lots:
			if lot["vacant"]:
				continue
			var d: Rect2 = Layout.house_info(lot)["driveway"]
			var inter := d.intersection(s)
			if inter.has_area():
				_flat(kit, conc, inter, 0.01)
	# Centre-line dashes.
	for r in Layout.roads:
		var rc: Rect2 = r["rect"]
		if r["horizontal"]:
			var x2 := rc.position.x + 1.0
			while x2 < rc.end.x:
				if x2 < 90.0 or x2 > 102.0:
					_flat(kit, yellow, Rect2(x2, rc.get_center().y - 0.06, 2.0, 0.12), 0.003)
				x2 += 5.0
		else:
			var z2 := rc.position.y + 1.0
			while z2 < rc.end.y:
				if not ((z2 > 77 and z2 < 89) or (z2 > 147 and z2 < 159)):
					_flat(kit, yellow, Rect2(rc.get_center().x - 0.06, z2, 0.12, 2.0), 0.003)
				z2 += 5.0
	# Curbs: low concrete strips along road edges (visual only).
	var curb := Mats.prop(Color(0.6, 0.6, 0.62), 0.5)
	for r in Layout.roads:
		var rc2: Rect2 = r["rect"]
		if r["horizontal"]:
			for z in [rc2.position.y, rc2.end.y]:
				var segs := _curb_segments(rc2.position.x, rc2.end.x, true)
				for sgm in segs:
					kit.box(curb, Transform3D(Basis(), Vector3((sgm[0] + sgm[1]) * 0.5, 0.04, z)), Vector3(sgm[1] - sgm[0], 0.08, 0.16))
		else:
			for x in [rc2.position.x, rc2.end.x]:
				var segs2 := _curb_segments(rc2.position.y, rc2.end.y, false)
				for sgm in segs2:
					kit.box(curb, Transform3D(Basis(), Vector3(x, 0.04, (sgm[0] + sgm[1]) * 0.5)), Vector3(0.16, 0.08, sgm[1] - sgm[0]))
	var mi := kit.instance(root, "Pavement", false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _curb_segments(a: float, b: float, horizontal: bool) -> Array:
	# Gaps for the crossing street.
	if horizontal:
		return [[a, 92.0], [100.0, b]]
	return [[a, 79.0], [87.0, 149.0], [157.0, b]]


# -----------------------------------------------------------------------------
func _houses(minimal: bool) -> void:
	var houses_node := Node3D.new()
	houses_node.name = "Houses"
	root.add_child(houses_node)
	var mailbox_mesh := Props.mailbox()
	var shrub_xf := []
	for lot in Layout.lots:
		if lot["vacant"]:
			continue
		var hollow: bool = lot["is_player"] or lot["is_neighbor"]
		var h := HouseBuilder.build(lot, houses_node, hollow)
		refs["houses"][lot["index"]] = h
		refs["roof_snows"].append(h["roof_snow"])
		if hollow:
			var body: StaticBody3D = h["root"].get_node("Collision")
			HouseBuilder.hollow_colliders(body, h["L"], h["wall_h"], lot["setback"], lot["setback"] + HouseBuilder.DEPTH)
		var hi := Layout.house_info(lot)
		var mb := MeshInstance3D.new()
		mb.name = "Mailbox_%d" % lot["index"]
		mb.mesh = mailbox_mesh
		var mp: Vector2 = hi["mailbox"]
		# The mailbox door (model -Z) faces the street (polish 4 §4).
		var mf: Vector2 = hi["mailbox_face"]
		mb.transform = Transform3D(Basis.looking_at(Vector3(mf.x, 0, mf.y), Vector3.UP), Vector3(mp.x, 0, mp.y))
		houses_node.add_child(mb)
		refs["mailboxes"][lot["index"]] = mb
		MeshKit.collider_box(houses_node, Vector3(mp.x, 0.7, mp.y), Vector3(0.3, 1.4, 0.3))
		# Shrubs either side of the porch.
		for u in [-3.6, 0.6]:
			var sp := Layout.lot_to_world(lot, Layout.gu(lot, u), lot["setback"] - 0.7)
			shrub_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.15)), Vector3(sp.x, 0, sp.y)))
	if not shrub_xf.is_empty():
		Props.multimesh(Props.shrub(), shrub_xf, root, "Shrubs", true)


# -----------------------------------------------------------------------------
func _vegetation() -> void:
	var ever := []
	var bare := []
	var tree_points := []
	for lot in Layout.lots:
		var r: Rect2 = lot["rect"]
		var trng := RandomNumberGenerator.new()
		trng.seed = lot["tree_seed"]
		var count: int = lot["trees"]
		if lot["vacant"]:
			count = 2
		var hi := Layout.house_info(lot) if not lot["vacant"] else {}
		for k in range(count):
			var placed := false
			for attempt in range(12):
				var u := trng.randf_range(-12.5, 12.5)
				var v := trng.randf_range(2.5, 26.0)
				var p := Layout.lot_to_world(lot, u, v)
				if not hi.is_empty():
					var bad := false
					for key in ["body", "garage", "driveway", "walkway", "porch", "stairs"]:
						if (hi[key] as Rect2).grow(2.2).has_point(p):
							bad = true
					if bad:
						continue
				if lot["is_player"] and p.distance_to(Layout.house_info(lot)["truck_spot"]) < 6.0:
					continue
				var xf := Transform3D(Basis(Vector3.UP, trng.randf() * TAU).scaled(Vector3.ONE * trng.randf_range(0.85, 1.25)), Vector3(p.x, 0, p.y))
				if trng.randf() < 0.7:
					ever.append(xf)
				else:
					bare.append(xf)
				tree_points.append(p)
				placed = true
				break
	# Bare trees on boulevards, evergreens around commercial lots and along the map edges.
	var x := 10.0
	while x < Layout.MAP_W - 6:
		if absf(x - 96) > 10:
			for z in [77.9, 88.1, 147.9, 158.1]:
				if rng.randf() < 0.35:
					bare.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.1)), Vector3(x + rng.randf_range(-2, 2), 0, z)))
					tree_points.append(Vector2(x, z))
		x += 14.0
	for i in range(26):
		var p := Vector2(rng.randf_range(2, Layout.MAP_W - 2), rng.randf_range(0.5, 3.5))
		ever.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.0, 1.5)), Vector3(p.x, 0, p.y)))
	for i in range(22):
		var p2 := Vector2(rng.randf_range(2, Layout.MAP_W - 2), rng.randf_range(Layout.MAP_D - 2.5, Layout.MAP_D - 0.5))
		if absf(p2.x - 96) < 8:
			continue
		ever.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.0, 1.5)), Vector3(p2.x, 0, p2.y)))
	for i in range(30):
		var z3 := rng.randf_range(4, Layout.MAP_D - 4)
		for xx in [rng.randf_range(0.5, 2.5), rng.randf_range(Layout.MAP_W - 2.5, Layout.MAP_W - 0.5)]:
			ever.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.0, 1.5)), Vector3(xx, 0, z3)))
	Props.multimesh(Props.evergreen(), ever, root, "Evergreens", true)
	Props.multimesh(Props.bare_tree(), bare, root, "BareTrees", true)
	# Trunk colliders.
	var trunks := StaticBody3D.new()
	trunks.name = "TreeTrunks"
	root.add_child(trunks)
	for xf in ever + bare:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.35
		cyl.height = 3.0
		cs.shape = cyl
		trunks.add_child(cs)
		cs.position = (xf as Transform3D).origin + Vector3(0, 1.5, 0)
	refs["tree_points"] = tree_points


func _fences() -> void:
	var xfs := []
	var body := StaticBody3D.new()
	body.name = "Fences"
	root.add_child(body)
	for lot in Layout.lots:
		if lot["vacant"]:
			continue
		var sb: float = lot["setback"]
		# Side fences from the back of the house to the back of the lot, on both sides.
		for u in [-13.9, 13.9]:
			_fence_run(xfs, body, Layout.lot_to_world(lot, u, sb + 4.0), Layout.lot_to_world(lot, u, 27.8))
		_fence_run(xfs, body, Layout.lot_to_world(lot, -13.9, 27.8), Layout.lot_to_world(lot, 13.9, 27.8))
	Props.multimesh(Props.fence_panel(), xfs, root, "FencePanels", true)


func _fence_run(xfs: Array, body: StaticBody3D, a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var n := maxi(1, int(round(length / 2.4)))
	var dir := (b - a) / length
	var yaw := atan2(-dir.y, dir.x)
	for k in range(n):
		var c := a + dir * (2.4 * (k + 0.5))
		xfs.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, 0, c.y)))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, 1.8, 0.2)
	cs.shape = box
	body.add_child(cs)
	var mid := (a + b) * 0.5
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0.9, mid.y))


## Lamp posts go every 26 m along the street edges, but never on a driveway apron, a walkway or
## a mailbox (polish 2 §6: one used to stand in the middle of the player's driveway entrance).
func _lamp_spot_clear(p: Vector2) -> bool:
	for lot in Layout.lots:
		if lot.get("vacant", false):
			continue
		var hi := Layout.house_info(lot)
		if (hi["driveway"] as Rect2).grow(0.9).has_point(p):
			return false
		var w: Rect2 = hi["walkway"]
		var conn := w.merge(Rect2(w.position.x, w.position.y - 3.2, w.size.x, w.size.y + 6.4)) if absf(w.size.x) < absf(w.size.y) else w
		if conn.grow(0.7).has_point(p):
			return false
		if (hi["mailbox"] as Vector2).distance_to(p) < 1.4:
			return false
	return true


func _lamp_spot(p: Vector2, along: Vector2) -> Vector2:
	for off in [0.0, 3.0, -3.0, 5.5, -5.5, 8.0, -8.0]:
		var q := p + along * float(off)
		if _lamp_spot_clear(q):
			return q
	return p


func _streetlights() -> void:
	var xfs := []
	var pts := []
	for r in Layout.roads:
		var rc: Rect2 = r["rect"]
		if r["horizontal"]:
			var x := 12.0
			var side := 0
			while x < Layout.MAP_W - 4:
				if absf(x - 96) > 9:
					var z := rc.position.y - 1.0 if side % 2 == 0 else rc.end.y + 1.0
					var yaw := 0.0 if side % 2 == 0 else PI
					var lp := _lamp_spot(Vector2(x, z), Vector2(1, 0))
					xfs.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(lp.x, 0, lp.y)))
					pts.append(Vector3(lp.x, 5.8, lp.y + (1.45 if side % 2 == 0 else -1.45)))
				x += 26.0
				side += 1
		else:
			var z2 := 10.0
			var side2 := 0
			while z2 < Layout.MAP_D - 4:
				if absf(z2 - 83) > 9 and absf(z2 - 153) > 9:
					var x2 := rc.position.x - 1.0 if side2 % 2 == 0 else rc.end.x + 1.0
					var yaw2 := -PI * 0.5 if side2 % 2 == 0 else PI * 0.5
					var lp2 := _lamp_spot(Vector2(x2, z2), Vector2(0, 1))
					xfs.append(Transform3D(Basis(Vector3.UP, yaw2), Vector3(lp2.x, 0, lp2.y)))
					pts.append(Vector3(lp2.x + (1.45 if side2 % 2 == 0 else -1.45), 5.8, lp2.y))
				z2 += 26.0
				side2 += 1
	Props.multimesh(Props.streetlight(), xfs, root, "Streetlights", true)
	var body := StaticBody3D.new()
	body.name = "LightPoles"
	root.add_child(body)
	for xf in xfs:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.16
		cyl.height = 6.0
		cs.shape = cyl
		body.add_child(cs)
		cs.position = (xf as Transform3D).origin + Vector3(0, 3, 0)
	refs["streetlights"] = pts
	_lamp_poles.clear()
	for xf in xfs:
		_lamp_poles.append(Vector2((xf as Transform3D).origin.x, (xf as Transform3D).origin.z))


var _lamp_poles: Array = []


## Where the street lamp poles stand (tests: none on a driveway apron, walkway or mailbox).
func lamp_poles() -> Array:
	return _lamp_poles


# -----------------------------------------------------------------------------
func _commercial() -> void:
	var kit := MeshKit.new()
	var trim := Mats.trim()
	var body := StaticBody3D.new()
	body.name = "Commercial"
	root.add_child(body)
	for b in Layout.buildings:
		var r: Rect2 = b["rect"]
		var h: float = b["height"]
		var c := Vector3(r.get_center().x, h * 0.5, r.get_center().y)
		var col := Color(0.62, 0.36, 0.3) if b["kind"] == "school" else (Color(0.7, 0.68, 0.62) if b["kind"] == "church" else Color(0.48, 0.5, 0.53))
		var wall := Mats.siding(col) if b["kind"] != "school" else Mats.prop(col, 0.4)
		kit.box(wall, Transform3D(Basis(), c), Vector3(r.size.x, h, r.size.y))
		kit.box(trim, Transform3D(Basis(), Vector3(c.x, h + 0.15, c.z)), Vector3(r.size.x + 0.4, 0.3, r.size.y + 0.4))
		HouseBuilder._add_box_shape(body, Transform3D(), c, Vector3(r.size.x, h, r.size.y))
		var front_z := r.end.y
		var lit := Mats.window_lit(Vector2(3, 2), 1.0)
		match b["kind"]:
			"store":
				# Big shop windows, entrance, canopy and signage.
				for k in range(4):
					var wx := r.position.x + 3.0 + k * 6.5
					kit.box(trim, Transform3D(Basis(), Vector3(wx + 1.6, 1.9, front_z + 0.04)), Vector3(4.4, 2.6, 0.1))
					kit.box(lit, Transform3D(Basis(), Vector3(wx + 1.6, 1.9, front_z + 0.1)), Vector3(4.0, 2.2, 0.02))
				kit.box(Mats.prop(Color(0.75, 0.15, 0.12), 1.0), Transform3D(Basis(), Vector3(c.x, 4.2, front_z + 1.5)), Vector3(r.size.x - 2, 0.25, 3.0))
				kit.pillow(Mats.snow_soft(), Transform3D(Basis(), Vector3(c.x, 4.33, front_z + 1.5)), r.size.x - 2, 3.0, 0.22, 0.06, 10, 3.0)
				kit.box(Mats.std(Color(0.12, 0.2, 0.32), 0.5), Transform3D(Basis(), Vector3(c.x, 5.4, front_z + 0.12)), Vector3(16, 1.4, 0.15))
				_label(Vector3(c.x, 5.42, front_z + 0.22), "NORTHERN SUPPLY CO.", 96, Color(1, 0.92, 0.7))
				_label(Vector3(r.position.x + 1.6, 2.5, front_z + 0.2), "OPEN\n7:00 – 21:00", 40, Color(1, 1, 0.9))
				_label(Vector3(Layout.store_pad.get_center().x, 2.2, Layout.store_pad.position.y - 0.2), "ORDER PICKUP", 44, Color(1, 0.85, 0.2))
				var post := Mats.prop(Color(0.25, 0.26, 0.28), 0.5)
				var board := Mats.std(Color(0.12, 0.2, 0.32), 0.5)
				kit.box(post, Transform3D(Basis(), Vector3(Layout.store_pad.get_center().x, 1.0, Layout.store_pad.position.y - 0.3)), Vector3(0.1, 2.0, 0.1))
				# The signs' lettering sits on a board on its post (polish 2 §6: it used to float).
				kit.box(board, Transform3D(Basis(), Vector3(Layout.store_pad.get_center().x, 2.2, Layout.store_pad.position.y - 0.27)), Vector3(2.9, 0.55, 0.06))
				for bi in range(Layout.store_bays.size()):
					var bay: Rect2 = Layout.store_bays[bi]
					_label(Vector3(bay.get_center().x, 1.6, bay.position.y - 0.4), "VEHICLE BAY %d" % (bi + 1), 30, Color(1, 0.85, 0.2))
					kit.box(board, Transform3D(Basis(), Vector3(bay.get_center().x, 1.6, bay.position.y - 0.47)), Vector3(2.2, 0.42, 0.06))
					kit.box(post, Transform3D(Basis(), Vector3(bay.get_center().x, 0.7, bay.position.y - 0.52)), Vector3(0.08, 1.4, 0.08))
			"school":
				for k in range(9):
					var wx2 := r.position.x + 3.0 + k * 4.6
					kit.box(lit, Transform3D(Basis(), Vector3(wx2, 2.8, front_z + 0.03)), Vector3(2.4, 1.6, 0.04))
				_label(Vector3(c.x, 5.2, front_z + 0.1), "MAPLE RIDGE SCHOOL", 80, Color(0.95, 0.95, 0.9))
				kit.cylinder(Mats.metal(), Transform3D(Basis(), Vector3(r.end.x + 4, 0, front_z + 3)), 0.07, 0.05, 9.0, 6, true)
			"church":
				kit.box(wall, Transform3D(Basis(), Vector3(c.x, h + 3.0, front_z - 2.5)), Vector3(3.5, 6.0, 3.5))
				kit.cylinder(Mats.roof(Color(0.25, 0.25, 0.3)), Transform3D(Basis(), Vector3(c.x, h + 6.0, front_z - 2.5)), 2.6, 0.05, 5.0, 4, true)
				for k in range(4):
					var wz := r.position.y + 3 + k * 3.5
					kit.box(Mats.window_lit(Vector2(1, 3), 1.0), Transform3D(Basis(), Vector3(r.end.x + 0.03, 3.2, wz)), Vector3(0.04, 3.0, 1.2))
				_label(Vector3(c.x, 3.0, front_z + 0.1), "ST. ANDREW'S", 64, Color(0.95, 0.95, 0.9))
		# Roof snow (flat roofs carry a pillow).
		kit.pillow(Mats.snow_soft(), Transform3D(Basis(), Vector3(c.x, h + 0.3, c.z)), r.size.x + 0.2, r.size.y + 0.2, 0.55, 0.15, 12, 4.0)
	# Snow dump sign and barriers.
	var dr := Layout.dump_rect
	_label(Vector3(dr.position.x - 2.0, 2.4, dr.position.y + 3), "MUNICIPAL\nSNOW DUMP", 64, Color(1, 0.85, 0.2))
	kit.box(Mats.prop(Color(0.2, 0.3, 0.55), 0.5), Transform3D(Basis(), Vector3(dr.position.x - 2.0, 2.4, dr.position.y + 2.9)), Vector3(3.0, 1.4, 0.1))
	for k in range(2):
		kit.box(Mats.prop(Color(0.25, 0.26, 0.28), 0.5), Transform3D(Basis(), Vector3(dr.position.x - 3.2 + k * 2.4, 0.9, dr.position.y + 2.9)), Vector3(0.1, 1.8, 0.1))
	var mi := kit.instance(root, "Commercial", true)


func _label(pos: Vector3, text: String, size: int, color: Color, yaw := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.008
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.position = pos
	l.rotation.y = yaw
	l.shaded = false
	l.double_sided = false
	root.add_child(l)
	return l


# -----------------------------------------------------------------------------
func _boundary() -> void:
	# Invisible walls at the map edge.
	var body := StaticBody3D.new()
	body.name = "MapBounds"
	root.add_child(body)
	var w := Layout.MAP_W
	var d := Layout.MAP_D
	for spec in [[Vector3(w * 0.5, 5, -0.5), Vector3(w + 2, 10, 1)], [Vector3(w * 0.5, 5, d + 0.5), Vector3(w + 2, 10, 1)],
			[Vector3(-0.5, 5, d * 0.5), Vector3(1, 10, d + 2)], [Vector3(w + 0.5, 5, d * 0.5), Vector3(1, 10, d + 2)]]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		cs.shape = box
		body.add_child(cs)
		cs.position = spec[0]
	# Snowy fields and forest beyond the map so the horizon is never empty.
	var kit := MeshKit.new()
	var snow := Mats.snow_soft()
	var far := 260.0
	var y := 0.85
	for r in [Rect2(-far, -far, w + far * 2, far), Rect2(-far, d, w + far * 2, far), Rect2(-far, 0, far, d), Rect2(w, 0, far, d)]:
		kit.quad(snow, Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y), Vector3.UP)
	kit.instance(root, "OuterFields", false)
	var xfs := []
	var frng := RandomNumberGenerator.new()
	frng.seed = 77
	for i in range(420):
		var side := i % 4
		var t := frng.randf()
		var dist := frng.randf_range(6, 60)
		var p := Vector2.ZERO
		match side:
			0: p = Vector2(-20 + t * (w + 40), -dist)
			1: p = Vector2(-20 + t * (w + 40), d + dist)
			2: p = Vector2(-dist, t * d)
			3: p = Vector2(w + dist, t * d)
		xfs.append(Transform3D(Basis(Vector3.UP, frng.randf() * TAU).scaled(Vector3.ONE * frng.randf_range(1.2, 2.2)), Vector3(p.x, 0.4, p.y)))
	Props.multimesh(Props.evergreen(), xfs, root, "Forest", false)
