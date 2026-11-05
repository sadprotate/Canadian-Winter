extends Node
## Centralised game clock. One game day lasts REAL_MIN_PER_DAY real minutes (polish 5 §9: 30, so
## 1 real minute = 48 game minutes; it was 24). Everything that converts real time to game time
## reads GAME_MIN_PER_REAL_SEC — nothing else may assume the rate.
## All time-based systems are advanced from here, in a fixed order, both during normal play
## and during sleep / multi-day skips (which run the same code in larger steps).
##
## Fast-forward (polish 5 §9): `speed` 1, 2 or 10 runs only the game clock N× faster, as N substeps
## of the same size per frame — every substep runs exactly what a frame at 1× runs for the world on
## the clock (the clock step, then the world's tick: box measuring, snowfall syncing and relaxation,
## the grader), so a stretch at 2× or 10× ends exactly where 1× does. The player, tools, vehicles,
## physics and animations stay at normal speed. Never saved: a new game and a load start at 1×.
## Anything that should stop fast-forward calls drop_to_1x(reason) — the one hook (weather alerts,
## contract warnings, bids won or lost, cold warnings, starting to work the snow, getting into a
## vehicle; §10's bidding and deadline warnings call it too).

signal hour_changed(day: int, hour: int)
signal day_changed(day: int)
signal winter_ended
signal skip_finished
## Polish 5 §9: the chosen fast-forward speed changed (`reason` is why when it went back to 1× on
## its own: "alert", "contract", "bid", "cold", "work", "vehicle", "unavailable", …; "" when chosen).
signal speed_changed(speed: int, reason: String)

const REAL_MIN_PER_DAY := 30.0
const GAME_MIN_PER_REAL_SEC := 1440.0 / (REAL_MIN_PER_DAY * 60.0)
## Polish 5 §9: the fast-forward speeds, in the order the key cycles them.
const SPEEDS := [1, 2, 10]
## Polish 5 §9: frame-budget caps (measured with tests/perf.tscn -- --ff_sweep, see HANDOFF §12):
## while the snowfall now is at least this many cm per game hour, a speed above `max` runs at
## `max`. On the build VM 10× held 16.7 ms at p95 with margin below 0.5 cm/h (worst 12.1 ms over
## seven runs at 0.5), only just or not at all above it (0.6–1.0 cm/h: 11.7–18.5 ms; 21–25 ms at a
## storm's 5.5 cm/h peak — every substep syncs snowfall into the map). 2× held everywhere (11.6 ms
## at 50 cm/h) but came within 0.4 ms of the line at a major event's 110 cm/h peak, so the heaviest
## hours of the biggest events run at 1×. The world adds its own (game_root.ff_cap(): the grader
## out, snow settling).
const SPEED_CAPS := [
	{"cm_h": 0.5, "max": 2, "why": "snowing"},
	{"cm_h": 80.0, "max": 1, "why": "blizzard"},
]
const DAYS_IN_WINTER := 121
const MONTHS := ["December", "January", "February", "March", "April"]
const MONTH_SHORT := ["Dec", "Jan", "Feb", "Mar", "Apr"]
const MONTH_START := [0, 31, 62, 90, 121]

var minutes := 0.0          # game minutes since Dec 1 00:00 of the current winter
var running := false        # true while a game is in progress (world loaded)
var time_scale := 1.0       # debug only
var skipping := false
var interrupt_reason := ""
var _ended := false
var speed := 1              # polish 5 §9: the fast-forward speed chosen (1, 2, 10); never saved
var drop_reason := ""       # why it last went back to 1× on its own ("" after a choice)
var substeps_last_frame := 0
var caps_on := true         # tests/perf.tscn measures the speeds uncapped too
## Polish 5 §9: the world's share of a frame on the clock (box measuring, snowfall syncing and
## relaxation, the grader), run once more for every extra substep. Set by the game world.
var world_tick := Callable()


func _process(delta: float) -> void:
	if not running or skipping or get_tree().paused:
		substeps_last_frame = 0
		return
	var step := delta * GAME_MIN_PER_REAL_SEC * time_scale
	if speed > 1:
		var why := unavailable_reason()
		if why != "":
			drop_to_1x(why)
	# Fast-forward: N substeps of the same size. Each extra one runs the clock step and then what the
	# rest of a frame at 1× runs for the world (Boxes, then the world's tick), so the order of
	# everything on the clock is the same at any speed; the frame's own step comes last, followed
	# by the frame's own box measuring and world update as at 1×.
	var n := effective_speed()
	var done := 1
	while done < n and not _ended:
		advance(step)
		Boxes.sim_step(delta)
		if world_tick.is_valid():
			world_tick.call(delta)
		done += 1
		if effective_speed() < n:
			break   # dropped to 1×, a mover came near or a cap took over: the rest at 1×
	substeps_last_frame = done
	advance(step)


