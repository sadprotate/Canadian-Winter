extends RefCounted
## System tests without the 3D world (Parts 30.3–30.5): clock, calendar, weather, snowfall during
## skips, municipal schedule, store orders, contracts (99% rule, recurring visits, bidding),
## survival (warmth, bills, outage timing), saves, winter completion and year scaling.

var runner


func _fresh(mode := "fun", seed_val := 4242) -> void:
	Game.world = null
	Game.player = null
	Clock.running = false
	Municipal.world_handles_passes = false
	Game.new_game(mode, seed_val)
	# The player starts in their bedroom (Survival cold is on from the first minute outdoors).
	Survival.in_player_house = true


func test_time_scale_and_calendar() -> void:
	_fresh()
	runner.near(Clock.GAME_MIN_PER_REAL_SEC * 60.0, 24.0, 1e-6, "1 real minute = 24 game minutes")
	runner.near(Clock.GAME_MIN_PER_REAL_SEC * 3600.0, 1440.0, 1e-6, "1 real hour = 1 game day")
	runner.check(Clock.DAYS_IN_WINTER == 121, "Winter is 121 days (Dec 1 – Mar 31)")
	runner.check(Clock.date_string(0) == "December 1", "Day 0 is December 1")
	runner.check(Clock.date_string(31) == "January 1", "Day 31 is January 1")
	runner.check(Clock.date_string(62) == "February 1", "Day 62 is February 1")
	runner.check(Clock.date_string(90) == "March 1", "Day 90 is March 1")
	runner.check(Clock.date_string(120) == "March 31", "Day 120 is March 31")
	var start := Clock.minutes
	Clock.advance(90.0)
	runner.near(Clock.minutes - start, 90.0, 1e-4, "advance moves the clock")


func test_weather_schedule_shape() -> void:
	_fresh()
	var b: BalanceData = Catalog.balance
	var n := Weather.events.size()
	runner.info("year 1: %d snowfall events, %.0f cm total, tiers %s" % [n, Weather.total_snow_cm, str(Weather.tier_counts())])
	runner.check(absi(n - b.snow_events_year1) <= 3, "About %d snowfall events in the first winter (%d)" % [b.snow_events_year1, n])
	var counts := [0, 0, 0, 0, 0, 0]
	for ev in Weather.events:
		counts[int(ev["cond"])] += 1
	runner.check(counts[2] + counts[3] > counts[4] + counts[5], "Most events are light (%s)" % str(counts))
	runner.check(counts[4] >= 2, "The first winter has storms (%d)" % counts[4])
	# Runs of 3+ consecutive snow-free days exist.
	var best_run := 0
	var run := 0
	for day in range(121):
		var any := false
		for h in range(day * 24, day * 24 + 24):
			if Weather.rate[h] > 0.01:
				any = true
		run = 0 if any else run + 1
		best_run = maxi(best_run, run)
	runner.check(best_run >= 3, "Runs of 3+ good days exist (longest %d)" % best_run)
	# Multi-day storms: some events chained with < 4 h gaps.
	var chained := 0
	for i in range(1, Weather.events.size()):
		if float(Weather.events[i]["start"]) - float(Weather.events[i - 1]["end"]) < 4.0:
			chained += 1
	runner.check(chained >= 1, "Multi-day storm systems occur (%d chained)" % chained)
	var tmin := 99.0
	var tmax := -99.0
	for t in Weather.temp:
		tmin = minf(tmin, t)
		tmax = maxf(tmax, t)
	runner.check(tmin >= -32.5 and tmin < -20.0, "Cold snaps reach well below -20 °C (min %.1f)" % tmin)
	runner.check(tmax <= 3.5, "Mild days stay near freezing (max %.1f)" % tmax)
	var fc := Weather.forecast(3)
	runner.check(fc.size() == 3, "Forecast returns entries")


func test_surprise_storms_and_alerts() -> void:
	_fresh()
	var surprises := 0
	for ev in Weather.events:
		if ev["surprise"]:
			surprises += 1
	runner.check(surprises >= 1, "Some storms arrive stronger than forecast (%d)" % surprises)
	var alerts := [0]
	var cb := func(_t): alerts[0] += 1
	Weather.alert_issued.connect(cb)
	Clock.skip(40 * 1440.0)
	Weather.alert_issued.disconnect(cb)
	runner.check(alerts[0] >= 1, "Severe-weather alerts were issued (%d)" % alerts[0])


func test_snowfall_skip_matches_realtime() -> void:
	_fresh("fun", 99)
	Clock.reset(Clock.at(1, 0.0))
	var f0 := Snow.fall_total
	# Real-time style: many small steps.
	for i in range(2 * 1440 * 2):
		Clock.advance(0.5)
	var real_fall := Snow.fall_total - f0
	_fresh("fun", 99)
	Clock.reset(Clock.at(1, 0.0))
	var f1 := Snow.fall_total
	Clock.skip(2 * 1440.0)
	var skip_fall := Snow.fall_total - f1
	runner.info("snowfall over 2 days: real-time %.4f m, skip %.4f m" % [real_fall, skip_fall])
	runner.near(skip_fall, real_fall, 1e-4, "Time skip accumulates exactly the same snowfall")
	# The snow sim actually gains that depth in an untouched lawn cell.
	_fresh("fun", 99)
	Clock.reset(Clock.at(1, 0.0))
	var p := Layout.lot_to_world(Layout.lots[3], -10.0, 20.0)
	var d0 := Snow.depth_at(p.x, p.y)
	Clock.skip(4 * 1440.0)
	var d1 := Snow.depth_at(p.x, p.y)
	runner.check(d1 > d0 - 0.05 or Snow.fall_total < 0.01, "Snow accumulates during sleep (%.3f -> %.3f, fell %.3f)" % [d0, d1, Snow.fall_total])


