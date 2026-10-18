extends SceneTree
## A8 joints in the engine (native/src/joints.cpp), on bench rooms walled in bedrock:
##  A. Pin: a bar hinged to the world swings, damps and hangs; the anchor stays put
##  B. a chain of ten links hangs to its full length with no gap opening
##  C. Weld: two bodies keep their angle under a load; Rope: never longer than its length, slack allowed
##  D. Bridge on two rooted anchors: holds an 800 cell slab; a low load limit snaps every joint under it
##  E. Motor: turns at its rate, stops against a ledge without winding on or pushing into rock
##  F. Slide: a piston follows its goal and holds, a gantry carriage stays between its limits
##  G. Assemblies: jointed bodies pass through each other and a hard knock still breaks one of them
##  H. A rooted anchor lets go when the rock under it is dug; events say why; removing a body drops its joints
##  I. Jointed bodies never turn back into ground; a driven body drags a heavy one
##  J. A save keeps the joints and the run goes on identically; a run twice gives the same checksum
##  K. The body table: 800 bodies, no 801st; parts made from a bitmap; the id table survives churn
## Run: godot --headless --path . --script tests/scenario_joints.gd

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0
var fails := 0

const PIN := 0
const ROPE := 1
const WELD := 2
const MOTOR := 3
const SLIDE := 4


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
		scenario_g()
		scenario_h()
		scenario_i()
		scenario_j()
		scenario_k()
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


func fresh() -> Rect2i:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	var room := Rect2i(200, 1000, 300, 300)
	fill(room.grow(20), D.BEDROCK)
	fill(room, D.AIR)
	return room


## A rigid stone body in the rectangle (made from the grid, then flagged as a module like a casing).
func part(r: Rect2i, m := D.STONE) -> int:
	fill(r, m)
	var id: int = game.sim.make_body(r.position.x, r.position.y, r.size.x, r.size.y, 0.0, 0.0, 0.0)
	game.sim.set_module(id, true)
	return id


func wpt(id: int, lx: float, ly: float) -> Vector2:
	var info: PackedFloat32Array = game.sim.body_info(id)
	var st: PackedFloat32Array = game.sim.body_state(id)
	return Vector2(st[0], st[1]) + Vector2(lx - info[2], ly - info[3]).rotated(st[2])


func joint(type: int, a: int, b: int, at: Vector2, extra := {}) -> int:
	var p := {"type": type, "a": a, "b": b, "ax": at.x, "ay": at.y, "bx": at.x, "by": at.y}
	p.merge(extra, true)
	return game.sim.add_joint(p)


func ticks(n: int) -> void:
	for i in n:
		game.sim.step()


func state(id: int) -> PackedFloat32Array:
	return game.sim.body_state(id)


func scenario_a() -> void:
	print("A. Pin")
	fresh()
	var bar := part(Rect2i(350, 1017, 60, 6))
	var j := joint(PIN, bar, 0, Vector2(350, 1020))
	check(j > 0, "a pin to the world is made")
	var maxerr := 0.0
	var swung := 0.0
	for t in 1800:
		game.sim.step()
		maxerr = maxf(maxerr, wpt(bar, 0.0, 3.0).distance_to(Vector2(350, 1020)))
		swung = maxf(swung, absf(state(bar)[2]))
	var st := state(bar)
	check(maxerr < 0.1, "the anchor stays within 0.1 cell of its place (%.3f)" % maxerr)
	check(swung > 1.0, "the bar swings down (peak angle %.2f)" % swung)
	check(absf(absf(st[2]) - PI * 0.5) < 0.12, "it hangs straight down after 30 s (angle %.2f)" % st[2])
	check(absf(st[5]) < 0.05, "and has stopped swinging (spin %.4f)" % st[5])
	check(game.sim.joint_count() == 1, "one joint left")


func scenario_b() -> void:
	print("B. Chain")
	fresh()
	var ids: Array = []
	for k in 10:
		ids.append(part(Rect2i(350 + k * 12, 1018, 12, 4)))
	joint(PIN, ids[0], 0, Vector2(350, 1020))
	for k in range(1, 10):
		joint(PIN, ids[k - 1], ids[k], Vector2(350 + k * 12, 1020))
	var maxgap := 0.0
	for t in 900:
		game.sim.step()
		for k in range(1, 10):
			maxgap = maxf(maxgap, wpt(ids[k - 1], 12.0, 2.0).distance_to(wpt(ids[k], 0.0, 2.0)))
	var tail := state(ids[9])
	check(maxgap < 3.0, "no gap opens past 3 cells (%.2f)" % maxgap)
	check(tail[1] - 1020.0 > 100.0, "it hangs to near its full 120 cells (%.0f)" % (tail[1] - 1020.0))
	check(game.sim.body_count() == 10, "no link broke (%d bodies)" % game.sim.body_count())


