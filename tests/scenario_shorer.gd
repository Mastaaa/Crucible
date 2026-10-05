extends SceneTree
## A5 part 6, the Shorer, on seed 7:
##  A. it sets powder as rock into the open air of its strip, a cell for a cell, and stops when the strip is full
##  B. it never displaces liquid or ground, and refuses what it cannot set (Water, Ash)
##  C. fed from a Tank joined under it, it shores from the Tank's Rubble
##  D. with no power it lays nothing
##  E. research gates the Build button
## Run: godot --headless --path . --script tests/scenario_shorer.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200     # ground level (dirt from here down)
const STONE := 2
const WATER := 9
const RUBBLE := 8
const ASH := 21
const SAND := 31
const GLASS := 43


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
		scenario_e()
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
	fill(Rect2i(200, SURFACE - 120, 144, 120), D.AIR)
	fill(Rect2i(200, SURFACE, 144, 160), 6)
	fill(Rect2i(200, SURFACE + 160, 144, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0
	game.researched["shorer"] = true


func place(def: String, x: int, y: int, turns: int = 0) -> int:
	var id := MC.place(game, def, Vector2i(x, y), turns)
	if id == 0:
		print("  !! can't place %s at %d,%d: %s" % [def, x, y, MC.check_place(game, def, Vector2i(x, y), turns)])
	return id


func held(id: int, mat: int) -> int:
	return int(game.modules[id]["contents"].get(mat, 0))


func count(r: Rect2i, mat: int) -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	mask[mat] = 1
	return game.sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)


## A Shorer on the ground at x 300 (front left, so its strip is the 3 columns to its left, 16 rows).
func shorer_on_ground() -> int:
	fresh()
	var id := place("shorer", 300, SURFACE - 16)
	secs(0.3)
	return id


const STRIP := Rect2i(297, SURFACE - 16, 3, 16)


func scenario_a() -> void:
	print("A. Shorer")
	var id := shorer_on_ground()
	check(MC.add_contents(game, id, RUBBLE, 60) == 60, "it takes 60 cells of Rubble")
	secs(1.1)
	check(count(STRIP, STONE) == 48, "the strip fills with Stone, 3 by 16 cells (%d)" % count(STRIP, STONE))
	check(held(id, RUBBLE) == 12, "paid for a cell for a cell (%d Rubble left)" % held(id, RUBBLE))
	check("full" in game.modules[id]["state"], "and it says the strip is full (%s)" % game.modules[id]["state"])
	check(game.modules[id].get("laid", 0) == 48, "48 laid, counted")
	# Cells that hang free weather away in time, and it lays them again.
	secs(20.0)
	check(count(STRIP, STONE) >= 44, "left alone it keeps the strip in repair (%d Stone, %d laid in all)" % [count(STRIP, STONE), game.modules[id].get("laid", 0)])


func scenario_b() -> void:
	print("B. what it leaves alone and refuses")
	var id := shorer_on_ground()
	game.sim.set_cell(298, SURFACE - 5, WATER)
	game.sim.set_cell(299, SURFACE - 3, 6)
	MC.add_contents(game, id, RUBBLE, 60)
	secs(1.1)
	check(game.sim.get_cell(299, SURFACE - 3) == 6, "a lump of ground in the strip stays")
	check(count(STRIP, STONE) <= 46 and count(STRIP, STONE) >= 40, "the rest fills round them (%d Stone)" % count(STRIP, STONE))
	check(MC.add_contents(game, id, WATER, 10) == 0 and MC.add_contents(game, id, ASH, 10) == 0, "Water and Ash are refused")
	id = shorer_on_ground()
	check(MC.add_contents(game, id, SAND, 5) == 5, "Sand is taken")
	secs(1.0)
	check(count(STRIP, GLASS) == 5, "and sets as Glass (%d Glass)" % count(STRIP, GLASS))


func scenario_c() -> void:
	print("C. fed from a Tank")
	fresh()
	var tank := place("tank", 300, SURFACE - 30)
	var sn := MC.snap(game, "shorer", 0, Vector2i(309, SURFACE - 30 - 8))
	var sh := MC.place(game, "shorer", sn["at"], 0)
	MC.add_contents(game, tank, RUBBLE, 40)
	secs(6.0)
	var left: int = sn["at"].x
	var r := Rect2i(left - 3, SURFACE - 30 - 16, 3, 16)
	check(sn["snapped"], "the Shorer sits on the Tank")
	check(count(r, STONE) >= 30, "it shores from the Tank's Rubble (%d Stone beside it)" % count(r, STONE))
	check(held(tank, RUBBLE) + held(sh, RUBBLE) <= 10, "and the Tank is emptied of it (%d + %d left)" % [held(tank, RUBBLE), held(sh, RUBBLE)])


func scenario_d() -> void:
	print("D. no power")
	var id := shorer_on_ground()
	MC.add_contents(game, id, RUBBLE, 60)
	for _i in 600:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(count(STRIP, STONE) == 0, "with no power it lays nothing (%d)" % count(STRIP, STONE))


func scenario_e() -> void:
	print("E. research")
	fresh()
	game.researched.erase("shorer")
	check(not MC.unlocked(game, MC.defs["shorer"]), "locked at first")
	game.researched["shorer"] = true
	check(MC.unlocked(game, MC.defs["shorer"]), "open once researched")
	var i: int = D.tech_index("shorer")
	check(i >= 0 and D.TECHS[i].get("module", "") == "shorer" and "press" in D.TECHS[i]["needs"], "its tech needs the Press")
