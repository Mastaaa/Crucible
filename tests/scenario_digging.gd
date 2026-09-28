extends SceneTree
## Phase-6 digging checks on seed 7, laid out by hand next to the Hub:
##  A. the fixed Drill: there from the start, can't be demolished or blasted,
##     straight 3-wide shaft, obsidian stops it until the Saw, cheap at full reach
##  B. a Thumper: blasts on its timer, pays per blast, sinks into dirt, can't
##     break stone until Thumper Charge, spares itself but not its neighbours
##  C. dragging a Thumper: follows the cursor through open space, stops at rock,
##     off the network while held, thrown when let go mid-swing
##  D. a Borer: charges up, then tunnels; runs on its reserve out past the network;
##     stops at bedrock, a building and (until the Saw) obsidian; water goes round it
##  E. Homing: at half power the Borer climbs back, recharges and goes back to work
##  F. a Relay Mast links 28 cells, to Conduits as well as Masts
## Run: godot --headless --path . --script tests/scenario_digging.gd

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
		scenario_e()
		scenario_f()
		print("FAILURES: %d" % fails)
		return true
	return false


func fresh(drill_on := false) -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	game.drill.enabled = drill_on
	game.stock[D.R_STONE] = 200.0
	for id in ["thumper", "borer"]:
		game.researched[id] = true
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


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func secs(s: float) -> void:
	for _i in int(s):
		game.stock[D.R_POWER] = 100.0
		game.run_ticks(60)
	game.run_ticks(int((s - int(s)) * 60.0))


func scenario_a() -> void:
	print("A. the fixed Drill")
	fresh(true)
	var d = game.drill
	check(d.fixed and d.built and d.x == 132 and d.y == 37, "it stands on the Hub's right from the start (%d, %d)" % [d.x, d.y])
	game.demolish(d)
	check(not d.dead, "it can't be demolished")
	game.blast(Vector2i(136, 41), 6.0, 6)
	check(d.hp == d.max_hp and not d.dead, "a blast beside it leaves it whole")
	game.levels["drill_bit"] = 3
	game.researched["drill_bit"] = true
	fill(Rect2i(132, 40, 3, 60), D.DIRT)
	fill(Rect2i(131, 44, 1, 40), D.STONE)   # walls either side, so nothing spills in
	fill(Rect2i(135, 44, 1, 40), D.STONE)
	secs(20.0)
	print("  after 20 s: reach %d / %d, bored %d" % [d.reach, d.reach_limit, d.cells_bored])
	check(d.reach == 30 and count(Rect2i(132, 40, 3, 30), D.AIR) == 90, "a straight 3-wide shaft, 30 rows down")
	check(count(Rect2i(131, 44, 1, 26), D.STONE) == 26 and count(Rect2i(135, 44, 1, 26), D.STONE) == 26, "its walls untouched")
	# Obsidian stops it until the Saw.
	game._finish_research("drill_shaft")
	fill(Rect2i(132, 70, 3, 30), D.DIRT)
	fill(Rect2i(132, 76, 3, 2), D.OBSIDIAN)
	secs(12.0)
	print("  on obsidian: reach %d, stopped above row %d" % [d.reach, 76 - 40])
	check(d.reach == 36 and count(Rect2i(132, 76, 3, 2), D.OBSIDIAN) == 6, "obsidian stops it without the Obsidian Saw")
	game.researched["obsidian_saw"] = true
	secs(20.0)
	check(count(Rect2i(132, 76, 3, 2), D.OBSIDIAN) == 0 and d.reach > 40, "with the Saw it cuts through (reach %d)" % d.reach)
	# At full reach, with fill dropped far down the shaft.
	fresh(true)
	d = game.drill
	game.levels["drill_shaft"] = 9
	game.researched["drill_shaft"] = true
	fill(Rect2i(132, 40, 3, 850), D.AIR)
	fill(Rect2i(131, 40, 1, 850), D.STONE)
	fill(Rect2i(135, 40, 1, 850), D.STONE)
	d.reach_limit = game.max_reach()
	d.reach = 850
	game.run_ticks(120)
	var t0 := Time.get_ticks_usec()
	game.run_ticks(600)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 600.0
	print("  full reach (%d rows): %.3f ms a tick" % [d.reach_limit, ms])
	fill(Rect2i(132, 480, 3, 4), D.LOOSE_DIRT)
	secs(8.0)
	var loose := 0
	for y in range(40, 40 + d.reach):
		for x in range(132, 135):
			if D.M.kind_of(game.sim.get_cell(x, y)) == D.M.K_POWDER:
				loose += 1
	check(loose == 0, "loose dirt dropped 440 rows down the shaft got dug out (%d left)" % loose)
	check(ms < 2.0, "the long channel stays cheap to watch")


