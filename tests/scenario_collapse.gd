extends SceneTree
## Phase-8 collapse checks on seed 7, on blocks of rock laid well away from the Hub:
##  A. spans: a room as wide as dirt spans stands; a wider one caves in from the
##     middle into an arch and stops; stone spans further; water holds nothing up;
##     freshly dug ground holds for its settling time first; the cave-in is called out
##  B. worldgen: the map starts out standing (nothing left for the rule to take)
##  C. Struts: the gap under the cursor, rock to rock; flat under a ceiling it props
##     it; upright in the middle it splits the span; too wide or no rock, no Strut;
##     its ends hold the rock round them against weathering; losing an anchor snaps it
##  D. a building on a thin roof falls when the roof caves in
##  E. Tremor Dampers: tremors spare stone near a Strut
##  F. ground: packed dirt spans far, gravel hardly at all and fast, glimmer
##     never gives; a stone lump held only by dirt comes down; water wears stone
##     to dirt, dirt to sand and sand away, and leaves gravel and clay alone
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
	game.drill.enabled = false
	game.stock[D.R_STONE] = 200.0
	game.researched["strut"] = true
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
	fill(Rect2i(x - 12, y - 16, w + 24, h + 24), m)
	fill(Rect2i(x, y, w, h), D.AIR)


func scenario_a() -> void:
	print("A. spans and arches")
	fresh()
	# The counts are local: weathering sheds the odd ceiling cell anywhere on the
	# map, and the blocks these rooms sit in cut through the seed's own caves.
	room(40, 80, 7, 5, D.DIRT)
	secs(15.0)
	var roof := count(Rect2i(40, 79, 7, 1), D.DIRT)
	check(count(Rect2i(40, 78, 7, 1), D.DIRT) == 7, "a room 7 wide in dirt stands (its roof %d / 7: dirt ceilings still shed the odd cell)" % roof)

	fresh()
	room(40, 80, 16, 5, D.DIRT)
	var c0: int = game.sim.get_caved()
	secs(8.0)
	var mid := top_open(47, 66, 80)
	var edge := top_open(40, 66, 80)
	var caved: int = game.sim.get_caved() - c0
	print("  16 wide: %d cells caved in; open up to row %d in the middle, %d at the edge" % [caved, mid, edge])
	check(caved >= 20, "a room 16 wide in dirt caves in")
	check(mid <= 76 and edge >= 79, "from the middle, leaving an arch (the middle rose %d rows, the edge %d)" % [80 - mid, 80 - edge])
	check(count(Rect2i(40, 80, 16, 5), D.LOOSE_DIRT) >= 15, "what came down lies in the room as loose dirt")
	var above := solid_in(Rect2i(28, 64, 40, 16))
	secs(10.0)
	var lost := above - solid_in(Rect2i(28, 64, 40, 16))
	check(lost <= 2, "then it stops: the arch stands (%d more cells gone over the next 10 s)" % lost)
	var called := false
	for a: Dictionary in game.alerts:
		if a["kind"] == "cavein":
			called = true
	check(called, "the cave-in is called out")

	fresh()
	room(40, 200, 15, 5, D.STONE)
	room(120, 200, 22, 5, D.STONE)
	c0 = game.sim.get_caved()
	secs(10.0)
	var st_narrow := 15 - count(Rect2i(40, 199, 15, 1), D.STONE)
	var st_wide := 22 - count(Rect2i(120, 199, 22, 1), D.STONE)
	print("  stone roofs: 15 wide lost %d, 22 wide lost %d" % [st_narrow, st_wide])
	check(st_narrow == 0, "stone spans 15")
	check(st_wide >= 8 and count(Rect2i(120, 200, 22, 5), D.RUBBLE) > 0, "and past that it caves in as rubble")

	fresh()
	room(40, 80, 12, 5, D.DIRT)
	fill(Rect2i(40, 80, 12, 5), D.WATER)
	c0 = game.sim.get_caved()
	secs(6.0)
	check(game.sim.get_caved() - c0 > 0, "water under a ceiling holds nothing up")

	fresh()
	room(40, 80, 16, 5, D.DIRT)
	for x in range(40, 56):
		game.sim.settle_around(x, 80, 1, int(D.SETTLE_S * D.TICKS_PER_S))
	secs(D.SETTLE_S - 2.0)
	var held_n := count(Rect2i(40, 79, 16, 1), D.DIRT)
	secs(8.0)
	var after_n := count(Rect2i(40, 79, 16, 1), D.DIRT)
	check(held_n == 16 and after_n <= 4, "freshly dug, it holds for its %d s of settling, then goes (ceiling %d / 16, then %d)" % [int(D.SETTLE_S), held_n, after_n])