func reset(start_minutes: float) -> void:
	minutes = start_minutes
	_ended = false
	speed = 1                # polish 5 §9: fast-forward is never saved — a new game or a load is 1×
	drop_reason = ""


# -----------------------------------------------------------------------------
# Polish 5 §9: fast-forward
# -----------------------------------------------------------------------------

## Why fast-forward can't be used right now ("" when it can): the world decides (on foot, indoors
## or at the computer; not in a vehicle or machine, during Gerry's lines, a dialog or sleep).
func unavailable_reason() -> String:
	if skipping:
		return "sleep"
	if not running:
		return "stopped"
	var w: Object = Game.world
	if w != null and is_instance_valid(w) and w.has_method("ff_unavailable"):
		return str(w.call("ff_unavailable"))
	return ""


## Why fast-forward is held at 1× for now ("" when it isn't): a scripted mover (the grader, Gerry)
## near the player — the pass is watched at 1×, and the chosen speed resumes after it.
func hold_reason() -> String:
	var w: Object = Game.world
	if w != null and is_instance_valid(w) and w.has_method("ff_hold"):
		return str(w.call("ff_hold"))
	return ""


## The highest speed the frame budget allows now, and why it's lower than 10× ("" when it isn't).
func speed_cap() -> int:
	return int(_cap()["max"])


func cap_reason() -> String:
	return str(_cap()["why"])


func _cap() -> Dictionary:
	var best := {"max": SPEEDS[SPEEDS.size() - 1], "why": ""}
	if not caps_on:
		return best
	var rate := Weather.snow_rate()
	for c in SPEED_CAPS:
		if rate >= float(c["cm_h"]) and int(c["max"]) < int(best["max"]):
			best = {"max": int(c["max"]), "why": str(c["why"])}
	var w: Object = Game.world
	if w != null and is_instance_valid(w) and w.has_method("ff_cap"):
		var wc: Dictionary = w.call("ff_cap")
		if not wc.is_empty() and int(wc["max"]) < int(best["max"]):
			best = {"max": int(wc["max"]), "why": str(wc["why"])}
	return best


## The speed the clock runs at this frame: the chosen one, capped by the frame budget, held at 1×
## while a scripted mover is near.
func effective_speed() -> int:
	if speed <= 1:
		return 1
	if hold_reason() != "":
		return 1
	return mini(speed, speed_cap())


## Choose a speed (1, 2 or 10). Refused (false) while fast-forward isn't available.
func set_speed(s: int) -> bool:
	if not s in SPEEDS:
		return false
	if s > 1 and unavailable_reason() != "":
		return false
	if s != speed:
		speed = s
		drop_reason = ""
		speed_changed.emit(speed, "")
	return true


## The fast-forward key: 1× → 2× → 10× → 1×.
func cycle_speed() -> bool:
	var i := SPEEDS.find(speed)
	return set_speed(SPEEDS[(i + 1) % SPEEDS.size()])


## Polish 5 §9: the one hook that stops fast-forward. Call it for anything the player should see
## at normal speed: a weather alert, a contract warning, a bid won or lost, a cold warning, the
## player starting to scoop, push or throw, getting into a vehicle (and §10's bidding / deadlines).
func drop_to_1x(reason: String) -> void:
	if speed == 1:
		return
	speed = 1
	drop_reason = reason
	speed_changed.emit(1, reason)


## Advance the clock and every dependent system, splitting at hour boundaries.
func advance(game_min: float) -> void:
	while game_min > 0.0 and not _ended:
		var to_hour := 60.0 - fmod(minutes, 60.0)
		if to_hour <= 0.0001:
			to_hour = 60.0
		var step := minf(game_min, to_hour)
		var start := minutes
		minutes += step
		game_min -= step
		var hb := int(floor((start + 0.0001) / 60.0))
		var ha := int(floor((minutes + 0.0001) / 60.0))
		if ha > hb:
			minutes = ha * 60.0
		_systems_advance(start, step)
		if ha > hb:
			var d := int(floor((minutes + 0.0001) / 1440.0))
			var h := ha % 24
			if h == 0:
				_systems_day(d)
				day_changed.emit(d)
			_systems_hour(d, h)
			hour_changed.emit(d, h)
		if minutes >= DAYS_IN_WINTER * 1440.0 - 0.001 and not _ended:
			_ended = true
			minutes = DAYS_IN_WINTER * 1440.0
			winter_ended.emit()
		if interrupt_reason != "":
			break


