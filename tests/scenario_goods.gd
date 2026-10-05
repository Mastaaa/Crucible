extends SceneTree
## A5 part 1, the goods bank and the Bus Hopper, on seed 7:
##  A. a Funnel banks a good under its own id and a stockpile material into the stockpile
##  B. a Bus Hopper imports what lies in its mouth and what a joined Tank passes in, and does nothing without power
##  C. a click moves it through every banked good (and Water) back to importing
##  D. exporting: it pours a good out of its mouth, hands it to a joined Tank, and exports Water
##  E. the bank survives a save and a load
##  F. research: the Bus Hopper's Build button waits for its tech
## Run: godot --headless --path . --script tests/scenario_goods.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
const Save = preload("res://scripts/save.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200     # ground level (dirt from here down)
const SAND := 31
const FLUX := 39
const SLICK := 35
const WATER := 9
const LOOSE := 7


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
		scenario_f()
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
	game.researched["bus_hopper"] = true


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


func good(mat: int) -> float:
	return float(game.goods.get(mat, 0.0))


func scenario_a() -> void:
	print("A. A Funnel banks goods")
	fresh()
	var fun := place("funnel", 300, SURFACE - 30)
	var stone0: float = game.stock[D.R_STONE]
	game.modules[fun]["contents"][FLUX] = 30
	secs(1.0)
	check(absf(good(FLUX) - 0.3) < 0.01, "30 cells of Flux bank 0.3 units of the good Flux (%.3f)" % good(FLUX))
	check(game.stock[D.R_STONE] == stone0, "and none of it went to the Stone stockpile")
	game.modules[fun]["contents"][LOOSE] = 30
	secs(1.0)
	check(absf(game.stock[D.R_STONE] - stone0 - 0.05) < 0.005 and not game.goods.has(LOOSE), "30 cells of Loose dirt still bank Stone, not a good (%.3f)" % (game.stock[D.R_STONE] - stone0))
	check(M.is_good(FLUX) and not M.is_good(LOOSE) and M.is_good(M.id_of("Slick")), "the data marks the wave 1 goods")
	var msg := ""
	for ms: Dictionary in game.milestones:
		if ms["text"].begins_with("First Flux"):
			msg = ms["text"]
	check(msg != "", "the first Flux is noted in the event log")


func hopper() -> int:
	fresh()
	var h := place("bus_hopper", 290, SURFACE - 40)
	secs(0.5)
	return h


## A Bus Hopper with a Tank resting on the ground against its in face (`feeds`: the Tank is on its left)
## or its out face (on its right). The Tank goes down first, the bolted hopper snaps to it.
func hopper_by_tank(feeds: bool) -> Dictionary:
	fresh()
	var x := 262 if feeds else 312
	var tank := place("tank", x, SURFACE - 26, 1)
	var cx := x + 30 + 13 if feeds else x - 13
	var sn := MC.snap(game, "bus_hopper", 0, Vector2i(cx, SURFACE - 20))
	var h := 0
	if sn["snapped"]:
		h = MC.place(game, "bus_hopper", sn["at"], 0)
	secs(0.5)
	return {"tank": tank, "hopper": h, "snapped": sn["snapped"] and h > 0 and tank > 0 and \
			game.modules[h]["faces"][1 if feeds else 0]["link_m"] == tank}


func scenario_b() -> void:
	print("B. A Bus Hopper imports")
	var h := hopper()
	var hm: Dictionary = game.modules[h]
	var mouth := Rect2i(290 + 2, SURFACE - 40 - 4, 22, 4)
	fill(Rect2i(296, SURFACE - 43, 10, 3), FLUX)
	check(until(func() -> bool: return good(FLUX) > 0.0, 5.0), "Flux lying in its mouth is banked (%.2f units)" % good(FLUX))
	check(absf(good(FLUX) - 0.3) < 0.06 and count_in(Rect2i(280, SURFACE - 80, 60, 80), FLUX) == 0, "all 30 cells of it, and none is left in the world (%.2f units)" % good(FLUX))
	check(hm["state"].begins_with("Importing"), "it says it is importing (%s)" % hm["state"])
	# Water in the mouth goes to the stockpile.
	var w0: float = game.stock[D.R_WATER]
	fill(Rect2i(296, SURFACE - 43, 8, 2), WATER)
	secs(2.0)
	check(game.stock[D.R_WATER] > w0, "Water in the mouth banks into the Water stockpile (%.3f)" % (game.stock[D.R_WATER] - w0))
	# A Tank joined to its in face passes in.
	var pair := hopper_by_tank(true)
	check(pair["tank"] > 0 and pair["hopper"] > 0 and pair["snapped"], "a Tank sits against its in face")
	if pair["snapped"]:
		var tank: int = pair["tank"]
		var before := good(FLUX)
		MC.add_contents(game, tank, FLUX, 60)
		check(until(func() -> bool: return good(FLUX) - before > 0.55, 12.0), "what the Tank passes in is banked too (%.2f units)" % (good(FLUX) - before))
	# No power: nothing is taken.
	h = hopper()
	fill(Rect2i(296, SURFACE - 43, 10, 3), FLUX)
	for _i in 300:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(good(FLUX) == 0.0 and count_in(Rect2i(280, SURFACE - 80, 60, 80), FLUX) == 30, "with no power it takes nothing")
	check(mouth.size.x > 0, "(mouth is %dx%d)" % [mouth.size.x, mouth.size.y])


func scenario_c() -> void:
	print("C. Clicking cycles the mode")
	var h := hopper()
	var hm: Dictionary = game.modules[h]
	var kind = MC.kinds["bus_hopper"]
	var def: Dictionary = MC.defs["bus_hopper"]
	kind.use(game, hm, def)
	check(hm.get("mode", -1) == -1, "with nothing banked a click stays on importing")
	game.goods[FLUX] = 2.0
	game.goods[SLICK] = 1.0
	kind.use(game, hm, def)
	check(hm["mode"] == SLICK, "a click picks the first banked good by id (%s)" % M.names[hm["mode"]])
	kind.use(game, hm, def)
	check(hm["mode"] == FLUX, "the next click picks the next")
	kind.use(game, hm, def)
	check(hm["mode"] == -1, "and then it is back to importing")
	game.stock[D.R_WATER] = 2.0
	kind.use(game, hm, def)
	check(hm["mode"] == WATER, "Water, which the Hub holds, comes first by id")
	kind.use(game, hm, def)
	check(hm["mode"] == SLICK, "then the goods in order")


func scenario_d() -> void:
	print("D. Exporting")
	var h := hopper()
	var hm: Dictionary = game.modules[h]
	var kind = MC.kinds["bus_hopper"]
	var def: Dictionary = MC.defs["bus_hopper"]
	game.goods[FLUX] = 1.0
	hm["mode"] = FLUX
	secs(6.0)
	var poured := count_in(Rect2i(270, SURFACE - 90, 90, 130), FLUX)
	check(good(FLUX) < 1.0 and poured > 20, "it pours Flux out of its mouth with nothing joined (%d cells in the world, %.2f banked)" % [poured, good(FLUX)])
	check(absf(good(FLUX) + float(poured) * 6.0 / 600.0 - 1.0) < 0.1, "and what is poured plus what is banked is about what there was (%.3f)" % (good(FLUX) + float(poured) * 0.01))
	# Hand over to a joined Tank.
	var pair := hopper_by_tank(false)
	check(pair["snapped"], "a Tank sits against its out face")
	if pair["snapped"]:
		var tank: int = pair["tank"]
		hm = game.modules[pair["hopper"]]
		game.goods[FLUX] = 1.0
		hm["mode"] = FLUX
		check(until(func() -> bool: return held(tank, FLUX) >= 60, 15.0), "the Flux goes into the joined Tank (%d cells)" % held(tank, FLUX))
		check(count_in(Rect2i(270, SURFACE - 90, 90, 130), FLUX) == 0, "and none is poured out of the mouth")
	# Water.
	h = hopper()
	hm = game.modules[h]
	game.stock[D.R_WATER] = 1.0
	hm["mode"] = WATER
	secs(4.0)
	var wet := count_in(Rect2i(270, SURFACE - 90, 90, 130), WATER)
	check(wet > 20 and game.stock[D.R_WATER] < 1.0, "Water is exported the same way (%d cells, %.2f left)" % [wet, game.stock[D.R_WATER]])
	# Nothing banked: nothing comes out.
	h = hopper()
	hm = game.modules[h]
	hm["mode"] = FLUX
	secs(2.0)
	check(count_in(Rect2i(270, SURFACE - 90, 90, 130), FLUX) == 0 and hm["state"].contains("none banked"), "with none banked it says so (%s)" % hm["state"])
	check(kind.info(game, hm, def).contains("Exporting Flux"), "the panel line names what it exports")


func scenario_e() -> void:
	print("E. Save and load")
	fresh()
	game.goods[FLUX] = 3.25
	game.goods[SLICK] = 0.5
	game.live_run = true
	var headless_was: bool = game.headless
	game.headless = false
	var ok: bool = game.save_run()
	game.headless = headless_was
	game.goods.clear()
	ok = ok and game.continue_run()
	check(ok and absf(good(FLUX) - 3.25) < 1e-6 and absf(good(SLICK) - 0.5) < 1e-6, "the bank is back after a load (%s)" % str(game.goods))
	Save.erase()


func scenario_f() -> void:
	print("F. research")
	fresh()
	game.researched.erase("bus_hopper")
	check(not MC.unlocked(game, MC.defs["bus_hopper"]), "the Bus Hopper is locked at first")
	game.researched["bus_hopper"] = true
	check(MC.unlocked(game, MC.defs["bus_hopper"]), "and open once researched")
	check(D.tech_index("bus_hopper") >= 0, "its tech is in the tree")
