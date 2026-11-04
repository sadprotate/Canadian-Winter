class_name ToolModels
extends RefCounted
## Procedural models for hand tools and walk-behind machines. Origin = where the hands grip
## (for held tools) / ground contact (for machines). Blade points along local -Z.
##
## Polish 5 §6: modelled on real tools — a D-grip (shovels, the electric shovel) or a T-grip
## (pusher, scrapers) on a shaft with a ferrule and a socket; blades with a riveted wear strip; the
## scrapers' steel moldboards with a bolted cutting edge, back ribs and the angle pivot; the
## pusher's wide face and brace; the sleigh's tub on runners with its U-bar; the electric shovel's
## rotor housing and battery; the blowers' housing, auger, chute, wheels and handles — in materials
## that read as plastic, aluminium, steel, wood, fibreglass or rubber with a little wear
## (shaders/tool.gdshader, Mats.tool).
## Kept as they were, so everything that holds, places or measures a tool is unchanged: the origin
## (the top hand's grip), tip() (where the shaft meets the blade) and the 55° shaft, blade_offset()
## (the load on the blade), each blade's width (the tool profile's width), the handle / blade split
## for first person (both through the viewmodel clip shader) and the blowers' chute pivot.

const FIN_PLAIN := 0
const FIN_PLASTIC := 1
const FIN_ALU := 2
const FIN_PAINT := 3
const FIN_STEEL := 4
const FIN_WOOD := 5
const FIN_FIBRE := 6
const FIN_RUBBER := 7

const SHAFT_R := 0.016                      # a 32 mm shaft
const CHUTE_POS := Vector3(0, 0.62, -0.25)  # a walk-behind blower's chute pivot (WalkBehind)
const X := Vector3.RIGHT

static var _cache: Dictionary = {}
## The x-range of each tool's cutting edge / intake as built (tests: it matches the profile width).
static var edge_span: Dictionary = {}


static func mesh_for(tool_id: String) -> ArrayMesh:
	return _build(tool_id, "all")


## First-person parts (polish §1): the handle alone (origin at the grip) and the blade alone
## (origin at the end of the shaft, in the orientation it has when the shaft runs at its natural
## angle) so the blade can lie flat on the snow whatever angle the shaft is held at.
static func handle_mesh(tool_id: String) -> ArrayMesh:
	return _build(tool_id, "handle")


static func blade_mesh(tool_id: String) -> ArrayMesh:
	return _build(tool_id, "blade")


## Polish 5 §6: a walk-behind blower's chute, origin at its pivot (CHUTE_POS on the machine); it
## turns about its own vertical axis and throws along its local -Z.
static func chute_mesh(tool_id: String) -> ArrayMesh:
	return _build(tool_id, "chute")


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


## Where the blade/scoop sits relative to the grip, used to place snow loads.
static func blade_offset(tool_id: String) -> Vector3:
	var t: ToolData = Catalog.tool(StringName(tool_id))
	if t.kind == ToolData.Kind.SLEIGH:
		return tip(tool_id) + Vector3(0, 0.1, 0.0)
	return tip(tool_id) + Vector3(0, 0.06, -0.19)


