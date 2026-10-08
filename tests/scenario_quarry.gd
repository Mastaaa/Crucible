extends SceneTree
## A3 starter kit on seed 7, a rig left of the Hub (so the Hub is its network):
##  A. assembly: Excavator, Tank, Funnel and Winch placed by contact join; the Winch hooks
##     the Tank, the rig is Tank plus Excavator, bolted modules hold still
##  B. a trip: the rig digs soft ground (a 30-wide tunnel, edges wobbling), lowers as rows
##     open, hauls up when the Tank is full, empties through the Funnel into the Hub's
##     stock, and goes down again
##  C. limits: Stone stops the Excavator until Drill Bit lifts its hardness; the cable
##     length is Drill Shaft's; no power or no Node or Hub in reach holds the rig
##  D. the Windmill makes power in open sky (and not under a roof or out of network reach)
##  E. placement: the Build list's click snaps onto a free face and charges the cost
##  F. a save keeps the rig, and it goes on after loading
##  G. loose sand slumped into the shaft behind the rig (the seed 7 jam): the Tank's hook stays
##     shut, and the rig ploughs up through the sand to the Funnel instead of jamming
##  H. a static plug (Stone) set across the shaft over the rig (a cave-in): the rig ploughs through it too,
##     and the shaft's walls and the rig's own casing stay
##  I. a rubble cell under the Tank's overhang as the rig goes down (the A5 bot's stall at depth 638):
##     the Winch shoves it aside instead of the Tank stopping on it while the Cutter goes on
##  J. a corner pixel of the Cutter's own casing, rounded into the slice in front of it by a tilted body (the A5
##     bot's "Obsidian ahead" at depth 2256), is not a wall; Obsidian that is nobody's still is
##  K. a docked Tank that holds a good the full goods bank cannot take says so ("The goods bank is full"), not just
##     "Emptying."; with room in the bank the Funnel takes the good and the rig goes on
## Run: godot --headless --path . --script tests/scenario_quarry.gd

