class_name ToolIcons
extends Node
## Polish 5 §6: one set of tool icons for the hotbar, the store, the upgrades and the rack (§15),
## rendered once from the game's own models (ToolModels, and a mitten for bare hands) in a
## render-once SubViewport: every tool from the same angle (one orthographic camera looking from
## the front left, above), under the same three lights, on the same transparent background, each
## fitted to its own cell of one image, which is then cut into one small texture per tool and the
## viewport freed. Headless runs (no renderer) and the frames before the render is done draw the
## procedural icons instead (Icons._draw_tool), so no test depends on a captured image.

const CELL := 240           # px per icon as rendered (cut out and scaled down to SIZE)
const PITCH := 1.6          # cells are this far apart (in icon widths), so a long handle running
                            # off its icon's corner never reaches the next icon
const SIZE := 128           # px per icon as kept
const COLS := 5
const FILL := 0.9           # how much of its icon the framed part's longer side fills
const SHAFT_SHOWN := 0.8    # long tools: framed from the blade up to this much of the shaft; the
                            # rest of the handle runs off the top corner
## From the object toward the camera: front left, above.
const VIEW := Vector3(-0.6, 0.55, -0.58)
## Long hand tools are turned in the picture (about the view axis, so the angle they are seen
## from doesn't change) until the line from the grip to the blade runs this way on screen:
## down and to the left.
const SCREEN_AXIS := Vector2(-0.62, -0.78)

static var textures: Dictionary = {}     # tool id ("" = bare hands) -> Texture2D
static var state := ""                   # "" | "rendering" | "done" | "headless"
static var render_ms := -1               # wall time from the start of the render to the textures
static var render_frames := 0            # main-loop frames that took
static var build_ms := -1                # of which: building the stage (and any models not built yet)
static var cut_ms := -1                  # of which: reading the image back and cutting the icons
static var image_px := Vector2i.ZERO


## Every icon in the set: bare hands ("") and every tool and machine.
static func ids() -> Array:
	var out := [""]
	for id in Catalog.TOOL_IDS:
		if id != &"hands":
			out.append(String(id))
	return out


## The rendered icon for a tool ("" = bare hands), or null (headless, or not rendered yet — the
## first call starts the render).
static func texture(id: String) -> Texture2D:
	if state == "":
		request()
	return textures.get(id)


static func request() -> void:
	if state != "":
		return
	if DisplayServer.get_name() == "headless":
		state = "headless"
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	state = "rendering"
	var n := ToolIcons.new()
	n.name = "ToolIconRender"
	tree.root.add_child.call_deferred(n)


func _ready() -> void:
	_render()


func _render() -> void:
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_frames_drawn()
	var list := ids()
	@warning_ignore("integer_division")
	var rows := (list.size() + COLS - 1) / COLS
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(CELL * PITCH * COLS), roundi(CELL * PITCH * rows))
	vp.own_world_3d = true
	vp.transparent_bg = true
	# Nothing is drawn until the stage is in place (its transforms flushed, as for the photo, §4).
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	build_stage(vp, list, rows)
	@warning_ignore("integer_division")
	build_ms = int((Time.get_ticks_usec() - t0) / 1000)
	await get_tree().process_frame
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var t1 := Time.get_ticks_usec()
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		image_px = img.get_size()
		img.convert(Image.FORMAT_RGBA8)
		for i in range(list.size()):
			@warning_ignore("integer_division")
			var c := Vector2((i % COLS) + 0.5, (i / COLS) + 0.5) * CELL * PITCH
			var cell := img.get_region(Rect2i(roundi(c.x - CELL * 0.5), roundi(c.y - CELL * 0.5), CELL, CELL))
			cell.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
			cell.generate_mipmaps()
			textures[list[i]] = ImageTexture.create_from_image(cell)
	@warning_ignore("integer_division")
	cut_ms = int((Time.get_ticks_usec() - t1) / 1000)
	state = "done"
	render_frames = Engine.get_frames_drawn() - f0
	@warning_ignore("integer_division")
	render_ms = int((Time.get_ticks_usec() - t0) / 1000)
	vp.queue_free()
	get_tree().call_group("tool_icons", "queue_redraw")
	queue_free()


## The stage: lights, the camera and one model per cell (no rendering here, so tests can build
## it headless). Returns {"camera": Camera3D, "items": [{id, node, cell: Vector2 (camera-plane
## centre), rect: Rect2 (the framed part's extent on the camera plane), pose: Basis}], "pitch"}.
## One world unit = one icon's width; cells are PITCH apart.
static func build_stage(parent: Node, list: Array, rows: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "IconStage"
	parent.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.78, 0.86)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	# Key light from the upper left in front, a cool fill from the right, a rim from behind.
	for l in [[Vector3(-0.45, 0.8, -0.4), Color(1.0, 0.96, 0.9), 1.35], [Vector3(0.8, 0.25, -0.3), Color(0.8, 0.86, 1.0), 0.45], [Vector3(0.2, 0.6, 0.9), Color(1, 1, 1), 0.6]]:
		var dl := DirectionalLight3D.new()
		dl.light_color = l[1]
		dl.light_energy = l[2]
		root.add_child(dl)
		dl.basis = Basis.looking_at(-(l[0] as Vector3).normalized(), Vector3.UP)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(rows) * PITCH          # one world unit per icon
	cam.near = 0.1
	cam.far = 200.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	root.add_child(cam)
	cam.basis = Basis.looking_at(-VIEW.normalized(), Vector3.UP)
	cam.position = VIEW.normalized() * 50.0
	cam.current = true
	var cb := cam.basis
	var ci := cb.inverse()
	var items := []
	for i in range(list.size()):
		var id: String = list[i]
		var mesh: Mesh = _mitten() if id == "" else ToolModels.mesh_for(id)
		var t: ToolData = null if id == "" else Catalog.tool(StringName(id))
		var pose := Basis()
		if id == "":
			# The mitten faces the camera, fingers up.
			pose = Basis.looking_at(-VIEW.normalized(), Vector3.UP) * Basis(Vector3.UP, 0.2)
		elif t.kind != ToolData.Kind.WALK_BLOWER:
			# Turn the tool about the view axis until its grip-to-blade line runs SCREEN_AXIS.
			var g := ci * ToolModels.blade_offset(id)
			var a := atan2(g.y, g.x)
			var want := atan2(SCREEN_AXIS.y, SCREEN_AXIS.x)
			pose = Basis(VIEW.normalized(), want - a)
		# Fit: the framed part's extent on the camera plane, from its vertices — a long tool from
		# its blade up most of its shaft, anything else whole.
		var tp := ToolModels.tip(id) if id != "" else Vector3.ZERO
		var long_tool := t != null and t.kind != ToolData.Kind.WALK_BLOWER and t.kind != ToolData.Kind.SLEIGH and tp.length() > 0.5
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for si in range(mesh.get_surface_count()):
			var arr := mesh.surface_get_arrays(si)
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				if long_tool and (v - tp).dot(-tp.normalized()) > tp.length() * SHAFT_SHOWN:
					continue
				var q := ci * (pose * v)
				lo = lo.min(Vector2(q.x, q.y))
				hi = hi.max(Vector2(q.x, q.y))
		var ext := hi - lo
		var s := (FILL if id != "" else 0.78) / maxf(maxf(ext.x, ext.y), 0.001)
		@warning_ignore("integer_division")
		var cell := Vector2((i % COLS) - (COLS - 1) * 0.5, (rows - 1) * 0.5 - (i / COLS)) * PITCH
		var mid := (lo + hi) * 0.5 * s
		var origin := cb * Vector3(cell.x - mid.x, cell.y - mid.y, 0.0)
		var mi := MeshInstance3D.new()
		mi.name = "Icon_" + (id if id != "" else "hands")
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.transform = Transform3D(pose.scaled(Vector3.ONE * s), origin)
		items.append({"id": id, "node": mi, "cell": cell, "rect": Rect2(cell - ext * s * 0.5, ext * s), "pose": pose})
	return {"camera": cam, "items": items, "pitch": PITCH}


static var _mitten_mesh: ArrayMesh


## Bare hands: the player's winter mitten (the character's dark blue-grey, a little lighter so it
## reads on the dark slots): a rounded mitt, the thumb out to the side, a ribbed cuff.
static func _mitten() -> ArrayMesh:
	if _mitten_mesh != null:
		return _mitten_mesh
	var kit := MeshKit.new()
	var glove := Mats.tool(ToolModels.FIN_RUBBER, Color(0.38, 0.4, 0.48), 0.92, 0.0, 0.0)
	var cuff := Mats.tool(ToolModels.FIN_RUBBER, Color(0.26, 0.27, 0.33), 0.95, 0.0, 0.0)
	kit.bevel_box(glove, Transform3D(Basis(), Vector3(0, 0.045, 0)), Vector3(0.1, 0.11, 0.046), 0.02)
	kit.sphere(glove, Transform3D(Basis().scaled(Vector3(0.05, 0.034, 0.023)), Vector3(0, 0.099, 0)), 1.0, 8, 16, true)
	kit.bevel_box(glove, Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(-50.0)), Vector3(0.062, 0.03, 0.004)), Vector3(0.034, 0.075, 0.032), 0.015)
	kit.bevel_box(cuff, Transform3D(Basis(), Vector3(0, -0.036, 0)), Vector3(0.12, 0.052, 0.058), 0.012)
	for k in range(3):
		kit.box(glove, Transform3D(Basis(), Vector3(0, -0.05 + k * 0.014, 0.0295)), Vector3(0.11, 0.004, 0.002))
	_mitten_mesh = kit.commit()
	return _mitten_mesh
