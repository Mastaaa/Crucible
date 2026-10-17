extends SceneTree
## SPIKE (throwaway): do position-based joints hold up against pixel ground?
## Run: godot --headless --path . --script tests/spike_joints.gd

const D = preload("res://scripts/defs.gd")
var game: Node
var f := 0


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		s1_pendulum()
		s2_chain()
		s3_bridge()
		s3b_bridge_snap()
		s4_motor()
		s5_cost()
		s6_determinism()
		s7_scale()
		s8_rope()
		s9_drag()
		return true
	return false


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func arena(r: Rect2i) -> void:
	fill(r.grow(20), D.BEDROCK)
	fill(r, D.AIR)


## A rigid body made of stone in the rectangle, held as a module so it never turns back into ground.
func part(r: Rect2i, m := D.STONE) -> int:
	fill(r, m)
	var id: int = game.sim.make_body(r.position.x, r.position.y, r.size.x, r.size.y, 0.0, 0.0, 0.0)
	game.sim.set_module(id, true)
	return id


func wpt(id: int, lx: float, ly: float) -> Vector2:
	var info: PackedFloat32Array = game.sim.body_info(id)
	var st: PackedFloat32Array = game.sim.body_state(id)
	var d := Vector2(lx - info[2], ly - info[3]).rotated(st[2])
	return Vector2(st[0], st[1]) + d


## Local (bitmap) point of a world point at the pose the body has now.
func lpt(id: int, w: Vector2) -> Vector2:
	var info: PackedFloat32Array = game.sim.body_info(id)
	var st: PackedFloat32Array = game.sim.body_state(id)
	return (w - Vector2(st[0], st[1])).rotated(-st[2]) + Vector2(info[2], info[3])


func pin(a: int, b: int, at: Vector2) -> int:
	return game.sim.add_joint(a, at.x, at.y, b, at.x, at.y, 0, 0.0, 0.0)


func ticks(n: int) -> void:
	for i in n:
		game.sim.step()


func s1_pendulum() -> void:
	print("S1 pendulum: 60x6 stone bar pinned at its left end to the world, released horizontal")
	fresh()
	var room := Rect2i(200, 1000, 300, 300)
	arena(room)
	var bar := part(Rect2i(350, 1017, 60, 6))
	var j: int = game.sim.add_joint(bar, 350.0, 1020.0, 0, 350.0, 1020.0, 0, 0.0, 0.0)
	var maxerr := 0.0
	var line := ""
	for t in range(1, 721):
		game.sim.step()
		var info: PackedFloat32Array = game.sim.body_info(bar)
		var st: PackedFloat32Array = game.sim.body_state(bar)
		# the left end of the bar in its bitmap is (0, 3)
		var err := wpt(bar, 0.0, 3.0).distance_to(Vector2(350, 1020))
		maxerr = maxf(maxerr, err)
		if t % 60 == 0:
			line += " %.2f" % st[2]
	var st2: PackedFloat32Array = game.sim.body_state(bar)
	print("  angle each second (rad):%s" % line)
	print("  max anchor error %.3f cells; final angle %.2f; strain now %s; bodies %d" % [maxerr, st2[2], str(game.sim.joint_state(j)), game.sim.body_count()])


func s2_chain() -> void:
	print("S2 chain: 10 links 12x4, head pinned, hanging then swung")
	fresh()
	var room := Rect2i(200, 1000, 300, 300)
	arena(room)
	var ids: Array = []
	for k in 10:
		ids.append(part(Rect2i(350 + k * 12, 1018, 12, 4)))
	pin(ids[0], 0, Vector2(350, 1020))
	for k in range(1, 10):
		pin(ids[k - 1], ids[k], Vector2(350 + k * 12, 1020))
	var maxgap := 0.0
	var peak_strain := 0.0
	for t in range(1, 901):
		game.sim.step()
		for k in range(1, 10):
			var a := wpt(ids[k - 1], 12.0, 2.0)
			var b := wpt(ids[k], 0.0, 2.0)
			maxgap = maxf(maxgap, a.distance_to(b))
	var tail: PackedFloat32Array = game.sim.body_state(ids[9])
	var head := wpt(ids[0], 0.0, 2.0)
	print("  max gap between links %.3f cells over 900 ticks; tail at (%.0f, %.0f), head anchor off by %.3f" % [maxgap, tail[0], tail[1], head.distance_to(Vector2(350, 1020))])
	print("  hangs: tail below head by %.0f of 120 cells; bodies %d, joints %d" % [tail[1] - 1020.0, game.sim.body_count(), game.sim.joint_count()])


