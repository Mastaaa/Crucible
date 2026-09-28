extends SceneTree
## Pacing probe: how fast the fixed Drill's shaft goes down on seed 7 with one
## Lab beside the Hub researching Drill Bit and Drill Shaft levels (the cheaper
## open one each time) on nothing but the Hub's own power. Prints a timeline. Not
## a bot: no Waterwheels, no Hoppers for the floods, no second Lab, so it's a slow
## line to compare builds against.
## Run: godot --headless --path . --script tests/descent.gd [-- --until=330 --limit=1800]

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var until := 330
var limit := 1800.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--until="):
			until = int(a.substr(8))
		elif a.begins_with("--limit="):
			limit = float(a.substr(8))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _pick() -> void:
	if game.current_tech != "":
		return
	var best := ""
	var best_cost := INF
	for id in ["drill_bit", "drill_shaft"]:
		if game.tech_block(id) != "":
			continue
		var cost: float = game.tech_step(id)["power"]
		if cost < best_cost:
			best_cost = cost
			best = id
	if best != "":
		game.pick_research(best)


func _process(_d: float) -> bool:
	f += 1
	if f != 2:
		return false
	game.new_game(7)
	game.paused = true
	var lab = game.place(D.B_LAB, Rect2i(118, 37, 4, 3))
	var d = game.drill
	print("time  head  reach  stone  power  water  research")
	var last := -1
	var reached := -1.0
	while game.game_time < limit:
		_pick()
		game.run_ticks(60)
		var head := int(d.drill_head().y)
		if head >= until and reached < 0.0:
			reached = game.game_time
		var t := int(game.game_time)
		if floori(t / 30.0) != last:
			last = floori(t / 30.0)
			var rs: String = game.current_tech
			var rtxt := "-"
			if rs != "":
				rtxt = "%s %d %d%%" % [rs, game.level(rs) + 1, int(game.tech_power_frac(rs) * 100.0)]
			print("%4ds  %4d  %3d/%-3d  %5.0f  %5.0f  %5.0f  %s  (bit %d, shaft %d)%s" % [t, head, d.reach, d.reach_limit,
					game.total(D.R_STONE), game.total(D.R_POWER), game.total(D.R_WATER), rtxt,
					game.level("drill_bit"), game.level("drill_shaft"), "" if lab.built else "  (Lab not built)"])
		if reached >= 0.0:
			break
	if reached >= 0.0:
		print("the shaft reached depth %d in %.0f s" % [until, reached])
	else:
		print("the shaft got to depth %d in %.0f s (reach %d; bit %d, shaft %d)" % [int(d.drill_head().y), game.game_time,
				d.reach_limit, game.level("drill_bit"), game.level("drill_shaft")])
	return true
