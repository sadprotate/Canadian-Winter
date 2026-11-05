class_name BalanceData
extends Resource
## Central balancing values. Edit res://data/balance.tres (or these defaults, which
## tools/data_gen/generate_data.gd writes into balance.tres on a data reset).

@export_group("Economy")
@export var starting_money: int = 50
@export var hydro_bill: int = 85
@export var hydro_due_day: int = 15
@export var store_open_hour: int = 7
@export var store_close_hour: int = 21
@export var contract_value_growth_per_year: float = 0.06
@export var contract_price_per_m3: float = 4.2
@export var contract_base_fee: float = 18.0
@export var recurring_visit_factor: float = 0.75
@export var late_payment_factor: float = 0.5
@export var proximity_radius: float = 70.0
@export var proximity_bid_bonus: float = 0.08

@export_group("Contracts")
## Polish 5 §10: due times replace the 48-hour snowed-in rule (a job won at 9:01 p.m. is due by
## 9 p.m. the next day; Contracts.DUE_HOUR). Warnings are posted when this many hours (or fewer)
## remain before a job is due.
@export var contract_warn_hours: float = 12.0
@export var contract_last_warn_hours: float = 3.0
## Reputation lost when a job is missed (still open at its due time).
@export var contract_lost_reputation: float = 6.0
## Polish 5 §7: the company's contract history keeps this many entries (the oldest go first).
@export var contract_history_max: int = 200
## Polish 5 §10 (Decision 5): the reputation tiers — their names, and the reputation each one
## starts at (Residential from the start, then Commercial, then City).
@export var rep_tier_names: PackedStringArray = PackedStringArray(["Residential", "Commercial", "City"])
@export var rep_tier_thresholds: PackedFloat32Array = PackedFloat32Array([0.0, 68.0, 85.0])
## Share of residential listings that are driveway jobs (the rest are path jobs) at reputation 0
## and at the Commercial threshold — linear between, and the Commercial share above it.
@export var driveway_share_rep0: float = 0.25
@export var driveway_share_commercial: float = 0.5
## Reputation gained for a completed job, scaled with its size: base + per m³, at most max. A
## recurring or city visit gains rep_visit_factor of that. Above rep_gain_full_below the gain falls
## off linearly towards reputation 100 (to a tenth at most): the next tier is harder to earn.
@export var rep_gain_base: float = 0.5
@export var rep_gain_per_m3: float = 0.03
@export var rep_gain_max: float = 2.0
@export var rep_visit_factor: float = 1.0
@export var rep_gain_full_below: float = 50.0
## The board: each morning (6 a.m.) it is filled up to this many open listings; the share of new
## listings that are commercial and city work (the rest residential), and the share of
## residential ones that are recurring.
@export var listings_per_day: int = 6
@export var listing_share_commercial: float = 0.15
@export var listing_share_city: float = 0.15
@export var listing_recurring_share: float = 0.45
## The largest residential job (m³ of snow) the board posts while your best equipment is a shovel
## or your hands — what the starting gear clears between 7 a.m. and 9 p.m. (tests/contract_bench);
## better equipment scales it by Contracts.EQUIP_RATE.
@export var listing_res_max_m3: float = 18.0
## Bids: nobody (you or a rival) bids below this fraction of the suggested price.
@export var bid_floor_frac: float = 0.8
## Rivals per listing, their first bids (fractions of the suggested price, before their edge),
## and how they answer an undercut: the chance, how often per listing, and by how much.
@export var rival_count_min: int = 1
@export var rival_count_max: int = 3
@export var rival_open_min: float = 0.97
@export var rival_open_max: float = 1.2
@export var rival_reply_chance: float = 0.5
@export var rival_replies_max: int = 2
@export var rival_reply_step_min: float = 0.02
@export var rival_reply_step_max: float = 0.06