func scenario_b() -> void:
	print("B. worldgen")
	fresh()
	print("  seed 7: %d cells cleared into arches at generation" % game.info["arched"])
	check(game.info["arched"] > 0, "generation arches caves and aquifers that span too far")
	check(game.sim.stabilize() == 0, "and leaves nothing for the rule to take")


func scenario_c() -> void:
	print("C. Struts")
	fresh()
	room(40, 80, 12, 5, D.DIRT)
	room(120, 80, 12, 5, D.DIRT)
	var r: Rect2i = game.strut_rect(Vector2i(45, 80), true)
	print("  flat under the ceiling: %s, %s" % [r, game.check_strut(r)])
	check(r == Rect2i(40, 80, 12, 1) and game.check_strut(r) == "", "it spans the gap under the cursor, rock to rock")
	var s = game.place_strut(r)
	check(s.built and game.sim.get_cell(45, 80) == D.BUILDING and game.stock[D.R_STONE] == 198.0, "built at once for 2 Stone")
	check(game.sim.get_held(39, 80) > 0 and game.sim.get_held(39, 85) > 0 and game.sim.get_held(39, 87) == 0, "the rock round its ends is held")
	secs(10.0)
	var propped := count(Rect2i(40, 79, 12, 1), D.DIRT)
	var bare := count(Rect2i(120, 79, 12, 1), D.DIRT)
	print("  ceiling left over the propped room %d / 12, over the bare one %d / 12" % [propped, bare])
	check(propped >= 11 and bare <= 8, "the ceiling resting on it stays; the bare one caves in")
	check(not s.dead and not s.connected and s.link == null, "it needs no link")

	fresh()
	room(40, 80, 20, 5, D.DIRT)
	check(game.check_strut(game.strut_rect(Vector2i(45, 80), true)).begins_with("Too wide"), "a gap of 20 is too wide")
	room(120, 80, 14, 5, D.DIRT)
	var up: Rect2i = game.strut_rect(Vector2i(127, 82), false)
	check(up == Rect2i(127, 80, 1, 5) and game.check_strut(up) == "", "upright, it spans floor to ceiling")
	var su = game.place_strut(up)
	secs(10.0)
	var roof := count(Rect2i(120, 79, 14, 1), D.DIRT)
	check(roof >= 13 and count(Rect2i(120, 78, 14, 1), D.DIRT) == 14 and not su.dead,
			"in the middle of a room 14 wide it splits the span in two, and it stands (roof %d / 14)" % roof)
	check(game.check_strut(game.strut_rect(Vector2i(100, 20), true)) != "", "out in the open sky there's nothing to span")
	room(160, 80, 7, 1, D.DIRT)
	fill(Rect2i(166, 80, 1, 1), D.WATER)
	check(game.check_strut(game.strut_rect(Vector2i(162, 80), true)) == "", "water in the gap is fine")

	# Held rock doesn't weather: two rooms 7 wide, one with an upright Strut in it.
	fresh()
	room(40, 80, 7, 5, D.DIRT)
	room(120, 80, 7, 5, D.DIRT)
	game.place_strut(game.strut_rect(Vector2i(43, 82), false))
	for _i in 40:
		game.sim.weather(20000)
		secs(0.25)
	var kept := count(Rect2i(40, 79, 7, 1), D.DIRT)
	var worn := count(Rect2i(120, 79, 7, 1), D.DIRT)
	print("  under heavy weathering: ceiling by the Strut %d / 7, without %d / 7" % [kept, worn])
	check(kept == 7 and worn < 7, "rock within %d cells of its ends doesn't weather" % D.STRUT_HOLD)

	fresh()
	room(40, 80, 12, 5, D.DIRT)
	var sn = game.place_strut(game.strut_rect(Vector2i(45, 80), true))
	game.sim.set_cell(52, 80, D.AIR)
	secs(0.5)
	check(sn.dead and game.sim.get_held(39, 80) == 0, "dig out an anchor and it snaps, letting go of the rock at the other end too")


func scenario_d() -> void:
	print("D. a building on a thin roof")
	fresh()
	fill(Rect2i(60, 56, 40, 34), D.DIRT)
	fill(Rect2i(77, 62, 6, 8), D.AIR)      # a pocket over the roof, narrow enough to stand
	fill(Rect2i(72, 72, 16, 6), D.AIR)
	var b = game.place(D.B_CONDUIT, Rect2i(79, 68, 2, 2))
	b.built = true
	var y0: int = b.y
	var fell := false
	for _i in 20:
		secs(0.5)
		if b.falling or b.y > y0:
			fell = true
	print("  roof 2 rows over a room 16 wide; the Conduit on it went from row %d to %d" % [y0, b.y])
	check(fell and b.y > y0, "the roof caves in and the Conduit comes down with it")