func s3_bridge() -> void:
	print("S3 bridge: 5 planks 30x6 between two bedrock pillars; a 40x20 stone slab (800 cells) dropped on the middle")
	fresh()
	var room := Rect2i(200, 1000, 300, 300)
	arena(room)
	var ids: Array = []
	for k in 5:
		ids.append(part(Rect2i(300 + k * 30, 1100, 30, 6)))
	fill(Rect2i(280, 1090, 20, 210), D.BEDROCK)
	fill(Rect2i(450, 1090, 20, 210), D.BEDROCK)
	var js: Array = []
	js.append(pin(ids[0], 0, Vector2(300, 1103)))
	for k in range(1, 5):
		js.append(pin(ids[k - 1], ids[k], Vector2(300 + k * 30, 1103)))
	js.append(pin(ids[4], 0, Vector2(450, 1103)))
	var sag := 0.0
	var peak := 0.0
	for t in range(1, 721):
		game.sim.step()
		if t == 120:
			var slab := Rect2i(355, 1040, 40, 20)
			fill(slab, D.STONE)
			game.sim.make_body(slab.position.x, slab.position.y, slab.size.x, slab.size.y, 0.0, 0.0, 0.0)
		var mid: PackedFloat32Array = game.sim.body_state(ids[2])
		sag = maxf(sag, mid[1] - 1103.0)
		for j in js:
			var s: PackedFloat32Array = game.sim.joint_state(j)
			if s.size() > 0:
				peak = maxf(peak, s[0])
	var mid2: PackedFloat32Array = game.sim.body_state(ids[2])
	print("  mid plank sag peak %.1f cells, now %.1f; peak joint strain %.2f; joints left %d of 6; bodies %d" % [sag, mid2[1] - 1103.0, peak, game.sim.joint_count(), game.sim.body_count()])


func s3b_bridge_snap() -> void:
	print("S3b bridge with a strain limit of 0.8 on every joint: does it snap under the slab?")
	fresh()
	var room := Rect2i(200, 1000, 300, 300)
	arena(room)
	var ids: Array = []
	for k in 5:
		ids.append(part(Rect2i(300 + k * 30, 1100, 30, 6)))
	fill(Rect2i(280, 1090, 20, 210), D.BEDROCK)
	fill(Rect2i(450, 1090, 20, 210), D.BEDROCK)
	var js: Array = []
	js.append(pin(ids[0], 0, Vector2(300, 1103)))
	for k in range(1, 5):
		js.append(pin(ids[k - 1], ids[k], Vector2(300 + k * 30, 1103)))
	js.append(pin(ids[4], 0, Vector2(450, 1103)))
	for j in js:
		game.sim.set_joint_limit(j, 0.8)
	for t in range(1, 361):
		game.sim.step()
		if t == 120:
			var slab := Rect2i(355, 1040, 40, 20)
			fill(slab, D.STONE)
			game.sim.make_body(slab.position.x, slab.position.y, slab.size.x, slab.size.y, 0.0, 0.0, 0.0)
	print("  joints left %d of 6 after the drop; bodies %d" % [game.sim.joint_count(), game.sim.body_count()])


