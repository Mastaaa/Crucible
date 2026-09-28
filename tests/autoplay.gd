extends SceneTree
## Autoplay bot. Plays a whole run headless through the real game code and
## reports milestones and timing. It reads the generator's info (it knows the
## map), so it measures whether the loop is completable and how long it takes,
## not how hard it is to work out.
##
## Route: down beside the Hub, sideways to a clear column, down to just above
## the chamber, sideways to the plug, down through it, then hang a Conduit next
## to the Crucible. On the way: recover from floods with a Hopper, drill side
## tunnels along glimmer veins, and farm obsidian at the lava lake.
##
## godot --headless --path . --script tests/autoplay.gd -- --seed=7 [--max=3600]

const D = preload("res://scripts/defs.gd")
const Building = preload("res://scripts/building.gd")

var game: Node
var seed_value := 7
var max_time := 3600.0
var milestones: Array = []
var last_report := 0.0

var plug_col := 0
var col := 0
var turn_y := 884
var start_x := 136
var stage := "descend"
var leg := 0
var cur: Building = null
var flood_hoppers: Array = []
var flooding := false
var blocked_tries := 0
var link_tries := 0

var glim_plan: Array = []       # {y, dir, count, placed}
var farm := {}                  # planned obsidian farm
var activated := false
var stats_worst := 0
var stats_total := 0
var stats_batches := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--max="):
			max_time = float(a.substr(6))
		elif a.begins_with("--slow="):
			slow = int(a.substr(7))
		elif a == "--pertick":
			pertick = true
		elif a == "--lite":
			lite = true
		elif a == "--trace":
			trace = true
		elif a == "--watch-farm":
			watch_farm = true
		elif a.begins_with("--shot-y="):
			shot_y = float(a.substr(9))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


var started := false

## The game's _ready runs after _initialize (and starts its own new game), so
## the bot sets up on its first frame.
func _setup() -> void:
	started = true
	game.new_game(seed_value)
	game.pause_on_breach = false
	# The bot drives the clock itself (run_ticks); the game's own frame loop stays
	# paused so real time doesn't leak in and runs are repeatable.
	game.paused = true
	plan()


var watch_farm := false
var trace := false
var lite := false
var pertick := false
var slow_ticks: Array = []
var lite_log: Array = []
var slow := 0
var watch_done := false

func _watch_farm() -> void:
	if watch_done or farm.get("tunnel") == null:
		return
	var ty: int = farm["ty"]
	for y in range(ty - 4, ty + 5):
		for x in range(3, D.W - 3):
			var m := cell(x, y)
			if m == D.WATER or m >= D.STEAM or m == D.LAVA:
				watch_done = true
				note("WATCH: %s at (%d,%d) tick %d" % [D.mat_name(m), x, y, game.ticks])
				var lines: Array = []
				for yy in range(y - 6, y + 30):
					var row := "%4d " % yy
					for xx in range(x - 30, x + 30):
						var c := cell(xx, yy)
						row += ".#sgoBdlrWL"[c] if c < 11 else "~"
					lines.append(row)
				print("\n".join(lines))
				for b: Building in game.buildings:
					if absi(b.x - x) < 30 and absi(b.y - y) < 30:
						print("  ", b.title(), " ", Vector2i(b.x, b.y), " ", Vector2i(b.w, b.h), " dir ", b.dir, " reach ", b.reach)
				return


var ending := 0
var shot_y := -1.0

func _process(_d: float) -> bool:
	if ending > 0:
		ending += 1
		if ending == 2:
			game._center_on(shot_y if shot_y >= 0.0 else game.deepest_building().center().y, true)
			game.selected = null
		if ending == 6:
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("/home/claude/shots/play_%d.png" % seed_value)
			return true
		return false
	if not started:
		_setup()
	if not game.paused:
		note("game was unpaused by someone (ticks %d)" % game.ticks)
		game.paused = true
	for _i in 10:
		var t0 := Time.get_ticks_usec()
		if pertick:
			for _k in 30:
				var k0 := Time.get_ticks_usec()
				game.run_ticks(1)
				var kus := Time.get_ticks_usec() - k0
				if kus > 4000:
					slow_ticks.append([kus, game.game_time, game.ticks])
		else:
			game.run_ticks(30)
		var us := Time.get_ticks_usec() - t0
		stats_worst = maxi(stats_worst, us)
		stats_total += us
		stats_batches += 1
		if slow > 0:
			OS.delay_msec(slow)
		if lite:
			lite_log.append("%d %s %d %d %d" % [game.ticks, game.stock, game.packets.size(), game.buildings.size(), game.sim.tick])
		if trace:
			print("T %d %s %s %d %d" % [game.ticks, game.sim.get_cells().hex_encode().md5_text(), game.stock, game.packets.size(), game.buildings.size()])
		think()
		if watch_farm:
			_watch_farm()
		if game.won or game.game_time > max_time or stage == "stop":
			finish()
			if DisplayServer.get_name() == "headless":
				return true
			ending = 1
			return false
	return false


# --- reporting ------------------------------------------------------------------------------

func note(s: String) -> void:
	var line := "[%s] %s" % [clock(game.game_time), s]
	milestones.append(line)
	print(line)


func clock(t: float) -> String:
	return "%02d:%02d" % [int(t / 60.0), int(t) % 60]


const COLS := {0: Color("#101018"), 1: Color("#2e2735"), 2: Color("#77767c"), 3: Color("#3fd0b5"),
	4: Color("#5a3585"), 5: Color("#f2c14e"), 6: Color("#6e4a2e"), 7: Color("#b07a4a"),
	8: Color("#a8a397"), 9: Color("#2a6fdc"), 10: Color("#ff6a1a")}

