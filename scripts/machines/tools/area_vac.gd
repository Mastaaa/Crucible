extends RefCounted
## Area Vac (A9 tools): a standalone tool that stands on a Pipe and draws the loose pixels (powder, liquid, gas) of a wide
## patch in front of it into the Pipe, nearest row first, for a little power a cell. The Pipe carries them to the base at
## its far end. The Vacuum does the same into the base it is plugged to; this one reaches wherever a Pipe can. It needs the
## network in reach of itself or of its Pipe, and stops while the Pipe is full.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const MT = preload("res://scripts/machines/tools/mount.gd")
const EX = preload("res://scripts/machines/exterior/ext.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var line := MT.ready(g, m, def)
	if line.is_empty():
		return
	var p: Dictionary = def["params"]
	var ldef: Dictionary = MU.defs[line["def"]]
	var budget := mini(MU.rate(g, int(p["rate"])), MU.capacity(line, ldef) - MU.stored(line))
	if budget <= 0:
		m["state"] = "Full: its Pipe is backed up."
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
				did += MU.add(line, ldef, mat, got[mat])
	m["pulled"] = m.get("pulled", 0) + did
	if m["state"] == "":
		m["state"] = "Drawing in." if did > 0 else "Nothing loose in reach."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %d cells drawn in so far." % [m.get("state", ""), m.get("pulled", 0)]


## The patch it draws from, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var p: Dictionary = def["params"]
	EX.outline(ov, g, EX.front_rect(g, m, def, int(p["width"]), int(p["depth"])), Color(0.4, 0.7, 0.95, 0.35), z)
