class_name ZoneMarkers
extends Node3D
## Where your jobs are, on the snow. Polish 5 §10: contracts have no stakes or flags (they used to
## get orange stakes with a flag at every corner and an orange line). Every incomplete box of an
## active job is outlined the way Gerry's trail is — BoxOutline's quest mode, there all the time — in
## a dark money green; the work outline turns the same green while you clear it (BoxOutline.job_fn),
## and this outline gives way to it so the box isn't drawn twice. Gerry's trail and every other box
## stay blue. For performance only the boxes near the player are laid, one per scan, and they are
## re-draped on the snow at a low rate (quickly only while the player is at the box; elsewhere only
## once its snow has changed); streets and parking lots are drawn within BoxOutline.DRAW_RADIUS of
## the player, as before.
## Also plays the small "box complete" moment (polish §7): a chime and a bright outline that flashes
## around the freshly bared box.

const SCAN_S := 0.25           # how often the jobs' boxes are looked at (s)
const LAY_RADIUS := 50.0       # a box within this of the player (m, to its nearest edge) is outlined…
const DROP_RADIUS := 60.0      # …and keeps its outline until it is farther than this
const LAY_PER_SCAN := 1        # outlines laid per scan at most (nearest first)
const NEAR_DIST := 8.0         # within this of a box its line is re-draped as often as the work outline's
const REDRAPE_NEAR_S := 0.35
const REDRAPE_NEAR_BIG_S := 1.2
const REDRAPE_FAR_S := 1.5     # …farther away, at most this often, and only once its snow has changed
const REDRAPE_DEPTH := 0.01    # by this much (average depth, m; BoxOutline.redrape_depth)

## Polish 5 §10: contracts have no stakes or flags, so this stays empty (the earlier "no flags on
## Gerry's trail" checks read it).
var _stakes: Dictionary = {}
var outlines: Dictionary = {}   # box id -> BoxOutline (quest mode, money green)
var work_outline: BoxOutline    # the world's work outline (a job's outline gives way to it)
var _t := 0.0
var _laid := 0
var _flash: MeshInstance3D
var _flash_im: ImmediateMesh
var _flash_mat: StandardMaterial3D
var _flash_t := 0.0


func _ready() -> void:
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


## A contract whose boxes are outlined: an active job or an open visit, not Gerry's trail.
static func is_job(c: Dictionary) -> bool:
	return (c["status"] == "active" or c["status"] == "needs_service") and not c.get("tutorial", false)


## True when the box belongs to one of your jobs (is_job) and still has snow to clear.
static func is_job_box(id: String) -> bool:
	if Boxes.is_complete(id):
		return false
	for c in Contracts.active:
		if is_job(c) and id in Contracts.contract_boxes(c):
			return true
	return false


## Every incomplete box of your jobs.
static func job_boxes() -> Array:
	var out := []
	for c in Contracts.active:
		if not is_job(c):
			continue
		for id in Contracts.contract_boxes(c):
			var b := Boxes.get_box(id)
			if not b.is_empty() and not b["complete"] and not (id in out):
				out.append(id)
	return out


static func _box_dist(b: Dictionary, p: Vector2) -> float:
	var d := INF
	for r in b["rects"]:
		d = minf(d, Boxes._dist_to_rect(r as Rect2, p))
	return d


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
	_t = SCAN_S
	_scan()


## Which job boxes are near enough to be outlined: lay the missing ones (nearest first,
## LAY_PER_SCAN per scan), drop those that are done or far away, and set how often each is re-draped.
func _scan() -> void:
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	var want := {}
	for c in Contracts.active:
		if not is_job(c):
			continue
		for id in Contracts.contract_boxes(c):
			var b := Boxes.get_box(id)
			if b.is_empty() or b["complete"] or want.has(id):
				continue
			var d := _box_dist(b, pp)
			if d <= (DROP_RADIUS if outlines.has(id) else LAY_RADIUS):
				want[id] = d
	for id in outlines.keys():
		if not want.has(id):
			(outlines[id] as BoxOutline).queue_free()
			outlines.erase(id)
	var ids := want.keys()
	ids.sort_custom(func(a, b): return want[a] < want[b])
	var laid := 0
	for id in ids:
		var ol: BoxOutline = outlines.get(id)
		if ol == null:
			if laid >= LAY_PER_SCAN:
				continue
			ol = _lay(id)
			laid += 1
		var near := float(want[id]) <= NEAR_DIST
		# (A street or a parking lot near the player: as often as the work outline re-drapes one.)
		ol.rebuild_s = (REDRAPE_NEAR_BIG_S if bool(Boxes.get_box(id).get("big", false)) else REDRAPE_NEAR_S) if near else REDRAPE_FAR_S
		ol.redrape_depth = 0.0 if near else REDRAPE_DEPTH


func _lay(id: String) -> BoxOutline:
	var ol := BoxOutline.new()
	ol.name = "JobOutline_" + id
	ol.job = true
	ol.quest_fn = func() -> String: return id
	ol.defer_to = work_outline
	# Spread the re-drapes of many outlines over the interval (golden-ratio steps, no randomness).
	ol.stagger = fmod(_laid * 0.618034, 1.0)
	_laid += 1
	add_child(ol)
	outlines[id] = ol
	return ol
