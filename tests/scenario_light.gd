extends SceneTree
## Light and anchoring scenarios (seed 7, by the Hub).
##  Light:
##   A. a sealed cave stays dark by a Conduit; a lit Lamp explores it; switched off,
##      it's remembered but no longer live
##   B. rock casts shadows: a cave behind a 6-cell wall stays dark beside the Lamp
##   C. sunlight falls straight down an open shaft and spills a little way sideways
##   D. lava lights itself: a Conduit sees a lava pool without a Lamp (and Tier 3
##      opens); with the Conduit gone, the explored pool still shows live
##  Anchoring:
##   E. a Conduit whose ledge is dug away falls, lands, and links up again
##   F. one dropped into a pool sinks to the floor, and the water ends up above it
##   G. a row of Bulkheads hangs off a wall by its end; cut that and the row falls
##   H. a Drill boring straight down from the surface rests on the lip of its shaft
##   I. the placement ghost snaps: down onto a floor, out of rock, onto a wall; not
##      when the spot is fine or nothing's near
## Run: godot --headless --path . --script tests/scenario_light.gd

const D = preload("res://scripts/defs.gd")
const SimFactory = preload("res://scripts/sim_factory.gd")

var game: Node
var f := 0
var fails := 0


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		if not SimFactory.native_available():
			print("The C++ sim isn't loaded: these need it.")
			print("FAILURES: 1")
			return true
		scenario_a_b()
		scenario_c()
		scenario_d()
		scenario_e()
		scenario_f()
		scenario_g()
		scenario_h()
		scenario_i()
		print("FAILURES: %d" % fails)
		return true
	return false


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


# --- Helpers --------------------------------------------------------------------------

func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true      # only lets tests place anywhere; the fog maps work as ever


func gfill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func count_in(r: Rect2i, m: int) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if game.sim.get_cell(x, y) == m:
				n += 1
	return n


## A finished building put straight into the world, off the network.
func drop_in(type: int, at: Vector2i) -> Object:
	var s: Vector2i = D.B_SIZES[type]
	gfill(Rect2i(at, s), D.BUILDING)
	var b = game._make_building(type, Rect2i(at, s))
	b.built = true
	game.scan_dirty = true
	return b


