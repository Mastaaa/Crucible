extends RefCounted
## Seeded map generator. The same seed always builds the same map.
##
##   Surface   0-200      sky and a flat pad holding the Hub
##   Topsoil   200-1500   dirt with stone lumps, two sealed aquifers (~19,000 water cells each)
##   Stone     1500-3000  stone, glimmer veins (~38,000 cells), air caves, water pockets
##   Magma     3000-4500  hot rock, 3-5 lava pockets and a ~32,000-cell lava lake
##   Chamber   4500-5120  bedrock shell around the Crucible; the only way in is a
##                        40-cell plug of hot rock in the ceiling
## Layer boundaries wobble by up to 48 cells. Bedrock lines the sides and floor.
## Springs sit on the floor of every aquifer and pocket and in some caves.
## Coal lies in seams through the Topsoil and Stone, and caps one lava pocket
## behind a skin of stone; Sulfur crusts sit beside lava and in deep stone.
##
## Phase 8b: the v2 map (256 x 1024) laid out SX times wider and SY times deeper,
## with its features F times bigger each way; the Hub and the Crucible are D.S
## times their v2 size.

const D = preload("res://scripts/defs.gd")
const SR = preload("res://scripts/spawn_regions.gd")
const W := D.W
const H := D.H
const SX := 3        # layout across, against the v2 map
const SY := 5        # layout down
const F := 4         # features (caves, aquifers, veins, pockets, the lake, the chamber)
const KSHIFT := 2    # the masks `_near` reads are in blocks of 4 x 4 cells
const KS := 1 << KSHIFT

const HUB_SIZE := Vector2i(8, 6) * D.S
const HUB_RECT := Rect2i((W >> 1) - (HUB_SIZE.x >> 1), D.GROUND_Y - HUB_SIZE.y, HUB_SIZE.x, HUB_SIZE.y)
const PAD_FLAT := 20 * D.S    # the ground is flat this far either side of the middle...
const PAD_BLEND := 6 * D.S    # ...and blends into the wobble over this much more
# The chamber is a dome resting on the floor; the Crucible stands on a bedrock
# altar in the middle, so a Conduit hung from the ceiling under the plug is
# within reach of it.
const CHAMBER_CX := W >> 1
const CHAMBER_FLOOR := 1010 * SY
const CHAMBER_RX := 104 * SX
const CHAMBER_RY := 62 * F
const CRUCIBLE_SIZE := Vector2i(14, 8) * D.S
const CRUCIBLE_DROP := 7 * D.S   # the Crucible's top sits this far under the dome's ceiling
const PLUG_W := 10 * F
const PLUG_SPREAD := 0.6         # the plug stays within this fraction of the dome's half-width of its middle

var rng := RandomNumberGenerator.new()
var g := PackedByteArray()
var features: Array = []     # Rect2i of placed pockets, for spacing
var spawn_table := {}        # data/spawn_regions.json unless a test sets its own
var _masks := {}             # material -> blocks (KS x KS) holding any of it, built on demand


