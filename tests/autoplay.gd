extends SceneTree
## Autoplay bot (phase 10). Plays a whole run headless through the game's own
## calls (place, lay_line, pick_research, Borer headings, activate_crucible) and
## prints the milestones with their times, so the pace can be tuned against it.
## It knows the map (it reads cells and the generator's info), so it measures how
## long the loop takes when you know where things are, not how hard it is to
## work out: a person should take about twice as long.
##
## The plan: a Lab researches the Drill down to the Stone band; a Borer opens the
## shaft on down to the hot rock; Borers sweep sideways along the richest glimmer
## bands (Tier 2); a Hopper at the shaft's foot drinks what water comes down it; a
## Thumper blasts down through the hot rock to lava (Tier 3); the Coolant Jacket and
## the last Drill Shaft levels take the Drill down to the bedrock; a Borer goes
## across to the plug and down it into the chamber (Tier 4); water poured on lava
## makes obsidian for the Borers to cut; Caches stock power by the Crucible; then
## it's lit.
##
## godot --headless --path . --script tests/autoplay.gd -- --seed=7 [--max=7200] [--quiet]
##   [--save=SECONDS] (checkpoint to user://bot_<seed>_<t>.save) [--load=PATH] [--dump=SECONDS]

const D = preload("res://scripts/defs.gd")
const Save = preload("res://scripts/save.gd")

var game: Node
var seed_value := 7
var max_time := 7200.0
var quiet := false
var save_at := -1.0
var load_from := ""
var dump_at := -1.0
var f := 0
var shown := 0                  # milestones printed so far
var last_status := -1.0
var jobs: Array = []            # what it's doing now, for the status line
var st := {}                    # the bot's own state (plain data, so checkpoints keep it)

