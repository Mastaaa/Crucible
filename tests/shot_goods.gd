extends SceneTree
## Screenshot of the goods terminal with a few goods banked, on seed 7.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_goods.gd -- --out=/path/prefix

var game: Node
var f := 0
var out := "/tmp/goods"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(7)
		game.paused = true
		game.goods = {35: 4.5, 39: 12.0, 40: 0.7, 44: 2.25}
		game.run_ticks(60)
		game.title.visible = false
		game.hud.visible = true
	elif f == 6:
		root.get_viewport().get_texture().get_image().save_png(out + "_panel.png")
		return true
	return false
