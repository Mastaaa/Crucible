extends RefCounted
## Seeded map generator. The same seed always builds the same map.
##
##   Surface   0-40     sky and a flat pad holding the Hub
##   Topsoil   40-300   dirt with stone lumps, two sealed aquifers (~1,200 water cells each)
##   Stone     300-600  stone, glimmer veins (~1,500 cells), air caves, water pockets (~600)
##   Magma     600-900  stone, 3-5 lava pockets (300-800 cells) and a ~2,000-cell lava lake
##   Chamber   900-1024 bedrock shell around the Crucible; the only way in is a
##                      10-cell stone plug in the ceiling
## Layer boundaries wobble by up to 12 cells. Bedrock lines the sides and floor.
## Springs sit on the floor of every aquifer and pocket and in some caves.
## Coal lies in seams through the Topsoil and Stone, and caps one lava pocket
## behind a skin of stone; Sulfur crusts sit beside lava and in deep stone.

const D = preload("res://scripts/defs.gd")
const W := 256
const H := 1024

const HUB_RECT := Rect2i(124, 34, 8, 6)
# The chamber is a dome resting on the floor; the Crucible stands on a bedrock
# altar in the middle, so a Conduit hung from the ceiling under the plug is
# within reach of it.
const CHAMBER_CX := 128
const CHAMBER_FLOOR := 1010
const CHAMBER_RX := 104
const CHAMBER_RY := 62
const CRUCIBLE_SIZE := Vector2i(14, 8)

var rng := RandomNumberGenerator.new()
var g := PackedByteArray()
var features: Array = []     # Rect2i of placed pockets, for spacing


