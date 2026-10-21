extends SceneTree
## Screenshot of the Floodlight (A9): a dark cavern under the Hub, two shelves in it, with a Lamp on the right and a Floodlight bolted to a Case, throwing its cone to the left,
## fog on, so the cone and the Lamp's pool show against the dark.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_floodlight.gd -- --out=/path/floodlight

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const JT = preload("res://scripts/machines/joints.gd")
var game: Node
var f := 0
var out := "/tmp/floodlight"
const FLOOR := 270


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


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.title.visible = false
		game.new_game(7)
		MC.ensure_defs()
		fill(Rect2i(20, 205, 840, 235), D.BEDROCK)
		fill(Rect2i(30, 210, 820, 220), D.AIR)
		fill(Rect2i(370, FLOOR, 90, 8), D.BEDROCK)
		fill(Rect2i(480, FLOOR, 130, 8), D.BEDROCK)
		game.researched["lamp"] = true
		game.researched["case"] = true
		game.researched["floodlight"] = true
		game.stock[D.R_POWER] = 90.0
		game.stock[D.R_STONE] = 100.0
		var nr := Rect2i(500, FLOOR - 20, 20, 20)
		game.place(D.B_NODE, nr)
		game.place(D.B_NODE, Rect2i(440, FLOOR - 20, 20, 20))
		var c := MC.place(game, "case", Vector2i(395, FLOOR - 26), 0)
		JT.attach(game, "piton", c, 0, Vector2(408.0, FLOOR + 0.5), Vector2(408.0, FLOOR + 0.5))
		game.run_ticks(600)
		var b := MC.bounds(game.modules[c])
		var fat := Vector2i(b.position.x - 16, b.position.y + (b.size.y >> 1) - 8)
		MC.place(game, "floodlight", fat, 2)
		MC.place(game, "lamp", Vector2i(560, FLOOR - 16), 0)
	if f == 4:
		game.run_ticks(150)
		game.paused = true
		game.set_zoom(game.zoom_min * 1.6)
		game._center_on(290.0, true, 440.0)
	if f == 9:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
