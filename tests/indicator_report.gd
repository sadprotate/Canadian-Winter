extends Node
## Polish 4 §3 diagnosis: where the scoop cuts, where the indicators are drawn and where a throw
## lands, for bare hands and every shovel-type tool, at three pitches, in first and third person.
## Run: godot --headless --fixed-fps 60 --path . res://tests/indicator_report.tscn
## Distances are horizontal, from the player's feet, in metres. "cut" is the centre of the cells
## cut that frame (midpoint of the stroke segment where the build doesn't expose it), "xhair" the
## snow under the screen centre, "hands" the first-person blade / third-person right hand, "ind" the
## on-snow indicator while scooping (and its offset from the cut), "ring→land" the indicator just
## before a release vs where the thrown snow lands.

var world: Node

const TOOLS := ["", "small_shovel", "standard_shovel", "wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh"]


func _ready() -> void:
	OS.low_processor_usage_mode = false
	await get_tree().process_frame
	Game.force_input = true
	Game.new_game("fun", 2024)
	Clock.reset(Clock.at(1, 11.0))
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	for i in range(4):
		await get_tree().physics_frame
	Clock.running = false
	print("tool              view pitch |  cut  xhair hands |  ind (off) | ring→land")
	var spot := 0
	for t in TOOLS:
		for view in ["fp", "tp"]:
			for pitch in [-60.0, -45.0, -30.0]:
				await _one(t, view, pitch, spot)
				spot += 1
	print("REPORT DONE")
	get_tree().quit()


func _one(tool: String, view: String, pitch: float, spot: int) -> void:
	var pl: Player = world.player
	var tc: ToolController = pl.tools
	var lot := Layout.player_lot
	# A fresh patch of deep yard snow each time, facing along the lawn.
	var u := -10.0 + float(spot % 6) * 1.6
	@warning_ignore("integer_division")
	var v := 3.0 + float((spot / 6) % 3) * 2.2
	var p2 := Layout.lot_to_world(lot, Layout.gu(lot, u), v)
	Snow.set_rect(Rect2(p2 - Vector2(2.5, 2.5), Vector2(5, 5)), 0.6)
	pl.teleport(Vector3(p2.x, Snow.ground_at(p2.x, p2.y) + 0.05, p2.y))
	pl.set_third_person(view == "tp")
	Game.carried = ""
	Game.slots = [tool, "", "", ""]
	Game.select_slot(0)
	var into := Vector2(lot["inward"]).normalized()
	var side := Vector2(into.y, -into.x)
	pl.set_yaw(atan2(-side.x, -side.y))
	pl.pitch = deg_to_rad(pitch)
	pl.head.rotation.x = pl.pitch
	for i in range(4):
		await get_tree().physics_frame
	var base := pl.yaw
	Input.action_press("primary")
	var cut_d := []
	var x_d := []
	var h_d := []
	var ind_d := []
	var ind_off := []
	var prev := Vector2.INF
	for k in range(16):
		pl.set_yaw(base + 0.3 * sin(k * 0.25))
		await get_tree().physics_frame
		var feet := Vector2(pl.global_position.x, pl.global_position.z)
		var now: Vector2 = tc.get("_stroke_prev")
		if tc.last_fill > 0.0 and (prev.x < INF or tc.get("last_cut_center") != null):
			var c: Vector2 = tc.get("last_cut_center") if tc.get("last_cut_center") != null else (prev + now) * 0.5
			cut_d.append(c.distance_to(feet))
			var cam := pl.active_camera()
			var hit := Snow.raycast(cam.global_position, -cam.global_transform.basis.z, 8.0)
			if hit["hit"]:
				x_d.append(Vector2(hit["position"].x, hit["position"].z).distance_to(feet))
			if not (tool == "" and view == "fp"):
				var hn: Node3D = tc.blade_fp if view == "fp" else pl.model.hand_r
				h_d.append(Vector2(hn.global_position.x, hn.global_position.z).distance_to(feet))
			if tc.indicator.visible:
				var ip := Vector2(tc.indicator.global_position.x, tc.indicator.global_position.z)
				ind_d.append(ip.distance_to(feet))
				ind_off.append(ip.distance_to(c))
		prev = now
	if OS.get_cmdline_user_args().has("--debug"):
		print("  debug: load %.4f state %s filling %s engaged %s tool %s pos %s depth %.2f input %s" % [tc.load, pl.state, tc.filling, tc.engaged, tc.tool_id, str(pl.global_position), Snow.depth_at(pl.global_position.x, pl.global_position.z) if Snow.has_method("depth_at") else -1.0, str(Game.input_captured())])
	# Look up to throw, still holding: the indicator vs where the snow then lands.
	pl.pitch = deg_to_rad(5.0)
	pl.head.rotation.x = pl.pitch
	for i in range(20):
		await get_tree().physics_frame
	var ring := Vector3.INF
	if tc.indicator.visible:
		ring = tc.indicator.global_position
	var before := world.find_children("*", "ThrownSnow", true, false).size()
	Input.action_release("primary")
	await get_tree().physics_frame
	var land := Vector3.INF
	var thrown := world.find_children("*", "ThrownSnow", true, false)
	if thrown.size() > before:
		land = (thrown[thrown.size() - 1] as ThrownSnow).landing.get("pos", Vector3.INF)
	var rl := "   —   "
	if ring != Vector3.INF and land != Vector3.INF:
		rl = "%5.2f m" % Vector2(ring.x - land.x, ring.z - land.z).length()
	elif land != Vector3.INF:
		rl = " (none)"
	for i in range(30):
		await get_tree().physics_frame
	print("%-17s %-4s %5.0f | %5s %5s %5s | %5s (%s) | %s" % [tool if tool != "" else "hands", view, pitch, _avg(cut_d), _avg(x_d), _avg(h_d), _avg(ind_d), _avg(ind_off), rl])


static func _avg(a: Array) -> String:
	if a.is_empty():
		return "  —  "
	var s := 0.0
	for x in a:
		s += float(x)
	return "%5.2f" % (s / a.size())
