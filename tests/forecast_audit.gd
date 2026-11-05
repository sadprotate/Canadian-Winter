extends Node
## Polish 5 §8: the forecast audit. Measures, over seeds × winters, how the TV's day cards, the
## radio's next three hours and the other displays compare with the weather that actually falls:
##   A. the strength each TV card names (light snow / snowstorm / major snowstorm), 0–3 days out
##   B. the error in a forecast event's start time, by lead
##   C. the error in a forecast event's total, by lead
##   D. a card's day total: the shown range vs the snow that falls that day, by lead
##   E. the radio's next three hours: the condition and the rate
##   F. displays that disagree, hour by hour: the TV vs the radio, either vs the HUD, vs what falls
## Pure functions of the weather schedule (no world, no rendering), so it runs on any build that has
## the pass-4 forecast model; what a build adds (a card's tier, start time) is read when it exists.
## test_polish5 (§8) calls the same functions for its targets.
## Run: godot --headless --path . res://tests/forecast_audit.tscn
##        [-- --seeds=2024,1,7,42,99 --winters=1,2,3 --every=3 --out=<file.md> --json=<file.json>
##            --set=fc_timing_h_per_day=0.5,fc_error_base=0.05]   (--set: try balance values in memory)

const SEEDS := [2024, 1, 7, 42, 99]
const TIER_RANK := {"": 0, "light": 1, "storm": 2, "major": 3}
const TIER_WORD := {"": "none", "light": "Light snow", "storm": "Snowstorm", "major": "Major snowstorm"}
## The targets (POLISH_ROUND_5_PROMPT §8 and Decision 7).
const RADIO_HORIZON_TARGET_H := 3.0
const TV_CALL_HOUR := 7


static func gen(s: int, y: int) -> void:
	Weather.generate(y, s + y * 13)


## The TV card's strength: the card's tier where the build names one, else (pass 4) its condition.
static func card_tier(e: Dictionary) -> String:
	if e.has("tier"):
		return str(e["tier"])
	match int(e["cond"]):
		Weather.C.LIGHT, Weather.C.MODERATE:
			return "light"
		Weather.C.HEAVY:
			return "storm"
		Weather.C.BLIZZARD:
			return "major"
	return ""


## The range a card shows, as numbers: [lo, hi] in cm ([0, 0] when it shows none).
static func shown_range(e: Dictionary) -> Array:
	var t := Weather.snow_range_text(e)
	if t == "":
		return [0, 0]
	var nums := []
	var cur := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			cur += ch
		elif cur != "":
			nums.append(int(cur))
			cur = ""
	if cur != "":
		nums.append(int(cur))
	if nums.size() == 1:
		return [0, nums[0]]
	return [nums[0], nums[1]]


## The TV's card for day `day` as issued at hour `issued`.
static func card(issued: int, day: int) -> Dictionary:
	if Weather.has_method("forecast_day"):
		return Weather.forecast_day(day, issued)
	Clock.minutes = issued * 60.0 + 30.0
	var k := day - Clock.day_index()
	var fc := Weather.forecast(k + 1)
	return fc[k] if fc.size() > k else {}


## The snow event `ev` drops on `day` (cm, the truth).
static func ev_on_day(ev: Dictionary, day: int) -> float:
	var s := 0.0
	var hrs: Dictionary = ev["hours"]
	for h in range(day * 24, day * 24 + 24):
		s += float(hrs.get(h, 0.0))
	return s


static func is_forecast_event(ev: Dictionary) -> bool:
	return not ev["surprise"]


## Decision 7, what the TV may name for event `ev` at issue hour `issued`: [lowest, highest] tier.
## Forecast events: their tier. A storm that arrives stronger than forecast: light until 7:00 a.m.
## on its day (or until it's inside the radio's window or has started), a snowstorm from then on —
## either is fine before. An unforecast major event: not on the TV before it starts.
static func tv_may_name(ev: Dictionary, issued: int) -> Array:
	var tier := Weather.tier_of(ev)
	var st: float = ev["start"]
	if st <= float(issued) or is_forecast_event(ev):
		return [tier, tier]
	if tier == "major":
		return ["", ""]
	@warning_ignore("integer_division")
	var call := int(floor(st)) / 24 * 24 + TV_CALL_HOUR
	if issued >= call:
		return [tier, tier]
	return ["light", tier]