## CPU-rendered picture of the map around the route (buildings in yellow).
func dump(path: String, y0: int, y1: int, x0 := -1, x1 := -1, s := 2) -> void:
	if x0 < 0:
		x0 = clampi(mini(col, start_x) - 60, 0, D.W)
		x1 = clampi(maxi(col, start_x) + 70, 0, D.W)
	var img := Image.create((x1 - x0) * s, (y1 - y0) * s, false, Image.FORMAT_RGB8)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var m := cell(x, y)
			var c: Color = COLS.get(m, Color.WHITE) if m < 11 else Color(0.95, 0.95, 1.0)
			img.fill_rect(Rect2i((x - x0) * s, (y - y0) * s, s, s), c)
	for b: Building in game.buildings:
		var r := Rect2i((b.x - x0) * s, (b.y - y0) * s, b.w * s, b.h * s)
		var c := Color(1, 0.85, 0.3) if b.built else Color(1, 0.5, 0.9)
		if b.type == D.B_CONDUIT:
			c = Color(0.4, 0.9, 1.0) if not b.drowned else Color(0.2, 0.3, 1.0)
		elif b.type == D.B_HOPPER:
			c = Color(0.3, 1.0, 0.5)
		elif b.type == D.B_SPOUT:
			c = Color(1, 0.3, 1)
		img.fill_rect(r.intersection(Rect2i(Vector2i.ZERO, img.get_size())), c)
	img.save_png(path)


func finish() -> void:
	if pertick:
		slow_ticks.sort_custom(func(p, q): return p[0] > q[0])
		note("ticks over 4 ms: %d; worst: %s" % [slow_ticks.size(), str(slow_ticks.slice(0, 8))])
	if lite:
		for l in lite_log:
			print("L ", l)
	dump("/home/claude/shots/bot_%d_a.png" % seed_value, 30, 530)
	dump("/home/claude/shots/bot_%d_b.png" % seed_value, 520, 1020)
	var lake: Rect2i = farm.get("body", game.info["lake"])
	dump("/home/claude/shots/bot_%d_farm.png" % seed_value, lake.position.y - 20, lake.end.y + 4,
			maxi(mini(lake.position.x, col) - 4, 0), mini(maxi(lake.end.x, col + 5) + 4, D.W), 6)
	note("FINISHED won=%s time=%s lost=%d drilled=%d stock S%d G%d O%d W%d" % [game.won, clock(game.game_time),
			game.buildings_lost, game.cells_drilled, game.stock[0], game.stock[1], game.stock[2], game.stock[3]])
	note("perf: avg %.3f ms/tick, worst 30-tick batch %.1f ms" % [stats_total / float(stats_batches * 30) / 1000.0, stats_worst / 1000.0])
	var counts := {}
	for b: Building in game.buildings:
		counts[b.title()] = counts.get(b.title(), 0) + 1
	note("buildings: " + str(counts))
	if cur != null:
		var cells_s := ""
		for rr in cur.reach:
			for k in 5:
				var c := cur.channel_cell(rr, k)
				cells_s += str(cell(c.x, c.y))
			cells_s += "|"
		note("  cur drill %s dir %d reach %d/%d built=%s conn=%s dead=%s done=%s leg %d channel %s" % [Vector2i(cur.x, cur.y), cur.dir,
				cur.reach, cur.reach_limit, cur.built, cur.connected, cur.dead, drill_done(cur), leg, cells_s])
	for b: Building in game.buildings:
		if not b.built:
			note("  unbuilt %s at %s: connected=%s link=%s delivered=%s cost=%s" % [b.title(), Vector2i(b.x, b.y), b.connected,
					"-" if b.link == null else "%s@%s" % [b.link.title(), Vector2i(b.link.x, b.link.y)], b.delivered, b.cost])
	var kinds := {}
	for a in game.alerts:
		kinds[a["kind"]] = kinds.get(a["kind"], 0) + a["n"]
	note("alert kinds: " + str(kinds))
	for a in game.alerts:
		if a["kind"] != "tremor":
			print("   alert %s %s x%d (at %d,%d)" % [clock(a["t"]), a["text"], a["n"], a["x"], a["y"]])
	var tail: Array = []
	for a in game.alerts.slice(maxi(0, game.alerts.size() - 12)):
		tail.append("%s x%d" % [a["text"], a["n"]])
	note("last alerts: " + "; ".join(tail))


# --- map reading (the bot's cheat sheet) ------------------------------------------------------

func cell(x: int, y: int) -> int:
	return game.sim.get_cell(x, y)


func band_has(x0: int, y0: int, x1: int, y1: int, bad: Array) -> bool:
	var no_caves: bool = D.AIR in bad
	for y in range(maxi(y0, 2), mini(y1, D.H - 2)):
		for x in range(maxi(x0, 2), mini(x1, D.W - 2)):
			var m := cell(x, y)
			if m == D.AIR:
				if no_caves and y > 300:
					return true
			elif m in bad:
				return true
	return false


func plan() -> void:
	plug_col = game.info["plug_x"] + 2
	var lake: Rect2i = game.info["lake"]
	var lake_side := signi(lake.get_center().x - plug_col)
	var best := -1
	var best_score := INF
	for c in range(4, D.W - 9):
		if c != plug_col and absi(c - plug_col) < 6:
			continue
		var score := absf(c - plug_col) + (30.0 if signi(c - plug_col) == lake_side else 0.0)
		if band_has(c - 3, 88, c + 8, turn_y + 6, [D.WATER]):
			score += 400.0
		if score >= best_score:
			continue
		if band_has(c - 3, 88, c + 8, turn_y + 6, [D.LAVA, D.AIR]):
			continue
		var a := mini(c, plug_col)
		var b := maxi(c, plug_col) + 5
		if band_has(a - 2, turn_y - 4, b + 2, turn_y + 9, [D.LAVA, D.AIR, D.WATER]):
			continue
		best = c
		best_score = score
	if best < 0:
		note("no clear column found; using the plug column")
		best = plug_col
	col = best
	start_x = 136 if col >= 128 else 115
	note("seed %d: plug column %d, main column %d, start %d, lake %s" % [seed_value, plug_col, col, start_x, lake])
	plan_glimmer()
	plan_farm()
	plan_tap()


