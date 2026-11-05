class_name FPArms
extends Node3D
## First-person arms (polish §1): orange coat sleeves with reflective bands and dark winter mittens
## matching the character model. Each hand is a wrist pivot with a palm, a hinged mitten (curls
## toward the palm) and a thumb. Poses are set as wrist targets in camera space; the sleeves follow
## from the wrist toward an elbow anchor below the screen. A snow mound sits in the cupped hands.
##
## Lives inside the player's viewmodel node, which is scaled down toward the camera so the arms
## and tools can never clip into walls, snowbanks or the ground.

var hand_l: Node3D
var hand_r: Node3D
var fingers_l: Node3D
var fingers_r: Node3D
var thumb_l: Node3D
var thumb_r: Node3D
var sleeve_l: Node3D
var sleeve_r: Node3D
var cup_load: MeshInstance3D
## Polish 5 §13: the insulated coat's sleeves (red, puffy, fleece cuffs), shown instead of the
## jacket's when it's worn (set_coat).
var jacket_sleeves: Array = []
var coat_sleeves: Array = []
var elbow_l := Vector3(-0.36, -0.75, 0.08)
var elbow_r := Vector3(0.36, -0.75, 0.08)
# Current (smoothed) hand state.
var _pos := [Vector3(-0.22, -0.36, -0.42), Vector3(0.22, -0.36, -0.42)]
var _rot := [Quaternion.IDENTITY, Quaternion.IDENTITY]
var _curl := [0.3, 0.3]
var _thumb := [0.3, 0.3]


func build(jacket: Color, glove: Color) -> void:
	var sleeve_m := Mats.fabric(jacket)
	var cuff_m := Mats.fabric(jacket.darkened(0.25))
	var refl := Mats.reflective()
	var mitt := Mats.fabric(glove)
	var mitt_dark := Mats.fabric(glove.darkened(0.25))
	for side in [-1.0, 1.0]:
		# Sleeve: modelled from the wrist (origin) back along +Z toward the elbow.
		var sk := MeshKit.new()
		sk.bevel_box(sleeve_m, Transform3D(Basis(), Vector3(0, 0, 0.32)), Vector3(0.125, 0.125, 0.56), 0.05)
		sk.bevel_box(refl, Transform3D(Basis(), Vector3(0, 0, 0.13)), Vector3(0.13, 0.13, 0.035), 0.01)
		sk.bevel_box(cuff_m, Transform3D(Basis(), Vector3(0, 0, 0.035)), Vector3(0.118, 0.118, 0.06), 0.03)
		var sleeve := Node3D.new()
		add_child(sleeve)
		var smi := MeshInstance3D.new()
		smi.mesh = sk.commit()
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sleeve.add_child(smi)
		jacket_sleeves.append(smi)
		# Hand: wrist pivot. Local -Z = fingers, +Y = back of the hand, -Y = palm.
		var hand := Node3D.new()
		add_child(hand)
		var hk := MeshKit.new()
		hk.bevel_box(mitt_dark, Transform3D(Basis(), Vector3(0, 0, 0.0)), Vector3(0.1, 0.075, 0.05), 0.025)
		hk.bevel_box(mitt, Transform3D(Basis(), Vector3(0, 0, -0.055)), Vector3(0.094, 0.042, 0.1), 0.02)
		_mi(hand, hk.commit())
		var fingers := Node3D.new()
		fingers.position = Vector3(0, 0, -0.1)
		hand.add_child(fingers)
		var fk := MeshKit.new()
		fk.bevel_box(mitt, Transform3D(Basis(), Vector3(0, -0.002, -0.042)), Vector3(0.092, 0.038, 0.09), 0.019)
		_mi(fingers, fk.commit())
		var thumb := Node3D.new()
		thumb.position = Vector3(-side * 0.045, -0.012, -0.03)
		hand.add_child(thumb)
		var tk := MeshKit.new()
		tk.bevel_box(mitt, Transform3D(Basis(), Vector3(0, 0, -0.03)), Vector3(0.034, 0.032, 0.07), 0.015)
		_mi(thumb, tk.commit())
		if side < 0.0:
			hand_l = hand
			fingers_l = fingers
			thumb_l = thumb
			sleeve_l = sleeve
		else:
			hand_r = hand
			fingers_r = fingers
			thumb_r = thumb
			sleeve_r = sleeve
	cup_load = MeshInstance3D.new()
	var lk := MeshKit.new()
	lk.sphere(Mats.snow_soft(), Transform3D(Basis().scaled(Vector3(1.25, 0.72, 1.1)), Vector3(0, 0, 0)), 0.1, 5, 9)
	lk.sphere(Mats.snow_soft(), Transform3D(Basis().scaled(Vector3(0.8, 0.6, 0.8)), Vector3(0.035, 0.045, -0.02)), 0.07, 4, 7)
	lk.sphere(Mats.snow_soft(), Transform3D(Basis().scaled(Vector3(0.7, 0.55, 0.7)), Vector3(-0.04, 0.035, 0.025)), 0.065, 4, 7)
	cup_load.mesh = lk.commit()
	cup_load.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cup_load.visible = false
	add_child(cup_load)


