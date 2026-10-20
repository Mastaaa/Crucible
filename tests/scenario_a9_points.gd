extends SceneTree
## A8 to A9 meeting points: what A9's Hookups (Pipe, Cable, Network, Conveyor) can count on from A8.
##  A. two modules that declare an `attach` entry on faces that touch offer points that coincide, and a
##     joint made there is keyed to both module ids
##  B. a declared point moves with its module (the joint carries the pair as one)
##  C. taking a module down clears its joints and leaves the other module's points as they were
##  D. A9 (live since the exterior track): a Pipe or Cable module declaring a hookup point that a joint
##     can be made at, and a Pipe laid at those points.
## Run: godot --headless --path . --script tests/scenario_a9_points.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const JT = preload("res://scripts/machines/joints.gd")
const LN = preload("res://scripts/machines/lines.gd")
const A9 := true
var game: Node
var f := 0
var fails := 0
const SURFACE := 200


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


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	MC.ensure_defs()
	fill(Rect2i(328, SURFACE - 140, 144, 140), D.AIR)
	fill(Rect2i(328, SURFACE, 144, 160), 6)
	fill(Rect2i(328, SURFACE + 160, 144, 40), D.BEDROCK)
	game.stock[D.R_STONE] = 60.0
	game.researched["joints"] = true
	MC.defs["test_box"]["attach"] = [{"face": "signal", "kind": "hookup"}]
	MC.defs["test_plug"]["attach"] = [{"face": "signal", "kind": "hookup"}]


func hookup(id: int) -> Dictionary:
	for pt: Dictionary in JT.points(game, game.modules[id]):
		if pt["kind"] == "hookup":
			return pt
	return {}


func pos(id: int) -> Vector2:
	var st: PackedFloat32Array = game.sim.body_state(game.modules[id]["body"])
	return Vector2(st[0], st[1])


## The box with the plug against its right side, both standing on the ground.
func pair() -> Array:
	var box := MC.place(game, "test_box", Vector2i(380, SURFACE - 20), 0)
	var plug := MC.place(game, "test_plug", Vector2i(408, SURFACE - 20), 0)
	return [box, plug]


func scenario_a() -> void:
	print("A. points that meet")
	fresh()
	var ids := pair()
	check(ids[0] != 0 and ids[1] != 0, "a box and a plug stand side by side")
	var hb := hookup(ids[0])
	var hp := hookup(ids[1])
	check(not hb.is_empty() and not hp.is_empty(), "each offers the hookup it declared")
	check(hb.get("name", "") == "signal" and hp.get("name", "") == "signal", "named for its face")
	check((hb["pos"] as Vector2).distance_to(hp["pos"]) < JT.GAP, "and the two sit where the faces meet (%.2f cells apart)" % (hb["pos"] as Vector2).distance_to(hp["pos"]))
	var gr := JT.grab(game, hb["pos"], "bolt")
	check(not gr.has("why") and [gr["a"], gr["b"]].has(ids[0]) and [gr["a"], gr["b"]].has(ids[1]), "a Bolt clicked there takes both modules")
	var j := JT.attach(game, "bolt", gr["a"], gr["b"], gr["at"])
	check(j > 0 and [game.joints[j]["a"], game.joints[j]["b"]].has(ids[0]) and [game.joints[j]["a"], game.joints[j]["b"]].has(ids[1]), "and the joint record names both module ids")


func scenario_b() -> void:
	print("B. a point moves with its module")
	fresh()
	var box := MC.place(game, "test_box", Vector2i(380, SURFACE - 60), 0)
	var plug := MC.place(game, "test_plug", Vector2i(408, SURFACE - 60), 0)
	var gr := JT.grab(game, hookup(box)["pos"], "bolt")
	JT.attach(game, "bolt", gr["a"], gr["b"], gr["at"])
	var h0: Vector2 = hookup(box)["pos"]
	var p0 := pos(box)
	game.run_ticks(20)
	var moved := pos(box) - p0
	check(moved.y > 3.0, "the pair falls (%.1f cells)" % moved.y)
	check((hookup(box)["pos"] as Vector2).distance_to(h0 + moved) < 1.0, "and the box's point goes with it")
	check((hookup(box)["pos"] as Vector2).distance_to(hookup(plug)["pos"]) < 2.0, "the two points stay together (%.2f apart)" % (hookup(box)["pos"] as Vector2).distance_to(hookup(plug)["pos"]))


func scenario_c() -> void:
	print("C. taking one down")
	fresh()
	var ids := pair()
	var gr := JT.grab(game, hookup(ids[0])["pos"], "bolt")
	var j := JT.attach(game, "bolt", gr["a"], gr["b"], gr["at"])
	var before: Vector2 = hookup(ids[1])["pos"]
	MC.remove(game, ids[0])
	check(not game.joints.has(j) and game.joints.is_empty(), "the joint goes with the module")
	check(game.modules.has(ids[1]) and (hookup(ids[1])["pos"] as Vector2).distance_to(before) < 0.5, "and the other keeps its point where it was")


func scenario_d() -> void:
	print("D. Pipe and Cable (A9)")
	if not A9:
		print("  (switched off until A9 lands)")
		return
	fresh()
	for def_id: String in ["pipe", "cable"]:
		check(MC.defs.has(def_id), "%s is a module" % def_id)
		var has := false
		for a: Dictionary in MC.defs.get(def_id, {}).get("attach", []):
			has = has or a.get("kind", "") == "hookup"
		check(has, "%s declares a hookup point" % def_id)
	# And a laid line is held at the points: a hinge at each hookup, owned by the line.
	for t in ["chute", "case", "pipes"]:
		game.researched[t] = true
	var c1 := MC.place(game, "case", Vector2i(340, SURFACE - 26), 0)
	var h1 := MC.place(game, "pipe_hookup", Vector2i(366, SURFACE - 25), 0)
	var c2 := MC.place(game, "case", Vector2i(440, SURFACE - 26), 0)
	var h2 := MC.place(game, "pipe_hookup", Vector2i(422, SURFACE - 25), 2)
	game.run_ticks(60)
	var p1 := hookup(h1)
	var p2 := hookup(h2)
	check(c1 != 0 and c2 != 0 and h1 != 0 and h2 != 0 and not p1.is_empty() and not p2.is_empty(), "a Pipe Hookup offers its point")
	var e1: Dictionary = JT.hold(game, p1["pos"])
	check(e1.get("mod", 0) == h1 and e1.get("kind", "") == "hookup", "a joint tool clicked at the point takes the hookup, not the base behind it")
	game.joint_from = {}
	LN.click(game, "pipe", p1["pos"])
	LN.click(game, "pipe", p2["pos"])
	var lines := LN.all(game)
	check(lines.size() == 1, "the Pipe tool lays a Pipe between two hookup points")
	if lines.size() == 1:
		var m: Dictionary = game.modules[lines[0]]
		var ok := true
		for k in 2:
			var j: Dictionary = game.joints.get(m["joints"][k], {})
			ok = ok and j.get("kind", "") == "hinge" and j.get("auto", 0) == lines[0] and [j.get("a", 0), j.get("b", 0)].has(m["ends"][k])
		check(ok, "held by a hinge at each point, owned by the line")
