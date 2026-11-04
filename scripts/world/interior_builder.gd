class_name InteriorBuilder
extends RefCounted
## Furnishes the hollow houses (player home, tutorial neighbor) and places their interactables.
## Coordinates are in the canonical house frame (see HouseBuilder): floor at y = PORCH_H.

const FY := Layout.PORCH_H
const WALL_INNER := 0.165       # the front wall's inner (room) face, from its line (HouseBuilder._wall_x)
const PHOTO_EYE_H := 1.6        # the framed photo's centre above the floor (eye height)


static func build_player(world: Node, root: Node3D, lot: Dictionary) -> Dictionary:
	var L := HouseBuilder.lot_transform(lot)
	var sb: float = lot["setback"]
	var kit := MeshKit.new()
	var out := {}
	var wood := Mats.wood(Color(0.5, 0.33, 0.2), 0.0)
	var dark_wood := Mats.wood(Color(0.32, 0.22, 0.15), 0.0)
	var fabric := Mats.fabric(Color(0.42, 0.5, 0.6))
	var stone := Mats.std(Color(0.5, 0.48, 0.47), 0.9)
	# Rug
	kit.box(Mats.fabric(Color(0.55, 0.2, 0.18)), L * Transform3D(Basis(), Vector3(-6.0, FY + 0.01, sb + 2.6)), Vector3(3.2, 0.02, 2.2))
	# Fireplace on the left wall
	var fx := HouseBuilder.BODY_X0 + 0.45
	var fz := sb + 2.6
	kit.box(stone, L * Transform3D(Basis(), Vector3(fx, FY + 0.65, fz)), Vector3(0.6, 1.3, 1.7))
	kit.box(stone, L * Transform3D(Basis(), Vector3(fx - 0.05, FY + 2.0, fz)), Vector3(0.45, 1.6, 1.1))
	kit.box(dark_wood, L * Transform3D(Basis(), Vector3(fx + 0.12, FY + 1.35, fz)), Vector3(0.5, 0.08, 1.9))
	kit.box(Mats.std(Color(0.08, 0.06, 0.05), 0.9), L * Transform3D(Basis(), Vector3(fx + 0.2, FY + 0.5, fz)), Vector3(0.25, 0.65, 0.95))
	var fire := MeshInstance3D.new()
	var fk := MeshKit.new()
	fk.box(Mats.emissive(Color(1.0, 0.45, 0.1), 3.5), Transform3D(Basis(), Vector3(0, 0.2, 0)), Vector3(0.12, 0.35, 0.7))
	fk.box(Mats.emissive(Color(1.0, 0.75, 0.25), 4.0), Transform3D(Basis(), Vector3(0.03, 0.12, 0)), Vector3(0.1, 0.2, 0.5))
	fire.mesh = fk.commit()
	root.add_child(fire)
	fire.global_position = L * Vector3(fx + 0.26, FY + 0.2, fz)
	out["fire_mesh"] = fire
	out["fireplace_pos"] = L * Vector3(fx + 0.8, FY, fz)
	# Couch facing the TV (back to the front window)
	var cx := -6.0
	var cz := sb + 1.35
	kit.bevel_box(fabric, L * Transform3D(Basis(), Vector3(cx, FY + 0.25, cz)), Vector3(2.2, 0.45, 0.85), 0.1)
	kit.bevel_box(fabric, L * Transform3D(Basis(), Vector3(cx, FY + 0.65, cz - 0.35)), Vector3(2.2, 0.6, 0.22), 0.1)
	for s in [-1.0, 1.0]:
		kit.bevel_box(fabric, L * Transform3D(Basis(), Vector3(cx + s * 1.1, FY + 0.45, cz)), Vector3(0.22, 0.5, 0.85), 0.08)
	kit.bevel_box(Mats.fabric(Color(0.85, 0.75, 0.55)), L * Transform3D(Basis(Vector3.UP, 0.3), Vector3(cx - 0.6, FY + 0.58, cz - 0.15)), Vector3(0.4, 0.35, 0.12), 0.06)
	# TV stand + TV on the partition wall
	var tvz := sb + 4.65
	kit.box(dark_wood, L * Transform3D(Basis(), Vector3(-6.0, FY + 0.3, tvz)), Vector3(1.8, 0.6, 0.45))
	kit.box(Mats.std(Color(0.05, 0.05, 0.06), 0.3), L * Transform3D(Basis(), Vector3(-6.0, FY + 1.05, tvz + 0.05)), Vector3(1.4, 0.82, 0.06))
	var screen := MeshInstance3D.new()
	var sk := MeshKit.new()
	sk.box(Mats.emissive(Color(0.35, 0.55, 0.85), 1.2), Transform3D(), Vector3(1.3, 0.72, 0.01))
	screen.mesh = sk.commit()
	root.add_child(screen)
	screen.global_transform = L * Transform3D(Basis(), Vector3(-6.0, FY + 1.05, tvz - 0.0))
	out["tv_screen"] = screen
	# Coffee table, lamp
	kit.box(wood, L * Transform3D(Basis(), Vector3(-6.0, FY + 0.22, sb + 2.7)), Vector3(1.1, 0.06, 0.6))
	for lx in [-0.5, 0.5]:
		for lz in [-0.25, 0.25]:
			kit.box(wood, L * Transform3D(Basis(), Vector3(-6.0 + lx, FY + 0.1, sb + 2.7 + lz)), Vector3(0.05, 0.2, 0.05))
	_floor_lamp_base(kit, L, Vector3(-3.6, FY, sb + 0.6))
	kit.cylinder(Mats.emissive(Color(1.0, 0.85, 0.6), 1.3), L * Transform3D(Basis(), Vector3(-3.6, FY + 1.35, sb + 0.6)), 0.25, 0.15, 0.3, 10, true)
	_house_plant(kit, L, Vector3(-8.6, FY, sb + 0.5))
	# Kitchen counter along the back wall, radio on it
	kit.box(Mats.std(Color(0.88, 0.86, 0.82), 0.6), L * Transform3D(Basis(), Vector3(-1.1, FY + 0.45, sb + 8.55)), Vector3(3.0, 0.9, 0.6))
	kit.box(Mats.std(Color(0.25, 0.25, 0.27), 0.4), L * Transform3D(Basis(), Vector3(-1.1, FY + 0.92, sb + 8.55)), Vector3(3.1, 0.05, 0.65))
	kit.bevel_box(Mats.std(Color(0.55, 0.15, 0.12), 0.5), L * Transform3D(Basis(), Vector3(-2.1, FY + 1.07, sb + 8.6)), Vector3(0.36, 0.22, 0.14), 0.03)
	out["radio_pos"] = L * Vector3(-2.1, FY + 1.07, sb + 8.6)
	# Computer desk with UPS battery backup
	var dx := 1.75
	var dz := sb + 8.45
	kit.box(wood, L * Transform3D(Basis(), Vector3(dx, FY + 0.74, dz)), Vector3(1.4, 0.05, 0.7))
	for lx2 in [-0.65, 0.65]:
		kit.box(wood, L * Transform3D(Basis(), Vector3(dx + lx2, FY + 0.37, dz)), Vector3(0.05, 0.74, 0.65))
	kit.box(Mats.std(Color(0.08, 0.08, 0.09), 0.4), L * Transform3D(Basis(), Vector3(dx, FY + 1.1, dz + 0.2)), Vector3(0.6, 0.38, 0.04))
	kit.box(Mats.std(Color(0.1, 0.1, 0.1), 0.4), L * Transform3D(Basis(), Vector3(dx, FY + 0.82, dz + 0.2)), Vector3(0.08, 0.15, 0.08))
	kit.box(Mats.std(Color(0.15, 0.15, 0.16), 0.6), L * Transform3D(Basis(), Vector3(dx, FY + 0.78, dz - 0.05)), Vector3(0.45, 0.02, 0.15))
	_desk_peripherals(kit, L, Vector3(dx, FY + 0.765, dz))
	kit.box(Mats.std(Color(0.12, 0.12, 0.13), 0.5), L * Transform3D(Basis(), Vector3(dx + 0.5, FY + 0.2, dz + 0.1)), Vector3(0.18, 0.4, 0.35))
	kit.box(Mats.std(Color(0.2, 0.2, 0.22), 0.5), L * Transform3D(Basis(), Vector3(dx - 0.45, FY + 0.12, dz + 0.1)), Vector3(0.2, 0.24, 0.32))
	var ups_led := MeshInstance3D.new()
	var lk := MeshKit.new()
	lk.box(Mats.emissive(Color(0.2, 1.0, 0.3), 3.0), Transform3D(), Vector3(0.04, 0.03, 0.01))
	ups_led.mesh = lk.commit()
	root.add_child(ups_led)
	ups_led.global_position = L * Vector3(dx - 0.45, FY + 0.2, dz - 0.07)
	out["ups_led"] = ups_led
	# Polish 4 §2: the monitor shows a desktop (or the lock screen) rendered by ComputerScreen.
	var monitor := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.54, 0.32)
	monitor.mesh = qm
	monitor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(monitor)
	monitor.global_transform = L * Transform3D(Basis(Vector3.UP, PI), Vector3(dx, FY + 1.1, dz + 0.177))
	out["monitor"] = monitor
	out["screen"] = ComputerScreen.make(root, monitor)
	# Office chair: the seat and back as before, now on a gas-lift column, a five-spoke base and
	# casters resting on the floor (its own mesh; no collider, as before).
	var ck := MeshKit.new()
	ck.bevel_box(Mats.fabric(Color(0.2, 0.2, 0.22)), L * Transform3D(Basis(), Vector3(dx, FY + 0.45, dz - 0.7)), Vector3(0.5, 0.08, 0.5), 0.04)
	ck.bevel_box(Mats.fabric(Color(0.2, 0.2, 0.22)), L * Transform3D(Basis(), Vector3(dx, FY + 0.8, dz - 0.95)), Vector3(0.5, 0.6, 0.08), 0.04)
	out["chair_casters"] = _chair_base(ck, L, Vector3(dx, FY, dz - 0.7), dz - 0.95)
	var chair := MeshInstance3D.new()
	chair.name = "OfficeChair"
	chair.mesh = ck.commit()
	chair.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(chair)
	out["chair"] = chair
	# Bedroom: bed + nightstand
	var bx := -6.6
	var bz := sb + 7.9
	kit.box(dark_wood, L * Transform3D(Basis(), Vector3(bx, FY + 0.22, bz)), Vector3(1.6, 0.44, 2.1))
	kit.bevel_box(Mats.fabric(Color(0.92, 0.92, 0.9)), L * Transform3D(Basis(), Vector3(bx, FY + 0.52, bz)), Vector3(1.5, 0.2, 2.0), 0.08)
	kit.bevel_box(Mats.fabric(Color(0.3, 0.42, 0.65)), L * Transform3D(Basis(), Vector3(bx, FY + 0.64, bz - 0.25)), Vector3(1.56, 0.1, 1.4), 0.05)
	kit.bevel_box(Mats.fabric(Color(0.95, 0.95, 0.95)), L * Transform3D(Basis(), Vector3(bx, FY + 0.7, bz + 0.72)), Vector3(1.2, 0.15, 0.4), 0.07)
	kit.box(dark_wood, L * Transform3D(Basis(), Vector3(bx, FY + 0.7, bz + 1.02)), Vector3(1.7, 1.4, 0.08))
	kit.box(wood, L * Transform3D(Basis(), Vector3(bx + 1.2, FY + 0.3, bz + 0.7)), Vector3(0.5, 0.6, 0.45))
	_table_lamp(kit, L, Vector3(bx + 1.2, FY + 0.6, bz + 0.7))
	# Coat rack by the door: a rail with pegs, a parka, a toque and a scarf (cozy detail)
	_coat_rack(kit, L, dark_wood, Vector3(0.6, FY + 1.7, sb + 0.15))
	# Polish 4 §5: a framed photo on the wall beside the front door, centred in the free wall
	# between the door opening (x -2.05) and the floor lamp's shade (x -3.6 + 0.25), at eye height,
	# flat on the wall's inner face.
	var pic_x := (-2.05 + (-3.6 + 0.25)) * 0.5
	out["photo"] = FramedPhoto.make(root, L * Transform3D(Basis(), Vector3(pic_x, FY + PHOTO_EYE_H, sb + WALL_INNER)))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# Furniture colliders
	var body := StaticBody3D.new()
	root.add_child(body)
	for spec in [[Vector3(cx, FY + 0.4, cz), Vector3(2.4, 0.8, 0.9)], [Vector3(-6.0, FY + 0.5, tvz), Vector3(1.8, 1.0, 0.5)],
			[Vector3(-1.1, FY + 0.5, sb + 8.55), Vector3(3.0, 1.0, 0.6)], [Vector3(dx, FY + 0.5, dz), Vector3(1.4, 1.0, 0.7)],
			[Vector3(bx, FY + 0.4, bz), Vector3(1.6, 0.8, 2.1)], [Vector3(fx, FY + 0.8, fz), Vector3(0.6, 1.6, 1.7)]]:
		HouseBuilder._add_box_shape(body, L, spec[0], spec[1])
	# Lights (switched off during a power outage)
	var lights := []
	for lp in [Vector3(-6.0, FY + 2.2, sb + 2.5), Vector3(-6.5, FY + 2.2, sb + 7.2), Vector3(0.2, FY + 2.2, sb + 6.8)]:
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.8, 0.55)
		ol.light_energy = 1.1
		ol.omni_range = 6.0
		ol.shadow_enabled = false
		root.add_child(ol)
		ol.global_position = L * lp
		lights.append(ol)
	var fire_light := OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.55, 0.2)
	fire_light.light_energy = 1.4
	fire_light.omni_range = 5.0
	root.add_child(fire_light)
	fire_light.global_position = L * Vector3(fx + 0.9, FY + 0.7, fz)
	out["lights"] = lights
	out["fire_light"] = fire_light
	# Interactables
	out["bed"] = Interactable.make(root, L * Vector3(bx, FY + 0.6, bz), Vector3(1.6, 0.8, 2.1),
		func(_p): return "[E] Go to sleep", func(_p): world.open_sleep())
	out["computer"] = Interactable.make(root, L * Vector3(dx, FY + 1.0, dz), Vector3(1.4, 0.9, 0.8),
		func(_p): return ("[E] Use computer" + ("  (battery backup)" if not Survival.power_on else "")) if Game.computer_unlocked() else "[E] Computer (locked)", func(_p): world.open_computer())
	out["tv"] = Interactable.make(root, L * Vector3(-6.0, FY + 1.0, tvz), Vector3(1.6, 1.0, 0.5),
		func(_p): return "[E] Watch the weather on TV" if Survival.power_on else "TV (no power)", func(_p): world.open_tv())
	out["radio"] = Interactable.make(root, out["radio_pos"], Vector3(0.5, 0.4, 0.4),
		func(_p): return "[E] Listen to the radio forecast", func(_p): world.radio_forecast())
	out["fireplace"] = Interactable.make(root, L * Vector3(fx + 0.2, FY + 0.7, fz), Vector3(0.8, 1.4, 1.7),
		func(_p): return "Fireplace — stand close to warm up" if Survival.power_on else "Fireplace (the furnace fan and igniter are off — no power)", func(_p): pass)
	return out


