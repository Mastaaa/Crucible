extends SceneTree
## Phase-8c rigid bodies on seed 7, in rooms lined with bedrock away from the Hub:
##  A. a dirt slab dropped from high shatters into loose dirt; dropped a short way it
##     lands whole and turns back into ground; hanging over an edge it tips off
##  B. a dirt ceiling 400 wide caves in as pieces, which break up on the floor
##  C. a slab dropped into a pool sinks slowly and lands whole; the water stays
##  D. a blast shoves a body
##  E. crushing: a heavy slab wrecks the Conduit it lands on, a pebble barely marks
##     one; a slab falling through a link wears it; mites can't live in a body
##  F. a building falling far is hurt, a short way or into water it isn't
##  G. Thumper collisions: thrown hard into a wall or up into a ceiling it's hurt,
##     launched at a blast's speed it isn't
## Run: godot --headless --path . --script tests/scenario_bodies.gd

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
		if game.sim.get_script() != null:
			print("  (the GDScript sim has no bodies: nothing to check)")
			print("FAILURES: 0")
			return true
		scenario_a()
		scenario_b()
		scenario_c()
		scenario_d()
		scenario_e()
		scenario_f()
		scenario_g()
		print("FAILURES: %d" % fails)
		return true
	return false


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	game.drill.enabled = false


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


## An open room walled, floored and roofed with 20 cells of bedrock (never gives way).
func arena(r: Rect2i) -> void:
	fill(r.grow(20), D.BEDROCK)
	fill(r, D.AIR)


## Fill `r` with `m` and make it a body; its id.
func slab(r: Rect2i, m: int, v := Vector2.ZERO) -> int:
	fill(r, m)
	return game.sim.make_body(r.position.x, r.position.y, r.size.x, r.size.y, v.x, v.y, 0.0)


## Bodies whose box overlaps `r` (the seed's own caves shed pieces elsewhere).
func bodies_in(r: Rect2i) -> int:
	var bl: PackedInt32Array = game.sim.get_bodies()
	var n := 0
	for k in range(0, bl.size(), 7):
		if Rect2i(bl[k + 1], bl[k + 2], bl[k + 3] - bl[k + 1] + 1, bl[k + 4] - bl[k + 2] + 1).intersects(r):
			n += 1
	return n


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


## Place a building by hand as built; the anchoring scan picks it up.
func put_built(type: int, r: Rect2i) -> Object:
	var b = game.place(type, r)
	b.built = true
	game.scan_dirty = true
	game.net_dirty = true
	return b


func scenario_a() -> void:
	print("A. drops")
	fresh()
	var room := Rect2i(200, 1000, 300, 300)
	arena(room)
	slab(Rect2i(220, 1010, 60, 16), D.DIRT)
	secs(3.0)
	var loose := count(room, D.LOOSE_DIRT)
	print("  from 270 up: dirt left whole %d, loose dirt on the floor %d / 960" % [count(room, D.DIRT), loose])
	check(count(room, D.DIRT) == 0 and loose >= 900, "a slab dropped from high shatters into loose dirt")
	check(bodies_in(room) == 0, "and nothing's left moving")

	fresh()
	arena(room)
	slab(Rect2i(300, 1276, 60, 16), D.DIRT)
	secs(2.0)
	var dirt := count(room, D.DIRT)
	print("  from 8 up: dirt %d / 960, all of it on the floor under where it was: %s" % [dirt, count(Rect2i(300, 1284, 60, 16), D.DIRT) == 960])
	check(bodies_in(room) == 0 and count(room, D.LOOSE_DIRT) == 0 and count(Rect2i(300, 1284, 60, 16), D.DIRT) == 960,
			"a short drop lands whole and turns back into ground where it lands")

	fresh()
	arena(room)
	fill(Rect2i(300, 1150, 60, 150), D.BEDROCK)     # a pillar off the floor
	var id := slab(Rect2i(325, 1136, 80, 12), D.CLAY)  # centre of mass 5 past its edge
	var turned := 0.0
	for _i in 90:
		game.run_ticks(1)
		var st: PackedFloat32Array = game.sim.body_state(id)
		if st.size() > 0:
			turned = maxf(turned, absf(st[2]))
	var on_top := count(Rect2i(300, 1100, 60, 50), D.CLAY)
	print("  over an edge: turned %.2f rad, clay left on the pillar %d" % [turned, on_top])
	check(turned > 0.3 and on_top == 0, "a slab hanging over an edge tips over and falls off")