func generate(sim: RefCounted, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	g = PackedByteArray()
	g.resize(W * H)
	features.clear()

	var wobble := FastNoiseLite.new()
	wobble.seed = seed_value
	wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wobble.frequency = 0.035

	var lumps := FastNoiseLite.new()
	lumps.seed = seed_value + 17
	lumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	lumps.frequency = 0.05
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
		var gy := D.GROUND_Y + int(round(wobble.get_noise_1d(x * 1.0) * 4.0))
		var pad := absi(x - 128)
		if pad <= 20:
			gy = D.GROUND_Y
		elif pad <= 26:
			gy = int(round(lerpf(D.GROUND_Y, gy, (pad - 20) / 6.0)))
		ground[x] = gy
		topsoil_end[x] = 300 + int(round(wobble.get_noise_1d(x + 700.0) * 12.0))
		shell_top[x] = 900 + int(round(wobble.get_noise_1d(x + 1400.0) * 5.0))

	# --- Bands ---
	for y in H:
		var row := y * W
		for x in W:
			var m := D.AIR
			if y >= ground[x]:
				if y < topsoil_end[x]:
					m = D.DIRT
				elif y < shell_top[x]:
					m = D.STONE
				else:
					m = D.BEDROCK
			g[row + x] = m

	# Stone lumps in the Topsoil (kept off the surface so the pad stays dirt).
	for y in range(D.GROUND_Y + 8, 312):
		var row := y * W
		for x in range(2, W - 2):
			if g[row + x] == D.DIRT and lumps.get_noise_2d(x, y * 1.3) > 0.4:
				g[row + x] = D.STONE

	# Ragged Topsoil/Stone boundary: a few dirt tongues reach down into the stone.
	for x in range(2, W - 2):
		var tongue := int(maxf(0.0, lumps.get_noise_2d(x * 2.0, 5000.0) * 14.0))
		for y in range(topsoil_end[x], topsoil_end[x] + tongue):
			if g[y * W + x] == D.STONE:
				g[y * W + x] = D.DIRT

	# --- Topsoil: two sealed aquifers ---
	var aquifers: Array = []
	aquifers.append(_place_blob(D.WATER, [D.DIRT, D.STONE], Vector2i(72, 184), Vector2i(105, 165), Vector2i(28, 14), 1200))
	aquifers.append(_place_blob(D.WATER, [D.DIRT, D.STONE], Vector2i(30, 226), Vector2i(185, 255), Vector2i(28, 14), 1200))

	# --- Stone: glimmer veins, caves, water pockets ---
	var glimmer := _veins(2400, 318, 585)
	var caves := randi_range_n(1, 2)
	var cave_rects: Array = []
	for _i in caves:
		cave_rects.append(_place_blob(D.AIR, [D.STONE, D.GLIMMER], Vector2i(24, 232), Vector2i(330, 575), Vector2i(22, 8), 0))
	var pockets := randi_range_n(1, 2)
	for _i in pockets:
		aquifers.append(_place_blob(D.WATER, [D.STONE, D.GLIMMER], Vector2i(24, 232), Vector2i(330, 575), Vector2i(20, 10), 600))

	# --- Chamber, plug and lake (the plug decides where the lake and the Crucible go) ---
	var plug_x := rng.randi_range(40, 206)
	var lake := _lava_lake(plug_x)
	# The Crucible stands on an altar right under the plug, its top 7 cells
	# below the dome ceiling so a Conduit hung there can reach it.
	var pc := plug_x + 5
	var nx := (pc - CHAMBER_CX) / float(CHAMBER_RX)
	var ceiling := int(ceil(CHAMBER_FLOOR - CHAMBER_RY * sqrt(maxf(0.0, 1.0 - nx * nx))))
	var crucible_rect := Rect2i(pc - (CRUCIBLE_SIZE.x >> 1), ceiling + 7, CRUCIBLE_SIZE.x, CRUCIBLE_SIZE.y)
	var altar_rect := Rect2i(crucible_rect.position.x - 6, crucible_rect.end.y,
			crucible_rect.size.x + 12, CHAMBER_FLOOR - crucible_rect.end.y)

	# --- Magma: lava pockets ---
	var pocket_count := rng.randi_range(3, 5)
	var lava_pockets: Array = []
	for _i in pocket_count:
		var rx := rng.randi_range(12, 19)
		var ry := rng.randi_range(7, 11)
		lava_pockets.append(_place_blob(D.LAVA, [D.STONE], Vector2i(22, 234), Vector2i(625, 800),
				Vector2i(rx, ry), rx * ry * 3))

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
	for y in range(HUB_RECT.position.y, HUB_RECT.end.y):
		for x in range(HUB_RECT.position.x, HUB_RECT.end.x):
			g[y * W + x] = D.BUILDING
	for y in range(crucible_rect.position.y, crucible_rect.end.y):
		for x in range(crucible_rect.position.x, crucible_rect.end.x):
			g[y * W + x] = D.BUILDING

	var springs := _find_springs(seed_value, aquifers, cave_rects)
	var deposits := _deposits(seed_value, lava_pockets, lake)
	_ground(seed_value, aquifers, topsoil_end)

	sim.set_cells(g)
	g = PackedByteArray()
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
	}


func randi_range_n(a: int, b: int) -> int:
	return rng.randi_range(a, b)


## Drop a noisy ellipse of `mat` somewhere in the given ranges, away from other
## features, replacing only materials in `replace`. Returns its bounding rect.
func _place_blob(mat: int, replace: Array, x_range: Vector2i, y_range: Vector2i,
		radius: Vector2i, _target: int) -> Rect2i:
	var best := Rect2i()
	for attempt in 40:
		var px := rng.randi_range(x_range.x, x_range.y)
		var py := rng.randi_range(y_range.x, y_range.y)
		var r := Rect2i(px - radius.x, py - radius.y, radius.x * 2 + 1, radius.y * 2 + 1)
		var ok := true
		for f in features:
			if r.grow(10).intersects(f):
				ok = false
				break
		if ok or attempt == 39:
			best = r
			break
	features.append(best)
	var cx := best.position.x + radius.x
	var cy := best.position.y + radius.y
	var phase := rng.randf() * TAU
	for y in range(best.position.y, best.end.y):
		for x in range(best.position.x, best.end.x):
			if x < 3 or x > W - 4:
				continue
			var nx := (x - cx) / float(radius.x)
			var ny := (y - cy) / float(radius.y)
			var edge := 1.0 + 0.12 * sin(atan2(ny, nx) * 3.0 + phase)
			if nx * nx + ny * ny <= edge:
				var i := y * W + x
				if g[i] in replace:
					g[i] = mat
	return best