# Research, in the order it wants it (upgrades repeat once per level).
const PLAN := ["drill_shaft", "drill_bit", "drill_shaft", "drill_shaft", "borer", "drill_shaft",
	"thumper", "thump_charge", "drill_shaft", "drill_shaft", "drill_bit",
	"coolant_jacket", "obsidian_saw", "drill_shaft",
	# while it waits on materials for the above
	"borer_cells", "thump_rhythm", "thump_efficiency", "cache", "lamp", "waterwheel", "spout"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--max="):
			max_time = float(a.substr(6))
		elif a == "--quiet":
			quiet = true
		elif a.begins_with("--save="):
			save_at = float(a.substr(7))
		elif a.begins_with("--load="):
			load_from = a.substr(7)
		elif a.begins_with("--dump="):
			dump_at = float(a.substr(7))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	if f == 2:
		setup()
	for _s in 10:
		game.run_ticks(60)
		think()
		report()
		if save_at > 0.0 and game.game_time >= save_at:
			checkpoint()
			save_at = -1.0
		if dump_at > 0.0 and game.game_time >= dump_at:
			dump_at = -1.0
			dump_shaft()
		if game.won or game.run_lost or game.game_time >= max_time:
			finish()
			return true
	return false


func setup() -> void:
	if load_from != "":
		if not game.continue_run(load_from):
			print("can't load ", load_from)
			quit()
			return
		var f2 := FileAccess.open(load_from + ".bot", FileAccess.READ)
		st = f2.get_var()
		seed_value = game.seed_value
		shown = game.milestones.size()
		print("loaded %s at %s" % [load_from, clock(game.game_time)])
		return
	game.new_game(seed_value)
	var sz: Vector2i = D.B_SIZES[D.B_LAB]
	game.place(D.B_LAB, Rect2i((D.W >> 1) - 10 * D.S, D.GROUND_Y - sz.y, sz.x, sz.y))
	st = {"chain_to": 0, "routes": {}, "swept": {}, "wait": {}, "deep": "", "tries": 0}
	print("seed %d: plug at x %d, Crucible %s" % [seed_value, game.info["plug_x"], game.info["crucible"]])


func checkpoint() -> void:
	var path := "user://bot_%d_%d.save" % [seed_value, int(game.game_time)]
	Save.write(game, path)
	var f2 := FileAccess.open(path + ".bot", FileAccess.WRITE)
	f2.store_var(st)
	f2.close()
	print("%s  checkpoint: %s" % [clock(game.game_time), ProjectSettings.globalize_path(path)])


# --- Thinking, once a game second ------------------------------------------------

func think() -> void:
	jobs.clear()
	game.pause_on_breach = false
	research()
	shaft_chain()
	drive_borers()
	deep_shaft()
	glimmer()
	water()
	lava()
	descent()
	plug()
	crucible()


func waiting(job: String) -> bool:
	return game.game_time < st["wait"].get(job, 0.0)


func wait(job: String, s: float) -> void:
	st["wait"][job] = game.game_time + s


func by_id(id: int) -> Object:
	for b in game.buildings:
		if b.id == id:
			return b
	return null


## The first tech in PLAN it can research and pay the materials for. Progress
## on one it leaves while short of materials is kept for later.
func research() -> void:
	# A Borer charging up, or starved, gets the power first.
	for id: int in st["routes"]:
		var b = by_id(id)
		if b != null and b.enabled and b.connected and (b.mode == 2 or b.starved):
			game.current_tech = ""
			jobs.append("research held for a Borer")
			return
	var cur: String = game.current_tech
	if cur != "" and not _short(cur):
		return
	var want := {}
	for id: String in PLAN:
		want[id] = want.get(id, 0) + 1
		if game.level(id) < want[id] and game.tech_block(id) == "" and not _short(id):
			if id != cur:
				game.pick_research(id)
			return


## The Labs still want materials for `id` that the stock doesn't have (past
## Tier 3, keeping back what the Crucible will want).
func _short(id: String) -> bool:
	var need: Array = game.tech_mats_needed(game.tech_step(id))
	var got: PackedFloat64Array = game.tech_mats_got(id)
	for r in D.NRES:
		var keep: float = D.RECIPE[r] if game.tiers_open[3] else 0.0
		if need[r] - got[r] > 0.001 and need[r] - got[r] > game.total(r) - keep + 0.001:
			return true
	return false


# --- The shaft ----------------------------------------------------------------------

## The deepest open row straight down the Drill's shaft: its head, or further
## where a Borer has gone on down. Read down its right side, clear of the chain
## on the left wall; anything of the bot's standing in it is the bottom.
func shaft_bottom() -> int:
	var d = game.drill
	var x: int = d.x + 25
	var y := int(d.drill_head().y)
	while y < D.H - 4 and not D.is_solid(game.sim.get_cell(x, y)):
		y += 1
	return y


## The rock under the shaft: its bottom, looking past anything standing in it.
func shaft_floor() -> int:
	var d = game.drill
	var x: int = d.x + 25
	var y := int(d.drill_head().y)
	while y < D.H - 4:
		var m: int = game.sim.get_cell(x, y)
		if D.is_solid(m) and m != D.BUILDING:
			break
		y += 1
	return y


## Where something sent from the bottom of the shaft stands.
func shaft_foot(h := 30) -> Rect2i:
	var d = game.drill
	return Rect2i(d.x, shaft_bottom() - h, 30, h)


## A Conduit line down the Drill's shaft against its left wall (so nothing
## snaps), a relay's spacing apart, and to just over its bottom (where something
## sent from it stands within reach) when something wants to stand there.
func shaft_chain() -> void:
	var d = game.drill
	var x: int = d.x + 10
	if st["chain_to"] == 0:
		st["chain_to"] = d.y + d.h - 108
	# The top of what has to be in reach: a Borer going on down the shaft (not the
	# debris riding on it), or whatever is sent from the foot.
	var top := shaft_bottom() - 30
	var follow := false
	for id: int in st["routes"]:
		var b = by_id(id)
		if b != null and not st["routes"][id]["trail"] and b.x == d.x and b.y > top:
			top = b.y
			follow = b.starved or b.stuck != ""      # it's waiting on power: close the gap
	var last_y := top - 35
	var gap: int = last_y - st["chain_to"]
	if gap < 120 and not ((follow or st.get("need_foot", false)) and st["chain_to"] < top - 70):
		return
	st["need_foot"] = false
	var a := Vector2i(x, mini(st["chain_to"] + 120, last_y))
	var b := Vector2i(x, last_y)
	game.lay_line(D.B_CONDUIT, a, b)
	st["chain_to"] = game.line_points(D.B_CONDUIT, a, b).back().y
	jobs.append("chain to %d" % st["chain_to"])


## Something of the shaft's (a Conduit, a plan for one) where a Borer at row y in
## the shaft would stand.
func _chain_near(y: int) -> bool:
	var d = game.drill
	var r := Rect2i(d.x, y - 2, 30, 34)
	for b in game.buildings:
		if b != d and b.rect().intersects(r):
			return true
	for p in game.plans:
		if game.footprint(p["type"], p["at"], p["horiz"]).intersects(r):
			return true
	return false


## Something of the bot's standing in the shaft's column at its foot.
func foot_taken() -> bool:
	var d = game.drill
	var r := shaft_foot(60)
	for b in game.buildings:
		if b.type != D.B_CONDUIT and b.rect().intersects(r) and b != d:
			return true
	return false


# --- Borers --------------------------------------------------------------------------
# Each one the bot sends has a route: legs of [heading, stop], where the stop is
# the row (heading down or up) or column (left or right) its middle must reach
# before it turns onto the next leg. It's taken back (half its cost) at the end,
# or when something it can't cut stops it.

## A Borer at `r` (or the nearest legal spot) heading off along `legs`, or null
## if it can't go there. `trail`: a Conduit line follows it.
func send_borer(r: Rect2i, legs: Array, why: String, trail := true, snap := true) -> Object:
	var reason: String = game.check_place(D.B_BORER, r)
	if reason != "" and snap:
		r = game.snap_place(D.B_BORER, Vector2i(r.get_center()), false)
		reason = game.check_place(D.B_BORER, r)
	if reason != "":
		print("%s  !! no Borer at %s (%s): %s" % [clock(game.game_time), r, why, reason])
		return null
	var b = game.place(D.B_BORER, r, legs[0][0])
	st["routes"][b.id] = {"legs": legs, "leg": 0, "why": why, "trail": trail, "last": Vector2i(r.get_center()), "cut": 0,
			"start": Vector2i(r.get_center())}
	return b


## Demolish the Conduits (and cut the plans) along a finished Borer's tunnel,
## leaving the shaft's own chain.
func _take_back_trail(area: Rect2i) -> void:
	var d = game.drill
	for b in game.buildings.duplicate():
		if b.type == D.B_CONDUIT and area.intersects(b.rect()) and (b.x + b.w < d.x - 2 or b.x > d.x + d.w + 2):
			game.demolish(b)
	for k in range(game.plans.size() - 1, -1, -1):
		if area.has_point(game.plans[k]["at"]):
			game.plans.remove_at(k)


## Keep a Conduit line close behind a Borer: from the last point laid toward its
## tail, a relay's spacing at a time, planned (they go down once it's open).
func _follow(b, rt: Dictionary) -> void:
	var tail := Vector2i(b.center()) - Vector2i(game.BORER_STEPS[b.dir]) * 40
	var last: Vector2i = rt["last"]
	if Vector2(tail - last).length() < 110.0:
		return
	var pts: Array = game.line_points(D.B_CONDUIT, last, tail)
	if pts.size() < 2:
		return
	game.lay_line(D.B_CONDUIT, pts[1], pts[pts.size() - 1])
	rt["last"] = pts[pts.size() - 1]


func drive_borers() -> void:
	for id: int in st["routes"].keys():
		var b = by_id(id)
		var rt: Dictionary = st["routes"][id]
		if b == null:
			st["routes"].erase(id)
			continue
		var legs: Array = rt["legs"]
		var k: int = rt["leg"]
		var c: Vector2 = b.center()
		if rt["trail"] and b.mode == 0:
			_follow(b, rt)
		if k < legs.size():
			var dir: int = legs[k][0]
			var stop: int = legs[k][1]
			if (dir == 0 and c.y >= stop) or (dir == 3 and c.y <= stop) or (dir == 1 and c.x <= stop) or (dir == 2 and c.x >= stop):
				rt["leg"] = k + 1
				if k + 1 < legs.size():
					game.set_borer_dir(b, legs[k + 1][0])
				else:
					b.enabled = false
		# Cut off from the network with an empty reserve for half a minute: written off.
		if b.starved and not b.connected:
			rt["cut"] += 1
			if rt["why"] == "deep":
				st["need_foot"] = true     # the shaft's chain catches it up
			elif rt["cut"] >= 30:
				print("%s  !! Borer (%s) cut off at %s" % [clock(game.game_time), rt["why"], c])
				b.enabled = false
		else:
			rt["cut"] = 0
		# Hot rock before the Coolant Jacket: glimmer Borers wait for it; the rest are done.
		var hot: bool = b.stuck.begins_with("Hot rock") and not game.researched.has("coolant_jacket")
		if not b.enabled or (b.stuck != "" and b.stuck != game.DRY and not (hot and rt["why"] == "glimmer")):
			if b.stuck != "" and not quiet:
				print("%s  Borer (%s) done at %d,%d: %s" % [clock(game.game_time), rt["why"], int(c.x), int(c.y), b.stuck])
			st["routes"].erase(id)
			game.demolish(b)
			if rt["why"] == "glimmer":
				_take_back_trail(Rect2i(mini(rt["start"].x, int(c.x)) - 20, int(c.y) - 30, absi(rt["start"].x - int(c.x)) + 40, 60))
			continue
		jobs.append("Borer (%s) %d/%d at %d,%d%s" % [rt["why"], rt["leg"] + 1, legs.size(), int(c.x), int(c.y),
				"" if b.stuck == "" else ": " + b.stuck])


func _busy(why: String) -> int:
	var n := 0
	for id: int in st["routes"]:
		if st["routes"][id]["why"] == why:
			n += 1
	return n


## A Borer from the shaft's foot straight down until the hot rock stops it, so the
## whole Stone band opens off the shaft. The chain follows it down.
func deep_shaft() -> void:
	if st["deep"] == "sent" and _busy("deep") == 0:
		st["deep"] = "done"
		print("%s  the shaft is open to %d" % [clock(game.game_time), shaft_bottom()])
	if st["deep"] != "" or not game.researched.has("borer") or game.level("drill_shaft") < 4 or waiting("deep"):
		return
	var d = game.drill
	if d.reach < d.reach_limit:
		return
	st["need_foot"] = true
	if send_borer(shaft_foot(), [[0, D.H - 10]], "deep", false) != null:
		st["deep"] = "sent"
	else:
		wait("deep", 20.0)


# --- Glimmer: Borers along the richest bands ------------------------------------------
# Out of the shaft sideways along a 30-row band to the map's edge, a Conduit line
# following. Before Tier 2 any glimmer will do; after, the richest band left.

func glimmer() -> void:
	if st["deep"] != "done" or waiting("glimmer") or _busy("glimmer") >= 2:
		return
	var mask := _mask([D.GLIMMER])
	var d = game.drill
	var bottom := shaft_bottom()
	var best := {}
	var least := 1 if not game.tiers_open[2] else 600      # cells: any at first, then several units' worth
	for y in range(D.LAYERS[2]["top"], bottom - 70, 10):
		if _chain_near(y):
			continue
		for side in [1, 2]:
			var key := "%d %d" % [floori(y / 30.0), side]
			if st["swept"].has(key):
				continue
			var x0: int = 4 if side == 1 else d.x + d.w
			var x1: int = d.x if side == 1 else D.W - 4
			var n: int = game.sim.count_in_rect(x0, y, x1 - x0, 30, mask)
			if n >= least and n > best.get("n", 0):
				best = {"y": y, "side": side, "key": key, "n": n}
	if best.is_empty():
		wait("glimmer", 30.0)
		return
	var side: int = best["side"]
	st["swept"][best["key"]] = true
	if send_borer(Rect2i(d.x, best["y"], 30, 30), [[side, 24 if side == 1 else D.W - 24]], "glimmer") == null:
		wait("glimmer", 10.0)
		return
	if not quiet:
		print("%s  glimmer: a Borer out along row %d going %s (%d cells of it)" % [clock(game.game_time), best["y"],
				"left" if side == 1 else "right", best["n"]])


func _mask(mats: Array) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(256)
	for k: int in mats:
		m[k] = 1
	return m


# --- Water: a Hopper at the shaft's foot ------------------------------------------

func water() -> void:
	if waiting("water"):
		return
	wait("water", 5.0)
	var d = game.drill
	var hopper = by_id(st.get("hopper", -1))
	# The Drill has further to go: out of its way.
	if hopper != null and d.reach < d.reach_limit and d.stuck == "":
		game.demolish(hopper)
		st.erase("hopper")
		return
	if hopper != null or foot_taken() or st.get("descent", "") == "sent":
		return
	var foot := shaft_foot(20)
	var wet: int = game.sim.count_in_rect(foot.position.x, foot.position.y - 60, 30, 80, _mask([D.WATER]))
	if wet < 60:
		return
	st["need_foot"] = true
	var r: Rect2i = game.snap_place(D.B_HOPPER, Vector2i(foot.get_center()), false)
	if game.check_place(D.B_HOPPER, r) == "":
		st["hopper"] = game.place(D.B_HOPPER, r).id
		if not quiet:
			print("%s  a Hopper at the shaft's foot (%d) for the water coming down" % [clock(game.game_time), r.position.y])


# --- Tier 3: a Thumper down through the hot rock to lava ----------------------------------
# The lava with the least hot rock over it: a Borer along just above the hot line
# to over it (a Conduit line following), then a Thumper from the end of that
# tunnel, blasting its way down.

## The first row of hot rock down column x (from the Stone band's bottom).
func hot_top(x: int) -> int:
	var y: int = D.HOT_TOP - 80
	while y < D.H - 4 and game.sim.get_cell(x, y) != D.HOT_ROCK:
		y += 1
	return y


func lava() -> void:
	if game.tiers_open[3] or st["deep"] != "done" or waiting("lava"):
		return
	if game.level("thump_charge") < 1 or not game.is_unlocked(D.B_THUMPER):
		return
	var t = by_id(st.get("thumper", -1))
	if t != null:
		jobs.append("Thumper at %d (%d blasts, power %.1f%s)" % [t.y, t.blasts, t.power, "" if t.connected else ", off the network"])
		# A Conduit line down its hole after it, so it can link when it lands.
		var last: Vector2i = st.get("lava_last", Vector2i(t.center()))
		var to := Vector2i(t.center()) - Vector2i(0, 45)
		if not t.connected and not t.flying and to.y - last.y > 90:
			var pts: Array = game.line_points(D.B_CONDUIT, last, to)
			if pts.size() >= 2:
				game.lay_line(D.B_CONDUIT, pts[1], pts.back())
				st["lava_last"] = pts.back()
		return
	if _busy("lava") > 0 or st["tries"] >= 6:
		return
	var d = game.drill
	var sx: int = d.x + 15
	if not st.has("lava_x"):
		# Pick the pocket: fewest rows of hot rock over it, then the shorter way across.
		var best_score := INF
		var pockets: Array = game.info["lava_pockets"].duplicate()
		pockets.append(game.info["lake"])
		for pr: Rect2i in pockets:
			var cx := pr.get_center().x
			var ly := pr.position.y
			while ly < pr.end.y and game.sim.get_cell(cx, ly) != D.LAVA:
				ly += 1
			if ly >= pr.end.y:
				continue
			var hot := ly - hot_top(cx)
			var score := hot + absi(cx - sx) * 0.1
			if score < best_score:
				best_score = score
				st["lava_x"] = clampi(cx, 30, D.W - 30)
				st["lava_y"] = ly
		print("%s  lava: aiming for %d,%d" % [clock(game.game_time), st.get("lava_x", -1), st.get("lava_y", -1)])
	var lx: int = st.get("lava_x", sx)
	if absi(lx - sx) > 20 and not st.get("lava_tunnel", false):
		# Along a row clear of the hot line all the way across, as low as the shaft
		# and its chain allow.
		var row := hot_top(sx)
		for x in range(mini(sx, lx), maxi(sx, lx) + 1, 4):
			row = mini(row, hot_top(x))
		row = mini(row - 40, shaft_bottom() - 32)
		var b = null
		for k in 12:
			if not _chain_near(row) and game.check_place(D.B_BORER, Rect2i(d.x, row, 30, 30)) == "":
				b = send_borer(Rect2i(d.x, row, 30, 30), [[2 if lx > sx else 1, lx], [0, st["lava_y"]]], "lava", true, false)
				break
			row -= 10
		if b == null:
			print("%s  !! no row for the lava tunnel" % clock(game.game_time))
			wait("lava", 30.0)
			return
		st["lava_tunnel"] = true
		st["lava_row"] = row
		return
	# The Thumper: at the bottom of the tunnel's end (where the hot rock stopped
	# the Borer), or at the shaft's foot.
	var at := Vector2i(lx, st.get("lava_row", shaft_bottom() - 30) + 20)
	var hy: int = st.get("lava_row", 0) + 30
	while hy < D.H - 4 and not D.is_solid(game.sim.get_cell(lx, hy)):
		hy += 1
	at.y = maxi(at.y, hy - 10)
	if absi(lx - sx) <= 20:
		st["need_foot"] = true
		at = Vector2i(sx, shaft_bottom() - 10)
	var r: Rect2i = game.snap_place(D.B_THUMPER, at, false)
	var why: String = game.check_place(D.B_THUMPER, r)
	if why != "":
		print("%s  !! no Thumper near %s: %s" % [clock(game.game_time), at, why])
		wait("lava", 20.0)
		return
	st["thumper"] = game.place(D.B_THUMPER, r).id
	st["lava_last"] = Vector2i(r.get_center())
	st["tries"] += 1
	print("%s  a Thumper at %s to blast down to lava (try %d)" % [clock(game.game_time), r.position, st["tries"]])


# --- Tier 3 on: down through the lava to the chamber ---------------------------------
# With the Coolant Jacket and the Obsidian Saw a Borer bores straight down from the
# shaft's foot through hot rock and whatever lava is under it (quenching it into
# obsidian as it goes) to the bedrock over the chamber. Then another goes across
# to the plug over the Crucible and down it, a Conduit line following.

func descent() -> void:
	if st.get("descent", "") == "sent" and _busy("descent") == 0:
		st["descent"] = "done"
		st["floor"] = shaft_bottom()
		print("%s  down to the bedrock at %d (obsidian %d)" % [clock(game.game_time), st["floor"], game.total(D.R_OBSIDIAN)])
	if st.get("descent", "") != "" or not game.tiers_open[3] or waiting("descent"):
		return
	if not game.researched.has("coolant_jacket") or not game.researched.has("obsidian_saw"):
		return
	# On the shaft's floor, with the bot's machines (the Hopper, the chain's last
	# Conduits) cleared out of the way.
	var d = game.drill
	var fl := shaft_floor()
	for b in game.buildings.duplicate():
		if b != d and not b.dead and b.rect().intersects(Rect2i(d.x - 5, fl - 120, 40, 125)):
			game.demolish(b)
	st.erase("hopper")
	st["chain_to"] = mini(st["chain_to"], fl - 125)
	var y := fl - 30
	while y > fl - 90 and game.check_place(D.B_BORER, Rect2i(d.x, y, 30, 30)) != "":
		y -= 5
	if send_borer(Rect2i(d.x, y, 30, 30), [[0, D.H - 10]], "descent", false, false) != null:
		st["descent"] = "sent"
		print("%s  a Borer down through the lava from %d" % [clock(game.game_time), y])
	else:
		wait("descent", 20.0)


func plug() -> void:
	if st.get("descent", "") != "done" or st.get("plug", "") == "done" or waiting("plug"):
		return
	var cr: Rect2i = game.info["crucible"]
	var ceiling: int = cr.position.y - 70
	var px: int = game.info["plug_x"] + 20
	var d = game.drill
	var sx: int = d.x + 15
	if st.get("plug", "") == "sent":
		if _busy("plug") == 0:
			st["plug"] = "done"
			# A Conduit in the plug's mouth, over the Crucible.
			game.lay_line(D.B_CONDUIT, Vector2i(px, ceiling - 12), Vector2i(px, ceiling - 12))
			print("%s  through the plug; a Conduit for the Crucible" % clock(game.game_time))
		return
	# Across under the lowest bedrock between the shaft and the plug, then down it.
	var row: int = st["floor"] - 30
	for x in range(mini(sx, px), maxi(sx, px) + 1, 4):
		var y := 4300
		while y < D.H - 4 and game.sim.get_cell(x, y) != D.BEDROCK:
			y += 1
		row = mini(row, y - 36)
	var legs: Array = []
	if absi(px - sx) > 4:
		legs.append([1 if px < sx else 2, px])
	legs.append([0, ceiling + 25])
	var b = null
	for k in 8:
		if game.check_place(D.B_BORER, Rect2i(d.x, row, 30, 30)) == "":
			b = send_borer(Rect2i(d.x, row, 30, 30), legs, "plug", true, false)
			break
		row -= 10
	if b == null:
		print("%s  !! no row to the plug from %d" % [clock(game.game_time), st["floor"]])
		wait("plug", 30.0)
		return
	st["plug"] = "sent"
	print("%s  a Borer to the plug at x %d along row %d" % [clock(game.game_time), px, row])


func crucible() -> void:
	var c = game.crucible
	if game.cstate != 0 or not c.connected:
		return
	for r in D.NRES:
		if game.total(r) < D.RECIPE[r]:
			jobs.append("stocking for the Crucible")
			return
	game.activate_crucible()
	print("%s  the Crucible: charging" % clock(game.game_time))


# --- Reporting --------------------------------------------------------------------

func clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [int(s / 3600.0), int(s / 60.0) % 60, s % 60]


func report() -> void:
	while shown < game.milestones.size():
		var m: Dictionary = game.milestones[shown]
		shown += 1
		if m["major"] or not quiet:
			print("%s  %s%s" % [clock(m["t"]), "" if m["major"] else "  ", m["text"]])
	if game.game_time - last_status >= 120.0:
		last_status = game.game_time
		var d = game.drill
		print("%s  -- head %d/%d bottom %d  S%d G%d O%d W%d P%d (+%.1f -%.1f)  research %s  plans %d  bldg %d  %s" % [
				clock(game.game_time), int(d.drill_head().y), d.reach_limit + d.y + d.h, shaft_bottom(), game.total(D.R_STONE),
				game.total(D.R_GLIMMER), game.total(D.R_OBSIDIAN), game.total(D.R_WATER), game.total(D.R_POWER),
				game.power_made, game.power_used, _research_text(), game.plans.size(), game.buildings.size(),
				d.stuck if d.stuck != "" else ", ".join(jobs)])


func _research_text() -> String:
	var id: String = game.current_tech
	if id == "":
		return "-"
	return "%s %d %d%%" % [id, game.level(id) + 1, int(game.tech_power_frac(id) * 100.0)]


## What's in the shaft's column, for debugging (--dump=seconds, then every minute).
func dump_shaft() -> void:
	var d = game.drill
	var out: Array = []
	for b in game.buildings:
		if b.x + b.w > d.x - 10 and b.x < d.x + d.w + 10 and b.y > d.y:
			out.append("%s@%d,%d%s%s" % [D.B_NAMES[b.type].left(4), b.x, b.y, "" if b.built else " bp", "" if b.connected else " OFF"])
	for p in game.plans:
		if absi(p["at"].x - (d.x + 15)) < 60:
			out.append("plan %s@%s" % [D.B_NAMES[p["type"]].left(4), p["at"]])
	print("%s  shaft (head %d, bottom %d, chain_to %d): %s" % [clock(game.game_time), int(d.drill_head().y), shaft_bottom(),
			st["chain_to"], "  ".join(out)])


func finish() -> void:
	print("FINISHED %s at %s: lost %d buildings, drilled %d cells" % [
			"WON" if game.won else ("LOST" if game.run_lost else "stopped"), clock(game.game_time),
			game.buildings_lost, game.cells_drilled])
