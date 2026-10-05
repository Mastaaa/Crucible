extends RefCounted
## Casing: the walls of a module, real cells of one material held together as a rigid
## body (A3 machine framework). Integrity is the share of the designed wall pixels still
## there. A breach is a path from the cavity to open air through missing wall pixels
## (thickness is the margin: one layer gone is a dent, both is a hole). Below DEAD the
## module is wreckage.

const D = preload("res://scripts/defs.gd")
const F = preload("res://scripts/machines/faces.gd")
const M = preload("res://scripts/materials.gd")

## Stand-in casing until the casing list exists.
## TODO: the casing material becomes a field of the module definition (and with it, what melts it).
const MATERIAL := D.OBSIDIAN
const DEAD := 0.5          # integrity below this and the module drops as wreckage
const BREACH_LEAK := 6     # contents units a breached module spills per scan

## Wear (A5): a vessel with an interior loses casing pixels while its hottest cell is above its
## melting point (`melts` in the definition, else MELT) and while corrosive contents sit in it.
const MELT := 1150         # degrees: Lava (1100) stays inside, Glass (1700) and white heat do not
const MELT_STEP := 150     # degrees over the melting point that cost one more pixel a scan
const MELT_MAX := 6        # pixels a scan at most
const ACID_UNITS := 400    # corrosive units that make the acid chance a scan its largest
const ACID_CHANCE := 0.1   # chance a scan that a vessel full of acid loses one pixel


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


## Casing wear for one module with an interior, once a scan: heat above the melting point and
## acid take pixels out of the wall (so integrity falls, and a hole opens in the end). It runs on
## what the interior holds, so an empty vessel never wears.
static func wear(g, m: Dictionary, def: Dictionary) -> void:
	var sim: Variant = m.get("sim")
	if sim == null or m["contents"].is_empty():
		return
	var b: Rect2i = m["box"]
	var hi: int = sim.rect_temp(b.position.x, b.position.y, b.size.x, b.size.y).y
	var melts := int(def.get("melts", MELT))
	var lost := 0
	var why := ""
	if hi > melts:
		lost = mini(MELT_MAX, 1 + floori(float(hi - melts) / float(MELT_STEP)))
		why = "melting"
	var acid := 0
	for mat: int in m["contents"]:
		if M.is_corrosive(mat):
			acid += m["contents"][mat]
	if acid > 0 and g.rng.randf() < ACID_CHANCE * minf(1.0, float(acid) / float(ACID_UNITS)):
		lost += 1
		why = why if why != "" else "corroding"
	if lost <= 0:
		return
	if not m.get("worn", false):
		m["worn"] = true
		g.alert("module", "%s casing is %s." % [def["name"], why], m["at"])
	_erode(g, m, def, lost)


## Takes `n` casing pixels (chosen at random from what is still there) out of the body.
static func _erode(g, m: Dictionary, def: Dictionary, n: int) -> void:
	var lay := F.layout(def, m["turns"])
	var cells: PackedByteArray = lay["cells"]
	var px: PackedByteArray = g.sim.body_pixels(m["body"])
	if px.size() != cells.size():
		return
	var w: int = lay["size"].x
	var hit := 0
	for _try in 80:
		var i: int = g.rng.randi() % cells.size()
		if cells[i] == F.CASING and px[i] != 0:
			g.sim.body_set_pixel(m["body"], i % w, floori(float(i) / float(w)), 0)
			px[i] = 0
			hit += 1
			if hit >= n:
				break
	if hit > 0:
		m["dirty"] = true
