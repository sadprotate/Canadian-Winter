class_name ToolItem
extends Area3D
## A physical tool (or store crate) in the world. Pick up with E. Buried items must be dug out.
## Dropped items rest on the snow surface; snow can fall on and bury them again.
##
## Polish 3 §6: a tool lying in snow can be picked up once PICKUP_EXPOSURE (75 %) of it is out of
## the snow, measured at sample points spread along its grip, shaft and blade (a point is out when
## the snow surface at its cell is below it, give or take 2 cm). The player picks it up when close
## to and facing it even if the crosshair is on the snow pile (Player._nearby_pickup).

const PICKUP_EXPOSURE := 0.75
const EXPOSE_TOLERANCE := 0.02

var entry: Dictionary = {}
var tool_id := ""
var mesh: MeshInstance3D
var _t := 0.0
var _glint: MeshInstance3D


func setup(e: Dictionary) -> void:
	entry = e
	tool_id = str(e["tool"])


func is_crate() -> bool:
	return tool_id.begins_with("crate:")


func crate_item() -> String:
	return tool_id.substr(6)


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.6, 1.4) if not is_crate() else Vector3(0.9, 0.9, 0.9)
	cs.shape = box
	cs.position = Vector3(0, 0.6, -0.4)
	add_child(cs)
	mesh = MeshInstance3D.new()
	if is_crate():
		var kit := MeshKit.new()
		kit.bevel_box(Mats.wood(Color(0.7, 0.55, 0.35), 1.0), Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(0.7, 0.6, 0.7), 0.03)
		kit.box(Mats.std(Color(0.75, 0.15, 0.12), 0.6), Transform3D(Basis(), Vector3(0, 0.45, -0.355)), Vector3(0.5, 0.15, 0.02))
		mesh.mesh = kit.commit()
		cs.position = Vector3(0, 0.4, 0)
	else:
		mesh.mesh = ToolModels.mesh_for(tool_id)
		# Lying in the snow: grip end raised, blade on the ground (handle pokes up when buried).
		mesh.rotation_degrees = Vector3(28, 0, 0)
		mesh.position = Vector3(0, 0.95, 0.3)
	add_child(mesh)
	if entry.get("buried", false):
		_glint = MeshInstance3D.new()
		_glint.mesh = SphereMesh.new()
		(_glint.mesh as SphereMesh).radius = 0.06
		(_glint.mesh as SphereMesh).height = 0.12
		_glint.material_override = Mats.emissive(Color(1, 1, 0.9), 4.0)
		_glint.position = Vector3(0, 1.0, 0.9)
		add_child(_glint)
	_settle()


func _settle() -> void:
	if entry.get("buried", false):
		global_position.y = Snow.ground_at(global_position.x, global_position.z)
		return
	var s := Snow.surface_height(global_position.x, global_position.z)
	if is_crate() or s < global_position.y:
		global_position.y = s


func buried_depth() -> float:
	return Snow.depth_at(global_position.x, global_position.z) if entry.get("buried", false) else 0.0


## Sample points on the tool (world space): along the grip and shaft, and across the blade.
## Polish 5 §6: from the model itself (ToolModels.sample_points: nine on the shaft, two rows of four
## on the blade — by its back and by its front edge).
func sample_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if mesh == null or is_crate():
		return out
	var xf := mesh.global_transform
	for p in ToolModels.sample_points(tool_id):
		out.append(xf * p)
	return out


## Fraction (0..1) of the tool that is out of the snow.
func exposure() -> float:
	if is_crate():
		return 1.0
	var pts := sample_points()
	if pts.is_empty():
		return 1.0
	var out := 0
	for p in pts:
		if Snow.surface_height(p.x, p.z) <= p.y + EXPOSE_TOLERANCE:
			out += 1
	return float(out) / float(pts.size())


func can_pick_up() -> bool:
	return is_crate() or exposure() >= PICKUP_EXPOSURE


func _process(delta: float) -> void:
	_t += delta
	if _t > 1.5:
		_t = 0.0
		_settle()
		if entry.get("buried", false) and exposure() >= PICKUP_EXPOSURE:
			entry["buried"] = false
	if _glint:
		_glint.visible = entry.get("buried", false) and exposure() > 0.2 and fmod(Time.get_ticks_msec() / 1000.0, 2.5) < 0.25


func interact_prompt(_p: Player) -> String:
	if not can_pick_up():
		return "Something is buried here — dig it out" if exposure() < 0.25 else "Dig it out a bit more"
	if is_crate():
		return "[E] Collect %s" % Catalog.item_name(StringName(crate_item()))
	return "[E] Pick up %s" % Catalog.tool(StringName(tool_id)).display_name


func interact(_p: Player) -> void:
	# Polish 5 §2: two presses in one frame reach it before queue_free(); the second must not
	# collect it again (a burst of E duplicated tools).
	if is_queued_for_deletion() or not can_pick_up():
		return
	if is_crate():
		_open_crate()
		return
	if not Game.add_tool(tool_id):
		Notify.push("Your hands and tool slots are full. Drop something first (%s)." % Settings.action_label("drop"), Notify.WARN)
		return
	if tool_id == "small_shovel" and not Game.flags.get("found_shovel", false):
		Game.flags["found_shovel"] = true
		Notify.push("You found a small snow shovel! Hold %s and sweep it through the snow to fill it, release to throw, hold %s to push." % [Settings.action_label("primary"), Settings.action_label("secondary")], Notify.GOOD)
	if entry.has("order_id"):
		Economy.mark_order(int(entry["order_id"]), "collected")
		Game.add_equipment_stat(Catalog.tool(StringName(tool_id)).display_name)
	AudioMgr.play_at("pickup_item", global_position, -2.0)
	Game.items.erase(entry)
	queue_free()


func _open_crate() -> void:
	var id := crate_item()
	var sid := StringName(id)
	# Polish 5 §13: equipment is put on as it's collected (the pad goes into your arms — not while
	# they're full); an old jacket or parka crate is the insulated coat now.
	if Catalog.RETIRED_UPGRADE_IDS.has(sid):
		sid = Equipment.COAT
		id = String(sid)
	if Catalog.EQUIPMENT.has(sid):
		if not Equipment.collect(sid):
			Notify.push(Settings.with_keys("Your arms are full. Put down what you're carrying first ({drop})."), Notify.WARN)
			return
		Game.add_equipment_stat(Catalog.item_name(sid))
		Notify.push(Equipment.collected_text(sid), Notify.GOOD)
	elif Catalog.UTILITY.has(sid):
		Game.heat_pouches += int(Catalog.UTILITY[sid]["count"])
		Notify.push("Collected %s." % Catalog.UTILITY[sid]["name"], Notify.GOOD)
	elif Catalog.upgrades.has(sid):
		Game.grant_upgrade(sid)
		Game.add_equipment_stat(Catalog.item_name(sid))
		Notify.push("%s installed." % Catalog.item_name(sid), Notify.GOOD)
		if sid == &"tool_rack" and Game.world and Game.world.has_method("build_tool_rack"):
			Game.world.build_tool_rack()
	if entry.has("order_id"):
		Economy.mark_order(int(entry["order_id"]), "collected")
	AudioMgr.play_at("pickup_item", global_position, -2.0)
	Game.items.erase(entry)
	Game.inventory_changed.emit()
	queue_free()