func glim_count(r: Rect2i) -> int:
	r = r.intersection(Rect2i(3, 0, D.W - 6, D.H))
	var n := 0
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			if cell(xx, yy) == D.GLIMMER:
				n += 1
	return n


func plan_glimmer() -> void:
	var cands: Array = []
	var clip := Rect2i(3, 0, D.W - 6, D.H)
	for y in range(312, 592):
		for dir in [1, 2]:
			var r := Rect2i(col - 48, y, 48, 5) if dir == 1 else Rect2i(col + 5, y, 48, 5)
			r = r.intersection(clip)
			if r.size.x < 10:
				continue
			if band_has(r.position.x, y - 3, r.end.x, y + 8, [D.WATER, D.LAVA, D.AIR]):
				continue
			var n := glim_count(r)
			# A second segment when the far half is worth it (the tunnel gets extended).
			var r2 := Rect2i(r.position.x - 48, y, 48, 5) if dir == 1 else Rect2i(r.end.x, y, 48, 5)
			r2 = r2.intersection(clip)
			if r2.size.x >= 10 and not band_has(r2.position.x, y - 3, r2.end.x, y + 8, [D.WATER, D.LAVA, D.AIR]):
				var n2 := glim_count(r2)
				if n2 >= 25:
					n += n2
			if n < 25:
				continue
			cands.append({"y": y, "dir": dir, "count": n, "placed": false})
	cands.sort_custom(func(a, b): return a["count"] > b["count"])
	var total := 0
	for c in cands:
		var clash := false
		for g in glim_plan:
			if absi(g["y"] - c["y"]) < 14:
				clash = true
		if clash:
			continue
		glim_plan.append(c)
		total += c["count"]
		if total >= 700 or glim_plan.size() >= 8:
			break
	glim_plan.sort_custom(func(a, b): return a["y"] < b["y"])
	var desc: Array = []
	for g in glim_plan:
		desc.append("%d%s:%d" % [g["y"], "L" if g["dir"] == 1 else "R", g["count"]])
	note("glimmer plan (%d cells): %s" % [total, ", ".join(desc)])


func plan_farm() -> void:
	# Candidates: the lava lake, and each sealed lava pocket. A pocket makes the
	# better farm: its lava can only meet water inside the drill's own channel,
	# where the crust gets mined, and the steam stays capped under the drill.
	var best := {}
	var best_score := INF
	var bodies: Array = [[game.info["lake"], true]]
	for p: Rect2i in game.info["lava_pockets"]:
		bodies.append([p, false])
	for entry in bodies:
		var c := farm_candidate(entry[0], entry[1])
		if c.is_empty():
			continue
		if c["score"] < best_score:
			best_score = c["score"]
			best = c
	if best.is_empty():
		farm = {"ty": 0, "dir": 1, "spots": [], "far": 0, "surface": 0, "stage": "failed", "tunnel": null, "drills": []}
		note("farm plan: no lava body within reach")
		return
	farm = best
	farm["stage"] = "wait"
	farm["tunnel"] = null
	farm["drills"] = []
	note("farm plan: %s %s, tunnel at %d heading %s, %d drills" % ["lake" if best["lake"] else "pocket",
			best["body"], best["ty"], "left" if best["dir"] == 1 else "right", best["spots"].size()])


func farm_candidate(body: Rect2i, lake: bool) -> Dictionary:
	var cx := body.get_center().x
	var dir := 1 if cx < col else 2
	var ty := body.position.y - (14 if lake else 10)
	if ty < 600 or ty > turn_y - 20:
		return {}
	var spots: Array = []
	var x := mini(body.end.x - 7, col - 10) if dir == 1 else maxi(body.position.x + 2, col + 10)
	while spots.size() < (5 if lake else 3):
		if x < body.position.x or x + 5 > body.end.x:
			break
		var surface := 99999
		var floor_y := 99999
		for k in 5:
			var fy := body.position.y
			while fy < body.end.y and cell(x + k, fy) != D.LAVA:
				fy += 1
			surface = mini(surface, fy)
			while fy < body.end.y + 2 and cell(x + k, fy) == D.LAVA:
				fy += 1
			floor_y = mini(floor_y, fy)
		if floor_y - surface >= 6 and not band_has(x, ty + 5, x + 5, surface, [D.WATER]):
			spots.append({"x": x, "limit": floor_y - 2 - (ty + 5), "surface": surface})
		x += -6 if dir == 1 else 6
	if spots.is_empty():
		return {}
	var far: int = spots.back()["x"]
	var x0 := mini(col + 5, far)
	var x1 := maxi(col, far + 5)
	if absi(far - col) > 150 or band_has(x0, ty - 3, x1, ty + 8, [D.LAVA, D.WATER, D.AIR]):
		return {}
	var score := absi(far - col) + (0.0 if lake else 60.0) - 4.0 * spots.size()
	return {"ty": ty, "dir": dir, "spots": spots, "far": far, "surface": spots[0]["surface"], "lake": lake,
			"body": body, "score": score}


## The nearest place along the farm tunnel where a drill fits over at least
## 6 cells of lava (the tunnel's own drill bodies and Conduits get in the way
## of the planned spots, so this looks at every x).
func farm_next_spot() -> Dictionary:
	var body: Rect2i = farm["body"]
	var ty: int = farm["ty"]
	var xs: Array = range(body.position.x, body.end.x - 4)
	if farm["dir"] == 1:
		xs.reverse()
	for x in xs:
		var r := Rect2i(x, ty, 5, 5)
		var why: String = game.check_place(D.B_DRILL, r)
		if why != "" and why != "Out of network range":
			continue
		var surface := 99999
		var floor_y := 99999
		for k in 5:
			var fy := ty + 5
			while fy < body.end.y and cell(x + k, fy) != D.LAVA:
				fy += 1
			surface = mini(surface, fy)
			while fy < body.end.y + 2 and cell(x + k, fy) == D.LAVA:
				fy += 1
			floor_y = mini(floor_y, fy)
		if floor_y - surface < 6 or floor_y > body.end.y + 1:
			continue
		if band_has(x, ty + 5, x + 5, surface, [D.WATER]):
			continue
		return {"x": x, "limit": floor_y - (ty + 5), "surface": surface, "far": why != ""}
	return {}


