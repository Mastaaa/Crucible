extends SceneTree
## A3 machine framework core on seed 7, in rooms lined with bedrock away from the Hub:
##  A. placement: a module is a rigid body of casing cells; turned placement swaps its
##     size and turns its faces; rock in the way refuses it; it never settles into ground
##  B. faces: pixel faces of a stack join and open, signal faces side by side join, a
##     power face against a pixel face doesn't, a module turned upside down joins; contents
##     pass through a joined pair; taking one away closes the other
##  C. integrity and breach: a dent (one layer) isn't a breach, a hole is and spills
##     the contents out; the integrity number follows the cells
##  D. wreckage: a casing knocked mostly away drops as wreckage and spills everything
##  E. a body the engine removed takes its module with it
##  F. a save keeps the registry and the body flag
## Run: godot --headless --path . --script tests/scenario_modules.gd

const D = preload("res://scripts/defs.gd")
const F = preload("res://scripts/machines/faces.gd")
const MC = preload("res://scripts/machines/machines.gd")
const CS = preload("res://scripts/machines/casing.gd")
const Save = preload("res://scripts/save.gd")
var game: Node
var f := 0
var fails := 0
var room := Rect2i(200, 1000, 300, 120)


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


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	fill(room.grow(20), D.BEDROCK)
	fill(room, D.AIR)


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func count(r: Rect2i, m: int) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if game.sim.get_cell(x, y) == m:
				n += 1
	return n


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


## Places module `def` standing on the room's floor with its left edge at x.
func on_floor(def: String, x: int, turns := 0) -> int:
	MC.ensure_defs()
	var size: Vector2i = F.layout(MC.defs[def], turns)["size"]
	return MC.place(game, def, Vector2i(x, room.end.y - size.y), turns)


## Places module `def` so that its face `fb` touches face `fa` of module `a` from outside.
func against(a: int, fa: int, def: String, fb: int, turns := 0) -> int:
	var ma: Dictionary = game.modules[a]
	var la := F.layout(MC.defs[ma["def"]], ma["turns"])
	var lb := F.layout(MC.defs[def], turns)
	var st: PackedFloat32Array = game.sim.body_state(ma["body"])
	var info: PackedFloat32Array = game.sim.body_info(ma["body"])
	var origin := Vector2(st[0] - info[2], st[1] - info[3])    # where a's bitmap starts
	var face: Dictionary = la["faces"][fa]
	var p: Vector2 = origin + face["centre"] + Vector2(face["dir"]) * 2.0 - lb["faces"][fb]["centre"]
	return MC.place(game, def, Vector2i(roundi(p.x), roundi(p.y)), turns)


func body_cells(id: int) -> int:
	return int(game.sim.body_info(game.modules[id]["body"])[4])


func scenario_a() -> void:
	print("A. placement")
	fresh()
	var b := on_floor("test_box", 230)
	var lay := F.layout(MC.defs["test_box"], 0)
	check(b > 0 and game.modules.size() == 1, "a box is placed")
	check(body_cells(b) == lay["designed"], "its body is its casing: %d cells" % lay["designed"])
	var up := F.layout(MC.defs["test_box"], 1)
	check(up["size"] == Vector2i(20, 28) and up["designed"] == lay["designed"], "turned once it is 20 x 28 with the same casing")
	var d0: Vector2i = lay["faces"][0]["dir"]
	var d1: Vector2i = up["faces"][0]["dir"]
	check(d0 == F.UP and d1 == F.RIGHT and up["faces"][1]["dir"] == F.LEFT, "its faces turn with it (top to right, bottom to left)")
	var t := on_floor("test_cap", 300, 1)
	check(t > 0 and game.sim.body_info(game.modules[t]["body"])[0] == 14.0, "a turned cap is placed 14 wide")
	check(MC.place(game, "test_box", Vector2i(230, room.end.y - 8), 0) == 0, "not into the floor")
	check(MC.check_place(game, "nope", Vector2i(230, 1000), 0) != "", "an unknown module is refused")
	secs(3.0)
	check(game.modules.size() == 2 and game.sim.body_count() >= 2, "lying still for 3 s it stays a body (never settles into ground)")
	check(game.modules[b]["integrity"] == 1.0, "and its integrity is 1")
	game.module_pick = "test_cap"
	MC.key(game, KEY_R)
	MC.click(game, Vector2i(420, room.end.y - 12))
	check(game.modules.size() == 3 and game.modules[game.next_module - 1]["turns"] == 1, "picked from the Build list, turned with R and clicked, a cap is placed")
	game.cancel_tool()
	check(game.module_pick == "", "cancelling the tool drops the pick")


func link_of(id: int, face: int) -> int:
	return game.modules[id]["faces"][face]["link_m"] if game.modules.has(id) else -1