func scenario_c() -> void:
	print("C. Weld and Rope")
	fresh()
	var arm := part(Rect2i(300, 1100, 40, 6))
	var cap := part(Rect2i(340, 1100, 10, 30))
	joint(PIN, arm, 0, Vector2(300, 1103))
	joint(WELD, arm, cap, Vector2(340, 1103))
	var a0 := state(arm)[2]
	var d0 := state(cap)[2]
	ticks(600)
	check(absf((state(arm)[2] - state(cap)[2]) - (a0 - d0)) < 0.02, "a weld holds the angle between two bodies while they swing (%.3f)" % ((state(arm)[2] - state(cap)[2]) - (a0 - d0)))
	check(absf(state(arm)[2]) > 0.5, "and the pair did swing (%.2f)" % state(arm)[2])
	# Rope: a block on a 50 long rope under a driven anchor.
	fresh()
	fill(Rect2i(420, 1000, 80, 300), D.BEDROCK)
	var anchor := part(Rect2i(250, 1020, 10, 10))
	var block := part(Rect2i(245, 1050, 40, 20))
	var r: int = game.sim.add_joint({"type": ROPE, "a": anchor, "b": block, "ax": 255.0, "ay": 1030.0, "bx": 265.0, "by": 1050.0, "len": 50.0})
	var maxlen := 0.0
	var slack := 1e9
	for t in 600:
		game.sim.drive_body(anchor, 0.4 if t < 400 else 0.0, 0.0, 0.0)
		game.sim.step()
		var d := wpt(anchor, 5.0, 10.0).distance_to(wpt(block, 20.0, 0.0))
		maxlen = maxf(maxlen, d)
		slack = minf(slack, d)
	check(maxlen < 51.0, "the rope is never longer than 50 (%.2f)" % maxlen)
	check(slack < 40.0, "and goes slack when the ends come together (%.1f)" % slack)
	check(game.sim.joint_count() == 1, "it holds")
	check(game.sim.joint_state(r).size() == 5, "joint_state answers")


func bridge(limit: float) -> Array:
	var room := fresh()
	var ids: Array = []
	for k in 5:
		ids.append(part(Rect2i(300 + k * 30, 1100, 30, 6)))
	fill(Rect2i(280, 1090, 20, 210), D.BEDROCK)
	fill(Rect2i(450, 1090, 20, 210), D.BEDROCK)
	var js: Array = []
	var extra := {"rooted": true}
	if limit > 0.0:
		extra["max_load"] = limit
	js.append(joint(PIN, ids[0], 0, Vector2(299.5, 1103), extra))
	extra.erase("rooted")
	for k in range(1, 5):
		js.append(joint(PIN, ids[k - 1], ids[k], Vector2(300 + k * 30, 1103), extra))
	extra["rooted"] = true
	js.append(joint(PIN, ids[4], 0, Vector2(450.5, 1103), extra))
	return [ids, js, room]


## A slab pressed down on the bridge's middle from above (so it lands gently), then let go.
func load_bridge(ids: Array, ticks_n: int, with_slab := true) -> Dictionary:
	var slab := Rect2i(355, 1040, 40, 20)
	var sid := -1
	var sag := 0.0
	var peak := 0.0
	for t in ticks_n:
		if t == 60 and with_slab:
			fill(slab, D.STONE)
			sid = game.sim.make_body(slab.position.x, slab.position.y, slab.size.x, slab.size.y, 0.0, 0.0, 0.0)
			game.sim.set_module(sid, true)
		if sid > 0 and t < 200:
			game.sim.drive_body(sid, 0.0, 0.5, 0.0)
		game.sim.step()
		if state(ids[2]).size() > 0:
			sag = maxf(sag, state(ids[2])[1] - 1103.0)
		if t >= ticks_n - 100:
			for j in game.sim.joint_ids():
				peak = maxf(peak, game.sim.joint_state(j)[1])
	return {"sag": sag, "peak": peak}


