extends Node3D
## Polish 8 §15: the player's garage — the overhead door (run from its button inside), the tool
## rack, the ceiling light and the first-visit hint. The shell (the hollow walls, the floor, the
## ceiling, the door from the house and its steps, the doorway's colliders) and the door's sections
## are HouseBuilder's, on the player's lot only; game_root makes this node once the world is built.
##
## - The overhead door opens and closes only from its button (E) inside. Closed, it blocks people
##   and vehicles, and a blade stops at its outer face (the old solid garage's face, gz0). It won't
##   close on something in the doorway. Its state is saved (Game.garage.door_open, closed by
##   default).
## - The rack: Catalog.balance.garage_rack_slots slots on the house-side wall, showing the real tool
##   models. F (store) with a tool in your hands, inside the garage, hangs it (on the slot you look
##   at if it's empty, else the first free one); E on a racked tool takes it into a free tool slot, or
##   swaps it with the one in your hands. Saved (Game.garage.rack). Upgrades follow the item type.
## - The light: a ceiling fixture, on while the house has power; a real light only while the player
##   is in or near the garage.

const DOOR_TIME := 2.4             # seconds to open or to close
const LIGHT_NEAR := 12.0
const RACK_LEN := 4.0              # the rack along the house-side wall (frame z), from the setback
const RACK_Z0 := 0.0

const _EquipmentRef := preload("res://scripts/data/equipment.gd")

var world: Node
var lot: Dictionary
var L: Transform3D
var sb := 0.0
var t := 0.0                       # where the door is: 0 closed … 1 open
var opening := false               # where it's going
var door: Node3D                   # HouseBuilder's sections
var door_body: StaticBody3D
var door_cs: CollisionShape3D
var rack_root: Node3D
var light: OmniLight3D
var fixture: MeshInstance3D
var _lamp_on: Material
var _lamp_off: Material
var _rack_sig := "?"


func setup(w: Node, door_node: Node3D) -> void:
	world = w
	door = door_node
	lot = Layout.player_lot
	L = HouseBuilder.lot_transform(lot)
	sb = float(lot["setback"])
	name = "Garage"
	_build_door_body()
	_build_button()
	_build_rack()
	_build_light()
	opening = bool(Game.garage.get("door_open", false))
	t = 1.0 if opening else 0.0
	_place_door()


func _gz0() -> float:
	return sb - 0.5


## The garage's footprint (world XZ), as Layout and Buildings have it.
static func footprint() -> Rect2:
	return Layout.house_info(Layout.player_lot)["garage"]


## True when a world point is inside the garage (its footprint, any height).
static func contains(p: Vector3) -> bool:
	return footprint().has_point(Vector2(p.x, p.z))


## The clear floor (world XZ) inside its walls.
static func floor_rect() -> Rect2:
	var s := float(Layout.player_lot["setback"])
	return HouseBuilder._world_rect(HouseBuilder.lot_transform(Layout.player_lot), HouseBuilder.GAR_X0 + HouseBuilder.GAR_IN_X0,
		HouseBuilder.GAR_X1 - HouseBuilder.WALL_T, s - 0.5, s + 7.0 - HouseBuilder.WALL_T)


## The steps down from the house (world XZ), vehicles kept off by their block.
static func steps_rect() -> Rect2:
	var s := float(Layout.player_lot["setback"])
	return HouseBuilder._world_rect(HouseBuilder.lot_transform(Layout.player_lot), HouseBuilder.GAR_X0,
		HouseBuilder.GAR_X0 + HouseBuilder.STEPS_X1 + 0.05, s + HouseBuilder.STEPS_Z0 - 0.1, s + HouseBuilder.LANDING_Z1)


# -----------------------------------------------------------------------------
# The overhead door
# -----------------------------------------------------------------------------

## The door's collider: the opening's full thickness, its outer face on the old solid garage's
## face (gz0), so a blade still stops where polish 7 measured it. It rises with the door.
func _build_door_body() -> void:
	door_body = StaticBody3D.new()
	door_body.name = "GarageDoorBody"
	door_body.collision_layer = 1
	door_body.collision_mask = 0
	add_child(door_body)
	door_cs = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HouseBuilder.GAR_DOOR_X1 - HouseBuilder.GAR_DOOR_X0, HouseBuilder.GAR_DOOR_H, HouseBuilder.GAR_DOOR_DEPTH)
	door_cs.shape = box
	door_body.add_child(door_cs)
	door_body.set_meta("garage_door", true)


