class_name ThrownSnow
extends Node3D
## A flying clump of snow carrying real volume. On landing it is deposited into the snow sim
## (or onto a roof / into a dump-truck bed). Volume is conserved while in flight.

var volume := 0.0
var start := Vector3.ZERO
var dir2 := Vector2.ZERO
var v0 := 0.0
var angle := 40.0
var flight := 0.5
var landing: Dictionary = {}
var spread := 0.4
var t := 0.0
var _mesh: MeshInstance3D
static var _clump_mesh: Mesh


static func spawn(parent: Node, from: Vector3, d2: Vector2, land: Dictionary, vol: float, ang: float, spread_r := 0.4) -> ThrownSnow:
	var s := ThrownSnow.new()
	s.volume = vol
	s.start = from
	s.dir2 = d2
	s.landing = land
	s.v0 = land.get("v0", 4.0)
	s.flight = maxf(float(land.get("time", 0.5)), 0.05)
	s.angle = ang
	s.spread = spread_r
	parent.add_child(s)
	s.global_position = from
	return s


func _ready() -> void:
	if _clump_mesh == null:
		var kit := MeshKit.new()
		kit.sphere(Mats.snow_soft(), Transform3D(), 1.0, 4, 7)
		kit.sphere(Mats.snow_soft(), Transform3D(Basis(), Vector3(0.5, 0.2, 0.3)), 0.6, 3, 6)
		kit.sphere(Mats.snow_soft(), Transform3D(Basis(), Vector3(-0.4, -0.1, -0.4)), 0.65, 3, 6)
		_clump_mesh = kit.commit()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _clump_mesh
	var r := clampf(pow(volume, 1.0 / 3.0) * 0.55, 0.05, 0.5)
	_mesh.scale = Vector3.ONE * r
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	t += delta
	if t >= flight:
		_land()
		return
	global_position = Throw.arc_point(start, dir2, v0, angle, t)
	_mesh.rotation += Vector3(3.0, 2.0, 1.0) * delta


func _land() -> void:
	var p: Vector3 = landing.get("pos", global_position)
	match landing.get("kind", "ground"):
		"roof":
			var rs: RoofSnow = landing["roof"]
			if is_instance_valid(rs):
				Snow.add_roof_volume(rs.house_index, volume)
				rs.refresh()
		"bed":
			var bed: Node = landing["bed"]
			if is_instance_valid(bed) and bed.has_method("add_load"):
				var over: float = bed.add_load(volume)
				if over > 0.0:
					Snow.deposit(Vector2(p.x, p.z), over, spread)
		_:
			Snow.deposit(Vector2(p.x, p.z), volume, spread, false)
	SnowFX.burst(p, clampi(int(volume * 300.0) + 6, 6, 40), 1.0 + volume * 6.0)
	SnowFX.puff(p + Vector3(0, 0.1, 0), clampf(0.25 + volume * 4.0, 0.25, 1.2))
	var big := volume > 0.06
	AudioMgr.play_at("snow_land_big" if big else AudioMgr.variant("snow_land", 3), p, -4.0 if big else -7.0, randf_range(0.9, 1.1))
	queue_free()


## Called on save / scene exit: never lose volume in flight.
func flush() -> void:
	if not is_queued_for_deletion():
		_land()