# --- helpers ------------------------------------------------------------------------------------

func try_place(type: int, r: Rect2i, dir := 0) -> Building:
	if game.check_place(type, r) != "":
		return null
	return game.place(type, r, dir)


func relay_near(p: Vector2) -> Building:
	var best: Building = null
	var best_d := INF
	for b: Building in game.relays:
		if b.connected and not b.drowned and b.center().distance_to(p) < best_d:
			best_d = b.center().distance_to(p)
			best = b
	return best


func pending_conduit() -> bool:
	for b: Building in game.buildings:
		if b.type == D.B_CONDUIT and not b.built:
			return true
	return false


func frontier(b: Building) -> Vector2:
	var c := b.channel_rect(b.reach)
	match b.dir:
		1:
			return Vector2(c.position.x, b.y + 2)
		2:
			return Vector2(c.end.x - 1, b.y + 2)
	return Vector2(b.x + 2, c.end.y - 1)


func drill_done(b: Building) -> bool:
	if b.reach < b.reach_limit and game._drill_can_extend(b):
		return false
	for r in b.reach:
		for k in 5:
			var c := b.channel_cell(r, k)
			if D.is_drillable(cell(c.x, c.y)):
				return false
	return true


## Keep a Conduit chain within reach of a drill's frontier: along the walls of
## shafts, on the floor of tunnels, clear of where the next drill will stand.
func extend_chain(b: Building, fr: Vector2, force := false) -> bool:
	if pending_conduit():
		return false
	var rel := relay_near(fr)
	if rel == null:
		return false
	var gap := rel.center().distance_to(fr)
	if gap < (10.0 if force else 22.0):
		return false
	var ch := b.channel_rect(b.reach)
	var keep_clear := Rect2i()
	match b.dir:
		1:
			keep_clear = Rect2i(ch.position.x, ch.position.y, 6, ch.size.y)
		2:
			keep_clear = Rect2i(ch.end.x - 6, ch.position.y, 6, ch.size.y)
		_:
			keep_clear = Rect2i(ch.position.x, ch.end.y - 6, ch.size.x, 6)
	var best := Rect2i()
	var best_d := INF
	# A drill's own body plugs its channel's start; the shaft or tunnel behind it counts too.
	var y_from := ch.position.y - 30 if b.dir == 0 else ch.position.y
	var x_from := ch.position.x - 35 if b.dir == 2 else ch.position.x
	var x_to := ch.end.x + 35 if b.dir == 1 else ch.end.x
	for y in range(y_from, ch.end.y - 2):
		for x in range(x_from, x_to - 2):
			var r := Rect2i(x, y, 3, 3)
			if r.intersects(keep_clear) or reserved(r):
				continue
			if b.dir == 0 and x != ch.position.x and x != ch.end.x - 3:
				continue
			if b.dir != 0 and y != ch.end.y - 3:
				continue
			# Any relay may carry it (check_place looks for one); it just has to
			# get the chain closer to the frontier than it is now.
			var c := Vector2(x + 1.5, y + 1.5)
			var d := c.distance_to(fr)
			if d >= best_d or d > gap - 4.0:
				continue
			if has_water(r):
				continue
			if game.check_place(D.B_CONDUIT, r) == "":
				best_d = d
				best = r
	if best_d < INF:
		game.place(D.B_CONDUIT, best, 0)
		return true
	return false


## The main-shaft drill whose channel holds row y.
func shaft_drill_at(y: int) -> Building:
	for b: Building in game.buildings:
		if b.type == D.B_DRILL and b.dir == 0 and b.x == col and not b.dead:
			var ch := b.channel_rect(b.reach)
			if y >= ch.position.y and y < ch.end.y:
				return b
	return null


func has_water(r: Rect2i) -> bool:
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			if cell(xx, yy) == D.WATER:
				return true
	return false


## Rows of the main shaft saved for side drills (glimmer tunnels, the farm tunnel).
func reserved(r: Rect2i) -> bool:
	if absi(r.position.x - col) > 4:
		return false
	for g in glim_plan:
		if not g["placed"] and Rect2i(col, g["y"] - 1, 5, 7).intersects(r):
			return true
	if farm["stage"] == "wait" and Rect2i(col, farm["ty"] - 1, 5, 7).intersects(r):
		return true
	for t in taps:
		if Rect2i(col, t["ty"] - 1, 5, 11).intersects(r):
			return true
	if tap.get("stage", "") in ["wait", "hopper", "tunnel", "flowing"] and Rect2i(col, tap["ty"] - 1, 5, 11).intersects(r):
		return true
	return false


# --- the plan -------------------------------------------------------------------------------------

func think() -> void:
	if stage == "descend":
		descend()
	elif stage == "link":
		link_crucible()
	glimmer()
	obsidian()
	crucible()
	if game.game_time - last_report >= 120.0:
		last_report = game.game_time
		if not farm.get("drills", []).is_empty():
			var fd: Building = farm["drills"][0]
			var col_cells := ""
			for yy in range(fd.y + fd.h + fd.reach - 4, fd.y + fd.h + fd.reach + 4):
				col_cells += "%d:%d " % [yy, cell(fd.x + 2, yy)]
			note("  farm drill: built=%s conn=%s en=%s reach=%d/%d bored=%d hp=%.0f dead=%s cells[%s]" % [fd.built, fd.connected, fd.enabled, fd.reach, fd.reach_limit, fd.cells_bored, fd.hp, fd.dead, col_cells])
			if not farm.get("spouts", []).is_empty():
				var sp: Building = farm["spouts"][0]
				note("  farm spout: conn=%s wet=%s queue=%d tokens=%.2f hp=%.0f sensor=(%d,%d)" % [sp.connected, sp.sensor_wet, sp.queue, sp.tokens, sp.hp, sp.sx, sp.sy])
		var dd: Building = game.deepest_building()
		note("  depth %d, stock S%d G%d O%d W%d, packets %d, sim %.2f ms/tick, lost %d" % [dd.y + dd.h,
				game.stock[0], game.stock[1], game.stock[2], game.stock[3], game.packets.size(), game.perf_sim_ms, game.buildings_lost])


