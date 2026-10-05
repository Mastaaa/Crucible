extends RefCounted
## Sensors (A5): Thermometer, Material Sensor and Timer share this script, told apart by the
## definition's `params.sense`. A sensor has a signal face; a module with a signal face called `gate`
## (the Pump, the heat vessels, the Caster, the Combustor, the Shorer) that touches it works only
## while the sensor's signal is on, and stops while it is off (`machines.gd` `gated`). Signals pass
## by contact and no further.
##   temperature: on while the cells in the mouth (`depth` rows in front of `front`) average at least `above` degrees
##   material:    on while the mouth holds at least `min` cells of the material it watches
##   timer:       on for `duty` of every `period` seconds
## A click steps the setting (`above`, the watched material, the period) through `steps` or `watch`.

const MU = preload("res://scripts/machines/mu.gd")
const M = preload("res://scripts/materials.gd")
const BH = preload("res://scripts/machines/logistics/bus_hopper.gd")


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	match p["sense"]:
		"temperature":
			var r := BH.mouth(g, m, def)
			var t: Vector3i = g.sim.rect_temp(r.position.x, r.position.y, r.size.x, r.size.y)
			m["reading"] = t.z
			m["signal"] = t.z >= int(m.get("above", p["steps"][1]))
		"material":
			var r := BH.mouth(g, m, def)
			var mask := PackedByteArray()
			mask.resize(256)
			mask[watched(m, p)] = 1
			var n: int = g.sim.count_in_rect(r.position.x, r.position.y, r.size.x, r.size.y, mask)
			m["reading"] = n
			m["signal"] = n >= int(p["min"])
		"timer":
			var period := float(m.get("period", p["steps"][1]))
			m["reading"] = period
			m["signal"] = fmod(g.game_time, period) < period * float(p["duty"])


## The material a Material Sensor is watching.
static func watched(m: Dictionary, p: Dictionary) -> int:
	return M.id_of(p["watch"][int(m.get("watch", 0)) % p["watch"].size()])


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


## Where a setting sits in a step list (JSON numbers come in as floats).
static func _at(steps: Array, v: int) -> int:
	for i in steps.size():
		if int(steps[i]) == v:
			return i
	return -1


## A click steps the setting on to the next.
static func use(g, m: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = def["params"]
	var what := ""
	match p["sense"]:
		"temperature":
			var steps: Array = p["steps"]
			var k := (_at(steps, int(m.get("above", steps[1]))) + 1) % steps.size()
			m["above"] = int(steps[k])
			what = "on at %d degrees" % int(steps[k])
		"material":
			m["watch"] = (int(m.get("watch", 0)) + 1) % (p["watch"] as Array).size()
			what = "watching %s" % M.names[watched(m, p)]
		"timer":
			var steps: Array = p["steps"]
			var k := (_at(steps, int(m.get("period", steps[1]))) + 1) % steps.size()
			m["period"] = int(steps[k])
			what = "every %d seconds" % int(steps[k])
	g.show_banner("%s: %s." % [def["name"], what], 1.5)


static func info(_g, m: Dictionary, def: Dictionary) -> String:
	var p: Dictionary = def["params"]
	var on := "On." if m.get("signal", false) else "Off."
	match p["sense"]:
		"temperature":
			return "%s Reads %d degrees, on at %d. Click to change." % [on, int(m.get("reading", 20)), int(m.get("above", p["steps"][1]))]
		"material":
			return "%s Sees %d cells of %s (needs %d). Click to change." % [on, int(m.get("reading", 0)), M.names[watched(m, p)], int(p["min"])]
	return "%s On for %d%% of every %d seconds. Click to change." % [on, roundi(float(p["duty"]) * 100.0), int(m.get("period", p["steps"][1]))]


## A lamp on the module (green on, dark off), and the mouth it reads, outlined.
static func draw(ov, g, m: Dictionary, def: Dictionary, z: float) -> void:
	var c: Vector2 = g.to_screen(m["at"])
	var on: bool = m.get("signal", false)
	ov.draw_circle(c, 2.5 * z, Color(0.4, 1.0, 0.5, 0.95) if on else Color(0.25, 0.3, 0.28, 0.9))
	if def["params"]["sense"] == "timer":
		return
	var r := BH.mouth(g, m, def)
	var a: Vector2 = g.to_screen(Vector2(r.position))
	var b: Vector2 = g.to_screen(Vector2(r.end))
	ov.draw_rect(Rect2(a, b - a), Color(0.5, 0.9, 0.7, 0.4), false, maxf(1.0, z * 0.5))
