extends Node
## Winter depth curves (polish §8 report). Simulates whole winters with time skips (snowfall and
## the city grader's passes, no player) and prints, per half month: the undisturbed yard depth,
## the cleared-then-left driveway, the street bank height, plus the events in each storm tier.
## Polish 5 §11: also the mean snow depth on Birch Avenue's sidewalks and on its boulevards (the
## strips between the sidewalks and the street), where the city's sidewalk crew moves its snow.
##   godot --headless --path . res://tests/depth_report.tscn [-- --years=1,5 --seed=2024]

var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	await get_tree().process_frame
	var years := str(args.get("years", "1,5")).split(",")
	var sd := int(args.get("seed", "2024"))
	for ys in years:
		_winter(int(ys), sd)
	get_tree().quit()


func _winter(year: int, sd: int) -> void:
	Game.world = null
	Game.player = null
	Clock.running = false
	Municipal.world_handles_passes = false
	Game.new_game("fun", sd)
	if year > 1:
		Game.start_winter(year)
	Survival.in_player_house = true
	var lot: Dictionary = Layout.lots[16]
	var yard := Layout.lot_to_world(lot, -9.0, 22.0)      # back yard: undisturbed
	var t := Weather.tier_counts()
	print("")
	print("=== Winter %d (seed %d): %d events — light %d, storms %d, major %d; %.0f cm total; starts at %.2f m ===" % [
		year, sd, Weather.events.size(), t["light"], t["storm"], t["major"], Weather.total_snow_cm, Snow.depth_at(yard.x, yard.y)])
	for ev in Weather.events:
		if Weather.tier_of(ev) != "light":
			print("   %-6s %s  %5.1f cm in %4.1f h%s" % [Weather.tier_of(ev), Clock.format_time(float(ev["start"]) * 60.0), float(ev["total"]),
				float(ev["end"]) - float(ev["start"]), "  (unforecast)" if ev["surprise"] else ""])
	print("   date      yard   street bank (max, along Birch Ave)   sidewalk (mean)   boulevard (mean)")
	var marks := [0, 14, 31, 45, 62, 76, 90, 104, 120]
	var day := 0
	for m in marks:
		if m > day:
			Clock.skip(Clock.at(m, 12.0) - Clock.minutes)
			Snow.relax_until_stable()
			day = m
		Snow.sync_all()
		print("   %-8s  %4.2f m   %4.2f m   %4.2f m   %4.2f m" % [Clock.date_string(m, true), Snow.depth_at(yard.x, yard.y), _bank_height(),
			_mean_depth([Rect2(4, 146.0, 84, 1.5), Rect2(4, 158.5, 84, 1.5)]), _mean_depth([Rect2(4, 147.5, 84, 1.5), Rect2(4, 157.0, 84, 1.5)])])


## Highest snow surface on the boulevard/sidewalk strips along Birch Avenue (x 4..88).
func _bank_height() -> float:
	var top := 0.0
	for strip: Rect2 in [Rect2(4, 146.0, 84, 3.0), Rect2(4, 157.0, 84, 3.0)]:
		var z: float = strip.position.y
		while z < strip.end.y:
			var x: float = strip.position.x
			while x < strip.end.x:
				top = maxf(top, Snow.ground_at(x, z) + Snow.depth_at(x, z))
				x += 0.5
			z += 0.25
	return top


## Polish 5 §11: the mean snow depth over some strips (m).
func _mean_depth(rects: Array) -> float:
	var v := 0.0
	var a := 0.0
	for r: Rect2 in rects:
		v += Snow.volume_in_rect(r)
		a += r.get_area()
	return v / maxf(a, 0.01)
