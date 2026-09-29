extends SceneTree
## Phase-7 Warren checks on seed 7, on a dirt pad laid beside the Hub:
##  A. the chamber's shape and Hard Teeth's scale; the search starts on it
##  C. a buried colony digs its chamber, hauls it home and banks it
##  D. hazards: crushed, lava, fire panic (it lights coal it brushes, then dies)
##  E. breeding: a lost mite is replaced for Stone
##  F. settling: freshly dug ground holds for a while, then weathers as before
##  G. a marker: they tunnel to it (wandering a little) and dig out a circle; a
##     stone shell stops them; clearing it sends them home
##  H. Sounding leaves a skin round a pool at the marker; Ember Brood walks
##     through fire; drowning and choking
## Run: godot --headless --path . --script tests/scenario_warren.gd

const D = preload("res://scripts/defs.gd")
const WR = preload("res://scripts/warren.gd")
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
		scenario_c()
		scenario_d()
		scenario_f()
		scenario_g()
		scenario_h()
		print("FAILURES: %d" % fails)
		return true
	return false


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	game.drill.enabled = false
	game.stock[D.R_STONE] = 200.0
	game.researched["warren"] = true
	game._refresh_unlocks()


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


## Every cell of a list of bites.
func bite_cells(bites: Array) -> Array:
	var out: Array = []
	for q: Vector2i in bites:
		var r := WR.bite_rect(q)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				out.append(Vector2i(x, y))
	return out


func count(cells: Array, m: int) -> int:
	var n := 0
	for c: Vector2i in cells:
		if game.sim.get_cell(c.x, c.y) == m:
			n += 1
	return n


## Put a mite in bite `q` of a Warren (its own cell to check hazards is the bite's middle).
func mite_at(b, q: Vector2i) -> Dictionary:
	var mt: Dictionary = WR.new_mite(q)
	b.mites.append(mt)
	return mt


func mid(q: Vector2i) -> Vector2i:
	return Vector2i(WR.bite_centre(q))


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func secs(s: float, w = null) -> void:
	for _i in int(s):
		game.stock[D.R_POWER] = 100.0
		if w != null:
			w.power = D.POWER_RESERVE
		game.run_ticks(60)


## A dirt pad left of the Hub, and a Warren on it: out in the open, or buried
## (dirt all round, with a slot a bite and a half tall over its roof for a doorstep).
func pad_warren(buried := false) -> Object:
	var hub = game.hub
	var top: int = hub.y + hub.h
	fill(Rect2i(hub.x - 300, hub.y - 140, 300, top - hub.y + 140), D.DIRT if buried else D.AIR)
	fill(Rect2i(hub.x - 300, top, 300, 400), D.DIRT)
	var sz: Vector2i = D.B_SIZES[D.B_WARREN]
	var r := Rect2i(hub.x - 9 * D.S, top - sz.y, sz.x, sz.y)
	if buried:
		fill(Rect2i(r.position.x, r.position.y - 8, r.size.x, r.size.y + 8), D.AIR)
	var why: String = game.check_place(D.B_WARREN, r)
	if why != "":
		print("  !! can't place the Warren at %s: %s" % [r, why])
		fails += 1
		return null
	var b = game.place(D.B_WARREN, r)
	for _i in 900:
		if b.built:
			break
		game.run_ticks(1)
	return b


## Run until the Warren's mites reach one of `stages`, or `limit` seconds pass.
func until_stage(b, stages: Array, limit: int) -> int:
	var t := 0
	while not stages.has(b.stage) and t < limit:
		secs(5, b)
		t += 5
	return t