# -----------------------------------------------------------------------------
# A + D. The TV's cards, 0–3 days out: the strength named and the day's range
# -----------------------------------------------------------------------------
## For every day a forecast event drops at least `min_cm` on, the cards for that day issued 0–3 days
## before (every `every` hours of the issuing day): is the strength right (at least the strongest the
## TV may name among the systems dropping min_cm that day, at most the strongest snowing on it at
## all, or within an hour of it — counted apart), and does the range contain what falls?
static func audit_cards(seeds: Array, winters: Array, every: int, min_cm := 1.0) -> Dictionary:
	var out := {"tier_n": [0, 0, 0, 0], "tier_bad": [0, 0, 0, 0], "tier_edge": [0, 0, 0, 0], "range_n": [0, 0, 0, 0], "range_in": [0, 0, 0, 0],
		"range_all_n": [0, 0, 0, 0], "range_all_in": [0, 0, 0, 0], "day_err": [0.0, 0.0, 0.0, 0.0], "day_n": [0, 0, 0, 0],
		"width": [0.0, 0.0, 0.0, 0.0],
		"tier_examples": [], "range_examples": []}
	var keep := Clock.minutes
	for s in seeds:
		for y in winters:
			gen(int(s), int(y))
			var n_ev := Weather.events.size()
			for d in range(1, 121):
				# The events on this day (truth): what drops at least min_cm, and anything at all.
				var on := []
				var touch := []
				var near := []
				var any_surprise := false
				var forecast_on := false
				for i in range(n_ev):
					var ev: Dictionary = Weather.events[i]
					if float(ev["end"]) < d * 24 - 1 or float(ev["start"]) > d * 24 + 25:
						continue
					var amt := ev_on_day(ev, d)
					if amt <= 0.0:
						# Snowing within an hour of the day ("from about midnight"): the card may name it.
						var hrs0: Dictionary = ev["hours"]
						if hrs0.has(d * 24 - 1) or hrs0.has(d * 24 + 24):
							near.append(i)
						continue
					if not is_forecast_event(ev):
						any_surprise = true
					touch.append(i)
					if amt >= min_cm:
						on.append(i)
						if is_forecast_event(ev):
							forecast_on = true
				var actual := 0.0
				for h in range(d * 24, d * 24 + 24):
					actual += Weather.rate[h]
				for k in range(4):
					var day0 := d - k
					if day0 < 0:
						continue
					for hh in range(0, 24, every):
						var iss := day0 * 24 + hh
						var c := card(iss, d)
						if c.is_empty():
							continue
						# A. the strength, for days a forecast event drops at least min_cm on.
						if forecast_on:
							# The card must name at least what drops min_cm on the day, and may name any
							# system that snows on it at all (a storm that starts late that evening).
							var lo := 0
							var hi := 0
							for i in touch:
								var ev2: Dictionary = Weather.events[i]
								# Snow already fallen today is what happened: the TV may name it.
								var may := tv_may_name(ev2, iss)
								var started := ev_on_day_before(ev2, d, iss) > 0.0
								if started:
									may = [Weather.tier_of(ev2), Weather.tier_of(ev2)]
								if on.has(i):
									lo = maxi(lo, TIER_RANK[may[0]])
								hi = maxi(hi, TIER_RANK[may[1]])
							var got: int = TIER_RANK[card_tier(c)]
							out["tier_n"][k] += 1
							var hi_near := hi
							for i in near:
								hi_near = maxi(hi_near, TIER_RANK[tv_may_name(Weather.events[i], iss)[1]])
							if got > hi and got <= hi_near and got >= lo:
								out["tier_edge"][k] += 1
							elif got < lo or got > hi:
								out["tier_bad"][k] += 1
								if (out["tier_examples"] as Array).size() < 12:
									out["tier_examples"].append("%d/%d %s, %d d out, issued %s: card \"%s\", expected %s" % [s, y, Clock.date_string(d, true), k, Clock.format_time(iss * 60.0), card_tier(c), str(on.map(func(i): return Weather.tier_of(Weather.events[i])))])
						# D. the range, on days with snow (either way).
						var r := shown_range(c)
						if actual < 0.5 and int(r[1]) == 0:
							continue
						var inside := float(r[0]) <= actual + 0.0001 and actual <= float(r[1]) + 0.0001
						out["range_all_n"][k] += 1
						out["range_all_in"][k] += 1 if inside else 0
						if actual >= 0.5:
							out["day_n"][k] += 1
							out["day_err"][k] += absf((float(c["snow_lo"]) + float(c["snow_hi"])) * 0.5 - actual) / actual
						if not any_surprise and forecast_on:
							out["range_n"][k] += 1
							out["range_in"][k] += 1 if inside else 0
							out["width"][k] += float(int(r[1]) - int(r[0])) / maxf(actual, 1.0)
							if not inside and (out["range_examples"] as Array).size() < 12:
								out["range_examples"].append("%d/%d %s, %d d out, issued %s: shown %d–%d cm, fell %.1f cm" % [s, y, Clock.date_string(d, true), k, Clock.format_time(iss * 60.0), r[0], r[1], actual])
	Clock.minutes = keep
	return out


