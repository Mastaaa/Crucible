extends SceneTree
## A5 part 3: the wave 2 materials (claude/WAVE2_MATERIALS.md). Sim-only bench scenarios first (an open
## room, flat 20 degrees, floor at FL), then the machines that make and use them, on seed 7:
##   1. Brine boils to Steam and Salt, and freezes to Chillant far below where Water does
##   2. Salt melts Ice, dissolves in Water and withers Weft
##   3. Lye neutralises Sourwater and Gall, scrubs Chlor, dissolves a Slick film
##   4. Chlor sinks and pools, eats Ferrite, turns Water to Sourwater
##   5. Lift rises and flashes
##   6. Slick distils to Smoke and Pitch; cold sets Pitch
##   7. Chillant ices Water and quenches Lava
##   8. Filings burn to Slag; a Ferrite bar grinds to Filings
##   9. Veinstone and Flux smelt to Slag and Wire
##  10. Gall eats faster than Sourwater, and wears Obsidian and Glass but not Glimmer or Lumen
##  11. Vitriol is quiet dry and turns to Gall wet
##  12. the Boiler, Chiller and Furnace leave Salt, Chillant and Wire; the Electrolyser splits Brine and Water;
##      the Combustor burns Lift and Pitch; casing wear weighs the acids
## Run: godot --headless --path . --script tests/scenario_wave2.gd

# A6: the world is 1024 wide and the Hub moved from x 384 to 512, so every bench x below is the old one plus 128.
const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
const CS = preload("res://scripts/machines/casing.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")

const FL := 900          # the bench's floor row: open air above it
const ALL := Rect2i(2, 400, 764, 500)
const SURFACE := 200     # ground level in the machine scenarios
const TECHS := ["boiler", "chiller", "furnace", "electrolyser", "combustor", "pump"]
const TX := 396          # the feed Tank's left edge in a rig: the machine plugged into its side stays inside the cleared arena

var game: Node
var f := 0
var fails := 0
var I := {}              # material name -> id


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		if not SimFactory.native_available() or game.sim.get_script() != null:
			print("The C++ sim isn't loaded: these need it.")
			print("FAILURES: 1")
			return true
		for nm: String in ["Brine", "Salt", "Lye", "Chlor", "Lift", "Pitch", "Chillant", "Filings", "Veinstone", "Lumen", "Gall",
				"Vitriol", "Pitch stone", "Wire", "Vitriol grit", "Water", "Ice", "Steam", "Sourwater", "Stone", "Rubble", "Slick",
				"Smoke", "Ferrite", "Ferrite bar", "Flux", "Slag", "Slag crust", "Obsidian", "Glass", "Glimmer", "Lava", "Sand",
				"Weft", "Ash", "Dirt", "Fire", "Hush"]:
			I[nm] = M.id_of(nm)
			if I[nm] < 0:
				check(false, "material %s exists" % nm)
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


# --- Bench helpers -------------------------------------------------------------------------

func bench_sim():
	var sim = SimFactory.create(1)
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


func pile(sim, x: int, w: int, h: int, m: int) -> Rect2i:
	var r := Rect2i(x, FL - h, w, h)
	fill(sim, r, m)
	return r


func count(sim, m: int, r := ALL) -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	mask[m] = 1
	return sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)


func steam(sim) -> int:
	var n := 0
	for m in range(D.STEAM, D.STEAM_LAST + 1):
		n += count(sim, m)
	return n


func run(sim, ticks: int) -> void:
	for _i in ticks:
		sim.step()


# --- The bench ------------------------------------------------------------------------------

