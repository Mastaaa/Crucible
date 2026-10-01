extends SceneTree
## A2: the wave 1 materials, one lab bench demonstration each (claude/WAVE1_MATERIALS.md).
##  Sim only, on bench sims (an open room, flat 20 degrees, floor at FL):
##   1. Slick fire on Water, snuffed by Hush
##   2. Sourwater on Stone, Ferrite and Glass
##   3. Quickmire on Sand, with and without Flux
##   4. Flux speeds Coal chunks (and stays unspent)
##   5. Ferrite smelted with Flux to Slag and bars (rigid bodies)
##   6. Rattle by fall, heat, fire and chain; Hush holds it back
##   7. Bloat soaks Water, Slick and Sourwater and bursts each into its own plume
##   8. Sand + Lava makes Glass; Glass shatters to Sand as a body
##   9. Rime freezes Water and quenches Lava, and is used up doing it
##  10. Wisp flashes; Hush and Rime undo it
##  11. Weft spreads where there is water, and stops for Rime, Hush and fire
##  12. Everything in one basin: 1 and 4 threads agree
## Run: godot --headless --path . --script tests/scenario_wave1.gd

const D = preload("res://scripts/defs.gd")
const Mats = preload("res://scripts/materials.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")

const FL := 900          # the bench's floor row: open air above it
const ALL := Rect2i(2, 400, 764, 500)

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
		scenario_1()
		scenario_2()
		scenario_3()
		scenario_4()
		scenario_5()
		scenario_6()
		scenario_7()
		scenario_8()
		scenario_9()
		scenario_10()
		scenario_11()
		scenario_12()
		print("FAILURES: %d" % fails)
		return true
	return false


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


# --- Helpers ---------------------------------------------------------------------------

func bench_sim(threads := 1):
	var sim = SimFactory.create(threads)
	sim.set_ambient(D.ambient_rows(D.BENCH_AMBIENT))
	WorldGen.new().bench(sim)
	return sim


func fill(sim, r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			sim.set_cell(x, y, m)


## Bedrock walls round x .. x + w - 1 up to height h, so a liquid stays in a pool.
func walls(sim, x: int, w: int, h: int) -> void:
	fill(sim, Rect2i(x - 2, FL - h, 2, h), D.BEDROCK)
	fill(sim, Rect2i(x + w, FL - h, 2, h), D.BEDROCK)


## A row of the basin's rectangle `r` from the bottom: height h of m.
func pile(sim, x: int, w: int, h: int, m: int) -> Rect2i:
	var r := Rect2i(x, FL - h, w, h)
	fill(sim, r, m)
	return r


func count(sim, m: int, r := ALL) -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	mask[m] = 1
	return sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)


func steam(sim, r := ALL) -> int:
	var n := 0
	for m in range(D.STEAM, D.STEAM_LAST + 1):
		n += count(sim, m, r)
	return n


func run(sim, ticks: int) -> void:
	for _i in ticks:
		sim.step()


## Ticks until `done.call()` holds, or `limit`.
func until(sim, limit: int, done: Callable) -> int:
	for t in limit:
		sim.step()
		if done.call():
			return t + 1
	return limit


# --- The twelve --------------------------------------------------------------------------

func scenario_1() -> void:
	print("1. Slick fire on Water, snuffed by Hush")
	var sim = bench_sim()
	walls(sim, 100, 60, 60)
	pile(sim, 100, 60, 10, D.WATER)
	fill(sim, Rect2i(100, FL - 12, 60, 2), D.SLICK)
	var before := count(sim, D.SLICK)
	sim.ignite(101, FL - 12)
	run(sim, 60)
	check(sim.count_burning() > 0, "a lit film burns on the water (%d cells alight)" % sim.count_burning())
	run(sim, 2400)
	var left := count(sim, D.SLICK)
	check(left * 2 < before, "the flame crawls over the film and burns it off (%d of %d cells left)" % [left, before])
	sim = bench_sim()
	walls(sim, 100, 60, 60)
	pile(sim, 100, 60, 10, D.WATER)
	fill(sim, Rect2i(100, FL - 12, 60, 2), D.SLICK)
	sim.ignite(101, FL - 12)
	run(sim, 30)
	fill(sim, Rect2i(100, FL - 40, 60, 28), D.HUSH)
	run(sim, 2400)
	var snuffed := count(sim, D.SLICK)
	check(sim.count_burning() == 0 and snuffed > left + 40, "Hush above puts it out (%d cells saved, %d without)" % [snuffed, left])


