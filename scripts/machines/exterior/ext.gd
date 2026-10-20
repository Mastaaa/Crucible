extends RefCounted
## What the exterior parts (A9: Spout, Vacuum, Energy Port, the Hookups, the Pipe Router) share: the base a
## part is plugged into and where its front is. The older exterior parts (Cutter, Pump, Funnel...) hang by
## pixel and mech faces and do not use these.

const MU = preload("res://scripts/machines/mu.gd")
const LY = preload("res://scripts/machines/layers.gd")
const M = preload("res://scripts/materials.gd")
const D = preload("res://scripts/defs.gd")
const CUT = preload("res://scripts/machines/excavation/cutter.gd")


## The base module `m` is plugged into (its dictionary), or {} when it has none.
static func base_of(g, m: Dictionary) -> Dictionary:
	var ids := LY.bases_of(g, m)
	return g.modules[ids[0]] if not ids.is_empty() else {}


## Power for `n` cells at `per` a cell: all of it, else half as many cells until it is paid or none is left.
## Returns the cells that were paid for.
static func pay(g, per: float, n: int) -> int:
	while n > 0 and not MU.take_power(g, per * float(n)):
		n = n >> 1
	return n


## The material `m` holds most of, or -1.
static func most(m: Dictionary) -> int:
	var best := -1
	var n := 0
	for k: int in m["contents"]:
		if m["contents"][k] > n:
			best = k
			n = m["contents"][k]
	return best


## The rectangle in front of `m`'s front wall: `depth` rows past it, `across` cells wide (centred).
static func front_rect(g, m: Dictionary, def: Dictionary, across: int, depth: int) -> Rect2i:
	var fo := CUT.front_of(g, m, def)
	var r: Rect2i = CUT.slice(fo["p"], fo["n"], 0, across, 0)
	return r.merge(CUT.slice(fo["p"], fo["n"], depth - 1, across, 0))


## Outlines rectangle `r` on the overlay.
static func outline(ov, g, r: Rect2i, col: Color, z: float) -> void:
	var a: Vector2 = g.to_screen(Vector2(r.position))
	var b: Vector2 = g.to_screen(Vector2(r.end))
	var w := maxf(1.0, z * 0.5)
	ov.draw_line(a, Vector2(b.x, a.y), col, w)
	ov.draw_line(Vector2(b.x, a.y), b, col, w)
	ov.draw_line(b, Vector2(a.x, b.y), col, w)
	ov.draw_line(Vector2(a.x, b.y), a, col, w)
