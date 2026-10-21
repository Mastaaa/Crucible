extends SceneTree
## Quarry bot (A3 cut). The phase 10 bot played the retired buildings and is gone; this one
## plays what the cut leaves: the starter rig (Cutter, Tank, Funnel, Winch), a Lab and a
## Windmill beside the Hub, and research in a fixed order. It prints the tutorial steps, the
## techs and the depth bands with their times, so the quarry's pace can be read off a run.
## It knows the map (it flattens a strip beside the Hub to build on), so it times the loop for
## someone who knows where things are. The full bot comes back at the end of A4.
##
## godot --headless --path . --script tests/autoplay.gd -- --seed=7 [--max=3600] [--quiet] [--cheat]
## --plug stands the rig over the Crucible chamber's plug instead of beside the Hub. --cheat starts with the research that bears on depth already done and keeps the Hub's power topped up,
## so a run tests what the machines can dig rather than how fast the economy lets them.

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const M = preload("res://scripts/materials.gd")
const Kit = preload("res://tests/autoplay_kit.gd")
const Cutter = preload("res://scripts/machines/excavation/cutter.gd")

const ORDER := ["drill_bit", "drill_shaft", "chute", "pump", "tank_size", "drill_shaft", "lamp", "drill_bit", "drill_shaft", "tank_size", "brace", "plating", "plating"]

## Once ORDER is spent: the first of these that has a level left and a tier open.
const AFTER := ["drill_shaft", "drill_bit", "tank_size", "throughput", "efficiency", "plating"]

var game: Node
var seed_value := 7
var max_time := 3600.0
var quiet := false
var side := -1               # -1 builds left of the Hub, 1 right of it
var f := 0
var rig := {}
var lab := 0
var windmill := 0
var filler := 0              # the Filler that lines the sand rim (--cheat has the tech; the fair bot does not research it)
var nodes := [0, 0, 0]       # Nodes down the strip, nearest the Hub first: 0 to place, 1 placed, 2 built
var rig_x := 0               # --rigx=N: stand the rig at column N (a column left of the Hub moves the Nodes and the Lab; right of it the rig sits beside the Hub)
var node_x := [0, 0, 0]      # where each one went
var col_x := 0               # a rig moved to a new column after a hard-rock patch stopped the old one
var moves := 0
const HARD := {"Flint": 3, "Basalt": 4, "Granite": 5}      # hard-rock patches and the Drill Bit level each takes
var step_seen := 0
var depth_seen := 0
var techs_seen := 0
var last_report := 0.0
var alerts_seen := {}
var cheat := false
var free_levels := {}
var vac_probe := false
var kit = null
var kit_shot := ""
var kit_shot_wait := 0
var shot_depth := 0
var shot_path := ""
var shot_wait := 0
var vac := 0
var digger := "cutter"       # what hangs under the Tank: the Cutter, or the Pump while it drains a liquid the Cutter stops at
var swaps := 0
var swap_logged := false
var halt_logged := ""
var pending := ""            # a digger swap that took the old one down and waits for room to hang the new one


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--max="):
			max_time = float(a.substr(6))
		elif a == "--right":
			side = 1
		elif a.begins_with("--rigx="):
			rig_x = int(a.substr(7))
		elif a == "--quiet":
			quiet = true
		elif a == "--cheat":
			cheat = true
		elif a.begins_with("--shot="):       # --shot=500:/tmp/rig saves a screenshot of the rig at that depth (needs a display: xvfb-run, no --headless)
			var sv := a.substr(7).split(":")
			shot_depth = int(sv[0])
			shot_path = sv[1]
		elif a == "--kit":                   # the surface kit probe (tests/autoplay_kit.gd); a cheated run
			kit = Kit.new()
			cheat = true
		elif a.begins_with("--shotkit="):    # screenshot of the kit once it has run a while (needs a display)
			kit_shot = a.substr(10)
		elif a == "--vac":                   # probe: a Vacuum on the Tank's right socket (cheat-only; it needs the Vacuum tech)
			vac_probe = true
		elif a.begins_with("--lv="):         # --lv=tank_size:3 starts with that research level (probes the economy)
			var kv := a.substr(5).split(":")
			free_levels[kv[0]] = int(kv[1])
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(seed_value)
		game.paused = true
		MC.ensure_defs()
		_flatten()
		for k: String in free_levels:
			game.levels[k] = free_levels[k]
		if not free_levels.is_empty():
			game._refresh_unlocks()
		if cheat:
			game.levels["drill_bit"] = 5
			game.levels["drill_shaft"] = 9
			game.levels["tank_size"] = 3
			game.researched["chute"] = true
			game.researched["pump"] = true
			game.researched["filler"] = true
			if vac_probe:
				for t: String in ["spout", "vacuum"]:
					game.researched[t] = true
			if kit != null:
				kit.prepare(game)
			game._refresh_unlocks()
			game.stock[D.R_STONE] += 20.0               # the Filler's 8 Stone and the Stone it lays, on top of the opening's 60
			game.stock[D.R_GLIMMER] = 40.0
			game.goods[M.id_of("Ferrite")] = 10.0       # the rig's one shaft crosses a seam once (about 2 units); Mk II wants 5 more
		return false
	if f < 3:
		return false
	_play()
	if kit != null:
		kit.step(self)
		if kit_shot != "" and kit.stage == 2 and game.game_time > kit.started + 120.0:
			kit_shot_now()
	if shot_depth > 0 and MC.deepest(game) >= shot_depth and rig.has("tank") and game.modules.has(rig["tank"]):
		shot_wait += 1
		if shot_wait == 1:
			var at: Vector2 = game.modules[rig["tank"]]["at"]
			game.title.visible = false
			game.set_zoom(game.zoom_max * 0.6)
			game._center_on(at.y, true, at.x)
		elif shot_wait == 4:
			var img := root.get_viewport().get_texture().get_image()
			img.save_png(shot_path + ".png")
			print("saved %s.png %s" % [shot_path, img.get_size()])
			shot_depth = 0
	if (game.game_time >= max_time or game.run_lost or game.won) and kit != null:
		kit.final_report(game)
	if game.game_time >= max_time or game.run_lost or game.won:
		_report(true)
		print("FAILURES: 0")
		return true
	return false