func descend() -> void:
	if cur == null:
		cur = try_place(D.B_DRILL, Rect2i(start_x, D.GROUND_Y - 5, 5, 5), 0)
		if cur != null:
			note("first drill at x %d" % start_x)
		return
	if not cur.built:
		return
	var fr := frontier(cur)
	if flooding:
		handle_flood()
		return
	extend_chain(cur, fr)
	if not cur.dead and not drill_done(cur):
		return
	if tap_due():
		run_tap()
		return
	var r := Rect2i()
	var dir := 0
	var next_leg := leg
	var limit := D.DRILL_REACH
	if leg == 0 or leg == 2 or leg == 4:
		var bottom := int(fr.y)
		var x := cur.x
		if leg == 4 and (game.crucible.connected or (bottom > 895 and cell(x + 2, bottom + 1) in [D.AIR, D.BUILDING]) \
				or Rect2i(x, bottom - 4, 5, 5).intersects(game.crucible.rect())):
			note("broke into the chamber at depth %d" % bottom)
			stage = "link"
			return
		if leg == 0:
			if x == col:
				next_leg = 2
			else:
				next_leg = 1
				dir = 1 if col < x else 2
				limit = clampi(absi(col - x), 5, D.DRILL_REACH)
		elif leg == 2 and bottom >= turn_y + 4:
			if col == plug_col:
				next_leg = 4
			else:
				next_leg = 3
				dir = 1 if plug_col < x else 2
				limit = clampi(absi(plug_col - x), 5, D.DRILL_REACH)
		r = Rect2i(x, bottom - 4, 5, 5)
		if dir == 0 and next_leg == 2:
			limit = clampi(turn_y + 4 - (r.position.y + 5) + 1, 1, D.DRILL_REACH)
	else:
		# leg 1 or 3: tunnelling sideways toward a column
		var target: int = col if leg == 1 else plug_col
		var reached: bool = (cur.x - cur.reach <= target) if cur.dir == 1 else (cur.x + cur.w + cur.reach - 1 >= target + 4)
		if reached:
			next_leg = 2 if leg == 1 else 4
			dir = 0
			r = Rect2i(target, cur.y, 5, 5)
			if next_leg == 2:
				limit = clampi(turn_y + 4 - (cur.y + 5) + 1, 1, D.DRILL_REACH)
		else:
			dir = cur.dir
			var rx := (cur.x - cur.reach) if dir == 1 else (cur.x + cur.w + cur.reach - 5)
			# Keep the last segment's body clear of the column the shaft turns down.
			rx = maxi(rx, target + 5) if dir == 1 else mini(rx, target - 5)
			r = Rect2i(rx, cur.y, 5, 5)
			limit = clampi(absi(target - rx), 5, D.DRILL_REACH)
	var wet := 0
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			if cell(xx, yy) == D.WATER:
				wet += 1
	if wet > 0:
		flooding = true
		note("shaft flooded around depth %d" % r.position.y)
		return
	var why: String = game.check_place(D.B_DRILL, r)
	if why == "Out of network range":
		extend_chain(cur, fr, true)
		return
	if why == "":
		var b: Building = game.place(D.B_DRILL, r, dir)
		game.set_reach_limit(b, limit)
		if next_leg != leg or r.position.y % 144 < 48:
			note("drill at %s facing %s, reach %d (leg %d)" % [r.position, ["down", "left", "right"][dir], b.reach_limit, next_leg])
		leg = next_leg
		cur = b
		blocked_tries = 0
		if sump_due and dir == 0:
			# Whatever still seeps in above lands on this Hopper instead of pooling
			# on the drill and drowning the Conduits.
			for y in range(b.y - 3, b.y - 14, -1):
				var hr := Rect2i(b.x, y, 5, 3)
				if game.check_place(D.B_HOPPER, hr) == "":
					game.place(D.B_HOPPER, hr, 0)
					note("sump hopper parked at depth %d" % y)
					sump_due = false
					break
		return
	if why == "Out of network range":
		return
	# Flooded? Drop Hoppers into the water and wait for it to drain.
	var water := 0
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			if cell(xx, yy) == D.WATER:
				water += 1
	if water > 0:
		flooding = true
		note("shaft flooded around depth %d" % r.position.y)
		return
	blocked_tries += 1
	if blocked_tries % 20 == 1:
		note("  next drill blocked at %s: %s" % [r, why])
	if blocked_tries > 200:
		stage = "stop"


var flood_anchor: Building = null
var sump_due := false      # a leaky section: park a Hopper over the next shaft drill
var flood_taken := -1
var flood_idle_t := 0.0
var flood_total := 0
var flood_waits := 0

