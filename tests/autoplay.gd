extends SceneTree
## Autoplay bot (phase 10). Plays a whole run headless through the game's own
## calls (place, lay_line, pick_research, Borer headings, activate_crucible) and
## prints the milestones with their times, so the pace can be tuned against it.
## It knows the map (it reads cells and the generator's info), so it measures how
## long the loop takes when you know where things are, not how hard it is to
## work out: a person should take about twice as long.
##
## The plan:
##  - a Lab researches the Drill down to the Topsoil's bottom, and a Conduit chain
##    follows it down its shaft (stopping over any water the Drill let in);
##  - a Borer leaves the Drill's foot (or, if the shaft has flooded, from over the
##    water and sideways) and goes straight down its own column (clear of any water)
##    to the hot rock, a Conduit line following: everything else hangs off that column;
##  - Borers sweep out of it along the richest glimmer bands (Tier 2);
##  - a Borer tunnels most of the way to the nearest water, a Hopper goes in behind
##    it, then it breaks through: the Hopper drinks the flow (Water). If the flow
##    stops, Hoppers go into the aquifer itself, and a dry one means the next aquifer;
##  - a Borer along just over the hot line to over the lava with the least hot rock
##    above it, and a Thumper blasts down from there (Tier 3);
##  - with the Coolant Jacket and the Obsidian Saw, jacketed Borers dive into that lava
##    for obsidian (then into the lava lake), and another bores down to the bedrock by
##    a way clear of lava and caves, then across and down the plug (Tier 4);
##  - Conduits down the plug hang one under the dome in reach of the Crucible; three
##    Caches by the plug fill, and it's lit, the line kept whole through the tremors.
## Every Borer's Conduit line starts again from the nearest live relay if it breaks.
##
## godot --headless --path . --script tests/autoplay.gd -- --seed=7 [--max=7200] [--quiet]
##   [--save=SECONDS] (checkpoint to user://bot_<seed>_<t>.save) [--load=PATH] [--dump=SECONDS]
##   [--rect=x,y,w,h] (what --dump maps) [--threads=N] (the sim's threads, to run seeds side by side)

const D = preload("res://scripts/defs.gd")
const Save = preload("res://scripts/save.gd")
const Mats = preload("res://scripts/materials.gd")

var game: Node
var seed_value := 7
var max_time := 7200.0
var quiet := false
var save_at := -1.0
var load_from := ""
var dump_at := -1.0
var dump_rect := [300, 1300, 400, 300]
var threads := -1
var f := 0
var shown := 0                  # milestones printed so far
var last_status := -1.0
var jobs: Array = []            # what it's doing now, for the status line
var st := {}                    # the bot's own state (plain data, so checkpoints keep it)

# Research, in the order it wants it (upgrades repeat once per level): only what
# the route needs, then fillers while it waits on materials.
const PLAN := ["drill_shaft", "drill_bit", "drill_shaft", "drill_shaft", "borer", "drill_shaft",
	"thumper", "thump_charge", "coolant_jacket", "obsidian_saw", "cache",
	"borer_cells", "thump_rhythm", "thump_efficiency", "lamp", "waterwheel", "spout"]


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
		elif a.begins_with("--threads="):
			threads = int(a.substr(10))
		elif a.begins_with("--rect="):
			dump_rect = Array(a.substr(7).split(",")).map(func(v): return int(v))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	if f == 2:
		setup()
	for _s in 10:
		for _t in 6:
			game.run_ticks(10)
			_turns()
		think()
		report()
		if save_at > 0.0 and game.game_time >= save_at:
			checkpoint()
			save_at = -1.0
		if dump_at > 0.0 and game.game_time >= dump_at:
			dump_at = -1.0
			area_dump(Rect2i(dump_rect[0], dump_rect[1], dump_rect[2], dump_rect[3]))
		if game.won or game.run_lost or game.game_time >= max_time:
			finish()
			return true
	return false


func setup() -> void:
	_setup()
	if threads > 0:
		game.sim.set_threads(threads)


func _setup() -> void:
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
	st = {"chain_to": 0, "routes": {}, "swept": {}, "wait": {}, "tries": 0}
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
	# While the Crucible charges nothing else runs: it needs every bit of power,
	# and the line down the plug has to be kept whole through the tremors.
	if game.cstate == 1:
		game.current_tech = ""
		place_conduits()
		drive_borers()
		keep_linked()
		mend()
		return
	research()
	shaft_chain()
	mend()
	place_conduits()
	drive_borers()
	deep()
	glimmer()
	tap()
	sump()
	lava()
	descent()
	obsidian()
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


func _mask(mats: Array) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(256)
	for k: int in mats:
		m[k] = 1
	return m


func _count(r: Rect2i, mats: Array) -> int:
	return game.sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, _mask(mats))


## The nearest legal spot for a `type` within `radius` of `c` (open, touching rock,
## explored, in network range), or an empty Rect2i. `below`: its top at least there.
func near_spot(type: int, c: Vector2i, radius: int, below := -1) -> Rect2i:
	var fp: Rect2i = game.footprint(type, c, false)
	var spots: PackedInt32Array = game.sim.place_spots(fp.position.x, fp.position.y, fp.size.x, fp.size.y, radius,
			Mats.mask("open"), Mats.mask("solid"))
	for k in range(0, spots.size(), 3):
		var r := Rect2i(fp.position + Vector2i(spots[k], spots[k + 1]), fp.size)
		if r.position.y >= below and game.check_place(type, r) == "":
			return r
	return Rect2i()


# --- Research -------------------------------------------------------------------------

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
	# A Lab turns at most 2 power a second into research: a second once a
	# generator makes more than that spare.
	if game.power_made >= 3.0 and not waiting("lab"):
		var labs := 0
		for b in game.buildings:
			if b.type == D.B_LAB:
				labs += 1
		if labs < 2:
			var r := near_spot(D.B_LAB, Vector2i((D.W >> 1) - 16 * D.S, D.GROUND_Y - 15), 120)
			if r.size.x > 0:
				game.place(D.B_LAB, r)
				print("%s  a second Lab at %s" % [clock(game.game_time), r.position])
			wait("lab", 30.0)
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


# --- The Drill's shaft -----------------------------------------------------------------

## The deepest open row straight down the Drill's shaft (read down its right
## side, clear of the chain on the left wall); anything standing in it is the bottom.
func shaft_bottom() -> int:
	var d = game.drill
	var x: int = d.x + 25
	var y := int(d.drill_head().y)
	while y < D.H - 4 and not D.is_solid(game.sim.get_cell(x, y)):
		y += 1
	return y


