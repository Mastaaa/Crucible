extends RefCounted
## Sieve and Centrifuge (A9 processing recut): an interior strip between bases. It draws from the base joined at
## its `in` face and passes what a rule allows into the base at another face; what the rule refuses stays where it
## was. Power is a little a cell, from a Node or the Hub in reach.
## The definition's `params`: `rule` (a MU.passes rule) into the `out` face, or `routes`, a list of {to (a face name),
## rule} for a strip with more than one way out (the Centrifuge: `light` on top, the heaviest out of `out`), then
## `rate` (cells a scan, each way) and `power` (a cell). The sorting rules `light` and `heavy` look at the whole
## load of the `in` base, so the lightest goes first and the last material left goes the heavy way.

const MU = preload("res://scripts/machines/mu.gd")
const BW = preload("res://scripts/machines/processing/base_work.gd")


## The ways out: [{to, rule}].
static func routes(p: Dictionary) -> Array:
	return p["routes"] if p.has("routes") else [{"to": "out", "rule": p["rule"]}]


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
	var power := float(p.get("power", 0.0))
	if power > 0.0 and not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	var moved := 0
	for r: Dictionary in routes(p):
		var dst: Dictionary = ends[1] if r["to"] == "out" else BW.base_at(g, m, def, r["to"])
		if dst.is_empty():
			continue
		moved += BW.carry(g, src, dst, r["rule"], MU.rate(g, int(p["rate"])), power)
	m["passed"] = m.get("passed", 0) + moved
	m["state"] = "Passing %d cells." % moved if moved > 0 else "Nothing to pass."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %d cells passed so far." % [m.get("state", ""), m.get("passed", 0)]


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
