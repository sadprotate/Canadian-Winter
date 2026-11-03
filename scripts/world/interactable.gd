class_name Interactable
extends StaticBody3D
## Generic interactable (layer 2): a callable for the prompt and one for the action.

var prompt_fn: Callable
var action_fn: Callable


static func make(parent: Node, pos: Vector3, size: Vector3, prompt: Callable, action: Callable, yaw := 0.0) -> Interactable:
	var it := Interactable.new()
	it.prompt_fn = prompt
	it.action_fn = action
	it.collision_layer = 1 << 1
	it.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	it.add_child(cs)
	parent.add_child(it)
	it.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	return it


func interact_prompt(p: Player) -> String:
	return prompt_fn.call(p) if prompt_fn.is_valid() else ""


func interact(p: Player) -> void:
	if action_fn.is_valid():
		action_fn.call(p)
