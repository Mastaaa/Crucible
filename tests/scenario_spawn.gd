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
	var heap_rows := {"areas": full["areas"], "spawns": full["spawns"].filter(func(r): return r.get("area", "") == "spoil_heap" and r["material"] in ["Sulfur", "Coal", "Clay", "Sand"])}
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
		# The full table adds wave 1 on top: its cells, plus what worldgen's arching clears under them.
		var wave := build(s, full)
		var cw: PackedByteArray = wave[0].get_cells()
		var fallout := 0
		var added := 0
		for i in D.W * D.H:
			if cw[i] != ca[i]:
				if cw[i] >= D.SLICK:
					added += 1
				else:
					fallout += 1
		check(added > 20000 and fallout < 1000, "seed %d: wave 1 places %d cells and shifts %d others" % [s, added, fallout])
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
