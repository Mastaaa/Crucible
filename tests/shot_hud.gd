extends SceneTree
## Screenshot of the HUD after the A3 cut: the Build list (structures and modules), a selected Node's
## panel, the minimap with a module on it, and the research tab with `--research`.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_hud.gd -- --out=/path/hud.png [--research]

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
var game: Node
var f := 0
var out := "/tmp/hud.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		game.title.visible = false
		game.hud.visible = true
		game.new_game(7)
		game.reveal_all = true
		MC.ensure_defs()
		var hub: Rect2i = game.hub.rect()
		for x in range(hub.position.x - 100, hub.position.x):
			for y in range(hub.end.y - 60, hub.end.y):
				game.sim.set_cell(x, y, D.AIR)
		MC.place(game, "lab", Vector2i(hub.position.x - 44, hub.end.y - 30), 0)
		var node = game._make_building(D.B_NODE, Rect2i(hub.position.x - 30, hub.end.y - 20, 20, 20))
		node.built = true
		game.net_dirty = true
		game.run_ticks(120)
		game.selected = node
		if OS.get_cmdline_user_args().has("--research"):
			game.hud.toggle_research()
		game.paused = true
	if f == 14:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
