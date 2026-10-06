extends SceneTree
## A5 part 5, moving and sorting fluids, on seed 7:
##  A. the Pump lifts the liquid in front of its mouth (Water, then oil) up into a Tank, and leaves powder alone
##  B. with no power it lifts nothing
##  C. the Sieve sends liquids and gases out of its top and solids out of its left face
##  D. the Centrifuge sends the lightest material up and the densest out of its left face, the one left goes the heavy way
##  E. research gates the three Build buttons; the data has densities
##  F. a Winch rig: the Cutter halts on oil, the Pump takes its place, drains the pocket and the rig comes up, the Cutter goes on
## Run: godot --headless --path . --script tests/scenario_fluids.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200     # ground level (dirt from here down)
const WATER := 9
const SAND := 31
const SLICK := 35
const STONE := 2
const TECHS := ["pump", "sieve", "centrifuge"]


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
	game.stock[D.R_POWER] = 90.0
	for t: String in TECHS:
		game.researched[t] = true


func place(def: String, x: int, y: int, turns: int = 0) -> int:
	var id := MC.place(game, def, Vector2i(x, y), turns)
	if id == 0:
		print("  !! can't place %s at %d,%d: %s" % [def, x, y, MC.check_place(game, def, Vector2i(x, y), turns)])
	return id


func until(cond: Callable, limit: float) -> bool:
	for _i in int(limit):
		if cond.call():
			return true
		secs(1.0)
	return cond.call()


func held(id: int, mat: int) -> int:
	return int(game.modules[id]["contents"].get(mat, 0))


## A Pump resting on the rim of a 20 wide, 6 deep pit filled with `mat`, a Tank on top of it.
func pumping(mat: int, dead := false) -> Dictionary:
	fresh()
	if dead:
		game.stock[D.R_POWER] = 0.0
	fill(Rect2i(303, SURFACE, 20, 6), mat)
	var pump := place("pump", 300, SURFACE - 16)
	var sn := MC.snap(game, "tank", 0, Vector2i(313, SURFACE - 16 - 15))
	var tank := MC.place(game, "tank", sn["at"], 0)
	for _i in 30:
		if dead:
			game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	return {"pump": pump, "tank": tank, "snapped": sn["snapped"]}


func pit_left(mat: int) -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	mask[mat] = 1
	return game.sim.count_in_rect(303, SURFACE, 20, 6, mask)


func scenario_a() -> void:
	print("A. Pump")
	var r := pumping(WATER)
	check(r["snapped"], "the Tank sits on the Pump")
	var tank: int = r["tank"]
	check(until(func() -> bool: return held(tank, WATER) >= 60, 40.0), "Water is lifted into the Tank (%d cells, %d left in the pit)" % [held(tank, WATER), pit_left(WATER)])
	check(game.modules[r["pump"]].get("lifted", 0) >= 60, "and counted (%d lifted)" % game.modules[r["pump"]].get("lifted", 0))
	r = pumping(SLICK)
	tank = r["tank"]
	check(until(func() -> bool: return held(tank, SLICK) >= 60, 40.0), "so is oil: Slick goes into the Tank (%d cells)" % held(tank, SLICK))
	r = pumping(SAND)
	secs(8.0)
	check(held(r["tank"], SAND) == 0 and pit_left(SAND) == 120, "powder is left alone (%d in the Tank, %d in the pit)" % [held(r["tank"], SAND), pit_left(SAND)])


func scenario_b() -> void:
	print("B. no power")
	var r := pumping(WATER, true)
	for _i in 600:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(held(r["tank"], WATER) == 0 and pit_left(WATER) == 120, "with no power it lifts nothing (%d in the Tank)" % held(r["tank"], WATER))


## A Sieve or Centrifuge on a Stone pedestal with a Tank on top and a turned Tank at its left face.
func sorter(def: String, mix: Dictionary, dead := false) -> Dictionary:
	fresh()
	if dead:
		game.stock[D.R_POWER] = 0.0
	fill(Rect2i(300, SURFACE - 7, 26, 7), STONE)
	var s := place(def, 300, SURFACE - 7 - 30)
	var top_sn := MC.snap(game, "tank", 0, Vector2i(313, SURFACE - 7 - 30 - 15))
	var top := MC.place(game, "tank", top_sn["at"], 0)
	var side_sn := {"snapped": false, "at": Vector2i()}
	var turns := 1
	for t in [1, 3]:
		side_sn = MC.snap(game, "tank", t, Vector2i(284, SURFACE - 13))
		turns = t
		if side_sn["snapped"]:
			break
	var side := MC.place(game, "tank", side_sn["at"], turns)
	for mat: int in mix:
		MC.add_contents(game, s, mat, mix[mat])
	for _i in 30:
		if dead:
			game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	return {"sorter": s, "top": top, "side": side, "snapped": top_sn["snapped"] and side_sn["snapped"]}


