class_name CharacterModel
extends Node3D
## Simple stylized character built from primitives (as in the references): rounded head, toque
## with pompom, scarf, bright orange jacket with reflective strips, dark cargo pants, chunky boots.
## Animated procedurally (walk, dig, push, wave, sit) by rotating limb pivots.

## Height of the hip joint above the soles (hips pivot at 0.95 m; boots reach down to ~0 m).
## Snow deeper than this can't be waded through (polish §6).
const HIP_HEIGHT := 0.95
const GLOVE_COLOR := Color(0.21, 0.21, 0.25)

var jacket_color := Color(0.95, 0.45, 0.12)
var toque_color := Color(0.33, 0.33, 0.45)
var pants_color := Color(0.22, 0.23, 0.25)
var scarf_color := Color(0.18, 0.18, 0.22)
var skin := Color(0.93, 0.78, 0.66)

var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var forearm_l: Node3D
var forearm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hand_r: Node3D     # tool attachment point
## Polish 5 §13: the insulated coat (a long red down parka over the jacket: hood, fleece cuffs) and
## snowshoes under the boots — built on demand by set_coat / set_snowshoes (the player's model only).
const COAT_COLOR := Color(0.62, 0.11, 0.1)
const FLEECE_COLOR := Color(0.9, 0.86, 0.77)
var coat_parts: Array = []
var shoe_parts: Array = []
var coat_on := false
var shoes_on := false
var walk_phase := 0.0
var pose := "idle"     # idle, walk, dig, push, carry, wave, throw, drive
var pose_t := 0.0
var action_t := 0.0    # 0..1 action progress (scoop/throw)
var sweep := 0.0       # -1..1 sideways sweep of a scoop (follows the mouse)
var speed := 0.0