func test_municipal_schedule_every_3_to_4_days() -> void:
	_fresh("fun", 7)
	var times := []
	var cb := func(): times.append(Clock.minutes)
	Municipal.pass_finished.connect(cb)
	var road := Rect2(20, 79, 40, 8)
	Clock.skip(1.9 * 1440.0)
	var road_before := Snow.volume_in_rect(road)
	Clock.skip(30.0 * 1440.0)
	Municipal.pass_finished.disconnect(cb)
	runner.check(times.size() >= 7, "Grader passes during a 32-day skip (%d)" % times.size())
	if times.is_empty():
		return
	var first_day := int(times[0] / 1440.0)
	runner.check(first_day == 2 or first_day == 3, "First pass on Dec 3 or 4 (day index %d)" % first_day)
	for i in range(1, times.size()):
		var gap: float = (times[i] - times[i - 1]) / 1440.0
		runner.check(gap > 2.9 and gap < 4.1, "Pass interval is 3–4 days (%.2f)" % gap)
	runner.info("grader passes at days: %s" % str(times.map(func(t): return snappedf(t / 1440.0, 0.01))))
	runner.check(Snow.volume_in_rect(road) < road_before, "Road snow reduced by the grader")


func test_grader_windrow_blocks_driveways() -> void:
	_fresh("fun", 7)
	var hi := Layout.house_info(Layout.lots[8])   # row B house (south of Maple St)
	var apron: Rect2 = hi["driveway"]
	var apron_edge := Rect2(apron.position.x, 87.0, apron.size.x, 1.5)
	Snow.set_rect(apron_edge, 0.0)
	var before := Snow.volume_in_rect(apron_edge)
	Municipal.run_batch(Municipal.route_lanes())
	var after := Snow.volume_in_rect(apron_edge)
	runner.check(after > before + 0.2, "The grader leaves a windrow across the driveway entrance (%.2f m3)" % after)


func test_store_orders_and_hours() -> void:
	_fresh()
	Game.money = 5000
	Clock.reset(Clock.at(2, 10.0))
	var r := Economy.buy("standard_shovel")
	runner.check(r["ok"], "Buying a shovel works during store hours")
	runner.check(Game.money == 5000 - Catalog.tool(&"standard_shovel").price, "Money decreased by the price")
	var o: Dictionary = Economy.orders[Economy.orders.size() - 1]
	runner.check(o["status"] == "ready", "Order placed during store hours is ready immediately")
	Clock.reset(Clock.at(2, 22.5))
	Economy.buy("wide_pusher")
	var o2: Dictionary = Economy.orders[Economy.orders.size() - 1]
	runner.check(o2["status"] == "pending", "Order placed after hours waits")
	runner.near(o2["ready_at"], Clock.at(3, 7.0), 0.01, "…until 7:00 the next morning")
	Clock.skip(Clock.at(3, 6.5) - Clock.minutes)
	runner.check(o2["status"] == "pending", "Still pending at 6:30")
	Clock.skip(60.0)
	runner.check(o2["status"] == "ready", "Ready at 7:00")
	Game.money = 10
	var r3 := Economy.buy("small_blower")
	runner.check(not r3["ok"], "Cannot buy without enough money")
	var r4 := Economy.buy("weather_pro")
	runner.check(not r4["ok"], "Upgrade blocked without money")


func _clear_zone(z: Dictionary) -> void:
	# Real snow removal: scoop the zone cell rows with a shovel-sized footprint and throw the
	# snow onto the adjacent lawn (conserving volume), as a player would.
	for ra in z["rects"]:
		var r := Contracts.a_to_rect(ra)
		var y := r.position.y - 0.2
		while y < r.end.y + 0.1:
			var x := r.position.x
			while x < r.end.x + 0.26:
				var got: Dictionary = Snow.scoop(Vector2(x, y), Vector2(0, 1), 0.5, 0.25, 0.3, 0.0)
				if got["volume"] > 0.0:
					Snow.deposit(Vector2(r.end.x + 3.0, y), got["volume"], 0.6)
				x += 0.5
			y += 0.25


