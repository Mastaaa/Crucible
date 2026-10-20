extends RefCounted
## Macerator (A4, recut in A9 into an interior strip): grinds solids to powder for the base at its `out` face. It
## takes two kinds of work: loose rigid bodies (a collapsed slab, a Press's block, a load a Conveyor brings) that
## touch its mouth, `front`, and solid cells (rock, ore) the base at its `in` face holds. Each cell becomes what
## it shatters to (Stone to Rubble), a few cells at a scan, and the powder goes straight into the `out` base.
## Modules' own casings are never ground. A body that has come to rest settles back into the ground in a
## moment (the engine's rule) and is then rock again, so bodies are ground on the way in: the Macerator holds
## one it has started on until it is gone. It needs power from a Node or the Hub in reach.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")
const BW = preload("res://scripts/machines/processing/base_work.gd")

const MOUTH := 3                # rows deep past the front that count as the mouth


## Ids of the loose bodies touching the mouth.
static func in_mouth(g, m: Dictionary, def: Dictionary) -> Array:
	var mods := {}
	for id: int in g.modules:
		mods[g.modules[id]["body"]] = true
	var fo := CUT.front_of(g, m, def)
	var out: Array = []
	for k in MOUTH:
		var r := CUT.slice(fo["p"], fo["n"], k, int(fo["across"]), 0)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var o: int = g.sim.get_owner(x, y)
				if o != 0 and not mods.has(o) and not out.has(o):
					out.append(o)
	return out


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	m["state"] = ""
	m["net"] = MU.networked(g, m, def)
	var ends := BW.ends(g, m, def)
	var why := BW.missing(ends)
	if why != "":
		m["state"] = why
		return
	var src: Dictionary = ends[0]
	var dst: Dictionary = ends[1]
	var bodies := in_mouth(g, m, def)
	var solids := _solids(g, src)
	if bodies.is_empty() and solids.is_empty():
		m["state"] = "Nothing to grind."
		return
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	var budget := MU.rate(g, int(p["rate"]))
	for mat: int in solids:
		if budget <= 0:
			break
		budget -= _crush(g, m, def, src, dst, mat, budget)
	for id: int in bodies:
		if budget <= 0:
			break
		budget -= _grind(g, m, def, dst, id, budget)


## The solid materials the `in` base holds that grind to something else, and may leave it.
static func _solids(g, src: Dictionary) -> Array:
	var out: Array = []
	for mat: int in src["contents"]:
		if M.kind_of(mat) == M.K_STATIC and M.ground_of(mat) != mat and BW.may_leave(g, src, mat):
			out.append(mat)
	return out


## Grinds up to `budget` solid cells of `mat` out of the `in` base into the `out` base; returns how many it did.
static func _crush(g, m: Dictionary, def: Dictionary, src: Dictionary, dst: Dictionary, mat: int, budget: int) -> int:
	var out := M.ground_of(mat)
	var dst_def: Dictionary = MU.defs[dst["def"]]
	var want := mini(mini(budget, src["contents"].get(mat, 0)), MU.capacity(dst, dst_def) - MU.stored(dst))
	if want <= 0:
		m["state"] = "Full: nowhere to put the powder."
		return 0
	var cost := D.power_per_cell(mat) * float(def["params"]["power_mult"])
	while want > 0 and not MU.take_power(g, cost * float(want)):
		want = want >> 1
	if want <= 0:
		m["state"] = "Waiting for power."
		return 0
	var got := MU.take(src, mat, want)
	var put := MU.add(dst, dst_def, out, got)
	if put < got:
		MU.add(src, MU.defs[src["def"]], mat, got - put)
	m["ground"] = m.get("ground", 0) + put
	m["state"] = "Grinding."
	return put


## Grinds up to `budget` cells of body `id`; returns how many it did.
static func _grind(g, m: Dictionary, def: Dictionary, dst: Dictionary, id: int, budget: int) -> int:
	var bi: PackedFloat32Array = g.sim.body_info(id)
	if bi.size() < 5:
		return 0
	var w := int(bi[0])
	var left := int(bi[4])
	var px: PackedByteArray = g.sim.body_pixels(id)
	var done := 0
	var start: int = m.get("sweep", 0) % maxi(1, px.size())
	for k in px.size():
		if done >= budget or left <= 0:
			break
		var i := (start + k) % px.size()
		var mat: int = px[i]
		if mat == 0:
			continue
		var out := M.ground_of(mat)
		if MU.capacity(dst, MU.defs[dst["def"]]) - MU.stored(dst) < 1:
			m["state"] = "Full: nowhere to put the powder."
			break
		if not MU.take_power(g, D.power_per_cell(mat) * float(def["params"]["power_mult"])):
			m["state"] = "Waiting for power."
			break
		if done == 0:
			g.sim.set_creature(id, true)     # a body being ground doesn't settle back into the ground
		MU.add(dst, MU.defs[dst["def"]], out, 1)
		m["ground"] = m.get("ground", 0) + 1
		m["state"] = "Grinding."
		done += 1
		left -= 1
		if left <= 0 or g.sim.body_set_pixel(id, i % w, floori(float(i) / float(w)), 0) < 0:
			g.sim.remove_body(id)
			left = 0
			break
	m["sweep"] = start + done
	return done


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, _def: Dictionary) -> String:
	return "%s %d ground so far." % [m.get("state", ""), m.get("ground", 0)]


## The mouth, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var fo := CUT.front_of(g, m, def)
	var a := Vector2(fo["p"])
	var n := Vector2(fo["n"])
	var side := Vector2(n.y, n.x).abs() * float(fo["across"]) * 0.5
	var b := a + n * float(MOUTH)
	var col := Color(0.9, 0.7, 0.4, 0.5)
	for pts in [[a - side, a + side], [a - side, b - side], [a + side, b + side], [b - side, b + side]]:
		ov.draw_line(g.to_screen(pts[0]), g.to_screen(pts[1]), col, maxf(1.0, z * 0.5))
