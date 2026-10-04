extends SceneTree
## Research checks on seed 7 (A3 cut: the Lab is a module; techs are Lamp, Brace, the upgrades):
##  A. what's locked at the start, and why
##  B. one Lab researches the Lamp on the Hub's own power; the Lamp module unlocks
##  C. two Labs on a full power store research twice as fast
##  D. Drill Bit levels up and each level costs more
##  E. Drill Shaft: the cable length (max_reach) follows its level
##  F. discoveries: Glimmer banked, lava seen, the Crucible in view
##  G. a Tier 2 level takes its Glimmer out of the Hub's stock, and a paused tech keeps its progress
## Run: godot --headless --path . --script tests/scenario_research.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
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
		if t % 60 == 0:
			game.stock[D.R_POWER] = 100.0    # the Hub's trickle is 0.2/s now; research is measured on a full store
		game.run_ticks(1)
		if game.researched.has(id):
			return (t + 1) / 60.0
	return -1.0


## A flat strip of ground on one side of the Hub, then a Lab standing on it: side -1 left of the
## Hub, 1 right of it.
func lab_at(side: int) -> int:
	var hub: Rect2i = game.hub.rect()
	var ground := hub.end.y
	var x0 := hub.position.x - 100 if side < 0 else hub.end.x
	for x in range(x0, x0 + 100):
		for y in range(ground - 60, ground):
			game.sim.set_cell(x, y, D.AIR)
		for y in range(ground, ground + 10):
			game.sim.set_cell(x, y, D.DIRT)
	var at := Vector2i(hub.position.x - 44 if side < 0 else hub.end.x + 4, ground - 30)
	var id := MC.place(game, "lab", at, 0)
	if id == 0:
		print("  !! can't place a Lab at %s: %s" % [at, MC.check_place(game, "lab", at, 0)])
		fails += 1
	game.run_ticks(60)
	return id


func lamp_open() -> bool:
	MC.ensure_defs()
	return MC.unlocked(game, MC.defs["lamp"])


func scenario_a() -> void:
	print("A. locked at the start")
	fresh()
	MC.ensure_defs()
	check(MC.unlocked(game, MC.defs["lab"]) and game.is_unlocked(D.B_NODE), "starting kit is open: the Lab module and the Node")
	check(not lamp_open(), "the Lamp waits for research")
	check(not game.is_unlocked(D.B_BRACE), "the Brace waits for research")
	check(game.tech_block("lamp") == "" and game.tech_block("brace") == "", "Tier 1 techs can be picked")
	check(game.tech_block("tremor_dampers").begins_with("Opens with"), "Tremor Dampers wait for their tier")
	check(game.tech_block("drill_bit") == "" and game.tech_block("drill_shaft") == "" and game.tech_block("tank_size") == "", "the quarry upgrades open from the start")


func scenario_b() -> void:
	print("B. one Lab on the Hub's own power")
	fresh()
	lab_at(-1)
	var cost: float = D.TECHS[D.tech_index("lamp")]["power"]
	var secs := research("lamp", cost)
	print("  Lamp (%d power) took %.1f s; research rate %.2f/s" % [int(cost), secs, game.research_rate])
	check(secs > 0.0 and secs < cost / D.LAB_POWER_PER_S * 1.2 + 5.0, "Lamp researched at a Lab's pace")
	check(lamp_open(), "the Lamp is in the build list now")
	check(game.current_tech == "", "nothing picked after it's done")


func scenario_c() -> void:
	print("C. two Labs on a full store")
	fresh()
	lab_at(1)
	lab_at(-1)
	game.stock[D.R_POWER] = 100.0
	game.run_ticks(60)
	var cost: float = D.TECHS[D.tech_index("drill_bit")]["levels"][0]["power"]
	var secs := research("drill_bit", cost)
	print("  Drill Bit 1 (%d power) took %.1f s with two Labs" % [int(cost), secs])
	check(secs > 0.0 and secs < cost / (2.0 * D.LAB_POWER_PER_S) * 1.3, "two Labs research at about twice the pace")