## Polish 5 §6 (pass 3's 17 exposure points, on the new model): nine along the shaft from the grip
## to the blade (for the sleigh: along its bar and arms) and two rows of four across the blade —
## by its back and by its front edge (the scraping edge). Tool frame (ToolItem maps them to the world).
static func sample_points(tool_id: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var t: ToolData = Catalog.tool(StringName(tool_id))
	if t == null or t.kind == ToolData.Kind.HANDS or t.kind == ToolData.Kind.WALK_BLOWER:
		return out
	var T := tip(tool_id)
	var w := clampf(t.width, 0.25, 1.0)
	var back := Vector3.ZERO
	var front := Vector3.ZERO
	match t.kind:
		ToolData.Kind.SHOVEL:
			back = Vector3(0, 0.004, -0.08)
			front = Vector3(0, 0.004, -(0.33 if t.tier <= 1 else 0.40) + 0.04)
		ToolData.Kind.PUSHER:
			back = Vector3(0, 0.17, -0.025)
			front = Vector3(0, 0.03, -0.093)
		ToolData.Kind.SCRAPER:
			var k := (0.26 if t.width > 0.9 else 0.21) / 0.21
			back = Vector3(0, 0.15 * k, -0.01 * k)
			front = Vector3(0, 0.02, -0.07 * k)
		ToolData.Kind.SLEIGH:
			back = Vector3(0, 0.004, 0.3)
			front = Vector3(0, 0.004, -0.38)
		ToolData.Kind.ELECTRIC_SHOVEL:
			w = 0.23   # across the motor housing's top and the scraper bar
			back = Vector3(0, 0.21, 0.03)
			front = Vector3(0, 0.003, -0.13)
	if t.kind == ToolData.Kind.SLEIGH:
		# The bar (three) and both arms (three each).
		for x in [-0.2, 0.0, 0.2]:
			out.append(Vector3(x, 0, 0))
		var ends := _sleigh_arm_ends(t)
		for f in [0.3, 0.55, 0.8]:
			for s in [-1.0, 1.0]:
				var top := Vector3(s * 0.3, 0, 0)
				out.append(top.lerp(Vector3(s * ends.x, ends.y, ends.z), f))
	else:
		# The grip, then down the shaft (a D-grip's hole has no shaft in it: the points start below
		# its yoke).
		var d_grip := t.kind == ToolData.Kind.SHOVEL or t.kind == ToolData.Kind.ELECTRIC_SHOVEL
		var s0 := 0.17 / T.length() if d_grip else 1.0 / 9.0
		out.append(Vector3.ZERO)
		for k2 in range(1, 9):
			out.append(T * lerpf(s0, 8.0 / 9.0, (k2 - 1) / 7.0))
	for k3 in range(4):
		var u := (-0.5 + k3 / 3.0) * w * 0.9
		out.append(T + back + Vector3(u, 0, 0))
		out.append(T + front + Vector3(u, 0, 0))
	return out


static func _build(tool_id: String, part: String) -> ArrayMesh:
	var key := tool_id + ":" + part
	if _cache.has(key):
		return _cache[key]
	var t: ToolData = Catalog.tool(StringName(tool_id))
	var kit := MeshKit.new()
	var m := _look(t)
	var with_handle := part == "all" or part == "handle"
	var with_blade := part == "all" or part == "blade"
	# Blade parts are modelled at the shaft tip; the blade-only mesh moves them to the origin.
	var T := tip(tool_id)
	var bx := Transform3D(Basis(), -T) if part == "blade" else Transform3D()
	var B := bx * Transform3D(Basis(), T)     # blade-local frame (origin at the tip) -> this part
	match t.kind:
		ToolData.Kind.SHOVEL:
			if with_handle:
				_long_handle(kit, m, tool_id, "D", 0.45, 0.0)
			if with_blade:
				_shovel_blade(kit, m, t, B)
		ToolData.Kind.PUSHER:
			if with_handle:
				_long_handle(kit, m, tool_id, "T", 0.52, 0.0)
			if with_blade:
				_pusher_blade(kit, m, t, B)
		ToolData.Kind.SCRAPER:
			if with_handle:
				_long_handle(kit, m, tool_id, "T", 0.52, PIVOT_S)
			if with_blade:
				_scraper_blade(kit, m, t, B)
		ToolData.Kind.SLEIGH:
			if with_handle:
				_sleigh_handle(kit, m, t)
			if with_blade:
				_sleigh_tub(kit, m, t, B)
		ToolData.Kind.ELECTRIC_SHOVEL:
			if with_handle:
				_electric_handle(kit, m, tool_id)
			if with_blade:
				_electric_head(kit, m, t, B)
		ToolData.Kind.WALK_BLOWER:
			if part == "chute":
				_blower_chute(kit, m, t)
			elif t.width > 0.65:
				_large_blower(kit, m, t)
			else:
				_small_blower(kit, m, t)
		_:
			pass
	var mesh := kit.commit()
	if part == "handle" or part == "blade":
		# First-person parts hide whatever is under the snow at the blade (viewmodel_clip).
		for si in range(mesh.get_surface_count()):
			mesh.surface_set_material(si, _clip_mat(mesh.surface_get_material(si)))
	_cache[key] = mesh
	return mesh


static var _clip_cache: Dictionary = {}
static var _clip_shader: Shader
const _TOOL_PARAMS := ["albedo", "roughness", "metallic", "finish", "wear", "edge_wear", "grain_axis"]


static func _clip_mat(src: Material) -> ShaderMaterial:
	if _clip_cache.has(src):
		return _clip_cache[src]
	if _clip_shader == null:
		_clip_shader = load("res://shaders/viewmodel_clip.gdshader")
	var sm := ShaderMaterial.new()
	sm.shader = _clip_shader
	if src is ShaderMaterial:
		for p in _TOOL_PARAMS:
			var v = (src as ShaderMaterial).get_shader_parameter(p)
			if v != null:
				sm.set_shader_parameter(p, v)
	elif src is StandardMaterial3D:
		var std := src as StandardMaterial3D
		sm.set_shader_parameter("albedo", std.albedo_color)
		sm.set_shader_parameter("roughness", std.roughness)
		sm.set_shader_parameter("metallic", std.metallic)
	_clip_cache[src] = sm
	return sm


# -----------------------------------------------------------------------------
# Materials
# -----------------------------------------------------------------------------

## The materials a tool is made of. Every key exists for every tool (generic values first).
static func _look(t: ToolData) -> Dictionary:
	var c := t.primary_color
	var shaft_axis := tip(String(t.id)).normalized() if t.kind != ToolData.Kind.WALK_BLOWER else Vector3.UP
	if shaft_axis == Vector3.ZERO:
		shaft_axis = Vector3(0, -0.819, -0.574)
	var m := {}
	m["black"] = Mats.tool(FIN_PLASTIC, Color(0.075, 0.075, 0.085), 0.55, 0.0, 0.25)
	m["rubber"] = Mats.tool(FIN_RUBBER, Color(0.07, 0.07, 0.075), 0.9, 0.0, 0.0)
	m["steel"] = Mats.tool(FIN_STEEL, Color(0.68, 0.69, 0.71), 0.38, 0.5, 0.5, 0.0, Vector3(0, 0, 1))
	m["blade"] = Mats.tool(FIN_PLASTIC, c, 0.5, 0.0, 0.35, 1.0)
	m["edge"] = m["steel"]
	m["shaft"] = Mats.tool(FIN_ALU, Color(0.8, 0.81, 0.83), 0.3, 0.45, 0.25, 0.0, shaft_axis)
	m["grip"] = m["black"]
	m["ferrule"] = m["steel"]
	m["socket"] = m["blade"]
	m["frame"] = Mats.tool(FIN_PAINT, Color(0.11, 0.11, 0.12), 0.42, 0.05, 0.35, 0.0)
	m["hub"] = Mats.tool(FIN_PLASTIC, Color(0.42, 0.43, 0.45), 0.5, 0.0, 0.2)
	m["accent"] = Mats.tool(FIN_PLASTIC, Color(0.95, 0.45, 0.1), 0.45, 0.0, 0.1)
	match String(t.id):
		"small_shovel":
			# A short orange poly scoop on an ash shaft, a thin aluminium wear strip.
			m["edge"] = Mats.tool(FIN_ALU, Color(0.8, 0.81, 0.83), 0.36, 0.45, 0.5, 0.0, X)
			m["ferrule"] = m["edge"]
			m["shaft"] = Mats.tool(FIN_WOOD, Color(0.78, 0.62, 0.42), 0.42, 0.0, 0.3, 0.0, shaft_axis)
		"standard_shovel":
			# A blue poly scoop with a riveted steel wear strip, a brushed aluminium shaft with a foam
			# sleeve where the lower hand goes.
			m["sleeve"] = m["rubber"]
			m["socket"] = m["blade"]
		"wide_pusher":
			# A wide green poly face with a steel wear strip and a steel brace on a varnished shaft.
			m["shaft"] = Mats.tool(FIN_WOOD, Color(0.66, 0.48, 0.3), 0.4, 0.0, 0.3, 0.0, shaft_axis)
			m["socket"] = m["frame"]
		"snow_scraper":
			# A red steel moldboard with a bolted steel cutting edge, on a black fibreglass shaft.
			m["blade"] = Mats.tool(FIN_PAINT, c, 0.42, 0.05, 0.45, 1.0)
			m["shaft"] = Mats.tool(FIN_FIBRE, Color(0.1, 0.1, 0.11), 0.3, 0.0, 0.3, 0.0, shaft_axis)
			m["socket"] = m["frame"]
			m["sleeve"] = m["rubber"]
		"large_scraper":
			# A wide yellow steel moldboard on two wheels, a black steel tube shaft.
			m["blade"] = Mats.tool(FIN_PAINT, c, 0.42, 0.05, 0.45, 1.0)
			m["shaft"] = Mats.tool(FIN_PAINT, Color(0.1, 0.1, 0.11), 0.38, 0.05, 0.3, 0.0, shaft_axis)
			m["socket"] = m["frame"]
			m["sleeve"] = m["rubber"]
		"snow_sleigh":
			# A blue poly tub on runners, a powder-coated U-bar with a foam grip.
			m["blade"] = Mats.tool(FIN_PLASTIC, c, 0.45, 0.0, 0.35, 1.0)
			m["bar"] = Mats.tool(FIN_PAINT, Color(0.09, 0.09, 0.1), 0.4, 0.05, 0.3, 0.0, X)
			m["foam"] = m["rubber"]
		"electric_shovel":
			# Green and black plastic, a dark anodised shaft, a rubber rotor, an orange trigger.
			m["body"] = Mats.tool(FIN_PLASTIC, c, 0.45, 0.0, 0.25, 0.5)
			m["shaft"] = Mats.tool(FIN_ALU, Color(0.15, 0.15, 0.16), 0.32, 0.35, 0.25, 0.0, shaft_axis)
			m["sleeve"] = m["rubber"]
		"small_blower":
			m["body"] = Mats.tool(FIN_PLASTIC, c, 0.42, 0.0, 0.3, 0.6)
		"large_blower":
			m["body"] = Mats.tool(FIN_PAINT, c, 0.4, 0.05, 0.35, 0.6)
			m["engine"] = Mats.tool(FIN_ALU, Color(0.58, 0.59, 0.61), 0.6, 0.35, 0.3, 0.0, Vector3.UP)
			m["auger"] = Mats.tool(FIN_PAINT, Color(0.55, 0.56, 0.58), 0.45, 0.1, 0.4, 0.0)
	if not m.has("body"):
		m["body"] = m["blade"]
	if not m.has("bar"):
		m["bar"] = m["frame"]
	if not m.has("foam"):
		m["foam"] = m["rubber"]
	if not m.has("engine"):
		m["engine"] = m["hub"]
	if not m.has("auger"):
		m["auger"] = m["rubber"]
	return m


# -----------------------------------------------------------------------------
# Handles
# -----------------------------------------------------------------------------

const PIVOT_S := 0.12   # scrapers: the shaft ends this far above its tip, at the angle pivot


## Grip, shaft, ferrule, the lower hand's sleeve (if any) and the socket into the blade, along the
## line from the grip (origin) to tip(). `short_end`: the shaft stops this far before the tip.
static func _long_handle(kit: MeshKit, m: Dictionary, tool_id: String, grip: String, sleeve_at: float, short_end: float) -> void:
	var T := tip(tool_id)
	var L := T.length()
	var d := T / L
	var n := X.cross(d).normalized()
	var s0 := _d_grip(kit, m, d) if grip == "D" else _t_grip(kit, m, d)
	var s_end := L - short_end
	var sock := 0.16 if short_end == 0.0 else 0.1
	_tube(kit, m["shaft"], d * s0, d * (s_end - sock + 0.02), SHAFT_R, 12, false)
	# The socket the shaft goes into (moulded with the blade, or a steel collar), with a rivet.
	_tube(kit, m["socket"], d * (s_end - sock), d * s_end, SHAFT_R + 0.004, 12, true, SHAFT_R + 0.0065)
	_rivet(kit, m["steel"], d * (s_end - sock + 0.04) + n * (SHAFT_R + 0.0045), n, 0.005)
	if m.has("sleeve"):
		_sleeve(kit, m["sleeve"], d, sleeve_at)


## A D-grip: the top hand closes on its bar through the origin; the legs meet in a yoke on the
## shaft, then a ferrule. Returns where the shaft itself starts.
static func _d_grip(kit: MeshKit, m: Dictionary, d: Vector3) -> float:
	var pts := [Vector2(-0.024, 0.168), Vector2(-0.052, 0.122), Vector2(-0.066, 0.066), Vector2(-0.062, 0.02),
		Vector2(-0.04, 0.0), Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.062, 0.02),
		Vector2(0.066, 0.066), Vector2(0.052, 0.122), Vector2(0.024, 0.168)]
	var rad := PackedFloat32Array([0.0125, 0.011, 0.011, 0.012, 0.0135, 0.0135, 0.0135, 0.012, 0.011, 0.011, 0.0125])
	var path := PackedVector3Array()
	for p in pts:
		path.append(X * (p as Vector2).x + d * (p as Vector2).y)
	var sp := _spline(path, rad, 3)
	_sweep(kit, m["grip"], sp[0], 0.0, 10, true, true, sp[1])
	_tube(kit, m["grip"], d * 0.15, d * 0.255, 0.0235, 12, true, 0.0195)
	_tube(kit, m["ferrule"], d * 0.244, d * 0.27, 0.0185, 12, true)
	return 0.25