## Springs: one on the floor of every aquifer and water pocket, and in some
## caves. They draw on their own random stream, so every seed's map is the
## same as it was before springs existed.
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
	while painted < target and guard < 60:
		guard += 1
		var px := rng.randf_range(12.0, W - 12.0)
		var py := rng.randf_range(y0, y1)
		var ang := rng.randf_range(-0.5, 0.5) + (PI if rng.randf() < 0.5 else 0.0)
		var steps := rng.randi_range(70, 130)
		# Somewhere along each vein it swells into a lode: the rich spot worth a tunnel.
		var lode_at := rng.randi_range(15, steps - 15)
		for s in steps:
			ang += rng.randf_range(-0.18, 0.18)
			px += cos(ang)
			py += sin(ang) * 0.8
			if px < 4.0 or px > W - 5.0 or py < y0 or py > y1:
				break
			var cx := int(px)
			var cy := int(py)
			if s == lode_at:
				painted += _lode(cx, cy, y0, y1)
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if absi(ox) + absi(oy) > 1 and rng.randf() < 0.5:
						continue
					var i := (cy + oy) * W + cx + ox
					if g[i] == D.STONE:
						g[i] = D.GLIMMER
						painted += 1
	return painted


## A ragged ellipse of Glimmer, 80-180 cells, only replacing Stone.
func _lode(cx: int, cy: int, y0: int, y1: int) -> int:
	var rx := rng.randf_range(7.0, 10.0)
	var ry := rng.randf_range(4.0, 6.0)
	var n := 0
	for oy in range(-6, 7):
		for ox in range(-10, 11):
			var x := cx + ox
			var y := cy + oy
			if x < 4 or x > W - 5 or y < y0 or y > y1:
				continue
			var d := (ox * ox) / (rx * rx) + (oy * oy) / (ry * ry)
			if d > 1.0 or (d > 0.7 and rng.randf() < 0.4):
				continue
			var i := y * W + x
			if g[i] == D.STONE:
				g[i] = D.GLIMMER
				n += 1
	return n


## A sealed cave with a lava lake in its lower part, offset from the plug so the
## straight route down skirts it.
func _lava_lake(plug_x: int) -> Rect2i:
	# Beside the plug, never over it: its near edge sits 6-20 cells from the plug.
	var rx := 50
	var ry := 18
	var gap := rng.randi_range(6, 20)
	var side := -1 if rng.randf() < 0.5 else 1
	var cx := plug_x + 5 + side * (rx + 5 + gap)
	if cx < rx + 6 or cx > W - rx - 7:
		side = -side
		cx = plug_x + 5 + side * (rx + 5 + gap)
	if cx < rx + 6 or cx > W - rx - 7:
		rx = 36
		cx = plug_x + 5 + side * (rx + 5 + gap)
	cx = clampi(cx, rx + 6, W - rx - 7)
	var cy := rng.randi_range(842, 858)
	var r := Rect2i(cx - rx, cy - ry, rx * 2 + 1, ry * 2 + 1)
	features.append(r)
	# Fill from the bottom until ~2,000 lava cells, air above.
	var inside: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var nx := (x - cx) / float(rx)
			var ny := (y - cy) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				inside.append(y * W + x)
	var lava_line := r.end.y
	var lava := 0
	while lava < 2000 and lava_line > r.position.y:
		lava_line -= 1
		for x in range(r.position.x, r.end.x):
			var nx := (x - cx) / float(rx)
			var ny := (lava_line - cy) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				lava += 1
	for i in inside:
		g[i] = D.LAVA if (i >> 8) >= lava_line else D.AIR
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
	for y in range(altar_rect.position.y, altar_rect.end.y):
		for x in range(altar_rect.position.x, altar_rect.end.x):
			g[y * W + x] = D.BEDROCK
	# The plug: a 10-wide stone column through the bedrock ceiling.
	for x in range(plug_x, plug_x + 10):
		for y in range(shell_top[x] - 2, CHAMBER_FLOOR):
			if g[y * W + x] == D.AIR:
				break
			g[y * W + x] = D.STONE


