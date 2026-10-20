extends RefCounted
## Pipe Hookup (A9): an exterior part that plugs into a base's side socket and gives a Pipe something to end
## at. The Pipe takes from and puts into the base behind it (lines.gd). The hookup itself does no work; it says
## what its Pipe is doing.

const MU = preload("res://scripts/machines/mu.gd")
const LN = preload("res://scripts/machines/lines.gd")
const EX = preload("res://scripts/machines/exterior/ext.gd")


static func scan(g, m: Dictionary, _def: Dictionary) -> void:
	var line := LN.taken(g, m["id"], "pipe")
	if line == 0:
		m["state"] = "No Pipe: lay one with the Pipe tool."
	else:
		m["state"] = g.modules[line].get("state", "")


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(g, m: Dictionary, _def: Dictionary) -> String:
	var base := EX.base_of(g, m)
	var on := "" if base.is_empty() else " On a %s." % MU.defs[base["def"]]["name"]
	return "%s%s" % [m.get("state", ""), on]


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
