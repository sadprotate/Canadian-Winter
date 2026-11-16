# Weather you can see and hear

What falls (the hourly schedule, the snow totals, the forecasts) is `Weather`'s and is not covered
here: this is how the weather looks and sounds. It reads the hour's look only, never the hours ahead.

## What it does for the player

- **Light snow:** real six-armed crystals in several shapes and sizes, drifting and fluttering down; a
  few large soft flakes drift past close to the camera; at night they glint near the street lamps
  and porch lanterns; a soft hush in still air.
- **Moderate:** clearly more flakes, a little faster, a light haze down the street.
- **Heavy:** dense snow slanted by the wind; the far end of the street disappears and the houses
  across it soften; the wind sound rises; blowing snow starts along the ground.
- **Blizzard:** a near whiteout (visibility in the tens of metres); streaks driven almost sideways;
  gusts come and go as pulses of denser snow, each with a gust sound (whistles, a rattle); sheets of
  blowing snow race along the ground and stream off roof ridges and the tops of banks; the trees
  sway; a howling wind under it all.
- **Windy hours without snowfall:** with the wind over `blowing_snow_wind_kmh` and snow on the
  ground, wisps run along the snow and off the roofs, with the wind's sound.
- **Indoors:** the snow is seen falling through the windows and the open garage door; no flake shows
  inside any building (the garage included). The wind is muffled as before.
- **Readable in every condition:** the box outlines (blue and money green) and the scoop indicator
  ignore the fog; the HUD, prompts and hint panel are drawn over everything.
- **Settings:** Graphics → Particle density scales every layer (Low 0.4; High counts as Medium, as
  before).
- **F1:** "Windy (no snow)" shows a 40 km/h wind with no snowfall for 2 game hours — the look and
  the sound only (no snow falls, the cold is unchanged, nothing is saved); "Clear override" ends it.

## How it works

- **What it reads:** `Weather.visual_rate()` (cm/h) and `visual_wind_kmh()` — the hour's values,
  blended from the previous hour's over its first `VISUAL_BLEND_MIN` (6) game minutes, or the forced
  values (F1, tests). `WeatherFX.level(rate)` maps the rate to a 0..1 look on a log scale (light
  ~0.31, moderate ~0.41, heavy ~0.54, a storm's 5.5 cm/h ~0.8, 12+ → 1). The wind blows one fixed way
  (`WIND_DIR`; Weather has no direction).
- **The layers** (`scripts/world/weather_fx.gd`, all `GPUParticles3D` in world space, drawn with
  `shaders/snow_flake.gdshader`; counts at Medium):
  - `flakes` (≤ 5000): from a box 24 m across, 8–12 m above the camera (over every eave), moved upwind
    so the slanted fall meets the camera; count `level^1.2`, fall 0.7–2.4 m/s (`speed_scale`, the
    lifetime fixed), size 6–15 cm in light snow down to 4–8.5 cm in a blizzard, slant from 30 % of the
    wind to 90 %.
  - `fill` (one shot): the same flakes released at once through the air round the camera when the
    game loads, the weather is forced or the camera jumps over 12 m (a teleport), so the air is full
    at once. (`preprocess` does nothing on this renderer.)
  - `near` (≤ 48): large soft flakes within 5 m, light snow in calm air only, never in the cab view.
  - `streaks` (≤ 2600): from 30 km/h with snowfall, full by 65 km/h; along their velocity
    (`particle_flag_align_y`), up to ~1.4 m long.
  - `drift` (≤ 1400) and `streams` (≤ 600): from `blowing_snow_wind_kmh` with snow on the ground
    (`drift` scaled by the share of sampled ground with snow), snowing or not.
- **Never inside a building:** `WeatherFX.hide_volumes()` is every `Buildings.all()` footprint up to
  its eaves (houses top − roof rise, garages 2.9 m, the civic buildings their height; + 0.1 m), set
  once into the shader's `hide_rects` / `hide_cut` (64 slots). The shader discards a particle whose
  centre is inside one, and tests pixel by pixel any particle near one (a streak passing a wall).
  `hidden_at(p)` is the same test on the CPU. Emission: `flakes` start above every eave
  (`flake_floor`); every other layer starts from points chosen outside every volume, refreshed every
  0.5 s or 2.5 m (`layer_points()` holds them).
- **The atlas** (`WeatherFX.atlas()`, drawn in code once per run): 4 × 2 frames of 64 px — six crystal
  variants (dendrites, plates, stars; `CRYSTALS`), a soft flake, a streak.
- **Light:** unshaded, white by day, dimmed at night (`night_factor`), plus a warm glint near the 16
  nearest lamps (`refs.streetlights` and `HouseBuilder.lantern_points`), twinkling.
- **Gusts** (`_gusts`): from about 25 km/h, every 3–9 s from 55 km/h (7–16 s below), a 0.7 s swell, a
  0.6–1.6 s hold and a 1.4 s fall; they raise the snow's density and speed, the streaks and the drift,
  and the trees' sway, and call `AudioMgr.weather_gust` with a `wind_gust_1..4` variant (and a rattle
  in strong wind). Visual and audio only: `Weather.wind_kmh()`, the exposure and the weather are
  untouched (Decision 5).
