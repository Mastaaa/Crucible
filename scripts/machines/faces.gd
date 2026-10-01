extends RefCounted
## Module faces and layouts (A3 machine framework). A face is a stretch of a module's
## wall with a type and an outward direction. It stays closed (plain casing) until a
## face of the same type and width touches it, square on, at a multiple of 90 degrees;
## both then open, and they close again when the contact ends.
##
## A module's template (see test_modules.gd) is a hollow rectangle: `size`, a `wall`
## thickness and a list of faces {type, dir, at, w, name}, where `at` is the middle of
## the face along its wall. `layout` turns it by quarter turns (placement is at 90
## degrees; the engine rotates it freely afterwards) into pixels and faces in the
## body's own frame, which is what the engine's bitmap uses.

const PIXEL := 0
const POWER := 1
const MECH := 2
const SIGNAL := 3
const TYPE_NAMES := ["pixel", "power", "mechanical", "signal"]

const UP := Vector2i(0, -1)
const RIGHT := Vector2i(1, 0)
const DOWN := Vector2i(0, 1)
const LEFT := Vector2i(-1, 0)

const CASING := 1    # layout cell values: casing pixel
const CAVITY := 2    # ... and inside, where contents sit

static var _cache := {}


## The template turned `turns` quarter turns clockwise: {size: Vector2i, cells:
## PackedByteArray (w * h of EMPTY/CASING/CAVITY), faces: [{type, dir, cells:
## Array[Vector2i], centre: Vector2, w, name}], designed: casing pixels, cavity: cells}.
static func layout(def: Dictionary, turns: int) -> Dictionary:
	turns = posmod(turns, 4)
	var key := "%s/%d" % [def["id"], turns]
	if _cache.has(key):
		return _cache[key]
	var w: int = def["size"].x
	var h: int = def["size"].y
	var t: int = def["wall"]
	var cells := PackedByteArray()
	cells.resize(w * h)
	for y in h:
		for x in w:
			var inside := x >= t and x < w - t and y >= t and y < h - t
			cells[y * w + x] = CAVITY if inside else CASING
	var faces: Array = []
	for f: Dictionary in def["faces"]:
		var dir: Vector2i = f["dir"]
		var span: int = f["w"]
		var from: int = int(f["at"]) - (span >> 1)
		var cl: Array = []
		for i in range(from, from + span):
			for d in t:
				if dir == UP:
					cl.append(Vector2i(i, d))
				elif dir == DOWN:
					cl.append(Vector2i(i, h - 1 - d))
				elif dir == LEFT:
					cl.append(Vector2i(d, i))
				else:
					cl.append(Vector2i(w - 1 - d, i))
		faces.append({"type": f["type"], "dir": dir, "cells": cl, "w": span, "name": f.get("name", "")})
	for _i in turns:
		var nw := h
		var nh := w
		var rot := PackedByteArray()
		rot.resize(nw * nh)
		for y in h:
			for x in w:
				rot[x * nw + (h - 1 - y)] = cells[y * w + x]
		cells = rot
		for f: Dictionary in faces:
			var cl: Array = f["cells"]
			for k in cl.size():
				var c: Vector2i = cl[k]
				cl[k] = Vector2i(h - 1 - c.y, c.x)
			var d: Vector2i = f["dir"]
			f["dir"] = Vector2i(-d.y, d.x)
		w = nw
		h = nh
	var designed := 0
	var cavity := 0
	for v in cells:
		if v == CASING:
			designed += 1
		elif v == CAVITY:
			cavity += 1
	for f: Dictionary in faces:
		var sum := Vector2.ZERO
		for c: Vector2i in f["cells"]:
			sum += Vector2(c) + Vector2(0.5, 0.5)
		f["centre"] = sum / maxi(1, f["cells"].size())
	var out := {"size": Vector2i(w, h), "cells": cells, "faces": faces, "designed": designed, "cavity": cavity}
	_cache[key] = out
	return out


## Whether a face of type `ta` and width `wa` can join one of `tb` and `wb`.
static func compatible(ta: int, wa: int, tb: int, wb: int) -> bool:
	return ta == tb and wa == wb
