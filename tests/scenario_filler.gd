extends SceneTree
## A7: the Filler (support/filler.gd) and Grout, on seed 7 with the Hub as the network, on a bench of Sand.
##  A. Grout is static rock that yields Stone and any Drill Bit digs; the Filler is tech-gated behind Brace
##  B. it lines a fresh shaft in Sand: the two walls turn to Grout cell for cell, the Sand behind is still
##     Sand, the shaft keeps its width, and without it the Sand slumps in
##  C. it pays 1 Stone for every 30 cells; the dune's open top, and Dirt, are left alone
##  D. no Stone, no power or out of reach: it lays nothing and says why
## Run: godot --headless --path . --script tests/scenario_filler.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")
const FILLER = preload("res://scripts/machines/support/filler.gd")
var game: Node
var f := 0
var fails := 0
const BENCH := 300       # the bench runs from here to the Hub's left edge
const FILLER_X := 440    # the Filler stands on Dirt at the right end of the Sand block, inside the Hub's reach
const SURFACE := 200     # ground level (dirt from here down)
const SHAFT_X := FILLER_X - 34
const SHAFT_W := 12
const SHAFT_H := 30


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


## Dirt ground with a block of `block` (Sand) 90 wide and 60 deep on top of it, the Filler's tech done.
func fresh(block: int) -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	MC.ensure_defs()
	fill(Rect2i(BENCH, SURFACE - 120, 170, 120), D.AIR)
	fill(Rect2i(BENCH, SURFACE, 170, 160), D.DIRT)
	fill(Rect2i(BENCH, SURFACE + 160, 170, 40), D.BEDROCK)
	fill(Rect2i(FILLER_X - 90, SURFACE, 90, 60), block)
	game.researched["filler"] = 1
	game._refresh_unlocks()
	game.stock[D.R_POWER] = 50.0
	game.stock[D.R_STONE] = 30.0
	game.info["spawned"] = {}


func place_filler(x: int) -> int:
	var id := MC.place(game, "filler", Vector2i(x, SURFACE - 16), 0)
	if id == 0:
		print("  !! can't place the Filler at %d: %s" % [x, MC.check_place(game, "filler", Vector2i(x, SURFACE - 16), 0)])
	return id


## A fresh 12 x 30 shaft through the block, dug the way the Cutter digs: the new faces hold for SETTLE_S.
func dig_shaft() -> void:
	var soft := CUT.soft_mask(MC.defs["cutter"], 0)
	game.sim.dig_rect(SHAFT_X, SURFACE, SHAFT_W, SHAFT_H, soft, D.SETTLE_RADIUS, int(D.SETTLE_S * D.TICKS_PER_S))


func count(r: Rect2i, mat: int) -> int:
	var c: PackedInt32Array = game.sim.rect_counts(r.position.x, r.position.y, r.size.x, r.size.y)
	return c[mat]


func scenario_a() -> void:
	print("A. Grout and the tech")
	fresh(M.id_of("Sand"))
	var g := M.id_of("Grout")
	check(g > 0 and M.kinds[g] == M.K_STATIC, "Grout is static rock")
	check(CUT.soft_mask(MC.defs["cutter"], 0)[g] == 1, "the first Drill Bit digs it")
	var def: Dictionary = MC.defs["filler"]
	check(def.has("tech") and D.tech_index(def["tech"]) >= 0, "the Filler names a tech that exists (%s)" % def.get("tech", ""))
	game.researched.erase("filler")
	game._refresh_unlocks()
	check(not MC.unlocked(game, def), "it is locked until researched")
	check("brace" in D.TECHS[D.tech_index("filler")]["needs"], "and the tech needs Brace")


