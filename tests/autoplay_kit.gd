extends RefCounted
## The quarry bot's kit probe (`--kit`, A9): a surface assembly right of the Hub that runs for the whole bot run, so a long
## session exercises the A9 parts the rig cannot carry. A Vacuum on Case A pulls a pile of Sand off the ground into the Case,
## a Pipe carries it to Case B, a Floodlight sits on Case B, and each Case is pinned to the ground. The pile is laid again
## whenever it is gone, and Case B is emptied when it is nearly full, so the loop keeps running.
## The pacing numbers do not read this: the kit has its own Nodes and Stone, and it only starts once the rig stands.

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const MU = preload("res://scripts/machines/mu.gd")
const JT = preload("res://scripts/machines/joints.gd")
const LN = preload("res://scripts/machines/lines.gd")
const M = preload("res://scripts/materials.gd")

const TECHS := ["case", "pipes", "spout", "vacuum", "floodlight", "joints", "strut", "cables"]
const PILE := Rect2i(0, 0, 30, 8)          # the sand heap under the Vacuum's mouth: its size, placed in `_dump`
const REPORT_EVERY := 600.0                # game seconds between status lines
const DUMP_EVERY := 120.0                  # game seconds before a new pile is laid, once the last is gone
const EMPTY_AT := 0.8                      # Case B is emptied past this share of its capacity

var stage := 0                             # 0 Nodes, 1 parts, 2 running
var nodes := [0, 0]                       # 0 to place, 1 placed, 2 built (the kit stands within reach of these two)
var node_x := [0, 0]
var ids := {}                              # "case_a", "hook_a", "vacuum", "case_b", "hook_b", "light", "pipe"
var lost := {}                             # parts already reported gone
var pinned := false
var piped := false
var started := 0.0
var last_report := 0.0
var dumps := 0
var last_dump := 0.0
var emptied := 0
var moved := 0                             # cells the Vacuum has put into Case A, seen from outside
var pile_at := Vector2i.ZERO
var sand := 0


func _init() -> void:
	sand = M.id_of("Sand")


## Marks the techs the kit needs as researched (the kit runs on the cheated bot).
func prepare(game: Node) -> void:
	for t: String in TECHS:
		game.researched[t] = true


func flatten_right(game: Node, hub: Rect2i) -> void:
	for x in range(hub.end.x, hub.end.x + 300):
		for y in range(hub.end.y - 80, hub.end.y):
			game.sim.set_cell(x, y, D.AIR)
		for y in range(hub.end.y, hub.end.y + 12):
			game.sim.set_cell(x, y, D.DIRT)


## One pass of the kit, called by the bot each time it plays. `bot` is the autoplay script (its `_put` pays and places).
func step(bot) -> void:
	var game: Node = bot.game
	var hub: Rect2i = game.hub.rect()
	var top := hub.end.y
	if stage == 0:
		if not bot.rig.has("winch"):
			return
		for k in nodes.size():
			var nx: int = hub.end.x + 10 + 80 * k
			if nodes[k] == 0:
				var r := Rect2i(nx, top - 20, 20, 20)
				if game.check_place(D.B_NODE, r) == "":
					game.place(D.B_NODE, r)
					node_x[k] = nx
					nodes[k] = 1
				return
			if nodes[k] == 1:
				if not bot._built_node(node_x[k], top - 20):
					return
				nodes[k] = 2
		stage = 1
		started = game.game_time
		game.stock[D.R_STONE] += 150.0          # the kit's own Stone, so the rig's budget is the one the baseline has
		print("%s  kit: Nodes built, placing the parts" % bot._clock(game.game_time))
	if stage == 1:
		_place_parts(bot, hub, top)
		return
	_run(bot, top)


func _place_parts(bot, hub: Rect2i, top: int) -> void:
	var game: Node = bot.game
	var xb := hub.end.x + 40
	var xa := xb + 26 + 18 + 40 + 18
	var plan := [
		["case_b", "case", xb, top - 26, 0],
		["hook_b", "pipe_hookup", xb + 26, top - 25, 0],
		["case_a", "case", xa, top - 26, 0],
		["hook_a", "pipe_hookup", xa - 18, top - 25, 2],
		["vacuum", "vacuum", xa + 26, top - 26, 0],
		["light", "floodlight", xb + 5, top - 42, 3],
	]
	for p: Array in plan:
		if ids.has(p[0]):
			continue
		var def: Dictionary = MC.defs[p[1]]
		if not MC.affordable(game, def) or MC.check_place(game, p[1], Vector2i(p[2], p[3]), p[4]) != "":
			return
		var id := MC.place(game, p[1], Vector2i(p[2], p[3]), p[4])
		if id == 0:
			return
		var cost: Array = def.get("cost", [])
		for r in cost.size():
			game.stock[r] -= cost[r]
		ids[p[0]] = id
	if not pinned:
		# A Case with a hookup or a Vacuum on one side tips: pin each to the ground under it.
		for k: String in ["case_a", "case_b"]:
			var c: Rect2i = MC.bounds(game.modules[ids[k]])
			var at := Vector2(c.position.x + (c.size.x >> 1), c.end.y + 0.5)
			JT.attach(game, "piton", ids[k], 0, at, at)
		pinned = true
		return
	if not piped:
		game.joint_from = {}
		LN.click(game, "pipe", _point(game, ids["hook_a"]))
		LN.click(game, "pipe", _point(game, ids["hook_b"]))
		var lines := LN.all(game)
		if lines.is_empty():
			print("%s  kit: the Pipe would not lay" % bot._clock(game.game_time))
			return
		ids["pipe"] = lines[lines.size() - 1]
		piped = true
		stage = 2
		_dump(game, top)
		print("%s  kit: parts placed and piped, %d Sand laid under the Vacuum" % [bot._clock(game.game_time), _pile(game)])