func scenario_d() -> void:
	print("D. Bridge")
	var br := bridge(0.0)
	var ids: Array = br[0]
	var empty := load_bridge(ids, 400, false)
	print("  (empty bridge: sag %.1f, joint load %.1f)" % [empty["sag"], empty["peak"]])
	var r := load_bridge(ids, 665)
	print("  (800 cell slab: sag %.1f, peak joint load %.1f)" % [r["sag"], r["peak"]])
	check(game.sim.joint_count() == 6, "six pins hold an 800 cell slab")
	check(r["sag"] > 2.0 and r["sag"] < 40.0, "the bridge sags but holds (%.1f)" % r["sag"])
	check(r["peak"] > 1.3 * empty["peak"], "and the slab shows in the load (%.1f against %.1f)" % [r["peak"], empty["peak"]])
	var limit: float = (empty["peak"] + r["peak"]) * 0.5
	br = bridge(0.0)
	ticks(300)
	for j: int in game.sim.joint_ids():
		game.sim.set_joint(j, {"max_load": limit})
	ticks(200)
	check(game.sim.joint_count() == 6, "a settled empty bridge keeps all six under a load limit of %.0f" % limit)
	load_bridge(br[0], 665)
	check(game.sim.joint_count() < 6, "the slab takes some (%d left)" % game.sim.joint_count())
	var ev: PackedInt32Array = game.sim.take_joint_events()
	check(ev.size() >= 2 and ev[1] == 1, "and they are reported as snapped (%s)" % str(ev))


func scenario_e() -> void:
	print("E. Motor")
	fresh()
	var arm := part(Rect2i(350, 1017, 60, 6))
	var j := joint(MOTOR, arm, 0, Vector2(350, 1020), {"rate": 1.0})
	# Hold the arm up against gravity: it turns at 1 rad/s.
	var a0 := state(arm)[2]
	ticks(60)
	var a1 := state(arm)[2]
	check(absf((a1 - a0) - 1.0) < 0.15, "it turns about 1 radian a second (%.3f)" % (a1 - a0))
	# A ledge in the way: it stalls, does not wind on, and nothing is pushed into rock.
	fresh()
	var arm2 := part(Rect2i(350, 1017, 60, 6))
	var m2 := joint(MOTOR, arm2, 0, Vector2(350, 1020), {"rate": 1.0, "lag": 0.2})
	fill(Rect2i(345, 1070, 50, 6), D.BEDROCK)
	ticks(300)
	var s: PackedFloat32Array = game.sim.joint_state(m2)
	var ang := state(arm2)[2]
	var inside := 0
	for y in range(1060, 1090):
		for x in range(340, 400):
			if game.sim.get_owner(x, y) == arm2 and game.sim.get_cell(x, y) == D.BEDROCK:
				inside += 1
	check(absf(s[4] - s[2]) <= 0.21, "the motor's target does not run ahead of the arm (lead %.3f)" % (s[4] - s[2]))
	check(ang > 0.9 and ang < 1.6, "the arm stops against the ledge (angle %.2f)" % ang)
	check(inside == 0, "with no pixel of it inside the rock (%d)" % inside)
	var before := state(arm2)
	ticks(120)
	var after := state(arm2)
	check(absf(after[2] - before[2]) < 0.02 and absf(after[5]) < 0.6, "and it stays put, no jitter (%.4f)" % (after[2] - before[2]))
	# Reverse: it turns back the other way.
	game.sim.set_joint(m2, {"rate": -1.0})
	ticks(60)
	check(state(arm2)[2] < ang - 0.5, "reversing turns it back (%.2f)" % state(arm2)[2])
	game.sim.set_joint(m2, {"hold": true})
	var held := state(arm2)[2]
	ticks(90)
	check(absf(state(arm2)[2] - held) < 0.05, "hold stops it where it is (%.3f)" % (state(arm2)[2] - held))
	# A motor spinning round and round for a long time keeps its angle exact.
	fresh()
	var rotor := part(Rect2i(350, 1017, 40, 6))
	var mj := joint(MOTOR, rotor, 0, Vector2(370, 1020), {"rate": 6.0})
	ticks(1500)
	var ms: PackedFloat32Array = game.sim.joint_state(mj)
	check(absf(state(rotor)[2]) < 30.0, "the rotor's angle stays small after many turns (%.1f)" % state(rotor)[2])
	check(game.sim.joint_count() == 1 and absf(ms[4] - ms[2]) < 0.3, "and the motor still follows it (lead %.3f)" % (ms[4] - ms[2]))
	check(wpt(rotor, 20.0, 3.0).distance_to(Vector2(370, 1020)) < 0.1, "with its pivot in place")


