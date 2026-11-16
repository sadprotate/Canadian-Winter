class_name WeatherFX
extends Node3D
## The weather you can see (polish 8 §7; Part 0 / polish 3 §3 before). Five particle layers, all in
## world space, all drawn with shaders/snow_flake.gdshader and a crystal atlas drawn here in code:
##   flakes  — the falling snow: six-armed crystals, mixed sizes, fluttering; more, faster and
##             smaller as the snowfall gets heavier, slanted more as the wind rises
##   fill    — the same flakes released all at once through the air round the camera when a game
##             loads or the weather is forced, so the air is full at once (the flakes from above
##             take a few seconds to fall to eye level)
##   near    — a few large soft flakes drifting past close to the camera (light snow, calm air;
##             never in the cab view)
##   streaks — snow driven almost sideways (strong wind with snowfall: the blizzard)
##   drift   — sheets of blowing snow racing along the ground (wind over blowing_snow_wind_kmh with
##             snow on the ground, snowing or not)
##   streams — snow streaming off roof ridges and the tops of banks (the same wind)
## Gusts (strong wind) come and go as pulses of denser, faster snow; trees sway with them (the
## wind_vec shader global) and the gust sound is started with each one (AudioMgr.weather_gust).
## Reads only Weather.visual_rate() and visual_wind_kmh() (the hour's look, blended over its first
## minutes): never the hours ahead, and nothing here changes the weather or the snow.
## No flake is emitted inside a building (Buildings.all(), the garage included: the flakes start
## above every roof, the other layers from points chosen outside every footprint) and none is
## drawn inside one: the shader drops any whose centre is in a footprint below its eaves.
## Randomness: its own generator (unseeded), never the global one.

const _Buildings := preload("res://scripts/world/buildings.gd")
const FLAKE_SHADER := preload("res://shaders/snow_flake.gdshader")

var particles: GPUParticles3D        # the falling flakes
var pmat: ParticleProcessMaterial
## The graphics setting's particle density (Low 0.4, Medium 1.0, High 1.5 — High counts as Medium).
var density := 1.0

const MAX_FLAKES := 5000
const MAX_NEAR := 48
const MAX_STREAKS := 2600
const MAX_DRIFT := 1400
const MAX_STREAMS := 600
## The flakes start this high above the camera (and 2 m either way: at least 8 m up, over every
## eave), over a square 24 m across — dense round the viewer; the fog does the distance.
const FLAKE_TOP := 10.0
const FLAKE_BOX := Vector3(12, 2, 12)
## Nominal fall of the flakes' column: FLAKE_TOP + 2 m in their 6 s lifetime at speed scale 1.
const FLAKE_LIFE := 6.0
const NOMINAL_FALL := 2.0
## The wind blows from this way (Weather has no wind direction).
const WIND_DIR := Vector3(0.8, 0, 0.6)
## The hide volumes the shader holds (Buildings.all() has 47).
const MAX_HIDE := 64
const MAX_LAMPS := 16
## The atlas: 4 × 2 frames of 64 px — 0–5 crystals, 6 a soft flake, 7 a streak.
const ATLAS_FRAME := 64

var layers: Dictionary = {}          # name -> {node, pmat, mat, max}
var gust := 0.0                      # 0..1 now
var wind_vec := Vector2.ZERO         # m/s, what the trees were last given (the wind_vec global)
var usec_last := 0                   # this script's own time last frame (µs; perf.tscn reports it)
var rng := RandomNumberGenerator.new()
var _gust_next := 4.0
var _gust_t := -1.0                  # time into the current gust (s), < 0: none
var _gust_len := 0.0
var _gust_peak := 0.0
var _hide_sig := ""
var _vols: Array = []                # hide_volumes(), as the shader holds them
var _vols_pk := PackedFloat32Array() # the same, packed (x0, z0, x1, z1, cut each)
var _lamp_cam := Vector3(INF, INF, INF)
var _pts_cam := Vector3(INF, INF, INF)
var _pts_t := 0.0
var _stream_t := 0.0
var _lamp_t := 0.0
var _all_lamps: Array = []
var _snow_frac := 0.0
var _points: Dictionary = {}         # layer -> the start points it holds (a CPU copy)
var _refill := false
var _tasks: Array = []
var _hide_t := 0.0
var _flake_off := Vector3(INF, 0, INF)
var _aabb_cam := Vector3(INF, INF, INF)
var _gust_sent := 0.0
var _last_cam := Vector3(INF, INF, INF)

static var _atlas: ImageTexture = null