func scenario_a() -> void:
	print("A. the chamber and the search")
	fresh()
	var b = pad_warren(true)
	if b == null:
		return
	var dome := WR.dome_bites(b, 1.0)
	var above := true
	for q: Vector2i in dome:
		if WR.bite_centre(q).y >= b.y + b.h or WR.home_rect(b).has_point(q):
			above = false
	check(dome.size() > 150 and dome.size() < 400 and above, "a half-circle over it, radius %d, above its floor line (%d bites)" % [int(D.WARREN_DOME_R), dome.size()])
	var big := WR.dome_bites(b, D.WARREN_TEETH_SCALE).size()
	check(big > dome.size() * 2, "Hard Teeth: radius %.0f (%d bites)" % [D.WARREN_DOME_R * D.WARREN_TEETH_SCALE, big])
	var s: Dictionary = WR.search(game, b)
	check(s.stage == "dome" and s.left < dome.size() and s.left > dome.size() - 30, "it starts on the chamber: every bite but its slot (%d of %d)" % [s.left, dome.size()])
	check(WR.home_dist(s, s.targets[0][1]) == 0, "nearest first: dug from its doorstep %s" % s.targets[0][1])
	var q: Vector2i = s.targets[5][0]
	fill(WR.bite_rect(q), D.SULFUR)
	var s2: Dictionary = WR.search(game, b)
	check(s2.left == s.left - 1, "a bite of sulfur is left alone (%d -> %d)" % [s.left, s2.left])


func scenario_c() -> void:
	print("C. a buried colony digs its chamber")
	fresh()
	var b = pad_warren(true)
	if b == null:
		return
	secs(1, b)
	check(b.mites.size() == D.WARREN_MITES, "3 mites come out (%d)" % b.mites.size())
	var stone0: float = game.stock[D.R_STONE]
	secs(20, b)
	check(b.cells_dug >= 400, "20 s in: %d cells nibbled" % b.cells_dug)
	check(game.stock[D.R_STONE] > stone0, "what they haul home is banked (+%.1f Stone)" % (game.stock[D.R_STONE] - stone0))
	var t: int = 21 + until_stage(b, ["idle"], 400)
	# A lump they ate round can hang in the middle of the chamber out of reach until
	# it weathers or caves in and lands where they can get at it.
	while b.zone_left > 0 and t < 400:
		secs(5, b)
		t += 5
	print("    chamber done in %d s: %d cells dug, %d mites lost" % [t, b.cells_dug, b.mites_lost])
	check(b.stage == "idle" and b.zone_left == 0, "the chamber gets finished, then they wait for a marker")
	check(b.built and not b.dead and not b.falling, "the Warren keeps its footing")


func scenario_d() -> void:
	print("D. hazards")
	fresh()
	var b = pad_warren()
	if b == null:
		return
	secs(1, b)
	b.enabled = false
	var n0: int = b.mites.size()
	var mt: Dictionary = b.mites[0]
	var c := mid(mt.p)
	game.sim.set_cell(c.x, c.y, D.DIRT)
	game.run_ticks(1)
	check(b.mites.size() < n0 and b.last_loss == "crushed", "dirt landing on one crushes it, and any sharing its bite")
	var top: int = game.hub.y + game.hub.h
	var hole := WR.bite_of(Vector2i(game.hub.x - 200, top + 40))
	fill(WR.bite_rect(hole), D.LAVA)
	mt = mite_at(b, hole)
	game.run_ticks(1)
	check(not b.mites.has(mt) and b.last_loss == "lava", "lava kills one")
	# Fire: a mite on a coal floor beside a flame.
	var q := WR.bite_of(Vector2i(game.hub.x - 200, top - 3))
	fill(Rect2i(q.x * WR.BITE - 12, top, 28, WR.BITE), D.COAL)
	mt = mite_at(b, q)
	var r := WR.bite_rect(q)
	game.sim.set_cell(r.end.x, r.position.y + 2, D.FIRE)
	game.run_ticks(2)
	check(mt.state == WR.S_PANIC, "a mite next to a flame catches and panics")
	var burning := false
	for _i in 4 * 60:
		game.run_ticks(1)
		if game.sim.count_burning() > 0:
			burning = true
	check(burning, "it lights what it brushes")
	check(not b.mites.has(mt) and b.last_loss == "burned", "and burns out")
	print("E. breeding")
	b.enabled = true
	var n1: int = b.mites.size()
	var lost0: int = b.mites_lost
	secs(D.WARREN_BREED_S + 1, b)
	var born: int = b.mites.size() - n1 + b.mites_lost - lost0
	check(born >= 1,
			"a replacement comes out within %d s (%d born)" % [int(D.WARREN_BREED_S), born])


