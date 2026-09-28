extends SceneTree
## Screenshot of the F1 help panel.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_help.gd -- --out=/path/help.png

var game: Node
var f := 0
var out := "/tmp/help.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		game.new_game(7)
		game.hud.toggle_help()
	if f == 8 and OS.get_cmdline_user_args().has("--end"):
		# scroll_to_end: the bottom of the help text
		for n in game.hud.help_panel.find_children("*", "ScrollContainer", true, false):
			n.scroll_vertical = 100000
	if f == 12:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
