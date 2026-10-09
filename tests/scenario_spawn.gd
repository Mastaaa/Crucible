extends SceneTree
## Spawn-region scenarios (A2).
##   A. the Spoil Heap stands beside the Hub on every seed, holds its stand-in materials
##      and nothing leaks out of it
##   B. the rest of each seed's layout is unchanged: with the table emptied, the map
##      differs only inside the Heap's box (seeds 5, 7, 11, 23); the wave 1 rows then add
##      cells of their own with little arching fallout
##   C. the table takes a made-up material name without code changes (skipped, no error)
##      and a new name once the resolver knows it
##   D. world rows keep to their home range (x fractions, depth band) and their hosts
##   E. the Heap holds still for a second of sim
##   F. biomes (A6): six per seed, opposite flanks in each band, clear of the Hub's middle third, ground recipes
##      applied, residents found only in their own biome (bar the outliers kept in the middle third)
##   G. the patch machinery on a plain grid: clipping, flanks, the surface anchor, the recipe, biome_at
## Run: godot --headless --path . --script tests/scenario_spawn.gd

const D = preload("res://scripts/defs.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")
const SR = preload("res://scripts/spawn_regions.gd")

var fails := 0


func _initialize() -> void:
	if not SimFactory.native_available():
		print("The C++ sim isn't loaded: these need it.")
		print("FAILURES: 1")
		quit()
		return
	scenario_a_b_e()
	scenario_c_d()
	scenario_f()
	scenario_g()
	print("FAILURES: %d" % fails)
	quit()


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func build(seed_value: int, table: Dictionary) -> Array:
	var sim = SimFactory.create()
	var wg := WorldGen.new()
	wg.spawn_table = table
	var info: Dictionary = wg.generate(sim, seed_value)
	return [sim, info]


func scenario_a_b_e() -> void:
	print("A. Spoil Heap, B. layout kept, E. holds still")
	var empty := {"areas": {}, "spawns": []}
	var full := SR.load_table()
	# The Heap's own rows (the first four), kept apart from the wave 1 rows after them.
	var heap_rows := {"areas": {"spoil_heap": full["areas"]["spoil_heap"]}, "spawns": full["spawns"].filter(func(r): return r.get("area", "") == "spoil_heap" and r["material"] in ["Sulfur", "Coal", "Clay", "Sand"])}
	for s in [5, 7, 11, 23]:
		var a := build(s, heap_rows)
		var b := build(s, empty)
		var info: Dictionary = a[1]
		var heap: Rect2i = info["spawned"]["areas"].get("spoil_heap", Rect2i())
		check(heap.size.x > 0, "seed %d: the Heap exists (%s)" % [s, heap])
		var hub: Rect2i = info["hub"]
		var off := absi(heap.get_center().x - hub.get_center().x)
		check(off >= 220 and off <= 300, "seed %d: it is %d cells off the Hub" % [s, off])
		var placed: Dictionary = info["spawned"]["placed"]
		for m in ["Sulfur", "Coal", "Clay", "Sand"]:
			check(placed.get(m, 0) > 0, "seed %d: %s in the Heap (%d cells)" % [s, m, placed.get(m, 0)])
		var ca: PackedByteArray = a[0].get_cells()
		var cb: PackedByteArray = b[0].get_cells()
		var outside := 0
		for y in D.H:
			for x in D.W:
				var i := y * D.W + x
				if ca[i] != cb[i]:
					if heap.has_point(Vector2i(x, y)):
						continue
					outside += 1
		check(outside == 0, "seed %d: %d cells differ outside the Heap" % [s, outside])
		# Only the Heap's box gets anything above the old ground; everything in it is Heap.
		var hosts := [D.GRAVEL, D.SULFUR, D.COAL, D.CLAY, D.SAND, D.AIR, D.SLICK, D.FLUX, D.RIME, D.WEFT]
		var stray := 0
		for y in range(heap.position.y, heap.end.y):
			for x in range(heap.position.x, heap.end.x):
				if not (ca[y * D.W + x] in hosts + [D.DIRT, D.STONE]):
					stray += 1
		check(stray == 0, "seed %d: %d odd cells in the Heap's box" % [s, stray])
		# The full table adds the rest on top (wave 1 and 2 rows, biome ground): its cells, plus what worldgen's arching clears under them (Air).
		var wave := build(s, full)
		var cw: PackedByteArray = wave[0].get_cells()
		var fallout := 0
		var added := 0
		for i in D.W * D.H:
			if cw[i] != ca[i]:
				if cw[i] == D.AIR:
					fallout += 1
				else:
					added += 1
		check(added > 100000 and fallout < 2500, "seed %d: the full table places %d cells and shifts %d others" % [s, added, fallout])
		if s == 7:
			for _t in 60:
				a[0].step()
			var moved := 0
			var now: PackedByteArray = a[0].get_cells()
			for y in range(heap.position.y, heap.end.y):
				for x in range(heap.position.x, heap.end.x):
					if now[y * D.W + x] != ca[y * D.W + x]:
						moved += 1
			check(moved < heap.size.x * heap.size.y * 0.02, "seed 7: %d of %d cells moved in a second" % [moved, heap.size.x * heap.size.y])


