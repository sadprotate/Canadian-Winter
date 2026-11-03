class_name Props
extends RefCounted
## Shared prop meshes (built once, reused by MultiMesh / instances).

static var _cache: Dictionary = {}


static func evergreen() -> ArrayMesh:
	if _cache.has("evergreen"):
		return _cache["evergreen"]
	var kit := MeshKit.new()
	var green := Mats.needles()
	var snow := Mats.snow_soft()
	kit.cylinder(Mats.bark(), Transform3D(), 0.2, 0.14, 1.2, 8, false)
	var tiers := 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(tiers):
		var base := 0.7 + i * 0.95
		var r := 1.75 - i * 0.3
		var h := 1.7 - i * 0.12
		kit.cylinder(green, Transform3D(Basis(), Vector3(0, base, 0)), r, 0.05, h, 12, true)
		# Snow resting on the tier: a white band slightly outside the needles on the upper part.
		var y0 := base + h * 0.32
		var r0 := r * (1.0 - 0.32) + 0.06
		kit.cylinder(snow, Transform3D(Basis(), Vector3(0, y0, 0)), r0, 0.12, h * 0.6, 12, false)
		# Lumpy pillows on the rim.
		var lumps := 6
		for k in range(lumps):
			var a := TAU * (k + rng.randf() * 0.4) / lumps
			var rr := r * 0.62
			var p := Vector3(cos(a) * rr, base + h * 0.42, sin(a) * rr)
			kit.sphere(snow, Transform3D(Basis().scaled(Vector3(1.0, 0.55, 1.0)), p), 0.32 - i * 0.04, 4, 7, true)
	kit.sphere(snow, Transform3D(Basis().scaled(Vector3(1, 0.8, 1)), Vector3(0, 0.7 + tiers * 0.95 + 0.25, 0)), 0.22, 4, 7)
	var m := kit.commit()
	_cache["evergreen"] = m
	return m


static func bare_tree() -> ArrayMesh:
	if _cache.has("bare"):
		return _cache["bare"]
	var kit := MeshKit.new()
	var bark := Mats.bark()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_branch(kit, bark, Vector3.ZERO, Vector3.UP, 0.24, 3.6, 0, rng)
	var m := kit.commit()
	_cache["bare"] = m
	return m


static func _branch(kit: MeshKit, mat: Material, start: Vector3, dir: Vector3, radius: float, length: float, depth: int, rng: RandomNumberGenerator) -> void:
	var up := dir.normalized()
	var side := up.cross(Vector3(0.3, 0.1, 1.0)).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var fwd := side.cross(up).normalized()
	var basis := Basis(side, up, fwd)
	var r_top := radius * 0.62
	kit.cylinder(mat, Transform3D(basis, start), radius, r_top, length, 6 if depth < 2 else 4, false)
	if depth >= 3:
		return
	var end := start + up * length
	var count := 3 if depth == 0 else 2
	for k in range(count):
		var a := TAU * (k + rng.randf() * 0.5) / count + depth
		var tilt := deg_to_rad(rng.randf_range(28.0, 50.0))
		var nd := (up * cos(tilt) + (side * cos(a) + fwd * sin(a)) * sin(tilt)).normalized()
		var at := start + up * length * rng.randf_range(0.65, 1.0)
		_branch(kit, mat, at, nd, r_top * 0.9, length * rng.randf_range(0.55, 0.75), depth + 1, rng)
	if depth == 0:
		_branch(kit, mat, end, up, r_top, length * 0.6, depth + 1, rng)


