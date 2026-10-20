extends SceneTree
## A5 heat processing on seed 7 (A9: the Heater, Chiller and Blender plug into a Tank's side socket):
##  A. a solid put into an interior lies on its floor (not hung at the top), and a `pass` rule with
##     `kinds` or `mats` lets only those out
##  B. the Heater on Boil turns a Tank's Water to Steam and the Tank passes only the gas on; with no power it stays cold
##  C. the Chiller freezes Water and the Tank passes only Ice
##  D. the Heater on Smelt fuses Sand to Glass and smelts Ferrite with Flux to Slag and bars; a click changes the setting
##  E. the Caster plugged into a Tank sets its Lava into a block of Obsidian (a body), and waits for enough liquid
##  F. the Combustor burns the richest fuel first into the Hub's power, and stops when it is full
##  G. casing wear: heat past the melting point and acid cost casing pixels, water and cool rooms do not
##  H. research gates the Build buttons; the material data names what casts and what burns
##  I. the Blender mixes a layered Tank, and a Heater on the same Tank waits while it stirs
##  J. the Heat Dispersal Unit evens out the heat of two Tanks
## Run: godot --headless --path . --script tests/scenario_thermal.gd

# A6: the world is 1024 wide and the Hub moved from x 384 to 512, so every bench x below is the old one plus 128.
const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
var game: Node
var f := 0
var fails := 0
const SURFACE := 200     # ground level (dirt from here down)
const OBSIDIAN := 4
const RUBBLE := 8
const TX := 396          # the feed Tank's left edge in a rig: a machine plugged into its side stays inside the cleared arena
const WATER := 9
const LAVA := 10
const STEAM := 11
const CHUNKS := 23
const SAND := 31
const SLICK := 35
const SOURWATER := 36
const FLUX := 39
const FERRITE := 40
const GLASS := 43
const ICE := 47
const SLAG := 48
const CRUST := 49
const BAR := 53
const TECHS := ["boiler", "chiller", "combustor", "furnace", "caster", "blender", "hdu"]
const MODS := ["heater", "chiller", "combustor", "caster", "blender", "hdu"]


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
	fill(Rect2i(328, SURFACE - 120, 144, 120), D.AIR)
	fill(Rect2i(328, SURFACE, 144, 160), 6)
	fill(Rect2i(328, SURFACE + 160, 144, 40), D.BEDROCK)
	game.stock[D.R_POWER] = 90.0
	for t: String in TECHS:
		game.researched[t] = true
	# A Node on the left edge of the arena: the Hub is 80 cells from a part on that side, so a Blender there would be out of reach.
	var node = game.place(D.B_NODE, Rect2i(352, SURFACE - 20, 20, 20))
	node.built = true
	game.scan_dirty = true
	game.net_dirty = true


func place(def: String, x: int, y: int, turns: int = 0) -> int:
	var id := MC.place(game, def, Vector2i(x, y), turns)
	if id == 0:
		print("  !! can't place %s at %d,%d: %s" % [def, x, y, MC.check_place(game, def, Vector2i(x, y), turns)])
	return id


func until(cond: Callable, limit: float) -> bool:
	for _i in int(limit):
		if cond.call():
			return true
		secs(1.0)
	return cond.call()


func held(id: int, mat: int) -> int:
	return int(game.modules[id]["contents"].get(mat, 0))


## A feed Tank on the ground with the machine `def` plugged into its right socket and, when `out` is set, a second
## Tank on top of the feed Tank.
func rig(def: String, mat: int, n: int, out := true) -> Dictionary:
	fresh()
	var tank := place("tank", TX, SURFACE - 30)
	var sn := MC.snap(game, def, 0, Vector2i(TX + 36, SURFACE - 15))
	var machine := MC.place(game, def, sn["at"], 0)
	var top := 0
	if out:
		var sn2 := MC.snap(game, "tank", 0, Vector2i(TX + 13, SURFACE - 30 - 15))
		top = MC.place(game, "tank", sn2["at"], 0)
	secs(0.2)
	if top != 0:
		MC.JT.hold_rig(game, top, [tank], true)          # a Tank stacked on a Tank slides off, so it is bolted on
	MC.add_contents(game, tank, mat, n)
	secs(0.5)
	return {"tank": tank, "vessel": machine, "top": top, "snapped": sn["snapped"]}