func scenario_e() -> void:
	print("E. Tremor Dampers")
	fresh()
	fill(Rect2i(10, 140, 60, 20), D.STONE)
	fill(Rect2i(20, 150, 40, 1), D.AIR)
	for x in [30, 40, 50]:
		game.sim.set_cell(x, 150, D.STONE)
	var s = game.place_strut(game.strut_rect(Vector2i(25, 150), true))
	check(s != null and s.anchor_a == Vector2i(19, 150) and s.anchor_b == Vector2i(30, 150), "a Strut in a slot in stone")
	game.researched["tremor_dampers"] = true
	game.scan_dirty = true
	game.run_ticks(6)
	for _i in 30:
		game.sim.tremor(400, 149, 152)
	var near := count(Rect2i(10, 140, 29, 20), D.RUBBLE)
	var far := count(Rect2i(45, 140, 16, 20), D.RUBBLE)
	print("  rubble shaken loose within reach of the Strut %d, beyond it %d" % [near, far])
	check(near == 0 and far > 0, "tremors spare stone within %d cells of a Strut" % int(D.STRUT_DAMP_R))


func scenario_f() -> void:
	print("F. ground")
	fresh()
	room(40, 80, 22, 5, D.PACKED_DIRT)
	room(120, 80, 6, 5, D.GRAVEL)
	room(40, 200, 30, 5, D.GLIMMER)
	secs(2.0)
	var grav_roof := count(Rect2i(120, 79, 6, 1), D.GRAVEL)
	secs(8.0)
	var packed_roof := count(Rect2i(40, 79, 22, 1), D.PACKED_DIRT)
	print("  roofs: packed dirt 22 wide %d / 22, gravel 6 wide %d / 6 after 2 s, glimmer 30 wide %d / 30" % [packed_roof, grav_roof, count(Rect2i(40, 199, 30, 1), D.GLIMMER)])
	check(packed_roof >= 21, "packed dirt roofs a room 22 wide")
	check(grav_roof <= 3 and count(Rect2i(120, 80, 6, 5), D.RUBBLE) > 0, "gravel won't roof 6, and comes down within a couple of seconds as rubble")
	check(count(Rect2i(40, 199, 30, 1), D.GLIMMER) == 30, "glimmer never gives")

	# A stone lump in a dirt roof over a tunnel 5 wide: one no wider than the tunnel
	# has only dirt beside it and comes down; one that rests on the dirt stays.
	fresh()
	room(40, 80, 5, 4, D.DIRT)
	fill(Rect2i(40, 77, 5, 3), D.STONE)
	room(120, 80, 5, 4, D.DIRT)
	fill(Rect2i(118, 77, 9, 3), D.STONE)
	secs(6.0)
	var lone := count(Rect2i(40, 77, 5, 3), D.STONE)
	var resting := count(Rect2i(118, 77, 9, 3), D.STONE)
	print("  stone lumps: over the tunnel only %d / 15 left, resting on dirt %d / 27" % [lone, resting])
	check(lone <= 5, "stone held only by dirt beside it comes down")
	check(resting == 27, "stone resting on dirt at its ends stays")

	# A pool in bedrock floored with a strip of each ground, and the wash pass run hard.
	fresh()
	fill(Rect2i(30, 90, 40, 14), D.BEDROCK)
	fill(Rect2i(32, 92, 36, 8), D.WATER)
	var walls := {D.STONE: 32, D.DIRT: 38, D.GRAVEL: 44, D.CLAY: 50, D.PACKED_DIRT: 56}
	for m: int in walls:
		fill(Rect2i(walls[m], 100, 6, 1), m)
	fill(Rect2i(62, 99, 6, 1), D.SAND)
	for _i in 250:
		game.sim.wash(262144)
		game.run_ticks(2)
	var left := {}
	for m: int in walls:
		left[m] = count(Rect2i(walls[m], 100, 6, 1), m)
	print("  after heavy washing, of 6 each: %s; sand %d / 6" % [left, count(Rect2i(62, 99, 6, 1), D.SAND)])
	check(left[D.GRAVEL] == 6 and left[D.CLAY] == 6, "water leaves gravel and clay alone")
	check(left[D.DIRT] <= 3, "and wears dirt into sand")
	check(left[D.STONE] < 6 and left[D.PACKED_DIRT] < 6, "stone and packed dirt give way far more slowly (to dirt)")
	check(count(Rect2i(62, 99, 6, 1), D.SAND) < 6, "sand in water gets carried off")