func scenario_f() -> void:
	print("F. Slide")
	fresh()
	fill(Rect2i(300, 1000, 20, 300), D.BEDROCK)
	var cyl := part(Rect2i(320, 1100, 20, 10))
	var rod := part(Rect2i(340, 1102, 30, 6))
	# The cylinder is held by the world (a weld to it), the rod slides out along x.
	joint(WELD, cyl, 0, Vector2(320, 1105))
	var sj := joint(SLIDE, cyl, rod, Vector2(340, 1105), {"dx": 1.0, "dy": 0.0, "lo": 0.0, "hi": 30.0, "drive": true, "rate": 20.0, "goal": 0.0})
	ticks(60)
	check(absf(game.sim.joint_state(sj)[3]) < 0.5, "at goal 0 the rod rests where it was (%.2f)" % game.sim.joint_state(sj)[3])
	game.sim.set_joint(sj, {"goal": 25.0})
	ticks(90)
	var s: PackedFloat32Array = game.sim.joint_state(sj)
	check(absf(s[3] - 25.0) < 0.6, "it runs out to its goal (%.2f of 25)" % s[3])
	check(absf(state(rod)[1] - 1105.0) < 1.0, "and stays on the line (y %.2f)" % state(rod)[1])
	game.sim.set_joint(sj, {"goal": 90.0})
	ticks(120)
	check(game.sim.joint_state(sj)[3] <= 30.6, "the goal is held to the limit (%.2f of 30)" % game.sim.joint_state(sj)[3])
	game.sim.set_joint(sj, {"goal": 0.0})
	ticks(120)
	check(absf(game.sim.joint_state(sj)[3]) < 0.6, "and it comes back (%.2f)" % game.sim.joint_state(sj)[3])
	# A load on the rod's end is pushed out; a slab in the way stalls it without winding on.
	var block := part(Rect2i(372, 1090, 20, 20))
	joint(WELD, rod, block, Vector2(371, 1105))
	fill(Rect2i(400, 1080, 40, 40), D.BEDROCK)
	game.sim.set_joint(sj, {"goal": 30.0})
	ticks(200)
	var inrock := 0
	for y in range(1080, 1120):
		for x in range(400, 440):
			if game.sim.get_owner(x, y) == block and game.sim.get_cell(x, y) == D.BEDROCK:
				inrock += 1
	check(inrock == 0, "with none of the block inside the wall (%d)" % inrock)
	var s2: PackedFloat32Array = game.sim.joint_state(sj)
	check(s2[3] < 10.0 and s2[3] > 0.0, "a wall in the way stops the piston (%.2f out)" % s2[3])
	check(absf(s2[4] - s2[3]) <= 0.25, "with its target not far ahead (lead %.3f)" % (s2[4] - s2[3]))
	# A free slide (no drive) on a tilted rail: the carriage runs down it under gravity and stops at hi.
	fresh()
	var ang := 0.4
	var u := Vector2(cos(ang), sin(ang))
	var nrm := Vector2(-sin(ang), cos(ang))
	var rpx := PackedByteArray()
	rpx.resize(100 * 4)
	rpx.fill(D.STONE)
	var rail: int = game.sim.make_part(100, 4, rpx, 350.0, 1100.0, ang)
	joint(WELD, rail, 0, Vector2(350, 1100))
	var cpx := PackedByteArray()
	cpx.resize(10 * 10)
	cpx.fill(D.STONE)
	var start := Vector2(350, 1100) - u * 30.0
	var car: int = game.sim.make_part(10, 10, cpx, start.x + nrm.x * 7.0, start.y + nrm.y * 7.0, ang)
	var gj := joint(SLIDE, rail, car, start, {"dx": u.x, "dy": u.y, "lo": -5.0, "hi": 60.0})
	ticks(240)
	var gs: PackedFloat32Array = game.sim.joint_state(gj)
	check(absf(gs[3] - 60.0) < 1.5, "a carriage runs down a tilted rail and stops at hi (%.2f of 60)" % gs[3])
	var cs := state(car)
	var off := (Vector2(cs[0], cs[1]) - start).dot(nrm)
	check(absf(off - 7.0) < 1.0, "staying on the rail's line (%.2f from it, 7 to begin with)" % off)
	check(absf(cs[2] - ang) < 0.05, "and at the rail's angle (%.3f)" % cs[2])