func _place_door() -> void:
	if door:
		HouseBuilder.place_garage_door(door, L, sb, t)
	var xc := (HouseBuilder.GAR_DOOR_X0 + HouseBuilder.GAR_DOOR_X1) * 0.5
	var lift := t * (HouseBuilder.GAR_DOOR_H + 0.1)
	var c := Vector3(xc, HouseBuilder.GAR_DOOR_H * 0.5 + lift, _gz0() + HouseBuilder.GAR_DOOR_DEPTH * 0.5)
	door_cs.global_transform = HouseBuilder._proper(L * Transform3D(Basis(), c))
	door_cs.disabled = t >= 0.999


func is_open() -> bool:
	return t >= 0.999


func is_closed() -> bool:
	return t <= 0.001


## The button: open the door, or close it unless something is in the doorway. (Pressed while it
## moves, it turns back.)
func press() -> void:
	if opening and blocked():
		Notify.push("Something is in the way of the garage door.", Notify.WARN)
		AudioMgr.ui("ui_error")
		return
	opening = not opening
	Game.garage["door_open"] = opening
	Game.dirty_since_save = true
	AudioMgr.play_at("door_open" if opening else "door_close", _button_pos(), -2.0, 0.55)


## Something stands in the doorway, under the door: the player, a vehicle or a walk-behind machine.
func blocked() -> bool:
	var xc := (HouseBuilder.GAR_DOOR_X0 + HouseBuilder.GAR_DOOR_X1) * 0.5
	var sh := BoxShape3D.new()
	sh.size = Vector3(HouseBuilder.GAR_DOOR_X1 - HouseBuilder.GAR_DOOR_X0, HouseBuilder.GAR_DOOR_H - 0.1, HouseBuilder.GAR_DOOR_DEPTH + 0.06)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = HouseBuilder._proper(L * Transform3D(Basis(), Vector3(xc, HouseBuilder.GAR_DOOR_H * 0.5 + 0.05, _gz0() + HouseBuilder.GAR_DOOR_DEPTH * 0.5)))
	q.collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3)
	q.exclude = [door_body.get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 32):
		var n: Object = hit["collider"]
		if n is Player or n is Vehicle or n is WalkBehind:
			return true
	# A walk-behind being pushed has its collider off: it's where it is.
	var pl := Game.player as Player
	if pl and pl.machine != null and _in_doorway((pl.machine as Node3D).global_position):
		return true
	return false


func _in_doorway(p: Vector3) -> bool:
	var r := HouseBuilder._world_rect(L, HouseBuilder.GAR_DOOR_X0, HouseBuilder.GAR_DOOR_X1, _gz0() - 0.6, _gz0() + HouseBuilder.GAR_DOOR_DEPTH + 0.6)
	return r.has_point(Vector2(p.x, p.z))


func _physics_process(delta: float) -> void:
	var goal := 1.0 if opening else 0.0
	if t != goal:
		t = move_toward(t, goal, delta / DOOR_TIME)
		_place_door()


# -----------------------------------------------------------------------------
# The button (inside, on the front wall beside the door, house side)
# -----------------------------------------------------------------------------

func _button_pos() -> Vector3:
	return L * Vector3(HouseBuilder.GAR_X0 + 0.42, 1.3, _gz0() + HouseBuilder.WALL_T + 0.03)


func _build_button() -> void:
	var kit := MeshKit.new()
	var at := Vector3(HouseBuilder.GAR_X0 + 0.42, 1.3, _gz0() + HouseBuilder.WALL_T + 0.02)
	kit.box(Mats.std(Color(0.85, 0.85, 0.82), 0.5), L * Transform3D(Basis(), at), Vector3(0.12, 0.18, 0.04))
	kit.box(Mats.emissive(Color(0.95, 0.3, 0.2), 1.6), L * Transform3D(Basis(), at + Vector3(0, 0.03, 0.025)), Vector3(0.05, 0.05, 0.02))
	var mi := MeshInstance3D.new()
	mi.name = "GarageButton"
	mi.mesh = kit.commit()
	add_child(mi)
	var n := (L.basis * Vector3(0, 0, 1)).normalized()
	var it := Interactable.make(self, _button_pos(), Vector3(0.3, 0.35, 0.12),
		func(_p): return "[E] %s the garage door" % ("Close" if opening else "Open"),
		func(_p): press(), atan2(n.x, n.z))
	it.name = "GarageButtonArea"


