class_name FramedPhoto
extends Node3D
## Polish 4 §5: a framed photograph on the wall beside the player's front door: the player's
## character standing by the pickup truck on a sunny winter day with the small shovel.
## Polish 5 §4: the photo is a hint — the shovel stands planted in the snow exactly where it lies
## buried on the first morning, relative to the truck (beside the driver's door, the side away
## from the house), seen from that side.
##
## The photo is rendered once from the game's own models — CharacterModel with the player's look,
## the truck's mesh from VehicleModels, ToolModels' small shovel (whatever that model is when the
## photo is taken) — in a SubViewport with its own World3D, camera and lights, then copied to a
## static texture and the viewport is freed. The truck is a plain mesh (no vehicle, physics body,
## registration or roof snow) and the photo scene changes no autoload (it only reads where the
## truck and the shovel start). Headless runs (no renderer) skip the capture and keep a plain
## placeholder. The print is a normal shaded material, so it darkens with the room at night.

const PHOTO := Vector2i(720, 480)      # 3:2 print, pixels
const PRINT := Vector2(0.42, 0.28)     # metres
const MAT_W := 0.07                    # the mat around the print
const FRAME_W := 0.035                 # the wooden moulding
const DEPTH := 0.03                    # frame depth off the wall
# The photo scene (polish 5 §4), for the passenger side (+X); x is mirrored for the driver's side.
const CAM := Vector3(7.2, 1.3, -1.6)    # camera, truck frame
const LOOK := Vector3(0.6, 0.95, -0.35) # what it looks at
const CHAR := Vector2(1.75, -2.15)     # where the character stands (x, z): by the front wheel
const SHOVEL_TURN_DEG := 18.0          # the scoop turned this far off the camera
const SHOVEL_LEAN_DEG := 6.0           # the shaft leans back a little
const SHOVEL_SINK := 0.05              # the blade's lowest point this far into the snow

var texture: Texture2D
var captured := false
var capture_ms := -1
var _print_mat: StandardMaterial3D


## A framed photo whose centre is at `xf.origin` on the wall, the print facing along xf.basis.z.
static func make(parent: Node, xf: Transform3D) -> FramedPhoto:
	var f := FramedPhoto.new()
	f.name = "FramedPhoto"
	parent.add_child(f)
	f.global_transform = xf
	f._orient_print()
	return f


## Polish 5 §4: a mirrored house transform (the player's lot is one: determinant -1) mirrors the
## print quad, so its UVs are flipped back. This must run once the frame has its place on the wall:
## pass 4 checked in _ready, which runs inside add_child before make() sets the transform, so the
## flip never happened and the print hung mirror-reversed.
func _orient_print() -> void:
	var mirrored := global_transform.basis.determinant() < 0.0
	_print_mat.uv1_scale = Vector3(-1, 1, 1) if mirrored else Vector3.ONE
	_print_mat.uv1_offset = Vector3(1, 0, 0) if mirrored else Vector3.ZERO


static func outer_size() -> Vector2:
	return PRINT + Vector2.ONE * (MAT_W + FRAME_W) * 2.0


func _ready() -> void:
	_build_frame()
	var ph := Image.create(8, 8, false, Image.FORMAT_RGB8)
	ph.fill(Color(0.72, 0.74, 0.78))
	texture = ImageTexture.create_from_image(ph)
	_print_mat.albedo_texture = texture
	if DisplayServer.get_name() == "headless":
		return
	_capture.call_deferred()


