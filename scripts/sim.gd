extends RefCounted
## The old GDScript falling-sand simulation, kept as a fallback: the game uses the
## C++ one (native/, loaded from bin/crucible_sim.gdextension) whenever it's there.
## This one is several times slower and ignores data/materials.json. Same API.
##
## Falling-sand simulation on a D.W x D.H byte grid.
##
## The grid is split into 32 x 32 chunks. Every chunk keeps a dirty rectangle:
## only cells inside a chunk's rectangle (grown by one cell) are visited next
## tick, so settled ground sleeps and costs nothing. Anything that changes a
## cell calls touch(), which wakes the area around it.
##
## Rules, at 60 ticks per second:
##   powders fall, then slip diagonally; they sink through liquids and gas
##   liquids fall, slip diagonally, then spread sideways (water 4 cells, lava 2)
##   lava only moves every other tick; water touching lava makes steam + obsidian
##   steam rises, drifts, ages through eight stages and condenses back to water
##   settled dirt holds its shape unless it has nothing under it and nothing
##   either side; erosion() makes exposed dirt trickle loose over time

const D = preload("res://scripts/defs.gd")

const W := D.W
const H := D.H
const BW := W >> 2   # blocks (4 x 4 cells) across, for heat and the fog maps
const CW := W >> 5       # chunks (32 x 32) across
const CH := H >> 5       # chunks down
const NCH := CW * CH
const EMPTY := 1 << 20

const AIR := 0
const STONE := 2
const DIRT := 6
const LOOSE_DIRT := 7
const RUBBLE := 8
const WATER := 9
const LAVA := 10
const OBSIDIAN := 4
const STEAM := 11
const STEAM_LAST := 18
const K_EMPTY := 0
const K_STATIC := 1
const K_POWDER := 2
const K_LIQUID := 3
const K_GAS := 4

var cells := PackedByteArray()
var stamp := PackedByteArray()      # tick marker: a cell moves at most once per tick
var tick := 0
var mark := 1
var rng := 22695477

# Dirty rectangles: a* is being processed this tick, b* collects the next one.
var ax0 := PackedInt32Array()
var ay0 := PackedInt32Array()
var ax1 := PackedInt32Array()
var ay1 := PackedInt32Array()
var bx0 := PackedInt32Array()
var by0 := PackedInt32Array()
var bx1 := PackedInt32Array()
var by1 := PackedInt32Array()

# Coarse lava map (one byte per 4 x 4 block) for the "rock glows near lava" warning.
var heat := PackedByteArray()
var heat_changed := true
var lava_dirty := PackedByteArray()

var changed := true
var _k := PackedByteArray()        # material kinds (materials.gd), for telling cells apart
var stat_chunks := 0
var stat_updates := 0
var reactions := 0
var eroded := 0


func _init() -> void:
	cells.resize(W * H)
	stamp.resize(W * H)
	for arr_name in ["ax0", "ay0", "ax1", "ay1", "bx0", "by0", "bx1", "by1"]:
		var arr := PackedInt32Array()
		arr.resize(NCH)
		set(arr_name, arr)
	ax0.fill(EMPTY)
	ay0.fill(EMPTY)
	ax1.fill(-1)
	ay1.fill(-1)
	_clear_next()
	heat.resize(BW * (H >> 2))
	lava_dirty.resize(NCH)
	D.M.ensure()
	_k = D.M.kinds.duplicate()


## Air or a gas.
func _thin(t: int) -> bool:
	var k := _k[t]
	return k == K_EMPTY or k == K_GAS


## Air, a liquid or a gas: what a powder can fall into.
func _yields(t: int) -> bool:
	var k := _k[t]
	return k == K_EMPTY or k >= K_LIQUID


func _clear_next() -> void:
	bx0.fill(EMPTY)
	by0.fill(EMPTY)
	bx1.fill(-1)
	by1.fill(-1)


# --- Waking -------------------------------------------------------------------

