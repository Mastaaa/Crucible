extends SceneTree
## A4 movers on seed 7, built left of the Hub (so the Hub is the network), a Tank as the load:
##  A. Piston: the load joins at the rod, runs out 20 cells and back, holds out or back when
##     clicked, costs power, stops without power or network, and reports a solid in its way
##  B. Gantry: a load hung under the rail rides along it, 80 cells at most, and comes back
##  C. a save keeps a Piston's mode and mount, and it goes on after loading
##  D. research: the Build buttons wait for their techs
## Run: godot --headless --path . --script tests/scenario_movers.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const Save = preload("res://scripts/save.gd")
var game: Node
var f := 0
var fails := 0
const X0 := 310          # the Piston's left edge (the Hub's link reach ends about 80 cells from its centre, 384, 170)
const RAIL := 240        # the Gantry's
const SURFACE := 200     # ground level there (dirt from here down)


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


func place(def: String, x: int, y: int, turns: int = 0) -> int:
	var id := MC.place(game, def, Vector2i(x, y), turns)
	if id == 0:
		print("  !! can't place %s at %d,%d: %s" % [def, x, y, MC.check_place(game, def, Vector2i(x, y), turns)])
	return id


## Runs until `cond` is true (checked every half second) or `limit` seconds pass; true if it came.
func until(cond: Callable, limit: float) -> bool:
	for _i in int(limit * 2.0):
		if cond.call():
			return true
		secs(0.5)
	return cond.call()


## The Piston with a Tank (turned over, so its hook meets the rod) standing on top of it, set to
## `mode` from the start.
func build_piston(mode: String = "back") -> Dictionary:
	var pis := place("piston", X0, SURFACE - 26)
	var tank := place("tank", X0, SURFACE - 26 - 30, 2)
	game.modules[pis]["mode"] = mode
	secs(1.0)
	return {"mover": pis, "load": tank}


## Power taken from the stock over `ticks` ticks (the game's counter resets twice a second, so
## it is summed a tick at a time).
func drawn(ticks: int) -> float:
	var total := 0.0
	for _i in ticks:
		var a: float = game.used_acc
		game.run_ticks(1)
		var b: float = game.used_acc
		total += b - a if b >= a else b
	return total


func y_of(id: int) -> float:
	return game.sim.body_state(game.modules[id]["body"])[1]


func scenario_a() -> void:
	print("A. Piston")
	fresh()
	var r := build_piston()
	var m: Dictionary = game.modules[r["mover"]]
	var tank: Dictionary = game.modules[r["load"]]
	check(m["tether"] == r["load"] and m["rig"] == [r["load"]], "the Tank joins at the rod and is the load")
	check(not m["faces"][0]["open"], "the joined face stays shut (a rod passes nothing)")
	var y0 := y_of(r["load"])
	m["mode"] = "run"
	var used := drawn(30)
	check(until(func() -> bool: return m["pos"] > 19.5, 20.0), "it runs out the whole stroke (%.1f)" % m["pos"])
	check(absf((y0 - y_of(r["load"])) - m["pos"]) < 0.6, "and the Tank is up by as much (%.1f, was %.1f)" % [y0 - y_of(r["load"]), m["pos"]])
	check(used > 0.05, "moving drew power (%.3f)" % used)
	check(until(func() -> bool: return m["pos"] < 0.5 and m["dir"] < 0, 20.0) or m["dir"] < 0, "then it turns round")
	check(until(func() -> bool: return m["pos"] < 0.1, 20.0), "and runs back home (%.2f)" % m["pos"])
	check(m["tether"] == r["load"], "the Tank stayed joined the whole way")
	# Clicking changes the mode: out, back, run.
	var at := Vector2i(X0 + 1, SURFACE - 13)
	check(MC.use(game, at) and m["mode"] == "out", "a click on the Piston switches it to out")
	check(until(func() -> bool: return m["pos"] > 19.9, 20.0), "and it holds there")
	var hold: float = m["pos"]
	var held := drawn(180)
	check(absf(m["pos"] - hold) < 0.1 and held < 0.001, "holding out costs nothing (%.1f, %.3f power)" % [m["pos"], held])
	MC.use(game, at)
	check(m["mode"] == "back" and until(func() -> bool: return m["pos"] < 0.1, 20.0), "the next click sends it back")
	MC.use(game, at)
	check(m["mode"] == "run", "and the one after runs it again")
	# Without power it stays put.
	m["mode"] = "run"
	for _i in 36:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	var stuck: float = m["pos"]
	for _i in 240:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(absf(m["pos"] - stuck) < 0.1 and m["why"] == "Waiting for power.", "with no power it waits (%.1f)" % m["pos"])
	game.stock[D.R_POWER] = 90.0
	check(until(func() -> bool: return m["pos"] > stuck + 3.0, 10.0), "and goes on once there is some")
	check(tank["integrity"] > 0.9, "(the Tank is unhurt)")
	# Rock in the way: a slab over the Tank stops it, and the Piston says so.
	fresh()
	fill(Rect2i(X0 - 20, SURFACE - 26 - 30 - 8, 60, 6), D.BEDROCK)
	r = build_piston("out")
	m = game.modules[r["mover"]]
	check(until(func() -> bool: return m["why"] == "Blocked.", 20.0), "a slab above the Tank blocks it and it says so")
	check(m["pos"] < 8.0, "short of the slab (%.1f)" % m["pos"])


