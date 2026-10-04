extends RefCounted
## Chute (A4): a bolted pixel pipe. Powder passed into one end comes out of the other (the `pass`
## rule in its definition moves it on), so a line of Chutes, joined end to end, carries what a
## Cutter, Laser or Macerator gives up across a gap to a Tank or a Funnel. It holds a little, a
## scan's worth, so a blocked line backs up to where it started. Straight lines only: a Chute's
## two faces are opposite ends.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")


static func scan(_g, m: Dictionary, def: Dictionary) -> void:
	m["cap"] = int(def["params"]["cap"])


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	var held := MU.stored(m)
	if held == 0:
		return "Empty."
	var best := -1
	var n := 0
	for k: int in m["contents"]:
		if m["contents"][k] > n:
			n = m["contents"][k]
			best = k
	return "%d of %d cells, mostly %s." % [held, MU.capacity(m, def), M.names[best]]


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