func scenario_2() -> void:
	print("2. Sourwater on Stone, Ferrite and Glass")
	var sim = bench_sim()
	pile(sim, 100, 60, 6, D.STONE)
	fill(sim, Rect2i(100, FL - 26, 60, 20), D.SOURWATER)
	run(sim, 600)
	check(count(sim, D.RUBBLE) > 10 and count(sim, D.STONE) < 360, "Stone pits to Rubble (%d cells)" % count(sim, D.RUBBLE))
	check(count(sim, D.WATER) > 10, "the acid spends into Water doing it (%d)" % count(sim, D.WATER))
	sim = bench_sim()
	pile(sim, 100, 60, 6, D.FERRITE)
	fill(sim, Rect2i(100, FL - 26, 60, 20), D.SOURWATER)
	var saw_wisp := 0
	for _t in 300:
		sim.step()
		saw_wisp = maxi(saw_wisp, count(sim, D.WISP) + sim.get_blasts())
	check(saw_wisp > 0, "Ferrite bubbles off Wisp (%d)" % saw_wisp)
	check(count(sim, D.RUBBLE) > 0, "and wears to Rubble (%d)" % count(sim, D.RUBBLE))
	sim = bench_sim()
	pile(sim, 100, 60, 6, D.GLASS)
	fill(sim, Rect2i(100, FL - 26, 60, 20), D.SOURWATER)
	run(sim, 600)
	check(count(sim, D.GLASS) == 360 and count(sim, D.SOURWATER) == 1200, "Glass takes no harm and the acid keeps")


func scenario_3() -> void:
	print("3. Quickmire on Sand, with and without Flux")
	var plain := _set_time(false)
	var with_flux := _set_time(true)
	check(plain > 200 and plain < 1200, "sand sets into Mire stone in about %.0f seconds" % (plain / 60.0))
	check(with_flux < plain * 0.7, "Flux in the pile sets it sooner (%.1f s against %.1f s)" % [with_flux / 60.0, plain / 60.0])
	var sim = bench_sim()
	pile(sim, 100, 60, 10, D.SAND)
	fill(sim, Rect2i(110, FL - 16, 40, 6), D.QUICKMIRE)
	run(sim, 1500)
	check(count(sim, D.SAND) == 0 and count(sim, D.QUICKMIRE) <= 3, "the whole pile binds (sand %d, quickmire %d left)" % [count(sim, D.SAND), count(sim, D.QUICKMIRE)])
	check(count(sim, D.MIRE_STONE) > 700, "into %d cells of Mire stone" % count(sim, D.MIRE_STONE))
	sim.heat_rect(100, FL - 20, 60, 20, 500)
	run(sim, 120)
	check(count(sim, D.MIRE_STONE) < 100, "heat past 450 breaks it back to Rubble (%d stone, %d rubble)" % [count(sim, D.MIRE_STONE), count(sim, D.RUBBLE)])


## Ticks until a sand pile (a third of it Flux if `flux`) with Quickmire on top has 60 cells of Mire stone.
func _set_time(flux: bool) -> int:
	var sim = bench_sim()
	pile(sim, 100, 60, 10, D.SAND)
	if flux:
		for y in range(FL - 10, FL):
			for x in range(100 + (y % 3), 160, 3):
				sim.set_cell(x, y, D.FLUX)
	fill(sim, Rect2i(110, FL - 16, 40, 6), D.QUICKMIRE)
	return until(sim, 2400, func(): return count(sim, D.MIRE_STONE) >= 60)


func scenario_4() -> void:
	print("4. Flux speeds Coal chunks and is not used up")
	var plain := _burn_time(false)
	var with_flux := _burn_time(true)
	check(with_flux < plain * 0.7, "a pile with Flux burns out sooner (%.1f s against %.1f s)" % [with_flux / 60.0, plain / 60.0])
	var sim = bench_sim()
	fill(sim, Rect2i(100, FL - 10, 20, 10), D.COAL_CHUNKS)
	fill(sim, Rect2i(120, FL - 10, 10, 10), D.FLUX)
	sim.ignite(105, FL - 10)
	run(sim, 3000)
	check(count(sim, D.FLUX) == 100, "the Flux is all still there (%d of 100)" % count(sim, D.FLUX))