func scenario_g() -> void:
	print("G. Assemblies")
	fresh()
	var a := part(Rect2i(350, 1290, 30, 10))
	var b := part(Rect2i(360, 1294, 30, 10))
	joint(PIN, a, b, Vector2(370, 1296))
	ticks(300)
	check(game.sim.body_count() == 2, "two overlapping bodies in one assembly do not break each other (%d bodies)" % game.sim.body_count())
	# A rope does not make an assembly: the two bump.
	fresh()
	var p := part(Rect2i(350, 1000, 20, 20))
	var q := part(Rect2i(355, 1040, 20, 20))
	game.sim.add_joint({"type": ROPE, "a": p, "b": q, "ax": 360.0, "ay": 1010.0, "bx": 365.0, "by": 1050.0, "len": 60.0})
	var fell := false
	for t in 200:
		game.sim.drive_body(p, 0.0, 0.0, 0.0)
		game.sim.step()
		if state(q).size() == 0:
			fell = true
	check(not fell and state(q)[1] > 1050.0, "a rope joins no assembly: the load falls its length (y %.0f)" % state(q)[1])


func scenario_h() -> void:
	print("H. Anchors and events")
	fresh()
	fill(Rect2i(340, 1000, 60, 100), D.STONE)
	var bar := part(Rect2i(370, 1100, 6, 60))
	var j := joint(PIN, bar, 0, Vector2(373, 1099.5), {"rooted": true})
	ticks(60)
	check(game.sim.joint_count() == 1, "a rooted anchor in stone holds")
	check(game.sim.take_joint_events().size() == 0, "and says nothing")
	for y in range(1085, 1100):
		for x in range(365, 382):
			game.sim.set_cell(x, y, D.AIR)
	ticks(2)
	check(game.sim.joint_count() == 0, "dig the stone away and it lets go")
	var ev: PackedInt32Array = game.sim.take_joint_events()
	check(ev.size() == 2 and ev[0] == j and ev[1] == 3, "the event names the joint and why (%s)" % str(ev))
	check(game.sim.take_joint_events().size() == 0, "events are taken once")
	# Removing a body drops its joints.
	fresh()
	var u := part(Rect2i(350, 1100, 20, 10))
	var v := part(Rect2i(370, 1100, 20, 10))
	var w := part(Rect2i(390, 1100, 20, 10))
	joint(PIN, u, v, Vector2(370, 1105))
	joint(PIN, v, w, Vector2(390, 1105))
	game.sim.remove_body(v)
	check(game.sim.joint_count() == 0, "removing a body drops both its joints")
	check(game.sim.take_joint_events().size() == 4, "and says so twice")
	# remove_joint ends an assembly: the bodies collide again.
	var k := joint(PIN, u, w, Vector2(380, 1105))
	check(game.sim.remove_joint(k), "remove_joint works")
	check(not game.sim.remove_joint(k), "and only once")
	check(game.sim.take_joint_events().size() == 0, "without an event")
	# A body shattered by a hard knock takes its joints.
	fresh()
	var rock := part(Rect2i(350, 1010, 30, 30), D.STONE)
	game.sim.set_module(rock, false)
	var holder := part(Rect2i(300, 1100, 20, 10))
	joint(PIN, holder, rock, Vector2(320, 1105))
	game.sim.drive_body(rock, 0.0, 9.0, 0.0)
	ticks(200)
	var ev2: PackedInt32Array = game.sim.take_joint_events()
	check(game.sim.joint_count() == 0 or state(rock).size() > 0, "a body that broke leaves no joint behind")
	check(game.sim.joint_count() == 0 or ev2.size() == 0, "(or it survived the knock)")