func _ready() -> void:
	rng.randomize()
	particles = _layer("flakes", MAX_FLAKES, FLAKE_LIFE, false, {"frame_lo": 0, "frame_hi": 5, "alpha": 0.95, "flutter": 0.12, "near_fade": 1.4})
	pmat = layers["flakes"]["pmat"]
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = FLAKE_BOX
	pmat.angular_velocity_min = -80.0
	pmat.angular_velocity_max = 80.0
	pmat.angle_min = 0.0
	pmat.angle_max = 360.0
	var fill := _layer("fill", MAX_FLAKES, FLAKE_LIFE, false, {"frame_lo": 0, "frame_hi": 5, "alpha": 0.95, "flutter": 0.12, "near_fade": 1.4})
	fill.one_shot = true
	fill.explosiveness = 1.0
	(layers["fill"]["pmat"] as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	_layer("near", MAX_NEAR, 7.0, false, {"frame_lo": 6, "frame_hi": 6, "alpha": 0.5, "flutter": 0.25, "near_fade": 1.1})
	_layer("streaks", MAX_STREAKS, 2.0, true, {"frame_lo": 7, "frame_hi": 7, "alpha": 0.7, "stretch_len": 1.0, "near_fade": 0.8})
	_layer("drift", MAX_DRIFT, 1.4, true, {"frame_lo": 7, "frame_hi": 7, "alpha": 0.42, "stretch_len": 2.2, "near_fade": 1.0})
	_layer("streams", MAX_STREAMS, 1.8, true, {"frame_lo": 7, "frame_hi": 7, "alpha": 0.5, "stretch_len": 1.2, "near_fade": 1.0})
	for k in ["near", "streaks", "drift", "streams"]:
		var pm: ParticleProcessMaterial = layers[k]["pmat"]
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		pm.emission_point_count = 0
		layers[k]["node"].emitting = false
	for k in ["streaks", "drift", "streams"]:
		(layers[k]["pmat"] as ParticleProcessMaterial).particle_flag_align_y = true
	for k in POINTS_CAP.keys():
		# Each point layer's texture made once at its full size (updated in place after).
		var blank := Image.create(int(POINTS_CAP[k]), 1, false, Image.FORMAT_RGBF)
		(layers[k]["pmat"] as ParticleProcessMaterial).emission_point_texture = ImageTexture.create_from_image(blank)
	var npm: ParticleProcessMaterial = layers["near"]["pmat"]
	npm.initial_velocity_min = 0.4
	npm.initial_velocity_max = 0.75
	npm.scale_min = 0.12
	npm.scale_max = 0.22
	var spm: ParticleProcessMaterial = layers["streaks"]["pmat"]
	spm.scale_min = 0.02
	spm.scale_max = 0.045
	var dpm: ParticleProcessMaterial = layers["drift"]["pmat"]
	dpm.gravity = Vector3(0, -0.8, 0)
	dpm.spread = 12.0
	dpm.scale_min = 0.25
	dpm.scale_max = 0.6
	var stpm: ParticleProcessMaterial = layers["streams"]["pmat"]
	stpm.gravity = Vector3(0, -2.5, 0)
	stpm.spread = 12.0
	stpm.scale_min = 0.1
	stpm.scale_max = 0.25
	_update_hide()
	Weather.condition_changed.connect(_on_condition_changed)
	_refill = true     # pre-filled on the first frame, once the weather's look is applied


## Forced weather (F1, the shots, the tests) changes at once: the air fills with it at once too, as
## when a game loads or the camera jumps (the hours' own changes blend in over a few minutes and
## fall in naturally).
func _on_condition_changed(_c: int) -> void:
	if Weather._overriding():
		_refill = true


func _layer(lname: String, amount: int, life: float, stretched: bool, params: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Snow_" + lname
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -30, -60), Vector3(120, 60, 120))
	p.amount_ratio = 0.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 6.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.05
	pm.scale_max = 0.1
	pm.anim_offset_min = 0.0     # a fixed random atlas frame per particle (the shader reads it)
	pm.anim_offset_max = 1.0
	pm.anim_speed_min = 0.0
	pm.anim_speed_max = 0.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = FLAKE_SHADER
	m.set_shader_parameter("atlas", atlas())
	m.set_shader_parameter("stretch", stretched)
	for k in params.keys():
		m.set_shader_parameter(k, params[k])
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	layers[lname] = {"node": p, "pmat": pm, "mat": m, "max": amount}
	return p


# -----------------------------------------------------------------------------
# The atlas (drawn in code, no imported image)
# -----------------------------------------------------------------------------

