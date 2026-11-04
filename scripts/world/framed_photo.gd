class_name FramedPhoto
extends Node3D
## Polish 4 §5: a framed photograph on the wall beside the player's front door: the player's
## character standing by the pickup truck on a sunny winter day, the small shovel (the one dug out
## beside the truck on the first morning) leaning against the passenger door.
##
## The photo is rendered once from the game's own models — CharacterModel with the player's look,
## the truck's mesh from VehicleModels, ToolModels' small shovel — in a SubViewport with its own
## World3D, camera and lights, then copied to a static texture and the viewport is freed. The truck
## is a plain mesh (no vehicle, physics body, registration or roof snow) and nothing in the photo
## scene touches an autoload. Headless runs (no renderer) skip the capture and keep a plain
## placeholder. The print is a normal shaded material, so it darkens with the room at night.

const PHOTO := Vector2i(720, 480)      # 3:2 print, pixels
const PRINT := Vector2(0.42, 0.28)     # metres
const MAT_W := 0.07                    # the mat around the print
const FRAME_W := 0.035                 # the wooden moulding
const DEPTH := 0.03                    # frame depth off the wall

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
	return f


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
	# Mirrored lots have a mirrored house transform: flip the print back.
	if global_transform.basis.determinant() < 0.0:
		_print_mat.uv1_scale = Vector3(-1, 1, 1)
		_print_mat.uv1_offset = Vector3(1, 0, 0)
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
	gm.albedo_color = Color(0.85, 0.9, 1.0, 0.07)
	gm.roughness = 0.04
	gm.metallic_specular = 0.9
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
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	build_scene(vp)
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


## The photo scene: snowy ground, a few spruces, the pickup, the player beside it and the small
## shovel leaning on the passenger door, under a clear winter sky. Truck frame: forward is -Z, the
## driver sits on the left (-X), so the passenger door is on the right (+X).
static func build_scene(vp: SubViewport) -> void:
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
	sun.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(205.0), 0.0)
	root.add_child(sun)
	# Snowy ground and a soft bank behind.
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.94, 0.95, 0.99)
	snow.roughness = 0.9
	var gk := MeshKit.new()
	gk.box(snow, Transform3D(Basis(), Vector3(0, -0.05, 0)), Vector3(60, 0.1, 60))
	gk.pillow(snow, Transform3D(Basis(), Vector3(-2.5, 0.0, 6.5)), 14.0, 4.0, 0.9, 0.3, 10, 2.6)
	var ground := MeshInstance3D.new()
	ground.mesh = gk.commit()
	root.add_child(ground)
	for p in [Vector3(-9, 0, 10), Vector3(-4.5, 0, 15), Vector3(2.0, 0, 16), Vector3(-13, 0, 5)]:
		var tree := MeshInstance3D.new()
		tree.mesh = Props.evergreen()
		tree.position = p
		tree.scale = Vector3.ONE * 1.1
		root.add_child(tree)
	# The pickup (the player's own truck model), parked.
	var vd: VehicleData = Catalog.vehicle(&"pickup")
	var info := VehicleModels.build(vd)
	var truck := Node3D.new()
	root.add_child(truck)
	var tm := MeshInstance3D.new()
	tm.mesh = info["mesh"]
	truck.add_child(tm)
	for w in info["wheels"]:
		var wm := MeshInstance3D.new()
		wm.mesh = w["mesh"]
		wm.position = w["pos"]
		truck.add_child(wm)
	# The small shovel leaning on the passenger door: its grip against the door below the window,
	# the shaft down to the blade on the snow, the blade across the door's length. The mesh's
	# origin is the grip, its shaft runs along SHAFT and its blade across local X.
	var sh := MeshInstance3D.new()
	sh.mesh = ToolModels.mesh_for("small_shovel")
	truck.add_child(sh)
	var shaft := Vector3(0, -sin(deg_to_rad(55)), -cos(deg_to_rad(55)))
	var grip := Vector3(1.07, 1.12, 0.05)
	var down := (Vector3(1.52, 0.12, 0.0) - grip).normalized()
	var across := Vector3(0, 0, 1)
	across = (across - down * across.dot(down)).normalized()
	var local := Basis(Vector3.RIGHT, shaft, Vector3.RIGHT.cross(shaft).normalized())
	var world := Basis(across, down, across.cross(down).normalized())
	sh.transform = Transform3D(world * local.transposed(), grip)
	# The player, standing by the front of the truck on the passenger side, facing the camera.
	var cam_pos := Vector3(6.6, 1.45, -3.9)
	var ch := CharacterModel.new()
	truck.add_child(ch)
	ch.build()
	ch.position = Vector3(1.75, 0.0, -2.05)
	var to := Vector2(cam_pos.x - ch.position.x, cam_pos.z - ch.position.z)
	ch.rotation.y = atan2(-to.x, -to.y)
	ch.set_pose("idle")
	for i in range(30):
		ch.animate(0.1, 0.0)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.position = cam_pos
	cam.look_at(Vector3(0.5, 0.9, -0.75))
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