func _burn_time(flux: bool) -> int:
	var sim = bench_sim()
	fill(sim, Rect2i(100, FL - 10, 20, 10), D.COAL_CHUNKS)
	if flux:
		for y in range(FL - 10, FL):
			for x in range(100 + (y % 2), 120, 2):
				sim.set_cell(x, y, D.FLUX)
	sim.ignite(105, FL - 10)
	for x in range(100, 120, 4):
		sim.ignite(x, FL - 1)
	run(sim, 5)
	return 5 + until(sim, 4000, func(): return sim.count_burning() == 0)


func scenario_5() -> void:
	print("5. Ferrite, Flux and heat: Slag and bars")
	var sim = bench_sim()
	pile(sim, 100, 40, 8, D.FERRITE)
	fill(sim, Rect2i(100, FL - 15, 40, 7), D.FLUX)
	sim.heat_rect(100, FL - 15, 40, 15, 900)
	run(sim, 300)
	check(count(sim, D.SLAG) + count(sim, D.SLAG_CRUST) > 30, "smelting turns Ferrite to Slag (%d liquid, %d crust)" % [count(sim, D.SLAG), count(sim, D.SLAG_CRUST)])
	check(sim.get_forged() >= 1, "bars are forged as rigid bodies (%d)" % sim.get_forged())
	run(sim, 600)
	check(count(sim, D.FERRITE_BAR) >= 6, "and lie as Ferrite bars once they stop (%d cells)" % count(sim, D.FERRITE_BAR))
	check(count(sim, D.FLUX) > 150, "the Flux isn't used up (%d cells)" % count(sim, D.FLUX))
	sim = bench_sim()
	pile(sim, 100, 40, 8, D.FERRITE)
	run(sim, 600)
	check(count(sim, D.SLAG) == 0 and sim.get_forged() == 0, "Ferrite without Flux or heat stays Ferrite")


func scenario_6() -> void:
	print("6. Rattle: fall, heat, fire and chain")
	var sim = bench_sim()
	sim.set_cell(200, FL - 10, D.RATTLE)
	run(sim, 100)
	check(sim.get_blasts() == 0 and count(sim, D.RATTLE) == 1, "a short drop doesn't set it off")
	sim = bench_sim()
	sim.set_cell(200, FL - 50, D.RATTLE)
	run(sim, 200)
	check(sim.get_blasts() == 1 and count(sim, D.RATTLE) == 0, "a long one does")
	sim = bench_sim()
	pile(sim, 200, 1, 1, D.RATTLE)
	sim.heat_rect(200, FL - 1, 1, 1, 150)
	run(sim, 60)
	check(sim.get_blasts() == 1, "a cell heated past 140 degrees goes off")
	sim = bench_sim()
	pile(sim, 200, 1, 1, D.RATTLE)
	sim.set_cell(201, FL - 1, D.FIRE)
	run(sim, 30)
	check(sim.get_blasts() == 1, "fire beside it sets it off")
	sim = bench_sim()
	pile(sim, 200, 14, 1, D.RATTLE)
	sim.heat_rect(200, FL - 1, 1, 1, 150)
	run(sim, 200)
	check(sim.get_blasts() == 14 and count(sim, D.RATTLE) == 0, "a row of fourteen goes off as a chain (%d blasts)" % sim.get_blasts())
	sim = bench_sim()
	pile(sim, 200, 14, 1, D.RATTLE)
	fill(sim, Rect2i(198, FL - 12, 18, 11), D.HUSH)
	sim.heat_rect(200, FL - 1, 14, 1, 150)
	run(sim, 100)
	check(sim.get_blasts() == 0 and count(sim, D.RATTLE) == 14, "under a layer of Hush a heated row won't go off (%d blasts)" % sim.get_blasts())


