class_name WeatherFX
extends Node3D
## Falling snow that follows the camera; amount and wind slant follow the weather intensity.
## Hidden indoors. Particle counts sized for the low-tier target.

var particles: GPUParticles3D
var pmat: ParticleProcessMaterial
var density := 1.0
const MAX_AMOUNT := 2400


func _ready() -> void:
	particles = GPUParticles3D.new()
	particles.amount = MAX_AMOUNT
	particles.lifetime = 6.0
	particles.preprocess = 4.0
	particles.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmat = ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(22, 1, 22)
	pmat.direction = Vector3(0, -1, 0)
	pmat.spread = 8.0
	pmat.initial_velocity_min = 1.2
	pmat.initial_velocity_max = 2.0
	pmat.gravity = Vector3(0, -0.6, 0)
	pmat.turbulence_enabled = false
	pmat.scale_min = 0.6
	pmat.scale_max = 1.4
	particles.process_material = pmat
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.9)
	m.albedo_texture = _dot_texture()
	q.material = m
	particles.draw_pass_1 = q
	add_child(particles)


static func _dot_texture() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


var _was_indoors := false
var _house_rects: Array = []


func _inside_house(p: Vector3) -> bool:
	if _house_rects.is_empty() and not Layout.player_lot.is_empty():
		for lot in [Layout.player_lot, Layout.neighbor_lot]:
			if not lot.is_empty():
				_house_rects.append(Layout.house_info(lot)["body"])
	if p.y < 0.3:
		return false
	for r in _house_rects:
		if (r as Rect2).has_point(Vector2(p.x, p.z)) and p.y < 4.5:
			return true
	return false


func _process(_d: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rate := Weather.visual_rate()   # polish 4 §1: eases into a new hour's snowfall
	# Indoors (the player, or whatever camera is looking, inside one of the two enterable houses)
	# no flake may show: the flakes are world-space and fall through roofs, so the ones already
	# in the air are hidden too, not just the emitter stopped (polish 3 §3).
	var indoors := (Game.player != null and (Game.player as Player).indoors) or _inside_house(cam.global_position)
	if indoors != _was_indoors:
		_was_indoors = indoors
		particles.visible = not indoors
		if not indoors and rate > 0.01:
			particles.restart()
	var inten := clampf(rate / 2.5, 0.0, 1.0)
	var want := 0.0 if rate <= 0.01 or indoors else clampf(0.12 + inten * 0.88, 0.0, 1.0)
	particles.amount_ratio = want * clampf(density, 0.2, 1.0)
	particles.emitting = want > 0.0
	global_position = cam.global_position + Vector3(0, 10, 0)
	var wind := Weather.visual_wind_kmh() / 3.6
	var wdir := Vector3(0.8, 0, 0.6).normalized()
	pmat.gravity = Vector3(wdir.x * wind * 0.35, -0.6 - inten * 1.2, wdir.z * wind * 0.35)
	pmat.initial_velocity_min = 1.0 + inten * 2.0
	pmat.initial_velocity_max = 1.8 + inten * 3.0
	RenderingServer.global_shader_parameter_set("wind_vec", Vector2(wdir.x, wdir.z) * wind)
