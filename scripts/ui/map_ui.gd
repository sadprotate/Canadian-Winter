class_name MapUI
extends Control
## Neighborhood map (Part 23): roads, houses, addresses, store, player's home, current position and
## active contract properties on a simple grid. No GPS routes, no waypoints. Polish 5 §5: every
## house and building number on its lot, the street names, no label over another (labels()).

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


## The map's scale and placement for a screen size.
func _fit(vs: Vector2) -> void:
	scale_px = minf((vs.y - 120.0) / Layout.MAP_D, (vs.x - 520.0) / Layout.MAP_W)
	origin = Vector2((vs.x - Layout.MAP_W * scale_px) * 0.5 - 150.0, 70.0)


# --- Polish 5 §5: the labels on the map ------------------------------------------------------
# Every name and number drawn on the map is laid out here first — the street names, every
# building's name and address, every house's number on its own lot (with HOME / vacant / a
# contract's hours under it), the parking lots — so none overlaps another (the test reads this).

const NUMBER_SIZE := 18       # house numbers (px at the 1920 × 1080 canvas)
const NAME_SIZE := 14
const STREET_SIZE := 15
const DARK := Color(0.1, 0.12, 0.2)
const HALO := Color(0.93, 0.95, 0.98)


func _font() -> Font:
	var f := get_theme_default_font()
	return f if f else ThemeDB.fallback_font


## One label: `text` in `size` px, centred on `center` (rotated a quarter turn, reading upwards, if
## `up`). `rect` is the box it covers on screen.
func _label(text: String, center: Vector2, size: int, color: Color, kind: String, key := "", up := false, halo := false) -> Dictionary:
	var font := _font()
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var box := Vector2(ts.y, ts.x) if up else ts
	return {"text": text, "center": center, "size": size, "color": color, "kind": kind, "key": key, "up": up, "halo": halo,
		"rect": Rect2(center - box * 0.5, box), "text_size": ts}


## The largest size up to `size` (down to 11) at which `text` fits in `width` px.
func _fit_size(text: String, size: int, width: float) -> int:
	var s := size
	while s > 11 and _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 1
	return s