func scenario_i() -> void:
	print("I. Staying a body, dragging")
	fresh()
	var plank := part(Rect2i(350, 1100, 40, 6))
	game.sim.set_module(plank, false)
	var settled := part(Rect2i(300, 1100, 40, 6))
	game.sim.set_module(settled, false)
	joint(PIN, plank, 0, Vector2(350, 1103))
	ticks(1200)
	check(state(plank).size() > 0, "a jointed body does not settle into ground after 20 s")
	check(state(settled).size() == 0, "an unjointed one does")
	# A driven body drags a heavy block through a pin.
	fresh()
	var tug := part(Rect2i(250, 1100, 10, 10))
	var heavy := part(Rect2i(260, 1090, 60, 30))
	joint(PIN, tug, heavy, Vector2(260, 1105))
	for t in 200:
		game.sim.drive_body(tug, 0.3, 0.0, 0.0)
		game.sim.step()
	check(state(tug)[0] > 300.0, "the driven body moves on (x %.0f)" % state(tug)[0])
	check(absf(state(heavy)[0] - state(tug)[0]) < 60.0, "and the heavy block comes with it (gap %.0f)" % (state(heavy)[0] - state(tug)[0]))


func scenario_j() -> void:
	print("J. Save and determinism")
	var sums := []
	var runs := []
	for run in 2:
		fresh()
		var ids: Array = []
		for k in 10:
			ids.append(part(Rect2i(350 + k * 12, 1018, 12, 4)))
		joint(PIN, ids[0], 0, Vector2(350, 1020))
		for k in range(1, 10):
			joint(PIN, ids[k - 1], ids[k], Vector2(350 + k * 12, 1020))
		var m := part(Rect2i(230, 1200, 30, 6))
		joint(MOTOR, m, 0, Vector2(230, 1203), {"rate": 1.0})
		ticks(300)
		runs.append(ids)
		sums.append([game.sim.checksum(), state(ids[9])[0], state(ids[9])[1]])
		if run == 0:
			var blob: PackedByteArray = game.sim.save_state()
			var before: int = game.sim.joint_count()
			ticks(200)
			var ahead := [game.sim.checksum(), state(ids[9])[0], state(ids[9])[1]]
			check(game.sim.load_state(blob), "a save with joints loads")
			check(game.sim.joint_count() == before, "all %d joints came back" % before)
			ticks(200)
			var again := [game.sim.checksum(), state(ids[9])[0], state(ids[9])[1]]
			check(ahead == again, "and the run goes on exactly as it did")
	check(sums[0] == sums[1], "the same build twice gives the same checksum and poses")


func scenario_k() -> void:
	print("K. The body table")
	fresh()
	var made := 0
	for i in 810:
		var r := Rect2i(210 + (i % 100) * 2, 1010 + (i / 100) * 3, 2, 2)
		fill(r, D.STONE)
		if game.sim.make_body(r.position.x, r.position.y, r.size.x, r.size.y, 0.0, 0.0, 0.0) > 0:
			made += 1
	check(made == 800, "800 bodies can be made, no more (%d)" % made)
	check(game.sim.body_count() == 800, "the count agrees")
	var t0 := Time.get_ticks_usec()
	ticks(20)
	print("  (800 bodies: %.0f us a tick)" % ((Time.get_ticks_usec() - t0) / 20.0))
	fresh()
	# Parts from a bitmap.
	var px := PackedByteArray()
	px.resize(40 * 3)
	px.fill(D.STONE)
	var id: int = game.sim.make_part(40, 3, px, 300.0, 1100.0, 0.5)
	check(id > 0, "make_part builds a body from a bitmap")
	var st := state(id)
	check(absf(st[0] - 300.0) < 0.01 and absf(st[1] - 1100.0) < 0.01 and absf(st[2] - 0.5) < 0.01, "at the pose asked")
	var info: PackedFloat32Array = game.sim.body_info(id)
	check(int(info[4]) == 120, "with all its pixels (%d)" % int(info[4]))
	check(game.sim.get_owner(300, 1100) == id, "stamped into the grid")
	check(game.sim.make_part(4, 4, PackedByteArray(), 300.0, 1100.0, 0.0) == -1, "a bitmap of the wrong size is refused")
	# Churn: make and remove many bodies; lookups stay right.
	var live := {}
	for i in 300:
		var pid: int = game.sim.make_part(6, 6, PackedByteArray(range(36).map(func(_i): return D.STONE)), 220.0 + (i % 50) * 5.0, 1020.0 + (i / 50) * 7.0, 0.0)
		live[pid] = true
		if i % 3 == 0:
			var gone: int = live.keys()[0]
			game.sim.remove_body(gone)
			live.erase(gone)
	var ok := true
	for pid: int in live:
		if state(pid).size() != 10:
			ok = false
	check(ok, "after churn every live body is found by its id")
	check(state(0).size() == 0 and state(65535).size() == 0, "and ids nobody has are not")