func test_contract_box_rule_and_payment() -> void:
	_fresh()
	Contracts._add_lot_listing(Layout.lots[2], 0, RandomNumberGenerator.new())
	var l: Dictionary = Contracts.listings[Contracts.listings.size() - 1]
	l["type"] = "one_time"
	var c := Contracts.force_award(int(l["lid"]))
	runner.check(not c.is_empty() and c["status"] == "active", "Contract won and active")
	var money0 := Game.money
	var z: Dictionary = c["zones"][0]
	runner.check(not (z["boxes"] as Array).is_empty(), "Contract zone is made of clearing boxes (%s)" % str(z["boxes"]))
	var req0 := Contracts.zone_required(z)
	runner.check(req0 > 0.05, "Zone starts with snow to remove (%.2f m3)" % req0)
	# Clear ~half: progress reflects it, not complete.
	var r0 := Contracts.a_to_rect(z["rects"][0])
	var half := Rect2(r0.position, Vector2(r0.size.x, r0.size.y * 0.5))
	var hz := {"rects": [Contracts.rect_to_a(half)]}
	_clear_zone(hz)
	Contracts.measure_zone(c, z)
	runner.check(z["progress"] > 0.2 and not z["done"], "Partial progress measured live (%.2f)" % z["progress"])
	# Snowfall during the job lowers progress.
	var p_before: float = z["progress"]
	Snow.add_snowfall(0.03)
	Contracts.measure_zone(c, z)
	runner.check(z["progress"] < p_before, "Snowfall lowers progress (%.2f -> %.2f)" % [p_before, z["progress"]])
	for zz in c["zones"]:
		_clear_zone(zz)
		Contracts.measure_zone(c, zz)
	for zz in c["zones"]:
		runner.check(zz["done"], "Zone '%s' complete at >= 90%%" % zz["name"])
		runner.check(Contracts.zone_required(zz) < 0.0005, "Zone left visually clean")
	runner.check(c["status"] == "completed", "One-time contract completed")
	runner.check(Game.money == money0 + int(c["pay"]), "Payment awarded (%d -> %d)" % [money0, Game.money])

## Leave `frac` of a box's peak snow in one corner (the rest cleared for real), then measure.
func _leave_fraction(b: Dictionary, frac: float) -> void:
	var r: Rect2 = b["rects"][0]
	var peak := Boxes.snow_volume(b, true)
	b["peak"] = peak
	for rr in b["rects"]:
		_clear_zone({"rects": [Contracts.rect_to_a(rr)]})
	var corner := Rect2(r.position + Vector2(0.5, 0.5), Vector2(1.0, 1.0))
	Snow.set_rect(corner, 0.0)
	var want := peak * frac
	# Pile the residual as a uniform layer over the corner (the 1 cm residual depth doesn't count).
	var res: float = Catalog.balance.contract_residual_depth
	Snow.add_layer_rect(corner, want / corner.get_area() + res)
	b["peak"] = peak


## Polish 3 §5: the completion rule is 90 % (was 98 %). For every kind of box: 89 % cleared stays
## open with its snow left alone, 90 % completes, snaps to bare ground and keeps clean edges.
func test_box_90_percent_snap() -> void:
	_fresh()
	var lot: Dictionary = Layout.lots[4]
	Contracts.create_tutorial_contract(50)      # Gerry's trail is a box too
	var street := ""
	var parking := ""
	for bb in Boxes.boxes:
		if street == "" and bb["kind"] == "street":
			street = bb["id"]
		if parking == "" and bb["kind"] == "parking":
			parking = bb["id"]
	var cases := {"path": Boxes.lot_box(lot, "path"), "driveway": Boxes.lot_box(lot, "driveway"),
		"sidewalk": Boxes.lot_box(lot, "sidewalk"), "street": street, "parking lot": parking, "Gerry's trail": "gerry_trail"}
	runner.check(is_equal_approx(Catalog.balance.box_completion, 0.90), "box_completion is 90 %% (%.2f)" % Catalog.balance.box_completion)
	var res: float = Catalog.balance.contract_residual_depth
	for kind in cases.keys():
		var b := Boxes.get_box(cases[kind])
		if not runner.check(not b.is_empty(), "%s: box exists" % kind):
			continue
		var peak := Boxes.snow_volume(b, true)
		runner.check(peak > 0.05, "%s: starts with snow (%.2f m3)" % [kind, peak])
		var r0: Rect2 = b["rects"][0]
		# Leave a uniform layer holding `frac` of the peak over the box's first rect, the rest cleared.
		for frac in [0.11, 0.099]:
			for rr in b["rects"]:
				Snow.set_rect(rr, 0.0)
			# The rect's cells cover a little more or less than its exact area: find the effective area.
			Snow.add_layer_rect(r0, 0.1 + res)
			var ae := Boxes.snow_volume(b, true) / 0.1
			Snow.set_rect(r0, 0.0)
			Snow.add_layer_rect(r0, peak * frac / ae + res)
			b["peak"] = peak
			var outside0 := Snow.total_volume() - _box_vol(b)
			Boxes.measure(b, true)
			if frac > 0.1:
				runner.check(not b["complete"], "%s: 89%% cleared stays open (%.3f)" % [kind, b["progress"]])
				runner.check(_box_vol(b) > 0.0005, "%s: …and its snow is left alone" % kind)
			else:
				runner.check(b["complete"], "%s: 90%% cleared completes (%.3f)" % [kind, b["progress"]])
				runner.check(_box_vol(b) < 1e-5, "%s: the last 10%% is removed — bare ground" % kind)
				runner.check(absf(Snow.total_volume() - outside0) < 0.002, "%s: snow outside the box untouched" % kind)
				Snow.relax_until_stable()
				runner.check(_box_vol(b) < 1e-5, "%s: keeps clean edges after relaxation" % kind)


