extends SceneTree
## Screenshot of two Tanks with their interiors drawn: one with sand, water and a pour of lava, one empty-ish,
## the first turned a quarter.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_interior.gd -- --out=/path/interior

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
var game: Node
var f := 0
var out := "/tmp/interior"
const X0 := 290
const SURFACE := 200


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.title.visible = false
		game.new_game(7)
		game.reveal_all = true
		MC.ensure_defs()
		var a := MC.place(game, "tank", Vector2i(X0 - 90, SURFACE - 34), 0)
		var b := MC.place(game, "tank", Vector2i(X0 - 50, SURFACE - 34), 0)
		var c := MC.place(game, "tank", Vector2i(X0 - 10, SURFACE - 34), 1)
		MC.add_contents(game, a, 31, 300)
		MC.add_contents(game, a, 9, 250)
		MC.add_contents(game, b, 9, 120)
		MC.add_contents(game, b, 10, 40)
		MC.add_contents(game, c, 31, 200)
		MC.add_contents(game, c, 9, 150)
		game.run_ticks(60 * 6)
		game.paused = true
		game.set_zoom(game.zoom_max * 0.5)
		game._center_on(SURFACE - 18.0, true, float(X0 - 40))
	if f == 8:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