## A T-grip: a barrel-shaped crossbar through the origin on a yoke, then a ferrule.
static func _t_grip(kit: MeshKit, m: Dictionary, d: Vector3) -> float:
	var path := PackedVector3Array([X * -0.08, X * -0.072, X * -0.04, Vector3.ZERO, X * 0.04, X * 0.072, X * 0.08])
	var rad := PackedFloat32Array([0.012, 0.0165, 0.019, 0.0195, 0.019, 0.0165, 0.012])
	_sweep(kit, m["grip"], path, 0.0, 12, true, true, rad)
	_tube(kit, m["grip"], d * -0.004, d * 0.105, 0.022, 12, true, 0.0195)
	_tube(kit, m["ferrule"], d * 0.095, d * 0.124, 0.0185, 12, true)
	return 0.11


## A foam / rubber sleeve on the shaft where the lower hand holds it.
static func _sleeve(kit: MeshKit, mat: Material, d: Vector3, at: float) -> void:
	var path := PackedVector3Array([d * (at - 0.09), d * (at - 0.075), d * (at + 0.075), d * (at + 0.09)])
	_sweep(kit, mat, path, 0.0, 12, true, true, PackedFloat32Array([SHAFT_R + 0.0008, 0.0198, 0.0198, SHAFT_R + 0.0008]))


# -----------------------------------------------------------------------------
# Blades (blade-local frame B: origin at the tip, -Z forward, the blade's floor / bottom at y = 0)
# -----------------------------------------------------------------------------

static func _shovel_blade(kit: MeshKit, m: Dictionary, t: ToolData, B: Transform3D) -> void:
	var W := t.width
	var small := t.tier <= 1
	var D := 0.33 if small else 0.40
	var hb := 0.15 if small else 0.17
	# The scoop's section, front edge first: a flat floor curving up into the back, which leans
	# back along the shaft (the shaft runs just behind it into its socket).
	var prof := PackedVector2Array([Vector2(-D, 0.0), Vector2(-D * 0.55, 0.0), Vector2(-0.11, 0.002), Vector2(-0.06, 0.013),
		Vector2(-0.025, 0.036), Vector2(0.004, 0.072), Vector2(0.03, 0.11), Vector2(0.046, hb - 0.012), Vector2(0.052, hb)])
	_sheet(kit, m["blade"], prof, -W * 0.5, W * 0.5, 0.007, B)
	edge_span[String(t.id)] = Vector2(-W * 0.5, W * 0.5)
	# Side walls between the floor and a line from the back's top down to the front corner.
	var wall := prof.duplicate()
	wall[0] = Vector2(-D + 0.012, 0.0)
	wall.append(Vector2(-D + 0.03, 0.022))
	for s in [-1.0, 1.0]:
		_wall(kit, m["blade"], wall, s * (W * 0.5 - 0.004), 0.008, prof.size() - 1, B)
	# A rolled lip along the back's top edge, and moulded ribs on the floor.
	_tube(kit, m["blade"], B * Vector3(-W * 0.5, hb, 0.052), B * Vector3(W * 0.5, hb, 0.052), 0.007, 8, true)
	var ribs := [-0.09, 0.0, 0.09] if small else [-0.15, -0.075, 0.0, 0.075, 0.15]
	var r0 := -D + 0.055
	var r1 := -0.1
	for x in ribs:
		kit.bevel_box(m["blade"], B * Transform3D(Basis(), Vector3(x, 0.003, (r0 + r1) * 0.5)), Vector3(0.01, 0.008, r1 - r0), 0.003)
	# The wear strip on the front edge, riveted through.
	kit.bevel_box(m["edge"], B * Transform3D(Basis(), Vector3(0, -0.0005, -D + 0.018)), Vector3(W + 0.002, 0.016, 0.042), 0.003)
	var nr := 3 if small else 5
	for i in range(nr):
		var x2 := (-0.5 + (i + 0.5) / nr) * W * 0.9
		_rivet(kit, m["steel"], B * Vector3(x2, 0.0075, -D + 0.026), Vector3.UP, 0.0055)


static func _pusher_blade(kit: MeshKit, m: Dictionary, t: ToolData, B: Transform3D) -> void:
	var W := t.width
	var up := -tip(String(t.id)).normalized()
	# A tall face curving forward at the bottom (concave to the front).
	var prof := PackedVector2Array([Vector2(-0.1, 0.0), Vector2(-0.093, 0.03), Vector2(-0.077, 0.07), Vector2(-0.053, 0.115),
		Vector2(-0.026, 0.16), Vector2(-0.004, 0.2), Vector2(0.01, 0.235), Vector2(0.015, 0.26)])
	_sheet(kit, m["blade"], prof, -W * 0.5, W * 0.5, 0.009, B)
	edge_span[String(t.id)] = Vector2(-W * 0.5, W * 0.5)
	_tube(kit, m["blade"], B * Vector3(-W * 0.5, 0.266, 0.017), B * Vector3(W * 0.5, 0.266, 0.017), 0.0095, 8, true)
	# The steel wear strip along the bottom of the face, riveted.
	_strip(kit, m["edge"], m["steel"], prof[0], prof[1], W + 0.002, -0.0045, 0.014, 7, 0.0055, B)
	# A steel bracket from the shaft's socket to the back of the face, and a Y-brace from the shaft.
	var nrm := _prof_normals(prof)
	var plate := PackedVector2Array()
	for i in range(1, 6):
		plate.append(prof[i] - nrm[i] * 0.015)
	var rev := PackedVector2Array()
	for i in range(plate.size() - 1, -1, -1):
		rev.append(plate[i])
	_sheet(kit, m["frame"], rev, -0.08, 0.08, 0.006, B)
	kit.bevel_box(m["frame"], B * Transform3D(Basis(), Vector3(0, 0.03, -0.045)), Vector3(0.06, 0.04, 0.085), 0.008)
	var brace_at := up * 0.17
	_tube(kit, m["frame"], B * (brace_at - up * 0.018), B * (brace_at + up * 0.018), SHAFT_R + 0.005, 10, true)
	for s in [-1.0, 1.0]:
		_tube(kit, m["frame"], B * brace_at, B * Vector3(s * 0.21, 0.175, -0.002), 0.0065, 8, true)
		_rivet(kit, m["steel"], B * Vector3(s * 0.21, 0.175, -0.002), Vector3(0, 0.3, 0.95).normalized(), 0.008)


