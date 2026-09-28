extends SceneTree
## Screenshot of the placement ghost snapping: a Drill picked with the cursor
## floating a cell above a cave floor; the ghost sits on the floor, with a faint
## box where the cursor is.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_snap.gd -- --out=/path/snap

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var out := "/tmp/snap"
var cursor := Vector2i(142, 49)


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


func build(type: int, r: Rect2i) -> void:
	var b = game.place(type, r)
	for _i in 900:
		if b.built:
			break
		game.run_ticks(1)
	game.run_ticks(2)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(7)
		game.reveal_all = true
		game.stock[D.R_STONE] = 200.0
		fill(Rect2i(128, 40, 24, 20), D.STONE)
		fill(Rect2i(132, 44, 16, 8), D.AIR)
		build(D.B_CONDUIT, Rect2i(140, 38, 2, 2))
		build(D.B_CONDUIT, Rect2i(136, 50, 2, 2))
		build(D.B_LAMP, Rect2i(132, 46, 2, 2))
		game.run_ticks(30)
		game._refresh_vision()
		game.paused = true
		game.set_zoom(game.zoom_max)
		game._center_on(48.0, true, 140.0)
		game.researched["borer"] = true
		game._refresh_unlocks()
		game.select_tool(D.B_BORER)
		game.banner_time = 0.0
	if f > 2 and f < 12:
		game.mouse_screen = game.to_screen(Vector2(cursor) + Vector2(0.5, 0.5))
		game.hover = cursor
	if f == 12:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size(), " ghost ", game.snap_place(D.B_BORER, cursor, false))
		return true
	return false
