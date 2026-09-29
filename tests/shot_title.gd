extends SceneTree
## Screenshots of the title screen and the end-of-run panels (phase 10).
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_title.gd -- --out=/tmp/title
## Writes <out>_title.png, <out>_win.png and <out>_loss.png.

var game: Node
var f := 0
var out := "/tmp/title"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 10:
		root.get_texture().get_image().save_png(out + "_title.png")
	if f == 11:
		game.start_run("7")
		game.game_time = 5423.0
		for m in [[40.0, "First Lab built"], [611.0, "Tier 2 open: the first Glimmer mined"],
				[1480.0, "Reached the Stone band (depth 1500)"], [2710.0, "Tier 3 open: the first lava seen"],
				[3390.0, "Reached the Magma band (depth 3000)"], [4705.0, "Reached the Chamber band (depth 4500)"],
				[4750.0, "Tier 4 open: the Crucible in view"], [5012.0, "The Crucible is connected"],
				[5190.0, "The Crucible started charging"], [5423.0, "The Crucible is lit"]]:
			game.milestones.append({"t": m[0], "text": m[1], "major": true})
		game.won = true
		game.hud.show_end()
	if f == 20:
		root.get_texture().get_image().save_png(out + "_win.png")
		game.won = false
		game.stock[0] = 0.0
		while not game.run_lost:
			game.blast(Vector2i(game.hub.center()), 60.0, 10)
	if f == 30:
		root.get_texture().get_image().save_png(out + "_loss.png")
		print("saved ", out, "_*.png")
		return true
	return false