func generate(sim: RefCounted, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	features.clear()
	_masks.clear()

	var wobble := FastNoiseLite.new()
	wobble.seed = seed_value
	wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wobble.frequency = 0.035 / F

	var lumps := FastNoiseLite.new()
	lumps.seed = seed_value + 17
	lumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	lumps.frequency = 0.05 / F
	lumps.fractal_type = FastNoiseLite.FRACTAL_FBM
	lumps.fractal_octaves = 2

	# --- Column profiles ---
	var ground := PackedInt32Array()
	var topsoil_end := PackedInt32Array()
	var shell_top := PackedInt32Array()
	ground.resize(W)
	topsoil_end.resize(W)
	shell_top.resize(W)
	for x in W:
		var gy := D.GROUND_Y + int(round(wobble.get_noise_1d(x) * 4.0 * F))
		var pad := absi(x - (W >> 1))
		if pad <= PAD_FLAT:
			gy = D.GROUND_Y
		elif pad <= PAD_FLAT + PAD_BLEND:
			gy = int(round(lerpf(D.GROUND_Y, gy, (pad - PAD_FLAT) / float(PAD_BLEND))))
		ground[x] = gy
		topsoil_end[x] = 300 * SY + int(round(wobble.get_noise_1d(x + 700.0 * F) * 12.0 * F))
		shell_top[x] = 900 * SY + int(round(wobble.get_noise_1d(x + 1400.0 * F) * 5.0 * F))

	# --- Bands --- (rows wholly inside one band are copied whole)
	var lo := [ground.duplicate(), topsoil_end.duplicate(), shell_top.duplicate()]
	for k in 3:
		lo[k].sort()
	var bands := [D.AIR, D.DIRT, D.STONE, D.BEDROCK]
	var whole: Array = []
	for m: int in bands:
		var row := PackedByteArray()
		row.resize(W)
		row.fill(m)
		whole.append(row)
	g = PackedByteArray()
	for y in H:
		var band := 0
		var mixed := false
		for k in 3:
			if y >= lo[k][W - 1]:
				band = k + 1
			elif y >= lo[k][0]:
				mixed = true
				break
		if not mixed:
			g.append_array(whole[band])
			continue
		var row := PackedByteArray()
		row.resize(W)
		for x in W:
			row[x] = D.AIR if y < ground[x] else (D.DIRT if y < topsoil_end[x] else (D.STONE if y < shell_top[x] else D.BEDROCK))
		g.append_array(row)

	# Stone lumps in the Topsoil (kept off the surface so the pad stays dirt).
	for y in range(D.GROUND_Y + 8 * F, 312 * SY):
		var row := y * W
		for x in range(2, W - 2):
			if g[row + x] == D.DIRT and lumps.get_noise_2d(x, y * 1.3) > 0.4:
				g[row + x] = D.STONE

	# Ragged Topsoil/Stone boundary: a few dirt tongues reach down into the stone.
	for x in range(2, W - 2):
		var tongue := int(maxf(0.0, lumps.get_noise_2d(x * 2.0, 5000.0 * F) * 14.0 * F))
		for y in range(topsoil_end[x], topsoil_end[x] + tongue):
			if g[y * W + x] == D.STONE:
				g[y * W + x] = D.DIRT

	# --- Topsoil: two sealed aquifers ---
	var aquifers: Array = []
	aquifers.append(_place_blob(D.WATER, [D.DIRT, D.STONE], Vector2i(72, 184) * SX, Vector2i(105, 165) * SY, Vector2i(28, 14) * F))
	aquifers.append(_place_blob(D.WATER, [D.DIRT, D.STONE], Vector2i(30, 226) * SX, Vector2i(185, 255) * SY, Vector2i(28, 14) * F))

	# --- Stone: glimmer veins, caves, water pockets ---
	var glimmer := _veins(2400 * F * F, 318 * SY, 585 * SY)
	var caves := rng.randi_range(1, 2)
	var cave_rects: Array = []
	for _i in caves:
		cave_rects.append(_place_blob(D.AIR, [D.STONE, D.GLIMMER], Vector2i(24, 232) * SX, Vector2i(330, 575) * SY, Vector2i(22, 8) * F))
	var pockets := rng.randi_range(1, 2)
	for _i in pockets:
		aquifers.append(_place_blob(D.WATER, [D.STONE, D.GLIMMER], Vector2i(24, 232) * SX, Vector2i(330, 575) * SY, Vector2i(20, 10) * F))

	# --- Chamber, plug and lake (the plug decides where the lake and the Crucible go) ---
	var spread := int(CHAMBER_RX * PLUG_SPREAD)
	var plug_x := rng.randi_range(CHAMBER_CX - spread, CHAMBER_CX + spread) - (PLUG_W >> 1)
	var lake := _lava_lake(plug_x)
	# The Crucible stands on an altar right under the plug, its top CRUCIBLE_DROP
	# below the dome ceiling so a Conduit hung there can reach it.
	var pc := plug_x + (PLUG_W >> 1)
	var nx := (pc - CHAMBER_CX) / float(CHAMBER_RX)
	var ceiling := int(ceil(CHAMBER_FLOOR - CHAMBER_RY * sqrt(maxf(0.0, 1.0 - nx * nx))))
	var crucible_rect := Rect2i(pc - (CRUCIBLE_SIZE.x >> 1), ceiling + CRUCIBLE_DROP, CRUCIBLE_SIZE.x, CRUCIBLE_SIZE.y)
	var altar_rect := Rect2i(crucible_rect.position.x - 6 * D.S, crucible_rect.end.y,
			crucible_rect.size.x + 12 * D.S, CHAMBER_FLOOR - crucible_rect.end.y)

	# --- Magma: lava pockets ---
	var pocket_count := rng.randi_range(3, 5)
	var lava_pockets: Array = []
	for _i in pocket_count:
		var rx := rng.randi_range(12, 19) * F
		var ry := rng.randi_range(7, 11) * F
		lava_pockets.append(_place_blob(D.LAVA, [D.STONE], Vector2i(22, 234) * SX, Vector2i(625, 800) * SY, Vector2i(rx, ry)))

	_chamber(plug_x, shell_top, altar_rect)

	# --- Walls and the Hub pad ---
	for y in H:
		var row := y * W
		g[row] = D.BEDROCK
		g[row + 1] = D.BEDROCK
		g[row + W - 2] = D.BEDROCK
		g[row + W - 1] = D.BEDROCK
	for y in range(H - 2, H):
		for x in W:
			g[y * W + x] = D.BEDROCK
	_fill(HUB_RECT, D.BUILDING)
	_fill(crucible_rect, D.BUILDING)

	var springs := _find_springs(seed_value, aquifers, cave_rects)
	var deposits := _deposits(seed_value, lava_pockets, lake)
	_ground(seed_value, aquifers, topsoil_end)
	_heat(wobble)
	if spawn_table.is_empty():
		spawn_table = SR.load_table()
	var spawned := SR.place(g, W, H, spawn_table, seed_value, {"hub": HUB_RECT, "ground": ground})

	sim.set_cells(g)
	g = PackedByteArray()
	_masks.clear()
	# Caves, aquifers and pockets wider than their rock spans start out as arches
	# that stand (the C++ sim clears what would cave in; the GDScript one has no
	# collapse).
	var arched: int = sim.stabilize()
	return {
		"seed": seed_value,
		"arched": arched,
		"hub": HUB_RECT,
		"crucible": crucible_rect,
		"plug_x": plug_x,
		"lake": lake,
		"aquifers": aquifers,
		"lava_pockets": lava_pockets,
		"glimmer": glimmer,
		"ground": ground,
		"caves": cave_rects,
		"springs": springs,
		"coal": deposits["coal"],
		"sulfur": deposits["sulfur"],
		"spawned": spawned,
	}


func _fill(r: Rect2i, mat: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g[y * W + x] = mat


## Drop a noisy ellipse of `mat` somewhere in the given ranges, away from other
## features, replacing only materials in `replace`. Returns its bounding rect.
func _place_blob(mat: int, replace: Array, x_range: Vector2i, y_range: Vector2i, radius: Vector2i) -> Rect2i:
	var best := Rect2i()
	for attempt in 40:
		var px := rng.randi_range(x_range.x, x_range.y)
		var py := rng.randi_range(y_range.x, y_range.y)
		var r := Rect2i(px - radius.x, py - radius.y, radius.x * 2 + 1, radius.y * 2 + 1)
		var ok := true
		for f in features:
			if r.grow(10 * F).intersects(f):
				ok = false
				break
		if ok or attempt == 39:
			best = r
			break
	features.append(best)
	var cx := best.position.x + radius.x
	var cy := best.position.y + radius.y
	var phase := rng.randf() * TAU
	for y in range(maxi(best.position.y, 0), mini(best.end.y, H)):
		for x in range(maxi(best.position.x, 3), mini(best.end.x, W - 3)):
			var nx := (x - cx) / float(radius.x)
			var ny := (y - cy) / float(radius.y)
			var edge := 1.0 + 0.12 * sin(atan2(ny, nx) * 3.0 + phase)
			if nx * nx + ny * ny <= edge:
				var i := y * W + x
				if g[i] in replace:
					g[i] = mat
	return best


## Springs: one on the floor of every aquifer and water pocket, and in some
## caves. They draw on their own random stream.
func _find_springs(seed_value: int, aquifers: Array, caves: Array) -> Array:
	var srng := RandomNumberGenerator.new()
	srng.seed = seed_value * 7919 + 13
	var out: Array = []
	for r: Rect2i in aquifers:
		var c := _floor_cell(r, D.WATER)
		if c.x >= 0:
			out.append(c)
	for r: Rect2i in caves:
		if srng.randf() < D.CAVE_SPRING_CHANCE:
			var c := _floor_cell(r, D.AIR)
			if c.x >= 0:
				out.append(c)
	return out


## The lowest cell of `mat` in the middle column of a feature.
func _floor_cell(r: Rect2i, mat: int) -> Vector2i:
	var cx := r.position.x + (r.size.x >> 1)
	for y in range(r.end.y - 1, r.position.y - 1, -1):
		if g[y * W + cx] == mat:
			return Vector2i(cx, y)
	return Vector2i(-1, -1)


## Wandering glimmer seams, mostly horizontal, until about `target` cells are painted.
func _veins(target: int, y0: int, y1: int) -> int:
	var painted := 0
	var guard := 0
	var half := F * 1.25   # half the seam's thickness
	while painted < target and guard < 60:
		guard += 1
		var px := rng.randf_range(12.0 * SX, W - 12.0 * SX)
		var py := rng.randf_range(y0, y1)
		var ang := rng.randf_range(-0.5, 0.5) + (PI if rng.randf() < 0.5 else 0.0)
		var steps := rng.randi_range(70, 130) * F
		# Somewhere along each vein it swells into a lode: the rich spot worth a tunnel.
		var lode_at := rng.randi_range(15 * F, steps - 15 * F)
		for s in steps:
			ang += rng.randf_range(-0.09, 0.09)
			px += cos(ang)
			py += sin(ang) * 0.8
			if px < 4.0 * F or px > W - 5.0 * F or py < y0 or py > y1:
				break
			var cx := int(px)
			var cy := int(py)
			if s == lode_at:
				painted += _lode(cx, cy, y0, y1)
			# Only the leading edge is new each step, so paint a ragged disc every
			# other step.
			if s % 2 != 0:
				continue
			var hr := int(ceil(half))
			for oy in range(-hr, hr + 1):
				for ox in range(-hr, hr + 1):
					var d := sqrt(ox * ox + oy * oy)
					if d > half or (d > half - 1.5 and rng.randf() < 0.5):
						continue
					var i := (cy + oy) * W + cx + ox
					if g[i] == D.STONE:
						g[i] = D.GLIMMER
						painted += 1
	return painted


## A ragged ellipse of Glimmer, only replacing Stone.
func _lode(cx: int, cy: int, y0: int, y1: int) -> int:
	var rx := rng.randf_range(7.0, 10.0) * F
	var ry := rng.randf_range(4.0, 6.0) * F
	var n := 0
	for oy in range(-6 * F, 6 * F + 1):
		for ox in range(-10 * F, 10 * F + 1):
			var x := cx + ox
			var y := cy + oy
			if x < 4 or x > W - 5 or y < y0 or y > y1:
				continue
			var d := (ox * ox) / (rx * rx) + (oy * oy) / (ry * ry)
			if d > 1.0 or (d > 0.85 and rng.randf() < 0.4):
				continue
			var i := y * W + x
			if g[i] == D.STONE:
				g[i] = D.GLIMMER
				n += 1
	return n


## A sealed cave with a lava lake in its lower part, offset from the plug so the
## straight route down skirts it.
func _lava_lake(plug_x: int) -> Rect2i:
	# Beside the plug, never over it: its near edge sits 6-20 (times F) cells from the plug.
	var rx := 50 * F
	var ry := 18 * F
	var gap := rng.randi_range(6, 20) * F
	var side := -1 if rng.randf() < 0.5 else 1
	var pc := plug_x + (PLUG_W >> 1)
	var margin := 6 * F
	var cx := pc + side * (rx + (PLUG_W >> 1) + gap)
	if cx < rx + margin or cx > W - rx - margin - 1:
		side = -side
		cx = pc + side * (rx + (PLUG_W >> 1) + gap)
	if cx < rx + margin or cx > W - rx - margin - 1:
		rx = 36 * F
		cx = pc + side * (rx + (PLUG_W >> 1) + gap)
	cx = clampi(cx, rx + margin, W - rx - margin - 1)
	var cy := rng.randi_range(842, 858) * SY
	var r := Rect2i(cx - rx, cy - ry, rx * 2 + 1, ry * 2 + 1)
	features.append(r)
	# Fill from the bottom until about LAKE_LAVA cells, air above.
	var lava_line := r.end.y
	var lava := 0
	while lava < 2000 * F * F and lava_line > r.position.y:
		lava_line -= 1
		for x in range(r.position.x, r.end.x):
			var nx := (x - cx) / float(rx)
			var ny := (lava_line - cy) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				lava += 1
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var nx := (x - cx) / float(rx)
			var ny := (y - cy) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				g[y * W + x] = D.LAVA if y >= lava_line else D.AIR
	return r


func _chamber(plug_x: int, shell_top: PackedInt32Array, altar_rect: Rect2i) -> void:
	# Carve the dome (upper half of an ellipse standing on the floor).
	for y in range(CHAMBER_FLOOR - CHAMBER_RY, CHAMBER_FLOOR):
		for x in range(CHAMBER_CX - CHAMBER_RX, CHAMBER_CX + CHAMBER_RX + 1):
			var nx := (x - CHAMBER_CX) / float(CHAMBER_RX)
			var ny := (y - CHAMBER_FLOOR) / float(CHAMBER_RY)
			if nx * nx + ny * ny <= 1.0:
				g[y * W + x] = D.AIR
	# The altar under the Crucible.
	_fill(altar_rect, D.BEDROCK)
	# The plug: a stone column through the bedrock ceiling.
	for x in range(plug_x, plug_x + PLUG_W):
		for y in range(shell_top[x] - 2 * F, CHAMBER_FLOOR):
			if g[y * W + x] == D.AIR:
				break
			g[y * W + x] = D.STONE


## Phase 9: the Magma band's stone is hot rock, from a wobbling line near its top
## down (the plug included). Last, so every other feature lands as before.
func _heat(wobble: FastNoiseLite) -> void:
	var top := PackedInt32Array()
	top.resize(W)
	var lo := H
	for x in W:
		top[x] = D.HOT_TOP + int(round(wobble.get_noise_1d(x + 2100.0 * F) * 6.0 * F))
		lo = mini(lo, top[x])
	for y in range(lo, H):
		var row := y * W
		for x in range(2, W - 2):
			if y >= top[x] and g[row + x] == D.STONE:
				g[row + x] = D.HOT_ROCK


## Coal seams and sulfur deposits. They draw on their own random stream and
## only replace dirt and stone.
func _deposits(seed_value: int, lava_pockets: Array, lake: Rect2i) -> Dictionary:
	var drng := RandomNumberGenerator.new()
	drng.seed = seed_value * 104729 + 7
	var coal: Array = []
	var sulfur: Array = []
	for _i in 2:
		coal.append(_seam(drng, D.COAL, Vector2i(90, 280) * SY))
	for _i in 3:
		coal.append(_seam(drng, D.COAL, Vector2i(320, 580) * SY))
	# One lava pocket wears a cap of coal, with a skin of stone between them.
	if not lava_pockets.is_empty():
		var lp: Rect2i = lava_pockets[drng.randi_range(0, lava_pockets.size() - 1)]
		coal.append(_cap(drng, D.COAL, lp, 2 * F, 3 * F))
	for lp: Rect2i in lava_pockets:
		if drng.randf() < 0.7:
			sulfur.append(_crust(drng, lp))
	sulfur.append(_crust(drng, lake))
	for _i in 2:
		sulfur.append(_nodule(drng, D.SULFUR, Vector2i(470, 590) * SY))
	return {"coal": coal, "sulfur": sulfur}


## Phase 8 ground, from noise of its own: packed dirt thickening toward the bottom
## of the Topsoil, sand pockets in its upper part (never near water or open space,
## so none pours at the start), gravel patches, a gravel bed along the
## Topsoil/Stone boundary, and clay lining the lower half of the Topsoil aquifers.
func _ground(seed_value: int, aquifers: Array, topsoil_end: PackedInt32Array) -> void:
	var pack := FastNoiseLite.new()
	pack.seed = seed_value + 301
	pack.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pack.frequency = 0.04 / F
	var sand := FastNoiseLite.new()
	sand.seed = seed_value + 302
	sand.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	sand.frequency = 0.05 / F
	var grav := FastNoiseLite.new()
	grav.seed = seed_value + 303
	grav.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grav.frequency = 0.05 / F
	var pack_top := 170 * SY
	var sand_bottom := 200 * SY
	var bed := 4 * F
	for y in range(D.GROUND_Y + 12 * F, 330 * SY):
		var row := y * W
		for x in range(3, W - 3):
			var i := row + x
			var m := g[i]
			if m != D.DIRT and m != D.STONE:
				continue
			var te := topsoil_end[x]
			if m == D.DIRT:
				var depth := float(y - pack_top) / float(maxi(te - pack_top, 1))
				if depth > 0.0 and pack.get_noise_2d(x, y * 1.6) * 0.5 + 0.5 < depth * 1.3 - 0.15:
					g[i] = D.PACKED_DIRT
					continue
				if y < sand_bottom and sand.get_noise_2d(x * 1.2, y * 2.0) > 0.38:
					g[i] = D.SAND
					continue
				if grav.get_noise_2d(x * 1.5, y * 1.5) > 0.45:
					g[i] = D.GRAVEL
					continue
			if absi(y - te) <= bed and grav.get_noise_2d(x * 0.7, 900.0 * F + y) > -0.2:
				g[i] = D.GRAVEL
	# Sand stays buried: none within 3 * F cells of water or open space, and none
	# over anything it could fall into (bottom up, so what's turned back holds the rest).
	for y in range(sand_bottom - 1, D.GROUND_Y + 11 * F, -1):
		for x in range(3, W - 3):
			var i := y * W + x
			if g[i] != D.SAND:
				continue
			var b := g[i + W]
			if b == D.AIR or b == D.WATER or b == D.LAVA or _near(x, y, D.WATER, 3 * F) or _near(x, y, D.AIR, 3 * F):
				g[i] = D.DIRT
	for r: Rect2i in aquifers:
		if r.position.y >= 300 * SY:
			continue
		var mid := r.position.y + (r.size.y >> 1)
		var box := r.grow(3 * F)
		for y in range(mid, box.end.y):
			for x in range(maxi(box.position.x, 3), mini(box.end.x, W - 3)):
				var i := y * W + x
				var m := g[i]
				if (m == D.DIRT or m == D.PACKED_DIRT or m == D.GRAVEL or m == D.SAND) and _near(x, y, D.WATER, 2 * F):
					g[i] = D.CLAY


## A wandering, mostly level band of `mat` 2-4 (times F) cells thick. Returns its bounds.
func _seam(r: RandomNumberGenerator, mat: int, y_range: Vector2i) -> Rect2i:
	var px := r.randf_range(16.0 * SX, W - 16.0 * SX)
	var py := r.randf_range(y_range.x, y_range.y)
	var ang := r.randf_range(-0.25, 0.25) + (PI if r.randf() < 0.5 else 0.0)
	var steps := r.randi_range(40, 90) * F
	var thick := r.randi_range(2, 3) * F
	var swell_at := r.randi_range(10 * F, steps - 10 * F)
	var box := Rect2i(int(px), int(py), 1, 1)
	for s in steps:
		ang += r.randf_range(-0.04, 0.04)
		px += cos(ang)
		py += sin(ang) * 0.5
		if px < 4.0 * F or px > W - 5.0 * F or py < y_range.x or py > y_range.y:
			break
		var t := thick + (2 * F if absi(s - swell_at) < 6 * F else 0)
		var cx := int(px)
		var cy := int(py) - (t >> 1)
		for k in t:
			if _put(cx, cy + k, mat, [D.DIRT, D.STONE]):
				box = box.expand(Vector2i(cx, cy + k))
	return box


## A layer of `mat` following the top of a lava pocket, `gap` cells of stone above it.
func _cap(r: RandomNumberGenerator, mat: int, pocket: Rect2i, gap: int, thick: int) -> Rect2i:
	var box := Rect2i(pocket.get_center(), Vector2i.ONE)
	var trim := int(pocket.size.x * r.randf_range(0.1, 0.25))
	for x in range(pocket.position.x + trim, pocket.end.x - trim):
		var top := -1
		for y in range(pocket.position.y, pocket.end.y):
			if g[y * W + x] == D.LAVA:
				top = y
				break
		if top < 0:
			continue
		for k in thick:
			var y := top - gap - thick + k
			if not _near(x, y, D.LAVA, gap) and _put(x, y, mat, [D.STONE]):
				box = box.expand(Vector2i(x, y))
	return box


## A lump of Sulfur beside a lava body: grown from a point a few cells out from
## its edge, never closer to the lava than 2 * F cells of stone.
func _crust(r: RandomNumberGenerator, body: Rect2i) -> Rect2i:
	var c := body.get_center()
	var box := Rect2i(c, Vector2i.ONE)
	# Walk out from the middle in a random direction until past the lava's edge.
	var ang := r.randf_range(0.0, TAU)
	var dir := Vector2(cos(ang), sin(ang) * 0.6)
	var p := Vector2(c)
	var guard := 0
	while guard < 80 * F:
		guard += 1
		p += dir
		var ix := int(p.x)
		var iy := int(p.y)
		if ix < 4 or ix > W - 5 or iy < 4 or iy > H - 5:
			return box
		if g[iy * W + ix] == D.STONE and not _near(ix, iy, D.LAVA, 2 * F):
			break
	p += dir * r.randf_range(1.0, 3.0) * F
	var rx := r.randf_range(3.0, 5.5) * F
	var ry := r.randf_range(2.5, 4.0) * F
	for oy in range(-5 * F, 5 * F + 1):
		for ox in range(-6 * F, 6 * F + 1):
			var d := (ox * ox) / (rx * rx) + (oy * oy) / (ry * ry)
			if d > 1.0 or (d > 0.8 and r.randf() < 0.45):
				continue
			var x := int(p.x) + ox
			var y := int(p.y) + oy
			if x < 4 or x > W - 5 or _near(x, y, D.LAVA, 2 * F):
				continue
			if _put(x, y, D.SULFUR, [D.STONE]):
				box = box.expand(Vector2i(x, y))
	return box


## A ragged lump of `mat` somewhere in deep stone.
func _nodule(r: RandomNumberGenerator, mat: int, y_range: Vector2i) -> Rect2i:
	var cx := r.randi_range(12 * SX, W - 12 * SX - 1)
	var cy := r.randi_range(y_range.x, y_range.y)
	var rx := r.randf_range(4.0, 7.0) * F
	var ry := r.randf_range(3.0, 5.0) * F
	var box := Rect2i(cx, cy, 1, 1)
	for oy in range(-6 * F, 6 * F + 1):
		for ox in range(-8 * F, 8 * F + 1):
			var d := (ox * ox) / (rx * rx) + (oy * oy) / (ry * ry)
			if d > 1.0 or (d > 0.85 and r.randf() < 0.4):
				continue
			if _put(cx + ox, cy + oy, mat, [D.STONE]):
				box = box.expand(Vector2i(cx + ox, cy + oy))
	return box


## Paint one cell if it's inside the walls and currently one of `over`.
func _put(x: int, y: int, mat: int, over: Array) -> bool:
	if x < 3 or x > W - 4 or y < D.GROUND_Y + 20 * F or y > H - 4:
		return false
	var i := y * W + x
	if g[i] in over:
		g[i] = mat
		return true
	return false


## Is there `mat` within about `r` cells (a square) of (x, y)? Answered from a
## mask of KS x KS blocks, built the first time `mat` is asked about, so it can
## say yes for `mat` up to KS - 1 cells further off. Masks are dropped when the map
## is done; paint `mat` only before its mask is built.
func _near(x: int, y: int, mat: int, r: int) -> bool:
	const BW := W >> KSHIFT
	const BH := H >> KSHIFT
	if not _masks.has(mat):
		# Hop from each hit to the next block along its row, so this costs a find
		# per block that has any, not a look at every cell.
		var m := PackedByteArray()
		m.resize(BW * BH)
		var i := g.find(mat)
		while i >= 0:
			var cy := floori(i / float(W))
			var bx := (i - cy * W) >> KSHIFT
			m[(cy >> KSHIFT) * BW + bx] = 1
			i = g.find(mat, cy * W + ((bx + 1) << KSHIFT))
		_masks[mat] = m
	var mask: PackedByteArray = _masks[mat]
	for by in range(maxi((y - r) >> KSHIFT, 0), mini((y + r) >> KSHIFT, BH - 1) + 1):
		var row := by * BW
		for bx in range(maxi((x - r) >> KSHIFT, 0), mini((x + r) >> KSHIFT, BW - 1) + 1):
			if mask[row + bx]:
				return true
	return false
