extends RefCounted
## Heat Dispersal Unit (A9 processing recut): an interior strip between two bases that carries heat from the
## hotter one to the cooler, until both hold their load at the same average temperature. The cells it works
## on are the ones holding something (the runs thermal.gd finds), so an empty base takes none. The energy it
## moves is in cell degrees: what one side gives is what the other gets, however many cells each holds.
## Params: `rate` (degrees a cell a scan at most), `power` (a second while it moves heat), `gap` (the
## difference in degrees it leaves alone).

const MU = preload("res://scripts/machines/mu.gd")
const BW = preload("res://scripts/machines/processing/base_work.gd")
const TH = preload("res://scripts/machines/processing/thermal.gd")


## The average temperature of a base's occupied cells and how many there are: Vector2i(average, count).
static func average(base: Dictionary) -> Vector2i:
	var sim: RefCounted = base["sim"]
	var sum := 0
	var n := 0
	for r: Vector3i in TH.runs(base):
		sum += (sim.rect_temp(r.x, r.y, r.z, 1) as Vector3i).z * r.z
		n += r.z
	return Vector2i(int(float(sum) / float(maxi(1, n))), n)


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	var ends := BW.ends(g, m, def)
	var why := BW.missing(ends)
	if why != "":
		m["state"] = why
		return
	var a: Vector2i = average(ends[0])
	var b: Vector2i = average(ends[1])
	m["heat"] = Vector2i(a.x, b.x)
	if a.y == 0 or b.y == 0:
		m["state"] = "One side holds nothing."
		return
	var diff := absi(a.x - b.x)
	if diff <= int(p["gap"]):
		m["state"] = "Both sides at about %d degrees." % ((a.x + b.x) >> 1)
		return
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	if not MU.take_power(g, float(p["power"]) * MU.SCAN_DT):
		m["state"] = "Waiting for power."
		return
	var hot: Dictionary = ends[0] if a.x > b.x else ends[1]
	var cold: Dictionary = ends[1] if a.x > b.x else ends[0]
	var nh: int = a.y if a.x > b.x else b.y
	var nc: int = b.y if a.x > b.x else a.y
	# Full equalisation moves diff * nh * nc / (nh + nc) cell degrees; a scan moves at most `rate` a cell of the smaller side.
	var energy := minf(float(diff) * float(nh) * float(nc) / float(nh + nc), float(MU.rate(g, int(p["rate"]))) * float(mini(nh, nc)))
	var dh := maxi(1, roundi(energy / float(nh)))
	var dc := maxi(1, roundi(energy / float(nc)))
	for r: Vector3i in TH.runs(hot):
		hot["sim"].heat_rect(r.x, r.y, r.z, 1, -dh)
	for r: Vector3i in TH.runs(cold):
		cold["sim"].heat_rect(r.x, r.y, r.z, 1, dc)
	m["state"] = "Moving heat: %d and %d degrees." % [maxi(a.x, b.x), mini(a.x, b.x)]


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return str(m.get("state", ""))


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
