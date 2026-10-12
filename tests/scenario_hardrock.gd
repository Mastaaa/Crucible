extends SceneTree
## A7: hard-rock patches (SpawnRegions._hard_rock), the rocks they are made of and the bit they take.
##  A. Flint, Basalt and Granite are static rock that yields Stone, and each opens at exactly one Drill Bit
##     level (3, 4 and 5): the level before leaves it standing
##  B. on seeds 7, 3, 11, 5 and 21 every band has a patch over the Hub's column, and no row of the map
##     has more than the cap of its width under patches
##  C. the cap holds when the table asks for far more rock than fits
##  D. patches stay inside their band's depth and replace only host rock (the Glimmer stash is whole)
## Run: godot --headless --path . --script tests/scenario_hardrock.gd

const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const MC = preload("res://scripts/machines/machines.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")
const SR = preload("res://scripts/spawn_regions.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")
const WorldGen = preload("res://scripts/worldgen.gd")
var fails := 0
var ROCKS := {"Flint": 3, "Basalt": 4, "Granite": 5}


func _initialize() -> void:
	M.ensure()
	MC.ensure_defs()
	scenario_a()
	scenario_b()
	scenario_c()
	scenario_d()
	print("FAILURES: %d" % fails)
	quit()


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func world(seed_value: int, table := {}) -> Array:
	var sim = SimFactory.create()
	var wg := WorldGen.new()
	if not table.is_empty():
		wg.spawn_table = table
	var info: Dictionary = wg.generate(sim, seed_value)
	return [sim, info]


## The widest share of the map's width that `mat` covers in any row between y0 and y1.
func row_share(sim, mat: int, y0: int, y1: int) -> float:
	var worst := 0.0
	for y in range(y0, y1, 4):
		var c: PackedInt32Array = sim.rect_counts(0, y, D.W, 4)
		worst = maxf(worst, float(c[mat]) / 4.0 / float(D.W))
	return worst


func scenario_a() -> void:
	print("A. the rocks and the bit each takes")
	var def: Dictionary = MC.defs["cutter"]
	for nm: String in ROCKS:
		var id: int = M.id_of(nm)
		var need: int = ROCKS[nm]
		check(id >= 0 and M.kinds[id] == M.K_STATIC, "%s is a static rock" % nm)
		check(M.yields_of(id).size() == 1 and M.yields_of(id)[0] == D.R_STONE, "%s pays only Stone" % nm)
		check(CUT.soft_mask(def, need - 1)[id] == 0, "%s stands against Drill Bit %d" % [nm, need - 1])
		check(CUT.soft_mask(def, need)[id] == 1, "%s opens at Drill Bit %d" % [nm, need])


func scenario_b() -> void:
	print("B. a patch over the Hub's column in every band, and the cap")
	var cap := float(SR.load_table()["hard_rock"]["cap"])
	for sd in [7, 3, 11, 5, 21]:
		var w := world(sd)
		var sim = w[0]
		var hub: Rect2i = w[1]["hub"]
		var hx := hub.position.x + (hub.size.x >> 1)
		for nm: String in ROCKS:
			var id: int = M.id_of(nm)
			var col: PackedInt32Array = sim.rect_counts(hx - 15, 280, 30, 2300)
			check(col[id] > 0, "seed %d: %s crosses the column under the Hub (%d cells)" % [sd, nm, col[id]])
		var worst := 0.0
		for nm: String in ROCKS:
			worst = maxf(worst, row_share(sim, M.id_of(nm), 280, 2600))
		check(worst <= cap, "seed %d: no row is more than %.2f hard rock (worst %.2f)" % [sd, cap, worst])


func scenario_c() -> void:
	print("C. the cap holds when the table asks for too much")
	var table := SR.load_table()
	var bands: Array = table["hard_rock"]["bands"]
	for b: Dictionary in bands:
		b["patches"] = [14, 14]
		b["width"] = [200, 260]
	var w := world(7, table)
	var cap := float(table["hard_rock"]["cap"])
	var worst := 0.0
	var cells := 0
	for nm: String in ROCKS:
		var id: int = M.id_of(nm)
		worst = maxf(worst, row_share(w[0], id, 280, 2600))
		cells += w[0].rect_counts(0, 280, D.W, 2300)[id]
	check(cells > 0, "patches still land (%d cells)" % cells)
	check(worst <= cap, "and no row passes %.2f (worst %.2f)" % [cap, worst])


func scenario_d() -> void:
	print("D. each rock stays in its band and the Glimmer stash survives")
	var table := SR.load_table()
	var w := world(7)
	var bands: Array = table["hard_rock"]["bands"]
	for b: Dictionary in bands:
		var id: int = M.id_of(str(b["material"]))
		var lo := int(b["depth"][0])
		var hi := int(b["depth"][1])
		var above: PackedInt32Array = w[0].rect_counts(0, 0, D.W, lo)
		var below: PackedInt32Array = w[0].rect_counts(0, hi + 1, D.W, D.H - hi - 1)
		check(above[id] == 0 and below[id] == 0, "%s sits between rows %d and %d" % [b["material"], lo, hi])
	var shards: int = M.id_of("Glimmer shards")
	var stash: PackedInt32Array = w[0].rect_counts(0, 1100, D.W, 220)
	check(stash[shards] > 3000, "the Glimmer shards stash is intact (%d cells)" % stash[shards])
