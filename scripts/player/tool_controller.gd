class_name ToolController
extends Node
## Tool behaviours (Parts 6.3, 9; polish §1–§3): every tool really moves snow in the snow sim.
##
## Hands and every shovel-type tool (shovels, pushers, scrapers, sleigh) share one scheme:
##   * hold the primary action (LMB) and sweep the aim point through the snow: the load fills from
##     the snow the sweep actually cuts through (deep snow fills fast, bare pavement fills nothing)
##     up to the tool's capacity, leaving a trench where it passed;
##   * release the primary action to throw the load forward where you face (a partial load too);
##     look down for a short drop, level or up for the full distance;
##   * hold the secondary action (RMB) to push the snow ahead of you into a growing berm.
## Scrapers angle their blade with the tool_angle action (R). The electric shovel keeps its hold-to-
## throw intake (LMB) and also pushes (RMB). Walk-behind blowers are separate machines.

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _Buildings := preload("res://scripts/world/buildings.gd")
const _Equipment := preload("res://scripts/data/equipment.gd")
const _HeatedPad := preload("res://scripts/world/heated_pad.gd")
const _ItemUpgrades := preload("res://scripts/data/item_upgrades.gd")

const RECUT_S := 0.3              # a cell can be cut again by the same stroke after this long
const SWEEP_MAX := 4.0            # m/s: fastest the scoop can travel through the snow
const GRIP_IN_HAND := Vector3(0.0, -0.05, -0.06)   # where a closed mitten's fist holds a bar

var player: Player
var tool_id := "__none__"
var data: ToolData
var load := 0.0
var load_road := 0.0
var filling := false
var pushing := false
var engaged := false
var cooldown := 0.0
var blade_angle := 0.0
var landing: Dictionary = {}
var indicator: MeshInstance3D
var held_tp: MeshInstance3D
var held_fp: MeshInstance3D
var blade_fp: MeshInstance3D       # first-person blade, posed separately so it can lie flat
var _blade_body := Basis()         # blade orientation in body space (set by _tool_body_xform)
var load_tp: MeshInstance3D
var load_fp: MeshInstance3D
var arms: FPArms
var vm_root: Node3D
var loop_player: AudioStreamPlayer3D
var hint := ""                 # short contextual hint for the HUD
var toss_t := 1.0              # 0..1 progress of the throw animation (1 = idle)
var sweep_speed := 0.0         # how fast the scoop is moving through the snow (m/s, smoothed)
var last_fill := 0.0           # m3 collected in the last physics frame (tests / HUD)
var _sweep_side := 0.0
var _stroke_prev := Vector2.ZERO
var _stroke_valid := false
var _cut_time: Dictionary = {}
var _dig_timer := 0.0
var _clock := 0.0
var _scoop_sfx := 0.0
var _prev_pos := Vector2.ZERO
var _stream_acc := 0.0
var _stream_timer := 0.0
var _land_timer := 0.0
var _msg_timer := 0.0
var _loop_vol := -80.0
var _fill_pressed := false
var _was_down := false
## Polish 6 §8.1: the throw rhythm. Seconds left of the last throw's recovery (ToolData
## throw_recovery_s): no scoop can start until it ends. A press during it is ignored; held through
## its end, the scoop starts then (_press_wait).
var recovery := 0.0
var _press_wait := false
var _hold_t := 0.0                 # seconds the primary action has been held (min_scoop_hold_s)
var _toss_len := 0.42              # seconds the throw's follow-through takes (toss_t 0 → 1)
var _cycle_swept := 0.0            # m3 the sweep took since the last in-place bite (one bite per cycle)
var _foot_cells := PackedInt32Array()  # the footprint the fallback last cut from (where the scoop was)
var _foot_left := 0.0              # m3 the footprint fallback may still take (the opening bite's share, once a load)
var _kept_short := false           # the load was kept by a release sooner than min_scoop_hold_s
var _held_ok: Dictionary = {}     # polish 5 §2: a held action whose press was accepted
var _held_was: Dictionary = {}
## Screenshot / debug helper: freeze the viewmodel in a pose ("hold", "scoop", "push", "toss").
var pose_override := ""
var toss_override := 0.5
static var _ring_ok: Mesh
static var _ring_bad: Mesh
static var _ring_back: Mesh
var landing_back_in_box := false
var tp_low_frac := 1.0             # third person: how far down its usual spot the left hand holds the shaft
var tp_grip_ok := true
## Polish 4 §3: the one indicator for hand tools shows where the snow goes next — on the snow at
## the pickup spot while the scoop is cutting (the centre of the cells cut that frame), out at the
## landing spot when loaded and not cutting, gliding between them.
const IND_GLIDE_S := 0.25
const IND_MAX_SPEED := 18.0        # m/s: the most it ever moves (a 0.3 m step per physics frame)
var ind_state := ""                # "" | "pickup" | "landing" | "preview"
var ind_target := Vector3.ZERO
var last_cut_center := Vector2.INF # centre of the cells the scoop cut in the last frame it cut
var _ind_from := Vector3.ZERO
var _ind_from_scale := 1.0
var _ind_scale := 1.0
var _ind_glide := 1.0
var _ind_shown := false
static var _ring_pick: Mesh
var vm_clip_y := -1000.0           # snow surface the first-person tool is clipped at (-1000: none)   # the landing ring is amber: the throw would land in the box being cleared
## Polish 5 §3: no snow work from inside a building. False while the player stands inside one (its
## footprint or its walls: Buildings.indoors) — then nothing is cut, pushed or taken in, nothing is
## thrown and no indicator shows. Outdoors, snow behind a building (the line from the eye to it
## crosses one: Buildings.blocks) is left alone too.
var work_ok := true
var _near_bld: Array = []          # buildings within a few metres (the short list the line test uses)
## A blade or intake pressed against a wall from outside reaches this far past the wall's line and
## still works the snow at its foot (the line test ignores that last stretch).
const REACH_SKIN := 0.35


func setup(p: Player) -> void:
	player = p
	indicator = MeshInstance3D.new()
	indicator.top_level = true
	indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	indicator.visible = false
	add_child(indicator)
	if _ring_ok == null:
		_ring_ok = _ring(Color(0.85, 1.0, 0.85, 0.85))
		_ring_bad = _ring(Color(1.0, 0.2, 0.15, 0.9))
		_ring_back = _ring(Color(1.0, 0.72, 0.2, 0.9))
	if _ring_pick == null:
		_ring_pick = _ring(Color(0.93, 0.96, 1.0, 0.8))
	held_tp = MeshInstance3D.new()
	player.model.add_child(held_tp)   # placed each frame (both hands reach it by IK)
	vm_root = Node3D.new()
	vm_root.name = "VMRoot"
	player.viewmodel.add_child(vm_root)
	arms = FPArms.new()
	arms.name = "Arms"
	vm_root.add_child(arms)
	arms.build(player.model.jacket_color, CharacterModel.GLOVE_COLOR)
	held_fp = MeshInstance3D.new()
	held_fp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vm_root.add_child(held_fp)
	blade_fp = MeshInstance3D.new()
	blade_fp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vm_root.add_child(blade_fp)
	for which in [0, 1]:
		var lm := MeshInstance3D.new()
		var kit := MeshKit.new()
		kit.sphere(Mats.snow_soft(), Transform3D(Basis().scaled(Vector3(1.2, 0.62, 1.0)), Vector3.ZERO), 0.18, 4, 8)
		kit.sphere(Mats.snow_soft(), Transform3D(Basis().scaled(Vector3(0.8, 0.5, 0.7)), Vector3(0.06, 0.06, -0.03)), 0.12, 4, 7)
		lm.mesh = kit.commit()
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lm.visible = false
		if which == 0:
			player.model.add_child(lm)
			load_tp = lm
		else:
			blade_fp.add_child(lm)
			load_fp = lm
			var vs := ShaderMaterial.new()
			vs.shader = load("res://shaders/viewmodel_snow.gdshader")
			lm.material_override = vs
	loop_player = AudioStreamPlayer3D.new()
	loop_player.bus = "SFX"
	loop_player.unit_size = 6.0
	player.add_child(loop_player)
	_prev_pos = Vector2(player.global_position.x, player.global_position.z)


static func _ring(color: Color) -> Mesh:
	var kit := MeshKit.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	var seg := 24
	for i in range(seg):
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		kit.quad(m, o0 * 0.42, o1 * 0.42, o1 * 0.5, o0 * 0.5, Vector3.UP)
		if i % 2 == 0:
			kit.quad(m, o0 * 0.08, o1 * 0.08, o1 * 0.12, o0 * 0.12, Vector3.UP)
	return kit.commit()


