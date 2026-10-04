extends SceneTree
## Screenshots of a ceiling caving in as pieces (phase 8c): a room 400 wide in dirt
## on seed 7, a frame every `--every` ticks.
## xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method gl_compatibility
##   --rendering-driver opengl3 --path . --script tests/shot_bodies.gd -- --out=/tmp/b [--every=20] [--shots=8]

const D = preload("res://scripts/defs.gd")
var game: Node
var out := "/tmp/bodies"
var every := 20
var shots := 8
var frames := 0
var taken := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--every="):
			every = int(a.substr(8))
		elif a.begins_with("--shots="):
			shots = int(a.substr(8))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		game.new_game(7)
		game.paused = true
		game.reveal_all = true
		fill(Rect2i(120, 900, 528, 400), D.DIRT)
		fill(Rect2i(120, 1200, 528, 100), D.STONE)
		fill(Rect2i(184, 1000, 400, 200), D.AIR)
		# A slab hanging over a pillar's edge.
		fill(Rect2i(500, 1120, 40, 80), D.STONE)
		fill(Rect2i(520, 1106, 50, 12), D.CLAY)
		game.sim.make_body(520, 1106, 50, 12, 0.0, 0.0, 0.0)
		game.set_zoom(1.6)
		game._center_on(1100.0, true, 384.0)
	elif frames > 4 and frames % 3 == 0:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s_%02d.png" % [out, taken])
		print("saved %s_%02d.png  tick %d  bodies %d  made %d shattered %d settled %d" % [out, taken, game.sim.get_tick(),
				game.sim.body_count(), game.sim.get_bodies_made(), game.sim.get_bodies_shattered(), game.sim.get_bodies_settled()])
		taken += 1
		if taken >= shots:
			return true
		game.run_ticks(every)
	return false
