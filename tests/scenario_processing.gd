extends SceneTree
## A4 processing on seed 7, A9 recut (the Press plugs into a Tank's side; the Macerator is a strip between two Tanks):
##  A. the Macerator grinds a loose slab at its mouth, and static rock its in Tank holds, to powder in its out Tank,
##     leaves module casings alone, and does nothing without power
##  B. the Press squeezes powder from the Tank beside it into a block of rock that comes out of its
##     front as a loose body, keeps that powder in the Tank, says when something is in the way, and does nothing without power
##  C. research: both Build buttons wait for their techs
##  D. a save from before the recut returns the old processing parts to stock; a current save keeps its parts
## Run: godot --headless --path . --script tests/scenario_processing.gd

# A6: the world is 1024 wide and the Hub moved from x 384 to 512, so every bench x below is the old one plus 128.
const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
const Save = preload("res://scripts/save.gd")
const BW = preload("res://scripts/machines/processing/base_work.gd")
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


## A Macerator strip on the ground with a Tank joined on each side, and a Stone slab dropped on its mouth.
func grinder() -> Dictionary:
	fresh()
	var left := place("tank", 386, SURFACE - 30)
	var sn := MC.snap(game, "macerator", 0, Vector2i(425, SURFACE - 8))
	var mac := MC.place(game, "macerator", sn["at"], 0)
	var sn2 := MC.snap(game, "tank", 0, Vector2i(451, SURFACE - 15))
	var right := MC.place(game, "tank", sn2["at"], 0)
	secs(1.0)
	fill(Rect2i(417, SURFACE - 22, 16, 6), STONE)
	var slab: int = game.sim.make_body(417, SURFACE - 22, 16, 6, 0.0, 0.0, 0.0)
	return {"mac": mac, "left": left, "tank": right, "slab": slab, "snapped": sn["snapped"] and sn2["snapped"]}


func scenario_a() -> void:
	print("A. Macerator")
	var r := grinder()
	secs(1.0)
	var mac: Dictionary = game.modules[r["mac"]]
	check(r["snapped"] and mac["faces"][0]["link_m"] == r["left"] and mac["faces"][1]["link_m"] == r["tank"] and r["slab"] > 0, "a Tank joins each side and the slab becomes a body")
	var tank: int = r["tank"]
	check(until(func() -> bool: return held(tank, RUBBLE) >= 96, 20.0), "the slab is ground to Rubble in the out Tank (%d cells)" % held(tank, RUBBLE))
	check(loose_bodies() == 0, "and is gone: just the module bodies are left (%d loose)" % loose_bodies())
	check(game.modules.has(r["mac"]) and game.modules.has(tank) and game.modules.has(r["left"]), "the casings were left alone")
	check(held(tank, STONE) == 0, "nothing came out as Stone (%d)" % held(tank, STONE))
	# A big one is eaten away a few cells at a time and doesn't settle back into the ground.
	r = grinder()
	game.sim.remove_body(r["slab"])
	fill(Rect2i(417, SURFACE - 22, 16, 6), D.AIR)
	fill(Rect2i(413, SURFACE - 36, 24, 14), STONE)
	game.sim.make_body(413, SURFACE - 36, 24, 14, 0.0, 0.0, 0.0)
	until(func() -> bool: return held(r["tank"], RUBBLE) >= 336, 40.0)
	secs(2.0)
	check(held(r["tank"], RUBBLE) >= 336 and loose_bodies() == 0, "a 336 cell block is ground away whole (%d cells of Rubble)" % held(r["tank"], RUBBLE))
	# Rock the in Tank holds is ground too.
	r = grinder()
	game.sim.remove_body(r["slab"])
	fill(Rect2i(417, SURFACE - 22, 16, 6), D.AIR)
	MC.add_contents(game, r["left"], STONE, 60)
	check(until(func() -> bool: return held(r["tank"], RUBBLE) >= 60, 20.0) and held(r["left"], STONE) == 0, "Stone in the in Tank comes out as Rubble in the out Tank (%d)" % held(r["tank"], RUBBLE))
	# No power: it grinds nothing.
	r = grinder()
	for _i in 600:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(held(r["tank"], RUBBLE) == 0 and game.sim.get_cell(425, SURFACE - 19) == STONE, "with no power it grinds nothing, and the slab is still there")
	# With nowhere to put the powder it stops, and says why.
	r = grinder()
	MC.add_contents(game, r["tank"], RUBBLE, 1144)
	secs(0.5)
	check(loose_bodies() >= 1 and "Full" in game.modules[r["mac"]]["state"], "full, it leaves the slab alone (%s)" % game.modules[r["mac"]]["state"])
	# Without a Tank on each side it says so.
	fresh()
	var lone := place("macerator", 444, SURFACE - 16)
	secs(1.0)
	check("base" in game.modules[lone]["state"], "alone it asks for a base on each side (%s)" % game.modules[lone]["state"])