func scenario_c() -> void:
	print("C. Sieve")
	var r := sorter("sieve", {SAND: 60, WATER: 60})
	check(r["snapped"], "both Tanks join the Sieve")
	var top: int = r["top"]
	var side: int = r["side"]
	until(func() -> bool: return held(top, WATER) >= 60 and held(side, SAND) >= 60, 30.0)
	check(held(top, WATER) >= 60 and held(top, SAND) == 0, "the Water goes up (%d Water, %d Sand in the top Tank)" % [held(top, WATER), held(top, SAND)])
	check(held(side, SAND) >= 60 and held(side, WATER) == 0, "the Sand goes out of the side (%d Sand, %d Water in the side Tank)" % [held(side, SAND), held(side, WATER)])


func scenario_d() -> void:
	print("D. Centrifuge")
	var r := sorter("centrifuge", {SAND: 90, SLICK: 30, WATER: 30})
	check(r["snapped"], "both Tanks join the Centrifuge")
	var top: int = r["top"]
	var side: int = r["side"]
	until(func() -> bool: return held(top, SLICK) >= 30 and held(top, WATER) >= 30 and held(side, SAND) >= 90, 40.0)
	check(held(top, SLICK) >= 30 and held(top, WATER) >= 30, "the light materials go up (%d Slick, %d Water)" % [held(top, SLICK), held(top, WATER)])
	check(held(side, SAND) >= 90 and held(side, SLICK) == 0 and held(side, WATER) == 0, "the densest goes out of the side (%d Sand, %d Slick, %d Water)" % [held(side, SAND), held(side, SLICK), held(side, WATER)])
	check(held(top, SAND) == 0, "and the last of it goes the heavy way, not up (%d Sand up top)" % held(top, SAND))
	r = sorter("centrifuge", {SAND: 60, WATER: 30}, true)
	for _i in 600:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(held(r["side"], SAND) == 0 and held(r["top"], WATER) == 0, "with no power it sorts nothing")


func scenario_e() -> void:
	print("E. research and data")
	fresh()
	for t: String in TECHS:
		game.researched.erase(t)
	var locked := true
	for t: String in TECHS:
		locked = locked and not MC.unlocked(game, MC.defs[t])
	check(locked, "all three are locked at first")
	for t: String in TECHS:
		game.researched[t] = true
	var open := true
	for t: String in TECHS:
		open = open and MC.unlocked(game, MC.defs[t])
	check(open, "and open once researched")
	check(M.density_of(SLICK) < M.density_of(WATER) and M.density_of(WATER) < M.density_of(SAND) and M.density_of(SAND) < M.density_of(40), "densities run Slick, Water, Sand, Ferrite")
	for t: String in TECHS:
		var i: int = D.tech_index(t)
		check(i >= 0 and D.TECHS[i].get("module", "") == t, "%s has its tech" % t)


## A shaft of air with a pocket of oil in the bottom of it, over a dirt floor, and the rig above it.
func scenario_f() -> void:
	print("F. a Pump rig clears the oil the Cutter stops at")
	fresh()
	game.researched["pump"] = true
	var x0 := 290
	var cut := place("cutter", x0, SURFACE - 16)
	var tank := place("tank", x0, SURFACE - 16 - 30)
	var fun := place("funnel", x0, SURFACE - 16 - 30 - 14)
	var winch := place("winch", x0 + 14, SURFACE - 16 - 30 - 18)
	secs(1.0)
	fill(Rect2i(x0 - 2, SURFACE, 30, 70), 0)           # the shaft is opened under a rig the Winch already holds
	fill(Rect2i(x0 - 2, SURFACE + 50, 30, 20), SLICK)
	var w: Dictionary = game.modules[winch]
	check(until(func() -> bool: return w["halt"] != "" and w["state"] == "docked", 200.0), "the Cutter reaches the oil and the rig comes up")
	check("Slick" in w["halt"], "the Winch says why: %s" % w["halt"])
	var oil_before := count_oil()
	MC.remove(game, cut)
	var pump := fit("pump", tank)
	secs(1.0)
	check(pump != 0 and w["rig"].has(pump), "the Pump takes the Cutter's place under the Tank")
	check(until(func() -> bool: return w["state"] == "down", 20.0), "swapping the digger lifts the hold")
	check(until(func() -> bool: return w["halt"] != "" and w["state"] == "docked" and "Pump" in w["halt"], 400.0), "the rig drains the pocket and comes up (%s)" % w["halt"])
	check(count_oil() < (oil_before >> 2), "most of the oil is gone from the shaft (%d of %d cells left)" % [count_oil(), oil_before])
	check(game.goods.get(SLICK, 0.0) > 0.5, "and the Funnel banked it (%.1f units of Slick)" % game.goods.get(SLICK, 0.0))
	MC.remove(game, pump)
	cut = fit("cutter", tank)
	secs(1.0)
	check(until(func() -> bool: return w["state"] == "down", 20.0), "put the Cutter back and the Winch goes down again")
	check(game.modules.has(tank) and game.modules.has(fun), "(the rig stands)")


## A module for the Tank's lower face, snapped on as the cursor would (the Winch parks a docked rig a few cells off where it was built).
func fit(def: String, tank: int) -> int:
	var at: Vector2 = game.modules[tank]["at"]
	var sn := MC.snap(game, def, 0, Vector2i(int(at.x), int(at.y) + 15 + 8))
	return MC.place(game, def, sn["at"], 0)


func count_oil() -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	mask[SLICK] = 1
	return game.sim.count_in_rect(288, SURFACE, 30, 70, mask)