func _point(game: Node, id: int) -> Vector2:
	for pt: Dictionary in JT.points(game, game.modules[id]):
		if pt["name"] == "pipe" and pt["kind"] == "hookup":
			return pt["pos"]
	return Vector2(-1, -1)


## Lays a heap of Sand on the ground under the Vacuum's mouth.
func _dump(game: Node, top: int) -> void:
	var v: Rect2i = MC.bounds(game.modules[ids["vacuum"]])
	pile_at = Vector2i(v.position.x + 5, top - PILE.size.y)
	for y in range(pile_at.y, top):
		for x in range(pile_at.x, pile_at.x + PILE.size.x):
			if game.sim.get_cell(x, y) == D.AIR:
				game.sim.set_cell(x, y, sand)
	dumps += 1
	last_dump = game.game_time


## Sand left in the area under the Vacuum.
func _pile(game: Node) -> int:
	var mask := PackedByteArray()
	mask.resize(256)
	mask[sand] = 1
	return game.sim.count_in_rect(pile_at.x - 20, pile_at.y - 10, PILE.size.x + 40, PILE.size.y + 14, mask)


func _run(bot, top: int) -> void:
	var game: Node = bot.game
	for k: String in ids:
		if not game.modules.has(ids[k]) and not lost.has(k):
			lost[k] = true
			print("%s  kit: the %s is gone" % [bot._clock(game.game_time), k])
	if not game.modules.has(ids["case_b"]) or not game.modules.has(ids["vacuum"]):
		return
	var b: Dictionary = game.modules[ids["case_b"]]
	if _pile(game) < 20 and game.game_time - last_dump >= DUMP_EVERY:
		_dump(game, top)
	if MU.stored(b) > int(float(MU.capacity(b, MC.defs["case"])) * EMPTY_AT):
		for mat: int in b["contents"].keys():
			emptied += MU.take(b, mat, int(b["contents"][mat]))
	if game.game_time - last_report >= REPORT_EVERY:
		last_report = game.game_time
		print("%s  %s" % [bot._clock(game.game_time), summary(game)])


func _state(game: Node, k: String) -> String:
	if not ids.has(k) or not game.modules.has(ids[k]):
		return "gone"
	var m: Dictionary = game.modules[ids[k]]
	if str(m.get("needs", "")) != "":
		return "needs: %s" % m["needs"]
	return "ok"


func summary(game: Node) -> String:
	var a := MU.stored(game.modules[ids["case_a"]]) if game.modules.has(ids["case_a"]) else -1
	var b := MU.stored(game.modules[ids["case_b"]]) if game.modules.has(ids["case_b"]) else -1
	var lit: bool = game.modules.has(ids["light"]) and game.modules[ids["light"]].get("lit", false)
	return "kit: Vacuum %s, Case A %d, Case B %d, Pipe carries %d, Floodlight %s, pile %d left, %d piles, %d cells emptied" % [
		_state(game, "vacuum"), a, b, MU.stored(game.modules[ids["pipe"]]) if game.modules.has(ids["pipe"]) else -1,
		"lit" if lit else "dark", _pile(game), dumps, emptied]


## The checks at the end of the run: every part still stands and has what it needs, the Vacuum has fed the Cases, the light is on.
func final_report(game: Node) -> void:
	if stage < 2:
		print("kit: FAIL never got built (stage %d)" % stage)
		return
	var bad: Array = []
	for k: String in ["case_a", "hook_a", "vacuum", "case_b", "hook_b", "light", "pipe"]:
		var s := _state(game, k)
		if s != "ok":
			bad.append("%s %s" % [k, s])
	var in_b := MU.stored(game.modules[ids["case_b"]]) if game.modules.has(ids["case_b"]) else 0
	if emptied + in_b <= 0:
		bad.append("nothing reached Case B")
	if not (game.modules.has(ids["light"]) and game.modules[ids["light"]].get("lit", false)):
		bad.append("the Floodlight is dark")
	print(summary(game))
	print("kit: %s" % ("ok" if bad.is_empty() else "FAIL " + "; ".join(bad)))
