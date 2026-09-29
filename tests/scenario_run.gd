extends SceneTree
## Phase-10 run checks on seed 7:
##  A. the Hub is hurt like any building, patches itself with its own Stone, warns
##     when it's failing, and when it goes the run is lost and the world stops
##  B. milestones: tiers, depth bands, first buildings, research, the Crucible
##  C. save and Continue: a run saved mid-play and loaded carries on exactly as the
##     original does (same cells, stock, buildings and packets after 20 s)
##  D. dragged lines: a Conduit chain down a shaft goes down one after another as
##     the network reaches, linked all the way; a row of Hoppers side by side;
##     right-click cuts a line's plans
## Run: godot --headless --path . --script tests/scenario_run.gd

const D = preload("res://scripts/defs.gd")
const Save = preload("res://scripts/save.gd")
const S := D.S
var game: Node
var f := 0
var fails := 0


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		scenario_a()
		scenario_b()
		if game.sim.has_method("save_state"):
			scenario_c()
		scenario_d()
		print("FAILURES: %d" % fails)
		return true
	return false


func fresh() -> void:
	game.new_game(7)
	game.paused = true
	game.reveal_all = true
	game.drill.enabled = false
	game.stock[D.R_STONE] = 200.0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		fails += 1
		print("  FAIL %s" % what)


func secs(s: float) -> void:
	game.run_ticks(int(s * 60.0))


func has_mark(prefix: String) -> bool:
	for m: Dictionary in game.milestones:
		if String(m["text"]).begins_with(prefix):
			return true
	return false


func scenario_a() -> void:
	print("A. the Hub can be lost")
	fresh()
	var hub = game.hub
	var at := Vector2i(hub.center())
	game.blast(at, D.BLAST_RADIUS, 10)
	check(hub.hp < hub.max_hp, "a blast on the Hub hurts it (%d of %d)" % [int(hub.hp), int(hub.max_hp)])
	hub.hp = hub.max_hp * 0.3
	var stone: float = game.stock[D.R_STONE]
	secs(1)
	check(hub.hp > hub.max_hp * 0.6 and game.stock[D.R_STONE] < stone,
			"under 60%% it patches itself with a Stone (%d HP, Stone %d -> %d)" % [int(hub.hp), int(stone), int(game.stock[D.R_STONE])])
	var before: float = hub.hp
	secs(2)
	check(is_equal_approx(hub.hp, before), "only one Stone at a time (%d HP)" % int(hub.hp))
	game._hurt(hub, hub.hp - hub.max_hp * 0.2, "blast")
	check(game.hub_warned and game.banner_text.contains("Hub is failing"), "under a third it warns: \"%s\"" % game.banner_text)
	game.stock[D.R_STONE] = 0.0
	var n := 0
	while not game.run_lost and n < 40:
		game.blast(at, D.BLAST_RADIUS, 10)
		n += 1
	check(game.run_lost and hub.dead, "blasts with no Stone to patch it destroy it (%d blasts)" % n)
	check(game.lost_cause == "blast" and has_mark("The Hub was destroyed by blast"), "the run is lost, by \"%s\"" % game.lost_cause)
	check(game.frozen(), "the world stands still")
	var t: float = game.game_time
	secs(1)
	check(game.game_time == t, "ticks do nothing after the loss")
	check(game.cells_drilled >= 0 and game.buildings_lost == 0, "the Hub isn't counted among buildings lost")
	fresh()
	check(not game.run_lost and not game.hub.dead and game.milestones.is_empty(), "a new game starts clean")


func scenario_b() -> void:
	print("B. milestones")
	fresh()
	game.discover(2, Vector2(game.hub.center()))
	check(has_mark("Tier 2 open: the first Glimmer mined"), "a tier opening is a milestone")
	var d = game.drill
	var keep: int = d.reach
	d.reach = 1500
	game._track_depth()
	d.reach = keep
	check(has_mark("Reached the Stone band"), "the Drill's head in the Stone band is a milestone")
	check(not has_mark("Reached the Magma band"), "... and not the Magma band")
	var lab = game.place(D.B_LAB, Rect2i((D.W >> 1) - 10 * S, D.GROUND_Y - D.B_SIZES[D.B_LAB].y, D.B_SIZES[D.B_LAB].x, D.B_SIZES[D.B_LAB].y))
	var n := 0
	while lab != null and not lab.built and n < 60:
		secs(1)
		n += 1
	check(lab != null and lab.built and has_mark("First Lab built"), "the first Lab built is a major milestone")
	game._finish_research("lamp")
	var minor := false
	for m: Dictionary in game.milestones:
		if m["text"] == "Researched Lamp":
			minor = not m["major"]
	check(minor, "research is a minor one")
	game.won = true
	check(game.frozen(), "a win stops the world...")
	game.keep_going()
	check(not game.frozen(), "... until you keep going")