## Saves a screenshot of the kit, zoomed on Case A, once it has run a couple of minutes.
func kit_shot_now() -> void:
	kit_shot_wait += 1
	var a: Dictionary = game.modules.get(kit.ids["case_a"], {})
	if a.is_empty():
		return
	if kit_shot_wait == 1:
		game.title.visible = false
		game.set_zoom(game.zoom_max * 0.45)
		game._center_on(a["at"].y, true, a["at"].x - 40.0)
	elif kit_shot_wait == 4:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(kit_shot + ".png")
		print("saved %s.png %s" % [kit_shot, img.get_size()])
		kit_shot = ""


## The strip left of the Hub, cleared to air over a dirt floor: the bot builds there.
func _flatten() -> void:
	var hub: Rect2i = game.hub.rect()
	var ground := hub.end.y
	var from := hub.position.x - 300 if side < 0 else hub.end.x
	var width := 300 if rig_x == 0 else 300 + hub.size.x + 200      # --rigx also builds to the Hub's right
	if kit != null:
		kit.flatten_right(game, hub)
	for x in range(from, from + width):
		if x >= hub.position.x and x < hub.end.x:
			continue
		for y in range(ground - 80, ground):
			game.sim.set_cell(x, y, D.AIR)
		for y in range(ground, ground + 12):
			game.sim.set_cell(x, y, D.DIRT)


## Places a module as the player would, paying its cost; 0 if it can't yet.
func _put(def_id: String, x: int, y: int) -> int:
	var def: Dictionary = MC.defs[def_id]
	if not MC.affordable(game, def) or MC.check_place(game, def_id, Vector2i(x, y), 0) != "":
		return 0
	var id := MC.place(game, def_id, Vector2i(x, y), 0)
	if id > 0:
		var cost: Array = def.get("cost", [])
		for r in cost.size():
			game.stock[r] -= cost[r]
	return id


