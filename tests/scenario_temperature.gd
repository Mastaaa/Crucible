extends SceneTree
## A1: the temperature field and family-tag reactions.
##  Sim only (seed 7, or a bench sim with a flat 20-degree ambient):
##   A. worldgen's ambient: the Topsoil cool, the Magma band at 550, lava at 1100
##   B. heat leaks from a hot spot into the stone round it, then settles back
##   C. water heated past 100 boils; steam that condenses comes back cool
##   D. hot rock in a cold place cools to stone; stone beside lava heats to hot rock
##   E. lava chilled hard enough freezes into obsidian
##   F. coal heated past its kindling point catches fire (with air beside it)
##   G. families: a family rule covers every member, a material's own rule wins
##   H. a temperature window and a catalyst family on a reaction
##   I. a falling hot slab keeps its heat
##   J. temperatures save and load, and 1 and 4 threads agree
##   K. the pass stays cheap on a fresh world
##  In the game:
##   L. the lab bench: an open room, the brush paints and heats, nothing is saved
## Run: godot --headless --path . --script tests/scenario_temperature.gd

const D = preload("res://scripts/defs.gd")
const Mats = preload("res://scripts/materials.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")
const Save = preload("res://scripts/save.gd")

var game: Node
var f := 0
var fails := 0


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		if not SimFactory.native_available():
			print("The C++ sim isn't loaded: these need it.")
			print("FAILURES: 1")
			return true
		scenario_a()
		scenario_b()
		scenario_c()
		scenario_d()
		scenario_e()
		scenario_f()
		scenario_g()
		scenario_h()
		scenario_i()
		scenario_j()
		scenario_k()
		scenario_l()
		print("FAILURES: %d" % fails)
		return true
	return false


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


# --- Helpers --------------------------------------------------------------------------

func world_sim(threads := 1):
	var sim = SimFactory.create(threads)
	WorldGen.new().generate(sim, 7)
	return sim


## A sim on the bench's open room (flat 20 degrees), optionally with its own reactions.
func bench_sim(threads := 1, reactions = null):
	var sim = SimFactory.create(threads)
	if reactions != null:
		sim.configure(Mats.sim_materials, reactions)
	sim.set_ambient(D.ambient_rows(D.BENCH_AMBIENT))
	WorldGen.new().bench(sim)
	return sim


func fill(sim, r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			sim.set_cell(x, y, m)


func count_in(sim, r: Rect2i, m: int) -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	mask[m] = 1
	return sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)


func steam_in(sim, r: Rect2i) -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	for m in range(D.STEAM, D.STEAM_LAST + 1):
		mask[m] = 1
	return sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)


func run(sim, ticks: int) -> void:
	for _i in ticks:
		sim.step()


## The first cell of `m` found scanning rows y0..y1 (every `step` cells), or (-1, -1).
func find(sim, m: int, y0: int, y1: int, step := 5) -> Vector2i:
	for y in range(y0, y1, step):
		for x in range(4, D.W - 4, step):
			if sim.get_cell(x, y) == m:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- Sim only ---------------------------------------------------------------------------

func scenario_a() -> void:
	print("A. worldgen's ambient")
	var sim = world_sim()
	var top: int = sim.get_temp(300, 400)
	var stone: int = sim.get_temp(300, 2200)
	var hot := find(sim, D.HOT_ROCK, 3300, 4400)
	var lava := find(sim, D.LAVA, 3100, 4400)
	var ht: int = sim.get_temp(hot.x, hot.y)
	var lt: int = sim.get_temp(lava.x, lava.y)
	print("  topsoil %d, stone band %d, hot rock %d, lava %d" % [top, stone, ht, lt])
	check(top >= 10 and top <= 30 and stone > top and stone < 100, "the ground warms with depth, under boiling above the Magma band")
	check(ht == D.AMBIENT_MAGMA and lt == 1100, "the Magma band's rock is at %d, lava at 1100" % D.AMBIENT_MAGMA)
	run(sim, 600)
	var ht2: int = sim.get_temp(hot.x, hot.y)
	check(count_in(sim, Rect2i(2, 3000, D.W - 4, 1500), D.HOT_ROCK) > 1000000 and ht2 >= 500,
			"ten seconds on, the band is still hot rock (%d at the same cell)" % ht2)


func scenario_b() -> void:
	print("B. heat leaks into its neighbours")
	var sim = bench_sim()
	var block := Rect2i(300, 400, 61, 61)
	fill(sim, block, D.BEDROCK)
	fill(sim, block.grow(-1), D.STONE)
	run(sim, 8)
	var c := block.get_center()
	sim.heat_rect(c.x - 2, c.y - 2, 5, 5, 580)
	var t0: int = sim.get_temp(c.x, c.y)
	run(sim, 600)
	var t1: int = sim.get_temp(c.x, c.y)
	var ring: int = sim.get_temp(c.x + 6, c.y)
	print("  middle %d -> %d after 10 s, 6 cells off %d" % [t0, t1, ring])
	check(t1 < t0 - 100 and ring > 40, "the hot spot cools as the stone round it warms")
	run(sim, 60 * 120)
	var t2: int = sim.get_temp(c.x, c.y)
	print("  two minutes later: %d" % t2)
	check(t2 < 100, "and the whole block settles back toward the room's 20")