## Snow event `ev` dropped on `day` before hour `issued` (the truth the card shows as what happened).
static func ev_on_day_before(ev: Dictionary, day: int, issued: int) -> float:
	var s := 0.0
	var hrs: Dictionary = ev["hours"]
	for h in range(day * 24, mini(day * 24 + 24, issued)):
		s += float(hrs.get(h, 0.0))
	return s


# -----------------------------------------------------------------------------
# B + C. A forecast event's start time and total, by lead (days out = its start day − the issuing day)
# -----------------------------------------------------------------------------
static func audit_events(seeds: Array, winters: Array) -> Dictionary:
	var out := {"n": [0, 0, 0, 0], "start_abs": [0.0, 0.0, 0.0, 0.0], "start_max": [0.0, 0.0, 0.0, 0.0],
		"shown_abs": [0.0, 0.0, 0.0, 0.0], "shown_max": [0.0, 0.0, 0.0, 0.0], "shown_n": [0, 0, 0, 0],
		"tot_rel": [0.0, 0.0, 0.0, 0.0], "tot_max": [0.0, 0.0, 0.0, 0.0], "events": 0}
	for s in seeds:
		for y in winters:
			gen(int(s), int(y))
			for i in range(Weather.events.size()):
				var ev: Dictionary = Weather.events[i]
				if not is_forecast_event(ev):
					continue
				out["events"] += 1
				var st: float = ev["start"]
				var total: float = ev["total"]
				var sd := int(floor(st / 24.0))
				for k in range(4):
					var day0 := sd - k
					if day0 < 0:
						continue
					for hh in range(24):
						var iss := day0 * 24 + hh
						if float(iss) >= st:
							break
						var view: Dictionary = Weather._fc_view(i, iss, st - float(iss), false)
						if not view.get("visible", false):
							continue
						var fs := st + float(view["shift"])
						var e := absf(fs - st)
						out["n"][k] += 1
						out["start_abs"][k] += e
						out["start_max"][k] = maxf(out["start_max"][k], e)
						var fc_tot := total * float(view["scale"])
						var te := absf(fc_tot - total) / total
						out["tot_rel"][k] += te
						out["tot_max"][k] = maxf(out["tot_max"][k], te)
						# The start time the card shows, where the build shows one (hour, rounded).
						if Weather.has_method("shown_start_h"):
							var sh: float = Weather.shown_start_h(i, iss)
							if sh >= 0.0:
								var e2 := absf(sh - st)
								out["shown_n"][k] += 1
								out["shown_abs"][k] += e2
								out["shown_max"][k] = maxf(out["shown_max"][k], e2)
	return out