## A Press plugged into the right of a Tank of Rubble (or its left, with `side` -1), a Stone-free arena beside it.
func presser(rubble: int, side := 1) -> Dictionary:
	fresh()
	if side < 0:      # the Hub is out of reach of a part on that side
		var node = game.place(D.B_NODE, Rect2i(352, SURFACE - 20, 20, 20))
		node.built = true
		game.scan_dirty = true
		game.net_dirty = true
	var tank := place("tank", 410, SURFACE - 30)
	var cx := 410 + 26 + 10 if side > 0 else 410 - 10
	var sn := MC.snap(game, "press", 0, Vector2i(cx, SURFACE - 15))
	var press := MC.place(game, "press", sn["at"], 0)
	MC.add_contents(game, tank, RUBBLE, rubble)
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
	check(r["snapped"], "the Press plugs into the Tank's side")
	var p: Dictionary = game.modules[r["press"]]
	# A pressed block that lands in the ground settles back into it after 30 still ticks,
	# so this waits a tick at a time and looks at the body the tick the block appears.
	for _i in 1800:
		if p.get("blocks", 0) >= 1:
			break
		game.run_ticks(1)
	check(p.get("blocks", 0) >= 1, "it presses a block (%s)" % p["state"])
	check(loose_bodies() == 1, "which is a loose body (%d)" % loose_bodies())
	var left: int = held(r["tank"], RUBBLE)
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
	# While it works the Tank keeps the powder in.
	r = presser(100)
	var tank_m: Dictionary = game.modules[r["tank"]]
	check(BW.may_leave(game, tank_m, RUBBLE) == false, "the Press holds its powder in its Tank")
	# It sits on either side.
	r = presser(100, -1)
	p = game.modules[r["press"]]
	for _i in 1800:
		if p.get("blocks", 0) >= 1:
			break
		game.run_ticks(1)
	check(r["snapped"] and p.get("blocks", 0) >= 1, "plugged into the Tank's left it presses too (%s)" % p["state"])
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


## A Press and a Macerator joined to Tanks, saved as the current version and as a version 4 file.
func scenario_d() -> void:
	print("D. a save from before the recut")
	var path := "user://processing_test.save"
	var tank: int = grinder()["left"]
	var sn := MC.snap(game, "press", 0, Vector2i(386 - 10, SURFACE - 15))
	var press := MC.place(game, "press", sn["at"], 0)
	secs(1.0)
	Save.write(game, path)
	game.continue_run(path)
	check(game.modules.has(press) and game.modules.size() >= 4, "a current save keeps its processing parts (%d modules)" % game.modules.size())
	var kept: int = game.modules.size()
	var stone: float = game.stock[D.R_STONE]
	# Patch the version word (bytes 4 to 7) back to 4.
	var fa := FileAccess.open(path, FileAccess.READ_WRITE)
	fa.seek(4)
	fa.store_32(4)
	fa.close()
	game.continue_run(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(not game.modules.has(press) and game.modules.size() == kept - 2, "a version 4 save loses its old Press and Macerator (%d modules left of %d)" % [game.modules.size(), kept])
	check(game.modules.has(tank), "but not the Tank beside it")
	var linked := false
	for fs: Dictionary in game.modules[tank]["faces"]:
		linked = linked or fs["link_m"] != 0
	check(not linked, "whose socket is free again")
	check(absf(game.stock[D.R_STONE] - (stone + 24.0)) < 0.5, "their price (24 Stone) is back in stock (%.1f from %.1f)" % [game.stock[D.R_STONE], stone])
