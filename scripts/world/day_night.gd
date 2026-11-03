class_name DayNight
extends Node3D
## Sky, sun/moon, ambient and fog driven by the game clock and weather.
## The dusk palette (purple-blue zenith, pink/orange horizon) matches the reference images.

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var override_hour := -1.0     # main menu / screenshots can force a time
var override_weather := -1
var shadows_enabled := true
var _t := 0.0
var night := 0.0
var _blend_from := -1           # previous hour's condition while the look is blending (-1: none)
var _blend_f := 1.0


func _ready() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.004
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.03
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 2.2
	sun.shadow_opacity = 0.8
	add_child(sun)


func set_shadow_quality(level: int) -> void:
	shadows_enabled = level > 0
	sun.shadow_enabled = shadows_enabled
	sun.directional_shadow_max_distance = [30.0, 45.0, 60.0, 90.0][clampi(level, 0, 3)]


## Day of winter (0 = Dec 1) and hour (0-24) -> sun elevation/azimuth in degrees.
static func sun_angles(day: float, hour: float) -> Vector2:
	# Day length for ~45°N: 8.8 h at the solstice (day 20) up to ~12.4 h at the end of March.
	var t := clampf((day - 20.0) / 100.0, -0.2, 1.0)
	var length := lerpf(8.8, 12.4, maxf(t, 0.0)) + (0.2 if t < 0.0 else 0.0)
	var noon := 12.1
	var rise := noon - length * 0.5
	var max_elev := lerpf(21.5, 47.0, maxf(t, 0.0))
	var phase := (hour - rise) / length   # 0 at sunrise, 1 at sunset
	var elev := 0.0
	if phase >= 0.0 and phase <= 1.0:
		elev = sin(phase * PI) * max_elev
	else:
		var p2 := phase if phase < 0.0 else phase - 1.0
		elev = -absf(p2) * length / 24.0 * 140.0
		elev = maxf(elev, -60.0)
	var az := lerpf(122.0, 238.0, clampf(phase, -0.3, 1.3))
	return Vector2(elev, az)


func _process(delta: float) -> void:
	_t += delta
	var hour := Clock.hour_f() if override_hour < 0.0 else override_hour
	var day := float(Clock.day_index()) if Clock.has_method("day_index") else 0.0
	var cond: int = Weather.condition() if override_weather < 0 else override_weather
	if override_weather < 0:
		# Polish 4 §1: over the first game minutes of an hour the sky, light and fog move from the
		# previous hour's look to this one's instead of snapping.
		_blend_from = Weather.visual_prev_condition()
		_blend_f = Weather.visual_mix()
		apply(day, hour, cond, Weather.visual_intensity())
		_blend_from = -1
		return
	apply(day, hour, cond, [0.0, 0.0, 0.25, 0.5, 0.75, 1.0][cond])


## Overcast amount and cloud cover for a weather condition.
static func _cloudiness(c: int) -> Vector2:
	match c:
		1: return Vector2(0.35, 0.65)
		2: return Vector2(0.55, 0.8)
		3: return Vector2(0.72, 0.9)
		4: return Vector2(0.85, 0.95)
		5: return Vector2(0.95, 1.0)
	return Vector2(0.0, 0.32)


