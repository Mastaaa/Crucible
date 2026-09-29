extends SceneTree
## Phase-2 power scenarios on seed 7, laid out by hand next to the Hub:
##  A. three Drills starting from an empty power store share the Hub's 2 power/s
##  B. a Waterwheel under a spring makes power and sends its surplus to the Hub
##  C. a Cache at the foot of a shaft banks a Drill's spoil, then keeps the
##     stretch below a cut Conduit running
##  D. a Hopper cut off from the network swallows a flood on its reserve, stops
##     when it runs dry, and picks up again once the line is mended
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
	print("A. three Drills (the fixed one and two more) on an empty power store")
	fresh()
	game.stock[D.R_POWER] = 0.0
	var drills: Array = [game.drill]
	game.drill.power = 0.0
	game.set_reach_limit(game.drill, D.DRILL_REACH)
	build(D.B_CONDUIT, R(140, 38, 2, 2))
	drills.append(put(D.B_DRILL, R(136, 37, 3, 3)))
	drills.append(put(D.B_DRILL, R(143, 37, 3, 3)))
	game.drill.cells_bored = 0
	var starved_ticks := 0
	for s in 30:
		for _t in 60:
			game.run_ticks(1)
			for d in drills:
				if d.starved:
					starved_ticks += 1
		if s % 3 != 2:
			continue
		var line := "  t=%2ds hub power %5.1f  used %.2f/s |" % [s + 2, game.stock[D.R_POWER], game.power_used]
		for d in drills:
			line += " bored %2d pwr %4.1f%s |" % [d.cells_bored, d.power, " STARVED" if d.starved else ""]
		print(line)
	var bored := 0
	for d in drills:
		bored += d.cells_bored
	check(starved_ticks > 20, "drills went short of power (%d drill-ticks starved)" % starved_ticks)
	var want: int = 3 * D.B_SIZES[D.B_DRILL].x * D.DRILL_REACH
	check(bored >= want, "all three channels finished anyway (%d / %d cells, and any fill that fell in)" % [bored, want])


func scenario_b() -> void:
	print("B. Waterwheel under a spring")
	fresh()
	carve(R(110, 40, 10, 80), true)
	build(D.B_CONDUIT, R(120, 38, 2, 2))
	build(D.B_CONDUIT, R(118, 50, 2, 2))
	var wheel = build(D.B_WATERWHEEL, R(110, 50, 3, 5))
	# Only this spring: seed 7's first aquifer lies under the room at this scale and
	# its own spring would flood the pit up to the wheel.
	game.info["springs"] = [P(111, 44)]
	secs(3.0)
	check(wheel != null and wheel.built, "wheel built")
	var hub_before: float = game.stock[D.R_POWER]
	for s in 40:
		secs(1.0)
		if s % 5 == 4:
			print("  t=%2ds flow %.2f/s  wheel holds %4.1f  made %.2f/s  hub power %5.1f  packets %d" % [
					s + 1, wheel.flow, wheel.store[D.R_POWER], game.power_made, game.stock[D.R_POWER], game.packets.size()])
	check(wheel.flow > 0.4 and wheel.flow < 0.9, "wheel makes about 0.64 power/s under a spring (%.2f)" % wheel.flow)
	check(game.stock[D.R_POWER] > hub_before + 40.0 * D.HUB_POWER_PER_S + 5.0 or game.stock[D.R_POWER] >= D.HUB_POWER_CAP - 1.0,
			"surplus reached the Hub (%.1f -> %.1f)" % [hub_before, game.stock[D.R_POWER]])
	var below := 0
	var pool := R(110, 55, 10, 65)
	for y in range(pool.position.y, pool.end.y):
		for x in range(pool.position.x, pool.end.x):
			if game.sim.get_cell(x, y) == D.WATER:
				below += 1
	print("  water that went through and pooled below: %d cells" % below)
	check(below > 150 * D.S * D.S, "water passed through the wheel")