## Recovering from a flooded shaft, the way a player would. A Hopper as wide as
## the shaft only drinks through its mouth, so the one that matters sits at the
## very bottom, where everything above pours onto it. If the bottom is out of
## network range, hang an anchor Conduit in the water first (it drowns, but a
## Hopper can still link to it); if even that can't reach, a Hopper as deep as
## the network allows lowers the water in the meantime.
func handle_flood() -> void:
	for h: Building in flood_hoppers:
		if not h.dead and not h.built:
			return
	if flood_anchor != null and not flood_anchor.dead and not flood_anchor.built:
		return
	var ch := cur.channel_rect(cur.reach)
	var top := ch.position.y
	var floor_y := ch.end.y - 1
	while floor_y < ch.end.y + 6 and cell(cur.x + 2, floor_y + 1) in [D.AIR, D.WATER]:
		floor_y += 1
	var water := 0
	var shallowest_wet := 99999
	for yy in range(top, floor_y + 1):
		for xx in range(cur.x, cur.x + 5):
			if cell(xx, yy) == D.WATER:
				water += 1
				shallowest_wet = mini(shallowest_wet, yy)
	var live: Array = []
	for h: Building in flood_hoppers:
		if not h.dead:
			live.append(h)
	if water == 0:
		var taken := flood_total
		for h: Building in live:
			taken += h.cells_taken
			game.demolish(h)
		note("flood drained (hoppers took %d cells)" % taken)
		sump_due = true
		flood_hoppers.clear()
		flood_anchor = null
		flooding = false
		flood_total = 0
		return
	if not live.is_empty():
		# Leave it while it drinks; pull it once it has been idle for 5 s.
		var h: Building = live.back()
		if h.cells_taken != flood_taken:
			flood_taken = h.cells_taken
			flood_idle_t = game.game_time
			return
		if game.game_time - flood_idle_t < 5.0 or h.y + h.h - 1 >= floor_y:
			return
		flood_total += h.cells_taken
		game.demolish(h)
		flood_hoppers.clear()
		return
	var bottom := Rect2i(cur.x, floor_y - 2, 5, 3)
	if game.check_place(D.B_HOPPER, bottom) == "":
		_flood_hopper(bottom, shallowest_wet, floor_y)
		return
	# Follow the falling waterline down with dry Conduits on the wall.
	if extend_chain(cur, Vector2(cur.x + 2, shallowest_wet - 2), true):
		return
	# Anchor high enough to leave the bottom free, low enough for a Hopper to link.
	var rel := relay_near(Vector2(cur.x + 2, floor_y))
	if rel != null and (flood_anchor == null or flood_anchor.dead):
		for y in range(floor_y - 14, floor_y - 5):
			var r := Rect2i(cur.x, y, 3, 3)
			if Vector2(r.position) .distance_to(rel.center() - Vector2(1.5, 1.5)) > D.RELAY_RANGE - 1.0:
				continue
			if game.check_place(D.B_CONDUIT, r) == "":
				flood_anchor = game.place(D.B_CONDUIT, r, 0)
				note("anchor conduit hung at depth %d over a flooded bottom at %d" % [y, floor_y])
				return
	# Can't reach the bottom yet: lower the water with a Hopper as deep as possible.
	for y in range(floor_y - 3, shallowest_wet - 3, -1):
		var hr := Rect2i(cur.x, y, 5, 3)
		if game.check_place(D.B_HOPPER, hr) == "":
			_flood_hopper(hr, shallowest_wet, floor_y)
			return
	flood_waits += 1
	if flood_waits % 40 == 1:
		note("  flood stuck: water %d..%d, anchor %s" % [shallowest_wet, floor_y, "-" if flood_anchor == null else str(flood_anchor.y)])


func _flood_hopper(r: Rect2i, wet_top: int, floor_y: int) -> void:
	flood_hoppers.append(game.place(D.B_HOPPER, r, 0))
	flood_taken = -1
	flood_idle_t = game.game_time
	note("hopper dropped into the flood at depth %d (water %d..%d)" % [r.position.y, wet_top, floor_y])


# --- water: a prepared tap ---------------------------------------------------------------
## Hopper at the bottom of the shaft first, then a side tunnel into an aquifer.
## The tunnel drill stops at the water; removing it lets the water pour down the
## shaft onto the Hopper.
var tap := {}

var taps: Array = []

func plan_tap() -> void:
	for a: Rect2i in game.info["aquifers"]:
		var dir := 0
		var gap := 0
		if a.position.x > col + 4:
			dir = 2
			gap = a.position.x - (col + 5)
		elif a.end.x < col:
			dir = 1
			gap = col - a.end.x
		else:
			continue
		if gap > 88:
			continue
		# Tunnel low in the aquifer, so nearly all of it drains down the shaft, and
		# clear of where the shaft drills will stand (every 48 rows from 83).
		var ty := a.end.y - 9
		while ty > a.position.y + 4 and (ty + 9 - 83) % 48 < 15:
			ty -= 1
		if ty > turn_y - 40:
			continue
		var x0 := (col + 5) if dir == 2 else a.end.x
		var x1 := a.position.x if dir == 2 else col
		if band_has(x0, ty - 2, x1, ty + 7, [D.LAVA, D.AIR]):
			continue
		var clash := false
		for t in taps:
			if absi(t["ty"] - ty) < 20:
				clash = true
		if clash:
			continue
		# Far enough to be sure of the water at this row (the aquifer is an ellipse).
		var need := gap + 10
		var far := (col + 5 + need - 1) if dir == 2 else (col - need)
		taps.append({"ty": ty, "dir": dir, "reach": clampi(need, 5, D.DRILL_REACH), "far": far, "rect": a, "stage": "wait"})
	taps.sort_custom(func(p, q): return p["ty"] < q["ty"])
	if taps.is_empty():
		note("no aquifer within reach of the main column: water must come from elsewhere")
		return
	for t in taps:
		note("water tap plan: aquifer %s, tunnel at depth %d heading %s" % [t["rect"], t["ty"], "left" if t["dir"] == 1 else "right"])
	tap = taps.pop_front()


func tap_due() -> bool:
	if leg != 2:
		return false
	if (tap.is_empty() or tap["stage"] == "done") and not taps.is_empty():
		tap = taps.pop_front()
	if tap.is_empty() or tap["stage"] == "done":
		return false
	if tap["stage"] != "wait":
		return true
	return int(frontier(cur).y) >= tap["ty"] + 12


