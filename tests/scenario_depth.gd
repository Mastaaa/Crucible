extends SceneTree
## Phase-9 depth checks on seed 7:
##  A. worldgen: the Magma band's rock is hot rock from about row 3000, the plug too;
##     hot rock and stone hold each other up along a row
##  B. water on hot rock boils into steam, and slowly quenches it to stone
##  C. the fixed Drill stops at hot rock until the Coolant Jacket, then cuts it for
##     water from the Hub, venting steam up its shaft; with no water it waits
##  D. a Borer: hot rock stops it until the jacket; it fills its tank before it sets
##     out, cuts on out past the network, and the steam comes out behind it
##  E. mites dig hot rock only with Ember Brood
##  F. a Steam Turbine makes power from steam rising through it (about 2/s over a room
##     full of it), passes the steam out of its top, and idles without it
##  G. the Crucible draws 4 power/s while charging; out of power for 5 s it drains
##  H. lava and Borers (phase 10): without the jacket a Borer stops short of any lava;
##     a jacketed one shrugs off lava while its tank has water, and with the Saw it
##     quenches lava it faces into obsidian and bores through, banking it
## Run: godot --headless --path . --script tests/scenario_depth.gd

const D = preload("res://scripts/defs.gd")
const WR = preload("res://scripts/warren.gd")
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
		scenario_c()
		scenario_d()
		scenario_e()
		scenario_f()
		scenario_g()
		scenario_h()
		print("FAILURES: %d" % fails)
		return true
	return false


func fresh(drill_on := false) -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	game.drill.enabled = drill_on
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


func scenario_c() -> void:
	print("C. the Drill and hot rock")
	fresh(true)
	var d = game.drill
	game.levels["drill_bit"] = 3
	game.researched["drill_bit"] = true
	var r0: int = D.DRILL_REACHES[0]
	fill(Rect2i(d.x, D.GROUND_Y, d.w, r0 + 200), D.DIRT)
	fill(Rect2i(d.x - S, D.GROUND_Y + 4 * S, S, r0 + 200), D.STONE)
	fill(Rect2i(d.x + d.w, D.GROUND_Y + 4 * S, S, r0 + 200), D.STONE)
	var hot_row := r0 - 60
	var hot := Rect2i(d.x, D.GROUND_Y + hot_row, d.w, 2 * S)
	fill(hot, D.HOT_ROCK)
	keep_hot(hot)
	secs(20.0)
	print("  on hot rock: reach %d, stopped above row %d: '%s'" % [d.reach, hot_row, d.stuck])
	check(d.reach == hot_row and count(hot, D.HOT_ROCK) == hot.get_area() and d.stuck.begins_with("Hot rock"),
			"hot rock stops the Drill without the Coolant Jacket")
	research("coolant_jacket")
	game.stock[D.R_WATER] = 0.0
	secs(6.0)
	print("  jacket, no water: reach %d, hot rock %d / %d, '%s'" % [d.reach, count(hot, D.HOT_ROCK), hot.get_area(), d.stuck])
	check(count(hot, D.HOT_ROCK) == hot.get_area() and d.stuck.begins_with("Out of water"), "with the jacket but no water it waits")
	game.stock[D.R_WATER] = 20.0
	var most := 0
	var shaft := Rect2i(d.x, D.GROUND_Y, d.w, hot_row)
	for _i in 20:
		secs(1.0)
		most = maxi(most, steam(shaft))
	var used: float = 20.0 - game.stock[D.R_WATER] - d.coolant
	print("  with water: reach %d, hot rock left %d, water used %.2f (tank %.1f), up to %d steam in the shaft" % [d.reach,
			count(hot, D.HOT_ROCK), used, d.coolant, most])
	check(count(hot, D.HOT_ROCK) == 0 and d.reach > hot_row + 2 * S, "it cuts through, water from the Hub in its tank")
	var want := hot.get_area() * D.COOLANT_WATER_PER_CELL
	check(absf(used - want) < 0.05, "for 1 Water per %d cells (%.2f of %.2f)" % [roundi(1.0 / D.COOLANT_WATER_PER_CELL), used, want])
	check(most > 0, "and the steam goes up the shaft")


