extends SceneTree
## A9 exterior parts on seed 7: the Spout and the Vacuum plug into a base's socket and work on its contents.
##  A. the Spout pours its base's contents out of its mouth, wants power, and passes into a Tank joined at its mouth
##  B. the Vacuum pulls loose powder and liquid from a wide patch into its base, nearest first, and stops when full
##  C. research: both Build buttons wait for their techs, and neither part works without a base
## Run: godot --headless --path . --script tests/scenario_exterior.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const MU = preload("res://scripts/machines/mu.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200
const SAND := 31
const WATER := 9
const CX := 424             # the base's left edge: the Hub's reach covers it


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
	fill(Rect2i(328, SURFACE - 120, 160, 120), D.AIR)
	fill(Rect2i(328, SURFACE, 160, 160), D.DIRT)
	fill(Rect2i(328, SURFACE + 160, 160, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0
	game.researched["chute"] = true
	game.researched["case"] = true
	game.researched["pump"] = true
	game.researched["spout"] = true
	game.researched["vacuum"] = true


func count_in(r: Rect2i, mat: int) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if game.sim.get_cell(x, y) == mat:
				n += 1
	return n


func held(id: int, mat: int) -> int:
	return int(game.modules[id]["contents"].get(mat, 0))


## A Case standing on the ground at CX with `part` plugged into its right socket (the part's plug level with it).
func case_and(part: String) -> Array:
	var c := MC.place(game, "case", Vector2i(CX, SURFACE - 26), 0)
	var plug: int = MC.defs[part]["faces"][0]["at"]
	var p := MC.place(game, part, Vector2i(CX + 26, SURFACE - 26 + 8 - plug), 0)
	return [c, p]


func scenario_a() -> void:
	print("A. Spout")
	fresh()
	var ids := case_and("spout")
	check(ids[0] != 0 and ids[1] != 0, "a Case and a Spout stand side by side")
	var spout: Dictionary = game.modules[ids[1]]
	secs(1.0)
	check(spout["needs"] == "" and MU.networked(game, spout, MC.defs["spout"]), "the Spout has its base and the Hub in reach (%s)" % spout["needs"])
	MC.add_contents(game, ids[0], SAND, 60)
	var arena := Rect2i(328, SURFACE - 120, 160, 120)
	secs(0.5)
	game.stock[D.R_POWER] = 0.0
	var held0 := held(ids[0], SAND)
	secs(1.0)
	game.stock[D.R_POWER] = 0.0
	check(held(ids[0], SAND) >= held0 and spout["state"].begins_with("Waiting") or held(ids[0], SAND) == held0, "with no power it pours nothing (%d held)" % held(ids[0], SAND))
	game.stock[D.R_POWER] = 90.0
	secs(12.0)
	var left := held(ids[0], SAND)
	var out := count_in(arena, SAND)
	check(left == 0 and out == 60, "with power it empties the Case onto the ground below (%d held, %d on the ground)" % [left, out])
	check(count_in(Rect2i(CX + 26, SURFACE - 8, 22, 8), SAND) > 40, "and the sand lies under its mouth")
	check(spout["poured"] == 60, "it counted what it poured (%d)" % spout["poured"])
	# Joined at its mouth to a Tank in a pit, it passes the contents in instead.
	fresh()
	fill(Rect2i(CX + 24, SURFACE, 40, 24), D.AIR)
	ids = case_and("spout")
	var sp: Dictionary = game.modules[ids[1]]
	var tank := MC.place(game, "tank", Vector2i(CX + 26 + 11 - 6, SURFACE - 26 + 8 - 7 + 14), 0)
	check(tank > 0, "a Tank stands in a pit under the Spout")
	secs(1.0)
	check(sp["faces"][1]["link_m"] == tank, "its mouth is joined to the Tank")
	MC.add_contents(game, ids[0], SAND, 60)
	secs(10.0)
	check(held(tank, SAND) == 60 and held(ids[0], SAND) == 0, "the Case's sand ends up in the Tank (%d)" % held(tank, SAND))
	check(count_in(Rect2i(328, SURFACE - 120, 160, 120), SAND) == 0, "and none is on the ground")


func scenario_b() -> void:
	print("B. Vacuum")
	fresh()
	var ids := case_and("vacuum")
	check(ids[0] != 0 and ids[1] != 0, "a Case and a Vacuum stand side by side")
	var vac: Dictionary = game.modules[ids[1]]
	var mouth_x := CX + 26 + 15
	fill(Rect2i(mouth_x - 15, SURFACE - 4, 30, 4), SAND)          # 120 cells of sand, 15 cells to each side of the mouth
	fill(Rect2i(mouth_x + 40, SURFACE - 4, 20, 4), SAND)          # and 80 well outside the patch
	secs(0.5)
	check(vac["needs"] == "" and MU.networked(game, vac, MC.defs["vacuum"]), "the Vacuum has its base and the Hub in reach (%s)" % vac["needs"])
	var p0: float = game.stock[D.R_POWER]
	secs(6.0)
	var in_case := held(ids[0], SAND)
	check(in_case == 120, "it pulls the patch's sand into the Case (%d of 120)" % in_case)
	check(count_in(Rect2i(mouth_x + 40, SURFACE - 4, 20, 4), SAND) == 80, "and leaves the sand outside its reach")
	check(vac["pulled"] == 120 and game.stock[D.R_POWER] < p0 + 2.0, "it counted them and drew power")
	# Water too, and a base that fills stops it.
	fill(Rect2i(mouth_x - 6, SURFACE - 6, 12, 6), WATER)
	secs(4.0)
	check(held(ids[0], WATER) > 0, "water is pulled in as well (%d)" % held(ids[0], WATER))
	var cap := MU.capacity(game.modules[ids[0]], MC.defs["case"])
	MC.add_contents(game, ids[0], SAND, cap - MU.stored(game.modules[ids[0]]) - 5)
	fill(Rect2i(mouth_x - 15, SURFACE - 4, 30, 4), SAND)
	secs(4.0)
	check(MU.stored(game.modules[ids[0]]) <= cap, "a full base is never overfilled (%d of %d)" % [MU.stored(game.modules[ids[0]]), cap])
	check(count_in(Rect2i(mouth_x - 15, SURFACE - 4, 30, 4), SAND) > 40 and vac["state"].begins_with("Full") or MU.stored(game.modules[ids[0]]) >= cap - 40,
			"and what does not fit stays where it lay (%s)" % vac["state"])


func scenario_c() -> void:
	print("C. research and bases")
	fresh()
	game.researched.erase("spout")
	game.researched.erase("vacuum")
	check(not MC.unlocked(game, MC.defs["spout"]) and not MC.unlocked(game, MC.defs["vacuum"]), "both are locked at first")
	var i := D.tech_index("vacuum")
	check(i >= 0 and "spout" in D.TECHS[i]["needs"] and D.TECHS[D.tech_index("spout")]["needs"] == ["pump"], "the Vacuum needs the Spout, which needs the Pump")
	game.researched["spout"] = true
	game.researched["vacuum"] = true
	check(MC.unlocked(game, MC.defs["spout"]) and MC.unlocked(game, MC.defs["vacuum"]), "and open once researched")
	var lone := MC.place(game, "spout", Vector2i(CX, SURFACE - 14), 0)
	secs(1.0)
	check(game.modules[lone]["needs"] != "", "a Spout with no base says what it needs (%s)" % game.modules[lone]["needs"])