func scenario_b() -> void:
	print("B. faces")
	fresh()
	var cap := on_floor("test_cap", 230)
	var box := against(cap, 0, "test_box", 1)
	check(cap > 0 and box > 0, "a box is set on a cap, out face to in face")
	secs(2.0)
	check(link_of(box, 1) == cap and link_of(cap, 0) == box, "their pixel faces joined")
	check(game.modules[box]["faces"][1]["open"] and game.modules[cap]["faces"][0]["open"], "and both opened")
	var port: int = F.layout(MC.defs["test_box"], 0)["faces"][1]["cells"].size()
	check(game.modules[box]["opened"] == port and body_cells(box) == game.modules[box]["designed"] - port,
			"opening took the port's %d pixels out of the casing" % port)
	check(game.modules[box]["integrity"] == 1.0 and game.modules[box]["breach"].x < 0, "an open port is no damage and no breach")
	check(link_of(box, 0) == 0 and link_of(box, 2) == 0, "the box's other faces stayed closed")
	MC.add_contents(game, box, D.WATER, 60)
	secs(3.0)
	var got: int = game.modules[cap]["contents"].get(D.WATER, 0)
	print("  box holds %d, cap holds %d" % [MC.stored(game.modules[box]), got])
	check(got >= 40 and MC.stored(game.modules[box]) + got == 60, "contents pass through the joined pair, none lost")
	MC.remove(game, box)
	secs(0.5)
	check(link_of(cap, 0) == 0 and not game.modules[cap]["faces"][0]["open"] and body_cells(cap) == game.modules[cap]["designed"],
			"taking the box away closes the cap's port again")

	fresh()
	box = on_floor("test_box", 230)
	var plug := against(box, 3, "test_plug", 0)
	secs(2.0)
	check(link_of(box, 3) == plug and link_of(plug, 0) == box, "signal faces side by side join")
	check(link_of(box, 2) == 0, "and the box's power face doesn't")

	fresh()
	box = on_floor("test_box", 230, 1)   # turned once: its top face is the power one
	cap = against(box, 2, "test_cap", 0, 2)   # the cap upside down, its pixel face on the power face
	secs(2.0)
	check(cap > 0 and link_of(box, 2) == 0 and link_of(cap, 0) == 0, "a pixel face against a power face stays closed")

	fresh()
	box = on_floor("test_box", 230)
	cap = against(box, 0, "test_cap", 0, 2)     # a cap turned upside down on the box's in face
	secs(2.0)
	check(cap > 0 and link_of(box, 0) == cap, "a module turned half way round joins")

	var fr := {"st": PackedFloat32Array([100.0, 50.0, PI / 2.0]), "info": PackedFloat32Array([10.0, 6.0, 4.0, 3.0, 20.0]), "lay": null}
	var p: Vector2 = MC._world(fr, Vector2(8.0, 3.0))
	check(p.distance_to(Vector2(100.0, 54.0)) < 0.01, "a body at 90 degrees maps its pixels round its centre of mass")


func scenario_c() -> void:
	print("C. integrity and breach")
	fresh()
	var box := on_floor("test_box", 230)
	MC.add_contents(game, box, D.WATER, 80)
	var designed: int = game.modules[box]["designed"]
	MC.knock_out(game, box, [Vector2i(0, 14)])      # one layer of the left wall
	secs(0.5)
	check(game.modules[box]["breach"].x < 0 and game.modules[box]["integrity"] < 1.0, "a dent (one layer) is no breach")
	check(absf(game.modules[box]["integrity"] - float(designed - 1) / designed) < 0.001, "the integrity number is the casing left: %d / %d" % [designed - 1, designed])
	secs(1.0)
	check(MC.stored(game.modules[box]) == 80, "and nothing leaks")
	MC.knock_out(game, box, [Vector2i(1, 14)])      # through the second layer
	secs(0.5)
	check(game.modules[box]["breach"].x >= 0, "a hole through both layers is a breach")
	secs(8.0)           # the leak follows the damage: this hole is two pixels, so it seeps
	var left := MC.stored(game.modules[box])
	var outside := count(Rect2i(room.position.x, room.position.y, 232, room.size.y), D.WATER)
	print("  contents left %d, water outside the box on its left: %d" % [left, outside])
	check(left < 20, "a breach spills the contents")
	check(outside >= 40, "and they land outside the hole")


func scenario_d() -> void:
	print("D. wreckage")
	fresh()
	var box := on_floor("test_box", 230)
	MC.add_contents(game, box, D.WATER, 60)
	var hit: Array = []
	for y in range(0, 20):
		for x in range(0, 17):
			hit.append(Vector2i(x, y))
	MC.knock_out(game, box, hit)
	secs(1.0)
	check(not game.modules.has(box), "a casing mostly gone is no longer a module")
	secs(3.0)
	var outside := count(room, D.WATER)
	check(outside >= 40, "its contents are on the ground: %d water" % outside)


func scenario_e() -> void:
	print("E. a lost body")
	fresh()
	var box := on_floor("test_box", 230)
	MC.add_contents(game, box, D.WATER, 40)
	game.sim.remove_body(game.modules[box]["body"])
	secs(1.0)
	check(not game.modules.has(box), "the engine losing the body drops the module")
	secs(2.0)
	check(count(room, D.WATER) >= 30, "and its contents spill")


func scenario_f() -> void:
	print("F. save")
	fresh()
	var cap := on_floor("test_cap", 230)
	var box := against(cap, 0, "test_box", 1)
	MC.add_contents(game, box, D.WATER, 20)
	secs(2.0)
	var path := "user://modules_test.save"
	Save.write(game, path)
	game.continue_run(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(game.modules.size() == 2 and game.modules.has(box), "the registry loads back")
	check(link_of(box, 1) == cap and MC.stored(game.modules[box]) + MC.stored(game.modules[cap]) == 20, "with its links and contents")
	secs(3.0)
	check(game.modules.size() == 2, "and the bodies still count as modules (no settling after a load)")