func run_tap() -> void:
	match tap["stage"]:
		"wait":
			# The Hopper spans the shaft just under the tunnel mouth.
			var hr := Rect2i(col, int(tap["ty"]) + 6, 5, 3)
			if game.check_place(D.B_HOPPER, hr) == "":
				tap["hopper"] = game.place(D.B_HOPPER, hr, 0)
				tap["stage"] = "hopper"
				note("tap: hopper placed under the tunnel at depth %d" % hr.position.y)
			else:
				tap["tries"] = tap.get("tries", 0) + 1
				if tap["tries"] > 40:
					note("tap: hopper spot %s blocked: %s" % [hr, game.check_place(D.B_HOPPER, hr)])
					tap["stage"] = "done"
		"hopper":
			var h: Building = tap["hopper"]
			if not h.built:
				return
			var r := Rect2i(col, tap["ty"], 5, 5)
			if game.check_place(D.B_DRILL, r) == "":
				var d: Building = game.place(D.B_DRILL, r, tap["dir"])
				game.set_reach_limit(d, tap["reach"])
				tap["drill"] = d
				tap["stage"] = "tunnel"
				note("tap: tunnel drill placed at depth %d" % tap["ty"])
		"tunnel":
			var d: Building = tap["drill"]
			if not d.built:
				return
			extend_chain(d, frontier(d))
			if not drill_done(d):
				return
			var far: int = tap["far"]
			var reached: bool = (d.x - d.reach <= far) if d.dir == 1 else (d.x + d.w + d.reach - 1 >= far)
			if not reached:
				# A long way to the water: another segment, then the first drill
				# comes out of the shaft so the water has a way through.
				var nr := Rect2i(d.x - d.reach, d.y, 5, 5) if d.dir == 1 else Rect2i(d.x + d.w + d.reach - 5, d.y, 5, 5)
				var why: String = game.check_place(D.B_DRILL, nr)
				tap["tries2"] = tap.get("tries2", 0) + 1
				if tap["tries2"] % 40 == 1:
					note("  tap: next segment at %s: %s" % [nr, why if why != "" else "ok"])
				if tap["tries2"] > 400:
					note("tap: giving up on this tunnel")
					tap["stage"] = "done"
					return
				if why == "Out of network range":
					extend_chain(d, frontier(d), true)
				elif why == "":
					var nd: Building = game.place(D.B_DRILL, nr, d.dir)
					game.set_reach_limit(nd, clampi(absi(far - nr.position.x) + 1, 5, D.DRILL_REACH))
					tap["drill"] = nd
					tap["old"] = tap.get("old", []) + [d]
					note("tap: tunnel carries on from x %d" % nr.position.x)
				return
			for od: Building in tap.get("old", []):
				game.demolish(od)
			game.demolish(d)
			# Conduits on the tunnel floor would only dam the water: pull them too.
			var tun := Rect2i(mini(far, col), int(tap["ty"]) - 1, absi(far - col) + 5, 7)
			for b: Building in game.buildings.duplicate():
				if b.type == D.B_CONDUIT and tun.encloses(b.rect()) and (b.x + 3 <= col or b.x >= col + 5):
					game.demolish(b)
			tap["stage"] = "flowing"
			tap["t0"] = game.game_time
			note("tap: tunnel reached the water; drill removed, water flowing (the hopper stays)")
		"flowing":
			var h: Building = tap["hopper"]
			if game.game_time - tap["t0"] < 12.0:
				return
			note("tap: hopper has banked %d cells so far; carrying on" % h.cells_taken)
			tap["stage"] = "done"


func link_crucible() -> void:
	if game.crucible.connected:
		note("CRUCIBLE CONNECTED")
		stage = "idle"
		return
	if pending_conduit():
		return
	link_tries += 1
	var cr: Rect2i = game.crucible.rect()
	var rel := relay_near(Vector2(cr.get_center()))
	var best := Rect2i()
	var best_d := INF
	for y in range(cr.position.y - 40, cr.position.y - 2):
		for x in range(cr.position.x - 24, cr.end.x + 24):
			var r := Rect2i(x, y, 3, 3)
			var c := Vector2(r.position) + Vector2(1.5, 1.5)
			if c.distance_to(rel.center()) > D.RELAY_RANGE:
				continue
			var dd: float = game.dist_to_rect(c, cr)
			if dd >= best_d:
				continue
			if game.check_place(D.B_CONDUIT, r) != "":
				continue
			best_d = dd
			best = r
	if best_d < INF:
		game.place(D.B_CONDUIT, best, 0)
		note("chamber conduit at %s, %.1f from the Crucible" % [best.position, best_d])
	elif link_tries > 30:
		note("could not find a spot to link the Crucible")
		stage = "stop"


# --- side projects ------------------------------------------------------------------------------

func glimmer() -> void:
	for g in glim_plan:
		if g.get("dead", false):
			continue
		if not g["placed"]:
			var y: int = g["y"]
			if cur == null or cur.dir != 0 or int(frontier(cur).y) < y + 20:
				continue
			var ok := false
			for dy in [0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5, -6, 6]:
				var gr := Rect2i(col, y + dy, 5, 5)
				if game.check_place(D.B_DRILL, gr) == "":
					g["drill"] = game.place(D.B_DRILL, gr, g["dir"])
					g["placed"] = true
					g["segments"] = 1
					note("glimmer drill at depth %d heading %s (%d cells expected)" % [gr.position.y, "left" if g["dir"] == 1 else "right", g["count"]])
					ok = true
					break
			if not ok:
				var sd := shaft_drill_at(y)
				extend_chain(sd if sd != null else cur, Vector2(col + 2, y + 2), true)
				g["tries"] = g.get("tries", 0) + 1
				if g["tries"] > 200:
					g["dead"] = true
					var reasons := []
					for dy in [0, -3, 3, -6, 6]:
						reasons.append("%d:%s" % [y + dy, game.check_place(D.B_DRILL, Rect2i(col, y + dy, 5, 5))])
					note("  glimmer tunnel at %d abandoned: %s" % [y, ", ".join(reasons)])
			continue
		# Extend a rich tunnel with a second segment.
		var d: Building = g["drill"]
		if d.dead or not d.built or g["segments"] >= 2 or not drill_done(d):
			continue
		var nx := (d.x - d.reach) if d.dir == 1 else (d.x + d.w + d.reach - 5)
		var seg := Rect2i(nx - 48, d.y, 48, 5) if d.dir == 1 else Rect2i(nx + 5, d.y, 48, 5)
		seg = seg.intersection(Rect2i(3, 0, D.W - 6, D.H))
		var n := 0
		for yy in range(seg.position.y, seg.end.y):
			for xx in range(seg.position.x, seg.end.x):
				if cell(xx, yy) == D.GLIMMER:
					n += 1
		if n < 25 or band_has(seg.position.x, d.y - 3, seg.end.x, d.y + 8, [D.WATER, D.LAVA, D.AIR]):
			g["segments"] = 2
			continue
		var r := Rect2i(nx, d.y, 5, 5)
		var why: String = game.check_place(D.B_DRILL, r)
		if why == "Out of network range":
			extend_chain(d, frontier(d), true)
		elif why == "":
			g["drill"] = game.place(D.B_DRILL, r, d.dir)
			g["segments"] = 2
			note("glimmer tunnel at depth %d extended (%d more cells)" % [d.y, n])
		else:
			g["segments"] = 2


