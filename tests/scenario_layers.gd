extends SceneTree
## A9 foundation: layers, sockets, the overseer and its readout, the Case, the Build list's groups.
##  A. the definition format: every definition passes `LY.validate`; the kit's parts are where the plan says
##  B. a part plugged into a base's socket: joined shut, welded, one assembly that falls as one piece
##  C. what a layer needs: a machine alone, an interior strip with one base, with two
##  D. the overseer's readout and names, and a part that is held up showing first
##  E. a line part hands what it carries to a neighbour when it is taken down
##  F. the Build list: headings by layer, stubs left out
##  G. a module saved before the Tank had sockets gets them closed on load
##  H. every stub can be placed by hand, says it is not built, and goes again
## Run: godot --headless --path . --script tests/scenario_layers.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const LY = preload("res://scripts/machines/layers.gd")
const JT = preload("res://scripts/machines/joints.gd")
const F = preload("res://scripts/machines/faces.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200
const AIR_Y := 162          # where a Case is built: a few cells over the ground, so a part not held to it can be seen to fall


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
	fill(Rect2i(328, SURFACE - 160, 224, 160), D.AIR)
	fill(Rect2i(328, SURFACE, 224, 160), 6)
	fill(Rect2i(328, SURFACE + 160, 224, 40), D.BEDROCK)
	game.stock[D.R_STONE] = 200.0


func pos(id: int) -> Vector2:
	var st: PackedFloat32Array = game.sim.body_state(game.modules[id]["body"])
	return Vector2(st[0], st[1])


## A Case at (x, AIR_Y) and a part plugged into its right socket.
func case_and(def_id: String) -> Array:
	var c := MC.place(game, "case", Vector2i(380, AIR_Y), 0)
	var p := MC.place(game, def_id, Vector2i(406, AIR_Y + 8 - 11), 0)
	return [c, p]


func scenario_a() -> void:
	print("A. the definition format")
	fresh()
	var bad: Array = []
	var layers := {}
	for id: String in MC.defs:
		bad.append_array(LY.validate(MC.defs[id]))
		layers[LY.layer_of(MC.defs[id])] = layers.get(LY.layer_of(MC.defs[id]), 0) + 1
	for b: String in bad:
		print("    " + b)
	check(bad.is_empty(), "every definition passes the layer rules (%d problems)" % bad.size())
	check(["base", "machine", "interior", "exterior", "line", "standalone", "anchored"].all(func(l: String) -> bool: return layers.has(l)),
			"every layer has a part")
	for id: String in ["tank", "vault", "case"]:
		check(MC.defs[id]["layer"] == "base", "%s is a base" % id)
	for id: String in ["cutter", "laser", "thumper", "pump", "funnel", "bus_hopper"]:
		check(MC.defs[id]["layer"] == "exterior" and MC.defs[id]["needs"].is_empty(), "%s is exterior and works without a base" % id)
	var stubs := 0
	for id: String in MC.defs:
		if MC.defs[id].get("stub", false):
			stubs += 1
	check(stubs == 15, "fifteen stubs (found %d)" % stubs)
	check(MC.defs["pipe"].has("inventory") and MC.defs["cable"].has("inventory") and MC.defs["network"].has("inventory"), "the lines carry an inventory")
	var hooks := 0
	for id: String in MC.defs:
		for a: Dictionary in MC.defs[id].get("attach", []):
			if a["kind"] == "hookup":
				hooks += 1
	check(hooks >= 8, "the Hookups, Pipe Router and lines declare hookup points (%d)" % hooks)
	var case: Dictionary = MC.defs["case"]
	var tank: Dictionary = MC.defs["tank"]
	check(case["wall"] > tank["wall"] and F.layout(case, 0)["cavity"] < F.layout(tank, 0)["cavity"], "the Case has the thicker wall and the smaller hollow")
	check(LY.needs_of(MC.defs["blender"]) == ["socket"] and LY.needs_of(MC.defs["hdu"]) == ["base_each_face"], "the default needs follow the layer")
	check(F_has_socket(MC.defs["tank"]) and F_has_socket(MC.defs["vault"]) and F_has_socket(case), "the Tank, Vault Cell and Case have sockets")


func F_has_socket(def: Dictionary) -> bool:
	for fc: Dictionary in def["faces"]:
		if fc["type"] == 4:
			return true
	return false


func scenario_b() -> void:
	print("B. a part in a base's socket")
	fresh()
	var ids := case_and("blender")
	check(ids[0] != 0 and ids[1] != 0, "a Case and a Blender stand side by side")
	var c: Dictionary = game.modules[ids[0]]
	var b: Dictionary = game.modules[ids[1]]
	var ci := LY_face(c, "socket_r")
	var bi := LY_face(b, "plug")
	check(c["faces"][ci]["link_m"] == ids[1] and b["faces"][bi]["link_m"] == ids[0], "socket and plug are joined")
	check(not c["faces"][ci]["open"] and not b["faces"][bi]["open"] and c["opened"] == 0 and b["opened"] == 0, "and stay shut: no wall pixels leave")
	check(b["needs"] == "", "the Blender has its base")
	check(b.get("welded", false), "it is welded to the Case")
	var bolts := 0
	for jid: int in game.joints:
		if game.joints[jid].get("auto", 0) == ids[1]:
			bolts += 1
	check(bolts == 1, "by one bolt of its own (%d)" % bolts)
	game.run_ticks(12)
	check(game.overseers.size() == 1 and game.overseers.values()[0]["members"] == [ids[0], ids[1]], "an overseer forms for the pair")
	check(game.overseers.values()[0]["name"] == "Processing line", "named for what it is (%s)" % game.overseers.values()[0]["name"])
	var d0 := pos(ids[1]) - pos(ids[0])
	game.run_ticks(30)
	check(pos(ids[0]).y > float(AIR_Y) + 5.0, "the pair falls (%.0f cells)" % (pos(ids[0]).y - float(AIR_Y)))
	check((pos(ids[1]) - pos(ids[0])).distance_to(d0) < 4.0, "as one piece (the offset moved %.2f cells)" % (pos(ids[1]) - pos(ids[0])).distance_to(d0))
	check(c["faces"][ci]["link_m"] == ids[1], "and the join holds")
	MC.remove(game, ids[0])
	check(game.joints.is_empty(), "taking the Case down takes the bolt")
	game.run_ticks(12)
	check(game.overseers.is_empty() and game.modules[ids[1]]["needs"] != "", "the Blender is alone again and says what it lacks")


func LY_face(m: Dictionary, name: String) -> int:
	return MC.MU.face_index(MC.defs[m["def"]], name)


func scenario_c() -> void:
	print("C. what a layer needs")
	fresh()
	var b := MC.place(game, "blender", Vector2i(400, SURFACE - 30), 0)
	game.run_ticks(12)
	var m: Dictionary = game.modules[b]
	check(m["needs"].begins_with("Needs a base"), "a Blender alone: \"%s\"" % m["needs"])
	check(m["state"] == m["needs"], "and that is its status")
	check(not m.has("welded") or not m["welded"], "nothing to weld")
	check(LY.line(game, m) == "", "no overseer for a part on its own")
	var info := MC.info(game, m)
	check(info.contains("Needs a base"), "the hover text says it")
	fresh()
	var a := MC.place(game, "case", Vector2i(380, AIR_Y), 0)
	var h := MC.place(game, "hdu", Vector2i(406, AIR_Y + 18 - 13), 0)
	game.run_ticks(12)
	check(game.modules[h]["needs"].begins_with("Needs a base joined on each side"), "a strip with one base: \"%s\"" % game.modules[h]["needs"])
	check(game.modules[h]["faces"][LY_face(game.modules[h], "a")]["link_m"] == a, "it joined the Case at its a face")
	fresh()
	a = MC.place(game, "case", Vector2i(380, AIR_Y), 0)
	h = MC.place(game, "hdu", Vector2i(406, AIR_Y + 18 - 13), 0)
	var bb := MC.place(game, "case", Vector2i(420, AIR_Y), 0)
	game.run_ticks(12)
	check(game.modules[h]["needs"] == "", "with a base on each side it has what it needs")
	check(game.modules[h]["faces"][LY_face(game.modules[h], "b")]["link_m"] == bb, "joined to the second Case at b")
	var strip: Dictionary = game.modules[h]
	check(strip["faces"][0]["open"] and strip["faces"][1]["open"], "and its pixel faces open, so what passes can pass")
	check(game.overseers.size() == 1 and game.overseers.values()[0]["members"].size() == 3, "one assembly of three")
	var bolts := 0
	for jid: int in game.joints:
		if game.joints[jid].get("auto", 0) == h:
			bolts += 1
	check(bolts == 2, "the strip is bolted to both Cases (%d)" % bolts)
	MC.remove(game, bb)
	game.run_ticks(12)
	check(game.modules[h]["needs"] != "", "taking one Case down leaves it wanting")


func scenario_d() -> void:
	print("D. the overseer's readout")
	fresh()
	var ids := case_and("blender")
	game.run_ticks(12)
	var line := LY.line(game, game.modules[ids[0]])
	print("    " + line)
	check(line.begins_with("Processing line, 2 parts"), "names the assembly and counts its parts")
	check(line.contains("Blender: Not built yet"), "and carries the lead's own status")
	check(line == LY.line(game, game.modules[ids[1]]), "the same line from either part")
	game.modules[ids[0]]["waits"] = "Waiting for the Blender to finish."
	line = LY.line(game, game.modules[ids[0]])
	check(line.contains("Case: Waiting for the Blender to finish"), "a part held up shows first")
	check(MC.info(game, game.modules[ids[1]]).contains(line), "and the hover text ends with the line")
	check(line.length() <= LY.MAX_LINE + 20, "kept short (%d characters)" % line.length())
	fresh()
	var t := MC.place(game, "tank", Vector2i(380, SURFACE - 54), 0)
	var cu := MC.place(game, "cutter", Vector2i(380, SURFACE - 24), 0)
	game.run_ticks(12)
	check(game.modules[t]["faces"][2]["link_m"] == cu, "a Tank and a Cutter join as they did")
	check(game.modules[cu]["needs"] == "" and game.modules[t]["needs"] == "", "the Cutter needs no base")
	check(game.overseers.values()[0]["name"] == "Harvester", "a base with an exterior part is a Harvester (%s)" % game.overseers.values()[0]["name"])
	fresh()
	var mm := MC.place(game, "test_plate", Vector2i(380, SURFACE - 30), 0)
	var m2 := MC.place(game, "test_plate", Vector2i(380, SURFACE - 20), 0)
	JT.attach(game, "bolt", mm, m2, pos(mm) + Vector2(0, 5))
	game.run_ticks(12)
	check(game.modules[mm]["overseer"] == game.modules[m2]["overseer"] and game.modules[mm]["overseer"] != 0, "two parts joined by a bolt are an assembly too")
	check(game.overseers[game.modules[mm]["overseer"]]["name"] == "Test Plate group", "named for its lead when no rule fits")


func scenario_e() -> void:
	print("E. a line part's inventory")
	fresh()
	var a := MC.place(game, "pipe", Vector2i(380, SURFACE - 12), 0)
	var b := MC.place(game, "pipe", Vector2i(420, SURFACE - 12), 0)
	game.run_ticks(12)
	check(game.modules[a]["faces"][1]["link_m"] == b, "two Pipes join end to end")
	check(MC.capacity(game.modules[a]) == 60, "a Pipe holds 60 in transit")
	check(MC.add_contents(game, a, 6, 45) == 45 and MC.add_contents(game, a, 6, 30) == 15, "it takes up to its cap")
	MC.take_down(game, a)
	check(MC.stored(game.modules[b]) == 60, "taken down, it hands what it carried to the Pipe next to it (%d)" % MC.stored(game.modules[b]))
	MC.take_down(game, b)
	check(game.modules.is_empty(), "and the last one spills its own")


func scenario_f() -> void:
	print("F. the Build list")
	fresh()
	var hud = game.hud
	var names: Array = []
	for h: Dictionary in hud.module_headers:
		names.append((h["label"] as Label).text)
	print("    " + ", ".join(names))
	check(names == ["Bases", "Machines", "Interiors", "Exterior parts", "Lines", "Standalone tools", "Anchored parts", "Other", "Joints and lines", "Test modules"],
			"a heading per layer, then the joint tools, then the test modules")
	MC.refresh_buttons(hud)
	var shown := {}
	for h: Dictionary in hud.module_headers:
		shown[(h["label"] as Label).text] = (h["label"] as Label).visible
	check(shown["Bases"] and shown["Exterior parts"] and shown["Other"] and shown["Test modules"], "Bases, Exterior parts, Other and Test modules show")
	check(not shown["Machines"] and not shown["Interiors"] and not shown["Standalone tools"] and not shown["Anchored parts"], "headings with only stubs under them stay hidden")
	check(not shown["Lines"], "and Lines waits for the Chute")
	game.researched["chute"] = true
	MC.refresh_buttons(hud)
	check((hud.module_headers[4]["label"] as Label).visible, "a heading shows once a button under it does")
	check(not game.researched.has("case") and not MC.unlocked(game, MC.defs["case"]), "the Case waits on its tech")
	game.researched["case"] = true
	for id: String in MC.defs:
		if MC.defs[id].get("stub", false):
			game.researched[id] = true
	var any := false
	for id: String in MC.defs:
		if MC.defs[id].get("stub", false) and MC.unlocked(game, MC.defs[id]):
			any = true
	check(MC.unlocked(game, MC.defs["case"]) and not any, "researched, the Case unlocks and a stub never does")


func scenario_g() -> void:
	print("G. an older save")
	fresh()
	var t := MC.place(game, "tank", Vector2i(380, AIR_Y), 0)
	var m: Dictionary = game.modules[t]
	check(m["faces"].size() == 7, "a Tank has seven faces now (%d)" % m["faces"].size())
	m["faces"] = m["faces"].slice(0, 3)
	MC.migrate(game)
	check(m["faces"].size() == 7 and m["faces"][5]["link_m"] == 0 and not m["faces"][5]["open"], "migrating adds the new ones closed")
	game.run_ticks(12)
	check(game.modules.has(t) and m["needs"] == "", "and it carries on")


func scenario_h() -> void:
	print("H. every stub")
	fresh()
	var n := 0
	for id: String in MC.defs:
		var def: Dictionary = MC.defs[id]
		if not def.get("stub", false):
			continue
		var m_id := MC.place(game, id, Vector2i(400, AIR_Y), 0)
		if m_id == 0:
			check(false, "%s can be placed" % id)
			continue
		game.run_ticks(12)
		var m: Dictionary = game.modules[m_id]
		var ok: bool = m["state"] == "Not built yet." or m["state"] == m["needs"]
		check(ok and MC.info(game, m).length() > 0, "%s: \"%s\"" % [id, m["state"]])
		MC.remove(game, m_id)
		n += 1
	check(n == 15, "all fifteen placed and taken down (%d)" % n)
