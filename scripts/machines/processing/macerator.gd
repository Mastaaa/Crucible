extends RefCounted
## Macerator (A4): bolted in place, grinds loose rigid bodies (a collapsed slab, a Press's block, a
## load a Conveyor brings) that touch its mouth, `front`, into powder. Each cell of a body becomes
## what it shatters to (Stone to Rubble), a few cells at a scan, and the powder goes into its hollow
## and out through its pixel face into whatever is joined there (a Tank, a Funnel). Modules'
## own casings are never ground. A body that has come to rest settles back into the ground in a
## moment (the engine's rule) and is then rock again, so bodies are ground on the way in: the
## Macerator holds one it has started on until it is gone. It needs power from a Node or the Hub in reach.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")

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
	m["cap"] = int(p["cap"])
	m["net"] = MU.networked(g, m, def)
	var bodies := in_mouth(g, m, def)
	if bodies.is_empty():
		m["state"] = "Nothing in the mouth."
		return
	if not m["net"]:
		m["state"] = "No power: no Node or Hub in reach."
		return
	var budget := int(p["rate"])
	for id: int in bodies:
		if budget <= 0:
			break
		budget -= _grind(g, m, def, id, budget)


## Grinds up to `budget` cells of body `id`; returns how many it did.
static func _grind(g, m: Dictionary, def: Dictionary, id: int, budget: int) -> int:
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
		if MU.capacity(m, def) - MU.stored(m) < 1:
			m["state"] = "Full: nowhere to put the powder."
			break
		if not MU.take_power(g, D.power_per_cell(mat) * float(def["params"]["power_mult"])):
			m["state"] = "Waiting for power."
			break
		if done == 0:
			g.sim.set_creature(id, true)     # a body being ground doesn't settle back into the ground
		MU.add(m, def, out, 1)
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


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	return "%s %d of %d cells held, %d ground so far." % [m.get("state", ""), MU.stored(m), MU.capacity(m, def), m.get("ground", 0)]


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
