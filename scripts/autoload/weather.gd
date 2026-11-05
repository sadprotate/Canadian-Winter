extends Node
## Dynamic winter weather. A full hourly schedule is generated per winter (deterministic per
## year/seed). Forecasts are noisy views of that schedule; some storms are "surprises" that
## arrive stronger than forecast and trigger severe-weather alerts. Snowfall feeds the snow sim.

signal condition_changed(cond: int)
signal alert_issued(text: String)

enum C { CLEAR, CLOUDY, LIGHT, MODERATE, HEAVY, BLIZZARD }
const NAMES := ["Clear", "Cloudy", "Light snow", "Moderate snow", "Heavy snow", "Blizzard"]
const HOURS := 121 * 24

var year := 1
var seed_value := 1
var cond := PackedByteArray()
var rate := PackedFloat32Array()     # cm/h
var temp := PackedFloat32Array()     # °C
var wind := PackedFloat32Array()     # km/h
var events: Array = []               # {start, end, cond, total, surprise, fc_cond, fc_shift, alerted}
var override_cond := -1              # debug override
var override_rate := -1.0
var override_until := -1.0
var difficulty := 0.0
var alerts: Array = []               # recent alerts [{time, text}]
var total_snow_cm := 0.0
var _last_cond := -1
## Polish 4 §1: what the forecast model reads besides the schedule. All derived from the seed
## (never saved): the background temperature / wind before events change them, which days are
## cloudy, and the forecast's fixed errors (per event and per 6-hour knot, from their own stream).
var base_temp := PackedFloat32Array()
var base_wind := PackedFloat32Array()
var cloudy_day := PackedByteArray()
var _ev_amt_err := PackedFloat32Array()
var _temp_knots := PackedFloat32Array()


func generate(y: int, s: int) -> void:
	year = y
	seed_value = s
	var b: BalanceData = Catalog.balance
	difficulty = minf(b.difficulty_cap, b.difficulty_growth_per_year * (y - 1))
	cond.resize(HOURS)
	rate.resize(HOURS)
	temp.resize(HOURS)
	wind.resize(HOURS)
	cond.fill(C.CLEAR)
	rate.fill(0.0)
	var target := int(round(lerpf(b.snow_events_year1, b.snow_events_max, _severity())))
	var gap_scale := 1.0
	for attempt in range(40):
		_gen_events(gap_scale)
		var n := events.size()
		if absi(n - target) <= 1:
			break
		gap_scale *= 1.0 + 0.6 * float(n - target) / target
		gap_scale = clampf(gap_scale, 0.2, 5.0)
	_gen_temperature()
	_fill_hours()
	_gen_forecast_noise()
	alerts.clear()
	override_cond = -1
	_last_cond = -1


## 0 for the first winter, 1 for the hardest (difficulty at its cap).
func _severity() -> float:
	var b: BalanceData = Catalog.balance
	return clampf(difficulty / maxf(b.difficulty_cap, 0.001), 0.0, 1.0)


## Storm tiers (polish §8): light snowfalls of 1–2 in, storms of 6 in – 1 ft, and rare major
## events (blizzards and unforecast surprise storms) that drop 3–4 ft in a few hours. The share of
## storms and major events grows with the winter's difficulty.
func tier_of(ev: Dictionary) -> String:
	return str(ev.get("tier", "light"))


