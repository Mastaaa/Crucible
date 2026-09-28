extends SceneTree
## Screenshots of Phase 5 chemistry on seed 7, in a cave under the Hub:
##   fire:   a coal seam alight under a line of Conduits, links wearing and breaking
##   blast:  debris in the air a moment after a blast in stone, glimmer and coal
##   sulfur: a burning sulfur crust, its fumes pooling round Conduits on the floor
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_chemistry.gd -- --scene=fire --out=/path/prefix

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var out := "/tmp/chem"
var scene := "fire"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--scene="):
			scene = a.substr(8)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func build(type: int, r: Rect2i, dir := 0) -> Object:
	var why: String = game.check_place(type, r)
	if why != "":
		print("can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		return null
	var b = game.place(type, r, dir)
	for _i in 900:
		if b.built:
			break
		game.run_ticks(1)
	game.run_ticks(2)
	return b


## A shaft from the Hub down into a cave, with Conduits along its ceiling.
func cave_with_line() -> Array:
	fill(Rect2i(140, 40, 6, 20), D.AIR)
	fill(Rect2i(100, 60, 91, 30), D.AIR)
	var out_list: Array = []
	for r: Rect2i in [Rect2i(136, 38, 2, 2), Rect2i(140, 50, 2, 2), Rect2i(146, 60, 2, 2),
			Rect2i(160, 60, 2, 2), Rect2i(174, 60, 2, 2), Rect2i(132, 60, 2, 2), Rect2i(118, 60, 2, 2)]:
		out_list.append(build(D.B_CONDUIT, r))
	return out_list


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(7)
		game.paused = true
		game.reveal_all = true
		game.stock[D.R_STONE] = 200.0
		match scene:
			"blast":
				_blast_scene()
			"sulfur":
				_sulfur_scene()
			_:
				_fire_scene()
		game._refresh_vision()
		game.mem_due = true
	if f == 12:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false


func _fire_scene() -> void:
	cave_with_line()
	# A coal seam in the cave floor, the cave only 20 rows tall over it.
	fill(Rect2i(100, 80, 91, 12), D.DIRT)
	fill(Rect2i(100, 77, 91, 4), D.COAL)
	game.stock[D.R_STONE] = 0.0
	for x in range(104, 188, 9):
		game.sim.ignite(x, 77)
	game.run_ticks(60 * 25)
	print("burning %d, flames %d, smoke %d, broken links %d, worn %d" % [game.sim.count_burning(),
			game.sim.count(D.FIRE), game.sim.count(D.SMOKE), game.broken_links.size(), game.link_hp.size()])
	game.set_zoom(game.zoom_max - 1)
	game._center_on(72.0, true, 146.0)


func _blast_scene() -> void:
	cave_with_line()
	fill(Rect2i(100, 70, 91, 20), D.STONE)
	fill(Rect2i(100, 76, 91, 3), D.GLIMMER)
	fill(Rect2i(100, 83, 91, 3), D.COAL)
	game.run_ticks(30)
	game.blast(Vector2i(128, 73), 8.0, 6)
	game.blast(Vector2i(165, 72), 6.0, 6)
	game.run_ticks(7)
	print("particles in the air: %d" % game.sim.particle_count())
	game.set_zoom(game.zoom_max - 1)
	game._center_on(74.0, true, 146.0)


func _sulfur_scene() -> void:
	cave_with_line()
	fill(Rect2i(100, 80, 91, 12), D.DIRT)
	fill(Rect2i(150, 56, 36, 4), D.SULFUR)
	for x in range(152, 184, 5):
		game.sim.ignite(x, 59)
	game.run_ticks(60 * 12)
	print("fumes %d, burning %d" % [game.sim.count(D.FUMES), game.sim.count_burning()])
	game.set_zoom(game.zoom_max - 1)
	game._center_on(72.0, true, 146.0)
