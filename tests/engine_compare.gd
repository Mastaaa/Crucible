extends SceneTree
## Runs the same set-pieces on the C++ sim and the old GDScript one and prints what
## came out, side by side, plus a thread-determinism check and timings.
## Run: godot --headless --path . --script tests/engine_compare.gd

const D = preload("res://scripts/defs.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const SimGD = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/worldgen.gd")

var fails := 0


func make(native: bool, threads := 1):
	var sim = SimFactory.create(threads) if native else SimGD.new()
	# The GDScript sim only knows the old chemistry, so compare on a world without spawn regions.
	var wg = WorldGen.new()
	wg.spawn_table = {"areas": {}, "spawns": []}
	wg.generate(sim, 7)
	return sim


func run(sim, ticks: int) -> float:
	var t0 := Time.get_ticks_usec()
	for _t in ticks:
		sim.step()
	return (Time.get_ticks_usec() - t0) / 1000.0


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func near(a: float, b: float, rel: float, abs_tol := 0.0) -> bool:
	return absf(a - b) <= maxf(abs_tol, rel * maxf(absf(a), absf(b)))


## A slab of water dropped into a carved cavern.
func slab(sim) -> Dictionary:
	for y in range(400, 520):
		for x in range(60, 180):
			sim.set_cell(x, y, D.WATER if y < 460 else D.AIR)
	var ms := run(sim, 600)
	# Surface: the highest row in the cavern with water in its middle column.
	var top := 520
	for y in range(400, 520):
		if sim.get_cell(120, y) == D.WATER:
			top = y
			break
	return {"water": sim.count(D.WATER), "top": top, "ms": ms}


## Water poured onto a lava pocket for 20 s.
func lava_pour(sim) -> Dictionary:
	for y in range(560, 600):
		for x in range(100, 140):
			sim.set_cell(x, y, D.LAVA if y >= 585 else D.AIR)
	var ms := 0.0
	for t in 1200:
		if t % 3 == 0 and t < 900:
			sim.set_cell(120, 562, D.WATER)
		var t0 := Time.get_ticks_usec()
		sim.step()
		ms += (Time.get_ticks_usec() - t0) / 1000.0
	var steam := 0
	for m in range(D.STEAM, D.STEAM_LAST + 1):
		steam += sim.count(m)
	return {"obsidian": sim.count(D.OBSIDIAN), "steam": steam, "reactions": sim.reactions, "ms": ms}


## A 6-wide shaft through the topsoil left open to erode for 60 s, then a tremor.
func erosion(sim) -> Dictionary:
	for y in range(D.GROUND_Y, 280):
		for x in range(20, 26):
			sim.set_cell(x, y, D.AIR)
	for t in 3600:
		if t % 2 == 0:
			sim.erode(D.ERODE_SAMPLES, D.GROUND_Y + 6, 330)
		sim.step()
	var loose: int = sim.count(D.LOOSE_DIRT)
	var crumbled: int = sim.tremor(200, D.GROUND_Y + 4, D.H - 4)
	return {"eroded": sim.eroded, "loose": loose, "tremor": crumbled}


func _initialize() -> void:
	print("C++ sim loaded: %s" % SimFactory.native_available())
	if not SimFactory.native_available():
		print("FAILURES: 1")
		quit()
		return

	print("A. water slab (7,200 cells) dropped into a cavern, 10 s")
	var a_gd := slab(make(false))
	var a_cc := slab(make(true))
	print("  gdscript %s\n  c++      %s" % [a_gd, a_cc])
	check(a_gd["water"] == a_cc["water"], "no water made or lost")
	check(absi(a_gd["top"] - a_cc["top"]) <= 1, "settles to the same level (row %d vs %d)" % [a_gd["top"], a_cc["top"]])
	print("  speed: %.1fx" % (a_gd["ms"] / maxf(a_cc["ms"], 0.001)))

	print("B. water poured on lava, 20 s")
	var b_gd := lava_pour(make(false))
	var b_cc := lava_pour(make(true))
	print("  gdscript %s\n  c++      %s" % [b_gd, b_cc])
	check(near(b_gd["obsidian"], b_cc["obsidian"], 0.35, 10), "similar obsidian crust")
	check(b_cc["reactions"] > 0, "water and lava react")

	print("C. an open shaft eroding for 60 s, then a tremor")
	var c_gd := erosion(make(false))
	var c_cc := erosion(make(true))
	print("  gdscript %s\n  c++      %s" % [c_gd, c_cc])
	check(near(c_gd["eroded"], c_cc["eroded"], 0.6, 6), "similar erosion")
	check(near(c_gd["tremor"], c_cc["tremor"], 0.5, 10), "a tremor finds about as much exposed stone to crumble")

	print("D. same result on 1 thread and on 4")
	var one = make(true, 1)
	var four = make(true, 4)
	for sim in [one, four]:
		for y in range(400, 520):
			for x in range(20, 236):
				sim.set_cell(x, y, D.WATER if y < 440 and (x >> 3) % 2 == 0 else D.AIR)
		for y in range(560, 600):
			for x in range(40, 220):
				sim.set_cell(x, y, D.LAVA if y >= 585 else D.AIR)
		for x in range(40, 220, 3):
			sim.set_cell(x, 562, D.WATER)
	var t1 := run(one, 900)
	var t4 := run(four, 900)
	print("  checksums %d / %d, %.0f ms vs %.0f ms (%d chunks, %d updates last tick)" % [one.checksum(), four.checksum(), t1, t4, four.stat_chunks, four.stat_updates])
	check(one.checksum() == four.checksum(), "identical cells")

	print("E. worst case: the whole Stone band as falling water, 2 s")
	var big = make(true, 4)
	for y in range(300, 700):
		for x in range(2, 254):
			if (x + y) % 3 != 0:
				big.set_cell(x, y, D.WATER)
			else:
				big.set_cell(x, y, D.AIR)
	var tb := run(big, 120)
	print("  %.2f ms a tick, %d updates in the last one" % [tb / 120.0, big.stat_updates])

	print("F. free fall (C++): a grain and a splash of water down a 280-row shaft")
	var ff = make(true, 4)
	for y in range(318, 603):
		for x in range(116, 141):
			var wall := x < 120 or x > 136 or y > 600
			ff.set_cell(x, y, D.BEDROCK if wall else D.AIR)
	ff.set_cell(124, 320, D.SAND)
	for x in range(130, 135):
		ff.set_cell(x, 320, D.WATER)
	run(ff, 30)
	var grain := -1
	for y in range(320, 601):
		if ff.get_cell(124, y) == D.SAND:
			grain = y
	print("  after 0.5 s the grain is at row %d (one cell a tick: 350)" % grain)
	check(grain > 380, "a falling grain speeds up past a cell a tick")
	run(ff, 60)
	var landed := 0
	var in_shaft := 0
	for y in range(320, 601):
		for x in range(120, 137):
			if ff.get_cell(x, y) == D.WATER:
				in_shaft += 1
				if y == 600:
					landed += 1
	check(ff.get_cell(124, 600) == D.SAND, "and lands on the floor within 1.5 s (one cell a tick: 4.7 s)")
	check(landed == 5 and in_shaft == 5, "the water lands too, none lost (%d of 5 on the floor)" % landed)
	print("FAILURES: %d" % fails)
	quit()
