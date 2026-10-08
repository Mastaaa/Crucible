extends RefCounted
## Electrolyser (A5 part 3): splits what a Tank passes into its bottom face, for power from a Node or the
## Hub in reach. Two cells of Brine become two of Lye, one of Chlor and one of Lift (the chlor-alkali
## process); a cell of Water becomes one of Lift and the oxygen, which is not a material, vents. A scan
## splits up to `rate` cells. The definition's `pass` rules do the rest: each product leaves by its own
## face, picked by `mats`, and Brine and Water stay in until they are split. A vessel that has no room for
## the products splits fewer cells (two Brine make four cells), and one that cannot pay for them waits.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	var brine := M.id_of("Brine")
	var water := M.id_of("Water")
	var pairs: int = m["contents"].get(brine, 0) >> 1
	var waters: int = m["contents"].get(water, 0)
	if pairs <= 0 and waters <= 0:
		m["state"] = "Nothing to split."
		return
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	var budget := MU.rate(g, int(p["rate"]))
	pairs = mini(pairs, budget >> 1)
	pairs = mini(pairs, maxi(0, MU.capacity(m, def) - MU.stored(m)) >> 1)      # a pair leaves two cells more than it took
	waters = mini(waters, budget - 2 * pairs)
	# Pay for the cells; a short store splits fewer.
	while pairs + waters > 0 and not MU.take_power(g, float(p["power"]) * float(2 * pairs + waters)):
		pairs >>= 1
		waters >>= 1
	if pairs + waters <= 0:
		m["state"] = "Waiting for power."
		return
	if pairs > 0:
		var took := MU.take(m, brine, 2 * pairs)
		pairs = took >> 1
		MU.add(m, def, M.id_of("Lye"), 2 * pairs)
		MU.add(m, def, M.id_of("Chlor"), pairs)
		MU.add(m, def, M.id_of("Lift"), pairs)
	if waters > 0:
		waters = MU.take(m, water, waters)
		MU.add(m, def, M.id_of("Lift"), waters)
	m["split"] = m.get("split", 0) + 2 * pairs + waters
	m["state"] = "Splitting."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	return "%s %d of %d cells held, %d cells split, %d passed on." % [m.get("state", ""), MU.stored(m), MU.capacity(m, def),
			m.get("split", 0), m.get("passed", 0)]


## Nothing of its own: the interior draws itself.
static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
