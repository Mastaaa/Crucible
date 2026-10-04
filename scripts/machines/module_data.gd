extends RefCounted
## Loads module definitions from data/modules/*.json (one file per module group) into the
## shape machines.gd registers (test_modules.gd shows it): sizes are [w, h], face types and
## directions are words. A definition's `kind` names the behaviour script that runs it.

const F = preload("res://scripts/machines/faces.gd")

## The group files, in Build-list order. A new group adds its file here.
const FILES := [
	"res://data/modules/logistics.json",
	"res://data/modules/excavation.json",
	"res://data/modules/movers.json",
	"res://data/modules/power.json",
	"res://data/modules/support.json",
]

const TYPES := {"pixel": F.PIXEL, "power": F.POWER, "mech": F.MECH, "signal": F.SIGNAL}
const DIRS := {"up": F.UP, "down": F.DOWN, "left": F.LEFT, "right": F.RIGHT}


static func defs() -> Array:
	var out: Array = []
	for path: String in FILES:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_error("module data missing: %s" % path)
			continue
		var json: Variant = JSON.parse_string(f.get_as_text())
		if not json is Dictionary:
			push_error("module data unreadable: %s" % path)
			continue
		for e: Dictionary in json.get("modules", []):
			out.append(_convert(e))
	return out


static func _convert(e: Dictionary) -> Dictionary:
	var d := e.duplicate(true)
	d["size"] = Vector2i(int(e["size"][0]), int(e["size"][1]))
	d["wall"] = int(e.get("wall", 2))
	var faces: Array = []
	for f: Dictionary in e["faces"]:
		var nf := f.duplicate()
		nf["type"] = TYPES[f["type"]]
		nf["dir"] = DIRS[f["dir"]]
		nf["at"] = int(f["at"])
		nf["w"] = int(f["w"])
		faces.append(nf)
	d["faces"] = faces
	var cost: Array = []
	for c in e.get("cost", [0, 0, 0, 0, 0]):
		cost.append(int(c))
	d["cost"] = cost
	return d