## Wake (x, y) and its neighbours for the next tick.
func touch(x: int, y: int) -> void:
	var c := (y >> 5) * CW + (x >> 5)
	if x < bx0[c]:
		bx0[c] = x
	if x > bx1[c]:
		bx1[c] = x
	if y < by0[c]:
		by0[c] = y
	if y > by1[c]:
		by1[c] = y
	var lx := x & 31
	var ly := y & 31
	if lx == 0 or lx == 31 or ly == 0 or ly == 31:
		_touch_edges(x, y, c)
	changed = true


## On a chunk border the neighbours live in other chunks: wake those too.
func _touch_edges(x: int, y: int, c: int) -> void:
	for dy in range(-1, 2):
		var yy := y + dy
		if yy < 0 or yy >= H:
			continue
		for dx in range(-1, 2):
			var xx := x + dx
			if xx < 0 or xx >= W:
				continue
			var c2 := (yy >> 5) * CW + (xx >> 5)
			if c2 == c:
				continue
			if xx < bx0[c2]:
				bx0[c2] = xx
			if xx > bx1[c2]:
				bx1[c2] = xx
			if yy < by0[c2]:
				by0[c2] = yy
			if yy > by1[c2]:
				by1[c2] = yy


## Wake every cell in a rectangle (used after big edits such as world generation).
func touch_rect(x0: int, y0: int, x1: int, y1: int) -> void:
	for cy in range(maxi(y0, 0) >> 5, (mini(y1, H - 1) >> 5) + 1):
		for cx in range(maxi(x0, 0) >> 5, (mini(x1, W - 1) >> 5) + 1):
			var c := cy * CW + cx
			bx0[c] = mini(bx0[c], maxi(x0, cx << 5))
			bx1[c] = maxi(bx1[c], mini(x1, (cx << 5) + 31))
			by0[c] = mini(by0[c], maxi(y0, cy << 5))
			by1[c] = maxi(by1[c], mini(y1, (cy << 5) + 31))
	changed = true


# --- Public cell access -------------------------------------------------------

func get_cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return D.BEDROCK
	return cells[y * W + x]


## Write a cell from game code (drills, hoppers, buildings). Wakes the area and
## lets any dirt that was leaning on this cell come loose.
func set_cell(x: int, y: int, m: int) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	var i := y * W + x
	var old := cells[i]
	if old == m:
		return
	cells[i] = m
	touch(x, y)
	if old == LAVA or m == LAVA:
		lava_dirty[(y >> 5) * CW + (x >> 5)] = 1
	if _yields(m):
		if y > 2 and cells[i - W] == DIRT:
			_dirt_check(i - W, x, y - 1)
		if x > 2 and cells[i - 1] == DIRT:
			_dirt_check(i - 1, x - 1, y)
		if x < W - 3 and cells[i + 1] == DIRT:
			_dirt_check(i + 1, x + 1, y)


# --- The tick -----------------------------------------------------------------

func step() -> void:
	tick += 1
	mark += 1
	if mark > 250:
		mark = 1
	var t: PackedInt32Array = ax0
	ax0 = bx0
	bx0 = t
	t = ay0
	ay0 = by0
	by0 = t
	t = ax1
	ax1 = bx1
	bx1 = t
	t = ay1
	ay1 = by1
	by1 = t
	t = PackedInt32Array()
	_clear_next()

	var chunks := 0
	var updates := 0
	var flip := tick & 1
	var mk := mark
	for cyi in range(CH - 1, -1, -1):
		for k in CW:
			var cxi := k if flip == 0 else CW - 1 - k
			var c := cyi * CW + cxi
			if ax1[c] < 0:
				continue
			chunks += 1
			var gx := cxi << 5
			var gy := cyi << 5
			var x0 := maxi(maxi(ax0[c] - 1, gx), 2)
			var x1 := mini(mini(ax1[c] + 1, gx + 31), W - 3)
			var y0 := maxi(maxi(ay0[c] - 1, gy), 2)
			var y1 := mini(mini(ay1[c] + 1, gy + 31), H - 3)
			for y in range(y1, y0 - 1, -1):
				var row := y * W
				if ((y + tick) & 1) == 0:
					for x in range(x0, x1 + 1):
						var i := row + x
						var m := cells[i]
						if _k[m] <= K_STATIC or stamp[i] == mk:
							continue
						_update(i, x, y, m)
						updates += 1
				else:
					for x in range(x1, x0 - 1, -1):
						var i := row + x
						var m := cells[i]
						if _k[m] <= K_STATIC or stamp[i] == mk:
							continue
						_update(i, x, y, m)
						updates += 1
	stat_chunks = chunks
	stat_updates = updates