func obsidian() -> void:
	match farm["stage"]:
		"wait":
			if farm["spots"].is_empty():
				farm["stage"] = "failed"
				return
			var r := Rect2i(col, farm["ty"], 5, 5)
			if game.check_place(D.B_DRILL, r) == "":
				var b: Building = game.place(D.B_DRILL, r, farm["dir"])
				game.set_reach_limit(b, clampi(absi(farm["far"] - col) + 5, 5, D.DRILL_REACH))
				farm["tunnel"] = b
				farm["stage"] = "tunnel"
				note("farm tunnel started at depth %d" % farm["ty"])
		"tunnel":
			var t: Building = farm["tunnel"]
			if t.dead:
				farm["stage"] = "failed"
				return
			if not t.built:
				return
			extend_chain(t, frontier(t))
			if not drill_done(t):
				return
			# A long way to the lake: carry on with another tunnel segment.
			var far: int = farm["far"]
			var reached: bool = (t.x - t.reach <= far) if t.dir == 1 else (t.x + t.w + t.reach - 1 >= far + 4)
			if not reached:
				var nr := Rect2i(t.x - t.reach, t.y, 5, 5) if t.dir == 1 else Rect2i(t.x + t.w + t.reach - 5, t.y, 5, 5)
				var nwhy: String = game.check_place(D.B_DRILL, nr)
				if nwhy == "Out of network range":
					extend_chain(t, frontier(t), true)
				elif nwhy == "":
					var nb: Building = game.place(D.B_DRILL, nr, t.dir)
					game.set_reach_limit(nb, clampi(absi(far - nr.position.x) + 5, 5, D.DRILL_REACH))
					farm["tunnel"] = nb
					note("farm tunnel carries on from x %d" % nr.position.x)
				return
			# Farm drills across the lava, nearest first, wherever one fits.
			var cap := 6 if farm["lake"] else 3
			if farm["drills"].size() < cap:
				var spot := farm_next_spot()
				if not spot.is_empty() and spot["far"]:
					extend_chain(t, Vector2(spot["x"] + 2, farm["ty"] + 2), true)
					farm["tries"] = farm.get("tries", 0) + 1
					if farm["tries"] < 200:
						return
				elif not spot.is_empty():
					var r := Rect2i(spot["x"], farm["ty"], 5, 5)
					var fd: Building = game.place(D.B_DRILL, r, 0)
					game.set_reach_limit(fd, clampi(spot["limit"], 2, D.DRILL_REACH))
					fd.set_meta("surface", spot["surface"])
					farm["drills"].append(fd)
					note("farm drill %d placed over the lava at x %d (reach %d)" % [farm["drills"].size(), spot["x"], fd.reach_limit])
					return
			farm["stage"] = "spout"
		"spout", "running":
			if farm["drills"].is_empty():
				farm["stage"] = "failed"
				return
			# A Spout under every farm drill (Glimmer allowing), each with its sensor
			# just above the lava so it pauses while water pools on the crust.
			var spouts: Array = farm.get("spouts", [])
			for fd: Building in farm["drills"]:
				if fd.dead or not fd.built or fd.reach < 6 or fd.get_meta("spout", false):
					continue
				var spare: float = game.stock[D.R_GLIMMER] - (0.0 if spouts.is_empty() else D.RECIPE[D.R_GLIMMER] + 4.0)
				if spare < 4.0 or game.stock[D.R_WATER] < 2.0:
					break
				var r := Rect2i(fd.x, fd.y + fd.h, 3, 3)
				if game.check_place(D.B_SPOUT, r) == "":
					var sp: Building = game.place(D.B_SPOUT, r, 0)
					sp.sensor_on = true
					sp.sx = fd.x + 3
					sp.sy = int(fd.get_meta("surface", farm["surface"])) - 3
					spouts.append(sp)
					fd.set_meta("spout", true)
					note("farm spout %d placed" % spouts.size())
					break
			farm["spouts"] = spouts
			if not spouts.is_empty():
				farm["stage"] = "running"
			var on: bool = not activated and game.stock[D.R_OBSIDIAN] < D.RECIPE[D.R_OBSIDIAN] + 2.0 and game.stock[D.R_WATER] > 5.0
			for sp: Building in spouts:
				if not sp.dead:
					sp.enabled = on


func crucible() -> void:
	if activated or not game.crucible.connected:
		return
	var s: PackedFloat64Array = game.stock
	if s[D.R_OBSIDIAN] >= D.RECIPE[D.R_OBSIDIAN] and s[D.R_GLIMMER] >= D.RECIPE[D.R_GLIMMER] and s[D.R_WATER] >= D.RECIPE[D.R_WATER]:
		for b: Building in game.buildings:
			if b.type == D.B_SPOUT:
				b.enabled = false
		game.activate_crucible()
		activated = true
		note("ACTIVATED the Crucible with S%d G%d O%d W%d" % [s[0], s[1], s[2], s[3]])