func _box_vol(b: Dictionary) -> float:
	# Unique cells only: a box's rects may overlap (Gerry's trail and its connector).
	var seen := {}
	var v := 0.0
	for r in b["rects"]:
		var c: Rect2i = Snow._rect_cells(r)
		for z in range(c.position.y, c.end.y):
			for x in range(c.position.x, c.end.x):
				var idx := z * Snow.W + x
				if not seen.has(idx):
					seen[idx] = true
					v += Snow.depth[idx] * Snow.CELL_AREA
	return v


## A street (sampled box) completes at an exact 90 % through the sampling path: the sample alone
## never completes it, the switch to exact counting happens early enough, and a residual the
## sample overrates (a strip along one sampled row) can't leave it stuck below the threshold.
func test_street_completes_at_exact_90_through_sampling() -> void:
	_fresh()
	var b: Dictionary = {}
	for bb in Boxes.boxes:
		if bb["kind"] == "street" and bb["big"]:
			b = bb
			break
	if not runner.check(not b.is_empty(), "a sampled street box exists"):
		return
	var r: Rect2 = b["rects"][0]
	var res: float = Catalog.balance.contract_residual_depth
	var t0 := Time.get_ticks_usec()
	var peak := Boxes.snow_volume(b, true)
	runner.info("exact count of %s (%.0f m2): %.2f ms" % [b["id"], b["area"], (Time.get_ticks_usec() - t0) / 1000.0])
	runner.check(peak > 1.0, "the street starts snowy (%.1f m3)" % peak)
	# Background (estimate-only) measurement never completes a big box.
	Snow.set_rect(r, 0.0)
	Snow.add_layer_rect(r, peak * 0.05 / r.get_area() + res)
	b["peak"] = peak
	Boxes.measure(b, false)
	runner.check(not b["complete"], "an estimate alone never completes a street (est. %.3f)" % b["progress"])
	Boxes.measure(b, true)
	runner.check(b["complete"], "the exact count completes it at >= 90 %%")
	# 89.5 % cleared exactly: stays open.
	Boxes._reopen(b)
	Snow.set_rect(r, 0.0)
	Snow.add_layer_rect(r, peak * 0.105 / r.get_area() + res)
	b["peak"] = peak
	Boxes.measure(b, true)
	runner.check(not b["complete"] and b["progress"] > 0.885 and b["progress"] < 0.9, "89.5 %% cleared: open (%.4f)" % b["progress"])
	# The rest as a narrow strip on one sampled row (the sample counts it about 4×): exactly 90.5 %.
	Snow.set_rect(r, 0.0)
	var c0 := Snow.cell_z(r.position.y) + 4
	var strip := Rect2(r.position.x, c0 * Snow.CELL, r.size.x, Snow.CELL)
	Snow.add_layer_rect(strip, peak * 0.095 / strip.get_area() + res)
	b["peak"] = peak
	var est := 1.0 - Boxes.snow_volume(b, false) / peak
	runner.info("strip residual: exact 90.5 %%, sample says %.1f %%" % (est * 100.0))
	var done := false
	for k in range(4):
		Boxes.measure(b, true)
		if b["complete"]:
			done = true
			break
		b.erase("_exact_at")
	runner.check(done, "…and a residual the sample overrates still completes (no getting stuck)")


func test_recurring_contract_visits() -> void:
	_fresh()
	Contracts._add_lot_listing(Layout.lots[5], 0, RandomNumberGenerator.new())
	var l: Dictionary = Contracts.listings[Contracts.listings.size() - 1]
	l["zones"] = [Contracts._zone("Driveway", [Boxes.lot_box(Layout.lots[5], "driveway")])]
	l["type"] = "recurring"
	var c := Contracts.force_award(int(l["lid"]))
	runner.check(c["status"] == "needs_service", "Recurring contract needs a first visit")
	var money0 := Game.money
	for z in c["zones"]:
		_clear_zone(z)
		Contracts.measure_zone(c, z)
	runner.check(c["status"] == "serviced" and c["visits"] == 1, "Visit completed")
	runner.check(Game.money > money0, "Visit paid")
	# A dusting below the reopen depth: no new visit.
	Snow.add_snowfall(0.01)
	Contracts.on_hour(Clock.day_index(), 10)
	runner.check(c["status"] == "serviced", "A dusting doesn't reopen the driveway")
	Snow.add_snowfall(0.03)
	Contracts.on_hour(Clock.day_index(), 11)
	runner.check(c["status"] == "needs_service", "New snow reopens the box: a new visit is needed")
	var money1 := Game.money
	for z in c["zones"]:
		_clear_zone(z)
		Contracts.measure_zone(c, z)
	runner.check(c["visits"] == 2 and Game.money > money1, "Second visit completed and paid")

func test_bidding_resolves() -> void:
	_fresh()
	var won := 0
	var lost := 0
	for k in range(4):
		if Contracts.listings.is_empty():
			Contracts._generate_listings(Clock.day_index(), false)
		var l: Dictionary = Contracts.listings[0]
		var amount := int(l["budget"] * (0.7 if k % 2 == 0 else 1.35))
		Contracts.place_bid(int(l["lid"]), amount)
	runner.check(Contracts.bids.size() == 4, "Bids pending")
	var act0 := Contracts.active.size()
	var rw0 := Contracts.rival_wins
	Clock.skip(4 * 60.0)
	won = Contracts.active.size() - act0
	lost = Contracts.rival_wins - rw0
	runner.check(Contracts.bids.is_empty(), "All bids resolved within a few hours")
	runner.check(won + lost == 4, "Each bid either won or lost (%d won, %d lost)" % [won, lost])
	runner.check(lost >= 1, "Overpriced bids can lose to rivals")


