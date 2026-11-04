class_name HouseBuilder
extends RefCounted
## Builds a house for a lot. Canonical frame: +X along the street (garage side), +Y up,
## +Z inward (away from the street). The lot transform maps this frame to the world.

const BODY_X0 := -9.25
const BODY_X1 := 2.75
const GAR_X0 := 2.75
const GAR_X1 := 9.25
const DEPTH := 9.0
const WALL_T := 0.22


static func lot_transform(lot: Dictionary) -> Transform3D:
	var right: Vector2 = lot["right"]
	var inward: Vector2 = lot["inward"]
	var sx := 1.0 if lot["garage_right"] else -1.0
	var bx := Vector3(right.x, 0, right.y) * sx
	var bz := Vector3(inward.x, 0, inward.y)
	return Transform3D(Basis(bx, Vector3.UP, bz), Vector3(lot["center_x"], 0, lot["front_z"]))


## Returns {root: Node3D, roof_snow: RoofSnow, door_xf: Transform3D, interior_root}
static func build(lot: Dictionary, parent: Node3D, hollow: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "House_%d" % lot["index"]
	parent.add_child(root)
	var L := lot_transform(lot)
	var sb: float = lot["setback"]
	var two := int(lot["style"]) == 1 and not hollow
	var wall_h := 5.6 if two else 3.0
	var rise := 2.0 if two else 2.3
	var kit := MeshKit.new()
	var siding := Mats.siding(lot["siding"])
	var trim := Mats.trim()
	var roofm := Mats.roof(lot["roof_color"])
	var stone := Mats.prop(Color(0.42, 0.42, 0.44), 0.6)
	var door_m := Mats.std(lot["door_color"], 0.55)
	var timber := Mats.wood(Color(0.62, 0.4, 0.22), 0.6)
	var gdoor := Mats.std(Color(0.36, 0.37, 0.4), 0.6)
	var lit := Mats.window_lit(Vector2(3, 2), 1.0)
	var small_lit := Mats.window_lit(Vector2(2, 2), 1.0)
	var garage_win := Mats.window_lit(Vector2(1, 1), 1.0)
	var lamp := Mats.emissive(Color(1.0, 0.78, 0.45), 2.2)

	var z0 := sb
	var z1 := sb + DEPTH
	var xc := (BODY_X0 + BODY_X1) * 0.5
	var bw := BODY_X1 - BODY_X0
	# ---------------- Body walls ----------------
	if not hollow:
		kit.box(siding, L * Transform3D(Basis(), Vector3(xc, wall_h * 0.5, (z0 + z1) * 0.5)), Vector3(bw, wall_h, DEPTH))
	else:
		_hollow_walls(kit, L, siding, wall_h, z0, z1, lot)
	# Foundation band
	kit.box(stone, L * Transform3D(Basis(), Vector3(xc, 0.25, (z0 + z1) * 0.5)), Vector3(bw + 0.08, 0.5, DEPTH + 0.08))
	# Corner trim boards
	for cx in [BODY_X0, BODY_X1]:
		for cz in [z0, z1]:
			kit.box(trim, L * Transform3D(Basis(), Vector3(cx, wall_h * 0.5, cz)), Vector3(0.16, wall_h, 0.16))
	# ---------------- Garage ----------------
	var gz0 := sb - 0.5
	var gz1 := sb + 7.0
	var gh := 2.9
	var gxc := (GAR_X0 + GAR_X1) * 0.5
	kit.box(siding, L * Transform3D(Basis(), Vector3(gxc, gh * 0.5, (gz0 + gz1) * 0.5)), Vector3(GAR_X1 - GAR_X0, gh, gz1 - gz0))
	kit.box(stone, L * Transform3D(Basis(), Vector3(gxc, 0.15, (gz0 + gz1) * 0.5)), Vector3(GAR_X1 - GAR_X0 + 0.06, 0.3, gz1 - gz0 + 0.06))
	# Garage door with panel lines and a row of lit windows (as in the references)
	var gdx := gxc
	kit.box(trim, L * Transform3D(Basis(), Vector3(gdx, 1.2, gz0 - 0.02)), Vector3(5.5, 2.45, 0.06))
	kit.box(gdoor, L * Transform3D(Basis(), Vector3(gdx, 1.12, gz0 - 0.06)), Vector3(5.1, 2.2, 0.06))
	for k in range(4):
		kit.box(trim, L * Transform3D(Basis(), Vector3(gdx, 0.35 + k * 0.52, gz0 - 0.095)), Vector3(5.1, 0.03, 0.02))
	for k in range(6):
		var wx := gdx - 2.1 + k * 0.84
		kit.box(garage_win, L * Transform3D(Basis(), Vector3(wx, 1.95, gz0 - 0.1)), Vector3(0.62, 0.26, 0.02))
	for cx in [GAR_X0 + 0.08, GAR_X1]:
		kit.box(trim, L * Transform3D(Basis(), Vector3(cx, gh * 0.5, gz0)), Vector3(0.16, gh, 0.16))
	# Wall lanterns (beside the door and the garage)
	var lantern_pts := [Vector3(-0.55, 2.0, z0 - 0.12), Vector3(GAR_X0 + 0.45, 2.0, gz0 - 0.12)]
	for lp in lantern_pts:
		kit.box(trim, L * Transform3D(Basis(), lp + Vector3(0, 0.02, 0.03)), Vector3(0.22, 0.36, 0.16))
		kit.box(lamp, L * Transform3D(Basis(), lp + Vector3(0, 0.0, -0.03)), Vector3(0.15, 0.24, 0.1))
	# ---------------- Windows ----------------
	if not hollow:
		_window(kit, L, Vector3(-6.2, 1.55, z0), Vector2(3.0, 1.45), lit, trim, true)
		_window(kit, L, Vector3(-6.2, 1.6, z1), Vector2(1.6, 1.1), small_lit, trim, false)
		_window(kit, L, Vector3(-2.0, 1.6, z1), Vector2(1.6, 1.1), small_lit, trim, false)
		_side_window(kit, L, Vector3(BODY_X0, 1.6, (z0 + z1) * 0.5), Vector2(1.3, 1.1), small_lit, trim)
		if two:
			_window(kit, L, Vector3(-6.2, 4.3, z0), Vector2(1.6, 1.1), small_lit, trim, true)
			_window(kit, L, Vector3(-2.0, 4.3, z0), Vector2(1.6, 1.1), small_lit, trim, true)
			_window(kit, L, Vector3(-4.0, 4.3, z1), Vector2(1.6, 1.1), small_lit, trim, false)
		# Front door (decorative on closed houses)
		kit.box(trim, L * Transform3D(Basis(), Vector3(-1.5, 1.6, z0 - 0.03)), Vector3(1.22, 2.18, 0.06))
		kit.box(door_m, L * Transform3D(Basis(), Vector3(-1.5, 1.58, z0 - 0.07)), Vector3(1.0, 2.06, 0.06))
		kit.box(small_lit, L * Transform3D(Basis(), Vector3(-1.5, 2.15, z0 - 0.105)), Vector3(0.45, 0.45, 0.02))
		kit.box(Mats.metal(Color(0.75, 0.62, 0.3)), L * Transform3D(Basis(), Vector3(-1.85, 1.5, z0 - 0.12)), Vector3(0.05, 0.12, 0.05))
	# ---------------- Porch, stairs, timber gable ----------------
	var pz0 := sb - 1.8
	kit.box(stone, L * Transform3D(Basis(), Vector3(-1.5, Layout.PORCH_H * 0.5, (pz0 + z0) * 0.5)), Vector3(2.8, Layout.PORCH_H, 1.8))
	kit.box(Mats.prop(Color(0.5, 0.5, 0.52), 1.0), L * Transform3D(Basis(), Vector3(-1.5, Layout.PORCH_H - 0.02, (pz0 + z0) * 0.5)), Vector3(2.9, 0.06, 1.88))
	kit.box(stone, L * Transform3D(Basis(), Vector3(-1.5, Layout.STEP_H * 0.5, sb - 2.1)), Vector3(1.6, Layout.STEP_H, 0.6))
	kit.box(stone, L * Transform3D(Basis(), Vector3(-1.5, Layout.STEP_H, sb - 1.95)), Vector3(1.6, Layout.STEP_H * 2.0, 0.3))
	var post_h := 2.75
	for px in [-2.75, -0.25]:
		kit.box(timber, L * Transform3D(Basis(), Vector3(px, Layout.PORCH_H + post_h * 0.5, pz0 + 0.15)), Vector3(0.2, post_h, 0.2))
		kit.box(stone, L * Transform3D(Basis(), Vector3(px, Layout.PORCH_H + 0.35, pz0 + 0.15)), Vector3(0.34, 0.7, 0.34))
	var ptop := Layout.PORCH_H + post_h
	kit.box(timber, L * Transform3D(Basis(), Vector3(-1.5, ptop + 0.1, pz0 + 0.15)), Vector3(2.9, 0.22, 0.24))
	# Timber truss in the porch gable
	var pr := 1.1
	var gbasis := Basis()
	kit.gable(Mats.siding(lot["siding"]), L * Transform3D(gbasis, Vector3(-1.5, ptop + 0.2, pz0 + 0.12)), 3.0, pr, 0.12)
	for side in [-1.0, 1.0]:
		var ang: float = atan2(pr, 1.5) * side
		kit.box(timber, L * Transform3D(Basis(Vector3(0, 0, 1), ang), Vector3(-1.5 - side * 0.75, ptop + 0.2 + pr * 0.5, pz0 + 0.02)), Vector3(1.85, 0.16, 0.16))
		kit.box(timber, L * Transform3D(Basis(Vector3(0, 0, 1), -ang * 0.9), Vector3(-1.5 - side * 0.55, ptop + 0.55, pz0 + 0.03)), Vector3(0.9, 0.1, 0.12))
	kit.box(timber, L * Transform3D(Basis(), Vector3(-1.5, ptop + 0.2 + pr * 0.45, pz0 + 0.03)), Vector3(0.12, pr * 0.9, 0.12))
	# Porch roof slabs (ridge runs toward the street)
	var prz0 := pz0 - 0.35
	var prz1 := z0 + 0.4
	var pxl := -1.5 - 1.75
	var pxr := -1.5 + 1.75
	var pry := ptop + 0.2
	kit.slab(roofm, L * Vector3(pxl, pry - 0.15, prz0), L * Vector3(-1.5, pry + pr, prz0), L * Vector3(-1.5, pry + pr, prz1), L * Vector3(pxl, pry - 0.15, prz1), 0.12, trim)
	kit.slab(roofm, L * Vector3(-1.5, pry + pr, prz0), L * Vector3(pxr, pry - 0.15, prz0), L * Vector3(pxr, pry - 0.15, prz1), L * Vector3(-1.5, pry + pr, prz1), 0.12, trim)
	# ---------------- Main roof ----------------
	var ov := 0.45
	var ex0 := BODY_X0 - 0.35
	var ex1 := BODY_X1 + 0.1
	var ridge_y := wall_h + rise
	var zm := (z0 + z1) * 0.5
	kit.slab(roofm, L * Vector3(ex0, wall_h - 0.12, z0 - ov), L * Vector3(ex1, wall_h - 0.12, z0 - ov), L * Vector3(ex1, ridge_y, zm), L * Vector3(ex0, ridge_y, zm), 0.16, trim)
	kit.slab(roofm, L * Vector3(ex0, ridge_y, zm), L * Vector3(ex1, ridge_y, zm), L * Vector3(ex1, wall_h - 0.12, z1 + ov), L * Vector3(ex0, wall_h - 0.12, z1 + ov), 0.16, trim)
	# Gable infill on both ends
	for gx in [BODY_X0, BODY_X1]:
		kit.gable(siding, L * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(gx, wall_h, zm)), DEPTH, rise, 0.2)
	# Fascia
	kit.box(trim, L * Transform3D(Basis(), Vector3((ex0 + ex1) * 0.5, wall_h - 0.2, z0 - ov + 0.02)), Vector3(ex1 - ex0, 0.22, 0.06))
	# Garage roof (lower gable, ridge along X)
	var g_rise := 1.5
	var gzm := (gz0 + gz1) * 0.5
	var gex1 := GAR_X1 + 0.35
	kit.slab(roofm, L * Vector3(GAR_X0, gh - 0.1, gz0 - 0.4), L * Vector3(gex1, gh - 0.1, gz0 - 0.4), L * Vector3(gex1, gh + g_rise, gzm), L * Vector3(GAR_X0, gh + g_rise, gzm), 0.14, trim)
	kit.slab(roofm, L * Vector3(GAR_X0, gh + g_rise, gzm), L * Vector3(gex1, gh + g_rise, gzm), L * Vector3(gex1, gh - 0.1, gz1 + 0.4), L * Vector3(GAR_X0, gh - 0.1, gz1 + 0.4), 0.14, trim)
	kit.gable(siding, L * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(GAR_X1, gh, gzm)), gz1 - gz0, g_rise, 0.2)
	kit.box(trim, L * Transform3D(Basis(), Vector3((GAR_X0 + gex1) * 0.5, gh - 0.16, gz0 - 0.38)), Vector3(gex1 - GAR_X0, 0.2, 0.06))
	# Chimney
	var chx := -6.8
	var chz := zm + 1.2
	kit.bevel_box(Mats.prop(Color(0.45, 0.44, 0.45), 1.0), L * Transform3D(Basis(), Vector3(chx, ridge_y - 0.2, chz)), Vector3(0.95, 3.0, 0.95), 0.04)
	kit.box(trim, L * Transform3D(Basis(), Vector3(chx, ridge_y + 1.32, chz)), Vector3(1.1, 0.12, 1.1))
	var mi := kit.instance(root, "HouseMesh", true)
	# ---------------- Colliders ----------------
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	if not hollow:
		_add_box_shape(body, L, Vector3(xc, wall_h * 0.5, zm), Vector3(bw, wall_h, DEPTH))
	_add_box_shape(body, L, Vector3(gxc, gh * 0.5, (gz0 + gz1) * 0.5), Vector3(GAR_X1 - GAR_X0, gh, gz1 - gz0))
	_add_box_shape(body, L, Vector3(-1.5, Layout.PORCH_H * 0.5, (pz0 + z0) * 0.5), Vector3(2.8, Layout.PORCH_H, 1.8))
	# Stairs as a ramp (smooth climbing), visual steps are separate.
	var ramp_len := 1.1
	var ramp_ang := atan2(Layout.PORCH_H, 0.9)
	var ramp_c := Vector3(-1.5, Layout.PORCH_H * 0.5 - 0.05, pz0 - 0.42)
	var rb := Basis(Vector3(1, 0, 0), -ramp_ang)
	_add_box_shape(body, L, ramp_c, Vector3(1.6, 0.1, ramp_len), rb)
	for px in [-2.75, -0.25]:
		_add_box_shape(body, L, Vector3(px, Layout.PORCH_H + 1.4, pz0 + 0.15), Vector3(0.3, 2.8, 0.3))
	# ---------------- Roof snow ----------------
	var rs := RoofSnow.new()
	rs.name = "RoofSnow"
	root.add_child(rs)
	var planes := []
	planes.append([L * Vector3(ex0, wall_h - 0.12, z0 - ov), L * Vector3(ex1, wall_h - 0.12, z0 - ov), L * Vector3(ex1, ridge_y, zm), L * Vector3(ex0, ridge_y, zm)])
	planes.append([L * Vector3(ex1, wall_h - 0.12, z1 + ov), L * Vector3(ex0, wall_h - 0.12, z1 + ov), L * Vector3(ex0, ridge_y, zm), L * Vector3(ex1, ridge_y, zm)])
	# The garage's and the porch's snow stops at the house wall (5th entry: which end meets it), and
	# the porch's starts at the wall's face, not where its roof slab ends inside the wall.
	planes.append([L * Vector3(GAR_X0, gh - 0.1, gz0 - 0.4), L * Vector3(gex1, gh - 0.1, gz0 - 0.4), L * Vector3(gex1, gh + g_rise, gzm), L * Vector3(GAR_X0, gh + g_rise, gzm), 0])
	planes.append([L * Vector3(gex1, gh - 0.1, gz1 + 0.4), L * Vector3(GAR_X0, gh - 0.1, gz1 + 0.4), L * Vector3(GAR_X0, gh + g_rise, gzm), L * Vector3(gex1, gh + g_rise, gzm), 1])
	planes.append([L * Vector3(pxl, pry - 0.15, z0), L * Vector3(pxl, pry - 0.15, prz0), L * Vector3(-1.5, pry + pr, prz0), L * Vector3(-1.5, pry + pr, z0), 0])
	planes.append([L * Vector3(pxr, pry - 0.15, prz0), L * Vector3(pxr, pry - 0.15, z0), L * Vector3(-1.5, pry + pr, z0), L * Vector3(-1.5, pry + pr, prz0), 1])
	rs.setup(planes, lot["index"])
	# Roof catch volume: thrown snow that hits this roof joins its snow layer.
	var catcher := Area3D.new()
	catcher.name = "RoofCatcher"
	catcher.collision_layer = 1 << 6
	catcher.collision_mask = 0
	catcher.set_meta("roof_snow", rs)
	root.add_child(catcher)
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(bw + 0.8, rise + 0.8, DEPTH + 1.0)
	rcs.shape = rbox
	catcher.add_child(rcs)
	rcs.global_transform = L * Transform3D(Basis(), Vector3(xc, wall_h + rise * 0.5, zm))
	var gcs := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(GAR_X1 - GAR_X0 + 0.6, g_rise + 0.6, gz1 - gz0 + 0.8)
	gcs.shape = gbox
	catcher.add_child(gcs)
	gcs.global_transform = L * Transform3D(Basis(), Vector3(gxc, gh + g_rise * 0.5, gzm))
	var out := {"root": root, "roof_snow": rs, "L": L, "wall_h": wall_h, "mesh": mi}
	if hollow:
		out["door_xf"] = L * Transform3D(Basis(), Vector3(-1.5, Layout.PORCH_H, z0))
	return out