# -----------------------------------------------------------------------------
# Polish 3 §3: small props that read as what they are
# -----------------------------------------------------------------------------

static var _two_sided := {}


## Material drawn from both sides (leaves, the lamp shade's inside, a pot rim).
static func _mat2(color: Color, emission := 0.0) -> StandardMaterial3D:
	var k := "%s/%s" % [str(color), str(emission)]
	if not _two_sided.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if emission > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = emission
		_two_sided[k] = m
	return _two_sided[k]


# -----------------------------------------------------------------------------
# Polish 4 §2: chair base, desk peripherals, the living-room lamp's base
# -----------------------------------------------------------------------------

## Gas-lift column, five-spoke base and twin-wheel casters under a chair seat centred over `floor`
## (house frame, floor height). The back's support bar meets the back at `back_z`. Returns the
## world positions of the casters' contact points with the floor.
static func _chair_base(kit: MeshKit, L: Transform3D, floor_pos: Vector3, back_z: float) -> Array:
	var black := Mats.std(Color(0.07, 0.07, 0.08), 0.45)
	var chrome := Mats.metal(Color(0.72, 0.74, 0.78))
	var x := floor_pos.x
	var z := floor_pos.z
	var y := floor_pos.y
	# Tilt mechanism under the seat, the column (chrome lift in a black sleeve), the hub.
	kit.box(black, L * Transform3D(Basis(), Vector3(x, y + 0.385, z)), Vector3(0.2, 0.03, 0.2))
	kit.cylinder(chrome, L * Transform3D(Basis(), Vector3(x, y + 0.2, z)), 0.022, 0.022, 0.17, 10, false)
	kit.cylinder(black, L * Transform3D(Basis(), Vector3(x, y + 0.09, z)), 0.034, 0.03, 0.13, 10, true)
	kit.cylinder(black, L * Transform3D(Basis(), Vector3(x, y + 0.075, z)), 0.06, 0.055, 0.04, 12, true)
	# Back support: a bar from under the seat to the back.
	kit.box(black, L * Transform3D(Basis(), Vector3(x, y + 0.385, (z + back_z) * 0.5 - 0.02)), Vector3(0.05, 0.025, absf(back_z - z) - 0.02))
	kit.box(black, L * Transform3D(Basis(), Vector3(x, y + 0.48, back_z + 0.035)), Vector3(0.05, 0.2, 0.025))
	var contacts := []
	var arm := 0.29
	var wheel_r := 0.026
	for k in range(5):
		var a := TAU * k / 5.0 + PI * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		# Spoke: slightly sloped down to its tip.
		var mid := Vector3(x, y + 0.085, z) + d * (arm * 0.5 + 0.02)
		kit.box(black, L * Transform3D(Basis(Vector3.UP, -a), mid), Vector3(arm, 0.032, 0.036))
		var tip := Vector3(x, y, z) + d * (arm + 0.02)
		# Caster: a swivel stem, a fork and twin wheels touching the floor.
		kit.cylinder(black, L * Transform3D(Basis(), tip + Vector3(0, 0.055, 0)), 0.009, 0.009, 0.03, 6, false)
		kit.box(black, L * Transform3D(Basis(Vector3.UP, -a), tip + Vector3(0, 0.045, 0)), Vector3(0.03, 0.02, 0.05))
		var side := Vector3(-d.z, 0, d.x)
		for sgn in [-1.0, 1.0]:
			var wc: Vector3 = tip + Vector3(0, wheel_r, 0) + side * (0.011 * sgn)
			# Axle along `side`: the cylinder's local Y runs along it.
			var wb := Basis(Vector3.UP, side, Vector3.UP.cross(side))
			kit.cylinder(black, L * Transform3D(wb, wc - side * 0.0045), wheel_r, wheel_r, 0.009, 10, true)
		contacts.append(L * tip)
	return contacts