## The first water down the Drill's shaft (an aquifer it bored through drains into
## it), or the bottom if there's none.
func shaft_water() -> int:
	var d = game.drill
	var x: int = d.x + 15
	var y: int = D.GROUND_Y
	var bottom := shaft_bottom()
	while y < bottom and game.sim.get_cell(x, y) != D.WATER:
		y += 1
	return y


## A Conduit line down the Drill's shaft against its left wall, a relay's spacing
## apart, and to just over its foot when something is to be sent from there.
func shaft_chain() -> void:
	if st.has("col_x"):
		return                     # the deep Borer's own line carries on from the foot
	var d = game.drill
	var x: int = d.x + 10
	if st["chain_to"] == 0:
		st["chain_to"] = d.y + d.h - 108
	var top := mini(shaft_bottom(), shaft_water()) - 30
	var last_y := top - 35
	var gap: int = last_y - st["chain_to"]
	if gap < 120 and not (st.get("need_foot", false) and st["chain_to"] < top - 70):
		return
	st["need_foot"] = false
	var a := Vector2i(x, mini(st["chain_to"] + 120, last_y))
	var b := Vector2i(x, last_y)
	game.lay_line(D.B_CONDUIT, a, b)
	st["chain_to"] = game.line_points(D.B_CONDUIT, a, b).back().y


# --- Borers --------------------------------------------------------------------------
# Each one the bot sends has a route: legs of [heading, stop], where the stop is
# the row (heading down or up) or column (left or right) its middle must reach
# before it turns onto the next leg. At the end it's taken back (half its cost),
# or held where it is if the route says so; something it can't cut ends it too.

## Conduits the bot wants at exact spots (its own queue, so nothing snaps): each
## goes down once its spot is open and in reach, or a few cells off it if debris
## sits there or the wall is, never further from the Conduit before it than a
## relay reaches.
func want_conduit(at: Vector2i, prev: Vector2i, route := -1) -> void:
	st["pending"] = st.get("pending", [])
	st["pending"].append({"at": at, "prev": prev, "route": route})


## Conduits still queued for a Borer's line.
func _queued(route: int) -> int:
	var n := 0
	for p: Dictionary in st.get("pending", []):
		if p.get("route", -1) == route:
			n += 1
	return n


func place_conduits() -> void:
	var left: Array = []
	for p: Dictionary in st.get("pending", []):
		var done := false
		for dy in [0, -6, 6, -12, 12, -20]:
			for dx in [0, -4, -8, -12, 4, 8, 12, -18, 18, -24, 24, -30, 30, -36, 36]:
				var c: Vector2i = p["at"] + Vector2i(dx, dy)
				if Vector2(c - p["prev"]).length() > D.RELAY_RANGE - 8.0:
					continue
				var r: Rect2i = game.footprint(D.B_CONDUIT, c, false)
				if game.check_place(D.B_CONDUIT, r) == "":
					game.place(D.B_CONDUIT, r)
					done = true
					break
			if done:
				break
		# Two minutes without a spot and it's given up on.
		p["tries"] = p.get("tries", 0) + 1
		if not done and p["tries"] < 120:
			left.append(p)
	st["pending"] = left


## A Borer at `r` heading off along `legs`, or null if it can't go there. `trail`:
## a Conduit line follows it; `hold`: it waits at the end instead of going back.
func send_borer(r: Rect2i, legs: Array, why: String, trail := true, hold := false) -> Object:
	var reason: String = game.check_place(D.B_BORER, r)
	if reason != "":
		if not quiet:
			print("%s  !! no Borer at %s (%s): %s" % [clock(game.game_time), r, why, reason])
		return null
	var b = game.place(D.B_BORER, r, legs[0][0])
	st["routes"][b.id] = {"legs": legs, "leg": 0, "why": why, "trail": trail, "hold": hold, "cut": 0,
			"last": Vector2i(r.get_center()), "start": Vector2i(r.get_center())}
	return b


## A new set of legs for a Borer the bot is holding, and off it goes.
func resume(b, legs: Array) -> void:
	var rt: Dictionary = st["routes"][b.id]
	rt["legs"] = legs
	rt["leg"] = 0
	rt["hold"] = false
	game.set_borer_dir(b, legs[0][0])
	b.enabled = true


## Keep a Conduit line close behind a Borer, hugging its tunnel (the left wall
## going up or down, the floor going across, so nothing snaps): from the last point
## laid toward its tail, a relay's spacing at a time, round the corner where it
## turned; closer when it's waiting on power.
func _follow(b, rt: Dictionary) -> void:
	var vertical: bool = b.dir == 0 or b.dir == 3
	var tail := Vector2i(b.x + 10, b.y - 30) if b.dir == 0 else (Vector2i(b.x + 10, b.y + b.h + 30) if b.dir == 3 \
			else Vector2i(b.x + b.w + 30 if b.dir == 1 else b.x - 30, b.y + b.h - 10))
	# Cut off with nothing queued (its line broke, or spots were given up on): the
	# line starts again from the nearest relay still on the network.
	if not b.connected and _queued(b.id) == 0:
		var near: Vector2i = rt["last"]
		var best := INF
		for r in game.buildings:
			if D.is_relay_type(r.type) and r.connected and r.built:
				var dd := Vector2(r.center()).distance_to(Vector2(tail))
				if dd < best:
					best = dd
					near = Vector2i(r.center())
		rt["last"] = near
	var last: Vector2i = rt["last"]
	# Round a corner: the next point is where the old line meets the new one.
	if (vertical and absi(last.x - tail.x) > 12) or (not vertical and absi(last.y - tail.y) > 12):
		var corner := Vector2i(tail.x, last.y) if vertical else Vector2i(last.x, tail.y)
		if Vector2(corner - last).length() > 110.0:
			corner = last + Vector2i(Vector2(corner - last).normalized() * 110.0)
		want_conduit(corner, last, b.id)
		rt["last"] = corner
		rt["laid"] = rt.get("laid", []) + [corner]
		return
	var gap := Vector2(tail - last).length()
	if gap < 110.0 and not ((b.starved or b.stuck == game.DRY) and not b.connected and gap > 40.0):
		return
	var step := minf(gap, 110.0)
	var to := last + Vector2i((Vector2(tail - last).normalized() * step).round())
	want_conduit(to, last, b.id)
	rt["last"] = to
	rt["laid"] = rt.get("laid", []) + [to]