func scenario_b() -> void:
	print("B. lining a shaft in Sand")
	var sand := M.id_of("Sand")
	var grout := M.id_of("Grout")
	# Without it: the Sand slumps into the shaft once the faces have settled.
	fresh(sand)
	dig_shaft()
	secs(60.0)
	var row := SURFACE + 5
	var open_c := 0
	for x in range(SHAFT_X - 40, SHAFT_X + SHAFT_W + 20):
		if game.sim.get_cell(x, row) == D.AIR:
			open_c += 1
	print("  no Filler: the shaft is %d wide at row %d (it was %d)" % [open_c, row, SHAFT_W])
	check(open_c > SHAFT_W + 6, "without a Filler the Sand slumps and the opening widens")
	# With it.
	fresh(sand)
	var id := place_filler(FILLER_X)
	check(id != 0, "the Filler goes up beside the dune")
	dig_shaft()
	secs(60.0)
	var m: Dictionary = game.modules[id]
	var lined := count(Rect2i(SHAFT_X - 2, SURFACE, SHAFT_W + 4, SHAFT_H), grout)
	print("  Filler: %d Grout cells, %d laid, state: %s" % [lined, m.get("laid", 0), m.get("why", "")])
	check(lined >= 2 * SHAFT_H - 6 and lined <= 2 * SHAFT_H + 8, "the two walls are Grout, about 2 x %d cells (%d)" % [SHAFT_H, lined])
	row = SURFACE + 5
	open_c = 0
	for x in range(SHAFT_X - 40, SHAFT_X + SHAFT_W + 20):
		if game.sim.get_cell(x, row) == D.AIR:
			open_c += 1
	check(open_c == SHAFT_W, "the shaft keeps its %d width (%d)" % [SHAFT_W, open_c])
	check(game.sim.get_cell(SHAFT_X - 1, row) == grout and game.sim.get_cell(SHAFT_X - 2, row) == sand, "one cell of Grout, Sand behind it")
	check(game.sim.get_cell(SHAFT_X + SHAFT_W, row) == grout and game.sim.get_cell(SHAFT_X + SHAFT_W + 1, row) == sand, "the same on the other wall")


func scenario_c() -> void:
	print("C. what it pays and what it leaves alone")
	var sand := M.id_of("Sand")
	var grout := M.id_of("Grout")
	fresh(sand)
	var id := place_filler(FILLER_X)
	dig_shaft()
	var stone0: float = game.stock[D.R_STONE]
	var power0: float = game.stock[D.R_POWER]
	secs(40.0)
	var laid: int = game.modules[id].get("laid", 0)
	var spent: float = stone0 - game.stock[D.R_STONE]
	print("  laid %d cells for %d Stone" % [laid, int(spent)])
	check(spent == ceilf(float(laid) / 30.0) and spent >= 1.0, "1 Stone for every 30 cells, paid when it needs the next lot (%d Stone for %d cells)" % [int(spent), laid])
	check(game.stock[D.R_POWER] < power0 + 0.5 * 40.0 and laid > 0, "and power a cell")
	check(game.sim.get_cell(FILLER_X - 80, SURFACE) == sand and game.sim.get_cell(FILLER_X - 5, SURFACE) == sand, "the dune's open top is left as Sand")
	check(count(Rect2i(FILLER_X - 90, SURFACE, 90, 60), grout) == laid, "only cells it set are Grout (%d)" % laid)
	# Dirt: a shaft in a dirt block has nothing loose to line.
	fresh(D.DIRT)
	id = place_filler(FILLER_X)
	dig_shaft()
	var before: float = game.stock[D.R_STONE]
	secs(20.0)
	check(game.modules[id].get("laid", 0) == 0 and game.stock[D.R_STONE] == before, "a shaft in Dirt gets nothing: no cell set, no Stone spent")


func scenario_d() -> void:
	print("D. no Stone, no power, out of reach")
	var sand := M.id_of("Sand")
	fresh(sand)
	var id := place_filler(FILLER_X)
	dig_shaft()
	game.stock[D.R_STONE] = 0.0
	secs(10.0)
	var m: Dictionary = game.modules[id]
	check(m.get("laid", 0) == 0 and "Stone" in m["why"], "with no Stone in the Hub it lays nothing: %s" % m["why"])
	# Power: scan by hand (the game is paused, so the Hub's trickle adds nothing) over a full sweep.
	fresh(sand)
	id = place_filler(FILLER_X)
	dig_shaft()
	m = game.modules[id]
	game.stock[D.R_STONE] = 20.0
	for _i in 130:
		game.stock[D.R_POWER] = 0.0
		FILLER.scan(game, m, MC.defs["filler"])
	check(m.get("laid", 0) == 0 and "power" in m["why"], "with an empty power store it lays nothing: %s" % m["why"])
	fresh(sand)
	var far := MC.place(game, "filler", Vector2i(BENCH + 10, SURFACE - 16), 0)
	dig_shaft()
	secs(5.0)
	if far != 0:
		check("reach" in game.modules[far]["why"] and game.modules[far].get("laid", 0) == 0, "out of the network's reach it lays nothing: %s" % game.modules[far]["why"])