## Keyboard key rows, a mouse on a pad, a pair of speakers and a monitor foot on the desk top
## (`top`: desk centre at the height of its surface, house frame).
static func _desk_peripherals(kit: MeshKit, L: Transform3D, top: Vector3) -> void:
	var key := Mats.std(Color(0.26, 0.27, 0.29), 0.55)
	var dark := Mats.std(Color(0.1, 0.1, 0.11), 0.4)
	var kb := top + Vector3(0, 0.025, -0.05)   # keyboard deck top
	for r in range(4):
		var n := 13 - (1 if r == 3 else 0)
		for c in range(n):
			var kx := -0.198 + c * 0.033 + (0.012 if r % 2 == 1 else 0.0)
			kit.box(key, L * Transform3D(Basis(), kb + Vector3(kx, 0.004, -0.045 + r * 0.03)), Vector3(0.027, 0.008, 0.024))
	kit.box(key, L * Transform3D(Basis(), kb + Vector3(0.0, 0.004, -0.045 + 4 * 0.03 - 0.005)), Vector3(0.16, 0.008, 0.022))
	# Mouse pad and mouse.
	kit.box(Mats.fabric(Color(0.14, 0.2, 0.32)), L * Transform3D(Basis(), top + Vector3(0.4, 0.002, -0.07)), Vector3(0.22, 0.004, 0.19))
	kit.bevel_box(dark, L * Transform3D(Basis(Vector3.UP, 0.12), top + Vector3(0.41, 0.017, -0.08)), Vector3(0.06, 0.026, 0.1), 0.012)
	# Speakers either side of the monitor, with their cones.
	for sx in [-0.43, 0.43]:
		kit.box(dark, L * Transform3D(Basis(), top + Vector3(sx, 0.09, 0.18)), Vector3(0.09, 0.18, 0.09))
		kit.cylinder(Mats.std(Color(0.2, 0.2, 0.22), 0.7), L * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), top + Vector3(sx, 0.11, 0.134)), 0.028, 0.028, 0.004, 12, true)
		kit.cylinder(Mats.std(Color(0.2, 0.2, 0.22), 0.7), L * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), top + Vector3(sx, 0.045, 0.134)), 0.016, 0.016, 0.004, 10, true)
	# Monitor foot under the stand's neck.
	kit.box(dark, L * Transform3D(Basis(), top + Vector3(0, 0.007, 0.2)), Vector3(0.26, 0.014, 0.18))
	# The tower under the desk (the box beside the right leg): a front bezel with two drive bays, a
	# power button with its blue light, and an intake grille along the bottom.
	var tw := top + Vector3(0.5, -0.565, 0.1)       # the tower's centre; its front faces the chair
	var fz := -0.175 - 0.003
	kit.box(Mats.std(Color(0.18, 0.18, 0.19), 0.45), L * Transform3D(Basis(), tw + Vector3(0, 0.0, fz)), Vector3(0.16, 0.38, 0.006))
	for by in [0.135, 0.105]:
		kit.box(Mats.std(Color(0.07, 0.07, 0.08), 0.5), L * Transform3D(Basis(), tw + Vector3(0, by, fz - 0.004)), Vector3(0.13, 0.022, 0.004))
	kit.cylinder(Mats.std(Color(0.3, 0.3, 0.32), 0.3), L * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), tw + Vector3(0.0, 0.06, fz - 0.003)), 0.012, 0.012, 0.005, 12, true)
	kit.box(Mats.emissive(Color(0.3, 0.6, 1.0), 2.0), L * Transform3D(Basis(), tw + Vector3(0.0, 0.035, fz - 0.004)), Vector3(0.03, 0.004, 0.003))
	for gy in range(5):
		kit.box(Mats.std(Color(0.06, 0.06, 0.07), 0.6), L * Transform3D(Basis(), tw + Vector3(0, -0.16 + gy * 0.014, fz - 0.004)), Vector3(0.12, 0.005, 0.003))