## Six crystal variants (arm length, branch count, branch length, arm width, plate size), a soft
## flake and a streak.
const CRYSTALS := [
	[0.92, 3, 0.34, 0.07, 0.0],     # fern-like dendrite
	[0.88, 2, 0.5, 0.08, 0.12],     # broad branches round a small plate
	[0.95, 0, 0.0, 0.1, 0.32],      # a hexagonal plate with stubby arms
	[0.8, 4, 0.22, 0.06, 0.0],      # fine dendrite
	[0.7, 1, 0.42, 0.11, 0.2],      # sector plate
	[0.96, 2, 0.28, 0.05, 0.0],     # thin star
]


static func atlas() -> ImageTexture:
	if _atlas != null:
		return _atlas
	var f := ATLAS_FRAME
	var img := Image.create(f * 4, f * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for i in range(8):
		var ox := (i % 4) * f
		var oy := (i / 4) * f
		for y in range(f):
			for x in range(f):
				var p := Vector2(x + 0.5 - f * 0.5, y + 0.5 - f * 0.5) / (f * 0.5)
				var a := 0.0
				if i < 6:
					a = _crystal(p, CRYSTALS[i])
				elif i == 6:
					a = pow(clampf(1.0 - p.length(), 0.0, 1.0), 1.6)
				else:
					# A streak: soft across, tapering to both ends along.
					a = clampf(1.0 - absf(p.x), 0.0, 1.0) * clampf(1.0 - pow(absf(p.y), 2.0), 0.0, 1.0)
					a = a * a
				img.set_pixel(ox + x, oy + y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


## Coverage (0..1) of a six-armed crystal at p (-1..1): folded into one 30° wedge (six-fold, mirror
## symmetric), an arm along +x with side branches at 60°, and an optional hexagonal plate.
static func _crystal(p: Vector2, c: Array) -> float:
	var r := p.length()
	if r > 1.0:
		return 0.0
	var ang := fposmod(atan2(p.y, p.x), PI / 3.0)
	if ang > PI / 6.0:
		ang = PI / 3.0 - ang
	var q := Vector2(cos(ang), sin(ang)) * r
	var arm: float = c[0]
	var nb: int = c[1]
	var bl: float = c[2]
	var w: float = c[3]
	var plate: float = c[4]
	var d := _seg_dist(q, Vector2.ZERO, Vector2(arm, 0.0))
	for k in range(nb):
		var t := arm * (0.35 + 0.5 * float(k) / maxf(nb - 1, 1))
		var l := bl * (1.0 - 0.35 * float(k) / maxf(nb, 1))
		d = minf(d, _seg_dist(q, Vector2(t, 0.0), Vector2(t, 0.0) + Vector2(cos(PI / 3.0), sin(PI / 3.0)) * l))
	var cov := 1.0 - smoothstep(w * 0.45, w, d)
	if plate > 0.0:
		# A hexagon of apothem `plate` (q is already in the 30° wedge: its edge is x = plate).
		cov = maxf(cov, 1.0 - smoothstep(plate - 0.03, plate + 0.02, q.x))
	return cov * (1.0 - smoothstep(0.92, 1.0, r))


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# -----------------------------------------------------------------------------
# What it reads
# -----------------------------------------------------------------------------

## How heavy the snowfall looks, 0..1, from the visual rate (cm/h; log scale: light 0.6 → 0.31,
## moderate 1.0 → 0.41, heavy 1.8 → 0.54, a storm's 5.5 → 0.8, 12 and over → 1).
static func level(rate: float) -> float:
	if rate <= 0.01:
		return 0.0
	return clampf(log(1.0 + rate / 0.25) / log(1.0 + 12.0 / 0.25), 0.0, 1.0)


## The hide volumes: every building's footprint up to its eaves (the roof hides what is above them
## from outside, the ceiling from inside): houses their walls (Buildings: top − roof rise), garages
## 2.9 m, the school, the store and the church their full height. [{rect: Rect2, cut: float}].
static func hide_volumes() -> Array:
	var out := []
	for b in _Buildings.all():
		var top: float = b["top"]
		var cut := top
		match str(b["kind"]):
			"house":
				cut = top - (2.0 if top >= _Buildings.TWO_STOREY_TOP - 0.01 else 2.3)
			"garage":
				cut = top - 1.5
		out.append({"rect": b["rect"], "cut": cut + 0.1})
	return out


## The shader's own test, on the CPU (tests, and where the emitters may start a particle).
static func hidden_at(p: Vector3, vols: Array = []) -> bool:
	if vols.is_empty():
		vols = hide_volumes()
	for v in vols:
		var r: Rect2 = v["rect"]
		if p.x > r.position.x and p.x < r.end.x and p.z > r.position.y and p.z < r.end.y and p.y < float(v["cut"]):
			return true
	return false


## The lowest point the falling flakes start from, for a camera at cam_y.
static func flake_floor(cam_y: float) -> float:
	return cam_y + FLAKE_TOP - FLAKE_BOX.y


## The particles alive now, per layer (amount × ratio while emitting), for perf reports.
func particle_counts() -> Dictionary:
	var out := {}
	var total := 0
	for k in layers.keys():
		var p: GPUParticles3D = layers[k]["node"]
		var n := int(round(p.amount * p.amount_ratio)) if p.emitting else 0
		out[k] = n
		total += n
	out["total"] = total
	return out


# -----------------------------------------------------------------------------
# Every frame
# -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame(delta)
	usec_last = Time.get_ticks_usec() - t0


func _frame(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	# A jump (a teleport, waking up somewhere else) fills the air round the new spot at once.
	if cp.distance_to(_last_cam) > 12.0:
		_refill = true
	_last_cam = cp
	var dens := clampf(density, 0.2, 1.0)
	var rate := Weather.visual_rate()
	var wind := Weather.visual_wind_kmh()
	var lv := level(rate)
	var thr: float = Catalog.balance.blowing_snow_wind_kmh if Catalog.balance else 20.0
	_gusts(delta, wind, thr)
	var wdir := WIND_DIR.normalized()
	var wind_ms := wind / 3.6
	var gust_ms := gust * clampf(wind_ms * 0.35, 0.0, 8.0)
	_tick_tasks(delta, cp, wdir, wind_ms)
	# The falling flakes: a column from FLAKE_TOP above, moved upwind so its slant meets the camera.
	var v_fall := lerpf(0.7, 2.4, lv)
	var v_h := wind_ms * lerpf(0.3, 0.9, smoothstep(25.0, 70.0, wind)) + gust_ms
	var flakes := 0.0 if rate <= 0.01 else maxf(0.08, pow(lv, 1.2)) * (1.0 + 0.25 * gust)
	_set_ratio("flakes", flakes * dens)
	var off := (wdir * v_h * (FLAKE_TOP / v_fall)).limit_length(60.0)
	var at := cp + Vector3(0, FLAKE_TOP, 0) - off
	if particles.global_position.distance_to(at) > 0.05:
		particles.global_position = at
	if absf(off.x - _flake_off.x) + absf(off.z - _flake_off.z) > 1.0:
		_flake_off = off
		particles.visibility_aabb = AABB(off - Vector3(40, FLAKE_TOP + 8.0, 40), Vector3(80, FLAKE_TOP + 16.0, 80))
	_put(particles, &"speed_scale", v_fall / NOMINAL_FALL)
	var vel := Vector3(wdir.x * v_h, -v_fall, wdir.z * v_h)
	_put(pmat, &"direction", vel.normalized())
	_put(pmat, &"initial_velocity_min", vel.length() * 0.85 / particles.speed_scale)
	_put(pmat, &"initial_velocity_max", vel.length() * 1.15 / particles.speed_scale)
	_put(pmat, &"scale_min", lerpf(0.06, 0.04, lv))
	_put(pmat, &"scale_max", lerpf(0.15, 0.085, lv))
	_param("flakes", &"flutter", lerpf(0.14, 0.03, maxf(lv, smoothstep(20.0, 50.0, wind))))
	# A few large soft flakes near the camera: light snow in calm air, never in the cab view.
	var near := 0.0 if rate <= 0.01 or _cab_view() else (1.0 - smoothstep(0.35, 0.6, lv)) * (1.0 - smoothstep(20.0, 32.0, wind))
	_put(layers["near"]["pmat"], &"direction", Vector3(wdir.x * v_h * 0.5, -0.6, wdir.z * v_h * 0.5).normalized())
	_set_ratio("near", near * dens)
	# Streaks driven almost sideways: strong wind with snowfall.
	var streaks := smoothstep(30.0, 65.0, wind) * smoothstep(0.25, 0.8, lv) * (0.6 + 0.6 * gust)
	var sv := Vector3(wdir.x * (wind_ms * 0.95 + gust_ms), -3.0, wdir.z * (wind_ms * 0.95 + gust_ms))
	_put(layers["streaks"]["pmat"], &"direction", sv.normalized())
	_put(layers["streaks"]["pmat"], &"initial_velocity_min", sv.length() * 0.85)
	_put(layers["streaks"]["pmat"], &"initial_velocity_max", sv.length() * 1.15)
	_set_ratio("streaks", streaks * dens)
	# Blowing snow along the ground and off roofs and banks: wind over the threshold, snow down.
	var blow := smoothstep(thr, thr + 30.0, wind) * _snow_frac
	var dv := Vector3(wdir.x, 0.22, wdir.z) * (wind_ms * 0.75 + gust_ms)
	_put(layers["drift"]["pmat"], &"direction", dv.normalized())
	_put(layers["drift"]["pmat"], &"initial_velocity_min", dv.length() * 0.7)
	_put(layers["drift"]["pmat"], &"initial_velocity_max", dv.length() * 1.1)
	_set_ratio("drift", blow * (0.7 + 0.5 * gust) * dens)
	var stv := Vector3(wdir.x, 0.3, wdir.z) * (wind_ms * 0.7 + gust_ms)
	_put(layers["streams"]["pmat"], &"direction", stv.normalized())
	_put(layers["streams"]["pmat"], &"initial_velocity_min", stv.length() * 0.6)
	_put(layers["streams"]["pmat"], &"initial_velocity_max", stv.length() * 1.0)
	_set_ratio("streams", smoothstep(thr + 5.0, thr + 35.0, wind) * (0.7 + 0.5 * gust) * dens)
	if cp.distance_to(_aabb_cam) > 10.0:
		_aabb_cam = cp
		for k in ["near", "streaks", "drift", "streams"]:
			(layers[k]["node"] as GPUParticles3D).visibility_aabb = AABB(cp - Vector3(70, 35, 70), Vector3(140, 70, 140))
	if absf(gust - _gust_sent) > 0.01 or (gust == 0.0 and _gust_sent != 0.0):
		_gust_sent = gust
		for k in layers.keys():
			(layers[k]["mat"] as ShaderMaterial).set_shader_parameter("gust", gust)
	if _refill:
		_refill = false
		_fill_air(cp, wdir, v_h, v_fall)
	# Trees sway with the wind and its gusts (foliage / snow_soft read wind_vec).
	var wv := Vector2(wdir.x, wdir.z) * (wind_ms + gust_ms)
	if wv.distance_to(wind_vec) > 0.01:
		wind_vec = wv
		RenderingServer.global_shader_parameter_set("wind_vec", wind_vec)


## Set a property only when it changes (every set re-uploads the material or the node state).
static func _put(obj: Object, prop: StringName, v: Variant) -> void:
	var cur: Variant = obj.get(prop)
	if typeof(v) == TYPE_FLOAT:
		if absf(float(cur) - float(v)) <= 0.002 * maxf(absf(float(v)), 1.0):
			return
	elif typeof(v) == TYPE_VECTOR3:
		if (cur as Vector3).distance_to(v) <= 0.002:
			return
	elif cur == v:
		return
	obj.set(prop, v)


func _param(lname: String, p: StringName, v: float) -> void:
	var m: ShaderMaterial = layers[lname]["mat"]
	var cur: Variant = m.get_shader_parameter(p)
	if cur == null or absf(float(cur) - v) > 0.002:
		m.set_shader_parameter(p, v)


## The start points and the lamps are rebuilt in turns, one a frame: never all in one frame.
func _tick_tasks(delta: float, cp: Vector3, wdir: Vector3, wind_ms: float) -> void:
	_pts_t -= delta
	_stream_t -= delta
	_lamp_t -= delta
	_hide_t -= delta
	if _tasks.is_empty():
		if _hide_t <= 0.0:
			_hide_t = 2.0
			_tasks.append("hide")
		if _pts_t <= 0.0 or cp.distance_to(_pts_cam) > 2.5:
			_pts_t = 0.5
			_pts_cam = cp
			_tasks.append_array(["near", "air", "ground"])
		if _stream_t <= 0.0:
			_stream_t = 1.5
			_tasks.append("streams")
		if _lamp_t <= 0.0 and cp.distance_to(_lamp_cam) > 3.0:
			_lamp_t = 0.5
			_lamp_cam = cp
			_tasks.append("lamps")
	if _tasks.is_empty():
		return
	match str(_tasks.pop_front()):
		"hide":
			_update_hide()
		"near":
			_near_points(cp)
		"air":
			_air_points(cp, wdir, wind_ms)
		"ground":
			_ground_points(cp, wdir)
		"streams":
			_update_streams(cp)
		"lamps":
			_update_lamps(cp)


## Release a column's worth of flakes at once through the air round the camera (never inside a
## building), moving as the falling flakes do; they fade out as the flakes from above arrive.
func _fill_air(cp: Vector3, wdir: Vector3, v_h: float, v_fall: float) -> void:
	var f: GPUParticles3D = layers["fill"]["node"]
	var fpm: ParticleProcessMaterial = layers["fill"]["pmat"]
	if particles.amount_ratio <= 0.0:
		f.emitting = false
		return
	var vols := _near_vols(cp, 30.0)
	var pts := PackedVector3Array()
	for i in range(1200):
		var h := rng.randf_range(-1.5, FLAKE_TOP - FLAKE_BOX.y)
		var p := cp + Vector3(rng.randf_range(-FLAKE_BOX.x, FLAKE_BOX.x), h, rng.randf_range(-FLAKE_BOX.z, FLAKE_BOX.z))
		p -= wdir * v_h * (maxf(h, 0.0) / maxf(v_fall, 0.1))      # on the slant that reaches the camera
		if p.y > Snow.ground_at(p.x, p.z) and _out_of(p, vols):
			pts.append(p)
	_set_points("fill", pts)
	fpm.direction = pmat.direction
	fpm.initial_velocity_min = pmat.initial_velocity_min
	fpm.initial_velocity_max = pmat.initial_velocity_max
	fpm.scale_min = pmat.scale_min
	fpm.scale_max = pmat.scale_max
	fpm.angular_velocity_min = pmat.angular_velocity_min
	fpm.angular_velocity_max = pmat.angular_velocity_max
	fpm.angle_max = 360.0
	f.speed_scale = particles.speed_scale
	f.amount_ratio = particles.amount_ratio
	f.visibility_aabb = AABB(cp - Vector3(40, 30, 40), Vector3(80, 60, 80))
	f.emitting = not pts.is_empty()
	f.restart()


func _set_ratio(lname: String, r: float) -> void:
	var p: GPUParticles3D = layers[lname]["node"]
	var pm: ParticleProcessMaterial = layers[lname]["pmat"]
	var ok := r > 0.001 and (pm.emission_shape != ParticleProcessMaterial.EMISSION_SHAPE_POINTS or pm.emission_point_count > 0)
	p.amount_ratio = clampf(r, 0.0, 1.0) if ok else 0.0
	if p.emitting != ok:
		p.emitting = ok


func _cab_view() -> bool:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl) or str(pl.get("state")) != "vehicle":
		return false
	var v = pl.get("vehicle")
	return v != null and is_instance_valid(v) and bool(v.get("cab_view"))


# -----------------------------------------------------------------------------
# Gusts (visual and audio only)
# -----------------------------------------------------------------------------

func _gusts(delta: float, wind: float, thr: float) -> void:
	var strong := smoothstep(maxf(thr + 5.0, 25.0), 60.0, wind)
	if _gust_t >= 0.0:
		_gust_t += delta
		var att := 0.7
		var rel := 1.4
		var g := 0.0
		if _gust_t < att:
			g = smoothstep(0.0, att, _gust_t)
		elif _gust_t < att + _gust_len:
			g = 1.0
		else:
			g = 1.0 - smoothstep(0.0, rel, _gust_t - att - _gust_len)
		gust = g * _gust_peak * strong
		if _gust_t > att + _gust_len + rel:
			_gust_t = -1.0
			gust = 0.0
		return
	gust = 0.0
	if strong <= 0.0:
		return
	_gust_next -= delta
	if _gust_next > 0.0:
		return
	_gust_next = rng.randf_range(3.0, 9.0) if wind >= 55.0 else rng.randf_range(7.0, 16.0)
	_gust_t = 0.0
	_gust_len = rng.randf_range(0.6, 1.6)
	_gust_peak = rng.randf_range(0.6, 1.0)
	# The sound starts with the swell (AudioMgr: not indoors, not in the menu's muted states).
	var level_db := lerpf(-15.0, -5.0, strong) + 3.0 * (_gust_peak - 0.8)
	AudioMgr.weather_gust("wind_gust_%d" % (rng.randi_range(1, 4)), level_db, rng.randf_range(0.92, 1.08))
	if wind >= 35.0 and rng.randf() < 0.45:
		AudioMgr.weather_gust("rattle", -12.0, rng.randf_range(0.95, 1.05))


# -----------------------------------------------------------------------------
# Where the layers start (never inside a building), the hide volumes, the lamps
# -----------------------------------------------------------------------------

func _update_hide() -> void:
	if not _vols.is_empty() and _Buildings.all().size() == _vols.size():
		return       # the buildings change only when one is registered (§16)
	var vols := hide_volumes()
	_vols = vols
	_vols_pk = PackedFloat32Array()
	for v in vols:
		var r: Rect2 = v["rect"]
		_vols_pk.append_array([r.position.x, r.position.y, r.end.x, r.end.y, float(v["cut"])])
	var sig := "%d" % vols.size()
	if not vols.is_empty():
		sig += "%s%s" % [str(vols[0]["rect"]), str(vols[vols.size() - 1]["rect"])]
	if sig == _hide_sig:
		return
	_hide_sig = sig
	var rects := PackedVector4Array()
	var cuts := PackedFloat32Array()
	for v in vols:
		if rects.size() >= MAX_HIDE:
			push_warning("WeatherFX: more than %d buildings: flakes may show inside the rest" % MAX_HIDE)
			break
		var r: Rect2 = v["rect"]
		rects.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
		cuts.append(float(v["cut"]))
	rects.resize(MAX_HIDE)
	cuts.resize(MAX_HIDE)
	for k in layers.keys():
		var m: ShaderMaterial = layers[k]["mat"]
		m.set_shader_parameter("hide_rects", rects)
		m.set_shader_parameter("hide_cut", cuts)
		m.set_shader_parameter("hide_count", mini(vols.size(), MAX_HIDE))


## The hide volumes now in the shader (tests).
func shader_hide() -> Dictionary:
	var m: ShaderMaterial = layers["flakes"]["mat"]
	return {"rects": m.get_shader_parameter("hide_rects"), "cut": m.get_shader_parameter("hide_cut"), "count": m.get_shader_parameter("hide_count")}


## Points round the camera for the near flakes, the streaks and the ground drift, each outside
## every building (below its eaves), rebuilt as the camera moves (one a frame, _tick_tasks).
func _near_points(cp: Vector3) -> void:
	var vols := _near_vols(cp, 10.0)
	var near := PackedVector3Array()
	for i in range(40):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 5.0
		var p := cp + Vector3(cos(a) * r, rng.randf_range(1.0, 3.0), sin(a) * r)
		if _out_of(p, vols):
			near.append(p)
	_set_points("near", near)


## Streaks: a block upwind of the camera, up to 8 m above the ground.
func _air_points(cp: Vector3, wdir: Vector3, wind_ms: float) -> void:
	var vols := _near_vols(cp, 30.0)
	var air := PackedVector3Array()
	var c := cp - wdir * clampf(wind_ms * 0.5, 3.0, 10.0)
	for i in range(240):
		var p := c + Vector3(rng.randf_range(-15.0, 15.0), 0.0, rng.randf_range(-15.0, 15.0))
		p.y = Snow.ground_at(p.x, p.z) + rng.randf_range(0.3, 8.0)
		if _out_of(p, vols):
			air.append(p)
	_set_points("streaks", air)


## Ground drift: on the snow within 16 m, upwind weighted; and how much of that ground has snow.
func _ground_points(cp: Vector3, wdir: Vector3) -> void:
	var vols := _near_vols(cp, 30.0)
	var ground := PackedVector3Array()
	var tried := 0
	var snowy := 0
	var g0 := cp - wdir * 5.0
	for i in range(160):
		var p := g0 + Vector3(rng.randf_range(-16.0, 16.0), 0.0, rng.randf_range(-16.0, 16.0))
		if not Snow.in_map(p.x, p.z):
			continue
		tried += 1
		var d := Snow.depth_at(p.x, p.z)
		if d < 0.03:
			continue
		var q := Vector3(p.x, Snow.ground_at(p.x, p.z) + d + 0.05, p.z)
		if not _out_of(q, vols):
			continue
		snowy += 1
		ground.append(q)
	_snow_frac = float(snowy) / maxf(tried, 1.0)
	_set_points("drift", ground)


## Roof ridges and eaves with snow on them, and the tops of banks, near the camera.
func _update_streams(cp: Vector3) -> void:
	var vols := _near_vols(cp, 30.0)
	var pts := PackedVector3Array()
	if Snow.roof_depth > 0.03:
		for b in _Buildings.all():
			if str(b["kind"]) not in ["house", "garage"]:
				continue
			var r: Rect2 = b["rect"]
			if r.grow(35.0).has_point(Vector2(cp.x, cp.z)):
				var top := float(b["top"]) + 0.08
				var along_x := r.size.x >= r.size.y
				for k in range(6):
					var t := (k + 0.5) / 6.0
					var p := Vector3(r.position.x + r.size.x * t, top, r.get_center().y) if along_x else Vector3(r.get_center().x, top, r.position.y + r.size.y * t)
					pts.append(p)
	# Bank tops: the snow surface standing well above the ground and above its neighbours.
	for i in range(80):
		var p := Vector3(cp.x + rng.randf_range(-25.0, 25.0), 0.0, cp.z + rng.randf_range(-25.0, 25.0))
		if not Snow.in_map(p.x, p.z):
			continue
		var g := Snow.ground_at(p.x, p.z)
		var d := Snow.depth_at(p.x, p.z)
		if d < 0.5:
			continue
		var s := g + d
		var around := 0.0
		for o in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
			around += Snow.surface_height(p.x + o.x, p.z + o.y) * 0.25
		if s - around > 0.2:
			var q := Vector3(p.x, s + 0.05, p.z)
			if _out_of(q, vols):
				pts.append(q)
	_set_points("streams", pts)


## The hide volumes within r of the camera, packed (x0, z0, x1, z1, cut each) for _out_of().
func _near_vols(cp: Vector3, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in range(0, _vols_pk.size(), 5):
		if cp.x > _vols_pk[i] - r and cp.x < _vols_pk[i + 2] + r and cp.z > _vols_pk[i + 1] - r and cp.z < _vols_pk[i + 3] + r:
			out.append_array([_vols_pk[i], _vols_pk[i + 1], _vols_pk[i + 2], _vols_pk[i + 3], _vols_pk[i + 4]])
	return out


## hidden_at() on packed volumes: true when p is outside all of them (a particle may start there).
static func _out_of(p: Vector3, pk: PackedFloat32Array) -> bool:
	for i in range(0, pk.size(), 5):
		if p.x > pk[i] and p.x < pk[i + 2] and p.z > pk[i + 1] and p.z < pk[i + 3] and p.y < pk[i + 4]:
			return false
	return true


## Each point layer's texture holds this many points, always (a texture that changes size while the
## GPU reads it stalls the frame; one of a fixed size is updated in place).
const POINTS_CAP := {"fill": 1280, "near": 64, "streaks": 512, "drift": 256, "streams": 160}


func _set_points(lname: String, pts: PackedVector3Array) -> void:
	var pm: ParticleProcessMaterial = layers[lname]["pmat"]
	var cap: int = POINTS_CAP[lname]
	if pts.size() > cap:
		pts = pts.slice(0, cap)
	_points[lname] = pts
	pm.emission_point_count = pts.size()
	if pts.is_empty():
		return
	var data := PackedFloat32Array()
	data.resize(cap * 3)
	for i in range(cap):
		var q: Vector3 = pts[i % pts.size()]
		data[i * 3] = q.x
		data[i * 3 + 1] = q.y
		data[i * 3 + 2] = q.z
	var img := Image.create_from_data(cap, 1, false, Image.FORMAT_RGBF, data.to_byte_array())
	var tex := pm.emission_point_texture as ImageTexture
	if tex == null:
		pm.emission_point_texture = ImageTexture.create_from_image(img)
	else:
		tex.update(img)


## The start points a layer holds now (tests).
func layer_points(lname: String) -> PackedVector3Array:
	return _points.get(lname, PackedVector3Array())


## The street lamps and porch lanterns nearest the camera, for the flakes' glint at night.
func _update_lamps(cp: Vector3) -> void:
	if _all_lamps.is_empty():
		var refs = get_parent().get("refs")
		if refs == null:
			refs = get_parent().get("_refs")
		if refs is Dictionary:
			for p in refs.get("streetlights", []):
				_all_lamps.append(Vector4(p.x, p.y - 0.3, p.z, 7.0))
		for lot in Layout.lots:
			if lot.get("vacant", false):
				continue
			var xf := HouseBuilder.lot_transform(lot)
			for lp in HouseBuilder.lantern_points(float(lot["setback"])):
				var w: Vector3 = xf * (lp as Vector3)
				_all_lamps.append(Vector4(w.x, w.y, w.z, 3.0))
	var near := _all_lamps.duplicate()
	near.sort_custom(func(a, b): return Vector3(a.x, a.y, a.z).distance_squared_to(cp) < Vector3(b.x, b.y, b.z).distance_squared_to(cp))
	var arr := PackedVector4Array()
	for l in near:
		if arr.size() >= MAX_LAMPS or Vector3(l.x, l.y, l.z).distance_to(cp) > 45.0:
			break
		arr.append(l)
	var n := arr.size()
	arr.resize(MAX_LAMPS)
	for k in layers.keys():
		var m: ShaderMaterial = layers[k]["mat"]
		m.set_shader_parameter("lamps", arr)
		m.set_shader_parameter("lamp_count", n)