func is_engaged() -> bool:
	return engaged


func _carrying() -> bool:
	return Game.carried != ""


func refresh_visuals() -> void:
	var id := Game.carried if _carrying() else Game.current_tool_id()
	var equip := _Equipment.is_equipment(id)
	# Polish 5 §13: the heated pad is carried rolled up (it isn't a tool).
	var mesh: Mesh = (_HeatedPad.carry_mesh() if equip else ToolModels.mesh_for(id)) if id != "" else null
	held_tp.mesh = mesh
	held_fp.mesh = (_HeatedPad.carry_mesh() if equip else ToolModels.handle_mesh(id)) if mesh != null else null
	blade_fp.mesh = ToolModels.blade_mesh(id) if mesh != null and not equip else null
	held_tp.visible = mesh != null and player.third_person
	held_fp.visible = mesh != null and not player.third_person
	blade_fp.visible = held_fp.visible
	arms.visible = not player.third_person
	if id != "" and mesh != null and not equip:
		load_fp.position = ToolModels.blade_offset(id) - ToolModels.tip(id)
	_update_load_visual()


func _update_load_visual() -> void:
	var cap := _capacity()
	var frac := clampf(load / maxf(cap, 0.0001), 0.0, 1.0)
	var vis := load > 0.00005
	var on_hands := data == null or data.kind == ToolData.Kind.HANDS
	# First person: a mound in the cupped hands, or on the blade, growing with the load.
	arms.show_cup_load(frac, vis and on_hands and arms.visible and held_fp.mesh == null)
	load_fp.visible = vis and not on_hands and held_fp.visible
	var s := lerpf(0.22, 1.0, pow(frac, 0.6))
	# A bigger load for the blade's size heaps higher (polish 2 §2: the full load reads as full).
	var heap := 1.0
	if data:
		var tray := maxf(data.width * 0.36 * 0.25, 0.01)
		heap = clampf(sqrt(_capacity() / tray), 0.8, 1.4)
		var w := clampf(data.width / 0.4, 0.8, 2.2)
		load_fp.scale = Vector3(w * s, s * heap, s * (1.6 if data.kind == ToolData.Kind.SLEIGH else 1.0))
	# Third person: on the blade, or held in front of the chest with bare hands.
	load_tp.visible = vis and player.third_person and player.state == "foot"
	if load_tp.visible:
		if on_hands or held_tp.mesh == null:
			var hm := player.model
			var mid := (hm.forearm_l.global_position + hm.forearm_r.global_position) * 0.5
			var f := Vector3(player.forward2().x, 0, player.forward2().y)
			load_tp.global_position = mid + f * 0.22 + Vector3(0, -0.12, 0)
			load_tp.scale = Vector3.ONE * lerpf(0.25, 0.9, pow(frac, 0.6))
		else:
			load_tp.global_transform = held_tp.global_transform * Transform3D(Basis(), ToolModels.blade_offset(tool_id))
			var w2 := clampf(data.width / 0.4, 0.8, 2.2)
			load_tp.scale = Vector3(w2 * s, s * heap, s)


# -----------------------------------------------------------------------------
# Profiles (tool data scaled by upgrades — polish 5 §13: the tool's own, ItemUpgrades)
# -----------------------------------------------------------------------------

func _capacity() -> float:
	if data == null:
		return 0.01
	var c := data.capacity
	if data.is_shovel_type():
		c *= _ItemUpgrades.mult(data.id, &"shovel_capacity")
	return c


func _fill_rate() -> float:
	return data.fill_rate * _ItemUpgrades.mult(data.id, &"shovel_capacity")


func _throw_dist() -> float:
	var d := data.throw_distance
	if data.is_shovel_type() or data.kind == ToolData.Kind.ELECTRIC_SHOVEL:
		d *= _ItemUpgrades.mult(data.id, &"throw_distance")
	return d


func _push_half_width() -> float:
	return data.push_width * _ItemUpgrades.mult(data.id, &"blade_width") * 0.5


func _push_strength() -> float:
	return data.push_strength * _ItemUpgrades.mult(data.id, &"push_speed")


func _sync_tool() -> void:
	var id := Game.current_tool_id()
	if _carrying():
		id = "__carry__"
	if id == tool_id:
		return
	# Switching tools with a load: the load drops at your feet (volume is never lost).
	if load > 0.0:
		dump_at_feet(true)
	# Polish 6 §8.1: what the electric shovel's chute still holds goes out now (it throws on a
	# rhythm, so a little can be waiting when you switch).
	_flush_stream()
	tool_id = id
	data = Catalog.tool(StringName(id)) if id != "" and id != "__carry__" else Catalog.tool(&"hands")
	# Polish 5 §3: a new tool works out its own landing at once (the electric shovel used to throw its
	# first bite to wherever the previous tool's last throw was aimed).
	landing = {}
	_land_timer = 0.0
	blade_angle = 0.0
	filling = false
	pushing = false
	engaged = false
	_stroke_valid = false
	_was_down = Input.is_action_pressed("primary")
	# Polish 6 §8.1: the recovery runs on across the switch. A press still held keeps waiting it out
	# (the new tool's scoop starts when it ends), and a hand or shovel-type tool shows the rest of
	# the follow-through (toss_t reaches 1 as the recovery ends).
	_press_wait = _press_wait and _was_down
	if recovery > 0.0 and id != "__carry__" and data.is_shovel_type():
		toss_t = clampf(1.0 - recovery / _toss_len, 0.0, 1.0)
	else:
		toss_t = 1.0
	_set_loop("")
	refresh_visuals()
	arms.snap(_hand_targets())
	if Game.in_game and id != "__carry__":
		_hint(controls_hint(data))


## One-line controls reminder for a tool, using the player's current bindings.
static func controls_hint(t: ToolData) -> String:
	var lmb := Settings.action_label("primary")
	var rmb := Settings.action_label("secondary")
	if t == null:
		return ""
	match t.kind:
		ToolData.Kind.ELECTRIC_SHOVEL:
			return "Hold %s: chew through snow and throw it where you aim  ·  Hold %s: push" % [lmb, rmb]
		ToolData.Kind.WALK_BLOWER:
			return ""
	var s := "Hold %s and sweep: scoop  ·  Release: throw  ·  Hold %s: push" % [lmb, rmb]
	if t.angle_adjustable:
		s += "  ·  %s: angle the blade" % Settings.action_label("tool_angle")
	return s


func _set_loop(loop_name: String) -> void:
	if loop_name == "":
		loop_player.stop()
		loop_player.set_meta("name", "")
		return
	if loop_player.get_meta("name", "") != loop_name:
		loop_player.stream = AudioMgr.stream(loop_name)
		loop_player.set_meta("name", loop_name)
		if loop_player.stream:
			loop_player.play()


func _physics_process(delta: float) -> void:
	_sync_tool()
	_clock += delta
	cooldown -= delta
	recovery = maxf(recovery - delta, 0.0)
	toss_t = minf(toss_t + delta / _toss_len, 1.0)
	last_fill = 0.0
	_msg_timer -= delta
	if _msg_timer <= 0.0:
		hint = ""
	var pos2 := Vector2(player.global_position.x, player.global_position.z)
	var travel := (pos2 - _prev_pos)
	_prev_pos = pos2
	if player.state != "foot":
		# Polish 6 §8.1: what the electric shovel's chute still holds (it throws on a rhythm) goes
		# out where it was going as the player gets into a vehicle or onto a blower.
		_flush_stream()
		# Polish 5 §3: a walk-behind blower shows its chute's landing on this indicator (it runs
		# before the player each frame, so hiding it here used to hide the blower's ring too).
		if player.state != "machine":
			indicator.visible = false
		_ind_shown = false
		ind_state = ""
		engaged = false
		filling = false
		pushing = false
		_held_was.clear()
		player.speed_mult_tool = 1.0
		_set_loop("")
		if player.state == "machine":
			# Both hands are on the snowblower: the slot tool is stowed.
			held_fp.visible = false
			blade_fp.visible = false
			held_tp.visible = false
		arms.visible = false
		_update_load_visual()
		return
	arms.visible = not player.third_person
	if held_fp.mesh != null and not player.third_person and not held_fp.visible:
		held_fp.visible = true
		blade_fp.visible = true
	if Input.is_action_just_pressed("drop") and Settings.accept_press("drop"):
		drop_tool()
		# Polish 5 §2: switch to what's left in your hands this frame. A carried item dropped
		# without it left one frame posing the hands on a tool that's gone (a degenerate grip:
		# two engine errors per drop).
		_sync_tool()
	if Input.is_action_just_pressed("use_pouch") and Game.is_survival() and Settings.accept_press("use_pouch"):
		if Survival.use_pouch():
			AudioMgr.play("paper", -6.0)
			Notify.push("You crack a heating pouch. Warmth +%d." % int(Catalog.balance.pouch_warmth), Notify.GOOD)
		else:
			_hint("No heating pouches. Buy them on the computer.")
	if _carrying():
		indicator.visible = false
		_ind_shown = false
		ind_state = ""
		engaged = false
		player.speed_mult_tool = 0.85
		if Input.is_action_just_pressed("primary"):
			_hint("Your hands are full — press %s to drop what you're carrying." % Settings.action_label("drop"))
		player.model.set_pose("carry")
		_animate_viewmodel(delta)
		return
	var ui_block := not Game.input_captured()
	var fwd := player.forward2()
	# Polish 5 §3: indoors (in any building) the tools don't touch the snow.
	_near_bld = _Buildings.near(pos2, 4.0)
	work_ok = not _Buildings.indoors(player.global_position)
	if pose_override != "":
		filling = pose_override == "scoop" or pose_override == "hold"
		pushing = pose_override == "push"
		engaged = filling or pushing
		toss_t = toss_override if pose_override == "toss" else 1.0
		sweep_speed = 1.2 if pose_override == "scoop" else 0.0
		if pose_override == "hold":
			filling = false
		_update_load_visual()
		_animate_viewmodel(delta)
		_animate_tp()
		return
	if data.is_shovel_type():
		_shovel_type(delta, pos2, fwd, travel, ui_block)
	elif data.kind == ToolData.Kind.ELECTRIC_SHOVEL:
		_electric(delta, pos2, fwd, travel, ui_block)
	_update_load_visual()
	_animate_viewmodel(delta)
	_animate_tp()