## The living-room floor lamp's base, turned like a real one: a wide, heavy foot, a rounded body,
## a neck narrowing up to the slim stem, and a socket under the shade (the shade and its glow are
## unchanged). `floor`: where it stands (house frame).
static func _floor_lamp_base(kit: MeshKit, L: Transform3D, floor_pos: Vector3) -> void:
	var m := Mats.metal(Color(0.3, 0.3, 0.3))
	# [height from the floor, radius] down the turned profile, from the foot up to the stem.
	var prof := [[0.0, 0.19], [0.022, 0.19], [0.032, 0.172], [0.05, 0.13], [0.09, 0.145], [0.13, 0.13],
		[0.165, 0.085], [0.205, 0.05], [0.25, 0.034], [0.3, 0.026]]
	for i in range(prof.size() - 1):
		var a: Array = prof[i]
		var b: Array = prof[i + 1]
		kit.cylinder(m, L * Transform3D(Basis(), floor_pos + Vector3(0, float(a[0]), 0)), float(a[1]), float(b[1]), float(b[0]) - float(a[0]), 20, i == 0 or i == prof.size() - 2)
	# Stem up into the shade, and a socket just below it.
	kit.cylinder(m, L * Transform3D(Basis(), floor_pos + Vector3(0, 0.3, 0)), 0.02, 0.018, 1.1, 10, false)
	kit.cylinder(m, L * Transform3D(Basis(), floor_pos + Vector3(0, 1.3, 0)), 0.032, 0.03, 0.08, 12, true)