func test_contract_value_growth() -> void:
	_fresh()
	Game.year = 1
	var p1 := Contracts._price(2.0, false)
	Game.year = 4
	var p4 := Contracts._price(2.0, false)
	Game.year = 1
	runner.check(p4 > p1 and p4 < p1 * 1.4, "Contract values rise modestly per year (%d -> %d)" % [p1, p4])
	runner.check(p1 >= 25 and p1 <= 90, "Early driveway contract in the $30–80 range (%d)" % p1)


func test_cold_from_minute_one() -> void:
	_fresh("survival")
	runner.check(Survival.enabled(), "Survival Mode: the cold is on from the very start")
	Survival.in_player_house = false
	Weather.force(Weather.C.CLEAR, 10.0)
	Clock.advance(30.0)
	runner.check(Survival.warmth < 100.0, "Cooling from the first minutes outdoors (%.2f)" % Survival.warmth)
	Weather.override_cond = -1
	Survival.in_player_house = true
	_fresh("fun")
	Survival.in_player_house = false
	Weather.force(Weather.C.BLIZZARD, 10.0)
	Clock.advance(120.0)
	Weather.override_cond = -1
	runner.near(Survival.warmth, 100.0, 0.001, "Fun Mode: no warmth loss at all, even in a blizzard")
	runner.check(not Survival.enabled(), "Fun Mode never enables the cold")

func test_warmth_rates() -> void:
	_fresh("survival")
	Survival.in_player_house = false
	Survival.vehicle_heat = 0.0
	Weather.force(Weather.C.CLEAR, 100.0)
	var h := Weather._hidx()
	# Early December is mild: around -3 °C with a light breeze.
	Weather.temp[h] = -3.0
	Weather.temp[h + 1] = -3.0
	Weather.wind[h] = 10.0
	var mild := Survival.outdoor_loss_per_hour()
	# A normal mid-winter day: -10 °C with a 15 km/h breeze.
	Weather.temp[h] = -10.0
	Weather.temp[h + 1] = -10.0
	Weather.wind[h] = 15.0
	var normal := Survival.outdoor_loss_per_hour()
	Weather.force(Weather.C.BLIZZARD, 100.0)
	var bliz := Survival.outdoor_loss_per_hour()
	Weather.override_cond = -1
	runner.info("loss/h mild %.1f (%.1f h), normal %.1f (to cold in %.1f h), blizzard %.1f (%.0f min)" % [mild, 70.0 / mild, normal, 70.0 / normal, bliz, 70.0 / bliz * 60.0])
	runner.check(mild < 6.0, "Mild early-December weather barely matters (%.1f %%/h)" % mild)
	runner.check(70.0 / normal > 2.5 and 70.0 / normal < 5.0, "Normal weather (-10 °C): 3–4 game hours of outdoor work before needing heat")
	Weather.temp[h] = -26.0
	Weather.temp[h + 1] = -26.0
	Weather.wind[h] = 30.0
	var vcold := Survival.outdoor_loss_per_hour()
	runner.check(70.0 / vcold > 1.0 and 70.0 / vcold < 2.6, "Very cold & windy: ~1.5–2 game hours (%.1f)" % (70.0 / vcold))
	runner.check(70.0 / bliz < 1.1 and 70.0 / bliz > 0.3, "Blizzard: 20–60 minutes before dangerous")
	runner.check(mild < normal and normal < vcold, "Colder and windier weather costs more warmth")
	Survival.warmth = 25.0
	Survival.in_player_house = true
	Survival.house_heat = 1.0
	var t := 0.0
	while Survival.warmth < 70.0 and t < 120.0:
		Clock.advance(1.0)
		t += 1.0
	runner.check(t <= 20.0, "Warming up indoors: cold to comfortable in ~10–15 game minutes (%.0f)" % t)

func test_bill_cutoff_exactly_midnight_16th() -> void:
	_fresh("survival")
	runner.check(Economy.bills.size() == 1 and Economy.bills[0]["amount"] == 85, "December bill of $85 issued")
	runner.check(int(Economy.bills[0]["due_day"]) == 14, "Due December 15")
	Clock.skip(Clock.at(14, 23.98) - Clock.minutes)
	runner.check(Survival.power_on, "Power still on at 23:58 on the 15th")
	Clock.skip(2.0)
	runner.check(not Survival.power_on, "Power cut at midnight into the 16th")
	runner.near(Survival.outage_start, Clock.at(15, 0.0), 0.01, "Outage starts exactly at midnight")
	Clock.skip(Clock.at(15, 12.0) - Clock.minutes)
	runner.check(Survival.house_heat > 0.4 and Survival.house_heat < 0.6, "House half-cooled at noon on the 16th (%.2f)" % Survival.house_heat)
	Clock.skip(Clock.at(16, 0.0) - Clock.minutes + 1.0)
	runner.near(Survival.house_heat, 0.0, 0.001, "No stored heat left by midnight into the 17th")
	var money0 := Game.money
	Game.money = 200
	var r := Economy.pay_bill(0)
	runner.check(r["ok"], "Overdue bill can be paid (computer on battery backup)")
	runner.check(Game.money == 200 - 85, "No reconnection fee")
	runner.check(Survival.power_on, "Paying restores power immediately")
	Clock.advance(30.0)
	runner.check(Survival.house_heat > 0.3, "House warms back up")
	Game.money = money0