func scenario_b() -> void:
	print("B. a ceiling breaking up")
	fresh()
	var x0 := 184
	var y0 := 1000
	fill(Rect2i(120, 900, 528, 300), D.DIRT)
	fill(Rect2i(120, 1200, 528, 40), D.BEDROCK)
	var room := Rect2i(x0, y0, 400, 200)
	fill(room, D.AIR)
	var made0: int = game.sim.get_bodies_made()
	var sh0: int = game.sim.get_bodies_shattered()
	var most := 0
	for _i in 40:
		secs(0.5)
		most = maxi(most, bodies_in(room.grow(20)))
	var made: int = game.sim.get_bodies_made() - made0
	var loose := count(room, D.LOOSE_DIRT)
	var mid := y0
	while mid > y0 - 100 and not D.is_solid(game.sim.get_cell(x0 + 200, mid - 1)):
		mid -= 1
	print("  20 s: %d pieces broke off (map-wide), %d shattered, up to %d falling in the room at once; %d loose dirt in it; the middle rose %d rows" % [made,
			game.sim.get_bodies_shattered() - sh0, most, loose, y0 - mid])
	check(most >= 2, "a ceiling 400 wide in dirt comes down in pieces")
	check(loose >= 20 * S * S and y0 - mid >= S, "which break up on the floor as the arch rises")


func scenario_c() -> void:
	print("C. into water")
	fresh()
	var room := Rect2i(250, 2000, 200, 300)
	arena(room)
	fill(Rect2i(250, 2150, 200, 150), D.WATER)
	var water := count(room, D.WATER)
	var id := slab(Rect2i(320, 2010, 60, 16), D.DIRT)
	var fastest_wet := 0.0
	for _i in 300:
		game.run_ticks(1)
		var st: PackedFloat32Array = game.sim.body_state(id)
		if st.size() > 0 and st[1] > 2175:
			fastest_wet = maxf(fastest_wet, st[4])
	secs(3.0)
	var after := count(room, D.WATER)
	print("  sinking at up to %.0f cells/s under the surface; on the bottom: dirt %d / 960, loose %d; water %d -> %d" % [fastest_wet,
			count(Rect2i(250, 2260, 200, 40), D.DIRT), count(room, D.LOOSE_DIRT), water, after])
	check(fastest_wet > 0.0 and fastest_wet <= 110.0, "it sinks slowly through the pool")
	check(bodies_in(room) == 0 and count(Rect2i(250, 2260, 200, 40), D.DIRT) == 960 and count(room, D.LOOSE_DIRT) == 0,
			"and lands whole on the bottom")
	check(absi(after - water) * 50 <= water, "the water it pushed aside is still there")


func scenario_d() -> void:
	print("D. a blast")
	fresh()
	var room := Rect2i(200, 2600, 300, 300)
	arena(room)
	var id := slab(Rect2i(330, 2700, 40, 12), D.STONE)
	game.run_ticks(2)
	var st: PackedFloat32Array = game.sim.body_state(id)
	game.blast(Vector2i(320, int(st[1])), 60.0, 4)    # 4 doesn't beat stone: it shoves, not breaks
	game.run_ticks(1)
	st = game.sim.body_state(id)
	print("  shoved from the left: vx %.0f cells/s" % st[3])
	check(st.size() > 0 and st[3] > 60.0, "a blast beside a falling slab shoves it away")


