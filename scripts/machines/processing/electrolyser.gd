extends RefCounted
## Electrolyser (A5 part 3, recut in A9 into an interior strip): splits what the base at its `in` face holds,
## for power from a Node or the Hub in reach. Two cells of Brine become two of Lye, one of Chlor and one of
## Lift (the chlor-alkali process); a cell of Water becomes one of Lift and the oxygen, which is not a material,
## vents. The Lye goes into the base at its `out` face and the gases (Chlor, Lift) into the base joined at its
## `gas` face on top: in one base Lye and Chlor eat each other, so the products are kept apart. A scan splits
## up to `rate` cells. Brine and Water not yet split stay where they are, and nothing else is touched.
## A far base with no room for the products gets fewer split, and one that cannot pay for them waits.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const LY = preload("res://scripts/machines/layers.gd")
const BW = preload("res://scripts/machines/processing/base_work.gd")


## The base joined at the `gas` face, or {}.
static func gas_base(g, m: Dictionary, def: Dictionary) -> Dictionary:
	var p := MU.partner(g, m, def, "gas")
	return p if not p.is_empty() and LY.layer_of(MU.defs[p["def"]]) == "base" and p.get("sim") != null else {}


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
	var gas_to := gas_base(g, m, def)
	if gas_to.is_empty():
		m["state"] = "Needs a base joined on top for the gases."
		return
	var brine := M.id_of("Brine")
	var water := M.id_of("Water")
	var pairs: int = (src["contents"].get(brine, 0) if BW.may_leave(g, src, brine) else 0) >> 1
	var waters: int = src["contents"].get(water, 0) if BW.may_leave(g, src, water) else 0
	if pairs <= 0 and waters <= 0:
		m["state"] = "Nothing to split."
		return
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	var room := maxi(0, MU.capacity(dst, MU.defs[dst["def"]]) - MU.stored(dst))
	var gas_room := maxi(0, MU.capacity(gas_to, MU.defs[gas_to["def"]]) - MU.stored(gas_to))
	var budget := MU.rate(g, int(p["rate"]))
	pairs = mini(pairs, budget >> 1)
	pairs = mini(pairs, mini(room >> 1, gas_room >> 1))      # a pair leaves two cells in each
	waters = mini(waters, budget - 2 * pairs)
	waters = mini(waters, gas_room - 2 * pairs)
	# Pay for the cells; a short store splits fewer.
	while pairs + waters > 0 and not MU.take_power(g, float(p["power"]) * float(2 * pairs + waters)):
		pairs >>= 1
		waters >>= 1
	if pairs + waters <= 0:
		m["state"] = "Waiting for power."
		return
	if pairs > 0:
		var took := MU.take(src, brine, 2 * pairs)
		pairs = took >> 1
		MU.add(dst, MU.defs[dst["def"]], M.id_of("Lye"), 2 * pairs)
		MU.add(gas_to, MU.defs[gas_to["def"]], M.id_of("Chlor"), pairs)
		MU.add(gas_to, MU.defs[gas_to["def"]], M.id_of("Lift"), pairs)
	if waters > 0:
		waters = MU.take(src, water, waters)
		MU.add(gas_to, MU.defs[gas_to["def"]], M.id_of("Lift"), waters)
	m["split"] = m.get("split", 0) + 2 * pairs + waters
	m["state"] = "Splitting."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %d cells split so far." % [m.get("state", ""), m.get("split", 0)]


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