func _gen_events(gap_scale: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + year * 104729
	var b: BalanceData = Catalog.balance
	var bag := _tier_bag()
	events.clear()
	var t := 34.0   # first event on Dec 2 (Dec 1 is the clear morning after the opening storm)
	var count := 0
	while t < HOURS - 8:
		var tier: String = bag[count] if count < bag.size() else "light"
		var c := C.LIGHT
		var total := 0.0
		var dur := 0.0
		var surprise := false
		var fc_cond := C.LIGHT
		match tier:
			"light":
				total = rng.randf_range(b.light_cm_min, b.light_cm_max)
				dur = rng.randf_range(3.0, 9.0)
				c = C.MODERATE if total >= 4.0 else C.LIGHT
				surprise = false
				fc_cond = c
			"storm":
				total = rng.randf_range(b.storm_cm_min, b.storm_cm_max)
				dur = rng.randf_range(8.0, 18.0)
				c = C.HEAVY
				surprise = rng.randf() < 0.25
				fc_cond = C.MODERATE if surprise else C.HEAVY
			"major":
				total = rng.randf_range(b.major_cm_min, b.major_cm_max)
				dur = rng.randf_range(3.0, 6.0)
				c = C.BLIZZARD
				# Half are forecast blizzards (with warnings), half arrive unforecast.
				surprise = rng.randf() < 0.5
				fc_cond = C.LIGHT if surprise else C.BLIZZARD
		var ev := {"start": t, "end": minf(t + dur, HOURS - 1), "cond": c, "tier": tier, "rate": total / dur,
			"total": total, "surprise": surprise, "fc_cond": fc_cond,
			"fc_shift": rng.randf_range(-4.0, 4.0), "alerted": false, "warned": false}
		events.append(ev)
		count += 1
		t += dur
		var g := rng.randf()
		var gap := 0.0
		if g < 0.12:
			gap = rng.randf_range(0.5, 3.0)       # multi-day storm: next system right behind
		elif g < 0.6:
			gap = rng.randf_range(20, 60) * gap_scale
		elif g < 0.84:
			gap = rng.randf_range(60, 100) * gap_scale
		else:
			gap = rng.randf_range(80, 120) * maxf(gap_scale, 0.8)  # 3-4 good days in a row
		t += gap


## The winter's mix of events, in order: how many storms and major events this winter gets grows
## with difficulty (a major event is rare in the first winter), then they are shuffled among the
## light snowfalls. The opening days of the first winter are always light.
func _tier_bag() -> Array:
	var b: BalanceData = Catalog.balance
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 3571 + year * 271
	var sev := _severity()
	var n := int(round(lerpf(b.snow_events_year1, b.snow_events_max, sev))) + 6
	var majors := int(floor(lerpf(b.majors_year1, b.majors_max, sev) + rng.randf()))
	var storms := maxi(1, int(round(lerpf(b.storms_year1, b.storms_max, sev) + rng.randf_range(-1.0, 1.0))))
	var lead := 2 if year <= 1 else 1
	var bag := []
	for i in range(n - lead):
		bag.append("major" if i < majors else ("storm" if i < majors + storms else "light"))
	# Fisher–Yates with the winter's own RNG, keeping the big ones inside the season.
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	var core := n - 6 - lead
	for i in range(core, bag.size()):
		if bag[i] != "light":
			for j in range(core):
				if bag[j] == "light":
					bag[j] = bag[i]
					bag[i] = "light"
					break
	var out := []
	for i in range(lead):
		out.append("light")
	out.append_array(bag)
	return out


func tier_counts() -> Dictionary:
	var out := {"light": 0, "storm": 0, "major": 0}
	for ev in events:
		out[tier_of(ev)] += 1
	return out


func _gen_temperature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + year * 977
	var phases := []
	for k in range(4):
		phases.append([rng.randf() * TAU, rng.randf_range(2.0, 9.0)])
	var snaps := []
	var n_snaps := rng.randi_range(3, 5)
	for k in range(n_snaps):
		var day := rng.randf_range(12, 105)
		snaps.append([day * 24.0, rng.randf_range(48, 96), rng.randf_range(10, 16)])
	for h in range(HOURS):
		var day := h / 24.0
		var seasonal := -2.5 - 9.5 * sin(PI * clampf(day / 112.0, 0.0, 1.0))
		var hod := fmod(h, 24.0)
		var diurnal := -3.0 * cos((hod - 3.0) / 24.0 * TAU)
		var syn := 0.0
		for p in phases:
			syn += sin(day / p[1] * TAU + p[0]) * 1.6
		var snap := 0.0
		var snap_wind := 0.0
		for s in snaps:
			var x: float = (h - s[0]) / s[1]
			if x > 0.0 and x < 1.0:
				snap -= s[2] * sin(x * PI)
				snap_wind = 18.0 * sin(x * PI)
		temp[h] = clampf(seasonal + diurnal + syn + snap, -32.0, 3.0)
		wind[h] = 6.0 + 8.0 * (0.5 + 0.5 * sin(day * 1.7 + phases[0][0])) + snap_wind


func _fill_hours() -> void:
	total_snow_cm = 0.0
	base_temp = temp.duplicate()
	base_wind = wind.duplicate()
	var onset_rate: float = Catalog.balance.storm_onset_cm_h
	for ev in events:
		var st: float = ev["start"]
		var en: float = ev["end"]
		var s := int(st)
		var e := int(ceil(en))
		var c: int = ev["cond"]
		var span_h := maxf(en - st, 0.5)
		for h in range(maxi(s - 5, 0), mini(e + 4, HOURS)):
			if cond[h] < C.CLOUDY:
				cond[h] = C.CLOUDY
		# Polish 4 §1: a storm or major event opens with light-to-moderate snow — the partial hour
		# it starts in and the next full hour, at up to storm_onset_cm_h — before it builds to its
		# peak, so the first hour alone doesn't tell a light snowfall from the start of something
		# bigger. The rest of its total falls over the remaining hours (same bell shape,
		# renormalised): totals, start and end hours are unchanged. Light snowfalls are unchanged.
		var lead_end := st
		if tier_of(ev) != "light":
			lead_end = maxf(st, minf(ceil(st + 1.0 - 0.001), en - 1.0))
		# The bell-shaped hourly weights over the whole event (the shape it always had); the hours
		# after the lead-in keep their share of it, renormalised so the event drops exactly its total.
		var weights := {}
		var wsum := 0.0
		for h in range(int(lead_end), mini(e, HOURS)):
			var a := maxf(float(h), lead_end)
			var bnd := minf(float(h + 1), en)
			var frac := maxf(bnd - a, 0.0)
			var x := ((a + bnd) * 0.5 - st) / span_h
			var w := clampf(sin(x * PI) * 1.35, 0.25, 1.15) * frac
			if w > 0.0:
				weights[h] = w
				wsum += w
		# Light-to-moderate: at most storm_onset_cm_h, at most a fraction of the event's mean rate,
		# below the first hour after it (so it builds from there), never more than a third of the snow.
		var lead_rate := minf(onset_rate, Catalog.balance.storm_onset_mean_frac * float(ev["total"]) / maxf(en - st, 0.5))
		if lead_end > st and wsum > 0.0:
			var h1 := int(lead_end)
			var f1 := maxf(minf(float(h1 + 1), en) - lead_end, 0.001)
			lead_rate = minf(lead_rate, 0.8 * float(ev["total"]) * float(weights.get(h1, 0.0)) / wsum / f1)
		lead_rate = minf(lead_rate, float(ev["total"]) / 3.0 / maxf(lead_end - st, 0.001))
		var hours := {}
		var lead_amt := 0.0
		for h in range(s, mini(int(ceil(lead_end)), HOURS)):
			var la := maxf(float(h), st)
			var lb := minf(float(h + 1), lead_end)
			var lf := maxf(lb - la, 0.0)
			if lf > 0.0:
				hours[h] = lead_rate * lf
				lead_amt += lead_rate * lf
		var rest := float(ev["total"]) - lead_amt
		for h in weights.keys():
			hours[h] = float(hours.get(h, 0.0)) + rest * float(weights[h]) / wsum
		var hkeys := hours.keys()
		hkeys.sort()
		var hconds := {}
		var htemp := {}
		var hwind := {}
		for hv in hkeys:
			var h: int = hv
			var r: float = hours[h]
			rate[h] += r
			var x2 := (h - st + 0.5) / span_h
			var hc := c
			var lead := float(h) < lead_end - 0.001
			if lead:
				hc = C.MODERATE if r >= onset_rate * 0.5 else C.LIGHT
			elif x2 < 0.12 or x2 > 0.9:
				hc = maxi(C.LIGHT, c - 1)
			cond[h] = maxi(cond[h], hc)
			total_snow_cm += r
			# Snow tends to fall in milder air; blizzards are windy and cold (from the end of the
			# lead-in: during it the wind and cold are those of a moderate snowfall).
			var shape := clampf(sin(clampf(x2, 0.0, 1.0) * PI) * 1.35, 0.25, 1.15)
			if c == C.BLIZZARD and not lead:
				temp[h] = minf(temp[h], -9.0 - 4.0 * shape)
				wind[h] = 50.0 + 28.0 * shape
			else:
				temp[h] = lerpf(temp[h], -5.0, 0.55)
				wind[h] = maxf(wind[h], [0, 0, 12, 20, 32, 60][C.MODERATE if lead else c] * (0.7 + 0.5 * shape))
			hconds[h] = hc
			htemp[h] = temp[h]
			hwind[h] = wind[h]
		ev["hours"] = hours
		ev["hcond"] = hconds
		ev["htemp"] = htemp
		ev["hwind"] = hwind
	# Random cloudy days.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + year
	cloudy_day.resize(121)
	cloudy_day.fill(0)
	for day in range(121):
		if rng.randf() < 0.3:
			cloudy_day[day] = 1
			for h in range(day * 24 + 6, day * 24 + 20):
				if cond[h] == C.CLEAR:
					cond[h] = C.CLOUDY


# -----------------------------------------------------------------------------
func _hidx(m: float = -1.0) -> int:
	if m < 0.0:
		m = Clock.minutes
	return clampi(int(m / 60.0), 0, HOURS - 1)


func condition() -> int:
	if override_cond >= 0 and Clock.minutes < override_until:
		return override_cond
	if cond.is_empty():
		return C.CLEAR
	return cond[_hidx()]


## Polish 6 §3: true when hour `h` is the hour now and a forced condition (Weather.force, the debug
## menu) holds the sky dry: none of the schedule's snow falls this hour.
func held_dry(h: int) -> bool:
	return h == _hidx() and override_cond >= 0 and Clock.minutes < override_until and override_rate <= 0.0


## Snowfall rate in cm per game hour right now.
func snow_rate() -> float:
	if override_cond >= 0 and Clock.minutes < override_until:
		return override_rate
	if rate.is_empty():
		return 0.0
	return rate[_hidx()]


func intensity() -> float:
	return clampf(snow_rate() / 3.0, 0.0, 1.0)


func temperature() -> float:
	if temp.is_empty():
		return -8.0
	var h := _hidx()
	var f := fmod(Clock.minutes, 60.0) / 60.0
	var t2 := temp[mini(h + 1, HOURS - 1)]
	var t := lerpf(temp[h], t2, f)
	if override_cond == C.BLIZZARD and Clock.minutes < override_until:
		t = minf(t, -14.0)
	return t


func wind_kmh() -> float:
	if wind.is_empty():
		return 10.0
	var w := wind[_hidx()]
	if override_cond >= 0 and Clock.minutes < override_until:
		w = [8.0, 12.0, 15.0, 22.0, 35.0, 70.0][override_cond]
	return w


## Canadian wind chill index (°C).
func wind_chill() -> float:
	var t := temperature()
	var v := maxf(wind_kmh(), 5.0)
	if t > 10.0:
		return t
	return 13.12 + 0.6215 * t - 11.37 * pow(v, 0.16) + 0.3965 * t * pow(v, 0.16)


func is_snowing() -> bool:
	return snow_rate() > 0.01


func on_advance(start_min: float, step_min: float) -> void:
	# Integrate snowfall across the step (rate is per hour; split at hour boundaries).
	var m := start_min
	var end := start_min + step_min
	var add_cm := 0.0
	while m < end - 0.0001:
		var nxt := minf(end, (floor(m / 60.0) + 1.0) * 60.0)
		var r := 0.0
		if override_cond >= 0 and m < override_until:
			r = override_rate
		else:
			r = rate[clampi(int(m / 60.0), 0, HOURS - 1)] if not rate.is_empty() else 0.0
		add_cm += r * (nxt - m) / 60.0
		m = nxt
	if add_cm > 0.0:
		Snow.add_snowfall(add_cm / 100.0)
		Game.stats_add("snowfall_cm", add_cm)


func on_hour(_day: int, hour: int) -> void:
	var c := condition()
	if c != _last_cond:
		_last_cond = c
		condition_changed.emit(c)
	var now_h := Clock.minutes / 60.0
	for ev in events:
		var st: float = ev["start"]
		# Advance warning for forecast severe storms.
		if not ev["warned"] and int(ev["fc_cond"]) >= C.HEAVY and st - now_h <= 9.0 and st - now_h > 0.0:
			ev["warned"] = true
			_alert("Severe weather advisory: %s expected around %s." % [NAMES[ev["fc_cond"]].to_lower(), Clock.format_time((st + ev["fc_shift"] * 0.25) * 60.0)])
		# Storm turns out stronger than forecast (emerges from the schedule, not scripted).
		if not ev["alerted"] and now_h >= st and now_h < float(ev["end"]):
			ev["alerted"] = true
			if ev["surprise"] and tier_of(ev) == "major":
				_alert("WEATHER ALERT: an unforecast storm is dumping snow at %d cm an hour — stay indoors!" % int(round(float(ev["rate"]))))
			elif ev["surprise"]:
				_alert("WEATHER ALERT: storm strengthening — %s conditions, worse than forecast!" % NAMES[ev["cond"]].to_lower())
			elif int(ev["cond"]) == C.BLIZZARD:
				_alert("BLIZZARD WARNING in effect. Stay safe and warm.")
	var t := temperature()
	if hour == 6 and t < -24.0:
		_alert("Extreme cold warning: %d °C, wind chill %d." % [int(t), int(wind_chill())])


func _alert(text: String) -> void:
	alerts.append({"time": Clock.minutes, "text": text})
	if alerts.size() > 20:
		alerts.pop_front()
	Clock.drop_to_1x("alert")   # polish 5 §9: a weather alert stops fast-forward
	alert_issued.emit(text)
	Notify.push(text, Notify.WARN)


## Debug / test: force a weather condition for a number of game hours.
func force(c: int, hours: float, cm_per_hour := -1.0) -> void:
	override_cond = c
	override_until = Clock.minutes + hours * 60.0
	if cm_per_hour < 0.0:
		var b: BalanceData = Catalog.balance
		cm_per_hour = [0.0, 0.0, b.rate_light_cm_h, b.rate_moderate_cm_h, b.rate_heavy_cm_h, b.rate_blizzard_cm_h][c]
	override_rate = cm_per_hour
	_last_cond = -1
	condition_changed.emit(c)
	if c == C.BLIZZARD:
		_alert("BLIZZARD WARNING: a blizzard has developed suddenly!")


# -----------------------------------------------------------------------------
# Forecasts (polish 4 §1): one model for the TV, the radio and the computer
# -----------------------------------------------------------------------------
# What actually falls is the schedule above. A forecast is a deterministic function of the seed,
# the hour it is issued and the hour it is for — no saved state. Each event carries one fixed
# amount error (its own seeded stream) and its fc_shift timing error, both scaled down as the
# event gets closer, so a day's call converges instead of jumping about. Forecast events stay
# forecast; a storm that will arrive stronger than forecast stays under-called, and an unforecast
# major event stays off the forecast, until the radio's surprise horizon before it starts (the TV
# never calls an unforecast one before it starts). Once an event has started, forecasts see it.

## The forecast's fixed errors, from a stream of their own (the schedule's draws are untouched).
func _gen_forecast_noise() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 6151 + year * 7877 + 3
	_ev_amt_err.resize(events.size())
	for i in range(events.size()):
		_ev_amt_err[i] = rng.randf_range(-1.0, 1.0)
	@warning_ignore("integer_division")
	_temp_knots.resize(HOURS / 6 + 2)
	for i in range(_temp_knots.size()):
		_temp_knots[i] = rng.randf_range(-1.0, 1.0)


func _skill() -> float:
	return maxf(Catalog.balance.forecast_skill, 0.05)


## How far off (as a fraction of the amount) a forecast `lead_h` game hours ahead can be.
func fc_error(lead_h: float) -> float:
	var b: BalanceData = Catalog.balance
	return (b.fc_error_base + b.fc_error_per_day * maxf(lead_h, 0.0) / 24.0) / _skill()


## How many game hours before a surprise starts the radio picks it up.
func surprise_horizon_h() -> float:
	return Catalog.balance.radio_surprise_horizon_h * _skill()


func issued_hour() -> int:
	return _hidx()


## How event `i` looks to a forecast issued at hour `issued`, `lead` hours ahead of its target:
## {visible, cond (shown), scale (amount factor), shift (timing error, hours)}.
func _fc_view(i: int, issued: int, lead: float, radio: bool) -> Dictionary:
	var ev: Dictionary = events[i]
	var st: float = ev["start"]
	var err := fc_error(lead)
	var amt := clampf(1.0 + _ev_amt_err[i] * err, 0.25, 3.0)
	# Started by the top of the hour it's issued at (the same hour tick the onset alerts go out on).
	if st <= float(issued):
		return {"visible": true, "cond": int(ev["cond"]), "scale": amt, "shift": 0.0}
	var close := st - float(issued) <= surprise_horizon_h()
	var shift := (float(ev["fc_shift"]) / 4.0) * Catalog.balance.fc_timing_h_per_day * lead / 24.0 / _skill()
	if ev["surprise"] and tier_of(ev) == "major":
		if radio and close:
			return {"visible": true, "cond": int(ev["cond"]), "scale": amt, "shift": shift}
		return {"visible": false}
	if int(ev["fc_cond"]) < int(ev["cond"]) and not close and not called_by(st, issued):
		# Under-called: the forecast shows the weaker system it expects (a few cm).
		return {"visible": true, "cond": int(ev["fc_cond"]), "scale": 4.0 / maxf(float(ev["total"]), 0.1) * amt, "shift": shift, "under": true}
	return {"visible": true, "cond": int(ev["cond"]), "scale": amt, "shift": shift}


## Polish 5 §8 (Decision 7): a storm that arrives stronger than forecast is called at its real
## strength from 7:00 a.m. on the day it starts (the radio has it once it's inside its window).
const CALL_HOUR := 7


static func called_by(st: float, issued: int) -> bool:
	return issued >= int(floor(st / 24.0)) * 24 + CALL_HOUR


func _temp_noise(h: int) -> float:
	@warning_ignore("integer_division")
	var k := h / 6
	var f := float(h % 6) / 6.0
	return lerpf(_temp_knots[mini(k, _temp_knots.size() - 1)], _temp_knots[mini(k + 1, _temp_knots.size() - 1)], f)


## The forecast for game hour `target`, issued at hour `issued`: {cond, rate (cm/h), temp, wind}.
## `radio`: the radio's view (it picks up surprises within the horizon; the TV doesn't).
func fc_hour(target: int, issued: int, radio := false) -> Dictionary:
	target = clampi(target, 0, HOURS - 1)
	var lead := maxf(float(target - issued), 0.0)
	@warning_ignore("integer_division")
	var day := target / 24
	var hod := target % 24
	var c := C.CLOUDY if (cloudy_day.size() > day and cloudy_day[day] == 1 and hod >= 6 and hod < 20) else C.CLEAR
	var r := 0.0
	var b: BalanceData = Catalog.balance
	var t := base_temp[target] + _temp_noise(target) * b.fc_temp_error_per_day * lead / 24.0 / _skill()
	var w := base_wind[target]
	var top := -1
	for i in range(events.size()):
		var ev: Dictionary = events[i]
		if float(ev["end"]) + 10.0 < float(target) or float(ev["start"]) - 10.0 > float(target):
			continue
		var view := _fc_view(i, issued, lead, radio)
		if not view["visible"]:
			continue
		var src := float(target) - float(view["shift"])
		var k := int(floor(src + 0.5))
		if src >= float(ev["start"]) - 5.0 and src <= float(ev["end"]) + 4.0:
			c = maxi(c, C.CLOUDY)
		var hrs: Dictionary = ev.get("hours", {})
		if not hrs.has(k):
			continue
		r += float(hrs[k]) * float(view["scale"])
		var hc: int = ev["hcond"][k]
		if view.get("under", false):
			hc = mini(hc, int(view["cond"]))
		if hc > top:
			top = hc
			if view.get("under", false):
				t = lerpf(t, -5.0, 0.55)
				w = maxf(w, 20.0)
			else:
				t = float(ev["htemp"][k]) + _temp_noise(target) * b.fc_temp_error_per_day * lead / 24.0 / _skill()
				w = float(ev["hwind"][k])
		c = maxi(c, hc)
	return {"cond": c, "rate": r, "temp": t, "wind": w}


func forecast_days() -> int:
	return int(Game.stat_value(&"forecast_days", 1.0)) + 1


## Daily forecast entries starting today (TV, computer, radio), from the forecast model issued at
## the current game hour. Hours of today already gone are what happened.
func forecast(days: int) -> Array:
	var out := []
	var today := Clock.day_index()
	var issued := _hidx()
	for kday in range(days):
		var day := today + kday
		if day >= 121:
			break
		out.append(forecast_day(day, issued))
	return out


## Polish 5 §8: one set of words for a snow system's strength — a light snowfall, a storm, a major
## event — used by the TV, the computer and the radio.
const TIER_NAMES := {"light": "Light snow", "storm": "Snowstorm", "major": "Major snowstorm"}
const TIER_RANK := {"": 0, "light": 1, "storm": 2, "major": 3}
const TIER_COND := {"": C.CLEAR, "light": C.LIGHT, "storm": C.HEAVY, "major": C.BLIZZARD}


static func tier_name(t: String) -> String:
	return str(TIER_NAMES.get(t, ""))


## The strength an hour's condition reads as (light and moderate snow are a light snowfall).
static func cond_tier(c: int) -> String:
	if c >= C.BLIZZARD:
		return "major"
	if c >= C.HEAVY:
		return "storm"
	return "light" if c >= C.LIGHT else ""


## The strength the forecast issued at hour `issued` names for event `i` ("" while it doesn't show
## it): a forecast event's own tier; a storm still under-called reads as a light snowfall.
func fc_tier(i: int, issued: int, radio := false) -> String:
	var ev: Dictionary = events[i]
	var view := _fc_view(i, issued, maxf(float(ev["start"]) - float(issued), 0.0), radio)
	if not view["visible"]:
		return ""
	return "light" if view.get("under", false) else tier_of(ev)


## When the forecast issued at `issued` has event `i` starting and ending (game hours; the timing
## error shrinks as it gets closer, and is gone once it has started): [start, end], or [] when the
## forecast doesn't show it.
func fc_span(i: int, issued: int, radio := false) -> Array:
	var ev: Dictionary = events[i]
	var st: float = ev["start"]
	var en: float = ev["end"]
	var vs := _fc_view(i, issued, maxf(st - float(issued), 0.0), radio)
	if not vs["visible"]:
		return []
	var ve := _fc_view(i, issued, maxf(en - float(issued), 0.0), radio)
	return [st + float(vs["shift"]), en + float(ve.get("shift", vs["shift"]))]


## The start time a card shows for event `i` issued at `issued`, to the hour (-1 when not shown).
func shown_start_h(i: int, issued: int) -> float:
	var sp := fc_span(i, issued)
	return -1.0 if sp.is_empty() else roundf(float(sp[0]))


## One day card (the TV's, the computer's) from the forecast issued at hour `issued`. The hours of
## the day already gone and the hour now are what is happening (what the HUD shows, what falls);
## the rest is the forecast. Polish 5 §8 adds the strength of the snow on the card ("tier") and
## when it should start and end ("from_h" / "to_h", game hours; -1 without snow).
func forecast_day(day: int, issued: int) -> Dictionary:
	var entry := {"day": day, "date": Clock.date_string(day, true), "cond": C.CLEAR, "hi": -99.0, "lo": 99.0,
		"snow_lo": 0.0, "snow_hi": 0.0, "wind": 0.0, "events": [], "issued": issued,
		"tier": "", "from_h": -1.0, "to_h": -1.0}
	var cloudy := 0
	for h in range(day * 24, day * 24 + 24):
		var hc := C.CLEAR
		var hr := 0.0
		var ht := 0.0
		var hw := 0.0
		var spread := 0.0
		if h <= issued:
			hc = cond[h]
			hr = rate[h]
			ht = temp[h]
			hw = wind[h]
		else:
			var f := fc_hour(h, issued)
			hc = f["cond"]
			hr = f["rate"]
			ht = f["temp"]
			hw = f["wind"]
			spread = minf(fc_error(float(h - issued)), 0.9)
		entry["hi"] = maxf(entry["hi"], ht)
		entry["lo"] = minf(entry["lo"], ht)
		entry["wind"] = maxf(entry["wind"], hw)
		entry["snow_lo"] += hr * (1.0 - spread)
		entry["snow_hi"] += hr * (1.0 + spread)
		if hc >= C.LIGHT:
			entry["cond"] = maxi(entry["cond"], hc)
		elif hc == C.CLOUDY and h % 24 >= 8 and h % 24 < 18:
			cloudy += 1
	if entry["cond"] == C.CLEAR and cloudy > 4:
		entry["cond"] = C.CLOUDY
	# The snow systems on the card: what has fallen today and is falling now, then every system the
	# forecast puts snow on the rest of the day in (the same hours the hourly forecast above uses).
	var d0 := day * 24
	var d1 := d0 + 24
	for i in range(events.size()):
		var ev: Dictionary = events[i]
		var st: float = ev["start"]
		var en: float = ev["end"]
		if en + 12.0 < float(d0) or st - 12.0 > float(d1):
			continue
		var hrs: Dictionary = ev["hours"]
		var on := false
		for h in range(d0, mini(d1, issued + 1)):
			if hrs.has(h):
				on = true
				break
		if not on:
			for h in range(maxi(d0, issued + 1), d1):
				var v := _fc_view(i, issued, float(h - issued), false)
				if v["visible"] and hrs.has(int(floor(float(h) - float(v["shift"]) + 0.5))):
					on = true
					break
		if not on:
			continue
		var t := fc_tier(i, issued)
		var sp := fc_span(i, issued)
		if t == "":
			# An unforecast major event in the hour it starts: the TV names what is falling now only
			# (it isn't on the TV before it starts — Decision 7; the next issue has it).
			t = cond_tier(int((ev["hcond"] as Dictionary).get(issued, C.LIGHT)))
			sp = [st, float(issued + 1)]
		# Polish 6 §3: a system due to be snowing now whose start time shown has passed (an hour
		# before this one) while none of it is falling moves to its new expected start, the next
		# hour ("from about noon" at 11:14). The schedule always snows through a system's hours, so
		# only a sky held dry by force (the debug menu's weather) does that.
		if issued >= d0 and hrs.has(issued) and held_dry(issued) and roundf(float(sp[0])) < float(issued):
			sp = [float(issued + 1), maxf(float(sp[1]), float(issued + 1))]
		if TIER_RANK[t] > TIER_RANK[entry["tier"]]:
			entry["tier"] = t
		entry["from_h"] = float(sp[0]) if entry["from_h"] < 0.0 else minf(entry["from_h"], float(sp[0]))
		entry["to_h"] = maxf(entry["to_h"], float(sp[1]))
		# Forecast systems touching the day (the computer's radar detail).
		entry["events"].append({"start": float(sp[0]), "end": float(sp[1]), "cond": TIER_COND[t], "tier": t})
	# The icon follows the strength named.
	entry["cond"] = maxi(entry["cond"], TIER_COND[entry["tier"]])
	return entry


## Polish 5 §8: a day card's words — the same on the TV and the computer: the date, the strength
## (or the sky when no snow is due), the snow expected as a range, when it should start and end,
## and the high and low. {date, title, amount, when, temps}
static func card_text(entry: Dictionary) -> Dictionary:
	var tier := str(entry.get("tier", ""))
	if tier == "" and int(entry["cond"]) >= C.LIGHT:
		tier = cond_tier(int(entry["cond"]))
	var title: String = tier_name(tier) if tier != "" else NAMES[int(entry["cond"])]
	var amount := snow_range_text(entry)
	if tier != "" and amount == "":
		amount = "Under 1 cm"
	# Polish 5 §11: the card's date with its weekday ("Fri Dec 4"), from Clock.weekday like every display.
	var date := "%s %s" % [Clock.weekday(int(entry["day"]), Game.year), str(entry["date"])]
	return {"date": date, "title": title, "amount": amount if tier != "" else "",
		"when": when_text(entry, float(entry.get("from_h", -1.0)), float(entry.get("to_h", -1.0))) if tier != "" else "",
		"temps": "High %d°  ·  Low %d°" % [int(entry["hi"]), int(entry["lo"])]}


## "from about 2 p.m.", "from about 2 p.m. to 10 p.m.", "until about 10 a.m.", "all day" — when the
## snow on a day card starts and ends, to the hour. A midnight that would read as the wrong end of
## the day is said in words: "overnight" (starting late that night), "until just after midnight".
static func when_text(entry: Dictionary, a: float, b: float) -> String:
	if a < 0.0 or b < 0.0:
		return ""
	var d0 := int(entry["day"]) * 24
	var ha := int(roundf(a))
	var hb := int(roundf(b))
	var starts := ha >= d0
	var ends := hb <= d0 + 24
	if starts and ha >= d0 + 24:
		return "overnight"
	if ends and hb <= d0:
		return "until just after midnight"
	if starts and ends:
		if hb <= ha:
			return "around %s" % hour_name(ha)
		return "from about %s to %s" % [hour_name(ha), hour_name(hb)]
	if starts:
		return "from about %s" % hour_name(ha)
	if ends:
		return "until about %s" % hour_name(hb)
	return "all day"


## One line for a card: "Snowstorm · 15–25 cm · from about 2 p.m."
static func card_line(entry: Dictionary) -> String:
	var c := card_text(entry)
	var parts := [c["title"]]
	for k in ["amount", "when"]:
		if str(c[k]) != "":
			parts.append(c[k])
	return "  ·  ".join(parts)


## The computer's card for a day: the TV's card, then the weather apps' detail (wind; the radar's
## systems hour by hour).
func forecast_text(entry: Dictionary, detail: int) -> String:
	var c := card_text(entry)
	var s := "%s  ·  %s" % [c["date"], card_line(entry)]
	s += "\n" + str(c["temps"])
	if detail >= 1:
		s += "  ·  wind %d km/h" % int(entry["wind"])
	if detail >= 2:
		for e in entry["events"]:
			s += "\n    %s from %s to %s" % [tier_name(str(e.get("tier", cond_tier(int(e["cond"]))))), Clock.format_time(maxf(e["start"], 0.0) * 60.0), Clock.format_time(e["end"] * 60.0)]
	return s


## The expected snow for a day card: "2–10 cm" (narrowing as the day gets closer), or "".
static func snow_range_text(entry: Dictionary) -> String:
	var lo := float(entry["snow_lo"])
	var hi := float(entry["snow_hi"])
	if hi < 0.5:
		return ""
	var a := int(floor(lo))
	var bnd := maxi(int(ceil(hi)), a + 1)
	if a <= 0:
		return "Up to %d cm" % bnd
	return "%d–%d cm" % [a, bnd]


## "2 p.m.", "noon", "midnight".
static func hour_name(h: int) -> String:
	var hh := h % 24
	if hh == 0:
		return "midnight"
	if hh == 12:
		return "noon"
	return "%d %s" % [hh if hh < 12 else hh - 12, "a.m." if hh < 12 else "p.m."]


## The radio's bulletin: what is happening now if it's snowing, then the next three game hours —
## the hour, the condition, the temperature (on the first hour and when it changes), the snowfall
## rate when it's heavy, rising wind. "2 p.m. light snow, −9°. 3 p.m. moderate snow, wind picking
## up. 4 p.m. heavy snow, 3 to 5 cm an hour." Polish 5 §8: then, from start to end, the system
## falling now or due in the window — its strength, when it should end and how much more is coming
## ("Snowstorm ending around 10 p.m., another 8 to 12 cm.") — or "Snow has ended." once it's over.
func radio_bulletin() -> String:
	var issued := _hidx()
	var parts := []
	var now_r := snow_rate()
	if now_r > 0.01:
		var nxt := fc_hour(issued + 1, issued, true)
		var now_c := condition()
		if int(nxt["cond"]) > now_c:
			# "Right now: moderate snow, heavy snow developing."
			parts.append("Right now: %s, %s developing." % [NAMES[now_c].to_lower(), NAMES[nxt["cond"]].to_lower()])
		else:
			var growing := float(nxt["rate"]) > now_r * 1.25 + 0.05
			parts.append("Right now: %s%s." % [NAMES[now_c].to_lower(), " developing" if growing else ""])
	var prev_w := wind_kmh()
	var said_t := INF
	for k in range(1, 4):
		var h := issued + k
		if h >= HOURS:
			break
		var f := fc_hour(h, issued, true)
		var p := "%s %s" % [hour_name(h).capitalize() if h % 12 == 0 else hour_name(h), NAMES[f["cond"]].to_lower()]
		if absf(float(f["temp"]) - said_t) >= 2.0:
			said_t = float(f["temp"])
			p += ", %s°" % _deg(said_t)
		if float(f["wind"]) - prev_w >= 8.0:
			p += ", wind picking up"
		if int(f["cond"]) >= C.HEAVY and float(f["rate"]) > 0.3:
			var e := fc_error(float(k))
			var lo := maxi(1, int(floor(float(f["rate"]) * (1.0 - e))))
			var hi := maxi(lo + 1, int(ceil(float(f["rate"]) * (1.0 + e))))
			p += ", %d to %d cm an hour" % [lo, hi]
		prev_w = float(f["wind"])
		parts.append(p + ".")
	var spell := radio_spell_text()
	if spell != "":
		parts.append(spell)
	return " ".join(parts)


## The radio's window: the rest of the hour now and the next three game hours.
const RADIO_WINDOW_H := 3


## The snow systems the radio follows now, as its forecast sees them: the one falling now, then the
## next one due to start in its window (at most two, in that order). [] when there are none.
func radio_spells(issued: int) -> Array:
	var now_h := Clock.minutes / 60.0
	var falling_i := -1
	var due := []
	for i in range(events.size()):
		var ev: Dictionary = events[i]
		if float(ev["end"]) + 6.0 < now_h or float(ev["start"]) - 6.0 > float(issued + RADIO_WINDOW_H + 1):
			continue
		var sp := fc_span(i, issued, true)
		if sp.is_empty():
			continue
		if falling_i < 0 and (ev["hours"] as Dictionary).has(issued) and rate[issued] > 0.01:
			falling_i = i
			continue
		if float(sp[1]) <= now_h or float(sp[0]) >= float(issued + RADIO_WINDOW_H + 1):
			continue
		due.append([float(sp[0]), i])
	due.sort()
	var out := []
	if falling_i >= 0:
		out.append(falling_i)
	for d in due:
		if out.size() < 2:
			out.append(int(d[1]))
	return out


## The first of them (-1 when there is none).
func radio_spell(issued: int) -> int:
	var sp := radio_spells(issued)
	return int(sp[0]) if not sp.is_empty() else -1


## "Snowstorm ending around 10 p.m., another 8 to 12 cm." while a system falls, "Snowstorm ending
## around 10 p.m., 15 to 25 cm in all." for one due in the radio's window (both when one follows
## the other); "Snow has ended." in the hours after the last one ended; "" otherwise.
func radio_spell_text() -> String:
	var issued := _hidx()
	var spells := radio_spells(issued)
	if spells.is_empty():
		var ended := last_snow_end_minutes()
		if ended >= 0.0 and Clock.minutes - ended <= RADIO_WINDOW_H * 60.0 and Clock.minutes >= ended:
			return "Snow has ended."
		return ""
	var out := []
	for i in spells:
		out.append(_spell_line(int(i), issued))
	return " ".join(out)


func _spell_line(i: int, issued: int) -> String:
	var ev: Dictionary = events[i]
	var sp := fc_span(i, issued, true)
	var hrs: Dictionary = ev["hours"]
	var falling := hrs.has(issued) and rate[issued] > 0.01
	# How much more: the rest of the hour now (what is falling), then the radio's forecast of the
	# system hour by hour to its end (the same hours the hourly forecast uses).
	var now_h := Clock.minutes / 60.0
	var more := 0.0
	if hrs.has(issued):
		more += float(hrs[issued]) * clampf(float(issued + 1) - now_h, 0.0, 1.0)
	var lead_sum := 0.0
	var lead_w := 0.0
	for h in range(issued + 1, mini(int(ceil(float(sp[1]))) + 2, HOURS)):
		var v := _fc_view(i, issued, float(h - issued), true)
		if not v["visible"]:
			continue
		var r := float(hrs.get(int(floor(float(h) - float(v["shift"]) + 0.5)), 0.0)) * float(v["scale"])
		more += r
		lead_sum += r * float(h - issued)
		lead_w += r
	var e := minf(fc_error(lead_sum / lead_w if lead_w > 0.0 else 0.0), 0.9)
	var lo := int(floor(more * (1.0 - e)))
	var hi := maxi(int(ceil(more * (1.0 + e))), lo + 1)
	var end_h := int(roundf(float(sp[1])))
	@warning_ignore("integer_division")
	var later := (end_h - 1) / 24 > issued / 24
	var s := "%s ending around %s%s" % [tier_name(fc_tier(i, issued, true)), hour_name(end_h), " tomorrow" if later else ""]
	if more * (1.0 + e) < 1.0:
		return s if s.ends_with(".") else s + "."
	if lo <= 0:
		return s + (", up to %d cm more." % hi if falling else ", up to %d cm." % hi)
	return s + (", another %d to %d cm." % [lo, hi] if falling else ", %d to %d cm in all." % [lo, hi])


static func _deg(t: float) -> String:
	var v := int(round(t))
	return ("−%d" % -v) if v < 0 else str(v)


## Polish 4 §1: when the hour changes, the look of the weather (sky, light, fog, falling flakes)
## moves to the new hour's conditions over a few game minutes instead of snapping. The snow that
## falls and every reading are the hour's own.
const VISUAL_BLEND_MIN := 6.0


func _overriding() -> bool:
	return override_cond >= 0 and Clock.minutes < override_until


## 0 → still looking like the previous hour, 1 → fully this hour's look.
func visual_mix() -> float:
	if _overriding() or cond.is_empty():
		return 1.0
	return clampf(fmod(Clock.minutes, 60.0) / VISUAL_BLEND_MIN, 0.0, 1.0)


func visual_prev_condition() -> int:
	if _overriding() or cond.is_empty():
		return condition()
	return cond[maxi(_hidx() - 1, 0)]


func visual_rate() -> float:
	if _overriding() or rate.is_empty():
		return snow_rate()
	return lerpf(rate[maxi(_hidx() - 1, 0)], rate[_hidx()], visual_mix())


func visual_intensity() -> float:
	return clampf(visual_rate() / 3.0, 0.0, 1.0)


func visual_wind_kmh() -> float:
	if _overriding() or wind.is_empty():
		return wind_kmh()
	return lerpf(wind[maxi(_hidx() - 1, 0)], wind[_hidx()], visual_mix())


func current_summary() -> String:
	return "%s, %d °C (feels like %d), wind %d km/h" % [NAMES[condition()], int(round(temperature())), int(round(wind_chill())), int(wind_kmh())]


## Hours (game) of the most recent snowfall end at or before now; -1 if snowing.
func last_snow_end_minutes() -> float:
	var h := _hidx()
	if rate[h] > 0.01:
		return -1.0
	while h > 0 and rate[h] <= 0.01:
		h -= 1
	return (h + 1) * 60.0


func serialize() -> Dictionary:
	var ev := []
	for e in events:
		ev.append({"start": e["start"], "alerted": e["alerted"], "warned": e["warned"]})
	# Polish 5 §8: the recent alerts too (optional key), so the TV's "Latest alert" and the
	# computer's list read the same after a reload.
	return {"year": year, "seed": seed_value, "events": ev, "override_cond": override_cond,
		"override_rate": override_rate, "override_until": override_until, "alerts": alerts.duplicate(true)}


func deserialize(d: Dictionary) -> void:
	generate(int(d.get("year", 1)), int(d.get("seed", 1)))
	var ev: Array = d.get("events", [])
	for i in range(mini(ev.size(), events.size())):
		# Schedules from older saves (before storm tiers) differ: stop at the first mismatch.
		if absf(float(ev[i].get("start", -1.0)) - float(events[i]["start"])) > 0.01:
			break
		events[i]["alerted"] = bool(ev[i].get("alerted", false))
		events[i]["warned"] = bool(ev[i].get("warned", false))
	override_cond = int(d.get("override_cond", -1))
	override_rate = float(d.get("override_rate", -1.0))
	override_until = float(d.get("override_until", -1.0))
	alerts.clear()
	for a in d.get("alerts", []):
		if a is Dictionary and a.has("text"):
			alerts.append({"time": float(a.get("time", 0.0)), "text": str(a["text"])})
	while alerts.size() > 20:
		alerts.pop_front()
