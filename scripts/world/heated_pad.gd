class_name HeatedPad
extends Node3D
## Polish 5 §13: the heated snow-melting pad lying where the player put it down (Game.equipment,
## Equipment.pad_*): a black rubber mat with heating cables and a small control box whose lamp
## glows orange while it melts (Heating) and goes dark in a power cut. The snow on it is the snow
## in its cells (it lies on the ground; snow on it hides it). Interact picks it up into your arms.

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _Equipment := preload("res://scripts/data/equipment.gd")
const _Heating := preload("res://scripts/world/heating.gd")

var mesh: MeshInstance3D
var lamp: MeshInstance3D
var _t := 0.0
var _lit := false

static var _mat_cache: Dictionary = {}
static var _carry_mesh: ArrayMesh


func _ready() -> void:
	var size := _Equipment.PAD_SIZE
	mesh = MeshInstance3D.new()
	mesh.name = "Pad"
	mesh.mesh = pad_mesh()
	add_child(mesh)
	lamp = MeshInstance3D.new()
	lamp.name = "Lamp"
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	lamp.mesh = sm
	lamp.position = Vector3(0.0, 0.135, size.y * 0.5 + 0.09)
	add_child(lamp)
	_set_lamp(false)
	Interactable.make(self, global_position + global_basis * Vector3(0, 0.25, 0), Vector3(size.x + 0.1, 0.6, size.y + 0.3),
		func(_p): return "[E] Pick up the heated pad%s" % ("" if Survival.power_on else "  (no power)"),
		func(_p): _pick_up(), rotation.y)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var lit := _Heating.running("pad")
	if lit != _lit:
		_set_lamp(lit)


func _set_lamp(on: bool) -> void:
	_lit = on
	lamp.material_override = Mats.emissive(Color(1.0, 0.45, 0.1), 3.0) if on else Mats.std(Color(0.2, 0.08, 0.05), 0.5)


func _pick_up() -> void:
	var why := _Equipment.pick_up_pad()
	if why != "":
		Notify.push(why, Notify.WARN)
		return
	AudioMgr.play_at("pickup_item", global_position, -3.0)
	if Game.world and Game.world.has_method("refresh_pad"):
		Game.world.refresh_pad()


## The pad on the ground: local X across it, Z along it, the top at +0.025; the control box at
## its +Z end.
static func pad_mesh() -> ArrayMesh:
	if _mat_cache.has("pad"):
		return _mat_cache["pad"]
	var size := _Equipment.PAD_SIZE
	var kit := MeshKit.new()
	var rubber := Mats.std(Color(0.07, 0.07, 0.08), 0.85)
	var cable := Mats.std(Color(0.55, 0.16, 0.08), 0.6)
	var box := Mats.std(Color(0.85, 0.86, 0.84), 0.5)
	kit.bevel_box(rubber, Transform3D(Basis(), Vector3(0, 0.0125, 0)), Vector3(size.x, 0.025, size.y), 0.01)
	# The heating cable runs back and forth under the rubber, showing as raised ribs.
	var n := 7
	for k in range(n):
		var x := lerpf(-size.x * 0.5 + 0.12, size.x * 0.5 - 0.12, float(k) / float(n - 1))
		kit.box(cable, Transform3D(Basis(), Vector3(x, 0.027, 0)), Vector3(0.025, 0.006, size.y - 0.24))
	for k in range(n - 1):
		var x0 := lerpf(-size.x * 0.5 + 0.12, size.x * 0.5 - 0.12, float(k) / float(n - 1))
		var x1 := lerpf(-size.x * 0.5 + 0.12, size.x * 0.5 - 0.12, float(k + 1) / float(n - 1))
		var zend := (size.y * 0.5 - 0.12) * (1.0 if k % 2 == 0 else -1.0)
		kit.box(cable, Transform3D(Basis(), Vector3((x0 + x1) * 0.5, 0.027, zend)), Vector3(x1 - x0 + 0.025, 0.006, 0.025))
	# The control box and its cord.
	kit.bevel_box(box, Transform3D(Basis(), Vector3(0, 0.07, size.y * 0.5 + 0.1)), Vector3(0.2, 0.13, 0.12), 0.02)
	kit.cylinder(rubber, Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0.0, 0.03, size.y * 0.5 + 0.03)), 0.012, 0.012, 0.08, 6, true)
	var m := kit.commit()
	_mat_cache["pad"] = m
	return m


## The pad folded in half and rolled up in your arms (first and third person): a roll across the
## body.
static func carry_mesh() -> ArrayMesh:
	if _carry_mesh != null:
		return _carry_mesh
	var size := _Equipment.PAD_SIZE
	var kit := MeshKit.new()
	var rubber := Mats.std(Color(0.08, 0.08, 0.09), 0.85)
	var cable := Mats.std(Color(0.55, 0.16, 0.08), 0.6)
	var b := Basis(Vector3(0, 0, 1), PI * 0.5)
	kit.cylinder(rubber, Transform3D(b, Vector3(0, 0, -0.05)), 0.12, 0.12, size.x * 0.5, 14, true)
	for x in [-0.2, 0.0, 0.2]:
		kit.cylinder(cable, Transform3D(b, Vector3(x, 0, -0.05)), 0.123, 0.123, 0.025, 14, false)
	_carry_mesh = kit.commit()
	return _carry_mesh
