extends RefCounted
## The goal layer (Alpha A3, v1). Static helpers the game calls with itself as `game`;
## the state is one Dictionary, `game.goals`, saved with the run.
##
## The Hub issues flat orders from data/instructions.json: a tutorial track (skippable
## from the first run) and then a standing order every few minutes. An order names what
## to deliver, never how. Depth bands act as chapters, each with one objective, reported
## through the event tracker (`game.mark`). Rewards are power paid into the Hub. Research
## also eats goods: `research_mats` adds a per-tier cost to a tech's own materials.

const D = preload("res://scripts/defs.gd")
const MC = preload("res://scripts/machines/machines.gd")
const PATH := "res://data/instructions.json"
const CHECK_EVERY := 30             # ticks between checks

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"tutorial": [], "standing": [], "chapters": []}
	return _data


static func fresh() -> Dictionary:
	return {
		"mode": "tutorial",         # "tutorial" until finished or skipped, then "standing"
		"step": 0,                  # next tutorial step
		"picks": 0,                 # standing orders issued so far
		"number": 0,                # instructions issued, for "Instruction N"
		"cur": {},                  # the order on the board: {text, check, reward, n}
		"base": [0.0, 0.0, 0.0, 0.0, 0.0],   # delivered totals when it was issued
		"delivered": [0.0, 0.0, 0.0, 0.0, 0.0],
		"next_t": 0.0,              # game time the next standing order is issued
		"chapter": 0,               # chapters completed
	}


## Goods banked at the Hub or a Cache, for delivery orders.
static func delivered(game, r: int, amount: float) -> void:
	game.goals["delivered"][r] += amount


## The Hub's tick hook. Cheap: it looks twice a second.
static func tick(game) -> void:
	if game.ticks % CHECK_EVERY != 0:
		return
	var g: Dictionary = game.goals
	var chapters: Array = data()["chapters"]
	while g["chapter"] < chapters.size() and _met(game, chapters[g["chapter"]]["check"], g):
		var c: Dictionary = chapters[g["chapter"]]
		g["chapter"] += 1
		game.mark("Chapter %d done (%s): %s" % [g["chapter"], c["band"], c["objective"]])
	if g["cur"].is_empty():
		if g["mode"] == "tutorial":
			_issue(game, data()["tutorial"][g["step"]])
		elif game.game_time >= g["next_t"]:
			_issue_standing(game)
		return
	if _met(game, g["cur"]["check"], g):
		_complete(game)


static func skip_tutorial(game) -> void:
	var g: Dictionary = game.goals
	if g["mode"] != "tutorial":
		return
	g["mode"] = "standing"
	g["cur"] = {}
	g["next_t"] = game.game_time + 20.0
	game.mark("Tutorial skipped", false)


static func _issue(game, def: Dictionary) -> void:
	var g: Dictionary = game.goals
	g["number"] += 1
	g["cur"] = {"text": def["text"], "check": def["check"], "reward": def.get("reward", {}), "n": g["number"]}
	g["base"] = g["delivered"].duplicate()
	game.show_banner("Instruction %d: %s" % [g["number"], def["text"]], 4.0)


static func _issue_standing(game) -> void:
	var g: Dictionary = game.goals
	var pool: Array = []
	for s: Dictionary in data()["standing"]:
		if s["chapter"] <= g["chapter"]:
			pool.append(s)
	if pool.is_empty():
		return
	var def: Dictionary = pool[g["picks"] % pool.size()]
	g["picks"] += 1
	_issue(game, def)


static func _complete(game) -> void:
	var g: Dictionary = game.goals
	var cur: Dictionary = g["cur"]
	var reward: Dictionary = cur["reward"]
	var pay := float(reward.get("power", 0.0))
	if pay > 0.0:
		game.stock[D.R_POWER] = minf(game.stock[D.R_POWER] + pay, game.power_cap())
	game.mark("Instruction %d done: %s" % [cur["n"], cur["text"]], false)
	game.show_banner("Instruction %d done.%s" % [cur["n"], " %d power sent." % int(pay) if pay > 0.0 else ""], 3.0)
	g["cur"] = {}
	if g["mode"] == "tutorial":
		g["step"] += 1
		if g["step"] >= (data()["tutorial"] as Array).size():
			g["mode"] = "standing"
			g["next_t"] = game.game_time + float(data()["gap_s"])
	else:
		g["next_t"] = game.game_time + float(data()["gap_s"])


static func _met(game, chk: Dictionary, g: Dictionary) -> bool:
	match chk["kind"]:
		"built":
			# A structure (Node, Bulkhead, Brace) or a module, by name.
			var type := D.B_NAMES.find(chk["building"])
			for b in game.buildings:
				if b.type == type and b.built and not b.dead:
					return true
			return MC.count_named(game, chk["building"]) > 0
		"researched":
			return game.researched.size() >= int(chk["count"])
		"deliver":
			var r := D.RES_NAMES.find(chk["res"])
			return g["delivered"][r] - g["base"][r] >= float(chk["amount"])
		"depth":
			return game.deepest >= int(chk["value"])
		"tier":
			return game.tiers_open[int(chk["tier"])]
		"light":
			return game.cstate >= 2
		"all":
			for sub: Dictionary in chk["of"]:
				if not _met(game, sub, g):
					return false
			return true
	return false


## "12 / 30" for a delivery order in progress, else "".
static func progress(game) -> String:
	var g: Dictionary = game.goals
	if g["cur"].is_empty():
		return ""
	var chk: Dictionary = g["cur"]["check"]
	if chk["kind"] != "deliver":
		return ""
	var r := D.RES_NAMES.find(chk["res"])
	return "%d / %d" % [mini(int(g["delivered"][r] - g["base"][r]), int(chk["amount"])), int(chk["amount"])]


## What a tech step wants delivered to the Labs: its own materials plus the goods
## cost of its tier. `t` is a tech, or a step from tech_step.
static func research_mats(t: Dictionary) -> Array:
	var own: Array = t.get("mats", [0, 0, 0, 0, 0])
	var extra: Array = data().get("research_goods", {}).get(str(int(t.get("tier", 1))), [0, 0, 0, 0, 0])
	var out: Array = []
	for r in D.NRES:
		out.append(own[r] + extra[r])
	return out


## Goods a tech step wants out of the goods bank, {good name: units}: its own `goods` plus the
## per-tier `research_bank` of data/instructions.json.
static func research_bank(t: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var tier: Dictionary = data().get("research_bank", {}).get(str(int(t.get("tier", 1))), {})
	for nm: String in tier:
		out[nm] = float(tier[nm])
	var own: Dictionary = t.get("goods", {})
	for nm: String in own:
		out[nm] = out.get(nm, 0.0) + float(own[nm])
	return out


## The chapter on the board: {} once all are done.
static func chapter(game) -> Dictionary:
	var chapters: Array = data()["chapters"]
	var n: int = game.goals["chapter"]
	return chapters[n] if n < chapters.size() else {}


## 0..1: how loud the tremor from below is, by how deep the run has got.
static func tremor(game) -> float:
	return clampf(float(game.deepest - 1500) / float(D.LAYERS[4]["top"] - 1500), 0.0, 1.0)
