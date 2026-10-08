extends SceneTree
## A6 part 4: the surface generators, on seed 7 with the Hub as the network.
##  A. Solar Panel: steady power under open sky, none under a roof (and again once the roof goes), none out of
##     the network's reach, and one at the bottom of an open pit works
##  B. the biome under a Solar Panel multiplies its power by the definition's `biomes` entry (Dunes pay best)
##  C. Waterwheel: water standing over it runs through and out underneath for power (up to `cells` a second);
##     pooled water under it, or none over it, stalls it; out of reach it feeds nothing
##  D. the two are tech-gated, and the Hub's help text and Build list know them
## Run: godot --headless --path . --script tests/scenario_generators.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const X0 := 418          # a bench column inside the Hub's reach
const SURFACE := 200     # ground level (dirt from here down)


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		if game.sim.get_script() != null:
			print("  (the GDScript sim has no bodies: nothing to check)")
			print("FAILURES: 0")
			return true
		scenario_a()
		scenario_b()
		scenario_c()
		scenario_d()
		print("FAILURES: %d" % fails)
		return true
	return false


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	MC.ensure_defs()
	fill(Rect2i(X0 - 30, SURFACE - 120, 110, 120), D.AIR)
	fill(Rect2i(X0 - 30, SURFACE, 110, 160), 6)
	fill(Rect2i(X0 - 30, SURFACE + 160, 110, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 10.0
	game.info["spawned"] = {}


func place(def: String, x: int, y: int) -> int:
	var id := MC.place(game, def, Vector2i(x, y), 0)
	if id == 0:
		print("  !! can't place %s at %d,%d: %s" % [def, x, y, MC.check_place(game, def, Vector2i(x, y), 0)])
	return id


## The range of a module's flow over `n` seconds, one sample a second.
func flows(id: int, n: int) -> Vector2:
	var lo := 99.0
	var hi := 0.0
	for _i in n:
		secs(1.0)
		lo = minf(lo, game.modules[id]["flow"])
		hi = maxf(hi, game.modules[id]["flow"])
	return Vector2(lo, hi)


func scenario_a() -> void:
	print("A. solar panel")
	fresh()
	var want: float = MC.defs["solar"]["params"]["power"]
	var id := place("solar", X0 + 32, SURFACE - 8)
	secs(2.0)
	var m: Dictionary = game.modules[id]
	var s := flows(id, 5)
	check(absf(s.x - want) < 0.001 and absf(s.y - want) < 0.001, "in open sky it makes %.2f power/s with no gusts (%.3f to %.3f)" % [want, s.x, s.y])
	var before: float = game.stock[D.R_POWER]
	secs(10.0)
	check(game.stock[D.R_POWER] - before > 10.0 * (D.HUB_POWER_PER_S + want) * 0.95, "and the Hub's stock gains it (%.2f)" % (game.stock[D.R_POWER] - before))
	fill(Rect2i(X0 + 30, SURFACE - 60, 28, 4), D.BEDROCK)
	secs(1.0)
	check(m["flow"] == 0.0 and "shades" in m["why"], "a roof high over it shades it: %s" % m["why"])
	fill(Rect2i(X0 + 30, SURFACE - 60, 28, 4), D.AIR)
	secs(1.0)
	check(m["flow"] > 0.0, "and it comes back when the roof goes")

	# A pit: air 24 wide and 32 deep, the panel at the bottom with open sky over it.
	fresh()
	fill(Rect2i(X0 + 32, SURFACE, 24, 40), D.AIR)
	var pit := place("solar", X0 + 32, SURFACE + 32)
	secs(2.0)
	check(pit != 0 and game.modules[pit]["flow"] > 0.0, "at the bottom of an open pit it works (%.2f power/s)" % game.modules[pit]["flow"])
	fill(Rect2i(X0 + 28, SURFACE - 1, 32, 3), D.BEDROCK)
	secs(1.0)
	check(game.modules[pit]["flow"] == 0.0 and "shades" in game.modules[pit]["why"], "a lid over the pit shades it")

	fresh()
	fill(Rect2i(600, SURFACE - 120, 120, 120), D.AIR)
	fill(Rect2i(600, SURFACE, 120, 100), 6)
	var far := place("solar", 620, SURFACE - 8)
	secs(2.0)
	check(game.modules[far]["flow"] == 0.0 and "reach" in game.modules[far]["why"], "out of the network's reach it feeds nothing: %s" % game.modules[far]["why"])


func scenario_b() -> void:
	print("B. the biome under it")
	fresh()
	var base: float = MC.defs["solar"]["params"]["power"]
	var best: float = MC.defs["solar"]["params"]["biomes"]["dunes"]
	check(best > 1.0, "the definition has Dunes pay more than the plain ground (x%.2f)" % best)
	var id := place("solar", X0 + 32, SURFACE - 8)
	game.info["spawned"] = {"shapes": {"dunes": {"cx": X0 + 44.0, "cy": float(SURFACE), "rx": 100.0, "ry": 100.0, "phase": 0.0}}}
	secs(2.0)
	var m: Dictionary = game.modules[id]
	check(m["biome"] == "dunes" and absf(m["flow"] - base * best) < 0.001, "over the Dunes it makes %.2f power/s (%.3f in %s)" % [base * best, m["flow"], m["biome"]])
	check("dunes" in m_info(id).to_lower(), "and says so: %s" % m_info(id))
	game.info["spawned"] = {"shapes": {"fen": {"cx": X0 + 44.0, "cy": float(SURFACE), "rx": 100.0, "ry": 100.0, "phase": 0.0}}}
	secs(1.0)
	check(absf(m["flow"] - base) < 0.001, "over a biome the definition does not name it makes the plain %.2f (%.3f)" % [base, m["flow"]])


func m_info(id: int) -> String:
	var m: Dictionary = game.modules[id]
	return MC.kinds[MC.defs[m["def"]]["kind"]].info(game, m, MC.defs[m["def"]])


## A pit 16 wide with a step at WY + 14 to a slot 12 wide and 10 deep; the wheel rests on the step.
func wheel_bench(wx: int, wy: int, water_rows: int) -> int:
	fresh()
	fill(Rect2i(wx, wy - 10, 16, 24), D.AIR)
	fill(Rect2i(wx + 2, wy + 14, 12, 10), D.AIR)
	var id := place("waterwheel", wx, wy)
	fill(Rect2i(wx, wy - water_rows, 16, water_rows), D.WATER)
	return id


func scenario_c() -> void:
	print("C. waterwheel")
	var wx := X0 + 32
	var wy := SURFACE + 20
	var id := wheel_bench(wx, wy, 10)
	var p: Dictionary = MC.defs["waterwheel"]["params"]
	var m: Dictionary = game.modules[id]
	game.stock[D.R_POWER] = 10.0
	var wet_before: int = game.sim.count_in_rect(wx, wy - 10, 16, 10, M.mask("liquid"))
	secs(2.0)
	var passed: int = m.get("passed", 0)
	var cap := int(2.0 * float(p["cells"]))
	check(passed > cap * 0.5 and passed <= cap + 4, "water standing on it runs through, %d cells in 2 s (at most %d)" % [passed, cap])
	var wet_after: int = game.sim.count_in_rect(wx, wy - 10, 16, 10, M.mask("liquid"))
	var under: int = game.sim.count_in_rect(wx + 2, wy + 14, 12, 10, M.mask("liquid"))
	check(wet_before - wet_after == passed and under == passed, "it leaves the pit above and lands in the slot under it (%d above gone, %d below)" % [wet_before - wet_after, under])
	var made: float = float(passed) * float(p["per_cell"])
	check(game.stock[D.R_POWER] - 10.0 > made * 0.99 and game.stock[D.R_POWER] - 10.0 < made + 2.0 * (D.HUB_POWER_PER_S + 0.05), "every cell pays %.4f power (%.2f made)" % [p["per_cell"], game.stock[D.R_POWER] - 10.0])
	check(m["flow"] > 0.2 and m["flow"] < float(p["cells"]) * float(p["per_cell"]) * 1.1, "it reads %.2f power/s" % m["flow"])
	secs(8.0)
	check("pooled" in m["why"] and m["flow"] == 0.0, "the slot fills and water pooled under it stalls it: %s" % m["why"])
	fill(Rect2i(wx + 2, wy + 14, 12, 10), D.AIR)
	secs(1.0)
	check(m["flow"] > 0.0, "and it turns again once the slot is drained")
	fill(Rect2i(wx, wy - 10, 16, 10), D.AIR)
	fill(Rect2i(wx + 2, wy + 14, 12, 10), D.AIR)
	secs(2.0)
	check(m["flow"] == 0.0 and "falls" in m["why"], "with no water over it it stands still: %s" % m["why"])

	# A spring in the pit over it (the Fen's pockets have one) keeps it turning after the standing water has gone.
	id = wheel_bench(wx, wy, 3)
	game.info["springs"] = [Vector2i(wx + 8, wy - 1)]
	m = game.modules[id]
	for _i in 20:
		fill(Rect2i(wx + 2, wy + 14, 12, 10), D.AIR)
		secs(0.5)
	var spring_cap := int(10.0 * float(p["cells"]))
	check(m.get("passed", 0) > spring_cap * 0.6, "with a spring over it and the slot drained it passes %d cells in 10 s, more than the 48 standing there (at most %d)" % [m.get("passed", 0), spring_cap])

	fresh()
	fill(Rect2i(600, SURFACE, 16, 24), D.AIR)
	var far := place("waterwheel", 600, SURFACE + 4)
	fill(Rect2i(600, SURFACE - 8, 16, 8), D.WATER)
	secs(2.0)
	check(far != 0 and game.modules[far].get("passed", 0) == 0 and "reach" in game.modules[far]["why"], "out of the network's reach it passes nothing: %s" % game.modules[far]["why"])


func scenario_d() -> void:
	print("D. research and the Build list")
	fresh()
	for id in ["solar", "waterwheel"]:
		var def: Dictionary = MC.defs[id]
		check(def.has("tech") and D.tech_index(def["tech"]) >= 0, "%s names a tech that exists (%s)" % [id, def.get("tech", "")])
		check(not MC.unlocked(game, def), "%s is locked until researched" % id)
		game.researched[def["tech"]] = 1
		check(MC.unlocked(game, def), "and unlocked once it is")
	check(not MC.defs["windmill"].has("tech"), "the Windmill stays in the starter kit")