static func _add_box_shape(body: StaticBody3D, L: Transform3D, center: Vector3, size: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	# Godot shapes do not support mirrored transforms: re-orthonormalise to a proper rotation.
	var t := L * Transform3D(basis, center)
	var b := t.basis
	var x := b.x.normalized()
	var y := b.y.normalized()
	var z := x.cross(y).normalized()
	cs.global_transform = Transform3D(Basis(x, y, z), t.origin)


static func _window(kit: MeshKit, L: Transform3D, c: Vector3, size: Vector2, pane: Material, trim: Material, front: bool) -> void:
	var dz := -1.0 if front else 1.0
	kit.box(trim, L * Transform3D(Basis(), c + Vector3(0, 0, dz * 0.03)), Vector3(size.x + 0.24, size.y + 0.24, 0.08))
	kit.box(pane, L * Transform3D(Basis(), c + Vector3(0, 0, dz * 0.08)), Vector3(size.x, size.y, 0.02))
	kit.box(Mats.prop(Color(0.85, 0.85, 0.86), 1.0), L * Transform3D(Basis(), c + Vector3(0, -size.y * 0.5 - 0.12, dz * 0.1)), Vector3(size.x + 0.4, 0.07, 0.2))


static func _side_window(kit: MeshKit, L: Transform3D, c: Vector3, size: Vector2, pane: Material, trim: Material) -> void:
	var dx := -1.0 if c.x < 0 else 1.0
	kit.box(trim, L * Transform3D(Basis(), c + Vector3(dx * 0.03, 0, 0)), Vector3(0.08, size.y + 0.24, size.x + 0.24))
	kit.box(pane, L * Transform3D(Basis(Vector3.UP, PI * 0.5), c + Vector3(dx * 0.08, 0, 0)), Vector3(size.x, size.y, 0.02))


## Hollow body walls for houses with interiors: openings for the door and windows.
static func _hollow_walls(kit: MeshKit, L: Transform3D, siding: Material, wall_h: float, z0: float, z1: float, _lot: Dictionary) -> void:
	# Polish 5 §3: the interior walls are finished — painted drywall, wallpaper in the bedroom (the
	# same average colour as the plain paint they had: Color(0.86, 0.8, 0.7), roughness 0.9).
	var mid := L * Vector3((BODY_X0 + BODY_X1) * 0.5, 0, (z0 + z1) * 0.5)
	var paint := Mats.interior_wall(Vector2(mid.x, mid.z), _world_rect(L, BODY_X0, -2.8, z0 + 5.0, z1))
	var t := WALL_T
	var fy := Layout.PORCH_H
	# Front wall (z = z0) openings: big window x[-7.7,-4.7] y[0.95,2.4], door x[-2.05,-0.95] y[fy, fy+2.1]
	var front_open := [[-7.7, -4.7, 0.95, 2.4], [-2.05, -0.95, fy, fy + 2.1]]
	_wall_x(kit, L, siding, paint, BODY_X0, BODY_X1, z0, t, wall_h, front_open, true)
	# Back wall (z = z1): bedroom window and kitchen window
	var back_open := [[-7.0, -5.6, 1.2, 2.3], [-1.2, 0.2, 1.2, 2.3]]
	_wall_x(kit, L, siding, paint, BODY_X0, BODY_X1, z1, t, wall_h, back_open, false)
	# Side walls
	_wall_z(kit, L, siding, paint, z0, z1, BODY_X0, t, wall_h, [[z0 + 5.6, z0 + 7.0, 1.2, 2.3]], true)
	_wall_z(kit, L, siding, paint, z0, z1, BODY_X1, t, wall_h, [], false)
	# Window glass and frames
	var glass := Mats.glass_clear()
	var trim := Mats.trim()
	for o in front_open:
		if o[2] > 0.9 and o[0] < -3.0:
			var c := Vector3((o[0] + o[1]) * 0.5, (o[2] + o[3]) * 0.5, z0)
			kit.box(glass, L * Transform3D(Basis(), c), Vector3(o[1] - o[0], o[3] - o[2], 0.03))
			_frame(kit, L, trim, o, z0, true)
	for o in back_open:
		var c2 := Vector3((o[0] + o[1]) * 0.5, (o[2] + o[3]) * 0.5, z1)
		kit.box(glass, L * Transform3D(Basis(), c2), Vector3(o[1] - o[0], o[3] - o[2], 0.03))
		_frame(kit, L, trim, o, z1, false)
	# Door stops (polish 3 §3): strips on the outer half of the door opening that the closed door
	# rests against, so the 4–5 cm gaps around the leaf no longer show the snow outside from
	# indoors. The door swings inward, clear of them.
	var dop: Array = front_open[1]
	var sz := z0 - 0.043
	kit.box(trim, L * Transform3D(Basis(), Vector3(dop[0] + 0.0375, (dop[2] + dop[3]) * 0.5, sz)), Vector3(0.075, dop[3] - dop[2], 0.024))
	kit.box(trim, L * Transform3D(Basis(), Vector3(dop[1] - 0.0375, (dop[2] + dop[3]) * 0.5, sz)), Vector3(0.075, dop[3] - dop[2], 0.024))
	kit.box(trim, L * Transform3D(Basis(), Vector3((dop[0] + dop[1]) * 0.5, dop[3] - 0.03, sz)), Vector3(dop[1] - dop[0], 0.06, 0.024))
	var so: Array = [z0 + 5.6, z0 + 7.0, 1.2, 2.3]
	kit.box(glass, L * Transform3D(Basis(), Vector3(BODY_X0, 1.75, (so[0] + so[1]) * 0.5)), Vector3(0.03, 1.1, 1.4))
	# Floor and ceiling
	var floor_m := Mats.wood(Color(0.55, 0.38, 0.24), 0.0)
	kit.box(floor_m, L * Transform3D(Basis(), Vector3((BODY_X0 + BODY_X1) * 0.5, fy - 0.05, (z0 + z1) * 0.5)), Vector3(BODY_X1 - BODY_X0, 0.1, DEPTH))
	kit.box(Mats.std(Color(0.92, 0.9, 0.86), 0.95), L * Transform3D(Basis(), Vector3((BODY_X0 + BODY_X1) * 0.5, wall_h + 0.05, (z0 + z1) * 0.5)), Vector3(BODY_X1 - BODY_X0, 0.1, DEPTH))
	# Interior partition between living room (front) and bedroom (back-left), doorway at x[-4.2,-3.2]
	var pz := z0 + 5.0
	_partition(kit, L, paint, BODY_X0 + t, -4.2, pz, wall_h)
	_partition(kit, L, paint, -3.2, -2.8, pz, wall_h)
	kit.box(paint, L * Transform3D(Basis(), Vector3(-3.7, fy + 2.35 + (wall_h - fy - 2.35) * 0.5, pz)), Vector3(1.0, wall_h - fy - 2.35, 0.12))
	# Wall between bedroom and kitchen/office area (x = -2.8, from pz to back)
	kit.box(paint, L * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-2.8, (fy + wall_h) * 0.5, (pz + z1) * 0.5)), Vector3(z1 - pz - t, wall_h - fy, 0.12))
	_interior_finish(kit, L, paint, wall_h, z0, z1)


