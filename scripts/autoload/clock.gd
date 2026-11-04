extends Node
## Centralised game clock. 1 real minute = 24 game minutes (fixed, Part 13.1).
## All time-based systems are advanced from here, in a fixed order, both during normal play
## and during sleep / multi-day skips (which run the same code in larger steps).

signal hour_changed(day: int, hour: int)
signal day_changed(day: int)
signal winter_ended
signal skip_finished

const GAME_MIN_PER_REAL_SEC := 0.4
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


func _process(delta: float) -> void:
	if not running or skipping or get_tree().paused:
		return
	advance(delta * GAME_MIN_PER_REAL_SEC * time_scale)


func reset(start_minutes: float) -> void:
	minutes = start_minutes
	_ended = false


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


static func weekday(day: int, year: int) -> String:
	var names := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
	return names[(day + year * 2) % 7]


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