func scenario_a() -> void:
	print("A. solids lie on the floor, `pass` filters")
	fresh()
	var tank := place("tank", 428, SURFACE - 30)
	MC.add_contents(game, tank, ICE, 20)
	var m: Dictionary = game.modules[tank]
	var b: Rect2i = m["box"]
	var floor_ice: int = m["sim"].rect_counts(b.position.x, b.end.y - 1, b.size.x, 1)[ICE]
	check(floor_ice == 20, "20 Ice lie on the floor row of the interior (%d there)" % floor_ice)
	MC.add_contents(game, tank, SAND, 30)
	secs(1.0)
	var rule := {"mats": ["Ice", "Glass"]}
	check(MC.MU.passes(rule, ICE) and not MC.MU.passes(rule, SAND), "`mats` lets Ice through and not Sand")
	var gas := {"kinds": ["gas"]}
	check(MC.MU.passes(gas, STEAM) and not MC.MU.passes(gas, WATER) and not MC.MU.passes(gas, ICE), "`kinds` lets gas through and not liquid or solid")
	check(MC.MU.passes({}, WATER), "with neither, everything goes")


func scenario_b() -> void:
	print("B. Heater on Boil")
	var r := rig("heater", WATER, 160)
	check(r["snapped"], "the Heater plugs into the Tank's side")
	var b: Dictionary = game.modules[r["vessel"]]
	var tank: int = r["tank"]
	var top: int = r["top"]
	var peak := [0]
	check(until(func() -> bool:
			peak[0] = maxi(peak[0], int(b["heat"]))
			return held(top, STEAM) + held(top, WATER) >= 10, 40.0), "Steam comes out of the top into the second Tank (%d Steam, %d Water)" % [held(top, STEAM), held(top, WATER)])
	check(peak[0] >= 50, "the Heater warmed the Tank's load well past room temperature (average peaked at %d degrees)" % peak[0])
	check(held(tank, WATER) < 160, "the feed Tank gave up Water (%d left)" % held(tank, WATER))
	check(held(top, ICE) == 0 and held(top, WATER) <= held(top, STEAM) + 10, "no liquid Water came through unboiled (%d Water, %d Steam)" % [held(top, WATER), held(top, STEAM)])
	r = rig("heater", WATER, 160)
	b = game.modules[r["vessel"]]
	for _i in 900:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(held(r["top"], STEAM) == 0 and held(r["tank"], WATER) > 0 and "power" in b["state"].to_lower(), "with no power it stays cold and passes nothing (%s)" % b["state"])
	r = rig("heater", WATER, 160)
	secs(1.0)
	check(held(r["top"], WATER) == 0, "the Tank holds its Water back while the Heater is on it (%d Water went up)" % held(r["top"], WATER))
	MC.remove(game, r["vessel"])
	secs(3.0)
	check(held(r["top"], WATER) > 0, "and lets it go once the Heater is gone (%d Water went up)" % held(r["top"], WATER))


func scenario_c() -> void:
	print("C. Chiller")
	var r := rig("chiller", WATER, 120)
	var top: int = r["top"]
	check(until(func() -> bool: return held(top, ICE) >= 30, 60.0), "Ice comes out of the top into the second Tank (%d Ice)" % held(top, ICE))
	check(held(top, WATER) == 0, "and no Water with it (%d)" % held(top, WATER))
	check(int(game.modules[r["vessel"]]["heat"]) <= 0, "the Chiller's coldest cell is below freezing (%d degrees)" % int(game.modules[r["vessel"]]["heat"]))


