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
## A contract is lost when its property stays snowed in (any of its boxes incomplete) for more
## than this many game hours. The clock does not run while a storm or blizzard is still falling.
@export var contract_snowed_in_hours: float = 48.0
## Warnings are posted when this many hours (or fewer) remain before a contract is lost.
@export var contract_warn_hours: float = 12.0
@export var contract_last_warn_hours: float = 3.0
## Reputation lost when a client drops you for leaving them snowed in.
@export var contract_lost_reputation: float = 6.0
## Polish 5 §7: the company's contract history keeps this many entries (the oldest go first).
@export var contract_history_max: int = 200

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
@export var fc_error_base: float = 0.06
@export var fc_error_per_day: float = 0.22
@export var fc_timing_h_per_day: float = 2.5
@export var fc_temp_error_per_day: float = 1.6
@export var radio_surprise_horizon_h: float = 1.0
@export var forecast_skill: float = 1.0

@export_group("Survival")
## Outdoor warmth loss (% per game hour) by wind-chill temperature (°C), linearly interpolated.
## Mild early-December days cost a few % per hour; normal −10 °C weather gives 3–4 game hours
## outside; very cold windy days ~1.5–2 hours; blizzards (x blizzard_cold_mult) 30–60 minutes.
@export var exposure_curve: PackedVector2Array = PackedVector2Array([Vector2(-2, 2), Vector2(-8, 6),
	Vector2(-17, 19), Vector2(-25, 28), Vector2(-40, 41), Vector2(-55, 52)])
@export var warmth_recover_per_hour: float = 280.0
@export var blizzard_cold_mult: float = 3.2
@export var heavy_cold_mult: float = 1.4
@export var moderate_cold_mult: float = 1.15
@export var vehicle_heat_warmup_s: float = 20.0
@export var pouch_warmth: float = 30.0
@export var pouch_protection_minutes: float = 30.0

@export_group("Player")
@export var walk_speed: float = 4.2
@export var sprint_speed: float = 6.6
@export var crouch_speed: float = 2.2
@export var jump_velocity: float = 4.6
## Polish 5 §2: world-changing presses (scoop, push, interact, drop, store, pouch, blade angle, the
## vehicle tool key) are capped at this many per second per action; presses beyond it are ignored,
## not queued. Holding a button, UI clicks and F1 aren't limited. 0 = no cap.
@export var input_max_presses_per_s: float = 6.0