func scenario_f() -> void:
	print("F. settling")
	fresh()
	var hub = game.hub
	var top: int = hub.y + hub.h
	# A dirt ceiling over a wide hole.
	var x0: int = hub.x - 330
	fill(Rect2i(x0, top, 300, 120), D.DIRT)
	fill(Rect2i(x0 + 20, top + 40, 260, 60), D.AIR)
	var held := Vector2i(x0 + 30, top + 39)
	game.excavated(Vector2i(held.x, held.y + 1))
	check(game.sim.get_settle(held.x, held.y) > 0, "the ceiling beside a dug cell is settling (%d ticks)" % game.sim.get_settle(held.x, held.y))
	check(game.sim.get_settle(held.x + 2 * D.S, held.y) == 0, "ceiling further off isn't")
	game.sim.set_cell(held.x, held.y + 1, D.LOOSE_DIRT)
	game.sim.settle_around(held.x, held.y + 1, 0, int(D.SETTLE_S * D.TICKS_PER_S))
	for _i in 3000:
		game.sim.weather(4000)
	game.run_ticks(60 * 5)
	check(game.sim.get_cell(held.x, held.y) == D.DIRT, "weathering leaves a settling cell alone")
	check(game.sim.get_cell(held.x, held.y + 1) == D.LOOSE_DIRT, "loose dirt that's settling hangs there")
	game.run_ticks(int((D.SETTLE_S - 4.0) * D.TICKS_PER_S))
	var fell: bool = game.sim.get_cell(held.x, held.y + 1) != D.LOOSE_DIRT
	for _i in 6000:
		game.sim.weather(4000)
	game.run_ticks(30)
	check(fell, "once settled, the loose dirt falls")
	check(game.sim.get_cell(held.x, held.y) != D.DIRT, "and weathering can take the ceiling again")


func scenario_g() -> void:
	print("G. a marker: tunnel there, dig out a circle")
	fresh()
	var b = pad_warren()
	if b == null:
		return
	secs(1, b)
	check(b.stage == "idle", "out in the open the chamber is air already, so they wait (%s)" % b.stage)
	var mk := Vector2i(b.x - 16 * D.S, b.y + b.h + 10 * D.S)
	check(b.center().distance_to(Vector2(mk)) <= game.warren_marker_range(), "a marker %d cells off is in range" % roundi(b.center().distance_to(Vector2(mk))))
	game.set_warren_marker(b, mk)
	secs(2, b)
	check(b.stage == "tunnel", "they head for it (%s)" % b.stage)
	var t: int = 3 + until_stage(b, ["done", "blocked"], 900)
	var circle := bite_cells(WR.marker_bites(b, 1.0))
	print("    marker dug out in %d s: %d cells dug, %d mites lost" % [t, b.cells_dug, b.mites_lost])
	check(b.stage == "done" and count(circle, D.DIRT) == 0, "they get there and dig out a circle round it (%s, %d dirt left)" % [b.stage, count(circle, D.DIRT)])
	# The tunnel: dug cells that aren't the circle, all within the corridor, not a ruled line.
	var tunnel := 0
	var stray := 0
	var offs := {}
	var in_circle := {}
	for c: Vector2i in circle:
		in_circle[c] = true
	for y in range(b.y + b.h, mk.y + 50):
		for x in range(mk.x - 50, b.x + b.w + 20):
			var c := Vector2i(x, y)
			if in_circle.has(c) or game.sim.get_cell(x, y) != D.AIR:
				continue
			tunnel += 1
			var off: float = WR.off_line(b, Vector2(c) + Vector2(0.5, 0.5))
			offs[roundi(off / WR.BITE)] = true
			if off > D.WARREN_TUNNEL_SLACK + 2.0 * WR.BITE:
				stray += 1
	check(tunnel >= 600 and stray == 0, "a tunnel of %d cells, none further than %d off the line" % [tunnel, int(D.WARREN_TUNNEL_SLACK)])
	check(offs.size() >= 3, "and it wanders a little (%d different distances off the line, in bites)" % offs.size())
	check(b.built and not b.falling, "the Warren keeps its footing")
	# Blocked: a stone shell round a new marker on a fresh map, and no Hard Teeth.
	# The shell and the ground round it are held, as Struts would hold them, so the
	# minutes they spend feeling round it don't weather a way in or cave their
	# diggings in on them.
	fresh()
	b = pad_warren()
	if b == null:
		return
	secs(1, b)
	var mk2 := Vector2i(b.x - 60, b.y + b.h + 90)
	for y in range(mk2.y - 45, mk2.y + 46):
		for x in range(mk2.x - 45, mk2.x + 46):
			var d := Vector2(x - mk2.x, y - mk2.y).length()
			if d >= 35.0 and d <= 45.0:
				game.sim.set_cell(x, y, D.STONE)
	game.sim.hold_circle(mk2.x, mk2.y, 90, 1)
	game.set_warren_marker(b, mk2)
	var t2: int = until_stage(b, ["blocked", "done"], 1200)
	check(b.stage == "blocked", "a stone shell round the marker stops them short, once they've felt round it (%s after %d s)" % [b.stage, t2])
	game.clear_warren_marker(b)
	secs(2, b)
	check(b.stage == "idle", "cleared, they go back to waiting")