func scenario_d() -> void:
	print("D. a Borer and hot rock")
	fresh()
	research("borer")
	fill(R(110, 40, 13, 60), D.DIRT)
	fill(R(118, 50, 3, 2), D.HOT_ROCK)
	keep_hot(R(118, 50, 3, 2))
	var b = build(D.B_BORER, R(118, 37, 3, 3), 0)
	if b == null:
		return
	secs(12.0)
	print("  stopped at row %d: %s" % [b.y + b.h, b.stuck])
	check(b.y + b.h == P(0, 50).y and b.stuck.begins_with("Hot rock"), "hot rock stops it without the jacket")
	# Back at the start, with the jacket: it fills up on the network, then goes.
	fresh()
	research("borer")
	research("coolant_jacket")
	game.stock[D.R_WATER] = 20.0
	fill(R(110, 40, 13, 60), D.DIRT)
	var hot := R(118, 60, 3, 3)
	fill(hot, D.HOT_ROCK)
	keep_hot(hot)
	b = build(D.B_BORER, R(118, 37, 3, 3), 0)
	for _i in 20:
		if b.mode != 2:
			break
		secs(1.0)
	var tank: float = b.coolant
	var most := 0
	var off := false
	for _i in 30:
		secs(1.0)
		off = off or not b.connected
		most = maxi(most, steam(Rect2i(b.x, b.y - 4 * S, b.w, 4 * S)))
		if b.y > hot.end.y + S:
			break
	print("  tank %.1f before; off the network %s; bottom at row %d (hot rock to %d), hot rock left %d, tank %.2f, up to %d steam behind it" % [tank,
			off, b.y + b.h, hot.end.y, count(hot, D.HOT_ROCK), b.coolant, most])
	check(tank >= D.COOLANT_CAP - 1.0, "it fills its tank while linked")
	check(off and count(hot, D.HOT_ROCK) == 0 and b.y + b.h > hot.end.y, "and cuts through hot rock out past the network")
	check(most > 0, "venting steam out of its tail")


func scenario_e() -> void:
	print("E. mites and hot rock")
	check(not WR.can_dig(D.HOT_ROCK, true), "Hard Teeth mites can't dig hot rock")
	check(WR.can_dig(D.HOT_ROCK, true, true) and WR.mask("ember")[D.HOT_ROCK] == 1 and WR.mask("teeth")[D.HOT_ROCK] == 0,
			"Ember Brood mites can")


