class_name BuriedKeys
extends Area3D
## The pickup truck keys, lost in the front lawn before the storm (Part 19.7).
## A small glint shows once the snow above them is thin; they can be picked up once dug out.

var mesh: MeshInstance3D
var glint: MeshInstance3D


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	cs.shape = box
	cs.position.y = 0.2
	add_child(cs)
	mesh = MeshInstance3D.new()
	var kit := MeshKit.new()
	kit.cylinder(Mats.metal(Color(0.8, 0.8, 0.75)), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.03, 0)), 0.035, 0.035, 0.01, 10, true)
	kit.box(Mats.metal(Color(0.85, 0.75, 0.4)), Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.06, 0.02, 0.02)), Vector3(0.08, 0.01, 0.025))
	kit.box(Mats.std(Color(0.1, 0.1, 0.1), 0.5), Transform3D(Basis(Vector3.UP, -0.3), Vector3(-0.05, 0.02, 0.0)), Vector3(0.05, 0.02, 0.03))
	mesh.mesh = kit.commit()
	add_child(mesh)
	glint = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.05
	s.height = 0.1
	glint.mesh = s
	glint.material_override = Mats.emissive(Color(1, 1, 0.85), 5.0)
	add_child(glint)


func depth() -> float:
	return Snow.depth_at(global_position.x, global_position.z)


func _process(_d: float) -> void:
	var d := depth()
	glint.position.y = d + 0.04
	glint.visible = d < 0.22 and fmod(Time.get_ticks_msec() / 1000.0, 2.0) < 0.2
	mesh.visible = d < 0.06


func interact_prompt(_p: Player) -> String:
	var d := depth()
	if d < 0.12:
		return "[E] Pick up the truck keys"
	if d < 0.25:
		return "Something glints under the snow..."
	return ""


func interact(_p: Player) -> void:
	if depth() >= 0.12:
		return
	Game.flags["truck_keys"] = true
	AudioMgr.play_at("keys_jingle", global_position, 0.0)
	Notify.push("You found your truck keys! (The truck still can't drive through deep snow.)", Notify.GOOD)
	queue_free()