## A bedside table lamp standing on `top` (the table top, house frame): weighted base, ceramic
## body, brass stem and socket, a glowing bulb and a fabric shade open at both ends.
static func _table_lamp(kit: MeshKit, L: Transform3D, top: Vector3) -> void:
	var brass := Mats.metal(Color(0.72, 0.58, 0.32))
	var ceramic := Mats.std(Color(0.86, 0.84, 0.78), 0.35)
	kit.cylinder(brass, L * Transform3D(Basis(), top), 0.085, 0.078, 0.022, 16, true)
	kit.cylinder(ceramic, L * Transform3D(Basis(), top + Vector3(0, 0.022, 0)), 0.05, 0.068, 0.07, 14, false)
	kit.sphere(ceramic, L * Transform3D(Basis().scaled(Vector3(1.0, 0.9, 1.0)), top + Vector3(0, 0.12, 0)), 0.07, 8, 14)
	kit.cylinder(ceramic, L * Transform3D(Basis(), top + Vector3(0, 0.17, 0)), 0.04, 0.022, 0.05, 12, true)
	kit.cylinder(brass, L * Transform3D(Basis(), top + Vector3(0, 0.215, 0)), 0.007, 0.007, 0.11, 8, false)
	kit.cylinder(brass, L * Transform3D(Basis(), top + Vector3(0, 0.31, 0)), 0.018, 0.016, 0.035, 10, true)
	kit.sphere(Mats.emissive(Color(1.0, 0.9, 0.65), 2.4), L * Transform3D(Basis(), top + Vector3(0, 0.37, 0)), 0.032, 6, 10)
	# Shade: a drum, slightly tapered, glowing warm; visible from inside and out.
	kit.cylinder(_mat2(Color(1.0, 0.86, 0.62), 1.15), L * Transform3D(Basis(), top + Vector3(0, 0.29, 0)), 0.15, 0.1, 0.19, 18, false)
	kit.cylinder(brass, L * Transform3D(Basis(), top + Vector3(0, 0.473, 0)), 0.102, 0.1, 0.008, 18, false)
	kit.sphere(brass, L * Transform3D(Basis(), top + Vector3(0, 0.495, 0)), 0.012, 4, 8)