func scenario_1() -> void:
	print("1. Brine boils to Steam and Salt, and freezes far colder than Water")
	var sim = bench_sim()
	walls(sim, 100, 60, 60)
	pile(sim, 100, 60, 10, I["Brine"])
	sim.heat_rect(100, FL - 10, 60, 10, 110)
	var seen := 0
	for _t in 240:
		sim.step()
		seen = maxi(seen, steam(sim))
	check(count(sim, I["Salt"]) > 20 and seen > 20, "a heated pool leaves Salt (%d cells) and gives off Steam (%d seen)" % [count(sim, I["Salt"]), seen])
	check(count(sim, I["Brine"]) < 600, "and the pool shrinks (%d of 600 left)" % count(sim, I["Brine"]))
	sim = bench_sim()
	walls(sim, 100, 60, 60)
	pile(sim, 100, 28, 10, I["Water"])
	pile(sim, 130, 28, 10, I["Brine"])
	sim.heat_rect(100, FL - 10, 60, 10, -25)
	run(sim, 120)
	check(count(sim, I["Ice"]) > 100, "at -5 degrees Water freezes to Ice (%d cells)" % count(sim, I["Ice"]))
	check(count(sim, I["Brine"]) > 200 and count(sim, I["Chillant"]) == 0, "and Brine does not (%d Brine)" % count(sim, I["Brine"]))
	sim.heat_rect(100, FL - 10, 60, 10, -25)
	run(sim, 60)
	check(count(sim, I["Chillant"]) > 100, "at -30 it turns to Chillant (%d cells)" % count(sim, I["Chillant"]))


func scenario_2() -> void:
	print("2. Salt melts Ice, dissolves in Water and withers Weft")
	var sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 6, I["Ice"])
	fill(sim, Rect2i(100, FL - 10, 40, 4), I["Salt"])
	run(sim, 1200)
	check(count(sim, I["Brine"]) > 20, "Salt on Ice makes Brine (%d cells)" % count(sim, I["Brine"]))
	sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 10, I["Water"])
	fill(sim, Rect2i(100, FL - 20, 40, 4), I["Salt"])
	run(sim, 1200)
	check(count(sim, I["Brine"]) > 20 and count(sim, I["Salt"]) < 160, "Salt dropped into Water dissolves into Brine (%d Brine, %d Salt left)" % [count(sim, I["Brine"]), count(sim, I["Salt"])])
	sim = bench_sim()
	pile(sim, 100, 30, 10, I["Dirt"])
	fill(sim, Rect2i(100, FL - 11, 30, 1), I["Weft"])
	fill(sim, Rect2i(100, FL - 12, 30, 1), I["Salt"])
	run(sim, 600)
	check(count(sim, I["Weft"]) < 15, "Salt on a Weft row kills it (%d of 30 left)" % count(sim, I["Weft"]))


func scenario_3() -> void:
	print("3. Lye meets acid, Chlor and oil")
	var sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 8, I["Sourwater"])
	fill(sim, Rect2i(100, FL - 16, 40, 8), I["Lye"])
	run(sim, 600)
	check(count(sim, I["Brine"]) > 100 and count(sim, I["Sourwater"]) < 160, "Lye over Sourwater makes Brine (%d Brine, %d Sourwater left)" % [count(sim, I["Brine"]), count(sim, I["Sourwater"])])
	sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 8, I["Gall"])
	fill(sim, Rect2i(100, FL - 16, 40, 8), I["Lye"])
	run(sim, 600)
	check(count(sim, I["Brine"]) > 100 and count(sim, I["Gall"]) < 160, "and over Gall (%d Brine, %d Gall left)" % [count(sim, I["Brine"]), count(sim, I["Gall"])])
	sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 6, I["Lye"])
	fill(sim, Rect2i(100, FL - 20, 40, 10), I["Chlor"])
	var before := count(sim, I["Chlor"])
	run(sim, 600)
	check(count(sim, I["Chlor"]) * 2 < before and count(sim, I["Lye"]) == 240, "Lye scrubs the Chlor out of the air and is not used up (%d of %d Chlor left, %d Lye)" % [count(sim, I["Chlor"]), before, count(sim, I["Lye"])])
	sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 6, I["Lye"])
	fill(sim, Rect2i(100, FL - 8, 40, 2), I["Slick"])
	run(sim, 600)
	check(count(sim, I["Slick"]) < 60, "Lye dissolves a film of oil (%d of 80 left)" % count(sim, I["Slick"]))


