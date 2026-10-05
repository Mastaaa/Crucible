extends RefCounted
## Machine interiors: a vessel's contents live in a small sim of their own, not as a count.
## A definition with `"interior": true` gets one. It is a box of the cavity's inner width, as
## tall as its capacity needs, with gravity straight down in the module's own frame and bedrock
## all round (the engine does nothing within three cells of its edge). A cell of material in
## it is one unit, so capacity and balance stay as they were; the Tank packs four units to a
## slot of its hollow, which is why the box is taller than the cavity and is drawn squeezed.
##
## `m["sim"]` is the CrucibleSim (null for a module without one, and after a load until
## `restore`), `m["box"]` the open part of it (a Rect2i), and `m["contents"]` stays what it was
## for everything else: a count per material, kept in step by `MU.add` and `MU.take` and
## recounted from the sim at every scan (`sync`), because reactions inside change what is there.
## MU holds the cell moves themselves (it cannot preload this file).

const D = preload("res://scripts/defs.gd")
const MU = preload("res://scripts/machines/mu.gd")
const F = preload("res://scripts/machines/faces.gd")
const SF = preload("res://scripts/sim_factory.gd")

const PAD := 3             # bedrock cells round the open box


static func wants(def: Dictionary) -> bool:
	return def.get("interior", false)


## The grid size and the open box a module's interior needs at its present capacity.
static func shape(m: Dictionary, def: Dictionary) -> Dictionary:
	var lay_w := int(F.layout(def, m["turns"])["size"].x)          # the width in the frame the module was placed in
	var iw := lay_w - 2 * int(def["wall"])
	var rows := ceili(float(MU.capacity(m, def)) / float(iw))
	var w := ceili(float(iw + 2 * PAD) / 32.0) * 32
	var h := ceili(float(rows + 2 * PAD) / 32.0) * 32
	return {"w": w, "h": h, "box": Rect2i(PAD, h - PAD - rows, iw, rows)}


## Makes or resizes the interior to fit the module's capacity. Contents sit at the bottom, so a
## taller box keeps them where they lie. A new interior is filled from `contents` (a module from
## an older save, or one that was handed units before it had a sim).
static func ensure(m: Dictionary, def: Dictionary) -> void:
	if not wants(def):
		return
	var want := shape(m, def)
	var box: Rect2i = want["box"]
	var sim: Variant = m.get("sim")
	if sim == null:
		sim = SF.create_pocket(want["w"], want["h"])
		_wall(sim, want["w"], want["h"], box)
		m["sim"] = sim
		m["box"] = box
		var held: Dictionary = m["contents"].duplicate()
		m["contents"].clear()
		for mat: int in held:
			MU.add(m, def, mat, held[mat])
		return
	var old: Rect2i = m["box"]
	if sim.get_width() == want["w"] and sim.get_height() == want["h"] and old == box:
		return
	var from: PackedByteArray = sim.get_cells()
	var ow: int = sim.get_width()
	var buf := PackedByteArray()
	buf.resize(int(want["w"]) * int(want["h"]))
	buf.fill(D.BEDROCK)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			buf[y * int(want["w"]) + x] = 0
	for r in mini(old.size.y, box.size.y):
		var sy := old.end.y - 1 - r
		var dy := box.end.y - 1 - r
		for x in mini(old.size.x, box.size.x):
			buf[dy * int(want["w"]) + box.position.x + x] = from[sy * ow + old.position.x + x]
	if sim.get_width() != want["w"] or sim.get_height() != want["h"]:
		sim.set_size(want["w"], want["h"])
		sim.set_ambient(PackedInt32Array([20]))
	sim.set_cells(buf)
	m["box"] = box


static func _wall(sim: RefCounted, w: int, h: int, box: Rect2i) -> void:
	var buf := PackedByteArray()
	buf.resize(w * h)
	buf.fill(D.BEDROCK)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			buf[y * w + x] = 0
	sim.set_cells(buf)


## Counts what the interior holds into `contents` (reactions change it between scans).
static func sync(m: Dictionary) -> void:
	var sim: Variant = m.get("sim")
	if sim == null:
		return
	var b: Rect2i = m["box"]
	var counts: PackedInt32Array = sim.rect_counts(b.position.x, b.position.y, b.size.x, b.size.y)
	var held := {}
	for mat in range(1, 256):
		if counts[mat] > 0:
			held[mat] = counts[mat]
	m["contents"] = held


## Every tick: the interior runs on.
static func step(m: Dictionary) -> void:
	var sim: Variant = m.get("sim")
	if sim != null:
		sim.step()


## The saved interiors, module id to the engine's bytes.
static func snapshot(g) -> Dictionary:
	var out := {}
	for id: int in g.modules:
		var sim: Variant = g.modules[id].get("sim")
		if sim != null:
			out[id] = sim.save_state()
	return out


## Puts saved interiors back after the modules have loaded (a module with none saved gets a
## fresh one, filled from its counts, at its next scan).
static func restore(g, saved: Dictionary) -> void:
	for id: int in saved:
		if not g.modules.has(id):
			continue
		var m: Dictionary = g.modules[id]
		var want := shape(m, MU.defs[m["def"]])
		var sim: RefCounted = SF.create_pocket(want["w"], want["h"])
		if sim.load_state(saved[id]):
			m["sim"] = sim
