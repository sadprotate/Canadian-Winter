class_name SnowRenderer
extends Node3D
## Renders the snow heightfield as 16 m chunks. Only dirty regions are recomputed; the
## mesh surface is re-uploaded natively. LOD: 1/2/4 cell steps with skirts to hide seams.

const CELL := 0.25
const CHUNK := 64

var camera: Camera3D
var lod_near := 40.0
var lod_far := 85.0
var shadow_dist := 48.0
var chunk_budget := 4          # chunk updates per frame
var relax_budget := 64         # relaxation tiles per frame (upper bound)
var relax_usec := 2500         # …and a time budget per frame (µs) for the low-tier CPU target
var sync_budget := 1           # snowfall chunk syncs per frame
var mesh_usec := 3500          # time budget for chunk mesh updates per frame (µs)
var updates_last_frame := 0
var detail := 1                # 0 low, 1 medium, 2 high (from settings)

var _mi: Array = []            # MeshInstance3D per chunk
var _mesh: Array = []          # ArrayMesh per chunk
var _lod := PackedInt32Array()
var _want_lod := PackedInt32Array()
var _verts: Array = []
var _norms: Array = []
var _uvs: Array = []
var _index_cache: Dictionary = {}
var _lod_timer := 0.0
var _material: Material
var _built := false


func _ready() -> void:
	_material = Mats.snow_ground()
	var n := Snow.CW * Snow.CH
	_lod.resize(n)
	_want_lod.resize(n)
	_lod.fill(0)
	_want_lod.fill(1)
	_verts.resize(n)
	_norms.resize(n)
	_uvs.resize(n)
	for ci in range(n):
		var mi := MeshInstance3D.new()
		mi.name = "SnowChunk%d" % ci
		var m := ArrayMesh.new()
		mi.mesh = m
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mi.append(mi)
		_mesh.append(m)
	apply_detail(Settings.get_value("graphics", "snow_detail", 1) if Settings.has_method("get_value") else 1)


func apply_detail(level: int) -> void:
	detail = clampi(level, 0, 2)
	match detail:
		0:
			lod_near = 26.0
			lod_far = 55.0
			chunk_budget = 3
		1:
			lod_near = 40.0
			lod_far = 85.0
			chunk_budget = 4
		2:
			lod_near = 60.0
			lod_far = 120.0
			chunk_budget = 6


## Build every chunk immediately (loading screen).
func build_all(cam_pos: Vector3) -> void:
	_update_lods(cam_pos)
	for ci in range(Snow.CW * Snow.CH):
		Snow.sync_chunk(ci)
		Snow.take_dirty(ci)
		_lod[ci] = _want_lod[ci]
		_full_build(ci)
	_built = true


func _process(delta: float) -> void:
	if not Snow.initialized:
		return
	var cam_pos := Vector3(96, 0, 100)
	var vp_cam := get_viewport().get_camera_3d()
	if vp_cam:
		cam_pos = vp_cam.global_position
	if not _built:
		build_all(cam_pos)
		return
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.3
		_update_lods(cam_pos)
	if Snow.auto_process:
		Snow.sync_round_robin(sync_budget)
		Snow.process_relax(relax_budget, relax_usec)
	_update_dirty(cam_pos)


