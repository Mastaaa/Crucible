extends RefCounted
## Blender (A9 processing recut): plugged into a base's socket, it stirs the contents of the base until the
## different materials in it lie mixed through the whole hollow, mainly so alloys form (materials react where
## they touch, so a mix reacts where layers would not). A stir starts when the base holds two or more kinds of
## loose material and the set of kinds has changed since the last one; it lasts `time` seconds, swaps `swaps`
## pairs of cells a scan and pays `power` a second. While it stirs it publishes `m["stirring"]`, which a Heater on
## the same base waits on. Solids (rock, bars) and the casing are never moved.
## Params: `time`, `swaps`, `power`, `rest` (seconds between stirs).

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const BW = preload("res://scripts/machines/processing/base_work.gd")


## The loose kinds a base holds, as a sorted key ("" when under two).
static func kinds_key(base: Dictionary) -> String:
	var ks: Array = []
	for mat: int in base["contents"]:
		if M.kind_of(mat) != M.K_STATIC:
			ks.append(mat)
	if ks.size() < 2:
		return ""
	ks.sort()
	return str(ks)


## Swaps `n` random pairs of different loose cells in the base's box. A swap moves the materials and leaves each
## place's temperature where it was.
static func stir(g, base: Dictionary, n: int) -> int:
	var sim: RefCounted = base["sim"]
	var b: Rect2i = base["box"]
	var w: int = sim.get_width()
	var cells: PackedByteArray = sim.get_cells()
	var spots: PackedInt32Array = PackedInt32Array()
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			var c := cells[y * w + x]
			if c != 0 and M.kind_of(c) != M.K_STATIC:
				spots.append(y * w + x)
	if spots.size() < 2:
		return 0
	var done := 0
	for _i in n * 3:
		var i := spots[g.rng.randi() % spots.size()]
		var j := spots[g.rng.randi() % spots.size()]
		if cells[i] == cells[j]:
			continue
		var a := cells[i]
		cells[i] = cells[j]
		cells[j] = a
		sim.set_cell(i % w, floori(float(i) / float(w)), cells[i])
		sim.set_cell(j % w, floori(float(j) / float(w)), cells[j])
		done += 1
		if done >= n:
			break
	return done


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	m["stirring"] = false
	m.erase("offers")
	var base := BW.plug_base(g, m)
	if base.is_empty() or base.get("sim") == null:
		m["state"] = "Its base has no hollow to work on."
		return
	var key := kinds_key(base)
	var left: float = m.get("stir_left", 0.0)
	if left <= 0.0:
		m["rested"] = float(m.get("rested", p["rest"])) + MU.SCAN_DT
		if key == "" or key == m.get("stirred", "") or float(m["rested"]) < float(p["rest"]):
			m["state"] = "Mixed." if key != "" else "Nothing to mix."
			return
		left = float(p["time"])
		m["stirred"] = key
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		m["stir_left"] = left
		return
	if not MU.take_power(g, float(p["power"]) * MU.SCAN_DT):
		m["state"] = "Waiting for power."
		m["stir_left"] = left
		return
	stir(g, base, MU.rate(g, int(p["swaps"])))
	left -= MU.SCAN_DT
	m["stir_left"] = left
	m["stirring"] = left > 0.0
	m["offers"] = ["stir"]
	if left <= 0.0:
		m["rested"] = 0.0
		m["state"] = "Mixed."
	else:
		m["state"] = "Stirring."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return str(m.get("state", ""))


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
