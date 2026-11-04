class_name MapUI
extends Control
## Neighborhood map (Part 23): roads, houses, addresses, store, player's home, current position and
## active contract properties on a simple grid. No GPS routes, no waypoints.

signal closed

var scale_px := 4.2
var origin := Vector2.ZERO


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()


func _process(_d: float) -> void:
	queue_redraw()


func _to_px(p: Vector2) -> Vector2:
	return origin + p * scale_px


func _rect_px(r: Rect2) -> Rect2:
	return Rect2(_to_px(r.position), r.size * scale_px)


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	scale_px = minf((vs.y - 120.0) / Layout.MAP_D, (vs.x - 520.0) / Layout.MAP_W)
	origin = Vector2((vs.x - Layout.MAP_W * scale_px) * 0.5 - 150.0, 70.0)
	var font := get_theme_default_font()
	var map_r := Rect2(origin, Vector2(Layout.MAP_W, Layout.MAP_D) * scale_px)
	draw_rect(map_r.grow(10), Color(0.93, 0.95, 0.98))
	draw_rect(map_r, Color(0.88, 0.91, 0.96))
	# Grid (16 m) with coordinates
	var cols := "ABCDEFGHIJKL"
	for i in range(13):
		var x := origin.x + i * 16.0 * scale_px
		draw_line(Vector2(x, map_r.position.y), Vector2(x, map_r.end.y), Color(0.6, 0.65, 0.75, 0.35), 1.0)
		if i < 12:
			draw_string(font, Vector2(x + 16.0 * scale_px * 0.5 - 5, map_r.position.y - 16), cols[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.92, 1.0))
	for j in range(15):
		var y := origin.y + j * 16.0 * scale_px
		draw_line(Vector2(map_r.position.x, y), Vector2(map_r.end.x, y), Color(0.6, 0.65, 0.75, 0.35), 1.0)
		if j < 14:
			draw_string(font, Vector2(map_r.position.x - 34, y + 16.0 * scale_px * 0.5 + 6), str(j + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.92, 1.0))
	for a in Layout.big_areas:
		draw_rect(_rect_px(a["rect"]), Color(0.7, 0.72, 0.78))
		draw_rect(_rect_px(a["apron"]), Color(0.7, 0.72, 0.78))
		draw_string(font, _to_px((a["rect"] as Rect2).get_center()) + Vector2(-60, 5), a["name"].replace(" parking lot", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.2, 0.22, 0.3))
	draw_rect(_rect_px(Layout.dump_rect), Color(0.6, 0.66, 0.8))
	for s in Layout.sidewalks:
		draw_rect(_rect_px(s), Color(0.8, 0.82, 0.86))
	for r in Layout.roads:
		draw_rect(_rect_px(r["rect"]), Color(0.32, 0.34, 0.38))
		var rc: Rect2 = r["rect"]
		if r["horizontal"]:
			draw_string(font, _to_px(Vector2(6, rc.get_center().y)) + Vector2(0, 6), r["name"].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		else:
			draw_string(font, _to_px(Vector2(rc.position.x, 6)) + Vector2(2, 12), "CEDAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	for b in Layout.buildings:
		draw_rect(_rect_px(b["rect"]), Color(0.45, 0.4, 0.42))
		draw_string(font, _to_px((b["rect"] as Rect2).get_center()) + Vector2(-60, 5), b["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	var contract_targets := {}
	for c in Contracts.active:
		if c["status"] != "completed" and c["status"] != "expired" and c["status"] != "lost":
			contract_targets[str(c["target"])] = c
			for id in Contracts.contract_boxes(c):
				var bx := Boxes.get_box(id)
				for rr in bx.get("rects", []):
					draw_rect(_rect_px(rr), Color(0.35, 0.85, 0.45, 0.6) if bx["complete"] else Color(1.0, 0.55, 0.15, 0.7))
	# Your own property's boxes: green when clear, white-ish when snowed in.
	for bx2 in Boxes.for_owner("lot:%d" % Layout.player_lot["index"]):
		for rr2 in bx2["rects"]:
			draw_rect(_rect_px(rr2), Color(0.35, 0.85, 0.45, 0.45) if bx2["complete"] else Color(0.9, 0.93, 1.0, 0.35))
	for lot in Layout.lots:
		var lr: Rect2 = lot["rect"]
		var is_c := contract_targets.has("lot:%d" % lot["index"])
		draw_rect(_rect_px(lr), Color(1.0, 0.6, 0.2) if is_c else Color(0.55, 0.6, 0.7, 0.6), false, 2.0 if is_c else 1.0)
		if not lot["vacant"]:
			var hi := Layout.house_info(lot)
			var col := Color(0.25, 0.5, 0.9) if lot["is_player"] else Color(0.5, 0.52, 0.58)
			draw_rect(_rect_px(hi["body"]), col)
			draw_rect(_rect_px(hi["garage"]), col.darkened(0.15))
			draw_rect(_rect_px(hi["driveway"]), Color(0.62, 0.64, 0.68))
		var label: String = str(lot["number"])
		if lot["is_player"]:
			label += " (HOME)"
		if lot["vacant"]:
			label += " vacant"
		var lp := _to_px(Vector2(lot["center_x"], lot["front_z"] + 2.5 * lot["dir"])) + Vector2(-14, 6)
		draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.12, 0.2) if not is_c else Color(0.8, 0.3, 0.0))
		if is_c:
			var left: float = Contracts.hours_left(contract_targets["lot:%d" % lot["index"]])
			if left < INF:
				draw_string(font, lp + Vector2(0, 16 * lot["dir"] + 4), "%dh" % int(ceil(maxf(left, 0.0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.1, 0.05) if left <= 12.0 else Color(0.7, 0.35, 0.0))
	# Store pad
	draw_rect(_rect_px(Layout.store_pad), Color(1.0, 0.85, 0.2))
	# Player
	var pp := Vector2(Game.player_pos.x, Game.player_pos.z)
	var pp_px := _to_px(pp)
	var yaw := Game.player_yaw
	var f := Vector2(-sin(yaw), -cos(yaw))
	var r := Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([pp_px + f * 14, pp_px - f * 8 + r * 8, pp_px - f * 8 - r * 8]), Color(0.9, 0.15, 0.1))
	draw_arc(pp_px, 16, 0, TAU, 24, Color(0.9, 0.15, 0.1), 2.0)
	# Legend
	var lx := map_r.end.x + 40
	var ly := map_r.position.y + 90.0   # below the HUD weather panel
	draw_string(font, Vector2(lx, ly + 10), "NEIGHBOURHOOD MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	var entries := [[Color(0.9, 0.15, 0.1), "You are here: " + Layout.describe_point(pp)], [Color(0.25, 0.5, 0.9), "Your home: " + Layout.player_lot["address"]],
		[Color(1.0, 0.6, 0.2), "Contract areas to clear (green = clear)"], [Color(1.0, 0.85, 0.2), "Store order pickup pad"],
		[Color(0.6, 0.66, 0.8), "Municipal snow dump"], [Color(0.32, 0.34, 0.38), "Streets (no snow allowed!)"]]
	for i in range(entries.size()):
		var y := ly + 60 + i * 34
		draw_rect(Rect2(Vector2(lx, y - 14), Vector2(18, 18)), entries[i][0])
		draw_string(font, Vector2(lx + 28, y), entries[i][1], HORIZONTAL_ALIGNMENT_LEFT, 420, 18, Color.WHITE)
	var gy := ly + 60 + entries.size() * 34 + 20
	draw_string(font, Vector2(lx, gy), "Grid: %s%d" % [cols[clampi(int(pp.x / 16.0), 0, 11)], clampi(int(pp.y / 16.0) + 1, 1, 14)], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.ACCENT)
	var list_y := gy + 40
	draw_string(font, Vector2(lx, list_y), "Contracts:", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.ACCENT)
	var k := 0
	for t in contract_targets.keys():
		var c2: Dictionary = contract_targets[t]
		var lh: float = Contracts.hours_left(c2)
		var st2: String = {"active": "to do", "needs_service": "needs clearing", "serviced": "clear"}.get(c2["status"], c2["status"])
		if lh < INF:
			st2 += " — %d h left" % int(ceil(maxf(lh, 0.0)))
		draw_string(font, Vector2(lx, list_y + 30 + k * 26), "• %s (%s)" % [c2["address"], st2], HORIZONTAL_ALIGNMENT_LEFT, 440, 17, Color(1.0, 0.6, 0.5) if lh <= 12.0 else Color.WHITE)
		k += 1
	draw_string(font, Vector2(lx, vs.y - 40), "%s or %s to close" % [Settings.action_label("map"), Settings.action_label("pause")], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.MUTED)
