extends Node
## Contracts (Part 15; polish 5 §10): the contract board, live bidding against simulated rivals,
## active contracts with zones made of clearing boxes (90% rule), recurring service visits and city
## contracts, and due times.
##
## Polish 5 §10 (Decisions 4 and 5):
## * Tiers. Listings are residential (path jobs and driveway jobs: more paths at low reputation),
##   commercial (the school, store and church parking lots) or city (street sections and
##   sidewalks). Above the player's tier a listing is shown locked ("Needs reputation N").
## * The bidding day. Until 9:00 p.m. the player may place, raise, lower or withdraw a bid; the
##   rivals bid at seeded times from their own random stream and may answer an undercut once or
##   twice; nobody bids below the floor. At 9:00 p.m. every listing posted at least 3 game hours
##   earlier closes (later ones close at 9:00 p.m. the next day); at 9:01 p.m. the lowest bid wins
##   (a tie goes to the player).
## * Due times replace the 48-hour snowed-in rule. A one-time job is due by 9:00 p.m. the day after
##   it was won. A recurring or city visit falls due when the contract's boxes reopen, by 9:00 p.m.
##   on the day after the snowfall that reopened them ends. Heavy snow or worse inside a job's
##   window moves its due time one day later, once per job. Done = every box complete before the
##   due time: paid, reputation gained (scaled with the job's size), in the history. Missed =
##   reputation lost, no pay, in the history, and the job back on the board. Gerry's trail has none.
## Everything here runs on the clock inside Clock.advance (on_advance / on_hour), so fast-forward
## runs it in the same per-step code as 1×.

signal changed

const RIVALS := [
	{"name": "Frost Brothers Snow Removal", "edge": 0.0},
	{"name": "Polar Plow Co.", "edge": 0.04},
	{"name": "Northern Shovelers", "edge": -0.03},
	{"name": "Great White Property Care", "edge": 0.02},
]
const CLIENT_FIRST := ["Linda", "Marc", "Priya", "Gord", "Nathalie", "Wei", "Sandra", "Tom", "Amélie", "Raj",
	"Doris", "Kevin", "Isabelle", "Ahmed", "Brenda", "Luc", "Fiona", "Dave", "Mei", "Yves", "Carol", "Jacques"]
const CLIENT_LAST := ["Tremblay", "MacDonald", "Singh", "Roy", "Chen", "Gagnon", "Wilson", "Côté", "Patel", "Martin",
	"Bouchard", "Campbell", "Leblanc", "Nguyen", "Morin", "Stewart"]

## Polish 5 §10 (Decision 4): bidding closes and jobs fall due at 9:00 p.m.; the award is a minute
## later; a listing posted less than 3 game hours before 9 p.m. closes at 9 p.m. the next day; a
## storm moves a due time one day.
const DUE_HOUR := 21.0
const AWARD_DELAY_MIN := 1.0
const MIN_LEAD_MIN := 180.0
const STORM_EXTENSION_MIN := 1440.0
const TIERS := ["residential", "commercial", "city"]
## What each level of equipment clears per real second at a human pace (m³/s): hands and shovels,
## pushers / scrapers / the sleigh / the electric shovel, blowers, vehicles with a plow or a blower.
## The shovel figure is tests/contract_bench's (the small shovel: 15.8 m³ in 12 real minutes).
const EQUIP_RATE := [0.02, 0.06, 0.1, 0.5]
## City sidewalk sections: the lots' sidewalk boxes along one side of a street, west or east of
## Cedar Lane (row letter + "w" / "e"; see Layout's rows).
const WALK_SECTIONS := ["A_w", "A_e", "B_w", "B_e", "C_w", "C_e", "D_w", "D_e"]

var listings: Array = []
## Polish 5 §10: the player's live bids, derived from the listings (each listing holds its own
## "bid"): {lid, amount, at, listing}. Not saved — rebuilt on load.
var bids: Array = []
var active: Array = []
var history: Array = []         # completed one-time jobs (pre-polish-5 record, still kept and saved)
## Polish 5 §7: the company's contract history — every job it held, oldest first (shown newest
## first): {id, address, client, type, result ("completed" / "missed" / "cancelled"), time, year,
## pay, rep}. A recurring or city contract adds one entry per visit. Capped at
## balance.contract_history_max. Saved from version 3 (old saves start with an empty history).
var job_history: Array = []
var _next_id := 1
var rival_wins := 0
## Polish 5 §10: the highest tier announced so far (one notification per tier reached).
var tier_noted := 0


func reset_for_new_game() -> void:
	listings = []
	bids = []
	active = []
	history = []
	job_history = []
	_next_id = 1
	rival_wins = 0
	tier_noted = 0


func start_winter() -> void:
	# Recurring contracts expire at winter's end unless renewed (renewals handled in the summary).
	var keep := []
	for c in active:
		if c.get("renewed", false):
			c["renewed"] = false
			c["status"] = "serviced"
			c["visits"] = 0
			c["last_service"] = 0.0
			c["snowed_min"] = 0.0
			c["warned"] = 0
			_clear_due(c)
			keep.append(c)
	active = keep
	bids = []
	listings = []
	tier_noted = maxi(tier_noted, tier_index())
	_generate_listings(0, true)
	changed.emit()


