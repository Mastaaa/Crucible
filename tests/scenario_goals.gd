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
	check(game.goals["cur"].get("n", 0) == 1 and game.goals["cur"]["text"] == "Build a Lab.", "Instruction 1 is on the board")
	check(is_equal_approx(D.HUB_POWER_PER_S, 0.2), "the Hub trickle is 0.2 power/s")


func scenario_b() -> void:
	print("B. tutorial steps pay out")
	fresh()
	game.stock[D.R_POWER] = 0.0
	game.run_ticks(60)
	var lab = game.place(D.B_LAB, Rect2i(game.hub.x + 4 * D.S, game.hub.y + game.hub.h - 3 * D.S, 4 * D.S, 3 * D.S))
	for _i in 600:
		if lab.built:
			break
		game.run_ticks(1)
	game.run_ticks(60)
	check(game.goals["step"] == 1, "building a Lab completes Instruction 1")
	check(game.stock[D.R_POWER] >= 90.0, "it paid about 100 power into the Hub (%.1f)" % game.stock[D.R_POWER])
	check(game.goals["cur"].get("n", 0) == 2, "Instruction 2 follows")


func scenario_c() -> void:
	print("C. delivery orders")
	fresh()
	game.goals["step"] = 2
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
	check(game.goals["step"] == 3, "35 banked finishes it")


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
	var fg: Array = game.tech_mats_needed(game.tech_step("floodgate"))
	check(fg[D.R_STONE] == 20 and fg[D.R_GLIMMER] == 10, "Floodgate wants 20 Stone and its 10 Glimmer")
	check(Save.GAME_VARS.has("goals"), "goals are in the save")
	var enc: Variant = Save._enc(game.goals)
	check(enc != null, "the goal state encodes")
