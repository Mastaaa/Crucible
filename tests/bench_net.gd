extends SceneTree
## Network benchmark: a big built network (Conduits, Drills, Hoppers, Caches,
## Lamps) made directly, then timed per tick. Run headless.

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func add(type: int, x: int, y: int) -> Object:
	var s: Vector2i = D.B_SIZES[type]
	for yy in range(y, y + s.y):
		for xx in range(x, x + s.x):
			game.sim.set_cell(xx, yy, D.BUILDING)
	# A floor under it, so it's anchored.
	for xx in range(x, x + s.x):
		if game.sim.get_cell(xx, y + s.y) != D.BUILDING:
			game.sim.set_cell(xx, y + s.y, D.STONE)
	var b = game._make_building(type, Rect2i(x, y, s.x, s.y))
	b.built = true
	return b


func _process(_d: float) -> bool:
	f += 1
	if f != 2:
		return false
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	game.stock[D.R_STONE] = 999.0
	# Twelve columns of Conduits 40 rows apart, 800 rows down, with machines beside
	# them (v2's 12 columns 19 apart, squeezed onto a map that's 3x wider for
	# buildings 10x bigger).
	for col in 12:
		var x := 12 + col * 62
		for y in range(D.GROUND_Y + 60, D.GROUND_Y + 860, 40):
			for yy in range(y - 8, y + 32):
				for xx in range(x - 2, x + 58):
					game.sim.set_cell(xx, yy, D.AIR)
			# A bedrock roof: 60 wide is under what dirt spans, but this bench times
			# the network, not a map's worth of weathering.
			for xx in range(x - 2, x + 58):
				game.sim.set_cell(xx, y - 9, D.BEDROCK)
			add(D.B_CONDUIT, x, y)
			match (floori(y / 40.0) + col) % 6:
				0:
					add(D.B_DRILL, x + 25, y)
				1:
					add(D.B_HOPPER, x + 25, y + 10)
				2:
					add(D.B_LAMP, x + 25, y)
				3:
					if col % 3 == 0:
						add(D.B_CACHE, x + 25, y)
	# Tie the columns together along the top.
	for x in range(20, D.W - 40, 120):
		add(D.B_CONDUIT, x, D.GROUND_Y - 20)
	game.net_dirty = true
	var t0 := Time.get_ticks_usec()
	game._rebuild_network()
	var rebuild_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var connected := 0
	for b in game.buildings:
		if b.connected:
			connected += 1
	print("buildings %d  relays %d  sources %d  connected %d  rebuild %.1f ms" % [game.buildings.size(), game.relays.size(), game.src_list.size(), connected, rebuild_ms])
	var worst := 0.0
	var sum := 0.0
	for t in 3600:
		var a := Time.get_ticks_usec()
		game.run_ticks(1)
		var dt := (Time.get_ticks_usec() - a) / 1000.0
		sum += dt
		if t > 60:
			worst = maxf(worst, dt)
		if t % 300 == 299:
			print("  t=%.0fs  avg %.2f ms/tick  worst %.2f  packets %d  power %.0f  used %.1f/s" % [(t + 1) / 60.0, sum / (t + 1), worst, game.packets.size(), game.total(D.R_POWER), game.power_used])
	return true