func s4_motor() -> void:
	print("S4 motor arm: 60x6 arm hinged to the world, motor 1 rad/s, a bedrock stop in its path, and a loose slab")
	fresh()
	var room := Rect2i(200, 1000, 300, 300)
	arena(room)
	var arm := part(Rect2i(350, 1017, 60, 6))
	var j: int = game.sim.add_joint(arm, 350.0, 1020.0, 0, 350.0, 1020.0, 2, 0.0, 1.0)
	# the arm swings down through a quarter turn and meets a ledge
	fill(Rect2i(345, 1070, 50, 6), D.BEDROCK)
	var slab := Rect2i(352, 1055, 30, 10)
	fill(slab, D.STONE)
	var sid: int = game.sim.make_body(slab.position.x, slab.position.y, slab.size.x, slab.size.y, 0.0, 0.0, 0.0)
	var maxerr := 0.0
	var line := ""
	var peak := 0.0
	for t in range(1, 721):
		game.sim.step()
		maxerr = maxf(maxerr, wpt(arm, 0.0, 3.0).distance_to(Vector2(350, 1020)))
		var s: PackedFloat32Array = game.sim.joint_state(j)
		peak = maxf(peak, s[0])
		if t % 60 == 0:
			var st: PackedFloat32Array = game.sim.body_state(arm)
			line += " %.2f" % st[2]
	var tip := wpt(arm, 60.0, 3.0)
	var inside := 0
	for y in range(1060, 1090):
		for x in range(340, 400):
			if game.sim.get_owner(x, y) == arm and game.sim.get_cell(x, y) == D.BEDROCK:
				inside += 1
	print("  arm angle each second:%s; max anchor error %.3f; peak strain %.2f; tip at (%.0f, %.0f)" % [line, maxerr, peak, tip.x, tip.y])
	var sst: PackedFloat32Array = game.sim.body_state(sid)
	print("  loose slab: %s; arm cells embedded in bedrock: %d" % [("still a body at (%.0f, %.0f)" % [sst[0], sst[1]]) if sst.size() > 0 else "back in the ground", inside])


func s5_cost() -> void:
	print("S5 cost: 15 chains of 10 links (150 bodies, 150 joints) against the same bodies unjointed")
	var results := []
	for jointed in [false, true]:
		fresh()
		var room := Rect2i(100, 1000, 700, 400)
		arena(room)
		var ids: Array = []
		for c in 15:
			var row: Array = []
			for k in 10:
				row.append(part(Rect2i(120 + c * 40, 1020 + k * 8, 20, 4) if false else Rect2i(120 + c * 44, 1020 + k * 14, 10, 4)))
			ids.append(row)
		if jointed:
			for c in 15:
				game.sim.add_joint(ids[c][0], 125.0 + c * 44 - 120 + 120, 1020.0, 0, 125.0 + c * 44, 1020.0, 0, 0.0, 0.0)
				for k in range(1, 10):
					var at := Vector2(125.0 + c * 44, 1020 + k * 14 - 5)
					pin(ids[c][k - 1], ids[c][k], at)
		if not jointed:
			for row in ids:
				for id in row:
					game.sim.drive_body(id, 0.0, 0.0, 0.0)
		else:
			ticks(120)
		var t0 := Time.get_ticks_usec()
		for i in 300:
			if not jointed:
				for row in ids:
					for id in row:
						game.sim.drive_body(id, 0.0, 0.0, 0.0)
			game.sim.step()
		var dt := (Time.get_ticks_usec() - t0) / 300.0
		results.append(dt)
		print("  %s: %.0f us a tick (bodies %d, joints %d)" % ["jointed, free" if jointed else "plain, held in place", dt, game.sim.body_count(), game.sim.joint_count()])


func s6_determinism() -> void:
	print("S6 determinism: the chain twice from a fresh game")
	var sums := []
	for run in 2:
		fresh()
		arena(Rect2i(200, 1000, 300, 300))
		var ids: Array = []
		for k in 10:
			ids.append(part(Rect2i(350 + k * 12, 1018, 12, 4)))
		pin(ids[0], 0, Vector2(350, 1020))
		for k in range(1, 10):
			pin(ids[k - 1], ids[k], Vector2(350 + k * 12, 1020))
		ticks(400)
		var st: PackedFloat32Array = game.sim.body_state(ids[9])
		sums.append([game.sim.checksum(), st[0], st[1], st[2]])
	print("  run 1 %s" % str(sums[0]))
	print("  run 2 %s" % str(sums[1]))
	print("  identical: %s" % str(sums[0] == sums[1]))


