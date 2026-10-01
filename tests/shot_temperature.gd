extends SceneTree
## Screenshots of A1: the lab bench (lava against stone, a pool of water, a coal
## seam heated at one end) plain and in the temperature view, then the fog on seed 7
## (black where nothing has been seen, dimmed where it has but isn't lit).
## xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method gl_compatibility
##   --rendering-driver opengl3 --path . --script tests/shot_temperature.gd -- --out=/tmp/t

const D = preload("res://scripts/defs.gd")
const WorldGen = preload("res://scripts/worldgen.gd")
var game: Node
var out := "/tmp/temperature"
var frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [out, name])
	print("saved %s_%s.png" % [out, name])


func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		if game.title != null:
			game.title.visible = false
		game.start_bench()
		var floor_y: int = WorldGen.BENCH_FLOOR
		fill(Rect2i(200, floor_y - 60, 120, 60), D.STONE)
		fill(Rect2i(320, floor_y - 40, 60, 40), D.LAVA)
		fill(Rect2i(380, floor_y - 60, 40, 60), D.STONE)
		fill(Rect2i(420, floor_y - 30, 120, 30), D.WATER)
		fill(Rect2i(560, floor_y - 20, 120, 20), D.COAL)
		game.sim.heat_rect(660, floor_y - 20, 20, 20, 800)
		game.run_ticks(60 * 20)
		game.set_zoom(1.4)
		game._center_on(floor_y - 200.0, true, D.W * 0.5)
	elif frames == 6:
		shot("bench")
		game.temp_view = true
	elif frames == 10:
		shot("bench_heat")
		game.temp_view = false
		game.new_game(7)
		game.paused = true
		game.run_ticks(60)
		game.set_zoom(1.0)
		game._center_on(D.GROUND_Y - 40.0, true, D.W * 0.5)
	elif frames == 16:
		shot("fog")
		return true
	return false