static func _scraper_blade(kit: MeshKit, m: Dictionary, t: ToolData, B: Transform3D) -> void:
	var W := t.width
	var large := W > 0.9
	var k := (0.26 if large else 0.21) / 0.21
	var up := -tip(String(t.id)).normalized()
	# A curved steel moldboard (like a small plow's), a bolted steel cutting edge at the bottom.
	var base := [Vector2(-0.072, 0.012), Vector2(-0.066, 0.035), Vector2(-0.052, 0.07), Vector2(-0.032, 0.11),
		Vector2(-0.01, 0.15), Vector2(0.01, 0.185), Vector2(0.022, 0.21)]
	var prof := PackedVector2Array()
	for p in base:
		prof.append(Vector2((p as Vector2).x * k, (p as Vector2).y * k))
	var H := prof[prof.size() - 1].y
	_sheet(kit, m["blade"], prof, -W * 0.5, W * 0.5, 0.005, B)
	edge_span[String(t.id)] = Vector2(-W * 0.5, W * 0.5)
	_tube(kit, m["blade"], B * Vector3(-W * 0.5, H + 0.002, prof[prof.size() - 1].x + 0.004), B * Vector3(W * 0.5, H + 0.002, prof[prof.size() - 1].x + 0.004), 0.007, 8, true)
	var e0 := Vector2(prof[0].x - 0.002, -0.004)
	var e1 := Vector2(prof[0].x + (prof[1].x - prof[0].x) * 1.4, 0.045 * k)
	_strip(kit, m["edge"], m["steel"], e0, e1, W, 0.005, 0.01, 5 if not large else 7, 0.0075, B)
	# Ribs down the back, a cross bar, and the pivot the shaft's angle plate turns on.
	var nrm := _prof_normals(prof)
	for x in ([-W * 0.3, 0.0, W * 0.3] if not large else [-W * 0.36, -W * 0.12, W * 0.12, W * 0.36]):
		var rib := PackedVector3Array()
		for i in range(1, prof.size()):
			var q := prof[i] - nrm[i] * 0.011
			rib.append(B * Vector3(x, q.y, q.x))
		_sweep(kit, m["frame"], rib, 0.0065, 6, true, true)
	var yb := 0.1 * k
	var zb := _prof_z_at(prof, yb) + 0.016
	_tube(kit, m["frame"], B * Vector3(-W * 0.42, yb, zb), B * Vector3(W * 0.42, yb, zb), 0.011, 10, true)
	var pv := up * PIVOT_S
	kit.cylinder(m["frame"], B * Transform3D(Basis(), pv + Vector3(0, -0.026, 0)), 0.034, 0.034, 0.044, 12, true)
	for s in [-1.0, 1.0]:
		_tube(kit, m["frame"], B * (pv + Vector3(s * 0.026, -0.012, -0.01)), B * Vector3(s * 0.075, yb, zb), 0.008, 8, true)
	# The angle plate: an arc of notches in front of the pivot, and the lock knob.
	for i in range(5):
		var a := deg_to_rad(-36.0 + 18.0 * i)
		kit.box(m["frame"], B * Transform3D(Basis(Vector3.UP, a), pv + Vector3(sin(a), 0, -cos(a)) * 0.062 + Vector3(0, 0.02, 0)), Vector3(0.022, 0.006, 0.024))
	kit.cylinder(m["accent"], B * Transform3D(Basis(), pv + Vector3(0, 0.024, -0.062)), 0.011, 0.009, 0.028, 8, true)
	if large:
		# Two small wheels behind the moldboard on brackets from the cross bar.
		var r := 0.07
		var wz := 0.11
		var wx := W * 0.5 - 0.15
		for s in [-1.0, 1.0]:
			_tube(kit, m["frame"], B * Vector3(s * wx, yb, zb), B * Vector3(s * wx, r, wz), 0.009, 8, true)
			_tube(kit, m["steel"], B * Vector3(s * (wx - 0.01), r, wz), B * Vector3(s * (wx + 0.05), r, wz), 0.008, 8, true)
			_wheel(kit, m["rubber"], m["hub"], B * Vector3(s * (wx + 0.03), r, wz), r, 0.036, 16, 0)


static func _sleigh_arm_ends(t: ToolData) -> Vector3:
	var T := tip(String(t.id))
	return Vector3(t.width * 0.5 + 0.016, T.y + 0.2, T.z + 0.2)


## The sleigh's U-bar: the crossbar both hands hold (through the origin, foam-covered) bending into
## two arms bolted to the tub's sides.
static func _sleigh_handle(kit: MeshKit, m: Dictionary, t: ToolData) -> void:
	var e := _sleigh_arm_ends(t)
	var path := PackedVector3Array()
	var rad := PackedFloat32Array()
	for s in [-1.0, 1.0]:
		var a := Vector3(s * e.x, e.y, e.z)
		var c := Vector3(s * 0.3, 0, 0)
		var dir := (c - a).normalized()
		var pts := [a, a.lerp(c, 0.5), c - dir * 0.075, c + Vector3(-s * 0.012, 0.0, 0.0), c + Vector3(-s * 0.075, 0, 0)]
		if s > 0.0:
			pts.reverse()
		for p in pts:
			path.append(p)
			rad.append(0.0125)
	var sp := _spline(path, rad, 3)
	_sweep(kit, m["bar"], sp[0], 0.0, 10, true, true, sp[1])
	_sweep(kit, m["foam"], PackedVector3Array([X * -0.25, X * -0.238, X * 0.238, X * 0.25]), 0.0, 12, true, true, PackedFloat32Array([0.013, 0.021, 0.021, 0.013]))


static func _sleigh_tub(kit: MeshKit, m: Dictionary, t: ToolData, B: Transform3D) -> void:
	var W := t.width
	# The floor (front edge first) curving up into the back wall.
	var prof := PackedVector2Array([Vector2(-0.45, 0.0), Vector2(-0.2, 0.0), Vector2(0.2, 0.0), Vector2(0.33, 0.008), Vector2(0.395, 0.04),
		Vector2(0.43, 0.11), Vector2(0.447, 0.2), Vector2(0.452, 0.3)])
	_sheet(kit, m["blade"], prof, -W * 0.5, W * 0.5, 0.01, B)
	edge_span[String(t.id)] = Vector2(-W * 0.5, W * 0.5)
	var wall := prof.duplicate()
	wall.append(Vector2(-0.43, 0.075))
	for s in [-1.0, 1.0]:
		_wall(kit, m["blade"], wall, s * (W * 0.5 - 0.006), 0.012, prof.size() - 1, B)
	# A rolled lip along the walls' top edge, round the back.
	var lip := PackedVector3Array()
	var lr := PackedFloat32Array()
	var hx := W * 0.5 - 0.012
	for p in [Vector3(-hx, 0.078, -0.43), Vector3(-hx, 0.19, 0.0), Vector3(-hx, 0.29, 0.405), Vector3(-hx, 0.3, 0.44), Vector3(-hx + 0.012, 0.302, 0.4515),
			Vector3(-hx + 0.04, 0.302, 0.452), Vector3(hx - 0.04, 0.302, 0.452), Vector3(hx - 0.012, 0.302, 0.4515), Vector3(hx, 0.3, 0.44), Vector3(hx, 0.29, 0.405),
			Vector3(hx, 0.19, 0.0), Vector3(hx, 0.078, -0.43)]:
		lip.append(B * p)
		lr.append(0.011)
	var sp := _spline(lip, lr, 3)
	_sweep(kit, m["blade"], sp[0], 0.0, 8, true, true, sp[1])
	# Runners underneath, the steel wear strip on the front edge, bolt plates for the bar.
	for x in [-0.27, 0.27]:
		kit.bevel_box(m["black"], B * Transform3D(Basis(), Vector3(x, -0.017, 0.0)), Vector3(0.036, 0.016, 0.84), 0.006)
	kit.bevel_box(m["edge"], B * Transform3D(Basis(), Vector3(0, -0.002, -0.43)), Vector3(W - 0.004, 0.017, 0.042), 0.003)
	for i in range(5):
		_rivet(kit, m["steel"], B * Vector3((-0.5 + (i + 0.5) / 5.0) * W * 0.9, 0.0075, -0.425), Vector3.UP, 0.0055)
	for s2 in [-1.0, 1.0]:
		kit.bevel_box(m["bar"], B * Transform3D(Basis(), Vector3(s2 * (W * 0.5 + 0.003), 0.2, 0.2)), Vector3(0.006, 0.07, 0.08), 0.002)


static func _electric_handle(kit: MeshKit, m: Dictionary, tool_id: String) -> void:
	var T := tip(tool_id)
	var L := T.length()
	var d := T / L
	var n := X.cross(d).normalized()
	var s0 := _d_grip(kit, m, d)
	# The trigger under the D's bar, the battery pack clipped on top of the shaft.
	kit.bevel_box(m["accent"], Transform3D(Basis(X, n, -d), d * 0.032 - n * 0.006), Vector3(0.026, 0.012, 0.03), 0.004)
	var bat := Transform3D(Basis(X, d, n), d * 0.24 + n * (SHAFT_R + 0.03))
	kit.bevel_box(m["black"], bat, Vector3(0.078, 0.15, 0.056), 0.012)
	kit.bevel_box(m["body"], bat * Transform3D(Basis(), Vector3(0, -0.01, 0.022)), Vector3(0.08, 0.11, 0.016), 0.005)
	for s in [0.18, 0.3]:
		_tube(kit, m["black"], d * (s - 0.012), d * (s + 0.012), 0.021, 10, true)
	_tube(kit, m["shaft"], d * s0, d * (L - 0.18), SHAFT_R, 12, false)
	_sleeve(kit, m["sleeve"], d, 0.42)
	_tube(kit, m["body"], d * (L - 0.2), d * L, 0.021, 12, true, 0.026)


