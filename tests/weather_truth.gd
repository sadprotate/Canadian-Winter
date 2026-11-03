extends Node
## Polish 4 §1: dump the weather that actually falls — every event's start, end, condition, tier
## and total, the first and last snowy hour, its peak hourly rate, and each winter's total — for
## seed 2024 and 20 other seeds, winters 1–5. The pass-3 dump is kept in
## tests/fixtures/polish4/weather_truth_baseline.json and test_polish4 compares against it.
## Run: godot --headless --path . res://tests/weather_truth.tscn -- --out=<file.json>

const SEEDS := [2024, 1, 7, 13, 42, 99, 123, 256, 404, 512, 777, 1000, 1234, 2025, 3141, 4096, 5000, 6789, 8080, 9001, 31337]


static func dump() -> Dictionary:
	var out := {}
	for s in SEEDS:
		for y in range(1, 6):
			Weather.generate(y, int(s) + y * 13)
			var evs := []
			for ev in Weather.events:
				var st: float = ev["start"]
				var en: float = ev["end"]
				var first := -1
				var last := -1
				var peak := 0.0
				var heavy := -1
				for h in range(int(st), mini(int(ceil(en)), Weather.HOURS)):
					if Weather.rate[h] > 0.0:
						if first < 0:
							first = h
						last = h
						peak = maxf(peak, Weather.rate[h])
					if heavy < 0 and Weather.cond[h] >= Weather.C.HEAVY:
						heavy = h
				# [start, end, cond, tier, total, first snowy hour, last snowy hour | peak hourly rate,
				# first hour at heavy or worse] — the last two are informational (the onset shape).
				evs.append([snappedf(st, 0.0001), snappedf(en, 0.0001), int(ev["cond"]), Weather.tier_of(ev),
					snappedf(float(ev["total"]), 0.0001), first, last, snappedf(peak, 0.001), heavy])
			out["%d/%d" % [s, y]] = {"total": snappedf(Weather.total_snow_cm, 0.001), "events": evs}
	return out


## Every alert the winter puts out, hour by hour, for a few seeds and winters: [hour, text].
static func alerts_dump() -> Dictionary:
	var out := {}
	var said := []
	var grab := func(t: String): said.append([int(round(Clock.minutes / 60.0)), t])
	Weather.alert_issued.connect(grab)
	var keep := Clock.minutes
	for s in [2024, 1, 7, 42]:
		for y in range(1, 4):
			Weather.generate(y, int(s) + y * 13)
			said.clear()
			for h in range(Weather.HOURS):
				Clock.minutes = h * 60.0
				Weather.on_hour(h / 24, h % 24)
			out["%d/%d" % [s, y]] = said.duplicate()
	Weather.alert_issued.disconnect(grab)
	Clock.minutes = keep
	return out


func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			path = a.substr(6)
	var d := dump()
	d["alerts"] = alerts_dump()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "", false))
	f.close()
	print("wrote %s (%d winters)" % [path, d.size()])
	get_tree().quit()