func scenario_c() -> void:
	print("C. water boils past 100, condensed steam comes back cool")
	var sim = bench_sim()
	var box := Rect2i(200, 300, 120, 200)
	fill(sim, box.grow(10), D.BEDROCK)
	fill(sim, box, D.AIR)
	var pool := Rect2i(box.position.x, box.end.y - 20, box.size.x, 20)
	fill(sim, pool, D.WATER)
	run(sim, 30)
	var w0 := count_in(sim, box, D.WATER)
	check(sim.get_temp(pool.get_center().x, pool.get_center().y) == 20 and steam_in(sim, box) == 0, "placed water is at 20 and stays water")
	sim.heat_rect(pool.position.x, pool.position.y, pool.size.x, 4, 100)
	run(sim, 16)
	var st := steam_in(sim, box)
	var w1 := count_in(sim, box, D.WATER)
	print("  heated the top 4 rows to 120: water %d -> %d, steam %d" % [w0, w1, st])
	check(st > 0 and w1 <= w0 - st / 2, "the heated water boils off")
	run(sim, 60 * 40)
	var back := count_in(sim, box, D.WATER)
	var hot := 0
	for x in range(box.position.x, box.end.x, 3):
		for y in range(box.position.y, box.end.y, 3):
			if sim.get_cell(x, y) == D.WATER and sim.get_temp(x, y) >= 100:
				hot += 1
	print("  40 s later: water %d, steam %d, water at 100 or more %d" % [back, steam_in(sim, box), hot])
	check(back > w1 and hot == 0, "steam condenses back into water that doesn't boil again")


func scenario_d() -> void:
	print("D. hot rock cools in the cold; stone heats beside lava")
	var sim = bench_sim()
	var slab := Rect2i(100, 400, 40, 40)
	fill(sim, slab.grow(4), D.BEDROCK)
	fill(sim, slab, D.HOT_ROCK)
	run(sim, 8)
	var t0: int = sim.get_temp(slab.get_center().x, slab.get_center().y)
	run(sim, 60 * 60)
	var left := count_in(sim, slab, D.HOT_ROCK)
	print("  placed at %d; a minute in a 20-degree room: %d of %d still hot rock" % [t0, left, slab.get_area()])
	check(t0 >= 540 and left < slab.get_area() / 4, "hot rock in a cold place cools to stone")
	# Stone with a lava pool against it.
	var tub := Rect2i(400, 400, 60, 40)
	fill(sim, tub.grow(12), D.BEDROCK)
	fill(sim, Rect2i(tub.position.x, tub.position.y, tub.size.x, 20), D.STONE)
	fill(sim, Rect2i(tub.position.x, tub.position.y + 20, tub.size.x, 20), D.LAVA)
	run(sim, 60 * 60)
	var heated := count_in(sim, Rect2i(tub.position.x, tub.position.y, tub.size.x, 20), D.HOT_ROCK)
	var near: int = sim.get_temp(tub.get_center().x, tub.position.y + 18)
	print("  a minute over lava: %d stone cells turned hot rock, the one 2 above it at %d" % [heated, near])
	check(heated >= tub.size.x / 2 and heated < tub.size.x * 10, "the stone nearest the lava heats into hot rock, the rest stays stone")


func scenario_e() -> void:
	print("E. chilled lava freezes into obsidian")
	var sim = bench_sim()
	var tub := Rect2i(300, 500, 30, 12)
	fill(sim, tub.grow(4), D.BEDROCK)
	fill(sim, tub, D.LAVA)
	run(sim, 120)
	check(count_in(sim, tub, D.LAVA) == tub.get_area(), "lava holds its heat in a cold room")
	sim.heat_rect(tub.position.x, tub.position.y, tub.size.x, tub.size.y, -1000)
	run(sim, 16)
	var ob := count_in(sim, tub, D.OBSIDIAN)
	print("  chilled by 1000: %d of %d obsidian" % [ob, tub.get_area()])
	check(ob == tub.get_area(), "it freezes solid")


