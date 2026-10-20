extends RefCounted
## Anchor Hookup (A9): an exterior part that plugs into a base's side socket and gives a joint or a line a place
## to be held: a Rope or a Strut whose end is clicked near its anchor point is held there, to the base. It does
## no work; it says how many joints hold on it and how hard they are pulled.

const MU = preload("res://scripts/machines/mu.gd")
const JT = preload("res://scripts/machines/joints.gd")


static func scan(g, m: Dictionary, _def: Dictionary) -> void:
	var held := 0
	var worst := 0.0
	for jid: int in JT.of_module(g, m["id"]):
		if g.joints[jid].get("auto", 0) != 0:
			continue
		held += 1
		worst = maxf(worst, float(JT.state(g, jid).get("strain", 0.0)))
	m["held"] = held
	m["strain"] = worst
	m["state"] = "Nothing held here." if held == 0 else "%d held, strain %.1f." % [held, worst]


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return m.get("state", "")


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
