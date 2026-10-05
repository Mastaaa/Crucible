extends RefCounted
## Combustor (A5): burns fuel for power. Fuel (Coal, Coal chunks, Slick; `fuel` in the material
## data) joined into its bottom face collects in its hollow, and while a Node or the Hub is in
## reach it burns a cell every `burn` seconds and adds that cell's power to the Hub's stockpile
## (up to its cap). It burns the richest fuel it holds first and burns nothing while the
## stockpile is full. The first answer to what to do with oil.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")


## The fuel it holds that pays the most per cell, or -1.
static func richest(m: Dictionary) -> int:
	var pick := -1
	var best := 0.0
	for mat: int in m["contents"]:
		var f := M.fuel_of(mat)
		if f > best:
			best = f
			pick = mat
	return pick


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	m["flow"] = 0.0
	var mat := richest(m)
	if mat < 0:
		m["state"] = "No fuel."
		return
	if not m["net"]:
		m["state"] = "No Node or Hub within reach."
		return
	var power := M.fuel_of(mat)
	if g.stock[D.R_POWER] + power > g.power_cap():
		m["state"] = "Power store full."
		return
	m["work"] = minf(m.get("work", 0.0) + MU.SCAN_DT, float(p["burn"]))
	if m["work"] < float(p["burn"]):
		m["state"] = "Burning %s." % M.names[mat]
		m["flow"] = power / float(p["burn"])
		return
	m["work"] = 0.0
	if MU.take(m, mat, 1) > 0:
		g.stock[D.R_POWER] += power
		m["burned"] = m.get("burned", 0) + 1
	m["state"] = "Burning %s." % M.names[mat]
	m["flow"] = power / float(p["burn"])


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	return "%s %d of %d cells held, %.1f power/s, %d cells burned." % [m.get("state", ""), MU.stored(m), MU.capacity(m, def),
			m.get("flow", 0.0), m.get("burned", 0)]


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