func _update_lods(cam_pos: Vector3) -> void:
	for ci in range(Snow.CW * Snow.CH):
		var cx := (ci % Snow.CW) * CHUNK * CELL + CHUNK * CELL * 0.5
		@warning_ignore("integer_division")
		var cz := (ci / Snow.CW) * CHUNK * CELL + CHUNK * CELL * 0.5
		var d := Vector2(cx, cz).distance_to(Vector2(cam_pos.x, cam_pos.z)) - CHUNK * CELL * 0.5
		var want := 1
		if d > lod_far:
			want = 4
		elif d > lod_near:
			want = 2
		_want_lod[ci] = want
		var mi: MeshInstance3D = _mi[ci]
		# The heightfield never casts shadows: self-shadowing a 25 cm grid under a low winter sun
		# only produces acne; the pillowy look comes from the shading. Saves shadow-pass cost too.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _update_dirty(cam_pos: Vector3) -> void:
	updates_last_frame = 0
	# Collect candidates: LOD changes and dirty chunks, nearest first.
	var cands := []
	for ci in range(Snow.CW * Snow.CH):
		if _lod[ci] != _want_lod[ci] or Snow.is_dirty(ci):
			var cx := (ci % Snow.CW) * CHUNK * CELL + CHUNK * CELL * 0.5
			@warning_ignore("integer_division")
			var cz := (ci / Snow.CW) * CHUNK * CELL + CHUNK * CELL * 0.5
			cands.append([Vector2(cx, cz).distance_squared_to(Vector2(cam_pos.x, cam_pos.z)), ci])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var t0 := Time.get_ticks_usec()
	for k in range(mini(chunk_budget, cands.size())):
		# Time budget keeps frame times stable on low-tier CPUs (always at least one update).
		if k > 0 and Time.get_ticks_usec() - t0 > mesh_usec:
			break
		var ci: int = cands[k][1]
		if _lod[ci] != _want_lod[ci]:
			Snow.take_dirty(ci)
			_lod[ci] = _want_lod[ci]
			_full_build(ci)
		else:
			var r := Snow.take_dirty(ci)
			if r.size.x >= 0:
				_partial(ci, r)
		updates_last_frame += 1


func _indices(step: int) -> PackedInt32Array:
	if _index_cache.has(step):
		return _index_cache[step]
	@warning_ignore("integer_division")
	var n := CHUNK / step + 1
	var idx := PackedInt32Array()
	for vz in range(n - 1):
		for vx in range(n - 1):
			var i00 := vz * n + vx
			var i10 := i00 + 1
			var i01 := i00 + n
			var i11 := i01 + 1
			idx.append_array([i00, i10, i11, i00, i11, i01])
	# Skirts (double-sided) along the 4 edges. Skirt vertex k mirrors edge vertex k.
	var base := n * n
	var edges := _edge_list(n)
	for e in range(edges.size()):
		var lst: PackedInt32Array = edges[e]
		for k in range(lst.size() - 1):
			var a := lst[k]
			var b := lst[k + 1]
			var sa := base + e * n + k
			var sb := base + e * n + k + 1
			idx.append_array([a, b, sb, a, sb, sa, a, sb, b, a, sa, sb])
	_index_cache[step] = idx
	return idx


func _edge_list(n: int) -> Array:
	var top := PackedInt32Array()
	var bottom := PackedInt32Array()
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	for k in range(n):
		top.append(k)
		bottom.append((n - 1) * n + k)
		left.append(k * n)
		right.append(k * n + n - 1)
	return [top, bottom, left, right]


func _vertex_height(gx: int, gz: int) -> float:
	gx = clampi(gx, 0, Snow.W - 1)
	gz = clampi(gz, 0, Snow.H - 1)
	var i := gz * Snow.W + gx
	var s := Snow.surf[i]
	if s == Snow.S_BLOCKED:
		# Extend neighbouring snow under the wall so banks meet walls flush.
		var best := -0.6
		for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = clampi(gx + o[0], 0, Snow.W - 1)
			var nz: int = clampi(gz + o[1], 0, Snow.H - 1)
			var j := nz * Snow.W + nx
			if Snow.surf[j] != Snow.S_BLOCKED and Snow.depth[j] > 0.002:
				best = maxf(best, Snow.ground[j] + Snow.depth[j])
		return best
	var d := Snow.depth[i]
	if d < 0.002:
		return Snow.ground[i] - 0.06
	return Snow.ground[i] + maxf(d, 0.014)


func _full_build(ci: int) -> void:
	var step := _lod[ci]
	@warning_ignore("integer_division")
	var n := CHUNK / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var total := n * n + 4 * n
	verts.resize(total)
	norms.resize(total)
	uvs.resize(total)
	_verts[ci] = verts
	_norms[ci] = norms
	_uvs[ci] = uvs
	_recompute(ci, 0, 0, n - 1, n - 1)