## Coal seams and sulfur deposits. They draw on their own random stream and
## only replace dirt and stone, so every seed keeps the rest of its map.
func _deposits(seed_value: int, lava_pockets: Array, lake: Rect2i) -> Dictionary:
	var drng := RandomNumberGenerator.new()
	drng.seed = seed_value * 104729 + 7
	var coal: Array = []
	var sulfur: Array = []
	for _i in 2:
		coal.append(_seam(drng, D.COAL, Vector2i(90, 280)))
	for _i in 3:
		coal.append(_seam(drng, D.COAL, Vector2i(320, 580)))
	# One lava pocket wears a cap of coal, with a skin of stone between them.
	if not lava_pockets.is_empty():
		var lp: Rect2i = lava_pockets[drng.randi_range(0, lava_pockets.size() - 1)]
		coal.append(_cap(drng, D.COAL, lp, 2, 3))
	for lp: Rect2i in lava_pockets:
		if drng.randf() < 0.7:
			sulfur.append(_crust(drng, lp))
	sulfur.append(_crust(drng, lake))
	for _i in 2:
		sulfur.append(_nodule(drng, D.SULFUR, Vector2i(470, 590)))
	return {"coal": coal, "sulfur": sulfur}


## Phase 8 ground, from noise of its own (so everything else lands where it did):
## packed dirt thickening toward the bottom of the Topsoil, sand pockets in its
## upper part (never near water or open space, so none pours at the start),
## gravel patches, a gravel bed along the Topsoil/Stone boundary, and clay lining
## the lower half of the Topsoil aquifers.
func _ground(seed_value: int, aquifers: Array, topsoil_end: PackedInt32Array) -> void:
	var pack := FastNoiseLite.new()
	pack.seed = seed_value + 301
	pack.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pack.frequency = 0.04
	var sand := FastNoiseLite.new()
	sand.seed = seed_value + 302
	sand.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	sand.frequency = 0.05
	var grav := FastNoiseLite.new()
	grav.seed = seed_value + 303
	grav.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grav.frequency = 0.05
	for y in range(D.GROUND_Y + 12, 330):
		var row := y * W
		for x in range(3, W - 3):
			var i := row + x
			var m := g[i]
			if m != D.DIRT and m != D.STONE:
				continue
			var te := topsoil_end[x]
			if m == D.DIRT:
				var depth := float(y - 170) / float(maxi(te - 170, 1))
				if depth > 0.0 and pack.get_noise_2d(x, y * 1.6) * 0.5 + 0.5 < depth * 1.3 - 0.15:
					g[i] = D.PACKED_DIRT
					continue
				if y < 200 and sand.get_noise_2d(x * 1.2, y * 2.0) > 0.38:
					g[i] = D.SAND
					continue
				if grav.get_noise_2d(x * 1.5, y * 1.5) > 0.45:
					g[i] = D.GRAVEL
					continue
			if absi(y - te) <= 4 and grav.get_noise_2d(x * 0.7, 900.0 + y) > -0.2:
				g[i] = D.GRAVEL
	# Sand stays buried: none within 3 cells of water or open space, and none over
	# anything it could fall into (bottom up, so what's turned back holds the rest).
	for y in range(329, D.GROUND_Y + 11, -1):
		for x in range(3, W - 3):
			var i := y * W + x
			if g[i] != D.SAND:
				continue
			var b := g[i + W]
			if b == D.AIR or b == D.WATER or b == D.LAVA or _near(x, y, D.WATER, 3) or _near(x, y, D.AIR, 3):
				g[i] = D.DIRT
	for r: Rect2i in aquifers:
		if r.position.y >= 300:
			continue
		var mid := r.position.y + (r.size.y >> 1)
		var box := r.grow(3)
		for y in range(mid, box.end.y):
			for x in range(maxi(box.position.x, 3), mini(box.end.x, W - 3)):
				var i := y * W + x
				var m := g[i]
				if (m == D.DIRT or m == D.PACKED_DIRT or m == D.GRAVEL or m == D.SAND) and _near(x, y, D.WATER, 2):
					g[i] = D.CLAY