func _update(i: int, x: int, y: int, m: int) -> void:
	rng = (rng * 1103515245 + 12345) & 0x7fffffff
	var d := 1 if (rng & 0x10000) != 0 else -1
	if _k[m] == K_POWDER:
		# Powder: fall, then slip diagonally. Sinks through liquid and gas.
		var b := i + W
		if _yields(cells[b]):
			_swap(i, b, x, y, x, y + 1)
			return
		if _yields(cells[b + d]) and _open(i + d):
			_swap(i, b + d, x, y, x + d, y + 1)
			return
		if _yields(cells[b - d]) and _open(i - d):
			_swap(i, b - d, x, y, x - d, y + 1)
		return
	if m == WATER:
		_water(i, x, y, d)
	elif m == LAVA:
		_lava(i, x, y, d)
	elif m >= STEAM and m <= STEAM_LAST:
		_steam(i, x, y, m, d)
	elif _k[m] == K_GAS:
		# Flames, smoke and fumes need the C++ sim; here they just vanish.
		cells[i] = AIR
		touch(x, y)


func _water(i: int, x: int, y: int, d: int) -> void:
	var b := i + W
	var t := cells[b]
	if _thin(t):
		_swap(i, b, x, y, x, y + 1)
		return
	t = cells[b + d]
	if _thin(t) and _open(i + d):
		_swap(i, b + d, x, y, x + d, y + 1)
		return
	t = cells[b - d]
	if _thin(t) and _open(i - d):
		_swap(i, b - d, x, y, x - d, y + 1)
		return
	_spread(i, x, y, d, WATER, 8, 4, 3)


## Sideways movement for a liquid that can't fall: head for a drop within `look`
## cells (moving at most `max_step`); with more of the same liquid on top, spread as
## far as `max_step`; a surface cell with room beside it wanders now and then
## (1 in 2^wander_bits ticks), which levels shallow slopes. A cell with no free
## neighbour does nothing and lets its chunk sleep.
func _spread(i: int, x: int, y: int, d: int, liquid: int, look: int, max_step: int, wander_bits: int) -> void:
	var dd := d
	var free_side := false
	for _p in 2:
		var j := i
		for s in range(1, look + 1):
			j += dd
			var t := cells[j]
			if not _thin(t):
				break
			if s == 1:
				free_side = true
			t = cells[j + W]
			if _thin(t):
				var k := s if s <= max_step else max_step
				_move_liquid(i, i + dd * k, x, y, x + dd * k, y, liquid)
				return
		dd = -dd
	if not free_side:
		return
	if cells[i - W] == liquid:
		dd = d
		for _p in 2:
			var best := -1
			var best_s := 0
			var j := i
			for s in range(1, max_step + 1):
				j += dd
				var t := cells[j]
				if not _thin(t):
					break
				best = j
				best_s = s
			if best >= 0:
				_move_liquid(i, best, x, y, x + dd * best_s, y, liquid)
				return
			dd = -dd
		return
	if ((rng >> 20) & ((1 << wander_bits) - 1)) == 0:
		var t := cells[i + d]
		if _thin(t):
			_move_liquid(i, i + d, x, y, x + d, y, liquid)
			return
		t = cells[i - d]
		if _thin(t):
			_move_liquid(i, i - d, x, y, x - d, y, liquid)
			return
	touch(x, y)