func scenario_d() -> void:
	print("D. Drill Bit")
	fresh()
	lab_at(-1)
	var lv: Array = D.TECHS[D.tech_index("drill_bit")]["levels"]
	check(game.level("drill_bit") == 0, "level 0 to start")
	check(research("drill_bit", float(lv[0]["power"])) > 0.0 and game.level("drill_bit") == 1, "researching it gives level 1")
	check(float(lv[1]["power"]) > float(lv[0]["power"]), "level 2 costs more than level 1")
	check(game.tech_block("drill_bit") == "", "level 2 can be picked next")


func scenario_e() -> void:
	print("E. Drill Shaft")
	fresh()
	lab_at(-1)
	check(game.max_reach() == D.SHAFT_REACHES[0], "the cable starts at %d rows" % D.SHAFT_REACHES[0])
	var lv: Array = D.TECHS[D.tech_index("drill_shaft")]["levels"]
	check(research("drill_shaft", float(lv[0]["power"])) > 0.0, "level 1 is researched")
	check(game.max_reach() == D.SHAFT_REACHES[1], "and the cable is %d rows" % D.SHAFT_REACHES[1])


func scenario_f() -> void:
	print("F. discoveries")
	fresh()
	check(not game.tiers_open[2], "Tier 2 starts shut")
	game._bank(game.hub.center(), D.R_GLIMMER, 1.0)
	game.run_ticks(2)
	check(game.tiers_open[2], "Tier 2 opens when Glimmer is banked")
	# Lava where a building can see it.
	build(D.B_NODE, R(140, 38, 2, 2))
	check(not game.tiers_open[3], "Tier 3 still shut")
	var lv := P(150, 44)
	game.sim.set_cell(lv.x, lv.y, D.LAVA)
	game.sim.refresh_heat(true)
	game._refresh_vision()
	check(game.tiers_open[3], "Tier 3 opens when lava is seen")
	# Something of yours in sight of the Crucible.
	var cr: Rect2i = game.crucible.rect()
	var node = game._make_building(D.B_NODE, Rect2i(cr.position.x, cr.position.y - 8 * D.S, 2 * D.S, 2 * D.S))
	node.built = true
	game._refresh_vision()
	check(game.tiers_open[4], "Tier 4 opens when the Crucible comes into view")


func scenario_g() -> void:
	print("G. a Tier 2 level takes Glimmer out of the stock")
	fresh()
	game.tiers_open[2] = true
	game.levels["drill_bit"] = 1
	var lv: Dictionary = D.TECHS[D.tech_index("drill_bit")]["levels"][1]
	check(lv["tier"] == 1, "(level 2 is a Tier 1 level)")
	game.levels["drill_bit"] = 2
	var l3: Dictionary = D.TECHS[D.tech_index("drill_bit")]["levels"][2]
	var want: float = l3["mats"][D.R_GLIMMER]
	game.stock[D.R_GLIMMER] = want + 7.0
	game.stock[D.R_POWER] = 100.0
	lab_at(-1)
	var secs := research("drill_bit", float(l3["power"]))
	print("  Drill Bit 3 (%d power, %d Glimmer) took %.1f s; Hub Glimmer %.0f" % [l3["power"], int(want), secs, game.stock[D.R_GLIMMER]])
	check(secs > 0.0 and game.level("drill_bit") == 3, "researched to level 3")
	check(absf(game.stock[D.R_GLIMMER] - 7.0) < 0.01, "exactly the level's %d Glimmer left the stock" % int(want))
	# Switching picks keeps progress.
	game.tech_power["drill_shaft"] = 30.0
	game.pick_research("tank_size")
	game.run_ticks(60)
	game.pick_research("drill_shaft")
	check(game.tech_power["drill_shaft"] >= 30.0, "a paused tech keeps its progress")