## A wandering, mostly level band of `mat` 2-4 cells thick. Returns its bounds.
func _seam(r: RandomNumberGenerator, mat: int, y_range: Vector2i) -> Rect2i:
	var px := r.randf_range(16.0, W - 16.0)
	var py := r.randf_range(y_range.x, y_range.y)
	var ang := r.randf_range(-0.25, 0.25) + (PI if r.randf() < 0.5 else 0.0)
	var steps := r.randi_range(40, 90)
	var thick := r.randi_range(2, 3)
	var swell_at := r.randi_range(10, steps - 10)
	var box := Rect2i(int(px), int(py), 1, 1)
	for s in steps:
		ang += r.randf_range(-0.08, 0.08)
		px += cos(ang)
		py += sin(ang) * 0.5
		if px < 4.0 or px > W - 5.0 or py < y_range.x or py > y_range.y:
			break
		var t := thick + (2 if absi(s - swell_at) < 6 else 0)
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
## its edge, never closer to the lava than two cells of stone.
func _crust(r: RandomNumberGenerator, body: Rect2i) -> Rect2i:
	var c := body.get_center()
	var box := Rect2i(c, Vector2i.ONE)
	# Walk out from the middle in a random direction until past the lava's edge.
	var ang := r.randf_range(0.0, TAU)
	var dir := Vector2(cos(ang), sin(ang) * 0.6)
	var p := Vector2(c)
	var guard := 0
	while guard < 80:
		guard += 1
		p += dir
		var ix := int(p.x)
		var iy := int(p.y)
		if ix < 4 or ix > W - 5 or iy < 4 or iy > H - 5:
			return box
		if g[iy * W + ix] == D.STONE and not _near(ix, iy, D.LAVA, 2):
			break
	p += dir * r.randf_range(1.0, 3.0)
	var rx := r.randf_range(3.0, 5.5)
	var ry := r.randf_range(2.5, 4.0)
	for oy in range(-5, 6):
		for ox in range(-6, 7):
			var d := (ox * ox) / (rx * rx) + (oy * oy) / (ry * ry)
			if d > 1.0 or (d > 0.6 and r.randf() < 0.45):
				continue
			var x := int(p.x) + ox
			var y := int(p.y) + oy
			if x < 4 or x > W - 5 or _near(x, y, D.LAVA, 2):
				continue
			if _put(x, y, D.SULFUR, [D.STONE]):
				box = box.expand(Vector2i(x, y))
	return box


## A ragged lump of `mat` somewhere in deep stone.
func _nodule(r: RandomNumberGenerator, mat: int, y_range: Vector2i) -> Rect2i:
	var cx := r.randi_range(12, W - 13)
	var cy := r.randi_range(y_range.x, y_range.y)
	var rx := r.randf_range(4.0, 7.0)
	var ry := r.randf_range(3.0, 5.0)
	var box := Rect2i(cx, cy, 1, 1)
	for oy in range(-6, 7):
		for ox in range(-8, 9):
			var d := (ox * ox) / (rx * rx) + (oy * oy) / (ry * ry)
			if d > 1.0 or (d > 0.65 and r.randf() < 0.4):
				continue
			if _put(cx + ox, cy + oy, mat, [D.STONE]):
				box = box.expand(Vector2i(cx + ox, cy + oy))
	return box


## Paint one cell if it's inside the walls and currently one of `over`.
func _put(x: int, y: int, mat: int, over: Array) -> bool:
	if x < 3 or x > W - 4 or y < D.GROUND_Y + 20 or y > H - 4:
		return false
	var i := y * W + x
	if g[i] in over:
		g[i] = mat
		return true
	return false


## Is there `mat` within `r` cells (a square) of (x, y)?
func _near(x: int, y: int, mat: int, r: int) -> bool:
	for yy in range(maxi(y - r, 0), mini(y + r, H - 1) + 1):
		for xx in range(maxi(x - r, 0), mini(x + r, W - 1) + 1):
			if g[yy * W + xx] == mat:
				return true
	return false