func test_bill_cutoff_during_multiday_skip() -> void:
	_fresh("survival")
	Clock.skip(Clock.at(9, 7.0) - Clock.minutes)
	Clock.skip(10 * 1440.0)
	runner.check(not Survival.power_on, "Unpaid bill cut power during a multi-day sleep")
	runner.near(Survival.outage_start, Clock.at(15, 0.0), 0.01, "…exactly at midnight into the 16th")
	runner.check(Economy.bills.size() == 1, "January bill not yet issued on Dec 19")
	# Paid bill: no cutoff in January.
	Game.money = 1000
	Economy.pay_bill(0)
	Clock.skip(Clock.at(31, 8.0) - Clock.minutes)
	runner.check(Economy.bills.size() == 2, "January bill issued on January 1")
	Economy.pay_bill(1)
	Clock.skip(Clock.at(47, 6.0) - Clock.minutes)
	runner.check(Survival.power_on, "Paid January bill: power stays on past Jan 16")


func test_freezing_at_home_without_heat_interrupts_sleep() -> void:
	_fresh("survival")
	Survival.activate()
	Survival.cut_power()
	Survival.outage_start = Clock.minutes - 1440.0
	Survival.in_player_house = true
	Survival.warmth = 100.0
	Clock.skip(2 * 1440.0)
	runner.check(Clock.interrupt_reason == "cold" or Survival.warmth < 30.0, "Sleeping in an unheated house wakes you up freezing")
	Clock.interrupt_reason = ""
	Survival.in_player_house = false


func test_freezing_death() -> void:
	_fresh("survival")
	Survival.activate()
	Survival.in_player_house = false
	Survival.warmth = 2.0
	var died := [false]
	var cb := func(): died[0] = true
	Survival.died.connect(cb)
	Weather.force(Weather.C.BLIZZARD, 10.0)
	Clock.advance(30.0)
	Survival.died.disconnect(cb)
	Weather.override_cond = -1
	runner.check(died[0] and Survival.dead, "Freezing death triggers")
	Survival.dead = false
	Survival.warmth = 100.0


func test_fun_mode_has_no_survival() -> void:
	_fresh("fun")
	Survival.activate()
	Survival.in_player_house = false
	Weather.force(Weather.C.BLIZZARD, 10.0)
	Clock.advance(240.0)
	Weather.override_cond = -1
	runner.near(Survival.warmth, 100.0, 0.001, "Fun mode: no warmth loss")
	runner.check(Economy.bills.is_empty(), "Fun mode: no hydro bills")
	Clock.skip(Clock.at(17, 8.0) - Clock.minutes)
	runner.check(Survival.power_on, "Fun mode: no heating failure")


func test_save_load_roundtrip() -> void:
	_fresh("survival", 555)
	Survival.activate()
	Game.money = 1234
	Game.slots = ["small_shovel", "", "wide_pusher", ""]
	Game.items.append({"uid": Game.uid(), "tool": "standard_shovel", "pos": Vector3(10, 0, 20), "yaw": 0.3})
	Clock.skip(Clock.at(3, 15.5) - Clock.minutes)
	var p := Layout.lot_to_world(Layout.player_lot, -6, 6)
	var got: Dictionary = Snow.scoop(p, Vector2(0, 1), 0.5, 0.5, 0.05)
	Snow.deposit(p + Vector2(-4, 0), got["volume"], 0.5)
	Snow.relax_until_stable()
	Economy.buy("standard_shovel")
	var c := Contracts.force_award(int(Contracts.listings[0]["lid"]))
	runner.check(Saves.save_game(), "Save written")
	var depth_copy := Snow.depth.duplicate()
	var clock_copy := Clock.minutes
	var passes := Municipal.next_pass
	# Scramble everything, then load.
	_fresh("fun", 1)
	Snow.clear_all()
	runner.check(Saves.load_game("survival"), "Save loaded")
	runner.check(Game.mode == "survival" and Game.money == 1234 - Catalog.tool(&"standard_shovel").price, "Money and mode restored")
	runner.check(Game.slots[0] == "small_shovel" and Game.slots[2] == "wide_pusher", "Tool slots restored")
	runner.near(Clock.minutes, clock_copy, 0.001, "Clock restored")
	runner.near(Municipal.next_pass, passes, 0.001, "Municipal schedule restored")
	runner.check(Survival.active, "Survival state restored")
	runner.check(Economy.orders.size() >= 1, "Store orders restored")
	var found := false
	for cc in Contracts.active:
		if int(cc["id"]) == int(c["id"]):
			found = true
	runner.check(found, "Active contract restored")
	Snow.sync_all()
	var maxdiff := 0.0
	for i in range(0, Snow.depth.size(), 7):
		maxdiff = maxf(maxdiff, absf(Snow.depth[i] - depth_copy[i]))
	runner.check(maxdiff < 1e-6, "Snow restored exactly (max diff %.7f)" % maxdiff)
	var info := Saves.peek("survival")
	runner.check(int(info.get("year", 0)) == 1, "Menu peek works")