func scenario_f() -> void:
	print("F. coal kindles")
	var sim = bench_sim()
	var room := Rect2i(500, 400, 60, 40)
	fill(sim, room.grow(4), D.BEDROCK)
	fill(sim, room, D.AIR)
	var seam := Rect2i(room.position.x, room.end.y - 10, room.size.x, 10)
	fill(sim, seam, D.COAL)
	var buried := Rect2i(seam.position.x + 20, seam.position.y + 4, 4, 4)
	run(sim, 8)
	check(sim.count_burning() == 0, "cold coal doesn't burn")
	sim.heat_rect(buried.position.x, buried.position.y, buried.size.x, buried.size.y, 800)
	run(sim, 16)
	check(sim.count_burning() == 0, "buried coal heated past its point stays put (no air)")
	sim.heat_rect(seam.position.x + 40, seam.position.y, 6, 2, 800)
	run(sim, 16)
	var burning: int = sim.count_burning()
	print("  surface heated: %d burning" % burning)
	check(burning > 0, "coal heated past its point with air beside it catches fire")


func scenario_g() -> void:
	print("G. families")
	Mats.ensure()
	var fuel := Mats.members("Fuel")
	check(fuel.has(D.COAL) and fuel.has(D.COAL_CHUNKS) and fuel.has(D.SULFUR) and fuel.has(D.SULFUR_GRIT) and not fuel.has(D.STONE),
			"Fuel holds coal and sulfur in both forms")
	check(Array(Mats.families_of(D.SULFUR)) == ["Fuel", "Corrosive"], "sulfur is Fuel and Corrosive")
	var molten := Mats.members("Molten")
	var lava_rule := false
	for r: Dictionary in Mats.sim_reactions:
		if r["a"] == D.LAVA and r["b"] == D.WATER and r["out_a"] == D.OBSIDIAN:
			lava_rule = true
	check(molten.has(D.LAVA) and lava_rule, "the data's Molten + Water rule covers lava")
	# A family rule and a material's own rule over it, in the engine.
	var rules := Mats.expand_reactions([
		{"when": ["Fuel", "Water"], "becomes": ["Ash", "same"], "chance": 1.0},
		{"when": ["Coal chunks", "Water"], "becomes": ["Rubble", "same"], "chance": 1.0},
	])
	var sim = bench_sim(1, rules)
	var tub := Rect2i(300, 500, 40, 10)
	fill(sim, tub.grow(4), D.BEDROCK)
	fill(sim, Rect2i(tub.position.x, tub.position.y, tub.size.x, 5), D.WATER)
	fill(sim, Rect2i(tub.position.x, tub.position.y + 5, 20, 5), D.COAL_CHUNKS)
	fill(sim, Rect2i(tub.position.x + 20, tub.position.y + 5, 20, 5), D.SULFUR_GRIT)
	run(sim, 60)
	var ash := count_in(sim, tub, D.ASH)
	var rubble := count_in(sim, tub, D.RUBBLE)
	print("  Fuel + Water -> Ash, Coal chunks + Water -> Rubble: ash %d, rubble %d" % [ash, rubble])
	check(ash > 0 and rubble > 0 and count_in(sim, Rect2i(tub.position.x, tub.position.y, 20, 10), D.ASH) == 0,
			"sulfur grit follows the family rule, coal chunks their own")


func scenario_h() -> void:
	print("H. a temperature window and a catalyst")
	var rules := Mats.expand_reactions([
		{"when": ["Sand", "Water"], "becomes": ["Clay", "same"], "chance": 0.0002, "min_temp": 50, "catalyst": "Corrosive", "boost": 40},
	])
	var sim = bench_sim(1, rules)
	var a := Rect2i(100, 500, 60, 6)
	var b := Rect2i(300, 500, 60, 6)
	for r: Rect2i in [a, b]:
		fill(sim, r.grow(6), D.BEDROCK)
		fill(sim, Rect2i(r.position.x, r.position.y, r.size.x, 3), D.WATER)
		fill(sim, Rect2i(r.position.x, r.position.y + 3, r.size.x, 3), D.SAND)
	# Under b's top row of sand, sulfur grit: the catalyst, touching every sand
	# cell at the water's edge.
	fill(sim, Rect2i(b.position.x, b.position.y + 4, b.size.x, 2), D.SULFUR_GRIT)
	run(sim, 60 * 5)
	var cold := count_in(sim, a, D.CLAY) + count_in(sim, b, D.CLAY)
	check(cold == 0, "at 20 degrees nothing happens (the rule wants 50)")
	for r: Rect2i in [a, b]:
		sim.heat_rect(r.position.x, r.position.y, r.size.x, r.size.y, 60)
	run(sim, 60 * 3)
	var plain := count_in(sim, a, D.CLAY)
	var boosted := count_in(sim, b, D.CLAY)
	print("  at 80 degrees for 3 s: %d clay without the catalyst, %d with it" % [plain, boosted])
	check(boosted > 20 and boosted > plain * 4, "warm, it goes, and much faster with Corrosive grit touching")


