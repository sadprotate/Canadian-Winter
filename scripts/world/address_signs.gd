class_name AddressSigns
extends RefCounted
## Polish 5 §5: the house and building numbers in the world, read from the layout (Layout's
## addresses). Every house: a plate by its front door, under the porch lantern, facing the street,
## and the number on its mailbox's door. Every other building: large numbers by its main entrance,
## on the wall that faces the street (Layout.buildings[i]["number_at"]). Each is its own small
## node with a visibility range, so numbers out of reading range are never drawn.

## The plate, in the house frame (HouseBuilder: x along the street, y up, z inward; the front
## wall's outer face at z = setback, or 5.5 cm in front of it on the hollow houses): centred under
## the wall lantern beside the door (the lantern at x -0.55, y 2.0), clear of the door's casing.
const PLATE_X := -0.55
const PLATE_Y := 1.6
const PLATE_SIZE := Vector2(0.56, 0.32)
const PLATE_DEPTH := 0.025
const PLATE_DIGIT_H := 0.21
const PLATE_BORDER := 0.02
const PLATE_RANGE := 35.0         # m: beyond this the plate isn't drawn (its digits are ~4 px there)
const PLATE_LAMP := 0.9           # the lantern's light on it at night (address_plate.gdshader)
const PLATE_PAINT := Color(0.08, 0.09, 0.11)
const DIGIT_PAINT := Color(0.92, 0.88, 0.76)
## The mailbox's door (Props.mailbox: the door is the model's -Z end at z -0.23, the box 0.26 wide,
## y 1.15–1.39 under its rounded top).
const MAILBOX_AT := Vector3(0.0, 1.29, -0.236)
const MAILBOX_DIGIT_H := 0.085
const MAILBOX_RANGE := 20.0
## Buildings: digits' height and how far they are drawn.
const BUILDING_DIGIT_H := 1.0
const BUILDING_RANGE := 90.0


## Where a house's plate is (world): its centre, its basis facing the street (+Z out, +X to the
## right as seen from the street, never mirrored).
static func plate_xf(lot: Dictionary, hollow: bool) -> Transform3D:
	var L := HouseBuilder.lot_transform(lot)
	var face_z: float = float(lot["setback"]) - (0.055 if hollow else 0.0)
	var c := L * Vector3(PLATE_X, PLATE_Y, face_z - PLATE_DEPTH * 0.5 - 0.004)
	var f: Vector2 = Layout.house_info(lot)["facing"]
	var z := Vector3(f.x, 0.0, f.y).normalized()
	return Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), c)


## The plate by a house's front door (child of the house's root).
static func house_plate(lot: Dictionary, parent: Node3D, hollow: bool) -> MeshInstance3D:
	var num := str(lot["number"])
	var key := "plate:" + num
	if not _meshes.has(key):
		var kit := MeshKit.new()
		var bw := Vector2(PLATE_BORDER / PLATE_SIZE.x, PLATE_BORDER / PLATE_SIZE.y)
		kit.box(Mats.address_paint(PLATE_PAINT, DIGIT_PAINT, bw, PLATE_LAMP), Transform3D(), Vector3(PLATE_SIZE.x, PLATE_SIZE.y, PLATE_DEPTH))
		kit.text(Mats.address_paint(DIGIT_PAINT, Color.BLACK, Vector2.ZERO, PLATE_LAMP), Transform3D(Basis(), Vector3(0, 0, PLATE_DEPTH * 0.5 + 0.002)), num, PLATE_DIGIT_H)
		_meshes[key] = kit.commit()
	var mi := _instance(parent, "HouseNumber", _meshes[key], PLATE_RANGE)
	_place(mi, plate_xf(lot, hollow))
	mi.set_meta("number", int(lot["number"]))
	mi.set_meta("address", str(lot["address"]))
	return mi


## The number on a mailbox's door (child of the mailbox; the door faces the street).
static func mailbox_number(lot: Dictionary, mailbox: Node3D) -> MeshInstance3D:
	var num := str(lot["number"])
	var key := "mailbox:" + num
	if not _meshes.has(key):
		var kit := MeshKit.new()
		# The door is the model's -Z end: the text faces -Z, reading left to right from in front.
		kit.text(Mats.address_paint(DIGIT_PAINT), Transform3D(Basis(Vector3.UP, PI), MAILBOX_AT), num, MAILBOX_DIGIT_H)
		_meshes[key] = kit.commit()
	var mi := _instance(mailbox, "MailboxNumber", _meshes[key], MAILBOX_RANGE)
	mi.set_meta("number", int(lot["number"]))
	return mi


## Where a building's number is (world) and which way it faces.
static func building_xf(b: Dictionary) -> Transform3D:
	var na: Array = b["number_at"]
	var c := Vector3(na[0], na[1], na[2])
	var z := Vector3(na[3], 0.0, na[4]).normalized()
	return Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), c)


## A building's number by its main entrance, in the lettering of its name sign.
static func building_number(b: Dictionary, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.name = "Number_%s" % b["id"]
	l.text = str(b["number"])
	l.font_size = 176
	l.pixel_size = BUILDING_DIGIT_H / (176.0 * 0.72)   # digits are ~0.72 em tall in the game's font
	l.modulate = Color(1, 0.92, 0.7) if b["kind"] == "store" else Color(0.95, 0.95, 0.9)
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.shaded = false
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	_place(l, building_xf(b))
	_range(l, BUILDING_RANGE)
	l.set_meta("number", int(b["number"]))
	l.set_meta("address", str(b["address"]))
	return l


## Puts a sign at a world transform (the world is built inside the tree; outside it, only the
## parent's own transform is undone).
static func _place(n: Node3D, xf: Transform3D) -> void:
	if n.is_inside_tree():
		n.global_transform = xf
	else:
		n.transform = (n.get_parent() as Node3D).transform.affine_inverse() * xf if n.get_parent() is Node3D else xf


## Meshes shared by every sign showing the same number ("plate:24", "mailbox:24").
static var _meshes := {}


static func _instance(parent: Node, node_name: String, mesh: Mesh, range_end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_range(mi, range_end)
	parent.add_child(mi)
	return mi


static func _range(g: GeometryInstance3D, end: float) -> void:
	g.visibility_range_end = end
	g.visibility_range_end_margin = 3.0
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