func _play() -> void:
	if cheat:
		game.stock[D.R_POWER] = 100.0
		game.goods.erase(M.id_of("Slick"))          # the oil goes to a Combustor off screen; a full bank would hold the Tank at the Funnel
	var hub: Rect2i = game.hub.rect()
	var top := hub.end.y
	var x0 := hub.position.x - 230 if side < 0 else hub.end.x + 200
	if OS.get_cmdline_user_args().has("--plug"):
		x0 = int(game.info["plug_x"]) + 7       # the rig stands over the chamber's plug (the one way through the bedrock)
	if rig_x > 0:
		x0 = rig_x
	if col_x > 0:
		x0 = col_x
	# Nodes first: a machine works only with one in reach, and each blueprint waits on the one before.
	var spots := [hub.position.x - 30, hub.position.x - 110, hub.position.x - 190] if side < 0 else [hub.end.x + 10, hub.end.x + 90, hub.end.x + 170]
	var left_rig: bool = rig_x > 0 and rig_x < hub.position.x      # a rig left of the Hub shares its strip, so the Nodes and the Lab move aside
	if left_rig:
		spots = [hub.position.x - 30, hub.position.x - 80, hub.end.x + 10]
	for k in nodes.size():
		if nodes[k] == 0:
			# the rig's shaft widens at the rim with every cave-in, so a spot undercut once is tried again further from it
			for dx in [0, 10, 20, 30, 40]:
				var nx: int = spots[k] + (dx if side < 0 else -dx)
				var r := Rect2i(nx, top - 20, 20, 20)
				if game.check_place(D.B_NODE, r) == "":
					game.place(D.B_NODE, r)
					node_x[k] = nx
					nodes[k] = 1
					break
			break
		elif nodes[k] == 2 and not _built_node(node_x[k], top - 20):
			nodes[k] = 0            # the Node came loose (a cave-in under it) and fell down the shaft: put another beside its spot
			print("%s  node %d lost, rebuilding" % [_clock(game.game_time), k])
			break
		elif nodes[k] == 1:
			if not _built_node(node_x[k], top - 20):
				_run(1.0)
				return
			nodes[k] = 2
	if not rig.has("winch"):
		# A rig that goes down through Sand lets the rim slump and drops the nearest Node into the shaft, so the Filler goes up
		# first, beside the rig, once the Nodes are in (it needs one in reach).
		if filler == 0 and game.researched.has("filler") and nodes.all(func(n): return n == 2):
			filler = _put("filler", x0 - 20, top - 16)
			if filler == 0:
				_run(1.0)
				return
		var parts := [["cutter", x0, top - 16], ["tank", x0, top - 46], ["funnel", x0, top - 60], ["winch", x0 + 14, top - 64]]
		for p: Array in parts:
			if not rig.has(p[0]):
				var id := _put(p[0], p[1], p[2])
				if id > 0:
					rig[p[0]] = id
					if p[0] == "cutter":
						rig["digger"] = id
		_run(1.0)
		return
	if vac_probe and vac == 0 and game.modules.has(rig.get("tank", -1)):
		var tb: Rect2i = MC.bounds(game.modules[rig["tank"]])
		vac = _put("vacuum", tb.end.x, tb.position.y + 1)
		if vac > 0:
			print("%s  vacuum probe: a Vacuum is on the Tank" % _clock(game.game_time))
	if windmill == 0:       # the Windmill first: at 16 Stone it can sit out of reach behind a Lab that took the Stone, with no power to dig more
		windmill = _put("windmill", hub.position.x - 150 if side < 0 else hub.end.x + 120, top - 40)
	elif lab == 0:
		lab = _put("lab", hub.position.x - 80 if side < 0 and not left_rig else hub.end.x + 40, top - 30)
	# The Lab drinks whatever power arrives and leaves the Cutter dry, so research waits while the stockpile is bare.
	if game.current_tech != "" and game.stock[D.R_POWER] < 1.0:
		game.current_tech = ""
	if game.current_tech == "" and game.stock[D.R_POWER] >= 8.0:
		var seen := {}
		for id: String in ORDER:
			seen[id] = int(seen.get(id, 0)) + 1
			if game.level(id) < int(seen[id]) and game.tech_block(id) == "":
				game.pick_research(id)
				break
		if game.current_tech == "":
			for id: String in AFTER:        # the fixed order is spent: the cable is what stops a rig, so keep lengthening it
				if game.tech_block(id) == "":
					game.pick_research(id)
					break
	_swap()
	_run(5.0)
	_report(false)


