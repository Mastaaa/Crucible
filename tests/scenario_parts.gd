extends SceneTree
## A8 part 2: joints in the game (scripts/machines/joints.gd), on Test Plates under a bedrock ceiling.
##  A. a hinge to the world: a plate swings from it and the pin holds; detach lets it fall
##  B. a bolt makes a rig of two plates that stay as they were; a hinge or a rope does not; the rig walk
##     stops at those
##  C. taking a module down clears its joints, records and engine alike
##  D. a joint rooted in thin air lets go at once and says so
##  E. attach points: edges, corners, the definition's own; a click takes the nearest or the surface
##  F. a save keeps the joints and the plate goes on hanging
##  G. the tools: Bolt, Hinge and Piton need their research, join what is under the click, cost Stone, and
##     a second click on a joint takes it off and gives the Stone back
##  I. the line tools: a Rope holds a plate under the ceiling; a Strut bolted rock to rock carries a plate, is
##     refused when too long or held nowhere, comes down for most of its price, and survives a save
##  H. the Motor: a click sets it turning right, left or holding; it draws power, turns the plate, and holds
##     when the power runs out
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
		scenario_g()
		scenario_h()
		scenario_i()
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


func click(kind: String, at: Vector2i) -> void:
	game.joint_pick = kind
	MC.click(game, at)
	game.joint_pick = ""


func scenario_g() -> void:
	print("G. the tools")
	fresh()
	game.stock[D.R_STONE] = 20.0
	var p1 := plate(421, 101)
	var p2 := plate(421, 109)
	check(not JT.unlocked(game, "bolt") and not JT.unlocked(game, "motor"), "the tools wait for their research")
	game.researched["joints"] = true
	check(JT.unlocked(game, "bolt") and JT.unlocked(game, "hinge") and JT.unlocked(game, "piton") and not JT.unlocked(game, "motor"), "Joints opens the bolt, hinge and piton")
	click("bolt", Vector2i(440, 300))
	check(game.joints.is_empty() and game.banner_text.contains("Nothing"), "a click on nothing joins nothing (%s)" % game.banner_text)
	click("bolt", Vector2i(440, 108))
	check(game.joints.size() == 1, "a click between two plates joins them")
	var j: Dictionary = game.joints.values()[0]
	check(j["kind"] == "bolt" and ((j["a"] == p1 and j["b"] == p2) or (j["a"] == p2 and j["b"] == p1)), "with a bolt")
	check(absf(game.stock[D.R_STONE] - 19.0) < 0.01, "for a Stone")
	check(MU.rig(game, p1, 0).has(p2), "and the rig walk crosses it")
	click("hinge", Vector2i(440, 108))
	check(game.joints.is_empty() and absf(game.stock[D.R_STONE] - 20.0) < 0.01, "a click on a joint takes it off and gives the Stone back")
	click("hinge", Vector2i(425, 98))
	check(game.joints.size() == 1 and game.joints.values()[0]["b"] == 0, "a plate beside the rock is hinged to the rock")
	game.stock[D.R_STONE] = 0.0
	click("hinge", Vector2i(440, 108))
	check(game.joints.size() == 1 and game.banner_text.contains("Stone"), "and with no Stone nothing is made (%s)" % game.banner_text)
	game.stock[D.R_STONE] = 20.0
	click("piton", Vector2i(440, 108))
	check(game.joints.size() == 1 and game.banner_text.contains("rock"), "a piton wants rock (%s)" % game.banner_text)
	click("piton", Vector2i(450, 99))
	check(game.joints.size() == 2, "and takes hold where the plate meets it")
	secs(3.0)
	var still := pos(p1)
	secs(1.0)
	check(pos(p1).distance_to(still) < 0.3 and game.joints.size() == 2, "a pitoned plate hangs still")
	game.joint_pick = "bolt"
	game.cancel_tool()
	check(game.joint_pick == "", "cancelling the tool puts it down")