func scenario_4() -> void:
	print("4. Chlor sinks, eats Ferrite, and turns Water to acid")
	var sim = bench_sim()
	walls(sim, 100, 60, 60)
	fill(sim, Rect2i(100, FL - 50, 60, 10), I["Chlor"])
	run(sim, 200)
	var low := count(sim, I["Chlor"], Rect2i(100, FL - 20, 60, 20))
	var all := count(sim, I["Chlor"])
	check(all > 100 and low * 10 >= all * 7, "it sinks to the floor (%d of %d cells in the bottom 20 rows)" % [low, all])
	sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 4, I["Ferrite"])
	fill(sim, Rect2i(100, FL - 20, 40, 16), I["Chlor"])
	run(sim, 600)
	check(count(sim, I["Rubble"]) > 10, "Chlor wears Ferrite to Rubble (%d cells)" % count(sim, I["Rubble"]))
	sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 4, I["Water"])
	fill(sim, Rect2i(100, FL - 20, 40, 16), I["Chlor"])
	run(sim, 600)
	check(count(sim, I["Sourwater"]) > 10, "Chlor in Water makes Sourwater (%d cells)" % count(sim, I["Sourwater"]))


func scenario_5() -> void:
	print("5. Lift rises and flashes")
	var sim = bench_sim()
	walls(sim, 100, 60, 120)
	fill(sim, Rect2i(100, FL - 10, 60, 10), I["Lift"])
	run(sim, 90)
	check(count(sim, I["Lift"], Rect2i(100, FL - 120, 60, 80)) > 0 or count(sim, I["Lift"]) < 600, "it climbs away from the floor and vents (%d of 600 left)" % count(sim, I["Lift"]))
	sim = bench_sim()
	fill(sim, Rect2i(100, FL - 40, 20, 20), I["Lift"])
	sim.set_cell(110, FL - 30, I["Fire"])
	run(sim, 120)
	check(sim.get_blasts() > 100 and count(sim, I["Lift"]) < 5, "a spark flashes the cloud (%d blasts)" % sim.get_blasts())


func scenario_6() -> void:
	print("6. Slick distils to Smoke and Pitch; cold sets Pitch")
	var sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 6, I["Slick"])
	sim.heat_rect(100, FL - 6, 40, 6, 110)
	var seen := 0
	for _t in 240:
		sim.step()
		seen = maxi(seen, count(sim, I["Smoke"]))
	check(count(sim, I["Pitch"]) > 20 and seen > 20, "hot Slick leaves Pitch (%d cells) and Smoke (%d seen)" % [count(sim, I["Pitch"]), seen])
	sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 6, I["Pitch"])
	run(sim, 300)
	check(count(sim, I["Pitch stone"]) == 0 and count(sim, I["Pitch"]) == 240, "Pitch at room temperature stays tar")
	sim.heat_rect(100, FL - 6, 40, 6, -25)
	run(sim, 120)
	check(count(sim, I["Pitch stone"]) > 100, "below freezing it sets to Pitch stone (%d cells)" % count(sim, I["Pitch stone"]))
	sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 6, I["Water"])
	fill(sim, Rect2i(100, FL - 12, 40, 6), I["Pitch"])
	run(sim, 600)
	check(count(sim, I["Pitch"], Rect2i(100, FL - 6, 40, 6)) > 20, "Pitch is heavier than Water and sinks through it (%d cells on the floor)" % count(sim, I["Pitch"], Rect2i(100, FL - 6, 40, 6)))