## When the Winch brings the rig up because a liquid stopped the Cutter, the Pump takes the Cutter's
## place under the Tank; when the Pump has drained what it can reach, the Cutter goes back.
func _swap() -> void:
	if not rig.has("winch") or not game.modules.has(rig["winch"]):
		return
	if pending == "" and rig.has("digger") and not game.modules.has(rig["digger"]) and game.modules.has(rig["tank"]):
		pending = digger        # the digger was lost (corroded away): hang a new one
	if pending != "":
		_exchange(pending)
		return
	var w: Dictionary = game.modules[rig["winch"]]
	var halt: String = w.get("halt", "")
	if halt != "" and halt != halt_logged:
		print("%s  halt at depth %d: %s" % [_clock(game.game_time), MC.deepest(game), halt])
		if OS.get_cmdline_user_args().has("--dump") and game.modules.has(rig.get("digger", -1)):
			_look_below(game.modules[rig["digger"]])
			_look_front(game.modules[rig["digger"]])
	halt_logged = halt
	if w["state"] != "docked" or halt == "":
		return
	if _hard_halt(halt):
		_move_rig()
		return
	if digger == "cutter" and game.researched.has("pump") and _liquid_halt(halt):
		_exchange("pump")
	elif digger == "pump" and "Pump" in halt:
		_exchange("cutter")


## True when the halt names a hard-rock patch that the Drill Bit cannot open yet.
func _hard_halt(halt: String) -> bool:
	for nm: String in HARD:
		if nm in halt and game.level("drill_bit") < int(HARD[nm]):
			return true
	return false


## The shaft is blocked by a lens of hard rock the bit cannot open: take the rig down and stand it on a
## column of the strip with the least of that rock below it. The bot reads the map to choose, which a
## player would learn by feeling for it with a Lamp or a probe shaft.
func _move_rig() -> void:
	var hub: Rect2i = game.hub.rect()
	var top := hub.end.y
	var lvl: int = game.level("drill_bit")
	var rocks: Array = []
	for nm: String in HARD:
		if int(HARD[nm]) > lvl:
			rocks.append(M.id_of(nm))
	var old_x: int = int(game.modules[rig["winch"]]["at"].x) - 14
	var best_x := -1
	var best_hard := 1 << 30
	for x in range(hub.position.x - 290, hub.end.x + 140, 10):
		if absi(x - old_x) < 40:
			continue
		var ok := true
		for p: Array in [["cutter", x, top - 16], ["tank", x, top - 46], ["funnel", x, top - 60], ["winch", x + 14, top - 64]]:
			if MC.check_place(game, p[0], Vector2i(p[1], p[2]), 0) != "":
				ok = false
				break
		if not ok or game.find_link(-1, Rect2i(x, top - 16, 22, 12), null) == null or game.find_link(-1, Rect2i(x + 14, top - 64, 8, 8), null) == null:
			continue        # a part would sit out of every Node's reach
		var counts: PackedInt32Array = game.sim.rect_counts(x, top, 30, 1500)
		var n := 0
		for id: int in rocks:
			n += counts[id]
		if n < best_hard:
			best_hard = n
			best_x = x
	if best_x < 0:
		return
	# Moving the rig by hand costs nothing, so each part's price goes back to the stockpile as it comes down.
	var down := {}
	for k: String in ["cutter", "tank", "funnel", "winch", "digger"]:
		var mid: int = rig.get(k, -1)
		if game.modules.has(mid) and not down.has(mid):
			down[mid] = true
			var cost: Array = MC.defs[game.modules[mid]["def"]].get("cost", [])
			for r in mini(cost.size(), D.NRES):
				game.stock[r] += float(cost[r])
			MC.remove(game, mid)
	rig = {}
	filler = 0
	digger = "cutter"
	pending = ""
	col_x = best_x
	moves += 1
	halt_logged = ""
	print("%s  move %d: hard rock stops the shaft, the rig goes to column %d (%d hard cells below it)" % [_clock(game.game_time), moves, best_x, best_hard])


## True for "The Excavator stopped: Slick ahead." when what it names is a liquid.
func _liquid_halt(halt: String) -> bool:
	var i := halt.find(": ")
	var j := halt.find(" ahead")
	if i < 0 or j < i:
		return false
	var id := M.id_of(halt.substr(i + 2, j - i - 2))
	return id > 0 and M.kinds[id] == M.K_LIQUID


## Takes the digger down and hangs `def_id` on the Tank's lower face in its place (paid for like any
## build). If the spot is not free yet the swap waits in `pending` and is tried again on the next pass.
func _exchange(def_id: String) -> void:
	var def: Dictionary = MC.defs[def_id]
	if pending == "":
		if not MC.affordable(game, def) or not game.modules.has(rig["tank"]):
			return
		MC.remove(game, rig["digger"])
		pending = def_id
	elif not MC.affordable(game, def):
		return
	var id := _hang(def_id)
	if id == 0:
		if not swap_logged:
			swap_logged = true
			print("%s  the %s waits for room under the Tank" % [_clock(game.game_time), def_id])
		return
	swap_logged = false
	var cost: Array = def.get("cost", [])
	for r in cost.size():
		game.stock[r] -= cost[r]
	rig["digger"] = id
	digger = def_id
	pending = ""
	swaps += 1
	print("%s  swap %d: the %s goes on the rig" % [_clock(game.game_time), swaps, def_id])