# -----------------------------------------------------------------------------
# E. The radio: its next three hours vs what falls
# -----------------------------------------------------------------------------
static func audit_radio(seeds: Array, winters: Array) -> Dictionary:
	var out := {"calls": 0, "right": 0, "snowy": 0, "snowy_right": 0, "rate_n": 0, "rate_in": 0, "rate_rel": 0.0,
		"by_k": [[0, 0], [0, 0], [0, 0]], "examples": []}
	for s in seeds:
		for y in winters:
			gen(int(s), int(y))
			for iss in range(24, Weather.HOURS - 4):
				for k in range(1, 4):
					var h := iss + k
					var f: Dictionary = Weather.fc_hour(h, iss, true)
					var tc: int = Weather.cond[h]
					var fc: int = f["cond"]
					out["calls"] += 1
					out["right"] += 1 if fc == tc else 0
					if tc >= Weather.C.LIGHT or fc >= Weather.C.LIGHT:
						out["snowy"] += 1
						out["by_k"][k - 1][0] += 1
						if fc == tc:
							out["snowy_right"] += 1
							out["by_k"][k - 1][1] += 1
						elif (out["examples"] as Array).size() < 10:
							out["examples"].append("%d/%d issued %s, +%d h: radio %s, fell %s (%.2f vs %.2f cm/h)" % [s, y, Clock.format_time(iss * 60.0), k, Weather.NAMES[fc], Weather.NAMES[tc], float(f["rate"]), Weather.rate[h]])
					var tr: float = Weather.rate[h]
					if tr >= 0.2:
						var rel := absf(float(f["rate"]) - tr) / tr
						out["rate_n"] += 1
						out["rate_rel"] += rel
						out["rate_in"] += 1 if rel <= 0.25 + 1e-6 else 0
	return out


