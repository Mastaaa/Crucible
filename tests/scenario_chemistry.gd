extends SceneTree
## Phase 5 chemistry scenarios.
##  Sim only:
##   A. a coal fire spreads, smokes and leaves ash; water puts it out
##   B. ceilings crumble: dirt quickly, stone slowly
##   C. gases sort themselves: fumes sink under smoke
##   D. fire, blasts and particles give the same result on 1 thread and on 4
##   E. every seed has coal and sulfur, none of it touching lava
##   F. a big coal fire and a string of blasts stay cheap
##  In the game (seed 7, by the Hub):
##   G. digging coal banks Stone and Power
##   H. sulfur corrodes a Conduit; a Stone patches it up
##   I. burning coal under a link breaks it; once the fire's out a Stone mends it
##   J. a blast's debris falls into a Hopper, which also swallows ash
## Run: godot --headless --path . --script tests/scenario_chemistry.gd

const D = preload("res://scripts/defs.gd")
const Mats = preload("res://scripts/materials.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")

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
		print("FAILURES: %d" % fails)
		return true
	return false


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


# --- Sim-only helpers ---------------------------------------------------------------

func make_sim(threads := 1):
	var sim = SimFactory.create(threads)
	WorldGen.new().generate(sim, 7)
	return sim


func fill(sim, r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			sim.set_cell(x, y, m)


## A stone box one cell thick around `inner`, air inside.
func sealed_box(sim, inner: Rect2i) -> void:
	fill(sim, inner.grow(1), D.STONE)
	fill(sim, inner, D.AIR)


func count_in(sim, r: Rect2i, m: int) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if sim.get_cell(x, y) == m:
				n += 1
	return n


func count_steam(sim) -> int:
	var n := 0
	for m in range(D.STEAM, D.STEAM_LAST + 1):
		n += sim.count(m)
	return n


func mean_y(sim, r: Rect2i, m: int) -> float:
	var sum := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if sim.get_cell(x, y) == m:
				sum += y
				n += 1
	return sum / maxf(n, 1.0)


# --- Sim-only scenarios -------------------------------------------------------------

func scenario_a() -> void:
	print("A. a coal fire in a sealed cave, then a flood")
	var sim = make_sim()
	var cave := Rect2i(60, 400, 60, 40)
	sealed_box(sim, cave)
	fill(sim, Rect2i(70, 430, 40, 10), D.COAL)
	sim.ignite(90, 430)
	var most_fire := 0
	var most_smoke := 0
	var most_burning := 0
	for t in 7200:
		sim.step()
		if t % 30 == 0:
			most_fire = maxi(most_fire, sim.count(D.FIRE))
			most_smoke = maxi(most_smoke, sim.count(D.SMOKE))
			most_burning = maxi(most_burning, sim.count_burning())
		if t == 1799:
			print("  after 30 s: %d burning, %d flames, %d smoke" % [sim.count_burning(), sim.count(D.FIRE), sim.count(D.SMOKE)])
	var burning: int = sim.count_burning()
	var ash: int = count_in(sim, cave, D.ASH)
	print("  after 2 min: %d burning (most %d), most flames %d, most smoke %d, ash %d, coal left %d" % [
		burning, most_burning, most_fire, most_smoke, ash, count_in(sim, cave, D.COAL)])
	check(most_burning >= 20, "the fire spread along the coal (up to %d cells alight)" % most_burning)
	check(burning >= 10, "and is still going after two minutes")
	check(most_fire > 0, "burning coal throws flames")
	check(most_smoke > 20, "and smoke")
	check(ash > 0, "burnt-out coal leaves ash")
	# Flood the cave down to just above the coal.
	var poured := 0
	for y in range(400, 426):
		for x in range(60, 120):
			if Mats.is_thin(sim.get_cell(x, y)):
				sim.set_cell(x, y, D.WATER)
				poured += 1
	var most_steam := 0
	for t in 1200:
		sim.step()
		if t % 30 == 0:
			most_steam = maxi(most_steam, count_steam(sim))
	var left: int = sim.count_burning()
	print("  after a 20 s flood of %d cells: %d still burning, most steam %d" % [poured, left, most_steam])
	check(left <= burning * 0.2, "water put most of it out (%d -> %d)" % [burning, left])
	check(most_steam > 0, "putting it out made steam")


func scenario_b() -> void:
	print("B. ceilings crumble")
	var sim = make_sim()
	# A 40-wide cave under a dirt ceiling, and one under stone.
	fill(sim, Rect2i(40, 130, 60, 24), D.DIRT)
	var dirt_cave := Rect2i(50, 141, 40, 10)
	fill(sim, dirt_cave, D.AIR)
	fill(sim, Rect2i(40, 470, 60, 24), D.STONE)
	var stone_cave := Rect2i(50, 481, 40, 10)
	fill(sim, stone_cave, D.AIR)
	var c0: int = sim.crumbled
	for _t in 3600:
		sim.step()
		sim.weather(D.WEATHER_SAMPLES)
	var dirt_fell := count_in(sim, dirt_cave.grow_individual(0, 3, 0, 0), D.LOOSE_DIRT)
	print("  dirt: %d cells came down in 60 s (%d crumbled map-wide)" % [dirt_fell, sim.crumbled - c0])
	check(dirt_fell >= 10 and dirt_fell <= 70, "a dirt ceiling sheds a cell every few seconds")
	for _t in 32400:
		sim.step()
		sim.weather(D.WEATHER_SAMPLES)
	var stone_fell := count_in(sim, stone_cave.grow_individual(0, 3, 0, 0), D.RUBBLE)
	print("  stone: %d cells came down in 10 min" % stone_fell)
	check(stone_fell >= 2 and stone_fell <= 30, "a stone ceiling, a cell a minute or so")
	check(sim.particle_count() < 50, "fallen pieces land (%d still in the air)" % sim.particle_count())


func scenario_c() -> void:
	print("C. fumes sink under smoke")
	var sim = make_sim()
	var box := Rect2i(150, 480, 20, 40)
	sealed_box(sim, box)
	fill(sim, Rect2i(150, 480, 20, 20), D.FUMES)
	fill(sim, Rect2i(150, 500, 20, 20), D.SMOKE)
	for _t in 240:
		sim.step()
	var fy := mean_y(sim, box, D.FUMES)
	var sy := mean_y(sim, box, D.SMOKE)
	print("  after 4 s: fumes average row %.1f, smoke %.1f (%d fumes, %d smoke left)" % [fy, sy, sim.count(D.FUMES), sim.count(D.SMOKE)])
	check(fy > sy + 8.0, "the fumes went under the smoke")


func scenario_d() -> void:
	print("D. same result on 1 thread and on 4, with fire, blasts and debris")
	var sums := []
	var ms := []
	for n in [1, 4]:
		var sim = make_sim(n)
		fill(sim, Rect2i(20, 380, 216, 50), D.AIR)
		fill(sim, Rect2i(20, 430, 216, 10), D.COAL)
		fill(sim, Rect2i(60, 380, 30, 20), D.WATER)
		for k in 10:
			sim.ignite(30 + k * 20, 430)
		var t0 := Time.get_ticks_usec()
		for t in 900:
			if t == 100:
				sim.explode(60, 425, 6.0, 6)
			if t == 300:
				sim.explode(180, 432, 6.0, 6)
			sim.step()
			sim.weather(D.WEATHER_SAMPLES)
		ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		sums.append(sim.checksum())
		print("  %d thread(s): checksum %d, %d burning, %d particles, %.0f ms" % [n, sim.checksum(), sim.count_burning(), sim.particle_count(), ms[-1]])
	check(sums[0] == sums[1], "identical")


func scenario_e() -> void:
	print("E. coal and sulfur in the world")
	var ok_all := true
	for s in [1, 2, 3, 7, 11, 42, 99, 12345]:
		var sim = SimFactory.create(1)
		WorldGen.new().generate(sim, s)
		var cells: PackedByteArray = sim.get_cells()
		var coal := 0
		var coal_top := 0
		var sulfur := 0
		var touching := 0
		for y in range(2, D.H - 2):
			for x in range(2, D.W - 2):
				var m := cells[y * D.W + x]
				if m != D.COAL and m != D.SULFUR:
					continue
				if m == D.COAL:
					coal += 1
					if y < 300:
						coal_top += 1
				else:
					sulfur += 1
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if cells[(y + oy) * D.W + x + ox] == D.LAVA:
							touching += 1
		print("  seed %d: coal %d (%d in the Topsoil), sulfur %d, touching lava %d" % [s, coal, coal_top, sulfur, touching])
		if coal < 300 or coal_top < 60 or sulfur < 60 or touching > 0:
			ok_all = false
	check(ok_all, "every seed has coal near the top and sulfur deep down, with stone between them and lava")


func scenario_f() -> void:
	print("F. cost of a big fire and a string of blasts (4 threads)")
	var sim = make_sim(4)
	fill(sim, Rect2i(20, 380, 216, 60), D.AIR)
	fill(sim, Rect2i(20, 410, 216, 30), D.COAL)
	for k in 20:
		sim.ignite(25 + k * 10, 410)
	for _t in 1500:
		sim.step()
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	for _t in 300:
		var t1 := Time.get_ticks_usec()
		sim.step()
		worst = maxf(worst, (Time.get_ticks_usec() - t1) / 1000.0)
	var avg := (Time.get_ticks_usec() - t0) / 1000.0 / 300.0
	print("  fire: %.2f ms a tick (worst %.2f), %d burning, %d flames, %d smoke, %d updates" % [
		avg, worst, sim.count_burning(), sim.count(D.FIRE), sim.count(D.SMOKE), sim.stat_updates])
	check(avg < 4.0, "a burning seam 216 x 30 costs under 4 ms a tick")
	var sim2 = make_sim(4)
	var t2 := Time.get_ticks_usec()
	var most := 0
	for t in 600:
		if t % 20 == 0 and t < 400:
			sim2.explode(30 + int(t / 20.0) * 10, 480, 6.0, 6)
		sim2.step()
		most = maxi(most, sim2.particle_count())
	var avg2 := (Time.get_ticks_usec() - t2) / 1000.0 / 600.0
	print("  20 blasts in stone: %.2f ms a tick (blasts included), up to %d particles in the air" % [avg2, most])
	check(avg2 < 4.0, "blasts and their debris stay cheap")


# --- Game helpers -------------------------------------------------------------------

func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	game.drill.enabled = false    # the fixed Drill's banking would muddy the stock checks


func put(type: int, r: Rect2i, dir := 0) -> Object:
	var why: String = game.check_place(type, r)
	if why != "":
		print("  !! can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		fails += 1
		return null
	return game.place(type, r, dir)


## Place and wait (up to 10 s) until it's built.
func build(type: int, r: Rect2i, dir := 0) -> Object:
	var b = put(type, r, dir)
	if b == null:
		return null
	for _i in 600:
		if b.built:
			break
		game.run_ticks(1)
	game.run_ticks(2)
	return b


func gfill(r: Rect2i, m: int) -> void:
	fill(game.sim, r, m)


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


# --- Game scenarios -----------------------------------------------------------------

func scenario_g() -> void:
	print("G. digging coal banks Stone and Power")
	fresh()
	var dr = game.drill
	gfill(Rect2i(dr.x, 40, 3, 14), D.COAL)
	dr.enabled = true
	game.set_reach_limit(dr, 12)
	game.levels["drill_bit"] = 2   # the plain fixed Drill is slow; this only wants the banking
	var stone0: float = game.stock[D.R_STONE]
	# Let the Hub's store sit at its cap, where it stops making power: anything
	# above it came out of the coal.
	game.stock[D.R_POWER] = D.HUB_POWER_CAP
	for _i in 60:
		secs(1.0)
		if dr.cells_bored >= 36:
			break
	secs(1.0)
	print("  drill bored %d coal cells; Stone %.1f -> %.1f, Power %.1f (cap %d)" % [dr.cells_bored, stone0, game.stock[D.R_STONE], game.stock[D.R_POWER], int(D.HUB_POWER_CAP)])
	check(dr.cells_bored >= 36, "the drill cut its channel through the coal")
	check(game.stock[D.R_STONE] >= stone0 + 5.0, "Stone banked")
	check(game.stock[D.R_POWER] > D.HUB_POWER_CAP + 2.0, "Power banked on top of the Hub's cap: coal pays for its digging")


func scenario_h() -> void:
	print("H. sulfur corrodes a Conduit, and a Stone patches it up")
	fresh()
	var c = build(D.B_CONDUIT, Rect2i(140, 38, 2, 2))
	if c == null:
		return
	gfill(Rect2i(136, 40, 10, 3), D.SULFUR)
	var lowest := 100.0
	var patched := false
	var stone0: float = game.stock[D.R_STONE]
	var last: float = c.hp
	for _i in 900:
		game.run_ticks(6)
		if c.dead:
			break
		lowest = minf(lowest, c.hp)
		if c.hp > last + 1.0:
			patched = true
		last = c.hp
	print("  after 90 s: HP %.0f (lowest %.0f), Stone %.1f -> %.1f" % [c.hp, lowest, stone0, game.stock[D.R_STONE]])
	check(lowest < 70.0, "the sulfur ate into it")
	check(patched, "a Stone arrived and patched it up")
	check(not c.dead, "it's still standing")


func scenario_i() -> void:
	print("I. a fire under a link: patched while there's Stone, broken when there isn't, mended after")
	fresh()
	var c1 = build(D.B_CONDUIT, Rect2i(136, 38, 2, 2))
	var c2 = build(D.B_CONDUIT, Rect2i(149, 38, 2, 2))
	if c1 == null or c2 == null:
		return
	check(c2.connected and c2.link == c1, "the second Conduit links through the first")
	# A row of coal along the line between them, alight.
	var seam := Rect2i(140, 39, 8, 1)
	gfill(seam, D.COAL)
	for x in range(140, 148):
		game.sim.ignite(x, 39)
	var key: int = game._link_key(c1, c2)
	var lowest := D.LINK_HP
	var patched := false
	var last := D.LINK_HP
	for _i in 100:
		game.run_ticks(6)
		var hp: float = game.link_health(c1, c2) * D.LINK_HP
		lowest = minf(lowest, hp)
		if hp > last + 1.0:
			patched = true
		last = hp
	check(lowest < D.LINK_HP * 0.6 and patched and not game.broken_links.has(key),
			"with Stone in hand the worn link is patched before it breaks (lowest %.0f HP)" % lowest)
	# No Stone to patch it with: it breaks.
	game.stock[D.R_STONE] = 0.0
	var broke_at := -1.0
	for i in 300:
		game.run_ticks(6)
		if game.broken_links.has(key):
			broke_at = i * 0.1
			break
	check(broke_at >= 0.0, "with none, it broke (after %.1f s)" % broke_at)
	game.run_ticks(4)
	check(not c2.connected, "and the far Conduit is cut off")
	# Put the fire out and bring Stone back.
	gfill(seam, D.AIR)
	game.stock[D.R_STONE] = 10.0
	var mended := -1.0
	for i in 300:
		game.run_ticks(6)
		if not game.broken_links.has(key) and c2.connected:
			mended = i * 0.1
			break
	check(mended >= 0.0, "a Stone mended it (%.1f s later) and the far Conduit is back" % mended)


func scenario_j() -> void:
	print("J. a blast's debris falls into a Hopper")
	fresh()
	var shaft := Rect2i(150, 40, 11, 30)
	gfill(Rect2i(147, 40, 17, 33), D.DIRT)   # plain dirt walls: none of the seed's sand pours in
	gfill(shaft, D.AIR)
	var c1 = build(D.B_CONDUIT, Rect2i(142, 38, 2, 2))
	var c2 = build(D.B_CONDUIT, Rect2i(150, 48, 2, 2))
	var c3 = build(D.B_CONDUIT, Rect2i(150, 62, 2, 2))
	var hop = build(D.B_HOPPER, Rect2i(154, 68, 3, 2))
	if c1 == null or c2 == null or c3 == null or hop == null:
		return
	# A stone funnel down to the Hopper's mouth, and a stone plug up the shaft.
	for k in 4:
		gfill(Rect2i(150, 67 - k, 4 - k, 1), D.STONE)
		gfill(Rect2i(157 + k, 67 - k, 4 - k, 1), D.STONE)
	gfill(Rect2i(150, 68, 4, 2), D.STONE)
	gfill(Rect2i(157, 68, 4, 2), D.STONE)
	gfill(Rect2i(152, 50, 9, 6), D.STONE)
	var stone0: float = game.stock[D.R_STONE]
	var taken0: int = hop.cells_taken
	var broke: int = game.blast(Vector2i(156, 53), D.BLAST_RADIUS, D.BLAST_POWER)
	var flying: int = game.sim.particle_count()
	secs(12.0)
	print("  blast broke %d cells, %d flew; the Hopper took %d; Stone %.1f -> %.1f" % [broke, flying, hop.cells_taken - taken0, stone0, game.stock[D.R_STONE]])
	check(broke > 30, "the blast broke the shaft wall")
	check(flying > 0, "debris flew")
	check(hop.cells_taken - taken0 >= 15, "the Hopper swallowed the debris")
	# Ash is worth nothing, but a Hopper still clears it.
	var taken1: int = hop.cells_taken
	var stone1: float = game.stock[D.R_STONE]
	gfill(Rect2i(154, 60, 3, 3), D.ASH)
	secs(3.0)
	check(hop.cells_taken - taken1 >= 9, "and clears ash (%d cells), for nothing" % (hop.cells_taken - taken1))
	check(game.stock[D.R_STONE] - stone1 < 0.9, "ash banks nothing")