func scenario_7() -> void:
	print("7. Chillant ices Water and quenches Lava")
	var sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 20, 10, I["Water"])
	pile(sim, 120, 20, 10, I["Chillant"])
	run(sim, 600)
	check(count(sim, I["Ice"]) > 30, "Water beside Chillant freezes (%d cells of Ice)" % count(sim, I["Ice"]))
	sim = bench_sim()
	pile(sim, 100, 6, 12, I["Chillant"])
	pile(sim, 106, 20, 12, I["Lava"])
	run(sim, 600)
	check(count(sim, I["Obsidian"]) > 10, "Lava beside Chillant quenches to Obsidian (%d cells)" % count(sim, I["Obsidian"]))
	sim = bench_sim()
	walls(sim, 100, 40, 40)
	pile(sim, 100, 40, 6, I["Chillant"])
	run(sim, 1800)
	check(count(sim, I["Chillant"]) == 240, "in a room at 20 degrees it holds its cold for good (%d of 240 cells)" % count(sim, I["Chillant"]))
	sim.heat_rect(100, FL - 6, 40, 6, 60)
	run(sim, 120)
	check(count(sim, I["Brine"]) > 200, "warmed through, it wakes back into Brine (%d cells)" % count(sim, I["Brine"]))


func scenario_8() -> void:
	print("8. Filings burn to Slag; a Ferrite bar grinds to Filings")
	var sim = bench_sim()
	pile(sim, 100, 20, 6, I["Filings"])
	sim.ignite(105, FL - 6)
	for x in range(100, 120, 4):
		sim.ignite(x, FL - 1)
	run(sim, 3600)
	check(count(sim, I["Filings"]) < 70 and count(sim, I["Slag"]) + count(sim, I["Slag crust"]) > 40, "a lit pile burns fast and leaves Slag (%d of 120 Filings left, %d Slag and crust)" % [count(sim, I["Filings"]), count(sim, I["Slag"]) + count(sim, I["Slag crust"])])
	check(M.ground_of(I["Ferrite bar"]) == I["Filings"], "a Ferrite bar grinds to Filings")


func scenario_9() -> void:
	print("9. Veinstone and Flux smelt to Slag and Wire")
	var sim = bench_sim()
	pile(sim, 100, 40, 8, I["Veinstone"])
	fill(sim, Rect2i(100, FL - 15, 40, 7), I["Flux"])
	sim.heat_rect(100, FL - 15, 40, 15, 900)
	run(sim, 300)
	check(count(sim, I["Slag"]) + count(sim, I["Slag crust"]) > 30, "Veinstone smelts to Slag (%d liquid, %d crust)" % [count(sim, I["Slag"]), count(sim, I["Slag crust"])])
	check(sim.get_forged() >= 1, "and Wire is forged as rigid bodies (%d)" % sim.get_forged())
	run(sim, 600)
	check(count(sim, I["Wire"]) >= 8, "which lie as Wire once they stop (%d cells)" % count(sim, I["Wire"]))
	sim = bench_sim()
	pile(sim, 100, 40, 8, I["Veinstone"])
	run(sim, 600)
	check(count(sim, I["Slag"]) == 0 and sim.get_forged() == 0, "Veinstone without Flux or heat stays Veinstone")


func scenario_10() -> void:
	print("10. Gall against Sourwater, Obsidian, Glass, Glimmer and Lumen")
	var rubble := {}
	for acid in ["Sourwater", "Gall"]:
		var sim = bench_sim()
		pile(sim, 100, 60, 6, I["Stone"])
		fill(sim, Rect2i(100, FL - 26, 60, 20), I[acid])
		run(sim, 90)
		rubble[acid] = count(sim, I["Rubble"])
	check(rubble["Gall"] > 20 and rubble["Gall"] * 10 >= rubble["Sourwater"] * 14, "Gall pits Stone faster than Sourwater in the first second and a half (%d Rubble against %d)" % [rubble["Gall"], rubble["Sourwater"]])
	for hard in ["Obsidian", "Glass"]:
		var sim = bench_sim()
		pile(sim, 100, 60, 6, I[hard])
		fill(sim, Rect2i(100, FL - 26, 60, 20), I["Gall"])
		run(sim, 1800)
		var worn: int = 360 - count(sim, I[hard])
		check(worn > 0 and worn < 120, "Gall wears %s, slowly (%d of 360 cells gone)" % [hard, worn])
	for safe in ["Glimmer", "Lumen", "Vitriol"]:
		var sim = bench_sim()
		pile(sim, 100, 60, 6, I[safe])
		fill(sim, Rect2i(100, FL - 26, 60, 20), I["Gall"])
		run(sim, 1200)
		check(count(sim, I[safe]) == 360, "%s takes no harm from it" % safe)
	var ferrite_sim = bench_sim()
	pile(ferrite_sim, 100, 60, 6, I["Ferrite"])
	fill(ferrite_sim, Rect2i(100, FL - 26, 60, 20), I["Gall"])
	run(ferrite_sim, 600)
	check(count(ferrite_sim, I["Rubble"]) > 20, "Gall eats Ferrite (%d Rubble)" % count(ferrite_sim, I["Rubble"]))
	check(CS.PLATING_STRONG > 0.0 and M.acid_of(I["Gall"]) == 2.0 and M.acid_of(I["Sourwater"]) == 1.0 and M.acid_of(I["Stone"]) == 0.0, "the acid strengths are in the data")