func _partial(ci: int, r: Rect2i) -> void:
	var step := _lod[ci]
	@warning_ignore("integer_division")
	var n := CHUNK / step + 1
	var vx0 := clampi(int(floor((r.position.x - 1) / float(step))), 0, n - 1)
	var vz0 := clampi(int(floor((r.position.y - 1) / float(step))), 0, n - 1)
	var vx1 := clampi(int(ceil((r.end.x + 1) / float(step))), 0, n - 1)
	var vz1 := clampi(int(ceil((r.end.y + 1) / float(step))), 0, n - 1)
	_recompute(ci, vx0, vz0, vx1, vz1)


func _recompute(ci: int, vx0: int, vz0: int, vx1: int, vz1: int) -> void:
	var step := _lod[ci]
	@warning_ignore("integer_division")
	var n := CHUNK / step + 1
	var gx0 := (ci % Snow.CW) * CHUNK
	@warning_ignore("integer_division")
	var gz0 := (ci / Snow.CW) * CHUNK
	var verts: PackedVector3Array = _verts[ci]
	var norms: PackedVector3Array = _norms[ci]
	var uvs: PackedVector2Array = _uvs[ci]
	_verts[ci] = null
	_norms[ci] = null
	_uvs[ci] = null
	var W := Snow.W
	var H := Snow.H
	var span := 2.0 * step * CELL
	var inv_step := 1.0 / float(step)
	# Height grid with a 1-vertex border so normals can use central differences.
	var gw := vx1 - vx0 + 3
	var gh := vz1 - vz0 + 3
	var hg := PackedFloat32Array()
	hg.resize(gw * gh)
	# Local read-only views of the sim arrays (no copy: packed arrays are copy-on-write) make the
	# inner loop several times faster than going through the autoload for every cell.
	var depth := Snow.depth
	var surf := Snow.surf
	var ground := Snow.ground
	var blocked := Snow.S_BLOCKED
	var k0 := 0
	for j in range(gh):
		var gz := clampi(gz0 + (vz0 - 1 + j) * step, 0, H - 1)
		var rowi := gz * W
		var gxs := gx0 + (vx0 - 1) * step
		for i in range(gw):
			var gx := clampi(gxs + i * step, 0, W - 1)
			var idx := rowi + gx
			if surf[idx] == blocked:
				hg[k0] = _vertex_height(gx, gz)
			else:
				var d := depth[idx]
				hg[k0] = ground[idx] - 0.06 if d < 0.002 else ground[idx] + maxf(d, 0.014)
			k0 += 1
	for vz in range(vz0, vz1 + 1):
		var gz := gz0 + vz * step
		var cgz := clampi(gz, 0, H - 1)
		var wz := (gz + 0.5) * CELL
		var j := vz - vz0 + 1
		for vx in range(vx0, vx1 + 1):
			var gx := gx0 + vx * step
			var i := vx - vx0 + 1
			var row := j * gw
			var h := hg[row + i]
			var k := vz * n + vx
			var cgx := clampi(gx, 0, W - 1)
			verts[k] = Vector3((gx + 0.5) * CELL, h, wz)
			var hl := hg[row + i - 1]
			var hr := hg[row + i + 1]
			var hu := hg[row - gw + i]
			var hd := hg[row + gw + i]
			norms[k] = Vector3(hl - hr, span, hu - hd).normalized()
			var gi := cgz * W + cgx
			# UV.x = depth; UV.y = surface code (integer part) + convexity (fraction, crest > 0,
			# hollow < 0, scaled to the LOD step) packed together to keep one attribute stream.
			uvs[k] = Vector2(depth[gi], surf[gi] + 0.4 + clampf((h - (hl + hr + hu + hd) * 0.25) * inv_step, -0.3, 0.3))
	# Skirts mirror edge vertices, dropped down.
	var base := n * n
	var edges := _edge_list(n)
	for e in range(4):
		var lst: PackedInt32Array = edges[e]
		for k in range(n):
			var src := lst[k]
			var v := verts[src]
			verts[base + e * n + k] = Vector3(v.x, v.y - 0.7, v.z)
			norms[base + e * n + k] = norms[src]
			uvs[base + e * n + k] = uvs[src]
	_verts[ci] = verts
	_norms[ci] = norms
	_uvs[ci] = uvs
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _indices(step)
	var m: ArrayMesh = _mesh[ci]
	m.clear_surfaces()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