# -----------------------------------------------------------------------------
# The rack
# -----------------------------------------------------------------------------

static func slots_n() -> int:
	var n := 6
	if Catalog.balance and "garage_rack_slots" in Catalog.balance:
		n = int(Catalog.balance.garage_rack_slots)
	return maxi(1, n)


## The rack's slots (tool ids, "" empty): at least as many as the balance gives.
static func rack() -> Array:
	if not Game.garage.has("rack") or not (Game.garage["rack"] is Array):
		Game.garage["rack"] = []
	var r: Array = Game.garage["rack"]
	while r.size() < slots_n():
		r.append("")
	return r


func _slot_z(i: int) -> float:
	return sb + RACK_Z0 + RACK_LEN / float(slots_n()) * (i + 0.5)


func _rack_x() -> float:
	return HouseBuilder.GAR_X0 + HouseBuilder.GAR_IN_X0


func _build_rack() -> void:
	rack_root = Node3D.new()
	rack_root.name = "Rack"
	add_child(rack_root)
	var kit := MeshKit.new()
	var wood := Mats.wood(Color(0.5, 0.35, 0.22), 0.0)
	var x := _rack_x() + 0.05
	var zc := sb + RACK_Z0 + RACK_LEN * 0.5
	kit.box(wood, L * Transform3D(Basis(), Vector3(x, 1.72, zc)), Vector3(0.1, 0.12, RACK_LEN))
	kit.box(wood, L * Transform3D(Basis(), Vector3(x, 0.62, zc)), Vector3(0.1, 0.08, RACK_LEN))
	var hook := Mats.metal(Color(0.3, 0.3, 0.32))
	for i in range(slots_n()):
		kit.box(hook, L * Transform3D(Basis(), Vector3(x + 0.1, 1.75, _slot_z(i))), Vector3(0.12, 0.03, 0.03))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	rack_root.add_child(mi)
	var n := (L.basis * Vector3(1, 0, 0)).normalized()
	for i in range(slots_n()):
		var k := i
		var it := Interactable.make(rack_root, L * Vector3(x + 0.2, 1.1, _slot_z(i)), Vector3(0.3, 1.5, RACK_LEN / float(slots_n()) - 0.04),
			func(_p): return slot_prompt(k), func(p): take(k, p), atan2(n.x, n.z))
		it.name = "RackSlot%d" % i
		it.set_meta("rack_slot", k)
	_refresh_rack()


## The tool in your hands: the one carried in your arms (never the heated pad), else the selected
## slot's ("" when your hands are empty).
static func held_tool() -> String:
	if Game.carried != "":
		return "" if Game.carried == String(_EquipmentRef.PAD) else Game.carried
	return str(Game.slots[Game.selected])


func slot_prompt(i: int) -> String:
	var r := rack()
	var id: String = r[i]
	var held := held_tool()
	if id == "":
		if held != "":
			return "[%s] Put %s on the rack" % [Settings.action_label("store"), Catalog.tool(StringName(held)).display_name]
		return "Tool rack (empty)"
	var nm := Catalog.tool(StringName(id)).display_name
	if Game.carried == "" and Game.free_slot() >= 0:
		return "[E] Take %s" % nm
	if held != "":
		return "[E] Swap %s for %s" % [Catalog.tool(StringName(held)).display_name, nm]
	return "%s (your hands are full)" % nm


## F: hang the tool in your hands — on the slot `prefer` if it's empty, else the first free one.
## "" when it's on the rack, otherwise why not.
func store(p: Player, prefer := -1) -> String:
	var held := held_tool()
	if held == "":
		return "empty"
	var r := rack()
	var i := prefer if prefer >= 0 and prefer < slots_n() and str(r[prefer]) == "" else -1
	if i < 0:
		for k in range(slots_n()):
			if str(r[k]) == "":
				i = k
				break
	if i < 0:
		Notify.push("The rack is full.", Notify.WARN)
		return "full"
	p.tools.dump_at_feet(true)
	if Game.carried != "":
		Game.carried = ""
		Game.inventory_changed.emit()
	else:
		Game.take_selected()
	r[i] = held
	Game.dirty_since_save = true
	AudioMgr.play_at("pickup_item", p.global_position, -4.0)
	_refresh_rack()
	return ""