func _build_frame() -> void:
	var outer := outer_size()
	var kit := MeshKit.new()
	var wood := Mats.wood(Color(0.42, 0.27, 0.16), 0.0)
	var z := DEPTH * 0.5
	# Moulding: four bars around the mat.
	var ow := outer.x
	var oh := outer.y
	kit.bevel_box(wood, Transform3D(Basis(), Vector3(0, oh * 0.5 - FRAME_W * 0.5, z)), Vector3(ow, FRAME_W, DEPTH), 0.006)
	kit.bevel_box(wood, Transform3D(Basis(), Vector3(0, -oh * 0.5 + FRAME_W * 0.5, z)), Vector3(ow, FRAME_W, DEPTH), 0.006)
	kit.bevel_box(wood, Transform3D(Basis(), Vector3(-ow * 0.5 + FRAME_W * 0.5, 0, z)), Vector3(FRAME_W, oh - FRAME_W * 2.0, DEPTH), 0.006)
	kit.bevel_box(wood, Transform3D(Basis(), Vector3(ow * 0.5 - FRAME_W * 0.5, 0, z)), Vector3(FRAME_W, oh - FRAME_W * 2.0, DEPTH), 0.006)
	# Backing board and the off-white mat.
	kit.box(Mats.std(Color(0.3, 0.26, 0.22), 0.9), Transform3D(Basis(), Vector3(0, 0, 0.004)), Vector3(ow - 0.01, oh - 0.01, 0.008))
	kit.box(Mats.std(Color(0.93, 0.91, 0.86), 0.95), Transform3D(Basis(), Vector3(0, 0, 0.012)), Vector3(ow - FRAME_W * 2.0, oh - FRAME_W * 2.0, 0.004))
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = kit.commit()
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)
	# The print, just in front of the mat.
	var q := QuadMesh.new()
	q.size = PRINT
	var pr := MeshInstance3D.new()
	pr.name = "Print"
	pr.mesh = q
	pr.position = Vector3(0, 0, 0.0145)
	pr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_print_mat = StandardMaterial3D.new()
	_print_mat.roughness = 0.75
	# Polish 5 §4: a matte print. Its own sheen and the glass's reflection of the bright sky laid a
	# milky veil over it on the wall (blacks lifted from 0.18 to 0.30 at noon, colour −15 %).
	_print_mat.metallic_specular = 0.0
	# Mirrored lots have a mirrored house transform: the print is flipped back by _orient_print().
	pr.material_override = _print_mat
	add_child(pr)
	# A hint of glass over it.
	var g := MeshInstance3D.new()
	g.name = "Glass"
	var gq := QuadMesh.new()
	gq.size = outer - Vector2.ONE * FRAME_W * 2.0
	g.mesh = gq
	g.position = Vector3(0, 0, DEPTH - 0.006)
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.85, 0.9, 1.0, 0.04)
	gm.roughness = 0.04
	gm.metallic_specular = 0.3
	g.material_override = gm
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)


# -----------------------------------------------------------------------------
# The photo itself
# -----------------------------------------------------------------------------

func _capture() -> void:
	var t0 := Time.get_ticks_usec()
	var vp := SubViewport.new()
	vp.size = PHOTO
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_2X
	# Polish 5 §4: nothing is drawn until the scene is in place. The nodes get their places (the
	# camera, the sun, the character, the shovel…) after they enter the tree, and those transforms
	# only reach the renderer when the engine flushes its transform notifications. Started from the
	# menu's New Game (a scene change), pass 4's single frame was drawn before that flush: the
	# camera still sat at the scene's origin under the truck, and the print showed the truck's
	# underside against the sky instead of the photo. So: build with drawing off, let one frame go
	# by, then draw once.
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	build_scene(vp)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		texture = ImageTexture.create_from_image(img)
		_print_mat.albedo_texture = texture
		captured = true
	vp.queue_free()
	@warning_ignore("integer_division")
	capture_ms = int((Time.get_ticks_usec() - t0) / 1000)


## Where the shovel stands in the photo: where it lies buried on the first morning, in the truck's
## frame (forward -Z, the driver on the left, -X), from the game's own start spots (polish 5 §4).
static func shovel_spot_in_truck_frame() -> Vector3:
	var ts: Dictionary = Game.truck_start()
	var sp: Vector2 = Game.shovel_spot()
	var rel: Vector3 = Vector3(sp.x, 0.0, sp.y) - (ts["pos"] as Vector3)
	return Basis(Vector3.UP, float(ts["yaw"])).inverse() * Vector3(rel.x, 0.0, rel.z)