func scenario_c_d() -> void:
	print("C. unknown names, D. home ranges")
	var w := 768
	var h := 1024
	var g := PackedByteArray()
	g.resize(w * h)
	g.fill(D.STONE)
	var table := {"areas": {}, "spawns": [
		{"material": "Moonglass", "host": ["Stone"], "x": [0.25, 0.5], "depth": [400, 600], "clumps": [6, 6], "radius": [4, 4]},
		{"material": "Sand", "host": ["Stone"], "x": [0.25, 0.5], "depth": [400, 600], "clumps": [6, 6], "radius": [4, 4]},
		{"material": "Coal", "host": ["Stone"], "enabled": false, "clumps": [5, 5]},
	]}
	var out := SR.place(g, w, h, table, 3, {})
	check(out["skipped"] == ["Moonglass"], "an unknown name is skipped: %s" % [out["skipped"]])
	check(out["placed"].get("Sand", 0) > 0, "known rows still place")
	check(not out["placed"].has("Coal"), "a parked row places nothing")
	var bad := 0
	for y in h:
		for x in w:
			if g[y * w + x] == D.SAND and (x < 187 or x > 389 or y < 395 or y > 605):
				bad += 1
	check(bad == 0, "no Sand outside its home range (%d)" % bad)
	# A name the table learns later works with no code change.
	g.fill(D.STONE)
	var out2 := SR.place(g, w, h, table, 3, {}, func(nm: String) -> int:
			return 77 if nm == "Moonglass" else (D.STONE if nm == "Stone" else (D.SAND if nm == "Sand" else (D.COAL if nm == "Coal" else -1))))
	check(out2["skipped"].is_empty() and out2["placed"].get("Moonglass", 0) > 0 and g.has(77), "a new material places once the resolver knows it")
	var untouched := g.count(D.STONE)
	check(untouched > 0 and g.count(D.COAL) == 0, "hosts only: nothing but Stone was replaced")


const BIOMES := ["dunes", "fen", "salt_flats", "ferrite_hills", "sulfur_vents", "gall_caverns"]
const PAIRS := [["dunes", "fen"], ["salt_flats", "ferrite_hills"], ["sulfur_vents", "gall_caverns"]]
## Materials the table places only in one biome (the Heap and the outliers aside, none of these are anywhere else).
const HOMES := {"Quickmire": "fen", "Bloat": "fen", "Brine": "salt_flats", "Chlor": "salt_flats", "Rattle": "ferrite_hills", "Sourwater": "ferrite_hills",
		"Gall": "gall_caverns", "Vitriol": "gall_caverns", "Veinstone": "gall_caverns", "Lumen": "gall_caverns"}