## The cell a joint's anchor is in now.
func spot(jid: int) -> Vector2i:
	var a: Array = JT.anchors(game, jid)
	return Vector2i(int(floor(a[0].x)), int(floor(a[0].y)))


func scenario_h() -> void:
	print("H. the Motor")
	fresh()
	game.researched["joints"] = true
	game.researched["motor"] = true
	game.stock[D.R_STONE] = 20.0
	game.stock[D.R_POWER] = 90.0
	var p1 := plate(421, 101)
	var p2 := plate(421, 109)
	var hold := JT.attach(game, "hinge", p1, 0, PIN)      # p1 hangs from the ceiling at its corner
	var mot := JT.attach(game, "motor", p2, p1, Vector2(441.0, 108.0))
	check(mot > 0 and hold > 0, "a hinge and a motor are made")
	secs(2.0)
	var a0: float = JT.state(game, mot)["angle"]
	secs(2.0)
	check(absf(float(JT.state(game, mot)["angle"]) - a0) < 0.05, "an idle motor holds its angle")
	check(JT.use(game, spot(mot)) and game.joints[mot]["mode"] == 1, "a click sets it turning right")
	var used := 0.0
	for _i in 120:
		var u0: float = game.used_acc
		game.run_ticks(1)
		var u1: float = game.used_acc
		used += u1 - u0 if u1 >= u0 else u1
	var a1: float = JT.state(game, mot)["angle"]
	check(a1 - a0 > 0.8, "it turns (%.2f rad in 2 s)" % (a1 - a0))
	check(used > 0.05, "and draws power (%.3f)" % used)
	JT.use(game, spot(mot))
	check(game.joints[mot]["mode"] == -1, "a second click reverses it")
	secs(2.0)
	check(float(JT.state(game, mot)["angle"]) < a1 - 0.8, "and it turns back")
	JT.use(game, spot(mot))
	check(game.joints[mot]["mode"] == 0, "a third click holds it")
	var a2: float = JT.state(game, mot)["angle"]
	secs(2.0)
	check(absf(float(JT.state(game, mot)["angle"]) - a2) < 0.1, "still")
	JT.use(game, spot(mot))
	for _i in 30:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	var a3: float = JT.state(game, mot)["angle"]
	for _i in 120:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(absf(float(JT.state(game, mot)["angle"]) - a3) < 0.1, "with no power it stops where it is")
	game.stock[D.R_POWER] = 50.0
	secs(2.0)
	check(float(JT.state(game, mot)["angle"]) - a3 > 0.5, "and goes on when the power returns")
	check(not JT.use(game, Vector2i(400, 150)), "a click away from a motor does nothing")


func two_clicks(kind: String, a: Vector2i, b: Vector2i) -> void:
	game.joint_pick = kind
	MC.click(game, a)
	MC.click(game, b)
	game.joint_pick = ""


func struts() -> Array:
	var out: Array = []
	for id: int in game.modules:
		if (game.modules[id]["def"] as String).begins_with("strut_"):
			out.append(id)
	return out