func _hint(text: String) -> void:
	hint = text
	_msg_timer = 2.2


## Polish 5 §2: a held action acts from an accepted press (Settings.accept_press) for as long as it
## is held; a press over the per-second cap is ignored until the button is let go and pressed again.
func _held(action: String, down: bool) -> bool:
	if down and not _held_was.get(action, false):
		_held_ok[action] = Settings.accept_press(action)
		if _held_ok[action] and work_ok:
			Clock.drop_to_1x("work")   # polish 5 §9: starting to scoop or push stops fast-forward
	_held_was[action] = down
	return down and _held_ok.get(action, false)


## Where thrown snow leaves the hands. Standing in a trench, the load is lifted up over the walls
## (up to arms overhead) so it can land on top instead of sliding back in.
func _hand_pos() -> Vector3:
	var f := Vector3(player.forward2().x, 0, player.forward2().y)
	var feet := player.feet_y()     # polish 5 §13: on snowshoes, on the snow
	var h := feet + 1.15
	var top := 0.0
	var p := player.global_position + f * 0.6
	for a in [Vector2.ZERO, player.aim_dir() * 0.4, Vector2(-player.aim_dir().y, player.aim_dir().x) * 0.4, -Vector2(-player.aim_dir().y, player.aim_dir().x) * 0.4]:
		var q: Vector2 = Vector2(p.x, p.z) + (a as Vector2)
		top = maxf(top, Snow.surface_height(q.x, q.y))
	h = clampf(maxf(h, top + 0.3), feet + 1.15, feet + 2.05)
	return Vector3(player.global_position.x, h, player.global_position.z) + f * 0.35


func _landing(dist: float, angle: float) -> Dictionary:
	var d2 := player.aim_dir()
	return Throw.compute(player.get_world_3d(), _hand_pos(), d2, dist, angle, [player.get_rid()])


func _show_indicator(l: Dictionary) -> void:
	landing_back_in_box = false
	if l.is_empty():
		indicator.visible = false
		return
	var p: Vector3 = l["pos"]
	# Amber (not red): the throw is allowed but lands back inside the box you're clearing.
	landing_back_in_box = l.get("valid", false) and Boxes.work_box != "" and not Boxes.is_complete(Boxes.work_box) \
		and Boxes.box_has_point(Boxes.work_box, Vector2(p.x, p.z))
	if not Settings.get_value("gameplay", "show_landing_indicator", true):
		indicator.visible = false
		return
	indicator.visible = true
	indicator.mesh = (_ring_back if landing_back_in_box else _ring_ok) if l.get("valid", false) else _ring_bad
	indicator.global_position = p + Vector3(0, 0.04, 0)


## The red / amber flags for a landing (what _show_indicator sets, without showing anything).
func _landing_flags(l: Dictionary) -> void:
	landing_back_in_box = false
	if l.is_empty():
		return
	var p: Vector3 = l["pos"]
	landing_back_in_box = l.get("valid", false) and Boxes.work_box != "" and not Boxes.is_complete(Boxes.work_box) \
		and Boxes.box_has_point(Boxes.work_box, Vector2(p.x, p.z))


func _landing_mesh(l: Dictionary) -> Mesh:
	return (_ring_back if landing_back_in_box else _ring_ok) if l.get("valid", false) else _ring_bad


static func _cell_center(i: int) -> Vector2:
	@warning_ignore("integer_division")
	return Vector2((float(i % Snow.W) + 0.5) * Snow.CELL, (float(i / Snow.W) + 0.5) * Snow.CELL)


func _on_snow(p: Vector2) -> Vector3:
	return Vector3(p.x, Snow.surface_height(p.x, p.y) + 0.04, p.y)


## Where the next scoop would cut if the player started it now: the centre of the snowy cells the
## in-place cut at the aim point takes (the same cells _fill cuts), or INF if there is no snow there.
func _next_cut_center(fwd: Vector2) -> Vector2:
	var p := _aim_point()
	var cells := Snow.cells_in_obb(p - fwd * data.reach * 0.5, fwd, data.width, data.reach)
	var sum := Vector2.ZERO
	var n := 0
	for i in cells:
		var c := _cell_center(i)
		if Snow.depth_at(c.x, c.y) > data.scrape_floor + 0.01 and not _behind_building(c):
			sum += c
			n += 1
	return sum / n if n > 0 else Vector2(INF, INF)


## Point the indicator at a new state / target. A change of state glides from where it is now; a
## fresh appearance starts in place; "" hides it.
func _indicate(state: String, target: Vector3, mesh: Mesh, scale: float) -> void:
	if state == "" or not Settings.get_value("gameplay", "show_landing_indicator", true):
		ind_state = state
		_ind_shown = false
		indicator.visible = false
		return
	if not _ind_shown:
		indicator.global_position = target
		_ind_glide = 1.0
		_ind_scale = scale
	elif state != ind_state:
		_ind_from = indicator.global_position
		_ind_from_scale = indicator.scale.x
		_ind_glide = 0.0
	ind_state = state
	ind_target = target
	_ind_scale = scale
	_ind_shown = true
	indicator.visible = true
	indicator.mesh = mesh


func _glide_indicator(delta: float) -> void:
	if not _ind_shown:
		return
	var s := 1.0
	var want := ind_target
	if _ind_glide < 1.0:
		_ind_glide = minf(_ind_glide + delta / IND_GLIDE_S, 1.0)
		s = smoothstep(0.0, 1.0, _ind_glide)
		want = _ind_from.lerp(ind_target, s)
	else:
		# In a state it follows its spot closely; a sudden change of spot (a throw arc that now
		# reaches a roof, the cut moving to the next cells) is eased instead of jumped.
		want = indicator.global_position.lerp(ind_target, 1.0 - exp(-delta / 0.012))
	indicator.global_position = indicator.global_position.move_toward(want, IND_MAX_SPEED * delta)
	var sc := lerpf(_ind_from_scale, _ind_scale, s)
	indicator.scale = Vector3(sc, 1.0, sc)
	# Readable at night, dimmed like the work outline.
	var night := 0.0
	if Game.world and Game.world.get("day_night") != null:
		night = float(Game.world.day_night.night)
	indicator.transparency = 0.3 * night


func _record_moved(v: float) -> void:
	Snow.stat_player_moved += v
	Game.stats_add("snow_moved", v)


# -----------------------------------------------------------------------------
# Hands and shovel-type tools: hold LMB to fill, release to throw, RMB to push
# -----------------------------------------------------------------------------