## E on a slot: take its tool into a free tool slot, or swap it with the one in your hands. (E on an
## empty slot hangs what you hold, like F.)
func take(i: int, p: Player) -> void:
	var r := rack()
	var id: String = r[i]
	if id == "":
		store(p, i)
		return
	if Game.carried == "" and Game.free_slot() >= 0:
		r[i] = ""
		Game.add_tool(id)
	else:
		var held := held_tool()
		if held == "":
			return
		p.tools.dump_at_feet(true)
		if Game.carried != "":
			Game.carried = id
		else:
			Game.slots[Game.selected] = id
		r[i] = held
		Game.inventory_changed.emit()
	Game.dirty_since_save = true
	AudioMgr.play_at("pickup_item", p.global_position, -4.0)
	_refresh_rack()


func _refresh_rack() -> void:
	var r := rack()
	var sig := ",".join(r)
	if sig == _rack_sig:
		return
	_rack_sig = sig
	for c in rack_root.get_children():
		if c.has_meta("rack_tool"):
			c.queue_free()
	var x := _rack_x() + 0.2
	for i in range(mini(r.size(), slots_n())):
		if str(r[i]) == "":
			continue
		var m := MeshInstance3D.new()
		m.name = "RackTool%d" % i
		m.mesh = ToolModels.mesh_for(str(r[i]))
		m.set_meta("rack_tool", true)
		rack_root.add_child(m)
		# Hung by the grip from its hook, the blade down and its width along the wall (as the old
		# rack on the front wall, turned to face into the garage).
		m.global_transform = L * Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(-30)), Vector3(x, 1.72, _slot_z(i)))
		m.scale = Vector3.ONE * 0.85


## The rack slot the player looks at (-1 if none).
static func looked_slot(p: Player) -> int:
	var f: Variant = p.get("focus")
	if f is Object and is_instance_valid(f) and (f as Object).has_meta("rack_slot"):
		return int((f as Object).get_meta("rack_slot"))
	return -1


# -----------------------------------------------------------------------------
# The light
# -----------------------------------------------------------------------------

func _build_light() -> void:
	var c := Vector3((HouseBuilder.GAR_X0 + HouseBuilder.GAR_X1) * 0.5, HouseBuilder.GAR_CEIL - 0.03, sb + 3.6)
	_lamp_on = Mats.emissive(Color(1.0, 0.93, 0.8), 2.4)
	_lamp_off = Mats.std(Color(0.8, 0.8, 0.78), 0.4)
	var kit := MeshKit.new()
	kit.box(Mats.std(Color(0.8, 0.8, 0.78), 0.4), Transform3D(), Vector3(1.2, 0.05, 0.22))
	fixture = MeshInstance3D.new()
	fixture.name = "GarageLight"
	fixture.mesh = kit.commit()
	add_child(fixture)
	fixture.global_transform = HouseBuilder._proper(L * Transform3D(Basis(), c))
	light = OmniLight3D.new()
	light.name = "GarageLamp"
	light.light_color = Color(1.0, 0.93, 0.82)
	light.light_energy = 1.3
	light.omni_range = 7.5
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	light.global_position = L * (c - Vector3(0, 0.25, 0))
	update_light(Vector3(1e6, 0, 1e6))


## On while the house has power; a real light only while the player is in or near the garage.
func update_light(player_pos: Vector3) -> void:
	var on := Survival.power_on
	fixture.material_override = _lamp_on if on else _lamp_off
	var near := contains(player_pos) or player_pos.distance_to(light.global_position) < LIGHT_NEAR
	light.visible = on and near


# -----------------------------------------------------------------------------
# Each frame: the rack follows the save (a load, a test); the first visit's hint
# -----------------------------------------------------------------------------

func _process(_d: float) -> void:
	_refresh_rack()
	var pl := Game.player as Player
	if pl and pl.in_garage and not Game.hint_seen("garage") and world and world.has_method("show_hint"):
		world.show_hint("garage")
