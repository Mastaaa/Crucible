extends SceneTree
## Phase-8 collapse checks on seed 7, on blocks of rock laid away from the Hub:
##  A. spans: a room as wide as dirt spans stands; a wider one caves in from the
##     middle into an arch and stops; stone spans further; water holds nothing up;
##     freshly dug ground holds for its settling time first; the cave-in is called out
##  B. worldgen: the map starts out standing (nothing left for the rule to take)
##  C. Braces: the gap under the cursor, rock to rock; flat under a ceiling it props
##     it; upright in the middle it splits the span; too wide or no rock, no Brace;
##     its ends hold the rock round them against weathering; losing an anchor snaps it
##  D. a building on a thin roof falls when the roof caves in
##  E. Tremor Dampers: tremors spare stone near a Brace
##  F. ground: packed dirt spans far, gravel hardly at all and fast, glimmer
##     never gives; a stone lump held only by dirt comes down; water wears stone
##     to dirt, dirt to sand and sand away, and leaves gravel and clay alone
## Phase 8b: v2's rooms at D.S times the size, stacked down the map (it's too
## narrow to set them side by side); times D.S longer for 10x the rows to cave,
## counts of cells D.S * D.S.
## Run: godot --headless --path . --script tests/scenario_collapse.gd

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
		if not game.sim.has_method("collapse") or game.sim.get_script() != null:
			print("  (the GDScript sim has no collapse: nothing to check)")
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


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	game.stock[D.R_STONE] = 200.0
	game.researched["brace"] = true
	game._refresh_unlocks()


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func count(r: Rect2i, m: int) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if game.sim.get_cell(x, y) == m:
				n += 1
	return n


func solid_in(r: Rect2i) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if D.is_solid(game.sim.get_cell(x, y)):
				n += 1
	return n


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


## Highest open row in column x between rows y0 and y1 (y1 if none).
func top_open(x: int, y0: int, y1: int) -> int:
	for y in range(y0, y1 + 1):
		if not D.is_solid(game.sim.get_cell(x, y)):
			return y
	return y1


## A block of `m` with a room carved in it: `w` wide, `h` tall, its top row at y.
func room(x: int, y: int, w: int, h: int, m: int) -> void:
	fill(Rect2i(x - 12 * S, y - 16 * S, w + 24 * S, h + 24 * S), m)
	fill(Rect2i(x, y, w, h), D.AIR)


const S := D.S
const X := 200       # rooms' left edge
const Y1 := 700      # first room's top row
const Y2 := 1400     # a second room's