## Axis-aligned world rect of a house-frame rect (x0..x1, z0..z1).
static func _world_rect(L: Transform3D, xa: float, xb: float, za: float, zb: float) -> Rect2:
	var a := L * Vector3(xa, 0, za)
	var b := L * Vector3(xb, 0, zb)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))


# Polish 5 §3: interior finish of the hollow houses (both enterable houses use this builder).
const IN_FACE := 0.165      # an outer wall's room face, from its line (the inner layer of _wall_x/_wall_z)
const PART_T := 0.06        # half the partitions' thickness (0.12)
const BASE_H := 0.09        # baseboard height above the floor
const BASE_T := 0.016       # baseboard / casing thickness off the wall
const CASE_W := 0.07        # door and window casing width

## Close the two cracks where the bedroom's walls met, and add baseboards and the casings around
## the door and window openings. Visual only: colliders, openings and walls are unchanged.
static func _interior_finish(kit: MeshKit, L: Transform3D, paint: Material, wall_h: float, z0: float, z1: float) -> void:
	var fy := Layout.PORCH_H
	var pz := z0 + 5.0
	var trim := Mats.interior_trim()
	var h := wall_h - fy
	var xl := BODY_X0 + IN_FACE            # room faces of the outer walls
	var xr := BODY_X1 - IN_FACE
	var zf := z0 + IN_FACE
	var zb := z1 - IN_FACE
	var xw := -2.8                          # the bedroom / office wall (0.12 thick)
	# --- The cracks ---
	# 1. The living-room / bedroom partition stopped 5.5 cm short of the outer wall's room face
	#    (it starts at BODY_X0 + WALL_T, the face is at BODY_X0 + 0.165): a floor-to-ceiling slot
	#    between the bedroom and the living room. Filled into the outer wall.
	kit.box(paint, L * Transform3D(Basis(), Vector3((xl - 0.04 + BODY_X0 + WALL_T) * 0.5, fy + h * 0.5, pz)), Vector3(BODY_X0 + WALL_T - xl + 0.04, h, PART_T * 2.0))
	# 2. The bedroom / office wall began 5 cm behind the partition's bedroom face, and the partition
	#    ended at that wall's centre line: a 5 × 12 cm slot through the T where they meet. A post
	#    fills the T from the partition's living-room face to the wall's start.
	kit.box(paint, L * Transform3D(Basis(), Vector3(xw, fy + h * 0.5, (pz - PART_T + pz + WALL_T * 0.5) * 0.5)), Vector3(0.12, h, PART_T + WALL_T * 0.5))
	# --- Baseboards: [axis, fixed coordinate, from, to, facing (+1/-1 along the other axis)] ---
	var door := [-2.05, -0.95]
	var pdoor := [-4.2, -3.2]
	var runs := [
		["x", zf, xl, door[0] - CASE_W, 1.0], ["x", zf, door[1] + CASE_W, xr, 1.0],          # front wall
		["x", zb, xl, xw - 0.06, -1.0], ["x", zb, xw + 0.06, xr, -1.0],                   # back wall
		["z", xl, zf, pz - PART_T, 1.0], ["z", xl, pz + PART_T, zb, 1.0],                 # left wall
		["z", xr, zf, zb, -1.0],                                                          # right wall
		["x", pz - PART_T, xl, pdoor[0] - CASE_W, -1.0], ["x", pz - PART_T, pdoor[1] + CASE_W, xw + 0.06, -1.0],   # partition, living room
		["x", pz + PART_T, xl, pdoor[0] - CASE_W, 1.0], ["x", pz + PART_T, pdoor[1] + CASE_W, xw - 0.06, 1.0],    # partition, bedroom
		["z", xw - 0.06, pz + PART_T, zb, -1.0], ["z", xw + 0.06, pz - PART_T - BASE_T, zb, 1.0],                 # bedroom / office wall
	]
	for r in runs:
		var a: float = minf(r[2], r[3])
		var b: float = maxf(r[2], r[3])
		var off: float = float(r[1]) + float(r[4]) * BASE_T * 0.5
		if r[0] == "x":
			kit.box(trim, L * Transform3D(Basis(), Vector3((a + b) * 0.5, fy + BASE_H * 0.5, off)), Vector3(b - a, BASE_H, BASE_T))
		else:
			kit.box(trim, L * Transform3D(Basis(), Vector3(off, fy + BASE_H * 0.5, (a + b) * 0.5)), Vector3(BASE_T, BASE_H, b - a))
	# --- Casings around the openings, on the room faces: [axis, face, facing, u0, u1, y0, y1, sill] ---
	var opens := [
		["x", zf, 1.0, door[0], door[1], fy, fy + 2.1, false],              # front door
		["x", zf, 1.0, -7.7, -4.7, 0.95, 2.4, true],                       # living-room window
		["x", zb, -1.0, -7.0, -5.6, 1.2, 2.3, true],                       # bedroom window
		["x", zb, -1.0, -1.2, 0.2, 1.2, 2.3, true],                        # kitchen window
		["z", xl, 1.0, z0 + 5.6, z0 + 7.0, 1.2, 2.3, true],                # bedroom side window
		["x", pz - PART_T, -1.0, pdoor[0], pdoor[1], fy, fy + 2.35, false],  # bedroom doorway, both sides
		["x", pz + PART_T, 1.0, pdoor[0], pdoor[1], fy, fy + 2.35, false],
	]
	for o in opens:
		var u0: float = o[3]
		var u1: float = o[4]
		var y0: float = o[5]
		var y1: float = o[6]
		var off2: float = float(o[1]) + float(o[2]) * BASE_T * 0.5
		var pieces := [[u0 - CASE_W * 0.5, (y0 + y1 + CASE_W) * 0.5, CASE_W, y1 - y0 + CASE_W],
			[u1 + CASE_W * 0.5, (y0 + y1 + CASE_W) * 0.5, CASE_W, y1 - y0 + CASE_W],
			[(u0 + u1) * 0.5, y1 + CASE_W * 0.5, u1 - u0 + CASE_W * 2.0, CASE_W]]
		if o[7]:
			# A window's apron under the opening.
			pieces[0] = [u0 - CASE_W * 0.5, (y0 + y1) * 0.5, CASE_W, y1 - y0 + CASE_W * 2.0]
			pieces[1] = [u1 + CASE_W * 0.5, (y0 + y1) * 0.5, CASE_W, y1 - y0 + CASE_W * 2.0]
			pieces.append([(u0 + u1) * 0.5, y0 - CASE_W * 0.5, u1 - u0 + CASE_W * 2.0, CASE_W])
		for pc in pieces:
			if o[0] == "x":
				kit.box(trim, L * Transform3D(Basis(), Vector3(pc[0], pc[1], off2)), Vector3(pc[2], pc[3], BASE_T))
			else:
				kit.box(trim, L * Transform3D(Basis(), Vector3(off2, pc[1], pc[0])), Vector3(BASE_T, pc[3], pc[2]))