func drive_borers() -> void:
	for id: int in st["routes"].keys():
		var b = by_id(id)
		var rt: Dictionary = st["routes"][id]
		if b == null:
			# Gone (burnt, crushed): it ended where it was last seen.
			rt["end"] = rt.get("pos", rt["start"])
			rt["stuck"] = "destroyed"
			print("%s  !! Borer (%s) destroyed near %s" % [clock(game.game_time), rt["why"], rt["end"]])
			st["routes"].erase(id)
			st["ended"] = st.get("ended", {})
			st["ended"][rt["why"]] = rt
			continue
		rt["pos"] = Vector2i(b.center())
		var legs: Array = rt["legs"]
		var c: Vector2 = b.center()
		if rt["trail"] and b.mode == 0:
			_follow(b, rt)
		_turn(b, rt)
		# The descent stops on the bedrock and waits there for the plug.
		if rt["why"] == "descent" and b.stuck.begins_with("Bedrock"):
			b.enabled = false
			rt["hold"] = true
			st["descent"] = "done"
			st["dx"] = int(c.x)
			st["floor"] = b.y + b.h
			print("%s  down to the bedrock at %d,%d" % [clock(game.game_time), st["dx"], st["floor"]])
		if rt["hold"] and not b.enabled:
			jobs.append("Borer (%s) held at %d,%d" % [rt["why"], int(c.x), int(c.y)])
			continue
		# A sweep cut off and starved for a minute is given up on (its line didn't
		# keep up); the Borers that matter get their lines mended instead.
		if rt["why"] == "glimmer" and not b.connected and b.starved:
			rt["stranded"] = rt.get("stranded", 0) + 1
			if rt["stranded"] >= 60:
				b.enabled = false
		else:
			rt["stranded"] = 0
		# Hot rock before the Coolant Jacket: glimmer Borers wait for it; the rest are done.
		var hot: bool = b.stuck.begins_with("Hot rock") and not game.researched.has("coolant_jacket")
		if not b.enabled or (b.stuck != "" and b.stuck != game.DRY and not (hot and rt["why"] == "glimmer")):
			rt["end"] = Vector2i(c)
			rt["stuck"] = b.stuck
			if b.stuck != "" and not quiet:
				print("%s  Borer (%s) done at %d,%d: %s" % [clock(game.game_time), rt["why"], int(c.x), int(c.y), b.stuck])
			st["routes"].erase(id)
			st["ended"] = st.get("ended", {})
			st["ended"][rt["why"]] = rt
			game.demolish(b)
			if rt["why"] == "glimmer":
				_take_back_trail(Rect2i(mini(rt["start"].x, int(c.x)) - 20, int(c.y) - 30, absi(rt["start"].x - int(c.x)) + 40, 60))
			continue
		jobs.append("Borer (%s) %d/%d at %d,%d%s%s" % [rt["why"], rt["leg"] + 1, legs.size(), int(c.x), int(c.y),
				"" if b.connected else " (off)", "" if b.stuck == "" else ": " + b.stuck])


## Relays cut off from the network (a Conduit scalded, burnt or crushed out of a
## line): a new line from the nearest one still on it to the nearest cut-off one,
## every 10 s. One in reach whose link broke is left to mend itself with a Stone.
func mend() -> void:
	if waiting("mend") or _queued(-3) > 0:
		return
	wait("mend", 10.0)
	var live: Array = []
	var dead: Array = []
	for b in game.buildings:
		if D.is_relay_type(b.type) and b.built and not b.falling:
			if b.connected:
				live.append(b)
			elif not b.drowned:
				dead.append(b)
	var best := INF
	var a := Vector2i()
	var z := Vector2i()
	for d in dead:
		for l in live:
			var dd := Vector2(d.center()).distance_to(l.center())
			if dd < best:
				best = dd
				a = Vector2i(l.center())
				z = Vector2i(d.center())
	if best == INF or best <= D.RELAY_RANGE - 10.0:
		return
	var last := a
	while Vector2(z - last).length() > 110.0:
		var to := last + Vector2i((Vector2(z - last).normalized() * 110.0).round())
		want_conduit(to, last, -3)
		last = to
	if not quiet:
		print("%s  mending the network from %s to %s" % [clock(game.game_time), a, z])


## Onto its next leg once it's past this one's stop (checked every few ticks, so
## it doesn't overshoot a turn by much).
func _turn(b, rt: Dictionary) -> void:
	var legs: Array = rt["legs"]
	var k: int = rt["leg"]
	if k >= legs.size() or not b.enabled:
		return
	var c: Vector2 = b.center()
	var dir: int = legs[k][0]
	var stop: int = legs[k][1]
	if (dir == 0 and c.y >= stop) or (dir == 3 and c.y <= stop) or (dir == 1 and c.x <= stop) or (dir == 2 and c.x >= stop):
		rt["leg"] = k + 1
		if rt["why"] == "deep" and k == 0 and legs.size() > 1:
			st["col_x"] = b.x + 15        # where it actually turned down
		if k + 1 < legs.size():
			game.set_borer_dir(b, legs[k + 1][0])
		else:
			b.enabled = false


func _turns() -> void:
	for id: int in st["routes"]:
		var b = by_id(id)
		if b != null:
			_turn(b, st["routes"][id])


func _busy(why: String) -> int:
	var n := 0
	for id: int in st["routes"]:
		if st["routes"][id]["why"] == why:
			n += 1
	return n


## The Conduits (and plans) along a finished Borer's tunnel go (half their cost
## back), away from the column.
func _take_back_trail(area: Rect2i) -> void:
	var cx: int = st.get("col_x", game.drill.x + 15)
	for b in game.buildings.duplicate():
		if b.type == D.B_CONDUIT and area.intersects(b.rect()) and absi(b.center().x - cx) > 30:
			game.demolish(b)
	for k in range(game.plans.size() - 1, -1, -1):
		if area.has_point(game.plans[k]["at"]):
			game.plans.remove_at(k)


# --- The column ----------------------------------------------------------------------
# Off the Drill's foot, a column of its own straight down to the hot rock, clear
# of any water (so nothing that hangs off it floods, and no water reaches the hot
# rock or lava under it to scald its Conduits).

## A Borer's spot in the column as near row y as there is one (within `reach`
## rows), or an empty Rect2i.
func col_spot(y: int, reach := 40) -> Rect2i:
	for k in range(0, reach + 1, 2):
		for yy in [y + k, y - k]:
			var r := Rect2i(st["col_x"] - 15, yy, 30, 30)
			if not _col_taken(yy) and game.check_place(D.B_BORER, r) == "":
				return r
	return Rect2i()


## Anything of the bot's standing where a Borer at row y in the column would.
func _col_taken(y: int) -> bool:
	var r := Rect2i(st["col_x"] - 15, y - 2, 30, 34)
	for b in game.buildings:
		if b != game.drill and b.rect().intersects(r):
			return true
	for p in game.plans:
		if game.footprint(p["type"], p["at"], p["horiz"]).intersects(r):
			return true
	return false


