extends RefCounted
## Casing: the walls of a module, real cells of one material held together as a rigid
## body (A3 machine framework). Integrity is the share of the designed wall pixels still
## there. A breach is a path from the cavity to open air through missing wall pixels
## (thickness is the margin: one layer gone is a dent, both is a hole). Below DEAD the
## module is wreckage.

const D = preload("res://scripts/defs.gd")
const F = preload("res://scripts/machines/faces.gd")

## Stand-in casing until the casing list exists.
## TODO: melting point (A1's temperature field) and corrosion apply to the walls, and
## the casing material becomes a field of the module definition.
const MATERIAL := D.OBSIDIAN
const DEAD := 0.5          # integrity below this and the module drops as wreckage
const BREACH_LEAK := 6     # contents units a breached module spills per scan


## Casing pixels of `m` as a share of the design, counting open ports as present.
static func integrity(m: Dictionary, count: int) -> float:
	var designed: int = m["designed"]
	return clampf(float(count + int(m["opened"])) / float(maxi(1, designed)), 0.0, 1.0)


## Local pixel where the cavity of `m` reaches open air through its wall, or (-1, -1)
## when it's sealed. `pixels` is the engine's bitmap (body_pixels); open ports count as
## sealed (they're joined to a partner's open port).
static func breach_at(m: Dictionary, lay: Dictionary, pixels: PackedByteArray) -> Vector2i:
	var size: Vector2i = lay["size"]
	var w := size.x
	var h := size.y
	var cells: PackedByteArray = lay["cells"]
	var sealed := {}
	var faces: Array = lay["faces"]
	for fi in faces.size():
		if m["faces"][fi]["open"]:
			for c: Vector2i in faces[fi]["cells"]:
				sealed[c.y * w + c.x] = true
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue: Array = []
	for i in w * h:
		if cells[i] == F.CAVITY and pixels[i] == 0:
			seen[i] = 1
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x := i % w
		var y := floori(i / float(w))
		for d: Vector2i in [F.UP, F.DOWN, F.LEFT, F.RIGHT]:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				return Vector2i(x, y)
			var j := ny * w + nx
			if seen[j] == 1 or pixels[j] != 0 or sealed.has(j):
				continue
			seen[j] = 1
			queue.append(j)
	return Vector2i(-1, -1)
