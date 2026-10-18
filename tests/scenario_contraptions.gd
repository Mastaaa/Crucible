extends SceneTree
## A8 demo contraptions, built the way a player would (tool clicks on Test Plates), kept as tests:
##  A. Crane: a mast pitoned to the ground, a boom on a Motor at its top, a load on a Rope from the boom's tip;
##     the Motor swings the boom and the load comes with it, nothing snaps, and it holds still when told to
##  B. Drawbridge: a plank on a Motor at the lip of a pier lifts to near upright, holds there, and comes down
##  C. Swinging arm: a Motor spins an arm on a pitoned post round and round
##  D. A Strut and a Rope in one frame: a Strut propped on a post carries a plate while a Rope holds another
## Run: godot --headless --path . --script tests/scenario_contraptions.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const JT = preload("res://scripts/machines/joints.gd")
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
	game.stock[D.R_POWER] = 90.0
	game.stock[D.R_STONE] = 60.0
	for t: String in ["joints", "motor", "strut", "rope"]:
		game.researched[t] = true


func plate(x: int, y: int, turns := 0) -> int:
	var id := MC.place(game, "test_plate", Vector2i(x, y), turns)
	if id == 0:
		print("  !! can't place a plate at %d,%d: %s" % [x, y, MC.check_place(game, "test_plate", Vector2i(x, y), turns)])
	return id


func click(kind: String, at: Vector2i) -> int:
	var before: int = game.next_joint
	game.joint_pick = kind
	MC.click(game, at)
	game.joint_pick = ""
	return game.next_joint - 1 if game.next_joint > before else 0


func pos(id: int) -> Vector2:
	var st: PackedFloat32Array = game.sim.body_state(game.modules[id]["body"])
	return Vector2(st[0], st[1])


func angle(id: int) -> float:
	return game.sim.body_state(game.modules[id]["body"])[2]


func gap(jid: int) -> float:
	var a: Array = JT.anchors(game, jid)
	return (a[0] as Vector2).distance_to(a[1]) if a.size() == 2 else 999.0


func motor_mode(jid: int, mode: int) -> void:
	game.joints[jid]["mode"] = mode


## Power drawn over `ticks` ticks, a tick at a time (the counter resets twice a second).
func drawn(ticks: int) -> float:
	var total := 0.0
	for _i in ticks:
		var a: float = game.used_acc
		game.run_ticks(1)
		var b: float = game.used_acc
		total += b - a if b >= a else b
	return total


func scenario_a() -> void:
	print("A. Crane")
	fresh()
	plate(420, 160, 1)                   # 6 wide, 40 tall: stands on the ground
	var boom := plate(405, 154, 0)             # 40 long, resting its end on the mast's top
	var load_p := plate(430, 190, 0)           # on the ground, to the right of the mast
	var pit := click("piton", Vector2i(423, 199))
	check(pit > 0 and game.joints[pit]["b"] == 0, "the mast is pitoned to the ground")
	var mot := click("motor", Vector2i(423, 160))
	check(mot > 0 and game.joints[mot]["kind"] == "motor", "a Motor joins the boom to the mast top")
	click("rope", Vector2i(443, 157))
	game.joint_pick = "rope"
	check(game.joint_from.is_empty() == false, "a rope's first end is taken on the boom's tip")
	game.joint_pick = ""
	click("rope", Vector2i(447, 193))
	var rope := 0
	for jid: int in game.joints:
		if game.joints[jid]["kind"] == "rope":
			rope = jid
	check(rope > 0 and game.joints[rope]["kind"] == "rope", "and the second on the load: a Rope")
	secs(3.0)
	check(game.joints.size() == 3 and gap(mot) < 1.5, "all three hold at rest (pin gap %.2f)" % gap(mot))
	var a0 := angle(boom)
	var l0 := pos(load_p)
	motor_mode(mot, -1)
	var used := drawn(90)
	check(a0 - angle(boom) > 0.4, "the Motor lifts the boom's tip (%.2f rad)" % (a0 - angle(boom)))
	check(used > 0.02, "and draws power (%.3f)" % used)
	check(game.joints.has(rope) and game.modules.has(load_p) and pos(load_p).distance_to(l0) > 4.0, "the load comes with it (moved %.1f cells)" % pos(load_p).distance_to(l0))
	motor_mode(mot, 0)
	secs(0.5)
	var held := angle(boom)
	secs(2.0)
	check(absf(angle(boom) - held) < 0.05, "a held Motor keeps the boom where it is")
	motor_mode(mot, 1)
	secs(1.0)
	check(angle(boom) > held + 0.4, "and turning back lowers it again (%.2f)" % angle(boom))
	check(game.joints.has(mot) and game.joints.has(pit), "nothing snapped")
	check(game.modules.size() == 3, "and no part broke")