## The electric shovel's head: a rubber two-paddle rotor in a shroud open at the front and bottom
## (the intake as wide as the tool's width), the motor housing behind, a hood that sends the snow
## forward.
static func _electric_head(kit: MeshKit, m: Dictionary, t: ToolData, B: Transform3D) -> void:
	var W := t.width
	var R := 0.115
	var c := Vector2(-0.17, 0.105)   # the rotor's axis (z, y)
	var arc := PackedVector2Array()
	for i in range(14):
		var th := deg_to_rad(250.0 - 195.0 * i / 13.0)
		arc.append(Vector2(c.x - R * cos(th), c.y + R * sin(th)))
	_sheet(kit, m["body"], arc, -W * 0.5, W * 0.5, 0.008, B)
	edge_span[String(t.id)] = Vector2(-W * 0.5, W * 0.5)
	for s in [-1.0, 1.0]:
		_side_plate(kit, m["body"], c, R + 0.012, 35.0, s * (W * 0.5 + 0.007), 0.014, B)
	_tube(kit, m["steel"], B * Vector3(-W * 0.5, c.y, c.x), B * Vector3(W * 0.5, c.y, c.x), 0.013, 10, true)
	for a in [deg_to_rad(25.0), deg_to_rad(205.0)]:
		var z := Vector3(0, sin(a), -cos(a))
		var y := z.cross(X)
		kit.bevel_box(m["rubber"], B * Transform3D(Basis(X, y, z), Vector3(0, c.y, c.x) + z * 0.058), Vector3(W - 0.02, 0.012, 0.1), 0.004)
	kit.box(m["steel"], B * Transform3D(Basis(), Vector3(0, 0.004, -0.13)), Vector3(W + 0.02, 0.01, 0.034))
	# The motor housing (two-tone), the neck up to the shaft's socket, vents.
	kit.bevel_box(m["body"], B * Transform3D(Basis(), Vector3(0, 0.125, 0.04)), Vector3(0.3, 0.17, 0.19), 0.045)
	kit.bevel_box(m["black"], B * Transform3D(Basis(), Vector3(0, 0.03, 0.04)), Vector3(0.31, 0.06, 0.2), 0.02)
	var up := -tip(String(t.id)).normalized()
	kit.bevel_box(m["body"], B * Transform3D(Basis(X, up, X.cross(up)), up * 0.08 + Vector3(0, 0.0, -0.012)), Vector3(0.11, 0.19, 0.085), 0.03)
	for s2 in [-1.0, 1.0]:
		for j in range(3):
			kit.box(m["black"], B * Transform3D(Basis(), Vector3(s2 * 0.151, 0.1 + j * 0.03, 0.04)), Vector3(0.004, 0.012, 0.11))
	# The discharge deflector over the top of the rotor, sending the snow forward.
	var hood := PackedVector2Array([Vector2(-0.13, 0.226), Vector2(-0.19, 0.25), Vector2(-0.25, 0.262), Vector2(-0.3, 0.256)])
	_sheet(kit, m["black"], hood, -W * 0.34, W * 0.34, 0.007, B)
	for s3 in [-1.0, 1.0]:
		var cheek := PackedVector2Array([Vector2(-0.13, 0.222), Vector2(-0.19, 0.246), Vector2(-0.25, 0.258), Vector2(-0.29, 0.252), Vector2(-0.24, 0.21)])
		_wall(kit, m["black"], cheek, s3 * W * 0.34, 0.008, 0, B)


# -----------------------------------------------------------------------------
# Walk-behind blowers (origin on the ground under the machine, -Z forward)
# -----------------------------------------------------------------------------

## Single-stage: a plastic auger housing with two twisted rubber paddles on each side, a scraper
## bar, the engine under a plastic cover, small wheels, the handle loop with its control bail.
static func _small_blower(kit: MeshKit, m: Dictionary, t: ToolData) -> void:
	var W := t.width
	var R := 0.19
	var c := Vector2(-0.36, 0.19)
	var arc := PackedVector2Array()
	for i in range(16):
		var th := deg_to_rad(262.0 - 190.0 * i / 15.0)
		arc.append(Vector2(c.x - R * cos(th), c.y + R * sin(th)))
	var I := Transform3D()
	_sheet(kit, m["body"], arc, -W * 0.5, W * 0.5, 0.008, I)
	edge_span[String(t.id)] = Vector2(-W * 0.5, W * 0.5)
	for s in [-1.0, 1.0]:
		_side_plate(kit, m["body"], c, R + 0.012, 62.0, s * (W * 0.5 + 0.006), 0.012, I)
	_tube(kit, m["steel"], Vector3(-W * 0.5, c.y, c.x), Vector3(W * 0.5, c.y, c.x), 0.03, 12, true)
	for s2 in [-1.0, 1.0]:
		for ph in [0.0, PI]:
			_helix(kit, m["rubber"], s2 * 0.035, s2 * (W * 0.5 - 0.015), c, 0.035, R - 0.02, ph + s2 * 0.4, s2 * 4.5, 6, 0.012, I)
	kit.box(m["steel"], Transform3D(Basis(), Vector3(0, 0.008, -0.335)), Vector3(W + 0.01, 0.014, 0.034))
	# The body: the engine under a red cover over a black chassis; the chute's base ring.
	kit.bevel_box(m["black"], Transform3D(Basis(), Vector3(0, 0.19, 0.08)), Vector3(0.46, 0.15, 0.5), 0.035)
	kit.bevel_box(m["body"], Transform3D(Basis(), Vector3(0, 0.355, 0.05)), Vector3(0.44, 0.22, 0.44), 0.08)
	kit.cylinder(m["black"], Transform3D(Basis(), Vector3(CHUTE_POS.x, 0.32, CHUTE_POS.z)), 0.1, 0.092, 0.05, 16, true)
	kit.cylinder(m["black"], Transform3D(Basis(), Vector3(0.1, 0.45, 0.12)), 0.03, 0.028, 0.03, 10, true)
	kit.cylinder(m["accent"], Transform3D(Basis(), Vector3(-0.1, 0.452, 0.15)), 0.018, 0.012, 0.02, 8, true)
	_tube(kit, m["black"], Vector3(0.22, 0.36, 0.12), Vector3(0.27, 0.36, 0.12), 0.006, 6, true)
	kit.bevel_box(m["black"], Transform3D(Basis(), Vector3(0.285, 0.36, 0.12)), Vector3(0.022, 0.026, 0.07), 0.008)
	for s3 in [-1.0, 1.0]:
		_wheel(kit, m["rubber"], m["hub"], Vector3(s3 * 0.265, 0.1, 0.17), 0.1, 0.05, 16, 0)
	_blower_handles(kit, m, Vector3(0.21, 0.3, 0.22), 1)