## A leafy house plant in a terracotta pot standing on `floor` (house frame).
static func _house_plant(kit: MeshKit, L: Transform3D, floor_pos: Vector3) -> void:
	var terra := Mats.std(Color(0.66, 0.36, 0.24), 0.8)
	kit.cylinder(terra, L * Transform3D(Basis(), floor_pos), 0.13, 0.165, 0.3, 14, true)
	kit.cylinder(_mat2(Color(0.62, 0.33, 0.22)), L * Transform3D(Basis(), floor_pos + Vector3(0, 0.29, 0)), 0.178, 0.18, 0.05, 16, false)
	kit.cylinder(Mats.std(Color(0.2, 0.13, 0.08), 0.95), L * Transform3D(Basis(), floor_pos + Vector3(0, 0.3, 0)), 0.16, 0.16, 0.012, 14, true)
	var greens := [Color(0.22, 0.45, 0.2), Color(0.28, 0.52, 0.24), Color(0.18, 0.4, 0.22), Color(0.3, 0.48, 0.18)]
	var stem := Mats.std(Color(0.25, 0.38, 0.17), 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var base := floor_pos + Vector3(0, 0.31, 0)
	for k in range(9):
		var a := TAU * k / 9.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var tilt := rng.randf_range(0.18, 0.55)
		var dir := (Vector3.UP * cos(tilt) + out * sin(tilt)).normalized()
		var length := rng.randf_range(0.32, 0.58)
		var root := base + out * rng.randf_range(0.01, 0.05)
		var tip := root + dir * length
		# Stem: a thin cylinder from the soil along `dir`.
		var sy := dir
		var sx := sy.cross(Vector3.FORWARD if absf(sy.z) < 0.9 else Vector3.RIGHT).normalized()
		var sz := sx.cross(sy).normalized()
		kit.cylinder(stem, L * Transform3D(Basis(sx, sy, sz), root), 0.008, 0.005, length, 5, false)
		var leaves := 3 + k % 2
		for j in range(leaves):
			var t := 0.4 + 0.6 * float(j) / float(leaves - 1)
			var p := root + dir * length * t
			var side := 1.0 if j % 2 == 0 else -1.0
			var la := a + side * rng.randf_range(0.5, 1.1)
			var lout := Vector3(cos(la), 0, sin(la))
			# Lower leaves droop more; a few point up.
			var droop := rng.randf_range(-0.1, 0.35) + (1.0 - t) * 0.25
			var ldir := (lout * cos(droop) - Vector3.UP * sin(droop) + Vector3.UP * 0.25).normalized()
			var ll := rng.randf_range(0.16, 0.26) * (1.15 if j == leaves - 1 else 1.0)
			var lw := ll * rng.randf_range(0.5, 0.62)
			var col: Color = greens[(k + j) % greens.size()]
			_leaf(kit, L, _mat2(col.lerp(Color(0.35, 0.55, 0.25), snappedf(rng.randf_range(0.0, 0.25), 0.05))), p, ldir, ll, lw)
		_leaf(kit, L, _mat2(greens[k % greens.size()]), tip, (dir + Vector3.UP * 0.3).normalized(), 0.17, 0.09)


## One leaf: a pointed blade folded along its midrib, drawn from both sides.
static func _leaf(kit: MeshKit, L: Transform3D, mat: Material, p: Vector3, dir: Vector3, length: float, width: float) -> void:
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.05:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	if up.y < 0.0:
		up = -up
	var tip := p + dir * length - up * length * 0.12
	var mid := p + dir * length * 0.45
	var l := mid + side * width * 0.5 + up * width * 0.12
	var r := mid - side * width * 0.5 + up * width * 0.12
	var n1 := (l - p).cross(tip - p).normalized()
	if n1.dot(up) < 0.0:
		n1 = -n1
	var n2 := (tip - p).cross(r - p).normalized()
	if n2.dot(up) < 0.0:
		n2 = -n2
	var w1 := L.basis * n1
	var w2 := L.basis * n2
	kit.tri(mat, L * p, L * l, L * tip, w1, w1, w1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, w1)
	kit.tri(mat, L * p, L * tip, L * r, w2, w2, w2, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, w2)


## Coat rack on the wall by the front door (`rail` = rail centre, house frame; the wall's inner
## face is about 0.11 m in front of the wall line): a wooden rail with four pegs, a parka on the
## second peg, a toque on the third and a scarf on the fourth.
static func _coat_rack(kit: MeshKit, L: Transform3D, wood: Material, rail: Vector3) -> void:
	kit.box(wood, L * Transform3D(Basis(), rail), Vector3(1.0, 0.1, 0.04))
	var peg_mat := Mats.metal(Color(0.3, 0.27, 0.24))
	var pegs := []
	for k in range(4):
		var px := rail.x - 0.36 + k * 0.24
		var base := Vector3(px, rail.y - 0.005, rail.z + 0.02)
		# Pegs stick out of the rail angled up a little so things stay on.
		kit.cylinder(peg_mat, L * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(72.0)), base), 0.012, 0.01, 0.1, 8, false)
		kit.sphere(peg_mat, L * Transform3D(Basis(), base + Vector3(0, 0.03, 0.095)), 0.016, 4, 8)
		pegs.append(base + Vector3(0, 0.02, 0.07))
	# The parka hangs from its collar loop on peg 2: shoulders, a body that flares a little to
	# the hem, sleeves hanging at the sides, a fur-trimmed hood folded down the back.
	var parka := Mats.fabric(Color(0.2, 0.35, 0.55))
	var dark := Mats.fabric(Color(0.14, 0.24, 0.4))
	var fur := Mats.fabric(Color(0.82, 0.78, 0.7))
	var hook: Vector3 = pegs[1]
	var cz := rail.z + 0.11              # coat centre: its back stays just off the wall
	var cx := hook.x
	kit.box(dark, L * Transform3D(Basis(), Vector3(cx, hook.y - 0.03, hook.z - 0.01)), Vector3(0.03, 0.06, 0.012))
	kit.bevel_box(dark, L * Transform3D(Basis(), Vector3(cx, hook.y - 0.08, cz - 0.02)), Vector3(0.2, 0.08, 0.12), 0.03)
	kit.bevel_box(fur, L * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(cx, hook.y - 0.13, cz + 0.05)), Vector3(0.24, 0.07, 0.06), 0.03)
	kit.bevel_box(parka, L * Transform3D(Basis(), Vector3(cx, hook.y - 0.17, cz)), Vector3(0.44, 0.1, 0.15), 0.045)
	kit.bevel_box(parka, L * Transform3D(Basis(), Vector3(cx, hook.y - 0.42, cz)), Vector3(0.42, 0.44, 0.15), 0.05)
	kit.bevel_box(parka, L * Transform3D(Basis(), Vector3(cx, hook.y - 0.76, cz + 0.005)), Vector3(0.46, 0.3, 0.155), 0.05)
	kit.box(fur, L * Transform3D(Basis(), Vector3(cx, hook.y - 0.9, cz + 0.006)), Vector3(0.47, 0.03, 0.158))
	kit.box(Mats.std(Color(0.75, 0.75, 0.72), 0.4), L * Transform3D(Basis(), Vector3(cx, hook.y - 0.55, cz + 0.079)), Vector3(0.012, 0.7, 0.004))
	for sx in [-1.0, 1.0]:
		var sb := Basis(Vector3.FORWARD, sx * deg_to_rad(5.0))
		kit.bevel_box(parka, L * Transform3D(sb, Vector3(cx + sx * 0.255, hook.y - 0.45, cz)), Vector3(0.1, 0.52, 0.12), 0.04)
		kit.bevel_box(dark, L * Transform3D(sb, Vector3(cx + sx * 0.278, hook.y - 0.73, cz)), Vector3(0.095, 0.06, 0.115), 0.025)
	# A red toque hanging by its crown on peg 3: white fold-up band, pompom at the peg.
	var tq: Vector3 = pegs[2]
	var red := Mats.fabric(Color(0.72, 0.14, 0.12))
	var cream := Mats.fabric(Color(0.92, 0.9, 0.86))
	kit.sphere(red, L * Transform3D(Basis().scaled(Vector3(0.95, 1.2, 0.8)), Vector3(tq.x, tq.y - 0.1, rail.z + 0.08)), 0.08, 6, 12)
	kit.cylinder(cream, L * Transform3D(Basis(), Vector3(tq.x, tq.y - 0.205, rail.z + 0.08)), 0.078, 0.08, 0.045, 12, true)
	kit.sphere(cream, L * Transform3D(Basis(), Vector3(tq.x, tq.y + 0.005, rail.z + 0.08)), 0.03, 4, 8)
	# A striped scarf over peg 4, both ends hanging.
	var sc: Vector3 = pegs[3]
	var s1 := Mats.fabric(Color(0.85, 0.66, 0.2))
	var s2 := Mats.fabric(Color(0.2, 0.42, 0.3))
	kit.bevel_box(s1, L * Transform3D(Basis(), Vector3(sc.x, sc.y + 0.005, rail.z + 0.075)), Vector3(0.13, 0.03, 0.05), 0.012)
	for k in range(2):
		var ex := sc.x - 0.045 + k * 0.09
		for band in range(5):
			kit.box(s1 if band % 2 == 0 else s2, L * Transform3D(Basis(Vector3.FORWARD, (k * 2 - 1) * 0.06), Vector3(ex, sc.y - 0.05 - band * 0.085, rail.z + 0.07 + k * 0.012)), Vector3(0.07, 0.086, 0.014))


