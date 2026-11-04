class_name MeshKit
extends RefCounted
## Procedural modelling kit. Accumulates triangles per material into one ArrayMesh with
## one surface per material (keeps draw calls low). All primitives take a Transform3D.
## Triangle winding is fixed automatically from the intended normal (Godot front faces are clockwise).

var _st: Dictionary = {}   # material id -> SurfaceTool
var _mat: Dictionary = {}
var _order: Array = []
var tri_count := 0


func _ensure(mat: Material) -> SurfaceTool:
	var key := mat.get_instance_id()
	var st: SurfaceTool = _st.get(key)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
		_mat[key] = mat
		_order.append(key)
	return st


func is_empty() -> bool:
	return _order.is_empty()


## Add one triangle; flips winding so the face points along `face_n`.
func tri(mat: Material, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, face_n := Vector3.ZERO) -> void:
	var st := _ensure(mat)
	var fn := face_n
	if fn == Vector3.ZERO:
		fn = na + nb + nc
	var cr := (b - a).cross(c - a)
	if cr.dot(fn) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
		var tu := ub
		ub = uc
		uc = tu
	st.set_normal(na)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(nb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(nc)
	st.set_uv(uc)
	st.add_vertex(c)
	tri_count += 1


## Flat quad a-b-c-d (any order around the perimeter), facing normal n.
func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		ua := Vector2(0, 0), ub := Vector2(1, 0), uc := Vector2(1, 1), ud := Vector2(0, 1)) -> void:
	tri(mat, a, b, c, n, n, n, ua, ub, uc, n)
	tri(mat, a, c, d, n, n, n, ua, uc, ud, n)


static func _xn(xf: Transform3D, n: Vector3) -> Vector3:
	return (xf.basis.inverse().transposed() * n).normalized()


func box(mat: Material, xf: Transform3D, size: Vector3, uv_world := false) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var c := n * h
		var eu := u * h
		var ew := w * h
		var p0 := xf * (c - eu - ew)
		var p1 := xf * (c + eu - ew)
		var p2 := xf * (c + eu + ew)
		var p3 := xf * (c - eu + ew)
		var wn := _xn(xf, n)
		var su := (eu.length() * 2.0) if uv_world else 1.0
		var sw := (ew.length() * 2.0) if uv_world else 1.0
		quad(mat, p0, p1, p2, p3, wn, Vector2(0, sw), Vector2(su, sw), Vector2(su, 0), Vector2(0, 0))


## Box with chamfered edges (soft, rounded-looking silhouette).
func bevel_box(mat: Material, xf: Transform3D, size: Vector3, bevel: float) -> void:
	var h := size * 0.5
	bevel = minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.95)
	if bevel <= 0.001:
		box(mat, xf, size)
		return
	var b := bevel
	var P := func(sx: float, sy: float, sz: float, axis: int) -> Vector3:
		if axis == 0:
			return Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
		elif axis == 1:
			return Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
		return Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)
	var S := [-1.0, 1.0]
	# Main faces
	for s in S:
		var nx := _xn(xf, Vector3(s, 0, 0))
		quad(mat, xf * P.call(s, -1, -1, 0), xf * P.call(s, 1, -1, 0), xf * P.call(s, 1, 1, 0), xf * P.call(s, -1, 1, 0), nx)
		var ny := _xn(xf, Vector3(0, s, 0))
		quad(mat, xf * P.call(-1, s, -1, 1), xf * P.call(1, s, -1, 1), xf * P.call(1, s, 1, 1), xf * P.call(-1, s, 1, 1), ny)
		var nz := _xn(xf, Vector3(0, 0, s))
		quad(mat, xf * P.call(-1, -1, s, 2), xf * P.call(1, -1, s, 2), xf * P.call(1, 1, s, 2), xf * P.call(-1, 1, s, 2), nz)
	# Edge bevels
	for s1 in S:
		for s2 in S:
			var nxy := _xn(xf, Vector3(s1, s2, 0).normalized())
			quad(mat, xf * P.call(s1, s2, -1, 0), xf * P.call(s1, s2, 1, 0), xf * P.call(s1, s2, 1, 1), xf * P.call(s1, s2, -1, 1), nxy)
			var nxz := _xn(xf, Vector3(s1, 0, s2).normalized())
			quad(mat, xf * P.call(s1, -1, s2, 0), xf * P.call(s1, 1, s2, 0), xf * P.call(s1, 1, s2, 2), xf * P.call(s1, -1, s2, 2), nxz)
			var nyz := _xn(xf, Vector3(0, s1, s2).normalized())
			quad(mat, xf * P.call(-1, s1, s2, 1), xf * P.call(1, s1, s2, 1), xf * P.call(1, s1, s2, 2), xf * P.call(-1, s1, s2, 2), nyz)
	# Corners
	for sx in S:
		for sy in S:
			for sz in S:
				var nc := _xn(xf, Vector3(sx, sy, sz).normalized())
				tri(mat, xf * P.call(sx, sy, sz, 0), xf * P.call(sx, sy, sz, 1), xf * P.call(sx, sy, sz, 2), nc, nc, nc)


