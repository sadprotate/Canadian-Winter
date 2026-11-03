class_name BoxOutline
extends MeshInstance3D
## Work outline (polish 2 §3): while the player takes snow out of a clearing box — scooping or
## pushing with hands or any tool, or running a blower — a thin, soft line traces that box's whole
## outer boundary on top of the snow (following the terrain), so it's clear what still needs
## clearing and where not to throw. Only the box being worked on is outlined; the line stays while
## the work goes on, fades a few seconds after it stops (or as soon as the player walks away), and
## vanishes when the box completes (the completion flash takes over).

const HOLD_S := 3.0          # seconds the outline stays after the last scoop / push
const FADE_S := 1.0
const LEAVE_DIST := 6.0      # walking this far from the box starts the fade at once
const COLOR := Color(0.62, 0.9, 1.0)
const WIDTH := 0.08
const LIFT := 0.035
const DRAW_RADIUS := 30.0

## Quest mode (polish 3 §4): when set, this outline shows the box this returns ("" for none)
## all the time — no fading when work stops or the player walks away — until it completes. Used for
## Gerry's trail while the tutorial asks you to clear it.
var quest_fn: Callable
## Work mode: a box another (quest) outline already shows is not drawn twice.
var skip_fn: Callable
var box_id := ""             # the outlined box ("" when hidden)
var alpha := 0.0             # current opacity factor 0..1 (tests read it)
var _seen_serial := -1
var _idle := 0.0
var _rebuild_t := 0.0
var _segs := PackedVector2Array()
var _im: ImmediateMesh
var _mat: StandardMaterial3D
var _big := false


func _ready() -> void:
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(COLOR, 0.0)
	material_override = _mat
	visible = false
	_seen_serial = Boxes.work_serial
	Boxes.box_completed.connect(_on_box_completed)


func _on_box_completed(id: String) -> void:
	if id == box_id:
		_hide()


func _hide() -> void:
	box_id = ""
	alpha = 0.0
	visible = false
	_im.clear_surfaces()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if quest_fn.is_valid():
		_process_quest(delta)
		return
	if Boxes.work_serial != _seen_serial:
		_seen_serial = Boxes.work_serial
		_idle = 0.0
		var skip: String = skip_fn.call() if skip_fn.is_valid() else ""
		if skip != "" and Boxes.work_box == skip:
			# The quest outline already shows this box; let any other outline fade.
			_idle = HOLD_S
		elif Boxes.work_box != box_id and Boxes.work_box != "":
			box_id = Boxes.work_box
			_segs = Boxes.outline_segments(box_id)
			_big = float(Boxes.get_box(box_id).get("area", 0.0)) > 250.0
			_rebuild_t = 0.0
	else:
		_idle += delta
	if box_id == "":
		return
	var b := Boxes.get_box(box_id)
	if b.is_empty() or b["complete"]:
		_hide()
		return
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	var away := true
	for r in b["rects"]:
		if (r as Rect2).grow(LEAVE_DIST).has_point(pp):
			away = false
			break
	var target := 1.0 if (_idle < HOLD_S and not away) else 0.0
	alpha = move_toward(alpha, target, delta / (0.25 if target > 0.0 else FADE_S))
	if alpha <= 0.0 and target == 0.0:
		_hide()
		return
	visible = true
	# Unshaded, so it would glow at night: dim it with the light so it stays a quiet hint.
	var night := 0.0
	if Game.world and Game.world.get("day_night") != null:
		night = float(Game.world.day_night.night)
	_mat.albedo_color = Color(COLOR * lerpf(1.0, 0.6, night), lerpf(0.72, 0.55, night) * alpha)
	_rebuild_t -= delta
	if _rebuild_t <= 0.0:
		# The snow under the line changes as the player digs: re-drape it now and then.
		_rebuild_t = 1.2 if _big else 0.35
		_build()


func _process_quest(delta: float) -> void:
	var id: String = quest_fn.call()
	var b := Boxes.get_box(id) if id != "" else {}
	if b.is_empty() or b["complete"]:
		if box_id != "":
			_hide()
		return
	if id != box_id:
		box_id = id
		_segs = Boxes.outline_segments(id)
		_big = float(b.get("area", 0.0)) > 250.0
		_rebuild_t = 0.0
	alpha = move_toward(alpha, 1.0, delta / 0.25)
	visible = true
	var night := 0.0
	if Game.world and Game.world.get("day_night") != null:
		night = float(Game.world.day_night.night)
	# Same look as the work outline; dimmed less at night so the objective is easy to find.
	_mat.albedo_color = Color(COLOR * lerpf(1.0, 0.78, night), lerpf(0.8, 0.72, night) * alpha)
	_rebuild_t -= delta
	if _rebuild_t <= 0.0:
		_rebuild_t = 0.35
		_build()


## Lay the boundary on the snow: a flat ribbon plus a low fin (visible from shallow angles), each
## corner at the higher of the snow surfaces around it, so a dug-out box shows its line along the
## top of the surrounding snow wall.
func _build() -> void:
	_im.clear_surfaces()
	if _segs.is_empty():
		return
	var hcache := {}
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, _segs.size(), 2):
		var a: Vector2 = _segs[i]
		var c: Vector2 = _segs[i + 1]
		# Long boxes (streets, parking lots): only the stretch around the player is drawn.
		if _big and a.distance_squared_to(pp) > DRAW_RADIUS * DRAW_RADIUS:
			continue
		var ha := _corner_h(a, hcache)
		var hc := _corner_h(c, hcache)
		var d := (c - a).normalized()
		var n := Vector2(-d.y, d.x) * WIDTH * 0.5
		var a0 := Vector3(a.x - n.x, ha, a.y - n.y)
		var a1 := Vector3(a.x + n.x, ha, a.y + n.y)
		var c0 := Vector3(c.x - n.x, hc, c.y - n.y)
		var c1 := Vector3(c.x + n.x, hc, c.y + n.y)
		for v in [a0, c0, c1, a0, c1, a1]:
			_im.surface_add_vertex(v)
		var up := Vector3(0, 0.045, 0)
		var fa := Vector3(a.x, ha, a.y)
		var fc := Vector3(c.x, hc, c.y)
		for v in [fa, fc, fc + up, fa, fc + up, fa + up]:
			_im.surface_add_vertex(v)
	_im.surface_end()


func _corner_h(v: Vector2, cache: Dictionary) -> float:
	if cache.has(v):
		return cache[v]
	var e := Snow.CELL * 0.5
	var h := -INF
	for o in [Vector2(-e, -e), Vector2(e, -e), Vector2(-e, e), Vector2(e, e)]:
		var q: Vector2 = v + o
		h = maxf(h, Snow.surface_height(q.x, q.y))
	h += LIFT
	cache[v] = h
	return h
