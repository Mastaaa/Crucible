extends SceneTree
## How much rigid bodies cost: N dirt slabs dropped at once into a bedrock room on
## seed 7, the sim's step timed while they fall, tumble and break up.
## Run: godot --headless --path . --script tests/bench_bodies.gd [-- --n=100]

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var n := 100


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func _process(_d: float) -> bool:
	f += 1
	if f != 2:
		return false
	game.new_game(7)
	game.paused = true
	game.drill.enabled = false
	var room := Rect2i(40, 1000, 688, 1400)
	fill(room.grow(20), D.BEDROCK)
	fill(room, D.AIR)
	game.run_ticks(30)
	var t0 := Time.get_ticks_usec()
	for _i in 60:
		game.sim.step()
	var idle := (Time.get_ticks_usec() - t0) / 60000.0
	for k in n:
		var x := 60 + (k % 10) * 66
		var y := 1020 + floori(k / 10.0) * 40
		fill(Rect2i(x, y, 50, 16), D.DIRT)
		game.sim.make_body(x, y, 50, 16, 0.0, 0.0, (k % 7 - 3) * 0.3)
	var worst := 0.0
	var total := 0.0
	var ticks := 0
	var most := 0
	while game.sim.body_count() > 0 and ticks < 1200:
		var t := Time.get_ticks_usec()
		game.sim.step()
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		most = maxi(most, game.sim.body_count())
		ticks += 1
	print("%d slabs (up to %d moving at once): step %.2f ms a tick on average over %d ticks, worst %.2f; %.2f ms with none" % [n, most, total / ticks, ticks, worst, idle])
	print("made %d shattered %d settled %d" % [game.sim.get_bodies_made(), game.sim.get_bodies_shattered(), game.sim.get_bodies_settled()])
	return true