func _shovel_type(delta: float, pos2: Vector2, fwd: Vector2, travel: Vector2, ui_block: bool) -> void:
	if data.angle_adjustable and not ui_block and Input.is_action_just_pressed("tool_angle") and Settings.accept_press("tool_angle"):
		var m := data.max_angle_deg
		blade_angle = m if blade_angle == 0.0 else (-m if blade_angle > 0.0 else 0.0)
		_hint("Blade angle: %s" % ("straight" if blade_angle == 0.0 else ("right" if blade_angle > 0.0 else "left")))
		AudioMgr.play("ui_click", -8.0)
	# Edges are tracked here (not with just_pressed/just_released) so a press or release is never
	# missed between physics frames.
	var fill_down := not ui_block and Input.is_action_pressed("primary")
	if fill_down and not _was_down:
		_hold_t = 0.0
		if recovery > 0.0:
			# Polish 6 §8.1: a press during the throw's recovery is ignored (not queued, no sound);
			# held through the end of the recovery, the scoop starts then.
			_press_wait = true
		else:
			_scoop_press()
	elif fill_down and _press_wait and recovery <= 0.0:
		_press_wait = false
		_scoop_press()
	# Release: throw whatever is carried (a partial load too) — polish 6 §8.1: unless it comes
	# sooner than min_scoop_hold_s after its press; then nothing is thrown and the load stays.
	if _was_down and not fill_down and _fill_pressed:
		_fill_pressed = false
		if load > 0.0 and not ui_block:
			if _hold_t + 1e-4 >= Catalog.balance.min_scoop_hold_s:
				_release_throw()
			else:
				_kept_short = true
	_was_down = fill_down
	if not fill_down:
		_fill_pressed = false
		_press_wait = false
	else:
		_hold_t += delta
	filling = fill_down and _fill_pressed
	pushing = _held("secondary", not ui_block and Input.is_action_pressed("secondary")) and not filling
	engaged = filling or pushing
	# Speed: carrying a heavy load slows you a little (a full sleigh a lot).
	var load_frac := clampf(load / maxf(_capacity(), 0.0001), 0.0, 1.0)
	var carry_mult := 1.0 - (0.45 if data.kind == ToolData.Kind.SLEIGH else 0.12) * load_frac
	if not work_ok:
		# Polish 5 §3: inside a building — no cut, no push, no indicator. A load carried in stays in
		# the hands (a release here keeps it: _release_throw).
		if filling or pushing:
			_hint("You can't work the snow from inside.")
		filling = false
		pushing = false
		engaged = false
		_stroke_valid = false
		landing = {}
		sweep_speed = lerpf(sweep_speed, 0.0, 1.0 - exp(-delta * 10.0))
		_indicate("", Vector3.ZERO, null, 1.0)
		player.speed_mult_tool = carry_mult
		_fade_loop(delta, -80.0)
		return
	if filling:
		_kept_short = false
		_fill(delta, pos2, fwd)
		player.speed_mult_tool = 0.85 * carry_mult
		if load > 0.0:
			_land_timer -= delta
			if _land_timer <= 0.0 or last_fill <= 0.0:
				_land_timer = 0.06
				landing = _landing(_throw_dist() * _pitch_factor(), data.throw_angle_deg)
			_landing_flags(landing)
		# Polish 4 §3: one indicator, where the snow goes next.
		if last_fill > 0.0:
			_indicate("pickup", _on_snow(last_cut_center), _ring_pick, maxf(data.width, 0.36))
		elif load > 0.0:
			_indicate("landing", landing.get("pos", indicator.global_position) + Vector3(0, 0.04, 0), _landing_mesh(landing), 1.0)
		else:
			var nxt := _next_cut_center(fwd)
			if nxt.x < INF:
				_indicate("preview", _on_snow(nxt), _ring_pick, maxf(data.width, 0.36))
			else:
				_indicate("", Vector3.ZERO, null, 1.0)
	else:
		_stroke_valid = false
		sweep_speed = lerpf(sweep_speed, 0.0, 1.0 - exp(-delta * 10.0))
		if load > 0.0 and not landing.is_empty():
			# A throw was refused (nowhere to land) and the load kept: show where it would land.
			if _kept_short:
				# Polish 6 §8.1: or a release sooner than min_scoop_hold_s kept it: then the spot
				# follows the aim, as while filling (it no longer stays where the last fill frame was).
				_land_timer -= delta
				if _land_timer <= 0.0:
					_land_timer = 0.06
					landing = _landing(_throw_dist() * _pitch_factor(), data.throw_angle_deg)
				_landing_flags(landing)
			_indicate("landing", landing.get("pos", indicator.global_position) + Vector3(0, 0.04, 0), _landing_mesh(landing), 1.0)
		else:
			_indicate("", Vector3.ZERO, null, 1.0)
		player.speed_mult_tool = carry_mult
	_glide_indicator(delta)
	if pushing:
		_push(delta, pos2, fwd, travel)
	else:
		_fade_loop(delta, -80.0)


## A scoop's press (hands, shovel-type tools): accepted or not by the per-second cap (polish 5 §2: a
## press over it is ignored — no scoop, and no throw on release).
func _scoop_press() -> void:
	_fill_pressed = Settings.accept_press("primary")
	if _fill_pressed and work_ok:
		Clock.drop_to_1x("work")   # polish 5 §9: starting to scoop stops fast-forward


## Aim point on the snow under the crosshair, kept within the tool's reach in front of the player.
func _aim_point() -> Vector2:
	var cam := player.active_camera()
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var base := Vector2(player.global_position.x, player.global_position.z)
	var aim := player.aim_dir()
	var reach := data.sweep_reach
	var p := base + aim * reach * 0.8
	var hit := Snow.raycast(from, dir, reach + (4.5 if player.third_person else 2.4))
	if hit["hit"]:
		var hp: Vector3 = hit["position"]
		p = Vector2(hp.x, hp.z)
	var d := p - base
	if d.length() > reach:
		d = d.normalized() * reach
	# Never behind you: keep the scoop at least a short way in front — unless you look right down
	# at your boots, then you can scoop the snow at your own feet (polish 2 §5).
	var steep := clampf((-rad_to_deg(player.pitch) - 55.0) / 20.0, 0.0, 1.0)
	var min_ahead := lerpf(0.35, 0.05, steep)
	var ahead := d.dot(aim)
	if ahead < min_ahead:
		d += aim * (min_ahead - ahead)
	return base + d


func _fill(delta: float, _pos2: Vector2, fwd: Vector2) -> void:
	var cap := _capacity()
	if load >= cap - 1e-6:
		_stroke_valid = false
		sweep_speed = lerpf(sweep_speed, 0.0, 1.0 - exp(-delta * 10.0))
		return
	var p := _aim_point()
	if not _stroke_valid:
		_stroke_prev = p
		_stroke_valid = true
		# Polish 6 §8.1: no opening bite. Digging in place takes its first bite one full cycle
		# after the press, not on it, and a new press keeps the re-cut memory (going over the same
		# cells again doesn't renew their bite early).
		_dig_timer = data.cycle_time
		_cycle_swept = 0.0
		# The opening bite's share: a load's first stroke may still take up to what its press used
		# to bite in place, but only as the sweep's fill where its strip comes up short (below). A
		# stroke that goes on filling a kept load gets none, so a click can't renew it.
		_foot_cells = PackedInt32Array()
		_foot_left = _fill_rate() * data.cycle_time * 0.4 if load <= 0.0 else 0.0
	var seg := p - _stroke_prev
	var seg_len := seg.length()
	var max_step := SWEEP_MAX * delta
	if seg_len > max_step:
		p = _stroke_prev + seg / seg_len * max_step
		seg = p - _stroke_prev
		seg_len = max_step
	sweep_speed = lerpf(sweep_speed, seg_len / maxf(delta, 0.001), 1.0 - exp(-delta * 12.0))
	var right := Vector2(-fwd.y, fwd.x)
	_sweep_side = lerpf(_sweep_side, clampf(seg.dot(right) / maxf(delta, 0.001) / 1.5, -1.0, 1.0), 1.0 - exp(-delta * 8.0))
	# Each pass of the scoop can cut one bite deep into every cell it crosses; a cell's bite is
	# used up gradually (the fill rate caps each frame) and renews once the scoop has left it.
	var cells := PackedInt32Array()
	var want := 0.0
	# Polish 6 §8.1: the dig cycle runs from the press for as long as the scoop is held, sweeping or
	# not: held still, it bites once per full cycle, the first one a cycle after the press. What the
	# sweep took during the cycle counts toward that bite, so a pause in a sweep (a mouse turning
	# back) adds no in-place lump on top of the sweep's own fill.
	_dig_timer -= delta
	var in_place := seg_len < 0.004
	if in_place:
		# Digging in place: one bite per cycle at the aim point.
		if _dig_timer > 0.0:
			return
		_dig_timer = data.cycle_time
		cells = Snow.cells_in_obb(p - fwd * data.reach * 0.5, fwd, data.width, data.reach)
		want = minf(cap - load, _fill_rate() * data.cycle_time * 0.4 - _cycle_swept)
		_cycle_swept = 0.0
	if not in_place:
		var dir := seg / seg_len
		cells = Snow.cells_in_obb(_stroke_prev - dir * 0.12, dir, data.width, seg_len + 0.24)
		want = minf(cap - load, _fill_rate() * delta)
	_stroke_prev = p
	if cells.is_empty() or want <= 0.0:
		return
	var acc := {"csum": Vector2.ZERO, "cn": 0, "road": 0.0}
	var v := _cut_cells(cells, want, acc)
	if not in_place and v < want - 1e-9 and _foot_left > 0.0:
		# Polish 6 §8.1: when the strip the sweep crossed comes up short (a short sweep across a
		# narrow trench, a pass over cells already cut, shallow snow), the rest of the frame's fill
		# comes from the scoop's footprint where it is now (the cells digging in place takes), at
		# most the opening bite's share in all for the load: the press's opening bite (gone), taken
		# at the fill rate as the sweep goes instead of in one frame. It reaches the trench walls as
		# that bite did. In deep snow most frames fill from the strip alone.
		_foot_cells = Snow.cells_in_obb(p - fwd * data.reach * 0.5, fwd, data.width, data.reach)
		var f := _cut_cells(_foot_cells, minf(want - v, _foot_left), acc)
		_foot_left -= f
		v += f
	if int(acc["cn"]) > 0:
		last_cut_center = acc["csum"] / float(acc["cn"])
	if not in_place:
		_cycle_swept += v
	if v <= 0.0:
		return
	Boxes.note_work(p)
	load += v
	load_road += float(acc["road"])
	last_fill = v
	_record_moved(v)
	_scoop_sfx -= delta
	if _scoop_sfx <= 0.0 and v > 0.0003:
		_scoop_sfx = 0.22
		var sfx := AudioMgr.variant("hand_scoop" if data.kind == ToolData.Kind.HANDS else "shovel_fill", 3)
		if not AudioMgr.has_sound(sfx):
			sfx = data.action_sound if data.action_sound != &"" else "hand_dig"
		AudioMgr.play_at(sfx, Vector3(p.x, player.global_position.y + 0.3, p.y), -5.0, randf_range(0.9, 1.12))
		var sp := Vector3(p.x, Snow.surface_height(p.x, p.y) + 0.05, p.y)
		SnowFX.burst(sp, maxi(3, int(data.particle_amount * 0.4)), 0.5)
		SnowFX.puff(sp, 0.18 + data.width * 0.25)
	if load >= cap - 1e-6:
		_hint("Full — release to throw." if data.kind != ToolData.Kind.HANDS else "Hands full — release to toss.")