## Every label for a screen of size `vs` (also sets the map's scale for that size).
func labels(vs: Vector2) -> Array:
	_fit(vs)
	var out := []
	var targets := _contract_targets()
	# Streets: along each one, on a stretch with no crossing.
	for r in Layout.roads:
		var rc: Rect2 = r["rect"]
		var nm: String = str(r["name"]).to_upper()
		if r["horizontal"]:
			var w := _font().get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, STREET_SIZE).x
			out.append(_label(nm, _to_px(Vector2(6, rc.get_center().y)) + Vector2(w * 0.5, 0), STREET_SIZE, Color.WHITE, "street", nm))
		else:
			out.append(_label(nm, _to_px(Vector2(rc.get_center().x, 118.0)), STREET_SIZE, Color.WHITE, "street", nm, true))
	# Buildings: the name (on two lines if it doesn't fit on one), and the address under it, on the
	# building.
	for b in Layout.buildings:
		var br := _rect_px(b["rect"])
		var w := br.size.x - 6.0
		var lines := []
		var nm2: String = b["name"]
		var ns := _fit_size(nm2, NAME_SIZE, w)
		if _font().get_string_size(nm2, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x > w and nm2.contains(" "):
			var cut := nm2.rfind(" ")
			for part in [nm2.substr(0, cut), nm2.substr(cut + 1)]:
				lines.append(_label(part, Vector2.ZERO, _fit_size(part, NAME_SIZE, w), Color.WHITE, "building", str(b["id"])))
		else:
			lines.append(_label(nm2, Vector2.ZERO, ns, Color.WHITE, "building", str(b["id"])))
		var ad: String = b["address"]
		lines.append(_label(ad, Vector2.ZERO, _fit_size(ad, NAME_SIZE + 1, w), Color(1.0, 0.86, 0.55), "building_address", str(b["id"])))
		var total := -1.0
		for ln in lines:
			total += (ln["rect"] as Rect2).size.y + 1.0
		var y := br.get_center().y - total * 0.5
		for ln in lines:
			var hgt := (ln["rect"] as Rect2).size.y
			_move(ln, Vector2(br.get_center().x, y + hgt * 0.5))
			y += hgt + 1.0
			out.append(ln)
	# Parking lots (named after their building).
	for a in Layout.big_areas:
		if a["id"] == "dump_lot":
			continue
		out.append(_label(str(a["name"]).replace(" parking lot", ""), _rect_px(a["rect"]).get_center(), NAME_SIZE, Color(0.2, 0.22, 0.3), "area", str(a["id"])))
	# Houses: the number on the front lawn, on the side away from the driveway; under it HOME,
	# vacant or a contract's hours left.
	for lot in Layout.lots:
		var u := Layout.gu(lot, -7.5) if not lot["vacant"] else 0.0
		var is_c := targets.has("lot:%d" % lot["index"])
		var num := _label(str(lot["number"]), Vector2.ZERO, NUMBER_SIZE, Color(0.8, 0.3, 0.0) if is_c else DARK, "number", str(lot["index"]), false, true)
		# Its top edge just inside the lot's street edge (v = 0.4 m), whichever way the lot faces.
		var v := 0.4 + (num["rect"] as Rect2).size.y * 0.5 / scale_px
		_move(num, _to_px(Layout.lot_to_world(lot, u, v)))
		out.append(num)
		var tag := ""
		var tag_col := DARK
		if lot["is_player"]:
			tag = "HOME"
			tag_col = Color(0.15, 0.4, 0.85)
		elif lot["vacant"]:
			tag = "vacant"
			tag_col = Color(0.35, 0.38, 0.48)
		if is_c:
			var left: float = Contracts.hours_left(targets["lot:%d" % lot["index"]])
			if left < INF:
				tag = "%dh" % int(ceil(maxf(left, 0.0)))
				tag_col = Color(0.85, 0.1, 0.05) if left <= 12.0 else Color(0.7, 0.35, 0.0)
		if tag != "":
			# Under the number, towards the house.
			var tl := _label(tag, Vector2.ZERO, 12, tag_col, "tag", str(lot["index"]), false, true)
			var vt := v + ((num["rect"] as Rect2).size.y * 0.5 + 1.0 + (tl["rect"] as Rect2).size.y * 0.5) / scale_px
			_move(tl, _to_px(Layout.lot_to_world(lot, u, vt)))
			out.append(tl)
	return out


func _move(l: Dictionary, center: Vector2) -> void:
	var r: Rect2 = l["rect"]
	l["center"] = center
	l["rect"] = Rect2(center - r.size * 0.5, r.size)


func _draw_label(l: Dictionary) -> void:
	var font := _font()
	var ts: Vector2 = l["text_size"]
	var sz: int = l["size"]
	var base := Vector2(-ts.x * 0.5, -ts.y * 0.5 + font.get_ascent(sz))
	if l["up"]:
		draw_set_transform(l["center"], -PI * 0.5, Vector2.ONE)
	else:
		draw_set_transform(l["center"], 0.0, Vector2.ONE)
	if l["halo"]:
		draw_string_outline(font, base, l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, HALO)
	draw_string(font, base, l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, l["color"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Live contracts by target ("lot:9", "area:store_lot", …).
func _contract_targets() -> Dictionary:
	var out := {}
	for c in Contracts.active:
		if c["status"] != "completed" and c["status"] != "expired" and c["status"] != "lost":
			out[str(c["target"])] = c
	return out


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	var lbls := labels(vs)
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
	draw_rect(_rect_px(Layout.dump_rect), Color(0.6, 0.66, 0.8))
	for s in Layout.sidewalks:
		draw_rect(_rect_px(s), Color(0.8, 0.82, 0.86))
	for r in Layout.roads:
		draw_rect(_rect_px(r["rect"]), Color(0.32, 0.34, 0.38))
	for b in Layout.buildings:
		draw_rect(_rect_px(b["rect"]), Color(0.45, 0.4, 0.42))
	var contract_targets := _contract_targets()
	for t in contract_targets.keys():
		for id in Contracts.contract_boxes(contract_targets[t]):
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
	# Store pad
	draw_rect(_rect_px(Layout.store_pad), Color(1.0, 0.85, 0.2))
	# Every name and number (polish 5 §5), on top of the map.
	for l in lbls:
		_draw_label(l)
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
		[Color(0.6, 0.66, 0.8), "Municipal snow dump"], [Color(0.32, 0.34, 0.38), "Streets"]]
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
