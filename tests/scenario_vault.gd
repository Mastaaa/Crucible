extends SceneTree
## A5 part 2, Vault cells, on seed 7:
##  A. cells join into a bank by contact; a bank with the Hub in reach raises the power and goods caps, one out of reach adds nothing
##  B. the raised power cap lets the Hub's store climb past 100; a full goods bank holds goods back at a Funnel and a Bus Hopper
##  C. losing a cell takes its share: power over the new cap is lost, goods scale down together, and an alert says so
##  D. research: the Vault Cell's Build button waits for its tech
## Run: godot --headless --path . --script tests/scenario_vault.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200
const FLUX := 39
const SLICK := 35
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
	for t in ["bus_hopper", "vault"]:
		game.researched[t] = true


func place(def: String, x: int, y: int, turns: int = 0) -> int:
	var id := MC.place(game, def, Vector2i(x, y), turns)
	if id == 0:
		print("  !! can't place %s at %d,%d: %s" % [def, x, y, MC.check_place(game, def, Vector2i(x, y), turns)])
	return id


## A cell and a second one snapped to its right.
func pair() -> Array:
	var a := place("vault", 296, SURFACE - 40)
	var sn := MC.snap(game, "vault", 0, Vector2i(296 + 16 + 8, SURFACE - 40 + 8))
	var b := 0
	if sn["snapped"]:
		b = MC.place(game, "vault", sn["at"], 0)
	secs(1.0)
	return [a, b]


func scenario_a() -> void:
	print("A. Cells make a bank")
	fresh()
	check(game.power_cap() == D.HUB_POWER_CAP and game.goods_cap() == D.HUB_GOODS_CAP, "with no cells the caps are the Hub's own (%d power, %d goods)" % [game.power_cap(), game.goods_cap()])
	var ids := pair()
	check(ids[0] > 0 and ids[1] > 0 and game.modules[ids[0]]["faces"][3]["link_m"] == ids[1], "a second cell snaps onto the first and joins it")
	check(game.power_cap() == D.HUB_POWER_CAP + 300.0 and game.goods_cap() == D.HUB_GOODS_CAP + 80.0, "two cells add 300 power and 80 goods (%d, %d)" % [game.power_cap(), game.goods_cap()])
	check(game.modules[ids[1]]["size_of"] == 2, "each knows its cluster has two cells")
	# One far from any Node or the Hub adds nothing.
	fresh()
	var far := MC.place(game, "vault", Vector2i(240, SURFACE - 40), 0)
	game.hub.x = 700
	secs(1.0)
	check(far > 0 and game.modules[far].get("live", true) == false and game.power_cap() == D.HUB_POWER_CAP, "a cell with no Node or Hub in reach adds nothing")


func scenario_b() -> void:
	print("B. The caps bite")
	fresh()
	pair()
	game.stock[D.R_POWER] = D.HUB_POWER_CAP
	secs(10.0)
	check(game.stock[D.R_POWER] > D.HUB_POWER_CAP + 1.0, "the Hub's power climbs past its old 100 (%.1f)" % game.stock[D.R_POWER])
	# A full goods bank.
	fresh()
	game.goods[SLICK] = D.HUB_GOODS_CAP
	var fun := place("funnel", 240, SURFACE - 30)
	game.modules[fun]["contents"][FLUX] = 50
	game.modules[fun]["contents"][LOOSE] = 50
	secs(1.0)
	check(not game.goods.has(FLUX) and int(game.modules[fun]["contents"].get(FLUX, 0)) == 50, "a Funnel holds Flux back while the bank is full")
	check(int(game.modules[fun]["contents"].get(LOOSE, 0)) == 0, "but still banks the rest")
	var hop := place("bus_hopper", 290, SURFACE - 40)
	secs(0.5)
	fill(Rect2i(296, SURFACE - 43, 5, 3), FLUX)
	fill(Rect2i(304, SURFACE - 43, 5, 3), LOOSE)
	secs(2.0)
	var flux_left := 0
	var loose_left := 0
	for y in range(SURFACE - 60, SURFACE):
		for x in range(280, 330):
			var c: int = game.sim.get_cell(x, y)
			flux_left += 1 if c == FLUX else 0
			loose_left += 1 if c == LOOSE else 0
	check(flux_left == 15 and loose_left == 0 and hop > 0, "a Bus Hopper leaves the Flux in its mouth and takes the Loose dirt (%d Flux, %d Loose left)" % [flux_left, loose_left])
	game.goods.clear()
	secs(2.0)
	check(game.goods.get(FLUX, 0.0) > 0.1, "with room made it takes the Flux (%.2f)" % game.goods.get(FLUX, 0.0))


func scenario_c() -> void:
	print("C. A lost cell takes its share")
	fresh()
	var ids := pair()
	game.stock[D.R_POWER] = 380.0
	game.goods[FLUX] = 80.0
	game.goods[SLICK] = 20.0
	secs(1.0)
	check(absf(game.stock[D.R_POWER] - 380.0) < 1.0 and absf(game.goods_total() - 100.0) < 0.01, "both cells hold it all (%d power, %.0f goods)" % [game.stock[D.R_POWER], game.goods_total()])
	var alerts0: int = game.alerts.size()
	MC._wreck(game, game.modules[ids[1]])
	secs(1.0)
	check(game.stock[D.R_POWER] == 250.0 or absf(game.stock[D.R_POWER] - 250.0) < 0.5, "power drops to the new cap (%.1f)" % game.stock[D.R_POWER])
	check(absf(game.goods_total() - 70.0) < 0.01, "goods scale down to the new cap (%.1f)" % game.goods_total())
	check(absf(game.goods[FLUX] / game.goods[SLICK] - 4.0) < 0.01, "in proportion (%.2f : 1)" % (game.goods[FLUX] / game.goods[SLICK]))
	check(game.alerts.size() > alerts0, "and an alert says a cell is gone")
	secs(1.0)
	check(game.stock[D.R_POWER] > 249.0 and absf(game.goods_total() - 70.0) < 0.01, "nothing else is lost afterwards")


func scenario_d() -> void:
	print("D. research")
	fresh()
	game.researched.erase("vault")
	check(not MC.unlocked(game, MC.defs["vault"]), "the Vault Cell is locked at first")
	game.researched["vault"] = true
	check(MC.unlocked(game, MC.defs["vault"]) and D.tech_index("vault") >= 0, "and opens once researched")
