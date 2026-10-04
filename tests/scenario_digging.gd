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
##  F. a Relay Mast links 280 cells, to Conduits as well as Masts
## Laid out as in v2, scaled by D.S about the Hub's pad (P, R), except where the
## narrower map (in building terms) needs it otherwise; counts of cells x S * S.
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


## Where a v2 cell near the Hub is now: the layout scales by D.S about the pad's
## middle at ground level.
func P(x: int, y: int) -> Vector2i:
	return Vector2i((D.W >> 1) + (x - 128) * D.S, D.GROUND_Y + (y - 40) * D.S)


## A v2 rectangle near the Hub, scaled the same way and kept inside the walls.
func R(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(P(x, y), Vector2i(w, h) * D.S).intersection(Rect2i(2, 2, D.W - 4, D.H - 4))


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


func _mats(r: Rect2i) -> Dictionary:
	var out := {}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var n := D.mat_name(game.sim.get_cell(x, y))
			out[n] = out.get(n, 0) + 1
	return out


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
	var at := P(132, 37)
	check(d.fixed and d.built and d.x == at.x and d.y == at.y, "it stands on the Hub's right from the start (%d, %d)" % [d.x, d.y])
	game.demolish(d)
	check(not d.dead, "it can't be demolished")
	game.blast(P(136, 41), 6.0 * D.S, 6)
	check(d.hp == d.max_hp and not d.dead, "a blast beside it leaves it whole")
	game.levels["drill_bit"] = 3
	game.researched["drill_bit"] = true
	var r0: int = D.DRILL_REACHES[0]
	var r1: int = D.DRILL_REACHES[1]
	fill(Rect2i(d.x, D.GROUND_Y, d.w, r0 * 2), D.DIRT)
	var wl := Rect2i(d.x - D.S, D.GROUND_Y + 4 * D.S, D.S, r0 * 2)
	var wr := Rect2i(d.x + d.w, D.GROUND_Y + 4 * D.S, D.S, r0 * 2)
	fill(wl, D.STONE)   # walls either side, so nothing spills in
	fill(wr, D.STONE)
	secs(20.0)
	print("  after 20 s: reach %d / %d, bored %d" % [d.reach, d.reach_limit, d.cells_bored])
	check(d.reach == r0 and count(Rect2i(d.x, D.GROUND_Y, d.w, r0), D.AIR) == d.w * r0, "a straight %d-wide shaft, %d rows down" % [d.w, r0])
	var wh := r0 - 4 * D.S
	check(count(Rect2i(wl.position, Vector2i(D.S, wh)), D.STONE) == D.S * wh and count(Rect2i(wr.position, Vector2i(D.S, wh)), D.STONE) == D.S * wh, "its walls untouched")
	# Obsidian stops it until the Saw: a layer halfway into Drill Shaft 1's reach.
	game._finish_research("drill_shaft")
	var ob_row := (r0 + r1) >> 1
	fill(Rect2i(d.x, D.GROUND_Y + r0, d.w, r1 - r0 + 50), D.DIRT)
	var ob := Rect2i(d.x, D.GROUND_Y + ob_row, d.w, 2 * D.S)
	fill(ob, D.OBSIDIAN)
	secs(12.0)
	print("  on obsidian: reach %d, stopped above row %d" % [d.reach, ob_row])
	check(d.reach == ob_row and count(ob, D.OBSIDIAN) == ob.get_area(), "obsidian stops it without the Obsidian Saw")
	game.researched["obsidian_saw"] = true
	secs(20.0)
	check(count(ob, D.OBSIDIAN) == 0 and d.reach > ob_row + 4 * D.S, "with the Saw it cuts through (reach %d)" % d.reach)
	# At full reach, with fill dropped far down the shaft.
	fresh(true)
	d = game.drill
	game.levels["drill_shaft"] = 9
	game.researched["drill_shaft"] = true
	var full: int = game.max_reach()
	fill(Rect2i(d.x, D.GROUND_Y, d.w, full), D.AIR)
	fill(Rect2i(d.x - D.S, D.GROUND_Y, D.S, full), D.STONE)
	fill(Rect2i(d.x + d.w, D.GROUND_Y, D.S, full), D.STONE)
	d.reach_limit = full
	d.reach = full
	game.run_ticks(120)
	var t0 := Time.get_ticks_usec()
	game.run_ticks(600)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 600.0
	print("  full reach (%d rows): %.3f ms a tick" % [d.reach_limit, ms])
	var drop := full >> 1
	fill(Rect2i(d.x, D.GROUND_Y + drop, d.w, 4 * D.S), D.LOOSE_DIRT)
	secs(8.0)
	var loose := 0
	for y in range(D.GROUND_Y, D.GROUND_Y + d.reach):
		for x in range(d.x, d.x + d.w):
			if D.M.kind_of(game.sim.get_cell(x, y)) == D.M.K_POWDER:
				loose += 1
	check(loose == 0, "loose dirt dropped %d rows down the shaft got dug out (%d left)" % [drop, loose])
	# 2.0 before A1; its temperature pass adds ~0.2 ms (2.1-2.4 measured), wave 1 materials ~0.5 more.
	check(ms < 3.5, "the long channel stays cheap to watch")


func scenario_b() -> void:
	print("B. a Thumper")
	fresh()
	fill(R(136, 40, 40, 40), D.DIRT)
	build(D.B_CONDUIT, R(140, 38, 2, 2))
	var t = build(D.B_THUMPER, R(146, 38, 2, 2))
	var nb = build(D.B_CONDUIT, R(149, 38, 2, 2))
	if t == null or nb == null:
		return
	t.power = D.POWER_RESERVE
	var p0: float = t.power
	secs(D.THUMP_INTERVALS[0] + 0.5)
	check(t.blasts == 1, "it went off on its timer (%d blasts)" % t.blasts)
	check(nb.hp < nb.max_hp and t.hp > t.max_hp - 2.0, "the Conduit beside it took the blast (HP %d), the Thumper didn't (HP %.1f; its own flash singes it at most)" % [int(nb.hp), t.hp])
	game.demolish(nb)
	check(game.link_health(t, t.link) >= 1.0 if t.link != null else true, "its own link is untouched")
	var crater := R(140, 40, 14, 8)
	check(count(crater, D.DIRT) < crater.get_area() - 20 * D.S * D.S, "it cratered the dirt under it")
	var y0: int = t.y
	for _i in 12:
		t.power = D.POWER_RESERVE
		secs(D.THUMP_INTERVALS[0])
	t.power = 0.0   # no 14th blast: let the last throw land before judging where it ended up
	secs(3.0)
	print("  after 13 blasts: sank from %d to %d, power %.1f (paid %.1f a blast)" % [y0, t.y, t.power, D.THUMP_COSTS[0]])
	check(t.y >= y0 + 2 * D.S and not t.flying, "it sinks into its crater and settles (slowly: most of the rubble falls back in without a Hopper)")
	check(p0 - D.THUMP_COSTS[0] < D.POWER_RESERVE, "a blast costs power")
	# Stone: out of reach at the start, broken with Thumper Charge.
	fresh()
	var slab := R(136, 40, 40, 30)
	fill(slab, D.STONE)
	build(D.B_CONDUIT, R(140, 38, 2, 2))
	t = build(D.B_THUMPER, R(146, 38, 2, 2))
	for _i in 3:
		t.power = D.POWER_RESERVE
		t.work = 99.0
		secs(3.0)
	check(count(slab, D.STONE) == slab.get_area(), "blast power %d doesn't break stone" % game.thump_power())
	game._finish_research("thump_charge")
	t.power = D.POWER_RESERVE
	t.work = 99.0
	secs(3.0)
	check(count(slab, D.STONE) < slab.get_area() - 10 * D.S * D.S, "Thumper Charge 1 (power %d) does" % game.thump_power())


func scenario_c() -> void:
	print("C. dragging a Thumper")
	fresh()
	fill(R(136, 20, 60, 20), D.AIR)   # this far out the ground wobbles above the pad's level
	fill(R(136, 40, 60, 20), D.DIRT)
	build(D.B_CONDUIT, R(140, 38, 2, 2))
	var t = build(D.B_THUMPER, R(146, 38, 2, 2))
	t.enabled = false
	var up := Vector2(P(160, 26))
	game.grab_thumper(t, up)
	game.run_ticks(60)
	print("  held toward %s: centre now %s, flying %s, linked %s" % [up, t.center(), t.flying, t.connected])
	check(t.center().distance_to(up) < 1.5 * D.S, "it follows the cursor through the air")
	check(t.flying and not t.connected, "and is off the network while held")
	t.hold_at = Vector2(P(160, 70))
	game.run_ticks(90)
	check(t.y + t.h == D.GROUND_Y and count(t.rect(), D.BUILDING) == t.w * t.h, "pulled into the ground, it stops on the surface (bottom row %d)" % (t.y + t.h - 1))
	# A flick: swing it left (over the Hub; the map's edge is too near on the right
	# at this scale) and let go.
	t.hold_at = Vector2(P(150, 24))
	game.run_ticks(60)
	t.hold_at = Vector2(P(0, 24))
	game.run_ticks(8)
	var let_go: float = t.center().x
	var speed: float = t.vx
	game.release_thumper(t)
	game.run_ticks(180)
	print("  let go at x %.0f moving %.0f cells/s; landed at %s" % [let_go, speed, t.center()])
	check(not t.flying and t.center().x < let_go - 5.0 * D.S, "thrown, it carries on and lands further along (%.0f)" % t.center().x)
	check(game.touches_solid(t.rect()), "resting on the ground")
	# Back in range, it links up again.
	game.grab_thumper(t, Vector2(P(145, 36)))
	game.run_ticks(120)
	game.release_thumper(t)
	game.run_ticks(120)
	check(t.connected, "dropped back beside a Conduit, it links again")


func scenario_d() -> void:
	print("D. a Borer")
	fresh()
	fill(R(110, 40, 13, 120), D.DIRT)
	fill(R(110, 70, 13, 40), D.STONE)
	fill(R(118, 52, 3, 6), D.WATER)
	var b = build(D.B_BORER, R(118, 37, 3, 3), 0)
	if b == null:
		return
	check(b.mode == 2 and b.y == P(0, 37).y, "it charges up where it was put first")
	# Only the filled column: the seed's aquifer beside it has an arch of air over it now,
	# which its spring keeps topping up.
	var col := R(110, 30, 13, 130)
	var water0 := count(col, D.WATER)
	var linked_left := -1.0
	var deepest := 0
	for i in 90:
		secs(1.0)
		if linked_left < 0.0 and not b.connected:
			linked_left = i
		deepest = maxi(deepest, b.y)
		if b.starved and b.power < 0.3:
			break
	var water1 := count(col, D.WATER)
	print("  bored %d cells down to row %d, power %.2f, starved %s; water %d -> %d" % [b.cells_bored, b.y + b.h, b.power, b.starved, water0, water1])
	check(linked_left >= 0.0 and b.y > P(0, 70).y, "it tunnelled on past the network, into the stone")
	check(b.starved and b.power < 0.3 and b.mode == 0, "and stopped once its reserve ran dry")
	var wall := R(117, 44, 1, 20)
	print("  tunnel dirt %d, wall dirt %d of %d; wall holds %s" % [count(R(118, 40, 3, 25), D.DIRT), count(wall, D.DIRT), wall.get_area(), _mats(wall)])
	check(count(R(118, 40, 3, 25), D.DIRT) == 0 and count(wall, D.DIRT) >= wall.get_area() * 0.98, "leaving a %d-wide tunnel with its walls standing" % b.w)
	check(absi(water1 - water0) <= 2 * D.S * D.S, "the water it went through went round it (%d -> %d)" % [water0, water1])
	# Stops: bedrock, a building, obsidian until the Saw.
	for case: Array in [[D.BEDROCK, "Bedrock"], [D.OBSIDIAN, "Obsidian"]]:
		fresh()
		fill(R(110, 40, 13, 30), D.DIRT)
		fill(R(118, 50, 3, 1), case[0])
		b = build(D.B_BORER, R(118, 37, 3, 3), 0)
		secs(12.0)
		print("  %s: stopped at row %d: %s" % [case[1], b.y + b.h, b.stuck])
		check(b.y + b.h == P(0, 50).y and b.stuck.begins_with(case[1]), "%s stops it" % case[1])
		if case[0] == D.OBSIDIAN:
			game.researched["obsidian_saw"] = true
			secs(6.0)
			check(b.y + b.h > P(0, 51).y, "with the Saw it cuts on (row %d)" % (b.y + b.h))
	fresh()
	fill(R(100, 40, 40, 20), D.DIRT)
	build(D.B_CONDUIT, R(112, 38, 2, 2))
	b = build(D.B_BORER, R(117, 37, 3, 3), 1)
	secs(6.0)
	check(b.x == P(114, 0).x and b.stuck.begins_with("A building"), "a building stops it (at x %d: %s)" % [b.x, b.stuck])


func scenario_e() -> void:
	print("E. Homing")
	fresh()
	game.tiers_open[2] = true
	game.researched["homing"] = true
	fill(R(110, 40, 13, 200), D.STONE)
	var b = build(D.B_BORER, R(118, 37, 3, 3), 0)
	var modes := {}
	var low := 99.0
	var first_deep := 0
	for i in 150:
		secs(1.0)
		modes[b.mode] = true
		if b.mode == 1 and first_deep == 0:
			first_deep = b.y
			low = b.power
		if first_deep > 0 and b.mode == 0 and b.y > first_deep + 3 * D.S:
			break
	print("  turned for home at row %d on %.1f power; modes seen %s; now at row %d, mode %d, power %.1f" % [first_deep + b.h, low, modes.keys(), b.y + b.h, b.mode, b.power])
	check(modes.has(1) and low <= D.BORER_RESERVES[0] * 0.5 + 0.5, "at half power it heads home")
	check(modes.has(3), "topped up, it heads back out")
	check(b.mode == 0 and b.y > first_deep + 3 * D.S, "and bores on past where it turned (row %d)" % (b.y + b.h))


func scenario_f() -> void:
	print("F. Relay Mast")
	fresh()
	game.tiers_open[2] = true
	game.researched["cache"] = true
	game.researched["relay_mast"] = true
	game._refresh_unlocks()
	game.stock[D.R_GLIMMER] = 10.0
	fill(R(136, 20, 90, 20), D.AIR)
	fill(R(136, 40, 90, 10), D.DIRT)
	check(game.check_place(D.B_CONDUIT, R(150, 38, 2, 2)) == "Out of network range", "a Conduit 22 v2 cells out is out of the Hub's range")
	var m = build(D.B_MAST, R(150, 37, 2, 3))
	check(m != null and m.connected, "a Mast there links")
	# The map is too narrow (in building terms) for v2's 25 cells further right, so
	# the Conduit sits that far below the Mast instead, in a pocket of its own.
	var pocket := Rect2i(m.x - 20, m.y + m.h + 210, 60, 40)
	fill(pocket, D.AIR)
	var cr := Rect2i(m.x, pocket.end.y - 2 * D.S, 2 * D.S, 2 * D.S)
	var c = build(D.B_CONDUIT, cr)
	check(c != null and c.connected and c.link == m, "and a Conduit %d cells from it links to the Mast" % roundi(m.center().distance_to(Vector2(cr.get_center()))))