func scenario_a() -> void:
	print("A. spans and arches")
	fresh()
	# The counts are local: weathering sheds the odd ceiling cell anywhere on the
	# map, and the blocks these rooms sit in cut through the seed's own caves.
	room(X, Y1, 7 * S, 5 * S, D.DIRT)
	secs(15.0)
	var roof := count(Rect2i(X, Y1 - 1, 7 * S, 1), D.DIRT)
	check(count(Rect2i(X, Y1 - 2 * S, 7 * S, 1), D.DIRT) == 7 * S, "a room 70 wide in dirt stands (its roof %d / 70: dirt ceilings still shed the odd cell)" % roof)

	fresh()
	room(X, Y1, 16 * S, 5 * S, D.DIRT)
	var c0: int = game.sim.get_caved()
	secs(16.0 * S)    # the arch rises about a row every 2.5 s
	var mid := top_open(X + 8 * S, Y1 - 14 * S, Y1)
	var edge := top_open(X, Y1 - 14 * S, Y1)
	var caved: int = game.sim.get_caved() - c0
	print("  160 wide: %d cells caved in; open up to row %d in the middle, %d at the edge" % [caved, mid, edge])
	check(caved >= 20 * S * S, "a room 160 wide in dirt caves in")
	check(mid <= Y1 - 4 * S and edge >= Y1 - S, "from the middle, leaving an arch (the middle rose %d rows, the edge %d)" % [Y1 - mid, Y1 - edge])
	check(count(Rect2i(X, Y1, 16 * S, 5 * S), D.LOOSE_DIRT) >= 15 * S * S, "what came down lies in the room as loose dirt")
	var zone := Rect2i(X - 12 * S, Y1 - 16 * S, 40 * S, 16 * S)
	var above := solid_in(zone)
	secs(10.0 * S)
	var lost := above - solid_in(zone)
	check(lost <= 4 * S * S, "then it stops: the arch stands (%d more cells gone over the next 100 s, weathering)" % lost)
	var called := false
	for a: Dictionary in game.alerts:
		if a["kind"] == "cavein":
			called = true
	check(called, "the cave-in is called out")

	fresh()
	room(X, 2000, 15 * S, 5 * S, D.STONE)
	room(X, 2500, 22 * S, 5 * S, D.STONE)
	c0 = game.sim.get_caved()
	secs(10.0 * S)
	var st_narrow := 15 * S - count(Rect2i(X, 1999, 15 * S, 1), D.STONE)
	var st_wide := 22 * S - count(Rect2i(X, 2499, 22 * S, 1), D.STONE)
	print("  stone roofs: 150 wide lost %d, 220 wide lost %d" % [st_narrow, st_wide])
	check(st_narrow <= 2 * S, "stone spans 150 (%d weathered out of its roof; a stray sample or two, against %d for the wide one)" % [st_narrow, st_wide])
	check(st_wide >= 8 * S and count(Rect2i(X, 2500, 22 * S, 5 * S), D.RUBBLE) > 0, "and past that it caves in as rubble")

	fresh()
	room(X, Y1, 12 * S, 5 * S, D.DIRT)
	fill(Rect2i(X, Y1, 12 * S, 5 * S), D.WATER)
	c0 = game.sim.get_caved()
	secs(6.0 * S)
	check(game.sim.get_caved() - c0 > 0, "water under a ceiling holds nothing up")

	fresh()
	room(X, Y1, 16 * S, 5 * S, D.DIRT)
	for x in range(X, X + 16 * S):
		game.sim.settle_around(x, Y1, S, int(D.SETTLE_S * D.TICKS_PER_S))
	secs(D.SETTLE_S - 2.0)
	var held_n := count(Rect2i(X, Y1 - 1, 16 * S, 1), D.DIRT)
	secs(8.0 * S)
	var after_n := count(Rect2i(X, Y1 - 1, 16 * S, 1), D.DIRT)
	check(held_n == 16 * S and after_n <= 4 * S, "freshly dug, it holds for its %d s of settling, then goes (ceiling %d / 160, then %d)" % [int(D.SETTLE_S), held_n, after_n])


func scenario_b() -> void:
	print("B. worldgen")
	fresh()
	print("  seed 7: %d cells cleared into arches at generation" % game.info["arched"])
	check(game.info["arched"] > 0, "generation arches caves and aquifers that span too far")
	check(game.sim.stabilize() == 0, "and leaves nothing for the rule to take")