static func build_neighbor(root: Node3D, lot: Dictionary) -> Dictionary:
	var L := HouseBuilder.lot_transform(lot)
	var sb: float = lot["setback"]
	var kit := MeshKit.new()
	var out := {}
	var stone := Mats.std(Color(0.55, 0.45, 0.4), 0.9)
	var fx := HouseBuilder.BODY_X0 + 0.45
	var fz := sb + 2.6
	kit.box(stone, L * Transform3D(Basis(), Vector3(fx, FY + 0.65, fz)), Vector3(0.6, 1.3, 1.7))
	kit.box(stone, L * Transform3D(Basis(), Vector3(fx - 0.05, FY + 2.0, fz)), Vector3(0.45, 1.6, 1.1))
	kit.box(Mats.emissive(Color(1.0, 0.5, 0.15), 3.5), L * Transform3D(Basis(), Vector3(fx + 0.26, FY + 0.35, fz)), Vector3(0.12, 0.4, 0.8))
	kit.box(Mats.fabric(Color(0.25, 0.4, 0.3)), L * Transform3D(Basis(), Vector3(-6.0, FY + 0.01, sb + 2.6)), Vector3(3.0, 0.02, 2.0))
	kit.bevel_box(Mats.fabric(Color(0.55, 0.3, 0.22)), L * Transform3D(Basis(), Vector3(-6.2, FY + 0.3, sb + 1.3)), Vector3(1.0, 0.6, 0.9), 0.12)
	kit.bevel_box(Mats.fabric(Color(0.55, 0.3, 0.22)), L * Transform3D(Basis(), Vector3(-6.2, FY + 0.75, sb + 0.95)), Vector3(1.0, 0.7, 0.2), 0.1)
	var wood := Mats.wood(Color(0.45, 0.3, 0.2), 0.0)
	kit.box(wood, L * Transform3D(Basis(), Vector3(1.75, FY + 0.74, sb + 8.45)), Vector3(1.4, 0.05, 0.7))
	kit.box(Mats.std(Color(0.08, 0.08, 0.09), 0.4), L * Transform3D(Basis(), Vector3(1.75, FY + 1.1, sb + 8.65)), Vector3(0.6, 0.38, 0.04))
	kit.box(Mats.emissive(Color(0.7, 0.85, 1.0), 1.3), L * Transform3D(Basis(), Vector3(1.75, FY + 1.1, sb + 8.627)), Vector3(0.54, 0.32, 0.01))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	root.add_child(mi)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.6, 0.3)
	fl.light_energy = 1.5
	fl.omni_range = 7.0
	root.add_child(fl)
	fl.global_position = L * Vector3(fx + 1.2, FY + 1.2, fz)
	out["fire_spot"] = L * Vector3(fx + 1.4, FY + 0.05, fz)
	out["player_spot"] = L * Vector3(fx + 2.6, FY + 0.05, fz + 0.4)
	out["computer_spot"] = L * Vector3(1.75, FY + 0.05, sb + 7.6)
	out["lights"] = [fl]
	return out