## Cut up to `want` m3 from `cells`, each at most its bite left (the re-cut memory): returns the
## volume taken and adds the road share and the centre of the cut cells to `acc`.
func _cut_cells(cells: PackedInt32Array, want: float, acc: Dictionary) -> float:
	var bites := PackedFloat32Array()
	bites.resize(cells.size())
	for k in range(cells.size()):
		var i := cells[k]
		var e: Array = _cut_time.get(i, [-10.0, 0.0])
		if _clock - float(e[0]) > RECUT_S:
			e = [_clock, data.bite]     # a fresh pass over this cell
		bites[k] = float(e[1])
		_cut_time[i] = e
		# Polish 5 §3: snow the eye can only reach through a building isn't cut.
		if not _near_bld.is_empty() and _behind_building(_cell_center(i)):
			bites[k] = 0.0
	if _cut_time.size() > 600:
		for key in _cut_time.keys():
			if _clock - float(_cut_time[key][0]) > 1.0:
				_cut_time.erase(key)
	var r := Snow.cut(cells, bites, data.scrape_floor, want)
	var taken: PackedFloat32Array = r["taken"]
	for k in range(cells.size()):
		var e2: Array = _cut_time[cells[k]]
		e2[0] = _clock
		e2[1] = maxf(float(e2[1]) - taken[k], 0.0)
		if taken[k] > 0.0:
			acc["csum"] = acc["csum"] + _cell_center(cells[k])
			acc["cn"] = int(acc["cn"]) + 1
	acc["road"] = float(acc["road"]) + float(r["road_volume"])
	return float(r["volume"])


## Polish 5 §3: is the snow at cell centre c behind a building — does the line from the player's eye
## to its surface cross one?
func _behind_building(c: Vector2) -> bool:
	if _near_bld.is_empty():
		return false
	return _Buildings.blocks(player.head.global_position, Vector3(c.x, Snow.surface_height(c.x, c.y), c.y), _near_bld)


## Polish 5 §3: may a blade or an intake whose near edge is at `p` (world XZ) work the snow — the
## player outdoors and the line from the eye to it clear of buildings (a blade pressed against a
## wall from outside still works at its foot: REACH_SKIN)?
func can_work_at(p: Vector2) -> bool:
	if not work_ok:
		return false
	if _near_bld.is_empty():
		return true
	return not _Buildings.blocks(player.head.global_position, Vector3(p.x, Snow.surface_height(p.x, p.y), p.y), _near_bld, REACH_SKIN)


## Look down for a short drop at your feet, level or up for the full throw.
func _pitch_factor() -> float:
	var pitch := player.pitch
	return lerpf(0.35, 1.0, clampf((rad_to_deg(pitch) + 55.0) / 60.0, 0.0, 1.0))


func _release_throw() -> void:
	if not work_ok:
		# Polish 5 §3: no throwing from inside a building; the load stays in the hands.
		_hint("You can't throw snow from inside.")
		AudioMgr.play("ui_error", -12.0)
		return
	landing = _landing(_throw_dist() * _pitch_factor(), data.throw_angle_deg)
	_landing_flags(landing)
	if not landing["valid"]:
		_hint("Nowhere for the snow to land — keep holding it and aim somewhere else.")
		AudioMgr.play("ui_error", -12.0)
		return
	Clock.drop_to_1x("work")   # polish 5 §9: a throw stops fast-forward
	_indicate("", Vector3.ZERO, null, 1.0)
	if landing_back_in_box:
		_hint("That landed back in the box you're clearing — throw past the outline.")
	var spread := 0.25 + load * 2.5 if data.kind != ToolData.Kind.SLEIGH else 0.45 + load * 1.5
	ThrownSnow.spawn(Game.world, _hand_pos() + Vector3(0, 0.15, 0), player.aim_dir(), landing, load, data.throw_angle_deg, spread)
	var sfx := "hand_toss" if data.kind == ToolData.Kind.HANDS else "shovel_throw"
	if not AudioMgr.has_sound(sfx):
		sfx = "shovel_throw"
	AudioMgr.play_at(sfx, player.global_position, -4.0, randf_range(0.92, 1.08))
	load = 0.0
	load_road = 0.0
	cooldown = 0.15
	# Polish 6 §8.1: the throw's recovery; its follow-through (toss_t) plays out over it.
	recovery = data.throw_recovery_s
	_toss_len = maxf(0.42, data.throw_recovery_s)
	toss_t = 0.0


## Drop the load at your feet (tool switch, saving) — volume is never lost.
func dump_at_feet(_force: bool) -> void:
	if load <= 0.0:
		return
	var pos2 := Vector2(player.global_position.x, player.global_position.z)
	var p := pos2 + player.forward2() * 0.6
	# Polish 5 §3 (Decision 12): no road rule — the street is a place like any other (it used to
	# refuse a dump there unless forced). Indoors the cells are walls: it spills outside.
	Snow.deposit(p, load, 0.35, true)
	AudioMgr.play_at(AudioMgr.variant("snow_land", 3), player.global_position, -6.0)
	SnowFX.burst(Vector3(p.x, player.global_position.y + 0.2, p.y), 10, 0.6)
	load = 0.0
	load_road = 0.0