func _systems_advance(start: float, step: float) -> void:
	Weather.on_advance(start, step)
	Snow.advance_settle(step)
	Heating.advance(step)      # polish 5 §13: the heated pad, driveway and path melt on the clock
	Survival.on_advance(step)
	Contracts.on_advance(step)


func _systems_hour(day: int, hr: int) -> void:
	Weather.on_hour(day, hr)
	Economy.on_hour(day, hr)
	Municipal.on_hour(day, hr)
	Boxes.on_hour(day, hr)
	Contracts.on_hour(day, hr)


func _systems_day(day: int) -> void:
	Economy.on_day(day)
	Contracts.on_day(day)


## Skip forward (sleep). Returns the minutes actually skipped (may stop early if interrupted).
func skip(game_min: float) -> float:
	skipping = true
	interrupt_reason = ""
	var start := minutes
	var remaining := game_min
	while remaining > 0.0 and not _ended:
		var step := minf(remaining, 30.0)
		advance(step)
		remaining -= step
		if interrupt_reason != "":
			break
	skipping = false
	Snow.sync_all()
	skip_finished.emit()
	return minutes - start


func request_interrupt(reason: String) -> void:
	if skipping:
		interrupt_reason = reason


func has_ended() -> bool:
	return _ended


# -----------------------------------------------------------------------------
func day_index() -> int:
	return int(minutes / 1440.0)


func hour_f() -> float:
	return fmod(minutes, 1440.0) / 60.0


func hour() -> int:
	return int(hour_f())


func minute_of_hour() -> int:
	return int(fmod(minutes, 60.0))


## Minutes since midnight of the given winter day.
static func at(day: int, hr: float) -> float:
	return day * 1440.0 + hr * 60.0


static func month_of(day: int) -> int:
	for m in range(4, -1, -1):
		if day >= MONTH_START[m]:
			return m
	return 0


static func day_of_month(day: int) -> int:
	return day - MONTH_START[month_of(day)] + 1


static func date_string(day: int, short := false) -> String:
	var m := month_of(day)
	return "%s %d" % [(MONTH_SHORT if short else MONTHS)[m], day_of_month(day)]


## Polish 5 §11: the real calendar behind the game's (it had a placeholder weekday and no years).
## Winter 1 starts on Tuesday, December 1, 2026, and winter N runs from December of 2025 + N to
## March of 2026 + N. The game's winter has no February 29 (Feb has 28 days, MONTH_START): a date
## keeps its real weekday, so in a leap winter (winter 2: Feb 28, 2028 is a Monday) the game's next
## day, March 1, is a Wednesday — the leap day is simply not played.
const FIRST_WINTER_YEAR := 2026
const WEEKDAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


## The real date of a winter day: Vector3i(year, month 1–12, day of month).
static func real_date(day: int, year: int) -> Vector3i:
	var m := month_of(day)
	var y := FIRST_WINTER_YEAR + maxi(year, 1) - 1 + (0 if m == 0 else 1)
	return Vector3i(y, 12 if m == 0 else m, day_of_month(day))


## Days from 1970-01-01 to a date of the (proleptic) Gregorian calendar.
static func _days_from_civil(y: int, m: int, d: int) -> int:
	if m <= 2:
		y -= 1
	@warning_ignore("integer_division")
	var era := (y if y >= 0 else y - 399) / 400
	var yoe := y - era * 400
	@warning_ignore("integer_division")
	var doy := (153 * (m + (-3 if m > 2 else 9)) + 2) / 5 + d - 1
	@warning_ignore("integer_division")
	var doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468


## The weekday of a winter day, 0 = Monday … 6 = Sunday (1970-01-01 was a Thursday).
static func weekday_index(day: int, year: int) -> int:
	var rd := real_date(day, year)
	return posmod(_days_from_civil(rd.x, rd.y, rd.z) + 3, 7)


## "Tue" — the one weekday every display uses (the HUD clock, the TV and computer cards, due
## times, the map's tags, the city crews' day).
static func weekday(day: int, year: int) -> String:
	return WEEKDAYS[weekday_index(day, year)]


func time_string() -> String:
	var h := hour()
	var mi := minute_of_hour()
	return "%02d:%02d" % [h, mi]


static func format_time(game_minutes: float) -> String:
	var d := int(game_minutes / 1440.0)
	var hm := fmod(game_minutes, 1440.0)
	return "%s %02d:%02d" % [date_string(d, true), int(hm / 60.0), int(fmod(hm, 60.0))]


## Day index of the given month (0=Dec..3=Mar) and day-of-month.
static func day_of(month: int, dom: int) -> int:
	return MONTH_START[month] + dom - 1