func test_invalid_save_never_crashes() -> void:
	var path := Saves.path_for("fun")
	DirAccess.make_dir_recursive_absolute(Saves.DIR)
	for p in [path, path + ".bak"]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("{this is not json")
		f.close()
	runner.check(Saves.peek("fun").is_empty(), "Corrupt save is reported as no save")
	runner.check(not Saves.load_game("fun"), "Loading a corrupt save fails gracefully")
	Saves.delete_save("fun")
	runner.check(not Saves.has_save("fun"), "Missing save handled")


func test_winter_end_and_next_year() -> void:
	_fresh("fun", 31)
	Game.money = 777
	Game.vehicles.append({"uid": Game.uid(), "id": "atv_blade", "pos": Vector3(120, 0, 30), "yaw": 0.0})
	Game.grant_upgrade(&"throw_1")
	var ended := [false]
	var cb := func(): ended[0] = true
	Clock.winter_ended.connect(cb)
	Clock.skip(Clock.at(120, 22.0) - Clock.minutes)
	runner.check(not ended[0], "Still winter on March 31 at 22:00")
	Clock.skip(3 * 60.0)
	Clock.winter_ended.disconnect(cb)
	runner.check(ended[0] and Clock.has_ended(), "April 1 ends the winter")
	var w1_snow := Weather.total_snow_cm
	Game.next_winter()
	runner.check(Game.year == 2, "Year 2 begins")
	runner.check(Clock.day_index() == 0, "New winter starts December 1")
	runner.check(Game.money == 777, "Money persists")
	runner.check(Game.has_upgrade(&"throw_1"), "Upgrades persist")
	var has_atv := false
	for v in Game.vehicles:
		if v["id"] == "atv_blade":
			has_atv = true
	runner.check(has_atv, "Vehicles persist")
	runner.check(Snow.depth_at(50.0, 92.0) < 0.6, "Seasonal snow reset to the new winter's start")
	runner.info("winter 1 snow %.0f cm, winter 2 %.0f cm" % [w1_snow, Weather.total_snow_cm])


func test_difficulty_scaling_is_capped() -> void:
	var totals := []
	for y in [1, 3, 6, 12, 40]:
		Weather.generate(y, 1234)
		totals.append(Weather.total_snow_cm)
	runner.info("seasonal snowfall by year (1,3,6,12,40): %s" % str(totals.map(func(t): return int(t))))
	runner.check(totals[2] > totals[0], "Later winters bring more snow")
	runner.check(totals[3] < totals[2] * 1.6 and totals[4] < totals[2] * 1.6, "Scaling is capped after the hardest winter (no runaway difficulty)")
	runner.near(Weather.difficulty, Catalog.balance.difficulty_cap, 1e-6, "Difficulty reaches its cap")


# -----------------------------------------------------------------------------
# Polish pass: 48-hour contracts, storm tiers, lamp-height ceiling
# -----------------------------------------------------------------------------

func _award_driveway(lot_index: int, kind := "one_time") -> Dictionary:
	Contracts._add_lot_listing(Layout.lots[lot_index], 0, RandomNumberGenerator.new())
	var l: Dictionary = Contracts.listings[Contracts.listings.size() - 1]
	l["zones"] = [Contracts._zone("Driveway", [Boxes.lot_box(Layout.lots[lot_index], "driveway")])]
	l["type"] = kind
	return Contracts.force_award(int(l["lid"]))


func test_contract_lost_after_48_hours_snowed_in() -> void:
	_fresh()
	Weather.force(Weather.C.CLEAR, 200.0)
	var c := _award_driveway(2)
	runner.check(Contracts.is_snowed_in(c), "A new job starts snowed in")
	Clock.advance(47.0 * 60.0)
	runner.check(c["status"] == "active", "Still kept after 47 hours snowed in (%.1f h left)" % Contracts.hours_left(c))
	Clock.advance(1.5 * 60.0)
	runner.check(c["status"] == "lost", "Lost after more than 48 hours snowed in")
	# The timer resets when the boxes are completed.
	var c2 := _award_driveway(6, "recurring")
	Clock.advance(30.0 * 60.0)
	runner.check(Contracts.hours_left(c2) < 19.0, "Timer running (%.1f h left)" % Contracts.hours_left(c2))
	for z in c2["zones"]:
		_clear_zone(z)
		Contracts.measure_zone(c2, z)
	runner.check(c2["status"] == "serviced" and Contracts.hours_left(c2) == INF, "Clearing every box stops and resets the clock")
	Snow.add_snowfall(0.04)
	Contracts.on_hour(Clock.day_index(), Clock.hour())
	runner.check(c2["status"] == "needs_service" and absf(Contracts.hours_left(c2) - Catalog.balance.contract_snowed_in_hours) < 0.01, "New snow restarts the full 48-hour clock")
	Clock.advance(47.0 * 60.0)
	runner.check(c2["status"] == "needs_service", "…kept at 47 h")
	# Storms pause the clock (clients don't expect clearing mid-storm).
	Weather.force(Weather.C.HEAVY, 10.0, 1.5)
	Clock.advance(5.0 * 60.0)
	runner.check(c2["status"] == "needs_service", "The clock pauses while a storm is falling")
	Weather.override_cond = -1