func _push(delta: float, pos2: Vector2, fwd: Vector2, travel: Vector2) -> void:
	var hw := _push_half_width()
	var face := fwd.rotated(deg_to_rad(blade_angle))
	var lead := 0.5 if data.kind == ToolData.Kind.HANDS else (0.85 if data.kind == ToolData.Kind.SLEIGH else 0.62)
	var center := pos2 + fwd * lead
	var adv := maxf(travel.dot(fwd), 0.0)
	var push_dist := 0.3 if data.kind == ToolData.Kind.HANDS else 0.38
	if not can_work_at(center - fwd * (adv + 0.07)):
		# Polish 5 §3: indoors, or the blade is on the far side of a building: nothing moves.
		player.speed_mult_tool = data.engaged_speed_mult * _ItemUpgrades.mult(data.id, &"push_speed")
		_fade_loop(delta, -80.0)
		return
	# Polish 5 §3 (Decision 12): no road rule — the berm carries over the curb onto the street.
	var r := Snow.blade_push(center, face, hw, adv + 0.07, data.scrape_floor, false, push_dist)
	_guard_behind(center, fwd, hw + 0.15)
	var moved: float = r["moved"]
	_record_moved(moved)
	if moved > 0.0005:
		Boxes.note_work(center)
	var ratio: float = r["berm"] / maxf(_push_strength(), 0.005)
	player.speed_mult_tool = data.engaged_speed_mult * _ItemUpgrades.mult(data.id, &"push_speed") / (1.0 + ratio * ratio)
	if r["kept"] > 0.002:
		_hint("The snow can't go any further this way.")
	elif ratio > 2.0 and player.current_speed < 0.3:
		_hint("Too much snow to push — scoop some away or push from another side.")
	var activity := clampf(moved / maxf(delta, 0.001) * 6.0, 0.0, 1.0)
	var loop := "push_scrape" if data.kind != ToolData.Kind.HANDS else ("push_snow" if AudioMgr.has_sound("push_snow") else "push_scrape")
	_set_loop(loop)
	_fade_loop(delta, lerpf(-24.0, -4.0, activity) if player.current_speed > 0.15 else -32.0)
	if moved > 0.0005 and randf() < 0.35:
		var bp := center + face * 0.45
		SnowFX.burst(Vector3(bp.x, player.global_position.y + 0.25, bp.y), maxi(2, int(data.particle_amount * 0.4)), 0.7, Vector3(face.x, 1.0, face.y).normalized())


## Keep the berm from slumping back over the blade into the strip just cleared.
func _guard_behind(center: Vector2, fwd: Vector2, hw: float) -> void:
	var side := Vector2(-fwd.y, fwd.x) * hw
	var back := center - fwd * 1.4
	var pts := [center + side, center - side, back + side, back - side]
	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	Snow.set_blade_guard(Rect2(mn, mx - mn))


func _fade_loop(delta: float, target: float) -> void:
	_loop_vol = move_toward(_loop_vol, target, delta * 60.0)
	loop_player.volume_db = _loop_vol
	if _loop_vol <= -79.0 and loop_player.playing:
		loop_player.stop()
		loop_player.set_meta("name", "")


# -----------------------------------------------------------------------------
# Electric shovel: hold LMB to chew through snow and toss it ahead; RMB pushes
# -----------------------------------------------------------------------------

func _electric(delta: float, pos2: Vector2, fwd: Vector2, travel: Vector2, ui_block: bool) -> void:
	filling = _held("primary", not ui_block and Input.is_action_pressed("primary"))
	pushing = _held("secondary", not ui_block and Input.is_action_pressed("secondary")) and not filling
	engaged = filling or pushing
	# Polish 6 §8.1: the chute throws on its own rhythm (throw_recovery_s), held or not, so starting
	# and stopping by clicking adds no throws: what it took in goes out on the next beat.
	_stream_timer -= delta
	if not work_ok:
		# Polish 5 §3: inside a building the shovel doesn't touch the snow (no intake, no push, no
		# indicator); what it already chewed is thrown where it was going.
		if filling or pushing:
			_hint("You can't work the snow from inside.")
		filling = false
		pushing = false
		engaged = false
		indicator.visible = false
		player.speed_mult_tool = 1.0
		_fade_loop(delta, -80.0)
		_flush_stream()
		return
	if pushing:
		indicator.visible = false
		_push(delta, pos2, fwd, travel)
		_stream_beat()
		return
	if not filling:
		indicator.visible = false
		player.speed_mult_tool = 1.0
		_fade_loop(delta, -80.0)
		_stream_beat()
		return
	player.speed_mult_tool = data.engaged_speed_mult
	if not can_work_at(pos2 + fwd * 0.3):
		# Polish 5 §3: the intake is on the far side of a building: no intake, no indicator.
		indicator.visible = false
		_fade_loop(delta, -80.0)
		_stream_beat()
		return
	_land_timer -= delta
	if _land_timer <= 0.0:
		_land_timer = 0.1
		landing = _landing(_throw_dist(), data.throw_angle_deg)
	_show_indicator(landing)
	_set_loop("electric_motor")
	_fade_loop(delta, -6.0)
	if not landing.get("valid", false):
		_hint("Nowhere for the snow to land — aim somewhere else.")
		return
	var r := Snow.intake(pos2 + fwd * 0.3, fwd, data.width, data.reach, data.rate * delta, data.scrape_floor)
	if float(r["volume"]) > 0.0:
		Boxes.note_work(pos2 + fwd * 0.5)
	_stream_acc += r["volume"]
	_record_moved(r["volume"])
	_stream_beat()


## The electric shovel's chute: what it took in goes out at most once per throw_recovery_s.
func _stream_beat() -> void:
	if _stream_timer <= 0.0 and _stream_acc > 0.0:
		_stream_timer = data.throw_recovery_s
		_flush_stream()


## Polish 6 §8.1: throw what the electric shovel's chute still holds now (saving: the game root lands
## it with the rest of the snow in flight).
func flush_chute() -> void:
	_flush_stream()


func _flush_stream() -> void:
	if _stream_acc <= 0.0:
		return
	if landing.get("valid", false):
		ThrownSnow.spawn(Game.world, _hand_pos() - Vector3(0, 0.6, 0), player.aim_dir(), landing, _stream_acc, data.throw_angle_deg, 0.45)
	else:
		var p := Vector2(player.global_position.x, player.global_position.z) + player.forward2() * 0.5
		Snow.deposit(p, _stream_acc, 0.4, true)
	_stream_acc = 0.0


# -----------------------------------------------------------------------------
# Drop
# -----------------------------------------------------------------------------

func drop_tool() -> void:
	if load > 0.0:
		dump_at_feet(true)
	# Polish 5 §13: the heated pad is put down (on your own lot only), not dropped like a tool.
	if _Equipment.pad_carried():
		var why := _Equipment.put_down_pad(player, player.forward2(), player.yaw)
		if why != "":
			_hint(why)
			return
		if Game.world and Game.world.has_method("refresh_pad"):
			Game.world.refresh_pad()
		AudioMgr.play_at("pickup_item", player.global_position, -6.0, 0.7)
		return
	var id := Game.take_selected()
	if id == "":
		return
	var p := player.global_position + Vector3(player.forward2().x, 0, player.forward2().y) * 0.8
	if Game.world and Game.world.has_method("spawn_tool_item"):
		Game.world.spawn_tool_item(id, Vector3(p.x, 0, p.z), player.yaw)
	AudioMgr.play_at("pickup_item", p, -6.0, 0.8)


# -----------------------------------------------------------------------------
# First-person viewmodel (polish §1)
# -----------------------------------------------------------------------------

## Hand basis from the direction the fingers point and the direction the back of the hand faces.
static func _hb(fingers: Vector3, back: Vector3) -> Basis:
	var z := -fingers.normalized()
	var y := (back - z * back.dot(z)).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Hand targets for bare hands, in camera space: idle, cupped (holding), scooping, flat palms
## (pushing) and the forward toss.
func _hand_targets() -> Array:
	var out := []
	var walk := sin(_clock * 7.5) * clampf(player.current_speed / 4.0, 0.0, 1.0)
	var holding := load > 0.00005
	var dip := sin(_clock * 9.0) * clampf(sweep_speed / 1.5, 0.0, 1.0)
	for k in [0, 1]:
		var s := -1.0 if k == 0 else 1.0
		var t := {}
		if pushing:
			# Flat palms forward, fingers up, shoving the snow ahead.
			var shove := 0.03 * sin(_clock * 6.0) * clampf(player.current_speed / 2.0, 0.0, 1.0)
			t["pos"] = Vector3(0.16 * s, -0.21 + 0.01 * walk, -0.5 - shove)
			t["basis"] = _hb(Vector3(0.08 * s, 1.0, -0.25), Vector3(0.05 * s, 0.1, 1.0))
			t["curl"] = 0.05
			t["thumb"] = 0.05
		elif toss_t < 1.0:
			# Forward toss: from the low cup up and out, palms opening forward.
			var e := _ease(toss_t)
			var up := sin(clampf(toss_t * 1.4, 0.0, 1.0) * PI * 0.5)
			t["pos"] = Vector3(0.07 * s, lerpf(-0.32, -0.08, up) - 0.12 * maxf(e - 0.75, 0.0), lerpf(-0.44, -0.68, up))
			t["basis"] = _hb(Vector3(0.18 * s, lerpf(0.2, 0.75, up), -1.0), Vector3(-0.5 * s, -1.0, lerpf(0.0, 0.8, up)))
			t["curl"] = lerpf(0.6, 0.05, up)
			t["thumb"] = lerpf(0.2, 0.0, up)
		elif filling and load < _capacity() - 1e-6:
			# Scooping: cupped hands pitched down into the snow, sweeping with the mouse.
			var sway := _sweep_side * 0.06
			t["pos"] = Vector3(0.058 * s + sway, -0.3 - 0.02 * dip, -0.52 - 0.03 * dip)
			t["basis"] = Basis(Vector3.RIGHT, deg_to_rad(-38.0)) * _hb(Vector3(-0.3 * s, 0.0, -1.0), Vector3(-0.55 * s, -1.0, 0.0))
			t["curl"] = 0.42
			t["thumb"] = 0.15
		elif holding or filling:
			# Cupped hands holding the snow.
			t["pos"] = Vector3(0.055 * s, -0.245 + 0.008 * walk, -0.5)
			t["basis"] = _hb(Vector3(-0.3 * s, 0.05, -1.0), Vector3(-0.55 * s, -1.0, 0.0))
			t["curl"] = 0.36
			t["thumb"] = 0.1
		else:
			# Idle: relaxed hands at the bottom of the view.
			t["pos"] = Vector3(0.24 * s, -0.285 + 0.012 * walk * s, -0.46)
			t["basis"] = _hb(Vector3(0.1 * s, -0.25, -1.0), Vector3(-0.5 * s, 1.0, 0.1))
			t["curl"] = 0.35
			t["thumb"] = 0.3
		out.append(t)
	return out


