extends RefCounted
## Funnel (A3 starter kit): bolted in place; whatever a docked Tank passes into it goes on
## into the Hub's stockpile, a cell of material paying what a cell dug by hand would (a good
## banks under its own id, A5).

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const LN = preload("res://scripts/machines/lines.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var left := mini(MU.rate(g, int(def["params"]["bank"])), LN.bank_room(g, m, def))     # out of reach, a Network line takes it
	for mat: int in m["contents"].keys():
		var n := mini(left, m["contents"][mat])
		if M.is_good(mat):
			n = mini(n, g.good_room_cells(mat))      # a full bank holds a good back
		if n <= 0:
			continue
		n = MU.take(m, mat, n)
		left -= n
		LN.bank(g, m, def, mat, n)
		m["banked"] = m.get("banked", 0) + n
		if left <= 0:
			break


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%d units banked so far" % m.get("banked", 0)


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
