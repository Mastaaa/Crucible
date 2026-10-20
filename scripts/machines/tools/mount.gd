extends RefCounted
## Standalone tools (A9 tools track, "MT"): the Area Vac, Scoop, Grabber and Floodlight. A tool stands on a line where its
## centre meets it: its `mount` side (the middle of that edge, the foot) rests against a drawn line (a Pipe, Cable or
## Network line, or a Strut: `mounts` lists the kinds a tool takes), and is bolted there by a joint the tool owns, so it goes
## with the line and the line goes with whatever carries it. `front` is the side the tool works on, opposite its mount.
## This file is the part every tool shares: finding the line, holding on to it, and asking whether the line puts the
## tool in reach of the network. layers.gd calls `line_under` and `hold` (a tool's `needs` is ["line"]).

const MU = preload("res://scripts/machines/mu.gd")
const JT = preload("res://scripts/machines/joints.gd")

const SLACK := 4.0              # cells: how far a foot may be from the face of a line and still stand on it
const NAMES := {"pipe": "a Pipe", "cable": "a Cable", "network": "a Network line", "strut": "a Strut"}


## The kind of line module a definition is ("pipe", "cable", "network", "strut"), or "".
static func line_kind(def: Dictionary) -> String:
	if def.get("layer", "") == "line":
		return str(def.get("kind", ""))
	if str(def.get("id", "")).begins_with("strut_"):
		return "strut"
	return ""


## Where tool `m`'s foot is in the world now, and the way it points out of the tool.
static func foot_of(g, m: Dictionary, def: Dictionary) -> Dictionary:
	var fr := MU.frame(g, m, def)
	var size: Vector2i = fr["lay"]["size"]
	var d: Vector2i = MU.FRONT_DIRS[def.get("mount", "up")]
	for _i in posmod(m["turns"], 4):
		d = Vector2i(-d.y, d.x)
	var local := Vector2(size) * 0.5 + Vector2(d) * Vector2(size) * 0.5
	return {"pos": MU.world(fr, local), "dir": MU.turn(fr, Vector2(d))}


## The ends of a line module's axis in the world: [a, b].
static func axis_of(g, line: Dictionary) -> Array:
	var fr := MU.frame(g, line, MU.defs[line["def"]])
	var size: Vector2i = fr["lay"]["size"]
	return [MU.world(fr, Vector2(0.0, size.y * 0.5)), MU.world(fr, Vector2(size.x, size.y * 0.5)), size.y]


## The line (module id) tool `m` stands on: the nearest one of a kind it takes whose face is within SLACK of the foot. 0 for none.
static func line_under(g, m: Dictionary, def: Dictionary) -> int:
	var mounts: Array = def.get("mounts", [])
	var foot: Vector2 = foot_of(g, m, def)["pos"]
	var best := 0
	var best_d := INF
	for id: int in g.modules:
		if id == m["id"]:
			continue
		var lm: Dictionary = g.modules[id]
		if not mounts.has(line_kind(MU.defs[lm["def"]])):
			continue
		var ax: Array = axis_of(g, lm)
		var d := foot.distance_to(Geometry2D.get_closest_point_to_segment(foot, ax[0], ax[1]))
		if d <= float(ax[2]) * 0.5 + SLACK and d < best_d:
			best = id
			best_d = d
	return best


## What a tool short of its line says.
static func missing(def: Dictionary) -> String:
	var names: Array = []
	for k: String in def.get("mounts", []):
		names.append(NAMES.get(k, k))
	return "Needs a line: set its %s side against %s." % [def.get("mount", "top"), " or ".join(names)]


## Keeps tool `m` bolted to the line it stands on (`m["on"]`, set by layers.gd's check) and takes the bolt off when it
## has none. The bolt carries the tool's id as `auto`, so it is not drawn or taken off by a click and goes with the tool.
static func hold(g, m: Dictionary, def: Dictionary) -> void:
	var lid: int = m.get("on", 0)
	if lid == 0 or not g.modules.has(lid):
		if m.get("held_by", 0) != 0:
			JT.drop_auto(g, m["id"])
			m["held_by"] = 0
		return
	for jid: int in g.joints:
		var j: Dictionary = g.joints[jid]
		if j.get("auto", 0) == m["id"] and j["kind"] == "bolt" and j["b"] == lid:
			return
	JT.drop_auto(g, m["id"])
	var at: Vector2 = foot_of(g, m, def)["pos"]
	var id := JT.attach(g, "bolt", m["id"], lid, at, at, {"max_load": JT.AUTO_LOAD, "limit": JT.AUTO_LIMIT})
	if id != 0:
		g.joints[id]["auto"] = m["id"]
		m["held_by"] = lid


## The modules a line is fixed to: its two ends (a drawn line) and whatever else is bolted to it, but not `except`.
static func neighbours(g, line: Dictionary, except: int) -> Array:
	var out: Array = []
	for e: int in line.get("ends", []):
		if e != except and g.modules.has(e):
			out.append(e)
	for jid: int in JT.of_module(g, line["id"]):
		var j: Dictionary = g.joints[jid]
		var o: int = j["b"] if j["a"] == line["id"] else j["a"]
		if o != 0 and o != except and g.modules.has(o) and not out.has(o):
			out.append(o)
	return out


## Whether tool `m` has the network in reach: a Node or the Hub in reach of the tool itself, or of a part its line is held by.
static func powered(g, m: Dictionary, def: Dictionary, line: Dictionary) -> bool:
	if MU.networked(g, m, def):
		return true
	if line.is_empty():
		return false
	for o: int in neighbours(g, line, m["id"]):
		var om: Dictionary = g.modules[o]
		if MU.networked(g, om, MU.defs[om["def"]]):
			return true
	return false


## The line module tool `m` stands on (its dictionary), or {}.
static func line_of(g, m: Dictionary) -> Dictionary:
	return g.modules.get(m.get("on", 0), {})


## The common start of a tool's scan: clears the state, and returns the line it stands on once it is in the network's
## reach, else {} with the state saying why.
static func ready(g, m: Dictionary, def: Dictionary) -> Dictionary:
	m["state"] = ""
	var line := line_of(g, m)
	if line.is_empty():
		m["state"] = missing(def)
		return {}
	if not powered(g, m, def, line):
		m["state"] = "No power: no Node or Hub in reach of it or of its line."
		return {}
	return line