## Transform of a held tool in camera space for the current action. The grip sits low at the
## right hip, the shaft runs forward and down so the blade is in view in front of the player.
func _tool_xform() -> Transform3D:
	var walk := sin(_clock * 7.5) * clampf(player.current_speed / 4.0, 0.0, 1.0)
	var sleigh := data.kind == ToolData.Kind.SLEIGH
	var pos := Vector3(0.24 if not sleigh else 0.0, -0.42, -0.42 if not sleigh else -0.36)
	var pitch := 34.5
	var yaw := 12.0 if not sleigh else 0.0
	var roll := 0.0
	if pushing:
		pos = Vector3(0.1 if not sleigh else 0.0, -0.5 + 0.01 * walk, -0.36 - 0.03 * sin(_clock * 6.0) * clampf(player.current_speed / 2.0, 0.0, 1.0))
		pitch = 24.0
		yaw = (5.0 if not sleigh else 0.0) - blade_angle
	elif toss_t < 1.0:
		var up := sin(clampf(toss_t * 1.4, 0.0, 1.0) * PI * 0.5)
		pos = Vector3(lerpf(0.2, 0.12, up), lerpf(-0.48, -0.26, up), lerpf(-0.4, -0.55, up))
		pitch = lerpf(26.0, 72.0, up)
		yaw = lerpf(12.0, 4.0, up)
		roll = lerpf(0.0, -8.0, up)
	elif filling and load < _capacity() - 1e-6:
		var dip := sin(_clock * 9.0) * clampf(sweep_speed / 1.5, 0.0, 1.0)
		pos = Vector3((0.2 if not sleigh else 0.0) + _sweep_side * 0.06, -0.48 - 0.02 * dip, -0.4 - 0.03 * dip)
		pitch = 24.0
		yaw = (12.0 if not sleigh else 0.0) - _sweep_side * 10.0
	elif load > 0.00005:
		pos = Vector3(0.22 if not sleigh else 0.0, -0.4 + 0.006 * walk, -0.44)
		pitch = 40.0
	else:
		pos.y += 0.008 * walk
	if data.kind == ToolData.Kind.ELECTRIC_SHOVEL and filling:
		pos.y -= 0.04
		pitch = 26.0
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), deg_to_rad(roll)))
	return Transform3D(b, pos)


## Where the hands hold the current tool, in the tool's own space (origin = the T-grip at the top
## of the shaft, shaft running toward ToolModels.tip): [top (right) hand, lower (left) hand].
## Each entry is {point, basis}: the point the hand closes around and the hand's orientation
## (local -Z fingers, -Y palm, X across the knuckles — the FPArms / mitten convention).
func _grip_frames() -> Array:
	var x := Vector3.RIGHT
	if data.kind == ToolData.Kind.SLEIGH:
		# Both hands overhand on the crossbar of the U-handle.
		var ds := Vector3(0, cos(deg_to_rad(-142.0)), sin(deg_to_rad(-142.0)))
		var ns := x.cross(ds).normalized()
		var bs := Basis(x, ns, -ds)
		return [{"point": Vector3(0.19, 0, 0), "basis": bs}, {"point": Vector3(-0.19, 0, 0), "basis": bs}]
	var d := ToolModels.tip(tool_id).normalized()
	var n := x.cross(d).normalized()          # perpendicular to the shaft, pointing up
	var along := 0.45
	match data.kind:
		ToolData.Kind.PUSHER, ToolData.Kind.SCRAPER:
			along = 0.52
		ToolData.Kind.ELECTRIC_SHOVEL:
			along = 0.42
	# Top hand overhand on the T-grip (knuckles along the crossbar, fingers down the shaft);
	# lower hand under the shaft, palm up, fingers wrapping round it from the left.
	return [{"point": Vector3.ZERO, "basis": Basis(x, n, -d)}, {"point": d * along, "basis": Basis(d, -n, -x)}]


## Both hands on a held tool, camera space: right hand on the grip at the top of the shaft, left
## hand around the shaft lower down (both on the crossbar for the sleigh). The hand is placed so
## the bar passes through its closed fist, whatever pose or angle the tool is held at.
func _tool_hand_targets(xf: Transform3D) -> Array:
	var frames := _grip_frames()
	var out := []
	for k in [1, 0]:   # left hand first (FPArms order), then right
		var f: Dictionary = frames[k]
		var hb: Basis = xf.basis.orthonormalized() * (f["basis"] as Basis)
		var p: Vector3 = xf * (f["point"] as Vector3) - hb * GRIP_IN_HAND
		out.append({"pos": p, "basis": hb, "curl": 0.95, "thumb": 0.8})
	return out


func _animate_viewmodel(delta: float) -> void:
	if player.third_person:
		return
	var vm := player.viewmodel
	vm.visible = player.state == "foot"
	if _carrying():
		arms.update_pose(_carry_targets(), delta)
		held_fp.visible = true
		blade_fp.visible = true
		held_fp.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(10), 0, 0)), Vector3(0.0, -0.3, -0.42))
		if _Equipment.is_equipment(Game.carried):
			held_fp.transform = Transform3D(Basis(), Vector3(0.0, -0.3, -0.5))   # polish 5 §13: the rolled pad
		blade_fp.transform = held_fp.transform * Transform3D(Basis(), ToolModels.tip(Game.carried))
		return
	if held_fp.mesh != null:
		# Looking down at the work, the tool is anchored to the body: the blade rests on (and sweeps
		# through) the snow where you aim. Looking up toward the horizon it's carried in view.
		var w := smoothstep(-0.5, -0.12, player.pitch)
		var xf := _tool_body_xform()
		var cam_level := Basis(Vector3.RIGHT, -player.pitch)
		var bb := cam_level * _blade_body
		if w > 0.0:
			var cx := _tool_xform()
			xf = xf.interpolate_with(cx, w)
			bb = bb.slerp(cx.basis, w)
		held_fp.transform = held_fp.transform.interpolate_with(xf, 1.0 - exp(-delta * 16.0))
		var tipp := held_fp.transform * ToolModels.tip(tool_id)
		var bt := Transform3D(bb.orthonormalized(), tipp)
		blade_fp.transform = Transform3D(blade_fp.transform.basis.slerp(bt.basis, 1.0 - exp(-delta * 16.0)).orthonormalized(), tipp)
		arms.update_pose(_tool_hand_targets(held_fp.transform), delta, 30.0)
		_update_vm_clip(w < 0.5 or pushing or filling)
	else:
		arms.update_pose(_hand_targets(), delta)
		vm_clip_y = -1000.0
		RenderingServer.global_shader_parameter_set("vm_snow_y", vm_clip_y)


## Where the shrunk first-person blade really is in the world, and the snow surface there: the
## tool's clip shader hides what's under the snow (a blade pushed into deep snow disappears in).
func _update_vm_clip(working: bool) -> void:
	var eye := player.fp_cam.global_position
	if not working:
		# Just carrying it in view (looking ahead): always show the whole tool and its load.
		vm_clip_y = -1000.0
		RenderingServer.global_shader_parameter_set("vm_snow_y", vm_clip_y)
		return
	var real := eye + (blade_fp.global_position - eye) / Player.VM_SCALE
	var surf := Snow.surface_height(real.x, real.z)
	# Only clip when the blade is actually down in the snow ahead of you, never when it's held up.
	vm_clip_y = surf if real.y < surf + 0.4 else -1000.0
	RenderingServer.global_shader_parameter_set("vm_eye", eye)
	RenderingServer.global_shader_parameter_set("vm_snow_y", vm_clip_y)