func scenario_f() -> void:
	print("F. a Steam Turbine")
	fresh()
	check(not game.is_unlocked(D.B_TURBINE), "locked before its research")
	research("steam_turbine")
	check(game.is_unlocked(D.B_TURBINE), "open after it")
	var room := Rect2i(200, 2100, 200, 400)
	arena(room)
	var sz: Vector2i = D.B_SIZES[D.B_TURBINE]
	# On a bedrock shelf, the room's left wall beside it: steam fills the room under it.
	var core := Rect2i(room.position.x, room.position.y + 200, sz.x, sz.y)
	fill(Rect2i(core.end.x, core.position.y, room.end.x - core.end.x, 10), D.BEDROCK)
	var t = put_built(D.B_TURBINE, core)
	game.run_ticks(10)
	var under := Rect2i(room.position.x, core.end.y, room.size.x, room.end.y - core.end.y)
	secs(2.0)
	check(t.flow == 0.0 and not t.dead, "idle with no steam")
	var made0: float = t.store[D.R_POWER]
	for _i in 6:
		fill(under, D.STEAM)
		game.run_ticks(60)
	var above := steam(Rect2i(room.position.x, room.position.y, room.size.x, core.position.y - room.position.y))
	print("  6 s over a room of steam: making %.2f power/s, holding %.1f; %d steam over it" % [t.flow, t.store[D.R_POWER], above])
	check(t.flow > 1.5 and t.flow <= 4.01, "it makes power from steam rising through it")
	check(t.store[D.R_POWER] > made0 and above > 0, "and the steam comes out of its top")


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
	print("H. lava and Borers")
	fresh()
	research("borer")
	# A dirt block with a pool of lava half a Borer wide under where it starts.
	fill(R(110, 40, 13, 60), D.DIRT)
	var pool := R(118, 50, 2, 3)
	fill(pool, D.LAVA)
	var b = build(D.B_BORER, R(118, 37, 3, 3), 0)
	if b == null:
		return
	secs(12.0)
	check(b.stuck.begins_with("Lava ahead") and b.y + b.h == pool.position.y and not b.dead,
			"without the jacket it stops short of lava it half faces (%s, bottom %d, pool %d)" % [b.stuck, b.y + b.h, pool.position.y])
	# The jacket and the Saw: it quenches the pool and bores on through, banking obsidian.
	fresh()
	for id in ["borer", "coolant_jacket", "obsidian_saw"]:
		research(id)
	game.stock[D.R_WATER] = 20.0
	fill(R(110, 40, 13, 60), D.DIRT)
	pool = R(118, 50, 3, 4)
	fill(pool, D.LAVA)
	b = build(D.B_BORER, R(118, 37, 3, 3), 0)
	var o0: float = game.total(D.R_OBSIDIAN)
	for _i in 40:
		secs(1.0)
		if b.y > pool.end.y + S:
			break
	print("  bottom at %d (pool %d-%d), lava left %d, obsidian banked %.1f, hp %d" % [b.y + b.h, pool.position.y, pool.end.y,
			count(pool, D.LAVA), game.total(D.R_OBSIDIAN) - o0, int(b.hp)])
	check(b.y > pool.end.y and count(pool, D.LAVA) == 0 and not b.dead, "with the jacket and the Saw it bores through the pool")
	check(game.total(D.R_OBSIDIAN) - o0 > 0.5 * pool.get_area() * D.cell_units(D.OBSIDIAN),
			"quenching it into obsidian and banking it (%.1f)" % (game.total(D.R_OBSIDIAN) - o0))
	# The shield: lava round a jacketed Borer boils its tank instead of burning it.
	fresh()
	research("borer")
	research("coolant_jacket")
	var room := Rect2i(300, 2100, 120, 120)
	arena(room)
	var cell := Rect2i(room.position.x + 40, room.end.y - 30, 30, 30)
	b = put_built(D.B_BORER, cell)
	b.enabled = false
	b.coolant = D.COOLANT_CAP
	fill(Rect2i(cell.position.x - 3, cell.position.y, 3, 30), D.LAVA)
	secs(3.0)
	check(b.hp >= b.max_hp and b.coolant < D.COOLANT_CAP, "lava beside a jacketed Borer boils its tank (%.2f left) and leaves it whole" % b.coolant)
	b.coolant = 0.0
	game.stock[D.R_WATER] = 0.0
	secs(3.0)
	check(b.hp < b.max_hp, "with the tank dry it burns (%d of %d)" % [int(b.hp), int(b.max_hp)])
	# Water standing on a jacketed Borer goes into its tank (its own steam condensing
	# back down a shaft).
	fresh()
	research("borer")
	research("coolant_jacket")
	game.stock[D.R_WATER] = 0.0
	arena(room)
	b = put_built(D.B_BORER, cell)
	b.enabled = false
	b.coolant = 0.0
	var wet := Rect2i(cell.position.x, cell.position.y - 10, 30, 10)
	fill(wet, D.WATER)
	secs(2.0)
	check(b.coolant > 0.8 * wet.get_area() / D.CELLS_PER_UNIT and count(room, D.WATER) < 0.2 * wet.get_area(),
			"water poured on a jacketed Borer ends up in its tank (%.2f of %.2f)" % [b.coolant, wet.get_area() / D.CELLS_PER_UNIT])