## Where a v2 cell near the Hub is now (see scenario_digging).
func P(x: int, y: int) -> Vector2i:
	return Vector2i((D.W >> 1) + (x - 128) * S, D.GROUND_Y + (y - 40) * S)


func fill(r: Rect2i, m: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			game.sim.set_cell(x, y, m)


func build(type: int, r: Rect2i) -> Object:
	var why: String = game.check_place(type, r)
	if why != "":
		print("  !! can't place %s at %s: %s" % [D.B_NAMES[type], r, why])
		fails += 1
		return null
	var b = game.place(type, r)
	for _i in 900:
		if b.built:
			break
		game.run_ticks(1)
	game.run_ticks(2)
	return b


## What a run looks like from outside, to compare two of them.
func snapshot() -> Dictionary:
	var blds: Array = []
	for b in game.buildings:
		blds.append([b.id, b.type, b.x, b.y, snappedf(b.hp, 0.01), b.built, snappedf(b.power, 0.01)])
	var mites := 0
	for b in game.buildings:
		mites += b.mites.size()
	return {"cells": game.sim.checksum(), "t": game.game_time, "stock": game.stock, "buildings": blds,
			"packets": game.packets.size(), "bodies": game.sim.body_count(), "mites": mites,
			"research": game.tech_power.duplicate(), "marks": game.milestones.size()}


func scenario_c() -> void:
	print("C. save and Continue")
	fresh()
	game.drill.enabled = true
	for id in ["thumper", "warren", "borer"]:
		game.researched[id] = true
	game._refresh_unlocks()
	# A dirt pad left of the Hub (as scenario_warren's) with a Conduit, a Lab and a
	# Warren on it; right of the Drill, a Thumper between two Conduits.
	var hub = game.hub
	var top: int = hub.y + hub.h
	fill(Rect2i(hub.x - 300, hub.y - 140, 300, top - hub.y + 140), D.AIR)
	fill(Rect2i(hub.x - 300, top, 300, 400), D.DIRT)
	build(D.B_CONDUIT, Rect2i(hub.x - 120, top - 20, 20, 20))
	var lab = build(D.B_LAB, Rect2i(hub.x - 200, top - 30, 40, 30))
	game.pick_research("lamp")
	build(D.B_WARREN, Rect2i(hub.x - 90, top - 30, 50, 30))
	fill(Rect2i(P(136, 40), Vector2i(400, 400)).intersection(Rect2i(2, 2, D.W - 4, D.H - 4)), D.DIRT)
	build(D.B_CONDUIT, Rect2i(P(140, 38), Vector2i(20, 20)))
	build(D.B_THUMPER, Rect2i(P(146, 38), Vector2i(20, 20)))
	build(D.B_CONDUIT, Rect2i(P(149, 38), Vector2i(20, 20)))
	secs(45)
	# Caught mid-flight: a blueprint's Stone on its way, a slab of dirt falling.
	game.place(D.B_CONDUIT, Rect2i(hub.x - 250, top - 20, 20, 20))
	fill(Rect2i(hub.x - 280, top - 130, 40, 10), D.DIRT)
	game.sim.make_body(hub.x - 280, top - 130, 40, 10, 0.0, 0.0, 0.0)
	game.run_ticks(20)
	var mites := 0
	for w in game.buildings:
		mites += w.mites.size()
	check(lab != null and lab.built and game.packets.size() > 0 and game.sim.body_count() > 0,
			"a Lab, a Thumper and a Warren at work (%d buildings, %d mites, %d packets, %d bodies)" % [
			game.buildings.size(), mites, game.packets.size(), game.sim.body_count()])
	game.live_run = true
	var headless_was: bool = game.headless
	game.headless = false
	var t0 := Time.get_ticks_msec()
	var ok: bool = game.save_run()
	var took := Time.get_ticks_msec() - t0
	game.headless = headless_was
	var size := FileAccess.get_file_as_bytes(Save.PATH).size()
	check(ok and Save.exists(), "saved (%.1f MB in %d ms)" % [size / 1048576.0, took])
	check(Save.peek().get("seed", -1) == 7, "the header says which seed")
	var saved_t: float = game.game_time
	secs(20)
	var a := snapshot()
	t0 = Time.get_ticks_msec()
	ok = game.continue_run()
	took = Time.get_ticks_msec() - t0
	check(ok and is_equal_approx(game.game_time, saved_t), "Continue loads it (%d ms), back at %.1f s" % [took, game.game_time])
	check(game.hub != null and game.drill != null and game.buildings.has(game.hub) and game.buildings.has(game.drill),
			"the Hub and the Drill are the loaded ones")
	game.paused = true
	secs(20)
	var b := snapshot()
	for k: String in a:
		check(str(a[k]) == str(b[k]), "20 s on, %s match%s" % [k, "" if str(a[k]) == str(b[k]) else ": %s vs %s" % [str(a[k]).left(160), str(b[k]).left(160)]])
	Save.erase()
	check(not Save.exists(), "erased")


func scenario_d() -> void:
	print("D. dragged lines")
	fresh()
	game.stock[D.R_STONE] = 400.0
	# A shaft 30 wide and 700 deep left of the Hub, walled in dirt.
	var hub = game.hub
	var top: int = hub.y + hub.h
	var x0: int = hub.x - 80
	fill(Rect2i(x0 - 60, top, 140, 760), D.DIRT)
	fill(Rect2i(x0, top, 30, 700), D.AIR)
	var a := Vector2i(x0 + 15, top + 12)
	var b := Vector2i(x0 + 15, top + 690)
	var pts: Array = game.line_points(D.B_CONDUIT, a, b)
	var now: int = game.lay_line(D.B_CONDUIT, a, b)
	check(pts.size() >= 5 and now >= 1 and now < pts.size(), "a Conduit line down it: %d laid out, %d at once, %d planned" % [
			pts.size(), now, game.plans.size()])
	var chain: Array = []
	var linked := false
	var n := 0
	while not linked and n < 240:
		secs(1)
		n += 1
		chain.clear()
		for bb in game.buildings:
			if bb.type == D.B_CONDUIT and bb.x >= x0 - 20 and bb.x < x0 + 40:
				chain.append(bb)
		linked = game.plans.is_empty() and chain.size() == pts.size()
		for bb in chain:
			linked = linked and bb.built and bb.connected
	check(game.plans.is_empty() and linked, "%d s later all %d are built and on the network (%d plans left)" % [n, chain.size(), game.plans.size()])
	var deep := 0
	for bb in chain:
		deep = maxi(deep, bb.y)
	check(deep > top + 560, "the chain reaches the bottom (depth %d of %d)" % [deep, top + 700])
	# A row of Hoppers along the ground right of the Drill.
	fill(Rect2i(P(136, 40), Vector2i(300, 60)).intersection(Rect2i(2, 2, D.W - 4, D.H - 4)), D.DIRT)
	build(D.B_CONDUIT, Rect2i(P(140, 38), Vector2i(20, 20)))
	var h0 := Vector2i(P(143, 39).x, D.GROUND_Y - 10)
	var hp: Array = game.line_points(D.B_HOPPER, h0, h0 + Vector2i(100, 0))
	var before: int = game.buildings.size()
	game.lay_line(D.B_HOPPER, h0, h0 + Vector2i(100, 0))
	var hoppers: Array = []
	for bb in game.buildings.slice(before):
		if bb.type == D.B_HOPPER:
			hoppers.append(bb)
	var apart := true
	for i in hoppers.size():
		for j in range(i + 1, hoppers.size()):
			apart = apart and not hoppers[i].rect().intersects(hoppers[j].rect())
	check(hp.size() == 4 and hoppers.size() == hp.size() and apart, "a row of %d Hoppers side by side, none overlapping (%d laid)" % [hp.size(), hoppers.size()])
	# Out into the unexplored: all plans; right-click the third cuts it and the rest.
	game.reveal_all = false
	var c0 := Vector2i(D.W - 60, top + 1200)
	var old: int = game.plans.size()
	game.lay_line(D.B_CONDUIT, c0, c0 + Vector2i(0, 800))
	var planned: int = game.plans.size() - old
	var k: int = game.plan_at(c0 + Vector2i(0, 240))
	if k >= 0:
		game.cut_plans(k)
	check(planned >= 6 and k >= 0 and game.plans.size() - old == 2, "a line into the unexplored waits as %d plans; cut at the third, %d stay" % [planned, game.plans.size() - old])