## Two-stage: a painted steel bucket with a steel spiral auger feeding the impeller and the chute,
## skid shoes and a scraper bar, an engine with its fuel tank, recoil starter and muffler, big
## lugged tyres, the handle loop with two bails and a dash.
static func _large_blower(kit: MeshKit, m: Dictionary, t: ToolData) -> void:
	var W := t.width
	var R := 0.24
	var c := Vector2(-0.4, 0.26)
	var arc := PackedVector2Array()
	for i in range(18):
		var th := deg_to_rad(265.0 - 190.0 * i / 17.0)
		arc.append(Vector2(c.x - R * cos(th), c.y + R * sin(th)))
	var I := Transform3D()
	_sheet(kit, m["body"], arc, -W * 0.5, W * 0.5, 0.008, I)
	edge_span[String(t.id)] = Vector2(-W * 0.5, W * 0.5)
	for s in [-1.0, 1.0]:
		_side_plate(kit, m["body"], c, R + 0.012, 66.0, s * (W * 0.5 + 0.007), 0.014, I)
		kit.bevel_box(m["steel"], Transform3D(Basis(), Vector3(s * (W * 0.5 + 0.024), 0.018, -0.39)), Vector3(0.02, 0.036, 0.22), 0.008)
	kit.box(m["steel"], Transform3D(Basis(), Vector3(0, 0.02, -0.4)), Vector3(W + 0.01, 0.016, 0.04))
	# The auger: two steel spirals on a shaft, turning the snow to the middle; the impeller's
	# opening in the back of the bucket.
	_tube(kit, m["steel"], Vector3(-W * 0.5, c.y, c.x), Vector3(W * 0.5, c.y, c.x), 0.024, 10, true)
	for s2 in [-1.0, 1.0]:
		_helix(kit, m["auger"], s2 * 0.075, s2 * (W * 0.5 - 0.02), c, 0.03, R - 0.03, 0.0, s2 * 22.0, 28, 0.006, I)
	for a in [0.0, PI]:
		var z := Vector3(0, sin(a + 0.6), -cos(a + 0.6))
		kit.box(m["auger"], Transform3D(Basis(X, z.cross(X), z), Vector3(0, c.y, c.x) + z * 0.1), Vector3(0.1, 0.006, 0.16))
	kit.cylinder(m["black"], Transform3D(Basis(X, Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, c.y + 0.02, c.x + R - 0.005)), 0.11, 0.11, 0.004, 16, true)
	# The impeller housing behind the bucket, up into the chute's base.
	kit.cylinder(m["body"], Transform3D(Basis(X, Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, 0.29, -0.17)), 0.155, 0.155, 0.12, 18, true)
	kit.cylinder(m["black"], Transform3D(Basis(), Vector3(CHUTE_POS.x, 0.42, CHUTE_POS.z)), 0.112, 0.105, 0.045, 16, true)
	# Frame and engine.
	kit.bevel_box(m["frame"], Transform3D(Basis(), Vector3(0, 0.27, 0.13)), Vector3(0.5, 0.05, 0.5), 0.012)
	kit.bevel_box(m["engine"], Transform3D(Basis(), Vector3(0, 0.42, 0.12)), Vector3(0.28, 0.24, 0.26), 0.03)
	for j in range(5):
		kit.box(m["engine"], Transform3D(Basis(), Vector3(-0.152, 0.34 + j * 0.035, 0.1)), Vector3(0.03, 0.008, 0.2))
	kit.cylinder(m["black"], Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0.14, 0.44, 0.13)), 0.115, 0.11, 0.05, 18, true)
	_tube(kit, m["black"], Vector3(0.19, 0.44, 0.13), Vector3(0.225, 0.46, 0.13), 0.005, 6, true)
	kit.bevel_box(m["black"], Transform3D(Basis(), Vector3(0.235, 0.465, 0.13)), Vector3(0.022, 0.028, 0.075), 0.008)
	kit.bevel_box(m["black"], Transform3D(Basis(), Vector3(0, 0.6, 0.11)), Vector3(0.25, 0.1, 0.22), 0.035)
	kit.bevel_box(m["body"], Transform3D(Basis(), Vector3(0, 0.605, 0.11)), Vector3(0.255, 0.05, 0.225), 0.012)
	kit.cylinder(m["black"], Transform3D(Basis(), Vector3(0.06, 0.65, 0.16)), 0.028, 0.026, 0.03, 10, true)
	_tube(kit, m["frame"], Vector3(-0.2, 0.42, 0.02), Vector3(-0.2, 0.42, 0.2), 0.035, 10, true)
	# Big lugged tyres on painted rims.
	for s3 in [-1.0, 1.0]:
		_wheel(kit, m["rubber"], m["body"], Vector3(s3 * 0.37, 0.19, 0.24), 0.19, 0.1, 20, 16)
		_tube(kit, m["steel"], Vector3(s3 * 0.24, 0.19, 0.24), Vector3(s3 * 0.33, 0.19, 0.24), 0.014, 8, true)
	_blower_handles(kit, m, Vector3(0.24, 0.32, 0.36), 2)
	# The dash between the handles.
	var dash := Transform3D(Basis(X, deg_to_rad(-35.0)), Vector3(0, 0.74, 0.5))
	kit.bevel_box(m["black"], dash, Vector3(0.48, 0.05, 0.13), 0.015)
	kit.cylinder(m["accent"], dash * Transform3D(Basis(), Vector3(0.1, 0.025, 0.0)), 0.009, 0.007, 0.05, 8, true)
	kit.cylinder(m["steel"], dash * Transform3D(Basis(), Vector3(-0.08, 0.025, 0.0)), 0.006, 0.006, 0.07, 6, true)


## The handle loop of a walk-behind blower: two painted tubes rising from the body to the grip bar
## (at 0.97 m, 0.66 m behind, ±0.26 m — where the player holds it), foam grips and the bails.
static func _blower_handles(kit: MeshKit, m: Dictionary, foot: Vector3, bails: int) -> void:
	var path := PackedVector3Array()
	var rad := PackedFloat32Array()
	for s in [-1.0, 1.0]:
		var pts := [Vector3(s * foot.x, foot.y, foot.z), Vector3(s * (foot.x + 0.02), 0.58, 0.45), Vector3(s * 0.26, 0.9, 0.63),
			Vector3(s * 0.25, 0.968, 0.66), Vector3(s * 0.19, 0.97, 0.66)]
		if s > 0.0:
			pts.reverse()
		for p in pts:
			path.append(p)
			rad.append(0.0135)
	var sp := _spline(path, rad, 3)
	_sweep(kit, m["frame"], sp[0], 0.0, 10, true, true, sp[1])
	for s2 in [-1.0, 1.0]:
		_sweep(kit, m["foam"], PackedVector3Array([Vector3(s2 * 0.235, 0.97, 0.66), Vector3(s2 * 0.225, 0.97, 0.66), Vector3(s2 * 0.1, 0.97, 0.66), Vector3(s2 * 0.09, 0.97, 0.66)]),
			0.0, 10, true, true, PackedFloat32Array([0.0145, 0.019, 0.019, 0.0145]))
		_tube(kit, m["frame"], Vector3(s2 * foot.x, foot.y, foot.z), Vector3(s2 * (foot.x - 0.03), foot.y - 0.06, foot.z - 0.05), 0.016, 8, true)
	var spans := [[-0.21, 0.21]] if bails == 1 else [[-0.23, -0.035], [0.035, 0.23]]
	for sp2 in spans:
		var a: float = sp2[0]
		var b: float = sp2[1]
		var bp := PackedVector3Array([Vector3(a, 0.972, 0.645), Vector3(a, 0.93, 0.615), Vector3(a + 0.02, 0.9, 0.6), Vector3(b - 0.02, 0.9, 0.6), Vector3(b, 0.93, 0.615), Vector3(b, 0.972, 0.645)])
		var br := PackedFloat32Array([0.0065, 0.0065, 0.0065, 0.0065, 0.0065, 0.0065])
		var bs := _spline(bp, br, 2)
		_sweep(kit, m["black"], bs[0], 0.0, 6, true, true, bs[1])


## The chute (origin at its pivot): a round tube up from the housing, bending forward into the
## deflector that sends the snow along -Z.
static func _blower_chute(kit: MeshKit, m: Dictionary, t: ToolData) -> void:
	var large := t.width > 0.65
	var r := 0.085 if large else 0.075
	var y0 := (0.42 + 0.045 - CHUTE_POS.y) if large else (0.32 + 0.05 - CHUTE_POS.y)
	var path := PackedVector3Array([Vector3(0, y0 - 0.01, 0), Vector3(0, 0.08, 0), Vector3(0, 0.17, -0.025), Vector3(0, 0.235, -0.09), Vector3(0, 0.26, -0.16)])
	var rad := PackedFloat32Array([r, r, r * 0.97, r * 0.93, r * 0.9])
	var sp := _spline(path, rad, 3)
	_sweep(kit, m["body"], sp[0], 0.0, 14, false, false, sp[1])
	var inner := PackedFloat32Array()
	for v in sp[1]:
		inner.append(float(v) - 0.006)
	_sweep(kit, m["black"], sp[0], 0.0, 14, false, false, inner, true)
	var last: Vector3 = sp[0][sp[0].size() - 1]
	var prev: Vector3 = sp[0][sp[0].size() - 2]
	var dir := (last - prev).normalized()
	_ring(kit, m["body"], last, dir, float(sp[1][sp[1].size() - 1]) - 0.006, float(sp[1][sp[1].size() - 1]), 14)
	# The deflector: a curved flap carrying on from the top of the mouth and bending down, and the
	# crank ring at the base.
	var r_end := float(sp[1][sp[1].size() - 1])
	var top := Vector3(0, -dir.z, dir.y)
	var lip := last + top * r_end
	var f1 := lip + dir * 0.05
	var f2 := f1 + dir * 0.05 - top * 0.014
	var f3 := f2 + dir * 0.035 - top * 0.032
	var hood := PackedVector2Array([Vector2(lip.z, lip.y), Vector2(f1.z, f1.y), Vector2(f2.z, f2.y), Vector2(f3.z, f3.y)])
	_sheet(kit, m["body"], hood, -r_end * 1.08, r_end * 1.08, 0.006, Transform3D())
	kit.cylinder(m["black"], Transform3D(Basis(), Vector3(0, y0 + 0.04, 0)), r + 0.016, r + 0.016, 0.03, 16, true)