@export_group("Clearing boxes")
## Fraction of a box's snow that must be cleared before the box completes and snaps to bare ground
## (polish 3: 90 %, was 98 %; the last ≤ 10 % is removed when the box completes).
@export var box_completion: float = 0.90
## Snow below this depth (m) does not count as snow when measuring a box.
@export var contract_residual_depth: float = 0.01
## A completed box reopens once its average snow depth reaches this (m).
@export var box_reopen_depth: float = 0.02

@export_group("Snow")
## Opening storm: average depth of the first winter's starting snow, and its maximum on open
## ground (kept below the character's hips so the player can wade from the very start).
@export var initial_depth_year1: float = 0.82
@export var opening_max_depth: float = 0.88
@export var initial_road_depth_year1: float = 0.55
@export var initial_depth_later: float = 0.35
@export var repose_max_diff: float = 0.23
## Compaction of deep untouched snow per day (fraction of the depth above settle_threshold).
## 0 = off: every snowfall stays on top of the snow already on the ground.
@export var settle_rate_per_day: float = 0.0
@export var settle_threshold: float = 0.3
## Thrown / pushed / slid ("loose") snow sinters into cohesive snow over time (polish 2 §5): the
## loose depth decays with this time constant in game hours (after a day ~half is firm, after
## three days almost all), so old banks and piles hold steep cut faces like undisturbed snow.
@export var loose_harden_hours: float = 30.0
## Snow surface ceiling (m above the ground): the height of the street lamps.
@export var snow_ceiling: float = 6.0

@export_group("Weather")
## Snow events in the first winter and in the hardest winter (interpolated by difficulty).
@export var snow_events_year1: int = 26
@export var snow_events_max: int = 34
## Light snowfall: 1–2 in.  Storm: 6 in – 1 ft.  Major event (blizzard / surprise storm): 3–4 ft.
@export var light_cm_min: float = 2.5
@export var light_cm_max: float = 5.0
@export var storm_cm_min: float = 15.0
@export var storm_cm_max: float = 30.0
@export var major_cm_min: float = 90.0
@export var major_cm_max: float = 120.0
## Storms and major events per winter in the first and in the hardest winter (interpolated by
## difficulty; the fraction of a major event is its chance of happening, so the first winter
## gets one major event 40 % of the time).
@export var storms_year1: float = 4.0
@export var storms_max: float = 9.0
@export var majors_year1: float = 0.4
@export var majors_max: float = 3.5
## Difficulty rises by this much per winter up to the cap (1.0 = hardest winter, reached in year 5).
@export var difficulty_growth_per_year: float = 0.25
@export var difficulty_cap: float = 1.0
## Snowfall rates used by debug weather overrides (cm per game hour).
@export var rate_light_cm_h: float = 0.6
@export var rate_moderate_cm_h: float = 1.0
@export var rate_heavy_cm_h: float = 1.8
@export var rate_blizzard_cm_h: float = 25.0
## Polish 4 §1: storms and major events open with this light-to-moderate rate (cm per game hour)
## over their first one to two game hours (a partial first hour plus one full hour); the rest of
## the event's total is spread over the remaining hours, so totals, starts and ends are unchanged.
@export var storm_onset_cm_h: float = 1.0
## ...and at most this fraction of the event's mean rate (total / duration), so a small storm
## still visibly builds from its lead-in.
@export var storm_onset_mean_frac: float = 0.5
## Polish 4 §1: the forecast model. Error grows with lead time: the fraction of an event's amount
## a forecast can be off by is fc_error_base + fc_error_per_day x days ahead (also the ± range
## shown); its timing drifts by up to fc_timing_h_per_day hours per day ahead; temperatures by up
## to fc_temp_error_per_day °C per day ahead. A storm that will arrive stronger than forecast, or
## unforecast, is picked up by the radio this many game hours before it starts (the TV never calls
## an unforecast one before it starts). forecast_skill scales it all: errors / skill, the surprise
## horizon x skill — the hook for forecasting equipment (no upgrade sets it yet).
## Polish 5 §8: tuned for the accuracy targets — per day 0.22 → 0.12 (a card's range holds the
## day's snow ≥ 90 % of the time three days out), timing 2.5 → 0.25 h per day (a start within the
## hour the day before), the radio's horizon 1 → 3 h (its whole window, Decision 7).
@export var fc_error_base: float = 0.06
@export var fc_error_per_day: float = 0.12
@export var fc_timing_h_per_day: float = 0.25
@export var fc_temp_error_per_day: float = 1.6
@export var radio_surprise_horizon_h: float = 3.0
@export var forecast_skill: float = 1.0

