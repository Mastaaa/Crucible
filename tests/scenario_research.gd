extends SceneTree
## Phase-3 research checks on seed 7, laid out by hand next to the Hub:
##  A. what's locked at the start, and why
##  B. one Lab researches the Lamp on the Hub's own power; the Lamp unlocks
##  C. two Labs on a full power store research twice as fast
##  D. Drill Bit: the fixed Drill digs 1.5x faster a level at 1.2x the power per cell
##  E. Drill Shaft: the Drill stops at 30 rows and carries on when the next level is done
##  F. discoveries: Glimmer mined, lava seen, the Crucible in view
##  G. a Tier 2 tech takes its Glimmer by packet, delivered to a Lab
## Run: godot --headless --path . --script tests/scenario_research.gd

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var fails := 0


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		scenario_a()
		scenario_b()
		scenario_c()
		scenario_d()
		scenario_e()
		scenario_f()
		scenario_g()
		print("FAILURES: %d" % fails)
		return true
	return false


## Where a v2 cell near the Hub is now: the layout scales by D.S about the pad's
## middle at ground level.
func P(x: int, y: int) -> Vector2i:
	return Vector2i((D.W >> 1) + (x - 128) * D.S, D.GROUND_Y + (y - 40) * D.S)


func R(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(P(x, y), Vector2i(w, h) * D.S)


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true


func carve(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, D.AIR)


func build(type: int, r: Rect2i, dir := 0) -> Object:
	var why: String = game.check_place(type, r)
	if why != "":
		print("  !! can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		fails += 1
		return null
	var b = game.place(type, r, dir)
	for _i in 600:
		if b.built:
			break
		game.run_ticks(1)
	game.run_ticks(2)
	return b


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


## Run until `id` is researched, up to `limit` seconds; returns the seconds taken or -1.
func research(id: String, limit: float) -> float:
	game.pick_research(id)
	for t in int(limit * 60.0):
		game.run_ticks(1)
		if game.researched.has(id):
			return (t + 1) / 60.0
	return -1.0


func scenario_a() -> void:
	print("A. locked at the start")
	fresh()
	check(game.is_unlocked(D.B_LAB) and game.is_unlocked(D.B_CONDUIT), "starting kit is open")
	check(not game.is_unlocked(D.B_DRILL), "the Drill isn't in the build list: there's one, fixed")
	check(game.drill != null and game.drill.fixed and game.drill.built, "the fixed Drill stands beside the Hub")
	check(not game.is_unlocked(D.B_SPOUT) and not game.is_unlocked(D.B_CACHE), "Spout and Cache wait for research")
	check(game.tech_block("lamp") == "" and game.tech_block("thumper") == "" and game.tech_block("borer") == "", "Tier 1 techs can be picked, Thumper and Borer among them")
	print("  floodgate: %s | warren: %s | homing: %s" % [game.tech_block("floodgate"), game.tech_block("warren"), game.tech_block("homing")])
	check(game.tech_block("floodgate").begins_with("Opens with"), "Tier 2 waits for its discovery")
	check(game.tech_block("warren") == "", "Warren can be picked from the start")
	check(game.tech_block("thump_charge") == "Needs Thumper", "Thumper upgrades wait on the Thumper")
	check(game.tech_block("drill_bit") == "" and game.tech_block("drill_shaft") == "", "Drill upgrades open from the start")


func scenario_b() -> void:
	print("B. one Lab on the Hub's own power")
	fresh()
	build(D.B_LAB, R(118, 37, 4, 3))
	var cost: float = D.TECHS[D.tech_index("lamp")]["power"]
	var secs := research("lamp", cost)
	print("  Lamp (%d power) took %.1f s; research rate %.2f/s" % [int(cost), secs, game.research_rate])
	check(secs > 0.0 and secs < cost / D.LAB_POWER_PER_S * 1.2 + 5.0, "Lamp researched at a Lab's pace")
	check(game.is_unlocked(D.B_LAMP), "Lamp is in the build list now")
	check(game.current_tech == "", "nothing picked after it's done")


func scenario_c() -> void:
	print("C. two Labs on a full store")
	fresh()
	build(D.B_LAB, R(136, 37, 4, 3))
	build(D.B_LAB, R(118, 37, 4, 3))
	game.stock[D.R_POWER] = 100.0
	game.run_ticks(60)
	var cost: float = D.TECHS[D.tech_index("drill_bit")]["levels"][0]["power"]
	var secs := research("drill_bit", cost)
	print("  Drill Bit 1 (%d power) took %.1f s with two Labs" % [int(cost), secs])
	check(secs > 0.0 and secs < cost / (2.0 * D.LAB_POWER_PER_S) * 1.3, "two Labs research at about twice the pace")


## Cells the fixed Drill bores in 4 s of plain dirt, once it's going.
func _drill_rate(label: String) -> int:
	var d = game.drill
	for yy in range(D.GROUND_Y, D.GROUND_Y + 60 * D.S):
		for xx in range(d.x, d.x + d.w):
			game.sim.set_cell(xx, yy, D.DIRT)
	d.reach = 0
	d.scan_from = 0
	d.power = 10.0
	game.stock[D.R_POWER] = 100.0
	game.run_ticks(60)
	var start: int = d.cells_bored
	game.run_ticks(240)
	var cells: int = d.cells_bored - start
	print("  %s: %d cells in 4 s" % [label, cells])
	return cells


func scenario_d() -> void:
	print("D. Drill Bit")
	fresh()
	var slow := _drill_rate("plain Drill")
	game.levels["drill_bit"] = 2
	game.researched["drill_bit"] = true
	var fast := _drill_rate("Drill Bit 2")
	check(fast >= slow * 1.9, "digs about 2.25x faster at level 2 (%d vs %d)" % [fast, slow])
	var plain := D.power_per_cell(D.DIRT)
	check(absf(game.drill_power(D.DIRT, 0) - plain * 1.44) < plain * 0.01, "dirt costs 1.44x the plain power a cell at level 2 (%.5f)" % game.drill_power(D.DIRT, 0))
	check(absf(game.drill_power(D.DIRT, int(D.DRILL_DEEP_ROWS)) - plain * 2.88) < plain * 0.01, "and twice that %d rows down" % int(D.DRILL_DEEP_ROWS))


func scenario_e() -> void:
	print("E. Drill Shaft")
	fresh()
	var d = game.drill
	game.levels["drill_bit"] = 3
	game.researched["drill_bit"] = true
	var r0: int = D.DRILL_REACHES[0]
	var r1: int = D.DRILL_REACHES[1]
	check(d.reach_limit == r0, "the Drill starts with %d rows of reach (%d)" % [r0, d.reach_limit])
	for _i in 3:
		game.stock[D.R_POWER] = 100.0
		game.run_ticks(60 * 10)
	check(d.reach == r0, "it stops at %d (%d)" % [r0, d.reach])
	game._finish_research("drill_shaft")
	for _i in 3:
		game.stock[D.R_POWER] = 100.0
		game.run_ticks(60 * 10)
	check(d.reach_limit == r1 and d.reach > r0 + floori((r1 - r0) / 3.0), "it carries on toward %d once Drill Shaft 1 is done (%d / %d)" % [r1, d.reach, d.reach_limit])
	check(game.level("drill_shaft") == 1 and game.tech_block("drill_shaft") == "", "level 2 can be picked next")


func scenario_f() -> void:
	print("F. discoveries")
	fresh()
	# Glimmer under a Drill.
	build(D.B_CONDUIT, R(140, 38, 2, 2))
	var vein := R(143, 42, 3, 4)
	for yy in range(vein.position.y, vein.end.y):
		for xx in range(vein.position.x, vein.end.x):
			game.sim.set_cell(xx, yy, D.GLIMMER)
	build(D.B_DRILL, R(143, 37, 3, 3))
	game.stock[D.R_POWER] = 100.0
	game.run_ticks(60 * 10)
	check(game.tiers_open[2], "Tier 2 opens when Glimmer is mined")
	check(game.tech_block("floodgate") == "Needs Spout", "Floodgate now waits only on Spout (%s)" % game.tech_block("floodgate"))
	# Lava where a building can see it.
	check(not game.tiers_open[3], "Tier 3 still shut")
	var lv := P(150, 44)
	game.sim.set_cell(lv.x, lv.y, D.LAVA)
	game.sim.refresh_heat(true)
	game._refresh_vision()
	check(game.tiers_open[3], "Tier 3 opens when lava is seen")
	# Something of yours in sight of the Crucible.
	var cr: Rect2i = game.crucible.rect()
	var lamp = game._make_building(D.B_LAMP, Rect2i(cr.position.x, cr.position.y - 8 * D.S, 2 * D.S, 2 * D.S))
	lamp.built = true
	lamp.power = 5.0
	game._refresh_vision()
	check(game.tiers_open[4], "Tier 4 opens when the Crucible comes into view")


func scenario_g() -> void:
	print("G. a Tier 2 tech takes Glimmer delivered to a Lab")
	fresh()
	game.tiers_open[2] = true
	game.researched["spout"] = true
	game._refresh_unlocks()
	var fg: Dictionary = D.TECHS[D.tech_index("floodgate")]
	var want: float = fg["mats"][D.R_GLIMMER]
	game.stock[D.R_GLIMMER] = want + 7.0
	game.stock[D.R_POWER] = 100.0
	build(D.B_LAB, R(118, 37, 4, 3))
	var secs := research("floodgate", fg["power"])
	print("  Floodgate (%d power, %d Glimmer) took %.1f s; Hub Glimmer %.0f" % [fg["power"], int(want), secs, game.stock[D.R_GLIMMER]])
	check(secs > 0.0, "researched")
	check(absf(game.stock[D.R_GLIMMER] - 7.0) < 0.01, "exactly the tech's %d Glimmer went to the Lab" % int(want))
	check(game.is_unlocked(D.B_FLOODGATE), "Floodgate unlocked")
	# Switching picks keeps progress.
	game.researched.erase("floodgate")
	game.tech_power["floodgate"] = 30.0
	game.pick_research("cache")
	game.run_ticks(60)
	game.pick_research("floodgate")
	check(game.tech_power["floodgate"] >= 30.0, "a paused tech keeps its progress")