func deep() -> void:
	if st.get("deep", "") == "sent" and _busy("deep") == 0:
		st["deep"] = "done"
		var rt: Dictionary = st["ended"]["deep"]
		st["col_floor"] = rt["end"].y + 15
		print("%s  the column at x %d is open to %d (%s)" % [clock(game.game_time), st["col_x"], st["col_floor"], rt["stuck"]])
	if st.get("deep", "") != "" or not game.researched.has("borer") or game.level("drill_shaft") < 4 or waiting("deep"):
		return
	var d = game.drill
	if d.reach < d.reach_limit:
		return
	var foot_y := shaft_bottom()
	# Water standing in the shaft (the Drill bored through an aquifer): set off from
	# over it, sideways, so the column stays dry.
	var wet := shaft_water() < foot_y
	if wet:
		foot_y = shaft_water() - 12
	# The column: the nearest x off the Drill's that has no water or lava near it all
	# the way down to the hot rock.
	var cx: int = d.x + 15
	for off in ([70, -70, 140, -140, 210, -210] if wet else [0, 70, -70, 140, -140, 210, -210]):
		var x: int = d.x + 15 + off
		if x < 40 or x > D.W - 40:
			continue
		if _count(Rect2i(x - 45, foot_y, 90, D.HOT_TOP + 40 - foot_y), [D.WATER, D.LAVA]) == 0:
			cx = x
			break
	st["need_foot"] = true
	var legs: Array = []
	if cx != d.x + 15:
		legs.append([2 if cx > d.x + 15 else 1, cx])
	legs.append([0, D.H - 10])
	if send_borer(Rect2i(d.x, foot_y - 30, 30, 30), legs, "deep") != null:
		st["deep"] = "sent"
		st["col_x"] = cx
		print("%s  the column: across to x %d and down" % [clock(game.game_time), cx])
	else:
		wait("deep", 10.0)


# --- Glimmer: Borers along the richest bands ------------------------------------------
# Out of the column sideways along a 30-row band to the map's edge, a Conduit line
# following. Before Tier 2 any glimmer will do; after, the richest band left.

func glimmer() -> void:
	if st.get("deep", "") != "done" or waiting("glimmer") or _busy("glimmer") >= 2:
		return
	var cx: int = st["col_x"]
	var best := {}
	var least := 1 if not game.tiers_open[2] else 600      # cells: any at first, then several units' worth
	for y in range(D.LAYERS[2]["top"], st["col_floor"] - 70, 10):
		if _col_taken(y):
			continue
		for side in [1, 2]:
			var key := "%d %d" % [floori(y / 30.0), side]
			if st["swept"].has(key):
				continue
			var x0: int = 4 if side == 1 else cx + 15
			var x1: int = cx - 15 if side == 1 else D.W - 4
			var n := _count(Rect2i(x0, y, x1 - x0, 30), [D.GLIMMER])
			if n >= least and n > best.get("n", 0):
				best = {"y": y, "side": side, "key": key, "n": n}
	# No glimmer left worth a sweep and Stone running short: sweep for Stone.
	if best.is_empty() and game.total(D.R_STONE) < 60.0:
		for y in range(D.LAYERS[2]["top"], st["col_floor"] - 70, 30):
			if _col_taken(y):
				continue
			for side in [1, 2]:
				var key := "%d %d" % [floori(y / 30.0), side]
				if st["swept"].has(key):
					continue
				var x0: int = 4 if side == 1 else cx + 15
				var x1: int = cx - 15 if side == 1 else D.W - 4
				var n := _count(Rect2i(x0, y, x1 - x0, 30), [D.STONE])
				if n > best.get("n", 0):
					best = {"y": y, "side": side, "key": key, "n": n}
	if best.is_empty():
		wait("glimmer", 30.0)
		return
	var side: int = best["side"]
	st["swept"][best["key"]] = true
	var r := col_spot(best["y"], 8)
	if r.size.x == 0 or send_borer(r, [[side, 24 if side == 1 else D.W - 24]], "glimmer") == null:
		wait("glimmer", 5.0)
		return
	if not quiet:
		print("%s  glimmer: a Borer out along row %d going %s (%d cells of it)" % [clock(game.game_time), best["y"],
				"left" if side == 1 else "right", best["n"]])


# --- Water: a Hopper at a tap ------------------------------------------------------------
# A Borer out of the column toward the nearest water in the Stone band, held a
# little short of it; a Hopper in the column just under the tunnel's mouth; then
# the Borer breaks through, and the water pours out of the tunnel onto the Hopper
# (the column under it stays dry; Conduits link past it).

func tap() -> void:
	if st.get("deep", "") != "done" or st.get("tap", "") == "done" or waiting("tap"):
		return
	var cx: int = st["col_x"]
	if not st.has("tap"):
		var best := Rect2i()
		var best_d := 1 << 30
		for w: Rect2i in game.info["aquifers"]:
			if w.get_center().y < D.LAYERS[2]["top"] or w.get_center().y > st["col_floor"] - 60:
				continue
			if _count(w, [D.WATER]) < 300 or st.get("tapped", []).has(w):
				continue
			var dd := absi(w.get_center().x - cx)
			if dd < best_d:
				best_d = dd
				best = w
		if best.size.x == 0:
			st["tap"] = "done"
			# The Drill's shaft may have one: an aquifer it bored through drains into it,
			# fed by its spring. A Hopper over the pool catches what falls.
			if shaft_water() < shaft_bottom() and not st.has("shaft_hopper"):
				for k in range(0, 60, 4):
					var sr := Rect2i(game.drill.x, shaft_water() - 22 - k, 30, 20)
					if game.check_place(D.B_HOPPER, sr) == "":
						st["shaft_hopper"] = game.place(D.B_HOPPER, sr).id
						print("%s  water: a Hopper over the pool in the Drill's shaft at %s" % [clock(game.game_time), sr.position])
						return
			print("%s  no water to tap off the column" % clock(game.game_time))
			return
		var r := col_spot(clampi(best.get_center().y - 15, D.LAYERS[2]["top"], st["col_floor"] - 90))
		var side := 1 if best.get_center().x < cx else 2
		var near: int = (best.end.x + 16) if side == 1 else (best.position.x - 16)
		if r.size.x == 0 or send_borer(r, [[side, near]], "tap", true, true) == null:
			wait("tap", 20.0)
			return
		st["tap"] = "boring"
		st["tap_w"] = best
		st["tap_side"] = side
		st["tap_row"] = r.position.y
		print("%s  water: a Borer toward %s along row %d" % [clock(game.game_time), best, r.position.y])
		return
	var bo = null
	for id: int in st["routes"]:
		if st["routes"][id]["why"] == "tap":
			bo = by_id(id)
	if st["tap"] == "boring":
		if bo == null:
			st["tap"] = "done"
			return
		if bo.enabled:
			return
		# Held short of the water: a Hopper in the column under the tunnel's mouth.
		var row: int = st["tap_row"]
		var top := row + 32
		var r := Rect2i()
		for k in range(0, 40, 2):
			var hr := Rect2i(cx - 15, top + k, 30, 20)
			if game.check_place(D.B_HOPPER, hr) == "":
				r = hr
				break
		if r.size.x == 0:
			wait("tap", 10.0)
			return
		st["tap_hopper"] = game.place(D.B_HOPPER, r).id
		st["tap"] = "hopper"
		return
	if st["tap"] == "hopper":
		var h = by_id(st["tap_hopper"])
		if h == null or bo == null:
			st["tap"] = "done"
			return
		if not h.built:
			return
		var w: Rect2i = st["tap_w"]
		resume(bo, [[st["tap_side"], (w.position.x - 30) if st["tap_side"] == 1 else (w.end.x + 30)]])
		st["tap"] = "done"
		st.erase("water_last")
		wait("sump", 90.0)          # the water takes a while to come through
		print("%s  water: the tap is open" % clock(game.game_time))


