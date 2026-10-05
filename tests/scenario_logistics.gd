extends SceneTree
## A4 logistics on seed 7:
##  A. a line of Chutes carries a Tank's powder up to another Tank
##  B. the Conveyor lifts powder off its top surface and delivers it at the far end into a joined
##     Tank, lets it fall off the end when nothing is joined, carries a loose body along, reverses
##     on a click, and does nothing without power
##  C. research: both Build buttons wait for their techs
## Run: godot --headless --path . --script tests/scenario_logistics.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200     # ground level (dirt from here down)
const SAND := 31
const STONE := 2


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
	fill(Rect2i(200, SURFACE - 120, 144, 120), D.AIR)
	fill(Rect2i(200, SURFACE, 144, 160), 6)
	fill(Rect2i(200, SURFACE + 160, 144, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0
	game.researched["chute"] = true
	game.researched["conveyor"] = true


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


func count_in(r: Rect2i, mat: int) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if game.sim.get_cell(x, y) == mat:
				n += 1
	return n


## Loose bodies in the arena (the world's own, far below, don't count).
func loose_bodies() -> Array:
	var mods := {}
	for mid: int in game.modules:
		mods[game.modules[mid]["body"]] = true
	var out: Array = []
	var bl: PackedInt32Array = game.sim.get_bodies()
	for k in range(0, bl.size(), 7):
		if not mods.has(bl[k]) and bl[k + 4] < SURFACE + 100:
			out.append(bl[k])
	return out


func scenario_a() -> void:
	print("A. Chutes")
	fresh()
	var low := place("tank", 300, SURFACE - 30)
	var sn1 := MC.snap(game, "chute", 0, Vector2i(313, SURFACE - 30 - 12))
	var c1 := MC.place(game, "chute", sn1["at"], 0)
	var sn2 := MC.snap(game, "chute", 0, Vector2i(sn1["at"].x + 7, sn1["at"].y - 12))
	var c2 := MC.place(game, "chute", sn2["at"], 0)
	var sn3 := MC.snap(game, "tank", 0, Vector2i(sn2["at"].x + 7, sn2["at"].y - 15))
	var high := MC.place(game, "tank", sn3["at"], 0)
	check(sn1["snapped"] and sn2["snapped"] and sn3["snapped"] and c1 > 0 and c2 > 0 and high > 0, "two Chutes and a Tank snap on above the first Tank")
	MC.add_contents(game, low, SAND, 100)
	check(until(func() -> bool: return held(high, SAND) >= 100, 20.0), "the Tank's powder comes out at the top of the line (%d cells)" % held(high, SAND))
	check(held(low, SAND) == 0 and held(c1, SAND) == 0 and held(c2, SAND) == 0, "and none is left on the way")


## A Conveyor held up off the ground, the belt 50 long over x 284..334 with its top at SURFACE - 18.
func belt(reversed: bool) -> Dictionary:
	fresh()
	var con := place("conveyor", 284, SURFACE - 18)
	if reversed:
		MC.kinds["conveyor"].use(game, game.modules[con], MC.defs["conveyor"])
	var tank := 0
	var joined := false
	if reversed:
		for t in [1, 3]:
			var sn := MC.snap(game, "tank", t, Vector2i(269, SURFACE - 13))
			if sn["snapped"]:
				tank = MC.place(game, "tank", sn["at"], t)
				joined = true
				break
	secs(1.0)
	return {"con": con, "tank": tank, "snapped": joined or not reversed}


func scenario_b() -> void:
	print("B. Conveyor")
	var r := belt(true)
	check(r["snapped"] and r["tank"] > 0, "a Tank joins the end the belt carries to")
	var tank: int = r["tank"]
	var con: Dictionary = game.modules[r["con"]]
	check(con["dir"] == -1, "a click reversed the belt")
	fill(Rect2i(300, SURFACE - 22, 8, 4), SAND)
	check(until(func() -> bool: return held(tank, SAND) >= 32, 25.0), "powder on the belt is delivered into the Tank (%d cells)" % held(tank, SAND))
	check(count_in(Rect2i(284, SURFACE - 22, 50, 4), SAND) == 0, "and none is left on the belt")
	# Nothing joined: it falls off the end.
	r = belt(false)
	con = game.modules[r["con"]]
	fill(Rect2i(300, SURFACE - 22, 8, 4), SAND)
	secs(15.0)
	var off := count_in(Rect2i(335, SURFACE - 60, 9, 60), SAND)
	var all := count_in(Rect2i(200, SURFACE - 120, 144, 120), SAND)
	check(off >= 10 and all == 32 and count_in(Rect2i(284, SURFACE - 22, 50, 4), SAND) == 0, "with nothing joined it lets the powder fall off the far end (%d cells past it, %d of 32 in all)" % [off, all])
	# A loose body lying on it rides.
	r = belt(false)
	con = game.modules[r["con"]]
	fill(Rect2i(296, SURFACE - 32, 14, 6), STONE)
	var slab: int = game.sim.make_body(296, SURFACE - 32, 14, 6, 0.0, 0.0, 0.0)
	secs(0.8)
	var st: PackedFloat32Array = game.sim.body_state(slab)
	var x0 := st[0]
	secs(1.0)
	st = game.sim.body_state(slab)
	check(st.size() > 0 and st[0] - x0 > 8.0, "a Stone slab on the belt is carried along (%.0f cells in a second)" % (st[0] - x0 if st.size() > 0 else 0.0))
	# No power: nothing moves.
	r = belt(false)
	con = game.modules[r["con"]]
	fill(Rect2i(300, SURFACE - 22, 8, 4), SAND)
	for _i in 600:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(count_in(Rect2i(284, SURFACE - 22, 50, 4), SAND) == 32 and con["queue"].is_empty(), "with no power the powder stays on the belt")


func scenario_c() -> void:
	print("C. research")
	fresh()
	game.researched.erase("chute")
	game.researched.erase("conveyor")
	check(not MC.unlocked(game, MC.defs["chute"]) and not MC.unlocked(game, MC.defs["conveyor"]), "both are locked at first")
	game.researched["chute"] = true
	game.researched["conveyor"] = true
	check(MC.unlocked(game, MC.defs["chute"]) and MC.unlocked(game, MC.defs["conveyor"]), "and open once researched")