func build() -> void:
	var jacket := Mats.fabric(jacket_color)
	var pants := Mats.fabric(pants_color)
	var boots := Mats.std(Color(0.55, 0.55, 0.53), 0.85)
	var soles := Mats.std(Color(0.18, 0.18, 0.19), 0.9)
	var glove := Mats.fabric(GLOVE_COLOR)
	var refl := Mats.reflective()
	hips = _pivot(self, Vector3(0, 0.95, 0))
	# Legs
	leg_l = _pivot(hips, Vector3(-0.12, 0, 0))
	leg_r = _pivot(hips, Vector3(0.12, 0, 0))
	for leg in [leg_l, leg_r]:
		var k := MeshKit.new()
		k.bevel_box(pants, Transform3D(Basis(), Vector3(0, -0.42, 0)), Vector3(0.2, 0.84, 0.22), 0.07)
		k.bevel_box(pants, Transform3D(Basis(), Vector3(0.1 if leg == leg_r else -0.1, -0.45, 0.0)), Vector3(0.05, 0.18, 0.16), 0.02)
		k.bevel_box(boots, Transform3D(Basis(), Vector3(0, -0.84, -0.04)), Vector3(0.22, 0.2, 0.32), 0.07)
		k.bevel_box(soles, Transform3D(Basis(), Vector3(0, -0.94, -0.05)), Vector3(0.24, 0.05, 0.34), 0.02)
		k.instance(leg, "Leg", true)
	# Torso
	torso = _pivot(hips, Vector3(0, 0.05, 0))
	var tk := MeshKit.new()
	tk.bevel_box(jacket, Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(0.52, 0.64, 0.32), 0.12)
	tk.bevel_box(refl, Transform3D(Basis(), Vector3(0, 0.22, 0)), Vector3(0.535, 0.05, 0.335), 0.02)
	tk.bevel_box(refl, Transform3D(Basis(), Vector3(0, 0.42, 0)), Vector3(0.535, 0.05, 0.335), 0.02)
	tk.bevel_box(Mats.fabric(jacket_color.darkened(0.2)), Transform3D(Basis(), Vector3(0, 0.0, 0)), Vector3(0.5, 0.08, 0.3), 0.03)
	# Scarf
	tk.cylinder(Mats.fabric(scarf_color), Transform3D(Basis(), Vector3(0, 0.6, 0)), 0.15, 0.13, 0.14, 10, true)
	tk.bevel_box(Mats.fabric(scarf_color), Transform3D(Basis(Vector3(1, 0, 0), 0.15), Vector3(0.08, 0.45, -0.15)), Vector3(0.1, 0.3, 0.05), 0.02)
	tk.instance(torso, "Torso", true)
	# Head
	head = _pivot(torso, Vector3(0, 0.78, 0))
	var hk := MeshKit.new()
	hk.sphere(Mats.std(skin, 0.7), Transform3D(Basis().scaled(Vector3(1.0, 1.02, 0.95)), Vector3(0, 0.05, 0)), 0.16, 8, 12)
	var eye := Mats.std(Color(0.08, 0.08, 0.1), 0.4)
	for ex in [-0.055, 0.055]:
		hk.sphere(eye, Transform3D(Basis().scaled(Vector3(0.7, 1.3, 0.5)), Vector3(ex, 0.07, -0.145)), 0.022, 4, 6)
	hk.sphere(Mats.fabric(toque_color), Transform3D(Basis().scaled(Vector3(1.05, 0.9, 1.05)), Vector3(0, 0.12, 0)), 0.17, 6, 12, true)
	hk.cylinder(Mats.fabric(toque_color.darkened(0.15)), Transform3D(Basis(), Vector3(0, 0.08, 0)), 0.172, 0.172, 0.06, 12, false)
	hk.sphere(Mats.fabric(toque_color.lightened(0.1)), Transform3D(Basis(), Vector3(0, 0.29, 0)), 0.06, 4, 8)
	# Scarf covering the lower face (as in the references)
	hk.sphere(Mats.fabric(scarf_color), Transform3D(Basis().scaled(Vector3(1.05, 0.55, 1.0)), Vector3(0, -0.06, -0.01)), 0.16, 5, 10)
	hk.instance(head, "Head", true)
	# Arms
	arm_l = _pivot(torso, Vector3(-0.31, 0.52, 0))
	arm_r = _pivot(torso, Vector3(0.31, 0.52, 0))
	for arm in [arm_l, arm_r]:
		var ak := MeshKit.new()
		ak.bevel_box(jacket, Transform3D(Basis(), Vector3(0, -0.17, 0)), Vector3(0.16, 0.36, 0.17), 0.06)
		ak.bevel_box(refl, Transform3D(Basis(), Vector3(0, -0.28, 0)), Vector3(0.165, 0.04, 0.175), 0.01)
		ak.instance(arm, "UpperArm", true)
		var fore := _pivot(arm, Vector3(0, -0.34, 0))
		var fk := MeshKit.new()
		fk.bevel_box(jacket, Transform3D(Basis(), Vector3(0, -0.14, 0)), Vector3(0.15, 0.3, 0.16), 0.06)
		fk.bevel_box(glove, Transform3D(Basis(), Vector3(0, -0.33, -0.01)), Vector3(0.13, 0.13, 0.14), 0.05)
		fk.instance(fore, "Forearm", true)
		if arm == arm_l:
			forearm_l = fore
		else:
			forearm_r = fore
	hand_r = _pivot(forearm_r, Vector3(0, -0.34, 0))


## Polish 5 §13: wear the insulated coat (or not). The coat is built the first time.
func set_coat(on: bool) -> void:
	if on and coat_parts.is_empty():
		_build_coat()
	coat_on = on
	for n in coat_parts:
		(n as Node3D).visible = on


## Polish 5 §13: snowshoes under the boots (or not).
func set_snowshoes(on: bool) -> void:
	if on and shoe_parts.is_empty():
		_build_snowshoes()
	shoes_on = on
	for n in shoe_parts:
		(n as Node3D).visible = on