@export_group("Survival")
## Outdoor warmth loss (% per game hour) by wind-chill temperature (°C), linearly interpolated.
## Polish 5 §9: warmth is a rate the player feels while playing, so with the 30-minute day (48
## game minutes per real minute, was 24) every warmth rate per game hour is halved: per real
## minute at 1× it is what it was (−8 °C: 3 %/game h = 2.4 %/real min, as 6 %/h was). It still
## runs on game time, so sleep and fast-forward apply it in full. In play: mild early-December
## days cost a few % per 2–3 real minutes; normal −10 °C weather gives 7–10 real minutes outside
## (6–8 game hours); very cold windy days ~4–5 real minutes; blizzards (x blizzard_cold_mult) 1–2.
@export var exposure_curve: PackedVector2Array = PackedVector2Array([Vector2(-2, 1), Vector2(-8, 3),
	Vector2(-17, 9.5), Vector2(-25, 14), Vector2(-40, 20.5), Vector2(-55, 26)])
## Warmth regained per game hour at home by the heat (and at Gerry's); halved in polish 5 §9 (was
## 280) so warming up takes the same real time.
@export var warmth_recover_per_hour: float = 140.0
@export var blizzard_cold_mult: float = 3.2
@export var heavy_cold_mult: float = 1.4
@export var moderate_cold_mult: float = 1.15
@export var vehicle_heat_warmup_s: float = 20.0
@export var pouch_warmth: float = 30.0
## How long a heating pouch keeps warming you (game minutes); doubled in polish 5 §9 (was 30) so it
## lasts the same 75 real seconds at 1×. While it lasts: outdoor loss × 0.6 and +pouch_warmth_per_hour.
@export var pouch_protection_minutes: float = 60.0
## Polish 5 §9: the pouch's warmth per game hour while it lasts (was a fixed +20 in survival.gd,
## halved like every warmth rate).
@export var pouch_warmth_per_hour: float = 10.0

@export_group("Player")
@export var walk_speed: float = 4.2
@export var sprint_speed: float = 6.6
@export var crouch_speed: float = 2.2
@export var jump_velocity: float = 4.6
## Polish 5 §2: world-changing presses (scoop, push, interact, drop, store, pouch, blade angle, the
## vehicle tool key) are capped at this many per second per action; presses beyond it are ignored,
## not queued. Holding a button, UI clicks and F1 aren't limited. 0 = no cap.
@export var input_max_presses_per_s: float = 6.0