func scenario_b() -> void:
	print("B. a Thumper")
	fresh()
	fill(Rect2i(136, 40, 40, 40), D.DIRT)
	build(D.B_CONDUIT, Rect2i(140, 38, 2, 2))
	var t = build(D.B_THUMPER, Rect2i(146, 38, 2, 2))
	var nb = build(D.B_CONDUIT, Rect2i(149, 38, 2, 2))
	if t == null or nb == null:
		return
	t.power = D.POWER_RESERVE
	var p0: float = t.power
	secs(D.THUMP_INTERVALS[0] + 0.5)
	check(t.blasts == 1, "it went off on its timer (%d blasts)" % t.blasts)
	check(nb.hp < nb.max_hp and t.hp > t.max_hp - 2.0, "the Conduit beside it took the blast (HP %d), the Thumper didn't (HP %.1f; its own flash singes it at most)" % [int(nb.hp), t.hp])
	game.demolish(nb)
	check(game.link_health(t, t.link) >= 1.0 if t.link != null else true, "its own link is untouched")
	check(count(Rect2i(140, 40, 14, 8), D.DIRT) < 14 * 8 - 20, "it cratered the dirt under it")
	var y0: int = t.y
	for _i in 12:
		t.power = D.POWER_RESERVE
		secs(D.THUMP_INTERVALS[0])
	print("  after 13 blasts: sank from %d to %d, power %.1f (paid %.1f a blast)" % [y0, t.y, t.power, D.THUMP_COSTS[0]])
	check(t.y >= y0 + 2 and not t.flying, "it sinks into its crater and settles (slowly: most of the rubble falls back in without a Hopper)")
	check(p0 - D.THUMP_COSTS[0] < D.POWER_RESERVE, "a blast costs power")
	# Stone: out of reach at the start, broken with Thumper Charge.
	fresh()
	fill(Rect2i(136, 40, 40, 30), D.STONE)
	build(D.B_CONDUIT, Rect2i(140, 38, 2, 2))
	t = build(D.B_THUMPER, Rect2i(146, 38, 2, 2))
	for _i in 3:
		t.power = D.POWER_RESERVE
		t.work = 99.0
		secs(3.0)
	check(count(Rect2i(136, 40, 40, 30), D.STONE) == 40 * 30, "blast power %d doesn't break stone" % game.thump_power())
	game._finish_research("thump_charge")
	t.power = D.POWER_RESERVE
	t.work = 99.0
	secs(3.0)
	check(count(Rect2i(136, 40, 40, 30), D.STONE) < 40 * 30 - 10, "Thumper Charge 1 (power %d) does" % game.thump_power())


func scenario_c() -> void:
	print("C. dragging a Thumper")
	fresh()
	fill(Rect2i(136, 40, 60, 20), D.DIRT)
	build(D.B_CONDUIT, Rect2i(140, 38, 2, 2))
	var t = build(D.B_THUMPER, Rect2i(146, 38, 2, 2))
	t.enabled = false
	game.grab_thumper(t, Vector2(160, 26))
	game.run_ticks(60)
	print("  held toward (160, 26): centre now %s, flying %s, linked %s" % [t.center(), t.flying, t.connected])
	check(t.center().distance_to(Vector2(160, 26)) < 1.5, "it follows the cursor through the air")
	check(t.flying and not t.connected, "and is off the network while held")
	t.hold_at = Vector2(160, 70)
	game.run_ticks(90)
	check(t.y + t.h == 40 and count(t.rect(), D.BUILDING) == 4, "pulled into the ground, it stops on the surface (bottom row %d)" % (t.y + t.h - 1))
	# A flick: swing it right and let go.
	t.hold_at = Vector2(150, 24)
	game.run_ticks(60)
	t.hold_at = Vector2(240, 24)
	game.run_ticks(8)
	var let_go: float = t.center().x
	game.release_thumper(t)
	game.run_ticks(180)
	print("  let go at x %.0f moving %.0f cells/s; landed at %s" % [let_go, t.vx, t.center()])
	check(not t.flying and t.center().x > let_go + 5.0, "thrown, it carries on and lands further along (%.0f)" % t.center().x)
	check(game.touches_solid(t.rect()), "resting on the ground")
	# Back in range, it links up again.
	game.grab_thumper(t, Vector2(145, 36))
	game.run_ticks(120)
	game.release_thumper(t)
	game.run_ticks(120)
	check(t.connected, "dropped back beside a Conduit, it links again")