func scenario_f() -> void:
	print("F. biomes")
	var dune_sides := {}
	for s in [5, 7, 11, 23]:
		var w := build(s, SR.load_table())
		var info: Dictionary = w[1]
		var sp: Dictionary = info["spawned"]
		var shapes: Dictionary = sp["shapes"]
		var cells: PackedByteArray = w[0].get_cells()
		check(shapes.size() == 6, "seed %d: six biomes (%s)" % [s, ", ".join(shapes.keys())])
		for pair in PAIRS:
			check(sp["sides"][pair[0]] != 0 and sp["sides"][pair[0]] == -sp["sides"][pair[1]], "seed %d: %s and %s take opposite flanks (%d, %d)" % [s, pair[0], pair[1], sp["sides"][pair[0]], sp["sides"][pair[1]]])
		dune_sides[sp["sides"]["dunes"]] = true
		var lo := D.W / 3.0
		var hi := D.W * 2.0 / 3.0
		for nm in BIOMES:
			var sh: Dictionary = shapes[nm]
			check(SR.biome_at(sp, int(sh["cx"]), int(sh["cy"])) == nm, "seed %d: %s is at its own centre (%d, %d)" % [s, nm, sh["cx"], sh["cy"]])
			if nm != "sulfur_vents":   # that one sits on a lava pocket, wherever the pocket is
				var reach: float = sh["rx"] * 1.1
				check(sh["cx"] + reach < lo or sh["cx"] - reach > hi, "seed %d: %s keeps out of the Hub's middle third (x %d to %d)" % [s, nm, sh["cx"] - reach, sh["cx"] + reach])
		for nm in ["dunes", "fen", "salt_flats", "ferrite_hills", "sulfur_vents"]:
			check(sp["recipe"][nm] > 1000, "seed %d: the %s ground recipe changed %d cells" % [s, nm, sp["recipe"][nm]])
		# The Dunes: no Dirt left inside, and no Water.
		var dunes: Dictionary = shapes["dunes"]
		var dirt := 0
		var water := 0
		var sand := 0
		for y in range(maxi(int(dunes["cy"] - dunes["ry"] * 1.1), 0), mini(int(dunes["cy"] + dunes["ry"] * 1.1), D.H)):
			for x in range(maxi(int(dunes["cx"] - dunes["rx"] * 1.1), 0), mini(int(dunes["cx"] + dunes["rx"] * 1.1), D.W)):
				if SR.inside(dunes, x, y):
					var c := cells[y * D.W + x]
					dirt += 1 if c == D.DIRT or c == D.PACKED_DIRT else 0
					water += 1 if c == D.WATER else 0
					sand += 1 if c == D.SAND else 0
		check(dirt == 0 and water == 0 and sand > 10000, "seed %d: the Dunes are sand all through (%d Sand, %d Dirt, %d Water)" % [s, sand, dirt, water])
		# Residents sit in their own biome.
		var outside := {}
		var ids := {}
		for nm: String in HOMES:
			ids[D.M.id_of(nm)] = nm
		for i in D.W * D.H:
			var c := cells[i]
			if ids.has(c) and SR.biome_at(sp, i % D.W, int(i / float(D.W))) != HOMES[ids[c]]:
				outside[ids[c]] = outside.get(ids[c], 0) + 1
		check(outside.is_empty(), "seed %d: residents stay in their biome (strays: %s)" % [s, outside])
		# The climate grid (A6 part 3): each biome's `ambient` lands on its own chunks, fades out past the rim, and touches nothing else.
		var amb_want := {"dunes": 20, "fen": -10, "salt_flats": -60, "sulfur_vents": 40, "gall_caverns": 40}
		check(sp["ambient"] == amb_want, "seed %d: five of the six biomes carry an ambient offset (%s)" % [s, sp["ambient"]])
		var offs := SR.chunk_offsets(sp, D.W, D.H)
		var cw := D.W >> 5
		var centres_ok := true
		var fades_ok := true
		for nm: String in amb_want:
			var shp: Dictionary = shapes[nm]
			centres_ok = centres_ok and offs[(int(shp["cy"]) >> 5) * cw + (int(shp["cx"]) >> 5)] == amb_want[nm]
			var out_x := int(shp["cx"] + (shp["rx"] * 1.1 + 64) * (1.0 if shp["cx"] < D.W * 0.5 else -1.0))   # inward, toward the middle of the map
			fades_ok = fades_ok and offs[(int(shp["cy"]) >> 5) * cw + (clampi(out_x, 0, D.W - 1) >> 5)] == 0
		check(centres_ok, "seed %d: the chunk at each biome's centre has its full offset" % s)
		check(fades_ok, "seed %d: and the chunks beyond the fade (rim + 64 cells inward) have none" % s)
		var stray_chunks := 0
		var part_chunks := 0
		for i in offs.size():
			if offs[i] == 0:
				continue
			var px := ((i % cw) << 5) + 16
			var py := (int(i / float(cw)) << 5) + 16
			var near := false
			for nm: String in amb_want:
				var shn: Dictionary = shapes[nm]
				near = near or (absf(px - shn["cx"]) <= shn["rx"] * 1.1 + 56 and absf(py - shn["cy"]) <= shn["ry"] * 1.1 + 56)
			stray_chunks += 0 if near else 1
			part_chunks += 1 if absi(offs[i]) < 20 else 0
		check(stray_chunks == 0 and part_chunks > 20, "seed %d: offsets sit within reach of their biomes only (%d strays) and fade through partial values (%d chunks under 20)" % [s, stray_chunks, part_chunks])
		check(offs[(int(shapes["ferrite_hills"]["cy"]) >> 5) * cw + (int(shapes["ferrite_hills"]["cx"]) >> 5)] == 0 and offs[(int(info["hub"].position.y) >> 5) * cw + (int(info["hub"].position.x) >> 5)] == 0, "seed %d: the Ferrite hills (no ambient of their own) and the Hub's chunk stay at the row's ambient" % s)
		# The Fen's Water pockets each carry a spring on their floor (A6 part 4: a Waterwheel's source).
		var fen_springs := 0
		var dry := 0
		for c: Vector2i in info["springs"]:
			if SR.biome_at(sp, c.x, c.y) == "fen" and cells[c.y * D.W + c.x] == D.WATER:
				fen_springs += 1
				dry += 1 if cells[(c.y + 1) * D.W + c.x] == D.WATER else 0
		check(fen_springs >= 2 and dry == 0, "seed %d: %d springs on the floors of Fen pockets (%d not on a floor)" % [s, fen_springs, dry])
		check(not sp.has("springs"), "seed %d: the springs are in the world's list, not left in the spawn record" % s)
		# Level 1 of every Mk upgrade stays a straight shaft: Flux, Rime and Ferrite in the middle third, below the Topsoil.
		for nm in ["Flux", "Rime", "Ferrite"]:
			var mid := 0
			var id: int = D.M.id_of(nm)
			for y in range(1500, 3000):
				for x in range(int(lo), int(hi)):
					mid += 1 if cells[y * D.W + x] == id else 0
			check(mid > 600, "seed %d: %d cells of %s in the Hub's middle third" % [s, mid, nm])
		# Beyond that, each lives on its biome's flank and not the other. Hills right: nothing of Salt flats' goods on the right, and the reverse.
		var salt_right: bool = sp["sides"]["salt_flats"] > 0
		var stray := 0
		for y in range(1000, 3000):
			for x in range(0, D.W):
				var left: bool = x < D.W * 0.25
				var right: bool = x > D.W * 0.75
				var c := cells[y * D.W + x]
				if (left and salt_right) or (right and not salt_right):
					stray += 1 if (c == D.M.id_of("Flux") or c == D.M.id_of("Rime")) else 0
				if (left and not salt_right) or (right and salt_right):
					stray += 1 if c == D.M.id_of("Ferrite") else 0
		check(stray == 0, "seed %d: Flux and Rime stay on the Salt flats' flank, Ferrite on the hills' (%d strays)" % [s, stray])
	check(dune_sides.size() == 2, "the Dunes took both flanks over four seeds")