## Cylinder / cone frustum along local +Y, base at y=0.
func cylinder(mat: Material, xf: Transform3D, r_bottom: float, r_top: float, height: float, seg := 12, caps := true) -> void:
	var slope := (r_bottom - r_top) / maxf(height, 0.0001)
	for i in range(seg):
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := _xn(xf, (d0 + Vector3(0, slope, 0)).normalized())
		var n1 := _xn(xf, (d1 + Vector3(0, slope, 0)).normalized())
		var b0 := xf * (d0 * r_bottom)
		var b1 := xf * (d1 * r_bottom)
		var t0 := xf * (d0 * r_top + Vector3(0, height, 0))
		var t1 := xf * (d1 * r_top + Vector3(0, height, 0))
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		var fn := (n0 + n1).normalized()
		tri(mat, b0, b1, t1, n0, n1, n1, Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), fn)
		if r_top > 0.0005:
			tri(mat, b0, t1, t0, n0, n1, n0, Vector2(u0, 1), Vector2(u1, 0), Vector2(u0, 0), fn)
		if caps:
			if r_top > 0.0005:
				var nt := _xn(xf, Vector3.UP)
				tri(mat, xf * Vector3(0, height, 0), t0, t1, nt, nt, nt)
			var nb := _xn(xf, Vector3.DOWN)
			tri(mat, xf * Vector3.ZERO, b0, b1, nb, nb, nb)


## UV sphere (ellipsoid via transform scale) centred at the transform origin.
func sphere(mat: Material, xf: Transform3D, radius: float, rings := 6, seg := 10, hemi := false) -> void:
	@warning_ignore("integer_division")
	var rmax := rings / 2 if hemi else rings
	for r in range(rmax):
		var t0 := PI * r / rings
		var t1 := PI * (r + 1) / rings
		for s in range(seg):
			var p0 := TAU * s / seg
			var p1 := TAU * (s + 1) / seg
			var d00 := Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0))
			var d01 := Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1))
			var d10 := Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0))
			var d11 := Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1))
			var n00 := _xn(xf, d00)
			var n01 := _xn(xf, d01)
			var n10 := _xn(xf, d10)
			var n11 := _xn(xf, d11)
			var fn := (n00 + n01 + n10 + n11).normalized()
			if r > 0:
				tri(mat, xf * (d00 * radius), xf * (d01 * radius), xf * (d11 * radius), n00, n01, n11, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, fn)
			tri(mat, xf * (d00 * radius), xf * (d11 * radius), xf * (d10 * radius), n00, n11, n10, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, fn)
	if hemi:
		var nb := _xn(xf, Vector3.DOWN)
		for s in range(seg):
			var p0 := TAU * s / seg
			var p1 := TAU * (s + 1) / seg
			tri(mat, xf * Vector3.ZERO, xf * (Vector3(cos(p0), 0, sin(p0)) * radius), xf * (Vector3(cos(p1), 0, sin(p1)) * radius), nb, nb, nb)


## Thick sloped slab defined by four top corners (a,b,c,d around the perimeter) and a thickness
## extruded along -normal. Used for roofs.
func slab(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, thickness: float, edge_mat: Material = null) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.y < 0.0:
		n = -n
	var off := -n * thickness
	quad(mat, a, b, c, d, n, Vector2(0, 0), Vector2((b - a).length(), 0), Vector2((b - a).length(), (d - a).length()), Vector2(0, (d - a).length()))
	quad(mat, a + off, b + off, c + off, d + off, -n)
	var em := edge_mat if edge_mat else mat
	var pts := [a, b, c, d]
	var center := (a + b + c + d) * 0.25
	for i in range(4):
		var p := pts[i] as Vector3
		var q := pts[(i + 1) % 4] as Vector3
		var mid := (p + q) * 0.5
		var en := (mid - center)
		en = (en - n * en.dot(n)).normalized()
		quad(em, p, q, q + off, p + off, en)


## Triangular prism wall (gable end) in the local XY plane, extruded along Z by depth.
func gable(mat: Material, xf: Transform3D, width: float, rise: float, depth: float) -> void:
	var hw := width * 0.5
	var hd := depth * 0.5
	for s in [-1.0, 1.0]:
		var n := _xn(xf, Vector3(0, 0, s))
		tri(mat, xf * Vector3(-hw, 0, s * hd), xf * Vector3(hw, 0, s * hd), xf * Vector3(0, rise, s * hd), n, n, n,
			Vector2(0, rise), Vector2(width, rise), Vector2(hw, 0))