## The photo scene: snowy ground, a few spruces, the pickup, the player beside it and the small
## shovel planted in the snow beside him, under a clear winter sky, in a three-quarter front view
## from the shovel's side of the truck. Truck frame: forward is -Z, the driver sits on the left
## (-X), so the passenger door is on the right (+X). Pass 4 framed the passenger side with the
## shovel leaning on that door; the shovel lies buried on the driver's side, so everything that
## depends on the side is mirrored by `s` (-1 for the driver's side).
static func build_scene(vp: SubViewport) -> void:
	var spot := shovel_spot_in_truck_frame()
	var s := -1.0 if spot.x < 0.0 else 1.0
	var root := Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.34, 0.52, 0.82)
	sm.sky_horizon_color = Color(0.8, 0.86, 0.95)
	sm.ground_horizon_color = Color(0.82, 0.86, 0.93)
	sm.ground_bottom_color = Color(0.7, 0.74, 0.82)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(180.0 + s * 25.0), 0.0)
	root.add_child(sun)
	# Snowy ground and a soft bank behind.
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.94, 0.95, 0.99)
	snow.roughness = 0.9
	var gk := MeshKit.new()
	gk.box(snow, Transform3D(Basis(), Vector3(0, -0.05, 0)), Vector3(60, 0.1, 60))
	gk.pillow(snow, Transform3D(Basis(), Vector3(-s * 2.5, 0.0, 6.5)), 14.0, 4.0, 0.9, 0.3, 10, 2.6)
	var ground := MeshInstance3D.new()
	ground.mesh = gk.commit()
	root.add_child(ground)
	for p in [Vector3(-9, 0, 10), Vector3(-4.5, 0, 15), Vector3(2.0, 0, 16), Vector3(-13, 0, 5)]:
		var tree := MeshInstance3D.new()
		tree.mesh = Props.evergreen()
		tree.position = Vector3(s * p.x, p.y, p.z)
		tree.scale = Vector3.ONE * 1.1
		root.add_child(tree)
	# The pickup (the player's own truck model), parked. Polish 7 §10: with its plow, the blade
	# raised as a parked vehicle holds it (0.18 m, Vehicle).
	var vd: VehicleData = Catalog.vehicle(&"pickup_plow")
	var info := VehicleModels.build(vd)
	var truck := Node3D.new()
	truck.name = "Truck"
	root.add_child(truck)
	var tm := MeshInstance3D.new()
	tm.mesh = info["mesh"]
	truck.add_child(tm)
	for w in info["wheels"]:
		var wm := MeshInstance3D.new()
		wm.mesh = w["mesh"]
		wm.position = w["pos"]
		truck.add_child(wm)
	if info.has("blade_mesh"):
		var bm := MeshInstance3D.new()
		bm.mesh = info["blade_mesh"]
		bm.position = (info["blade_pivot"] as Vector3) + Vector3(0, 0.18, 0)
		truck.add_child(bm)
	var cam_pos := Vector3(s * CAM.x, CAM.y, CAM.z)
	# The small shovel, planted upright in the snow where it lies buried, its scoop turned towards
	# the camera. Placed from its own mesh (the grip is the origin, the shaft runs to tip()), so a
	# remodelled shovel stands the same way.
	var sh := MeshInstance3D.new()
	sh.name = "Shovel"
	sh.mesh = ToolModels.mesh_for("small_shovel")
	truck.add_child(sh)
	var tip := ToolModels.tip("small_shovel")
	var shaft := tip.normalized()
	var to_cam := Vector3(cam_pos.x - spot.x, 0.0, cam_pos.z - spot.z).normalized().rotated(Vector3.UP, s * deg_to_rad(SHOVEL_TURN_DEG))
	var down := Vector3(0, -1, 0).rotated(to_cam.cross(Vector3.UP).normalized(), deg_to_rad(SHOVEL_LEAN_DEG))
	# Tool frame: X across the blade, the shaft, and their normal (towards the scoop's opening).
	var local := Basis(Vector3.RIGHT, shaft, Vector3.RIGHT.cross(shaft).normalized())
	var across := Vector3.UP.cross(to_cam).normalized()
	var world := Basis(across, down, across.cross(down).normalized())
	var rot := world * local.transposed()
	var low := INF
	var aabb: AABB = sh.mesh.get_aabb()
	for k in range(8):
		low = minf(low, (rot * aabb.get_endpoint(k)).y)
	var at := spot - rot * tip
	sh.transform = Transform3D(rot, Vector3(at.x, -low - SHOVEL_SINK, at.z))
	# The player, standing beside the truck next to the shovel, facing the camera.
	var ch := CharacterModel.new()
	ch.name = "Character"
	truck.add_child(ch)
	ch.build()
	ch.position = Vector3(s * CHAR.x, 0.0, CHAR.y)
	var to := Vector2(cam_pos.x - ch.position.x, cam_pos.z - ch.position.z)
	ch.rotation.y = atan2(-to.x, -to.y)
	ch.set_pose("idle")
	for i in range(30):
		ch.animate(0.1, 0.0)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 38.0
	root.add_child(cam)
	cam.position = cam_pos
	cam.look_at(Vector3(s * LOOK.x, LOOK.y, LOOK.z))
	cam.current = true
	# Print treatment: a slightly warm tint, a soft vignette and a white border.
	var tint := ColorRect.new()
	tint.color = Color(1.0, 0.82, 0.55, 0.07)
	tint.size = Vector2(PHOTO)
	vp.add_child(tint)
	var vig := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.0))
	gr.set_color(1, Color(0.05, 0.03, 0.02, 0.38))
	gr.set_offset(0, 0.55)
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 1.08)
	gt.width = 128
	gt.height = 128
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.size = Vector2(PHOTO)
	vp.add_child(vig)
	var b := 16.0
	for r in [Rect2(0, 0, PHOTO.x, b), Rect2(0, PHOTO.y - b, PHOTO.x, b), Rect2(0, 0, b, PHOTO.y), Rect2(PHOTO.x - b, 0, b, PHOTO.y)]:
		var e := ColorRect.new()
		e.color = Color(0.97, 0.96, 0.93)
		e.position = r.position
		e.size = r.size
		vp.add_child(e)
