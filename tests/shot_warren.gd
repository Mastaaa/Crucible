extends SceneTree
## Screenshot of a Warren on seed 7: one left of the Hub, selected, its mites
## tunnelling toward a marker down and to the left, with the chamber, the line to
## the marker and the circle they'll dig there outlined.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_warren.gd -- --out=/path/warren

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var out := "/tmp/warren"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func build(type: int, r: Rect2i, dir := 0) -> Object:
	var why: String = game.check_place(type, r)
	if why != "":
		print("can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		return null
	var b = game.place(type, r, dir)
	for _i in 900:
		if b.built:
			break
		game.stock[D.R_POWER] = 100.0
		game.run_ticks(1)
	return b


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(7)
		game.paused = true
		game.drill.enabled = false
		game.stock[D.R_STONE] = 300.0
		game.researched["warren"] = true
		game._refresh_unlocks()
		var hub = game.hub
		var w = build(D.B_WARREN, game.snap_place(D.B_WARREN, Vector2i(hub.x - 10, hub.y + hub.h - 3), false), 0)
		game.set_warren_marker(w, Vector2i(w.x - 14, w.y + w.h + 12))
		for _i in 110 * 4:
			game.stock[D.R_POWER] = 100.0
			game.run_ticks(15)
		game.selected = w
		game._refresh_vision()
		game.mem_due = true
		game.set_zoom(game.zoom_max)
		game._center_on(float(w.y + 10), true, float(w.x - 5))
		game.banner_time = 0.0
		print("warren at %s, %d mites, dug %d, %s" % [Vector2i(w.x, w.y), w.mites.size(), w.cells_dug, w.stage])
	if f == 12:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
