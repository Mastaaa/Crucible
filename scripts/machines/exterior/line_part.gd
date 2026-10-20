extends RefCounted
## Behaviour of a drawn line (A9: the Pipe, the Cable, the Network line). The work is in machines/lines.gd; this is
## the shape the module registry calls.

const LN = preload("res://scripts/machines/lines.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	LN.scan_line(g, m, def)


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(g, m: Dictionary, def: Dictionary) -> String:
	return LN.info(g, m, def)


static func use(g, m: Dictionary, def: Dictionary) -> void:
	LN.use(g, m, def)


static func rescue(g, m: Dictionary, def: Dictionary) -> void:
	LN.rescue(g, m, def)


static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	LN.draw(ov, g, m, def, z)