func scenario_d() -> void:
	print("D. Heater on Smelt")
	var r := rig("heater", SAND, 120)
	var top: int = r["top"]
	var hot: Dictionary = game.modules[r["vessel"]]
	var cfg: Dictionary = MC.defs["heater"]
	game.researched.erase("furnace")
	check(MC.kinds["thermal"].modes(game, cfg).size() == 1, "without Smelting researched the Heater has one setting")
	MC.kinds["thermal"].use(game, hot, cfg)
	check(hot.get("mode", 0) == 0, "and a click leaves it on Boil")
	game.researched["furnace"] = true
	MC.kinds["thermal"].use(game, hot, cfg)
	check(hot.get("mode", 0) == 1 and "Smelt" in hot["state"], "with it a click sets Smelt (%s)" % hot["state"])
	check(until(func() -> bool: return held(top, GLASS) >= 30, 90.0), "Sand fuses to Glass and goes out of the top (%d Glass, %d Sand left in the Tank)" % [held(top, GLASS), held(r["tank"], SAND)])
	check(held(top, SAND) == 0, "no Sand went through with it (%d)" % held(top, SAND))
	r = rig("heater", FERRITE, 80)
	game.modules[r["vessel"]]["mode"] = 1
	MC.add_contents(game, r["tank"], FLUX, 40)
	var top2: int = r["top"]
	var fur: Dictionary = game.modules[r["vessel"]]
	var forged := until(func() -> bool: return held(top2, BAR) >= 12, 150.0)
	var slag := held(top2, SLAG) + held(top2, CRUST) + held(r["tank"], SLAG) + held(r["tank"], CRUST)
	check(slag > 0, "Ferrite with Flux smelts to Slag (%d cells)" % slag)
	check(forged, "and bars come out of the top (%d bar cells; the Heater reads %d degrees)" % [held(top2, BAR), int(fur["heat"])])
	check(held(top2, FERRITE) == 0 and held(top2, FLUX) == 0, "unsmelted Ferrite and Flux stay in the Tank")


func scenario_e() -> void:
	print("E. Caster")
	var r := rig("caster", LAVA, 120, false)
	var c: Dictionary = game.modules[r["vessel"]]
	check(until(func() -> bool: return c.get("blocks", 0) >= 1, 40.0), "it casts a block (%s)" % c["state"])
	var found := false
	var mods := {}
	for mid: int in game.modules:
		mods[game.modules[mid]["body"]] = true
	var bl: PackedInt32Array = game.sim.get_bodies()
	for k in range(0, bl.size(), 7):
		if not mods.has(bl[k]) and bl[k + 4] < SURFACE + 100:
			var px: PackedByteArray = game.sim.body_pixels(bl[k])
			found = found or (px.size() > 0 and px.count(OBSIDIAN) == 96)
	check(found, "a loose body of 96 Obsidian cells")
	var left := held(r["tank"], LAVA)
	check(left == 24, "paid for with 96 cells of Lava (%d left)" % left)
	r = rig("caster", LAVA, 40, false)
	c = game.modules[r["vessel"]]
	secs(8.0)
	check(c.get("blocks", 0) == 0 and "Waiting for liquid" in c["state"], "short of liquid it waits (%s)" % c["state"])
	check(M.cast_of(LAVA) == OBSIDIAN and M.cast_of(WATER) == ICE and M.cast_of(SLAG) == CRUST and M.cast_of(SAND) == -1, "the data says what casts to what")


func scenario_f() -> void:
	print("F. Combustor")
	fresh()
	game.stock[D.R_POWER] = 10.0
	var tank := place("tank", 428, SURFACE - 30)
	var sn := MC.snap(game, "combustor", 0, Vector2i(441, SURFACE - 30 - 9))
	var comb := MC.place(game, "combustor", sn["at"], 0)
	MC.add_contents(game, tank, SLICK, 10)
	MC.add_contents(game, tank, CHUNKS, 10)
	secs(3.5)
	var c: Dictionary = game.modules[comb]
	var burned: int = c.get("burned", 0)
	var slick_left := held(tank, SLICK) + held(comb, SLICK)
	var chunks_left := held(tank, CHUNKS) + held(comb, CHUNKS)
	check(burned >= 2 and burned <= 5, "it burns a cell a second (%d burned in 3.5 s)" % burned)
	check(slick_left == 10 - burned and chunks_left == 10, "Slick, the richer fuel, goes first (%d Slick, %d Coal chunks left)" % [slick_left, chunks_left])
	check(game.stock[D.R_POWER] >= 10.0 + 3.0 * float(burned) - 0.01, "and its power reaches the Hub's store (%.1f)" % game.stock[D.R_POWER])
	game.stock[D.R_POWER] = game.power_cap()
	var before: int = c.get("burned", 0)
	secs(3.0)
	check(c.get("burned", 0) == before and "full" in c["state"], "with the store full it burns nothing (%s)" % c["state"])