## If the tap stops paying (its tunnel caves in, say) while its aquifer still has
## water, a Hopper goes into the aquifer itself, as low as it can link: it drinks
## from its sides, and the springs keep the aquifer topped up.
func sump() -> void:
	if st.get("tap", "") != "done" or not st.has("tap_w") or waiting("sump"):
		return
	wait("sump", 30.0)
	var now: float = game.total(D.R_WATER)
	var last: float = st.get("water_last", -1.0)
	st["water_last"] = now
	if last < 0.0 or now > last + 1.0:
		return
	var aq: Rect2i = st["tap_w"]
	if _count(aq, [D.WATER]) < 600 or st.get("sumps", 0) >= 3:
		# Drained, and its spring isn't keeping up (rubble can bury one), or Hoppers
		# in it get nothing: tap the next.
		if st.get("tapped", []).size() < 3:
			st["tapped"] = st.get("tapped", []) + [aq]
			for k in ["tap", "tap_w", "tap_side", "tap_row", "tap_hopper", "water_last"]:
				st.erase(k)
			st["sumps"] = 0
			print("%s  water: nothing more from that aquifer; the next one" % clock(game.game_time))
		return
	var cx: int = st["col_x"]
	var best := Rect2i()
	var best_d := INF
	for y in range(aq.end.y - 20, aq.position.y - 1, -4):
		for x in range(aq.position.x - 10, aq.end.x - 19, 4):
			var r := Rect2i(x, y, 30, 20)
			var d := absf(r.get_center().x - cx) * 0.2 + (aq.end.y - y) * 2.0     # low first: it stays under water
			if d >= best_d or game.check_place(D.B_HOPPER, r) != "":
				continue
			# Its power comes by a relay: one under water passes nothing on.
			var l = game.find_link(D.B_HOPPER, r)
			if l == null or l.drowned or _count(l.rect(), [D.WATER]) > 0:
				continue
			best = r
			best_d = d
	if best.size.x == 0:
		print("%s  !! the tap has stopped and there's no spot for a Hopper in its aquifer" % clock(game.game_time))
		st["sumps"] = st.get("sumps", 0) + 1
		return
	game.place(D.B_HOPPER, best)
	st["sumps"] = st.get("sumps", 0) + 1
	print("%s  water: the tap has stopped; a Hopper into the aquifer at %s" % [clock(game.game_time), best.position])


# --- Tier 3: a Thumper down through the hot rock to lava ----------------------------------
# The lava with the least hot rock over it: a Borer along just over the hot line
# to over it (a Conduit line following) and down to the hot rock, then a Thumper
# from there, blasting its way down, its own Conduit line after it.

## The first row of hot rock down column x.
func hot_top(x: int) -> int:
	var y: int = D.HOT_TOP - 80
	while y < D.H - 4 and game.sim.get_cell(x, y) != D.HOT_ROCK:
		y += 1
	return y


func lava() -> void:
	if game.tiers_open[3] or st.get("deep", "") != "done" or waiting("lava"):
		return
	if game.level("thump_charge") < 1 or not game.is_unlocked(D.B_THUMPER):
		return
	var t = by_id(st.get("thumper", -1))
	if t != null:
		jobs.append("Thumper at %d (%d blasts, power %.1f%s)" % [t.y, t.blasts, t.power, "" if t.connected else ", off the network"])
		var last: Vector2i = st.get("lava_last", Vector2i(t.center()))
		if not t.connected and not t.flying:
			# Its crater wanders: the line goes after it from the nearest live relay.
			if _queued(-2) == 0:
				var best := INF
				for r in game.buildings:
					if D.is_relay_type(r.type) and r.connected and r.built:
						var dd := Vector2(r.center()).distance_to(t.center())
						if dd < best:
							best = dd
							last = Vector2i(r.center())
			var gap := Vector2(t.center()).distance_to(Vector2(last))
			if gap > 70.0 and _queued(-2) == 0:
				var to := last + Vector2i((Vector2(Vector2i(t.center()) - last).normalized() * minf(110.0, gap - 35.0)).round())
				want_conduit(to, last, -2)
				st["lava_last"] = to
		return
	if _busy("lava") > 0 or st["tries"] >= 6:
		return
	var cx: int = st["col_x"]
	if not st.has("lava_x"):
		# The pocket with the fewest rows of hot rock over it, then the shorter way.
		var best_score := INF
		var pockets: Array = game.info["lava_pockets"].duplicate()
		pockets.append(game.info["lake"])
		for pr: Rect2i in pockets:
			var px := pr.get_center().x
			var ly := pr.position.y
			while ly < pr.end.y and game.sim.get_cell(px, ly) != D.LAVA:
				ly += 1
			if ly >= pr.end.y:
				continue
			var score := (ly - hot_top(px)) + absi(px - cx) * 0.1
			if score < best_score:
				best_score = score
				st["lava_x"] = clampi(px, 30, D.W - 30)
				st["lava_y"] = ly
		print("%s  lava: aiming for %d,%d" % [clock(game.game_time), st.get("lava_x", -1), st.get("lava_y", -1)])
	var lx: int = st.get("lava_x", cx)
	if absi(lx - cx) > 20 and not st.has("lava_row"):
		# Along a row clear of the hot line all the way across, then down to it.
		var row := hot_top(cx)
		for x in range(mini(cx, lx), maxi(cx, lx) + 1, 4):
			row = mini(row, hot_top(x))
		row = mini(row - 40, st["col_floor"] - 32)
		for k in 12:
			if not _col_taken(row) and send_borer(Rect2i(cx - 15, row, 30, 30), [[2 if lx > cx else 1, lx], [0, st["lava_y"]]], "lava") != null:
				st["lava_row"] = row
				return
			row -= 10
		print("%s  !! no row for the lava tunnel" % clock(game.game_time))
		wait("lava", 30.0)
		return
	# The Thumper: at the bottom of the tunnel's end, or at the column's foot.
	var at := Vector2i(lx, st.get("lava_row", st["col_floor"] - 60) + 30)
	var hy: int = at.y
	while hy < D.H - 4 and not D.is_solid(game.sim.get_cell(lx, hy)):
		hy += 1
	var r := near_spot(D.B_THUMPER, Vector2i(lx, hy - 10), 60, at.y - 20)
	if r.size.x == 0 and st.has("lava_row"):
		r = near_spot(D.B_THUMPER, Vector2i(lx, hy - 10), 60, st["lava_row"])     # up in the tunnel
	if r.size.x == 0:
		print("%s  !! no spot for a Thumper near %d,%d" % [clock(game.game_time), lx, hy])
		wait("lava", 20.0)
		return
	st["thumper"] = game.place(D.B_THUMPER, r).id
	st["lava_last"] = Vector2i(r.get_center())
	st["tries"] += 1
	print("%s  a Thumper at %s to blast down to lava (try %d)" % [clock(game.game_time), r.position, st["tries"]])


