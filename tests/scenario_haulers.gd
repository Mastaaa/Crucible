extends SceneTree
## A4 haulers on seed 7: the Drone Cage
##  A. its drones carry loose powder lying in the square round it into the cage, and on into a joined Tank
##  B. powder outside the square is left until a click makes the square bigger
##  C. rock isn't lifted, and with no power nothing is
##  D. research: the Build button waits for the tech
## Run: godot --headless --path . --script tests/scenario_haulers.gd

# A6: the world is 1024 wide and the Hub moved from x 384 to 512, so every bench x below is the old one plus 128.
const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200     # ground level (dirt from here down)
const SAND := 31


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
		scenario_nearest()
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
	fill(Rect2i(328, SURFACE - 120, 144, 120), D.AIR)
	fill(Rect2i(328, SURFACE, 144, 160), 6)
	fill(Rect2i(328, SURFACE + 160, 144, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0
	game.researched["drone_cage"] = true


func until(cond: Callable, limit: float) -> bool:
	for _i in int(limit):
		if cond.call():
			return true
		secs(1.0)
	return cond.call()


func held(id: int, mat: int) -> int:
	return int(game.modules[id]["contents"].get(mat, 0))


func count_in(r: Rect2i, mat: int) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if game.sim.get_cell(x, y) == mat:
				n += 1
	return n


## A Drone Cage on the ground with a Tank on top of it.
func cage() -> Dictionary:
	fresh()
	var cg := MC.place(game, "drone_cage", Vector2i(428, SURFACE - 20), 0)
	var sn := MC.snap(game, "tank", 0, Vector2i(441, SURFACE - 20 - 15))
	var tank := MC.place(game, "tank", sn["at"], 0)
	secs(1.0)
	return {"cage": cg, "tank": tank, "snapped": sn["snapped"] and cg > 0 and tank > 0}


func scenario_a() -> void:
	print("A. Drone Cage")
	var r := cage()
	check(r["snapped"], "a Tank joins the cage's top face")
	var tank: int = r["tank"]
	var pile := Rect2i(396, SURFACE - 6, 10, 6)
	fill(pile, SAND)
	check(until(func() -> bool: return held(tank, SAND) >= 60, 40.0), "the drones carry the pile into the Tank (%d of 60 cells)" % held(tank, SAND))
	check(count_in(Rect2i(328, SURFACE - 40, 144, 40), SAND) == 0, "and no sand is left lying about")
	check(game.modules[r["cage"]]["hauled"] >= 60, "the cage counts what it hauled (%d)" % game.modules[r["cage"]]["hauled"])


func scenario_nearest() -> void:
	print("A2. nearest first")
	var r := cage()
	fill(Rect2i(416, SURFACE - 6, 8, 6), SAND)        # about 25 cells from the cage's middle
	fill(Rect2i(390, SURFACE - 6, 8, 6), SAND)        # about 50
	secs(0.2)
	var cg: Dictionary = game.modules[r["cage"]]
	var first: Vector2 = Vector2.ZERO
	for d: Dictionary in cg["drones"]:
		if d["s"] != 0:
			first = d["t"]
			break
	check(first != Vector2.ZERO and absf(first.x - 443.0) < 35.0, "the first drone goes for the nearer pile (to x %.0f)" % first.x)
	secs(0.8)
	var targets := {}
	for d: Dictionary in cg["drones"]:
		if d["s"] != 0:
			targets[Vector2i(d["t"])] = true
	check(targets.size() >= 2, "and the others go to other spots, not the same one (%d spots)" % targets.size())


func scenario_b() -> void:
	print("B. the square")
	var r := cage()
	var tank: int = r["tank"]
	var far := Rect2i(373, SURFACE - 6, 10, 6)       # 65 cells off: outside the middle square, inside the wide one
	fill(far, SAND)
	secs(10.0)
	check(held(tank, SAND) == 0 and count_in(Rect2i(328, SURFACE - 40, 144, 40), SAND) == 60, "powder outside the square is left alone")
	MC.kinds["drone_cage"].use(game, game.modules[r["cage"]], MC.defs["drone_cage"])
	check(until(func() -> bool: return held(tank, SAND) >= 60, 40.0), "a click widens the square and it is fetched (%d of 60)" % held(tank, SAND))


func scenario_c() -> void:
	print("C. rock and power")
	var r := cage()
	var ground := count_in(Rect2i(328, SURFACE, 144, 4), 6)
	secs(15.0)
	check(count_in(Rect2i(328, SURFACE, 144, 4), 6) == ground, "the ground under the drones is left alone")
	check("No loose powder" in game.modules[r["cage"]]["state"], "and the cage says there is nothing to fetch (%s)" % game.modules[r["cage"]]["state"])
	r = cage()
	fill(Rect2i(396, SURFACE - 6, 10, 6), SAND)
	for _i in 900:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(held(r["tank"], SAND) == 0 and count_in(Rect2i(328, SURFACE - 40, 144, 40), SAND) == 60, "with no power the drones stay home")


func scenario_d() -> void:
	print("D. research")
	fresh()
	game.researched.erase("drone_cage")
	check(not MC.unlocked(game, MC.defs["drone_cage"]), "the Drone Cage is locked at first")
	game.researched["drone_cage"] = true
	check(MC.unlocked(game, MC.defs["drone_cage"]), "and open once researched")