- **Trees:** `foliage.gdshader` and `snow_soft.gdshader` bend vertices by the `wind_vec` global (m/s,
  set by WeatherFX with the gusts) when their `sway` uniform is on (`Mats.needles()`, `Mats.bark()`,
  `Mats.tree_snow()` only), from 8 m/s.
- **Fog** (`DayNight.apply`): per condition `[0.0035, 0.004, 0.007, 0.012, 0.026, 0.065]` (heavy and
  blizzard raised in polish 8), scaled by the intensity and blended between hours.
- **Sound** (`AudioMgr`): the weather loops (`WEATHER_LOOPS`: `wind_light`, `wind_strong`, `blizzard`,
  `snow_hush`, `blizzard_howl`) follow `AudioMgr.weather_mix(visual_rate, visual_wind)`; indoors −10 dB
  and the 700 Hz low-pass, as before. Gusts play through `weather_gust` (not indoors, not paused).
  The sounds come from `tools/audio/gen_audio.py` (`snd_snow_hush`, `snd_wind_gust`, `snd_blizzard_howl`).
- **Randomness:** WeatherFX has its own unseeded `RandomNumberGenerator`; `weather_gust` takes its
  pitch from it (no draw from the global generator).
- **Graphics:** `density` (game_root / main_menu `_apply_graphics`) multiplies every layer, clamped to
  0.2..1.0.

## Where it lives

- `scripts/world/weather_fx.gd`, `shaders/snow_flake.gdshader`.
- `scripts/autoload/audio_manager.gd` (`weather_mix`, `weather_gust`, `WEATHER_LOOPS`).
- `scripts/autoload/weather.gd` (`visual_*`, `debug_windy`), `scripts/world/day_night.gd` (fog).
- `shaders/foliage.gdshader`, `shaders/snow_soft.gdshader`, `scripts/world/mats.gd` (`tree_snow`),
  `scripts/world/props.gd`.
- `scripts/player/tool_controller.gd` (`_ring`), `scripts/world/box_outline.gd` (no fog).
- `scripts/ui/debug_menu.gd` ("Windy (no snow)"), `tools/audio/gen_audio.py`.
- Balance: `blowing_snow_wind_kmh`.

## Connects to

`Weather` (the visual values; `condition_changed` refills the air when forced), `Buildings`
(footprints), `Snow` (ground and roof snow, read only), `HouseBuilder` (lanterns), the street lamps
(`world_builder` refs), `Settings` (particle density), `AudioMgr`, `DayNight`.

## How to test

- `--only=polish8 --test=test_s7_`: no new global random calls; no flake emitted or drawn inside a
  building (the shader's volumes, the CPU mirror, every layer's start points, outdoors / in the house /
  in the garage); each level reads at a glance (counts, near flakes, streaks, blowing snow, the windy
  look, sway, the density setting, the sound mix); gusts visual and audio only.
- `--only=polish5 --test=test_s9_fast_forward_equals_1x`, `--only=polish3 --test=test_menu_respects_graphics_settings`,
  `--only=gameplay --test=test_audio_files_exist_for_every_sound`.
- `tests/perf.tscn -- --only=weather`: light, heavy, the blizzard's peak with drift, at 1× and at
  fast-forward; particle counts and WeatherFX's own µs. `tests/shot.tscn -- --wind=40` for a windy dry
  hour. `tests/weather_truth.tscn` must stay identical.

## Decisions

- Polish 8 §7: the look and sound follow the visual rate and wind (Decision 5: visual and audio only,
  never the truth ahead). Flakes are cut inside every building rather than hidden whenever the camera
  is indoors (the snow is seen through windows and the open garage door). The F1 windy button changes
  only the look and sound. Graphics High stays as Medium for the weather (the owner's default). The
  outlines and scoop ring ignore fog (the owner's default). No big near flakes in the cab view.

## Known issues

- No flake is cut inside a vehicle's cab: in the cab view the falling snow can pass through the
  roof (as before).
- The wind always blows the same way.