func test_storm_tiers_by_winter() -> void:
	var b: BalanceData = Catalog.balance
	var stats := {}
	for y in [1, 5]:
		var tot := {"light": 0, "storm": 0, "major": 0}
		var light_ok := true
		var storm_ok := true
		var major_ok := true
		for sd in range(12):
			Weather.generate(y, 500 + sd * 31)
			var c := Weather.tier_counts()
			for k in c:
				tot[k] += c[k]
			for ev in Weather.events:
				var cm: float = ev["total"]
				match Weather.tier_of(ev):
					"light":
						light_ok = light_ok and cm >= b.light_cm_min - 0.01 and cm <= b.light_cm_max + 0.01
					"storm":
						storm_ok = storm_ok and cm >= b.storm_cm_min - 0.01 and cm <= b.storm_cm_max + 0.01
					"major":
						major_ok = major_ok and cm >= b.major_cm_min - 0.01 and cm <= b.major_cm_max + 0.01 and float(ev["end"]) - float(ev["start"]) <= 6.01
		stats[y] = tot
		runner.check(light_ok and storm_ok and major_ok, "Winter %d: light 2.5–5 cm, storms 15–30 cm, major events 90–120 cm in a few hours" % y)
	runner.info("12 winters each — year 1: %s, year 5: %s" % [str(stats[1]), str(stats[5])])
	var w1: Dictionary = stats[1]
	var w5: Dictionary = stats[5]
	runner.check(w1["light"] > (w1["storm"] + w1["major"]) * 3, "Winter 1 is mostly light snowfalls")
	runner.check(w1["storm"] >= 12 * 2, "Winter 1 still has a few storms (%.1f per winter)" % (w1["storm"] / 12.0))
	runner.check(w1["major"] <= 12, "Major events are rare in winter 1 (%.2f per winter)" % (w1["major"] / 12.0))
	runner.check(w5["major"] > w1["major"] * 3 and w5["storm"] > w1["storm"], "Later winters bring more storms and major events")
	# The schedule really drops it: the first-winter opening is light.
	Weather.generate(1, 77)
	runner.check(Weather.tier_of(Weather.events[0]) == "light" and Weather.tier_of(Weather.events[1]) == "light", "Winter 1 opens with light snowfalls")
	var ev0: Dictionary = Weather.events[0]
	var sum := 0.0
	for h in range(int(ev0["start"]), int(ceil(ev0["end"]))):
		sum += Weather.rate[h]
	runner.near(sum, float(ev0["total"]), 0.05, "An event's hourly snowfall adds up to its total")


func test_snow_ceiling_at_lamp_height() -> void:
	_fresh()
	var ceil_h: float = Catalog.balance.snow_ceiling
	var p := Layout.lot_to_world(Layout.lots[3], -6.0, 6.0)
	var region := Rect2(p - Vector2(25, 25), Vector2(50, 50))
	var before := Snow.volume_in_rect(region)
	# Dump far more snow on one spot than fits under the ceiling.
	var dumped := 0.0
	for k in range(30):
		dumped += Snow.deposit(p, 6.0, 0.6)
	Snow.relax_until_stable()
	var top := 0.0
	var y := region.position.y
	while y < region.end.y:
		var x := region.position.x
		while x < region.end.x:
			top = maxf(top, Snow.ground_at(x, y) + Snow.depth_at(x, y))
			x += 0.25
		y += 0.25
	runner.info("180 m3 dumped on one spot: highest surface %.2f m (ceiling %.1f m)" % [top, ceil_h])
	runner.check(top <= ceil_h + 1e-3, "Snow stops at street-lamp height")
	runner.near(Snow.volume_in_rect(region), before + 180.0, 0.05, "…and the excess spills over: volume conserved (%.1f placed)" % dumped)
	# Snowfall can't push the surface above the ceiling either.
	Snow.add_snowfall(1.5)
	Snow.sync_all()
	runner.check(Snow.ground_at(p.x, p.y) + Snow.depth_at(p.x, p.y) <= ceil_h + 1e-3, "Snowfall stops at the ceiling")
	# A blade can't push a berm above it: the snow that doesn't fit stays in front of the blade.
	var v0 := Snow.volume_in_rect(region)
	Snow.blade_push(p + Vector2(0, 3.0), Vector2(0, -1), 1.0, 0.5, 0.0, true)
	runner.near(Snow.volume_in_rect(region), v0, 0.01, "Pushing into a ceiling-high bank conserves volume")
	runner.check(Snow.max_depth_in_radius(p.x, p.y + 2.0, 0.5) <= ceil_h + 1e-3, "…and keeps it under the ceiling")


func test_upgrades_and_stats() -> void:
	_fresh()
	Game.money = 5000
	Clock.reset(Clock.at(2, 12.0))
	var r := Economy.buy("weather_pro")
	runner.check(r["ok"] and Game.has_upgrade(&"weather_pro"), "Weather app activates immediately")
	runner.check(Weather.forecast_days() >= 4, "Forecast lookahead grows with the app")
	var r2 := Economy.buy("throw_2")
	runner.check(not r2["ok"], "Tiered upgrade requires the previous one")
	Economy.buy("throw_1")
	runner.check(Economy.has_open_order("throw_1"), "Tool upgrade becomes a store pickup")
