extends Node
## Survival Mode: warmth, cold exposure, house heat and power outages (Part 17).

signal state_changed(state: int)
signal died
signal power_changed(on: bool)

enum St { COMFORTABLE, COOLING, COLD, DANGER, CRITICAL, DEAD }
const STATE_NAMES := ["Comfortable", "Cooling", "Cold", "Dangerously cold", "Critical freezing", "Frozen"]

var warmth := 100.0
var active := false          # Survival Mode: on from the first minute of a new game (Fun Mode: never)
var power_on := true
var outage_start := -1.0
var house_heat := 1.0
var invulnerable := false
var pouch_until := -1.0
var dead := false
# Context flags set by the world each frame.
var in_player_house := false
var in_neighbor_house := false
var near_fire := false
var vehicle_heat := 0.0      # 0..1 while in a heated running vehicle cab
var last_rate := 0.0
var _state := St.COMFORTABLE


func start_winter() -> void:
	warmth = 100.0
	power_on = true
	outage_start = -1.0
	house_heat = 1.0
	pouch_until = -1.0
	dead = false
	_state = St.COMFORTABLE


func enabled() -> bool:
	return Game.is_survival() and active and not invulnerable


func activate() -> void:
	if not active:
		active = true
		Game.dirty_since_save = true


func state() -> int:
	if dead:
		return St.DEAD
	if warmth >= 70.0:
		return St.COMFORTABLE
	if warmth >= 45.0:
		return St.COOLING
	if warmth >= 25.0:
		return St.COLD
	if warmth >= 10.0:
		return St.DANGER
	return St.CRITICAL


func cut_power() -> void:
	if not power_on:
		return
	power_on = false
	outage_start = Clock.minutes
	power_changed.emit(false)
	Notify.push("POWER CUT: your hydro bill was not paid. The house will cool down over the day.", Notify.BAD)
	Game.dirty_since_save = true


func restore_power() -> void:
	if power_on:
		return
	power_on = true
	outage_start = -1.0
	power_changed.emit(true)
	Notify.push("Power and heating restored. The house is warming back up.", Notify.GOOD)
	Game.dirty_since_save = true


## Polish 5 §9: a warmth rate per game hour as the player feels it — per real minute at 1×.
static func per_real_minute(rate_per_game_hour: float) -> float:
	return rate_per_game_hour * Clock.GAME_MIN_PER_REAL_SEC


## Cold exposure curve: warmth-% lost per game hour at a given (wind-chill) temperature.
static func exposure(feels_c: float) -> float:
	var pts: PackedVector2Array = Catalog.balance.exposure_curve
	if pts.is_empty():
		return 10.0
	if feels_c >= pts[0].x:
		return pts[0].y
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		if feels_c >= b.x:
			return lerpf(a.y, b.y, (a.x - feels_c) / (a.x - b.x))
	return pts[pts.size() - 1].y


## Outdoor cooling rate in warmth-% per game hour (positive number), driven by the actual weather:
## temperature and wind (wind chill), snowfall intensity and blizzards.
func outdoor_loss_per_hour() -> float:
	var b: BalanceData = Catalog.balance
	var wc := Weather.wind_chill()
	var mult := 1.0
	match Weather.condition():
		Weather.C.MODERATE: mult = b.moderate_cold_mult
		Weather.C.HEAVY: mult = b.heavy_cold_mult
		Weather.C.BLIZZARD: mult = b.blizzard_cold_mult
	var loss := exposure(wc) * mult
	# Polish 5 §13: the insulated coat (it replaces the old jacket and parka upgrades).
	loss *= Equipment.cold_mult()
	if Clock.minutes < pouch_until:
		loss *= 0.6
	return loss


func compute_rate() -> float:
	var b: BalanceData = Catalog.balance
	var gain := b.warmth_recover_per_hour
	var rate := 0.0
	if in_neighbor_house:
		rate = gain
	elif in_player_house:
		var sheltered := exposure(Weather.temperature()) * 0.65 * Equipment.cold_mult()
		var g := gain * Game.stat_value(&"house_warm", 1.0)
		if near_fire and power_on:
			g *= 1.4
		rate = house_heat * g - (1.0 - house_heat) * sheltered
	elif vehicle_heat > 0.0:
		rate = vehicle_heat * gain - (1.0 - vehicle_heat) * outdoor_loss_per_hour() * 0.5
	else:
		rate = -outdoor_loss_per_hour()
	if Clock.minutes < pouch_until:
		rate += b.pouch_warmth_per_hour   # polish 5 §9: was a fixed +20 (per game hour)
	return rate


func on_advance(step_min: float) -> void:
	# House heat: full within an hour when powered; loses all stored heat over the day after a cut.
	if power_on:
		house_heat = minf(1.0, house_heat + step_min / 60.0)
	else:
		house_heat = clampf(1.0 - (Clock.minutes - outage_start) / 1440.0, 0.0, 1.0)
	if not enabled():
		warmth = 100.0
		last_rate = 0.0
		return
	if dead:
		return
	last_rate = compute_rate()
	warmth = clampf(warmth + last_rate * step_min / 60.0, 0.0, 100.0)
	var s := state()
	if s != _state:
		var prev := _state
		_state = s
		state_changed.emit(s)
		if s > prev and s >= St.COLD:
			Clock.drop_to_1x("cold")   # polish 5 §9: a cold warning stops fast-forward
			Notify.push("You are %s." % STATE_NAMES[s].to_lower(), Notify.WARN if s < St.DANGER else Notify.BAD)
	if Clock.skipping and warmth < 30.0:
		Clock.request_interrupt("cold")
	if warmth <= 0.0:
		dead = true
		died.emit()


## Use a heating pouch (utility item). Returns true if one was used.
func use_pouch() -> bool:
	if Game.heat_pouches <= 0:
		return false
	Game.heat_pouches -= 1
	var b: BalanceData = Catalog.balance
	warmth = minf(100.0, warmth + b.pouch_warmth)
	pouch_until = Clock.minutes + b.pouch_protection_minutes
	Game.inventory_changed.emit()
	return true


func serialize() -> Dictionary:
	return {"warmth": warmth, "active": active, "power_on": power_on, "outage_start": outage_start,
		"house_heat": house_heat, "pouch_until": pouch_until}


func deserialize(d: Dictionary) -> void:
	warmth = float(d.get("warmth", 100.0))
	active = bool(d.get("active", false))
	power_on = bool(d.get("power_on", true))
	outage_start = float(d.get("outage_start", -1.0))
	house_heat = float(d.get("house_heat", 1.0))
	pouch_until = float(d.get("pouch_until", -1.0))
	dead = false
	_state = state()