func scenario_7() -> void:
	print("7. Bloat soaks Water, Slick and Sourwater and bursts each")
	var plumes := {D.WATER: "steam", D.SLICK: "fire", D.SOURWATER: "fumes"}
	for liquid in plumes:
		var sim = bench_sim()
		fill(sim, Rect2i(100, FL - 20, 20, 20), liquid)
		var bloat := Rect2i(100, FL - 40, 20, 12)
		fill(sim, bloat, D.BLOAT)
		var dry := count(sim, D.BLOAT)
		run(sim, 400)
		var swollen := count(sim, D.SWOLLEN_BLOAT)
		check(swollen > dry and count(sim, D.BLOAT) < dry,
				"Bloat soaks %s and swells (%d cells from %d)" % [Mats.name_of(liquid), swollen, dry])
		sim.heat_rect(95, FL - 70, 40, 70, 160)
		var seen := 0
		for _t in 90:
			sim.step()
			match plumes[liquid]:
				"steam": seen = maxi(seen, steam(sim))
				"fire": seen = maxi(seen, count(sim, D.FIRE) + sim.count_burning())
				"fumes": seen = maxi(seen, count(sim, D.FUMES))
		check(seen > 0 and count(sim, D.SWOLLEN_BLOAT) * 3 < swollen, "heat bursts it into %s (%d seen, %d swollen left)" % [plumes[liquid], seen, count(sim, D.SWOLLEN_BLOAT)])
	var sim2 = bench_sim()
	pile(sim2, 100, 20, 6, D.BLOAT)
	sim2.heat_rect(100, FL - 6, 20, 6, 200)
	run(sim2, 1800)
	check(count(sim2, D.ASH) > 0, "dry Bloat just burns to Ash (%d)" % count(sim2, D.ASH))


func scenario_8() -> void:
	print("8. Sand + Lava makes Glass; Glass breaks to Sand")
	var sim = bench_sim()
	pile(sim, 100, 40, 20, D.SAND)
	pile(sim, 140, 40, 20, D.LAVA)
	run(sim, 600)
	check(count(sim, D.GLASS) > 20, "a clear seam forms where they meet (%d cells)" % count(sim, D.GLASS))
	# A slab dropped from height breaks.
	sim = bench_sim()
	fill(sim, Rect2i(100, FL - 120, 24, 8), D.GLASS)
	check(sim.make_body(100, FL - 120, 24, 8, 0.0, 0.0, 0.0) >= 0, "a slab of Glass becomes a body")
	run(sim, 240)
	check(count(sim, D.GLASS) < 96 and count(sim, D.SAND) > 20, "a hard fall shatters it to Sand (%d Glass, %d Sand)" % [count(sim, D.GLASS), count(sim, D.SAND)])


func scenario_9() -> void:
	print("9. Rime freezes Water and quenches Lava")
	var sim = bench_sim()
	pile(sim, 100, 20, 12, D.WATER)
	pile(sim, 120, 6, 12, D.RIME)
	run(sim, 600)
	check(count(sim, D.ICE) > 10, "Water beside Rime freezes to Ice (%d cells)" % count(sim, D.ICE))
	check(count(sim, D.RIME) > 60, "and the Rime lasts (%d of 72 cells)" % count(sim, D.RIME))
	sim = bench_sim()
	pile(sim, 100, 6, 12, D.RIME)
	pile(sim, 106, 20, 12, D.LAVA)
	var rime := count(sim, D.RIME)
	run(sim, 600)
	check(count(sim, D.OBSIDIAN) > 10, "Lava beside Rime quenches to Obsidian (%d cells)" % count(sim, D.OBSIDIAN))
	check(count(sim, D.RIME) < rime, "and the Rime is used up as it does (%d of %d left)" % [count(sim, D.RIME), rime])
	sim = bench_sim()
	pile(sim, 100, 6, 6, D.RIME)
	run(sim, 1800)
	check(count(sim, D.RIME) == 36, "on its own in open air Rime keeps for half a minute")