func scenario_c() -> void:
	print("C. Braces")
	fresh()
	room(X, Y1, 12 * S, 5 * S, D.DIRT)
	room(X, Y2, 12 * S, 5 * S, D.DIRT)
	var r: Rect2i = game.brace_rect(Vector2i(X + 5 * S, Y1), true)
	print("  flat under the ceiling: %s, %s" % [r, game.check_brace(r)])
	check(r == Rect2i(X, Y1, 12 * S, D.BRACE_THICK) and game.check_brace(r) == "", "it spans the gap under the cursor, rock to rock, %d thick" % D.BRACE_THICK)
	var s = game.place_brace(r)
	check(s.built and game.sim.get_cell(X + 5 * S, Y1) == D.BUILDING and game.stock[D.R_STONE] == 198.0, "built at once for 2 Stone")
	check(game.sim.get_held(X - 1, Y1) > 0 and game.sim.get_held(X - 1, Y1 + 5 * S) > 0 and game.sim.get_held(X - 1, Y1 + 7 * S) == 0, "the rock round its ends is held")
	secs(10.0 * S)
	var propped := count(Rect2i(X, Y1 - 1, 12 * S, 1), D.DIRT)
	var bare := count(Rect2i(X, Y2 - 1, 12 * S, 1), D.DIRT)
	print("  ceiling left over the propped room %d / 120, over the bare one %d / 120" % [propped, bare])
	check(propped >= 11 * S and bare <= 8 * S, "the ceiling resting on it stays; the bare one caves in")
	check(not s.dead and not s.connected and s.link == null, "it needs no link")

	fresh()
	room(X, Y1, 20 * S, 5 * S, D.DIRT)
	check(game.check_brace(game.brace_rect(Vector2i(X + 5 * S, Y1), true)).begins_with("Too wide"), "a gap of 200 is too wide")
	room(X, Y2, 14 * S, 5 * S, D.DIRT)
	var up: Rect2i = game.brace_rect(Vector2i(X + 7 * S, Y2 + 2 * S), false)
	check(up == Rect2i(X + 7 * S, Y2, D.BRACE_THICK, 5 * S) and game.check_brace(up) == "", "upright, it spans floor to ceiling")
	var su = game.place_brace(up)
	secs(10.0 * S)
	var roof := count(Rect2i(X, Y2 - 1, 14 * S, 1), D.DIRT)
	check(roof >= 10 * S and count(Rect2i(X, Y2 - 2 * S, 14 * S, 1), D.DIRT) == 14 * S and not su.dead,
			"in the middle of a room 140 wide it splits the span in two, and it stands (roof %d / 140)" % roof)
	check(game.check_brace(game.brace_rect(Vector2i(X, 60), true)) != "", "out in the open sky there's nothing to span")
	room(X, 2200, 7 * S, 1 * S, D.DIRT)
	fill(Rect2i(X + 6 * S, 2200, S, S), D.WATER)
	check(game.check_brace(game.brace_rect(Vector2i(X + 2 * S, 2200), true)) == "", "water in the gap is fine")

	# Held rock doesn't weather: two rooms 70 wide, one with an upright Brace in it.
	fresh()
	room(X, Y1, 7 * S, 5 * S, D.DIRT)
	room(X, Y2, 7 * S, 5 * S, D.DIRT)
	game.place_brace(game.brace_rect(Vector2i(X + 3 * S, Y1 + 2 * S), false))
	for _i in 40:
		game.sim.weather(300000)
		secs(0.25)
	var kept := count(Rect2i(X, Y1 - 1, 7 * S, 1), D.DIRT)
	var worn := count(Rect2i(X, Y2 - 1, 7 * S, 1), D.DIRT)
	print("  under heavy weathering: ceiling by the Brace %d / 70, without %d / 70" % [kept, worn])
	check(kept == 7 * S and worn < 7 * S, "rock within %d cells of its ends doesn't weather" % D.BRACE_HOLD)

	fresh()
	room(X, Y1, 12 * S, 5 * S, D.DIRT)
	var sn = game.place_brace(game.brace_rect(Vector2i(X + 5 * S, Y1), true))
	game.sim.set_cell(sn.anchor_b.x, sn.anchor_b.y, D.AIR)
	secs(0.5)
	check(sn.dead and game.sim.get_held(X - 1, Y1) == 0, "dig out an anchor and it snaps, letting go of the rock at the other end too")


func scenario_d() -> void:
	print("D. a building on a thin roof")
	fresh()
	var x0 := X
	var y0 := Y1
	fill(Rect2i(x0, y0, 40 * S, 34 * S), D.DIRT)
	fill(Rect2i(x0 + 17 * S, y0 + 6 * S, 6 * S, 8 * S), D.AIR)      # a pocket over the roof, narrow enough to stand
	fill(Rect2i(x0 + 12 * S, y0 + 16 * S, 16 * S, 6 * S), D.AIR)
	var b = game.place(D.B_NODE, Rect2i(x0 + 19 * S, y0 + 12 * S, 2 * S, 2 * S))
	b.built = true
	game.scan_dirty = true    # built by hand: the anchoring scan picks it up
	var by0: int = b.y
	var fell := false
	for _i in 40 * S:
		secs(0.5)
		if b.falling or b.y > by0:
			fell = true
			break
	print("  roof 20 rows over a room 160 wide; the Conduit on it went from row %d to %d" % [by0, b.y])
	check(fell, "the roof caves in and the Conduit comes down with it")


func scenario_e() -> void:
	print("E. Tremor Dampers")
	fresh()
	var y := 2200
	fill(Rect2i(X - 100, y - 100, 600, 200), D.STONE)
	fill(Rect2i(X, y, 400, 10), D.AIR)
	for k in [100, 200, 300]:
		fill(Rect2i(X + k, y, 10, 10), D.STONE)
	var s = game.place_brace(game.brace_rect(Vector2i(X + 50, y), true))
	check(s != null and s.anchor_a == Vector2i(X - 1, y) and s.anchor_b == Vector2i(X + 100, y), "a Brace in a slot in stone")
	game.researched["tremor_dampers"] = true
	game.scan_dirty = true
	game.run_ticks(6)
	for _i in 30:
		game.sim.tremor(40000, y - 10, y + 20)
	var reach := int(D.BRACE_DAMP_R)
	var near := count(Rect2i(X - 100, y - 100, 100 + 100 + reach - 110, 200), D.RUBBLE)
	var far := count(Rect2i(X + 100 + reach + 30, y - 100, 150, 200), D.RUBBLE)
	print("  rubble shaken loose within reach of the Brace %d, beyond it %d" % [near, far])
	check(near == 0 and far > 0, "tremors spare stone within %d cells of a Brace" % reach)


