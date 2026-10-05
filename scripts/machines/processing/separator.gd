extends RefCounted
## Sieve and Centrifuge (A5): vessels that sort what a Tank passes into them. All the sorting is in the
## definition: `pass` is a list of rules, one per out face, each with a filter (`kinds` for the Sieve,
## `heavy` and `light` for the Centrifuge; see MU.passes). This script only sets the capacity and reports.

const MU = preload("res://scripts/machines/mu.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	m["cap"] = int(def["params"]["cap"])
	m["net"] = MU.networked(g, m, def)


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	var need := "" if m.get("net", true) or not _powered(def) else " No power: no Node or Hub in reach."
	return "%d of %d cells held, %d passed on.%s" % [MU.stored(m), MU.capacity(m, def), m.get("passed", 0), need]


static func _powered(def: Dictionary) -> bool:
	for rule: Dictionary in def.get("pass", []):
		if rule.get("power", 0.0) > 0.0:
			return true
	return false


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