func scenario_g() -> void:
	print("G. patch machinery")
	var w := 1024
	var h := 1024
	var rock := {"areas": {"p": {"shape": "patch", "x": [0.4, 0.5], "depth": [300, 500], "size": [40, 30], "label": "P", "color": [1, 0, 0],
				"ground": [{"from": ["Stone"], "to": "Sand", "density": 0.5}]}},
			"spawns": [{"material": "Coal", "area": "p", "host": ["Stone"], "clumps": [6, 6], "radius": [30, 40], "shape": "blob"}]}
	var g := PackedByteArray()
	g.resize(w * h)
	g.fill(D.STONE)
	var out := SR.place(g, w, h, rock, 3, {})
	var shape: Dictionary = out["shapes"]["p"]
	var inside_n := 0
	var outside_n := 0
	var coal_in := 0
	var sand_out := 0
	for y in h:
		for x in w:
			var c := g[y * w + x]
			var in_p := SR.inside(shape, x, y)
			if c == D.SAND:
				sand_out += 0 if in_p else 1
				inside_n += 1
			if c == D.COAL:
				coal_in += 1 if in_p else 0
				outside_n += 0 if in_p else 1
	check(inside_n > 500 and sand_out == 0, "the recipe turns about half the patch to Sand and touches nothing outside (%d Sand, %d outside)" % [inside_n, sand_out])
	check(coal_in > 200 and outside_n == 0, "a resident much wider than its patch is cut at the rim (%d Coal in, %d out)" % [coal_in, outside_n])
	check(out["recipe"]["p"] == inside_n, "and the recipe's count matches (%d)" % out["recipe"]["p"])
	check(SR.biome_at(out, int(shape["cx"]), int(shape["cy"])) == "p" and SR.biome_at(out, 5, 5) == "", "biome_at names the patch and nothing elsewhere")
	rock["areas"]["p"]["ambient"] = 25
	g.fill(D.STONE)
	out = SR.place(g, w, h, rock, 3, {})
	shape = out["shapes"]["p"]
	var offs_p := SR.chunk_offsets(out, w, h)
	var cwp := w >> 5
	var inner := offs_p[(int(shape["cy"]) >> 5) * cwp + (int(shape["cx"]) >> 5)]
	var total := 0
	for v in offs_p:
		total += 1 if v != 0 else 0
	check(out["ambient"] == {"p": 25} and inner == 25 and total > 4 and total < 60, "a patch with `ambient` sets it on the chunks in and just round it (%d at the centre, %d chunks)" % [inner, total])
	rock["areas"]["p"].erase("ambient")
	g.fill(D.STONE)
	out = SR.place(g, w, h, rock, 3, {})
	var none_set := true
	for v in SR.chunk_offsets(out, w, h):
		none_set = none_set and v == 0
	check(out["ambient"].is_empty() and none_set, "and one without it sets nothing")
	rock["spawns"][0]["spring"] = true
	g.fill(D.STONE)
	out = SR.place(g, w, h, rock, 3, {})
	var floors := 0
	var off_floor := 0
	for c: Vector2i in out["springs"]:
		floors += 1
		off_floor += 0 if g[c.y * w + c.x] == D.COAL and g[(c.y + 1) * w + c.x] != D.COAL else 1
	check(floors >= 2 and off_floor == 0, "a row marked `spring` lists the floor of each clump it painted (%d springs, %d off a floor)" % [floors, off_floor])
	rock["spawns"][0].erase("spring")
	g.fill(D.STONE)
	out = SR.place(g, w, h, rock, 3, {})
	check(out["springs"].is_empty(), "and a row without it lists none")
	rock["spawns"][0]["clip"] = false
	g.fill(D.STONE)
	out = SR.place(g, w, h, rock, 3, {})
	shape = out["shapes"]["p"]
	outside_n = 0
	for y in h:
		for x in w:
			if g[y * w + x] == D.COAL and not SR.inside(shape, x, y):
				outside_n += 1
	check(outside_n > 100, "with clip off the same row spills out of it (%d Coal out)" % outside_n)
	# Flanks: x is written for the left one, `opposite` takes the other, the surface anchor stands on the ground.
	var lefts := 0
	var ok_sides := true
	var ok_x := true
	for sd in range(1, 9):
		var table := {"areas": {
				"a": {"shape": "patch", "x": [0.1, 0.2], "depth": [400, 400], "size": [30, 20], "side": "random"},
				"b": {"shape": "patch", "x": [0.1, 0.2], "depth": [400, 400], "size": [30, 20], "opposite": "a"}}, "spawns": []}
		g.fill(D.STONE)
		var o := SR.place(g, w, h, table, sd, {})
		ok_sides = ok_sides and o["sides"]["a"] == -o["sides"]["b"] and o["sides"]["a"] != 0
		lefts += 1 if o["sides"]["a"] < 0 else 0
		for nm in ["a", "b"]:
			var cx: float = o["shapes"][nm]["cx"]
			var left_range: bool = cx >= 0.1 * w - 1 and cx <= 0.2 * w + 1
			var right_range: bool = cx >= 0.8 * w - 1 and cx <= 0.9 * w + 1
			ok_x = ok_x and (left_range if o["sides"][nm] < 0 else right_range)
	check(ok_sides and lefts > 0 and lefts < 8, "a patch takes a flank per seed and its opposite the other (%d of 8 seeds on the left)" % lefts)
	check(ok_x, "the right flank mirrors the home range")
	var ground := PackedInt32Array()
	ground.resize(w)
	for x in w:
		ground[x] = 300 + (x >> 4)
	var surf := {"areas": {"s": {"shape": "patch", "x": [0.3, 0.6], "size": [20, 20], "anchor": "surface"}}, "spawns": []}
	g.fill(D.STONE)
	var os := SR.place(g, w, h, surf, 4, {"ground": ground})
	var sh: Dictionary = os["shapes"]["s"]
	check(int(sh["cy"]) == ground[int(sh["cx"])], "the surface anchor puts the centre on the ground (%d vs %d)" % [sh["cy"], ground[int(sh["cx"])]])
	# Avoiding: a rectangle over the whole home range can't be dodged, a small one can.
	var dodge := {"areas": {"d": {"shape": "patch", "x": [0.0, 1.0], "depth": [200, 800], "size": [30, 20], "avoid": ["aquifers"]}}, "spawns": []}
	var hits := 0
	for sd in range(1, 9):
		g.fill(D.STONE)
		var od := SR.place(g, w, h, dodge, sd, {"aquifers": [Rect2i(400, 300, 200, 300)]})
		hits += 1 if od["areas"]["d"].intersects(Rect2i(400, 300, 200, 300)) else 0
	check(hits == 0, "a patch looks for ground clear of what it avoids (%d of 8 seeds overlap)" % hits)
	# A rule with not_near keeps clear of what it names.
	var shy := {"areas": {"q": {"shape": "patch", "x": [0.5, 0.5], "depth": [400, 400], "size": [50, 40],
			"ground": [{"from": ["Stone"], "to": "Sand", "not_near": ["Coal"], "gap": 3}]}}, "spawns": []}
	g.fill(D.STONE)
	for y in range(380, 420):
		for x in range(500, 520):
			g[y * w + x] = D.COAL
	var oq := SR.place(g, w, h, shy, 5, {})
	var touching := 0
	for y in range(370, 430):
		for x in range(490, 530):
			if g[y * w + x] == D.SAND:
				for yy in range(y - 1, y + 2):
					for xx in range(x - 1, x + 2):
						touching += 1 if g[yy * w + xx] == D.COAL else 0
	check(oq["recipe"]["q"] > 1000 and touching == 0, "not_near keeps the recipe off the cells beside what it names (%d changed, %d touching)" % [oq["recipe"]["q"], touching])