func _move_liquid(i: int, j: int, x: int, y: int, x2: int, y2: int, liquid: int) -> void:
	if liquid == LAVA:
		if (tick & 1) == 1:
			touch(x, y)
			return
		lava_dirty[(y >> 5) * CW + (x >> 5)] = 1
		lava_dirty[(y2 >> 5) * CW + (x2 >> 5)] = 1
	_swap(i, j, x, y, x2, y2)


func _lava(i: int, x: int, y: int, d: int) -> void:
	# Water contact: the lava crusts into obsidian and the water flashes to steam.
	var j := -1
	var jx := x
	var jy := y
	if cells[i - W] == WATER:
		j = i - W
		jy = y - 1
	elif cells[i + W] == WATER:
		j = i + W
		jy = y + 1
	elif cells[i - 1] == WATER:
		j = i - 1
		jx = x - 1
	elif cells[i + 1] == WATER:
		j = i + 1
		jx = x + 1
	if j >= 0:
		cells[i] = OBSIDIAN
		cells[j] = STEAM
		stamp[i] = mark
		stamp[j] = mark
		touch(x, y)
		touch(jx, jy)
		lava_dirty[(y >> 5) * CW + (x >> 5)] = 1
		reactions += 1
		return
	# Sluggish: moves only on even ticks (_move_liquid defers odd ones).
	var b := i + W
	var t := cells[b]
	if _thin(t):
		_move_liquid(i, b, x, y, x, y + 1, LAVA)
		return
	t = cells[b + d]
	if _thin(t) and _open(i + d):
		_move_liquid(i, b + d, x, y, x + d, y + 1, LAVA)
		return
	t = cells[b - d]
	if _thin(t) and _open(i - d):
		_move_liquid(i, b - d, x, y, x - d, y + 1, LAVA)
		return
	_spread(i, x, y, d, LAVA, 4, 2, 4)


func _steam(i: int, x: int, y: int, m: int, d: int) -> void:
	# Age roughly one stage a second; after the last stage it condenses.
	if ((rng >> 17) & 63) == 0:
		m += 1
		if m > STEAM_LAST:
			cells[i] = WATER
			stamp[i] = mark
			touch(x, y)
			return
		cells[i] = m
		changed = true
	if y <= 3:
		cells[i] = AIR
		touch(x, y)
		return
	var u := i - W
	var t := cells[u]
	if t == AIR or t == WATER:
		_swap(i, u, x, y, x, y - 1)
		return
	t = cells[u + d]
	if t == AIR and _open(i + d):
		_swap(i, u + d, x, y, x + d, y - 1)
		return
	t = cells[u - d]
	if t == AIR and _open(i - d):
		_swap(i, u - d, x, y, x - d, y - 1)
		return
	if cells[i + d] == AIR and ((rng >> 23) & 3) == 0:
		_swap(i, i + d, x, y, x + d, y)
		return
	touch(x, y)


## Diagonal moves need the cell beside to be open: nothing squeezes between two
## solid cells that only meet at a corner (a sealed drill channel stays sealed).
func _open(j: int) -> bool:
	var t := cells[j]
	return _yields(t)


func _swap(i: int, j: int, x: int, y: int, x2: int, y2: int) -> void:
	var a := cells[i]
	var b := cells[j]
	cells[i] = b
	cells[j] = a
	stamp[i] = mark
	stamp[j] = mark
	touch(x, y)
	touch(x2, y2)
	if b == AIR and cells[i - W] == DIRT:
		_dirt_check(i - W, x, y - 1)


