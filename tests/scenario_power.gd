extends SceneTree
## Hub and Node scenarios on seed 7 (A3 cut: the Hub is the only source, machines are modules):
##  A. the Hub trickles power up to its cap and no further
##  B. Nodes laid in a chain down a shaft are built by packet and connect to the Hub
##  C. a Node under water stops relaying and what hangs off it drops out; it returns once dry
##  D. a Node in the open with no Node or Hub in reach stays unlinked and its blueprint waits
## Laid out as in v2, scaled by D.S about the Hub's pad (P, R); counts of cells x S * S.
## Run: godot --headless --path . --script tests/scenario_power.gd

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var fails := 0


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		scenario_a()
		scenario_b()
		scenario_c()
		scenario_d()
		print("FAILURES: %d" % fails)
		return true
	return false


## Where a v2 cell near the Hub is now: the layout scales by D.S about the pad's
## middle at ground level.
func P(x: int, y: int) -> Vector2i:
	return Vector2i((D.W >> 1) + (x - 128) * D.S, D.GROUND_Y + (y - 40) * D.S)


## A v2 rectangle near the Hub, scaled the same way.
func R(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(P(x, y), Vector2i(w, h) * D.S)


func fresh() -> void:
	game.new_game(7)
	# The Spoil Heap stands on seed 7's surface where these shafts open: clear it.
	var heap: Rect2i = game.info["spawned"]["areas"].get("spoil_heap", Rect2i())
	for y in range(heap.position.y, mini(heap.end.y, D.GROUND_Y)):
		for x in range(heap.position.x, heap.end.x):
			game.sim.set_cell(x, y, D.AIR)
	game.paused = true
	game.reveal_all = true


## Open `r` to the air. `lined` first walls its sides and floor with 3 * S cells
## of plain dirt, so none of the seed's sand or loose ground pours in.
func carve(r: Rect2i, lined := false) -> void:
	if lined:
		for y in range(r.position.y, r.end.y + 3 * D.S):
			for x in range(r.position.x - 3 * D.S, r.end.x + 3 * D.S):
				game.sim.set_cell(x, y, D.DIRT)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, D.AIR)


## Loose powder that eroded down into a spot (a few cells at the new scale) is
## swept out of it first.
func sweep(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var m: int = game.sim.get_cell(x, y)
			if m == D.LOOSE_DIRT or m == D.SAND or m == D.RUBBLE:
				game.sim.set_cell(x, y, D.AIR)


func put(type: int, r: Rect2i, dir := 0) -> Object:
	sweep(r)
	var why: String = game.check_place(type, r)
	if why != "":
		print("  !! can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		fails += 1
		return null
	return game.place(type, r, dir)


## Place and wait (up to 10 s) until it's built.
func build(type: int, r: Rect2i, dir := 0) -> Object:
	var b = put(type, r, dir)
	if b == null:
		return null
	for _i in 600:
		if b.built:
			break
		game.run_ticks(1)
	game.run_ticks(2)
	return b


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


func scenario_a() -> void:
	print("A. the Hub trickle and its cap")
	fresh()
	game.stock[D.R_POWER] = 0.0
	secs(10.0)
	check(absf(game.stock[D.R_POWER] - 10.0 * D.HUB_POWER_PER_S) < 0.3, "ten seconds make about %.1f power (%.2f)" % [10.0 * D.HUB_POWER_PER_S, game.stock[D.R_POWER]])
	game.stock[D.R_POWER] = D.HUB_POWER_CAP - 0.1
	secs(5.0)
	check(game.stock[D.R_POWER] <= D.HUB_POWER_CAP + 0.001, "it stops at the cap (%.2f of %d)" % [game.stock[D.R_POWER], int(D.HUB_POWER_CAP)])


func scenario_b() -> void:
	print("B. a chain of Nodes down a shaft")
	fresh()
	carve(R(110, 40, 10, 80), true)
	var n1 = build(D.B_NODE, R(118, 42, 2, 2))
	var n2 = build(D.B_NODE, R(118, 54, 2, 2))
	var n3 = build(D.B_NODE, R(110, 66, 2, 2))
	secs(2.0)
	check(n1 != null and n1.built and n2 != null and n2.built and n3 != null and n3.built, "all three Nodes are built")
	check(n1.connected and n2.connected and n3.connected, "all three are linked to the Hub")
	check(n3.link != null or n3.parent != null, "the last one hangs off the one before it")


func scenario_c() -> void:
	print("C. a Node under water")
	fresh()
	carve(R(110, 40, 10, 80), true)
	var n1 = build(D.B_NODE, R(118, 42, 2, 2))
	var n2 = build(D.B_NODE, R(118, 54, 2, 2))
	var n3 = build(D.B_NODE, R(110, 66, 2, 2))
	secs(2.0)
	check(n2.connected and n3.connected, "the chain is linked to start with")
	# Flood the shaft from the middle Node to the floor (water would only run down it otherwise).
	var flood := R(110, 52, 10, 68)
	for y in range(flood.position.y, flood.end.y):
		for x in range(flood.position.x, flood.end.x):
			if game.sim.get_cell(x, y) == D.AIR:
				game.sim.set_cell(x, y, D.WATER)
	secs(6.0)
	check(n2.drowned, "the Node in the water is drowned")
	check(not n3.connected, "the Node below it drops out")
	check(n1.connected, "the one above it stays linked")
	for y in range(flood.position.y, flood.end.y):
		for x in range(flood.position.x, flood.end.x):
			if game.sim.get_cell(x, y) == D.WATER:
				game.sim.set_cell(x, y, D.AIR)
	secs(10.0)
	check(not n2.drowned and n2.connected and n3.connected, "once it is dry again the chain relinks")


func scenario_d() -> void:
	print("D. a Node out of reach is refused")
	fresh()
	carve(R(90, 40, 10, 40), true)
	var r := R(98, 50, 2, 2)
	var why: String = game.check_place(D.B_NODE, r)
	check(why.find("network range") >= 0, "a Node far from the Hub and every other Node is refused (%s)" % why)
	carve(R(110, 40, 10, 80), true)
	var near = build(D.B_NODE, R(118, 42, 2, 2))
	check(near != null and near.built and near.connected, "one in reach is built and linked")
