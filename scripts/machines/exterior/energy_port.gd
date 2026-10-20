extends RefCounted
## Energy Port (A9): an exterior part that plugs into a base's side socket and is where a Cable ends. An assembly
## with a Node or the Hub in reach and an Energy Port, joined by a live Cable to the Energy Port of another
## assembly, puts that one in the network's reach as well (machines/lines.gd, `MU.networked`).

const MU = preload("res://scripts/machines/mu.gd")
const LN = preload("res://scripts/machines/lines.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var line := LN.taken(g, m["id"], "cable")
	if line == 0:
		m["state"] = "No Cable: lay one with the Cable tool."
	elif MU.direct(g, m, def):
		m["state"] = "In reach of the network itself. %s" % g.modules[line].get("state", "")
	elif g.net_reach.has(m["id"]):
		m["state"] = "Fed through its Cable."
	else:
		m["state"] = "Out of reach. %s" % g.modules[line].get("state", "")


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return m.get("state", "")


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