# -----------------------------------------------------------------------------
# Building blocks
# -----------------------------------------------------------------------------

static func _nx(xf: Transform3D, n: Vector3) -> Vector3:
	return (xf.basis.inverse().transposed() * n).normalized()


## A straight tube (frustum) from a to b; radius r at a, r_b at b (r if negative).
static func _tube(kit: MeshKit, mat: Material, a: Vector3, b: Vector3, r: float, seg := 10, caps := true, r_b := -1.0) -> void:
	var v := b - a
	var h := v.length()
	if h < 1e-5:
		return
	var y := v / h
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	kit.cylinder(mat, Transform3D(Basis(x, y, z), a), r, r if r_b < 0.0 else r_b, h, seg, caps)


## A dome-headed rivet (or bolt head) sitting on a surface at p, facing along nrm.
static func _rivet(kit: MeshKit, mat: Material, p: Vector3, nrm: Vector3, r: float) -> void:
	_tube(kit, mat, p - nrm * r * 0.2, p + nrm * r * 0.55, r, 8, true, r * 0.5)


## A smooth curve through the points (per extra points between each pair; Hermite segments with
## tangents scaled to each segment's length, so short corner segments next to long straight ones
## don't overshoot); radii interpolated.
static func _spline(pts: PackedVector3Array, radii: PackedFloat32Array, per: int) -> Array:
	var out := PackedVector3Array()
	var rr := PackedFloat32Array()
	var n := pts.size()
	for i in range(n - 1):
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, n - 1)]
		var l0 := p1.distance_to(p0)
		var l1 := p2.distance_to(p1)
		var l2 := p3.distance_to(p2)
		var m1 := (p2 - p0) * (l1 / maxf(l0 + l1, 1e-6))
		var m2 := (p3 - p1) * (l1 / maxf(l1 + l2, 1e-6))
		for k in range(per + 1):
			var t := float(k) / float(per + 1)
			var t2 := t * t
			var t3 := t2 * t
			out.append((2.0 * t3 - 3.0 * t2 + 1.0) * p1 + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2 + (t3 - t2) * m2)
			rr.append(lerpf(radii[i], radii[i + 1], t))
	out.append(pts[n - 1])
	rr.append(radii[n - 1])
	return [out, rr]


## A tube swept along a path (rings carried along the bends); radius r or one per point.
## `inside`: faces point inwards (the inside of an open chute).
static func _sweep(kit: MeshKit, mat: Material, path: PackedVector3Array, r: float, seg := 10, cap_a := true, cap_b := true, radii := PackedFloat32Array(), inside := false) -> void:
	var n := path.size()
	if n < 2:
		return
	var tang: Array[Vector3] = []
	for i in range(n):
		var a: Vector3 = path[maxi(i - 1, 0)]
		var b: Vector3 = path[mini(i + 1, n - 1)]
		tang.append((b - a).normalized())
	var u: Vector3 = tang[0].cross(Vector3.UP if absf(tang[0].y) < 0.9 else Vector3.RIGHT).normalized()
	var lens := PackedFloat32Array([0.0])
	for i in range(1, n):
		lens.append(lens[i - 1] + path[i].distance_to(path[i - 1]))
	var total := maxf(lens[n - 1], 1e-5)
	var rings: Array = []
	var norms: Array = []
	var flip := -1.0 if inside else 1.0
	for i in range(n):
		var t: Vector3 = tang[i]
		u = (u - t * u.dot(t)).normalized()
		var w := t.cross(u)
		var rr: float = r if radii.is_empty() else radii[i]
		var ps := PackedVector3Array()
		var ns := PackedVector3Array()
		for k in range(seg):
			var a2 := TAU * k / seg
			var nn := u * cos(a2) + w * sin(a2)
			ps.append(path[i] + nn * rr)
			ns.append(nn * flip)
		rings.append(ps)
		norms.append(ns)
	for i in range(n - 1):
		var v0 := lens[i] / total
		var v1 := lens[i + 1] / total
		for k in range(seg):
			var k2 := (k + 1) % seg
			var pa: Vector3 = rings[i][k]
			var pb: Vector3 = rings[i][k2]
			var pc: Vector3 = rings[i + 1][k2]
			var pd: Vector3 = rings[i + 1][k]
			var na: Vector3 = norms[i][k]
			var nb: Vector3 = norms[i][k2]
			var nc: Vector3 = norms[i + 1][k2]
			var nd: Vector3 = norms[i + 1][k]
			var fn := (na + nb + nc + nd).normalized()
			var u0 := float(k) / seg
			var u1 := float(k + 1) / seg
			kit.tri(mat, pa, pb, pc, na, nb, nc, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), fn)
			kit.tri(mat, pa, pc, pd, na, nc, nd, Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1), fn)
	if cap_a:
		var c0 := -tang[0] * flip
		for k in range(seg):
			kit.tri(mat, path[0], rings[0][k], rings[0][(k + 1) % seg], c0, c0, c0, Vector2(0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 0.0), c0)
	if cap_b:
		var c1 := tang[n - 1] * flip
		for k in range(seg):
			kit.tri(mat, path[n - 1], rings[n - 1][k], rings[n - 1][(k + 1) % seg], c1, c1, c1, Vector2(0.5, 1.0), Vector2(0.5, 1.0), Vector2(0.5, 1.0), c1)


## A flat ring (annulus) at p facing along dir (the lip of an open tube).
static func _ring(kit: MeshKit, mat: Material, p: Vector3, dir: Vector3, r0: float, r1: float, seg: int) -> void:
	var u := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := dir.cross(u)
	for k in range(seg):
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		kit.quad(mat, p + d0 * r0, p + d1 * r0, p + d1 * r1, p + d0 * r1, dir)


## Inner-side normals of a profile (z, y), front edge first: the side a scoop holds its load on.
static func _prof_normals(prof: PackedVector2Array) -> PackedVector2Array:
	var n := prof.size()
	var segn := PackedVector2Array()
	for i in range(n - 1):
		var d := (prof[i + 1] - prof[i]).normalized()
		segn.append(Vector2(-d.y, d.x))
	var vn := PackedVector2Array()
	for i in range(n):
		vn.append((segn[maxi(i - 1, 0)] + segn[mini(i, n - 2)]).normalized())
	return vn


## z of a profile (front edge first, y rising) at height y.
static func _prof_z_at(prof: PackedVector2Array, y: float) -> float:
	for i in range(prof.size() - 1):
		if y >= prof[i].y and y <= prof[i + 1].y and prof[i + 1].y > prof[i].y:
			return lerpf(prof[i].x, prof[i + 1].x, (y - prof[i].y) / (prof[i + 1].y - prof[i].y))
	return prof[prof.size() - 1].x