## Settled dirt with nothing under it and nothing either side comes loose.
func _dirt_check(i: int, x: int, y: int) -> void:
	if cells[i] != DIRT:
		return
	var t := cells[i + W]
	if not _yields(t):
		return
	t = cells[i - 1]
	if not _yields(t):
		return
	t = cells[i + 1]
	if not _yields(t):
		return
	cells[i] = LOOSE_DIRT
	touch(x, y)


# --- Slow hazards ---------------------------------------------------------------

## Random samples across a depth band: exposed dirt (open air below it, or open
## air diagonally below and beside it) trickles loose.
func erode(samples: int, y_min: int, y_max: int) -> void:
	var span := y_max - y_min
	for _s in samples:
		rng = (rng * 1103515245 + 12345) & 0x7fffffff
		var x := 2 + ((rng >> 7) % (W - 4))
		rng = (rng * 1103515245 + 12345) & 0x7fffffff
		var y := y_min + ((rng >> 7) % span)
		var i := y * W + x
		if cells[i] != DIRT:
			continue
		if cells[i + W] == AIR \
				or (cells[i - 1] == AIR and cells[i + W - 1] == AIR) \
				or (cells[i + 1] == AIR and cells[i + W + 1] == AIR):
			cells[i] = LOOSE_DIRT
			touch(x, y)
			eroded += 1


## Crumble up to `count` Stone cells that sit beside open air into Rubble.
func tremor(cells_wanted: int, y_min: int, y_max: int) -> int:
	var done := 0
	var tries := 0
	var span := y_max - y_min
	while done < cells_wanted and tries < 60000:
		tries += 1
		rng = (rng * 1103515245 + 12345) & 0x7fffffff
		var x := 3 + ((rng >> 7) % (W - 6))
		rng = (rng * 1103515245 + 12345) & 0x7fffffff
		var y := y_min + ((rng >> 7) % span)
		var i := y * W + x
		if cells[i] != STONE:
			continue
		if cells[i - W] == AIR or cells[i + W] == AIR or cells[i - 1] == AIR or cells[i + 1] == AIR:
			cells[i] = RUBBLE
			touch(x, y)
			done += 1
	return done


# --- Lava warning map -----------------------------------------------------------

## Rebuild the coarse lava map for chunks where lava moved (or everything).
func refresh_heat(all: bool) -> void:
	for c in NCH:
		if not all and lava_dirty[c] == 0:
			continue
		lava_dirty[c] = 0
		var gx := (c % CW) << 5
		var gy := floori(c / float(CW)) << 5
		for by in 8:
			for bx in 8:
				var v := 0
				var x0 := gx + bx * 4
				var y0 := gy + by * 4
				for yy in range(y0, y0 + 4):
					var row := yy * W
					for xx in range(x0, x0 + 4):
						if cells[row + xx] == LAVA:
							v = 255
							break
					if v != 0:
						break
				heat[((gy >> 2) + by) * BW + (gx >> 2) + bx] = v
		heat_changed = true


## Count cells of one material (debug and tests).
func count(m: int) -> int:
	return cells.count(m)


# --- The same API as the C++ sim ---------------------------------------------------

func configure(_materials: Array, _reactions: Array) -> void:
	pass


func set_seed(_s: int) -> void:
	pass


func set_threads(_n: int) -> void:
	pass


func get_cells() -> PackedByteArray:
	return cells


func set_cells(data: PackedByteArray) -> void:
	cells = data


func get_heat() -> PackedByteArray:
	return heat


func checksum() -> int:
	return hash(cells)