func scenario_b() -> void:
	print("B. Gantry")
	fresh()
	var rail := place("gantry", RAIL, SURFACE - 90)
	var tank := place("tank", RAIL - 12, SURFACE - 78)
	var m: Dictionary = game.modules[rail]
	m["mode"] = "back"
	secs(1.0)
	check(m["tether"] == tank and m["rig"] == [tank], "the Tank hangs from the carriage")
	var x0: float = game.sim.body_state(game.modules[tank]["body"])[0]
	m["mode"] = "run"
	check(until(func() -> bool: return m["pos"] > 79.0, 60.0), "the Tank rides out along the rail (%.1f)" % m["pos"])
	var x1: float = game.sim.body_state(game.modules[tank]["body"])[0]
	check(absf((x1 - x0) - m["pos"]) < 1.0 and absf(y_of(tank) - y_of(tank)) < 0.01, "sideways, by as much (%.1f cells)" % (x1 - x0))
	check(m["pos"] < 80.5, "and no further than the rail (%.1f)" % m["pos"])
	check(until(func() -> bool: return m["pos"] < 1.0, 60.0), "then it comes back")
	var y_a := y_of(tank)
	secs(2.0)
	check(absf(y_of(tank) - y_a) < 0.5, "the Tank hangs level, it doesn't sag (%.2f)" % (y_of(tank) - y_a))
	MC.use(game, Vector2i(RAIL + 50, SURFACE - 89))
	check(m["mode"] == "out", "a click on the rail switches it to out")
	# Turned a quarter, the rail runs up and down: a Gantry stood on its end.
	fresh()
	var up := place("gantry", 300, SURFACE - 118, 1)
	var t2 := place("tank", 270, SURFACE - 118 - 12, 1)
	var m2: Dictionary = game.modules[up]
	m2["mode"] = "back"
	secs(1.0)
	m2["mode"] = "run"
	check(m2["tether"] == t2, "a turned rail takes a load on its side")
	var ay: float = y_of(t2)
	check(until(func() -> bool: return absf(m2["pos"]) > 20.0, 40.0), "and carries it along its length (%.1f)" % m2["pos"])
	check(absf(y_of(t2) - ay) > 15.0, "up or down the wall (%.1f)" % (y_of(t2) - ay))


func scenario_c() -> void:
	print("C. save")
	fresh()
	var r := build_piston()
	var m: Dictionary = game.modules[r["mover"]]
	m["mode"] = "out"
	check(until(func() -> bool: return m["pos"] > 6.0, 20.0), "the Piston is on its way out")
	var path := "user://movers_test.save"
	Save.write(game, path)
	game.continue_run(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.paused = true
	var m2: Dictionary = game.modules[r["mover"]]
	check(m2["tether"] == r["load"] and m2["mode"] == "out", "it loads back mounted and still set to out")
	check(until(func() -> bool: return m2["pos"] > 19.5, 20.0), "and finishes the stroke (%.1f)" % m2["pos"])


func scenario_d() -> void:
	print("D. research")
	fresh()
	for id: String in ["piston", "gantry"]:
		check(not MC.unlocked(game, MC.defs[id]), "the %s is locked at first" % id)
		game.researched[id] = true
		check(MC.unlocked(game, MC.defs[id]), "and open once researched")