static func _frame(kit: MeshKit, L: Transform3D, trim: Material, o: Array, z: float, front: bool) -> void:
	var w: float = o[1] - o[0]
	var h: float = o[3] - o[2]
	var cx: float = (o[0] + o[1]) * 0.5
	var cy: float = (o[2] + o[3]) * 0.5
	var dz := -0.12 if front else 0.12
	kit.box(trim, L * Transform3D(Basis(), Vector3(cx, o[3] + 0.05, z + dz)), Vector3(w + 0.2, 0.1, 0.06))
	kit.box(trim, L * Transform3D(Basis(), Vector3(cx, o[2] - 0.05, z + dz)), Vector3(w + 0.2, 0.1, 0.06))
	kit.box(trim, L * Transform3D(Basis(), Vector3(o[0] - 0.05, cy, z + dz)), Vector3(0.1, h, 0.06))
	kit.box(trim, L * Transform3D(Basis(), Vector3(o[1] + 0.05, cy, z + dz)), Vector3(0.1, h, 0.06))
	kit.box(trim, L * Transform3D(Basis(), Vector3(cx, cy, z)), Vector3(0.05, h, 0.05))
	kit.box(Mats.prop(Color(0.85, 0.85, 0.86), 1.0), L * Transform3D(Basis(), Vector3(cx, o[2] - 0.12, z + dz * 1.4)), Vector3(w + 0.4, 0.07, 0.2))


