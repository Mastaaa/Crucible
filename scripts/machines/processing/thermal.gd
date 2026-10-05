extends RefCounted
## Thermal vessel (A5): the Boiler, the Chiller and the Furnace are this one script with a
## different target temperature. It is a hollow module with an interior (interior.gd), and while
## the cells in it sit short of the target it pushes heat into them (or pulls it out), a few
## degrees a scan, for power from a Node or the Hub in reach. What the heat does is the sim's own
## business: Water boils to Steam at 100, freezes at 0, Sand fuses to Glass at 900, Ferrite and
## Flux smelt to Slag and bars between 850 and 1000. Its `pass` rule picks what leaves (steam,
## ice, the molten and the finished) and keeps the rest in to cook.
##
## The heater works on the cells that hold something, run by run along each row of the interior,
## and goes by their average: heating warms the cells in the box and not the empty space above
## them, so a Furnace holds its load at the target rather than a few cells of air.
## An empty vessel does nothing and costs nothing.

const MU = preload("res://scripts/machines/mu.gd")


## The runs of occupied cells in the interior's box, row by row: Vector3i(x, y, length) in the
## interior's own grid.
static func runs(m: Dictionary) -> Array:
	var sim: RefCounted = m["sim"]
	var b: Rect2i = m["box"]
	var w: int = sim.get_width()
	var cells: PackedByteArray = sim.get_cells()
	var out: Array = []
	for y in range(b.position.y, b.end.y):
		var x := b.position.x
		while x < b.end.x:
			if cells[y * w + x] == 0:
				x += 1
				continue
			var x0 := x
			while x < b.end.x and cells[y * w + x] != 0:
				x += 1
			out.append(Vector3i(x0, y, x - x0))
	return out


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	var sim: Variant = m.get("sim")
	if sim == null:
		return
	if m["contents"].is_empty():
		m["state"] = "Empty."
		m["heat"] = 20
		return
	var rs := runs(m)
	var sum := 0
	var n := 0
	for r: Vector3i in rs:
		sum += (sim.rect_temp(r.x, r.y, r.z, 1) as Vector3i).z * r.z
		n += r.z
	var avg := int(float(sum) / float(maxi(1, n)))
	var target := int(p["target"])
	var warming := target > 20
	m["heat"] = avg
	if (avg >= target) if warming else (avg <= target):
		m["state"] = "At %d degrees." % target
		return
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	if not MU.take_power(g, float(p["power"]) * MU.SCAN_DT):
		m["state"] = "Waiting for power."
		return
	var d := MU.rate(g, int(p["rate"])) * (1 if warming else -1)
	for r: Vector3i in rs:
		sim.heat_rect(r.x, r.y, r.z, 1, d)
	m["state"] = "%s toward %d degrees." % ["Heating" if warming else "Cooling", target]


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	return "%s %d of %d cells held, %d degrees (set to %d)." % [m.get("state", ""), MU.stored(m),
			MU.capacity(m, def), m.get("heat", 20), int(def["params"]["target"])]


## Nothing of its own: the interior draws itself.
static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
