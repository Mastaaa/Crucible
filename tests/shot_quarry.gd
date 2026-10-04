extends SceneTree
## Screenshots of the starter quarry: the rig docked under its Funnel and Winch beside the
## Hub, then a few seconds into the first descent, with the hover readout on the Tank.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_quarry.gd -- --out=/path/quarry

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
var game: Node
var f := 0
var out := "/tmp/quarry"
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
		game.drill.enabled = false
		game.stock[D.R_POWER] = 90.0
		MC.ensure_defs()
		MC.place(game, "cutter", Vector2i(X0, SURFACE - 16), 0)
		MC.place(game, "tank", Vector2i(X0, SURFACE - 46), 0)
		MC.place(game, "funnel", Vector2i(X0, SURFACE - 60), 0)
		MC.place(game, "winch", Vector2i(X0 + 14, SURFACE - 64), 0)
		MC.place(game, "windmill", Vector2i(X0 + 32, SURFACE - 36), 0)
		game.run_ticks(60 * 30)
		game._refresh_vision()
		game.paused = true
		game.set_zoom(game.zoom_max * 0.5)
		game._center_on(SURFACE + 25.0, true, float(X0 + 20))
	if f > 2 and f < 12:
		game.hover = Vector2i(X0 + 15, SURFACE - 63)
		game.mouse_screen = game.to_screen(Vector2(game.hover))
	if f == 12:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