## Place through the network and wait (up to 10 s) until it's built.
func build(type: int, r: Rect2i) -> Object:
	var why: String = game.check_place(type, r)
	if why != "":
		print("  !! can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		fails += 1
		return null
	var b = game.place(type, r)
	for _i in 600:
		if b.built:
			break
		game.run_ticks(1)
	game.run_ticks(2)
	return b


## Share (0..1) of the 4x4 blocks inside `r` that `map` marks.
func share(map: PackedByteArray, r: Rect2i) -> float:
	var n := 0
	var on := 0
	for by in range(r.position.y >> 2, (r.end.y - 1 >> 2) + 1):
		for bx in range(r.position.x >> 2, (r.end.x - 1 >> 2) + 1):
			n += 1
			if map[by * 64 + bx] != 0:
				on += 1
	return on / float(maxi(n, 1))


func light_at(x: int, y: int) -> int:
	var lp: PackedByteArray = game.sim.get_light()
	return lp[y * D.W + x]


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


# --- Light ------------------------------------------------------------------------------

func scenario_a_b() -> void:
	print("A. a dark cave, a Lamp, and the Lamp switched off")
	fresh()
	gfill(Rect2i(150, 70, 60, 30), D.STONE)
	var cave_l := Rect2i(154, 80, 16, 8)
	var cave_r := Rect2i(176, 80, 12, 8)
	gfill(cave_l, D.AIR)
	gfill(cave_r, D.AIR)
	var inner_l := cave_l.grow(-1)
	drop_in(D.B_CONDUIT, Vector2i(155, 86))
	game._refresh_vision()
	print("  by a Conduit alone: %.0f%% of the cave explored" % (share(game.known, inner_l) * 100.0))
	check(share(game.known, inner_l) == 0.0, "a Conduit sees nothing in the dark")
	var lamp = drop_in(D.B_LAMP, Vector2i(162, 86))
	lamp.power = D.POWER_RESERVE
	game._refresh_vision()
	print("  with a lit Lamp: %.0f%% explored, %.0f%% live" % [share(game.known, inner_l) * 100.0, share(game.vis, inner_l) * 100.0])
	check(share(game.known, inner_l) == 1.0, "the Lamp lights the cave and it's explored")
	check(share(game.vis, inner_l) == 1.0, "and all of it shows live")
	print("B. a 6-cell wall between the Lamp and the next cave")
	var inner_r := cave_r.grow(-1)
	print("  far cave: %.0f%% explored; light on its near edge %d" % [share(game.known, inner_r) * 100.0, light_at(177, 84)])
	check(share(game.known, inner_r) == 0.0 and light_at(177, 84) == 0, "the wall's shadow keeps it dark, though the Lamp watches that far")
	check(light_at(170, 84) > 0, "the light still reaches the wall's face and a little way in")
	lamp.power = 0.0
	game._refresh_vision()
	var far_end := Rect2i(154, 80, 4, 8)
	print("  Lamp out: far end %.0f%% explored, %.0f%% live" % [share(game.known, far_end) * 100.0, share(game.vis, far_end) * 100.0])
	check(share(game.known, far_end) == 1.0, "switched off, the cave stays explored")
	check(share(game.vis, far_end) == 0.0, "but shows as last seen, not live")


func scenario_c() -> void:
	print("C. sunlight down a shaft")
	fresh()
	gfill(Rect2i(200, 40, 50, 64), D.STONE)
	gfill(Rect2i(210, 40, 3, 60), D.AIR)
	gfill(Rect2i(213, 94, 34, 4), D.AIR)
	game._refresh_vision()
	print("  light 50 down the shaft %d, 4 into the side tunnel %d, 30 in %d" % [light_at(211, 90), light_at(217, 96), light_at(243, 96)])
	check(light_at(211, 90) == 255, "the shaft is sunlit all the way down")
	check(light_at(217, 96) > 0, "light spills a little way into a side tunnel")
	check(light_at(243, 96) == 0, "but not far")


func scenario_d() -> void:
	print("D. lava lights itself")
	fresh()
	gfill(Rect2i(56, 116, 28, 16), D.STONE)
	gfill(Rect2i(60, 120, 20, 8), D.AIR)
	gfill(Rect2i(70, 126, 10, 2), D.LAVA)
	var c = drop_in(D.B_CONDUIT, Vector2i(61, 126))
	check(not game.tiers_open[3], "Tier 3 isn't open yet")
	game._refresh_vision()
	var pool := Rect2i(70, 122, 6, 6)       # the end of it within the Conduit's sight
	print("  over the pool: %.0f%% explored, %.0f%% live" % [share(game.known, pool) * 100.0, share(game.vis, pool) * 100.0])
	check(share(game.known, pool) == 1.0, "a Conduit sees the glowing pool without a Lamp")
	check(game.tiers_open[3], "and the lava opens Tier 3")
	game.demolish(c)
	game._refresh_vision()
	print("  Conduit gone: %.0f%% live" % (share(game.vis, pool) * 100.0))
	check(share(game.vis, pool) == 1.0, "explored and still lit, it shows live with nothing watching")


# --- Anchoring --------------------------------------------------------------------------

## A stone pit beside the Hub: open from the surface down to a floor at row 50,
## and a small stone ledge hanging in it.
func pit() -> void:
	gfill(Rect2i(132, 40, 14, 16), D.STONE)
	gfill(Rect2i(134, 40, 8, 10), D.AIR)
	# A ledge hanging in the middle: bedrock, since stone with nothing of its own
	# kind to hang from comes down now.
	gfill(Rect2i(136, 43, 4, 2), D.BEDROCK)


func fall_until_landed(b, limit_s: float) -> bool:
	var fell := false
	for _i in int(limit_s * 60.0):
		game.run_ticks(1)
		if b.falling:
			fell = true
		elif fell:
			return true
	return false


func scenario_e() -> void:
	print("E. a Conduit loses its ledge")
	fresh()
	pit()
	var c = build(D.B_CONDUIT, Rect2i(137, 41, 2, 2))
	if c == null:
		return
	secs(1.0)
	check(c.connected and not c.falling, "on its ledge it holds, linked to the Hub")
	gfill(Rect2i(136, 43, 4, 2), D.AIR)
	var landed := fall_until_landed(c, 4.0)
	secs(0.5)
	print("  landed %s at row %d after %d cells; connected %s" % [landed, c.y, c.fell, c.connected])
	check(landed and c.y == 48, "it fell and landed on the pit floor")
	check(c.connected, "and linked up again where it landed")
	check(count_in(Rect2i(134, 40, 8, 10), D.BUILDING) == 4, "its cells moved with it, none left behind")


func scenario_f() -> void:
	print("F. a Conduit falls into a pool")
	fresh()
	pit()
	gfill(Rect2i(134, 46, 8, 4), D.WATER)
	var water0 := count_in(Rect2i(132, 30, 14, 26), D.WATER)
	var c = build(D.B_CONDUIT, Rect2i(137, 41, 2, 2))
	if c == null:
		return
	gfill(Rect2i(136, 43, 4, 2), D.AIR)
	var landed := fall_until_landed(c, 4.0)
	secs(2.0)
	var water1 := count_in(Rect2i(132, 30, 14, 26), D.WATER)
	print("  landed %s at row %d; water %d -> %d" % [landed, c.y, water0, water1])
	check(landed and c.y == 48, "it sank to the floor")
	check(water1 == water0, "no water lost or made on the way down")
	check(count_in(Rect2i(137, 46, 2, 2), D.WATER) > 0 or count_in(Rect2i(134, 44, 8, 4), D.WATER) > 0, "the water sits above it now")


func scenario_g() -> void:
	print("G. a row of Bulkheads off a wall")
	fresh()
	gfill(Rect2i(132, 40, 16, 16), D.STONE)
	gfill(Rect2i(134, 40, 12, 10), D.AIR)
	var row: Array = []
	for k in 4:
		row.append(drop_in(D.B_BULKHEAD, Vector2i(134 + k * 2, 41)))
	secs(1.0)
	var any := false
	for b in row:
		any = any or b.falling or b.y != 41
	check(not any, "held up by the end one touching the wall")
	gfill(Rect2i(133, 40, 1, 4), D.AIR)
	secs(2.0)
	var down := 0
	for b in row:
		if not b.falling and b.y == 48:
			down += 1
	print("  %d of 4 on the floor" % down)
	check(down == 4, "cut from the wall, the whole row falls to the floor")


func scenario_h() -> void:
	print("H. a Drill rests on the lip of its own shaft")
	fresh()
	gfill(Rect2i(132, 40, 10, 30), D.STONE)
	var dr = build(D.B_DRILL, Rect2i(135, 37, 3, 3))
	if dr == null:
		return
	for _i in 40:
		secs(1.0)
		if dr.reach >= D.DRILL_REACH:
			break
	print("  channel %d / %d, drill at row %d" % [dr.reach, D.DRILL_REACH, dr.y])
	check(dr.reach >= 6, "it bored a channel")
	check(dr.y == 37 and not dr.falling, "and stayed where it was put")


func scenario_i() -> void:
	print("I. the placement ghost snaps to surfaces")
	fresh()
	# A stone room beside the Hub: rows 44-51, floor at row 52, walls at columns 131 and 147.
	gfill(Rect2i(128, 40, 24, 20), D.STONE)
	gfill(Rect2i(132, 44, 15, 8), D.AIR)   # 15 wide: stone spans 15
	build(D.B_CONDUIT, Rect2i(140, 38, 2, 2))
	build(D.B_CONDUIT, Rect2i(136, 50, 2, 2))
	var drill_r: Rect2i = game.snap_place(D.B_DRILL, Vector2i(142, 49), false)
	print("  Drill, cursor 1 above the floor: %s" % drill_r)
	check(drill_r == Rect2i(141, 49, 3, 3), "a floating Drill drops onto the floor below it")
	var in_rock: Rect2i = game.snap_place(D.B_DRILL, Vector2i(142, 53), false)
	print("  Drill, cursor in the floor: %s" % in_rock)
	check(in_rock == Rect2i(141, 49, 3, 3), "one poking into the floor comes up onto it")
	var wall: Rect2i = game.snap_place(D.B_LAMP, Vector2i(134, 47), false)
	print("  Lamp, cursor 1 off the wall: %s" % wall)
	check(wall.position.x == 132 and game.check_place(D.B_LAMP, wall) == "", "a Lamp near a wall goes onto the wall")
	var fine: Rect2i = game.snap_place(D.B_CONDUIT, Vector2i(145, 51), false)
	check(fine == game.footprint(D.B_CONDUIT, Vector2i(145, 51), false), "a spot that's already fine stays put")
	var sky: Rect2i = game.snap_place(D.B_CONDUIT, Vector2i(200, 20), false)
	check(sky == game.footprint(D.B_CONDUIT, Vector2i(200, 20), false) and game.check_place(D.B_CONDUIT, sky) == "Must touch rock",
			"high in the sky, nothing near enough: it stays under the cursor and says why")
	var bh: Rect2i = game.snap_place(D.B_BULKHEAD, Vector2i(142, 49), false)
	check(bh == game.footprint(D.B_BULKHEAD, Vector2i(142, 49), false), "Bulkheads never snap")
