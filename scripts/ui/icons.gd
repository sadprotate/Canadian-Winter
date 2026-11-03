class_name Icons
extends Control
## Procedurally drawn icons (weather conditions and tools). No image assets needed.

var kind := "weather"
var code := 0           # weather condition
var tool_id := ""
var night := false
var tint := Color.WHITE


static func weather(cond: int, size := 64.0) -> Icons:
	var i := Icons.new()
	i.kind = "weather"
	i.code = cond
	i.custom_minimum_size = Vector2(size, size)
	return i


static func tool(id: String, size := 64.0) -> Icons:
	var i := Icons.new()
	i.kind = "tool"
	i.tool_id = id
	i.custom_minimum_size = Vector2(size, size)
	return i


func set_weather(cond: int, is_night: bool) -> void:
	if cond != code or is_night != night:
		code = cond
		night = is_night
		queue_redraw()


func set_tool(id: String) -> void:
	if id != tool_id:
		tool_id = id
		queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	if kind == "weather":
		_draw_weather(c, s)
	else:
		_draw_tool(c, s)


func _cloud(c: Vector2, s: float, col: Color) -> void:
	draw_circle(c + Vector2(-0.18, 0.05) * s, 0.16 * s, col)
	draw_circle(c + Vector2(0.0, -0.06) * s, 0.21 * s, col)
	draw_circle(c + Vector2(0.2, 0.06) * s, 0.15 * s, col)
	draw_rect(Rect2(c + Vector2(-0.32, 0.05) * s, Vector2(0.64, 0.15) * s), col)


func _flake(p: Vector2, r: float, col: Color) -> void:
	for k in range(3):
		var a := PI / 3.0 * k
		var d := Vector2(cos(a), sin(a)) * r
		draw_line(p - d, p + d, col, maxf(1.5, r * 0.25), true)


func _draw_weather(c: Vector2, s: float) -> void:
	var sun := Color(1.0, 0.82, 0.35)
	var moon := Color(0.85, 0.88, 1.0)
	var cloud := Color(0.9, 0.92, 0.97)
	var dark := Color(0.62, 0.66, 0.76)
	match code:
		0:
			if night:
				draw_circle(c, 0.24 * s, moon)
				draw_circle(c + Vector2(0.11, -0.08) * s, 0.21 * s, Color(0.07, 0.09, 0.15))
			else:
				draw_circle(c, 0.2 * s, sun)
				for k in range(8):
					var a := TAU * k / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * 0.28 * s, c + Vector2(cos(a), sin(a)) * 0.4 * s, sun, maxf(2.0, s * 0.05), true)
		1:
			draw_circle(c + Vector2(-0.15, -0.15) * s, 0.15 * s, moon if night else sun)
			_cloud(c + Vector2(0.04, 0.06) * s, s, cloud)
		2, 3, 4:
			_cloud(c + Vector2(0, -0.12) * s, s, cloud if code == 2 else dark)
			var n: int = [2, 3, 5][code - 2]
			for k in range(n):
				var p := c + Vector2(-0.25 + 0.5 * k / maxf(n - 1, 1), 0.28 + 0.06 * (k % 2)) * s
				_flake(p, 0.07 * s, Color.WHITE)
		5:
			_cloud(c + Vector2(0, -0.16) * s, s, Color(0.5, 0.53, 0.62))
			for k in range(5):
				var p0 := c + Vector2(-0.3 + 0.15 * k, 0.12) * s
				draw_line(p0, p0 + Vector2(-0.12, 0.28) * s, Color.WHITE, maxf(2.0, s * 0.04), true)
			_flake(c + Vector2(0.25, 0.32) * s, 0.06 * s, Color.WHITE)


func _draw_tool(c: Vector2, s: float) -> void:
	if tool_id == "":
		# Bare hands: a mitten.
		var g := Color(0.75, 0.77, 0.82, 0.55)
		draw_circle(c + Vector2(0, 0.05) * s, 0.18 * s, g)
		draw_circle(c + Vector2(-0.2, -0.05) * s, 0.08 * s, g)
		draw_rect(Rect2(c + Vector2(-0.14, 0.12) * s, Vector2(0.28, 0.16) * s), g)
		return
	if tool_id.begins_with("crate:"):
		draw_rect(Rect2(c - Vector2(0.25, 0.22) * s, Vector2(0.5, 0.44) * s), Color(0.7, 0.55, 0.35))
		return
	var t: ToolData = Catalog.tool(StringName(tool_id))
	var col := t.primary_color
	var metal := Color(0.75, 0.77, 0.8)
	match t.kind:
		ToolData.Kind.SHOVEL:
			draw_line(c + Vector2(-0.3, -0.35) * s, c + Vector2(0.08, 0.1) * s, metal, maxf(2.5, s * 0.05), true)
			draw_line(c + Vector2(-0.38, -0.38) * s, c + Vector2(-0.24, -0.32) * s, Color(0.15, 0.15, 0.15), maxf(4.0, s * 0.08), true)
			var w := 0.16 + t.width * 0.25
			var pts := PackedVector2Array([c + Vector2(0.02, 0.05) * s, c + Vector2(0.02 + w, 0.05 - w * 0.4) * s, c + Vector2(0.3 + w * 0.6, 0.38) * s, c + Vector2(0.12, 0.42) * s])
			draw_colored_polygon(pts, col)
		ToolData.Kind.PUSHER, ToolData.Kind.SCRAPER:
			draw_line(c + Vector2(0, -0.38) * s, c + Vector2(0, 0.18) * s, metal, maxf(2.5, s * 0.05), true)
			var hw := clampf(t.width * 0.3, 0.2, 0.42)
			draw_rect(Rect2(c + Vector2(-hw, 0.16) * s, Vector2(hw * 2.0, 0.16) * s), col)
			if t.kind == ToolData.Kind.SCRAPER:
				draw_rect(Rect2(c + Vector2(-hw, 0.3) * s, Vector2(hw * 2.0, 0.04) * s), metal)
		ToolData.Kind.SLEIGH:
			draw_line(c + Vector2(-0.2, -0.35) * s, c + Vector2(-0.2, 0.05) * s, metal, 3.0, true)
			draw_line(c + Vector2(0.2, -0.35) * s, c + Vector2(0.2, 0.05) * s, metal, 3.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.35, 0.0) * s, c + Vector2(0.35, 0.0) * s, c + Vector2(0.3, 0.35) * s, c + Vector2(-0.3, 0.35) * s]), col)
		ToolData.Kind.ELECTRIC_SHOVEL:
			draw_line(c + Vector2(-0.25, -0.38) * s, c + Vector2(0.05, 0.05) * s, metal, 3.0, true)
			draw_rect(Rect2(c + Vector2(-0.05, 0.0) * s, Vector2(0.38, 0.3) * s), col)
			draw_circle(c + Vector2(0.14, 0.3) * s, 0.08 * s, Color(0.9, 0.9, 0.9))
		ToolData.Kind.WALK_BLOWER:
			draw_rect(Rect2(c + Vector2(-0.3, 0.0) * s, Vector2(0.6, 0.3) * s), col)
			draw_rect(Rect2(c + Vector2(0.08, -0.32) * s, Vector2(0.1, 0.34) * s), col.darkened(0.2))
			draw_circle(c + Vector2(-0.22, 0.34) * s, 0.08 * s, Color(0.1, 0.1, 0.1))
			draw_circle(c + Vector2(0.22, 0.34) * s, 0.08 * s, Color(0.1, 0.1, 0.1))
