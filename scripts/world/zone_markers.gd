class_name ZoneMarkers
extends Node3D
## Contract zones as physical markers: orange stakes at the corners and a soft glowing outline
## drawn on the snow surface while the player is nearby (not for Gerry's tutorial trail, which
## is outlined in blue by BoxOutline). Also plays the small "box complete"
## moment (polish §7): a chime and a bright outline that flashes around the freshly bared box.

var _stakes: Dictionary = {}     # key -> Array[Node3D]
var _line: MeshInstance3D
var _im: ImmediateMesh
var _t := 0.0
var _flash: MeshInstance3D
var _flash_im: ImmediateMesh
var _flash_mat: StandardMaterial3D
var _flash_t := 0.0
static var _stake_mesh: Mesh


func _ready() -> void:
	if _stake_mesh == null:
		var kit := MeshKit.new()
		kit.cylinder(Mats.wood(Color(0.6, 0.45, 0.3), 0.0), Transform3D(), 0.025, 0.02, 1.6, 6, true)
		kit.box(Mats.emissive(Color(1.0, 0.45, 0.05), 1.6), Transform3D(Basis(), Vector3(0.09, 1.45, 0)), Vector3(0.18, 0.12, 0.01))
		_stake_mesh = kit.commit()
	_im = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.mesh = _im
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	m.vertex_color_use_as_albedo = false
	_line.material_override = m
	add_child(_line)
	_flash_im = ImmediateMesh.new()
	_flash = MeshInstance3D.new()
	_flash.mesh = _flash_im
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(0.75, 1.0, 0.85, 0.0)
	_flash.material_override = _flash_mat
	_flash.visible = false
	add_child(_flash)
	Boxes.box_completed.connect(_on_box_completed)


func _on_box_completed(id: String) -> void:
	var b := Boxes.get_box(id)
	if b.is_empty() or not is_inside_tree():
		return
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	var near := false
	var center := Vector2.ZERO
	for r in b["rects"]:
		center += (r as Rect2).get_center()
		if (r as Rect2).grow(25.0).has_point(pp):
			near = true
	if not near:
		return
	center /= float((b["rects"] as Array).size())
	AudioMgr.play_at("box_complete" if AudioMgr.has_sound("box_complete") else "ui_money", Vector3(center.x, Snow.ground_at(center.x, center.y) + 0.5, center.y), -2.0)
	# Bright outline hugging the bare ground, plus a few sparkles along the edges.
	_flash_im.clear_surfaces()
	_flash_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in b["rects"]:
		_band(r as Rect2, 0.12)
	_flash_im.surface_end()
	_flash.visible = true
	_flash_t = 1.4
	for r in b["rects"]:
		var rr: Rect2 = r
		for p in [rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y), rr.get_center()]:
			SnowFX.burst(Vector3(p.x, Snow.ground_at(p.x, p.y) + 0.1, p.y), 6, 0.5)


## A thin glowing band just inside the edges of a rect, lying on the bare ground.
func _band(r: Rect2, w: float) -> void:
	var y := 0.03
	var inner := r.grow(-w)
	var outer := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var inn := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	for i in range(4):
		var a: Vector2 = outer[i]
		var b2: Vector2 = outer[(i + 1) % 4]
		var c: Vector2 = inn[(i + 1) % 4]
		var d: Vector2 = inn[i]
		var ya := Snow.ground_at(a.x, a.y) + y
		for p in [a, b2, c, a, c, d]:
			_flash_im.surface_add_vertex(Vector3(p.x, maxf(Snow.ground_at(p.x, p.y), ya - y) + y, p.y))


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		var a := clampf(_flash_t / 1.4, 0.0, 1.0)
		_flash_mat.albedo_color = Color(0.75, 1.0, 0.85, 0.9 * a * a)
		if _flash_t <= 0.0:
			_flash.visible = false
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var want := {}
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	_im.clear_surfaces()
	var drew := false
	for c in Contracts.active:
		if c["status"] != "active" and c["status"] != "needs_service":
			continue
		# Gerry's tutorial trail has no stakes or orange line: its objective is the blue
		# outline (BoxOutline quest mode, polish 3 §4). Real contracts keep their stakes.
		if c.get("tutorial", false):
			continue
		for zi in range(c["zones"].size()):
			var z: Dictionary = c["zones"][zi]
			if z["done"]:
				continue
			for ri in range(z["rects"].size()):
				var r := Contracts.a_to_rect(z["rects"][ri])
				var key := "%d_%d_%d" % [c["id"], zi, ri]
				want[key] = r
				if r.grow(25.0).has_point(pp):
					if not drew:
						_im.surface_begin(Mesh.PRIMITIVE_LINES)
						drew = true
					_outline(r)
	if drew:
		_im.surface_end()
	# Stakes
	for k in _stakes.keys():
		if not want.has(k):
			for s in _stakes[k]:
				(s as Node3D).queue_free()
			_stakes.erase(k)
	for k in want.keys():
		if _stakes.has(k):
			continue
		var r2: Rect2 = want[k]
		var arr := []
		for p in [r2.position, Vector2(r2.end.x, r2.position.y), r2.end, Vector2(r2.position.x, r2.end.y)]:
			var s := MeshInstance3D.new()
			s.mesh = _stake_mesh
			add_child(s)
			s.global_position = Vector3(p.x, Snow.ground_at(p.x, p.y), p.y)
			arr.append(s)
		_stakes[k] = arr


func _outline(r: Rect2) -> void:
	var pts := []
	var step := 0.5
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		var n := maxi(1, int(a.distance_to(b) / step))
		for k in range(n):
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			_im.surface_add_vertex(Vector3(p0.x, Snow.surface_height(p0.x, p0.y) + 0.05, p0.y))
			_im.surface_add_vertex(Vector3(p1.x, Snow.surface_height(p1.x, p1.y) + 0.05, p1.y))
