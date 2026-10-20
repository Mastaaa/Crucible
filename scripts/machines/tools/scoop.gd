extends RefCounted
## Scoop (A9 tools): a standalone tool that stands on a Pipe and lifts a measured scoop of one powder or liquid out of the
## small spot in front of it into the Pipe. It picks the most plentiful material there and keeps to it until the spot has
## none left, so a sample of Glimmer in a pile of Sand comes out clean once the Sand is not what it chose. Where the Area Vac
## takes everything loose in a wide patch, the Scoop takes a single material from a narrow one, a row at a time.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const D = preload("res://scripts/defs.gd")
const MT = preload("res://scripts/machines/tools/mount.gd")
const EX = preload("res://scripts/machines/exterior/ext.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")


## The most plentiful powder or liquid in `counts`, or -1.
static func _best(counts: PackedInt32Array) -> int:
	var best := -1
	var n := 0
	for mat in 256:
		var k := M.kind_of(mat)
		if (k == M.K_POWDER or k == M.K_LIQUID) and counts[mat] > n:
			best = mat
			n = counts[mat]
	return best


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var line := MT.ready(g, m, def)
	if line.is_empty():
		return
	var p: Dictionary = def["params"]
	var ldef: Dictionary = MU.defs[line["def"]]
	var left := mini(MU.rate(g, int(p["scoop"])), MU.capacity(line, ldef) - MU.stored(line))
	if left <= 0:
		m["state"] = "Full: its Pipe is backed up."
		return
	var fo := CUT.front_of(g, m, def)
	var width := int(p["width"])
	var depth := int(p["depth"])
	var whole := EX.front_rect(g, m, def, width, depth)
	var counts: PackedInt32Array = g.sim.rect_counts(whole.position.x, whole.position.y, whole.size.x, whole.size.y)
	var want: int = m.get("want", -1)
	if want < 0 or counts[want] == 0:
		want = _best(counts)
	m["want"] = want
	if want < 0:
		m["state"] = "Nothing to scoop."
		return
	var mask := PackedByteArray()
	mask.resize(256)
	mask[want] = 1
	var did := 0
	for k in depth:
		var r := CUT.slice(fo["p"], fo["n"], k, width, 0)
		var there: int = g.sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)
		if there == 0 or there > left - did:
			continue
		if not MU.take_power(g, float(p["power"]) * there):
			m["state"] = "Waiting for power."
			break
		var got: PackedInt32Array = g.sim.dig_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask, 0, 0)
		did += MU.add(line, ldef, want, got[want])
	m["scooped"] = m.get("scooped", 0) + did
	if m["state"] == "":
		m["state"] = "Scooping %s." % M.names[want] if did > 0 else "Waiting on a fuller row of %s." % M.names[want]


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %d cells scooped so far." % [m.get("state", ""), m.get("scooped", 0)]


## The spot it scoops from, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var p: Dictionary = def["params"]
	EX.outline(ov, g, EX.front_rect(g, m, def, int(p["width"]), int(p["depth"])), Color(0.95, 0.8, 0.4, 0.4), z)
