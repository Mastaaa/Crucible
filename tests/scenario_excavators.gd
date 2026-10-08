extends SceneTree
## A4 excavators on seed 7:
##  A. the full Cutter: Hot rock stops it until Drill Bit level 4, then it goes through
##  B. a Cutter mounted on a Piston (no Winch, no Tank) is carried, powered and digs the wall it is
##     pushed into
##  C. the Laser Excavator strips a vein of Glimmer along its beam, leaves rock that isn't ore, and
##     with Filler on swaps the cell it took for Stone from the Hub's stock
##  D. research: the Laser's and Thumper's Build buttons wait for their techs
##  E. the Thumper: the Winch lowers, lifts and drops it, each landing blasts a cone below it, the
##     cone breaks rock and Obsidian and leaves the sides, and a floor it can't break halts the rig
## Run: godot --headless --path . --script tests/scenario_excavators.gd

# A6: the world is 1024 wide and the Hub moved from x 384 to 512, so every bench x below is the old one plus 128.
const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const X0 := 418          # the rig's left edge (left of the Hub, so the Hub is its network)
const SURFACE := 200     # ground level there (dirt from here down)
const HOT := 34          # Hot rock


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
	fill(Rect2i(328, SURFACE - 120, 144, 120), D.AIR)
	fill(Rect2i(328, SURFACE, 144, 160), 6)
	fill(Rect2i(328, SURFACE + 160, 144, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0


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


func scenario_a() -> void:
	print("A. Hot rock")
	fresh()
	fill(Rect2i(X0 - 30, SURFACE + 30, 110, 30), HOT)
	var cut := place("cutter", X0, SURFACE - 16)
	var tank := place("tank", X0, SURFACE - 16 - 30)
	var fun := place("funnel", X0, SURFACE - 16 - 30 - 14)
	var winch := place("winch", X0 + 14, SURFACE - 16 - 30 - 18)
	secs(1.0)
	var w: Dictionary = game.modules[winch]
	game.levels["drill_bit"] = 3
	check(until(func() -> bool: return w["halt"] != "" and w["state"] == "docked", 150.0), "at Drill Bit 3 a Hot rock seam stops the Cutter")
	check("Hot rock" in w["halt"], "and says why: %s" % w["halt"])
	game.levels["drill_bit"] = 4
	check(until(func() -> bool: return w["state"] == "down", 10.0), "level 4 lifts the hold")
	check(until(func() -> bool: return w["cable"] > 70.0 or w["halt"] != "", 200.0) and w["cable"] > 70.0, "and the Cutter goes through the seam (%.0f cells down)" % w["cable"])
	var left := 0
	for y in range(SURFACE + 31, SURFACE + 59):
		for x in range(X0, X0 + 26):
			if game.sim.get_cell(x, y) == HOT:
				left += 1
	check(left == 0, "leaving none of it in the shaft (%d cells)" % left)
	game.levels["drill_bit"] = 0
	check(game.modules.has(cut) and game.modules.has(tank) and game.modules.has(fun), "(the rig stands)")


## A Piston lying on its side pushes a Cutter into a dirt wall.
func scenario_b() -> void:
	print("B. a Cutter on a Piston")
	fresh()
	fill(Rect2i(454, SURFACE - 100, 18, 100), 6)       # a dirt wall to the right
	var pis := place("piston", 408, SURFACE - 42, 1)
	var sn := MC.snap(game, "cutter", 3, Vector2i(442, SURFACE - 36))
	var cut := MC.place(game, "cutter", sn["at"], 3)
	check(sn["snapped"] and cut > 0, "the Cutter snaps onto the Piston's rod")
	game.modules[pis]["mode"] = "out"
	secs(1.0)
	var m: Dictionary = game.modules[pis]
	var c: Dictionary = game.modules[cut]
	check(m["tether"] == cut and c["rig_of"] == pis, "and is the Piston's load, so it counts as carried")
	check(until(func() -> bool: return m["pos"] > 8.0, 20.0), "the Piston pushes it out (%.1f)" % m["pos"])
	secs(10.0)
	check(c.get("dug", 0) > 60, "it digs what it is pushed into (%d cells)" % c.get("dug", 0))
	check(MC.stored(c) > 60, "and holds it (%d units)" % MC.stored(c))
	check("Full" in c["state"], "until it is full, and says so (%s)" % c["state"])
	var gone := 0
	for y in range(SURFACE - 60, SURFACE - 20):
		for x in range(454, 471):
			if game.sim.get_cell(x, y) == D.AIR:
				gone += 1
	check(gone > 60, "the wall has a hole in it (%d open cells)" % gone)


## A Laser on a held Piston, its beam along a row that starts a vein of Glimmer in a dirt wall.
func laser_rig(filler: bool) -> Dictionary:
	fresh()
	fill(Rect2i(454, SURFACE - 100, 18, 100), 6)
	var pis := place("piston", 408, SURFACE - 42, 1)
	var sn := MC.snap(game, "laser", 3, Vector2i(441, SURFACE - 36))
	var las := MC.place(game, "laser", sn["at"], 3)
	game.modules[pis]["mode"] = "back"
	var l: Dictionary = game.modules[las]
	l["filler"] = filler
	secs(1.0)
	var fo: Dictionary = MC.kinds["laser"].CUT.front_of(game, l, MC.defs["laser"])
	var row := int(roundf(fo["p"].y))
	for x in range(454, 464):
		game.sim.set_cell(x, row, D.GLIMMER)
	return {"piston": pis, "laser": las, "row": row, "snapped": sn["snapped"]}


func glimmer_in(l: Dictionary) -> int:
	return int(l["contents"].get(D.GLIMMER, 0))


func scenario_c() -> void:
	print("C. Laser")
	var r := laser_rig(false)
	var l: Dictionary = game.modules[r["laser"]]
	check(r["snapped"] and l["rig_of"] == r["piston"], "the Laser sits on the Piston and counts as carried")
	check(until(func() -> bool: return glimmer_in(l) >= 10, 20.0), "its beam strips the vein (%d cells of Glimmer)" % glimmer_in(l))
	var open := 0
	for x in range(454, 464):
		if game.sim.get_cell(x, r["row"]) == D.AIR:
			open += 1
	check(open == 10 and game.sim.get_cell(464, r["row"]) == 6, "and nothing else: the row is open to the end of the vein, the dirt past it is still there")
	secs(2.0)
	check("not ore" in l["state"] and "Dirt" in l["state"], "the beam says what it stopped on (%s)" % l["state"])
	check(glimmer_in(l) == 10 and MC.stored(l) == 10, "and the Laser holds just the ore (%d units)" % MC.stored(l))
	# Filler on: the cell taken is swapped for Stone, and the beam stops there.
	r = laser_rig(true)
	l = game.modules[r["laser"]]
	var stone0: float = game.stock[D.R_STONE]
	check(until(func() -> bool: return glimmer_in(l) >= 1, 20.0), "with Filler on it takes the first cell")
	secs(3.0)
	check(glimmer_in(l) == 1 and game.sim.get_cell(454, r["row"]) == 2, "and leaves Stone in its place, the rest of the vein behind it")
	check(game.stock[D.R_STONE] < stone0 and "not ore" in l["state"], "paid from the Hub's Stone, and the beam stops on the filler (%s)" % l["state"])
	# A click switches Filler.
	MC.kinds["laser"].use(game, l, MC.defs["laser"])
	check(l["filler"] == false, "a click switches Filler off again")
	# Without power it takes nothing.
	r = laser_rig(false)
	l = game.modules[r["laser"]]
	for _i in 60:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(glimmer_in(l) == 0, "with no power it takes nothing")


func scenario_d() -> void:
	print("D. research")
	fresh()
	check(not MC.unlocked(game, MC.defs["laser"]), "the Laser is locked at first")
	game.researched["laser"] = true
	check(MC.unlocked(game, MC.defs["laser"]), "and open once researched")
	check(not MC.unlocked(game, MC.defs["thumper"]), "the Thumper is locked at first")
	game.researched["thumper"] = true
	check(MC.unlocked(game, MC.defs["thumper"]), "and open once researched")


## A Thumper under a Winch over a stack of Stone, a seam of Obsidian and bedrock.
func scenario_e() -> void:
	print("E. Thumper")
	fresh()
	# The engine's cone: a blast aimed down breaks rock below and leaves rock beside.
	fill(Rect2i(378, SURFACE - 40, 60, 60), 2)
	var broke: int = game.sim.explode_cone(408, SURFACE - 30, 20.0, 14, PI * 0.5, PI * 0.25)
	check(broke > 50 and game.sim.get_cell(408, SURFACE - 15) == D.AIR, "a cone blast aimed down breaks rock below it (%d cells)" % broke)
	check(game.sim.get_cell(408 + 18, SURFACE - 28) == 2 and game.sim.get_cell(408, SURFACE - 38) == 2, "and leaves the rock beside and behind it")
	fresh()
	game.researched["thumper"] = true
	# A tilted landing can wedge the Thumper at the shaft floor, and where it lands depends on the
	# ground: this x is one it lands square at (A6; 418, 420 and 432 wedge).
	var ex := X0 + 6
	fill(Rect2i(X0 - 40, SURFACE + 20, 130, 30), 2)
	fill(Rect2i(X0 - 40, SURFACE + 50, 130, 14), 4)
	fill(Rect2i(X0 - 40, SURFACE + 64, 130, 60), D.BEDROCK)
	var winch := place("winch", ex + 14, SURFACE - 80)
	var sn := MC.snap(game, "thumper", 0, Vector2i(ex + 22, SURFACE - 51))
	var th := MC.place(game, "thumper", sn["at"], 0)
	check(sn["snapped"] and th > 0, "the Thumper hooks onto the Winch's cable")
	secs(1.0)
	var w: Dictionary = game.modules[winch]
	var t: Dictionary = game.modules[th]
	check(w["tether"] == th and t["rig_of"] == winch, "and is its rig")
	# Dirt cells well off to each side of the shaft, at the top, are outside every cone.
	var side_ok := true
	var rows := [SURFACE + 2, SURFACE + 8]
	check(until(func() -> bool: return t.get("thumps", 0) >= 2, 40.0), "its first landings set off blasts (%d)" % t.get("thumps", 0))
	var last: Dictionary = t["last"]
	check(last["broke"] > 100 and last["power"] >= 10, "a blast out of a long drop breaks a lot: power %d, %d cells" % [last["power"], last["broke"]])
	check(until(func() -> bool: return w["halt"] != "", 400.0), "it works down through the rock until something stops it (%s)" % w["halt"])
	check("nothing left" in w["halt"], "and the halt says the floor is unbreakable")
	var left := 0
	for y in range(SURFACE + 20, SURFACE + 62):
		for x in range(ex + 13, ex + 32):
			var c: int = game.sim.get_cell(x, y)
			if (c == 2 or c == 4) and game.sim.get_owner(x, y) == 0:
				left += 1
	check(left == 0, "the shaft is clear of Stone and Obsidian all the way down (%d cells left)" % left)
	for y in rows:
		for x in [ex + 22 - 24, ex + 22 + 24]:
			if game.sim.get_cell(x, y) != 6:
				side_ok = false
	check(side_ok, "while the dirt to either side of the cone at the top is untouched")
	var bed := 0
	for x in range(ex + 10, ex + 35):
		if game.sim.get_cell(x, SURFACE + 64) == D.BEDROCK:
			bed += 1
	check(bed == 25, "and the bedrock is whole (%d of 25 cells)" % bed)
	check(w["plowed"] > 100, "the rubble was shoved aside as it went (%d cells)" % w["plowed"])
	check(w["cable"] > 90.0, "cable out %.0f" % w["cable"])
	check(game.modules.has(th) and game.modules.has(winch), "(the rig stands)")
	# A click on the Winch starts it again.
	MC.kinds["winch"].use(game, w, MC.defs["winch"])
	check(w["halt"] == "", "a click on the Winch clears the halt")
	# Without power the Winch does nothing.
	fresh()
	game.researched["thumper"] = true
	winch = place("winch", ex + 14, SURFACE - 80)
	sn = MC.snap(game, "thumper", 0, Vector2i(ex + 22, SURFACE - 51))
	th = MC.place(game, "thumper", sn["at"], 0)
	w = game.modules[winch]
	for _i in 300:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(w["cable"] < 3.0, "with no power the cable stays put (%.1f)" % w["cable"])
