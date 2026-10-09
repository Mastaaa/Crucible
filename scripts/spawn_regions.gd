extends RefCounted
## Spawn regions (A2): data/spawn_regions.json says where each material may appear,
## and `place` paints those spots into the map before the sim takes it. Draws from its
## own random stream, so the rest of a seed's layout stays put.

const D = preload("res://scripts/defs.gd")
const Mats = preload("res://scripts/materials.gd")
const PATH := "res://data/spawn_regions.json"
const EDGE := 4          # clumps keep this far from the map's sides and floor
const TOP := D.GROUND_Y + 20 * 4   # world spawns stay under the surface layer
const REF_W := 768        # the width a row's clump counts were written for; a wider world gets proportionally more clumps (A6)
const CSHIFT := 5         # the engine's chunks are 32 x 32 cells (crucible_sim.h); a biome's climate is set per chunk (A6)
const CLIMATE_FADE := 40  # a biome's `ambient` offset reaches this far past its rim, fading to nothing
const RIM := 0.2          # how ragged a patch's rim is, as a share of its radius squared (a clump's rim uses the same)


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
## "ground" (the surface row of each column), and for patches that look for them
## "aquifers" and "lava_pockets" (Rect2i lists). `resolve` turns a name into an id
## (-1 if unknown). Returns {"areas": name -> Rect2i, "placed": name -> cells,
## "skipped": names the material table doesn't know, "shapes": patch name -> its
## ragged ellipse (see `inside`), "sides": patch name -> -1 left or 1 right,
## "recipe": patch name -> cells its ground recipe changed, "springs": the cells of a `spring`
## row's clumps that a spring sits on (the floor of the clump's middle column), "ambient": patch
## name -> degrees its area's `ambient` adds to the row's ambient (see `chunk_offsets`)}.
static func place(g: PackedByteArray, w: int, h: int, table: Dictionary, seed_value: int,
		ctx: Dictionary, resolve: Callable = Callable()) -> Dictionary:
	if not resolve.is_valid():
		resolve = Mats.id_of
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var out := {"areas": {}, "placed": {}, "skipped": [], "shapes": {}, "sides": {}, "recipe": {}, "springs": [], "ambient": {}}
	var areas: Dictionary = table.get("areas", {})
	for nm: String in areas:
		if nm.begins_with("_"):
			continue
		var r := _area(g, w, h, nm, areas[nm], rng, ctx, resolve, out)
		if r.size.x > 0:
			out["areas"][nm] = r
			if out["shapes"].has(nm) and int(areas[nm].get("ambient", 0)) != 0:
				out["ambient"][nm] = int(areas[nm]["ambient"])
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
		var shape: Dictionary = {}
		if area_name == "world":
			box = _band(row, w, h)
		elif out["areas"].has(area_name):
			box = out["areas"][area_name]
			if out["shapes"].has(area_name) and row.get("clip", true):
				shape = out["shapes"][area_name]
			if row.has("depth"):   # a row may keep to part of its patch's depth
				box = box.intersection(_band({"depth": row["depth"]}, w, h))
				if box.size.x <= 0 or box.size.y <= 0:
					continue
		else:
			continue
		var n := _count(rng, row.get("clumps", [1, 1]))
		if area_name == "world":
			n = maxi(1, roundi(n * float(w) / REF_W))
		var cells := 0
		for _i in n:
			var rad := _count(rng, row.get("radius", [3, 5]))
			var cx := 0
			var cy := 0
			for _try in 16:   # a clump starts on a host, or the row is skipped
				cx = rng.randi_range(box.position.x, box.end.x - 1)
				cy = rng.randi_range(box.position.y, box.end.y - 1)
				if g[cy * w + cx] in hosts and (shape.is_empty() or inside(shape, cx, cy)):
					break
			var added := _clump(g, w, h, mat, hosts, cx, cy, rad, row.get("shape", "blob"), float(row.get("density", 0.5)), rng, float(row.get("aspect", 1.0)), shape)
			cells += added
			if added > 0 and row.get("spring", false):
				var floor_y := _floor(g, w, h, mat, cx, cy, rad)
				if floor_y >= 0:
					out["springs"].append(Vector2i(cx, floor_y))
		var key: String = str(row["material"])
		out["placed"][key] = out["placed"].get(key, 0) + cells
	return out


## The lowest cell of `mat` in column `x`, looking `rad` rows either side of `cy`, or -1.
static func _floor(g: PackedByteArray, w: int, h: int, mat: int, x: int, cy: int, rad: int) -> int:
	for y in range(mini(cy + rad, h - 1), cy - rad - 1, -1):
		if y >= 0 and g[y * w + x] == mat:
			return y
	return -1


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


static func _area(g: PackedByteArray, w: int, h: int, nm: String, a: Dictionary, rng: RandomNumberGenerator,
		ctx: Dictionary, resolve: Callable, out: Dictionary) -> Rect2i:
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
			return _patch(g, w, h, nm, a, rng, ctx, resolve, out)
	return Rect2i()


