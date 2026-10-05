extends SceneTree
## A5 part 7, sensors and the Thermoelectric Plate, on seed 7:
##  A. the Thermometer's signal follows the temperature in front of its mouth, and a click moves the setting
##  B. the Material Sensor's signal follows the cells of its material in the mouth
##  C. the Timer switches on and off
##  D. a module whose gate face touches a sensor works only while the signal is on (a Combustor burns only with Water in sight)
##  E. the Thermoelectric Plate pays out for a difference between its sides and nothing for none
##  F. research gates the four Build buttons
## Run: godot --headless --path . --script tests/scenario_sensing.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200     # ground level (dirt from here down)
const WATER := 9
const CHUNKS := 23
const TECHS := ["thermometer", "material_sensor", "timer", "thermoelectric", "combustor"]


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		if game.sim.get_script() != null:
			print("  (the GDScript sim has no bodies: nothing to check)")
			print("FAILURES: 0")
			return true
		scenario_a()
		scenario_b()
		scenario_c()
		scenario_d()
		scenario_e()
		scenario_f()
		print("FAILURES: %d" % fails)
		return true
	return false


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	MC.ensure_defs()
	fill(Rect2i(200, SURFACE - 120, 144, 120), D.AIR)
	fill(Rect2i(200, SURFACE, 144, 160), 6)
	fill(Rect2i(200, SURFACE + 160, 144, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 10.0
	for t: String in TECHS:
		game.researched[t] = true


func place(def: String, x: int, y: int, turns: int = 0) -> int:
	var id := MC.place(game, def, Vector2i(x, y), turns)
	if id == 0:
		print("  !! can't place %s at %d,%d: %s" % [def, x, y, MC.check_place(game, def, Vector2i(x, y), turns)])
	return id


func sig(id: int) -> bool:
	return bool(game.modules[id].get("signal", false))


func scenario_a() -> void:
	print("A. Thermometer")
	fresh()
	var th := place("thermometer", 300, SURFACE - 60)
	secs(0.5)
	check(not sig(th), "cool air: off (reads %d degrees)" % int(game.modules[th].get("reading", -1)))
	var mouth: Rect2i = MC.kinds["sensor"].BH.mouth(game, game.modules[th], MC.defs["thermometer"])
	game.sim.heat_rect(mouth.position.x, mouth.position.y, mouth.size.x, mouth.size.y, 200)
	secs(0.5)
	check(sig(th), "heated past 100 in its mouth: on (reads %d)" % int(game.modules[th].get("reading", -1)))
	MC.kinds["sensor"].use(game, game.modules[th], MC.defs["thermometer"])
	secs(0.5)
	check(game.modules[th].get("above", -1) == 300 and not sig(th), "a click moves the setting to 300 and it goes off (above %s, reads %d)" % [str(game.modules[th].get("above")), int(game.modules[th].get("reading", -1))])
	check("300" in MC.kinds["sensor"].info(game, game.modules[th], MC.defs["thermometer"]), "and says so")


func scenario_b() -> void:
	print("B. Material Sensor")
	fresh()
	var ms := place("material_sensor", 300, SURFACE - 14)
	secs(0.5)
	check(not sig(ms), "nothing in its mouth: off")
	fill(Rect2i(302, SURFACE, 8, 1), WATER)
	secs(0.5)
	check(sig(ms), "8 cells of Water in its mouth: on (sees %d)" % int(game.modules[ms].get("reading", -1)))
	MC.kinds["sensor"].use(game, game.modules[ms], MC.defs["material_sensor"])
	secs(0.5)
	check(not sig(ms), "a click makes it watch Slick instead: off")


func scenario_c() -> void:
	print("C. Timer")
	fresh()
	var tm := place("timer", 300, SURFACE - 60)
	var ons := 0
	var offs := 0
	for _i in 16:
		secs(0.5)
		if sig(tm):
			ons += 1
		else:
			offs += 1
	check(ons >= 6 and offs >= 6, "over 8 seconds it spends about half its time on (%d on, %d off samples)" % [ons, offs])


## A Combustor holding Coal chunks on the ground with a Material Sensor against its right face.
func gated_burner() -> Dictionary:
	fresh()
	var comb := place("combustor", 300, SURFACE - 18)
	var sn := MC.snap(game, "material_sensor", 0, Vector2i(334, SURFACE - 9))
	var ms := MC.place(game, "material_sensor", sn["at"], 0)
	MC.add_contents(game, comb, CHUNKS, 20)
	secs(0.5)
	return {"comb": comb, "ms": ms, "snapped": sn["snapped"], "x": sn["at"].x}


func scenario_d() -> void:
	print("D. a signal gates a module")
	var r := gated_burner()
	var comb: Dictionary = game.modules[r["comb"]]
	check(r["snapped"] and comb["faces"][1]["link_m"] == r["ms"], "the sensor joins the Combustor's gate face")
	secs(4.0)
	check(comb.get("burned", 0) == 0 and "signal" in comb["state"], "no Water in sight: the Combustor does nothing (%s)" % comb["state"])
	fill(Rect2i(int(r["x"]) + 2, SURFACE, 8, 1), WATER)
	secs(4.0)
	check(comb.get("burned", 0) >= 2, "Water in sight: it burns (%d cells)" % comb.get("burned", 0))
	check(not MC.gated(game, comb) and MC.defs["combustor"] != null, "and is no longer gated")
	fresh()
	var lone := place("combustor", 300, SURFACE - 18)
	MC.add_contents(game, lone, CHUNKS, 20)
	secs(4.0)
	check(game.modules[lone].get("burned", 0) >= 2, "a gate face joined to nothing leaves it working (%d burned)" % game.modules[lone].get("burned", 0))


func scenario_e() -> void:
	print("E. Thermoelectric Plate")
	fresh()
	var cold := place("thermoelectric", 300, SURFACE - 60)
	var before: float = game.stock[D.R_POWER]
	secs(4.0)
	var gain_cold: float = game.stock[D.R_POWER] - before
	var s: Array = MC.kinds["thermoelectric"].sides(game, game.modules[cold], MC.defs["thermoelectric"])
	game.sim.heat_rect(s[0].position.x, s[0].position.y, s[0].size.x, s[0].size.y, 400)
	before = game.stock[D.R_POWER]
	secs(4.0)
	var gain_hot: float = game.stock[D.R_POWER] - before
	check(gain_hot - gain_cold > 1.0, "400 degrees between its sides pays about 0.4 power a second (%.2f against %.2f over 4 s)" % [gain_hot, gain_cold])
	check(absi(int(game.modules[cold]["diff"])) >= 300, "it reads the difference (%d degrees)" % int(game.modules[cold]["diff"]))


func scenario_f() -> void:
	print("F. research")
	fresh()
	for t: String in TECHS:
		game.researched.erase(t)
	var locked := true
	for t: String in TECHS:
		locked = locked and not MC.unlocked(game, MC.defs[t])
	check(locked, "all are locked at first")
	for t: String in TECHS:
		game.researched[t] = true
	var open := true
	for t: String in TECHS:
		open = open and MC.unlocked(game, MC.defs[t])
	check(open, "and open once researched")