func _build_coat() -> void:
	var coat := Mats.fabric(COAT_COLOR)
	var seam := Mats.fabric(COAT_COLOR.darkened(0.3))
	var fleece := Mats.fabric(FLEECE_COLOR)
	# The body: longer and puffier than the jacket (it covers the jacket and its reflective strips:
	# small bevels, so no corner of the jacket shows through), quilted front and back, to the thighs.
	var tk := MeshKit.new()
	tk.bevel_box(coat, Transform3D(Basis(), Vector3(0, 0.21, 0)), Vector3(0.6, 0.88, 0.39), 0.06)
	for y in [0.03, 0.2, 0.37]:
		tk.box(seam, Transform3D(Basis(), Vector3(0, y, 0)), Vector3(0.38, 0.016, 0.396))
	# Zip and placket down the front.
	tk.box(seam, Transform3D(Basis(), Vector3(0, 0.21, -0.197)), Vector3(0.035, 0.86, 0.01))
	# The hood folded down at the back, its fleece trim round the collar.
	tk.bevel_box(coat, Transform3D(Basis(Vector3(1, 0, 0), -0.25), Vector3(0, 0.6, 0.15)), Vector3(0.38, 0.2, 0.16), 0.07)
	tk.cylinder(fleece, Transform3D(Basis(), Vector3(0, 0.66, 0.01)), 0.19, 0.17, 0.08, 12, true)
	coat_parts.append(tk.instance(torso, "Coat", true))
	for arm in [arm_l, arm_r]:
		var ak := MeshKit.new()
		ak.bevel_box(coat, Transform3D(Basis(), Vector3(0, -0.17, 0)), Vector3(0.195, 0.38, 0.205), 0.045)
		ak.box(seam, Transform3D(Basis(), Vector3(0, -0.2, 0)), Vector3(0.198, 0.014, 0.208))
		coat_parts.append(ak.instance(arm, "CoatSleeve", true))
		var fore: Node3D = forearm_l if arm == arm_l else forearm_r
		var fk := MeshKit.new()
		fk.bevel_box(coat, Transform3D(Basis(), Vector3(0, -0.13, 0)), Vector3(0.185, 0.3, 0.195), 0.06)
		fk.bevel_box(fleece, Transform3D(Basis(), Vector3(0, -0.285, -0.005)), Vector3(0.19, 0.06, 0.2), 0.03)
		coat_parts.append(fk.instance(fore, "CoatCuff", true))


func _build_snowshoes() -> void:
	var deck := Mats.std(Color(0.16, 0.2, 0.3), 0.7)
	var rim := Mats.std(Color(0.72, 0.74, 0.78), 0.35, 0.6)
	var strap := Mats.fabric(Color(0.95, 0.45, 0.12))
	for leg in [leg_l, leg_r]:
		var k := MeshKit.new()
		var x := 0.025 * (-1.0 if leg == leg_l else 1.0)   # a little outward: the two don't touch
		# Aluminium frame (rounded at both ends), the decking on it, the binding over the boot.
		k.bevel_box(rim, Transform3D(Basis(), Vector3(x, -0.962, -0.02)), Vector3(0.22, 0.022, 0.72), 0.08)
		k.bevel_box(deck, Transform3D(Basis(), Vector3(x, -0.952, -0.02)), Vector3(0.18, 0.012, 0.66), 0.07)
		k.bevel_box(strap, Transform3D(Basis(), Vector3(0, -0.88, -0.1)), Vector3(0.25, 0.04, 0.06), 0.015)
		k.bevel_box(strap, Transform3D(Basis(), Vector3(0, -0.86, 0.05)), Vector3(0.25, 0.04, 0.05), 0.015)
		shoe_parts.append(k.instance(leg, "Snowshoe", true))


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func set_pose(p: String) -> void:
	if p != pose:
		pose = p
		pose_t = 0.0


