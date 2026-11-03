class_name Neighbor
extends Node3D
## The tutorial neighbor, Gerry (Part 19). Waits on his porch, waving and calling for help, until
## the player reaches him. He is the only resident the player ever meets in person.
##
## Polish 3 §4: after the trail is cleared he walks (with the walk animation, never teleporting
## while he can be seen) down the trail to his mailbox to meet the player, thanks them and invites
## them in, walks back up the trail and the steps, opens his door and goes in to the fire. If the
## player lags he waits at the door, turned towards them, waving them over, for as long as it
## takes. Inside he talks the player through the business (non-blocking lines on the HUD) and
## walks over to his computer for that part. All of this is derived from the tutorial stage plus
## transient state: nothing new is saved. Loading a game at TRAIL_DONE puts him at his door,
## waiting, and the sequence resumes from there.

signal arrived(mode: String)

const WALK_SPEED := 1.25
const FOLLOW_DIST := 5.0      # the player this close (or already inside): Gerry goes in
const COME_DIST := 4.0        # waiting at the door, the player coming this close: in he goes

var model: CharacterModel
var body: StaticBody3D
var world: Node
var _call_timer := 6.0
var inside := false
var label: Label3D
## porch | to_meet | meet | to_door | door_wait | entering | to_fire | inside | to_computer
var mode := "porch"
var invited := false          # he has asked the player in (this session, or derived on load)
var _path: Array = []         # world-space waypoints still to walk
var _next_mode := ""
var _speed := 0.0
var _y := 0.0


