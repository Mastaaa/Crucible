extends SceneTree
## Screenshots of the biome view (A6): the whole width at each depth asked for, fog off, biomes outlined and named.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_biomes.gd -- --seed=7 --depths=200,1000,2200,3500 --out=/path/biomes
## writes /path/biomes_<depth>.png

var game: Node
var f := 0
var seed_value := 7
var depths: Array = [200, 1000, 2200, 3500]
var out := "/tmp/biomes"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--depths="):
			depths = Array(a.substr(9).split(","))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.title.visible = false
		game.new_game(seed_value)
		game.reveal_all = true
		game.biome_view = true
		game.paused = true
		game.set_zoom(game.zoom_min)
	var k := int((f - 4) / 6.0)
	if f >= 4 and (f - 4) % 6 == 0 and k < depths.size():
		game._center_on(float(depths[k]), true, game.D.W * 0.5)
	var j := int((f - 8) / 6.0)
	if f >= 8 and (f - 8) % 6 == 0 and j < depths.size():
		var d: String = str(depths[j])
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s_%s.png" % [out, d])
		print("saved %s_%s.png %s" % [out, d, img.get_size()])
	return f > 8 + 6 * depths.size()