func scenario_h() -> void:
	print("H. Sounding, Ember Brood, drowning, choking")
	fresh()
	game.researched["sounding"] = true
	game.researched["hard_teeth"] = true
	var b = pad_warren()
	if b == null:
		return
	# A pool in a lump of stone (a dirt skin would weather away once it settled).
	var mk := Vector2i(b.x - 8 * D.S, b.y + b.h + 8 * D.S)
	for y in range(mk.y - 60, mk.y + 61):
		for x in range(mk.x - 60, mk.x + 61):
			if Vector2(x - mk.x, y - mk.y).length() <= 60.0:
				game.sim.set_cell(x, y, D.STONE)
	var pool := Rect2i(mk.x - 10, mk.y, 20, 20)
	fill(pool, D.WATER)
	# Once the circle is dug the skin hangs in the middle of it with no stone of its
	# own to hang from, so it would cave in (phase 8): hold it, as a Strut's end would.
	game.sim.hold_circle(mk.x, mk.y + 10, 40, 1)
	game.set_warren_marker(b, mk)
	var t: int = until_stage(b, ["done", "blocked"], 900)
	var water := 0
	for y in range(pool.position.y, pool.end.y):
		for x in range(pool.position.x, pool.end.x):
			if game.sim.get_cell(x, y) == D.WATER:
				water += 1
	var circle := bite_cells(WR.marker_bites(b, D.WARREN_TEETH_SCALE))
	check(b.stage == "done" and water == 400, "with Sounding they dig out round a pool at the marker and it stays put (%s in %d s, %d water)" % [b.stage, t, water])
	check(count(circle, D.STONE) >= 600 and count(circle, D.AIR) >= 2000, "a skin of stone is left round it (%d cells), the rest dug (%d)" % [count(circle, D.STONE), count(circle, D.AIR)])
	game.researched.erase("hard_teeth")
	# Ember Brood: fire doesn't catch.
	b.enabled = false
	game.researched["ember_brood"] = true
	var top: int = game.hub.y + game.hub.h
	var q := WR.bite_of(Vector2i(game.hub.x - 200, top - 3))
	var mt := mite_at(b, q)
	var r := WR.bite_rect(q)
	game.sim.set_cell(r.end.x, r.position.y + 2, D.FIRE)
	game.run_ticks(3)
	check(mt.state != WR.S_PANIC and b.mites.has(mt), "an Ember Brood mite doesn't catch")
	game.researched.erase("ember_brood")
	# Drowning and choking, each in a sealed bite.
	var wet := WR.bite_of(Vector2i(game.hub.x - 240, top + 80))
	fill(WR.bite_rect(wet), D.WATER)
	var m1 := mite_at(b, wet)
	var gas := WR.bite_of(Vector2i(game.hub.x - 260, top + 80))
	var m2 := mite_at(b, gas)
	var gc := mid(gas)
	for _i in int((D.MITE_DROWN_S - 1.0) * 60):
		game.sim.set_cell(gc.x, gc.y, D.FUMES)
		game.run_ticks(1)
	var alive: bool = b.mites.has(m1) and b.mites.has(m2)
	for _i in 150:
		game.sim.set_cell(gc.x, gc.y, D.FUMES)
		game.run_ticks(1)
	check(alive and not b.mites.has(m1), "a mite under water drowns after %d s" % int(D.MITE_DROWN_S))
	check(not b.mites.has(m2), "one in fumes chokes after %d s" % int(D.MITE_CHOKE_S))