func _ready() -> void:
	model = CharacterModel.new()
	model.jacket_color = Color(0.62, 0.14, 0.12)
	model.toque_color = Color(0.2, 0.32, 0.25)
	model.pants_color = Color(0.25, 0.27, 0.35)
	model.scarf_color = Color(0.85, 0.82, 0.7)
	model.skin = Color(0.9, 0.74, 0.62)
	add_child(model)
	model.build()
	model.scale = Vector3.ONE * 1.02
	body = StaticBody3D.new()
	body.collision_layer = 1 | (1 << 1)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	add_child(body)
	body.set_meta("npc", self)
	label = Label3D.new()
	label.text = ""
	label.position = Vector3(0, 2.25, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.006
	label.outline_size = 10
	label.no_depth_test = true
	add_child(label)
	_y = global_position.y


# -----------------------------------------------------------------------------
# Places along his walk (world space), from his lot's layout
# -----------------------------------------------------------------------------

static func _lot() -> Dictionary:
	return Layout.neighbor_lot


static func _w(u: float, v: float, y: float) -> Vector3:
	var p := Layout.lot_to_world(_lot(), Layout.gu(_lot(), u), v)
	return Vector3(p.x, y, p.y)


## Inside the house, house frame (x, z) at floor height.
static func _h(x: float, z: float) -> Vector3:
	var L := HouseBuilder.lot_transform(_lot())
	return L * Vector3(x, Layout.PORCH_H, float(_lot()["setback"]) + z)


## Where he meets the player: on his walk beside the mailbox (polish 4: at the foot of the walk).
static func meet_point() -> Vector3:
	var p: Vector2 = Layout.house_info(_lot())["mailbox_path_point"]
	return Vector3(p.x, 0.0, p.y)


static func door_point() -> Vector3:
	return _w(-1.5, float(_lot()["setback"]) - 0.75, Layout.PORCH_H)


## Walk from the meeting point by the mailbox back up the trail and the steps to the door.
static func path_up_to_door() -> Array:
	var sb: float = _lot()["setback"]
	return [_w(-1.5, sb - 2.7, 0.0), _w(-1.5, sb - 1.6, Layout.PORCH_H), door_point()]


static func path_down_to_meet() -> Array:
	var sb: float = _lot()["setback"]
	return [door_point(), _w(-1.5, sb - 1.6, Layout.PORCH_H), _w(-1.5, sb - 2.7, 0.0), meet_point()]


## Through the door to the fire (inside, around the armchair).
static func path_in_to_fire() -> Array:
	var fz := 2.6
	var fx := HouseBuilder.BODY_X0 + 0.45 + 1.4
	return [_h(-1.5, 0.9), _h(-4.6, 2.4), _h(fx, fz)]


static func path_fire_to_computer() -> Array:
	return [_h(-2.2, 3.6), _h(1.0, 6.8), _h(1.75, 7.6)]


func fire_spot() -> Vector3:
	return path_in_to_fire()[2]


# -----------------------------------------------------------------------------
# Behaviour
# -----------------------------------------------------------------------------

## Put him where the tutorial stage says he should be (spawn and load).
func place_for_stage() -> void:
	var st := Game.stage()
	if st == Game.Stage.TRAIL_DONE:
		# Loading mid-sequence: he's at his door, waiting for the player to follow him in.
		invited = true
		_set_pos(door_point())
		mode = "door_wait"
	else:
		var pc: Vector2 = Layout.house_info(_lot())["porch_center"]
		_set_pos(Vector3(pc.x, Layout.PORCH_H, pc.y))
		mode = "porch"


func _set_pos(p: Vector3) -> void:
	global_position = p
	_y = p.y


## The trail is done: he comes down the trail to meet the player by his mailbox.
func come_down() -> void:
	if mode == "porch":
		walk(path_down_to_meet(), "meet")


## After the invitation: back up the trail to his door (then in, once the player follows).
func go_in() -> void:
	invited = true
	if mode in ["porch", "to_meet", "meet"]:
		var start := Vector2(global_position.x, global_position.z)
		var pts := path_up_to_door()
		# Skip waypoints already behind him (he may be on the steps or the porch).
		while pts.size() > 1 and Vector2(pts[0].x, pts[0].z).distance_to(start) > Vector2(pts[1].x, pts[1].z).distance_to(start) and Vector2(pts[1].x, pts[1].z).distance_to(start) < 2.0:
			pts.pop_front()
		walk(pts, "door_wait")


func walk(points: Array, then_mode: String) -> void:
	_path = points.duplicate()
	_next_mode = then_mode
	mode = _walk_mode(then_mode)


func _walk_mode(then_mode: String) -> String:
	match then_mode:
		"meet":
			return "to_meet"
		"door_wait":
			return "to_door"
		"inside":
			return "to_fire"
		"computer":
			return "to_computer"
	return "walking"


func is_walking() -> bool:
	return not _path.is_empty()


func interact_prompt(_p: Player) -> String:
	match mode:
		"porch":
			match Game.stage():
				Game.Stage.START, Game.Stage.LETTER_READ:
					return "[E] Talk to your neighbour"
				Game.Stage.NEIGHBOR_TALKED, Game.Stage.TRAIL_DONE:
					return "[E] Talk to Gerry"
			return ""
		"to_meet", "meet":
			return "[E] Talk to Gerry"
		"to_door", "door_wait", "entering":
			return "[E] Talk to Gerry"
		"inside", "to_fire", "to_computer", "computer":
			if world and world.has_method("is_gerry_talking") and world.is_gerry_talking():
				return ""
			return "[E] Talk to Gerry"
	return ""


func interact(_p: Player) -> void:
	if world:
		world.neighbor_dialogue(self)


func _process(delta: float) -> void:
	var st := Game.stage()
	var pp := Game.player_pos
	var pl: Player = Game.player
	var player_inside := pl != null and is_instance_valid(pl) and pl.in_neighbor_house
	# Walking.
	_speed = 0.0
	if not _path.is_empty():
		var tgt: Vector3 = _path[0]
		var here := Vector2(global_position.x, global_position.z)
		var to := Vector2(tgt.x, tgt.z) - here
		var step := WALK_SPEED * delta
		if to.length() <= step:
			global_position.x = tgt.x
			global_position.z = tgt.z
			_path.pop_front()
		else:
			var d := to.normalized()
			global_position.x += d.x * step
			global_position.z += d.y * step
			rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.y), delta * 8.0)
		_speed = WALK_SPEED
		# Smooth height: up and down the steps, onto the porch, the floor indoors.
		_y = move_toward(_y, tgt.y, delta * 1.4)
		global_position.y = _y
		if _path.is_empty():
			mode = _next_mode
			arrived.emit(mode)
	# What he does while not walking.
	match mode:
		"porch":
			var waiting := st <= Game.Stage.LETTER_READ
			if waiting and st == Game.Stage.LETTER_READ:
				model.set_pose("wave")
			elif st == Game.Stage.TRAIL_DONE:
				model.set_pose("cheer" if fmod(Time.get_ticks_msec() / 1000.0, 4.0) < 1.0 else "idle")
			else:
				model.set_pose("idle")
			_face(pp, delta, global_position.distance_to(pp) < 20.0 or waiting)
			if waiting and st == Game.Stage.LETTER_READ:
				_call_timer -= delta
				if _call_timer <= 0.0:
					_call_timer = randf_range(22.0, 38.0)
					call_for_help()
		"meet":
			model.set_pose("cheer" if fmod(Time.get_ticks_msec() / 1000.0, 4.0) < 1.0 else "idle")
			_face(pp, delta, true)
		"door_wait":
			# At his door: in he goes once the player follows (or is already inside); otherwise
			# he turns to them and waves them over, as long as it takes.
			var near := Vector2(pp.x - global_position.x, pp.z - global_position.z).length()
			if player_inside or near < COME_DIST or (near < FOLLOW_DIST and _player_coming(pp)):
				_enter()
			else:
				model.set_pose("wave" if fmod(Time.get_ticks_msec() / 1000.0, 3.0) < 1.6 else "idle")
				_face(pp, delta, true)
		"inside", "computer":
			model.set_pose("idle")
			if player_inside:
				_face(pp, delta, true)
		_:
			model.set_pose("idle")
	model.animate(delta, _speed)


var _last_pp := Vector3.ZERO


## The player is walking towards him.
func _player_coming(pp: Vector3) -> bool:
	var before := Vector2(_last_pp.x - global_position.x, _last_pp.z - global_position.z).length()
	var now := Vector2(pp.x - global_position.x, pp.z - global_position.z).length()
	_last_pp = pp
	return now < before - 0.001


func _enter() -> void:
	mode = "entering"
	if world and world.get("neighbor_door") != null:
		var door: Door = world.neighbor_door
		if not door.open:
			door.set_open(true)
	walk(path_in_to_fire(), "inside")


func _face(pp: Vector3, delta: float, want: bool) -> void:
	if not want:
		return
	var d := Vector2(pp.x - global_position.x, pp.z - global_position.z)
	if d.length() > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.y), delta * 3.0)


func call_for_help() -> void:
	AudioMgr.play_at("help_call", global_position + Vector3(0, 1.6, 0), 4.0)
	label.text = "Hey, help!"
	if world:
		world.subtitle("Neighbour (across the street): \"Hey, help!\"", 3.0)
	get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(label): label.text = "")