func scenario_g() -> void:
	print("G. casing wear")
	fresh()
	var tank := place("tank", 428, SURFACE - 30)
	MC.add_contents(game, tank, WATER, 20)
	secs(1.0)
	var m: Dictionary = game.modules[tank]
	check(m["integrity"] == 1.0, "a Tank with Water in it is whole")
	var b: Rect2i = m["box"]
	m["sim"].heat_rect(b.position.x, b.position.y, b.size.x, b.size.y, 1500)
	secs(0.8)
	check(m["integrity"] < 0.97 and game.modules.has(tank), "heat past the melting point wears the casing away (integrity %.2f)" % m["integrity"])
	check(m.get("worn", false) and not game.alerts.is_empty(), "and raises an alert")
	fresh()
	tank = place("tank", 428, SURFACE - 30)
	MC.add_contents(game, tank, WATER, 20)
	m = game.modules[tank]
	var b2: Rect2i = m["box"]
	m["sim"].heat_rect(b2.position.x, b2.position.y, b2.size.x, b2.size.y, 400)
	secs(2.0)
	check(m["integrity"] == 1.0, "a hot room below the melting point does no harm (integrity %.2f)" % m["integrity"])
	fresh()
	tank = place("tank", 428, SURFACE - 30)
	var tank2 := place("tank", 378, SURFACE - 30)
	MC.add_contents(game, tank, SOURWATER, 400)
	MC.add_contents(game, tank2, WATER, 400)
	secs(40.0)
	check(game.modules.has(tank) and game.modules[tank]["integrity"] < 0.97, "Sourwater eats the casing (integrity %.2f)" % game.modules[tank]["integrity"])
	check(game.modules[tank2]["integrity"] == 1.0, "plain Water does not (integrity %.2f)" % game.modules[tank2]["integrity"])


func scenario_h() -> void:
	print("H. research and data")
	fresh()
	for t: String in TECHS:
		game.researched.erase(t)
	var locked := true
	for t: String in MODS:
		locked = locked and not MC.unlocked(game, MC.defs[t])
	check(locked, "all six are locked at first")
	for t: String in TECHS:
		game.researched[t] = true
	var open := true
	for t: String in MODS:
		open = open and MC.unlocked(game, MC.defs[t])
	check(open, "and open once researched")
	check(M.fuel_of(SLICK) > M.fuel_of(CHUNKS) and M.fuel_of(CHUNKS) > 0.0 and M.fuel_of(SAND) == 0.0, "the data says what burns and for how much")
	for t: String in MODS:
		var i: int = D.tech_index(MC.defs[t]["tech"])
		check(i >= 0 and D.TECHS[i].get("module", "") == t, "%s has its tech" % t)
	var sm: int = D.tech_index("furnace")
	check(sm >= 0 and D.TECHS[sm].get("module", "") == "heater", "Smelting is the Heater's second setting")
	check(MC.defs["case"]["melts"] > MC.defs["tank"].get("melts", 1150), "a Case stands more heat than a Tank")


## Cells of `mat` in the bottom ten rows of Tank `id`'s box.
func low_half(id: int, mat: int) -> int:
	var m: Dictionary = game.modules[id]
	var b: Rect2i = m["box"]
	return m["sim"].rect_counts(b.position.x, b.end.y - 10, b.size.x, 10)[mat]


