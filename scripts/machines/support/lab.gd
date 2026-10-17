extends RefCounted
## Lab (A3, survivor of the cut): turns power into progress on the current tech, up to
## LAB_POWER_PER_S, and takes the goods that tech wants out of the Hub's stockpile. Both come
## straight from the stock while a Node or the Hub is in reach (MU.networked), like every
## module's: nothing travels by packet. Every Lab leaves `g.lab_reserve` power in the stock for
## the other machines, so a Cutter on the same Windmill keeps digging. The setting is one for the
## whole stockpile; a click on any Lab steps it through RESERVES.

const MU = preload("res://scripts/machines/mu.gd")
const D = preload("res://scripts/defs.gd")
const M = preload("res://scripts/materials.gd")

const RESERVES := [0, 2, 5, 10, 20]


static func scan(g, m: Dictionary, def: Dictionary) -> void:
	m["working"] = false
	m["why"] = ""
	if g.current_tech == "":
		m["why"] = "Nothing picked: T opens Research."
		return
	if not MU.networked(g, m, def):
		m["why"] = "No Node or Hub within reach."
		return
	var st: Dictionary = g.tech_step(g.current_tech)
	if st.is_empty():
		return
	_goods(g, def)
	var need: float = float(st["power"]) - g.tech_power.get(g.current_tech, 0.0)
	if need <= 0.0:
		return
	var burn := minf(D.LAB_POWER_PER_S * MU.SCAN_DT, need)
	var keep := float(g.lab_reserve)
	burn = minf(burn, g.stock[D.R_POWER] - keep)
	if burn <= 0.0:
		m["why"] = "No power in the Hub's stockpile." if keep <= 0.0 else "Holding %d power for the machines." % roundi(keep)
		return
	g.stock[D.R_POWER] -= burn
	g.used_acc += burn
	g.research_acc += burn
	g.tech_power[g.current_tech] = g.tech_power.get(g.current_tech, 0.0) + burn
	m["working"] = true


## Moves what the current tech still wants of Stone, Glimmer, Obsidian and Water from the
## stockpile into the tech, up to `goods_per_s` units a second for this Lab.
static func _goods(g, def: Dictionary) -> void:
	var want: Array = g.tech_mats_needed(g.tech_step(g.current_tech))
	var got: PackedFloat64Array = g.tech_mats_got(g.current_tech)
	var left: float = float(def["params"]["goods_per_s"]) * MU.SCAN_DT
	for r in D.NRES:
		if r == D.R_POWER or want[r] <= got[r] or left <= 0.0:
			continue
		var n: float = minf(minf(left, float(want[r]) - got[r]), g.stock[r])
		if n <= 0.0:
			continue
		g.stock[r] -= n
		got[r] += n
		left -= n
	g.tech_mats[g.current_tech] = got
	# Goods out of the bank, from the same quota.
	var bank: Dictionary = g.tech_bank_needed(g.tech_step(g.current_tech))
	var in_bank: Dictionary = g.tech_bank_got(g.current_tech)
	for nm: String in bank:
		var need: float = float(bank[nm]) - in_bank.get(nm, 0.0)
		if need <= 1e-6 or left <= 0.0:
			continue
		var n: float = g.take_good(M.id_of(nm), minf(left, need))
		if n > 0.0:
			in_bank[nm] = in_bank.get(nm, 0.0) + n
			left -= n


## A click steps the power the Labs leave for the other machines on to the next setting.
static func use(g, _m: Dictionary, def: Dictionary) -> void:
	var k := (RESERVES.find(int(g.lab_reserve)) + 1) % RESERVES.size()
	g.lab_reserve = int(RESERVES[k])
	g.show_banner("%ss leave %d power for the machines." % [def["name"], g.lab_reserve], 1.5)


static func step(_g, _m: Dictionary, _def: Dictionary) -> void:
	pass


static func info(g, m: Dictionary, _def: Dictionary) -> String:
	var tail := " Leaves %d power for the machines (click to change)." % int(g.lab_reserve)
	if m.get("why", "") != "":
		var why: String = m["why"]
		return why if why.begins_with("Holding") else why + tail
	if m.get("working", false):
		return "Researching %s (%d%%)." % [g.tech(g.current_tech)["name"], roundi(g.tech_power_frac(g.current_tech) * 100.0)] + tail
	return "Idle." + tail


## A small lit window on the front while it works.
static func draw(ov, g, m: Dictionary, def: Dictionary, _z: float) -> void:
	if not m.get("working", false):
		return
	var r := MU.bounds(m, def)
	var a: Vector2 = g.to_screen(Vector2(r.position.x + 6, r.position.y + 6))
	var b: Vector2 = g.to_screen(Vector2(r.end.x - 6, r.position.y + 12))
	ov.draw_rect(Rect2(a, b - a), Color(0.9, 0.6, 0.85, 0.7))
