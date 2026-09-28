extends SceneTree
## Phase-1 smoke test: place a drill and conduits by hand, run, check vision/fog and drilling.
const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(7)
		game.paused = true
		var hub = game.hub
		print("hub ", hub.rect(), " crucible ", game.crucible.rect(), " zoom ", game.zoom, " min ", game.zoom_min, " max ", game.zoom_max)
		var d = game.drill
		print("fixed drill ", d.rect(), " fixed=", d.fixed)
		game.run_ticks(600)
		print("drill built=", d.built, " reach=", d.reach, " bored=", d.cells_bored, " stock=", game.stock)
		var c = game.place(D.B_CONDUIT, Rect2i(d.x, d.y + d.h + 4, 2, 2), 0)
		print("conduit check after: built?", c.built)
		game.run_ticks(600)
		print("conduit built=", c.built, " connected=", c.connected)
		var seen := 0
		for v in game.vis:
			if v != 0: seen += 1
		print("visible blocks ", seen, " known ", game.known.count(255))
	if f == 5 and DisplayServer.get_name() == "headless":
		return true
	if f == 6:
		game._center_on(60.0, true, 128.0)
	if f == 10:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("/home/claude/shots/v2b.png")
		return true
	return false
