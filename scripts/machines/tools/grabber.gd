extends RefCounted
## Grabber (A9 tools): a standalone tool that stands on a line and takes hold of a loose rigid body (a fallen slab, a Press's
## block, rubble that has not settled) that comes between its jaws: a bolt between the Grabber and the body. It holds until
## a click lets go, and carries the body wherever its line is carried (a Strut on a Motor, a rig on a Winch), so a rig can
## pick a slab up and set it down. A click steps its mode: grab (takes the next body that comes in reach), hold (has one),
## off (lets go and ignores bodies until clicked). A grab costs a little power; holding costs none.

const MU = preload("res://scripts/machines/mu.gd")
const JT = preload("res://scripts/machines/joints.gd")
const MT = preload("res://scripts/machines/tools/mount.gd")
const EX = preload("res://scripts/machines/exterior/ext.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")


## The engine body ids of every module (a tool does not grab machinery).
static func _module_bodies(g) -> Dictionary:
	var out := {}
	for id: int in g.modules:
		out[g.modules[id]["body"]] = true
	return out


## The loose body in the jaws nearest the front point: {body, cells, at} (at: a cell of it, the nearest to the front point), or {}.
static func _find(g, def: Dictionary, zone: Rect2i, front: Vector2) -> Dictionary:
	var mine := _module_bodies(g)
	var bl: PackedInt32Array = g.sim.get_bodies()
	var cap: int = int(def["params"]["max_cells"])
	var best := {}
	var best_d := INF
	for k in range(0, bl.size(), 7):
		var id := bl[k]
		if mine.has(id) or bl[k + 6] > cap or bl[k + 6] <= 0:
			continue
		var box := Rect2i(bl[k + 1], bl[k + 2], bl[k + 3] - bl[k + 1] + 1, bl[k + 4] - bl[k + 2] + 1)
		if not box.intersects(zone):
			continue
		var hit := box.intersection(zone)
		var at := Vector2(-1.0, -1.0)
		var at_d := INF
		for y in range(hit.position.y, hit.end.y):
			for x in range(hit.position.x, hit.end.x):
				if g.sim.get_owner(x, y) != id:
					continue
				var d := Vector2(x + 0.5, y + 0.5).distance_to(front)
				if d < at_d:
					at_d = d
					at = Vector2(x + 0.5, y + 0.5)
		if at.x >= 0.0 and at_d < best_d:
			best_d = at_d
			best = {"body": id, "cells": bl[k + 6], "at": at}
	return best


## Lets go: the bolt comes off and the body is loose again.
static func release(g, m: Dictionary) -> void:
	var grip: Dictionary = m.get("grip", {})
	if not grip.is_empty():
		g.sim.remove_joint(int(grip["eng"]))
		m.erase("grip")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	m["state"] = ""
	var mode: String = m.get("mode", "grab")
	var grip: Dictionary = m.get("grip", {})
	if not grip.is_empty():
		var live := false
		for e: int in g.sim.joint_ids():
			live = live or e == int(grip["eng"])
		if not live:
			m.erase("grip")
			grip = {}
			m["state"] = "Lost its grip."
			mode = "grab" if mode == "hold" else mode
	if mode == "hold" and grip.is_empty():
		mode = "grab"
	m["mode"] = mode
	if mode == "hold":
		m["state"] = "Holding a body."
		return
	if mode == "off":
		m["state"] = "Open: click to grab again."
		return
	var line := MT.line_of(g, m)
	if line.is_empty():
		m["state"] = MT.missing(def)
		return
	if not MT.powered(g, m, def, line):
		m["state"] = "No power: no Node or Hub in reach of it or of its line."
		return
	var p: Dictionary = def["params"]
	var zone := EX.front_rect(g, m, def, int(p["width"]), int(p["depth"]))
	var fo := CUT.front_of(g, m, def)
	var found := _find(g, def, zone, fo["p"])
	if found.is_empty():
		if m["state"] == "":
			m["state"] = "Waiting for a body."
		return
	if not MU.take_power(g, float(p["power"])):
		m["state"] = "Waiting for power."
		return
	var at: Vector2 = found["at"]
	var k: Dictionary = JT.KINDS["bolt"]
	var eng: int = g.sim.add_joint({"type": k["type"], "a": m["body"], "b": found["body"], "ax": at.x, "ay": at.y, "bx": at.x, "by": at.y,
			"max_load": float(p["load"]), "limit": JT.AUTO_LIMIT, "rooted": false})
	if eng <= 0:
		m["state"] = "Could not close on it."
		return
	m["grip"] = {"eng": eng, "body": found["body"], "cells": found["cells"]}
	m["mode"] = "hold"
	m["grabbed"] = m.get("grabbed", 0) + 1
	m["state"] = "Holding a body of %d cells." % found["cells"]


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


## A click steps grab, hold and off: a held body is let go, an open Grabber closes on the next body, an idle one opens.
static func use(g, m: Dictionary, _def: Dictionary) -> void:
	var mode: String = m.get("mode", "grab")
	if mode == "hold":
		release(g, m)
		m["mode"] = "off"
	elif mode == "off":
		m["mode"] = "grab"
	else:
		m["mode"] = "off"
	g.show_banner("Grabber: %s." % {"grab": "will take the next body", "off": "open and idle", "hold": "holding"}[m["mode"]], 1.5)


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %d taken so far. Click to let go or grab." % [m.get("state", ""), m.get("grabbed", 0)]


## The jaws, outlined: green while holding.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var p: Dictionary = def["params"]
	var col := Color(0.5, 0.95, 0.5, 0.6) if m.get("mode", "grab") == "hold" else Color(0.95, 0.75, 0.4, 0.4)
	EX.outline(ov, g, EX.front_rect(g, m, def, int(p["width"]), int(p["depth"])), col, z)
