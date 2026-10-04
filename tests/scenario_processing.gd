extends SceneTree
## A4 processing on seed 7:
##  A. the Macerator grinds a loose slab at its mouth to powder, passes it to a joined Tank, leaves
##     module casings alone, and does nothing without power
##  B. the Press squeezes powder from a Tank under it into a block of rock that comes out of its
##     front as a loose body, says when something is in the way, and does nothing without power
##  C. research: both Build buttons wait for their techs
## Run: godot --headless --path . --script tests/scenario_processing.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200     # ground level (dirt from here down)
const RUBBLE := 8
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
	game.researched["macerator"] = true
	game.researched["press"] = true


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


## A Macerator on the ground with a Tank joined to its side, and a Stone slab dropped on its mouth.
func grinder() -> Dictionary:
	fresh()
	var mac := place("macerator", 316, SURFACE - 18)
	var sn := {"snapped": false}
	var turns := 1
	for t in [1, 3]:
		sn = MC.snap(game, "tank", t, Vector2i(301, SURFACE - 15))
		turns = t
		if sn["snapped"]:
			break
	var tank := MC.place(game, "tank", sn["at"], turns)
	secs(1.0)
	fill(Rect2i(323, SURFACE - 28, 16, 6), STONE)
	var slab: int = game.sim.make_body(323, SURFACE - 28, 16, 6, 0.0, 0.0, 0.0)
	return {"mac": mac, "tank": tank, "slab": slab, "snapped": sn["snapped"]}


func scenario_a() -> void:
	print("A. Macerator")
	var r := grinder()
	secs(1.0)
	check(game.modules[r["mac"]]["faces"][0]["link_m"] == r["tank"] and r["slab"] > 0, "the Tank joins the Macerator's side face and the slab becomes a body")
	var tank: int = r["tank"]
	check(until(func() -> bool: return held(tank, RUBBLE) >= 96, 20.0), "the slab is ground to Rubble in the Tank (%d cells)" % held(tank, RUBBLE))
	check(loose_bodies() == 0, "and is gone: just the two module bodies are left (%d loose)" % loose_bodies())
	check(game.modules.has(r["mac"]) and game.modules.has(tank), "the casings were left alone")
	check(held(tank, STONE) == 0, "nothing came out as Stone (%d)" % held(tank, STONE))
	# A big one is eaten away a few cells at a time and doesn't settle back into the ground.
	r = grinder()
	game.sim.remove_body(r["slab"])
	fill(Rect2i(323, SURFACE - 28, 16, 6), D.AIR)
	fill(Rect2i(317, SURFACE - 34, 24, 14), STONE)
	game.sim.make_body(317, SURFACE - 34, 24, 14, 0.0, 0.0, 0.0)
	until(func() -> bool: return held(r["tank"], RUBBLE) >= 336, 40.0)
	secs(2.0)
	check(held(r["tank"], RUBBLE) >= 336 and loose_bodies() == 0, "a 336 cell block is ground away whole (%d cells of Rubble)" % held(r["tank"], RUBBLE))
	# No power: it grinds nothing.
	r = grinder()
	for _i in 600:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(held(r["tank"], RUBBLE) == 0 and game.sim.get_cell(330, SURFACE - 21) == STONE, "with no power it grinds nothing, and the slab is still there")
	# With nowhere to put the powder it stops, and says why.
	r = grinder()
	game.modules[r["tank"]]["contents"][RUBBLE] = 1144
	game.modules[r["mac"]]["contents"][RUBBLE] = 400
	secs(0.5)
	check(loose_bodies() >= 1 and "Full" in game.modules[r["mac"]]["state"], "full, it leaves the slab alone (%s)" % game.modules[r["mac"]]["state"])


## A Press with a Tank of Rubble under it, a Stone-free arena to its right.
func presser(rubble: int) -> Dictionary:
	fresh()
	var tank := place("tank", 300, SURFACE - 30)
	var sn := MC.snap(game, "press", 0, Vector2i(313, SURFACE - 30 - 9))
	var press := MC.place(game, "press", sn["at"], 0)
	game.modules[tank]["contents"][RUBBLE] = rubble
	secs(1.0)
	return {"tank": tank, "press": press, "snapped": sn["snapped"]}


## Loose bodies in the arena (the world's own, far below, don't count).
func loose_bodies() -> int:
	var mods := {}
	for mid: int in game.modules:
		mods[game.modules[mid]["body"]] = true
	var n := 0
	var bl: PackedInt32Array = game.sim.get_bodies()
	for k in range(0, bl.size(), 7):
		if not mods.has(bl[k]) and bl[k + 4] < SURFACE + 100:
			n += 1
	return n


func scenario_b() -> void:
	print("B. Press")
	var r := presser(100)
	check(r["snapped"], "the Press sits on the Tank's top face")
	var p: Dictionary = game.modules[r["press"]]
	check(until(func() -> bool: return p.get("blocks", 0) >= 1, 30.0), "it presses a block (%s)" % p["state"])
	check(loose_bodies() == 1, "which is a loose body (%d)" % loose_bodies())
	var left: int = held(r["tank"], RUBBLE) + held(r["press"], RUBBLE)
	check(left == 4, "paid for with 96 cells of powder (%d left)" % left)
	var found := false
	for k in game.sim.get_bodies().size() / 7:
		var id: int = game.sim.get_bodies()[k * 7]
		var mods := false
		for mid: int in game.modules:
			if game.modules[mid]["body"] == id:
				mods = true
		if not mods:
			var px: PackedByteArray = game.sim.body_pixels(id)
			found = px.size() > 0 and px.count(STONE) == 96 and px.count(0) == px.size() - 96
	check(found, "a block of 96 Stone cells")
	# Something in the way: it waits.
	r = presser(100)
	p = game.modules[r["press"]]
	var fp: Rect2i = MC.kinds["press"].footprint(game, p, MC.defs["press"])
	fill(Rect2i(fp.position.x + 2, fp.position.y + 2, 3, 3), 6)
	secs(8.0)
	check(p.get("blocks", 0) == 0 and "Blocked" in p["state"], "a lump in its way holds it (%s)" % p["state"])
	# No power: no block.
	r = presser(100)
	p = game.modules[r["press"]]
	for _i in 900:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(p.get("blocks", 0) == 0, "with no power it presses nothing")
	# Short of powder it waits.
	r = presser(40)
	p = game.modules[r["press"]]
	secs(5.0)
	check(p.get("blocks", 0) == 0 and "Waiting for powder" in p["state"], "short of powder it waits (%s)" % p["state"])


func scenario_c() -> void:
	print("C. research")
	fresh()
	game.researched.erase("macerator")
	game.researched.erase("press")
	check(not MC.unlocked(game, MC.defs["macerator"]) and not MC.unlocked(game, MC.defs["press"]), "both are locked at first")
	game.researched["macerator"] = true
	game.researched["press"] = true
	check(MC.unlocked(game, MC.defs["macerator"]) and MC.unlocked(game, MC.defs["press"]), "and open once researched")