func scenario_11() -> void:
	print("11. Vitriol is quiet dry and turns to Gall wet")
	var sim = bench_sim()
	pile(sim, 100, 30, 6, I["Vitriol"])
	run(sim, 900)
	check(count(sim, I["Vitriol"]) == 180 and count(sim, I["Gall"]) == 0, "dry Vitriol just sits")
	walls(sim, 100, 30, 40)
	fill(sim, Rect2i(100, FL - 14, 30, 8), I["Water"])
	run(sim, 900)
	check(count(sim, I["Gall"]) > 20 and count(sim, I["Vitriol"]) < 180, "Water on it makes Gall (%d Gall, %d Vitriol left)" % [count(sim, I["Gall"]), count(sim, I["Vitriol"])])
	sim = bench_sim()
	walls(sim, 100, 30, 40)
	pile(sim, 100, 30, 4, I["Vitriol grit"])
	fill(sim, Rect2i(100, FL - 14, 30, 10), I["Water"])
	run(sim, 600)
	check(count(sim, I["Gall"]) > 20, "so does the grit it breaks into (%d Gall)" % count(sim, I["Gall"]))


# --- The machines ---------------------------------------------------------------------------

func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


func gfill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	MC.ensure_defs()
	gfill(Rect2i(328, SURFACE - 120, 200, 120), D.AIR)
	gfill(Rect2i(328, SURFACE, 200, 160), I["Dirt"])
	gfill(Rect2i(328, SURFACE + 160, 200, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0
	for t: String in TECHS:
		game.researched[t] = true


func place(def: String, x: int, y: int, turns: int = 0) -> int:
	var id := MC.place(game, def, Vector2i(x, y), turns)
	if id == 0:
		print("  !! can't place %s at %d,%d: %s" % [def, x, y, MC.check_place(game, def, Vector2i(x, y), turns)])
	return id


func until(cond: Callable, limit: float) -> bool:
	for _i in int(limit):
		if cond.call():
			return true
		secs(1.0)
	return cond.call()


func held(id: int, mat: int) -> int:
	return int(game.modules[id]["contents"].get(mat, 0))


## A feed Tank on the ground at x 300, the vessel `def` bolted on top of it and a Tank above that.
func line(def: String, mat: int, n: int) -> Dictionary:
	fresh()
	var tank := place("tank", TX, SURFACE - 30)
	var sn := MC.snap(game, def, 0, Vector2i(TX + 36, SURFACE - 15))
	var vessel := MC.place(game, def, sn["at"], 0)
	var sn2 := MC.snap(game, "tank", 0, Vector2i(TX + 13, SURFACE - 30 - 15))
	var top := MC.place(game, "tank", sn2["at"], 0)
	secs(0.2)
	MC.JT.hold_rig(game, top, [tank], true)          # a Tank stacked on a Tank slides off, so it is bolted on
	MC.add_contents(game, tank, mat, n)
	secs(0.5)
	return {"tank": tank, "vessel": vessel, "top": top, "snapped": sn["snapped"] and sn2["snapped"]}


## A feed Tank, the strip `def` against its right side and a second Tank against the strip's right; with `gas`,
## a third Tank on top of the strip (the strip is then 30 tall, level with the two Tanks).
func strip(def: String, mix: Dictionary, gas := false) -> Dictionary:
	fresh()
	var h: int = MC.defs[def]["size"][1]
	var feed := place("tank", 386, SURFACE - 30)
	var sn := MC.snap(game, def, 0, Vector2i(425, SURFACE - (h >> 1)))
	var mid := MC.place(game, def, sn["at"], 0)
	var sn2 := MC.snap(game, "tank", 0, Vector2i(sn["at"].x + int(MC.defs[def]["size"][0]) + 13, SURFACE - 15))
	var out := MC.place(game, "tank", sn2["at"], 0)
	var top := 0
	var joined: bool = sn["snapped"] and sn2["snapped"]
	if gas:
		var sn3 := MC.snap(game, "tank", 0, Vector2i(sn["at"].x + (int(MC.defs[def]["size"][0]) >> 1), SURFACE - 30 - 15))
		top = MC.place(game, "tank", sn3["at"], 0)
		joined = joined and sn3["snapped"]
		secs(0.2)
		MC.JT.hold_rig(game, top, [feed, out], true)          # a Tank on a narrow strip slides off, so it is bolted on
	for mat: int in mix:
		MC.add_contents(game, feed, mat, mix[mat])
	secs(0.5)
	return {"feed": feed, "strip": mid, "out": out, "top": top, "snapped": joined}


## Pixels of casing a module still has.
func pixels(id: int) -> int:
	var px: PackedByteArray = game.sim.body_pixels(game.modules[id]["body"])
	return px.size() - px.count(0)


func scenario_12() -> void:
	print("12. The machines")
	# Heater on Boil: Brine leaves Salt, Slick leaves Pitch; the gas and what it leaves go up, the liquids stay.
	var r := line("heater", I["Brine"], 120)
	MC.add_contents(game, r["tank"], I["Slick"], 60)
	var top: int = r["top"]
	check(r["snapped"], "a Heater plugs into a Tank's side with another Tank on top")
	var ok := until(func() -> bool: return held(top, I["Salt"]) >= 10 and held(top, I["Pitch"]) >= 10, 90.0)
	check(ok, "Brine leaves Salt and Slick leaves Pitch, and both go out of the top (%d Salt, %d Pitch)" % [held(top, I["Salt"]), held(top, I["Pitch"])])
	check(held(top, I["Steam"]) + held(top, I["Smoke"]) > 0 and held(top, I["Brine"]) == 0 and held(top, I["Slick"]) == 0, "with the gas (%d Steam, %d Smoke) while the liquids stay in the feed Tank" % [held(top, I["Steam"]), held(top, I["Smoke"])])
	# Chiller: Brine to Chillant.
	r = line("chiller", I["Brine"], 100)
	var ok2 := until(func() -> bool: return held(r["top"], I["Chillant"]) >= 20, 90.0)
	check(ok2 and held(r["top"], I["Brine"]) == 0, "the Chiller turns Brine to Chillant and passes only that (%d Chillant, %d Brine)" % [held(r["top"], I["Chillant"]), held(r["top"], I["Brine"])])
	# Heater on Smelt: Veinstone and Flux to Wire.
	r = line("heater", I["Veinstone"], 80)
	MC.add_contents(game, r["tank"], I["Flux"], 40)
	game.modules[r["vessel"]]["mode"] = 1
	var top2: int = r["top"]
	var forged := until(func() -> bool: return held(top2, I["Wire"]) >= 8, 150.0)
	check(forged, "the Heater on Smelt smelts Veinstone with Flux to Wire, out of the top (%d Wire)" % held(top2, I["Wire"]))
	# Electrolyser strip: Brine and Water from one Tank to another.
	var e := strip("electrolyser", {I["Brine"]: 60, I["Water"]: 20}, true)
	var feed: int = e["feed"]
	var out: int = e["out"]
	var up: int = e["top"]
	check(e["snapped"], "a Tank joins each side of the Electrolyser and a third its top")
	var done := until(func() -> bool: return held(out, I["Lye"]) >= 60 and held(up, I["Chlor"]) + held(up, I["Lift"]) >= 70, 40.0)
	check(done, "60 Brine and 20 Water give 60 Lye in the out Tank and about 30 Chlor and 50 Lift in the top one (%d, %d, %d)" % [held(out, I["Lye"]), held(up, I["Chlor"]), held(up, I["Lift"])])
	check(held(out, I["Chlor"]) + held(out, I["Lift"]) + held(up, I["Lye"]) + held(feed, I["Lye"]) == 0 and held(out, I["Brine"]) + held(out, I["Water"]) == 0, "each product goes to its own Tank and the feed stays in its own")
	check(game.stock[D.R_POWER] < 90.0 - 35.0, "and it paid power a cell, 80 cells at 0.5 (%.1f of 90 left)" % game.stock[D.R_POWER])
	e = strip("electrolyser", {I["Brine"]: 60}, true)
	for _i in 600:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(held(e["out"], I["Lye"]) == 0 and held(e["feed"], I["Brine"]) == 60 and "power" in game.modules[e["strip"]]["state"].to_lower(), "with no power it splits nothing (%s)" % game.modules[e["strip"]]["state"])
	# Combustor: Lift and Pitch burn for power, Pitch first.
	fresh()
	game.stock[D.R_POWER] = 10.0
	var tank := place("tank", 428, SURFACE - 30)
	var csn := MC.snap(game, "combustor", 0, Vector2i(441, SURFACE - 30 - 9))
	var comb := MC.place(game, "combustor", csn["at"], 0)
	secs(0.5)           # a vessel sizes its interior at its first scan
	MC.add_contents(game, tank, I["Pitch"], 4)
	MC.add_contents(game, tank, I["Lift"], 4)
	secs(2.5)
	var burned: int = game.modules[comb].get("burned", 0)
	var pitch_left := held(tank, I["Pitch"]) + held(comb, I["Pitch"])
	var lift_left := held(tank, I["Lift"]) + held(comb, I["Lift"])
	check(burned >= 1 and pitch_left == 4 - burned and lift_left == 4, "the Combustor burns Pitch, the richer fuel, before Lift (%d burned, %d Pitch, %d Lift left)" % [burned, pitch_left, lift_left])
	check(game.stock[D.R_POWER] >= 10.0 + 4.0 * float(burned) - 0.01, "at 4 power a cell of Pitch (%.1f)" % game.stock[D.R_POWER])
	# Casing wear weighs the acid: casing pixels left after 400 scans.
	var left := {}
	for acid in ["Sourwater", "Gall", "Vitriol"]:
		fresh()
		var t2 := place("tank", 428, SURFACE - 30)
		MC.add_contents(game, t2, I[acid], 300)
		var whole := pixels(t2)
		for _i in 400:
			CS.wear(game, game.modules[t2], MC.defs["tank"])
		left[acid] = float(pixels(t2)) / float(whole)
	check(left["Gall"] < left["Sourwater"] and left["Sourwater"] < 1.0 and left["Vitriol"] > left["Sourwater"] - 0.001, "a Tank of Gall loses more casing than one of Sourwater, and Vitriol least (%.2f, %.2f, %.2f left)" % [left["Gall"], left["Sourwater"], left["Vitriol"]])
	fresh()
	game.levels["plating"] = 4
	var t3 := place("tank", 428, SURFACE - 30)
	MC.add_contents(game, t3, I["Gall"], 300)
	var t4 := place("tank", 468, SURFACE - 30)
	MC.add_contents(game, t4, I["Sourwater"], 300)
	for _i in 400:
		CS.wear(game, game.modules[t3], MC.defs["tank"])
		CS.wear(game, game.modules[t4], MC.defs["tank"])
	check(game.modules[t3].get("worn", false) and not game.modules[t4].get("worn", false), "Plating IV stops Sourwater and only blunts Gall")