# -----------------------------------------------------------------------------
# F. Displays that disagree, hour by hour (at half past each hour)
# -----------------------------------------------------------------------------
## The checks:
##  radio_tv      — the radio calls snow for an hour of its window, the TV's card for that day shows none
##  radio_tv_time — …the card shows snow but at another time of day (start/end more than an hour off)
##  strength      — the radio calls heavy snow or a blizzard, the card for that day names a lighter strength
##  spell_tier    — the radio's start-to-end line names a strength the card for that day doesn't reach
##  ended_snow    — the radio says the snow has ended and calls snow for an hour of its window
##  falling_tv    — snow is falling, the TV's today card shows none
##  falling_radio — snow is falling, the radio doesn't say what's happening now
##  hud_falling   — the HUD (the hour's condition) says snow and nothing falls, or the reverse
##  radio_now     — the radio's "right now" isn't the HUD's condition
## The radio picking up an unforecast major event before the TV (Decision 7) is counted on its own.
static func audit_sync(seeds: Array, winters: Array, minute := 30.0) -> Dictionary:
	var keys := ["radio_tv", "radio_tv_time", "strength", "spell_tier", "ended_snow", "falling_tv", "falling_radio", "hud_falling", "radio_now"]
	var out := {"hours": 0, "checked": 0, "surprise_window": 0, "examples": []}
	for k in keys:
		out[k] = 0
	var keep := Clock.minutes
	for s in seeds:
		for y in winters:
			gen(int(s), int(y))
			for iss in range(0, Weather.HOURS - 4):
				out["hours"] += 1
				Clock.minutes = iss * 60.0 + minute
				var falling := Weather.snow_rate() > 0.01
				var hud: int = Weather.condition()
				if (hud >= Weather.C.LIGHT) != (Weather.rate[iss] > 0.0):
					out["hud_falling"] += 1
					_ex(out, "%d/%d %s: HUD %s, %.3f cm/h falling" % [s, y, Clock.format_time(Clock.minutes), Weather.NAMES[hud], Weather.rate[iss]])
				var calls := []
				for k in range(1, 4):
					calls.append(Weather.fc_hour(iss + k, iss, true))
				var radio_snow := false
				for f in calls:
					radio_snow = radio_snow or int(f["cond"]) >= Weather.C.LIGHT
				if not falling and not radio_snow:
					continue
				out["checked"] += 1
				# Inside an unforecast major event's radio lead (Decision 7): the radio is ahead of the TV.
				var lead_window := false
				for ev in Weather.events:
					if ev["surprise"] and Weather.tier_of(ev) == "major" and float(ev["start"]) > float(iss) and float(ev["start"]) - float(iss) <= RADIO_HORIZON_TARGET_H + 1.0:
						lead_window = true
				if lead_window:
					out["surprise_window"] += 1
				var bulletin := Weather.radio_bulletin()
				if bulletin.contains("Snow has ended.") and radio_snow:
					out["ended_snow"] += 1
					_ex(out, "%d/%d %s: \"%s\"" % [s, y, Clock.format_time(Clock.minutes), bulletin])
				if falling and not bulletin.begins_with("Right now:"):
					out["falling_radio"] += 1
					_ex(out, "%d/%d %s: snow falling, radio \"%s\"" % [s, y, Clock.format_time(Clock.minutes), bulletin])
				if falling:
					var now_name: String = Weather.NAMES[hud].to_lower()
					if not bulletin.begins_with("Right now: " + now_name):
						out["radio_now"] += 1
						_ex(out, "%d/%d %s: HUD %s, radio \"%s\"" % [s, y, Clock.format_time(Clock.minutes), now_name, bulletin.left(60)])
				@warning_ignore("integer_division")
				var today := iss / 24
				var cards := {}
				cards[today] = card(iss, today)
				if falling and card_tier(cards[today]) == "":
					out["falling_tv"] += 1
					_ex(out, "%d/%d %s: snow falling, TV today \"%s\"" % [s, y, Clock.format_time(Clock.minutes), Weather.NAMES[int(cards[today]["cond"])]])
				# The radio's start-to-end line names a strength the TV's card for that day names too.
				if Weather.has_method("radio_spells") and not lead_window:
					for sp in Weather.radio_spells(iss):
						var span: Array = Weather.fc_span(sp, iss, true)
						var sday := today if Weather.rate[iss] > 0.0 and (Weather.events[sp]["hours"] as Dictionary).has(iss) else int(floor(maxf(float(span[0]), float(iss)) / 24.0))
						if not cards.has(sday):
							cards[sday] = card(iss, sday)
						var st_t: String = Weather.fc_tier(sp, iss, true)
						if TIER_RANK[card_tier(cards[sday])] < TIER_RANK[st_t]:
							out["spell_tier"] += 1
							_ex(out, "%d/%d %s: radio \"%s\", TV card %s names %s" % [s, y, Clock.format_time(Clock.minutes), Weather.radio_spell_text(), str(cards[sday]["date"]), TIER_WORD[card_tier(cards[sday])]])
				for k in range(1, 4):
					var f: Dictionary = calls[k - 1]
					if int(f["cond"]) < Weather.C.LIGHT:
						continue
					var h := iss + k
					@warning_ignore("integer_division")
					var dd := h / 24
					if not cards.has(dd):
						cards[dd] = card(iss, dd)
					var c: Dictionary = cards[dd]
					var tier := card_tier(c)
					if tier == "":
						if lead_window:
							continue
						out["radio_tv"] += 1
						_ex(out, "%d/%d %s: radio %s at %s, TV card %s \"%s\"" % [s, y, Clock.format_time(Clock.minutes), Weather.NAMES[int(f["cond"])], Weather.hour_name(h), str(c["date"]), Weather.NAMES[int(c["cond"])]])
						continue
					var need := 2 if int(f["cond"]) == Weather.C.HEAVY else (3 if int(f["cond"]) == Weather.C.BLIZZARD else 1)
					if TIER_RANK[tier] < need and not lead_window:
						out["strength"] += 1
						_ex(out, "%d/%d %s: radio %s at %s, TV card %s names %s" % [s, y, Clock.format_time(Clock.minutes), Weather.NAMES[int(f["cond"])], Weather.hour_name(h), str(c["date"]), TIER_WORD[tier]])
					# The radio's hour [h, h + 1) more than an hour from when the card has snow ("about").
					if c.has("from_h") and c.has("to_h") and not lead_window:
						if float(h) + 1.0 < float(c["from_h"]) - 1.0 or float(h) > float(c["to_h"]) + 1.0:
							out["radio_tv_time"] += 1
							_ex(out, "%d/%d %s: radio snow at %s, TV card %s %.1f–%.1f h" % [s, y, Clock.format_time(Clock.minutes), Weather.hour_name(h), str(c["date"]), float(c["from_h"]), float(c["to_h"])])
	Clock.minutes = keep
	return out


