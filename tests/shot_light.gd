extends SceneTree
## Screenshot of light and shadow on seed 7: a sunlit shaft from the Hub into a
## cave, a Lamp on the left with a stone pillar throwing a shadow, a lava pool
## glowing on the right, and a stretch lit once by a second Lamp, now switched off
## (explored, shown as last seen).
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_light.gd -- --out=/path/light

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var out := "/tmp/light"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func build(type: int, r: Rect2i) -> Object:
	var why: String = game.check_place(type, r)
	if why != "":
		print("can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		return null
	var b = game.place(type, r)
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
		fill(Rect2i(96, 44, 100, 50), D.STONE)
		fill(Rect2i(140, 40, 4, 22), D.AIR)
		fill(Rect2i(100, 62, 92, 22), D.AIR)
		fill(Rect2i(118, 67, 5, 17), D.STONE)
		fill(Rect2i(172, 80, 20, 4), D.LAVA)
		for r: Rect2i in [Rect2i(136, 38, 2, 2), Rect2i(140, 50, 2, 2), Rect2i(146, 62, 2, 2),
				Rect2i(132, 62, 2, 2), Rect2i(160, 62, 2, 2), Rect2i(119, 62, 2, 2)]:
			build(D.B_CONDUIT, r)
		build(D.B_LAMP, Rect2i(126, 62, 2, 2))
		var far = build(D.B_LAMP, Rect2i(112, 62, 2, 2))
		game.run_ticks(60)
		game._refresh_vision()
		if far != null:
			far.enabled = false
		game.reveal_all = false
		game.run_ticks(30)
		game._refresh_vision()
		game.mem_due = true
		game.set_zoom(game.zoom_max - 1)
		game._center_on(68.0, true, 146.0)
	if f == 12:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