static func _partition(kit: MeshKit, L: Transform3D, paint: Material, xa: float, xb: float, z: float, wall_h: float) -> void:
	var fy := Layout.PORCH_H
	kit.box(paint, L * Transform3D(Basis(), Vector3((xa + xb) * 0.5, (fy + wall_h) * 0.5, z)), Vector3(absf(xb - xa), wall_h - fy, 0.12))


## Wall along X at depth z with rectangular openings [x0, x1, y0, y1]. Builds siding outside and paint inside.
static func _wall_x(kit: MeshKit, L: Transform3D, outer: Material, inner: Material, xa: float, xb: float, z: float, t: float, h: float, openings: Array, front: bool) -> void:
	var segs := _split_wall(xa, xb, h, openings)
	var dz := t * 0.5 if front else -t * 0.5
	for s in segs:
		var c := Vector3((s[0] + s[1]) * 0.5, (s[2] + s[3]) * 0.5, z + dz * 0.5)
		var size := Vector3(s[1] - s[0], s[3] - s[2], t * 0.5)
		kit.box(outer, L * Transform3D(Basis(), c - Vector3(0, 0, dz * 0.5)), size)
		kit.box(inner, L * Transform3D(Basis(), c + Vector3(0, 0, dz * 0.5)), size)


static func _wall_z(kit: MeshKit, L: Transform3D, outer: Material, inner: Material, za: float, zb: float, x: float, t: float, h: float, openings: Array, left: bool) -> void:
	var segs := _split_wall(za, zb, h, openings)
	var dx := t * 0.5 if left else -t * 0.5
	for s in segs:
		var c := Vector3(x + dx * 0.5, (s[2] + s[3]) * 0.5, (s[0] + s[1]) * 0.5)
		var size := Vector3(t * 0.5, s[3] - s[2], s[1] - s[0])
		kit.box(outer, L * Transform3D(Basis(), c - Vector3(dx * 0.5, 0, 0)), size)
		kit.box(inner, L * Transform3D(Basis(), c + Vector3(dx * 0.5, 0, 0)), size)