func scenario_i() -> void:
	print("I. Struts and Ropes")
	fresh()
	game.researched["joints"] = true
	game.stock[D.R_STONE] = 30.0
	var pl := plate(421, 101)
	two_clicks("rope", Vector2i(425, 98), Vector2i(425, 103))
	check(game.joints.is_empty() and game.banner_text.contains("locked") == false, "a rope wants its research (%s)" % game.banner_text)
	game.researched["rope"] = true
	game.researched["strut"] = true
	game.joint_pick = "rope"
	MC.click(game, Vector2i(425, 98))
	check(not game.joint_from.is_empty(), "the first click holds the rope's start")
	game.cancel_tool()
	check(game.joint_from.is_empty(), "cancelling lets go of it")
	two_clicks("rope", Vector2i(425, 98), Vector2i(425, 103))
	check(game.joints.size() == 1 and game.joints.values()[0]["kind"] == "rope", "a rope from the ceiling to the plate")
	check(absf(game.stock[D.R_STONE] - 29.0) < 0.01, "for a Stone")
	secs(4.0)
	var rj: int = game.joints.keys()[0]
	var gap := pin_gap(rj)
	check(game.joints.has(rj) and gap > 2.0 and gap < 8.0, "it holds the plate hanging (%.1f cells)" % gap)
	check(pos(pl).y > 105.0 and pos(pl).y < 135.0, "short of the floor (y %.1f)" % pos(pl).y)
	two_clicks("rope", Vector2i(425, 98), Vector2i(425, 98))
	check(game.joints.size() == 1, "a rope of no length is refused (%s)" % game.banner_text)
	two_clicks("rope", Vector2i(380, 95), Vector2i(380, 96))
	check(game.joints.size() == 1, "and a rope from rock to rock (%s)" % game.banner_text)
	game.joint_pick = "rope"
	MC.click(game, spot(rj))
	check(game.joints.size() == 0 and absf(game.stock[D.R_STONE] - 30.0) < 0.01, "a click on a rope's anchor takes it off and refunds it")

	# A Strut across a gap, rock to rock.
	fresh()
	game.researched["joints"] = true
	game.researched["strut"] = true
	game.stock[D.R_STONE] = 30.0
	fill(Rect2i(380, 120, 12, 40), D.BEDROCK)
	fill(Rect2i(448, 120, 12, 40), D.BEDROCK)
	two_clicks("strut", Vector2i(391, 140), Vector2i(448, 140))
	var st := struts()
	check(st.size() == 1, "a strut is built across the gap (%s)" % game.banner_text)
	if st.is_empty():
		return
	var sid: int = st[0]
	var bolts := 0
	for jid: int in game.joints:
		if game.joints[jid]["kind"] == "bolt" and game.joints[jid]["a"] == sid and game.joints[jid]["b"] == 0:
			bolts += 1
	check(bolts == 2, "bolted to the rock at both ends (%d)" % bolts)
	check(absf(game.stock[D.R_STONE] - 25.0) < 0.01, "for 5 Stone (%.0f left)" % game.stock[D.R_STONE])
	var pl2 := plate(405, 132)
	secs(4.0)
	check(game.modules.has(pl2) and pos(pl2).y < 140.0, "a plate laid on it stays up (y %.1f)" % pos(pl2).y)
	check(game.joints.size() == 2 and pos(sid).distance_to(Vector2(419.5, 140.5)) < 3.0, "and the strut has not moved (%s)" % str(pos(sid)))
	# Refusals.
	var before: float = game.stock[D.R_STONE]
	two_clicks("strut", Vector2i(391, 150), Vector2i(470, 150))
	check(struts().size() == 1 and game.banner_text.contains("Too long"), "a strut over 60 cells is refused (%s)" % game.banner_text)
	two_clicks("strut", Vector2i(400, 110), Vector2i(412, 110))
	check(struts().size() == 1 and game.banner_text.contains("need") , "one held nowhere is refused (%s)" % game.banner_text)
	two_clicks("strut", Vector2i(391, 155), Vector2i(395, 155))
	check(struts().size() == 1 and game.banner_text.contains("short"), "and one too short (%s)" % game.banner_text)
	check(absf(game.stock[D.R_STONE] - before) < 0.01, "none of them cost anything")
	# A save keeps it, and its definition comes back.
	secs(1.0)
	var path := "user://parts_test2.save"
	Save.write(game, path)
	MC.defs.erase(game.modules[sid]["def"])
	game.continue_run(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.paused = true
	check(game.modules.has(sid) and MC.defs.has(game.modules[sid]["def"]), "a loaded strut finds its definition")
	secs(3.0)
	check(game.modules.has(pl2) and pos(pl2).y < 140.0 and game.joints.size() == 2, "and goes on carrying the plate")
	# Taking it down.
	var stone: float = game.stock[D.R_STONE]
	MC.take_down(game, sid)
	check(struts().is_empty() and game.joints.is_empty() and game.stock[D.R_STONE] > stone, "taking it down clears its bolts and gives Stone back")