static func _ex(out: Dictionary, t: String) -> void:
	if (out["examples"] as Array).size() < 24:
		out["examples"].append(t)


# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------
static func pct(a: float, b: float) -> String:
	return "—" if b <= 0.0 else "%.1f %%" % (100.0 * a / b)


static func tables(cards: Dictionary, evs: Dictionary, radio: Dictionary, sync: Dictionary) -> String:
	var L := []
	L.append("**A. Strength named on the TV's card** (days a forecast event drops ≥ 1 cm on; issued every few hours of the issuing day)")
	L.append("")
	L.append("| Days out | Cards | Wrong strength | Naming a system that starts or ends within an hour of the day |")
	L.append("|---|---|---|---|")
	for k in range(3, -1, -1):
		L.append("| %d | %d | %d (%s) | %d |" % [k, cards["tier_n"][k], cards["tier_bad"][k], pct(cards["tier_bad"][k], cards["tier_n"][k]), cards["tier_edge"][k]])
	L.append("")
	L.append("**B/C. A forecast event's start time and total** (issued every hour of the issuing day, before it starts)")
	L.append("")
	L.append("| Days out | Forecasts | Start: mean error | Start: worst | Shown start: worst | Total: mean error | Total: worst |")
	L.append("|---|---|---|---|---|---|---|")
	for k in range(3, -1, -1):
		var n: float = maxf(evs["n"][k], 1)
		var shown := "—" if int(evs["shown_n"][k]) == 0 else "%.2f h" % float(evs["shown_max"][k])
		L.append("| %d | %d | %.2f h | %.2f h | %s | %.1f %% | %.1f %% |" % [k, evs["n"][k], float(evs["start_abs"][k]) / n, float(evs["start_max"][k]), shown, 100.0 * float(evs["tot_rel"][k]) / n, 100.0 * float(evs["tot_max"][k])])
	L.append("")
	L.append("**D. A card's day total** (the range shown vs the snow that falls that day)")
	L.append("")
	L.append("| Days out | Days (forecast events only) | Range contains it | Range width / day total | All snowy days | Range contains it | Mean error of the middle |")
	L.append("|---|---|---|---|---|---|---|")
	for k in range(3, -1, -1):
		L.append("| %d | %d | %s | %.0f %% | %d | %s | %.0f %% |" % [k, cards["range_n"][k], pct(cards["range_in"][k], cards["range_n"][k]), 100.0 * float(cards["width"][k]) / maxf(cards["range_n"][k], 1), cards["range_all_n"][k], pct(cards["range_all_in"][k], cards["range_all_n"][k]), 100.0 * float(cards["day_err"][k]) / maxf(cards["day_n"][k], 1)])
	L.append("")
	L.append("**E. The radio's next three hours**")
	L.append("")
	L.append("| Calls | Condition right | Snowy calls | Condition right | +1 h | +2 h | +3 h | Rate within ±25 % | Mean rate error |")
	L.append("|---|---|---|---|---|---|---|---|---|")
	var bk: Array = radio["by_k"]
	L.append("| %d | %s | %d | %s | %s | %s | %s | %s | %.1f %% |" % [radio["calls"], pct(radio["right"], radio["calls"]), radio["snowy"], pct(radio["snowy_right"], radio["snowy"]),
		pct(bk[0][1], bk[0][0]), pct(bk[1][1], bk[1][0]), pct(bk[2][1], bk[2][0]), pct(radio["rate_in"], radio["rate_n"]), 100.0 * float(radio["rate_rel"]) / maxf(radio["rate_n"], 1)])
	L.append("")
	L.append("**F. Hours where displays disagree** (%d hours, %d with snow falling or on the radio; %d of those inside an unforecast major event's radio lead)" % [sync["hours"], sync["checked"], sync["surprise_window"]])
	L.append("")
	var has_spell := Weather.has_method("radio_spell")
	L.append("| Radio snow, TV card none | …at another time | Radio heavier than the TV's strength | Radio's start-to-end strength above the TV's | \"Snow has ended\" with snow due | Falling, TV today none | Falling, radio silent | HUD vs falling | Radio \"right now\" vs HUD |")
	L.append("|---|---|---|---|---|---|---|---|---|")
	L.append("| %d | %d | %d | %s | %s | %d | %d | %d | %d |" % [sync["radio_tv"], sync["radio_tv_time"], sync["strength"], str(sync["spell_tier"]) if has_spell else "—", str(sync["ended_snow"]) if has_spell else "—", sync["falling_tv"], sync["falling_radio"], sync["hud_falling"], sync["radio_now"]])
	return "\n".join(L)


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var seeds := []
	for x in str(args.get("seeds", ",".join(SEEDS.map(func(v): return str(v))))).split(","):
		seeds.append(int(x))
	var winters := []
	for x in str(args.get("winters", "1,2,3")).split(","):
		winters.append(int(x))
	var every := int(args.get("every", "3"))
	# Tuning: try forecast values without editing the balance files (name=value,…).
	if args.has("set"):
		for kv in str(args["set"]).split(","):
			var p := kv.split("=")
			Catalog.balance.set(p[0], float(p[1]))
	var b: BalanceData = Catalog.balance
	print("fc_error_base %.3f, fc_error_per_day %.3f, fc_timing_h_per_day %.3f, radio_surprise_horizon_h %.1f" % [b.fc_error_base, b.fc_error_per_day, b.fc_timing_h_per_day, b.radio_surprise_horizon_h])
	var t0 := Time.get_ticks_msec()
	var cards := audit_cards(seeds, winters, every)
	var t1 := Time.get_ticks_msec()
	var evs := audit_events(seeds, winters)
	var radio := audit_radio(seeds, winters)
	var t2 := Time.get_ticks_msec()
	var sync := audit_sync(seeds, winters)
	var t3 := Time.get_ticks_msec()
	var md := "Forecast audit — seeds %s × winters %s\n\n" % [str(seeds), str(winters)] + tables(cards, evs, radio, sync)
	md += "\n\nExamples — strength:\n- " + "\n- ".join(cards["tier_examples"])
	md += "\n\nExamples — range:\n- " + "\n- ".join(cards["range_examples"])
	md += "\n\nExamples — radio:\n- " + "\n- ".join(radio["examples"])
	md += "\n\nExamples — sync:\n- " + "\n- ".join(sync["examples"])
	print(md)
	print("\n(cards %d ms, events + radio %d ms, sync %d ms)" % [t1 - t0, t2 - t1, t3 - t2])
	if args.has("out"):
		var f := FileAccess.open(str(args["out"]), FileAccess.WRITE)
		f.store_string(md + "\n")
		f.close()
	if args.has("json"):
		var f2 := FileAccess.open(str(args["json"]), FileAccess.WRITE)
		f2.store_string(JSON.stringify({"cards": cards, "events": evs, "radio": radio, "sync": sync}, " "))
		f2.close()
	AudioMgr.quit(0)