## Shaft geometry of the held tool model: handle length from the grip to the blade, and how far
## below horizontal the shaft runs when the blade sits flat (see ToolModels).
func _shaft() -> Vector2:
	match data.kind:
		ToolData.Kind.PUSHER, ToolData.Kind.SCRAPER:
			return Vector2(1.35, 55.0)
		ToolData.Kind.SLEIGH:
			return Vector2(1.13, 48.6)
		ToolData.Kind.ELECTRIC_SHOVEL:
			return Vector2(1.0, 55.0)
	return Vector2(1.05 if data.tier <= 1 else 1.25, 55.0)


## Held tool in camera space, built in body space (eye at the origin, yaw only) so it lies on the
## ground ahead: the blade reaches for a target on the snow, the grip stays near the right hip.
func _tool_body_xform() -> Transform3D:
	var eye := player.fp_cam.global_position
	var pos2 := Vector2(player.global_position.x, player.global_position.z)
	var fwd := player.forward2()
	var cap := _capacity()
	var target2 := pos2 + fwd * 1.05
	var lift := 0.02
	if pushing:
		target2 = pos2 + fwd * (0.95 if data.kind != ToolData.Kind.SLEIGH else 1.05)
	elif toss_t < 1.0:
		lift = 0.25 + 1.1 * sin(clampf(toss_t * 1.4, 0.0, 1.0) * PI * 0.5)
		target2 = pos2 + fwd * lerpf(0.9, 1.25, toss_t)
	elif filling and load < cap - 1e-6:
		target2 = _aim_point()
		target2 = pos2 + (target2 - pos2).limit_length(maxf(_shaft().x * 0.95, 0.8))
	elif load > 0.00005:
		lift = 0.3
		target2 = pos2 + fwd * 0.95
	var surf := Snow.surface_height(target2.x, target2.y)
	if pushing:
		surf = Snow.ground_at(target2.x, target2.y) + minf(Snow.depth_at(target2.x, target2.y), 0.25)
	var world_t := Vector3(target2.x, surf + lift, target2.y)
	var yaw_b := Basis(Vector3.UP, player.yaw)
	var t := yaw_b.inverse() * (world_t - eye)
	var sh := _shaft()
	var gx := 0.2
	if data.kind == ToolData.Kind.SLEIGH:
		gx = 0.0
	elif pushing:
		gx = 0.1     # pushing, both hands come in front of the body
	var g := Vector3(gx, -0.75, -0.28)
	for _k in range(2):
		var v := t - g
		g = t - v.normalized() * sh.x
		g = Vector3(clampf(g.x, -0.15, 0.35), clampf(g.y, -1.05, -0.4), clampf(g.z, -0.75, 0.05))
	var v2 := t - g
	var yaw := atan2(-v2.x, -v2.z)
	var elev := atan2(v2.y, Vector2(v2.x, v2.z).length())
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, elev + deg_to_rad(sh.y))
	# The blade lies (nearly) flat on the snow whatever the shaft angle: tipped back to hold a
	# load, flipped up as it throws, edge-down while scooping.
	var tilt := 0.0
	if pushing:
		tilt = 0.0
	elif toss_t < 1.0:
		tilt = lerpf(12.0, 65.0, sin(clampf(toss_t * 1.4, 0.0, 1.0) * PI * 0.5))
	elif filling and load < cap - 1e-6:
		tilt = -4.0
	elif load > 0.00005:
		tilt = 14.0
	# Pushing, the blade faces the way you walk (square, or at the scraper's angle), not the shaft.
	var blade_yaw := -deg_to_rad(blade_angle) if pushing else yaw
	_blade_body = Basis(Vector3.UP, blade_yaw) * Basis(Vector3.RIGHT, deg_to_rad(tilt))
	if pushing and blade_angle != 0.0:
		b = b * Basis(Vector3.UP, deg_to_rad(-blade_angle))
	# Body space -> camera space (undo the head pitch).
	return Transform3D(Basis(Vector3.RIGHT, -player.pitch), Vector3.ZERO) * Transform3D(b, g)


func _carry_targets() -> Array:
	var out := []
	for s in [-1.0, 1.0]:
		out.append({"pos": Vector3(0.2 * s, -0.3, -0.4), "basis": _hb(Vector3(-0.3 * s, 0.2, -1.0), Vector3(-0.8 * s, -0.4, 0.0)), "curl": 0.7, "thumb": 0.4})
	return out


# -----------------------------------------------------------------------------
# Third person: matching body poses and the tool in the hands
# -----------------------------------------------------------------------------

func _animate_tp() -> void:
	var m := player.model
	var hands := data.kind == ToolData.Kind.HANDS
	if pushing:
		m.set_pose("hands_push" if hands else "push")
	elif toss_t < 1.0:
		m.set_pose("hands_toss" if hands else "throw")
		m.action_t = toss_t
	elif filling and load < _capacity() - 1e-6:
		m.set_pose("hands_scoop" if hands else "dig")
		m.action_t = fmod(_clock * 1.6, 1.0)
		m.sweep = _sweep_side
	elif load > 0.00005 or filling:
		m.set_pose("hands_hold" if hands else "carry")
	elif not hands and not _carrying() and player.current_speed < 2.5:
		m.set_pose("tool_idle")
	else:
		m.set_pose("idle")
	_orient_tp_tool()


## Third-person held tool: grip in the right hand, blade forward and down in front of the body.
func _orient_tp_tool() -> void:
	if held_tp.mesh == null or not player.third_person:
		return
	held_tp.visible = player.state == "foot"
	if not held_tp.visible:
		return
	var m := player.model
	if _carrying() or data == null or data.kind == ToolData.Kind.HANDS:
		# A carried item simply sits in the right hand.
		held_tp.global_transform = Transform3D(Basis(Vector3.UP, player.yaw), m.hand_r.global_position)
		return
	# The tool is placed against the body for the pose (top grip in front of the right hip, the
	# shaft pitched for the action), then both arms reach it: right mitten on the T-grip, left
	# mitten around the shaft lower down (polish 2 §1). Pitch raises the blade (positive).
	var t := clampf(m.action_t, 0.0, 1.0)
	var pitch := 18.0
	var grip := Vector3(0.08, 1.06, -0.36)       # model space (-Z forward), metres above the soles
	match m.pose:
		"push":
			pitch = 16.0
			grip = Vector3(0.0, 1.0, -0.46)
		"carry":
			pitch = 30.0
			grip = Vector3(0.06, 1.1, -0.4)
		"dig":
			pitch = 6.0 + 8.0 * sin(t * PI)
			grip = Vector3(0.06 + 0.04 * m.sweep, 0.98 - 0.05 * sin(t * PI), -0.44)
		"throw":
			var k := sin(clampf(t * 1.4, 0.0, 1.0) * PI * 0.5)
			pitch = lerpf(12.0, 58.0, k)
			grip = Vector3(lerpf(0.08, 0.04, k), lerpf(1.0, 1.3, k), lerpf(-0.38, -0.48, k))
	# Like a real shoveller, the shaft runs across the front of the body (top hand at the right
	# hip, blade out in front of the middle) so the left hand can reach well down the shaft.
	# Pushing, the blade stays square in front.
	var across := 0.22
	if m.pose == "push":
		across = 0.0
		grip.x = 0.0
	if data.kind == ToolData.Kind.SLEIGH:
		grip.y += 0.06
		grip.x = 0.0
		across = 0.0
	var yaw := player.yaw + across + deg_to_rad(-blade_angle if pushing else 0.0)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	var frames := _grip_frames()
	var top: Vector3 = frames[0]["point"]
	var low: Vector3 = frames[1]["point"]
	var grip_w := m.global_transform * grip
	var xf := Transform3D(b, grip_w - b * top)
	held_tp.global_transform = xf
	m.reach(false, xf * top)
	# The lower hand slides up the shaft if the pose puts the usual spot out of the left arm's reach.
	var sh := m.shoulder_global(true)
	var reach_len := (CharacterModel.ARM_A + CharacterModel.ARM_B + CharacterModel.SHOULDER_SLIDE) * m.global_transform.basis.get_scale().x - 0.01
	var f := 1.0
	if data.kind != ToolData.Kind.SLEIGH:
		while f > 0.3 and sh.distance_to(xf * (low * f)) > reach_len:
			f -= 0.05
	tp_low_frac = f
	tp_grip_ok = m.reach(true, xf * (low * f))