func apply(day: float, hour: float, cond: int, intensity: float) -> void:
	var a := sun_angles(day, hour)
	var elev := a.x
	var az := deg_to_rad(a.y)
	var sdir := Vector3(sin(az) * cos(deg_to_rad(elev)), sin(deg_to_rad(elev)), -cos(az) * cos(deg_to_rad(elev)))
	# Blend weights: day (high sun), dusk (low sun), night (sun well below horizon).
	var w_day := smoothstep(6.0, 22.0, elev)
	var w_night := 1.0 - smoothstep(-12.0, -2.0, elev)
	var w_dusk := clampf(1.0 - w_day - w_night, 0.0, 1.0)
	night = w_night
	var zen := Color(0.42, 0.56, 0.86) * w_day + Color(0.38, 0.39, 0.74) * w_dusk + Color(0.05, 0.06, 0.15) * w_night
	var hor := Color(0.8, 0.84, 0.93) * w_day + Color(0.86, 0.68, 0.82) * w_dusk + Color(0.16, 0.17, 0.3) * w_night
	var dusk_c := Color(1.0, 0.62, 0.48)
	var dusk_s := 0.12 * w_day + 0.95 * w_dusk + 0.1 * w_night
	var oc_cl := _cloudiness(cond)
	if _blend_from >= 0 and _blend_f < 1.0:
		oc_cl = _cloudiness(_blend_from).lerp(oc_cl, _blend_f)
	var overcast := oc_cl.x
	var clouds := oc_cl.y
	var oc := Color(0.66, 0.67, 0.74) * (1.0 - w_night) + Color(0.12, 0.13, 0.2) * w_night
	sky_mat.set_shader_parameter("zenith", zen)
	sky_mat.set_shader_parameter("horizon", hor)
	sky_mat.set_shader_parameter("dusk", dusk_c)
	sky_mat.set_shader_parameter("dusk_strength", dusk_s * (1.0 - overcast * 0.8))
	sky_mat.set_shader_parameter("ground", hor.darkened(0.15))
	sky_mat.set_shader_parameter("cloud_cover", clouds)
	sky_mat.set_shader_parameter("overcast", overcast * 0.85)
	sky_mat.set_shader_parameter("overcast_color", oc)
	sky_mat.set_shader_parameter("stars", w_night * (1.0 - overcast))
	sky_mat.set_shader_parameter("sun_dir", sdir)
	sky_mat.set_shader_parameter("time_offset", _t)
	sky_mat.set_shader_parameter("cloud_lit", Color(0.98, 0.95, 0.95) * w_day + Color(1.0, 0.76, 0.8) * w_dusk + Color(0.2, 0.22, 0.32) * w_night)
	sky_mat.set_shader_parameter("cloud_dark", Color(0.7, 0.72, 0.8) * w_day + Color(0.52, 0.5, 0.72) * w_dusk + Color(0.08, 0.09, 0.16) * w_night)
	# Light: sun during the day/dusk, cool moonlight at night.
	var light_dir := sdir
	var lcol := Color(1.0, 0.95, 0.88) * w_day + Color(1.0, 0.7, 0.52) * w_dusk
	var energy := 1.25 * w_day + 0.95 * w_dusk
	if elev < 2.0:
		var m := 1.0 - smoothstep(-6.0, 2.0, elev)
		var moon := Vector3(-0.35, 0.62, 0.7).normalized()
		light_dir = light_dir.lerp(moon, m).normalized()
		lcol = lcol.lerp(Color(0.55, 0.64, 0.9), m)
		energy = lerpf(energy, 0.26, m)
	energy *= 1.0 - overcast * 0.6
	sun.light_color = lcol
	sun.light_energy = energy
	if light_dir.y < 0.08:
		light_dir.y = 0.08
		light_dir = light_dir.normalized()
	sun.transform = Transform3D.IDENTITY.looking_at(-light_dir, Vector3.UP if absf(light_dir.y) < 0.99 else Vector3.FORWARD)
	sun.shadow_enabled = shadows_enabled and energy > 0.12
	# Very long low-sun shadows read as hard stripes across the snow; keep them soft and faint.
	sun.shadow_opacity = lerpf(0.35, 0.8, smoothstep(3.0, 16.0, elev))
	var amb := Color(0.62, 0.67, 0.8) * w_day + Color(0.58, 0.52, 0.72) * w_dusk + Color(0.17, 0.2, 0.33) * w_night
	amb = amb.lerp(oc, overcast * 0.5)
	env.ambient_light_color = amb
	env.ambient_light_energy = 0.62 + overcast * 0.4
	var fogs := [0.0035, 0.004, 0.007, 0.012, 0.02, 0.05]
	var fog_base: float = fogs[clampi(cond, 0, 5)]
	if _blend_from >= 0 and _blend_f < 1.0:
		fog_base = lerpf(fogs[clampi(_blend_from, 0, 5)], fog_base, _blend_f)
	env.fog_density = fog_base * (0.6 + 0.4 * clampf(intensity * 1.5, 0.0, 1.0)) + 0.0015
	env.fog_light_color = hor.lerp(oc, overcast)
	env.fog_light_energy = 1.0
	RenderingServer.global_shader_parameter_set("night_factor", w_night)