## Polish 5 §13: the coat's sleeves instead of the jacket's (built the first time).
func set_coat(on: bool) -> void:
	if on and coat_sleeves.is_empty():
		var coat := Mats.fabric(CharacterModel.COAT_COLOR)
		var seam := Mats.fabric(CharacterModel.COAT_COLOR.darkened(0.3))
		var fleece := Mats.fabric(CharacterModel.FLEECE_COLOR)
		for sl in [sleeve_l, sleeve_r]:
			var k := MeshKit.new()
			k.bevel_box(coat, Transform3D(Basis(), Vector3(0, 0, 0.34)), Vector3(0.15, 0.15, 0.56), 0.065)
			for z in [0.2, 0.36, 0.52]:
				k.box(seam, Transform3D(Basis(), Vector3(0, 0, z)), Vector3(0.152, 0.152, 0.012))
			k.bevel_box(fleece, Transform3D(Basis(), Vector3(0, 0, 0.045)), Vector3(0.142, 0.142, 0.075), 0.035)
			var mi := MeshInstance3D.new()
			mi.mesh = k.commit()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(sl as Node3D).add_child(mi)
			coat_sleeves.append(mi)
	for n in coat_sleeves:
		(n as Node3D).visible = on
	for n in jacket_sleeves:
		(n as Node3D).visible = not on


func _mi(parent: Node3D, mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Snap the smoothed state to the given targets (no blending), e.g. after switching tools.
func snap(targets: Array) -> void:
	for k in [0, 1]:
		var t: Dictionary = targets[k]
		_pos[k] = t["pos"]
		_rot[k] = (t["basis"] as Basis).get_rotation_quaternion()
		_curl[k] = t.get("curl", 0.3)
		_thumb[k] = t.get("thumb", 0.3)
	_apply()


## Blend toward hand targets: [{pos, basis, curl, thumb}, {…}] for left and right (camera space).
func update_pose(targets: Array, delta: float, speed := 14.0) -> void:
	var f := 1.0 - exp(-delta * speed)
	for k in [0, 1]:
		var t: Dictionary = targets[k]
		_pos[k] = (_pos[k] as Vector3).lerp(t["pos"], f)
		_rot[k] = (_rot[k] as Quaternion).slerp((t["basis"] as Basis).get_rotation_quaternion(), f)
		_curl[k] = lerpf(_curl[k], float(t.get("curl", 0.3)), f)
		_thumb[k] = lerpf(_thumb[k], float(t.get("thumb", 0.3)), f)
	_apply()


func _apply() -> void:
	var hands := [hand_l, hand_r]
	var fingers := [fingers_l, fingers_r]
	var thumbs := [thumb_l, thumb_r]
	var sleeves := [sleeve_l, sleeve_r]
	var elbows := [elbow_l, elbow_r]
	for k in [0, 1]:
		var h: Node3D = hands[k]
		var b := Basis(_rot[k])
		h.transform = Transform3D(b, _pos[k])
		(fingers[k] as Node3D).rotation = Vector3(-float(_curl[k]) * 1.45, 0, 0)
		var side := -1.0 if k == 0 else 1.0
		(thumbs[k] as Node3D).rotation = Vector3(-float(_thumb[k]) * 0.9, side * (0.55 - float(_thumb[k]) * 0.35), 0)
		# Sleeve from the wrist back toward the elbow anchor (follows the hand, below the screen).
		var wrist: Vector3 = _pos[k] + b.z * 0.02
		var to_elbow: Vector3 = (elbows[k] as Vector3) - wrist
		var s: Node3D = sleeves[k]
		if to_elbow.length() > 0.01:
			var zf := to_elbow.normalized()
			var up := b.y if absf(b.y.dot(zf)) < 0.95 else Vector3.UP
			var xf := up.cross(zf).normalized()
			var yf := zf.cross(xf).normalized()
			s.transform = Transform3D(Basis(xf, yf, zf), wrist)


## Snow carried in cupped hands: a mound between the palms that scales with the load.
func show_cup_load(fraction: float, visible_now: bool) -> void:
	cup_load.visible = visible_now and fraction > 0.003
	if not cup_load.visible:
		return
	var mid: Vector3 = ((_pos[0] as Vector3) + (_pos[1] as Vector3)) * 0.5
	var up := (Basis(_rot[0]).y + Basis(_rot[1]).y) * -0.5   # palms face up when cupped (-Y local)
	if up.length() < 0.1:
		up = Vector3.UP
	up = up.normalized()
	var s := lerpf(0.28, 1.12, pow(clampf(fraction, 0.0, 1.0), 0.55))   # a full 30 L double handful
	cup_load.position = mid + up * (0.008 + 0.04 * s) + Vector3(0, 0, -0.05)
	cup_load.scale = Vector3(s, s, s)
