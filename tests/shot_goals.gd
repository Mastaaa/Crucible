extends SceneTree
## Screenshot of the goal panel mid-run on seed 7, with the Research tab open.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_goals.gd -- --out=/path/prefix

var game: Node
var f := 0
var out := "/tmp/goals"


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
		game.deepest = 3300
		game.goals["step"] = 2
		game.run_ticks(60)
		game.title.visible = false
		game.hud.visible = true
	elif f == 6:
		root.get_viewport().get_texture().get_image().save_png(out + "_panel.png")
		game.hud.toggle_research()
	elif f == 10:
		root.get_viewport().get_texture().get_image().save_png(out + "_research.png")
		return true
	return false
