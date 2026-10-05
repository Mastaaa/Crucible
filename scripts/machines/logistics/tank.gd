extends RefCounted
## Tank (A3 starter kit): a hollow module that holds what the Excavator below it digs and
## empties through its top face into a Funnel when it docks (the `pass` rule in its
## definition does the emptying). Its size is the first limit research lifts.

const MU = preload("res://scripts/machines/mu.gd")
const F = preload("res://scripts/machines/faces.gd")
const M = preload("res://scripts/materials.gd")


## Cells of material the Tank holds at the given Tank Size level: its hollow, packed `pack`
## to a slot, times the level's fill.
static func capacity_at(def: Dictionary, level: int) -> int:
	var fill: Array = def["params"]["fill"]
	var cavity: int = F.layout(def, 0)["cavity"]
	return maxi(1, int(cavity * float(def["params"]["pack"]) * float(fill[mini(level, fill.size() - 1)])))


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	m["cap"] = capacity_at(def, g.level("tank_size"))


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	var cap := MU.capacity(m, def)
	var s := "%d of %d cells" % [MU.stored(m), cap]
	var best := -1
	var n := 0
	for k: int in m["contents"]:
		if m["contents"][k] > n:
			n = m["contents"][k]
			best = k
	if best >= 0:
		s += ", mostly %s" % M.names[best]
	return s


## What it holds, as a level in its hollow in the colour of what there is most of.
static func draw(ov, g, m: Dictionary, def: Dictionary, _z: float) -> void:
	if m.get("sim") != null:
		return          # the interior draws itself (scripts/interior_layer.gd)
	var n := MU.stored(m)
	if n <= 0:
		return
	var best := 0
	var most := 0
	for k: int in m["contents"]:
		if m["contents"][k] > most:
			most = m["contents"][k]
			best = k
	var fr := MU.frame(g, m, def)
	var size: Vector2i = fr["lay"]["size"]
	var t := float(def["wall"])
	var level := float(n) / float(maxi(1, MU.capacity(m, def)))
	var bottom := float(size.y) - t
	var top := bottom - (float(size.y) - 2.0 * t) * level
	var pts := PackedVector2Array()
	for c: Vector2 in [Vector2(t, bottom), Vector2(size.x - t, bottom), Vector2(size.x - t, top), Vector2(t, top)]:
		pts.append(g.to_screen(MU.world(fr, c)))
	ov.draw_colored_polygon(pts, Color(M.color_of(best), 0.75))
