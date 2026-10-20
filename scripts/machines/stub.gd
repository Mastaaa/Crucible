extends RefCounted
## Placeholder behaviour for a part A9 has defined but not built (a definition with `"stub": true`,
## `"kind": "stub"`). The part has its layer, faces, attach points and price; a track fills in the
## behaviour by giving the definition its own `kind` and dropping `stub`. Until then it can't be picked
## from the Build list, and placed by hand (tests) it says so.


static func scan(_g, m: Dictionary, _def: Dictionary) -> void:
	m["state"] = "Not built yet."


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(_g, _m: Dictionary, def: Dictionary) -> String:
	return "Not built yet (the %s track)." % def.get("track", "A9")


static func draw(_ov, _g, _m: Dictionary, _def: Dictionary, _z: float) -> void:
	pass
