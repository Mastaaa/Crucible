extends SceneTree
## A5 part 8, Mk upgrades paid in goods, on seed 7:
##  A. a level that wants goods waits for them, then takes them out of the bank and finishes
##  B. the per-tier goods and a level's own goods add up
##  C. Throughput lifts a Shorer's cells a scan, and a Funnel's, level by level
##  D. Efficiency takes a tenth off power a level
##  E. Plating lifts the temperature a casing stands, and acid wears it less
## Run: godot --headless --path . --script tests/scenario_upgrades.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const Goals = preload("res://scripts/goals.gd")
const CS = preload("res://scripts/machines/casing.gd")
const Funnel = preload("res://scripts/machines/logistics/funnel.gd")
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


func count(r: Rect2i, mat: int) -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	mask[mat] = 1
	return game.sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)


func scenario_a() -> void:
	print("A. a level paid in goods")
	fresh()
	game.tiers_open[2] = true
	var lab := place("lab", 290, SURFACE - 30)
	secs(0.5)
	game.tech_power["throughput"] = 1199.0
	game.pick_research("throughput")
	var flux := M.id_of("Flux")
	secs(10.0)
	check(game.level("throughput") == 0, "with no Flux in the bank the level waits")
	check(not game.tech_mats_done("throughput"), "and the Labs say it still wants goods")
	game.bank_good(flux, 5.0)
	secs(10.0)
	check(game.level("throughput") == 1, "with Flux banked it finishes (level %d)" % game.level("throughput"))
	check(absf(game.goods.get(flux, 0.0) - 3.0) < 0.01, "and took exactly its 2 units (%.2f left)" % game.goods.get(flux, 0.0))
	check(lab != 0, "(Lab placed)")


func scenario_b() -> void:
	print("B. goods costs add up")
	fresh()
	check(Goals.research_bank(game.tech_step("lamp")).is_empty(), "a Tier 1 tech wants no goods")
	check(Goals.research_bank(game.tech_step("centrifuge")).get("Flux", 0.0) == 2.0, "a Tier 3 tech wants 2 Flux")
	check(Goals.research_bank(game.tech_step("tremor_dampers")).get("Glass", 0.0) == 2.0, "a Tier 4 tech wants 2 Glass")
	game.levels["throughput"] = 3
	var iv: Dictionary = Goals.research_bank(game.tech_step("throughput"))
	check(iv.get("Glass", 0.0) == 10.0 and iv.get("Ferrite bar", 0.0) == 6.0, "Throughput IV: its own 8 Glass plus the tier's 2, and 6 Ferrite bars")
	for t: Dictionary in D.TECHS:
		if not t.has("levels"):
			continue
		for lv: Dictionary in t["levels"]:
			for nm: String in lv.get("goods", {}):
				if M.id_of(nm) < 0:
					check(false, "%s names a material that does not exist: %s" % [t["name"], nm])
	check(true, "every goods name in the tree is a material")


func scenario_c() -> void:
	print("C. Throughput")
	var made: Array = []
	for lvl in [0, 2, 4]:
		fresh()
		game.levels["throughput"] = lvl
		var id := place("shorer", 300, SURFACE - 16)
		MC.add_contents(game, id, RUBBLE, 120)
		game.run_ticks(7)
		made.append(count(Rect2i(297, SURFACE - 16, 3, 16), STONE))
	check(made[0] > 0 and made[1] > made[0] and made[2] > made[1], "cells laid in the first scan climb with the level (%s)" % str(made))
	check(MU.rate(game, 30) == 90, "level 4 triples a rate of 30 to %d" % MU.rate(game, 30))
	var took: Array = []
	for lvl in [0, 2, 4]:
		fresh()
		game.levels["throughput"] = lvl
		var fid := place("funnel", 300, SURFACE - 14)
		var fm: Dictionary = game.modules[fid]
		fm["contents"][RUBBLE] = 1000
		Funnel.scan(game, fm, MC.defs["funnel"])
		took.append(fm.get("banked", 0))
	check(took[0] == 40 and took[1] == 80 and took[2] == 120, "a Funnel banks 40, 80, 120 cells a scan at levels 0, 2, 4 (%s)" % str(took))


func scenario_d() -> void:
	print("D. Efficiency")
	fresh()
	game.stock[D.R_POWER] = 10.0
	MU.take_power(game, 1.0)
	check(absf(game.stock[D.R_POWER] - 9.0) < 0.001, "level 0 costs the full 1.0")
	game.levels["efficiency"] = 4
	game.stock[D.R_POWER] = 10.0
	MU.take_power(game, 1.0)
	check(absf(game.stock[D.R_POWER] - 9.4) < 0.001, "level 4 costs 0.6 (stock %.2f)" % game.stock[D.R_POWER])


func hot_tank(plating: int) -> Dictionary:
	fresh()
	game.levels["plating"] = plating
	game.researched["tank"] = true
	var id := place("tank", 300, SURFACE - 30)
	secs(0.3)
	MC.add_contents(game, id, RUBBLE, 40)
	var m: Dictionary = game.modules[id]
	var b: Rect2i = m["box"]
	m["sim"].heat_rect(b.position.x, b.position.y, 3, 3, 1280)
	return m


func scenario_e() -> void:
	print("E. Plating")
	var m := hot_tank(0)
	var hi: int = m["sim"].rect_temp(m["box"].position.x, m["box"].position.y, 3, 3).y
	CS.wear(game, m, MC.defs["tank"])
	check(hi > 1150 and m.get("worn", false), "unplated, a casing wears at %d degrees" % hi)
	m = hot_tank(3)
	CS.wear(game, m, MC.defs["tank"])
	check(not m.get("worn", false), "Plating III stands the same heat (melts at %d)" % (CS.MELT + CS.PLATING_MELT * 3))
	# Acid: level 4 takes the whole chance away.
	fresh()
	game.levels["plating"] = 4
	game.researched["tank"] = true
	var id := place("tank", 300, SURFACE - 30)
	secs(0.3)
	MC.add_contents(game, id, M.id_of("Sourwater"), 400)
	var worn := false
	for _i in 200:
		CS.wear(game, game.modules[id], MC.defs["tank"])
		worn = worn or game.modules[id].get("worn", false)
	check(not worn, "Plating IV takes no wear from acid in 200 scans")