func animate(delta: float, move_speed: float) -> void:
	speed = move_speed
	pose_t += delta
	var moving := move_speed > 0.3
	if moving:
		walk_phase += delta * clampf(move_speed, 0.5, 7.0) * 2.1
	else:
		walk_phase = lerpf(walk_phase, round(walk_phase / PI) * PI, delta * 6.0)
	var sw := sin(walk_phase) * clampf(move_speed / 4.0, 0.0, 1.0)
	var t := 1.0 - exp(-delta * 12.0)
	# Legs swing when walking.
	leg_l.rotation.x = lerpf(leg_l.rotation.x, sw * 0.7, t)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -sw * 0.7, t)
	hips.position.y = 0.95 + absf(cos(walk_phase)) * 0.03 * clampf(move_speed / 4.0, 0, 1)
	# Sign convention: positive X rotation swings a hanging arm FORWARD (toward -Z, the facing).
	var al := Vector3(-sw * 0.6, 0, -0.08)
	var ar := Vector3(sw * 0.6, 0, 0.08)
	var fl := Vector3(0.2, 0, 0)
	var fr := Vector3(0.2, 0, 0)
	var tor := Vector3.ZERO
	match pose:
		"tool_idle":
			# Standing with a hand tool, both hands on it (IK places the hands), leaning in a little.
			tor = Vector3(-0.38, 0, 0)
		"dig", "carry", "throw":
			# Two-handed shovel grip, leaning forward (like the references).
			tor = Vector3(-0.5, 0, 0)
			al = Vector3(0.75, 0, 0.22)
			ar = Vector3(0.45, 0, -0.12)
			fl = Vector3(0.65, 0, 0)
			fr = Vector3(0.55, 0, 0)
			if pose == "dig":
				var k := sin(clampf(action_t, 0.0, 1.0) * PI * 2.0) * 0.5 + 0.5
				tor.x -= 0.08 + 0.12 * k
				tor.y = sweep * 0.15
				ar.x += 0.3 * k
				al.x += 0.2 * k
			elif pose == "carry":
				tor.x = -0.4
				al.x = 0.95
				ar.x = 0.7
			elif pose == "throw":
				var k2 := sin(clampf(action_t * 1.4, 0.0, 1.0) * PI * 0.5)
				# Wind-up (arms low and back, torso twisted) -> release (arms swing up and forward).
				tor = Vector3(-0.5 + 0.3 * k2, 0.5 * (1.0 - k2), 0)
				ar = Vector3(-0.3 + 1.7 * k2, 0, -0.2)
				al = Vector3(0.1 + 1.4 * k2, 0, 0.3)
				fl = Vector3(0.4, 0, 0)
				fr = Vector3(0.3, 0, 0)
		"push":
			tor = Vector3(-0.55, 0, 0)
			al = Vector3(1.0, 0, 0.12)
			ar = Vector3(1.0, 0, -0.12)
			fl = Vector3(0.3, 0, 0)
			fr = Vector3(0.3, 0, 0)
		"hands", "hands_scoop":
			# Bent over, cupped hands sweeping through the snow in front.
			var kh := sin(clampf(action_t, 0, 1) * PI * 2.0) * 0.5 + 0.5
			tor = Vector3(-0.62 - 0.08 * kh, sweep * 0.12, 0)
			al = Vector3(1.05 + 0.18 * kh, sweep * 0.45, 0.28)
			ar = Vector3(1.05 + 0.18 * kh, sweep * 0.45, -0.28)
			fl = Vector3(0.25, 0, 0)
			fr = Vector3(0.25, 0, 0)
		"hands_hold":
			# Cupped hands together in front of the chest, holding the snow.
			tor = Vector3(-0.12, 0, 0)
			al = Vector3(0.62, 0, 0.42)
			ar = Vector3(0.62, 0, -0.42)
			fl = Vector3(1.05, 0, 0)
			fr = Vector3(1.05, 0, 0)
		"hands_push":
			# Leaning in, arms out straight, flat palms shoving the snow.
			tor = Vector3(-0.42, 0, 0)
			al = Vector3(1.45, 0, 0.16)
			ar = Vector3(1.45, 0, -0.16)
			fl = Vector3(0.12, 0, 0)
			fr = Vector3(0.12, 0, 0)
		"hands_toss":
			# Underhand toss: from low and bent to arms up and forward.
			var kt := sin(clampf(action_t * 1.4, 0.0, 1.0) * PI * 0.5)
			tor = Vector3(lerpf(-0.45, 0.05, kt), 0, 0)
			al = Vector3(lerpf(0.7, 1.75, kt), 0, 0.2)
			ar = Vector3(lerpf(0.7, 1.75, kt), 0, -0.2)
			fl = Vector3(lerpf(0.6, 0.1, kt), 0, 0)
			fr = Vector3(lerpf(0.6, 0.1, kt), 0, 0)
		"wave":
			ar = Vector3(0, 0, 2.6 + sin(pose_t * 9.0) * 0.35)
			fr = Vector3(0, 0, 0.3)
		"cheer":
			ar = Vector3(0, 0, 2.5)
			al = Vector3(0, 0, -2.5)
		"drive":
			al = Vector3(1.2, 0, 0.1)
			ar = Vector3(1.2, 0, -0.1)
	torso.rotation = torso.rotation.lerp(tor, t)
	arm_l.position = SHOULDER_L
	arm_r.position = SHOULDER_R
	arm_l.rotation = arm_l.rotation.lerp(al, t)
	arm_r.rotation = arm_r.rotation.lerp(ar, t)
	forearm_l.rotation = forearm_l.rotation.lerp(fl, t)
	forearm_r.rotation = forearm_r.rotation.lerp(fr, t)