## Split a wall rectangle [a,b]x[0,h] into solid pieces around openings (vertical strips).
static func _split_wall(a: float, b: float, h: float, openings: Array) -> Array:
	var segs := []
	var cuts := []
	for o in openings:
		cuts.append(o)
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var x := a
	for o in cuts:
		if o[0] > x:
			segs.append([x, o[0], 0.0, h])
		if o[2] > 0.0:
			segs.append([o[0], o[1], 0.0, o[2]])
		if o[3] < h:
			segs.append([o[0], o[1], o[3], h])
		x = o[1]
	if x < b:
		segs.append([x, b, 0.0, h])
	return segs


## Colliders for the hollow walls (separate so they match the openings).
static func hollow_colliders(body: StaticBody3D, L: Transform3D, wall_h: float, z0: float, z1: float) -> void:
	var t := WALL_T
	var fy := Layout.PORCH_H
	for s in _split_wall(BODY_X0, BODY_X1, wall_h, [[-2.05, -0.95, 0.0, fy + 2.1]]):
		_add_box_shape(body, L, Vector3((s[0] + s[1]) * 0.5, (s[2] + s[3]) * 0.5, z0), Vector3(s[1] - s[0], s[3] - s[2], t))
	_add_box_shape(body, L, Vector3((BODY_X0 + BODY_X1) * 0.5, wall_h * 0.5, z1), Vector3(BODY_X1 - BODY_X0, wall_h, t))
	_add_box_shape(body, L, Vector3(BODY_X0, wall_h * 0.5, (z0 + z1) * 0.5), Vector3(t, wall_h, DEPTH))
	_add_box_shape(body, L, Vector3(BODY_X1, wall_h * 0.5, (z0 + z1) * 0.5), Vector3(t, wall_h, DEPTH))
	_add_box_shape(body, L, Vector3((BODY_X0 + BODY_X1) * 0.5, fy * 0.5 - 0.05, (z0 + z1) * 0.5), Vector3(BODY_X1 - BODY_X0, fy + 0.1, DEPTH))
	_add_box_shape(body, L, Vector3((BODY_X0 + BODY_X1) * 0.5, wall_h + 0.1, (z0 + z1) * 0.5), Vector3(BODY_X1 - BODY_X0, 0.2, DEPTH))
	var pz := z0 + 5.0
	_add_box_shape(body, L, Vector3((BODY_X0 + t + -4.2) * 0.5, wall_h * 0.5, pz), Vector3(absf(-4.2 - BODY_X0 - t), wall_h, 0.14))
	_add_box_shape(body, L, Vector3(-3.0, wall_h * 0.5, pz), Vector3(0.4, wall_h, 0.14))
	_add_box_shape(body, L, Vector3(-2.8, wall_h * 0.5, (pz + z1) * 0.5), Vector3(0.14, wall_h, z1 - pz), Basis())
