class_name SnowFX
extends Node3D
## Pooled snow particle effects (scoops, landings, scrapes, blower streams). Low counts for
## the low-tier target; amounts scale with the particle density setting.

static var instance: SnowFX
var _pool: Array = []
var _next := 0
var _puffs: Array = []
var _next_puff := 0
static var _puff_mesh: Mesh
var density := 1.0
static var _mat: StandardMaterial3D
static var _mesh: Mesh


func _ready() -> void:
	instance = self
	density = [0.4, 1.0, 1.6][clampi(int(Settings.get_value("graphics", "particles", 1)), 0, 2)]
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.96, 0.97, 1.0)
		_mat.roughness = 0.9
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_mat.billboard_keep_scale = true
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		var q := QuadMesh.new()
		q.size = Vector2(0.06, 0.06)
		q.material = _mat
		_mesh = q
	# Soft powder puffs (polish 2 §5): a low, slow cloud where snow is scooped or lands.
	if _puff_mesh == null:
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.97, 0.98, 1.0, 0.55)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		pm.billboard_keep_scale = true
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var pq := QuadMesh.new()
		pq.size = Vector2(0.16, 0.16)
		pq.material = pm
		_puff_mesh = pq
	for i in range(8):
		var pf := CPUParticles3D.new()
		pf.emitting = false
		pf.one_shot = true
		pf.explosiveness = 0.85
		pf.amount = 12
		pf.lifetime = 0.7
		pf.mesh = _puff_mesh
		pf.direction = Vector3.UP
		pf.spread = 85.0
		pf.initial_velocity_min = 0.25
		pf.initial_velocity_max = 0.9
		pf.gravity = Vector3(0, -0.6, 0)
		pf.damping_min = 0.8
		pf.damping_max = 1.6
		pf.scale_amount_min = 0.7
		pf.scale_amount_max = 1.6
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.6))
		curve.add_point(Vector2(0.4, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		pf.scale_amount_curve = curve
		pf.local_coords = false
		add_child(pf)
		_puffs.append(pf)
	for i in range(14):
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.9
		p.amount = 32
		p.lifetime = 0.9
		p.mesh = _mesh
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 3.2
		p.gravity = Vector3(0, -9.0, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.8
		p.damping_min = 0.5
		p.damping_max = 1.5
		p.local_coords = false
		add_child(p)
		_pool.append(p)


static func burst(pos: Vector3, amount: int, strength := 1.0, dir := Vector3.UP) -> void:
	if instance == null:
		return
	instance._burst(pos, amount, strength, dir)


func _burst(pos: Vector3, amount: int, strength: float, dir: Vector3) -> void:
	var p: CPUParticles3D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.global_position = pos
	p.amount = maxi(2, int(amount * density))
	p.direction = dir
	p.initial_velocity_min = 0.8 * strength
	p.initial_velocity_max = 2.6 * strength
	p.restart()
	p.emitting = true


## A soft powder cloud of the given size (≈ radius in metres).
static func puff(pos: Vector3, size := 0.4) -> void:
	if instance == null:
		return
	instance._puff(pos, size)


func _puff(pos: Vector3, size: float) -> void:
	var p: CPUParticles3D = _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % _puffs.size()
	p.global_position = pos
	p.amount = maxi(3, int(clampf(size * 22.0, 4.0, 24.0) * density))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = clampf(size * 0.5, 0.05, 0.6)
	p.initial_velocity_max = 0.5 + size
	p.restart()
	p.emitting = true


## A continuous stream emitter (blower chutes). Caller owns it.
static func make_stream(parent: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 60
	p.lifetime = 1.1
	p.mesh = _mesh
	p.spread = 6.0
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.6
	p.local_coords = false
	parent.add_child(p)
	return p