## The board's own stream before polish 5 (kept for the pre-§10 callers' seeds; nothing new draws
## from it).
func _rng_for(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = Game.weather_seed * 131 + Game.year * 7 + salt
	return r


## Polish 5 §10: the listing supply's own seeded stream (one per day of the winter).
func _supply_rng(day: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([Game.weather_seed, Game.year, day, "board"])
	return r


## Polish 5 §10: the rivals' own seeded stream — a pure function of the seed, the winter, the
## listing and what is being decided, so their replies are deterministic whenever they happen.
func _rival_rng(lid: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([Game.weather_seed, Game.year, lid, salt, "rivals"])
	return r


# -----------------------------------------------------------------------------
# Zones (made of clearing boxes)
# -----------------------------------------------------------------------------
#
# A contract zone is a named group of clearing boxes (see Boxes). A zone is done when all of its
# boxes are complete (90 % rule, then the box snaps to bare ground).

static func rect_to_a(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


static func a_to_rect(a: Array) -> Rect2:
	return Rect2(a[0], a[1], a[2], a[3])


func _ready() -> void:
	Boxes.box_completed.connect(_on_box_changed)
	Boxes.box_reopened.connect(_on_box_changed)


func zone_area(z: Dictionary) -> float:
	var a := 0.0
	for ra in z["rects"]:
		a += float(ra[2]) * float(ra[3])
	return a


## Quick estimate used when posting listings (large lots would otherwise stall a frame).
func zone_estimate(z: Dictionary) -> float:
	var res: float = Catalog.balance.contract_residual_depth
	var v := 0.0
	for ra in z["rects"]:
		var r := a_to_rect(ra)
		v += Snow.estimate_volume(r, res, 1 if r.get_area() < 60.0 else 4)
	return v


func zone_required(z: Dictionary) -> float:
	var v := 0.0
	for id in z.get("boxes", []):
		var b := Boxes.get_box(id)
		if not b.is_empty() and not b["complete"]:
			v += Boxes.snow_volume(b, true)
	return v


## Update a zone from its boxes. Returns its progress 0..1.
func measure_zone(_c: Dictionary, z: Dictionary, exact := true) -> float:
	var ids: Array = z.get("boxes", [])
	if ids.is_empty():
		return 1.0
	var sum := 0.0
	var all_done := true
	for id in ids:
		var b := Boxes.get_box(id)
		if b.is_empty():
			continue
		Boxes.measure(b, exact)
		sum += float(b["progress"])
		if not b["complete"]:
			all_done = false
	z["progress"] = 1.0 if all_done else sum / ids.size()
	z["done"] = all_done
	return z["progress"]


func contract_boxes(c: Dictionary) -> Array:
	var out := []
	for z in c["zones"]:
		for id in z.get("boxes", []):
			out.append(id)
	return out


func is_snowed_in(c: Dictionary) -> bool:
	for id in contract_boxes(c):
		if not Boxes.is_complete(id):
			return true
	return false


func _live(c: Dictionary) -> bool:
	var st: String = c["status"]
	return st == "active" or st == "needs_service" or st == "serviced"


# -----------------------------------------------------------------------------
# Polish 5 §10: due times
# -----------------------------------------------------------------------------

## 9:00 p.m. of a winter day (game minutes).
static func due_at_day(day: int) -> float:
	return Clock.at(day, DUE_HOUR)


static func day_of(m: float) -> int:
	return int(floor(m / 1440.0))


## The next 9:00 p.m. strictly after `m` (game minutes).
static func next_9pm(m: float) -> float:
	var t := due_at_day(day_of(m))
	return t if t > m + 1e-6 else t + 1440.0


## When bidding on a listing posted at `posted` closes: 9 p.m. that day if it was posted at least 3
## game hours before, else 9 p.m. the next day.
static func close_for(posted: float) -> float:
	var t := due_at_day(day_of(posted))
	return t if t - posted >= MIN_LEAD_MIN - 1e-6 else t + 1440.0


## Hours left before the job is due (INF when there is no due time: a recurring contract waiting
## for snow, a visit whose snowfall is still falling, Gerry's trail, a finished job).
func hours_left(c: Dictionary) -> float:
	if c.get("tutorial", false) or not _live(c) or c["status"] == "serviced":
		return INF
	var due := float(c.get("due", -1.0))
	if due < 0.0:
		return INF
	return (due - Clock.minutes) / 60.0


## True while a recurring or city visit waits for its snowfall to end before its due time is set.
func due_pending(c: Dictionary) -> bool:
	return _live(c) and c["status"] == "needs_service" and not c.get("tutorial", false) and float(c.get("due", -1.0)) < 0.0


## "9 p.m." for a time of day (game minutes).
static func clock_text(m: float) -> String:
	var hm := fmod(m, 1440.0)
	var h := int(hm / 60.0)
	var mi := int(fmod(hm, 60.0))
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return ("%d" % h12 if mi == 0 else "%d:%02d" % [h12, mi]) + (" a.m." if h < 12 else " p.m.")


## "9 p.m. Tue" for a time (game minutes): the hour, then the weekday.
static func when_text(m: float) -> String:
	return "%s %s" % [clock_text(m), Clock.weekday(day_of(m), Game.year)]


## "9 p.m. today" / "9 p.m. tomorrow" / "9 p.m. Tue" for a time (game minutes), seen from now.
static func when_text_rel(m: float) -> String:
	var dd := day_of(m) - Clock.day_index()
	if dd == 0:
		return clock_text(m) + " today"
	if dd == 1:
		return clock_text(m) + " tomorrow"
	return when_text(m)


## The job's due time in words: "9 p.m. Tue", "after the snow stops" (a visit whose snowfall is
## still falling), or "" when there is none.
func due_text(c: Dictionary) -> String:
	if due_pending(c):
		return "9 p.m. the day after the snow stops"
	var left := hours_left(c)
	if left == INF:
		return ""
	return when_text(float(c["due"]))


func _clear_due(c: Dictionary) -> void:
	c["due"] = -1.0
	c["ext"] = false
	c["warned"] = 0
	c.erase("snow_seen")


## A one-time job (or a recurring contract's first visit) won at `t`: due by 9 p.m. the next day.
func _set_due_after_award(c: Dictionary, t: float) -> void:
	c["due"] = due_at_day(day_of(t) + 1)
	c["ext"] = false
	c["warned"] = 0


## A recurring or city visit falls due: its due time waits for the snow that reopened the boxes
## to stop (the next on_advance sets it).
func _open_visit(c: Dictionary, t: float) -> void:
	c["due"] = -1.0
	c["ext"] = false
	c["warned"] = 0
	c["reopened"] = t
	c["snow_seen"] = t if _snowing_at(t) else -1.0


func _rate_at(m: float) -> float:
	if Weather.override_cond >= 0 and m < Weather.override_until:
		return Weather.override_rate
	if Weather.rate.is_empty():
		return 0.0
	return Weather.rate[clampi(int(m / 60.0), 0, Weather.HOURS - 1)]


func _cond_at(m: float) -> int:
	if Weather.override_cond >= 0 and m < Weather.override_until:
		return Weather.override_cond
	if Weather.cond.is_empty():
		return Weather.C.CLEAR
	return Weather.cond[clampi(int(m / 60.0), 0, Weather.HOURS - 1)]


func _snowing_at(m: float) -> bool:
	return _rate_at(m) > 0.01


## Heavy snow or worse falling at game minute m (the storm rule).
func _storming_at(m: float) -> bool:
	return _cond_at(m) >= Weather.C.HEAVY and _snowing_at(m)


# -----------------------------------------------------------------------------
# Completion, misses, reputation
# -----------------------------------------------------------------------------

func _on_box_changed(id: String) -> void:
	for c in active:
		if not _live(c):
			continue
		if not (id in contract_boxes(c)):
			continue
		_refresh(c)


## Re-evaluate a contract's zones and status after its boxes changed.
func _refresh(c: Dictionary) -> void:
	var all_done := true
	for z in c["zones"]:
		measure_zone(c, z, false)
		if not z["done"]:
			all_done = false
	var st: String = c["status"]
	if c["type"] == "one_time":
		if st == "active" and all_done:
			_finish(c)
	else:
		if all_done and st == "needs_service":
			_finish(c)
		elif not all_done and st == "serviced":
			c["status"] = "needs_service"
			_open_visit(c, Clock.minutes)
			Notify.push("%s needs clearing — new snow on the property." % c["address"], Notify.INFO)
			changed.emit()


## Polish 5 §10: reputation gained for a completed job, scaled with its size (m³) — and harder to
## earn as the company's name grows: above balance.rep_gain_full_below the gain falls off linearly
## towards reputation 100 (never under a tenth of it). A missed job always costs the same.
static func rep_gain(size_m3: float, visit := false, rep := -1.0) -> float:
	var b: BalanceData = Catalog.balance
	var r := Game.reputation if rep < 0.0 else rep
	var g := clampf(b.rep_gain_base + b.rep_gain_per_m3 * maxf(size_m3, 0.0), b.rep_gain_base, b.rep_gain_max)
	var fall := clampf((100.0 - r) / maxf(100.0 - b.rep_gain_full_below, 1.0), 0.1, 1.0)
	return snappedf(g * fall * (b.rep_visit_factor if visit else 1.0), 0.01)


func _finish(c: Dictionary) -> void:
	match c["type"]:
		"one_time":
			var pay: int = c["pay"]
			var g := 2.0 if c.get("tutorial", false) else rep_gain(float(c.get("size", 0.0)))
			c["status"] = "completed"
			_pay(c, pay, "Contract completed")
			Game.stats_add("contracts_completed", 1)
			adjust_reputation(g)
			history.append({"id": c["id"], "address": c["address"], "pay": pay, "time": Clock.minutes})
			record_job(c, "completed", pay, g)
			if c.get("tutorial", false):
				Game.set_stage(Game.Stage.TRAIL_DONE)
		_:
			var g2 := rep_gain(float(c.get("size", 0.0)), true)
			c["status"] = "serviced"
			c["visits"] = int(c.get("visits", 0)) + 1
			c["last_service"] = Clock.minutes
			_pay(c, int(c["pay"]), "Service visit")
			Game.stats_add("visits_completed", 1)
			adjust_reputation(g2)
			record_job(c, "completed", int(c["pay"]), g2)
	c["snowed_min"] = 0.0
	_clear_due(c)
	Notify.push("%s — all clear." % c["address"], Notify.GOOD)
	changed.emit()


## A job still open at its due time: reputation lost, no pay, in the history, back on the board.
func _lose(c: Dictionary) -> void:
	var b: BalanceData = Catalog.balance
	Clock.drop_to_1x("contract")   # polish 5 §9: so does losing it
	c["status"] = "lost"
	adjust_reputation(-b.contract_lost_reputation)
	record_job(c, "missed", 0, -b.contract_lost_reputation)
	Game.stats_add("contracts_lost", 1)
	Game.stats_add("missed_deadlines", 1)
	Notify.push("MISSED: %s wasn't cleared by %s — no pay, %d reputation. It's back on the board." % [c["address"], clock_text(float(c.get("due", Clock.minutes))), -int(b.contract_lost_reputation)], Notify.BAD)
	_relist(c)
	changed.emit()
	Game.dirty_since_save = true


## Polish 5 §7: add a job to the company's history (completed, missed or cancelled), dropping the
## oldest entries past balance.contract_history_max.
func record_job(c: Dictionary, result: String, pay: int, rep: float) -> void:
	job_history.append({"id": int(c.get("id", 0)), "address": str(c.get("address", "")), "client": str(c.get("client", "")),
		"type": str(c.get("type", "one_time")), "result": result, "time": Clock.minutes, "year": Game.year,
		"pay": pay, "rep": snappedf(rep, 0.01)})
	var cap := int(Catalog.balance.contract_history_max)
	if cap > 0 and job_history.size() > cap:
		job_history = job_history.slice(job_history.size() - cap)
	Game.dirty_since_save = true


func _pay(c: Dictionary, amount: int, what: String) -> void:
	Game.add_money(amount)
	Economy.log_tx("%s: %s" % [what, c["address"]], amount)
	Notify.push("Payment received: $%d from %s." % [amount, c["client"]], Notify.GOOD)


## Polish 5 §10: change the reputation and announce a tier once, the first time it is reached.
func adjust_reputation(delta: float) -> void:
	Game.adjust_reputation(delta)
	var t := tier_index()
	if t > tier_noted:
		tier_noted = t
		var names: PackedStringArray = Catalog.balance.rep_tier_names
		Notify.push("%s tier reached (reputation %d): %s contracts are open to you." % [names[t], int(Game.reputation),
			"parking lot" if t == 1 else "street and sidewalk"], Notify.GOOD)


# -----------------------------------------------------------------------------
# Polish 5 §10: tiers
# -----------------------------------------------------------------------------

## The player's tier (0 Residential, 1 Commercial, 2 City) at `rep` (the current reputation if < 0).
func tier_index(rep := -1.0) -> int:
	var r := Game.reputation if rep < 0.0 else rep
	var th: PackedFloat32Array = Catalog.balance.rep_tier_thresholds
	var t := 0
	for i in range(th.size()):
		if r >= th[i] - 1e-6:
			t = i
	return t


func tier_name(i: int) -> String:
	var names: PackedStringArray = Catalog.balance.rep_tier_names
	return names[clampi(i, 0, names.size() - 1)]


func tier_threshold(i: int) -> float:
	var th: PackedFloat32Array = Catalog.balance.rep_tier_thresholds
	return th[clampi(i, 0, th.size() - 1)]


## The tier a listing or contract belongs to (0..2), from its target.
static func target_tier(target: String) -> int:
	if target.begins_with("area:"):
		return 1
	if target.begins_with("road:") or target.begins_with("walk:"):
		return 2
	return 0


func listing_tier(l: Dictionary) -> int:
	return TIERS.find(str(l.get("tier", TIERS[target_tier(str(l.get("target", "")))])))


## Above the player's tier: shown, but nobody can bid on it from here.
func listing_locked(l: Dictionary) -> bool:
	return listing_tier(l) > tier_index()


## Progress to the next tier: {name, need (the reputation it starts at), left, frac}; {} at the top.
func next_tier() -> Dictionary:
	var t := tier_index()
	var th: PackedFloat32Array = Catalog.balance.rep_tier_thresholds
	if t + 1 >= th.size():
		return {}
	var lo := th[t]
	var hi := th[t + 1]
	return {"name": tier_name(t + 1), "need": hi, "left": maxf(hi - Game.reputation, 0.0), "frac": clampf((Game.reputation - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)}


## Share of residential listings that are driveway jobs at the player's reputation.
func driveway_share(rep := -1.0) -> float:
	var b: BalanceData = Catalog.balance
	var r := Game.reputation if rep < 0.0 else rep
	return lerpf(b.driveway_share_rep0, b.driveway_share_commercial, clampf(r / maxf(tier_threshold(1), 0.01), 0.0, 1.0))


func municipal_unlocked() -> bool:
	return tier_index() >= 2


func big_jobs_unlocked() -> bool:
	return tier_index() >= 1


## The largest residential job (m³) the board posts for the player's best equipment: what it
## clears between 7 a.m. and 9 p.m.
func res_cap_m3() -> float:
	return Catalog.balance.listing_res_max_m3 * EQUIP_RATE[equipment_capability()] / EQUIP_RATE[0]


## Active contract zone the player is in or near (for the HUD).
func zone_near(p: Vector2, radius := 6.0) -> Dictionary:
	for c in active:
		if c["status"] != "active" and c["status"] != "needs_service":
			continue
		for z in c["zones"]:
			if z["done"]:
				continue
			for ra in z["rects"]:
				if a_to_rect(ra).grow(radius).has_point(p):
					return {"contract": c, "zone": z}
	return {}


## Contract (if any) that owns a box.
func contract_for_box(id: String) -> Dictionary:
	for c in active:
		if _live(c) and id in contract_boxes(c):
			return c
	return {}


# -----------------------------------------------------------------------------
# Time hooks
# -----------------------------------------------------------------------------

## Heavy snow or worse is falling now.
func storming() -> bool:
	return Weather.condition() >= Weather.C.HEAVY and Weather.is_snowing()


## Every clock step (Clock._systems_advance; fast-forward runs it per substep): the rivals' bids,
## closing at 9 p.m., the award at 9:01 p.m., then the due times — in that order.
func on_advance(step: float) -> void:
	var now := Clock.minutes
	var start := now - step
	_rejump(start, now)
	_rivals_step(now)
	_close_step(now)
	_deadlines_step(start, now)


## A listing still open whose close had already passed before this step began: the clock was set
## past it without running through it (tests and shots set the time directly; play, sleep and the
## F1 jumps always step through 9 p.m.). It is posted again from now, so the board isn't emptied.
func _rejump(start: float, now: float) -> void:
	for l in listings:
		if not bool(l.get("closed", false)) and float(l["closes"]) < start - 1.0:
			l["posted"] = now
			l["closes"] = close_for(now)
			l["outbid_at"] = -1e9
			_plan_rivals(l, now)


func _deadlines_step(start: float, now: float) -> void:
	var b: BalanceData = Catalog.balance
	for c in active:
		if not _live(c) or c.get("tutorial", false):
			continue
		if c["status"] == "serviced":
			continue
		var due := float(c.get("due", -1.0))
		if due < 0.0:
			if c["type"] == "one_time":
				continue
			# A visit: due by 9 p.m. the day after the snowfall that reopened its boxes ends. Its
			# window opens when the boxes reopen, so heavy snow or worse still falling then counts for
			# the storm rule (a day later, once).
			if _snowing_at(start):
				c["snow_seen"] = now
				if _storming_at(start):
					c["ext"] = true
				continue
			var end := float(c.get("snow_seen", -1.0))
			if end < 0.0:
				end = float(c.get("reopened", start))
			c["due"] = due_at_day(day_of(end - 0.001) + 1) + (STORM_EXTENSION_MIN if bool(c.get("ext", false)) else 0.0)
			c["warned"] = 0
			c.erase("snow_seen")
			if bool(c.get("ext", false)):
				Notify.push("Storm: %s is due %s, a day later." % [c["address"], when_text(float(c["due"]))], Notify.INFO)
			changed.emit()
			continue
		if not bool(c.get("ext", false)) and _storming_at(start):
			# Heavy snow or worse inside the job's window: one more day, once per job.
			c["ext"] = true
			c["due"] = due + STORM_EXTENSION_MIN
			c["warned"] = 0
			Notify.push("Storm: %s is now due %s." % [c["address"], when_text(float(c["due"]))], Notify.INFO)
			changed.emit()
			continue
		var left := (due - now) / 60.0
		var warned := int(c.get("warned", 0))
		if now >= due - 1e-6:
			_lose(c)
		elif left <= b.contract_last_warn_hours and warned < 2:
			c["warned"] = 2
			Clock.drop_to_1x("contract")   # polish 5 §9: a contract warning stops fast-forward
			Notify.push("URGENT: %s is due %s — %d h left." % [c["address"], when_text(due), int(ceil(left))], Notify.BAD)
		elif left <= b.contract_warn_hours and warned < 1:
			c["warned"] = 1
			Clock.drop_to_1x("contract")
			Notify.push("%s is due %s — %d h left to clear it." % [c["address"], when_text(due), int(ceil(left))], Notify.WARN)


func on_hour(day: int, hour: int) -> void:
	for c in active:
		if _live(c):
			_refresh(c)
	if hour == 6:
		_generate_listings(day, false)
	changed.emit()


func on_day(_day: int) -> void:
	pass


# -----------------------------------------------------------------------------
# Board / listings
# -----------------------------------------------------------------------------

func _occupied_targets() -> Dictionary:
	var used := {}
	for c in active:
		if _live(c):
			used[str(c["target"])] = true
	for l in listings:
		used[str(l["target"])] = true
	return used


func _client_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [CLIENT_FIRST[rng.randi() % CLIENT_FIRST.size()], CLIENT_LAST[rng.randi() % CLIENT_LAST.size()]]


func _price(volume: float, recurring: bool) -> int:
	var b: BalanceData = Catalog.balance
	var growth := 1.0 + b.contract_value_growth_per_year * (Game.year - 1)
	var v := b.contract_base_fee + b.contract_price_per_m3 * pow(maxf(volume, 0.5), 0.75)
	if recurring:
		v *= b.recurring_visit_factor
	return int(round(v * growth))


## Residential lots a listing can name (not the player's, not Gerry's, not vacant).
static func residential_lots() -> Array:
	var out := []
	for lot in Layout.lots:
		if not (lot["vacant"] or lot["is_player"] or lot["is_neighbor"]):
			out.append(lot)
	return out


## Polish 5 §10: the morning board. Filled up to balance.listings_per_day open listings: commercial
## and city work by their shares (shown locked below their tier), the rest residential — a driveway
## job with driveway_share(), else a path job — on a lot with snow on that box and no job running,
## no bigger than the player's equipment clears in a day (res_cap_m3). From the supply's own stream.
func _generate_listings(day: int, initial: bool) -> void:
	var b: BalanceData = Catalog.balance
	var rng := _supply_rng(day)
	var used := _occupied_targets()
	var want := b.listings_per_day
	var tries := 0
	var cap := res_cap_m3()
	var lots := residential_lots()
	while listings.size() < want and tries < 60:
		tries += 1
		var roll := rng.randf()
		if roll < b.listing_share_city:
			if rng.randf() < 0.5:
				var seg: Dictionary = Layout.road_segments[rng.randi() % Layout.road_segments.size()]
				if used.has("road:" + seg["id"]) or Boxes.is_complete("road_" + str(seg["id"])):
					continue
				_add_municipal_listing(seg, day, rng)
				used["road:" + seg["id"]] = true
			else:
				var sec: String = WALK_SECTIONS[rng.randi() % WALK_SECTIONS.size()]
				if used.has("walk:" + sec):
					continue
				if _add_walk_listing(sec, day, rng).is_empty():
					continue
				used["walk:" + sec] = true
			continue
		if roll < b.listing_share_city + b.listing_share_commercial:
			var areas := [Layout.big_areas[0], Layout.big_areas[1], Layout.big_areas[2]]
			var a: Dictionary = areas[rng.randi() % areas.size()]
			if used.has("area:" + a["id"]) or Boxes.is_complete("area_" + str(a["id"])):
				continue
			_add_area_listing(a, day, rng)
			used["area:" + a["id"]] = true
			continue
		var kind := "driveway" if rng.randf() < driveway_share() else "path"
		var lot: Dictionary = lots[rng.randi() % lots.size()]
		var key := "lot:%d" % lot["index"]
		if used.has(key):
			continue
		# A driveway too big for the day falls back to the same client's path.
		var pick := ""
		for k in ([kind, "path"] if kind == "driveway" else [kind]):
			var bx := Boxes.get_box(Boxes.lot_box(lot, k))
			if bx.is_empty() or bx["complete"]:
				continue
			if _zone_volume_estimate([Boxes.lot_box(lot, k)]) <= cap:
				pick = k
				break
		if pick == "":
			continue
		_add_lot_listing(lot, day, rng, pick)
		used[key] = true
	changed.emit()


func _zone_volume_estimate(box_ids: Array) -> float:
	return zone_estimate(_zone("", box_ids))


func _zone(zone_name: String, box_ids: Array) -> Dictionary:
	var ra := []
	for id in box_ids:
		var b := Boxes.get_box(id)
		for r in b.get("rects", []):
			ra.append(rect_to_a(r))
	return {"name": zone_name, "boxes": box_ids.duplicate(), "rects": ra, "done": false, "progress": 0.0}


## A residential listing: a path job ("path") or a driveway job ("driveway"); "" picks one by
## driveway_share() from `rng`.
func _add_lot_listing(lot: Dictionary, day: int, rng: RandomNumberGenerator, kind := "") -> Dictionary:
	var b: BalanceData = Catalog.balance
	if kind == "":
		kind = "driveway" if rng.randf() < driveway_share() else "path"
	var zones := [_zone("Driveway" if kind == "driveway" else "Path to the house", [Boxes.lot_box(lot, kind)])]
	var recurring := rng.randf() < b.listing_recurring_share and day > 0
	var vol := 0.0
	var area := 0.0
	for z in zones:
		vol += zone_estimate(z)
		area += zone_area(z)
	var est := vol if not recurring else area * 0.07
	var l := {"lid": _next_id, "target": "lot:%d" % lot["index"], "address": lot["address"],
		"client": _client_name(rng), "type": "recurring" if recurring else "one_time", "zones": zones,
		"est_volume": est, "now_volume": vol, "budget": _price(est, recurring), "pos": [lot["center_x"], lot["front_z"]],
		"tier": "residential", "job": kind}
	return _post(l)


func _add_area_listing(a: Dictionary, _day: int, rng: RandomNumberGenerator) -> Dictionary:
	var r: Rect2 = a["rect"]
	var zones := [_zone("Parking lot", ["area_" + str(a["id"])])]
	var recurring := rng.randf() < 0.5
	var vol := zone_estimate(zones[0])
	var est := vol if not recurring else zone_area(zones[0]) * 0.07
	var budget := int(_price(est, recurring) * 1.25)
	var l := {"lid": _next_id, "target": "area:" + a["id"], "address": a["place"], "client": a["name"].split(" parking")[0],
		"type": "recurring" if recurring else "one_time", "zones": zones, "est_volume": est, "now_volume": vol, "budget": budget,
		"pos": [r.get_center().x, r.get_center().y], "large": true, "tier": "commercial", "job": "parking"}
	return _post(l)


func _add_municipal_listing(seg: Dictionary, _day: int, _rng: RandomNumberGenerator) -> Dictionary:
	var zones := [_zone("Road section", ["road_" + str(seg["id"])])]
	var est := zone_area(zones[0]) * 0.06
	var budget := int(_price(est, true) * 1.4)
	var l := {"lid": _next_id, "target": "road:" + seg["id"], "address": seg["name"], "client": "City of Maple Ridge",
		"type": "municipal", "zones": zones, "est_volume": est, "now_volume": zone_estimate(zones[0]), "budget": budget,
		"pos": [seg["rect"].get_center().x, seg["rect"].get_center().y], "segment": seg["id"], "large": true,
		"tier": "city", "job": "street"}
	return _post(l)


static func walk_section_lots(sec: String) -> Array:
	return Layout.walk_section_lots(sec)


static func walk_section_name(sec: String) -> String:
	return Layout.walk_section_name(sec)


## A city sidewalk contract: the section's sidewalk boxes that aren't part of an open residential
## job (Decision 5). {} when every one of them is.
func _add_walk_listing(sec: String, _day: int, _rng: RandomNumberGenerator) -> Dictionary:
	var ids := []
	for lot in walk_section_lots(sec):
		var id := Boxes.lot_box(lot, "sidewalk")
		if Boxes.get_box(id).is_empty() or not contract_for_box(id).is_empty():
			continue
		ids.append(id)
	if ids.is_empty():
		return {}
	var zones := [_zone("Sidewalks", ids)]
	var est := zone_area(zones[0]) * 0.06
	var budget := int(_price(est, true) * 1.4)
	var c0: Vector2 = Vector2.ZERO
	for lot in walk_section_lots(sec):
		c0 += Vector2(lot["center_x"], lot["front_z"])
	c0 /= maxf(walk_section_lots(sec).size(), 1.0)
	var l := {"lid": _next_id, "target": "walk:" + sec, "address": walk_section_name(sec), "client": "City of Maple Ridge",
		"type": "municipal", "zones": zones, "est_volume": est, "now_volume": zone_estimate(zones[0]), "budget": budget,
		"pos": [c0.x, c0.y], "tier": "city", "job": "sidewalk"}
	return _post(l)


## Put a new listing on the board now: when its bidding closes, and the rivals' plan for it.
func _post(l: Dictionary) -> Dictionary:
	_next_id += 1
	var now := Clock.minutes
	l["posted"] = now
	l["closes"] = close_for(now)
	l["bid"] = 0
	l["bid_at"] = -1.0
	l["closed"] = false
	l["outbid_at"] = -1e9
	_plan_rivals(l, now)
	listings.append(l)
	return l


## The rivals who will bid on a listing, when, how much at first, and their floor — all from the
## rivals' own stream for this listing. Near your home or your other clients they ask a little
## more (balance.proximity_bid_bonus): those jobs are easier to win.
func _plan_rivals(l: Dictionary, from_t: float) -> void:
	var b: BalanceData = Catalog.balance
	var lid := int(l["lid"])
	var rng := _rival_rng(lid, 0)
	var s := float(l["budget"])
	var close_t := float(l["closes"])
	var n := clampi(b.rival_count_min + rng.randi() % maxi(b.rival_count_max - b.rival_count_min + 1, 1), 0, RIVALS.size())
	if listing_tier(l) > 0:
		n = mini(n + 1, RIVALS.size())
	var first := rng.randi() % RIVALS.size()
	var span := maxf(close_t - from_t, 1.0)
	var lo := from_t + minf(60.0, span * 0.1)
	var hi := close_t - minf(90.0, span * 0.15)
	var p: Array = l.get("pos", [0, 0])
	var near := near_existing(Vector2(float(p[0]), float(p[1])))
	var out := []
	for k in range(n):
		var ri := (first + k) % RIVALS.size()
		var edge := float(RIVALS[ri]["edge"])
		var amt := s * rng.randf_range(b.rival_open_min, b.rival_open_max) * (1.0 + edge) * (1.0 + (b.proximity_bid_bonus if near else 0.0))
		var at := rng.randf_range(lo, maxf(hi, lo))
		out.append({"r": ri, "at": snappedf(at, 0.001), "open": maxi(int(round(amt)), bid_floor(l)), "bid": 0, "replies": 0, "next": -1.0, "next_step": 0})
	l["rivals"] = out


func listing_by_id(lid: int) -> Dictionary:
	for l in listings:
		if int(l["lid"]) == lid:
			return l
	return {}


## Proximity to existing clients or home (rivals ask more there: easier to win).
func near_existing(pos: Vector2) -> bool:
	var b: BalanceData = Catalog.balance
	var home := Layout.lot_to_world(Layout.player_lot, 0, 10)
	if pos.distance_to(home) < b.proximity_radius:
		return true
	for c in active:
		if not _live(c):
			continue
		var p: Array = c.get("pos", [0, 0])
		if Vector2(p[0], p[1]).distance_to(pos) < b.proximity_radius:
			return true
	return false


## 0 hands/shovel, 1 pushers/sleigh, 2 blowers, 3 vehicles with plow/blower.
func equipment_capability() -> int:
	var cap := 0
	for v in Game.vehicles:
		var vd: VehicleData = Catalog.vehicle(StringName(v["id"]))
		if vd and (vd.has_plow or vd.has_blower):
			cap = 3
	if cap < 3 and (Game.owns_tool("small_blower") or Game.owns_tool("large_blower")):
		cap = 2
	if cap < 2:
		for t in ["wide_pusher", "snow_scraper", "large_scraper", "snow_sleigh", "electric_shovel"]:
			if Game.owns_tool(t):
				cap = 1
	return cap


# -----------------------------------------------------------------------------
# Polish 5 §10: live bidding
# -----------------------------------------------------------------------------

## The lowest bid anyone may make on a listing (balance.bid_floor_frac of the suggested price).
func bid_floor(l: Dictionary) -> int:
	return maxi(1, int(ceil(float(l["budget"]) * Catalog.balance.bid_floor_frac - 1e-6)))


## The lowest rival bid on a listing: {i (index in its rivals, -1 if none), amount, name}.
func _lowest_rival(l: Dictionary) -> Dictionary:
	var best := {"i": -1, "amount": 0, "name": ""}
	var rv: Array = l.get("rivals", [])
	for k in range(rv.size()):
		var a := int(rv[k]["bid"])
		if a > 0 and (best["i"] < 0 or a < int(best["amount"])):
			best = {"i": k, "amount": a, "name": RIVALS[int(rv[k]["r"])]["name"]}
	return best


## Number of bids on a listing now (each rival that has bid, and yours).
func bid_count(l: Dictionary) -> int:
	var n := 1 if int(l.get("bid", 0)) > 0 else 0
	for rv in l.get("rivals", []):
		if int(rv["bid"]) > 0:
			n += 1
	return n


## Your status on a listing: {mine, lowest (the lowest rival bid, 0 if none), winning, text}.
## Ties go to you. text is "Winning", "Outbid · lowest bid $X" or "" (no bid).
func bid_status(l: Dictionary) -> Dictionary:
	var mine := int(l.get("bid", 0))
	var low := int(_lowest_rival(l)["amount"])
	var winning := mine > 0 and (low <= 0 or mine <= low)
	var text := ""
	if mine > 0:
		text = "Winning" if winning else "Outbid · lowest bid $%d" % low
	return {"mine": mine, "lowest": low, "winning": winning, "text": text}


func _sync_bids() -> void:
	bids = []
	for l in listings:
		if int(l.get("bid", 0)) > 0:
			bids.append({"lid": int(l["lid"]), "amount": int(l["bid"]), "at": float(l.get("bid_at", -1.0)), "listing": l})


## Place, raise or lower your bid on a listing (until it closes). Not below the floor, not on a
## locked listing.
func place_bid(lid: int, amount: int) -> Dictionary:
	var l := listing_by_id(lid)
	if l.is_empty():
		return {"ok": false, "msg": "Listing no longer available."}
	if bool(l.get("closed", false)):
		return {"ok": false, "msg": "Bidding has closed on %s." % l["address"]}
	if listing_locked(l):
		return {"ok": false, "msg": "Needs reputation %d." % int(tier_threshold(listing_tier(l)))}
	var fl := bid_floor(l)
	if amount < fl:
		return {"ok": false, "msg": "The lowest bid accepted is $%d." % fl}
	var had := int(l.get("bid", 0))
	if had == amount:
		return {"ok": true, "msg": "Your bid is already $%d." % amount}
	l["bid"] = amount
	l["bid_at"] = Clock.minutes
	_sync_bids()
	_maybe_reply(l, Clock.minutes)
	if had > 0:
		Notify.push("Bid on %s changed to $%d." % [l["address"], amount], Notify.INFO)
	else:
		Notify.push("Bid of $%d placed on %s." % [amount, l["address"]], Notify.INFO)
	changed.emit()
	Game.dirty_since_save = true
	var st := bid_status(l)
	return {"ok": true, "msg": "%s: $%d — %s. Bidding closes %s." % [l["address"], amount, st["text"].to_lower(), when_text_rel(float(l["closes"]))]}


## Withdraw your bid (until bidding closes).
func withdraw_bid(lid: int) -> Dictionary:
	var l := listing_by_id(lid)
	if l.is_empty() or int(l.get("bid", 0)) <= 0:
		return {"ok": false, "msg": "No bid to withdraw."}
	if bool(l.get("closed", false)):
		return {"ok": false, "msg": "Bidding has closed on %s." % l["address"]}
	l["bid"] = 0
	l["bid_at"] = -1.0
	_sync_bids()
	Notify.push("Bid on %s withdrawn." % l["address"], Notify.INFO)
	changed.emit()
	Game.dirty_since_save = true
	return {"ok": true, "msg": "Bid on %s withdrawn." % l["address"]}


## You just took the lead from the rival who had the lowest bid: it may answer (its own stream:
## whether, when and by how much), up to balance.rival_replies_max times per listing.
func _maybe_reply(l: Dictionary, t: float) -> void:
	var b: BalanceData = Catalog.balance
	var lead := _lowest_rival(l)
	var mine := int(l.get("bid", 0))
	if int(lead["i"]) < 0 or mine <= 0 or mine >= int(lead["amount"]):
		return
	var rv: Dictionary = l["rivals"][int(lead["i"])]
	if int(rv["replies"]) >= b.rival_replies_max or float(rv["next"]) >= 0.0:
		return
	var rr := _rival_rng(int(l["lid"]), 100 + int(rv["r"]) * 10 + int(rv["replies"]))
	var go := rr.randf() < b.rival_reply_chance
	var delay := rr.randf_range(30.0, 120.0)
	var step := rr.randf_range(b.rival_reply_step_min, b.rival_reply_step_max)
	if not go:
		rv["replies"] = int(rv["replies"]) + 1
		return
	var at := t + delay
	if at >= float(l["closes"]) - 0.5:
		return
	rv["next"] = snappedf(at, 0.001)
	rv["next_step"] = maxi(1, int(round(float(l["budget"]) * step)))


## A rival's bid lands: if it puts you behind, an "Outbid" notification (unless the board is on
## screen), at most once per listing per game hour.
func _rival_bid(l: Dictionary, k: int, amount: int, t: float) -> void:
	var before := bid_status(l)
	(l["rivals"][k] as Dictionary)["bid"] = amount
	var after := bid_status(l)
	if before["winning"] and not after["winning"] and not _board_showing() and t - float(l.get("outbid_at", -1e9)) >= 60.0 - 1e-6:
		l["outbid_at"] = t
		Notify.push("Outbid on %s — lowest bid $%d." % [l["address"], int(after["lowest"])], Notify.WARN)
	changed.emit()


## The Contract board is on screen (the computer open on it).
func _board_showing() -> bool:
	var w: Object = Game.world
	if w == null or not is_instance_valid(w):
		return false
	var m = w.get("modal")
	return m is ComputerUI and m.current >= 0 and ComputerUI.APP_IDS[m.current] == "board"


## The rivals' bids due by `now`, in time order: first bids at their seeded times, then replies.
func _rivals_step(now: float) -> void:
	for l in listings:
		if bool(l.get("closed", false)):
			continue
		var rv: Array = l.get("rivals", [])
		var due := []
		for k in range(rv.size()):
			if int(rv[k]["bid"]) <= 0 and float(rv[k]["at"]) <= now:
				due.append([float(rv[k]["at"]), k, 0])
			if float(rv[k]["next"]) >= 0.0 and float(rv[k]["next"]) <= now:
				due.append([float(rv[k]["next"]), k, 1])
		if due.is_empty():
			continue
		due.sort()
		for e in due:
			var r: Dictionary = rv[int(e[1])]
			if int(e[2]) == 0:
				_rival_bid(l, int(e[1]), int(r["open"]), float(e[0]))
			else:
				r["next"] = -1.0
				r["replies"] = int(r["replies"]) + 1
				var mine := int(l.get("bid", 0))
				if mine <= 0 or mine >= int(r["bid"]):
					continue
				var amount := maxi(bid_floor(l), mine - int(r["next_step"]))
				if amount >= mine:
					continue   # can't beat your bid without going under its floor (ties go to you)
				_rival_bid(l, int(e[1]), amount, float(e[0]))


## 9:00 p.m.: bidding closes on the listings due to close; 9:01 p.m.: the lowest bid wins.
func _close_step(now: float) -> void:
	var done := []
	for l in listings:
		var ct := float(l["closes"])
		if not bool(l.get("closed", false)) and now >= ct - 1e-6:
			l["closed"] = true
			changed.emit()
		if bool(l.get("closed", false)) and now >= ct + AWARD_DELAY_MIN - 1e-6:
			done.append(l)
	for l in done:
		listings.erase(l)
		_resolve(l)
	if not done.is_empty():
		_sync_bids()
		changed.emit()
		Game.dirty_since_save = true


## The award (9:01 p.m.): the lowest bid wins, a tie goes to you; a notification for each bid of
## yours won or lost.
func _resolve(l: Dictionary) -> void:
	var mine := int(l.get("bid", 0))
	var low := _lowest_rival(l)
	var t_award := float(l["closes"]) + AWARD_DELAY_MIN
	if mine > 0:
		Clock.drop_to_1x("bid")   # polish 5 §9: a bid won or lost stops fast-forward
	if mine > 0 and (int(low["i"]) < 0 or mine <= int(low["amount"])):
		var c := _award(l, mine, t_award)
		var kind := "recurring service" if l["type"] != "one_time" else "one-time job"
		var who := (Game.company_name + " wins ") if Game.company_name != "" else ""
		Notify.push("Bid won! %s%s — %s at $%d, due %s." % [who, l["address"], kind, mine, due_text(c) if due_text(c) != "" else "after the next snowfall"], Notify.GOOD)
	elif mine > 0:
		rival_wins += 1
		Notify.push("Bid lost: %s — %s won at $%d." % [l["address"], low["name"], int(low["amount"])], Notify.WARN)
	elif int(low["i"]) >= 0:
		rival_wins += 1


func _award(l: Dictionary, amount: int, t := -1.0) -> Dictionary:
	if t < 0.0:
		t = Clock.minutes
	var c := {"id": _next_id, "target": l["target"], "address": l["address"], "client": l["client"],
		"type": l["type"], "zones": l["zones"].duplicate(true), "pay": amount, "status": "active", "visits": 0,
		"pos": l["pos"], "accepted": t, "segment": l.get("segment", ""), "snowed_min": 0.0, "warned": 0,
		"tier": l.get("tier", TIERS[target_tier(str(l["target"]))]), "job": l.get("job", ""),
		"size": float(l.get("est_volume", 0.0)), "suggested": int(l.get("budget", amount))}
	_next_id += 1
	if c["type"] != "one_time":
		c["status"] = "needs_service"
	var all_done := true
	for z in c["zones"]:
		measure_zone(c, z, false)
		if not z["done"]:
			all_done = false
	if c["type"] != "one_time" and all_done:
		c["status"] = "serviced"
		_clear_due(c)
	else:
		_set_due_after_award(c, t)
	active.append(c)
	changed.emit()
	Game.dirty_since_save = true
	return c


## Debug / tests: win a listing outright.
func force_award(lid: int, amount := -1) -> Dictionary:
	var l := listing_by_id(lid)
	if l.is_empty():
		return {}
	listings.erase(l)
	_sync_bids()
	return _award(l, amount if amount > 0 else int(l["budget"]))


## A missed job goes back on the board (a fresh listing for the same client), closing at the next
## 9 p.m. or the one after (posted less than 3 h before it).
func _relist(c: Dictionary) -> void:
	if _occupied_targets().has(str(c["target"])):
		return
	var zones := []
	for z in c["zones"]:
		zones.append(_zone(str(z["name"]), z.get("boxes", [])))
	var vol := 0.0
	for z in zones:
		vol += zone_estimate(z)
	var est := vol if c["type"] == "one_time" else float(c.get("size", vol))
	var l := {"lid": _next_id, "target": c["target"], "address": c["address"], "client": c["client"], "type": c["type"],
		"zones": zones, "est_volume": est, "now_volume": vol,
		"budget": _price(est, false) if c["type"] == "one_time" else int(c.get("suggested", c["pay"])),
		"pos": c["pos"], "tier": c.get("tier", TIERS[target_tier(str(c["target"]))]), "job": c.get("job", ""), "relisted": true}
	if str(c.get("segment", "")) != "":
		l["segment"] = c["segment"]
	if target_tier(str(c["target"])) > 0:
		l["large"] = true
	_post(l)


## Tutorial contract created by the neighbor's negotiation: one dynamic box from his porch steps
## down the walk to his mailbox (Layout.gerry_trail_rects). No due time.
func create_tutorial_contract(pay: int) -> Dictionary:
	var lot := Layout.neighbor_lot
	Boxes.add_dynamic("gerry_trail", "path", "Trail to the mailbox", "lot:%d" % lot["index"], Layout.gerry_trail_rects(), lot["address"])
	var zone := _zone("Trail to the mailbox", ["gerry_trail"])
	var c := {"id": _next_id, "target": "lot:%d" % lot["index"], "address": lot["address"], "client": "Gerry (neighbour)",
		"type": "one_time", "zones": [zone], "pay": pay, "status": "active", "visits": 0,
		"pos": [lot["center_x"], lot["front_z"]], "accepted": Clock.minutes, "tutorial": true, "snowed_min": 0.0, "warned": 0,
		"due": -1.0, "ext": false, "tier": "residential", "job": "path", "size": 0.0}
	_next_id += 1
	measure_zone(c, zone)
	active.append(c)
	changed.emit()
	if zone["done"]:
		_refresh(c)
	return c


func contracted_segments() -> Array:
	var out := []
	for c in active:
		if c["type"] == "municipal" and _live(c) and str(c.get("segment", "")) != "":
			out.append(c["segment"])
	return out


func active_count() -> int:
	var n := 0
	for c in active:
		if _live(c):
			n += 1
	return n


## End of winter: recurring contracts expire unless renewed.
func end_winter(renew_ids: Array) -> void:
	for c in active:
		if c["type"] != "one_time" and c["status"] != "lost" and int(c["id"]) in renew_ids:
			c["renewed"] = true
		elif c["status"] != "completed" and c["status"] != "lost":
			c["status"] = "expired"


func serialize() -> Dictionary:
	return {"listings": listings, "active": active, "history": history, "job_history": job_history,
		"next_id": _next_id, "rival_wins": rival_wins, "tier_noted": tier_noted}


func deserialize(d: Dictionary) -> void:
	listings = d.get("listings", [])
	var old_bids: Array = d.get("bids", [])
	active = d.get("active", [])
	history = d.get("history", [])
	# Polish 5 §7 (version 3): optional; old saves start with an empty history.
	job_history = []
	for e in d.get("job_history", []):
		if e is Dictionary:
			job_history.append({"id": int(e.get("id", 0)), "address": Layout.current_place(str(e.get("address", ""))),
				"client": str(e.get("client", "")), "type": str(e.get("type", "one_time")), "result": str(e.get("result", "completed")),
				"time": float(e.get("time", 0.0)), "year": int(e.get("year", 1)), "pay": int(e.get("pay", 0)), "rep": float(e.get("rep", 0.0))})
	_next_id = int(d.get("next_id", 1))
	rival_wins = int(d.get("rival_wins", 0))
	# Polish 5 §10: optional; an old save announces no tier it has already reached.
	tier_noted = int(d.get("tier_noted", tier_index()))
	for c in active:
		c["id"] = int(c["id"])
		c["warned"] = int(c.get("warned", 0))
		c["snowed_min"] = float(c.get("snowed_min", 0.0))
		for z in c["zones"]:
			if not z.has("boxes"):
				z["boxes"] = _migrate_zone_boxes(c, z)
			if c.get("tutorial", false):
				# Polish 3 §4: the trail's rectangles follow the moved mailbox (old saves too).
				var tb := Boxes.get_box("gerry_trail")
				if not tb.is_empty():
					var ra := []
					for r in tb["rects"]:
						ra.append(rect_to_a(r))
					z["rects"] = ra
	for l in listings:
		l["lid"] = int(l["lid"])
		for z in l["zones"]:
			if not z.has("boxes"):
				z["boxes"] = _migrate_zone_boxes(l, z)
	# Polish 5 §10: a pending bid from before live bidding (its listing was taken off the board) goes
	# back on the board with the bid on it.
	for bd in old_bids:
		if bd is Dictionary and bd.get("listing", null) is Dictionary:
			var bl: Dictionary = bd["listing"]
			bl["lid"] = int(bl.get("lid", 0))
			for z in bl.get("zones", []):
				if not z.has("boxes"):
					z["boxes"] = _migrate_zone_boxes(bl, z)
			bl["bid"] = int(bd.get("amount", 0))
			bl["bid_at"] = Clock.minutes
			listings.append(bl)
	# Polish 5 §5: every place is named as the layout names it now (a parking lot saved before §5
	# was "<building> parking lot"; it is "<building>, <address>").
	for c in active + listings:
		var place := Layout.place_name(str(c.get("target", "")))
		if place != "":
			c["address"] = place
	for h in history:
		h["address"] = Layout.current_place(str(h.get("address", "")))
	_migrate_due_times()
	_sync_bids()
	changed.emit()


## Polish 5 §10, old saves (from before due times): an active one-time job is due by 9 p.m. on the
## first day at least 24 game hours after the load; a pending recurring or city visit follows the
## rule from the load (due by 9 p.m. the day after the snow now falling stops); jobs above the
## player's tier are kept; open listings close at the next 9 p.m. (rivals bid until then). New
## keys of a contract or a listing are filled in where missing; nothing else changes.
func _migrate_due_times() -> void:
	var now := Clock.minutes
	for c in active:
		if not c.has("tier"):
			c["tier"] = TIERS[target_tier(str(c.get("target", "")))]
		if not c.has("job"):
			c["job"] = _job_of(c)
		if not c.has("size"):
			# The job's size for its reputation gain: a visit's estimate (as the board prices one), or
			# the snow a one-time job holds now.
			c["size"] = 0.0
			for z in c["zones"]:
				c["size"] = float(c["size"]) + (zone_area(z) * 0.07 if c["type"] != "one_time" else zone_required(z))
		c["ext"] = bool(c.get("ext", false))
		if c.has("due"):
			c["due"] = float(c["due"])
			continue
		c["due"] = -1.0
		if c.get("tutorial", false) or not _live(c):
			continue
		if c["type"] == "one_time" and c["status"] == "active":
			c["due"] = next_9pm(now + 1440.0 - 1e-3)
			c["warned"] = 0
		elif c["status"] == "needs_service":
			_open_visit(c, now)
	for l in listings:
		if not l.has("tier"):
			l["tier"] = TIERS[target_tier(str(l.get("target", "")))]
		if not l.has("job"):
			l["job"] = _job_of(l)
		if not l.has("closes"):
			l["posted"] = now
			l["closes"] = next_9pm(now)
			l["closed"] = false
			l["outbid_at"] = -1e9
			if not l.has("bid"):
				l["bid"] = 0
				l["bid_at"] = -1.0
			_plan_rivals(l, now)
		l["bid"] = int(l.get("bid", 0))
		l["closed"] = bool(l.get("closed", false))
		for rv in l.get("rivals", []):
			rv["r"] = int(rv["r"])
			rv["bid"] = int(rv["bid"])
			rv["open"] = int(rv["open"])
			rv["replies"] = int(rv["replies"])
			rv["next_step"] = int(rv.get("next_step", 0))


## The kind of job a zone list is, for the board: "driveway", "path", "parking", "street",
## "sidewalk".
func _job_of(c: Dictionary) -> String:
	var t := str(c.get("target", ""))
	if t.begins_with("area:"):
		return "parking"
	if t.begins_with("road:"):
		return "street"
	if t.begins_with("walk:"):
		return "sidewalk"
	for z in c.get("zones", []):
		if str(z.get("name", "")).begins_with("Driveway"):
			return "driveway"
	return "path"


## Save version 1 zones were plain rects: map them onto the matching clearing boxes.
func _migrate_zone_boxes(c: Dictionary, z: Dictionary) -> Array:
	var target: String = str(c.get("target", ""))
	var zname: String = str(z.get("name", ""))
	if c.get("tutorial", false):
		var lot := Layout.neighbor_lot
		Boxes.add_dynamic("gerry_trail", "path", "Trail to the mailbox", "lot:%d" % lot["index"], Layout.gerry_trail_rects(), lot["address"])
		return ["gerry_trail"]
	if target.begins_with("lot:"):
		var idx := int(target.substr(4))
		if zname.begins_with("Driveway"):
			return ["lot%d_driveway" % idx]
		if zname.begins_with("Sidewalk"):
			return ["lot%d_sidewalk" % idx]
		return ["lot%d_path" % idx]
	if target.begins_with("area:"):
		return ["area_" + target.substr(5)]
	if target.begins_with("road:"):
		return ["road_" + target.substr(5)]
	return []
