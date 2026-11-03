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
		var len := maxf(en - st, 0.5)
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
			var x := ((a + bnd) * 0.5 - st) / len
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
			var x2 := (h - st + 0.5) / len
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


func on_hour(day: int, hour: int) -> void:
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
	if int(ev["fc_cond"]) < int(ev["cond"]) and not close:
		# Under-called: the forecast shows the weaker system it expects (a few cm).
		return {"visible": true, "cond": int(ev["fc_cond"]), "scale": 4.0 / maxf(float(ev["total"]), 0.1) * amt, "shift": shift, "under": true}
	return {"visible": true, "cond": int(ev["cond"]), "scale": amt, "shift": shift}


func _temp_noise(h: int) -> float:
	var k := h / 6
	var f := float(h % 6) / 6.0
	return lerpf(_temp_knots[mini(k, _temp_knots.size() - 1)], _temp_knots[mini(k + 1, _temp_knots.size() - 1)], f)


## The forecast for game hour `target`, issued at hour `issued`: {cond, rate (cm/h), temp, wind}.
## `radio`: the radio's view (it picks up surprises within the horizon; the TV doesn't).
func fc_hour(target: int, issued: int, radio := false) -> Dictionary:
	target = clampi(target, 0, HOURS - 1)
	var lead := maxf(float(target - issued), 0.0)
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
		var entry := {"day": day, "date": Clock.date_string(day, true), "cond": C.CLEAR, "hi": -99.0, "lo": 99.0,
			"snow_lo": 0.0, "snow_hi": 0.0, "wind": 0.0, "events": [], "issued": issued}
		var cloudy := 0
		for h in range(day * 24, day * 24 + 24):
			var hc := C.CLEAR
			var hr := 0.0
			var ht := 0.0
			var hw := 0.0
			var spread := 0.0
			if h < issued:
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
		# Forecast systems touching the day (the computer's radar detail).
		for i in range(events.size()):
			var ev: Dictionary = events[i]
			var lead := maxf(float(ev["start"]) - float(issued), 0.0)
			var view := _fc_view(i, issued, lead, false)
			if not view["visible"]:
				continue
			var fs := float(ev["start"]) + float(view["shift"])
			var fe := float(ev["end"]) + float(view["shift"])
			if fe < day * 24 or fs > day * 24 + 24:
				continue
			entry["events"].append({"start": fs, "end": fe, "cond": int(view["cond"])})
		out.append(entry)
	return out


func forecast_text(entry: Dictionary, detail: int) -> String:
	var s := "%s: %s, high %d° low %d°" % [entry["date"], NAMES[entry["cond"]], int(entry["hi"]), int(entry["lo"])]
	if entry["snow_hi"] > 0.2:
		if detail >= 1:
			s += ", snow %d–%d cm" % [int(entry["snow_lo"]), int(ceil(entry["snow_hi"]))]
		else:
			s += ", snow expected"
	if detail >= 1:
		s += ", wind %d km/h" % int(entry["wind"])
	if detail >= 2:
		for e in entry["events"]:
			s += "\n    %s from %s to %s" % [NAMES[e["cond"]], Clock.format_time(maxf(e["start"], 0.0) * 60.0), Clock.format_time(e["end"] * 60.0)]
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
## up. 4 p.m. heavy snow, 3 to 5 cm an hour."
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
	return " ".join(parts)


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
	return {"year": year, "seed": seed_value, "events": ev, "override_cond": override_cond,
		"override_rate": override_rate, "override_until": override_until}


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