func scenario_i() -> void:
	print("I. a falling hot slab keeps its heat")
	var sim = bench_sim()
	var slab := Rect2i(380, 300, 30, 10)
	fill(sim, slab, D.HOT_ROCK)
	sim.heat_rect(slab.position.x, slab.position.y, slab.size.x, slab.size.y, 300)
	var id: int = sim.make_body(slab.position.x, slab.position.y, slab.size.x, slab.size.y, 0.0, 0.0, 0.0)
	check(id > 0, "the slab is a body")
	run(sim, 90)
	var floor_y := WorldGen.BENCH_FLOOR
	var landed: Vector3i = sim.rect_temp(slab.position.x - 40, floor_y - 40, slab.size.x + 80, 40)
	print("  after 1.5 s: hottest cell on the floor %d" % landed.y)
	check(landed.y > 500, "it lands as hot as it fell")


func scenario_j() -> void:
	print("J. saving, and threads")
	var make := func(threads: int):
		var s = bench_sim(threads)
		var tub := Rect2i(200, 600, 200, 60)
		fill(s, tub.grow(6), D.BEDROCK)
		fill(s, Rect2i(tub.position.x, tub.position.y + 40, 100, 20), D.LAVA)
		fill(s, Rect2i(tub.position.x + 100, tub.position.y + 40, 100, 20), D.WATER)
		fill(s, Rect2i(tub.position.x, tub.position.y + 20, 200, 20), D.STONE)
		s.heat_rect(tub.position.x + 150, tub.position.y + 20, 20, 20, 400)
		return s
	var one = make.call(1)
	var four = make.call(4)
	run(one, 600)
	run(four, 600)
	var r := Rect2i(194, 594, 212, 72)
	var t1: Vector3i = one.rect_temp(r.position.x, r.position.y, r.size.x, r.size.y)
	var t4: Vector3i = four.rect_temp(r.position.x, r.position.y, r.size.x, r.size.y)
	check(one.checksum() == four.checksum() and t1 == t4, "1 and 4 threads give the same cells and temperatures (%s)" % t1)
	var bytes: PackedByteArray = one.save_state()
	var copy = bench_sim(1)
	var ok: bool = copy.load_state(bytes)
	var same := ok
	for p: Vector2i in [Vector2i(250, 650), Vector2i(330, 630), Vector2i(360, 645), Vector2i(220, 620)]:
		same = same and copy.get_temp(p.x, p.y) == one.get_temp(p.x, p.y)
	run(one, 300)
	run(copy, 300)
	var a: Vector3i = one.rect_temp(r.position.x, r.position.y, r.size.x, r.size.y)
	var b: Vector3i = copy.rect_temp(r.position.x, r.position.y, r.size.x, r.size.y)
	check(same and a == b and one.checksum() == copy.checksum(), "a loaded sim has the same temperatures and steps on the same")


func scenario_k() -> void:
	print("K. the pass's cost on a fresh world")
	var times := []
	for every in [D.TEMP_EVERY, 1000000]:
		var sim = world_sim(4)
		var p: Dictionary = D.temp_params()
		p["every"] = every
		sim.set_temp_params(p)
		run(sim, 600)
		var t0 := Time.get_ticks_usec()
		run(sim, 600)
		times.append((Time.get_ticks_usec() - t0) / 600000.0)
		if every == D.TEMP_EVERY:
			print("  chunks the pass looks at: %d of %d" % [sim.stat_tchunks, (D.W / 32) * (D.H / 32)])
			check(sim.stat_tchunks < 400, "it only looks where heat is moving")
	print("  %.3f ms a tick with it, %.3f without" % [times[0], times[1]])


# --- In the game -----------------------------------------------------------------------

func scenario_l() -> void:
	print("L. the lab bench")
	var had_save := Save.exists()
	game.start_bench()
	check(game.bench and game.reveal_all and game.brush_mode and game.info.get("bench", false), "it opens with the brush in hand and the room in view")
	var c := Vector2i(300, 500)
	game.brush_idx = game.bench_mats.find(D.LAVA)
	game._paint(c, false)
	check(game.sim.get_cell(c.x, c.y) == D.LAVA and game.sim.get_temp(c.x, c.y) == 1100, "the brush paints lava, at lava's heat")
	game.brush_idx = game.bench_mats.find(game.BRUSH_COOL)
	var before: int = game.sim.get_temp(c.x, c.y)
	game._paint(c, false)
	check(game.sim.get_temp(c.x, c.y) == before - game.BRUSH_DEGREES, "the cool brush takes heat out")
	check(game.bench_mats.has(D.HOT_ROCK) and game.bench_mats.has(D.OBSIDIAN) and not game.bench_mats.has(D.BUILDING),
			"every material is on the brush, a building's cells aren't")
	game.run_ticks(120)
	check(not game.save_run() and Save.exists() == had_save, "the bench is never saved")
	game.new_game(7)
	check(not game.bench, "a new run isn't the bench")