func scenario_10() -> void:
	print("10. Wisp flashes; Hush and Rime undo it")
	var sim = bench_sim()
	fill(sim, Rect2i(100, FL - 40, 20, 20), D.WISP)
	sim.set_cell(110, FL - 30, D.FIRE)
	run(sim, 120)
	check(sim.get_blasts() > 300 and count(sim, D.WISP) < 5, "a spark flashes the whole cloud (%d blasts)" % sim.get_blasts())
	sim = bench_sim()
	for y in range(FL - 40, FL - 20):
		for x in range(100, 120):
			sim.set_cell(x, y, D.WISP if (x + y) % 2 == 0 else D.HUSH)
	var cloud := count(sim, D.WISP)
	run(sim, 200)
	check(count(sim, D.WISP) * 2 < cloud and sim.get_blasts() == 0, "Hush and Wisp cancel (%d cells left of %d)" % [count(sim, D.WISP), cloud])
	sim = bench_sim()
	fill(sim, Rect2i(100, FL - 20, 20, 20), D.WISP)
	pile(sim, 100, 20, 2, D.RIME)
	run(sim, 600)
	check(count(sim, D.SLICK) > 0, "a Wisp cloud over Rime rains Slick (%d cells)" % count(sim, D.SLICK))


func scenario_11() -> void:
	print("11. Weft spreads, then stops for Rime, Hush and fire")
	var sim = bench_sim()
	pile(sim, 100, 60, 20, D.DIRT)
	fill(sim, Rect2i(112, FL - 23, 3, 3), D.WATER)
	sim.set_cell(110, FL - 21, D.WEFT)
	sim.set_cell(111, FL - 21, D.WEFT)
	run(sim, 1800)
	var grown := count(sim, D.WEFT)
	check(grown > 6 and count(sim, D.WATER) < 9, "it eats sideways and drinks (%d cells, %d water left)" % [grown, count(sim, D.WATER)])
	sim = bench_sim()
	pile(sim, 100, 60, 20, D.DIRT)
	fill(sim, Rect2i(112, FL - 23, 3, 3), D.WATER)
	sim.set_cell(110, FL - 21, D.WEFT)
	sim.set_cell(111, FL - 21, D.WEFT)
	pile(sim, 100, 2, 1, D.RIME)
	fill(sim, Rect2i(104, FL - 22, 12, 4), D.RIME)
	run(sim, 600)
	check(count(sim, D.WEFT) <= 2, "Rime goes round it and it goes dormant (%d cells)" % count(sim, D.WEFT))
	sim = bench_sim()
	pile(sim, 100, 60, 20, D.DIRT)
	fill(sim, Rect2i(106, FL - 30, 14, 10), D.HUSH)
	for x in range(108, 116):
		sim.set_cell(x, FL - 21, D.WEFT)
	run(sim, 600)
	check(count(sim, D.WEFT) < 8 and count(sim, D.ASH) > 0, "Hush withers it to Ash (%d cells left, %d Ash)" % [count(sim, D.WEFT), count(sim, D.ASH)])
	sim = bench_sim()
	pile(sim, 100, 60, 20, D.DIRT)
	for x in range(108, 116):
		sim.set_cell(x, FL - 21, D.WEFT)
	sim.ignite(108, FL - 21)
	run(sim, 900)
	check(count(sim, D.WEFT) < 8, "fire burns a patch out (%d cells left)" % count(sim, D.WEFT))


func scenario_12() -> void:
	print("12. Everything in one basin")
	var a = _basin(1)
	var b = _basin(4)
	var kinds := 0
	for m in range(D.SLICK, D.FERRITE_BAR + 1):
		if count(a, m) > 0:
			kinds += 1
	print("  %d of %d wave 1 materials still present after a minute; %d blasts, %d bars forged" % [kinds, D.FERRITE_BAR - D.SLICK + 1, a.get_blasts(), a.get_forged()])
	check(kinds >= 8, "the basin is still a mix a minute on")
	check(a.checksum() == b.checksum(), "one thread and four agree on every cell")


func _basin(threads: int):
	var sim = bench_sim(threads)
	sim.set_seed(5)
	var order := [D.SLICK, D.SOURWATER, D.HUSH, D.QUICKMIRE, D.FLUX, D.FERRITE, D.RATTLE, D.BLOAT, D.GLASS, D.RIME, D.WISP, D.WEFT, D.SAND, D.WATER, D.LAVA, D.DIRT]
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for y in range(FL - 60, FL):
		for x in range(100, 220):
			if rng.randf() < 0.5:
				sim.set_cell(x, y, order[rng.randi() % order.size()])
	run(sim, 3600)
	return sim
