class_name Store
extends Node3D
## Northern Supply Co. (Part 16.4): no interior, no clerk. Every ready order physically appears in
## the parking lot: tools/crates on the pickup pad, walk-behind machines beside it, vehicles in bays.
## Polish 5 §13: equipment (the coat, snowshoes, the heated pad) is a crate on the pad like an
## upgrade; collecting it puts it on (or the pad in your arms).
## Plow installation: drive your pickup into the lot while a plow order is ready (polish 5 §13: the
## pickup's own upgrade, ItemUpgrades.PLOW_ID).

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _ItemUpgrades := preload("res://scripts/data/item_upgrades.gd")

var world: Node


func _ready() -> void:
	Economy.orders_changed.connect(spawn_ready)
	call_deferred("spawn_ready")


func _pad_slot(i: int) -> Vector3:
	var pad := Layout.store_pad
	var cols := 6
	var x := pad.position.x + 1.1 + (i % cols) * 2.2
	@warning_ignore("integer_division")
	var z := pad.position.y + 1.2 + (i / cols) * 1.6
	return Vector3(x, 0, z)


func _occupied_slots() -> Array:
	var used := []
	for it in Game.items:
		if it.has("pad_slot"):
			used.append(int(it["pad_slot"]))
	for m in Game.machines:
		if m.has("pad_slot"):
			used.append(int(m["pad_slot"]))
	return used


func _free_slot() -> int:
	var used := _occupied_slots()
	for i in range(18):
		if not (i in used):
			return i
	return randi() % 18


func _free_bay() -> Vector3:
	for bay in Layout.store_bays:
		var b: Rect2 = bay
		var free := true
		for v in Game.vehicles:
			var p: Vector3 = v["pos"]
			if b.grow(1.0).has_point(Vector2(p.x, p.z)):
				free = false
		if free:
			return Vector3(b.get_center().x, 0, b.get_center().y)
	var lot: Rect2 = Layout.big_areas[1]["rect"]
	return Vector3(lot.position.x + 10 + randf() * 30, 0, lot.position.y + 12)


func spawn_ready() -> void:
	if world == null:
		return
	for o in Economy.orders:
		if o["status"] != "ready":
			continue
		var kind: String = o["kind"]
		var item: String = o["item"]
		match kind:
			"tool":
				var slot := _free_slot()
				var at := _pad_slot(slot)
				at.y = Snow.surface_height(at.x, at.z)   # polish 6 §3: on the snow on the pad
				var e := {"uid": Game.uid(), "tool": item, "pos": at, "yaw": 0.0, "order_id": o["id"], "pad_slot": slot}
				Game.items.append(e)
				world.spawn_item_node(e)
			"machine":
				var slot2 := _free_slot()
				var e2 := {"uid": Game.uid(), "tool": item, "pos": _pad_slot(slot2) + Vector3(0, 0, 0.3), "yaw": 0.0, "order_id": o["id"], "pad_slot": slot2}
				Game.machines.append(e2)
				world.spawn_machine_node(e2)
				Game.add_equipment_stat(Catalog.item_name(StringName(item)))
			"vehicle":
				var p := _free_bay()
				var e3 := {"uid": Game.uid(), "id": item, "pos": p, "yaw": 0.0, "snow": 0.0, "order_id": o["id"]}
				Game.vehicles.append(e3)
				world.spawn_vehicle_node(e3)
				Game.add_equipment_stat(Catalog.item_name(StringName(item)))
			"upgrade", "utility", "equipment":
				if item == String(_ItemUpgrades.PLOW_ID):
					o["status"] = "spawned"
					continue
				var slot3 := _free_slot()
				var e4 := {"uid": Game.uid(), "tool": "crate:" + item, "pos": _pad_slot(slot3), "yaw": 0.0, "order_id": o["id"], "pad_slot": slot3}
				Game.items.append(e4)
				world.spawn_item_node(e4)
		o["status"] = "spawned"


## Remove pad slot bookkeeping once an item has left the pad.
func _process(_delta: float) -> void:
	var lot: Rect2 = (Layout.big_areas[1]["rect"] as Rect2).grow(2.0)
	for o in Economy.orders:
		if o["item"] == String(_ItemUpgrades.PLOW_ID) and o["status"] == "spawned":
			for v in world.vehicle_nodes():
				var veh: Vehicle = v
				if veh.data.kind == VehicleData.Kind.PICKUP and lot.has_point(Vector2(veh.global_position.x, veh.global_position.z)):
					world.install_plow(veh)
					Economy.mark_order(int(o["id"]), "collected")
					Game.grant_upgrade(_ItemUpgrades.PLOW_ID)
					Game.add_equipment_stat("Pickup front plow")
					Notify.push("The store crew bolted a front plow onto your pickup! %s to drop the blade, %s/%s to angle it." % [Settings.action_label("veh_tool"),
						Settings.action_label("veh_aim_left"), Settings.action_label("veh_aim_right")], Notify.GOOD)
					break
