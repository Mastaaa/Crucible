extends RefCounted
## Spout (A9): an exterior part plugged into a base's socket. It takes the base's contents through the wall
## and pours them out of its mouth, a few cells a scan, for a little power a cell. Joined at its mouth to
## another module's pixel face (a Chute, a Tank) it passes them in there instead. The slow, small counterpart
## of a Tank's top face: the base empties where the Spout points, not where the Tank docks. A Node or the Hub
## has to be in reach.

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
	if MU.stored(base) <= 0:
		m["state"] = "Its base is empty."
		return
	var out := MU.partner(g, m, def, "mouth")
	var fo := CUT.front_of(g, m, def)
	var left := MU.rate(g, int(p["rate"]))
	var did := 0
	var blocked := false
	for mat: int in base["contents"].keys():
		if left <= 0 or blocked:
			break
		var want := mini(left, int(base["contents"].get(mat, 0)))
		want = EX.pay(g, float(p["power"]), want)
		if want <= 0:
			m["state"] = "Waiting for power."
			return
		var got := MU.take(base, mat, want)
		var moved := got
		if not out.is_empty():
			moved = MU.add(out, MU.defs[out["def"]], mat, got)
		else:
			moved = _pour(g, fo, mat, got)
		if moved < got:
			MU.add(base, bdef, mat, got - moved)             # what did not leave goes back where it came from
			blocked = true
		left -= moved
		did += moved
	m["poured"] = m.get("poured", 0) + did
	if did > 0:
		m["state"] = "Pouring."
	else:
		m["state"] = "Blocked: ground under the mouth." if out.is_empty() else "Blocked: nothing joined at the mouth takes it."


## `n` cells of `mat` leave the mouth as loose pixels, spread across it, none into rock or a pile that has
## reached it. Returns how many left.
static func _pour(g, fo: Dictionary, mat: int, n: int) -> int:
	var nrm := Vector2(fo["n"])
	var side := Vector2(nrm.y, nrm.x).abs()
	var out := 0
	for _i in n:
		var off: float = (g.rng.randf() - 0.5) * 6.0
		var at: Vector2 = (fo["p"] as Vector2) + nrm * 1.5 + side * off
		var cell: int = g.sim.get_cell(int(floor(at.x)), int(floor(at.y)))
		if not M.buildable_in(cell):
			continue
		var v: Vector2 = nrm * 0.5 + side * (g.rng.randf() - 0.5) * 0.4         # cells a tick
		g.sim.add_particle(at.x, at.y, v.x, v.y, mat)
		out += 1
	return out


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(g, m: Dictionary, _def: Dictionary) -> String:
	var base := EX.base_of(g, m)
	var what := ""
	if not base.is_empty():
		var best := EX.most(base)
		if best >= 0:
			what = " Its base holds mostly %s." % M.names[best]
	return "%s%s %d cells poured so far." % [m.get("state", ""), what, m.get("poured", 0)]


## The mouth, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	EX.outline(ov, g, EX.front_rect(g, m, def, 6, 3), Color(0.95, 0.7, 0.4, 0.5), z)