## What touches a building's outline (and, with `inside`, fills it):
## (lava, steam, liquid, open) cell counts. Steam counts as open; lava as liquid.
func ring_counts(x: int, y: int, w: int, h: int, inside: bool) -> Vector4i:
	var idx := PackedInt32Array()
	for xx in range(x, x + w):
		idx.append((y - 1) * W + xx)
		idx.append((y + h) * W + xx)
	for yy in range(y, y + h):
		idx.append(yy * W + x - 1)
		idx.append(yy * W + x + w)
	if inside:
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				idx.append(yy * W + xx)
	var lava := 0
	var steam := 0
	var liquid := 0
	var open := 0
	for i in idx:
		var m := cells[i]
		if m == AIR:
			open += 1
		elif m == WATER:
			liquid += 1
		elif m == LAVA:
			lava += 1
			liquid += 1
		elif m >= STEAM and m <= STEAM_LAST:
			steam += 1
			open += 1
		elif _thin(m):
			open += 1
	return Vector4i(lava, steam, liquid, open)


# --- Phase 5 API: the C++ sim does fire, particles, blasts and weathering; this
# one only answers so the game runs without it. ---------------------------------

var ignitions := 0
var crumbled := 0
var _aux := PackedByteArray()


func get_aux(_x: int, _y: int) -> int:
	return 0


func get_aux_bytes() -> PackedByteArray:
	if _aux.size() != W * H:
		_aux.resize(W * H)
	return _aux


func ignite(_x: int, _y: int) -> void:
	pass


## Settling needs the C++ sim; here freshly dug ground weathers straight away.
func settle_around(_x: int, _y: int, _radius: int, _ticks: int) -> void:
	pass


func get_settle(_x: int, _y: int) -> int:
	return 0


func count_burning() -> int:
	return 0


func particle_count() -> int:
	return 0


func add_particle(_x: float, _y: float, _vx: float, _vy: float, _m: int) -> void:
	pass


func weather(_samples: int) -> int:
	return 0


## Collapse, holds and tremor shields need the C++ sim: here ceilings only
## erode, and Struts prop what rests on them but hold nothing round their ends.
func collapse(_rows: int) -> int:
	return 0


func stabilize() -> int:
	return 0


func wash(_samples: int) -> int:
	return 0


func hold_circle(_x: int, _y: int, _r: int, _delta: int) -> void:
	pass


func get_held(_x: int, _y: int) -> int:
	return 0


func set_shields(_circles: PackedInt32Array) -> void:
	pass


func get_last_cave() -> Vector2i:
	return Vector2i(-1, -1)


## A blast without debris or fire: clears what it can break within the radius.
func explode(x: int, y: int, radius: float, power: int) -> int:
	var r := int(ceil(radius))
	var broken := 0
	for yy in range(maxi(y - r, 2), mini(y + r, H - 3) + 1):
		for xx in range(maxi(x - r, 2), mini(x + r, W - 3) + 1):
			if (xx - x) * (xx - x) + (yy - y) * (yy - y) > radius * radius:
				continue
			var m := cells[yy * W + xx]
			if m == AIR or m == D.BEDROCK or m == D.BUILDING or _thin(m):
				continue
			if m == OBSIDIAN and power < 10:
				continue
			set_cell(xx, yy, AIR)
			broken += 1
	return broken


func building_hazards(x: int, y: int, w: int, h: int, inside: bool, _reach: int) -> PackedInt32Array:
	var rc := ring_counts(x, y, w, h, inside)
	# What could hold it up: solid cells and other buildings' cells on the outline, corners included.
	var ground := 0
	var strut := 0
	for yy in range(y - 1, y + h + 1):
		for xx in range(x - 1, x + w + 1):
			if (yy >= y and yy < y + h and xx >= x and xx < x + w) or xx < 0 or yy < 0 or xx >= W or yy >= H:
				continue
			var m := cells[yy * W + xx]
			if m == D.BUILDING:
				strut += 1
			elif D.is_solid(m):
				ground += 1
	return PackedInt32Array([rc.x, 0, rc.y, rc.z, rc.w, 0, ground, strut])


