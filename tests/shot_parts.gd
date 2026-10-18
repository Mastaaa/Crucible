extends SceneTree
## Screenshot of joints: a plate hinged to a ceiling, a second bolted under it, a third on a motor
## (turning), one pitoned to rock, and the Hinge tool picked with the cursor on a free spot.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_parts.gd -- --out=/path/parts

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const JT = preload("res://scripts/machines/joints.gd")
var game: Node
var f := 0
var out := "/tmp/parts"
const SURFACE := 200


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
		game.reveal_all = true
		MC.ensure_defs()
		fill(Rect2i(328, SURFACE - 140, 144, 140), D.AIR)
		fill(Rect2i(370, 90, 100, 10), D.BEDROCK)
		fill(Rect2i(470, 100, 10, 70), D.BEDROCK)
		var p1 := MC.place(game, "test_plate", Vector2i(421, 101), 0)
		var p2 := MC.place(game, "test_plate", Vector2i(421, 109), 0)
		var p3 := MC.place(game, "test_plate", Vector2i(421, 117), 0)
		var p4 := MC.place(game, "test_plate", Vector2i(428, 140), 0)
		game.stock[D.R_POWER] = 90.0
		JT.attach(game, "hinge", p1, 0, Vector2(421.0, 98.5))
		JT.attach(game, "bolt", p1, p2, Vector2(440.0, 108.0))
		var m := JT.attach(game, "motor", p3, p2, Vector2(440.0, 116.0))
		game.joints[m]["mode"] = 1
		JT.attach(game, "piton", p4, 0, Vector2(470.5, 142.5))
		game.run_ticks(90)
		game.paused = true
		game.joint_pick = "hinge"
		game.set_zoom(game.zoom_max * 0.5)
		game._center_on(125.0, true, 430.0)
	if f == 6:
		game.hover = Vector2i(448, 128)
	if f == 9:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
