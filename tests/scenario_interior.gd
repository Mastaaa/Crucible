extends SceneTree
## Machine interiors (a vessel's contents are a sim of their own), on seed 7:
##  A. a Tank has an interior sized from its capacity, empty at first; its counts track the cells
##  B. what goes in settles in layers (sand under water) and comes out the top by count
##  C. a full Tank refuses more, and the cells inside are exactly the units it counts
##  D. reactions run inside (lava on water makes rock) and the counts follow
##  E. a breach leaks the interior out into the world, faster the more casing is gone
##  F. Tank Size research grows the interior and keeps what is in it
##  G. an interior survives a save and a load
##  H. every vessel with the flag has one, a turned Tank's box follows its turned layout
## Run: godot --headless --path . --script tests/scenario_interior.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const MU = preload("res://scripts/machines/mu.gd")
const Save = preload("res://scripts/save.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200     # ground level (dirt from here down)
const SAND := 31
const WATER := 9
const LAVA := 10


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
		scenario_h()
		print("FAILURES: %d" % fails)
		return true
	return false


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func fresh() -> int:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	MC.ensure_defs()
	fill(Rect2i(200, SURFACE - 120, 144, 120), D.AIR)
	fill(Rect2i(200, SURFACE, 144, 160), 6)
	fill(Rect2i(200, SURFACE + 160, 144, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0
	var id := MC.place(game, "tank", Vector2i(300, SURFACE - 30), 0)
	secs(0.3)
	return id


func held(id: int, mat: int) -> int:
	return int(game.modules[id]["contents"].get(mat, 0))


## Cells of `mat` inside the module's interior box, counted from the sim itself.
func inside(id: int, mat: int) -> int:
	var m: Dictionary = game.modules[id]
	var b: Rect2i = m["box"]
	return m["sim"].rect_counts(b.position.x, b.position.y, b.size.x, b.size.y)[mat]


## Mean row of `mat` inside the interior (bigger is lower).
func mean_row(id: int, mat: int) -> float:
	var m: Dictionary = game.modules[id]
	var b: Rect2i = m["box"]
	var cells: PackedByteArray = m["sim"].get_cells()
	var w: int = m["sim"].get_width()
	var sum := 0.0
	var n := 0
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			if cells[y * w + x] == mat:
				sum += y
				n += 1
	return sum / maxf(1.0, n)


func scenario_a() -> void:
	print("A. A Tank has an interior")
	var t := fresh()
	var m: Dictionary = game.modules[t]
	var cap := MU.capacity(m, MC.defs["tank"])
	check(m["sim"] != null, "the Tank has a sim of its own")
	var b: Rect2i = m["box"]
	check(b.size.x == 22 and b.size.x * b.size.y >= cap, "its box is 22 wide and holds the capacity (%d x %d for %d)" % [b.size.x, b.size.y, cap])
	check(MU.stored(m) == 0 and inside(t, SAND) == 0, "it starts empty")
	check(MC.add_contents(game, t, SAND, 50) == 50 and inside(t, SAND) == 50 and held(t, SAND) == 50, "50 Sand goes in as 50 cells and a count of 50")
	var funnel := MC.place(game, "funnel", Vector2i(300, SURFACE - 70), 0)
	check(funnel > 0 and game.modules[funnel]["sim"] == null, "a Funnel has no interior, just a count")


func scenario_b() -> void:
	print("B. Layers, and out by count")
	var t := fresh()
	MC.add_contents(game, t, WATER, 120)
	MC.add_contents(game, t, SAND, 120)
	secs(4.0)
	check(held(t, SAND) == 120 and held(t, WATER) == 120, "nothing is lost while it settles (%d sand, %d water)" % [held(t, SAND), held(t, WATER)])
	check(mean_row(t, SAND) > mean_row(t, WATER), "the Sand lies under the Water (rows %.1f and %.1f)" % [mean_row(t, SAND), mean_row(t, WATER)])
	var took := MU.take(game.modules[t], SAND, 70)
	check(took == 70 and held(t, SAND) == 50 and inside(t, SAND) == 50, "taking 70 Sand leaves 50 in the count and in the sim")
	check(MU.take(game.modules[t], SAND, 500) == 50 and not game.modules[t]["contents"].has(SAND), "asking for more takes what is there")


func scenario_c() -> void:
	print("C. Capacity")
	var t := fresh()
	var m: Dictionary = game.modules[t]
	var cap := MU.capacity(m, MC.defs["tank"])
	var put := MC.add_contents(game, t, SAND, cap + 300)
	check(put == cap and MU.stored(m) == cap, "a full Tank takes %d and refuses the rest (%d)" % [cap, put])
	secs(3.0)
	var cells := 0
	for mat in range(1, 256):
		cells += inside(t, mat)
	check(cells == cap, "and the cells inside are exactly the units it counts (%d)" % cells)
	check(MC.add_contents(game, t, WATER, 10) == 0, "it takes nothing more")


func scenario_d() -> void:
	print("D. Reactions run inside")
	var t := fresh()
	MC.add_contents(game, t, WATER, 60)
	MC.add_contents(game, t, LAVA, 60)
	secs(6.0)
	var kinds := m_kinds(t)
	check(held(t, LAVA) < 60 or held(t, WATER) < 60, "lava and water react (%s)" % str(kinds))
	var total := 0
	for mat: int in game.modules[t]["contents"]:
		total += game.modules[t]["contents"][mat]
	var cells := 0
	for mat in range(1, 256):
		cells += inside(t, mat)
	check(total == cells, "the count follows the cells (%d of %d)" % [total, cells])


func m_kinds(id: int) -> Dictionary:
	return game.modules[id]["contents"].duplicate()


func scenario_e() -> void:
	print("E. A breach leaks it out")
	var t := fresh()
	MC.add_contents(game, t, WATER, 200)
	secs(1.0)
	MC.knock_out(game, t, [Vector2i(0, 15), Vector2i(1, 15)])
	secs(0.5)
	check(game.modules[t]["breach"].x >= 0, "a hole through both layers is a breach")
	var before := MU.stored(game.modules[t])
	secs(5.0)
	var left := MU.stored(game.modules[t])
	check(left < before - 40, "the interior leaks through it (%d to %d)" % [before, left])
	check(inside(t, WATER) == held(t, WATER), "the count still matches the sim (%d)" % inside(t, WATER))
	# A small hole against a gutted wall, side by side.
	var small := fresh()
	var big := MC.place(game, "tank", Vector2i(240, SURFACE - 30), 0)
	secs(0.3)
	MC.add_contents(game, small, SAND, 600)
	MC.add_contents(game, big, SAND, 600)
	secs(1.0)
	MC.knock_out(game, small, [Vector2i(0, 15), Vector2i(1, 15)])
	var wall: Array = [Vector2i(0, 15), Vector2i(1, 15)]
	for y in range(3, 25):
		wall.append(Vector2i(24, y))
		wall.append(Vector2i(25, y))
	MC.knock_out(game, big, wall)
	secs(0.5)
	check(game.modules[small]["breach"].x >= 0 and game.modules[big]["breach"].x >= 0, "both are breached")
	check(game.modules.has(big) and game.modules[big]["integrity"] >= 0.5, "the big one is damaged but not wreckage (%.2f)" % game.modules[big]["integrity"])
	var s0 := MU.stored(game.modules[small])
	var b0 := MU.stored(game.modules[big])
	secs(1.5)
	var lost_small := s0 - MU.stored(game.modules[small])
	var lost_big := b0 - MU.stored(game.modules[big])
	check(lost_small >= 1 and lost_big > lost_small * 5, "a gutted wall pours much faster than a pinhole seeps (%d against %d in 1.5 s)" % [lost_big, lost_small])


func scenario_f() -> void:
	print("F. Tank Size research")
	var t := fresh()
	MC.add_contents(game, t, SAND, 200)
	MC.add_contents(game, t, WATER, 100)
	secs(3.0)
	var rows0: int = game.modules[t]["box"].size.y
	var row_sand := mean_row(t, SAND)
	game.levels["tank_size"] = 2
	secs(0.5)
	var b: Rect2i = game.modules[t]["box"]
	check(b.size.y > rows0, "the box grows with the capacity (%d rows to %d)" % [rows0, b.size.y])
	check(held(t, SAND) == 200 and held(t, WATER) == 100 and inside(t, SAND) == 200 and inside(t, WATER) == 100, "and keeps what was in it")
	secs(2.0)
	check(mean_row(t, WATER) < mean_row(t, SAND), "still in layers after the move (rows %.1f and %.1f; sand was %.1f)" % [mean_row(t, WATER), mean_row(t, SAND), row_sand])


func scenario_g() -> void:
	print("G. Save and load")
	var t := fresh()
	MC.add_contents(game, t, SAND, 150)
	MC.add_contents(game, t, WATER, 90)
	secs(3.0)
	var sum0: int = game.modules[t]["sim"].checksum()
	game.live_run = true
	var headless_was: bool = game.headless
	game.headless = false
	var ok: bool = game.save_run()
	game.headless = headless_was
	game.modules[t]["sim"] = null
	ok = ok and game.continue_run()
	var m: Dictionary = game.modules.get(t, {})
	check(ok and not m.is_empty() and m["sim"] != null, "the Tank and its sim are back after a load")
	if ok and not m.is_empty() and m["sim"] != null:
		check(m["sim"].checksum() == sum0, "the cells are the ones that were saved")
		check(held(t, SAND) == 150 and held(t, WATER) == 90, "and so are the counts (%d sand, %d water)" % [held(t, SAND), held(t, WATER)])
		secs(1.0)
		check(inside(t, SAND) == 150, "it keeps running")
	Save.erase()


func scenario_h() -> void:
	print("H. Other vessels")
	fresh()
	MC.ensure_defs()
	var want := ["press", "macerator", "bus_hopper", "cutter", "laser"]
	var at := {"press": Vector2i(210, SURFACE - 26), "macerator": Vector2i(240, SURFACE - 26), "bus_hopper": Vector2i(270, SURFACE - 30),
			"cutter": Vector2i(210, SURFACE - 70), "laser": Vector2i(250, SURFACE - 70)}
	for d: String in want:
		var id := MC.place(game, d, at[d], 0)
		check(id > 0 and game.modules[id]["sim"] != null, "a %s has an interior" % d)
		if id > 0 and game.modules[id]["sim"] != null:
			var m: Dictionary = game.modules[id]
			var inner: int = int(MC.defs[d]["size"][0]) - 2 * int(MC.defs[d]["wall"])
			check(m["box"].size.x == inner, "its box is as wide as its cavity (%d)" % inner)
	var funnel := MC.place(game, "funnel", Vector2i(300, SURFACE - 70), 0)
	check(funnel > 0 and game.modules[funnel]["sim"] == null, "the Funnel stays a count")
	fresh()
	var t := MC.place(game, "tank", Vector2i(260, SURFACE - 40), 1)
	var lay: Vector2i = MC.F.layout(MC.defs["tank"], 1)["size"]
	check(t > 0 and game.modules[t]["box"].size.x == lay.x - 4, "a Tank placed turned has a box as wide as its turned cavity (%d of %d)" % [game.modules[t]["box"].size.x, lay.x - 4])