func hazards_batch(rects: PackedInt32Array, reach: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in int(rects.size() / 5.0):
		out.append_array(building_hazards(rects[k * 5], rects[k * 5 + 1], rects[k * 5 + 2], rects[k * 5 + 3], rects[k * 5 + 4] != 0, reach))
	return out


func segment_hazards(_x0: int, _y0: int, _x1: int, _y1: int) -> PackedInt32Array:
	return PackedInt32Array([0, 0, 0])


func segments_batch(segs: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(int(segs.size() / 4.0) * 3)
	return out


## Light, roughly: no shadows, no glow, whole blocks lit within each light's
## radius and the sky above the ground. Returns the same three maps as the C++
## sim (live, explored, seen), a byte per 4 x 4 block each.
func light_update(lights: PackedInt32Array, sights: PackedInt32Array, sun: int, known: PackedByteArray) -> PackedByteArray:
	var n := BW * (H >> 2)
	var bits := PackedByteArray()
	bits.resize(n)
	if sun > 0:
		for b in BW * (D.GROUND_Y >> 2):
			bits[b] = 1
	_stamp(bits, lights, 1)
	_stamp(bits, sights, 2)
	var out := PackedByteArray()
	out.resize(3 * n)
	for b in n:
		var seen := bits[b] == 3
		var k := seen or (known.size() >= n and known[b] != 0)
		if k and (bits[b] & 1) != 0:
			out[b] = 255
		if k:
			out[n + b] = 255
		if seen:
			out[2 * n + b] = 255
	return out


func _stamp(out: PackedByteArray, circles: PackedInt32Array, bit: int) -> void:
	for k in range(0, circles.size() - 2, 3):
		var px := float(circles[k])
		var py := float(circles[k + 1])
		var r := float(circles[k + 2])
		var r2 := (r + 2.0) * (r + 2.0)
		for ky in range(maxi(int((py - r) / 4.0), 0), mini(int((py + r) / 4.0), (H >> 2) - 1) + 1):
			for kx in range(maxi(int((px - r) / 4.0), 0), mini(int((px + r) / 4.0), BW - 1) + 1):
				var dx := kx * 4 + 2.0 - px
				var dy := ky * 4 + 2.0 - py
				if dx * dx + dy * dy <= r2:
					out[ky * BW + kx] |= bit


## No per-cell light here: the renderer lights whole blocks instead.
func set_light_view(_x0: int, _y0: int, _x1: int, _y1: int) -> void:
	pass


func get_light() -> PackedByteArray:
	return PackedByteArray()


# Render tiles, the simple way: every tile counts as changed while anything has,
# and the remembered map is the live one.
const TS := 256
var _mem_all := true


func get_tiles_across() -> int:
	return (W + TS - 1) >> 8


func get_tiles_down() -> int:
	return (H + TS - 1) >> 8


func take_dirty_tiles() -> PackedInt32Array:
	var out := PackedInt32Array()
	if changed:
		for t in get_tiles_across() * get_tiles_down():
			out.append(t)
		_mem_all = true
	return out


func take_mem_tiles() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _mem_all:
		for t in get_tiles_across() * get_tiles_down():
			out.append(t)
		_mem_all = false
	return out


func reset_memory() -> void:
	_mem_all = true


func get_tile(which: int, tile: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(TS * TS)
	var src: PackedByteArray = get_aux_bytes() if which == 1 else cells
	var tw := get_tiles_across()
	var x0 := (tile % tw) * TS
	var y0 := floori(tile / float(tw)) * TS
	var w := mini(TS, W - x0)
	for yy in mini(TS, H - y0):
		var i := (y0 + yy) * W + x0
		var row: PackedByteArray = src.slice(i, i + w)
		for k in w:
			out[yy * TS + k] = row[k]
	return out


## Where each material shows up in the blocks a mask marks (-1: nowhere).
func count_in_rect(x: int, y: int, w: int, h: int, mask: PackedByteArray) -> int:
	var n := 0
	for yy in range(maxi(y, 0), mini(y + h, H)):
		for xx in range(maxi(x, 0), mini(x + w, W)):
			n += 1 if mask[cells[yy * W + xx]] else 0
	return n


func block_counts(bx: int, by: int, bw: int, bh: int, mask: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(bw * bh)
	for j in bh:
		for i in bw:
			out[j * bw + i] = count_in_rect((bx + i) * 4, (by + j) * 4, 4, 4, mask)
	return out


func rect_counts(x: int, y: int, w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(256)
	for yy in range(maxi(y, 0), mini(y + h, H)):
		for xx in range(maxi(x, 0), mini(x + w, W)):
			out[cells[yy * W + xx]] += 1
	return out


func dig_rect(x: int, y: int, w: int, h: int, mask: PackedByteArray, settle_r: int, settle_ticks: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(256)
	for yy in range(maxi(y, 0), mini(y + h, H)):
		for xx in range(maxi(x, 0), mini(x + w, W)):
			var m: int = cells[yy * W + xx]
			if mask[m]:
				out[m] += 1
				set_cell(xx, yy, AIR)
				settle_around(xx, yy, settle_r, settle_ticks)
	return out


func block_circles(circles: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(BW * (H >> 2))
	for k in range(0, circles.size() - 2, 3):
		var px := float(circles[k])
		var py := float(circles[k + 1])
		var r := float(circles[k + 2])
		for ky in range(maxi(int((py - r) / 4.0), 0), mini(int((py + r) / 4.0), (H >> 2) - 1) + 1):
			for kx in range(maxi(int((px - r) / 4.0), 0), mini(int((px + r) / 4.0), BW - 1) + 1):
				var dx := kx * 4 + 2.0 - px
				var dy := ky * 4 + 2.0 - py
				if dx * dx + dy * dy <= (r + 2.0) * (r + 2.0):
					out[ky * BW + kx] = 255
	return out


## Spots within `radius` where a w x h footprint is all `open_mask` and touches a
## `solid_mask` cell on a side, nearest first, as (dx, dy, rests) triples.
func place_spots(x: int, y: int, w: int, h: int, radius: int, open_mask: PackedByteArray, solid_mask: PackedByteArray) -> PackedInt32Array:
	var offs: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				offs.append(Vector2i(dx, dy))
	offs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())
	var out := PackedInt32Array()
	for o: Vector2i in offs:
		var rx := x + o.x
		var ry := y + o.y
		if rx < 2 or ry < 2 or rx + w > W - 2 or ry + h > H - 2:
			continue
		if count_in_rect(rx, ry, w, h, open_mask) != w * h:
			continue
		var below := count_in_rect(rx, ry + h, w, 1, solid_mask)
		if below + count_in_rect(rx, ry - 1, w, 1, solid_mask) + count_in_rect(rx - 1, ry, 1, h, solid_mask) + count_in_rect(rx + w, ry, 1, h, solid_mask) == 0:
			continue
		out.append_array([o.x, o.y, 1 if below > 0 else 0])
	return out


func materials_in(mask: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(256)
	out.fill(-1)
	for b in mask.size():
		if mask[b] == 0:
			continue
		var bx := (b % BW) * 4
		var by := floori(b / float(BW)) * 4
		for yy in range(by, by + 4):
			for xx in range(bx, bx + 4):
				var i := yy * W + xx
				if out[cells[i]] < 0:
					out[cells[i]] = i
	return out


# Rigid bodies (phase 8c) live only in the C++ sim: this one has no collapse to
# break pieces off, so there are never any.
func set_body_params(_p: Dictionary) -> void:
	pass


func make_body(_x: int, _y: int, _w: int, _h: int, _vx: float, _vy: float, _spin: float) -> int:
	return -1


func body_count() -> int:
	return 0


func get_bodies() -> PackedInt32Array:
	return PackedInt32Array()


func take_impacts() -> PackedInt32Array:
	return PackedInt32Array()


func get_owner(_x: int, _y: int) -> int:
	return 0


func body_state(_id: int) -> PackedFloat32Array:
	return PackedFloat32Array()
