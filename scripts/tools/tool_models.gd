class_name ToolModels
extends RefCounted
## Procedural models for hand tools and walk-behind machines. Origin = where the hands grip
## (for held tools) / ground contact (for machines). Blade points along local -Z.

static var _cache: Dictionary = {}


static func mesh_for(tool_id: String) -> ArrayMesh:
	return _build(tool_id, "all")


## First-person parts (polish §1): the handle alone (origin at the grip) and the blade alone
## (origin at the end of the shaft, in the orientation it has when the shaft runs at its natural
## angle) so the blade can lie flat on the snow whatever angle the shaft is held at.
static func handle_mesh(tool_id: String) -> ArrayMesh:
	return _build(tool_id, "handle")


static func blade_mesh(tool_id: String) -> ArrayMesh:
	return _build(tool_id, "blade")


## Where the shaft ends / the blade attaches, relative to the grip.
static func tip(tool_id: String) -> Vector3:
	var t: ToolData = Catalog.tool(StringName(tool_id))
	var dir := Vector3(0, -sin(deg_to_rad(55)), -cos(deg_to_rad(55)))
	match t.kind:
		ToolData.Kind.SHOVEL:
			return dir * (1.05 if t.tier <= 1 else 1.25)
		ToolData.Kind.PUSHER, ToolData.Kind.SCRAPER:
			return dir * 1.35
		ToolData.Kind.SLEIGH:
			return Vector3(0, -0.85, -0.75)
		ToolData.Kind.ELECTRIC_SHOVEL:
			return Vector3(0, -0.75, -0.62)
	return Vector3.ZERO


static func _build(tool_id: String, part: String) -> ArrayMesh:
	var key := tool_id + ":" + part
	if _cache.has(key):
		return _cache[key]
	var t: ToolData = Catalog.tool(StringName(tool_id))
	var kit := MeshKit.new()
	var handle := Mats.metal(Color(0.7, 0.72, 0.76))
	var grip := Mats.std(Color(0.12, 0.12, 0.13), 0.8)
	var main := Mats.std(t.primary_color, 0.55)
	var edge := Mats.metal(Color(0.55, 0.57, 0.6))
	var with_handle := part != "blade"
	var with_blade := part != "handle"
	# Blade parts are modelled at the shaft tip; the blade-only mesh moves them to the origin.
	var bx := Transform3D(Basis(), -tip(tool_id)) if part == "blade" else Transform3D()
	match t.kind:
		ToolData.Kind.SHOVEL:
			var hl := 1.05 if t.tier <= 1 else 1.25
			if with_handle:
				_handle(kit, handle, grip, hl)
			if with_blade:
				_blade(kit, main, edge, t.width, 0.2, hl, 0.12, bx)
		ToolData.Kind.PUSHER, ToolData.Kind.SCRAPER:
			var hl2 := 1.35
			if with_handle:
				_handle(kit, handle, grip, hl2)
			if with_blade:
				_blade(kit, main, edge, t.width, 0.32, hl2, 0.05, bx)
				if t.width > 1.0:
					for s in [-1.0, 1.0]:
						kit.cylinder(Mats.rubber(), bx * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(s * (t.width * 0.5 - 0.1), 0.08, -hl2 - 0.05) + Vector3(-0.04 * s, 0, 0)), 0.09, 0.09, 0.08, 10, true)
		ToolData.Kind.SLEIGH:
			# U-shaped handle and a deep scoop tub.
			if with_handle:
				for s in [-1.0, 1.0]:
					kit.cylinder(handle, Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-142)), Vector3(s * 0.3, 0, 0)), 0.02, 0.02, 0.98, 6, false)
				kit.cylinder(grip, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.3, 0, 0)), 0.025, 0.025, 0.6, 6, true)
			if with_blade:
				var tub := bx * Transform3D(Basis(), Vector3(0, -0.85, -0.75))
				kit.bevel_box(main, tub * Transform3D(Basis(), Vector3(0, -0.02, 0)), Vector3(t.width, 0.06, 0.9), 0.02)
				kit.bevel_box(main, tub * Transform3D(Basis(), Vector3(0, 0.14, 0.43)), Vector3(t.width, 0.34, 0.05), 0.02)
				for s2 in [-1.0, 1.0]:
					kit.bevel_box(main, tub * Transform3D(Basis(), Vector3(s2 * t.width * 0.5, 0.12, 0.0)), Vector3(0.05, 0.3, 0.9), 0.02)
		ToolData.Kind.ELECTRIC_SHOVEL:
			if with_handle:
				_handle(kit, handle, grip, 1.0)
			if with_blade:
				var body := bx * Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-35)), Vector3(0, -0.75, -0.62))
				kit.bevel_box(main, body, Vector3(0.36, 0.22, 0.42), 0.06)
				kit.cylinder(Mats.std(Color(0.9, 0.9, 0.9), 0.6), body * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.16, -0.1, -0.18)), 0.08, 0.08, 0.32, 10, true)
				kit.box(Mats.std(Color(0.1, 0.1, 0.1), 0.6), body * Transform3D(Basis(), Vector3(0, 0.12, 0.05)), Vector3(0.12, 0.08, 0.18))
		ToolData.Kind.WALK_BLOWER:
			var w := t.width
			var big := w > 0.65
			kit.bevel_box(main, Transform3D(Basis(), Vector3(0, 0.42, 0.05)), Vector3(w * 0.75, 0.38, 0.55), 0.08)
			kit.bevel_box(main, Transform3D(Basis(), Vector3(0, 0.25, -0.35)), Vector3(w, 0.5 if big else 0.4, 0.3), 0.06)
			kit.cylinder(Mats.metal(Color(0.3, 0.3, 0.32)), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(w * 0.48, 0.18, -0.42)), 0.13, 0.13, w * 0.96, 12, true)
			kit.box(Mats.std(Color(0.12, 0.12, 0.12), 0.6), Transform3D(Basis(), Vector3(0, 0.62, 0.15)), Vector3(0.3, 0.12, 0.25))
			for s in [-1.0, 1.0]:
				kit.cylinder(Mats.rubber(), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(s * (w * 0.4) + 0.06 * s, 0.17, 0.28)), 0.17, 0.17, 0.12, 12, true)
				kit.cylinder(handle, Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(55)), Vector3(s * 0.24, 0.45, 0.3)), 0.022, 0.022, 0.9, 6, false)
			kit.cylinder(grip, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.26, 0.97, 0.66)), 0.025, 0.025, 0.52, 6, true)
		_:
			pass
	var m := kit.commit()
	if part != "all":
		# First-person parts hide whatever is under the snow at the blade (viewmodel_clip).
		for si in range(m.get_surface_count()):
			var sm := m.surface_get_material(si)
			if sm is StandardMaterial3D:
				m.surface_set_material(si, _clip_mat(sm))
	_cache[key] = m
	return m


