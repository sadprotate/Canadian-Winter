class_name BoxOutline
extends MeshInstance3D
## Work outline (polish 2 §3): while the player takes snow out of a clearing box — scooping or
## pushing with hands or any tool, or running a blower — a thin, soft line traces that box's whole
## outer boundary on top of the snow (following the terrain), so it's clear what still needs
## clearing and where not to throw. Only the box being worked on is outlined; the line stays while
## the work goes on, fades a few seconds after it stops (or as soon as the player walks away), and
## vanishes when the box completes (the completion flash takes over).
##
## Polish 5 §10: a box of one of your jobs is outlined in a dark money green instead of the blue —
## persistently (ZoneMarkers lays one quest-mode outline per box) and as the work outline while you
## clear it; Gerry's trail and every other box stay blue.

const HOLD_S := 3.0          # seconds the outline stays after the last scoop / push
const FADE_S := 1.0
const LEAVE_DIST := 6.0      # walking this far from the box starts the fade at once
const COLOR := Color(0.62, 0.9, 1.0)
## Polish 5 §10: a job's box — dark money green. Unshaded, so it is dimmed at night like the blue,
## but less (it is dark and doesn't glow): it stays clearly green on the night snow.
const JOB_COLOR := Color(0.07, 0.42, 0.17)
const JOB_NIGHT_KEEP := 0.85
const JOB_ALPHA := Vector2(0.92, 0.85)   # opacity by day, at night
const WIDTH := 0.08
const LIFT := 0.035
const DRAW_RADIUS := 30.0

## Quest mode (polish 3 §4): when set, this outline shows the box this returns ("" for none)
## all the time — no fading when work stops or the player walks away — until it completes. Used for
## Gerry's trail while the tutorial asks you to clear it.
var quest_fn: Callable
## Work mode: a box another (quest) outline already shows is not drawn twice.
var skip_fn: Callable
## Polish 5 §10: drawn in JOB_COLOR (a box of one of your jobs) instead of the blue.
var job := false
## Work mode: true when the box being worked belongs to one of your jobs (sets `job`).
var job_fn: Callable
## Quest mode: how often (s) the line is re-draped on the snow.
var rebuild_s := 0.35
## Quest mode: the work outline. While it shows this outline's box, this one gives way (fades out as
## it fades in, and back), so the box is never drawn twice.
var defer_to: BoxOutline
## Quest mode: 0..1, spreads the re-drapes of many outlines over the interval.
var stagger := 0.0
## Quest mode: when > 0, a re-drape that is due is skipped unless the snow in the box changed by this
## much (average depth, m) — or, for a street or a parking lot, the player moved a few metres (the
## part drawn follows them) — or REDRAPE_MAX_S went by. ZoneMarkers sets it for boxes away from the
## player.
var redrape_depth := 0.0
const REDRAPE_MAX_S := 6.0
const REDRAPE_MOVE := 3.0
var _drape_d := -1.0
var _drape_age := 0.0
var _drape_at := Vector2.INF
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
			job = job_fn.is_valid() and bool(job_fn.call(box_id))
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
	_mat.albedo_color = _tint(0.6, Vector2(0.72, 0.55))
	_rebuild_t -= delta
	if _rebuild_t <= 0.0:
		# The snow under the line changes as the player digs: re-drape it now and then.
		_rebuild_t = 1.2 if _big else 0.35
		if job_fn.is_valid():
			job = bool(job_fn.call(box_id))
		_build()


func _process_quest(delta: float) -> void:
	var id: String = quest_fn.call()
	var b := Boxes.get_box(id) if id != "" else {}
	if b.is_empty() or b["complete"]:
		if box_id != "":
			_hide()
		return
	var first := id != box_id
	if first:
		box_id = id
		_segs = Boxes.outline_segments(id)
		_big = float(b.get("area", 0.0)) > 250.0
		_rebuild_t = 0.0
	# Polish 5 §10: give way to the work outline while it shows the same box.
	var target := 1.0
	if defer_to != null and is_instance_valid(defer_to) and defer_to.visible and defer_to.box_id == box_id:
		target = 1.0 - defer_to.alpha
	alpha = move_toward(alpha, target, delta / 0.25)
	if alpha <= 0.0 and not first:
		visible = false
		_rebuild_t = 0.0     # re-drape as soon as it shows again
		_drape_age = REDRAPE_MAX_S
		return
	visible = true
	# Same look as the work outline; dimmed less at night so the objective is easy to find.
	_mat.albedo_color = _tint(0.78, Vector2(0.8, 0.72))
	_rebuild_t -= delta
	_drape_age += delta
	if _rebuild_t <= 0.0:
		_rebuild_t = rebuild_s * (1.0 + stagger) if first else rebuild_s
		var d := float(b.get("vol", 0.0)) / maxf(float(b.get("area", 0.0)), 0.01)
		var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
		if first or redrape_depth <= 0.0 or absf(d - _drape_d) >= redrape_depth or _drape_age >= REDRAPE_MAX_S \
				or (_big and pp.distance_to(_drape_at) >= REDRAPE_MOVE):
			_drape_d = d
			_drape_age = 0.0
			_drape_at = pp
			_build()


## The line's colour now: blue, dimmed at night by `keep` (an unshaded line would glow) with the
## opacity `a` (by day, at night) — or a job's money green (JOB_*), the same in both modes.
func _tint(keep: float, a: Vector2) -> Color:
	var night := 0.0
	if Game.world and Game.world.get("day_night") != null:
		night = float(Game.world.day_night.night)
	var col := COLOR
	if job:
		col = JOB_COLOR
		keep = JOB_NIGHT_KEEP
		a = JOB_ALPHA
	return Color(col * lerpf(1.0, keep, night), lerpf(a.x, a.y, night) * alpha)


## The colour the line is drawn in now (tests).
func line_color() -> Color:
	return _mat.albedo_color


## Lay the boundary on the snow: a flat ribbon plus a low fin (visible from shallow angles), each
## corner at the higher of the snow surfaces around it, so a dug-out box shows its line along the
## top of the surrounding snow wall.
func _build() -> void:
	_im.clear_surfaces()
	if _segs.is_empty():
		return
	var hcache := {}
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	var begun := false
	for i in range(0, _segs.size(), 2):
		var a: Vector2 = _segs[i]
		var c: Vector2 = _segs[i + 1]
		# Long boxes (streets, parking lots): only the stretch around the player is drawn.
		if _big and a.distance_squared_to(pp) > DRAW_RADIUS * DRAW_RADIUS:
			continue
		if not begun:
			_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			begun = true
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
	# (A street or a parking lot with no edge within DRAW_RADIUS of the player draws nothing.)
	if begun:
		_im.surface_end()


func _corner_h(v: Vector2, cache: Dictionary) -> float:
	if cache.has(v):
		return cache[v]
	# The four cells meeting at this grid corner (polish 5 §10b: read at their centres directly — the
	# same heights surface_height gives there, a quarter of the reads).
	var cx := roundi(v.x / Snow.CELL)
	var cz := roundi(v.y / Snow.CELL)
	var h := maxf(maxf(Snow.cell_surface(cx - 1, cz - 1), Snow.cell_surface(cx, cz - 1)), maxf(Snow.cell_surface(cx - 1, cz), Snow.cell_surface(cx, cz)))
	h += LIFT
	cache[v] = h
	return h