## Places `def_id` against the Tank's lower face and returns its id, or 0. The Tank's stored position
## lags its body by a cell or two, so the snapped spot is tried a row or two lower as well, and only
## a placement that joined the Tank's face is kept.
func _hang(def_id: String) -> int:
	var def: Dictionary = MC.defs[def_id]
	var b: Rect2i = MC.bounds(game.modules[rig["tank"]])
	var size: Vector2i = Vector2i(def["size"][0], def["size"][1])
	var sn := MC.snap(game, def_id, 0, Vector2i(b.position.x + (b.size.x >> 1), b.end.y + (size.y >> 1)))
	for dy in [0, 1, 2]:
		var at := Vector2i(sn["at"].x, sn["at"].y + dy)
		if MC.check_place(game, def_id, at, 0) != "":
			continue
		var id := MC.place(game, def_id, at, 0)
		if id == 0:
			continue
		if game.modules[id]["faces"][0]["link_m"] != 0:
			return id
		MC.remove(game, id)
	return 0



func _built_node(x: int, y: int) -> bool:
	for b: Object in game.buildings:
		if b.type == D.B_NODE and b.x == x and absi(b.y - y) < 40 and b.built:      # one that fell down the shaft keeps its x
			return true
	return false


func _run(s: float) -> void:
	game.run_ticks(int(s * 60.0))


func _clock(t: float) -> String:
	return "%d:%02d" % [floori(t / 60.0), int(t) % 60]


func _report(final: bool) -> void:
	var t: float = game.game_time
	if int(game.goals["step"]) > step_seen:
		step_seen = int(game.goals["step"])
		print("%s  tutorial: instruction %d done" % [_clock(t), step_seen])
	var techs := 0
	for id: String in game.researched:
		techs += 1
	for id: String in game.levels:
		techs += int(game.levels[id])
	if techs > techs_seen:
		techs_seen = techs
		print("%s  research: %d done (%s)" % [_clock(t), techs, ", ".join(game.researched.keys())])
	for a: Dictionary in game.alerts:
		var key := "%s@%d" % [a["text"], int(a["t"] / 30.0)]
		if a["kind"] != "info" and not alerts_seen.has(key):
			alerts_seen[key] = true
			print("%s  alert: %s" % [_clock(t), a["text"]])
	var depth := MC.deepest(game)
	while depth >= (depth_seen + 1) * 500:
		depth_seen += 1
		print("%s  the rig has reached depth %d" % [_clock(t), depth_seen * 500])
	if final or (not quiet and t - last_report >= 300.0):
		last_report = t
		var why := ""
		if rig.has("winch") and game.modules.has(rig["winch"]):
			var w: Dictionary = game.modules[rig["winch"]]
			why = "winch %s %s" % [w.get("state", "?"), w.get("why", "")]
		if final and OS.get_cmdline_user_args().has("--dump"):
			for k: String in rig:
				var md: Dictionary = game.modules.get(rig[k], {})
				print("  %s: %s" % [k, str(md).left(700)])
		if final and OS.get_cmdline_user_args().has("--dump") and rig.has("tank") and game.modules.has(rig["tank"]):
			_look_above(game.modules[rig["tank"]])
			_look_below(game.modules[rig["tank"]])
		if OS.get_cmdline_user_args().has("--profile") and t >= 6000.0:
			_shaft_profile()
		if final and OS.get_cmdline_user_args().has("--dump"):
			print("  goods %s, tech power %s, tech bank %s" % [str(game.goods), str(game.tech_power), str(game.tech_bank)])
			print("  winch blips (wall readings that came and went): %d" % game.modules.get(rig.get("winch", -1), {}).get("blips", 0))
		print("%s  depth %d, Stone %d (delivered %d), Glimmer %d, power %d (made %.2f used %.2f), tech %s, %s" % [_clock(t), depth, int(game.stock[D.R_STONE]), int(game.goals["delivered"][D.R_STONE]), int(game.stock[D.R_GLIMMER]), int(game.stock[D.R_POWER]), game.power_made, game.power_used, game.current_tech, why])