func scenario_i() -> void:
	print("I. Blender")
	fresh()
	var tank := place("tank", TX, SURFACE - 30)
	var box: Rect2i = game.modules[tank]["box"]
	for y in range(box.end.y - 14, box.end.y):                 # 14 rows of Sand under 14 rows of Rubble, laid by hand
		for x in range(box.position.x, box.end.x):
			game.modules[tank]["sim"].set_cell(x, y, SAND)
			game.modules[tank]["sim"].set_cell(x, y - 14, RUBBLE)
	secs(1.0)
	var before := low_half(tank, RUBBLE)
	check(before == 0, "a layered Tank has no Rubble at the bottom to start with (%d cells in the bottom ten rows)" % before)
	var sn := MC.snap(game, "blender", 0, Vector2i(TX + 36, SURFACE - 15))
	var bl := MC.place(game, "blender", sn["at"], 0)
	check(sn["snapped"] and game.modules[bl]["needs"] == "", "the Blender plugs into the Tank's side")
	var b: Dictionary = game.modules[bl]
	check(until(func() -> bool: return b.get("stirring", false), 10.0), "the Blender starts stirring once the Tank holds two materials (%s)" % b["state"])
	check(until(func() -> bool: return not b.get("stirring", false) and b.get("stirred", "") != "", 20.0), "and stops after a few seconds (%s)" % b["state"])
	var after := low_half(tank, RUBBLE)
	check(after > before + 60, "the Rubble is mixed down through the Sand (%d cells in the bottom ten rows, was %d)" % [after, before])
	secs(6.0)
	check(not b.get("stirring", false), "it does not stir again until something new arrives (%s)" % b["state"])
	game.stock[D.R_POWER] = 0.0
	MC.add_contents(game, tank, WATER, 40)
	for _i in 300:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(not b.get("stirring", false) and "power" in b["state"].to_lower(), "with no power it stirs nothing (%s)" % b["state"])
	# A Heater on the other side waits while the Blender stirs.
	fresh()
	tank = place("tank", TX, SURFACE - 30)
	var hs := MC.snap(game, "heater", 0, Vector2i(TX + 36, SURFACE - 15))
	var heater := MC.place(game, "heater", hs["at"], 0)
	var bs := MC.snap(game, "blender", 0, Vector2i(TX - 10, SURFACE - 15))
	bl = MC.place(game, "blender", bs["at"], 0)
	check(hs["snapped"] and bs["snapped"], "a Heater on one socket and a Blender on the other")
	MC.add_contents(game, tank, SAND, 40)
	MC.add_contents(game, tank, WATER, 40)
	var h: Dictionary = game.modules[heater]
	b = game.modules[bl]
	var held_up := [false]
	var line_seen := [""]
	var heated := until(func() -> bool:
			if b.get("stirring", false) and h.get("waits", "") != "":
				held_up[0] = true
				line_seen[0] = MC.LY.line(game, h)
			return "Heating" in h.get("state", ""), 40.0)
	check(held_up[0], "the Heater holds while the Blender stirs")
	check("Blender" in line_seen[0] and "stirring" in line_seen[0], "and the overseer says so (%s)" % line_seen[0])
	check(heated and h.get("waits", "") == "", "then it heats the mix (%s)" % h["state"])


func scenario_j() -> void:
	print("J. Heat Dispersal Unit")
	fresh()
	var ta := place("tank", TX, SURFACE - 30)
	var hs := MC.snap(game, "hdu", 0, Vector2i(TX + 33, SURFACE - 8))
	var hdu := MC.place(game, "hdu", hs["at"], 0)
	var tbs := MC.snap(game, "tank", 0, Vector2i(TX + 53, SURFACE - 15))
	var tb := MC.place(game, "tank", tbs["at"], 0)
	check(hs["snapped"] and tbs["snapped"], "a Heat Dispersal Unit joins two Tanks")
	MC.add_contents(game, ta, SAND, 200)
	MC.add_contents(game, tb, SAND, 200)
	secs(1.0)
	var a: Dictionary = game.modules[ta]
	var bm: Dictionary = game.modules[tb]
	a["sim"].heat_rect(a["box"].position.x, a["box"].position.y, a["box"].size.x, a["box"].size.y, 300)
	var hot0: int = MC.kinds["hdu"].average(a).x
	var cold0: int = MC.kinds["hdu"].average(bm).x
	check(hot0 - cold0 > 200, "one Tank is hot and the other cold (%d and %d degrees)" % [hot0, cold0])
	var even := until(func() -> bool: return absi(MC.kinds["hdu"].average(a).x - MC.kinds["hdu"].average(bm).x) < 30, 60.0)
	var hot1: int = MC.kinds["hdu"].average(a).x
	var cold1: int = MC.kinds["hdu"].average(bm).x
	check(even, "the heat evens out (%d and %d degrees)" % [hot1, cold1])
	check(hot1 > cold0 + 40 and hot1 < hot0 and cold1 > cold0 + 40, "the cold Tank warmed as the hot one cooled (%d to %d, %d to %d)" % [cold0, cold1, hot0, hot1])
	# With no power it moves nothing.
	a["sim"].heat_rect(a["box"].position.x, a["box"].position.y, a["box"].size.x, a["box"].size.y, 200)
	var cold2: int = MC.kinds["hdu"].average(bm).x
	for _i in 300:
		game.stock[D.R_POWER] = 0.0
		game.run_ticks(1)
	check(MC.kinds["hdu"].average(bm).x <= cold2 + 3 and "power" in game.modules[hdu]["state"].to_lower(), "with no power the cold Tank stays cold (%s)" % game.modules[hdu]["state"])
	# Without a Tank on both sides it does nothing and says why.
	MC.remove(game, tb)
	secs(1.0)
	check("base" in game.modules[hdu]["state"].to_lower() or "Needs" in game.modules[hdu]["state"], "with one Tank gone it says what is missing (%s)" % game.modules[hdu]["state"])