func scenario_f() -> void:
	print("F. ground")
	fresh()
	room(X, Y1, 22 * S, 5 * S, D.PACKED_DIRT)
	room(X, Y2, 6 * S, 5 * S, D.GRAVEL)
	room(X, 2400, 30 * S, 5 * S, D.GLIMMER)
	secs(2.0 * S)
	var grav_roof := count(Rect2i(X, Y2 - 1, 6 * S, 1), D.GRAVEL)
	secs(8.0 * S)
	var packed_roof := count(Rect2i(X, Y1 - 1, 22 * S, 1), D.PACKED_DIRT)
	print("  roofs: packed dirt 220 wide %d / 220, gravel 60 wide %d / 60 after 20 s, glimmer 300 wide %d / 300" % [packed_roof, grav_roof, count(Rect2i(X, 2399, 30 * S, 1), D.GLIMMER)])
	check(packed_roof >= 20 * S, "packed dirt roofs a room 220 wide")
	check(grav_roof <= 3 * S and count(Rect2i(X, Y2, 6 * S, 5 * S), D.RUBBLE) > 0, "gravel won't roof 60, and comes down within 20 s as rubble")
	check(count(Rect2i(X, 2399, 30 * S, 1), D.GLIMMER) == 30 * S, "glimmer never gives")

	# A stone lump in a dirt roof over a tunnel 50 wide: one no wider than the tunnel
	# has only dirt beside it and comes down; one that rests on the dirt stays.
	fresh()
	room(X, Y1, 5 * S, 8 * S, D.DIRT)      # deep enough that its own rubble doesn't prop it
	fill(Rect2i(X, Y1 - 3 * S, 5 * S, 3 * S), D.STONE)
	room(X, Y2, 5 * S, 8 * S, D.DIRT)
	fill(Rect2i(X - 2 * S, Y2 - 3 * S, 9 * S, 3 * S), D.STONE)
	secs(12.0 * S)    # a row about every 3 s
	var lone := count(Rect2i(X, Y1 - 3 * S, 5 * S, 3 * S), D.STONE)
	var resting := count(Rect2i(X - 2 * S, Y2 - 3 * S, 9 * S, 3 * S), D.STONE)
	print("  stone lumps: over the tunnel only %d / 1500 left, resting on dirt %d / 2700" % [lone, resting])
	check(lone <= 5 * S * S, "stone held only by dirt beside it comes down")
	check(resting >= 26 * S * S, "stone resting on dirt at its ends stays (bar what weathers off)")

	# A pool in bedrock floored with a strip of each ground, and the wash pass run hard.
	fresh()
	var px := 100
	var py := Y1
	fill(Rect2i(px, py, 40 * S, 14 * S), D.BEDROCK)
	fill(Rect2i(px + 2 * S, py + 2 * S, 36 * S, 8 * S), D.WATER)
	var walls := {D.STONE: 2, D.DIRT: 8, D.GRAVEL: 14, D.CLAY: 20, D.PACKED_DIRT: 26}
	for m: int in walls:
		fill(Rect2i(px + walls[m] * S, py + 10 * S, 6 * S, S), m)
	fill(Rect2i(px + 32 * S, py + 9 * S, 6 * S, S), D.SAND)
	for _i in 250:
		game.sim.wash(D.W * D.H)
		game.run_ticks(2)
	var left := {}
	for m: int in walls:
		left[m] = count(Rect2i(px + walls[m] * S, py + 10 * S, 6 * S, 1), m)
	var sand_left := count(Rect2i(px + 32 * S, py + 9 * S, 6 * S, S), D.SAND)
	print("  after heavy washing, top row of each strip, of 60: %s; sand %d / 600" % [left, sand_left])
	check(left[D.GRAVEL] == 6 * S and left[D.CLAY] == 6 * S, "water leaves gravel and clay alone")
	check(left[D.DIRT] <= 3 * S, "and wears dirt into sand")
	check(left[D.STONE] < 6 * S and left[D.PACKED_DIRT] < 6 * S, "stone and packed dirt give way far more slowly (to dirt)")
	check(sand_left < 6 * S * S, "sand in water gets carried off")
