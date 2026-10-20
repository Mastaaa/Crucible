extends RefCounted
## Pipe Router (A9): a bolted junction with three Pipe ends. Pipes that end at it put what they carry into its
## hollow and Pipes that start at it draw from there, sharing its stock between them: it merges what comes in and
## splits what goes out. It holds only a little, so a blocked line backs up.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const LN = preload("res://scripts/machines/lines.gd")
const EX = preload("res://scripts/machines/exterior/ext.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	m["cap"] = int(def["params"]["cap"])
	var n := 0
	for pt: String in ["a", "b", "c"]:
		if LN.taken(g, m["id"], pt) != 0:
			n += 1
	m["pipes"] = n
	m["state"] = "No Pipe." if n == 0 else "%d Pipe%s joined." % [n, "" if n == 1 else "s"]


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	var held := MU.stored(m)
	var what := "Empty."
	if held > 0:
		what = "%d of %d cells, mostly %s." % [held, MU.capacity(m, def), M.names[EX.most(m)]]
	return "%s %s" % [m.get("state", ""), what]


## What it holds, as a level in its hollow.
static func draw(ov, g, m: Dictionary, def: Dictionary, _z: float) -> void:
	var n := MU.stored(m)
	if n <= 0:
		return
	var fr := MU.frame(g, m, def)
	var size: Vector2i = fr["lay"]["size"]
	var t := float(def["wall"])
	var level := float(n) / float(maxi(1, MU.capacity(m, def)))
	var bottom := float(size.y) - t
	var top := bottom - (float(size.y) - 2.0 * t) * level
	var pts := PackedVector2Array()
	for c: Vector2 in [Vector2(t, bottom), Vector2(size.x - t, bottom), Vector2(size.x - t, top), Vector2(t, top)]:
		pts.append(g.to_screen(MU.world(fr, c)))
	ov.draw_colored_polygon(pts, Color(M.color_of(EX.most(m)), 0.75))