static func mailbox() -> ArrayMesh:
	if _cache.has("mailbox"):
		return _cache["mailbox"]
	var kit := MeshKit.new()
	var wood := Mats.wood(Color(0.62, 0.42, 0.24), 0.8)
	kit.box(wood, Transform3D(Basis(), Vector3(0, 0.55, 0)), Vector3(0.12, 1.1, 0.12))
	kit.box(wood, Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(40)), Vector3(0, 0.95, 0.12)), Vector3(0.07, 0.3, 0.07))
	kit.box(wood, Transform3D(Basis(), Vector3(0, 1.12, 0.05)), Vector3(0.18, 0.05, 0.6))
	var body := Mats.prop(Color(0.32, 0.34, 0.37), 0.3, 0.45)
	kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 1.27, 0.05)), Vector3(0.26, 0.24, 0.56), 0.03)
	kit.cylinder(body, Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 1.39, -0.23)), 0.13, 0.13, 0.56, 10, true)
	var red := Mats.std(Color(0.85, 0.25, 0.1), 0.5)
	kit.box(red, Transform3D(Basis(), Vector3(0.15, 1.38, 0.1)), Vector3(0.02, 0.24, 0.05))
	kit.box(red, Transform3D(Basis(), Vector3(0.15, 1.48, 0.0)), Vector3(0.02, 0.06, 0.18))
	kit.pillow(Mats.snow_soft(), Transform3D(Basis(), Vector3(0, 1.5, 0.05)), 0.3, 0.6, 0.14, 0.06, 6, 2.5)
	var m := kit.commit()
	_cache["mailbox"] = m
	return m


static func streetlight() -> ArrayMesh:
	if _cache.has("streetlight"):
		return _cache["streetlight"]
	var kit := MeshKit.new()
	var pole := Mats.prop(Color(0.25, 0.26, 0.28), 0.6, 0.5)
	kit.cylinder(pole, Transform3D(), 0.12, 0.08, 6.2, 8, true)
	kit.box(pole, Transform3D(Basis(), Vector3(0, 6.1, 0.7)), Vector3(0.1, 0.1, 1.5))
	kit.bevel_box(pole, Transform3D(Basis(), Vector3(0, 6.0, 1.45)), Vector3(0.4, 0.18, 0.7), 0.05)
	kit.box(Mats.emissive(Color(1.0, 0.82, 0.55), 3.0), Transform3D(Basis(), Vector3(0, 5.9, 1.45)), Vector3(0.3, 0.03, 0.55))
	kit.pillow(Mats.snow_soft(), Transform3D(Basis(), Vector3(0, 6.09, 1.45)), 0.4, 0.7, 0.08, 0.03, 5, 2.5)
	var m := kit.commit()
	_cache["streetlight"] = m
	return m


static func fence_panel() -> ArrayMesh:
	if _cache.has("fence"):
		return _cache["fence"]
	var kit := MeshKit.new()
	var wood := Mats.wood(Color(0.55, 0.4, 0.26), 1.0)
	kit.box(wood, Transform3D(Basis(), Vector3(-1.2, 0.85, 0)), Vector3(0.12, 1.7, 0.12))
	kit.box(wood, Transform3D(Basis(), Vector3(0, 0.45, 0)), Vector3(2.4, 0.08, 0.06))
	kit.box(wood, Transform3D(Basis(), Vector3(0, 1.35, 0)), Vector3(2.4, 0.08, 0.06))
	for k in range(13):
		kit.box(wood, Transform3D(Basis(), Vector3(-1.1 + k * 0.183, 0.82, 0.05)), Vector3(0.16, 1.55, 0.03))
	kit.pillow(Mats.snow_soft(), Transform3D(Basis(), Vector3(0, 1.6, 0.04)), 2.4, 0.14, 0.07, 0.02, 6, 2.0)
	var m := kit.commit()
	_cache["fence"] = m
	return m


static func shrub() -> ArrayMesh:
	if _cache.has("shrub"):
		return _cache["shrub"]
	var kit := MeshKit.new()
	kit.sphere(Mats.needles(), Transform3D(Basis().scaled(Vector3(1, 0.7, 1)), Vector3(0, 0.3, 0)), 0.6, 5, 9)
	kit.sphere(Mats.snow_soft(), Transform3D(Basis().scaled(Vector3(1.05, 0.55, 1.05)), Vector3(0, 0.5, 0)), 0.58, 4, 9, true)
	var m := kit.commit()
	_cache["shrub"] = m
	return m


static func multimesh(mesh: Mesh, xforms: Array, parent: Node, name: String, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi
