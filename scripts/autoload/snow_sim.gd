extends Node
## Snow simulation: a persistent heightfield of snow depth covering the whole neighborhood.
##
## Representation: one float (meters of snow) per 0.25 m cell, plus static ground height and
## surface type per cell. All tool, vehicle, grader and weather interactions go through the
## operations below; volume is moved between cells (conserved), except for the explicit
## exceptions (dump truck disposal, clearing-box completion — up to the last 10 % of a box's snow
## since polish 3 — melting since polish 5 §13, and debug commands).
##
## Melting (polish 5 §13): the heated pad and the heated driveway and path melt the snow on them
## (Heating, on the game clock). It is the one new loss of snow since polish 3's box exception and it
## is ledgered: melt_rect adds every m³ it removes to `melted`, so total_volume() + melted is what
## the snow was before — exactly (the conservation tests assert it; no tolerance was loosened).
##
## Road rule (Part 8.9): removed in polish 5 §3 (Decision 12) for every bit of snow the player
## moves — tools, blowers and vehicles now pass allow_road = true / player_rule = false, so their
## snow lands on (or is pushed onto) the street where it's aimed. The flags stay for what still
## keeps to the curb: wading never shoulders yard snow onto the road, and relaxation still treats
## the curb line as a wall (yard snow doesn't slump onto the street by itself). Snowfall and the
## city grader are exempt as before.
##
## Ceiling: the snow surface never rises above `ceiling` (street-lamp height). Snowfall stops
## adding at the ceiling; operations spill the excess into neighbouring cells (volume conserved).
##
## Cohesion: undisturbed snow (fallen and settled) holds steep, clean cut walls; snow that was
## thrown, pushed or has slid ("loose") slumps to the angle of repose. Cells of completed
## clearing boxes ("held") act as a retaining wall for slumping snow, like the curb.

signal reset_done

const CELL := 0.25
const INV_CELL := 4.0
const CELL_AREA := 0.0625
const W := 768
const H := 896
const CHUNK := 64
const CW := 12
const CH := 14
const TILE := 8
const TW := 96
const TH := 112

const S_LAWN := 0
const S_ROAD := 1
const S_DRIVEWAY := 2
const S_SIDEWALK := 3
const S_PORCH := 4
const S_BLOCKED := 5
const S_LOT := 6
const S_DUMP := 7
const S_BOULEVARD := 8
const S_WALKWAY := 9
const S_STAIRS := 10

var depth := PackedFloat32Array()
var ground := PackedFloat32Array()
var surf := PackedByteArray()
var fall_mult := PackedFloat32Array()
var loose := PackedFloat32Array()     # depth (m) of loose snow (thrown / pushed / slid) on top of each cell
var hold := PackedByteArray()         # 1 = inside a completed clearing box (no slump inflow)

var fall_total := 0.0          # cumulative snowfall (m) since the winter started
var settle_clock := 0.0        # game minutes elapsed (for settling)
var chunk_fall := PackedFloat32Array()
var chunk_settle := PackedFloat32Array()
var sync_cursor := 0

# Dirty rect per chunk (cell coords, inclusive) for the renderer. -1 = clean.
var dirty_x0 := PackedInt32Array()
var dirty_z0 := PackedInt32Array()
var dirty_x1 := PackedInt32Array()
var dirty_z1 := PackedInt32Array()
var chunk_version := PackedInt32Array()

# Relaxation work queue (tile indices).
var relax_queue: Dictionary = {}   # membership set
var relax_list: PackedInt32Array = PackedInt32Array()      # cold queue (batch ops, cascades)
var relax_hot: PackedInt32Array = PackedInt32Array()       # hot queue (player ops near the camera)
var hot_head := 0                # read index into relax_hot (FIFO without O(n) pops)
var hot_mode := true   # ops queue into the hot list unless a batch op disables it
var relax_ops_last_frame := 0
## Polish 6 §3: the queue is saved (serialize_pending "relax"), so a reload settles what was still
## pending. A save without it (older saves) is settled once on load: deserialize sets this and
## Saves.load_game settles the map once the boxes' held cells are back (settle_all, or settle_begin
## for the main menu's loading screen to step through).
var settle_on_load := false
## Polish 6 §3: blade_push's own random stream (how far past the blade each cell's snow lands), so
## a push no longer depends on draws from the engine's global generator. Seeded per winter
## (reset_for_winter), its state saved (serialize_pending "push_rng").
var push_rng := RandomNumberGenerator.new()
const PUSH_SEED := 7703
# Blade guard: the strip just cleared behind an engaged blade acts as a wall for slumping, so a
# tall berm can't spill back over the blade (cell-space AABB, expires after a couple of frames).
var guard_x0 := 0
var guard_z0 := 0
var guard_x1 := -1
var guard_z1 := -1
var guard_ttl := 0

var repose := 0.23
var repose_cut := 1.6          # undisturbed snow: max height step per cell (near-vertical cut walls)
var settle_rate := 0.0
var loose_harden_min := 1800.0   # time constant of loose → cohesive (game minutes)
var settle_threshold := 0.3
var ceiling := 6.0             # max snow surface height (street-lamp height)
var initialized := false
var _noise := FastNoiseLite.new()
var stat_player_moved := 0.0    # m3 moved by the player (for season stats)
## Polish 5 §13: the melted-volume ledger — every m³ melt_rect removed this winter (saved).
var melted := 0.0
# Simplified roof layer (Part 8.8): shared depth from snowfall + per-house extra (thrown snow).
var roof_depth := 0.0
var roof_extra: Dictionary = {}
var auto_process := true         # world calls tick(); tests can drive manually


func _ready() -> void:
	push_rng.seed = PUSH_SEED
	_noise.seed = 1337
	_noise.frequency = 0.045
	_noise.fractal_octaves = 3
	var n := W * H
	depth.resize(n)
	ground.resize(n)
	surf.resize(n)
	fall_mult.resize(n)
	loose.resize(n)
	hold.resize(n)
	chunk_fall.resize(CW * CH)
	chunk_settle.resize(CW * CH)
	dirty_x0.resize(CW * CH)
	dirty_z0.resize(CW * CH)
	dirty_x1.resize(CW * CH)
	dirty_z1.resize(CW * CH)
	chunk_version.resize(CW * CH)
	_build_static()


func _apply_balance() -> void:
	var b: BalanceData = Catalog.balance
	if b:
		repose = b.repose_max_diff
		settle_rate = b.settle_rate_per_day
		settle_threshold = b.settle_threshold
		ceiling = b.snow_ceiling
		loose_harden_min = maxf(b.loose_harden_hours, 0.01) * 60.0


# -----------------------------------------------------------------------------
# Static ground / surface map
# -----------------------------------------------------------------------------

func _build_static() -> void:
	Layout.ensure()
	surf.fill(S_LAWN)
	ground.fill(0.0)
	for r in Layout.boulevards:
		_paint(r, S_BOULEVARD)
	for r in Layout.sidewalks:
		_paint(r, S_SIDEWALK)
	for a in Layout.big_areas:
		_paint(a["rect"], S_LOT)
		_paint(a["apron"], S_LOT)
	_paint(Layout.dump_rect, S_DUMP)
	for lot in Layout.lots:
		if lot["vacant"]:
			continue
		var hi := Layout.house_info(lot)
		_paint(hi["walkway"], S_WALKWAY)
		_paint(hi["driveway"], S_DRIVEWAY)
	# Sidewalk crosses driveways.
	for r in Layout.sidewalks:
		_paint_if(r, S_SIDEWALK, S_DRIVEWAY)
	for r in Layout.roads:
		_paint(r["rect"], S_ROAD)
	for b in Layout.buildings:
		_paint(b["rect"], S_BLOCKED)
	for lot in Layout.lots:
		if lot["vacant"]:
			continue
		var hi := Layout.house_info(lot)
		_paint(hi["body"], S_BLOCKED)
		_paint(hi["garage"], S_BLOCKED)
		_paint(hi["porch"], S_PORCH, Layout.PORCH_H)
		_paint(hi["stairs"], S_STAIRS, Layout.STEP_H)
		_paint(hi["stair_upper"], S_STAIRS, Layout.STEP_H * 2.0)
	# Snowfall multiplier: noise (baked natively), drifts near walls, shelter under porch roofs.
	var nimg := _noise.get_image(W, H, false, false, true)
	nimg.convert(Image.FORMAT_L8)
	var nb := nimg.get_data()
	for i in range(W * H):
		var s := surf[i]
		if s == S_BLOCKED:
			fall_mult[i] = 0.0
		elif s == S_PORCH:
			fall_mult[i] = 0.22
		else:
			fall_mult[i] = 0.88 + 0.24 * (nb[i] / 255.0)
	# Drift bonus within 1.5 m of buildings.
	for lot in Layout.lots:
		if lot["vacant"]:
			continue
		var hi := Layout.house_info(lot)
		_drift_margin(hi["body"], 1.5, 1.18)
		_drift_margin(hi["garage"], 1.5, 1.18)
	for b in Layout.buildings:
		_drift_margin(b["rect"], 2.0, 1.2)


func _drift_margin(r: Rect2, margin: float, mult: float) -> void:
	var c := _rect_cells(r.grow(margin))
	for z in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			var i := z * W + x
			var s := surf[i]
			if s != S_BLOCKED and s != S_PORCH and s != S_ROAD:
				fall_mult[i] = minf(fall_mult[i] * mult, 1.4)


func _rect_cells(r: Rect2) -> Rect2i:
	var x0 := clampi(int(round(r.position.x * INV_CELL)), 0, W)
	var z0 := clampi(int(round(r.position.y * INV_CELL)), 0, H)
	var x1 := clampi(int(round(r.end.x * INV_CELL)), 0, W)
	var z1 := clampi(int(round(r.end.y * INV_CELL)), 0, H)
	return Rect2i(x0, z0, x1 - x0, z1 - z0)


func _paint(r: Rect2, s: int, g: float = 0.0) -> void:
	var c := _rect_cells(r)
	for z in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			var i := z * W + x
			surf[i] = s
			ground[i] = g


func _paint_if(r: Rect2, s: int, only_on: int) -> void:
	var c := _rect_cells(r)
	for z in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			var i := z * W + x
			if surf[i] == only_on:
				surf[i] = s


# -----------------------------------------------------------------------------
# Winter initialisation
# -----------------------------------------------------------------------------

## Fill the map with the starting snow for a winter. year 1 = the big opening storm.
func reset_for_winter(year: int) -> void:
	_apply_balance()
	var b: BalanceData = Catalog.balance
	var base := b.initial_depth_year1 if year <= 1 else b.initial_depth_later + 0.04 * minf(year - 2, 6)
	var road_base := b.initial_road_depth_year1 if year <= 1 else base * 0.6
	var noise2 := FastNoiseLite.new()
	noise2.seed = 4242 + year
	noise2.frequency = 0.035
	var nimg := noise2.get_image(W, H, false, false, true)
	nimg.convert(Image.FORMAT_L8)
	var nb := nimg.get_data()
	# Small rolling lumps (~2 m) so fresh snow looks soft and pillowy, not flat.
	var noise3 := FastNoiseLite.new()
	noise3.seed = 99 + year
	noise3.frequency = 0.11
	noise3.fractal_octaves = 2
	var limg := noise3.get_image(W, H, false, false, true)
	limg.convert(Image.FORMAT_L8)
	var lb := limg.get_data()
	var store_lot: Rect2 = Layout.big_areas[1]["rect"]
	var sl := _rect_cells(store_lot)
	# The opening storm stays below the character's hips on open ground so the player can wade
	# (slowly) from the very first minute; a soft knee keeps the lumpy look instead of a flat cap.
	var cap := b.opening_max_depth if year <= 1 else INF
	var knee := cap - 0.14
	for z in range(H):
		for x in range(W):
			var i := z * W + x
			var s := surf[i]
			var d := 0.0
			if s == S_BLOCKED:
				d = 0.0
			elif s == S_ROAD:
				d = road_base * (0.94 + 0.12 * (nb[i] / 255.0))
			elif s == S_PORCH:
				d = base * 0.25
			else:
				var m := fall_mult[i]
				d = base * (m - 0.1 + 0.2 * (nb[i] / 255.0) + 0.12 * (lb[i] / 255.0 - 0.5))
				if s == S_STAIRS:
					d = maxf(0.0, base * m - ground[i] * 0.5)
				if d > knee:
					d = knee + (cap - knee) * tanh((d - knee) / (cap - knee))
			if x >= sl.position.x and x < sl.end.x and z >= sl.position.y and z < sl.end.y and s == S_LOT:
				d = 0.06
			depth[i] = clampf(d, 0.0, maxf(ceiling - ground[i], 0.0))
	loose.fill(0.0)
	hold.fill(0)
	# The tutorial neighbor stands on his porch: a small trampled spot.
	if year <= 1 and not Layout.neighbor_lot.is_empty():
		var hi := Layout.house_info(Layout.neighbor_lot)
		var p: Vector2 = hi["porch_center"]
		set_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), 0.04)
	fall_total = 0.0
	settle_clock = 0.0
	melted = 0.0
	roof_depth = 0.6 if year <= 1 else 0.25
	roof_extra.clear()
	chunk_fall.fill(0.0)
	chunk_settle.fill(0.0)
	relax_queue.clear()
	relax_list.clear()
	relax_hot.clear()
	hot_head = 0
	settle_on_load = false
	settling = false
	push_rng.seed = PUSH_SEED + year
	stat_player_moved = 0.0
	_mark_all_dirty()
	initialized = true
	reset_done.emit()


func _mark_all_dirty() -> void:
	for ci in range(CW * CH):
		dirty_x0[ci] = 0
		dirty_z0[ci] = 0
		dirty_x1[ci] = CHUNK
		dirty_z1[ci] = CHUNK
		chunk_version[ci] += 1


# -----------------------------------------------------------------------------
# Snowfall and settling (lazy per chunk)
# -----------------------------------------------------------------------------

## Called by the weather system with the snowfall depth (m) added since last call.
func add_snowfall(amount_m: float) -> void:
	if amount_m > 0.0:
		fall_total += amount_m
		# Roofs keep what falls on them (up to a thick, overhanging cap; beyond that it slides off).
		roof_depth = minf(roof_depth + amount_m, ROOF_MAX)


const ROOF_MAX := 2.4


func advance_settle(game_minutes: float) -> void:
	settle_clock += game_minutes
	# Only very thick roof loads slowly slide off; new snow always shows on the roofs.
	var days := game_minutes / 1440.0
	if roof_depth > 1.2:
		roof_depth = maxf(1.2, roof_depth - days * 0.02 * (roof_depth - 1.2))
	for k in roof_extra.keys():
		roof_extra[k] = maxf(0.0, roof_extra[k] - days * 0.02)


func roof_total(house_index: int) -> float:
	return roof_depth + float(roof_extra.get(house_index, 0.0))


## Snow thrown onto a roof lands and stays there (joins the simplified roof layer).
func add_roof_volume(house_index: int, vol: float, roof_area := 160.0) -> void:
	roof_extra[house_index] = minf(float(roof_extra.get(house_index, 0.0)) + vol / roof_area, 1.5)


func _chunk_needs_sync(ci: int) -> bool:
	return fall_total - chunk_fall[ci] > 0.0 or settle_clock - chunk_settle[ci] > 0.0


func sync_chunk(ci: int) -> void:
	var df := fall_total - chunk_fall[ci]
	var dmin := settle_clock - chunk_settle[ci]
	if df <= 0.0 and dmin <= 0.0:
		return
	chunk_fall[ci] = fall_total
	chunk_settle[ci] = settle_clock
	var settle := settle_rate * dmin / 1440.0
	var thr := settle_threshold
	var ceil_h := ceiling
	# Loose snow left alone sinters: the loose share of each cell decays with time.
	var harden := exp(-dmin / loose_harden_min) if dmin > 0.0 else 1.0
	var cx := (ci % CW) * CHUNK
	@warning_ignore("integer_division")
	var cz := (ci / CW) * CHUNK
	for z in range(cz, cz + CHUNK):
		var row := z * W
		for x in range(cx, cx + CHUNK):
			var i := row + x
			if harden < 1.0 and loose[i] > 0.0:
				var lz := loose[i] * harden
				loose[i] = lz if lz > 0.002 else 0.0
			var m := fall_mult[i]
			if m <= 0.0:
				continue
			var d := depth[i]
			if settle > 0.0 and d > thr:
				d -= settle * minf(d - thr, 1.2)
				if d < thr:
					d = thr
			# New snow lands on top of whatever is there, up to the lamp-height ceiling.
			var top := ceil_h - ground[i]
			depth[i] = minf(d + df * m, maxf(top, d))
	dirty_x0[ci] = 0
	dirty_z0[ci] = 0
	dirty_x1[ci] = CHUNK
	dirty_z1[ci] = CHUNK
	chunk_version[ci] += 1


## Sync chunks only when enough has accumulated to be visible (called each frame by the world).
func sync_round_robin(count: int, min_fall := 0.003) -> void:
	var n := CW * CH
	var done := 0
	var checked := 0
	while done < count and checked < n:
		var ci := sync_cursor
		sync_cursor = (sync_cursor + 1) % n
		checked += 1
		var df := fall_total - chunk_fall[ci]
		var dmin := settle_clock - chunk_settle[ci]
		if df >= min_fall or dmin >= 180.0:
			sync_chunk(ci)
			done += 1


func sync_all() -> void:
	for ci in range(CW * CH):
		sync_chunk(ci)


## Bring the chunks covering a cell range up to date before an operation. Tiny pending amounts
## (< SYNC_MIN_FALL) are left pending: they are applied uniformly later, so nothing is lost, and
## continuous snowfall doesn't force a full chunk sync + remesh every frame.
const SYNC_MIN_FALL := 0.002
const SYNC_MIN_SETTLE := 180.0


func _sync_cells(x0: int, z0: int, x1: int, z1: int) -> void:
	@warning_ignore("integer_division")
	var c0x := clampi(x0 / CHUNK, 0, CW - 1)
	@warning_ignore("integer_division")
	var c1x := clampi(x1 / CHUNK, 0, CW - 1)
	@warning_ignore("integer_division")
	var c0z := clampi(z0 / CHUNK, 0, CH - 1)
	@warning_ignore("integer_division")
	var c1z := clampi(z1 / CHUNK, 0, CH - 1)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			var ci := cz * CW + cx
			if fall_total - chunk_fall[ci] >= SYNC_MIN_FALL or settle_clock - chunk_settle[ci] >= SYNC_MIN_SETTLE:
				sync_chunk(ci)


## Snowfall that has fallen on a chunk but is not yet written into its cells.
func _pending_fall(cx: int, cz: int) -> float:
	@warning_ignore("integer_division")
	return fall_total - chunk_fall[(cz / CHUNK) * CW + cx / CHUNK]


# -----------------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------------

func cell_x(x: float) -> int:
	return clampi(int(floor(x * INV_CELL)), 0, W - 1)


func cell_z(z: float) -> int:
	return clampi(int(floor(z * INV_CELL)), 0, H - 1)


func in_map(x: float, z: float) -> bool:
	return x >= 0.0 and z >= 0.0 and x < W * CELL and z < H * CELL


func depth_at(x: float, z: float) -> float:
	if not in_map(x, z):
		return 0.0
	var cx := cell_x(x)
	var cz := cell_z(z)
	var i := cz * W + cx
	# Queries include pending snowfall analytically instead of forcing a chunk sync.
	var d := depth[i]
	return minf(d + _pending_fall(cx, cz) * fall_mult[i], maxf(ceiling - ground[i], d))


func surface_at(x: float, z: float) -> int:
	if not in_map(x, z):
		return S_LAWN
	return surf[cell_z(z) * W + cell_x(x)]


func ground_at(x: float, z: float) -> float:
	if not in_map(x, z):
		return 0.0
	return ground[cell_z(z) * W + cell_x(x)]


func is_road(x: float, z: float) -> bool:
	return surface_at(x, z) == S_ROAD


## Snow surface height (ground + depth) with bilinear smoothing.
func surface_height(x: float, z: float) -> float:
	if not in_map(x, z):
		return 0.0
	var fx := x * INV_CELL - 0.5
	var fz := z * INV_CELL - 0.5
	var x0 := clampi(int(floor(fx)), 0, W - 1)
	var z0 := clampi(int(floor(fz)), 0, H - 1)
	var x1 := mini(x0 + 1, W - 1)
	var z1 := mini(z0 + 1, H - 1)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var tz := clampf(fz - z0, 0.0, 1.0)
	var h00 := _h(x0, z0)
	var h10 := _h(x1, z0)
	var h01 := _h(x0, z1)
	var h11 := _h(x1, z1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Polish 5 §10b: the snow surface height at the centre of cell (cx, cz) — what surface_height reads
## there — or 0 outside the map. (The box outlines drape on it: a quarter of the reads.)
func cell_surface(cx: int, cz: int) -> float:
	if cx < 0 or cz < 0 or cx >= W or cz >= H:
		return 0.0
	return _h(cx, cz)


func _h(cx: int, cz: int) -> float:
	var i := cz * W + cx
	if surf[i] == S_BLOCKED:
		return 0.0
	var d := depth[i]
	return ground[i] + minf(d + _pending_fall(cx, cz) * fall_mult[i], maxf(ceiling - ground[i], d))


## Max depth sampled in a small disc (used for movement blocking).
func max_depth_in_radius(x: float, z: float, r: float) -> float:
	var m := 0.0
	var steps := [Vector2(0, 0), Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]
	for s in steps:
		m = maxf(m, depth_at(x + s.x, z + s.y))
	return m


## Total snow volume (m3) in a world rect above a residual depth.
func volume_in_rect(r: Rect2, residual := 0.0) -> float:
	var c := _rect_cells(r)
	if c.size.x <= 0 or c.size.y <= 0:
		return 0.0
	_sync_cells(c.position.x, c.position.y, c.end.x - 1, c.end.y - 1)
	var v := 0.0
	for z in range(c.position.y, c.end.y):
		var row := z * W
		for x in range(c.position.x, c.end.x):
			var d := depth[row + x] - residual
			if d > 0.0:
				v += d
	return v * CELL_AREA


## Fast estimate for large areas (contract listings): samples every `stride`-th cell and includes
## pending snowfall analytically, without syncing chunks.
func estimate_volume(r: Rect2, residual := 0.0, stride := 4) -> float:
	var c := _rect_cells(r)
	if c.size.x <= 0 or c.size.y <= 0:
		return 0.0
	var v := 0.0
	var n := 0
	for z in range(c.position.y, c.end.y, stride):
		var row := z * W
		for x in range(c.position.x, c.end.x, stride):
			var i := row + x
			n += 1
			if surf[i] == S_BLOCKED:
				continue
			var d0 := depth[i]
			var d := minf(d0 + _pending_fall(x, z) * fall_mult[i], maxf(ceiling - ground[i], d0)) - residual
			if d > 0.0:
				v += d
	if n == 0:
		return 0.0
	return v / n * c.size.x * c.size.y * CELL_AREA


func total_volume() -> float:
	sync_all()
	var v := 0.0
	for d in depth:
		v += d
	return v * CELL_AREA


## March a ray against the snow surface. Returns {hit, position} (no physics bodies involved).
func raycast(from: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var step := 0.12
	var t := 0.0
	var prev := from
	while t < max_dist:
		t += step
		var p := from + dir * t
		if not in_map(p.x, p.z):
			break
		var h := surface_height(p.x, p.z)
		if p.y <= h:
			# refine
			var a := prev
			var b := p
			for k in range(5):
				var m := (a + b) * 0.5
				if m.y <= surface_height(m.x, m.z):
					b = m
				else:
					a = m
			return {"hit": true, "position": b}
		prev = p
	return {"hit": false, "position": from + dir * max_dist}


# -----------------------------------------------------------------------------
# Dirty tracking / relaxation scheduling
# -----------------------------------------------------------------------------

func mark_dirty(x0: int, z0: int, x1: int, z1: int) -> void:
	x0 = clampi(x0 - 1, 0, W - 1)
	z0 = clampi(z0 - 1, 0, H - 1)
	x1 = clampi(x1 + 1, 0, W - 1)
	z1 = clampi(z1 + 1, 0, H - 1)
	@warning_ignore("integer_division")
	var c0x := x0 / CHUNK
	@warning_ignore("integer_division")
	var c1x := mini(x1 / CHUNK, CW - 1)
	@warning_ignore("integer_division")
	var c0z := z0 / CHUNK
	@warning_ignore("integer_division")
	var c1z := mini(z1 / CHUNK, CH - 1)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			var ci := cz * CW + cx
			var lx0 := clampi(x0 - cx * CHUNK, 0, CHUNK)
			var lz0 := clampi(z0 - cz * CHUNK, 0, CHUNK)
			var lx1 := clampi(x1 - cx * CHUNK, 0, CHUNK)
			var lz1 := clampi(z1 - cz * CHUNK, 0, CHUNK)
			if dirty_x0[ci] < 0:
				dirty_x0[ci] = lx0
				dirty_z0[ci] = lz0
				dirty_x1[ci] = lx1
				dirty_z1[ci] = lz1
			else:
				dirty_x0[ci] = mini(dirty_x0[ci], lx0)
				dirty_z0[ci] = mini(dirty_z0[ci], lz0)
				dirty_x1[ci] = maxi(dirty_x1[ci], lx1)
				dirty_z1[ci] = maxi(dirty_z1[ci], lz1)
			chunk_version[ci] += 1
	# Neighbouring chunks share border vertices: dirty them too when touching the edge.
	if x0 % CHUNK == 0 and x0 > 0:
		_dirty_edge(x0 - 1, z0, z1)
	if z0 % CHUNK == 0 and z0 > 0:
		_dirty_edge_z(z0 - 1, x0, x1)


func _dirty_edge(x: int, z0: int, z1: int) -> void:
	@warning_ignore("integer_division")
	var cx := x / CHUNK
	@warning_ignore("integer_division")
	for cz in range(z0 / CHUNK, mini(z1 / CHUNK, CH - 1) + 1):
		var ci := cz * CW + cx
		var lz0 := clampi(z0 - cz * CHUNK, 0, CHUNK)
		var lz1 := clampi(z1 - cz * CHUNK, 0, CHUNK)
		if dirty_x0[ci] < 0:
			dirty_x0[ci] = CHUNK - 1
			dirty_z0[ci] = lz0
			dirty_x1[ci] = CHUNK
			dirty_z1[ci] = lz1
		else:
			dirty_x1[ci] = CHUNK
			dirty_z0[ci] = mini(dirty_z0[ci], lz0)
			dirty_z1[ci] = maxi(dirty_z1[ci], lz1)
		chunk_version[ci] += 1


func _dirty_edge_z(z: int, x0: int, x1: int) -> void:
	@warning_ignore("integer_division")
	var cz := z / CHUNK
	@warning_ignore("integer_division")
	for cx in range(x0 / CHUNK, mini(x1 / CHUNK, CW - 1) + 1):
		var ci := cz * CW + cx
		var lx0 := clampi(x0 - cx * CHUNK, 0, CHUNK)
		var lx1 := clampi(x1 - cx * CHUNK, 0, CHUNK)
		if dirty_x0[ci] < 0:
			dirty_x0[ci] = lx0
			dirty_z0[ci] = CHUNK - 1
			dirty_x1[ci] = lx1
			dirty_z1[ci] = CHUNK
		else:
			dirty_z1[ci] = CHUNK
			dirty_x0[ci] = mini(dirty_x0[ci], lx0)
			dirty_x1[ci] = maxi(dirty_x1[ci], lx1)
		chunk_version[ci] += 1


## Consume the dirty rect for a chunk (local cell coords). Returns Rect2i with size -1 if clean.
func take_dirty(ci: int) -> Rect2i:
	if dirty_x0[ci] < 0:
		return Rect2i(0, 0, -1, -1)
	var r := Rect2i(dirty_x0[ci], dirty_z0[ci], dirty_x1[ci] - dirty_x0[ci], dirty_z1[ci] - dirty_z0[ci])
	dirty_x0[ci] = -1
	return r


func is_dirty(ci: int) -> bool:
	return dirty_x0[ci] >= 0


func _queue_relax(x0: int, z0: int, x1: int, z1: int) -> void:
	@warning_ignore("integer_division")
	var t0x := clampi((x0 - 2) / TILE, 0, TW - 1)
	@warning_ignore("integer_division")
	var t1x := clampi((x1 + 2) / TILE, 0, TW - 1)
	@warning_ignore("integer_division")
	var t0z := clampi((z0 - 2) / TILE, 0, TH - 1)
	@warning_ignore("integer_division")
	var t1z := clampi((z1 + 2) / TILE, 0, TH - 1)
	for tz in range(t0z, t1z + 1):
		for tx in range(t0x, t1x + 1):
			_push_tile(tz * TW + tx)


func _push_tile(t: int) -> void:
	if not relax_queue.has(t):
		relax_queue[t] = true
		if hot_mode:
			relax_hot.append(t)
		else:
			relax_list.append(t)


func _pop_tile() -> int:
	if hot_head < relax_hot.size():
		var t := relax_hot[hot_head]
		hot_head += 1
		if hot_head >= relax_hot.size():
			relax_hot.clear()
			hot_head = 0
		return t
	var t2 := relax_list[relax_list.size() - 1]
	relax_list.resize(relax_list.size() - 1)
	return t2


func relax_pending() -> int:
	return relax_hot.size() - hot_head + relax_list.size()


## Process queued relaxation tiles (angle of repose). Returns number of tiles processed.
## Mark the area behind an engaged blade (world rect) so relaxation won't refill it.
func set_blade_guard(r: Rect2) -> void:
	guard_x0 = clampi(int(floor(r.position.x * INV_CELL)), 0, W - 1)
	guard_z0 = clampi(int(floor(r.position.y * INV_CELL)), 0, H - 1)
	guard_x1 = clampi(int(floor(r.end.x * INV_CELL)), 0, W - 1)
	guard_z1 = clampi(int(floor(r.end.y * INV_CELL)), 0, H - 1)
	guard_ttl = 3


func _guarded(i: int) -> bool:
	var x := i % W
	@warning_ignore("integer_division")
	var z := i / W
	return x >= guard_x0 and x <= guard_x1 and z >= guard_z0 and z <= guard_z1


func process_relax(max_tiles: int = 48, max_usec: int = 0) -> int:
	if guard_ttl > 0:
		guard_ttl -= 1
	var processed := 0
	relax_ops_last_frame = 0
	var t0 := Time.get_ticks_usec()
	while processed < max_tiles and relax_pending() > 0:
		if max_usec > 0 and processed > 0 and Time.get_ticks_usec() - t0 > max_usec:
			break
		var t: int = _pop_tile()
		relax_queue.erase(t)
		var tx := t % TW
		@warning_ignore("integer_division")
		var tz := t / TW
		var moved := _relax_tile(tx, tz)
		processed += 1
		if moved > 1e-5:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var nx := tx + dx
					var nz := tz + dz
					if nx >= 0 and nz >= 0 and nx < TW and nz < TH:
						_push_tile(nz * TW + nx)
	relax_ops_last_frame = processed
	return processed


func relax_until_stable(limit := 200000) -> void:
	var n := 0
	while relax_pending() > 0 and n < limit:
		n += process_relax(256)


## Polish 6 §3: a saved tile back in its queue (deserialize), in the saved order.
func _restore_tile(t: int, hot: bool) -> void:
	if t < 0 or t >= TW * TH or relax_queue.has(t):
		return
	relax_queue[t] = true
	if hot:
		relax_hot.append(t)
	else:
		relax_list.append(t)


## Polish 6 §3: settle the whole map — every tile queued and relaxed until nothing moves. For a
## save written before the relaxation queue was saved (settle_on_load): whatever its last operations
## had left pending (the city's pass during a sleep, above all) was lost with the queue, and would
## otherwise collapse at the first snow work nearby. The relaxation's own rule, queue and order;
## only a tile that moved more than SETTLE_MOVED_MIN (summed over its cells, m) queues its
## neighbours again, so the long tail of sub-millimetre adjustments is left to the game's
## relaxation (it finds nothing over a millimetre afterwards). settle_begin() queues the map;
## settle_step(max_usec) works through it (the main menu's loading screen, a frame at a time) and
## returns true while there is more; settle_all() does it at once and returns the tiles visited.
const SETTLE_MOVED_MIN := 0.001
var settling := false
var settle_visits := 0


func settle_begin() -> void:
	settle_on_load = false
	settling = true
	settle_visits = 0
	for t in range(TW * TH):
		if not relax_queue.has(t):
			relax_queue[t] = true
			relax_list.append(t)


func settle_step(max_usec: int) -> bool:
	if not settling:
		return false
	var t0 := Time.get_ticks_usec()
	while relax_pending() > 0:
		if max_usec > 0 and Time.get_ticks_usec() - t0 > max_usec:
			return true
		var t: int = _pop_tile()
		relax_queue.erase(t)
		var tx := t % TW
		@warning_ignore("integer_division")
		var tz := t / TW
		var moved := _relax_tile(tx, tz)
		settle_visits += 1
		if moved > SETTLE_MOVED_MIN:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var nx := tx + dx
					var nz := tz + dz
					if nx >= 0 and nz >= 0 and nx < TW and nz < TH:
						_push_tile(nz * TW + nx)
	settling = false
	return false


func settle_all() -> int:
	settle_begin()
	settle_step(0)
	return settle_visits


## Move snow from the higher cell hi_i down to lo_i across a height step `diff`. Loose snow on top
## slides at the angle of repose; the undisturbed snow below only gives way past a near-vertical
## step (repose_cut). Whatever slides becomes loose snow on the lower cell. Returns the amount.
func _slump(hi_i: int, lo_i: int, diff: float, maxd: float, rc: float) -> float:
	var amt := 0.0
	var lz := loose[hi_i]
	if lz > 0.0:
		amt = minf((diff - maxd) * 0.45, lz)
	if diff > rc:
		amt = maxf(amt, minf((diff - rc) * 0.45, depth[hi_i]))
	amt = minf(amt, depth[hi_i])
	if amt <= 0.0:
		return 0.0
	depth[hi_i] -= amt
	loose[hi_i] = maxf(0.0, minf(lz - amt, depth[hi_i]))
	depth[lo_i] += amt
	loose[lo_i] += amt
	return amt


func _relax_tile(tx: int, tz: int) -> float:
	var x0 := tx * TILE
	var z0 := tz * TILE
	var x1 := mini(x0 + TILE, W - 1)
	var z1 := mini(z0 + TILE, H - 1)
	_sync_cells(maxi(x0 - 1, 0), maxi(z0 - 1, 0), mini(x1, W - 1), mini(z1, H - 1))
	var maxd := repose
	var moved := 0.0
	# Quick reject: a tile whose surface (plus its +x/+z border) is within the repose limit
	# everywhere cannot move snow. Most queued neighbour tiles end here.
	var hmin := INF
	var hmax := -INF
	for z in range(z0, mini(z1 + 1, H)):
		var row0 := z * W
		for x in range(x0, mini(x1 + 1, W)):
			var i0 := row0 + x
			if surf[i0] == S_BLOCKED:
				continue
			var hh := ground[i0] + depth[i0]
			if hh < hmin:
				hmin = hh
			if hh > hmax:
				hmax = hh
	if hmax - hmin <= maxd:
		return 0.0
	var g := guard_ttl > 0 and x1 >= guard_x0 and x0 <= guard_x1 and z1 >= guard_z0 and z0 <= guard_z1
	var rc := repose_cut
	# Each cell is compared with its +x and +z neighbour; flow goes from the higher to the lower
	# cell (both directions), so every edge in the tile is visited once per pass. Loose snow on the
	# higher cell slumps at the angle of repose; undisturbed snow keeps steep cut walls. Snow never
	# slumps into the road from the property side, into a guarded strip behind a blade, or into a
	# completed clearing box (held cells) from outside it.
	for z in range(z0, z1):
		var row := z * W
		for x in range(x0, x1):
			var i := row + x
			var si := surf[i]
			if si == S_BLOCKED:
				continue
			var hi := ground[i] + depth[i]
			# +x neighbour
			var n := i + 1
			var sn := surf[n]
			if sn != S_BLOCKED:
				var hn := ground[n] + depth[n]
				var diff := hi - hn
				if diff > maxd:
					if not (sn == S_ROAD and si != S_ROAD) and not (g and _guarded(n)) and not (hold[n] == 1 and hold[i] == 0):
						var amt := _slump(i, n, diff, maxd, rc)
						hi -= amt
						moved += amt
				elif -diff > maxd:
					if not (si == S_ROAD and sn != S_ROAD) and not (g and _guarded(i)) and not (hold[i] == 1 and hold[n] == 0):
						var amt2 := _slump(n, i, -diff, maxd, rc)
						hi += amt2
						moved += amt2
			# +z neighbour
			n = i + W
			sn = surf[n]
			if sn != S_BLOCKED:
				var hn2 := ground[n] + depth[n]
				var diff2 := hi - hn2
				if diff2 > maxd:
					if not (sn == S_ROAD and si != S_ROAD) and not (g and _guarded(n)) and not (hold[n] == 1 and hold[i] == 0):
						moved += _slump(i, n, diff2, maxd, rc)
				elif -diff2 > maxd:
					if not (si == S_ROAD and sn != S_ROAD) and not (g and _guarded(i)) and not (hold[i] == 1 and hold[n] == 0):
						moved += _slump(n, i, -diff2, maxd, rc)
	if moved > 1e-6:
		mark_dirty(x0 - 1, z0 - 1, x1 + 1, z1 + 1)
	return moved


# -----------------------------------------------------------------------------
# Core operations
# -----------------------------------------------------------------------------

## Cells whose centers lie inside an oriented rectangle. center/fwd in world XZ.
## The rectangle spans [0, length] along fwd and [-width/2, width/2] across.
func cells_in_obb(origin: Vector2, fwd: Vector2, width: float, length: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	fwd = fwd.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var corners := [origin + right * width * 0.5, origin - right * width * 0.5,
		origin + fwd * length + right * width * 0.5, origin + fwd * length - right * width * 0.5]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for c in corners:
		mn = mn.min(c)
		mx = mx.max(c)
	var x0 := clampi(int(floor(mn.x * INV_CELL)), 0, W - 1)
	var z0 := clampi(int(floor(mn.y * INV_CELL)), 0, H - 1)
	var x1 := clampi(int(floor(mx.x * INV_CELL)), 0, W - 1)
	var z1 := clampi(int(floor(mx.y * INV_CELL)), 0, H - 1)
	var hw := width * 0.5
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2((x + 0.5) * CELL, (z + 0.5) * CELL) - origin
			var a := c.dot(fwd)
			var b := c.dot(right)
			if a >= 0.0 and a <= length and absf(b) <= hw:
				out.append(z * W + x)
	if out.is_empty():
		# Footprint smaller than a cell: take the cell under the center of the footprint.
		var p := origin + fwd * length * 0.5
		if in_map(p.x, p.y):
			out.append(cell_z(p.y) * W + cell_x(p.x))
	return out


func _sync_list(cells: PackedInt32Array) -> void:
	if cells.is_empty():
		return
	var x0 := W
	var z0 := H
	var x1 := 0
	var z1 := 0
	for i in cells:
		var x := i % W
		@warning_ignore("integer_division")
		var z := i / W
		x0 = mini(x0, x)
		z0 = mini(z0, z)
		x1 = maxi(x1, x)
		z1 = maxi(z1, z)
	_sync_cells(x0, z0, x1, z1)


func _bounds_of(cells: PackedInt32Array) -> Rect2i:
	var x0 := W
	var z0 := H
	var x1 := 0
	var z1 := 0
	for i in cells:
		var x := i % W
		@warning_ignore("integer_division")
		var z := i / W
		x0 = mini(x0, x)
		z0 = mini(z0, z)
		x1 = maxi(x1, x)
		z1 = maxi(z1, z)
	return Rect2i(x0, z0, x1 - x0, z1 - z0)


## Scoop snow from an oriented footprint, levelling from the top down, up to max_vol (m3).
## Returns {volume, road_volume}.
func scoop(origin: Vector2, fwd: Vector2, width: float, length: float, max_vol: float, floor_d := 0.0) -> Dictionary:
	var cells := cells_in_obb(origin, fwd, width, length)
	_sync_list(cells)
	var avail := 0.0
	for i in cells:
		if surf[i] == S_BLOCKED:
			continue
		var d := depth[i] - floor_d
		if d > 0.0:
			avail += d
	if avail <= 0.0 or max_vol <= 0.0:
		return {"volume": 0.0, "road_volume": 0.0}
	var want := max_vol / CELL_AREA   # in depth-units summed over cells
	var level := floor_d
	if avail > want:
		# Find level L so that sum(max(0, d - L)) == want (bisection).
		var lo := floor_d
		var hi := floor_d
		for i in cells:
			hi = maxf(hi, depth[i])
		for _k in range(24):
			var mid := (lo + hi) * 0.5
			var s := 0.0
			for i in cells:
				if surf[i] == S_BLOCKED:
					continue
				var d := depth[i] - mid
				if d > 0.0:
					s += d
			if s > want:
				lo = mid
			else:
				hi = mid
		level = hi
	var taken := 0.0
	var taken_road := 0.0
	for i in cells:
		if surf[i] == S_BLOCKED:
			continue
		var d := depth[i]
		if d > level:
			var amt := d - level
			depth[i] = level
			loose[i] = minf(loose[i], level)
			taken += amt
			if surf[i] == S_ROAD:
				taken_road += amt
	# Exact top-up so that we never exceed the request due to bisection tolerance.
	var b := _bounds_of(cells)
	mark_dirty(b.position.x, b.position.y, b.end.x, b.end.y)
	_queue_relax(b.position.x, b.position.y, b.end.x, b.end.y)
	return {"volume": taken * CELL_AREA, "road_volume": taken_road * CELL_AREA}


## Sweep cut for hands and shovel-type tools: each listed cell loses up to bites[k] metres off its
## top (never below floor_d); the total is capped at max_vol, scaled evenly across the cells.
## Leaves a crisp trench where the scoop passed. Returns {volume, road_volume, taken} where taken
## holds the depth removed from each listed cell.
func cut(cells: PackedInt32Array, bites: PackedFloat32Array, floor_d: float, max_vol: float) -> Dictionary:
	var taken_cells := PackedFloat32Array()
	taken_cells.resize(cells.size())
	if cells.is_empty() or max_vol <= 0.0:
		return {"volume": 0.0, "road_volume": 0.0, "taken": taken_cells}
	_sync_list(cells)
	var amts := PackedFloat32Array()
	amts.resize(cells.size())
	var avail := 0.0
	for k in range(cells.size()):
		var i := cells[k]
		if surf[i] == S_BLOCKED:
			continue
		var a := minf(bites[k], depth[i] - floor_d)
		if a > 0.0:
			amts[k] = a
			avail += a
	if avail <= 0.0:
		return {"volume": 0.0, "road_volume": 0.0, "taken": taken_cells}
	var f := minf(1.0, (max_vol / CELL_AREA) / avail)
	var taken := 0.0
	var taken_road := 0.0
	for k in range(cells.size()):
		var a2 := amts[k] * f
		if a2 <= 0.0:
			continue
		var i2 := cells[k]
		depth[i2] -= a2
		loose[i2] = minf(loose[i2], depth[i2])
		taken_cells[k] = a2
		taken += a2
		if surf[i2] == S_ROAD:
			taken_road += a2
	var b := _bounds_of(cells)
	mark_dirty(b.position.x, b.position.y, b.end.x, b.end.y)
	_queue_relax(b.position.x, b.position.y, b.end.x, b.end.y)
	return {"volume": taken * CELL_AREA, "road_volume": taken_road * CELL_AREA, "taken": taken_cells}


## Setup only (not conserving): raise a smooth oblong mound over a buried object.
func add_mound(center: Vector2, half: Vector2, height: float, yaw: float) -> void:
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	var ext := maxf(half.x, half.y) + 0.5
	var x0 := clampi(int(floor((center.x - ext) * INV_CELL)), 0, W - 1)
	var z0 := clampi(int(floor((center.y - ext) * INV_CELL)), 0, H - 1)
	var x1 := clampi(int(floor((center.x + ext) * INV_CELL)), 0, W - 1)
	var z1 := clampi(int(floor((center.y + ext) * INV_CELL)), 0, H - 1)
	_sync_cells(x0, z0, x1, z1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := z * W + x
			if surf[i] == S_BLOCKED or surf[i] == S_ROAD:
				continue
			var c := Vector2((x + 0.5) * CELL, (z + 0.5) * CELL) - center
			var u := c.dot(ax) / maxf(half.x, 0.01)
			var v := c.dot(az) / maxf(half.y, 0.01)
			var r2 := u * u + v * v
			if r2 >= 1.0:
				continue
			var k := cos(sqrt(r2) * PI * 0.5)
			depth[i] = minf(depth[i] + height * k * k, maxf(ceiling - ground[i], depth[i]))
	mark_dirty(x0, z0, x1, z1)


## Mark / unmark the cells of a clearing box as held (completed box: no slump inflow).
func set_hold_rect(r: Rect2, on: bool) -> void:
	var c := _rect_cells(r)
	var v := 1 if on else 0
	for z in range(c.position.y, c.end.y):
		var row := z * W
		for x in range(c.position.x, c.end.x):
			hold[row + x] = v


## Deposit volume (m3) around a point with a cone profile. Road cells only receive snow if
## allow_road is true (snow that came from the road, graders, debug). Cells never rise above the
## ceiling: the excess spills outward into the nearest cells with room (volume is conserved).
## Returns the deposited volume (always vol unless the whole map is full).
func deposit(p: Vector2, vol: float, radius: float, allow_road := false) -> float:
	if vol <= 0.0:
		return 0.0
	radius = maxf(radius, CELL * 0.75)
	var x0 := clampi(int(floor((p.x - radius) * INV_CELL)), 0, W - 1)
	var z0 := clampi(int(floor((p.y - radius) * INV_CELL)), 0, H - 1)
	var x1 := clampi(int(floor((p.x + radius) * INV_CELL)), 0, W - 1)
	var z1 := clampi(int(floor((p.y + radius) * INV_CELL)), 0, H - 1)
	_sync_cells(x0, z0, x1, z1)
	var idxs := PackedInt32Array()
	var ws := PackedFloat32Array()
	var wsum := 0.0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := z * W + x
			var s := surf[i]
			if s == S_BLOCKED:
				continue
			if s == S_ROAD and not allow_road:
				continue
			var c := Vector2((x + 0.5) * CELL, (z + 0.5) * CELL)
			var dist := c.distance_to(p)
			if dist > radius:
				continue
			var w := 1.0 - dist / radius * 0.85
			idxs.append(i)
			ws.append(w)
			wsum += w
	var left := vol / CELL_AREA
	if wsum > 0.0:
		var dvol := left
		left = 0.0
		for k in range(idxs.size()):
			var i2 := idxs[k]
			var add := dvol * ws[k] / wsum
			var room := ceiling - ground[i2] - depth[i2]
			if add > room:
				left += add - maxf(room, 0.0)
				add = maxf(room, 0.0)
			if add > 0.0:
				depth[i2] += add
				loose[i2] += add
		mark_dirty(x0, z0, x1, z1)
		_queue_relax(x0, z0, x1, z1)
	if left > 1e-9:
		left = _spill(p, left, allow_road)
	return vol - left * CELL_AREA


## Put `amount` (depth units, i.e. m3 / CELL_AREA) into the cells nearest to p that still have room
## under the ceiling, searching outward ring by ring. Returns what could not be placed.
func _spill(p: Vector2, amount: float, allow_road := false) -> float:
	var cx := cell_x(p.x)
	var cz := cell_z(p.y)
	var r := 0
	var maxr := maxi(W, H)
	while amount > 1e-9 and r < maxr:
		var bx0 := maxi(cx - r, 0)
		var bz0 := maxi(cz - r, 0)
		var bx1 := mini(cx + r, W - 1)
		var bz1 := mini(cz + r, H - 1)
		_sync_cells(bx0, bz0, bx1, bz1)
		var ring := PackedInt32Array()
		var room_sum := 0.0
		var perim := PackedInt32Array()
		if r == 0:
			perim.append(cz * W + cx)
		else:
			for x in range(cx - r, cx + r + 1):
				for z in [cz - r, cz + r]:
					if x >= 0 and x < W and z >= 0 and z < H:
						perim.append(z * W + x)
			for z in range(cz - r + 1, cz + r):
				for x in [cx - r, cx + r]:
					if x >= 0 and x < W and z >= 0 and z < H:
						perim.append(z * W + x)
		for i in perim:
			var s := surf[i]
			if s == S_BLOCKED or (s == S_ROAD and not allow_road):
				continue
			var room := ceiling - ground[i] - depth[i]
			if room > 1e-6:
				ring.append(i)
				room_sum += room
		if room_sum > 0.0:
			var f := minf(1.0, amount / room_sum)
			for i in ring:
				var add := (ceiling - ground[i] - depth[i]) * f
				depth[i] += add
				loose[i] += add
				amount -= add
			mark_dirty(bx0, bz0, bx1, bz1)
			_queue_relax(bx0, bz0, bx1, bz1)
		r += 1
	return maxf(amount, 0.0)


## Blade push step (pushers, scrapers, plows). The blade is a segment centred at `center`
## with face normal `face_n` (the direction snow is pushed) and tangent across the blade.
## Snow under/behind the face within `band` is moved ahead of the face along the face normal.
## Returns {moved, berm, blocked_volume}.
func blade_push(center: Vector2, face_n: Vector2, half_w: float, band: float, floor_d: float, player_rule := true, push_dist := 0.4) -> Dictionary:
	face_n = face_n.normalized()
	var tang := Vector2(-face_n.y, face_n.x)
	var reach := half_w + 0.3
	var mn := center - Vector2(reach + band, reach + band)
	var mx := center + Vector2(reach + band, reach + band)
	var x0 := clampi(int(floor(mn.x * INV_CELL)) - 2, 0, W - 1)
	var z0 := clampi(int(floor(mn.y * INV_CELL)) - 2, 0, H - 1)
	var x1 := clampi(int(floor(mx.x * INV_CELL)) + 2, 0, W - 1)
	var z1 := clampi(int(floor(mx.y * INV_CELL)) + 2, 0, H - 1)
	_sync_cells(maxi(x0 - 4, 0), maxi(z0 - 4, 0), mini(x1 + 4, W - 1), mini(z1 + 4, H - 1))
	var moved := 0.0
	var kept := 0.0
	var berm := 0.0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := z * W + x
			var c := Vector2((x + 0.5) * CELL, (z + 0.5) * CELL) - center
			var along := c.dot(tang)
			if absf(along) > half_w:
				continue
			var ahead := c.dot(face_n)
			if ahead > 0.0 and ahead < 0.65:
				berm += depth[i]
			if ahead > 0.0 or ahead < -band:
				continue
			var s := surf[i]
			if s == S_BLOCKED:
				continue
			var d := depth[i] - floor_d
			if d <= 0.0:
				continue
			# Target: pushed out ahead of the face along its normal.
			var tp := center + tang * along + face_n * (push_dist + push_rng.randf() * 0.12)
			if not in_map(tp.x, tp.y):
				continue
			var tx := cell_x(tp.x)
			var tz := cell_z(tp.y)
			var t := tz * W + tx
			if t == i:
				continue
			var ts := surf[t]
			if ts == S_BLOCKED:
				kept += d
				continue
			if player_rule and ts == S_ROAD and s != S_ROAD:
				kept += d   # curb acts as a wall: snow stays on the property side
				continue
			# The berm can't rise above the ceiling: whatever doesn't fit stays in front of the blade.
			var mv := minf(d, maxf(ceiling - ground[t] - depth[t], 0.0))
			if mv < d:
				kept += d - mv
			if mv <= 0.0:
				continue
			depth[i] -= mv
			depth[t] += mv
			loose[t] += mv
			loose[i] = minf(loose[i], depth[i])
			moved += mv
	if moved > 0.0:
		mark_dirty(x0, z0, x1, z1)
		_queue_relax(x0, z0, x1, z1)
	return {"moved": moved * CELL_AREA, "berm": berm * CELL_AREA, "kept": kept * CELL_AREA}


## Remove snow from an intake footprint (blowers, electric shovels, sleigh loading),
## nearest the intake first, up to max_vol. Returns {volume, road_volume}.
func intake(origin: Vector2, fwd: Vector2, width: float, length: float, max_vol: float, floor_d := 0.005) -> Dictionary:
	var cells := cells_in_obb(origin, fwd, width, length)
	_sync_list(cells)
	var budget := max_vol / CELL_AREA
	var taken := 0.0
	var taken_road := 0.0
	# Order by distance along fwd (cells are generated row-major; sort a small array).
	var order := []
	for i in cells:
		@warning_ignore("integer_division")
		var c := Vector2((i % W + 0.5) * CELL, (i / W + 0.5) * CELL) - origin
		order.append([c.dot(fwd), i])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for e in order:
		if budget <= 0.0:
			break
		var i: int = e[1]
		if surf[i] == S_BLOCKED:
			continue
		var d := depth[i] - floor_d
		if d <= 0.0:
			continue
		var amt := minf(d, budget)
		depth[i] -= amt
		loose[i] = minf(loose[i], depth[i])
		budget -= amt
		taken += amt
		if surf[i] == S_ROAD:
			taken_road += amt
	if taken > 0.0:
		var b := _bounds_of(cells)
		mark_dirty(b.position.x, b.position.y, b.end.x, b.end.y)
		_queue_relax(b.position.x, b.position.y, b.end.x, b.end.y)
	return {"volume": taken * CELL_AREA, "road_volume": taken_road * CELL_AREA}


## Set every cell in a rect to an exact depth (debug / contract cleanup / setup). Not conserving.
func set_rect(r: Rect2, d: float, only_above := false) -> float:
	var c := _rect_cells(r)
	if c.size.x <= 0 or c.size.y <= 0:
		return 0.0
	_sync_cells(c.position.x, c.position.y, c.end.x - 1, c.end.y - 1)
	var removed := 0.0
	for z in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			var i := z * W + x
			if surf[i] == S_BLOCKED:
				continue
			if only_above and depth[i] <= d:
				continue
			removed += depth[i] - d
			depth[i] = d
			# Setting a depth lays settled (cohesive) snow; trimming only the top keeps what's left.
			loose[i] = minf(loose[i], d) if only_above else 0.0
	mark_dirty(c.position.x, c.position.y, c.end.x, c.end.y)
	_queue_relax(c.position.x, c.position.y, c.end.x, c.end.y)
	return removed * CELL_AREA


## Add a uniform layer (debug). Not conserving.
func add_layer_rect(r: Rect2, d: float) -> void:
	var c := _rect_cells(r)
	_sync_cells(c.position.x, c.position.y, c.end.x - 1, c.end.y - 1)
	for z in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			var i := z * W + x
			if surf[i] != S_BLOCKED:
				depth[i] = clampf(depth[i] + d, 0.0, maxf(ceiling - ground[i], 0.0))
	mark_dirty(c.position.x, c.position.y, c.end.x, c.end.y)


## Polish 5 §13: melt up to `amount` (m of depth) off the top of every cell in a world rect (the
## heated pad, a heated box). Buildings' cells are skipped. What melts leaves the snow and goes into
## the ledger `melted` (m³, each cell's removal measured after it is stored, so the ledger matches
## the depth array exactly). Neighbouring loose snow may slump onto the melted cells (relaxation
## is queued, as after any operation). Returns the volume melted (m³).
## Bare cells (a float's worth of snow, e.g. what the lazy snowfall's rounding leaves) don't count.
const MELT_MIN := 1e-6


func melt_rect(r: Rect2, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var c := _rect_cells(r)
	if c.size.x <= 0 or c.size.y <= 0:
		return 0.0
	_sync_cells(c.position.x, c.position.y, c.end.x - 1, c.end.y - 1)
	var gone := 0.0
	for z in range(c.position.y, c.end.y):
		var row := z * W
		for x in range(c.position.x, c.end.x):
			var i := row + x
			var d := depth[i]
			if d <= MELT_MIN or surf[i] == S_BLOCKED:
				continue
			depth[i] = maxf(d - amount, 0.0)
			var after := depth[i]
			gone += d - after
			if loose[i] > after:
				loose[i] = after
	if gone <= 0.0:
		return 0.0
	mark_dirty(c.position.x, c.position.y, c.end.x, c.end.y)
	_queue_relax(c.position.x, c.position.y, c.end.x, c.end.y)
	var v := gone * CELL_AREA
	melted += v
	return v


func clear_all() -> void:
	sync_all()
	depth.fill(0.0)
	_mark_all_dirty()


## Wading (polish 2 §5): pushing through deep snow leaves a trench. The cells under the body are
## trodden down to about 40 % of their depth (at least 12 cm stays) and the snow is shouldered
## aside onto both flanks as loose snow — volume is conserved. Road snow is only shouldered by
## someone standing on the road, and yard snow never lands on the road (road rule). Snow inside
## a completed box (bare, held) is left alone, and so is snow whose surface is above `max_top`
## (the wader's hips: snow taller than that is a wall to dig through, not something you can tread
## down by leaning on it). Returns the volume moved (m3). Polish 5 §13: `keep_frac` is the share of
## the depth left under the feet at each wade (0.4; on snowshoes much more: a shallow track, Player).
## With `stamp` > 0 (snowshoes) the cells trodden are noted in `recent` (cell -> stamp) and a cell
## trodden by one of the last RECENT_WADES wades isn't trodden again: one pass treads once.
const WADE_MIN := 0.15

const RECENT_WADES := 3

func wade(p: Vector2, dir: Vector2, radius := 0.26, max_top := INF, keep_frac := 0.4, recent: Dictionary = {}, stamp := 0) -> float:
	if not in_map(p.x, p.y) or dir.length() < 0.01:
		return 0.0
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	var x0 := clampi(int(floor((p.x - radius) * INV_CELL)), 0, W - 1)
	var z0 := clampi(int(floor((p.y - radius) * INV_CELL)), 0, H - 1)
	var x1 := clampi(int(floor((p.x + radius) * INV_CELL)), 0, W - 1)
	var z1 := clampi(int(floor((p.y + radius) * INV_CELL)), 0, H - 1)
	_sync_cells(x0, z0, x1, z1)
	var yard := 0.0
	var road := 0.0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2((x + 0.5) * CELL, (z + 0.5) * CELL)
			if c.distance_to(p) > radius:
				continue
			var i := z * W + x
			if surf[i] == S_BLOCKED or hold[i] == 1:
				continue
			var d := depth[i]
			if d < WADE_MIN or ground[i] + d > max_top:
				continue
			if stamp > 0:
				if recent.has(i) and stamp - int(recent[i]) <= RECENT_WADES:
					continue
				recent[i] = stamp
			var keep := maxf(0.12, d * keep_frac)
			var take := d - keep
			depth[i] = keep
			loose[i] = minf(loose[i], keep)
			if surf[i] == S_ROAD:
				road += take
			else:
				yard += take
	var moved := yard + road
	if moved <= 0.0:
		return 0.0
	mark_dirty(x0, z0, x1, z1)
	_queue_relax(x0, z0, x1, z1)
	for s in [1.0, -1.0]:
		var at: Vector2 = p + side * float(s) * (radius + 0.3)
		if yard > 0.0:
			deposit(at, yard * 0.5 * CELL_AREA, 0.22, false)
		if road > 0.0:
			deposit(at, road * 0.5 * CELL_AREA, 0.22, true)
	return moved * CELL_AREA


## (Before polish 2 footsteps used to shave a little off shallow snow without putting it
## anywhere — not volume conserving. Kept for old callers; does nothing now.)
func compress_footprint(_p: Vector2, _amount: float) -> void:
	pass


## Municipal grader lane pass (exempt from the road rule). Clears a lane band to a ragged
## residual and windrows the snow beyond the lane edge on the push side (onto the road edge,
## boulevard, sidewalk and driveway aprons). Returns moved volume (m3).
func grader_lane(a: Vector2, b: Vector2, push: Vector2, blade_w: float, residual: float, seed_val: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var along := (b - a).normalized()
	var length := a.distance_to(b)
	var mn := a.min(b) - Vector2(blade_w + 4, blade_w + 4)
	var mx := a.max(b) + Vector2(blade_w + 4, blade_w + 4)
	var x0 := clampi(int(floor(mn.x * INV_CELL)), 0, W - 1)
	var z0 := clampi(int(floor(mn.y * INV_CELL)), 0, H - 1)
	var x1 := clampi(int(floor(mx.x * INV_CELL)), 0, W - 1)
	var z1 := clampi(int(floor(mx.y * INV_CELL)), 0, H - 1)
	_sync_cells(x0, z0, x1, z1)
	var hw := blade_w * 0.5
	# Collect volume per along-slice so the windrow follows the lane.
	var slices := int(ceil(length / CELL)) + 1
	var slice_vol := PackedFloat32Array()
	slice_vol.resize(slices)
	var patch_noise := FastNoiseLite.new()
	patch_noise.seed = seed_val
	patch_noise.frequency = 0.12
	var total := 0.0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := z * W + x
			var c := Vector2((x + 0.5) * CELL, (z + 0.5) * CELL)
			var rel := c - a
			var s := rel.dot(along)
			if s < 0.0 or s > length:
				continue
			var off := rel.dot(push)  # positive toward the push side
			if absf(off) > hw:
				continue
			# Leftover ridges and patches: the city is bad at its job.
			var n := patch_noise.get_noise_2d(x, z)
			var res := residual * (1.0 + 0.9 * n)
			if n > 0.45:
				res = depth[i] * 0.55   # skipped patch
			if absf(off) > hw - 0.3:
				res = maxf(res, depth[i] * 0.45)  # uneven blade edge
			var d := depth[i] - maxf(res, 0.0)
			if d <= 0.0:
				continue
			depth[i] -= d
			var si := clampi(int(s / CELL), 0, slices - 1)
			slice_vol[si] += d
			total += d
	# Windrow: deposit just beyond the blade edge on the push side (1.6 m band).
	var edge_off := hw + 0.2
	for si in range(slices):
		var v := slice_vol[si]
		if v <= 0.0:
			continue
		var base := a + along * (si * CELL + CELL * 0.5)
		var placed := 0.0
		var weights := [0.12, 0.2, 0.22, 0.2, 0.14, 0.08, 0.04]
		for k in range(weights.size()):
			var p := base + push * (edge_off + k * CELL)
			if not in_map(p.x, p.y):
				continue
			var t := cell_z(p.y) * W + cell_x(p.x)
			if surf[t] == S_BLOCKED:
				continue
			var amt: float = minf(v * weights[k], maxf(ceiling - ground[t] - depth[t], 0.0))
			depth[t] += amt
			loose[t] += amt
			placed += amt
		if placed < v:
			# Windrow at the ceiling: spill the rest outward (city grader is exempt from the road rule).
			var p2 := base + push * edge_off
			var rest := _spill(p2, v - placed, true)
			if rest > 0.0:
				depth[cell_z(base.y) * W + cell_x(base.x)] += rest
	mark_dirty(x0, z0, x1, z1)
	_queue_relax(x0, z0, x1, z1)
	return total * CELL_AREA


## Polish 5 §11: the city's sidewalk crew on a sidewalk rect `r` (whole cells). Every cell is
## cleared to bare pavement and held (no slump inflow, as in a completed box), and its snow goes —
## volume conserved — straight out from the sidewalk in `out` (a cell step toward the street), column
## by column, onto the strip between the sidewalk and the street (the cells beyond it up to the
## curb: the boulevard, or a driveway's apron) as a mound on the strip's sidewalk side (CREW_MOUND),
## beside the grader's windrow, which lies on its street side. Whatever a column's strip has no room
## for under the ceiling goes onto the street's edge, outward from the curb (Decision 12). Returns
## the volume moved (m³).
const CREW_MOUND := [0.3, 0.3, 0.2, 0.12, 0.06, 0.02]
const CREW_STRIP_MAX := 12   # cells looked at beyond the sidewalk for the strip (the boulevard is 6)
const CREW_EDGE_MAX := 24    # cells of the street the overflow may go to, from the curb
## What is left of a column after the strip is float32 rounding below this (depth units, 1 µm):
## not overflow.
const CREW_RESIDUE := 1e-6


func sidewalk_clear(r: Rect2, out: Vector2i) -> float:
	var c := _rect_cells(r)
	if c.size.x <= 0 or c.size.y <= 0 or out == Vector2i.ZERO:
		return 0.0
	var cols_x := out.y != 0          # out along z: one column per x cell
	var n_cols := c.size.x if cols_x else c.size.y
	var n_deep := c.size.y if cols_x else c.size.x
	# The first strip cell of column 0, just beyond the rect on the street side.
	var edge := Vector2i(c.position.x, c.end.y if out.y > 0 else c.position.y - 1) if cols_x \
		else Vector2i(c.end.x if out.x > 0 else c.position.x - 1, c.position.y)
	var step := Vector2i(1, 0) if cols_x else Vector2i(0, 1)
	var reach := CREW_STRIP_MAX + CREW_EDGE_MAX
	var lo := Vector2i(mini(c.position.x, c.position.x + out.x * reach), mini(c.position.y, c.position.y + out.y * reach))
	var hi := Vector2i(maxi(c.end.x - 1, c.end.x - 1 + out.x * reach), maxi(c.end.y - 1, c.end.y - 1 + out.y * reach))
	lo = lo.clamp(Vector2i.ZERO, Vector2i(W - 1, H - 1))
	hi = hi.clamp(Vector2i.ZERO, Vector2i(W - 1, H - 1))
	_sync_cells(lo.x, lo.y, hi.x, hi.y)
	var moved := 0.0
	for k in range(n_cols):
		var total := 0.0
		for j in range(n_deep):
			var cell := Vector2i(c.position.x + k, c.position.y + j) if cols_x else Vector2i(c.position.x + j, c.position.y + k)
			var i := cell.y * W + cell.x
			if surf[i] == S_BLOCKED:
				continue
			total += depth[i]
			depth[i] = 0.0
			loose[i] = 0.0
			hold[i] = 1
		if total <= 0.0:
			continue
		# The strip: the cells beyond the sidewalk up to the curb (the first street cell); then the
		# street's edge, outward from the curb.
		var strip := PackedInt32Array()
		var road := PackedInt32Array()
		var p := edge + step * k
		for n in range(reach):
			if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
				break
			var i2 := p.y * W + p.x
			var s2 := surf[i2]
			if s2 == S_ROAD:
				if road.size() >= CREW_EDGE_MAX:
					break
				road.append(i2)
			elif not road.is_empty() or strip.size() >= CREW_STRIP_MAX:
				break
			elif s2 != S_BLOCKED:
				strip.append(i2)
			p += out
		var left := _crew_fill(strip, total, CREW_MOUND)
		if left > CREW_RESIDUE:
			left = _crew_fill(strip, left, [])     # whatever room is left on the strip
		if left > CREW_RESIDUE:
			left = _crew_fill(road, left, [])      # the street's edge
		if left > CREW_RESIDUE:
			# Nowhere along the column (not on this map): the nearest room, as every operation does.
			var pc: int = strip[0] if not strip.is_empty() else (road[0] if not road.is_empty() else (edge + step * k).y * W + (edge + step * k).x)
			@warning_ignore("integer_division")
			left = _spill(Vector2((pc % W + 0.5) * CELL, (pc / W + 0.5) * CELL), left, true)
		moved += total - maxf(left, 0.0)
	mark_dirty(lo.x, lo.y, hi.x, hi.y)
	_queue_relax(lo.x, lo.y, hi.x, hi.y)
	return moved * CELL_AREA


## Put `amount` (depth units) into `cells` under the ceiling: by `weights` (the first cells, each
## at most its room; the last weighted cell takes what is left), or with no weights each cell up
## to its room in turn. What a cell receives is read back from the float32 map, so what is placed
## is counted exactly. Returns what didn't fit.
func _crew_fill(cells: PackedInt32Array, amount: float, weights: Array) -> float:
	var left := amount
	if cells.is_empty() or amount <= 0.0:
		return left
	var n := cells.size() if weights.is_empty() else mini(cells.size(), weights.size())
	var wsum := 0.0
	for k in range(n):
		wsum += 1.0 if weights.is_empty() else float(weights[k])
	if wsum <= 0.0:
		return left
	for k in range(n):
		var i := cells[k]
		var room := maxf(ceiling - ground[i] - depth[i], 0.0)
		var share := left if weights.is_empty() or k == n - 1 else amount * float(weights[k]) / wsum
		var add := minf(minf(share, left), room)
		if add <= 0.0:
			continue
		var before := depth[i]
		depth[i] = before + add
		var got := depth[i] - before
		loose[i] += got
		left -= got
		if weights.is_empty() and left <= CREW_RESIDUE:
			break
	return left


# -----------------------------------------------------------------------------
# Persistence (compact: zstd-compressed float32 depth + scalars)
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	sync_all()
	# Quantize to 1 mm, delta-encode along rows, compress. The live state is snapped to the
	# same quantization so the running game and a reloaded save are bit-identical.
	var q := PackedInt32Array()
	q.resize(W * H)
	var prev := 0
	for i in range(W * H):
		var v := int(round(depth[i] * 1000.0))
		if v < 0:
			v = 0
		depth[i] = v / 1000.0
		q[i] = v - prev
		prev = v
	var raw := q.to_byte_array()
	var comp := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var rx := {}
	for k in roof_extra.keys():
		rx[str(k)] = roof_extra[k]
	var lq := PackedInt32Array()
	lq.resize(W * H)
	for i in range(W * H):
		var lv := int(round(minf(loose[i], depth[i]) * 1000.0))
		loose[i] = lv / 1000.0
		lq[i] = lv
	var lcomp := lq.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)
	return {"w": W, "h": H, "fmt": 2, "size": raw.size(), "data": comp, "fall_total": fall_total,
		"settle_clock": settle_clock, "moved": stat_player_moved, "roof": roof_depth, "roof_extra": rx,
		"loose": lcomp, "melted": melted}


## Polish 6 §3 (version 3, optional keys of the save's snow, beside serialize()): the relaxation
## still pending, in the order it would run — the hot list from its read index, then the cold
## stack — and blade_push's stream (its state as text: a 64-bit value, which a JSON number can't
## hold exactly). deserialize() reads both back.
func serialize_pending() -> Dictionary:
	var hot := []
	for k in range(hot_head, relax_hot.size()):
		hot.append(relax_hot[k])
	return {"relax": {"hot": hot, "cold": Array(relax_list)}, "push_rng": str(push_rng.state)}


func deserialize(d: Dictionary) -> bool:
	if int(d.get("w", 0)) != W or int(d.get("h", 0)) != H:
		return false
	var comp: PackedByteArray = d.get("data", PackedByteArray())
	var raw := comp.decompress(int(d.get("size", 0)), FileAccess.COMPRESSION_ZSTD)
	if raw.size() != W * H * 4:
		return false
	_apply_balance()
	if int(d.get("fmt", 1)) == 2:
		var q := raw.to_int32_array()
		var acc := 0
		for i in range(W * H):
			acc += q[i]
			depth[i] = acc / 1000.0
	else:
		depth = raw.to_float32_array()
	fall_total = float(d.get("fall_total", 0.0))
	settle_clock = float(d.get("settle_clock", 0.0))
	stat_player_moved = float(d.get("moved", 0.0))
	melted = float(d.get("melted", 0.0))      # polish 5 §13 (version 3, optional)
	roof_depth = float(d.get("roof", 0.3))
	roof_extra.clear()
	var rx: Dictionary = d.get("roof_extra", {})
	for k in rx.keys():
		roof_extra[int(k)] = float(rx[k])
	loose.fill(0.0)
	var lc = d.get("loose", PackedByteArray())
	if lc is PackedByteArray and (lc as PackedByteArray).size() > 0:
		var lr := (lc as PackedByteArray).decompress(W * H * 4, FileAccess.COMPRESSION_ZSTD)
		if lr.size() == W * H * 4:
			var li := lr.to_int32_array()
			for i in range(W * H):
				loose[i] = li[i] / 1000.0
	hold.fill(0)
	chunk_fall.fill(fall_total)
	chunk_settle.fill(settle_clock)
	relax_queue.clear()
	relax_list.clear()
	relax_hot.clear()
	hot_head = 0
	guard_ttl = 0
	# Polish 6 §3: the pending relaxation as saved; a save without it is settled once on load
	# (Saves.load_game → settle_all, after the boxes' held cells are restored).
	var rq = d.get("relax", null)
	settle_on_load = not (rq is Dictionary)
	settling = false
	if rq is Dictionary:
		for v in (rq as Dictionary).get("hot", []):
			_restore_tile(int(v), true)
		for v in (rq as Dictionary).get("cold", []):
			_restore_tile(int(v), false)
	var ps := str(d.get("push_rng", ""))
	if ps.is_valid_int():
		push_rng.state = ps.to_int()
	else:
		push_rng.seed = PUSH_SEED
	_mark_all_dirty()
	initialized = true
	reset_done.emit()
	return true
