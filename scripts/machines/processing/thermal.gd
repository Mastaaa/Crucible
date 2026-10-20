extends RefCounted
## Heater and Chiller (A9 processing recut; they were the Boiler, Furnace and Chiller chambers of A5).
## A machine plugged into a base's socket: while the cells in the base sit short of the target it pushes
## heat into them (or pulls it out), a few degrees a scan, for power from a Node or the Hub in reach. What
## the heat does is the sim's own business: Water boils to Steam at 100, freezes at 0, Sand fuses to Glass at
## 900, Ferrite and Flux smelt to Slag and bars between 850 and 1000.
##
## A definition lists `modes` ({name, target, lets, tech}); a Heater has Boil and, once Smelting is researched,
## Smelt, and a click cycles them (the Chiller has one). A mode's `lets` is what may leave the base while the
## part is on it (see base_work.gd): steam and what the boiling leaves, or the molten and the finished.
## Everything else stays in the base to cook.
##
## It works on the cells that hold something, run by run along each row of the base's box, and goes by their
## average: heating warms the cells in the box and not the empty space above them, so a base holds its load at
## the target rather than a few cells of air. An empty base costs nothing. A Blender stirring the same base
## makes it wait (`m["waits"]`) until the stirring is done.

const MU = preload("res://scripts/machines/mu.gd")
const BW = preload("res://scripts/machines/processing/base_work.gd")
const LY = preload("res://scripts/machines/layers.gd")


## The runs of occupied cells in a base's box, row by row: Vector3i(x, y, length) in the base's own grid.
static func runs(base: Dictionary) -> Array:
	var sim: RefCounted = base["sim"]
	var b: Rect2i = base["box"]
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


## The modes the player can use now (a mode with a `tech` needs it researched).
static func modes(g, def: Dictionary) -> Array:
	var out: Array = []
	for md: Dictionary in def["params"]["modes"]:
		if not md.has("tech") or g.researched.has(md["tech"]):
			out.append(md)
	return out


static func mode_of(g, m: Dictionary, def: Dictionary) -> Dictionary:
	var ms := modes(g, def)
	return ms[posmod(int(m.get("mode", 0)), ms.size())] if not ms.is_empty() else def["params"]["modes"][0]


## A click steps to the next mode the player has.
static func use(g, m: Dictionary, def: Dictionary) -> void:
	var ms := modes(g, def)
	if ms.size() < 2:
		return
	m["mode"] = (int(m.get("mode", 0)) + 1) % ms.size()
	m["state"] = "Set to %s." % ms[m["mode"]]["name"]


## The Blender on the same base that is stirring now, or {}.
static func stirring(g, m: Dictionary, base: Dictionary) -> Dictionary:
	for id: int in LY.peers(g, m):
		var o: Dictionary = g.modules[id]
		if o.get("stirring", false) and BW.plug_base(g, o).get("id", -1) == base["id"]:
			return o
	return {}


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	m.erase("waits")
	var mode := mode_of(g, m, def)
	m["mode_name"] = mode["name"]
	var base := BW.plug_base(g, m)
	if base.is_empty() or base.get("sim") == null:
		m["state"] = "Its base has no hollow to work on."
		return
	m["lets"] = mode["lets"]
	if base["contents"].is_empty():
		m["state"] = "Empty."
		m["heat"] = 20
		return
	var rs := runs(base)
	var sim: RefCounted = base["sim"]
	var sum := 0
	var n := 0
	for r: Vector3i in rs:
		sum += (sim.rect_temp(r.x, r.y, r.z, 1) as Vector3i).z * r.z
		n += r.z
	var avg := int(float(sum) / float(maxi(1, n)))
	var target := int(mode["target"])
	var warming := target > 20
	m["heat"] = avg
	if (avg >= target) if warming else (avg <= target):
		m["state"] = "At %d degrees." % target
		return
	var mixer := stirring(g, m, base)
	if not mixer.is_empty():
		m["waits"] = "Waiting for the Blender to finish stirring."
		m["state"] = m["waits"]
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


static func info(g, m: Dictionary, def: Dictionary) -> String:
	var mode := mode_of(g, m, def)
	var s := "%s (%s, %d degrees)." % [m.get("state", ""), mode["name"], int(mode["target"])]
	if modes(g, def).size() > 1:
		s += " Click to change the setting."
	return s


## Nothing of its own: the base draws itself.
static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
