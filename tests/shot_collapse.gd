extends SceneTree
## Screenshot of collapse on seed 7, in a block of dirt left of the Hub: a room
## too wide for dirt that has caved into an arch over its own rubble, one held up
## by an upright Strut (selected, with the rock its ends hold ringed), one with a
## flat Strut under its ceiling, and a Strut's ghost spanning a fourth.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_collapse.gd -- --out=/path/collapse

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var out := "/tmp/collapse"


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


func lamp(x: int, y: int) -> void:
	var l = game.place(D.B_LAMP, Rect2i(x, y, 2, 2))
	game._complete(l)
	l.power = D.POWER_RESERVE


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(7)
		game.paused = true
		game.drill.enabled = false
		game.reveal_all = true
		game.stock[D.R_STONE] = 300.0
		game.researched["strut"] = true
		game._refresh_unlocks()
		fill(Rect2i(74, 42, 50, 34), D.DIRT)
		fill(Rect2i(80, 50, 17, 6), D.AIR)       # too wide: it caves in
		fill(Rect2i(103, 50, 14, 6), D.AIR)      # an upright Strut splits it
		fill(Rect2i(80, 62, 12, 5), D.AIR)       # a flat Strut under its roof
		fill(Rect2i(100, 63, 7, 4), D.AIR)       # the ghost goes here
		lamp(87, 54)
		lamp(105, 54)
		lamp(81, 65)
		lamp(101, 65)
		var up = game.place_strut(game.strut_rect(Vector2i(110, 52), false))
		game.place_strut(game.strut_rect(Vector2i(85, 62), true))
		for _i in 12 * 4:
			game.stock[D.R_POWER] = 100.0
			game.run_ticks(15)
		game.selected = up
		game.tool_type = D.B_STRUT
		game.tool_horizontal = true
		game._refresh_vision()
		game.mem_due = true
		game.set_zoom(game.zoom_max)
		game._center_on(58.0, true, 98.0)
		game.banner_time = 0.0
		print("caved %d; strut %s" % [game.sim.get_caved(), up.rect()])
	if f >= 3 and f < 12:
		game.hover = Vector2i(104, 63)
		game.mouse_screen = game.to_screen(Vector2(104.5, 63.5))
	if f == 12:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
