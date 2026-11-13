class_name VehicleModels
extends RefCounted
## Procedural vehicle models. Vehicle faces local -Z; origin at ground level, centre of the body.
## Returns {mesh, wheels:[{pos, r}], blade_z, chute_pos, cab_cam, bed_rect, roof_snow:[Transform3D,size]}.
## Polish 7 playtest fix 3: a plow vehicle's also has blade_box, the space its blade fills in the
## blade's frame (the plate, its cutting edge and any lamps; not the arms behind it), which
## vehicle.gd makes solid; with blade_mult > 1 (the plow width upgrade) it has blade_lamps too, the
## lamps' lenses as a mesh of their own (the vehicle lights them with its headlights).

## Polish 7 playtest fix 3: the upgraded blade (blade_mult > 1): this blue, as wide as the strip it
## clears (blade_mult x the base width), UPGRADED_TALL x as tall, with two plow lamps on top.
const UPGRADED_BLUE := Color(0.1, 0.36, 0.92)
const UPGRADED_TALL := 1.2
const LAMP_LENS := Color(0.78, 0.78, 0.72)


static func build(vd: VehicleData, blade_mult := 1.0) -> Dictionary:
	var kit := MeshKit.new()
	var bkit := MeshKit.new()
	var up := blade_mult > 1.0
	var tall := UPGRADED_TALL if up else 1.0
	var lens_kit: MeshKit = MeshKit.new() if up else null
	var body := Mats.prop(vd.body_color, 0.25, 0.35)
	var dark := Mats.std(vd.accent_color, 0.6)
	var glass := Mats.std(Color(0.12, 0.15, 0.2), 0.12, 0.3)
	var chrome := Mats.metal(Color(0.75, 0.76, 0.78))
	var lamp := Mats.emissive(Color(1.0, 0.85, 0.55), 1.5)
	var tail := Mats.emissive(Color(0.9, 0.1, 0.08), 1.2)
	var blade_m := Mats.prop(UPGRADED_BLUE if up else Color(0.95, 0.75, 0.1), 0.4, 0.4)
	var L := vd.length
	var W := vd.width
	var info := {"wheels": [], "blade_z": -L * 0.5 - 0.6, "chute": Vector3(0, 2.0, -L * 0.5), "cab_cam": Vector3(-0.35, 1.6, -0.2),
		"bed": Rect2(), "snow": []}
	match vd.kind:
		VehicleData.Kind.PICKUP, VehicleData.Kind.PICKUP_PLOW:
			W = 2.0
			var wz := [-1.65, 1.5]
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 0.85, -1.55)), Vector3(W, 0.6, 1.9), 0.18)   # hood
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 1.3, -0.1)), Vector3(W, 1.1, 1.6), 0.2)     # cab
			kit.bevel_box(glass, Transform3D(Basis(Vector3(1, 0, 0), -0.35), Vector3(0, 1.55, -0.82)), Vector3(W - 0.18, 0.55, 0.06), 0.03)
			for s in [-1.0, 1.0]:
				kit.box(glass, Transform3D(Basis(), Vector3(s * (W * 0.5 + 0.005), 1.55, -0.15)), Vector3(0.02, 0.45, 1.25))
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 0.85, 1.55)), Vector3(W, 0.65, 2.3), 0.12)   # bed
			kit.box(dark, Transform3D(Basis(), Vector3(0, 1.12, 1.6)), Vector3(W - 0.25, 0.1, 2.1))
			kit.bevel_box(dark, Transform3D(Basis(), Vector3(0, 0.75, -2.5)), Vector3(W - 0.2, 0.4, 0.12), 0.05)  # grille
			for g in range(3):
				kit.box(chrome, Transform3D(Basis(), Vector3(0, 0.65 + g * 0.1, -2.57)), Vector3(W - 0.5, 0.03, 0.02))
			for s in [-1.0, 1.0]:
				kit.box(lamp, Transform3D(Basis(), Vector3(s * 0.75, 0.9, -2.52)), Vector3(0.36, 0.14, 0.04))
				kit.box(tail, Transform3D(Basis(), Vector3(s * 0.85, 0.95, 2.72)), Vector3(0.14, 0.3, 0.04))
				kit.bevel_box(dark, Transform3D(Basis(), Vector3(s * (W * 0.5 + 0.12), 1.55, -0.85)), Vector3(0.18, 0.14, 0.08), 0.03)  # mirrors
			kit.bevel_box(chrome, Transform3D(Basis(), Vector3(0, 0.45, -2.6)), Vector3(W, 0.18, 0.18), 0.05)
			kit.bevel_box(chrome, Transform3D(Basis(), Vector3(0, 0.45, 2.75)), Vector3(W, 0.16, 0.16), 0.05)
			for z in wz:
				for s in [-1.0, 1.0]:
					info["wheels"].append({"pos": Vector3(s * 0.92, 0.42, z), "r": 0.42})
			info["snow"] = [[Transform3D(Basis(), Vector3(0, 1.85, -0.1)), Vector2(1.9, 1.5)], [Transform3D(Basis(), Vector3(0, 1.15, -1.55)), Vector2(1.9, 1.8)], [Transform3D(Basis(), Vector3(0, 1.18, 1.55)), Vector2(1.9, 2.2)]]
			info["cab_cam"] = Vector3(-0.4, 1.65, -0.15)
			if vd.kind == VehicleData.Kind.PICKUP_PLOW:
				info["blade_box"] = _plow(bkit, blade_m, dark, 2.4 * blade_mult, 0.0, 0.75 * tall, lens_kit)
				info["blade_pivot"] = Vector3(0, 0, -3.05)
				info["blade_z"] = -3.15
		VehicleData.Kind.ATV:
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 0.75, 0)), Vector3(1.1, 0.4, 1.9), 0.15)
			kit.bevel_box(dark, Transform3D(Basis(), Vector3(0, 1.0, 0.25)), Vector3(0.45, 0.18, 0.8), 0.07)
			kit.cylinder(dark, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.4, 1.15, -0.55)), 0.025, 0.025, 0.8, 6, true)
			kit.box(dark, Transform3D(Basis(), Vector3(0, 0.95, -0.95)), Vector3(1.2, 0.08, 0.3))
			kit.box(dark, Transform3D(Basis(), Vector3(0, 0.95, 0.95)), Vector3(1.2, 0.08, 0.3))
			for z in [-0.7, 0.7]:
				for s in [-1.0, 1.0]:
					info["wheels"].append({"pos": Vector3(s * 0.62, 0.32, z), "r": 0.32})
			info["blade_box"] = _plow(bkit, blade_m, dark, 1.5 * blade_mult, 0.0, 0.5 * tall, lens_kit)
			info["blade_pivot"] = Vector3(0, 0, -1.6)
			info["blade_z"] = -1.7
			info["cab_cam"] = Vector3(0, 1.75, 0.3)
			info["snow"] = [[Transform3D(Basis(), Vector3(0, 1.0, -0.95)), Vector2(1.1, 0.3)], [Transform3D(Basis(), Vector3(0, 1.0, 0.95)), Vector2(1.1, 0.3)]]
		VehicleData.Kind.TRACTOR_BLADE, VehicleData.Kind.TRACTOR_BLOWER:
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 1.05, -0.8)), Vector3(1.0, 0.8, 1.8), 0.15)
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 1.0, 0.7)), Vector3(1.3, 0.7, 1.4), 0.1)
			kit.box(glass, Transform3D(Basis(), Vector3(0, 2.0, 0.65)), Vector3(1.35, 1.2, 1.3))
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 2.65, 0.65)), Vector3(1.55, 0.12, 1.5), 0.04)
			kit.cylinder(dark, Transform3D(Basis(), Vector3(0.3, 1.4, -1.3)), 0.06, 0.06, 0.9, 6, true)
			info["wheels"] = [{"pos": Vector3(-0.85, 0.75, 0.75), "r": 0.75}, {"pos": Vector3(0.85, 0.75, 0.75), "r": 0.75},
				{"pos": Vector3(-0.75, 0.45, -1.2), "r": 0.45}, {"pos": Vector3(0.75, 0.45, -1.2), "r": 0.45}]
			if vd.kind == VehicleData.Kind.TRACTOR_BLADE:
				info["blade_box"] = _plow(bkit, blade_m, dark, 2.4 * blade_mult, 0.0, 0.85 * tall, lens_kit)
				info["blade_pivot"] = Vector3(0, 0, -2.55)
				info["blade_z"] = -2.65
			else:
				var hb := Mats.prop(Color(0.85, 0.12, 0.1), 0.3, 0.4)
				kit.bevel_box(hb, Transform3D(Basis(), Vector3(0, 0.5, -2.5)), Vector3(2.1, 0.85, 0.8), 0.1)
				kit.cylinder(Mats.metal(Color(0.3, 0.3, 0.32)), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(1.0, 0.4, -2.85)), 0.32, 0.32, 2.0, 12, true)
				info["blade_z"] = -2.9
				info["chute"] = Vector3(0, 1.5, -2.4)
			info["cab_cam"] = Vector3(0, 2.15, 0.7)
			info["snow"] = [[Transform3D(Basis(), Vector3(0, 2.73, 0.65)), Vector2(1.5, 1.45)], [Transform3D(Basis(), Vector3(0, 1.47, -0.8)), Vector2(0.95, 1.7)]]
		VehicleData.Kind.GRADER:
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 1.3, -1.5)), Vector3(0.6, 0.45, 5.0), 0.1)
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 1.3, 2.4)), Vector3(2.2, 1.2, 2.6), 0.15)
			kit.box(glass, Transform3D(Basis(), Vector3(0, 2.45, 1.0)), Vector3(1.8, 1.2, 1.5))
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 3.1, 1.0)), Vector3(2.0, 0.12, 1.7), 0.04)
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 0.9, -3.9)), Vector3(1.6, 0.7, 0.7), 0.1)
			info["wheels"] = [{"pos": Vector3(-1.05, 0.6, -3.9), "r": 0.6}, {"pos": Vector3(1.05, 0.6, -3.9), "r": 0.6},
				{"pos": Vector3(-1.05, 0.6, 1.8), "r": 0.6}, {"pos": Vector3(1.05, 0.6, 1.8), "r": 0.6},
				{"pos": Vector3(-1.05, 0.6, 3.2), "r": 0.6}, {"pos": Vector3(1.05, 0.6, 3.2), "r": 0.6}]
			var gh := 0.6 * tall
			bkit.box(blade_m if up else Mats.metal(Color(0.3, 0.3, 0.32)), Transform3D(Basis(), Vector3(0, 0.15 + gh * 0.5, 0)), Vector3(3.7 * blade_mult, gh, 0.12))
			var gb := AABB(Vector3(-3.7 * blade_mult * 0.5, 0.15, -0.06), Vector3(3.7 * blade_mult, gh, 0.12))
			if lens_kit:
				gb = gb.merge(_plow_lamps(bkit, lens_kit, dark, gb.size.x * 0.5 - 0.3, Vector3(0, gb.end.y, 0)))
			info["blade_box"] = gb
			info["blade_pivot"] = Vector3(0, 0, -0.6)
			info["blade_z"] = -0.6
			info["cab_cam"] = Vector3(0, 2.6, 1.0)
			info["snow"] = [[Transform3D(Basis(), Vector3(0, 3.18, 1.0)), Vector2(1.9, 1.6)]]
		VehicleData.Kind.PLOW_TRUCK, VehicleData.Kind.ROTARY, VehicleData.Kind.DUMP_TRUCK:
			kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 1.45, -2.4)), Vector3(2.4, 1.9, 1.9), 0.2)
			kit.bevel_box(glass, Transform3D(Basis(), Vector3(0, 1.95, -3.36)), Vector3(2.2, 0.7, 0.05), 0.02)
			kit.box(dark, Transform3D(Basis(), Vector3(0, 0.8, -3.42)), Vector3(2.0, 0.6, 0.06))
			for s in [-1.0, 1.0]:
				kit.box(lamp, Transform3D(Basis(), Vector3(s * 0.9, 1.0, -3.45)), Vector3(0.3, 0.15, 0.04))
				kit.box(Mats.emissive(Color(1.0, 0.6, 0.1), 2.0), Transform3D(Basis(), Vector3(s * 0.7, 2.48, -2.3)), Vector3(0.25, 0.12, 0.25))
			kit.box(dark, Transform3D(Basis(), Vector3(0, 0.7, 0.8)), Vector3(1.0, 0.4, 6.0))
			info["wheels"] = [{"pos": Vector3(-1.1, 0.55, -2.4), "r": 0.55}, {"pos": Vector3(1.1, 0.55, -2.4), "r": 0.55},
				{"pos": Vector3(-1.1, 0.55, 1.6), "r": 0.55}, {"pos": Vector3(1.1, 0.55, 1.6), "r": 0.55},
				{"pos": Vector3(-1.1, 0.55, 2.9), "r": 0.55}, {"pos": Vector3(1.1, 0.55, 2.9), "r": 0.55}]
			info["cab_cam"] = Vector3(-0.5, 2.2, -2.5)
			info["snow"] = [[Transform3D(Basis(), Vector3(0, 2.42, -2.4)), Vector2(2.3, 1.8)]]
			if vd.kind == VehicleData.Kind.PLOW_TRUCK:
				kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 1.6, 1.8)), Vector3(2.5, 1.6, 3.6), 0.1)
				info["blade_box"] = _plow(bkit, blade_m if up else Mats.prop(Color(0.15, 0.15, 0.16), 0.4, 0.5), dark, 3.4 * blade_mult, 0.0, 1.1 * tall, lens_kit)
				info["blade_pivot"] = Vector3(0, 0, -4.3)
				info["blade_z"] = -4.4
				info["snow"].append([Transform3D(Basis(), Vector3(0, 2.42, 1.8)), Vector2(2.4, 3.5)])
			elif vd.kind == VehicleData.Kind.ROTARY:
				kit.bevel_box(body, Transform3D(Basis(), Vector3(0, 1.6, 1.6)), Vector3(2.5, 1.6, 3.4), 0.1)
				var drum := Mats.prop(Color(0.85, 0.85, 0.82), 0.3, 0.4)
				kit.bevel_box(drum, Transform3D(Basis(), Vector3(0, 1.1, -4.1)), Vector3(2.7, 2.0, 1.2), 0.2)
				kit.cylinder(Mats.metal(Color(0.3, 0.3, 0.32)), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 1.1, -4.65)), 0.9, 0.9, 0.2, 14, true)
				kit.cylinder(drum, Transform3D(Basis(), Vector3(0, 2.1, -3.9)), 0.3, 0.25, 1.2, 10, true)
				info["blade_z"] = -4.75
				info["chute"] = Vector3(0, 3.3, -3.9)
			else:
				var bed_m := Mats.prop(Color(0.55, 0.56, 0.58), 0.2, 0.5)
				kit.bevel_box(bed_m, Transform3D(Basis(), Vector3(0, 1.35, 1.7)), Vector3(2.5, 0.12, 4.4), 0.04)
				for s in [-1.0, 1.0]:
					kit.bevel_box(bed_m, Transform3D(Basis(), Vector3(s * 1.22, 2.0, 1.7)), Vector3(0.08, 1.3, 4.4), 0.03)
				kit.bevel_box(bed_m, Transform3D(Basis(), Vector3(0, 2.0, 3.88)), Vector3(2.5, 1.3, 0.08), 0.03)
				kit.bevel_box(bed_m, Transform3D(Basis(), Vector3(0, 2.0, -0.48)), Vector3(2.5, 1.3, 0.08), 0.03)
				info["bed"] = Rect2(-1.15, -0.4, 2.3, 4.2)
				info["bed_center"] = Vector3(0, 1.45, 1.7)
	# Wheels
	var tire := Mats.rubber()
	var hub := Mats.metal(Color(0.5, 0.52, 0.55))
	for w in info["wheels"]:
		var p: Vector3 = w["pos"]
		var r: float = w["r"]
		var wk := MeshKit.new()
		wk.cylinder(tire, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(r * 0.35, 0, 0)), r, r, r * 0.7, 14, true)
		wk.cylinder(hub, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(r * 0.37 * signf(p.x), 0, 0)), r * 0.5, r * 0.5, 0.03, 10, true)
		w["mesh"] = wk.commit()
	info["mesh"] = kit.commit()
	if not bkit.is_empty():
		info["blade_mesh"] = bkit.commit()
	if lens_kit and not lens_kit.is_empty():
		info["blade_lamps"] = lens_kit.commit()
	return info