# --- Tier 3 on: down through the lava to the chamber ---------------------------------
# With the Coolant Jacket and the Obsidian Saw a Borer bores straight down from the
# lava tunnel's end (or the column's foot) through the hot rock and whatever lava
# is under it, quenching it into obsidian, to the bedrock over the chamber. Then
# another goes across to the plug over the Crucible and down it, a Conduit line
# following.

func descent() -> void:
	if st.get("descent", "") == "sent" and _busy("descent") == 0:
		var rt: Dictionary = st["ended"]["descent"]
		st["descent"] = ""
		print("%s  !! the descent stopped at %s (%s); again" % [clock(game.game_time), rt["end"], rt["stuck"]])
		# Its line would be in the next one's way.
		for p: Vector2i in rt.get("laid", []):
			for b in game.buildings.duplicate():
				if b.type == D.B_CONDUIT and b.rect().grow(22).has_point(p):
					game.demolish(b)
		st["pending"] = []
		st["descents"] = st.get("descents", 0) + 1
		wait("descent", 20.0)
	if st.get("descents", 0) >= 5:
		jobs.append("the descent failed five times")
		return
	if st.get("descent", "") != "" or not game.tiers_open[3] or waiting("descent") or st.get("deep", "") != "done":
		return
	if not game.researched.has("coolant_jacket") or not game.researched.has("obsidian_saw"):
		return
	if game.total(D.R_WATER) < 12.0:
		jobs.append("the descent waits for water")
		return
	# From the column's foot down to the bedrock by a way that keeps clear of lava.
	var cx: int = st["col_x"]
	var fl: int = st["col_floor"]
	# Water standing at the column's foot (a spring in a cave by it, a tap's
	# overflow) leaves nowhere to start from: a Hopper drinks it first.
	var foot := Rect2i(cx - 60, fl - 160, 120, 180)
	var wet := _count(foot, [D.WATER])
	var dr = by_id(st.get("drain", -1))
	if dr != null and wet < 100:
		game.demolish(dr)
		st.erase("drain")
	elif dr == null and wet > 200:
		var h := _in_water(D.B_HOPPER, foot)
		if h.size.x > 0:
			st["drain"] = game.place(D.B_HOPPER, h).id
			print("%s  water at the column's foot: a Hopper to drink it" % clock(game.game_time))
		wait("descent", 10.0)
		return
	elif dr != null:
		jobs.append("draining the column's foot")
		wait("descent", 10.0)
		return
	var r := near_spot(D.B_BORER, Vector2i(cx, fl - 60), 100, fl - 220)
	if r.size.x == 0:
		print("%s  !! no spot for the descent near the column's foot" % clock(game.game_time))
		wait("descent", 20.0)
		return
	var legs := lava_free_legs(Vector2i(r.get_center().x, r.position.y + 30))
	if legs.is_empty():
		print("%s  !! no way down clear of lava" % clock(game.game_time))
		wait("descent", 60.0)
		return
	var dx: int = r.get_center().x
	for lg: Array in legs:
		if lg[0] == 1 or lg[0] == 2:
			dx = lg[1]
	if send_borer(r, legs, "descent") == null:
		print("%s  !! no spot for the descent at the column's foot" % clock(game.game_time))
		wait("descent", 20.0)
		return
	st["descent"] = "sent"
	print("%s  a Borer down to the bedrock by x %d, from %s: %s" % [clock(game.game_time), dx, r.position, legs])


## The lowest spot for a `type` (a Hopper, say) in the water in `area`, or an
## empty Rect2i.
func _in_water(type: int, area: Rect2i) -> Rect2i:
	var sz: Vector2i = D.B_SIZES[type]
	for y in range(area.end.y - sz.y, area.position.y - 1, -4):
		for x in range(area.position.x, area.end.x - sz.x + 1, 4):
			var r := Rect2i(Vector2i(x, y), sz)
			if _count(r, [D.WATER]) > r.get_area() / 3.0 and game.check_place(type, r) == "":
				return r
	return Rect2i()


