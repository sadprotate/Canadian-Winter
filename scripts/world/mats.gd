class_name Mats
extends RefCounted
## Shared material library. Materials are cached so identical looks share one resource
## (fewer state changes, and global tweaks like night lighting apply everywhere).

static var _cache: Dictionary = {}
static var _shaders: Dictionary = {}


static func _shader(name: String) -> Shader:
	if not _shaders.has(name):
		_shaders[name] = load("res://shaders/%s.gdshader" % name)
	return _shaders[name]


static func _key(parts: Array) -> String:
	return str(parts)


static func std(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var k := _key(["std", color, roughness, metallic])
	if not _cache.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		_cache[k] = m
	return _cache[k]


static func emissive(color: Color, energy := 1.0) -> StandardMaterial3D:
	var k := _key(["emi", color, energy])
	if not _cache.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cache[k] = m
	return _cache[k]


static func shader_mat(shader_name: String, params: Dictionary) -> ShaderMaterial:
	var k := _key([shader_name, params])
	if not _cache.has(k):
		var m := ShaderMaterial.new()
		m.shader = _shader(shader_name)
		for p in params.keys():
			m.set_shader_parameter(p, params[p])
		_cache[k] = m
	return _cache[k]


static func siding(color: Color) -> ShaderMaterial:
	return shader_mat("siding", {"albedo": color})


static func asphalt() -> ShaderMaterial:
	return shader_mat("pavement", {"albedo": Color(0.27, 0.28, 0.3), "speckle": 0.1, "wetness": 0.6})


static func lot_asphalt() -> ShaderMaterial:
	return shader_mat("pavement", {"albedo": Color(0.3, 0.31, 0.33), "speckle": 0.1, "wetness": 0.4})


static func concrete() -> ShaderMaterial:
	return shader_mat("pavement", {"albedo": Color(0.46, 0.47, 0.49), "speckle": 0.06, "slab_size": 1.5, "wetness": 0.5})


static func driveway() -> ShaderMaterial:
	return shader_mat("pavement", {"albedo": Color(0.38, 0.39, 0.41), "speckle": 0.07, "slab_size": 2.75, "wetness": 0.55})


static func lawn() -> ShaderMaterial:
	return shader_mat("foliage", {"albedo": Color(0.3, 0.33, 0.24), "snow_amount": 0.0})


static func snow_ground() -> ShaderMaterial:
	return shader_mat("snow_ground", {})


static func snow_soft() -> ShaderMaterial:
	return shader_mat("snow_soft", {})


static func needles() -> ShaderMaterial:
	return shader_mat("foliage", {"albedo": Color(0.1, 0.25, 0.17), "snow_amount": 1.0, "snow_threshold": 0.45})


static func bark() -> ShaderMaterial:
	return shader_mat("foliage", {"albedo": Color(0.32, 0.22, 0.15), "snow_amount": 1.2, "snow_threshold": 0.6})


static func wood(color := Color(0.58, 0.38, 0.22), snow := 1.0) -> ShaderMaterial:
	return shader_mat("wood", {"albedo": color, "snow_amount": snow})


static func prop(color: Color, snow := 1.0, rough := 0.7) -> ShaderMaterial:
	return shader_mat("foliage", {"albedo": color, "snow_amount": snow, "snow_threshold": 0.7, "roughness": rough})


static func window_lit(panes := Vector2(2, 2), lit := 1.0) -> ShaderMaterial:
	return shader_mat("window", {"panes": panes, "lit": lit})


static func glass_clear() -> StandardMaterial3D:
	var k := "glass_clear"
	if not _cache.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.8, 0.9, 0.18)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.2
		_cache[k] = m
	return _cache[k]


static func trim() -> StandardMaterial3D:
	return std(Color(0.22, 0.23, 0.25), 0.7)


## Polish 5 §3: the finished interior walls of the enterable houses — painted drywall with a faint
## roller texture, a subtle wallpaper on the walls facing into `paper` (world XZ rect, the bedroom).
## Averages to the old plain paint (0.86, 0.8, 0.7). `origin`: the house's centre (world XZ).
static func interior_wall(origin: Vector2, paper: Rect2) -> ShaderMaterial:
	return shader_mat("interior_wall", {"origin": origin, "paper_rect": Vector4(paper.position.x, paper.position.y, paper.end.x, paper.end.y)})


## Polish 5 §5: house numbers — matte paint (a plate with a painted border, or the digits) that the
## porch lantern above lights at night (`lamp` > 0; shaders/address_plate.gdshader).
static func address_paint(color: Color, border_color := Color.BLACK, border_uv := Vector2.ZERO, lamp := 0.0) -> ShaderMaterial:
	return shader_mat("address_plate", {"albedo": color, "border_color": border_color, "border": border_uv, "lamp": lamp})


## Polish 5 §3: painted interior trim (baseboards, door and window casings).
static func interior_trim() -> StandardMaterial3D:
	return std(Color(0.9, 0.88, 0.83), 0.55)


static func roof(color: Color) -> StandardMaterial3D:
	return std(color, 0.9)


static func metal(color := Color(0.62, 0.64, 0.68)) -> StandardMaterial3D:
	return std(color, 0.35, 0.6)


static func rubber() -> StandardMaterial3D:
	return std(Color(0.08, 0.08, 0.09), 0.9)


static func fabric(color: Color) -> StandardMaterial3D:
	return std(color, 0.92)


static func reflective() -> StandardMaterial3D:
	var k := "reflective"
	if not _cache.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.87, 0.9)
		m.roughness = 0.3
		m.metallic = 0.4
		m.emission_enabled = true
		m.emission = Color(0.4, 0.42, 0.45)
		m.emission_energy_multiplier = 0.3
		_cache[k] = m
	return _cache[k]