## Polish 7 playtest fix 3: returns the space the plate (tilted 12°: its box) and its cutting edge
## fill, and the lamps when `lens_kit` is given (the upgraded blade), for the blade's solid shape.
## The arms behind the plate aren't counted.
static func _plow(kit: MeshKit, blade: Material, dark: Material, width: float, z: float, h: float, lens_kit: MeshKit = null) -> AABB:
	kit.bevel_box(blade, Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-12)), Vector3(0, h * 0.5 + 0.08, z)), Vector3(width, h, 0.1), 0.03)
	kit.box(Mats.metal(Color(0.4, 0.4, 0.42)), Transform3D(Basis(), Vector3(0, 0.06, z + 0.04)), Vector3(width, 0.06, 0.06))
	kit.box(dark, Transform3D(Basis(), Vector3(0, h * 0.45, z + 0.4)), Vector3(0.6, 0.15, 0.8))
	for s in [-0.6, 0.6]:
		kit.box(dark, Transform3D(Basis(), Vector3(s, h * 0.5, z + 0.25)), Vector3(0.1, 0.1, 0.5))
	var a := deg_to_rad(12.0)
	var hy := h * 0.5 * cos(a) + 0.05 * sin(a)
	var hz := h * 0.5 * sin(a) + 0.05 * cos(a)
	var out := AABB(Vector3(-width * 0.5, h * 0.5 + 0.08 - hy, z - hz), Vector3(width, hy * 2.0, hz * 2.0))
	out = out.merge(AABB(Vector3(-width * 0.5, 0.03, z + 0.01), Vector3(width, 0.06, 0.06)))
	if lens_kit:
		# The plate leans forward: the lamps stand on the middle of its top edge.
		out = out.merge(_plow_lamps(kit, lens_kit, dark, width * 0.5 - 0.3, Vector3(0, h * 0.5 + 0.08 + h * 0.5 * cos(a), z - h * 0.5 * sin(a))))
	return out


## Polish 7 playtest fix 3: the upgraded blade's two plow lamps, at ±xs along its top edge (its middle
## at `top`): housings on short brackets (in `kit`), their lenses facing ahead (in `lens_kit`).
## Returns the space they fill.
static func _plow_lamps(kit: MeshKit, lens_kit: MeshKit, dark: Material, xs: float, top: Vector3) -> AABB:
	var out := AABB()
	for s in [-1.0, 1.0]:
		var c := top + Vector3(s * xs, 0, 0)
		kit.box(dark, Transform3D(Basis(), c + Vector3(0, 0.04, 0)), Vector3(0.05, 0.08, 0.05))
		kit.bevel_box(dark, Transform3D(Basis(), c + Vector3(0, 0.15, 0)), Vector3(0.24, 0.14, 0.14), 0.03)
		lens_kit.box(Mats.std(LAMP_LENS, 0.3), Transform3D(Basis(), c + Vector3(0, 0.15, -0.075)), Vector3(0.18, 0.1, 0.02))
		var box := AABB(c + Vector3(-0.12, 0.0, -0.085), Vector3(0.24, 0.22, 0.155))
		out = box if s < 0.0 else out.merge(box)
	return out