## What sits in the shaft just above the Tank: loose bodies, and the solid cells by material.
func _look_above(tank: Dictionary) -> void:
	var at: Vector2 = tank["at"]
	var mods := {}
	for id: int in game.modules:
		mods[game.modules[id]["body"]] = true
	var bl: PackedInt32Array = game.sim.get_bodies()
	for k in range(0, bl.size(), 7):
		if not mods.has(bl[k]) and bl[k + 4] > at.y - 60 and bl[k + 2] < at.y + 20 and bl[k + 3] > at.x - 60 and bl[k + 1] < at.x + 60:
			print("  body %d box (%d,%d)-(%d,%d) %d cells, speed %d" % [bl[k], bl[k + 1], bl[k + 2], bl[k + 3], bl[k + 4], bl[k + 6], bl[k + 5]])
	for dy in [-8, -16, -24, -32, -48]:
		var row := ""
		for dx in range(-24, 25, 2):
			var c: int = game.sim.get_cell(int(at.x) + dx, int(at.y) + dy)
			row += "." if c == 0 else str(c % 10)
		print("  y%+d %s" % [dy, row])


## The rows round the Tank's bottom edge, for a rig that stopped in open ground: what touches the Tank.
func _look_below(tank: Dictionary) -> void:
	var tb: Rect2i = MC.bounds(tank)
	var sv: PackedFloat32Array = game.sim.body_state(tank["body"])
	print("  tank bounds %s body (%.2f, %.2f) rot %.4f" % [str(tb), sv[0], sv[1], sv[2]])
	for yy in range(tb.end.y - 6, tb.end.y + 8):
		var row := ""
		for xx in range(tb.position.x - 8, tb.end.x + 9):
			var c: int = game.sim.get_cell(xx, yy)
			row += "." if c == 0 else str(c % 10)
		print("  y%d %s" % [yy, row])
	var near := []
	for yy in range(tb.position.y, tb.end.y + 4):
		for xx in [tb.position.x - 2, tb.position.x - 1, tb.end.x, tb.end.x + 1]:
			var c: int = game.sim.get_cell(xx, yy)
			if c != 0:
				near.append("(%d,%d)=%d" % [xx, yy, c])
	print("  cells within 2 of the Tank's sides: %s" % ", ".join(near))


## What sits in the slices just ahead of a Cutter's front: material names and counts, the way `scan` reads them.
func _look_front(m: Dictionary) -> void:
	var def: Dictionary = MC.defs[m["def"]]
	if def.get("kind", "") != "cutter":
		return
	var fo: Dictionary = Cutter.front_of(game, m, def)
	print("  front p %s n %s across %d off %d" % [str(fo["p"]), str(fo["n"]), fo["across"], m.get("off", 0)])
	for k in 6:
		var r: Rect2i = Cutter.slice(fo["p"], fo["n"], k, int(def["params"]["width"]), m.get("off", 0))
		var counts: PackedInt32Array = game.sim.rect_counts(r.position.x, r.position.y, r.size.x, r.size.y)
		var parts := []
		for mat in range(1, 256):
			if counts[mat] > 0:
				parts.append("%s %d" % [M.names[mat], counts[mat]])
		print("    k%d %s: %s" % [k, str(r), ", ".join(parts)])


## Liquids and gas in the shaft column by depth band: where the water, lava and steam sit.
func _shaft_profile() -> void:
	var tank: Dictionary = game.modules.get(rig.get("tank", -1), {})
	if tank.is_empty():
		return
	var x0: int = int(tank["at"].x) - 15
	var mats := {"Water": D.WATER, "Lava": D.LAVA, "Slick": D.SLICK, "Steam": D.STEAM}
	var line := ""
	for y0 in range(150, 3000, 200):
		var parts := []
		for nm: String in mats:
			var mask := PackedByteArray()
			mask.resize(256)
			mask[mats[nm]] = 1
			if nm == "Steam":
				for k in range(D.STEAM, D.STEAM_LAST + 1):
					mask[k] = 1
			var n: int = game.sim.count_in_rect(x0, y0, 30, 200, mask)
			if n > 0:
				parts.append("%s %d" % [nm, n])
		if not parts.is_empty():
			line += "  y%d: %s\n" % [y0, ", ".join(parts)]
	print("  shaft profile at %s:\n%s" % [_clock(game.game_time), line.rstrip("\n")])