static var _clip_cache: Dictionary = {}
static var _clip_shader: Shader


static func _clip_mat(src: StandardMaterial3D) -> ShaderMaterial:
	if _clip_cache.has(src):
		return _clip_cache[src]
	if _clip_shader == null:
		_clip_shader = load("res://shaders/viewmodel_clip.gdshader")
	var sm := ShaderMaterial.new()
	sm.shader = _clip_shader
	sm.set_shader_parameter("albedo", src.albedo_color)
	sm.set_shader_parameter("roughness", src.roughness)
	sm.set_shader_parameter("metallic", src.metallic)
	_clip_cache[src] = sm
	return sm


static func _handle(kit: MeshKit, handle: Material, grip: Material, length: float) -> void:
	# Handle runs from the grip (origin) down/forward to the blade: direction (0, -sin 55°, -cos 55°).
	# (MeshKit cylinders grow along their local +Y, so +Y is rotated 145° about X onto that line.)
	var b := Basis(Vector3(1, 0, 0), deg_to_rad(-145))
	kit.cylinder(handle, Transform3D(b, Vector3.ZERO), 0.018, 0.018, length, 6, false)
	kit.cylinder(grip, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.07, 0.0, 0.0)), 0.022, 0.022, 0.14, 6, true)


static func _blade(kit: MeshKit, main: Material, edge: Material, width: float, height: float, hl: float, curve: float, bx := Transform3D()) -> void:
	var dir := Vector3(0, -sin(deg_to_rad(55)), -cos(deg_to_rad(55)))
	var tp := dir * hl
	var bb := Basis(Vector3(1, 0, 0), deg_to_rad(-10))
	kit.bevel_box(main, bx * Transform3D(bb, tp + Vector3(0, height * 0.35, -0.02)), Vector3(width, height, 0.03), 0.012)
	var floor_len := 0.36 if curve > 0.08 else 0.12
	kit.bevel_box(main, bx * Transform3D(Basis(), tp + Vector3(0, 0.0, -floor_len * 0.5)), Vector3(width, 0.03, floor_len), 0.01)
	kit.box(edge, bx * Transform3D(Basis(), tp + Vector3(0, -0.01, -0.35 if curve > 0.08 else -0.12)), Vector3(width, 0.02, 0.03))
	if curve > 0.08:
		# Low side walls make a scoop that holds a load.
		for s in [-1.0, 1.0]:
			kit.bevel_box(main, bx * Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(8)), tp + Vector3(s * (width * 0.5 - 0.012), 0.045, -0.16)), Vector3(0.025, 0.09, 0.3), 0.008)


## Where the blade/scoop sits relative to the grip, used to place snow loads.
static func blade_offset(tool_id: String) -> Vector3:
	var t: ToolData = Catalog.tool(StringName(tool_id))
	if t.kind == ToolData.Kind.SLEIGH:
		return tip(tool_id) + Vector3(0, 0.1, 0.0)
	return tip(tool_id) + Vector3(0, 0.06, -0.19)
