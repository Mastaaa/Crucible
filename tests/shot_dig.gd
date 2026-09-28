extends SceneTree
## Screenshot of the phase-6 digging tools on seed 7: the fixed Drill's shaft
## beside the Hub with Conduits down it, a Borer tunnelling left out of the shaft
## with a Lamp at its mouth, a Thumper in the air over its crater beside a
## Hopper, and a Relay Mast out on the surface. The Borer is selected.
## xvfb-run godot --rendering-method gl_compatibility --path . --script tests/shot_dig.gd -- --out=/path/dig

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var out := "/tmp/dig"
var thumper


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
	game.run_ticks(2)
	return b


func run(s: float) -> void:
	for _i in int(s * 4.0):
		game.stock[D.R_POWER] = 100.0
		game.run_ticks(15)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(7)
		game.paused = true
		game.stock[D.R_STONE] = 300.0
		game.stock[D.R_GLIMMER] = 20.0
		game.tiers_open[2] = true
		for id in ["thumper", "borer", "lamp", "cache", "relay_mast"]:
			game.researched[id] = true
		game.levels["drill_bit"] = 3
		game.levels["drill_shaft"] = 2
		game.researched["drill_bit"] = true
		game.researched["drill_shaft"] = true
		game._refresh_unlocks()
		game.drill.reach_limit = game.max_reach()
		run(50.0)
		for y in [50, 64, 78]:
			build(D.B_CONDUIT, Rect2i(132, y, 2, 2))
		build(D.B_LAMP, Rect2i(132, 74, 2, 2))
		build(D.B_BORER, Rect2i(132, 69, 3, 3), 1)
		build(D.B_CONDUIT, Rect2i(140, 38, 2, 2))
		build(D.B_MAST, game.snap_place(D.B_MAST, Vector2i(157, 37), false))
		build(D.B_HOPPER, Rect2i(143, 38, 3, 2))
		thumper = build(D.B_THUMPER, Rect2i(148, 38, 2, 2))
		run(40.0)
	if f >= 3 and f < 400:
		# Catch the Thumper on its way up.
		game.stock[D.R_POWER] = 100.0
		game.run_ticks(1)
		if thumper.flying and thumper.vy < -6.0 and thumper.blasts >= 4:
			f = 400
			for b in game.buildings:
				if b.type == D.B_BORER:
					game.selected = b
			game._refresh_vision()
			game.mem_due = true
			game.set_zoom(game.zoom_max - 1)
			game._center_on(62.0, true, 134.0)
			game.banner_time = 0.0
			print("thumper at %s" % thumper.center())
	if f == 410:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out + ".png")
		print("saved ", out, ".png ", img.get_size())
		return true
	return false
