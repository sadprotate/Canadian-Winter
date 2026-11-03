class_name Door
extends Node3D
## Hinged front door (player house, and the neighbor's door during the tutorial).

var open := false
var locked_fn: Callable      # returns "" if usable, else a reason
var hinge: Node3D
var body: AnimatableBody3D
var _target := 0.0
var label := "door"
var glass: MeshInstance3D

const WIN_C := Vector2(0.52, 1.58)       # window opening centre (hinge frame, x across, y up)
const WIN_SIZE := Vector2(0.42, 0.42)

static var _glass: StandardMaterial3D
static var _frost: StandardMaterial3D


## Lightly tinted clear glass.
static func _glass_mat() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = Color(0.78, 0.87, 0.96, 0.2)
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.roughness = 0.04
		_glass.metallic_specular = 0.8
	return _glass


## A touch of frost in the corners of the pane, so it reads as glass.
static func _frost_mat() -> StandardMaterial3D:
	if _frost == null:
		_frost = StandardMaterial3D.new()
		_frost.albedo_color = Color(0.93, 0.96, 1.0, 0.42)
		_frost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_frost.roughness = 0.6
	return _frost


static func make(parent: Node, xf: Transform3D, color: Color, name_label: String) -> Door:
	var d := Door.new()
	d.label = name_label
	parent.add_child(d)
	d.global_transform = xf
	d._build(color)
	return d


func _build(color: Color) -> void:
	hinge = Node3D.new()
	hinge.position = Vector3(-0.52, 0, 0)
	add_child(hinge)
	var kit := MeshKit.new()
	# Polish 3 §3: the door has a real window opening (glass you can see through from both
	# sides) instead of a lit picture of a window on its outer face. The slab is built around the
	# opening; a trim frame rings it on both faces.
	var paint := Mats.std(color, 0.55)
	var x0 := WIN_C.x - WIN_SIZE.x * 0.5
	var x1 := WIN_C.x + WIN_SIZE.x * 0.5
	var y0 := WIN_C.y - WIN_SIZE.y * 0.5
	var y1 := WIN_C.y + WIN_SIZE.y * 0.5
	kit.box(paint, Transform3D(Basis(), Vector3(0.52, y0 * 0.5, 0)), Vector3(1.0, y0, 0.06))
	kit.box(paint, Transform3D(Basis(), Vector3(0.52, (y1 + 2.06) * 0.5, 0)), Vector3(1.0, 2.06 - y1, 0.06))
	kit.box(paint, Transform3D(Basis(), Vector3((0.02 + x0) * 0.5, WIN_C.y, 0)), Vector3(x0 - 0.02, WIN_SIZE.y, 0.06))
	kit.box(paint, Transform3D(Basis(), Vector3((x1 + 1.02) * 0.5, WIN_C.y, 0)), Vector3(1.02 - x1, WIN_SIZE.y, 0.06))
	var trim := Mats.std(Color(0.93, 0.92, 0.88), 0.5)
	for zf in [-1.0, 1.0]:
		var z: float = zf * 0.036
		kit.box(trim, Transform3D(Basis(), Vector3(WIN_C.x, y1 + 0.0175, z)), Vector3(WIN_SIZE.x + 0.07, 0.035, 0.012))
		kit.box(trim, Transform3D(Basis(), Vector3(WIN_C.x, y0 - 0.0175, z)), Vector3(WIN_SIZE.x + 0.07, 0.035, 0.012))
		kit.box(trim, Transform3D(Basis(), Vector3(x0 - 0.0175, WIN_C.y, z)), Vector3(0.035, WIN_SIZE.y, 0.012))
		kit.box(trim, Transform3D(Basis(), Vector3(x1 + 0.0175, WIN_C.y, z)), Vector3(0.035, WIN_SIZE.y, 0.012))
	kit.box(Mats.metal(Color(0.75, 0.62, 0.3)), Transform3D(Basis(), Vector3(0.88, 0.98, -0.06)), Vector3(0.05, 0.12, 0.05))
	kit.box(Mats.metal(Color(0.75, 0.62, 0.3)), Transform3D(Basis(), Vector3(0.88, 0.98, 0.06)), Vector3(0.05, 0.12, 0.05))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	hinge.add_child(mi)
	# The pane: its own (transparent) mesh so it sorts against snow and particles outside, and a
	# child of the hinge so it swings with the door. A thin box: each face shows from its side.
	var gk := MeshKit.new()
	gk.box(_glass_mat(), Transform3D(Basis(), Vector3(WIN_C.x, WIN_C.y, 0)), Vector3(WIN_SIZE.x, WIN_SIZE.y, 0.008))
	var frost := _frost_mat()
	for zf in [-1.0, 1.0]:
		var z: float = zf * 0.0045
		var fw := 0.028
		gk.box(frost, Transform3D(Basis(), Vector3(WIN_C.x, WIN_C.y + WIN_SIZE.y * 0.5 - fw * 0.5, z)), Vector3(WIN_SIZE.x, fw, 0.001))
		gk.box(frost, Transform3D(Basis(), Vector3(WIN_C.x, WIN_C.y - WIN_SIZE.y * 0.5 + fw * 0.5, z)), Vector3(WIN_SIZE.x, fw, 0.001))
		gk.box(frost, Transform3D(Basis(), Vector3(WIN_C.x - WIN_SIZE.x * 0.5 + fw * 0.5, WIN_C.y, z)), Vector3(fw, WIN_SIZE.y - fw * 2.0, 0.001))
		gk.box(frost, Transform3D(Basis(), Vector3(WIN_C.x + WIN_SIZE.x * 0.5 - fw * 0.5, WIN_C.y, z)), Vector3(fw, WIN_SIZE.y - fw * 2.0, 0.001))
	glass = MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = gk.commit()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hinge.add_child(glass)
	body = AnimatableBody3D.new()
	body.collision_layer = 1 | (1 << 1)
	body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.06, 0.1)
	cs.shape = box
	cs.position = Vector3(0.52, 1.03, 0)
	body.add_child(cs)
	hinge.add_child(body)
	body.set_meta("door", self)


func interact_prompt(_p: Player) -> String:
	var why: String = locked_fn.call() if locked_fn.is_valid() else ""
	if why != "":
		return why
	return "[E] %s %s" % ["Close" if open else "Open", label]


func interact(_p: Player) -> void:
	var why: String = locked_fn.call() if locked_fn.is_valid() else ""
	if why != "":
		AudioMgr.play_at("truck_locked", global_position, -6.0, 1.2)
		return
	set_open(not open)


func set_open(o: bool) -> void:
	open = o
	_target = deg_to_rad(-100.0) if open else 0.0
	AudioMgr.play_at("door_open" if open else "door_close", global_position, -4.0)


func _physics_process(delta: float) -> void:
	hinge.rotation.y = lerp_angle(hinge.rotation.y, _target, delta * 6.0)