## Upper arm and forearm length (shoulder pivot -> elbow pivot -> centre of the mitten).
const ARM_A := 0.34
const ARM_B := 0.33
const SHOULDER_L := Vector3(-0.31, 0.52, 0)
const SHOULDER_R := Vector3(0.31, 0.52, 0)
const SHOULDER_SLIDE := 0.1


## Two-bone IK: put the left (or right) mitten on `target` (world space), elbow bending out and
## down. Returns false (and reaches as far as it can) when the target is out of reach. Called
## after animate() each frame while holding a tool, so both hands grip the handle (polish 2 §1).
func reach(left: bool, target: Vector3) -> bool:
	var arm: Node3D = arm_l if left else arm_r
	var fore: Node3D = forearm_l if left else forearm_r
	var inv := torso.global_transform.affine_inverse()
	var t := inv * target
	var sh: Vector3 = SHOULDER_L if left else SHOULDER_R
	var v := t - sh
	var reach_len := ARM_A + ARM_B - 0.005
	# Reaching far, the shoulder itself comes forward a little (like a real reach across the body).
	if v.length() > reach_len:
		sh += v.normalized() * minf(v.length() - reach_len, SHOULDER_SLIDE)
		v = t - sh
	var dist := v.length()
	var ok := dist <= reach_len + 0.002
	dist = clampf(dist, 0.08, reach_len)
	var w := v.normalized()
	# Elbow points outward, down and back (pole), like a real two-handed shovel grip.
	var pole := Vector3(-1.0 if left else 1.0, -0.6, 0.6).normalized()
	var pp := pole - w * pole.dot(w)
	if pp.length() < 0.01:
		pp = Vector3(0, 0, 1) - w * w.z
	pp = pp.normalized()
	var cos_a := clampf((ARM_A * ARM_A + dist * dist - ARM_B * ARM_B) / (2.0 * ARM_A * dist), -1.0, 1.0)
	var alpha := acos(cos_a)
	var u := (w * cos(alpha) + pp * sin(alpha)).normalized()   # shoulder -> elbow
	# Arm basis: -Y along the upper arm; the forearm bends about local X toward local -Z.
	var y := -u
	var side := w - u * w.dot(u)
	var z := -side.normalized() if side.length() > 0.001 else Vector3(0, 0, 1)
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	arm.transform = Transform3D(Basis(x, y, z), sh)
	var cos_e := clampf((ARM_A * ARM_A + ARM_B * ARM_B - dist * dist) / (2.0 * ARM_A * ARM_B), -1.0, 1.0)
	fore.rotation = Vector3(PI - acos(cos_e), 0, 0)
	return ok


func reach_left(target: Vector3) -> bool:
	return reach(true, target)


func shoulder_global(left: bool) -> Vector3:
	return torso.global_transform * (SHOULDER_L if left else SHOULDER_R)


func shoulder_l_global() -> Vector3:
	return shoulder_global(true)