func scenario_e() -> void:
	print("E. crushing")
	fresh()
	var room := Rect2i(200, 3000, 300, 300)
	arena(room)
	var big = put_built(D.B_CONDUIT, Rect2i(260, 3280, 2 * S, 2 * S))
	var small = put_built(D.B_CONDUIT, Rect2i(420, 3280, 2 * S, 2 * S))
	game.run_ticks(6)
	slab(Rect2i(230, 3100, 80, 20), D.STONE)
	slab(Rect2i(428, 3100, 4, 4), D.STONE)
	secs(2.0)
	print("  Conduit under a 1600-cell slab: dead=%s; under a 16-cell pebble: %.0f / %.0f HP" % [big.dead, small.hp, small.max_hp])
	check(big.dead, "a heavy slab dropped on a Conduit wrecks it")
	check(not small.dead and small.hp < small.max_hp and small.hp > small.max_hp * 0.8, "a pebble barely marks one")

	# A link: the Hub's own Conduit, and a slab dropped through the line between them.
	fresh()
	var c = game.place(D.B_CONDUIT, Rect2i(game.hub.x - 12 * S, game.hub.y + game.hub.h - 2 * S, 2 * S, 2 * S))
	c.built = true
	game.net_dirty = true
	game.scan_dirty = true
	game.run_ticks(6)
	var mid: Vector2 = (c.center() + game.hub.center()) * 0.5
	var before: float = game.link_health(c, game.hub)
	slab(Rect2i(int(mid.x) - 20, int(mid.y) - 90, 40, 12), D.STONE)
	secs(1.5)
	var after: float = game.link_health(c, game.hub)
	print("  link to %s: %.2f -> %.2f (Hub %s, Conduit %s)" % [c.link.title() if c.link else "nothing", before, after, game.hub.rect(), c.rect()])
	check(c.link == game.hub and after < before, "a slab falling through a link wears it")

	fresh()
	arena(room)
	var id := slab(Rect2i(300, 3100, 40, 12), D.STONE)
	var st: PackedFloat32Array = game.sim.body_state(id)
	var mt := WR.new_mite(WR.bite_of(Vector2i(int(st[0]), int(st[1]))))
	check(WR._hazards(game, mt) == "crushed", "a mite where a body is is crushed")


func scenario_f() -> void:
	print("F. falling buildings")
	fresh()
	var room := Rect2i(200, 3600, 300, 400)
	arena(room)
	var high = put_built(D.B_CONDUIT, Rect2i(240, 3620, 2 * S, 2 * S))
	var low = put_built(D.B_CONDUIT, Rect2i(400, 3960, 2 * S, 2 * S))
	secs(4.0)
	print("  fell %d: %.0f / %.0f HP; fell %d: %.0f HP" % [high.fell, high.hp, high.max_hp, low.fell, low.hp])
	check(not high.falling and high.fell > 300 and high.hp < high.max_hp * 0.5 and not high.dead, "a Conduit falling 360 cells lands hurt")
	check(not low.falling and low.fell > 0 and low.hp == low.max_hp, "one falling a few cells is fine")

	fresh()
	arena(room)
	fill(Rect2i(200, 3850, 300, 150), D.WATER)
	var wet = put_built(D.B_CONDUIT, Rect2i(240, 3620, 2 * S, 2 * S))
	secs(6.0)
	print("  into a pool: fell %d, %.0f / %.0f HP" % [wet.fell, wet.hp, wet.max_hp])
	check(not wet.falling and wet.fell > 300 and wet.hp == wet.max_hp, "one falling into a pool lands soft")


func scenario_g() -> void:
	print("G. Thumper collisions")
	fresh()
	var room := Rect2i(200, 4300, 300, 300)
	arena(room)
	var t = put_built(D.B_THUMPER, Rect2i(420, 4580, 2 * S, 2 * S))
	game.run_ticks(2)
	game.launch(t, 450.0, -100.0)
	secs(1.5)
	print("  thrown at a wall at 450: %.0f / %.0f HP" % [t.hp, t.max_hp])
	check(t.hp < t.max_hp and not t.dead, "thrown hard into a wall it's hurt")

	fresh()
	arena(Rect2i(200, 4300, 300, 60))
	t = put_built(D.B_THUMPER, Rect2i(300, 4340, 2 * S, 2 * S))
	game.run_ticks(2)
	game.launch(t, 0.0, -(D.THUMP_LAUNCH + 2.0 * game.thump_power()))
	secs(1.5)
	var soft: float = t.hp
	game.launch(t, 0.0, -450.0)
	secs(1.5)
	print("  launched into a ceiling 40 up: at a blast's speed %.0f HP, at 450 %.0f HP" % [soft, t.hp])
	check(soft == t.max_hp, "a blast's launch into a low ceiling doesn't hurt it")
	check(t.hp < soft, "a hard one does")