## A patch (A6: a biome): a ragged ellipse of `size` = [rx, ry] cells whose centre is drawn inside a home range.
##   x, depth    the home range of the centre, as for a world row; x is written for the left flank.
##   side        "random" picks a flank per seed (a right flank mirrors x); omitted, x is used as written.
##   opposite    the name of an earlier patch: take the flank it did not.
##   anchor      "box" (the default) a centre anywhere in the range; "surface" the centre on the ground at a column
##               of the range's x; "lava_pocket" the centre of the lava pocket nearest the flank.
##   avoid       ctx keys ("aquifers", "lava_pockets") whose rectangles the patch's box tries not to touch.
##   ground      the recipe: rules {from: [names], to: name, density: share of the cells, not_near: [names], gap}, tried in
##               order on every cell of the patch; a rule with not_near leaves cells within `gap` (3) cells of those alone.
##   label, color   what the biome view calls it and paints it.
## Rows that name the patch as their area start inside it and are cut off at its rim.
static func _patch(g: PackedByteArray, w: int, h: int, nm: String, a: Dictionary, rng: RandomNumberGenerator,
		ctx: Dictionary, resolve: Callable, out: Dictionary) -> Rect2i:
	var size: Array = a.get("size", [20, 10])
	var rx := float(size[0])
	var ry := float(size[1])
	var side := 0
	if a.has("opposite") and out["sides"].has(str(a["opposite"])):
		side = -int(out["sides"][str(a["opposite"])])
	elif a.get("side", "") == "random" or a.has("opposite"):
		side = 1 if rng.randf() < 0.5 else -1
	var home := a.duplicate()
	if side > 0:
		var xs: Array = a.get("x", [0.0, 1.0])
		home["x"] = [1.0 - float(xs[1]), 1.0 - float(xs[0])]
	var box := _band(home, w, h)
	out["sides"][nm] = side
	var c := Vector2i()
	var bound := Rect2i()
	var tries := 24 if a.has("avoid") else 1
	for _try in tries:
		match a.get("anchor", "box"):
			"surface":
				c.x = rng.randi_range(box.position.x, box.end.x - 1)
				var ground: PackedInt32Array = ctx.get("ground", PackedInt32Array())
				c.y = ground[c.x] if c.x < ground.size() else box.position.y
			"lava_pocket":
				var best := -1.0
				c = box.get_center()
				for p: Rect2i in ctx.get("lava_pockets", []):
					var d := absf(p.get_center().x - box.get_center().x)
					if best < 0.0 or d < best:
						best = d
						c = p.get_center()
			_:
				c.x = rng.randi_range(box.position.x, box.end.x - 1)
				c.y = rng.randi_range(box.position.y, box.end.y - 1)
		bound = Rect2i(c.x - ceili(rx * 1.1), c.y - ceili(ry * 1.1), ceili(rx * 2.2) + 1, ceili(ry * 2.2) + 1).intersection(Rect2i(0, 0, w, h))
		var clear := true
		for key: String in a.get("avoid", []):
			for r: Rect2i in ctx.get(key, []):
				if r.intersects(bound):
					clear = false
		if clear:
			break
	var shape := {"cx": float(c.x), "cy": float(c.y), "rx": rx, "ry": ry, "phase": rng.randf() * TAU,
			"label": str(a.get("label", nm)), "color": _color(a.get("color", [0.8, 0.8, 0.8]))}
	out["shapes"][nm] = shape
	out["recipe"][nm] = _recipe(g, w, h, a.get("ground", []), shape, bound, rng, resolve)
	return bound


static func _color(v) -> Color:
	return Color(float(v[0]), float(v[1]), float(v[2])) if v is Array and v.size() >= 3 else Color(0.8, 0.8, 0.8)


## Applies a patch's ground recipe to every cell inside its shape; returns the cells changed.
static func _recipe(g: PackedByteArray, w: int, h: int, rules_in: Array, shape: Dictionary, bound: Rect2i,
		rng: RandomNumberGenerator, resolve: Callable) -> int:
	var rules: Array = []
	for r: Dictionary in rules_in:
		var from_ids: Array = []
		for n in r.get("from", []):
			var id: int = resolve.call(str(n))
			if id >= 0:
				from_ids.append(id)
		var shy: Array = []
		for n in r.get("not_near", []):
			var sid: int = resolve.call(str(n))
			if sid >= 0:
				shy.append(sid)
		var to: int = resolve.call(str(r.get("to", "")))
		if to >= 0 and not from_ids.is_empty():
			rules.append({"from": from_ids, "to": to, "density": float(r.get("density", 1.0)), "shy": shy, "gap": int(r.get("gap", 3))})
	if rules.is_empty():
		return 0
	var n := 0
	var cx: float = shape["cx"]
	var cy: float = shape["cy"]
	var rx: float = shape["rx"]
	var ry: float = shape["ry"]
	for y in range(bound.position.y, mini(bound.end.y, h - EDGE)):
		var ny := (y - cy) / ry
		var ny2 := ny * ny
		if ny2 > 1.0 + RIM:
			continue
		var span := rx * sqrt(maxf(1.0 + RIM - ny2, 0.0))
		var sure := rx * sqrt(1.0 - RIM - ny2) if ny2 <= 1.0 - RIM else -1.0   # inside whatever the rim does here (none, past the ellipse's ends)
		for x in range(maxi(int(cx - span), EDGE), mini(int(cx + span) + 1, w - EDGE)):
			if absf(x - cx) > sure and not inside(shape, x, y):
				continue
			var i := y * w + x
			var cur := g[i]
			for r: Dictionary in rules:
				if cur in r["from"] and (r["density"] >= 1.0 or rng.randf() < r["density"]) and not _near(g, w, h, x, y, r["gap"], r["shy"]):
					g[i] = r["to"]
					n += 1
					break
	return n