## A thin curved sheet: the profile (z, y), front edge first, swept across x0..x1 in frame xf, the
## inner face on the profile and `thick` behind it. UV: u across, v along the profile from the
## front edge (0), so the material's edge wear lands on the edge that scrapes.
static func _sheet(kit: MeshKit, mat: Material, prof: PackedVector2Array, x0: float, x1: float, thick: float, xf: Transform3D) -> void:
	var n := prof.size()
	var vn := _prof_normals(prof)
	var lens := PackedFloat32Array([0.0])
	for i in range(1, n):
		lens.append(lens[i - 1] + prof[i].distance_to(prof[i - 1]))
	var total := maxf(lens[n - 1], 1e-5)
	var P := func(i: int, x: float, side: int) -> Vector3:
		var q: Vector2 = prof[i] - vn[i] * (thick * side)
		return xf * Vector3(x, q.y, q.x)
	var N := func(i: int, side: int) -> Vector3:
		var s := 1.0 if side == 0 else -1.0
		return _nx(xf, Vector3(0, vn[i].y, vn[i].x) * s)
	for i in range(n - 1):
		var v0 := lens[i] / total
		var v1 := lens[i + 1] / total
		for side in [0, 1]:
			var na: Vector3 = N.call(i, side)
			var nb: Vector3 = N.call(i + 1, side)
			var fn := (na + nb).normalized()
			var a: Vector3 = P.call(i, x0, side)
			var b: Vector3 = P.call(i + 1, x0, side)
			var c: Vector3 = P.call(i + 1, x1, side)
			var d: Vector3 = P.call(i, x1, side)
			kit.tri(mat, a, b, c, na, nb, nb, Vector2(0, v0), Vector2(0, v1), Vector2(1, v1), fn)
			kit.tri(mat, a, c, d, na, nb, na, Vector2(0, v0), Vector2(1, v1), Vector2(1, v0), fn)
		# The sheet's thickness at both ends.
		for e in [[x0, -1.0], [x1, 1.0]]:
			var ex: float = e[0]
			var en := _nx(xf, Vector3(e[1], 0, 0))
			kit.quad(mat, P.call(i, ex, 0), P.call(i + 1, ex, 0), P.call(i + 1, ex, 1), P.call(i, ex, 1), en, Vector2(0, v0), Vector2(0, v1), Vector2(0, v1), Vector2(0, v0))
	# The front and back lips.
	var d0 := (prof[1] - prof[0]).normalized()
	var d1 := (prof[n - 1] - prof[n - 2]).normalized()
	kit.quad(mat, P.call(0, x0, 0), P.call(0, x1, 0), P.call(0, x1, 1), P.call(0, x0, 1), _nx(xf, Vector3(0, -d0.y, -d0.x)), Vector2(0, 0), Vector2(1, 0), Vector2(1, 0), Vector2(0, 0))
	kit.quad(mat, P.call(n - 1, x0, 0), P.call(n - 1, x1, 0), P.call(n - 1, x1, 1), P.call(n - 1, x0, 1), _nx(xf, Vector3(0, d1.y, d1.x)), Vector2(0, 1), Vector2(1, 1), Vector2(1, 1), Vector2(0, 1))


## A flat plate in the plane x (thickness `thick` across x): the convex polygon poly (z, y), fanned
## from its first point; the edges from index `rim_from` round to the start get a rim.
static func _wall(kit: MeshKit, mat: Material, poly: PackedVector2Array, x: float, thick: float, rim_from: int, xf: Transform3D) -> void:
	var n := poly.size()
	for s in [-1.0, 1.0]:
		var xx: float = x + s * thick * 0.5
		var nrm := _nx(xf, Vector3(s, 0, 0))
		for i in range(1, n - 1):
			kit.tri(mat, xf * Vector3(xx, poly[0].y, poly[0].x), xf * Vector3(xx, poly[i].y, poly[i].x), xf * Vector3(xx, poly[i + 1].y, poly[i + 1].x),
				nrm, nrm, nrm, Vector2(0.5, 1), Vector2(0.5, 1), Vector2(0.5, 1), nrm)
	var cz := Vector2.ZERO
	for p in poly:
		cz += p
	cz /= float(n)
	for i in range(rim_from, n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var mid := (a + b) * 0.5
		var out := Vector2(-(b - a).y, (b - a).x).normalized()
		if out.dot(mid - cz) < 0.0:
			out = -out
		var en := _nx(xf, Vector3(0, out.y, out.x))
		var h := thick * 0.5
		kit.quad(mat, xf * Vector3(x - h, a.y, a.x), xf * Vector3(x + h, a.y, a.x), xf * Vector3(x + h, b.y, b.x), xf * Vector3(x - h, b.y, b.x), en, Vector2(0.5, 1), Vector2(0.5, 1), Vector2(0.5, 1), Vector2(0.5, 1))


## A housing's side plate in the plane x: round the back from the front top (angle a0, degrees;
## 0 = the front, 90 = the top) over the top and the back to the bottom (centre c (z, y), radius
## r), then flat along the bottom and straight up the front edge. `thick` across x, rimmed.
static func _side_plate(kit: MeshKit, mat: Material, c: Vector2, r: float, a0: float, x: float, thick: float, xf: Transform3D) -> void:
	var poly := PackedVector2Array()
	var steps := 16
	for i in range(steps + 1):
		var th := deg_to_rad(lerpf(a0, 270.0, float(i) / steps))
		poly.append(Vector2(c.x - r * cos(th), c.y + r * sin(th)))
	poly.append(Vector2(poly[0].x, c.y - r))
	_wall(kit, mat, poly, x, thick, 0, xf)


## A strip (wear strip, cutting edge) along the profile segment a -> b (z, y), across `width`, its
## middle `off` in front of the face (negative: behind it), `thick` thick, with `count` rivets of
## radius rr on its front.
static func _strip(kit: MeshKit, mat: Material, rivet_mat: Material, a: Vector2, b: Vector2, width: float, off: float, thick: float, count: int, rr: float, xf: Transform3D) -> void:
	var up2 := (b - a).normalized()
	var up := Vector3(0, up2.y, up2.x)
	var fwd := Vector3(0, up2.x, -up2.y)   # the face's front (its inner side)
	var seg_len := a.distance_to(b)
	var mid2 := (a + b) * 0.5
	var mid := Vector3(0, mid2.y, mid2.x) + fwd * off
	var basis := Basis(X, up, X.cross(up))
	kit.bevel_box(mat, xf * Transform3D(basis, mid), Vector3(width, seg_len, thick), 0.003)
	for i in range(count):
		var x := (-0.5 + (i + 0.5) / count) * width * 0.92
		_rivet(kit, rivet_mat, xf * (Vector3(x, 0, 0) + mid + fwd * (thick * 0.5)), _nx(xf, fwd), rr)


## A wheel across x at centre c: a tyre (with `lugs` tread blocks if > 0) and a hub on both sides.
static func _wheel(kit: MeshKit, tyre: Material, hub: Material, c: Vector3, r: float, w: float, seg: int, lugs: int) -> void:
	_tube(kit, tyre, c - X * w * 0.5, c + X * w * 0.5, r, seg, true)
	_tube(kit, hub, c - X * (w * 0.5 + 0.004), c + X * (w * 0.5 + 0.004), r * 0.56, seg, true)
	_tube(kit, hub, c - X * (w * 0.5 + 0.012), c + X * (w * 0.5 + 0.012), r * 0.16, 8, true)
	for i in range(lugs):
		var a := TAU * i / lugs
		var dir := Vector3(0, sin(a), cos(a))
		for s in [-1.0, 1.0]:
			var off: float = s * w * 0.22 + (0.012 if i % 2 == 0 else -0.012)
			var b := Basis(X, dir, X.cross(dir)) * Basis(dir, s * 0.35)
			kit.box(tyre, Transform3D(b, c + X * off + dir * (r + 0.004)), Vector3(w * 0.4, 0.014, 0.03))


## A twisted ribbon round the axis c (z, y) from x0 to x1: an auger paddle or a spiral flight.
static func _helix(kit: MeshKit, mat: Material, x0: float, x1: float, c: Vector2, r0: float, r1: float, phase: float, twist: float, steps: int, thick: float, xf: Transform3D) -> void:
	var P := func(x: float, r: float) -> Vector3:
		var ph := phase + twist * (x - x0)
		return xf * Vector3(x, c.y + r * sin(ph), c.x - r * cos(ph))
	for i in range(steps):
		var xa := lerpf(x0, x1, float(i) / steps)
		var xb := lerpf(x0, x1, float(i + 1) / steps)
		var a: Vector3 = P.call(xa, r0)
		var b: Vector3 = P.call(xa, r1)
		var c2: Vector3 = P.call(xb, r1)
		var d: Vector3 = P.call(xb, r0)
		var nrm := (b - a).cross(d - a).normalized()
		var o := nrm * thick * 0.5
		kit.quad(mat, a + o, b + o, c2 + o, d + o, nrm)
		kit.quad(mat, a - o, b - o, c2 - o, d - o, -nrm)
		kit.quad(mat, b - o, b + o, c2 + o, c2 - o, (b - a).normalized())
