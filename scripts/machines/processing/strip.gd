extends RefCounted
## Sieve (A9 processing recut): an interior strip between two bases. It draws from the base joined at its
## `in` face and lets through to the base at its `out` face whatever its `rule` passes (a Sieve: liquids and
## gases); what the rule refuses stays where it was. Power is a little a cell, from a Node or the Hub in reach.
## The definition's `params`: `rule` (a MU.passes rule), `rate` (cells a scan), `power` (a cell).

const MU = preload("res://scripts/machines/mu.gd")
const BW = preload("res://scripts/machines/processing/base_work.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	var ends := BW.ends(g, m, def)
	var why := BW.missing(ends)
	if why != "":
		m["state"] = why
		return
	var src: Dictionary = ends[0]
	var dst: Dictionary = ends[1]
	var power := float(p.get("power", 0.0))
	if power > 0.0 and not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	var moved := BW.carry(g, src, dst, p["rule"], MU.rate(g, int(p["rate"])), power)
	m["passed"] = m.get("passed", 0) + moved
	m["state"] = "Passing %d cells." % moved if moved > 0 else "Nothing to pass."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %d cells passed so far." % [m.get("state", ""), m.get("passed", 0)]


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