func s7_scale() -> void:
	print("S7 scale: N bodies of 10x4 held in place, each pinned to the next in rows of 10 (joints = N - N/10), us per tick")
	for n in [0, 150, 400, 800]:
		fresh()
		var room := Rect2i(100, 1000, 700, 400)
		arena(room)
		var ids: Array = []
		for i in n:
			ids.append(part(Rect2i(120 + (i % 10) * 12, 1010 + (i / 10) * 6, 10, 4)))
		for i in n:
			if i % 10 != 0:
				game.sim.add_joint(ids[i - 1], 120.0 + (i % 10) * 12 - 1.0, 1012.0 + (i / 10) * 6, ids[i], 120.0 + (i % 10) * 12 - 1.0, 1012.0 + (i / 10) * 6, 0, 0.0, 0.0)
		ticks(60)
		var t0 := Time.get_ticks_usec()
		for i in 240:
			for id in ids:
				game.sim.drive_body(id, 0.0, 0.0, 0.0)
			game.sim.step()
		print("  %d bodies, %d joints: %.0f us a tick" % [game.sim.body_count(), game.sim.joint_count(), (Time.get_ticks_usec() - t0) / 240.0])


func s8_rope() -> void:
	print("S8 rope: a 40x20 block 20 below a held anchor, rope 50 long, anchor driven toward a wall")
	fresh()
	var room := Rect2i(200, 1000, 300, 300)
	arena(room)
	fill(Rect2i(420, 1000, 80, 300), D.BEDROCK)
	var anchor := part(Rect2i(250, 1020, 10, 10))
	var block := part(Rect2i(245, 1050, 40, 20))
	var j: int = game.sim.add_joint(anchor, 255.0, 1030.0, block, 265.0, 1050.0, 1, 50.0, 0.0)
	var maxlen := 0.0
	var peak := 0.0
	var line := ""
	for t in range(1, 601):
		game.sim.drive_body(anchor, 0.4 if t < 400 else 0.0, 0.0, 0.0)
		game.sim.step()
		var a := wpt(anchor, 5.0, 10.0)
		var b := wpt(block, 20.0, 0.0)
		maxlen = maxf(maxlen, a.distance_to(b))
		var s: PackedFloat32Array = game.sim.joint_state(j)
		if s.size() > 0:
			peak = maxf(peak, s[0])
		if t % 100 == 0:
			line += " %.0f" % a.distance_to(b)
	var ast: PackedFloat32Array = game.sim.body_state(anchor)
	print("  rope end to end each 100 ticks:%s; max %.1f of 50; peak strain %.2f; anchor stopped at x %.0f (wall at 420)" % [line, maxlen, peak, ast[0]])


func s9_drag() -> void:
	print("S9 drag into rock: a held anchor driven right pulls a hinged 60x6 bar into a bedrock wall")
	fresh()
	var room := Rect2i(200, 1000, 300, 300)
	arena(room)
	fill(Rect2i(420, 1000, 80, 300), D.BEDROCK)
	var anchor := part(Rect2i(300, 1017, 10, 6))
	var bar := part(Rect2i(310, 1017, 60, 6))
	var j: int = game.sim.add_joint(anchor, 310.0, 1020.0, bar, 310.0, 1020.0, 0, 0.0, 0.0)
	var peak := 0.0
	var maxerr := 0.0
	var jitter := 0.0
	var last := Vector2.ZERO
	for t in range(1, 901):
		game.sim.drive_body(anchor, 0.5 if t < 300 else 0.0, 0.0, 0.0)
		game.sim.step()
		var a := wpt(anchor, 10.0, 3.0)
		var b := wpt(bar, 0.0, 3.0)
		maxerr = maxf(maxerr, a.distance_to(b))
		var s: PackedFloat32Array = game.sim.joint_state(j)
		if s.size() > 0:
			peak = maxf(peak, s[0])
		var st: PackedFloat32Array = game.sim.body_state(bar)
		if t > 500:
			jitter = maxf(jitter, Vector2(st[0], st[1]).distance_to(last))
		last = Vector2(st[0], st[1])
	var ast: PackedFloat32Array = game.sim.body_state(anchor)
	var bst: PackedFloat32Array = game.sim.body_state(bar)
	print("  anchor stopped at x %.0f; bar centre (%.0f, %.0f) angle %.2f; max pin separation %.2f; peak strain %.2f; joint %s; per-tick wobble after 500 ticks %.3f" % [ast[0], bst[0], bst[1], bst[2], maxerr, peak, "kept" if game.sim.joint_count() > 0 else "gone", jitter])