## Rounded snow pillow over a rectangle in local XZ (centred), top at local +Y.
## The top bulges up to `thickness` with soft rounded edges that droop by `droop` beyond the edge.
func pillow(mat: Material, xf: Transform3D, sx: float, sz: float, thickness: float, droop := 0.08, res := 8, power := 3.0) -> void:
	if thickness <= 0.004:
		return
	var nx := res
	var nz := maxi(3, int(res * sz / maxf(sx, 0.01)))
	nz = clampi(nz, 3, 24)
	var hx := sx * 0.5 + droop * 0.5
	var hz := sz * 0.5 + droop * 0.5
	var pts := []
	for iz in range(nz + 1):
		var row := []
		for ix in range(nx + 1):
			var u := float(ix) / nx * 2.0 - 1.0
			var v := float(iz) / nz * 2.0 - 1.0
			var e := pow(pow(absf(u), power) + pow(absf(v), power), 1.0 / power)
			var f := sqrt(maxf(0.0, 1.0 - pow(minf(e, 1.0), 2.4)))
			var y := thickness * (0.12 + 0.88 * f) - droop * smoothstep(0.75, 1.0, e)
			if ix == 0 or iz == 0 or ix == nx or iz == nz:
				y = -droop
			row.append(Vector3(u * hx, y, v * hz))
		pts.append(row)
	for iz in range(nz):
		for ix in range(nx):
			var p00: Vector3 = pts[iz][ix]
			var p10: Vector3 = pts[iz][ix + 1]
			var p01: Vector3 = pts[iz + 1][ix]
			var p11: Vector3 = pts[iz + 1][ix + 1]
			var n00 := _grid_normal(pts, ix, iz, nx, nz)
			var n10 := _grid_normal(pts, ix + 1, iz, nx, nz)
			var n01 := _grid_normal(pts, ix, iz + 1, nx, nz)
			var n11 := _grid_normal(pts, ix + 1, iz + 1, nx, nz)
			var w00 := _xn(xf, n00)
			var w10 := _xn(xf, n10)
			var w01 := _xn(xf, n01)
			var w11 := _xn(xf, n11)
			tri(mat, xf * p00, xf * p10, xf * p11, w00, w10, w11, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, _xn(xf, Vector3.UP))
			tri(mat, xf * p00, xf * p11, xf * p01, w00, w11, w01, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, _xn(xf, Vector3.UP))


## Polish 5 §5: flat text in the game's font (the UI's font, ThemeDB.fallback_font, through
## TextMesh's glyph outlines): the glyphs' height (digits and capitals) is `height`, centred on
## xf's origin, reading along xf's +X and facing its +Z. Returns the text's width.
func text(mat: Material, xf: Transform3D, s: String, height: float) -> float:
	var tm := TextMesh.new()
	tm.font = ThemeDB.fallback_font
	tm.font_size = 32
	tm.curve_step = 1.0
	tm.depth = 0.0
	tm.text = s
	var arr := tm.get_mesh_arrays()
	if arr.is_empty():
		return 0.0
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in range(v.size()):
			idx.append(i)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in v:
		lo = lo.min(p)
		hi = hi.max(p)
	var k := height / maxf(hi.y - lo.y, 0.0001)
	var mid := (lo + hi) * 0.5
	var n := _xn(xf, Vector3.BACK)
	for t in range(0, idx.size() - 2, 3):
		if nrm[idx[t]].z < 0.5:
			continue   # only the front face of the glyphs
		var a := xf * Vector3((v[idx[t]].x - mid.x) * k, (v[idx[t]].y - mid.y) * k, 0.0)
		var b := xf * Vector3((v[idx[t + 1]].x - mid.x) * k, (v[idx[t + 1]].y - mid.y) * k, 0.0)
		var c := xf * Vector3((v[idx[t + 2]].x - mid.x) * k, (v[idx[t + 2]].y - mid.y) * k, 0.0)
		tri(mat, a, b, c, n, n, n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, n)
	return (hi.x - lo.x) * k


static func _grid_normal(pts: Array, ix: int, iz: int, nx: int, nz: int) -> Vector3:
	var l: Vector3 = pts[iz][maxi(ix - 1, 0)]
	var r: Vector3 = pts[iz][mini(ix + 1, nx)]
	var d: Vector3 = pts[maxi(iz - 1, 0)][ix]
	var u: Vector3 = pts[mini(iz + 1, nz)][ix]
	var n := (u - d).cross(r - l).normalized()
	if n.y < 0.0:
		n = -n
	return n


func commit(existing: ArrayMesh = null) -> ArrayMesh:
	var mesh := existing if existing else ArrayMesh.new()
	for key in _order:
		var st: SurfaceTool = _st[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat[key])
	return mesh


## Convenience: build a MeshInstance3D from this kit.
func instance(parent: Node, name := "Mesh", shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func xf_at(pos: Vector3, yaw := 0.0, scale := Vector3.ONE) -> Transform3D:
	var b := Basis(Vector3.UP, yaw).scaled(scale)
	return Transform3D(b, pos)


static func xf_basis(pos: Vector3, basis: Basis) -> Transform3D:
	return Transform3D(basis, pos)


## Static collision box helper.
static func collider_box(parent: Node, center: Vector3, size: Vector3, yaw := 0.0, layer := 1) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_transform = Transform3D(Basis(Vector3.UP, yaw), center)
	return sb