## A Borer's legs from `from` down to the bedrock over the chamber, keeping clear
## of lava and caves: a search over 30-cell blocks (down or across, never up).
func lava_free_legs(from: Vector2i) -> Array:
	var bs := 30
	var x0 := 30
	var nx := floori((D.W - 60) / float(bs))
	var y0: int = from.y
	var ny := floori((4480 - y0) / float(bs))
	# Blocks it can cross: no lava near, and solid (a Borer breaking into a cave
	# falls), bar the column it starts in.
	var col := Rect2i(st["col_x"] - 15, 0, 30, st["col_floor"])
	var open: Array = [D.AIR, D.WATER, D.STEAM, D.RUBBLE, D.SAND, D.GRAVEL]
	var free := {}
	for j in ny:
		for i in nx:
			var blk := Rect2i(x0 + i * bs, y0 + j * bs, bs, bs)
			var near := blk.grow(16)
			var built := false
			for b in game.buildings:
				if b.rect().intersects(blk) and not b.rect().encloses(Rect2i(from - Vector2i(15, 30), Vector2i(30, 30))):
					built = true
					break
			free[Vector2i(i, j)] = not built and _count(blk.grow(20), [D.LAVA]) == 0 \
					and _count(near, open) - _count(near.intersection(col), open) < bs * 3
	var start := Vector2i(clampi(floori((from.x - x0) / float(bs)), 0, nx - 1), 0)
	var prev := {start: start}
	var queue: Array = [start]
	var goal := Vector2i(-1, -1)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c.y == ny - 1:
			goal = c
			break
		for d: Vector2i in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n := c + d
			if n.x < 0 or n.x >= nx or n.y >= ny or prev.has(n) or not free.get(n, false):
				continue
			prev[n] = c
			queue.append(n)
	if goal.x < 0:
		if not quiet:
			for j in ny:
				var line := ""
				for i in nx:
					var k := Vector2i(i, j)
					line += "@" if k == start else ("+" if prev.has(k) else ("." if free[k] else "#"))
				print("%5d %s" % [y0 + j * bs, line])
		return []
	var path: Array = [goal]
	while path.back() != start:
		path.append(prev[path.back()])
	path.reverse()
	# Blocks to legs: a turn wherever the heading changes.
	var legs: Array = []
	for k in range(1, path.size()):
		var d: Vector2i = path[k] - path[k - 1]
		var dir := 0 if d.y > 0 else (1 if d.x < 0 else 2)
		var stop: int = (y0 + path[k].y * bs + (bs >> 1)) if dir == 0 else (x0 + path[k].x * bs + (bs >> 1))
		if not legs.is_empty() and legs.back()[0] == dir:
			legs.back()[1] = stop
		else:
			legs.append([dir, stop])
	legs.append([0, D.H - 10])
	return legs


## Obsidian: a jacketed Borer dives from the Thumper's hole down through the lava
## pocket under it, quenching it as it goes (lava floods its tunnel behind it and
## it seldom comes back); again until there's enough. Once dives there stop paying,
## they go into the lava lake instead, from the descent's tunnel over it.
func obsidian() -> void:
	if not game.tiers_open[3] or not st.has("lava_x") or waiting("obsidian") or _busy("dive") > 0:
		return
	if not game.researched.has("coolant_jacket") or not game.researched.has("obsidian_saw"):
		return
	var got: float = game.total(D.R_OBSIDIAN)
	if got >= D.RECIPE[D.R_OBSIDIAN] + 4 or st.get("dives", 0) >= 24:
		return
	if game.total(D.R_WATER) < 8.0:
		return
	# Three dives in a row that banked less than a unit: the pocket's done.
	if st.has("dive_from"):
		st["dry_dives"] = st.get("dry_dives", 0) + 1 if got - st["dive_from"] < 1.0 else 0
	st["dive_from"] = got
	if st.get("dry_dives", 0) >= 3 and st.get("dive_at", "") != "lake":
		if st.get("descent", "") != "done":
			return
		st["dive_at"] = "lake"
		st["dry_dives"] = 0
		print("%s  obsidian: the pocket's spent; on to the lava lake" % clock(game.game_time))
	var r := Rect2i()
	var legs: Array = []
	if st.get("dive_at", "") == "lake":
		# From the nearest spot the network reaches: down into it from over it, or
		# across into its side (a Borer that breaks into its cave drops in).
		var lk: Rect2i = game.info["lake"]
		var lx := lk.get_center().x
		var ly := lk.position.y
		while ly < lk.end.y and game.sim.get_cell(lx, ly) != D.LAVA:
			ly += 1
		r = near_spot(D.B_BORER, Vector2i(lx, ly - 80), 200, ly - 260)
		if r.size.x == 0:
			r = near_spot(D.B_BORER, Vector2i(lx, ly + 20), 320)
		if r.size.x > 0 and absi(r.get_center().x - lx) > (lk.size.x >> 2):
			legs.append([1 if lx < r.get_center().x else 2, lx])
		legs.append([0, lk.end.y])
	else:
		var t = by_id(st.get("thumper", -1))
		if t != null:
			game.demolish(t)
			st.erase("thumper")
		var top: int = st.get("lava_row", st["col_floor"] - 60)
		# What earlier dives left in the hole goes first.
		for b in game.buildings.duplicate():
			if b.type != D.B_HOPPER and b.rect().intersects(Rect2i(st["lava_x"] - 60, top + 30, 120, 400)):
				game.demolish(b)
		r = near_spot(D.B_BORER, Vector2i(st["lava_x"], top + 40), 150, top - 20)
		legs.append([0, st["lava_y"] + 120])
	if r.size.x == 0 or send_borer(r, legs, "dive", false) == null:
		wait("obsidian", 20.0)
		return
	st["dives"] = st.get("dives", 0) + 1
	print("%s  obsidian: a dive into the %s from %s (dive %d, %d so far)" % [clock(game.game_time),
			"lava lake" if st.get("dive_at", "") == "lake" else "lava", r.position, st["dives"], got])


func plug() -> void:
	if st.get("descent", "") != "done" or st.get("plug", "") == "done" or waiting("plug"):
		return
	var cr: Rect2i = game.info["crucible"]
	var ceiling: int = cr.position.y - 70          # the dome's ceiling under the plug
	var px: int = game.info["plug_x"] + 20
	var sx: int = st["dx"]
	if st.get("plug", "") == "sent":
		if _busy("plug") > 0:
			return
		var rt: Dictionary = st["ended"]["plug"]
		if _count(Rect2i(px - 10, ceiling - 3, 20, 3), [D.AIR, D.STEAM, D.WATER]) < 40:
			st["plug"] = ""
			print("%s  !! the plug Borer stopped at %s (%s); again" % [clock(game.game_time), rt["end"], rt["stuck"]])
			return
		st["plug"] = "done"
		# The line on down the plug from its lowest Conduit to the mouth, against
		# the tunnel's left wall.
		var mouth := Vector2i(px - 6, ceiling + 4)      # hanging just under the ceiling: in reach of the Crucible
		var last := Vector2i(px - 6, st["floor"] - 100)
		for b in game.buildings:
			if b.type == D.B_CONDUIT and b.rect().intersects(Rect2i(px - 40, last.y, 80, ceiling - last.y)) \
					and b.center().y > last.y:
				last = Vector2i(b.center())
		while Vector2(mouth - last).length() > 110.0:
			var to := last + Vector2i((Vector2(mouth - last).normalized() * 110.0).round())
			want_conduit(to, last)
			last = to
		want_conduit(mouth, last)
		print("%s  through the plug; Conduits from %s to %s for the Crucible" % [clock(game.game_time), last, mouth])
		return
	# Across over the highest bedrock between the descent and the plug, then down
	# it until its bottom is through the dome's ceiling (its top still in the plug).
	var row: int = st["floor"] - 30
	for x in range(mini(sx, px) - 15, maxi(sx, px) + 16, 2):
		var y := 4300
		while y < D.H - 4 and game.sim.get_cell(x, y) != D.BEDROCK:
			y += 1
		row = mini(row, y - 32)
	var legs: Array = []
	if absi(px - sx) > 4:
		legs.append([1 if px < sx else 2, px])
	legs.append([0, ceiling - 14])
	# The descent's own Borer, waiting on the bedrock, goes on.
	for id: int in st["routes"]:
		var rt: Dictionary = st["routes"][id]
		var db = by_id(id)
		if rt["why"] != "descent" or db == null:
			continue
		if db.y > row:
			legs.push_front([3, row + 15])
		rt["why"] = "plug"
		resume(db, legs)
		st["plug"] = "sent"
		print("%s  the descent's Borer on to the plug at x %d" % [clock(game.game_time), px])
		return
	var r := near_spot(D.B_BORER, Vector2i(sx, row + 15), 60, row - 40)
	if r.size.x == 0 or send_borer(r, legs, "plug") == null:
		print("%s  !! no spot to set off for the plug from %d,%d" % [clock(game.game_time), sx, row])
		wait("plug", 30.0)
		return
	st["plug"] = "sent"
	print("%s  a Borer to the plug at x %d from %s" % [clock(game.game_time), px, r.position])


