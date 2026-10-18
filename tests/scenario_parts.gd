extends SceneTree
## A8 part 2: joints in the game (scripts/machines/joints.gd), on Test Plates under a bedrock ceiling.
##  A. a hinge to the world: a plate swings from it and the pin holds; detach lets it fall
##  B. a bolt makes a rig of two plates that stay as they were; a hinge or a rope does not; the rig walk
##     stops at those
##  C. taking a module down clears its joints, records and engine alike
##  D. a joint rooted in thin air lets go at once and says so
##  E. attach points: edges, corners, the definition's own; a click takes the nearest or the surface
##  F. a save keeps the joints and the plate goes on hanging
## Run: godot --headless --path . --script tests/scenario_parts.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const MU = preload("res://scripts/machines/mu.gd")
const JT = preload("res://scripts/machines/joints.gd")
const Save = preload("res://scripts/save.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200
const PIN := Vector2(421.0, 98.5)       # in the ceiling, a little above the first plate's top left


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
	fill(Rect2i(328, SURFACE - 140, 144, 140), D.AIR)
	fill(Rect2i(328, SURFACE, 144, 160), 6)
	fill(Rect2i(328, SURFACE + 160, 144, 40), D.BEDROCK)
	fill(Rect2i(370, 90, 100, 10), D.BEDROCK)      # the ceiling: rows 90 to 99


func plate(x: int, y: int) -> int:
	var id := MC.place(game, "test_plate", Vector2i(x, y), 0)
	if id == 0:
		print("  !! can't place a plate at %d,%d: %s" % [x, y, MC.check_place(game, "test_plate", Vector2i(x, y), 0)])
	return id


func pos(id: int) -> Vector2:
	var st: PackedFloat32Array = game.sim.body_state(game.modules[id]["body"])
	return Vector2(st[0], st[1]) if st.size() >= 2 else Vector2(-1.0, -1.0)


## Runs up to `limit` seconds a tick at a time, true if the banner reads `text` at some point.
func banner_says(text: String, limit: float) -> bool:
	game.banner_text = ""
	for _i in int(limit * 60.0):
		game.run_ticks(1)
		if game.banner_text.contains(text):
			return true
	return false


func pin_gap(jid: int) -> float:
	var a: Array = JT.anchors(game, jid)
	return (a[0] as Vector2).distance_to(a[1]) if a.size() == 2 else 999.0


func scenario_a() -> void:
	print("A. hinge to the world")
	fresh()
	var p := plate(421, 101)
	var j := JT.attach(game, "hinge", p, 0, PIN)
	check(j > 0 and game.joints.has(j) and game.sim.joint_count() == 1, "the hinge is made and counted")
	check(JT.of_module(game, p) == [j], "the plate knows it")
	secs(4.0)
	check(game.joints.has(j) and game.sim.joint_count() == 1, "it holds the plate")
	check(pin_gap(j) < 1.5, "the pin stays put (%.2f cells apart)" % pin_gap(j))
	var a: float = game.sim.body_state(game.modules[p]["body"])[2]
	check(absf(a) > 1.0, "and the plate has swung down from it (%.2f rad)" % a)
	check(pos(p).y > 108.0, "to hang below the ceiling (centre at y %.1f)" % pos(p).y)
	check(JT.state(game, j).has("strain"), "the engine reports its strain")
	check(JT.detach(game, j) and game.sim.joint_count() == 0 and not JT.detach(game, j), "a detach takes it away, once")
	var y0 := pos(p).y
	secs(0.2)
	check(game.modules.has(p) and pos(p).y > y0 + 3.0, "and the plate falls (y %.1f to %.1f)" % [y0, pos(p).y])


func scenario_b() -> void:
	print("B. bolts, hinges, ropes")
	fresh()
	var p1 := plate(421, 101)
	var p2 := plate(421, 109)
	var p3 := plate(421, 117)
	var hinge := JT.attach(game, "hinge", p1, 0, PIN)
	var bolt := JT.attach(game, "bolt", p1, p2, Vector2(440, 108.0))
	var rope := JT.attach(game, "rope", p2, p3, Vector2(440, 115.0))
	check(hinge > 0 and bolt > 0 and rope > 0, "a hinge, a bolt and a rope are made")
	var off0 := pos(p2) - pos(p1)
	secs(4.0)
	var off1 := pos(p2) - pos(p1)
	check(off0.distance_to(off1) < 1.5 or absf(off0.length() - off1.length()) < 1.5, "the bolted plates keep their distance (%.1f, was %.1f)" % [off1.length(), off0.length()])
	check(JT.rigid_partners(game, p1) == [p2] and JT.rigid_partners(game, p2) == [p1], "each is the other's rigid partner")
	check(MU.rig(game, p1, 0).has(p2) and MU.rig(game, p2, 0).has(p1), "a rig walk crosses the bolt both ways")
	check(not MU.rig(game, p1, 0).has(p3), "and stops at the rope")
	check(MU.rig(game, p3, 0) == [p3], "a plate on a rope alone is its own rig")
	check(not MU.rig(game, p1, p2).has(p2), "the stop is kept")
	var h2 := JT.attach(game, "hinge", p3, p1, Vector2(440, 123.0))
	check(not JT.rigid_partners(game, p1).has(p3) and not MU.rig(game, p3, 0).has(p1) and h2 > 0, "a hinge is not rigid either")
	check(JT.attach(game, "bolt", p1, p1, Vector2(430, 104)) == 0, "a module can't be bolted to itself")
	check(JT.attach(game, "bolt", p1, 99, Vector2(430, 104)) == 0, "or to one that isn't there")
	check(JT.attach(game, "weld", p1, p2, Vector2(430, 104)) == 0, "or by a kind that doesn't exist")


func scenario_c() -> void:
	print("C. taking a module down")
	fresh()
	var p1 := plate(421, 101)
	var p2 := plate(421, 109)
	JT.attach(game, "hinge", p1, 0, PIN)
	var bolt := JT.attach(game, "bolt", p1, p2, Vector2(440, 108.0))
	check(game.joints.size() == 2 and game.sim.joint_count() == 2, "two joints to start")
	MC.remove(game, p2)
	check(not game.joints.has(bolt) and game.joints.size() == 1, "removing the second plate clears the bolt's record")
	check(game.sim.joint_count() == 1, "and the engine's joint")
	MC.remove(game, p1)
	check(game.joints.is_empty() and game.sim.joint_count() == 0, "removing the first clears the hinge")
	MC.reset(game)
	check(game.joints.is_empty() and game.next_joint == 1, "a reset starts the numbering over")


func scenario_d() -> void:
	print("D. nothing to hold on to")
	fresh()
	var p := plate(421, 101)
	var j := JT.attach(game, "hinge", p, 0, Vector2(421.0, 130.5))      # open air
	check(banner_says("lost its hold", 1.0), "a hinge rooted in air lets go and the player is told")
	check(not game.joints.has(j), "and its record goes")
	var q := plate(421, 120)
	var b := JT.attach(game, "bolt", p, q, Vector2(440, 117.0), Vector2(440, 117.0), {"limit": 0.5, "max_load": 0.5})
	check(b > 0 and banner_says("snapped", 2.0) and not game.joints.has(b), "a bolt pulled past its limit snaps and says so")


func scenario_e() -> void:
	print("E. attach points")
	fresh()
	var p := plate(421, 101)
	var pts: Array = JT.points(game, game.modules[p])
	check(pts.size() == 8, "a plate offers its four edges and four corners (%d)" % pts.size())
	var found := false
	for pt: Dictionary in pts:
		if (pt["pos"] as Vector2).distance_to(Vector2(441.0, 101.0)) < 1.0 and pt["kind"] == "edge":
			found = true
	check(found, "the middle of the top edge is one")
	var s := JT.snap(game, Vector2(422.0, 101.5))
	check(s.get("module", 0) == p and s["kind"] == "corner", "a click near a corner takes it (%s)" % s.get("kind", "?"))
	s = JT.snap(game, Vector2(430.0, 105.0))
	check(s.get("module", 0) == p and s["kind"] == "surface", "a click on the plate takes its surface (%s)" % s.get("kind", "?"))
	check(JT.snap(game, Vector2(400.0, 150.0)).is_empty(), "and one in the open takes nothing")
	# A definition's own attach entries come with it.
	MC.defs["test_plate"]["attach"] = [{"face": "hook", "kind": "anchor"}]
	check(JT.points(game, game.modules[p]).size() == 8, "an attach entry naming no face is ignored")
	MC.defs["test_plate"].erase("attach")
	var box := MC.place(game, "test_box", Vector2i(380, 140), 0)
	var bp: Array = JT.points(game, game.modules[box])
	check(bp.size() == 12, "a box also offers its four faces (%d)" % bp.size())
	MC.defs["test_box"]["attach"] = [{"face": "power", "kind": "hookup"}]
	bp = JT.points(game, game.modules[box])
	check(bp.size() == 13 and bp[12]["kind"] == "hookup" and bp[12]["name"] == "power", "and a listed attach point is added with its kind")
	MC.defs["test_box"].erase("attach")


func scenario_f() -> void:
	print("F. save")
	fresh()
	var p := plate(421, 101)
	var j := JT.attach(game, "hinge", p, 0, PIN)
	secs(2.0)
	var path := "user://parts_test.save"
	Save.write(game, path)
	game.continue_run(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.paused = true
	check(game.joints.has(j) and game.joints[j]["kind"] == "hinge" and game.next_joint == j + 1, "the record loads back")
	check(game.sim.joint_count() == 1 and not JT.state(game, j).is_empty(), "so does the engine's joint")
	secs(3.0)
	check(game.joints.has(j) and pin_gap(j) < 1.5, "and it goes on holding (%.2f)" % pin_gap(j))
	var a: float = game.sim.body_state(game.modules[p]["body"])[2]
	check(absf(a) > 1.0, "with the plate hanging from it (%.2f rad)" % a)