@export_group("Pickup truck")
## Polish 5 §12: the pickup in snow (the plain pickup only; every other vehicle keeps its own
## VehicleData clearance and bank checks). Snow under the wheels slows it on this depth scale
## (speed limit × 1 / (1 + 2.5 (depth / scale)²)): 15 cm → 40 km/h, 30 cm → 22 km/h.
@export var pickup_drag_depth: float = 0.4
## Average snow under the wheels at which it is stuck (dig around the wheels). The opening's
## driveway snow (~0.8 m) is above it.
@export var pickup_stuck_depth: float = 0.6
## Snow ahead of the bumper up to this depth passes under the truck (storm snow); above it the
## front shoves the snow ahead and out to the sides (the blade op at the truck's width, down to
## this depth: no clean lane, no pavement).
@export var pickup_shove_floor: float = 0.3
## Snow ahead deeper than this pushes back harder than the engine pulls: only the truck's speed
## carries it on, so a run-up shoves through a short bank and a long stretch bogs it down. Below
## it the truck keeps going, slower the deeper the snow.
@export var pickup_bog_depth: float = 0.7
## The snow also pushes back with the square of the speed (per m/s², per unit of the depth
## above): hitting a bank fast slows the truck a lot, so a faster run-up only carries it a
## little further.
@export var pickup_shove_drag: float = 0.16
## Below this speed, in snow deeper than the bog depth, the truck stops ("Snowbank ahead").
@export var pickup_shove_min_speed: float = 1.0
## Snow ahead deeper than this is a wall to the pickup (above the grille): it stops at any speed.
@export var pickup_bank_max: float = 0.95

@export_group("Upgrades")
## Polish 5 §13 (Decision 8): every item type has its own upgrade tracks (ItemUpgrades). A level
## keeps the effect of the old global upgrade it comes from; its price is that upgrade's price ×
## the item's price ÷ the family's reference price (hand tools, walk-behind blowers, vehicles), to
## two significant figures. Bare hands are priced as an item worth upgrade_hands_price.
@export var upgrade_price_ref_tool: float = 400.0
@export var upgrade_price_ref_machine: float = 790.0
@export var upgrade_price_ref_vehicle: float = 14000.0
@export var upgrade_hands_price: float = 12.0
## The heated cab (vehicles without a cab): its price for a vehicle at the vehicle reference price.
@export var upgrade_cab_price: float = 1500.0
## The ladder: a track's levels stop where the item would pass the next item's base value of what
## the track improves by more than this fraction (unless the item is already ahead there at base).
@export var upgrade_ladder_slack: float = 0.15

@export_group("Equipment")
## Polish 5 §13: equipment from the Equipment store (picked up at the store, never in a tool slot).
## The insulated coat (Survival only, Decision 9) lowers the warmth lost outdoors (and sheltered
## in a cold house) by this fraction. It replaces the old Insulated Work Jacket and Arctic Parka
## upgrades (×0.8 and ×0.75: together ×0.6), so an old save keeps the protection it paid for.
@export var coat_price: int = 480
@export var coat_cold_protection: float = 0.4
## Snowshoes: you sink in this fraction of the snow's depth — the snow under the snowshoes is trodden
## down that much (a track that deep; wading without them treads down about 60 %) and you stand on
## it (the hip rule is measured from there); you wade only through the snow you sink into, so you
## move much faster.
@export var snowshoes_price: int = 160
@export var snowshoes_sink: float = 0.25
## The heated pad: the snow on it melts at this rate (cm of depth per game hour, a world rate).
@export var pad_price: int = 650
@export var pad_melt_cm_h: float = 30.0

@export_group("Heating")
## Polish 5 §13: the heated driveway and heated path (house upgrades, data/upgrades/heated_*.tres)
## melt the snow on those two boxes at this rate (cm of depth per game hour, a world rate): it keeps
## up with a light snowfall and falls behind in a storm. A power cut stops them (and the pad).
## 1.0 cm/h: of the scheduled events of 21 seeds × winters 1–3, no light snowfall (0 of 1,402)
## builds 2 cm on it (the box's reopen depth) and 331 of 333 storms do (1.5 cm/h: 254 of 333).
@export var heated_melt_cm_h: float = 1.0
## The power it takes to melt snow (the pad, the heated driveway and path alike): this much per m³
## melted goes on the next hydro bill (Survival). Real cables use about 20 kWh a cubic metre (≈ $2.40
## at 12 ¢); the game charges less so the house upgrades stay a comfort, not a burden: the heated
## driveway costs up to $1.11 an hour while it melts, about $70 in a December, $160 in a stormy January.
@export var melt_cost_per_m3: float = 1.5
