extends RefCounted
## Funnel (A3 starter kit): bolted in place; whatever a docked Tank passes into it goes on
## into the Hub's stockpile, a cell of material paying what a cell dug by hand would (a good
## banks under its own id, A5).

const MU = preload("res://scripts/machines/mu.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var left: int = def["params"]["bank"]
	for mat: int in m["contents"].keys():
		var n := mini(left, m["contents"][mat])
		if n <= 0:
			continue
		m["contents"][mat] -= n
		if m["contents"][mat] <= 0:
			m["contents"].erase(mat)
		left -= n
		g.bank_cells(m["at"], mat, n)
		m["banked"] = m.get("banked", 0) + n
		if left <= 0:
			break


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%d units banked so far" % m.get("banked", 0)


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