# A6: the world is 1024 wide and the Hub moved from x 384 to 512, so every bench x below is the old one plus 128.
const D = preload("res://scripts/defs.gd")
const F = preload("res://scripts/machines/faces.gd")
const MC = preload("res://scripts/machines/machines.gd")
const Save = preload("res://scripts/save.gd")
const M = preload("res://scripts/materials.gd")
const Winch = preload("res://scripts/machines/movers/winch.gd")
const Cutter = preload("res://scripts/machines/excavation/cutter.gd")
var game: Node
var f := 0
var fails := 0
var verbose := false
const X0 := 418          # the rig's left edge
const SURFACE := 200     # ground level there (dirt from here down)


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		verbose = OS.get_cmdline_user_args().has("--verbose")
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
		scenario_g()
		scenario_h()
		scenario_i()
		scenario_j()
		scenario_k()
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
	# Open sky over a column of dirt 160 deep, then bedrock.
	fill(Rect2i(X0 - 30, SURFACE - 120, 110, 120), D.AIR)
	fill(Rect2i(X0 - 30, SURFACE, 110, 160), 6)
	fill(Rect2i(X0 - 30, SURFACE + 160, 110, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0


func place(def: String, x: int, y: int) -> int:
	var id := MC.place(game, def, Vector2i(x, y), 0)
	if id == 0:
		print("  !! can't place %s at %d,%d: %s" % [def, x, y, MC.check_place(game, def, Vector2i(x, y), 0)])
	return id


## The starter rig: Cutter on the ground, Tank on it, Funnel and Winch bolted on top.
func build_rig() -> Dictionary:
	var cut := place("cutter", X0, SURFACE - 16)
	var tank := place("tank", X0, SURFACE - 16 - 30)
	var fun := place("funnel", X0, SURFACE - 16 - 30 - 14)
	var winch := place("winch", X0 + 14, SURFACE - 16 - 30 - 18)
	secs(1.0)
	return {"cut": cut, "tank": tank, "fun": fun, "winch": winch}


func winch_of(r: Dictionary) -> Dictionary:
	return game.modules[r["winch"]]


## Runs until `cond` is true (checked every second) or `limit` seconds pass; true if it came.
func until(cond: Callable, limit: float) -> bool:
	for _i in int(limit):
		if cond.call():
			return true
		secs(1.0)
	return cond.call()


## Cells of the tunnel row `y` between x0 and x1 that are open.
func open_in_row(y: int, x0: int, x1: int) -> int:
	var n := 0
	for x in range(x0, x1):
		if game.sim.get_cell(x, y) == D.AIR:
			n += 1
	return n


func scenario_a() -> void:
	print("A. assembly")
	fresh()
	var r := build_rig()
	var w := winch_of(r)
	check(w["tether"] == r["tank"], "the Winch hooked the Tank")
	check(w["rig"].size() == 2 and w["rig"].has(r["tank"]) and w["rig"].has(r["cut"]), "the rig is the Tank and the Cutter (the Funnel is bolted)")
	var tk: Dictionary = game.modules[r["tank"]]
	check(tk["faces"][0]["link_m"] == r["fun"], "the Tank's top pixel face joined the Funnel")
	check(tk["faces"][2]["link_m"] == r["cut"], "the Tank's bottom face joined the Cutter")
	check(game.modules[r["cut"]]["powered"], "the rig has power from the Hub")
	secs(20.0)
	var fun: int = game.modules[r["fun"]]["body"]
	check(game.sim.get_owner(X0 + 1, SURFACE - 60 + 1) == fun and game.sim.get_owner(X0 + 12, SURFACE - 47) == fun, "the bolted Funnel is where it was put")
	check(game.sim.get_owner(X0 + 15, SURFACE - 64 + 1) == w["body"], "and so is the Winch")
	check(w["cable"] > 10.0, "while the rig has gone down the shaft on the cable (%.0f cells)" % w["cable"])


func scenario_b() -> void:
	print("B. a trip")
	fresh()
	var r := build_rig()
	var w := winch_of(r)
	var stone0: float = game.stock[D.R_STONE]
	check(until(func() -> bool: return w["state"] == "up", 60.0), "the Tank fills and the Winch hauls up")
	var maxc := int(w["cable"])
	check(until(func() -> bool: return w["state"] == "docked", 40.0), "the rig docks with the Funnel")
	var edges := {}
	var intact := 0
	for y in range(SURFACE + 2, SURFACE + maxc - 2):
		for x in range(X0, X0 + 26):
			if game.sim.get_cell(x, y) == 6:
				intact += 1
		for x in range(X0 - 10, X0 + 40):
			if game.sim.get_cell(x, y) == D.AIR:
				edges[x] = true
				break
	check(intact == 0, "the shaft is cut through the whole width of the rig (%d cells of dirt left in it)" % intact)
	check(edges.size() >= 2, "and its edge wobbles (%d different left edges)" % edges.size())
	check(game.sim.get_cell(X0 - 16, SURFACE + 20) == 6 and game.sim.get_cell(X0 + 45, SURFACE + 20) == 6, "the ground beside it is left alone")
	check(until(func() -> bool: return w["state"] == "down", 20.0), "and goes down again once the Funnel has emptied the Tank")
	check(game.stock[D.R_STONE] - stone0 > 1.0, "the Hub banked Stone from the trip (%.2f)" % (game.stock[D.R_STONE] - stone0))
	var cut: Dictionary = game.modules[r["cut"]]
	var held := MC.stored(game.modules[r["tank"]]) + MC.stored(cut) + MC.stored(game.modules[r["fun"]])
	check(cut["dug"] == game.modules[r["fun"]]["banked"] + held, "every cell dug is banked or still held (%d = %d + %d)" % [cut["dug"], game.modules[r["fun"]]["banked"], held])


func scenario_c() -> void:
	print("C. limits")
	fresh()
	fill(Rect2i(X0 - 30, SURFACE + 30, 110, 30), 2)       # a Stone seam
	var r := build_rig()
	var w := winch_of(r)
	check(until(func() -> bool: return w["halt"] != "" and w["state"] == "docked", 150.0), "Stone stops the Cutter and the rig comes up to wait")
	check("Stone" in w["halt"], "and says why: %s" % w["halt"])
	secs(5.0)
	check(w["state"] == "docked", "it stays up while research hasn't changed")
	game.levels["drill_bit"] = 1
	check(until(func() -> bool: return w["state"] == "down", 5.0), "Drill Bit lifts the hold")
	check(until(func() -> bool: return w["cable"] > 70.0 or w["halt"] != "", 120.0), "and the Cutter goes through the seam")
	check(w["cable"] > 70.0, "to %.0f cells down" % w["cable"])
	check(w["limit"] == D.SHAFT_REACHES[0], "the cable is Drill Shaft's length (%d)" % w["limit"])
	game.levels["drill_shaft"] = 1
	secs(1.0)
	check(w["limit"] == D.SHAFT_REACHES[1], "and a level longer: %d" % w["limit"])
	game.levels["drill_bit"] = 0
	game.levels["drill_shaft"] = 0
	# Out of the network's reach: nothing moves.
	fresh()
	fill(Rect2i(600, SURFACE - 120, 120, 120), D.AIR)
	fill(Rect2i(600, SURFACE, 120, 100), 6)
	var far := {}
	far["cut"] = MC.place(game, "cutter", Vector2i(620, SURFACE - 16), 0)
	far["tank"] = MC.place(game, "tank", Vector2i(620, SURFACE - 46), 0)
	far["fun"] = MC.place(game, "funnel", Vector2i(620, SURFACE - 60), 0)
	far["winch"] = MC.place(game, "winch", Vector2i(634, SURFACE - 64), 0)
	secs(5.0)
	var fw := winch_of(far)
	check(not fw["net"] and fw["cable"] < 2.0 and "reach" in fw["why"], "a rig with no Node or Hub in reach holds still (%s)" % fw["why"])


func scenario_d() -> void:
	print("D. windmill")
	fresh()
	var wm := MC.place(game, "windmill", Vector2i(X0 + 32, SURFACE - 36), 0)
	secs(3.0)
	var m: Dictionary = game.modules[wm]
	var lo := 9.0
	var hi := 0.0
	game.stock[D.R_POWER] = 10.0
	for _i in 14:
		secs(1.0)
		lo = minf(lo, m["flow"])
		hi = maxf(hi, m["flow"])
	check(lo > 0.0 and hi > lo * 1.3, "it turns in the gusts (%.2f to %.2f power/s)" % [lo, hi])
	check(game.stock[D.R_POWER] > 10.0 + 14.0 * (D.HUB_POWER_PER_S + 0.1), "and the Hub's stock gains it (%.1f)" % game.stock[D.R_POWER])
	fill(Rect2i(X0 + 30, SURFACE - 60, 20, 6), D.BEDROCK)
	secs(1.0)
	check(m["flow"] == 0.0 and "sky" in m["why"], "a roof over it stops it: %s" % m["why"])
	fill(Rect2i(600, SURFACE - 120, 120, 120), D.AIR)
	fill(Rect2i(600, SURFACE, 120, 100), 6)
	var far := MC.place(game, "windmill", Vector2i(620, SURFACE - 36), 0)
	secs(2.0)
	check(game.modules[far]["flow"] == 0.0 and "reach" in game.modules[far]["why"], "out of the network's reach it feeds nothing: %s" % game.modules[far]["why"])


func scenario_e() -> void:
	print("E. placement")
	fresh()
	var tank := place("tank", X0, SURFACE - 30)
	secs(1.0)
	game.stock[D.R_STONE] = 20.0
	game.module_pick = "funnel"
	game.module_turns = 0
	var want := Vector2i(X0, SURFACE - 44)
	var sn := MC.snap(game, "funnel", 0, want + Vector2i(11, 8))
	check(sn["snapped"] and sn["at"] == want, "a Funnel held near the Tank's top face snaps onto it (%s)" % str(sn["at"]))
	var far := MC.snap(game, "funnel", 0, Vector2i(X0 - 25, SURFACE - 100))
	check(not far["snapped"], "one held far from any face doesn't")
	var n: int = game.modules.size()
	MC.click(game, want + Vector2i(11, 8))
	check(game.modules.size() == n + 1 and game.stock[D.R_STONE] == 16.0, "a click places it and charges its cost (4 Stone)")
	game.stock[D.R_STONE] = 1.0
	MC.click(game, Vector2i(X0 + 60, SURFACE - 60))
	check(game.modules.size() == n + 1 and game.stock[D.R_STONE] == 1.0, "without the Stone the click places nothing")
	game.module_pick = ""
	check(not MC.module_at(game, Vector2i(X0 + 1, SURFACE - 30 + 1)).is_empty() and MC.module_at(game, Vector2i(X0 + 200, SURFACE - 80)).is_empty(), "a cell of a module's casing finds the module")
	check(tank > 0, "(the Tank stands)")


func scenario_f() -> void:
	print("F. save")
	fresh()
	var r := build_rig()
	var w := winch_of(r)
	check(until(func() -> bool: return w["cable"] > 12.0, 30.0), "the rig is on its way down")
	var path := "user://quarry_test.save"
	Save.write(game, path)
	game.continue_run(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.paused = true
	var w2: Dictionary = game.modules[r["winch"]]
	check(w2["tether"] == r["tank"] and w2["rig"].size() == 2, "the rig loads back hooked")
	var c0: float = w2["cable"]
	secs(15.0)
	check(w2["cable"] > c0 + 5.0 or w2["state"] != "down", "and carries on (cable %.0f to %.0f, %s)" % [c0, w2["cable"], w2["state"]])
	check(game.modules.size() == 4, "all four modules are still modules")


func scenario_g() -> void:
	print("G. sand behind the rig")
	fresh()
	var r := build_rig()
	var w := winch_of(r)
	var tank: Dictionary = game.modules[r["tank"]]
	check(not tank["faces"][1]["open"] and tank["faces"][1]["link_m"] == r["winch"], "the Tank's hook is joined to the Winch and its casing stays shut")
	game.levels["tank_size"] = 1        # a longer trip, so the roof is well down the shaft by the time it fills
	check(until(func() -> bool: return w["cable"] > 60.0, 150.0), "the rig goes down the shaft (%.0f cells)" % w["cable"])
	# A slump: the shaft above the Tank fills with sand, over the rig's clearance too.
	var top := int(MC.bounds(tank).position.y)
	var sand := 31
	var laid := 0
	for y in range(SURFACE + 1, top):
		for x in range(X0 - 4, X0 + 30):
			if game.sim.get_cell(x, y) == D.AIR and game.sim.get_owner(x, y) == 0:
				game.sim.set_cell(x, y, sand)
				laid += 1
	check(laid > 200, "(%d cells of sand laid in the shaft)" % laid)
	check(until(func() -> bool: return w["state"] == "up", 90.0), "the Tank fills and the Winch hauls up")
	check(until(func() -> bool: return w["state"] == "docked", 120.0), "the rig gets through the sand and docks (cable %.0f, %s)" % [w["cable"], w["why"]])
	check(w.get("plowed", 0) > 0, "by clearing loose powder off its path (%d cells)" % w.get("plowed", 0))
	var tb := MC.bounds(tank)
	var inside: int = game.sim.count_in_rect(tb.position.x + 2, tb.position.y + 2, tb.size.x - 4, tb.size.y - 4, M.mask("powder"))
	check(inside == 0, "and no sand got into the Tank's hollow (%d cells)" % inside)
	game.levels["tank_size"] = 0


func scenario_h() -> void:
	print("H. a static plug over the rig")
	fresh()
	var r := build_rig()
	var w := winch_of(r)
	var tank: Dictionary = game.modules[r["tank"]]
	check(until(func() -> bool: return w["cable"] > 60.0, 150.0), "the rig goes down the shaft (%.0f cells)" % w["cable"])
	var top := int(MC.bounds(tank).position.y)
	var stone := 2
	var laid := 0
	for y in range(top - 40, top - 10):
		for x in range(X0 - 4, X0 + 30):
			if game.sim.get_cell(x, y) == D.AIR and game.sim.get_owner(x, y) == 0:
				game.sim.set_cell(x, y, stone)
				laid += 1
	check(laid > 400, "(%d cells of Stone laid across the shaft)" % laid)
	var wall_before: int = game.sim.count_in_rect(X0 - 12, top - 40, 8, 30, M.mask("solid"))
	w["state"] = "up"
	check(until(func() -> bool: return w["state"] == "docked", 200.0), "the rig climbs through the plug and docks (cable %.0f, %s)" % [w["cable"], w["why"]])
	check(w.get("plowed", 0) > 300, "by clearing it off its path (%d cells)" % w.get("plowed", 0))
	var wall_after: int = game.sim.count_in_rect(X0 - 12, top - 40, 8, 30, M.mask("solid"))
	check(wall_after == wall_before, "and the ground beside the shaft is untouched (%d cells before and after)" % wall_before)
	check(game.modules.has(r["tank"]) and game.modules[r["tank"]]["integrity"] > 0.99, "with the rig's casing whole (%.2f)" % game.modules[r["tank"]]["integrity"])


func scenario_i() -> void:
	print("I. powder at the rig's sides and under it on the way down")
	fresh()
	var r := build_rig()
	var w := winch_of(r)
	check(until(func() -> bool: return w["cable"] > 40.0, 150.0), "the rig goes down the shaft (%.0f cells)" % w["cable"])
	var cut: Dictionary = game.modules[r["cut"]]
	var tb := MC.bounds(game.modules[r["tank"]])
	var cb := MC.bounds(cut)
	var below := Vector2i(cb.position.x + (cb.size.x >> 1), cb.end.y + 1)
	var beside := Vector2i(tb.end.x + 1, tb.position.y + 10)
	var powder := M.mask("powder")
	game.sim.set_cell(below.x, below.y, D.RUBBLE)
	game.sim.set_cell(below.x + 3, below.y, D.STONE)
	game.sim.set_cell(beside.x, beside.y, D.RUBBLE)
	Winch._plow_down(game, w, cut)
	check(game.sim.count_in_rect(beside.x, beside.y, 1, 1, powder) == 0, "rubble lodged beside the Tank is shoved aside")
	check(game.sim.count_in_rect(below.x, below.y, 1, 1, powder) == 1, "the Excavator's own span is left to the Excavator")
	Winch._plow_down(game, w, {})
	check(game.sim.count_in_rect(below.x, below.y, 1, 1, powder) == 0, "any other module clears the powder under its bottom edge")
	check(game.sim.get_cell(below.x + 3, below.y) == D.STONE, "rock stays where it is")
	game.sim.set_cell(below.x + 3, below.y, D.AIR)
	check(until(func() -> bool: return w["cable"] > 70.0, 150.0), "and the rig goes on down (%.0f cells)" % w["cable"])
	check(game.modules.has(r["cut"]) and game.modules[r["cut"]]["integrity"] > 0.99, "with the casings whole")


func scenario_j() -> void:
	print("J. a Cutter's own casing is not a wall")
	fresh()
	var r := build_rig()
	var w := winch_of(r)
	check(until(func() -> bool: return w["cable"] > 40.0, 150.0), "the rig goes down the shaft (%.0f cells)" % w["cable"])
	var cut: Dictionary = game.modules[r["cut"]]
	var cb := MC.bounds(cut)
	var row := Rect2i(cb.position.x, cb.end.y - 1, cb.size.x, 1)      # the casing's bottom row
	var raw: PackedInt32Array = game.sim.rect_counts(row.position.x, row.position.y, row.size.x, row.size.y)
	check(raw[D.OBSIDIAN] > 0, "the Cutter's bottom row holds casing cells (%d)" % raw[D.OBSIDIAN])
	check(Cutter.counts_ahead(game, cut, row)[D.OBSIDIAN] == 0, "and none of them counts as ahead of it")
	var below := Rect2i(cb.position.x, cb.end.y + 1, cb.size.x, 1)
	game.sim.set_cell(cb.position.x + 3, below.position.y, D.OBSIDIAN)
	check(Cutter.counts_ahead(game, cut, below)[D.OBSIDIAN] == 1, "an Obsidian cell that is nobody's still does")
	for x in range(cb.position.x - 4, cb.end.x + 4):
		for y in range(below.position.y, below.position.y + 6):
			game.sim.set_cell(x, y, D.OBSIDIAN)
	check(until(func() -> bool: return w["halt"] != "", 60.0) and "Obsidian" in w["halt"], "a real wall below stops the rig (%s)" % w["halt"])


func scenario_k() -> void:
	print("K. a full goods bank says why the rig waits")
	fresh()
	var cut := place("cutter", X0, SURFACE - 16)
	var tank := place("tank", X0, SURFACE - 16 - 30)
	var fun := place("funnel", X0, SURFACE - 16 - 30 - 14)
	secs(1.0)
	var salt := M.id_of("Salt")
	game.goods[M.id_of("Flux")] = game.goods_cap()
	MC.add_contents(game, tank, salt, 900)               # more than the Funnel holds, so the Tank keeps some
	var winch := place("winch", X0 + 14, SURFACE - 16 - 30 - 18)
	var w: Dictionary = game.modules[winch]
	secs(1.0)
	check(w["state"] == "docked" and "bank is full" in w["why"], "with the bank full the docked rig says so (%s: %s)" % [w["state"], w["why"]])
	check(game.modules[tank]["contents"].get(salt, 0) > 0, "and the Tank keeps Salt it cannot unload (%d)" % game.modules[tank]["contents"].get(salt, 0))
	game.goods.erase(M.id_of("Flux"))
	check(until(func() -> bool: return w["state"] == "down", 40.0), "with room in the bank the Funnel empties the Tank and the rig goes down (%s)" % w["why"])
	check(game.goods.get(salt, 0.0) > 0.0, "the Salt is banked (%.3f units)" % game.goods.get(salt, 0.0))
	check(cut != 0 and fun != 0, "(rig placed)")
