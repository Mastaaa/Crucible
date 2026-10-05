extends RefCounted
## Bus Hopper (A5): the network's import and export point. Bolted in place with an open mouth
## in front. Importing (the default), it swallows the loose bankable pixels in its mouth and
## whatever a joined Tank, Chute or Conveyor passes in, and banks them: a good under its own
## id, anything else into its stockpile (Funnel rules). Click it to switch to exporting a
## banked good (or Water): it takes units off the bank and passes them out of its `out` face
## into whatever is joined there, or pours them out of its mouth when nothing is. Both ways need
## a Node or the Hub in reach and a little power per cell.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")

const IMPORT := -1              # the mode that imports; any other value is the material exported


## The loose cells the mouth covers: `depth` rows past the front wall, the wall's width across.
static func mouth(g, m: Dictionary, def: Dictionary) -> Rect2i:
	var fo := CUT.front_of(g, m, def)
	var depth := int(def["params"]["depth"])
	var r: Rect2i = CUT.slice(fo["p"], fo["n"], 0, int(fo["across"]), 0)
	return r.merge(CUT.slice(fo["p"], fo["n"], depth - 1, int(fo["across"]), 0))


## Materials a click can switch to export, in id order: banked goods, then Water if the Hub holds some.
static func exportable(g) -> Array:
	var out: Array = []
	for mat: int in g.goods:
		if g.goods[mat] > 0.001:
			out.append(mat)
	var water := M.id_of("Water")
	if g.stock[D.R_WATER] > 0.01 and not out.has(water):
		out.append(water)
	out.sort()
	return out


## Units one cell of `mat` is worth in the bank.
static func units_per_cell(mat: int) -> float:
	return D.cell_units(mat)


static func banked(g, mat: int) -> float:
	if M.is_good(mat):
		return g.goods.get(mat, 0.0)
	if mat == M.id_of("Water"):
		return g.stock[D.R_WATER]
	return 0.0


static func _take(g, mat: int, units: float) -> void:
	if M.is_good(mat):
		g.take_good(mat, units)
	else:
		g.stock[D.R_WATER] = maxf(0.0, g.stock[D.R_WATER] - units)


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	m["state"] = ""
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	var mode: int = m.get("mode", IMPORT)
	if mode == IMPORT:
		_import(g, m, def)
	else:
		_export(g, m, def, mode)


static func _import(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	var power := float(p["power"])
	var did := 0
	# What joined modules passed in.
	var left := int(p["rate"])
	for mat: int in m["contents"].keys():
		var n := mini(left, int(m["contents"][mat]))
		if M.is_good(mat):
			n = mini(n, g.good_room_cells(mat))      # a full bank holds a good back
		if n <= 0 or not MU.take_power(g, power * n):
			continue
		m["contents"][mat] -= n
		if m["contents"][mat] <= 0:
			m["contents"].erase(mat)
		left -= n
		g.bank_cells(m["at"], mat, n)
		did += n
		if left <= 0:
			break
	# What lies in the mouth.
	var r := mouth(g, m, def)
	var mask := M.mask("loose_bank" if g.goods_room() >= 1.0 else "loose_stock")    # no room: goods stay out
	var there: int = g.sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)
	if there > 0:
		if MU.take_power(g, power * there):
			var got: PackedInt32Array = g.sim.dig_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask, 0, 0)
			for mat in 256:
				if got[mat] > 0:
					g.bank_cells(m["at"], mat, got[mat])
					did += got[mat]
		else:
			m["state"] = "Waiting for power."
			return
	m["moved"] = m.get("moved", 0) + did
	m["state"] = "Importing." if did > 0 else "Importing: nothing to take."


static func _export(g, m: Dictionary, def: Dictionary, mat: int) -> void:
	var p: Dictionary = def["params"]
	var power := float(p["power"])
	var upc := units_per_cell(mat)
	var room := MU.capacity(m, def) - MU.stored(m)
	var n := mini(mini(int(p["rate"]), room), int(floor(banked(g, mat) / upc)))
	if n > 0:
		if not MU.take_power(g, power * n):
			m["state"] = "Waiting for power."
			return
		_take(g, mat, upc * n)
		MU.add(m, def, mat, n)
		m["moved"] = m.get("moved", 0) + n
	var out := MU.partner(g, m, def, "out")
	if out.is_empty():
		_pour(g, m, def)
	if MU.stored(m) > 0 or n > 0:
		m["state"] = "Exporting %s." % M.names[mat]
	else:
		m["state"] = "Exporting %s: none banked." % M.names[mat]


## Nothing joined at `out`: what the hollow holds goes out of the mouth, a few cells at a scan.
static func _pour(g, m: Dictionary, def: Dictionary) -> void:
	var fo := CUT.front_of(g, m, def)
	var pt: Vector2 = fo["p"]
	var nrm := Vector2(fo["n"])
	var side := Vector2(nrm.y, nrm.x).abs()
	var left := int(def["params"]["rate"])
	for mat: int in m["contents"].keys():
		while left > 0 and m["contents"][mat] > 0:
			var off: float = (g.rng.randf() - 0.5) * float(fo["across"]) * 0.6
			var at: Vector2 = pt + nrm * 1.5 + side * off
			var v: Vector2 = nrm * 0.5 + side * (g.rng.randf() - 0.5) * 0.4   # cells a tick
			g.sim.add_particle(at.x, at.y, v.x, v.y, mat)
			m["contents"][mat] -= 1
			left -= 1
		if m["contents"][mat] <= 0:
			m["contents"].erase(mat)
		if left <= 0:
			break


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


## A click moves on to the next banked good to export, and after the last one back to importing.
static func use(g, m: Dictionary, def: Dictionary) -> void:
	var opts := exportable(g)
	var mode: int = m.get("mode", IMPORT)
	var next := IMPORT
	if mode == IMPORT:
		if not opts.is_empty():
			next = opts[0]
	else:
		var k := opts.find(mode)
		if k >= 0 and k + 1 < opts.size():
			next = opts[k + 1]
		elif k < 0:
			var later := opts.filter(func(o: int) -> bool: return o > mode)
			if not later.is_empty():
				next = later[0]
	m["mode"] = next
	g.show_banner("%s: %s." % [def["name"], "importing" if next == IMPORT else "exporting " + M.names[next]], 1.5)


static func info(g, m: Dictionary, _def: Dictionary) -> String:
	var mode: int = m.get("mode", IMPORT)
	var what := "Importing" if mode == IMPORT else "Exporting %s (%.1f banked)" % [M.names[mode], banked(g, mode)]
	return "%s Click to switch. %s %d cells moved so far." % [m.get("state", ""), what + ".", m.get("moved", 0)]


## The mouth, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var r := mouth(g, m, def)
	var col := Color(0.4, 0.85, 0.8, 0.5) if m.get("mode", IMPORT) == IMPORT else Color(0.95, 0.7, 0.4, 0.5)
	var a: Vector2 = g.to_screen(Vector2(r.position))
	var b: Vector2 = g.to_screen(Vector2(r.end))
	var w := maxf(1.0, z * 0.5)
	ov.draw_line(a, Vector2(b.x, a.y), col, w)
	ov.draw_line(Vector2(b.x, a.y), b, col, w)
	ov.draw_line(b, Vector2(a.x, b.y), col, w)
	ov.draw_line(Vector2(a.x, b.y), a, col, w)