func scenario_d() -> void:
	print("D. a Borer")
	fresh()
	fill(Rect2i(110, 40, 13, 120), D.DIRT)
	fill(Rect2i(110, 70, 13, 40), D.STONE)
	fill(Rect2i(118, 52, 3, 6), D.WATER)
	var b = build(D.B_BORER, Rect2i(118, 37, 3, 3), 0)
	if b == null:
		return
	check(b.mode == 2 and b.y == 37, "it charges up where it was put first")
	# Only the filled column: the seed's aquifer beside it has an arch of air over it now,
	# which its spring keeps topping up.
	var water0 := count(Rect2i(110, 30, 13, 130), D.WATER)
	var linked_left := -1.0
	var deepest := 0
	for i in 90:
		secs(1.0)
		if linked_left < 0.0 and not b.connected:
			linked_left = i
		deepest = maxi(deepest, b.y)
		if b.starved and b.power < 0.3:
			break
	var water1 := count(Rect2i(110, 30, 13, 130), D.WATER)
	print("  bored %d cells down to row %d, power %.2f, starved %s; water %d -> %d" % [b.cells_bored, b.y + b.h, b.power, b.starved, water0, water1])
	check(linked_left >= 0.0 and b.y > 70, "it tunnelled on past the network, into the stone")
	check(b.starved and b.power < 0.3 and b.mode == 0, "and stopped once its reserve ran dry")
	check(count(Rect2i(118, 40, 3, 25), D.DIRT) == 0 and count(Rect2i(117, 44, 1, 20), D.DIRT) == 20, "leaving a 3-wide tunnel with its walls standing")
	check(absi(water1 - water0) <= 2, "the water it went through went round it (%d -> %d)" % [water0, water1])
	# Stops: bedrock, a building, obsidian until the Saw.
	for case: Array in [[D.BEDROCK, "Bedrock"], [D.OBSIDIAN, "Obsidian"]]:
		fresh()
		fill(Rect2i(110, 40, 13, 30), D.DIRT)
		fill(Rect2i(118, 50, 3, 1), case[0])
		b = build(D.B_BORER, Rect2i(118, 37, 3, 3), 0)
		secs(12.0)
		print("  %s: stopped at row %d: %s" % [case[1], b.y + b.h, b.stuck])
		check(b.y + b.h == 50 and b.stuck.begins_with(case[1]), "%s stops it" % case[1])
		if case[0] == D.OBSIDIAN:
			game.researched["obsidian_saw"] = true
			secs(6.0)
			check(b.y + b.h > 51, "with the Saw it cuts on (row %d)" % (b.y + b.h))
	fresh()
	fill(Rect2i(100, 40, 40, 20), D.DIRT)
	build(D.B_CONDUIT, Rect2i(112, 38, 2, 2))
	b = build(D.B_BORER, Rect2i(117, 37, 3, 3), 1)
	secs(6.0)
	check(b.x == 114 and b.stuck.begins_with("A building"), "a building stops it (at x %d: %s)" % [b.x, b.stuck])


func scenario_e() -> void:
	print("E. Homing")
	fresh()
	game.tiers_open[2] = true
	game.researched["homing"] = true
	fill(Rect2i(110, 40, 13, 200), D.STONE)
	var b = build(D.B_BORER, Rect2i(118, 37, 3, 3), 0)
	var modes := {}
	var low := 99.0
	var first_deep := 0
	for i in 150:
		secs(1.0)
		modes[b.mode] = true
		if b.mode == 1 and first_deep == 0:
			first_deep = b.y
			low = b.power
		if first_deep > 0 and b.mode == 0 and b.y > first_deep + 3:
			break
	print("  turned for home at row %d on %.1f power; modes seen %s; now at row %d, mode %d, power %.1f" % [first_deep + 3, low, modes.keys(), b.y + 3, b.mode, b.power])
	check(modes.has(1) and low <= D.BORER_RESERVES[0] * 0.5 + 0.5, "at half power it heads home")
	check(modes.has(3), "topped up, it heads back out")
	check(b.mode == 0 and b.y > first_deep + 3, "and bores on past where it turned (row %d)" % (b.y + 3))


func scenario_f() -> void:
	print("F. Relay Mast")
	fresh()
	game.tiers_open[2] = true
	game.researched["cache"] = true
	game.researched["relay_mast"] = true
	game._refresh_unlocks()
	game.stock[D.R_GLIMMER] = 10.0
	fill(Rect2i(136, 20, 90, 20), D.AIR)
	fill(Rect2i(136, 40, 90, 10), D.DIRT)
	check(game.check_place(D.B_CONDUIT, Rect2i(150, 38, 2, 2)) == "Out of network range", "a Conduit 23 cells out is out of the Hub's range")
	var m = build(D.B_MAST, Rect2i(150, 37, 2, 3))
	check(m != null and m.connected, "a Mast there links")
	var c = build(D.B_CONDUIT, Rect2i(175, 38, 2, 2))
	check(c != null and c.connected and c.link == m, "and a Conduit 25 cells past it links to the Mast")