func scenario_b() -> void:
	print("B. Drawbridge")
	fresh()
	fill(Rect2i(380, 176, 20, 24), D.BEDROCK)       # the near pier, top at row 176
	fill(Rect2i(430, 176, 30, 24), D.BEDROCK)       # the far one
	var plank := plate(390, 170, 0)
	var mot := click("motor", Vector2i(390, 175))
	check(plank != 0 and mot > 0 and game.joints[mot]["b"] == 0, "a Motor on the lip of the pier holds the plank's end")
	secs(2.0)
	check(absf(angle(plank)) < 0.15 and game.modules.has(plank), "the plank lies across (%.2f rad)" % angle(plank))
	motor_mode(mot, -1)
	var used := drawn(60)
	check(used > 0.02, "lifting it draws power (%.3f)" % used)
	secs(0.6)
	check(angle(plank) < -1.0, "it lifts (%.2f rad)" % angle(plank))
	motor_mode(mot, 0)
	secs(0.3)
	var up := angle(plank)
	secs(3.0)
	check(absf(angle(plank) - up) < 0.05 and angle(plank) < -1.0, "and holds up (%.2f rad)" % angle(plank))
	motor_mode(mot, 1)
	secs(0.7)                                  # stops short of the pier: a Motor that meets rock is the player's to stop
	motor_mode(mot, 0)
	secs(0.3)
	check(game.modules.has(plank) and angle(plank) > up + 0.6, "then comes down again (%.2f rad)" % angle(plank))
	check(game.joints.has(mot), "the Motor held the whole time")


func scenario_c() -> void:
	print("C. Swinging arm")
	fresh()
	var post := plate(420, 160, 1)
	var arm := plate(405, 154, 0)
	var pit := click("piton", Vector2i(423, 199))
	var mot := click("motor", Vector2i(423, 160))
	check(post != 0 and arm != 0 and pit > 0 and mot > 0, "a post, an arm and a Motor")
	motor_mode(mot, 1)
	secs(1.0)
	var a0 := angle(arm)
	secs(6.0)
	check(angle(arm) - a0 > 6.0, "the arm goes round and round (%.1f rad in 6 s)" % (angle(arm) - a0))
	check(gap(mot) < 2.0, "the pin stays put (%.2f cells)" % gap(mot))
	check(game.joints.has(mot) and game.joints.has(pit) and game.modules.size() == 2, "nothing snapped or broke")
	motor_mode(mot, 0)
	secs(1.0)
	var rest := angle(arm)
	secs(2.0)
	check(absf(angle(arm) - rest) < 0.05, "and it stops when told to")


func scenario_d() -> void:
	print("D. Strut and Rope together")
	fresh()
	fill(Rect2i(380, 150, 12, 50), D.BEDROCK)
	fill(Rect2i(440, 150, 12, 50), D.BEDROCK)
	game.joint_pick = "strut"
	MC.click(game, Vector2i(391, 150))
	MC.click(game, Vector2i(440, 150))
	game.joint_pick = ""
	var struts: Array = []
	for id: int in game.modules:
		if (game.modules[id]["def"] as String).begins_with("strut_"):
			struts.append(id)
	check(struts.size() == 1, "a Strut spans the gap at row 150")
	var load_p := plate(398, 140, 0)
	fill(Rect2i(370, 90, 100, 10), D.BEDROCK)
	var hung := plate(405, 110, 0)
	click("rope", Vector2i(410, 99))
	var rope := click("rope", Vector2i(412, 111))
	check(rope > 0, "and a Rope holds a plate from the ceiling")
	secs(4.0)
	check(game.modules.has(load_p) and pos(load_p).y < 150.0, "the plate on the Strut stays up (y %.1f)" % pos(load_p).y)
	check(game.modules.has(hung) and game.joints.has(rope) and pos(hung).y < 140.0, "the roped plate hangs (y %.1f)" % pos(hung).y)
	check(game.joints.size() == 3, "all three joints hold (%d)" % game.joints.size())
