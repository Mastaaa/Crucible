extends SceneTree
## Quarry bot (A3 cut). The phase 10 bot played the retired buildings and is gone; this one
## plays what the cut leaves: the starter rig (Cutter, Tank, Funnel, Winch), a Lab and a
## Windmill beside the Hub, and research in a fixed order. It prints the tutorial steps, the
## techs and the depth bands with their times, so the quarry's pace can be read off a run.
## It knows the map (it flattens a strip beside the Hub to build on), so it times the loop for
## someone who knows where things are. The full bot comes back at the end of A4.
##
## godot --headless --path . --script tests/autoplay.gd -- --seed=7 [--max=3600] [--quiet] [--cheat]
## --cheat starts with the research that bears on depth already done and keeps the Hub's power topped up,
## so a run tests what the machines can dig rather than how fast the economy lets them.

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")

const ORDER := ["drill_bit", "drill_shaft", "tank_size", "drill_shaft", "lamp", "drill_bit", "drill_shaft", "tank_size", "brace"]

var game: Node
var seed_value := 7
var max_time := 3600.0
var quiet := false
var side := -1               # -1 builds left of the Hub, 1 right of it
var f := 0
var rig := {}
var lab := 0
var windmill := 0
var nodes := [0, 0, 0]       # Nodes down the strip, nearest the Hub first
var step_seen := 0
var depth_seen := 0
var techs_seen := 0
var last_report := 0.0
var alerts_seen := {}
var cheat := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--max="):
			max_time = float(a.substr(6))
		elif a == "--right":
			side = 1
		elif a == "--quiet":
			quiet = true
		elif a == "--cheat":
			cheat = true
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		game.new_game(seed_value)
		game.paused = true
		MC.ensure_defs()
		_flatten()
		if cheat:
			game.levels["drill_bit"] = 5
			game.levels["drill_shaft"] = 8
			game.levels["tank_size"] = 3
		return false
	if f < 3:
		return false
	_play()
	if game.game_time >= max_time or game.run_lost or game.won:
		_report(true)
		print("FAILURES: 0")
		return true
	return false


## The strip left of the Hub, cleared to air over a dirt floor: the bot builds there.
func _flatten() -> void:
	var hub: Rect2i = game.hub.rect()
	var ground := hub.end.y
	var from := hub.position.x - 300 if side < 0 else hub.end.x
	for x in range(from, from + 300):
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
	var hub: Rect2i = game.hub.rect()
	var top := hub.end.y
	var x0 := hub.position.x - 230 if side < 0 else hub.end.x + 200
	# Nodes first: a machine works only with one in reach, and each blueprint waits on the one before.
	var spots := [hub.position.x - 30, hub.position.x - 110, hub.position.x - 190] if side < 0 else [hub.end.x + 10, hub.end.x + 90, hub.end.x + 170]
	for k in nodes.size():
		if nodes[k] == 0:
			var r := Rect2i(spots[k], top - 20, 20, 20)
			if game.check_place(D.B_NODE, r) == "":
				game.place(D.B_NODE, r)
				nodes[k] = 1
			break
		elif not _built_node(spots[k]):
			_run(1.0)
			return
	if not rig.has("winch"):
		var parts := [["cutter", x0, top - 16], ["tank", x0, top - 46], ["funnel", x0, top - 60], ["winch", x0 + 14, top - 64]]
		for p: Array in parts:
			if not rig.has(p[0]):
				var id := _put(p[0], p[1], p[2])
				if id > 0:
					rig[p[0]] = id
		_run(1.0)
		return
	if lab == 0:
		lab = _put("lab", hub.position.x - 80 if side < 0 else hub.end.x + 40, top - 30)
	elif windmill == 0:
		windmill = _put("windmill", hub.position.x - 150 if side < 0 else hub.end.x + 120, top - 40)
	if game.current_tech == "":
		var seen := {}
		for id: String in ORDER:
			seen[id] = int(seen.get(id, 0)) + 1
			if game.level(id) < int(seen[id]) and game.tech_block(id) == "":
				game.pick_research(id)
				break
	_run(5.0)
	_report(false)


func _built_node(x: int) -> bool:
	for b: Object in game.buildings:
		if b.type == D.B_NODE and b.x == x and b.built:
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
		print("%s  depth %d, Stone %d, power %d, tech %s, %s" % [_clock(t), depth, int(game.stock[D.R_STONE]), int(game.stock[D.R_POWER]), game.current_tech, why])
