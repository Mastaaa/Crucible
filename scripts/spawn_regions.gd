extends RefCounted
## Spawn regions (A2): data/spawn_regions.json says where each material may appear,
## and `place` paints those spots into the map before the sim takes it. Draws from its
## own random stream, so the rest of a seed's layout stays put.

const D = preload("res://scripts/defs.gd")
const Mats = preload("res://scripts/materials.gd")
const PATH := "res://data/spawn_regions.json"
const EDGE := 4          # clumps keep this far from the map's sides and floor
const TOP := D.GROUND_Y + 20 * 4   # world spawns stay under the surface layer


static func load_table(path: String = PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("spawn regions: can't read %s" % path)
		return {"areas": {}, "spawns": []}
	var t = JSON.parse_string(f.get_as_text())
	if not (t is Dictionary):
		push_warning("spawn regions: %s isn't a JSON object" % path)
		return {"areas": {}, "spawns": []}
	return t


## Paints `table` into `g` (w x h material ids). `ctx` carries "hub" (Rect2i) and
## "ground" (the surface row of each column). `resolve` turns a name into an id
## (-1 if unknown). Returns {"areas": name -> Rect2i, "placed": name -> cells,
## "skipped": names the material table doesn't know}.
static func place(g: PackedByteArray, w: int, h: int, table: Dictionary, seed_value: int,
		ctx: Dictionary, resolve: Callable = Callable()) -> Dictionary:
	if not resolve.is_valid():
		resolve = Mats.id_of
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var out := {"areas": {}, "placed": {}, "skipped": []}
	var areas: Dictionary = table.get("areas", {})
	for nm: String in areas:
		if nm.begins_with("_"):
			continue
		var r := _area(g, w, h, areas[nm], rng, ctx, resolve)
		if r.size.x > 0:
			out["areas"][nm] = r
	for row: Dictionary in table.get("spawns", []):
		if not row.get("enabled", true):
			continue
		var mat: int = resolve.call(str(row.get("material", "")))
		if mat < 0:
			out["skipped"].append(str(row.get("material", "")))
			continue
		var hosts: Array = []
		for hn in row.get("host", []):
			var hid: int = resolve.call(str(hn))
			if hid >= 0:
				hosts.append(hid)
		if hosts.is_empty():
			continue
		var area_name: String = row.get("area", "world")
		var box: Rect2i
		if area_name == "world":
			box = _band(row, w, h)
		elif out["areas"].has(area_name):
			box = out["areas"][area_name]
		else:
			continue
		var n := _count(rng, row.get("clumps", [1, 1]))
		var cells := 0
		for _i in n:
			var rad := _count(rng, row.get("radius", [3, 5]))
			var cx := 0
			var cy := 0
			for _try in 16:   # a clump starts on a host, or the row is skipped
				cx = rng.randi_range(box.position.x, box.end.x - 1)
				cy = rng.randi_range(box.position.y, box.end.y - 1)
				if g[cy * w + cx] in hosts:
					break
			cells += _clump(g, w, h, mat, hosts, cx, cy, rad, row.get("shape", "blob"), float(row.get("density", 0.5)), rng, float(row.get("aspect", 1.0)))
		var key: String = str(row["material"])
		out["placed"][key] = out["placed"].get(key, 0) + cells
	return out


static func _count(rng: RandomNumberGenerator, pair: Array) -> int:
	return rng.randi_range(int(pair[0]), int(pair[1]))


## The home range of a world spawn as a box: x as fractions of the width, depth in rows.
static func _band(row: Dictionary, w: int, h: int) -> Rect2i:
	var xs: Array = row.get("x", [0.0, 1.0])
	var ds: Array = row.get("depth", [TOP, h - 2 * EDGE])
	var x0 := clampi(int(float(xs[0]) * w), EDGE, w - EDGE - 1)
	var x1 := clampi(int(float(xs[1]) * w), x0 + 1, w - EDGE)
	var y0 := clampi(int(ds[0]), TOP, h - 2 * EDGE - 1)
	var y1 := clampi(int(ds[1]), y0 + 1, h - EDGE)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


static func _area(g: PackedByteArray, w: int, h: int, a: Dictionary, rng: RandomNumberGenerator,
		ctx: Dictionary, resolve: Callable) -> Rect2i:
	match a.get("shape", ""):
		"mound":
			var fill: int = resolve.call(str(a.get("fill", "")))
			if fill < 0:
				return Rect2i()
			var ground: PackedInt32Array = ctx["ground"]
			var hub: Rect2i = ctx["hub"]
			var dx := _count(rng, a.get("dx", [100, 160]))
			var side := 1 if rng.randf() < 0.5 else -1
			var width := _count(rng, a.get("width", [64, 80]))
			var height := _count(rng, a.get("height", [9, 12]))
			var cx := hub.position.x + (hub.size.x >> 1) + side * dx
			var half := width >> 1
			var top := h
			var bottom := 0
			for x in range(maxi(cx - half, EDGE), mini(cx + half, w - EDGE)):
				# A cosine hump: slope under 1 a cell, so powder stays put.
				var t := (x - cx) / float(half)
				var hh := int(round(height * 0.5 * (1.0 + cos(t * PI))))
				for k in hh:
					var y: int = ground[x] - 1 - k
					if y >= 0 and g[y * w + x] == D.AIR:
						g[y * w + x] = fill
						top = mini(top, y)
						bottom = maxi(bottom, y + 1)
			if bottom <= top:
				return Rect2i()
			return Rect2i(cx - half, top, width, bottom - top)
		"patch":
			var box := _band(a, w, h)
			var size: Array = a.get("size", [20, 10])
			var cx := rng.randi_range(box.position.x, box.end.x - 1)
			var cy := rng.randi_range(box.position.y, box.end.y - 1)
			return Rect2i(cx - int(size[0]), cy - int(size[1]), int(size[0]) * 2 + 1, int(size[1]) * 2 + 1).intersection(Rect2i(0, 0, w, h))
	return Rect2i()


## Paints one clump at (cx, cy) over the hosts only; returns the cells changed.
static func _clump(g: PackedByteArray, w: int, h: int, mat: int, hosts: Array, cx: int, cy: int,
		rad: int, shape: String, density: float, rng: RandomNumberGenerator, aspect := 1.0) -> int:
	var n := 0
	var phase := rng.randf() * TAU
	# `aspect` squashes a blob into a seam: rad cells either way across, rad / aspect up and down.
	var ry := maxi(int(rad / aspect), 1)
	for oy in range(-ry, ry + 1):
		for ox in range(-rad, rad + 1):
			var x := cx + ox
			var y := cy + oy
			if x < EDGE or x >= w - EDGE or y < 0 or y >= h - EDGE:
				continue
			var edge := 1.0 + 0.2 * sin(atan2(oy * aspect, ox) * 3.0 + phase)
			if (ox * ox + oy * oy * aspect * aspect) > rad * rad * edge:
				continue
			if shape == "speckle" and rng.randf() > density:
				continue
			var i := y * w + x
			if g[i] in hosts:
				g[i] = mat
				n += 1
	return n
