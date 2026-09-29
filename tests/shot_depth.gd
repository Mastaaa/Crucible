extends SceneTree
## Screenshots of phase 9 on seed 7: a room cut across the top of the hot rock, water
## boiling on its floor and a Steam Turbine hung in a chimney over it catching the steam.
## xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method gl_compatibility
##   --rendering-driver opengl3 --path . --script tests/shot_depth.gd -- --out=/tmp/d [--every=30] [--shots=4]

const D = preload("res://scripts/defs.gd")
var game: Node
var out := "/tmp/depth"
var every := 30
var shots := 4
var frames := 0
var taken := 0
var turbine = null


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
		game.drill.enabled = false
		game.researched["steam_turbine"] = true
		game._refresh_unlocks()
		fill(Rect2i(540, 2960, 140, 120), D.AIR)     # narrower than stone's span
		fill(Rect2i(590, 2760, 40, 200), D.AIR)      # the chimney
		turbine = game.place(D.B_TURBINE, Rect2i(590, 2920, 40, 40))
		turbine.built = true
		game.scan_dirty = true
		game.net_dirty = true
		fill(Rect2i(540, 3050, 140, 30), D.WATER)
		game.set_zoom(1.6)
		game._center_on(2950.0, true, 560.0)
	elif frames > 4 and frames % 3 == 0:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s_%02d.png" % [out, taken])
		print("saved %s_%02d.png  tick %d  turbine %.2f power/s" % [out, taken, game.sim.get_tick(), turbine.flow])
		taken += 1
		if taken >= shots:
			return true
		fill(Rect2i(540, 3060, 140, 20), D.WATER)
		game.run_ticks(every)
	return false