func scenario_c() -> void:
	print("C. Cache at the foot of a shaft, then the line above it cut")
	fresh()
	carve(R(150, 40, 11, 60), true)
	build(D.B_CONDUIT, R(140, 38, 2, 2))
	var conduits: Array = []
	for y in [46, 59, 72, 85, 97]:
		conduits.append(build(D.B_CONDUIT, R(150, y, 2, 2)))
	var cache = build(D.B_CACHE, R(153, 97, 3, 3))
	var drill = put(D.B_DRILL, R(157, 97, 3, 3))
	secs(40.0)
	print("  after 40 s: cache holds %s   drill bored %d   hub %s" % [_fmt(cache.store), drill.cells_bored, _fmt(game.stock)])
	check(cache.built and drill.built, "cache and drill built")
	check(drill.cells_bored >= 30 * D.S * D.S, "drill bored its channel (%d)" % drill.cells_bored)
	check(cache.store[D.R_POWER] > 20.0, "cache topped up with power (%.0f)" % cache.store[D.R_POWER])
	# Cut the line above the cache.
	game.demolish(conduits[1])
	game.run_ticks(1)
	check(conduits[2].connected and conduits[4].connected, "stretch below the cut stays linked through the Cache")
	var stone_before: float = cache.store[D.R_STONE]
	var d2 = put(D.B_DRILL, R(158, 85, 3, 3), 2)
	if d2 != null:
		d2.reach_limit = mini(D.DRILL_REACH, D.W - 4 - (d2.x + d2.w))
	secs(20.0)
	print("  20 s after the cut: cache holds %s   new drill built=%s bored %d  power %.1f" % [_fmt(cache.store), d2.built if d2 else false, d2.cells_bored if d2 else -1, d2.power if d2 else -1.0])
	check(d2 != null and d2.built, "a drill past the cut was built from the Cache (stone %.1f -> %.1f)" % [stone_before, cache.store[D.R_STONE]])
	check(d2 != null and d2.cells_bored > 0, "and it runs on the Cache's power")
	# Drain the Cache's power: the drill past the cut starves even though the Hub is full.
	cache.store[D.R_POWER] = 0.0
	d2.power = 0.0
	d2.reach_limit = mini(D.DRILL_REACH, D.W - 4 - (d2.x + d2.w))   # the map ends sooner here than in v2
	secs(3.0)
	print("  cache emptied of power: drill starved=%s  hub power %.0f" % [d2.starved, game.stock[D.R_POWER]])
	check(d2.starved or d2.reach >= d2.reach_limit, "drill past the cut starves once its Cache is dry")


func scenario_d() -> void:
	print("D. a cut-off Hopper under a flood")
	fresh()
	carve(R(150, 40, 11, 60), true)
	build(D.B_CONDUIT, R(140, 38, 2, 2))
	var conduits: Array = []
	for y in [46, 59, 72, 85, 97]:
		conduits.append(build(D.B_CONDUIT, R(150, y, 2, 2)))
	var hop = build(D.B_HOPPER, R(153, 98, 3, 2))
	secs(4.0)
	check(hop.power >= 9.0, "hopper filled its reserve (%.1f)" % hop.power)
	game.demolish(conduits[1])
	game.run_ticks(2)
	check(not hop.connected, "hopper cut off")
	var poured := 0
	var shaft := R(150, 44, 11, 53)
	for y in range(shaft.position.y, shaft.end.y):
		for x in range(shaft.position.x, shaft.end.x):
			if game.sim.get_cell(x, y) == D.AIR:
				game.sim.set_cell(x, y, D.WATER)
				poured += 1
	secs(40.0)
	var left := 0
	var whole := R(150, 40, 11, 60)
	for y in range(whole.position.y, whole.end.y):
		for x in range(whole.position.x, whole.end.x):
			if game.sim.get_cell(x, y) == D.WATER:
				left += 1
	print("  poured %d cells; hopper took %d on its reserve, %d left, starved=%s" % [poured, hop.cells_taken, left, hop.starved])
	var on_reserve := D.POWER_RESERVE / D.HOPPER_POWER_PER_CELL
	check(hop.starved and hop.cells_taken >= on_reserve * 0.9 and hop.cells_taken <= on_reserve * 1.04, "ran on its reserve (about %d cells), then stopped" % int(on_reserve))
	var drowned := 0
	for c in conduits:
		if c != null and not c.dead and c.drowned:
			drowned += 1
	print("  conduits drowned: %d" % drowned)
	build(D.B_CONDUIT, R(150, 59, 2, 2))
	secs(30.0)
	left = 0
	for y in range(whole.position.y, whole.end.y):
		for x in range(whole.position.x, whole.end.x):
			if game.sim.get_cell(x, y) == D.WATER:
				left += 1
	print("  line mended: hopper took %d in all, %d left, starved=%s, water banked %.1f" % [hop.cells_taken, left, hop.starved, game.total(D.R_WATER)])
	check(left < 10 * D.S * D.S and not hop.starved, "hopper drained the rest once power came back (%d left)" % left)


func _fmt(a: PackedFloat64Array) -> String:
	var parts: Array = []
	for r in D.NRES:
		parts.append("%s %.0f" % [D.RES_NAMES[r].substr(0, 2), a[r]])
	return " ".join(parts)
