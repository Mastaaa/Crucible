extends SceneTree
## Screenshot of the power pieces in play on seed 7: a Waterwheel under a spring,
## a Cache and Drill at the foot of a shaft, a Lamp, and surface Drills short of power.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_power.gd -- --out=/path/prefix

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var out := "/tmp/power"
var sel := "cache"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--select="):
			sel = a.substr(9)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func carve(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, D.AIR)


func build(type: int, r: Rect2i, dir := 0) -> Object:
	var why: String = game.check_place(type, r)
	if why != "":
		print("can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		return null
	var b = game.place(type, r, dir)
	for _i in 900:
		if b.built:
			break
		game.run_ticks(1)
	game.run_ticks(2)
	return b


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(7)
		game.paused = true
		game.reveal_all = true
		game.stock[D.R_STONE] = 200.0
		carve(Rect2i(110, 40, 10, 80))
		carve(Rect2i(150, 40, 11, 60))
		build(D.B_CONDUIT, Rect2i(120, 38, 2, 2))
		build(D.B_CONDUIT, Rect2i(118, 50, 2, 2))
		var wheel = build(D.B_WATERWHEEL, Rect2i(110, 50, 3, 5))
		game.info["springs"].append(Vector2i(111, 44))
		build(D.B_CONDUIT, Rect2i(140, 38, 2, 2))
		for y in [46, 59, 72, 85, 97]:
			build(D.B_CONDUIT, Rect2i(150, y, 2, 2))
		var cache = build(D.B_CACHE, Rect2i(153, 97, 3, 3))
		build(D.B_LAMP, Rect2i(159, 72, 2, 2))
		game.run_ticks(60 * 20)
		var drill = build(D.B_DRILL, Rect2i(157, 97, 3, 3))
		build(D.B_DRILL, Rect2i(136, 37, 3, 3))
		build(D.B_DRILL, Rect2i(143, 37, 3, 3))
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(150)
		game.reveal_all = false
		game._refresh_vision()
		game.mem_due = true
		match sel:
			"wheel":
				game.selected = wheel
			"drill":
				game.selected = drill
			_:
				game.selected = cache
		game._center_on(72.0, true, 135.0)
	if f == 12:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
