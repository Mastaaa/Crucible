extends SceneTree
## A9 standalone tools on seed 7: the Area Vac, Scoop and Grabber, each standing on a line where its centre meets it, and the
## Floodlight, bolted to a machine.
##  A. mounting: a tool with its foot against a Pipe is bolted to it and works, one off the line says what it needs, a tool
##     goes with its line, and the definitions pass the layer checks
##  B. Area Vac: draws every loose pixel of the patch under it into its Pipe and the Pipe carries it to the far base
##  C. Scoop: lifts one material at a time, the most plentiful, and keeps to it
##  D. Floodlight: bolted to the top of a Case it throws a cone of light, 400 cells long and 40 degrees wide, while the stock pays,
##     and stays dark off a machine (a Pipe is no host) or without power
##  E. Grabber: takes a loose body between its jaws, carries it with its line, lets go on a click
##  F. research gates all four, and a tool on a line survives a save
## Run: godot --headless --path . --script tests/scenario_tools.gd

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const MU = preload("res://scripts/machines/mu.gd")
const JT = preload("res://scripts/machines/joints.gd")
const LN = preload("res://scripts/machines/lines.gd")
const LY = preload("res://scripts/machines/layers.gd")
const EX = preload("res://scripts/machines/exterior/ext.gd")
const MT = preload("res://scripts/machines/tools/mount.gd")
const FL = preload("res://scripts/machines/tools/floodlight.gd")
const Save = preload("res://scripts/save.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200
const SAND := 31
const RUBBLE := 8
const PIT := Rect2i(376, SURFACE, 64, 40)


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


## Two Cases a pit apart, each with a Pipe Hookup on the side facing the pit, and a Pipe laid between the hookups. The pit
## is carved under the Pipe and `depth` deep. Returns [case a, case b, pipe].
func rig(depth := 30) -> Array:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	MC.ensure_defs()
	fill(Rect2i(328, SURFACE - 120, 160, 120), D.AIR)
	fill(Rect2i(328, SURFACE, 160, 160), D.DIRT)
	fill(Rect2i(328, SURFACE + 160, 160, 40), D.BEDROCK)
	# A pit in bedrock walls (dirt slumps and takes the Cases with it), a bedrock step under the near Case so the Pipe runs
	# level (a turned hookup's Pipe face is 4 cells higher than an unturned one's).
	fill(Rect2i(366, SURFACE, 84, depth + 8), D.BEDROCK)
	fill(Rect2i(PIT.position.x, SURFACE, PIT.size.x, depth), D.AIR)
	fill(Rect2i(330, SURFACE - 4, 36, 4), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0
	game.stock[D.R_STONE] = 300.0
	for t in ["chute", "case", "pump", "joints", "strut", "pipes", "cables", "lamp", "vacuum", "spout", "scoop", "area_vac", "grabber", "floodlight"]:
		game.researched[t] = true
	var a := MC.place(game, "case", Vector2i(336, SURFACE - 30), 0)
	var ha := MC.place(game, "pipe_hookup", Vector2i(336 + 26, SURFACE - 29), 0)
	var b := MC.place(game, "case", Vector2i(460, SURFACE - 26), 0)
	var hb := MC.place(game, "pipe_hookup", Vector2i(460 - 18, SURFACE - 25), 2)
	# A Case with a hookup on one side tips: pin each Case to the rock under it.
	JT.attach(game, "piton", a, 0, Vector2(349.0, SURFACE - 3.5), Vector2(349.0, SURFACE - 3.5))
	JT.attach(game, "piton", b, 0, Vector2(473.0, SURFACE + 0.5), Vector2(473.0, SURFACE + 0.5))
	secs(1.0)
	game.joint_from = {}
	LN.click(game, "pipe", point(ha, "pipe"))
	LN.click(game, "pipe", point(hb, "pipe"))
	var now := LN.all(game)
	return [a, b, now[now.size() - 1] if not now.is_empty() else 0]


func point(id: int, name: String) -> Vector2:
	for pt: Dictionary in JT.points(game, game.modules[id]):
		if pt["name"] == name and pt["kind"] == "hookup":
			return pt["pos"]
	return Vector2(-1, -1)


var why := ""


## A Floodlight on top of module `host`, turned so its foot is at the bottom and its front points up.
func mount_light(host: int) -> int:
	var b := MC.bounds(game.modules[host])
	var at := Vector2i(b.position.x + (b.size.x >> 1) - 8, b.position.y - 16)
	why = MC.check_place(game, "floodlight", at, 3)
	return MC.place(game, "floodlight", at, 3)


## A tool of `def_id` hanging from the middle of the Pipe, its top edge a cell under the pipe's underside.
func hang(def_id: String, pipe: int, dx := 0) -> int:
	var pm: Dictionary = game.modules[pipe]
	var size: Vector2i = MC.defs[def_id]["size"] if MC.defs[def_id]["size"] is Vector2i else Vector2i(MC.defs[def_id]["size"][0], MC.defs[def_id]["size"][1])
	var at := Vector2i(int(pm["at"].x) + dx - (size.x >> 1), int(pm["at"].y) + 3)
	why = MC.check_place(game, def_id, at, 0)
	return MC.place(game, def_id, at, 0)


func held(id: int, mat: int) -> int:
	return int(game.modules[id]["contents"].get(mat, 0))


func count(r: Rect2i, mat: int) -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	mask[mat] = 1
	return game.sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)


func scenario_a() -> void:
	print("A. mounting")
	var r := rig()
	check(r[0] != 0 and r[1] != 0 and r[2] != 0, "two Cases stand with a Pipe laid across the pit")
	if r[2] == 0:
		return
	var t := hang("scoop", r[2])
	check(t != 0, "a Scoop is hung under the Pipe (%s)" % why)
	if t == 0:
		return
	secs(1.0)
	var tm: Dictionary = game.modules[t]
	check(tm["needs"] == "" and tm["on"] == r[2], "it stands on the Pipe (needs '%s')" % tm["needs"])
	var bolts := 0
	for jid: int in game.joints:
		if game.joints[jid].get("auto", 0) == t and game.joints[jid]["b"] == r[2]:
			bolts += 1
	check(bolts == 1, "and is bolted to it by one joint of its own")
	var y0 := float(tm["at"].y)
	secs(2.0)
	check(absf(float(tm["at"].y) - y0) < 1.5, "it stays put (moved %.1f)" % (float(tm["at"].y) - y0))
	var lone := MC.place(game, "scoop", Vector2i(PIT.position.x + 4, SURFACE + 14), 0)
	secs(0.6)
	check(lone != 0 and game.modules[lone]["needs"].begins_with("Needs a line"), "a Scoop off any line says what it needs (%s)" % game.modules[lone]["needs"])
	var bad := 0
	for id: String in ["area_vac", "scoop", "grabber", "floodlight"]:
		bad += LY.validate(MC.defs[id]).size()
	check(bad == 0, "the four definitions pass the layer checks")
	check(not game.modules[r[2]]["state"].begins_with("Cut"), "the Pipe is whole")
	MC.take_down(game, r[2])
	secs(0.6)
	check(game.modules.has(t) and game.modules[t]["needs"].begins_with("Needs a line"), "a tool with its Pipe taken down says what it needs")
	var kept := 0
	for jid: int in game.joints:
		if game.joints[jid].get("auto", 0) == t:
			kept += 1
	check(kept == 0, "and keeps no bolt to a line that is gone")


func scenario_b() -> void:
	print("B. Area Vac")
	var r := rig()
	var v := hang("area_vac", r[2])
	check(v != 0, "an Area Vac is hung under the Pipe (%s)" % why)
	if v == 0:
		return
	fill(Rect2i(PIT.position.x + 6, SURFACE + 14, 54, 16), SAND)
	secs(0.3)
	var before := count(PIT, SAND)
	check(before > 600, "a bed of sand lies under it (%d cells)" % before)
	secs(1.0)
	check(game.modules[v]["needs"] == "", "it stands on the Pipe (%s)" % game.modules[v]["needs"])
	secs(12.0)
	var after := count(PIT, SAND)
	check(after < before, "it draws the sand in (%d left of %d)" % [after, before])
	check(held(r[1], SAND) > 0, "and the Pipe carries it to the far Case (%d there)" % held(r[1], SAND))
	check(game.modules[v].get("pulled", 0) > 0, "the readout counts it: %s" % MC.info(game, game.modules[v]).replace("\n", " / "))
	var power := float(game.stock[D.R_POWER])
	var pulled: int = game.modules[v]["pulled"]
	for _i in 180:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(game.modules[v]["pulled"] == pulled, "with the stock dry it draws nothing")
	game.stock[D.R_POWER] = power


func scenario_c() -> void:
	print("C. Scoop")
	var r := rig()
	var s := hang("scoop", r[2])
	check(s != 0, "a Scoop is hung under the Pipe (%s)" % why)
	if s == 0:
		return
	# A bin in its spot: rubble on top of more sand, between bedrock posts and a bedrock floor.
	var sm: Dictionary = game.modules[s]
	var zone: Rect2i = EX.front_rect(game, sm, MC.defs["scoop"], 10, 10)
	var cx := zone.position.x + (zone.size.x >> 1)
	var y0 := zone.position.y + 1          # the zone's first row overlaps the tool's own last row
	fill(Rect2i(cx - 6, y0, 1, 10), D.BEDROCK)
	fill(Rect2i(cx + 5, y0, 1, 10), D.BEDROCK)
	fill(Rect2i(cx - 6, y0 + 9, 12, 2), D.BEDROCK)
	fill(Rect2i(cx - 5, y0 + 4, 10, 5), SAND)
	fill(Rect2i(cx - 5, y0, 10, 4), RUBBLE)
	var sand0 := count(PIT, SAND)
	var rubble0 := count(PIT, RUBBLE)
	check(sand0 == 50 and rubble0 == 40, "sand (%d) lies under rubble (%d) in the bin" % [sand0, rubble0])
	secs(0.35)
	check(sm["needs"] == "", "it stands on the Pipe (%s)" % sm["needs"])
	var taken := sand0 - count(PIT, SAND)
	check(taken > 0 and sm.get("want", -1) == SAND, "it lifts sand, the larger share, first (%d of %d cells; %s)" % [taken, sand0, MC.info(game, sm).split("\n")[1]])
	check(held(r[1], RUBBLE) == 0 and count(PIT, RUBBLE) == rubble0, "and no rubble while sand is its pick (%d rubble taken)" % (rubble0 - count(PIT, RUBBLE)))
	secs(10.0)
	check(held(r[1], SAND) == 50, "the Pipe carries the sand to the far Case (%d there)" % held(r[1], SAND))
	check(held(r[1], RUBBLE) == 40, "and it moves on to the rubble once the sand is gone (%d there)" % held(r[1], RUBBLE))


func scenario_d() -> void:
	print("D. Floodlight")
	var r := rig()
	var t := mount_light(r[1])
	check(t != 0, "a Floodlight is set on top of the far Case (%s)" % why)
	if t == 0:
		return
	secs(1.5)
	var tm: Dictionary = game.modules[t]
	check(tm["needs"] == "" and tm["on"] == r[1], "it stands on the Case (needs '%s')" % tm["needs"])
	var bolts := 0
	for jid: int in game.joints:
		if game.joints[jid].get("auto", 0) == t and game.joints[jid]["b"] == r[1]:
			bolts += 1
	check(bolts == 1, "and is bolted to it by one joint of its own")
	check(tm.get("lit", false), "it is lit with the Hub's stock to pay (%s)" % tm.get("state", ""))
	var beam: Array = FL.beam(game, tm, MC.defs["floodlight"])
	var lit_n := 0
	for l: Array in MC.lights(game):
		for c: Array in beam:
			if (l[0] as Vector2).distance_to(c[0]) < 0.5 and absf(l[1] - c[1]) < 0.5:
				lit_n += 1
	check(lit_n >= beam.size(), "the game lights all of its circles (%d of %d)" % [lit_n, beam.size()])
	var lens := Vector2(tm["at"])
	var far := 0.0
	var off := 0.0
	for c: Array in beam:
		var d: Vector2 = (c[0] as Vector2) - lens
		far = maxf(far, -d.y + c[1])
		off = maxf(off, absf(d.x) + c[1])
	check(beam.size() >= 4, "it throws a chain of circles (%d)" % beam.size())
	check(far > 380.0 and far < 410.0, "up to the range, twice the Lamp's reach (%d cells against the Lamp's %d)" % [int(far), int(D.LIGHT_LAMP)])
	check(off < 0.4 * far, "and the cone is narrow: %d cells either side at most against %d long" % [int(off), int(far)])
	var below := 0
	for c: Array in beam:
		if (c[0] as Vector2).y > lens.y + 4.0:
			below += 1
	check(below == 0, "and points out of its front, not down")
	var stock := float(game.stock[D.R_POWER])
	for _i in 90:
		game.stock[D.R_POWER] = 0.0        # the Hub's trickle would pay a Floodlight otherwise
		game.run_ticks(1)
	check(not tm.get("lit", false), "it goes dark with the stock dry")
	game.stock[D.R_POWER] = stock
	var pm: Dictionary = game.modules[r[2]]
	var pat := Vector2i(int(pm["at"].x) - 8, MC.bounds(pm).end.y + 1)      # hung under the Pipe, turned so its foot is at the top
	var onpipe := MC.place(game, "floodlight", pat, 1)
	var lone := MC.place(game, "floodlight", Vector2i(PIT.position.x + 4, SURFACE + 14), 0)
	secs(1.5)
	check(onpipe != 0 and not game.modules[onpipe].get("lit", false) and game.modules[onpipe]["needs"].begins_with("Needs a machine"), "one set against a Pipe stays dark (a line is no host)")
	check(lone != 0 and not game.modules[lone].get("lit", false) and game.modules[lone]["needs"].begins_with("Needs a machine"), "one standing off any machine stays dark")


func scenario_e() -> void:
	print("E. Grabber")
	var r := rig()
	var gb := hang("grabber", r[2])
	check(gb != 0, "a Grabber is hung under the Pipe (%s)" % why)
	if gb == 0:
		return
	var gm: Dictionary = game.modules[gb]
	secs(0.6)
	var zone: Rect2i = EX.front_rect(game, gm, MC.defs["grabber"], 22, 8)
	var cx := zone.position.x + (zone.size.x >> 1)
	var plate := Rect2i(cx - 12, zone.end.y, 24, 2)
	fill(plate, D.BEDROCK)
	fill(Rect2i(cx - 5, zone.end.y - 6, 10, 6), D.STONE)
	var body: int = game.sim.make_body(cx - 5, zone.end.y - 6, 10, 6, 0.0, 0.0, 0.0)
	check(body > 0, "a loose slab lies in the jaws' reach")
	if body <= 0:
		return
	secs(0.7)
	check(gm.get("mode", "") == "hold" and not (gm.get("grip", {}) as Dictionary).is_empty(), "it takes hold of the slab (%s)" % gm.get("state", ""))
	var y0: float = game.sim.body_state(body)[1]
	# Remove the pit floor: a held slab stays up, a free one falls.
	fill(plate, D.AIR)
	secs(1.0)
	var y1: float = game.sim.body_state(body)[1]
	check(absf(y1 - y0) < 3.0, "the slab stays up when the floor goes (moved %.1f)" % (y1 - y0))
	var click := Vector2i(int(MT.foot_of(game, gm, MC.defs["grabber"])["pos"].x), int(MT.foot_of(game, gm, MC.defs["grabber"])["pos"].y) + 1)
	MC.use(game, click)
	check(gm["mode"] == "off" and (gm.get("grip", {}) as Dictionary).is_empty(), "a click lets go")
	secs(2.0)
	var y2: float = game.sim.body_state(body)[1] if game.sim.body_info(body).size() > 0 else 9999.0
	check(y2 > y1 + 5.0, "and the slab falls (%.1f cells)" % (y2 - y1))
	MC.use(game, click)
	check(gm["mode"] == "grab", "another click readies it to grab again")


func scenario_f() -> void:
	print("F. research and saving")
	var r := rig()
	var t := mount_light(r[1])
	var s := hang("scoop", r[2], -14)
	secs(1.0)
	check(t != 0 and s != 0, "a Floodlight stands on the Case and a Scoop hangs from the Pipe")
	var path := "user://tools_test.save"
	Save.write(game, path)
	game.continue_run(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	secs(1.5)
	check(game.modules.has(t) and game.modules[t]["on"] == r[1], "the Floodlight still stands on its Case after a save")
	check(game.modules.has(t) and game.modules[t].get("lit", false), "and is lit")
	for id: String in ["scoop", "area_vac", "grabber", "floodlight"]:
		game.researched.erase(id)
	for id: String in ["scoop", "area_vac", "grabber", "floodlight"]:
		check(not MC.unlocked(game, MC.defs[id]), "the %s waits for its tech" % MC.defs[id]["name"])
	game.researched["scoop"] = true
	check(MC.unlocked(game, MC.defs["scoop"]) and not MC.unlocked(game, MC.defs["area_vac"]), "and they open one by one")
