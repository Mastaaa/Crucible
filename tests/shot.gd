extends SceneTree
## Renders the game for a few frames and saves screenshots.
## godot --path . --script tests/shot.gd -- --seed=123 --out=/path/prefix --frames=40 [--y=500] [--reveal] [--zoom=3] [--ticks=0]

var frames := 0
var game: Node
var out := "/tmp/shot"
var target := 40
var cam := -1.0
var reveal := false
var zoom := -1
var pre_ticks := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--frames="): target = int(a.substr(9))
		elif a.begins_with("--y="): cam = float(a.substr(4))
		elif a == "--reveal": reveal = true
		elif a.begins_with("--zoom="): zoom = int(a.substr(7))
		elif a.begins_with("--ticks="): pre_ticks = int(a.substr(8))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		if zoom > 0: game.set_zoom(zoom)
		if reveal: game.reveal_all = true
		if cam >= 0.0:
			game._center_on(cam, true)
		if pre_ticks > 0: game.run_ticks(pre_ticks)
	if frames == target:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
