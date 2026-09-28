extends SceneTree
## Screenshot of the Research tab mid-game on seed 7: a couple of Tier 1 techs done,
## Tier 2 opened, one tech in progress.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_research.gd -- --out=/path/prefix [--closed]

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var out := "/tmp/research"
var closed := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--closed":
			closed = true
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(7)
		game.paused = true
		var lab = game.place(D.B_LAB, Rect2i(118, 37, 4, 3))
		game.run_ticks(120)
		for id in ["lamp", "spout", "thumper"]:
			game.researched[id] = true
		game.levels["drill_bit"] = 1
		game.levels["drill_shaft"] = 2
		game.levels["thump_charge"] = 1
		for id in ["drill_bit", "drill_shaft", "thump_charge"]:
			game.researched[id] = true
		game._refresh_unlocks()
		game.tiers_open[2] = true
		game.tech_power["cache"] = 25.0
		game.pick_research("floodgate")
		game.tech_power["floodgate"] = 70.0
		game.tech_mats_got("floodgate")
		game.tech_mats["floodgate"][D.R_GLIMMER] = 2.0
		game.stock[D.R_GLIMMER] = 1.0
		game.run_ticks(240)
		game.selected = lab
		if not closed:
			game.hud.toggle_research()
		game._center_on(60.0, true, 128.0)
	if f == 14:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
