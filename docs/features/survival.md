# Survival: warmth and the cold

## What it does for the player

- **Survival Mode only.** Fun Mode has no cold anywhere.
- Warmth runs from 100 % down to 0 % (frozen). Outdoors you cool down; indoors, in a running cab,
  or near Gerry's fire you warm up.
- The warmth meter shows a state: Comfortable (≥ 70), Cooling (≥ 45), Cold (≥ 25), Dangerously cold
  (≥ 10), Critical freezing. Each step down from Cold on is a warning (a notification) and drops
  fast-forward to 1×.
- The player is less insulated than before polish 8: even on a mild first day, by the time Gerry's
  trail is done (outside throughout), the cold warnings are showing.
- Nights are colder on foot: from dusk to 7:00 a.m. the loss outdoors is higher.
- An enclosed cab (the pickups, the plow truck, the dump truck, the grader, the tractors and the
  rotary blower) keeps the wind out. With the engine running (I by default, `veh_engine`) it warms
  you, slower than indoors. The ATV and the walk-behind blowers give no shelter.
- The garage shelters like a cab with its engine off, with its door open or closed.
- Hints: the first cold warning of a game opens "Warming up" (indoors, a running cab, a heating
  pouch) once. At dusk before a cold night, "Cold night ahead. Sleep, or work from a heated cab."
- Freezing: the death screen, then back to the main menu (progress since the last save is lost).

## How it works

All rates are warmth-% per game hour; the balance comments give each as a felt rate (per real minute
at 1×, `Survival.per_real_minute`), as round 5 §9's audit set out.

- **Outdoors** (`outdoor_loss_per_hour`): (`exposure(wind chill)` from `exposure_curve` × the
  snowfall multiplier (`moderate_cold_mult`, `heavy_cold_mult`, `blizzard_cold_mult`) +
  `player_base_loss_per_hour`, the colder player's own loss whatever the weather) × the coat
  (`Equipment.cold_mult()`, `coat_cold_protection`) × 0.6 while a pouch lasts × `player_cold_mult` ×
  `night_cold_mult` at night (`Survival.night_at`: from `DayNight.sunset_hour(day)` to
  `NIGHT_ENDS_H`, 7:00). An open machine (the ATV, a walk-behind blower) is outdoors.
- **Sheltered** (`sheltered_loss_per_hour`: the garage, a cab with the engine off, a running cab
  still warming up): `exposure(air temperature)` × the coat × `player_cold_mult` (× 0.6 with a
  pouch). No wind, snowfall, night or base loss.
- **A cab:** `VehicleData.heated_cabin` marks an enclosed cab (the owner chose to reuse it rather
  than add a field). In one, `Survival.in_cab` is set; with the engine on, the cab's heat ramps 0→1
  (`vehicle.gd`) and the rate is `heat × cab_warmth_per_hour − (1 − heat) × sheltered loss`. Engine
  off: the heat decays and the cab only shelters. The ATV's heated-cab upgrade
  (`ItemUpgrades.has_heated_cab`) stays unwired.
- **The engine:** `veh_engine` toggles it (vehicle context). Off: no throttle, the blade/blower
  can't be raised, lowered or started, the status line says so, the HUD shows "Engine off".
- **Indoors** (unchanged by polish 8; neither `player_cold_mult` nor the base loss applies): the player's house
  `house_heat × warmth_recover_per_hour × house_warm` (× 1.4 near the fire with power), minus the
  cold coming in when the heat is low; Gerry's house `warmth_recover_per_hour`.
- **Pouches:** `pouch_warmth` at once, then for `pouch_protection_minutes` the loss × 0.6 and
  `pouch_warmth_per_hour`.
- **Power:** an unpaid hydro bill cuts the power; the house loses its heat over a day.
- **Ticks:** `Survival.on_advance(step)` runs inside the clock's per-step tick, so 1×, 2× and 10× give
  the same warmth. While skipping (sleep), warmth under 30 interrupts.
- **The cold-night warning** (`_cold_night`): at dusk, if `Weather.forecast_low` from dusk to 7:00
  (the forecast model issued now, never the weather that will fall) is under `cold_night_low_c`, it
  is due (flags `cold_night_day`, `cold_night_due`, saved with the flags). It shows at dusk, or the
  first time that night the player isn't indoors or in a running cab; once a night. With hints off
  it is a WARN notification.
- **The opening target:** `opening_target_warmth` is where warmth should land at the end of the
  measured opening (`contract_bench --job=opening`, about 6 real minutes outdoors, done around noon
  on Dec 1). `player_base_loss_per_hour` and `player_cold_mult` are tuned together so every tested
  seed ends with the cold warnings showing and not critical, their mean near the target: one
  multiplier alone couldn't, as Dec 1's weather differs by seed (wind chill about −1 to −10 °C).
  The figures are in `test_polish8.gd` (`S14_OPENING_IN_S`, `S14_OPENING_OUT_S`); re-measure when
  the opening changes.

## Where it lives

- `scripts/autoload/survival.gd`: state, rates, warnings, cold night, death.
- `scripts/player/player.gd`: `in_player_house`, `in_neighbor_house`, `near_fire`, `in_garage`.
- `scripts/vehicles/vehicle.gd`: the engine, `vehicle_heat`, `in_cab`.
- `scripts/data/equipment.gd`: the coat. `scripts/autoload/weather.gd`: `forecast_low`.
  `scripts/world/day_night.gd`: `sunset_hour`.
- `scripts/ui/help_text.gd`: `WARM_UP`, `COLD_NIGHT`. `scripts/game/game_root.gd`: `_on_died`.
- Balance: the Survival group in `data/balance.tres` / `scripts/data/balance_data.gd`.

## Connects to

Weather (temperature, wind chill, condition, forecasts), Clock (per-step tick, fast-forward, sleep),
the hint panel (`docs/features/hints.md`), vehicles (`docs/features/vehicles.md`), the garage
(`docs/features/garage.md`), saves (`warmth`, `active`, power, pouch; the flags).

## How to test

- `test_polish8 --test=test_s14_` (opening target per seed, night vs day, shelter, the hints,
  time to danger, the path job, Fun Mode and sleep unchanged, 1×/2×/10× equality).
- `test_systems --test=test_warmth_rates`, `test_polish5 --test=test_s9_`.
- `tests/contract_bench.tscn -- --job=opening --seed=<n>`: the opening at a human pace.

## Decisions

- Polish 5 §9: rates are felt rates; cold warnings drop fast-forward to 1×.
- Polish 5 §13: the insulated coat replaces the jacket and parka upgrades.
- Polish 8 §14: a colder player (`player_cold_mult` and `player_base_loss_per_hour`: the owner chose
  the base loss so a mild first day is as cold as a cold one), colder nights on foot, enclosed cabs
  warm with the engine on and shelter with it off, the garage shelters, the cold-night and
  warming-up hints. The opening is tuned by day (it ends before dusk), with the night multiplier in
  place.

## Known issues

- The ATV's heated-cab upgrade is still unwired (on hold).
- A player who clears Gerry's trail by hand (no shovel) has to go in to warm up partway (the owner's
  answer). Freezing before the first sleep loses the new game: there is no save yet.
