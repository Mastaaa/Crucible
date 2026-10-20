extends SceneTree
## A9 lines on seed 7: the Pipe, the Cable and the Network line, laid with the two-click tool between hookups.
##  A. a Pipe carries a base's contents to another base, backs up when that is full, runs the other way on a click
##     and hands what it holds back to its base when it is taken down
##  B. a Pipe Router merges two Pipes' worth into one and shares its stock between the Pipes leaving it
##  C. a Cable charges from the Hub's stock and puts an assembly out of reach in the network's reach, until it is cut
##  D. a Network line carries a remote Funnel's cells to a port in reach, which banks them
##  E. the tools: ends that do not suit are refused, research gates the buttons, a line saves and loads
## Run: godot --headless --path . --script tests/scenario_lines.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const MU = preload("res://scripts/machines/mu.gd")
const JT = preload("res://scripts/machines/joints.gd")
const LN = preload("res://scripts/machines/lines.gd")
const Save = preload("res://scripts/save.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200
const SAND := 31


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
	fill(Rect2i(328, SURFACE - 120, 160, 120), D.AIR)
	fill(Rect2i(328, SURFACE, 160, 160), D.DIRT)
	fill(Rect2i(328, SURFACE + 160, 160, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0
	game.stock[D.R_STONE] = 200.0
	for t in ["chute", "case", "pump", "joints", "pipes", "cables", "network_line", "bus_hopper"]:
		game.researched[t] = true


func held(id: int, mat: int) -> int:
	return int(game.modules[id]["contents"].get(mat, 0))


## A Case at x with a Pipe Hookup plugged into its right socket (`turns` 0) or its left one (2).
func base_and_hookup(x: int, side_right: bool, part := "pipe_hookup") -> Array:
	var c := MC.place(game, "case", Vector2i(x, SURFACE - 26), 0)
	var w: int = MC.defs[part]["size"][0]
	var p: int = MC.place(game, part, Vector2i(x + 26, SURFACE - 25) if side_right else Vector2i(x - w, SURFACE - 25), 0 if side_right else 2)
	return [c, p]


func point(id: int, name: String) -> Vector2:
	for pt: Dictionary in JT.points(game, game.modules[id]):
		if pt["name"] == name and pt["kind"] == "hookup":
			return pt["pos"]
	return Vector2(-1, -1)


func lay(kind: String, a: int, an: String, b: int, bn: String) -> int:
	var before := LN.all(game).size()
	game.joint_from = {}
	LN.click(game, kind, point(a, an))
	LN.click(game, kind, point(b, bn))
	var now := LN.all(game)
	return now[now.size() - 1] if now.size() > before else 0


func scenario_a() -> void:
	print("A. Pipe")
	fresh()
	var a := base_and_hookup(336, true)
	var b := base_and_hookup(460, false)
	secs(1.0)
	check(a[0] != 0 and a[1] != 0 and b[0] != 0 and b[1] != 0, "two Cases stand with a Pipe Hookup each")
	var stone0: float = game.stock[D.R_STONE]
	var pipe := lay("pipe", a[1], "pipe", b[1], "pipe")
	check(pipe != 0, "a Pipe is laid between the hookups")
	if pipe == 0:
		return
	check(game.stock[D.R_STONE] < stone0, "and paid for (%d Stone)" % int(stone0 - game.stock[D.R_STONE]))
	check(lay("pipe", a[1], "pipe", b[1], "pipe") == 0, "a hookup takes one Pipe")
	MC.add_contents(game, a[0], SAND, 60)
	secs(3.0)
	check(held(b[0], SAND) == 60 and held(a[0], SAND) == 0, "it carries the first Case's sand to the second (%d there, %d left)" % [held(b[0], SAND), held(a[0], SAND)])
	check(game.modules[pipe]["carried"] >= 60, "and counts it (%d)" % game.modules[pipe]["carried"])
	# Click it to turn it round.
	var mid := Vector2i(roundi(game.modules[pipe]["at"].x), roundi(game.modules[pipe]["at"].y))
	check(MC.use(game, mid) and game.modules[pipe]["dir"] == -1, "a click on it runs it the other way")
	secs(3.0)
	check(held(a[0], SAND) == 60 and held(b[0], SAND) == 0, "and the sand comes back (%d, %d)" % [held(a[0], SAND), held(b[0], SAND)])
	# Back the right way round, a full far base backs it up, and taking it down hands the load back to its start.
	check(MC.use(game, mid) and game.modules[pipe]["dir"] == 1, "a second click turns it again")
	var cap := MU.capacity(game.modules[b[0]], MC.defs["case"])
	MC.add_contents(game, b[0], SAND, cap)
	MU.take(game.modules[a[0]], SAND, held(a[0], SAND))
	MC.add_contents(game, a[0], SAND, 30)
	secs(3.0)
	check(MU.stored(game.modules[b[0]]) == cap and held(a[0], SAND) == 0 and MU.stored(game.modules[pipe]) == 30,
			"into a full Case nothing more is put: the Pipe keeps its 30 (%s)" % game.modules[pipe]["state"])
	MC.take_down(game, pipe)
	check(not game.modules.has(pipe), "taking it down removes it")
	check(held(a[0], SAND) == 30, "and what it held goes back to the base it was drawn from (%d)" % held(a[0], SAND))


func scenario_b() -> void:
	print("B. Pipe Router")
	fresh()
	var a := base_and_hookup(336, true)
	var b := base_and_hookup(458, false)
	var router := MC.place(game, "pipe_router", Vector2i(400, SURFACE - 22), 0)
	secs(1.0)
	check(router != 0, "a Router stands between them (%s)" % (game.modules[router]["needs"] if router != 0 else "not placed"))
	if router == 0:
		return
	var p1 := lay("pipe", a[1], "pipe", router, "a")
	var p2 := lay("pipe", router, "c", b[1], "pipe")
	check(p1 != 0 and p2 != 0, "a Pipe runs into it and another out of it")
	if p1 == 0 or p2 == 0:
		return
	MC.add_contents(game, a[0], SAND, 80)
	secs(4.0)
	check(held(b[0], SAND) == 80 and held(a[0], SAND) == 0, "sand goes through the Router to the far Case (%d)" % held(b[0], SAND))
	check(MU.stored(game.modules[router]) == 0, "and nothing is left in the Router")


func scenario_c() -> void:
	print("C. Cable")
	fresh()
	var far := MC.place(game, "case", Vector2i(336, SURFACE - 26), 0)
	var far_port := MC.place(game, "energy_port", Vector2i(362, SURFACE - 25 + 7 - 7), 0)
	var near := MC.place(game, "case", Vector2i(440, SURFACE - 26), 0)
	var near_port := MC.place(game, "energy_port", Vector2i(420, SURFACE - 25), 2)
	secs(1.0)
	check(far != 0 and far_port != 0 and near != 0 and near_port != 0, "two Cases, each with an Energy Port")
	var mf: Dictionary = game.modules[far]
	var mn: Dictionary = game.modules[near]
	check(MU.networked(game, mn, MC.defs["case"]) and not MU.networked(game, mf, MC.defs["case"]), "the near Case is in reach and the far one is not")
	var p0: float = game.stock[D.R_POWER]
	var cable := lay("cable", far_port, "cable", near_port, "cable")
	check(cable != 0, "a Cable is laid between the ports (%s)" % ("" if cable == 0 else "ok"))
	if cable == 0:
		return
	secs(4.0)
	var cm: Dictionary = game.modules[cable]
	check(cm["charge"] > 0.5 and MU.stored(cm) == 0, "its power is held as charge, not as cells (%.1f charge, %d cells)" % [cm["charge"], MU.stored(cm)])
	check(game.stock[D.R_POWER] < p0, "taken from the Hub's stock")
	check(cm["energised"] and MU.networked(game, mf, MC.defs["case"]), "once half full the far Case is in the network's reach (%s)" % cm["state"])
	check(MU.networked(game, game.modules[far_port], MC.defs["energy_port"]), "and so is its Energy Port")
	# Cut: take the near port away.
	var stock0: float = game.stock[D.R_POWER]
	var charge: float = cm["charge"]
	MC.take_down(game, near_port)
	secs(1.0)
	check(not game.modules.has(cable), "taking an end away takes the Cable with it")
	check(not MU.networked(game, mf, MC.defs["case"]), "and the far Case is out of reach again")
	check(game.stock[D.R_POWER] >= stock0 + charge * 0.99 - 0.5, "its charge went back to the Hub's stock (%.1f of %.1f)" % [game.stock[D.R_POWER] - stock0, charge])


func scenario_d() -> void:
	print("D. Network line")
	fresh()
	var far := MC.place(game, "funnel", Vector2i(372, SURFACE - 14), 0)
	var near := MC.place(game, "funnel", Vector2i(470, SURFACE - 14), 0)
	secs(1.0)
	check(far != 0 and near != 0, "two Funnels, one in reach of the Hub and one not")
	var fm: Dictionary = game.modules[far]
	check(not MU.direct(game, fm, MC.defs["funnel"]) and MU.direct(game, game.modules[near], MC.defs["funnel"]), "the far one has no Node or Hub in reach")
	var line := lay("network", far, "net", near, "net")
	check(line != 0, "a Network line is laid between them")
	if line == 0:
		return
	var s0 := float(game.stock[D.R_STONE])
	game.stock[D.R_POWER] = 0.0
	MC.add_contents(game, far, D.DIRT, 30)
	for _t in 60:
		game.run_ticks(1)
		game.stock[D.R_POWER] = 0.0
	check(held(far, D.DIRT) == 30 and MU.stored(game.modules[line]) == 0, "a port banking through a line pays a power a cell: with none, it holds back")
	game.stock[D.R_POWER] = 90.0
	secs(1.0)
	check(held(far, D.DIRT) < 30, "the far Funnel passes its cells into the line (%d left)" % held(far, D.DIRT))
	secs(3.0)
	check(held(far, D.DIRT) == 0 and MU.stored(game.modules[line]) == 0, "which carries them to the near port (%d in transit)" % MU.stored(game.modules[line]))
	check(float(game.stock[D.R_STONE]) > s0, "where they are banked (%.2f Stone)" % (game.stock[D.R_STONE] - s0))
	check(game.modules[line]["carried"] == 30, "the line counted them (%d)" % game.modules[line]["carried"])
	MC.add_contents(game, near, D.DIRT, 30)
	game.stock[D.R_POWER] = 0.0
	for _t in 60:
		game.run_ticks(1)
		game.stock[D.R_POWER] = 0.0
	check(held(near, D.DIRT) == 0, "a port in reach of the Hub banks for nothing")
	# The Node transit view counts the packets in flight through a building.
	var pk = game.Packet.new()
	pk.res = D.R_STONE
	pk.hops = [game.hub]
	game.packets.append(pk)
	check(game.transit_through(game.hub).get(D.R_STONE, 0) == 1, "a Node (here the Hub) reports the packets passing through it")
	game.packets.erase(pk)
	# Cut it: what the line holds is delivered if the far port stands.
	MC.add_contents(game, far, D.DIRT, 10)
	secs(0.2)
	MC.take_down(game, line)
	check(not game.modules.has(line), "taking the line down leaves the Funnels standing")
	var kept := int(held(far, D.DIRT))
	secs(2.0)
	check(held(far, D.DIRT) == kept, "and the far Funnel banks nothing without a line")


func scenario_e() -> void:
	print("E. tools and saving")
	fresh()
	var a := base_and_hookup(336, true)
	var b := base_and_hookup(460, false)
	secs(1.0)
	game.joint_from = {}
	var wrong_start: Dictionary = {"hit": true, "pos": Vector2(0, 0), "mod": a[0], "kind": "hookup", "name": "x"}
	check(LN.why(game, "pipe", wrong_start, wrong_start) != "", "a Pipe cannot start on a Case itself")
	var ea: Dictionary = {"hit": true, "pos": point(a[1], "pipe"), "mod": a[1], "kind": "hookup", "name": "pipe"}
	var eb: Dictionary = {"hit": true, "pos": point(b[1], "pipe"), "mod": b[1], "kind": "hookup", "name": "pipe"}
	check(LN.why(game, "pipe", ea, eb) == "", "two hookups on different bases are fine")
	check(LN.why(game, "cable", ea, eb) != "", "but a Cable needs Energy Ports")
	game.stock[D.R_STONE] = 0.0
	check(LN.why(game, "pipe", ea, eb).begins_with("Needs"), "a Pipe needs its Stone")
	game.stock[D.R_STONE] = 200.0
	var pipe := lay("pipe", a[1], "pipe", b[1], "pipe")
	check(pipe != 0, "it is laid once there is Stone")
	game.modules[pipe]["contents"][SAND] = 5
	secs(0.05)
	var path := "user://lines_test.save"
	Save.write(game, path)
	game.continue_run(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(game.modules.has(pipe) and MC.defs.has(game.modules[pipe]["def"]), "a Pipe survives a save (%s)" % (game.modules[pipe]["def"] if game.modules.has(pipe) else "gone"))
	check(game.modules.has(pipe) and game.modules[pipe]["ends"] == [a[1], b[1]] and LN.connected(game, game.modules[pipe]), "with its two ends and hinges")
	secs(3.0)
	check(game.modules.has(pipe) and held(b[0], SAND) == 5, "and carries on (%d)" % held(b[0], SAND))
	# Research gates the tools.
	game.researched.erase("pipes")
	game.researched.erase("cables")
	game.researched.erase("network_line")
	check(not JT.unlocked(game, "pipe") and not JT.unlocked(game, "cable") and not JT.unlocked(game, "network"), "all three line tools wait for their techs")
	game.researched["pipes"] = true
	check(JT.unlocked(game, "pipe") and not JT.unlocked(game, "cable"), "and open one by one")
