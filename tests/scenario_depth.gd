extends SceneTree
## Phase-9 depth checks on seed 7:
##  A. worldgen: the Magma band's rock is hot rock from about row 3000, the plug too;
##     hot rock and stone hold each other up along a row
##  B. water on hot rock boils into steam, and slowly quenches it to stone
##  G. the Crucible draws 4 power/s while charging; out of power for 5 s it drains
##  H. a spring tops up at the slowed rate (Alex, A5: a quarter of the first, so a breached aquifer floods a shaft slowly)
## Run: godot --headless --path . --script tests/scenario_depth.gd

const D = preload("res://scripts/defs.gd")
const S := D.S
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
		if game.sim.get_script() != null:
			print("  (the GDScript sim has no reactions or collapse: the rest needs the C++ one)")
			print("FAILURES: %d" % fails)
			return true
		scenario_b()
		scenario_g()
		scenario_h()
		print("FAILURES: %d" % fails)
		return true
	return false


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	game.stock[D.R_STONE] = 200.0


## Where a v2 cell near the Hub is now (see scenario_digging).
func P(x: int, y: int) -> Vector2i:
	return Vector2i((D.W >> 1) + (x - 128) * S, D.GROUND_Y + (y - 40) * S)


func R(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(P(x, y), Vector2i(w, h) * S).intersection(Rect2i(2, 2, D.W - 4, D.H - 4))


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


## A1: hot rock this near the surface cools to stone within half a minute. Rows
## holding a set-piece's hot rock get the Magma band's ambient, so it stays hot.
func keep_hot(r: Rect2i) -> void:
	var rows := D.ambient_rows()
	for y in range(r.position.y - 4, r.end.y + 4):
		rows[y] = D.AMBIENT_MAGMA
	game.sim.set_ambient(rows)


func count(r: Rect2i, m: int) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if game.sim.get_cell(x, y) == m:
				n += 1
	return n


## Steam at any stage of its ageing.
func steam(r: Rect2i) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var m: int = game.sim.get_cell(x, y)
			if m >= D.STEAM and m <= D.STEAM_LAST:
				n += 1
	return n


## An open room walled, floored and roofed with 20 cells of bedrock.
func arena(r: Rect2i) -> void:
	fill(r.grow(20), D.BEDROCK)
	fill(r, D.AIR)


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


## Run `s` seconds with the Hub's power topped up.
func secs(s: float) -> void:
	for _i in int(s):
		game.stock[D.R_POWER] = 100.0
		game.run_ticks(60)
	game.run_ticks(int((s - int(s)) * 60.0))


func research(id: String) -> void:
	game.researched[id] = true
	game._refresh_unlocks()


func build(type: int, r: Rect2i, dir := 0) -> Object:
	var why: String = game.check_place(type, r)
	if why != "":
		print("  !! can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		fails += 1
		return null
	var b = game.place(type, r, dir)
	for _i in 900:
		if b.built:
			break
		game.run_ticks(1)
	game.run_ticks(2)
	return b


## Place a building by hand as built.
func put_built(type: int, r: Rect2i) -> Object:
	var b = game.place(type, r)
	b.built = true
	game.scan_dirty = true
	game.net_dirty = true
	return b


func scenario_a() -> void:
	print("A. hot rock in the Magma band")
	fresh()
	var above := Rect2i(2, 2900, D.W - 4, 60)
	var band := Rect2i(2, 3300, D.W - 4, 100)
	var hot_above := count(above, D.HOT_ROCK)
	var hot := count(band, D.HOT_ROCK)
	var stone := count(band, D.STONE)
	print("  rows 2900-2960: hot rock %d; rows 3300-3400: hot rock %d, stone %d" % [hot_above, hot, stone])
	check(hot_above == 0 and hot * 2 > band.get_area() and stone == 0, "the Magma band's rock is hot rock, the Stone band's isn't")
	var plug := 0
	for y in range(4400, 4600):
		var m: int = game.sim.get_cell(209, y)
		if m == D.HOT_ROCK:
			plug += 1
		elif m == D.STONE:
			plug = -9999
	check(plug > 20, "the plug into the chamber is hot rock (%d cells down its middle)" % plug)
	if game.sim.get_script() != null:
		return
	# A roof half stone, half hot rock, over a 140-wide room (stone spans 150): it holds
	# as one (bar the odd drip). Half stone, half packed dirt, the stone half caves.
	var left := []
	for other: int in [D.HOT_ROCK, D.PACKED_DIRT]:
		fresh()
		var room := Rect2i(300, 2600, 140, 60)
		fill(room.grow(40), D.BEDROCK)
		fill(Rect2i(room.position.x - 40, room.position.y - 40, 220, 40), D.STONE)
		fill(Rect2i(room.position.x + 70, room.position.y - 40, 110, 40), other)
		fill(room, D.AIR)
		game.run_ticks(20 * 60)
		var roof := Rect2i(room.position.x, room.position.y - 40, room.size.x, 40)
		left.append(count(roof, D.STONE) + count(roof, other))
	print("  a roof over 140 after 20 s, of 5600 cells: stone and hot rock %d, stone and packed dirt %d" % left)
	check(left[0] >= 5600 - 20 and left[1] < 5600 - 500, "hot rock and stone hold each other up along a row")


func scenario_b() -> void:
	print("B. water on hot rock")
	fresh()
	var room := Rect2i(200, 3400, 300, 200)
	arena(room)
	var floor_r := Rect2i(200, 3560, 300, 40)
	fill(floor_r, D.HOT_ROCK)
	var pool := Rect2i(200, 3530, 300, 30)
	fill(pool, D.WATER)
	var w0 := count(room, D.WATER)
	game.run_ticks(60)
	var w1 := count(room, D.WATER)
	var st := steam(room)
	print("  1 s: water %d -> %d, steam %d" % [w0, w1, st])
	check(w1 < w0 and st > 0, "water on hot rock boils into steam")
	# Keep it wet for a while: some of the floor quenches.
	for _i in 60:
		fill(pool, D.WATER)
		game.run_ticks(60)
	var quenched := count(floor_r, D.STONE)
	print("  60 s kept wet: %d of the floor's %d hot rock cells quenched to stone" % [quenched, floor_r.get_area()])
	check(quenched > 0 and quenched < floor_r.size.x * 2, "kept wet, it slowly quenches to stone")


func scenario_g() -> void:
	print("G. the Crucible's power draw")
	fresh()
	game.run_ticks(5)
	game.crucible.connected = true
	game.activate_crucible()
	check(game.cstate == 1, "charging")
	game.c_delivered[D.R_GLIMMER] = 10.0
	game.c_power = D.CRUCIBLE_POWER_RESERVE
	game.run_ticks(120)
	var p1: float = game.c_power
	print("  2 s from %d: power %.2f, draining %s" % [int(D.CRUCIBLE_POWER_RESERVE), p1, game.c_draining])
	check(absf(D.CRUCIBLE_POWER_RESERVE - p1 - 2.0 * D.CRUCIBLE_POWER_PER_S) < 0.1 and not game.c_draining, "it draws 4 power/s while charging")
	game.run_ticks(60 * 8)
	var early: bool = game.c_draining
	game.run_ticks(60 * 4)
	print("  out of power: draining at 8 s %s, at 12 s %s (starved %s); glimmer fed %.2f of 10" % [early, game.c_draining,
			game.c_starved, game.c_delivered[D.R_GLIMMER]])
	check(game.c_starved and game.c_draining and game.c_delivered[D.R_GLIMMER] < 10.0, "out of power for 5 s, the charge drains")


func scenario_h() -> void:
	print("H. a spring's pace")
	fresh()
	var r := Rect2i(P(128, 60), Vector2i(60, 50))
	arena(r)
	game.info["springs"] = [Vector2i(r.position.x + 30, r.end.y - 1)]
	game.run_ticks(600)
	var water := count(r, D.WATER)
	var want := int(D.SPRING_CELLS_PER_S * 10.0)
	print("  10 s: %d Water cells (the rate gives %d)" % [water, want])
	check(want == 2 * S * S * 10, "a spring makes %d cells a second, a quarter of the first rate" % int(D.SPRING_CELLS_PER_S))
	check(absf(float(water - want)) < float(want) * 0.15, "and ten seconds of it put %d cells in the room" % water)
