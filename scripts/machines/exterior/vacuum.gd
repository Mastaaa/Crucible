extends RefCounted
## Vacuum (A9): an exterior part plugged into a base's socket. It pulls the loose pixels (powder, liquid,
## gas) of a wide patch in front of its mouth into its base, nearest row first, for a little power a cell.
## The quick way to gather whatever lies about; the Drone Cage is the slow, precise one for a single
## material. A Node or the Hub has to be in reach.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const EX = preload("res://scripts/machines/exterior/ext.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["state"] = ""
	if not MU.networked(g, m, def):
		m["state"] = "No power: no Node or Hub in reach."
		return
	var base := EX.base_of(g, m)
	if base.is_empty():
		return
	var bdef: Dictionary = MU.defs[base["def"]]
	var room := MU.capacity(base, bdef) - MU.stored(base)
	var budget := mini(MU.rate(g, int(p["rate"])), room)
	if budget <= 0:
		m["state"] = "Full: nowhere to put what it pulls in."
		return
	var fo := CUT.front_of(g, m, def)
	var mask := M.mask("loose")
	var did := 0
	for k in int(p["depth"]):
		var r := CUT.slice(fo["p"], fo["n"], k, int(p["width"]), 0)
		var there: int = g.sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)
		if there == 0 or there > budget - did:
			continue
		if not MU.take_power(g, float(p["power"]) * there):
			m["state"] = "Waiting for power."
			break
		var got: PackedInt32Array = g.sim.dig_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask, 0, 0)
		for mat in 256:
			if got[mat] > 0:
				did += MU.add(base, bdef, mat, got[mat])
	m["pulled"] = m.get("pulled", 0) + did
	if m["state"] == "":
		m["state"] = "Pulling in." if did > 0 else "Nothing loose in reach."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %d cells pulled in so far." % [m.get("state", ""), m.get("pulled", 0)]


## The patch it pulls from, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var p: Dictionary = def["params"]
	EX.outline(ov, g, EX.front_rect(g, m, def, int(p["width"]), int(p["depth"])), Color(0.4, 0.7, 0.95, 0.35), z)