func crucible() -> void:
	var c = game.crucible
	if game.cstate != 0:
		return
	if not c.connected:
		if st.get("plug", "") == "done":
			keep_linked()
		return
	for r in D.NRES:
		if game.total(r) < D.RECIPE[r]:
			jobs.append("stocking for the Crucible")
			return
	# Its draw is twice what the Hub makes over the ~100 s of the charge, and the
	# Hub's packets take longer to get down there than its reserve lasts: three
	# Caches by the plug and a full Hub hold the rest.
	if not game.researched.has("cache"):
		jobs.append("the Crucible waits for the Cache")
		return
	var caches: Array = []
	for b in game.buildings:
		if b.type == D.B_CACHE:
			caches.append(b)
	if caches.size() < 3:
		if not waiting("cache"):
			var r := near_spot(D.B_CACHE, Vector2i(st["dx"], st["floor"] - 20), 150)
			if r.size.x == 0:
				print("%s  !! no spot for a Cache by the plug" % clock(game.game_time))
				wait("cache", 20.0)
			else:
				game.place(D.B_CACHE, r)
				print("%s  a Cache by the plug at %s" % [clock(game.game_time), r.position])
		jobs.append("Caches for the Crucible")
		return
	for k in caches:
		if not k.built or k.store[D.R_POWER] < D.CACHE_TOPUP[D.R_POWER] - 5.0:
			jobs.append("filling the Caches")
			return
	if game.stock[D.R_POWER] < D.HUB_POWER_CAP - 10.0 or _busy("dive") > 0:
		jobs.append("filling the Hub")
		return
	game.activate_crucible()
	print("%s  the Crucible: charging" % clock(game.game_time))


## Tremors can knock a Conduit out of the plug: then the line goes back down from
## the lowest one still linked (what fell is cleared away first).
func keep_linked() -> void:
	if game.crucible.connected or waiting("relink") or not st.has("dx"):
		return
	wait("relink", 5.0)
	var cr: Rect2i = game.info["crucible"]
	var ceiling: int = cr.position.y - 70
	var px: int = game.info["plug_x"] + 20
	var col := Rect2i(px - 40, st["floor"] - 100, 80, cr.position.y - st["floor"] + 100)
	var last := Vector2i(px - 6, st["floor"] - 100)
	for b in game.buildings.duplicate():
		if b.type != D.B_CONDUIT or not b.rect().intersects(col):
			continue
		if not b.connected:
			game.demolish(b)
		elif b.center().y > last.y:
			last = Vector2i(b.center())
	var mouth := Vector2i(px - 6, ceiling + 4)
	st["pending"] = []
	while Vector2(mouth - last).length() > 110.0:
		var to := last + Vector2i((Vector2(mouth - last).normalized() * 110.0).round())
		want_conduit(to, last)
		last = to
	want_conduit(mouth, last)
	print("%s  !! the Crucible is cut off; the line down the plug again from %s" % [clock(game.game_time), last])


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
		print("%s  -- head %d  S%d G%d O%d W%d P%d (+%.1f -%.1f)  research %s  plans %d  bldg %d  %s" % [
				clock(game.game_time), int(d.drill_head().y), game.total(D.R_STONE),
				game.total(D.R_GLIMMER), game.total(D.R_OBSIDIAN), game.total(D.R_WATER), game.total(D.R_POWER),
				game.power_made, game.power_used, _research_text(), game.plans.size(), game.buildings.size(),
				d.stuck if d.stuck != "" else ", ".join(jobs)])
		if game.cstate == 1:
			print("         Crucible %d%%%s%s%s" % [int(game.crucible_charge() * 100.0), "" if game.crucible.connected else ", cut off",
					", out of power" if game.c_starved else "", ", draining" if game.c_draining else ""])


func _research_text() -> String:
	var id: String = game.current_tech
	if id == "":
		return "-"
	return "%s %d %d%%" % [id, game.level(id) + 1, int(game.tech_power_frac(id) * 100.0)]


## A coarse picture of an area (a character per 4x4 block) and the buildings in it.
func area_dump(r: Rect2i) -> void:
	var names := {D.AIR: ".", D.STONE: "S", D.HOT_ROCK: "#", D.LAVA: "L", D.WATER: "w", D.OBSIDIAN: "O", D.BUILDING: "B",
			D.RUBBLE: "r", D.DIRT: "d", D.GLIMMER: "g", D.BEDROCK: "X"}
	for y in range(r.position.y, r.end.y, 4):
		var row := ""
		for x in range(r.position.x, r.end.x, 4):
			var m: int = game.sim.get_cell(x, y)
			row += names.get(m, "s" if m >= D.STEAM and m <= D.STEAM_LAST else "?")
		print("%5d %s" % [y, row])
	for b in game.buildings:
		if b.rect().intersects(r):
			print("  %s at %s %s %s" % [D.B_NAMES[b.type], b.rect(), "built" if b.built else "blueprint", "on" if b.connected else "OFF"])


func finish() -> void:
	print("FINISHED %s at %s: lost %d buildings, drilled %d cells" % [
			"WON" if game.won else ("LOST" if game.run_lost else "stopped"), clock(game.game_time),
			game.buildings_lost, game.cells_drilled])