## Whether any of `mats` lies within `gap` cells of (x, y) (a square window).
static func _near(g: PackedByteArray, w: int, h: int, x: int, y: int, gap: int, mats: Array) -> bool:
	if mats.is_empty():
		return false
	for yy in range(maxi(y - gap, 0), mini(y + gap + 1, h)):
		for xx in range(maxi(x - gap, 0), mini(x + gap + 1, w)):
			if g[yy * w + xx] in mats:
				return true
	return false


## Whether cell (x, y) lies inside a patch's shape: an ellipse whose rim wobbles three times round.
static func inside(s: Dictionary, x: int, y: int) -> bool:
	var nx: float = (x - float(s["cx"])) / float(s["rx"])
	var ny: float = (y - float(s["cy"])) / float(s["ry"])
	var d2 := nx * nx + ny * ny
	if d2 <= 1.0 - RIM:
		return true
	if d2 > 1.0 + RIM:
		return false
	return d2 <= 1.0 + RIM * sin(atan2(ny, nx) * 3.0 + float(s["phase"]))


## The patch (biome) a cell is in, by name, or "" if none. `spawned` is the "spawned" entry of the
## world's info; the first patch listed wins where two overlap.
static func biome_at(spawned: Dictionary, x: int, y: int) -> String:
	var shapes: Dictionary = spawned.get("shapes", {})
	for nm: String in shapes:
		if inside(shapes[nm], x, y):
			return nm
	return ""


## The ambient offset of each engine chunk in degrees (chunks across, then down; `w` x `h` cells), for
## `sim.set_ambient_offsets`: each biome with an `ambient` adds it in full to the chunks whose middle is
## inside its rim, and less the further out, to nothing at CLIMATE_FADE cells. A world with no biomes
## (the bench, a table without patches) gives all zeros.
static func chunk_offsets(spawned: Dictionary, w: int, h: int) -> PackedInt32Array:
	var cw := w >> CSHIFT
	var ch := h >> CSHIFT
	var out := PackedInt32Array()
	out.resize(cw * ch)
	var shapes: Dictionary = spawned.get("shapes", {})
	var amb: Dictionary = spawned.get("ambient", {})
	var half := 1 << (CSHIFT - 1)
	for nm: String in amb:
		if not shapes.has(nm) or int(amb[nm]) == 0:
			continue
		var s: Dictionary = shapes[nm]
		var reach_x: float = float(s["rx"]) * 1.1 + CLIMATE_FADE   # the rim wobbles out to about 1.1 radii
		var reach_y: float = float(s["ry"]) * 1.1 + CLIMATE_FADE
		var c0 := maxi(int((float(s["cx"]) - reach_x) / (1 << CSHIFT)), 0)
		var c1 := mini(int((float(s["cx"]) + reach_x) / (1 << CSHIFT)), cw - 1)
		var r0 := maxi(int((float(s["cy"]) - reach_y) / (1 << CSHIFT)), 0)
		var r1 := mini(int((float(s["cy"]) + reach_y) / (1 << CSHIFT)), ch - 1)
		for cy in range(r0, r1 + 1):
			for cx in range(c0, c1 + 1):
				var k := _reach(s, (cx << CSHIFT) + half, (cy << CSHIFT) + half)
				if k > 0.0:
					out[cy * cw + cx] += roundi(float(amb[nm]) * k)
	return out


## 1.0 for a point inside the patch, falling to 0.0 at CLIMATE_FADE cells outside it (rings of eight
## points every eight cells).
static func _reach(s: Dictionary, x: int, y: int) -> float:
	if inside(s, x, y):
		return 1.0
	for r in range(8, CLIMATE_FADE, 8):
		for k in 8:
			var a := k * TAU / 8.0
			if inside(s, x + roundi(cos(a) * r), y + roundi(sin(a) * r)):
				return 1.0 - float(r) / CLIMATE_FADE
	return 0.0


## Paints one clump at (cx, cy) over the hosts only; returns the cells changed.
static func _clump(g: PackedByteArray, w: int, h: int, mat: int, hosts: Array, cx: int, cy: int,
		rad: int, shape: String, density: float, rng: RandomNumberGenerator, aspect := 1.0, clip := {}) -> int:
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
			if not clip.is_empty() and not inside(clip, x, y):
				continue
			if shape == "speckle" and rng.randf() > density:
				continue
			var i := y * w + x
			if g[i] in hosts:
				g[i] = mat
				n += 1
	return n
