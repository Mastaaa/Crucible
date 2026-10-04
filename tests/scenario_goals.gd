extends SceneTree
## Goal layer (A3 v1) checks on seed 7:
##  A. a fresh run starts the tutorial; the Hub trickle is 0.2 power/s
##  B. tutorial steps complete in order and pay power into the Hub
##  C. delivery orders count what is banked since they were issued
##  D. skipping the tutorial hands over to standing orders
##  E. chapters complete by depth and reach the event tracker
##  F. research costs goods by tier; the goal state encodes for the save
## Run: godot --headless --path . --script tests/scenario_goals.gd

const D = preload("res://scripts/defs.gd")
const Goals = preload("res://scripts/goals.gd")
const MC = preload("res://scripts/machines/machines.gd")
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
		scenario_a()
		scenario_b()
		scenario_c()
		scenario_d()
		scenario_e()
		scenario_f()
		print("FAILURES: %d" % fails)
		return true
	return false


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func scenario_a() -> void:
	print("A. a fresh run")
	fresh()
	game.run_ticks(60)
	check(game.goals["mode"] == "tutorial", "the tutorial is on")
	check(game.goals["cur"].get("n", 0) == 1 and game.goals["cur"]["text"] == "Build a Cutter Excavator, a Tank, a Funnel and a Winch.", "Instruction 1 is on the board")
	check(is_equal_approx(D.HUB_POWER_PER_S, 0.2), "the Hub trickle is 0.2 power/s")


func scenario_b() -> void:
	print("B. tutorial steps pay out")
	fresh()
	MC.ensure_defs()
	# Open sky over dirt, so the starter rig can stand on it.
	for y in range(80, 400):
		for x in range(250, 370):
			game.sim.set_cell(x, y, D.AIR if y < 200 else 6)
	game.stock[D.R_POWER] = 0.0
	game.run_ticks(60)
	for part: Array in [["cutter", 290, 184], ["tank", 290, 154], ["funnel", 290, 140]]:
		MC.place(game, part[0], Vector2i(part[1], part[2]), 0)
	game.run_ticks(60)
	check(game.goals["step"] == 0, "three of the four rig parts do not complete Instruction 1")
	MC.place(game, "winch", Vector2i(304, 136), 0)
	game.run_ticks(60)
	check(game.goals["step"] == 1, "the whole rig completes Instruction 1")
	check(game.stock[D.R_POWER] >= 35.0, "it paid about 40 power into the Hub (%.1f)" % game.stock[D.R_POWER])
	check(game.goals["cur"].get("n", 0) == 2, "Instruction 2 follows")
	game._bank(game.hub.center(), D.R_STONE, 30.0)
	game.run_ticks(60)
	check(game.goals["cur"]["text"] == "Build a Lab.", "the Lab is the third order")
	var lab_id := MC.place(game, "lab", Vector2i(330, 170), 0)
	check(lab_id != 0, "the Lab is placed (%s)" % MC.check_place(game, "lab", Vector2i(330, 170), 0))
	game.run_ticks(60)
	check(game.goals["step"] == 3, "a Lab module completes Instruction 3")


func scenario_c() -> void:
	print("C. delivery orders")
	fresh()
	game.goals["step"] = 1
	game.run_ticks(60)
	check(game.goals["cur"]["text"] == "Deliver 30 Stone to the Hub.", "the Stone order is up")
	game._bank(game.hub.center(), D.R_STONE, 10.0)
	game.run_ticks(60)
	check(Goals.progress(game) == "10 / 30", "10 banked counts (%s)" % Goals.progress(game))
	game._bank(game.hub.center(), D.R_GLIMMER, 50.0)
	game.run_ticks(60)
	check(Goals.progress(game) == "10 / 30", "Glimmer doesn't count toward Stone")
	game._bank(game.hub.center(), D.R_STONE, 25.0)
	game.run_ticks(60)
	check(game.goals["step"] == 2, "35 banked finishes it")


func scenario_d() -> void:
	print("D. skipping the tutorial")
	fresh()
	game.run_ticks(60)
	Goals.skip_tutorial(game)
	check(game.goals["mode"] == "standing" and game.goals["cur"].is_empty(), "standing orders, nothing on the board")
	game.run_ticks(60 * 25)
	check(not game.goals["cur"].is_empty(), "a standing order is issued")
	check(game.goals["cur"]["text"].find("Stone") >= 0 or game.goals["cur"]["text"].find("Water") >= 0, "chapter 0 orders ask for Stone or Water (%s)" % game.goals["cur"]["text"])


func scenario_e() -> void:
	print("E. chapters")
	fresh()
	game.deepest = 1600
	game.run_ticks(60)
	check(game.goals["chapter"] == 1, "reaching Stone completes chapter 1")
	var found := false
	for m: Dictionary in game.milestones:
		if str(m["text"]).begins_with("Chapter 1 done"):
			found = true
	check(found, "the event tracker has it")
	game.tiers_open[2] = true
	game.deepest = 3100
	game.run_ticks(60)
	check(game.goals["chapter"] == 2, "Glimmer and depth 3000 complete chapter 2")


func scenario_f() -> void:
	print("F. research goods and the save")
	fresh()
	check(game.tech_mats_needed(game.tech_step("lamp"))[D.R_STONE] == 10, "a tier 1 tech wants 10 Stone")
	var td: Array = game.tech_mats_needed(game.tech_step("tremor_dampers"))
	check(td[D.R_STONE] == 0 and td[D.R_OBSIDIAN] == 20, "a tier 4 tech wants only its own 20 Obsidian (%s)" % str(td))
	check(Save.GAME_VARS.has("goals"), "goals are in the save")
	var enc: Variant = Save._enc(game.goals)
	check(enc != null, "the goal state encodes")
