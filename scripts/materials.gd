extends RefCounted
## Reads data/materials.json once: the sim's material table and reactions, what
## the game needs to know about each material (name, kind, digging, what it
## yields, what it does to buildings) and the renderer's palette. defs.gd answers
## material questions through this, so a new material is one entry in the data file.

const PATH := "res://data/materials.json"
const KINDS := ["empty", "static", "powder", "liquid", "gas"]
const K_EMPTY := 0
const K_STATIC := 1
const K_POWDER := 2
const K_LIQUID := 3
const K_GAS := 4
# Stockpile order, as in defs.gd (kept here so the two files don't preload each other).
const RESOURCES := ["Stone", "Glimmer", "Obsidian", "Water", "Power"]
# Render styles, in the order the terrain shader numbers them.
const STYLES := ["empty", "flat", "rock", "strata", "speckle", "sparkle", "water", "lava", "fade", "smoke", "fire"]
# Palette flags (row 3, red channel).
const F_ROCK := 1
const F_BURNS := 2
const F_GLINTS := 4
const F_SENSED := 8

static var loaded := false
static var names := PackedStringArray()
static var kinds := PackedByteArray()
static var dig_rates := PackedFloat32Array()
static var dig_powers := PackedFloat32Array()
static var worths := PackedFloat32Array()   # per id: units a dug cell pays, against dirt's 1
static var yields: Array = []           # per id: PackedInt32Array of stockpiles
static var hots := PackedByteArray()
static var burns := PackedByteArray()
static var corrosives := PackedByteArray()
static var sighted := PackedStringArray()
static var ids := {}                    # name -> first id
static var families := {}               # family name -> its bit (A1): reactions can name a family
static var family_of := PackedInt32Array()   # per id: the material's family bits
static var sim_materials: Array = []    # for CrucibleSim.configure
static var sim_reactions: Array = []
# Temperature defaults by kind (A1): how readily heat crosses into a neighbour (0..1)
# and how strongly the depth's ambient pulls the cell back (0..1). Rock sits in the
# ground and settles back; loose, liquid and open cells only trade heat with what
# touches them.
const CONDUCT_BY_KIND := [0.04, 0.2, 0.12, 0.4, 0.04]
const SINK_BY_KIND := [0.0, 1.0, 0.25, 0.0, 0.0]
static var _palette: Image = null
static var _pal_rows: Array = []        # [color, color2, accent, style, mix, grain, flags, life_max, burn_life] per id


static func ensure() -> void:
	if loaded:
		return
	loaded = true
	names.resize(256)
	kinds.resize(256)
	kinds.fill(K_STATIC)
	dig_rates.resize(256)
	dig_powers.resize(256)
	dig_powers.fill(0.2)
	worths.resize(256)
	worths.fill(1.0)
	yields.resize(256)
	for i in 256:
		yields[i] = PackedInt32Array()
	family_of.resize(256)
	hots.resize(256)
	burns.resize(256)
	corrosives.resize(256)
	sighted.resize(256)
	_pal_rows.resize(256)
	for i in 256:
		names[i] = "Unknown"
	var text := FileAccess.get_file_as_string(PATH)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Can't read %s" % PATH)
		return
	# First pass: ids by name, so entries can refer to each other in any order.
	for e: Dictionary in data.get("materials", []):
		var id := int(e.get("id", -1))
		var nm: String = e.get("name", "")
		if id >= 0 and id < 256 and not ids.has(nm):
			ids[nm] = id
		for fam in _list(e.get("family", [])):
			if ids.has(fam):
				push_error("%s: family %s is also a material's name" % [nm, fam])
			elif not families.has(fam):
				if families.size() >= 16:
					push_error("%s: more than 16 families (%s)" % [nm, fam])
				else:
					families[fam] = 1 << families.size()
	for e: Dictionary in data.get("materials", []):
		var id := int(e.get("id", -1))
		if id < 0 or id > 255:
			continue
		var kind := KINDS.find(e.get("kind", "static"))
		if kind < 0:
			push_error("%s: unknown kind %s" % [e.get("name", "?"), e.get("kind")])
			kind = K_STATIC
		var ys := PackedInt32Array()
		var yv = e.get("yields", [])
		for y in (yv if yv is Array else [yv]):
			var r := RESOURCES.find(y)
			if r < 0:
				push_error("%s: yields unknown stockpile %s" % [e.get("name", "?"), y])
			else:
				ys.append(r)
		var burn: Dictionary = e.get("burn", {})
		var life: Array = e.get("life", [0, 0])
		var stages := int(e.get("stages", 1))
		var fam_bits := 0
		for fam in _list(e.get("family", [])):
			fam_bits |= int(families.get(fam, 0))
		var heats: Dictionary = e.get("heats", {})
		var cools: Dictionary = e.get("cools", {})
		for s in stages:
			var mid := id + s
			names[mid] = e.get("name", "Unknown")
			kinds[mid] = kind
			family_of[mid] = fam_bits
			dig_rates[mid] = float(e.get("dig_rate", 0.0))
			dig_powers[mid] = float(e.get("dig_power", 0.2))
			worths[mid] = float(e.get("worth", 1.0))
			yields[mid] = ys
			hots[mid] = 1 if bool(e.get("hot", false)) else 0
			burns[mid] = 1 if not burn.is_empty() else 0
			corrosives[mid] = 1 if bool(e.get("corrosive", false)) else 0
			sighted[mid] = e.get("sighted", "")
			var m := {
				"id": mid,
				"kind": kind,
				"density": int(e.get("density", 100)),
				"look": int(e.get("look", 0)),
				"max_step": int(e.get("max_step", 0)),
				"wander_bits": int(e.get("wander_bits", 0)),
				"slow": int(e.get("slow", 1)),
				"vents": bool(e.get("vents", false)),
				"glows": bool(e.get("glows", false)),
				"hot": bool(e.get("hot", false)),
				"flame": bool(e.get("flame", false)),
				"corrosive": bool(e.get("corrosive", false)),
				"scalds": bool(e.get("scalds", false)),
				"quench": bool(e.get("quench", false)),
				"quench_to": _ref(e, "quench_to"),
				"loosens_to": _ref(e, "loosens_to"),
				"erodes_to": _ref(e, "erodes_to"),
				"crumbles_to": _ref(e, "crumbles_to"),
				"shatters_to": _ref(e, "shatters_to"),
				"crumble": float(e.get("crumble", 0.0)),
				"crumbles_into": _ref(e, "crumbles_into"),
				"durability": int(e.get("durability", 0)),
				"buoyancy": int(e.get("buoyancy", 8)),
				"drift": int(e.get("drift", 64)),
				"life_min": int(life[0]),
				"life_max": int(life[1]),
				"life_decay": int(round(float(e.get("life_decay", 1.0)) * 256.0)),
				"ages_exposed": bool(e.get("ages_exposed", false)),
				"expires_to": _ref(e, "expires_to"),
				"expires_alt": _ref(e, "expires_alt"),
				"alt_chance": float(e.get("alt_chance", 0.0)),
				"light": int(e.get("light", 0)),
				"opacity": int(e.get("opacity", 0)),
				"structure": bool(e.get("structure", false)),
				"span": int(e.get("span", 0)),
				"overhang": int(e.get("overhang", 0)),
				"cohesive": bool(e.get("cohesive", false)),
				"kin": _ref(e, "kin"),
				"wash_to": _ref(e, "wash_to"),
				"wash": float(e.get("wash", 0.0)),
				"conduct": float(e.get("conduct", CONDUCT_BY_KIND[kind])),
				"sink": float(e.get("sink", SINK_BY_KIND[kind])),
				"family": fam_bits,
			}
			if e.has("cave"):
				m["cave"] = float(e["cave"])
			# Temperature (A1): what a source holds itself at, the points where it
			# becomes something else, and the heat it catches fire at.
			if e.has("temp"):
				m["placed"] = float(e["temp"])
			if e.has("hold"):
				m["hold"] = float(e["hold"])
				m["hold_rate"] = float(e.get("hold_rate", 0.25))
			if not heats.is_empty():
				m["heats_at"] = float(heats.get("at", 0.0))
				m["heats_to"] = _ref(heats, "to", e)
				m["heats_cost"] = float(heats.get("cost", 0.0))
			if not cools.is_empty():
				m["cools_at"] = float(cools.get("at", 0.0))
				m["cools_to"] = _ref(cools, "to", e)
				m["cools_cost"] = float(cools.get("cost", 0.0))
			if e.has("kindle"):
				m["kindle"] = float(e["kindle"])
			_wave1(e, m)
			if not burn.is_empty():
				m["burn_life"] = int(burn.get("life", 60))
				m["ignite"] = float(burn.get("ignite", 0.05))
				m["burn_speed"] = float(burn.get("speed", 0.1))
				m["burns_to"] = _ref(burn, "to", e)
				m["burn_gas"] = _ref(burn, "gas", e)
				m["gas_chance"] = float(burn.get("gas_chance", 0.0))
				m["flame_chance"] = float(burn.get("flame_chance", 0.0))
				if burn.has("temp"):
					m["burn_temp"] = float(burn["temp"])
				m["burn_wet"] = bool(burn.get("wet", false))
				if burn.has("catalyst"):
					m["burn_catalyst"] = _fam_bit(burn["catalyst"], e)
					m["burn_boost"] = float(burn.get("boost", 1.0))
			if e.has("age_chance"):
				m["age_chance"] = int(e["age_chance"])
				m["age_to"] = mid + 1 if s < stages - 1 else _ref(e, "condenses_to")
			sim_materials.append(m)
			_pal_rows[mid] = _pal_row(e, s, stages, int(life[1]), int(m.get("burn_life", 0)))
	sim_reactions = expand_reactions(data.get("reactions", []))


## The A2 keys of one entry, into the sim's dictionary `m`: heat_mass; sets {to, speed,
## catalyst, boost} (a countdown in aux, started from `life`); blast {radius, power,
## impact (cells/s of fall), temp, flame, inhibit}; absorbs {to, chance}; plume (what a
## swollen cell of this liquid bursts into); bursts {at, into}; grows {over, feed,
## reach, chance}; body {w, h} (a rigid body forged by a reaction's `emit`).
static func _wave1(e: Dictionary, m: Dictionary) -> void:
	if e.has("heat_mass"):
		m["heat_mass"] = int(e["heat_mass"])
	var sets: Dictionary = e.get("sets", {})
	if not sets.is_empty():
		m["sets_to"] = _ref(sets, "to", e)
		m["set_speed"] = float(sets.get("speed", 0.1))
		if sets.has("catalyst"):
			m["set_catalyst"] = _fam_bit(sets["catalyst"], e)
			m["set_boost"] = float(sets.get("boost", 1.0))
	var blast: Dictionary = e.get("blast", {})
	if not blast.is_empty():
		m["blast_r"] = int(blast.get("radius", 4))
		m["blast_power"] = int(blast.get("power", 4))
		# Cells a second of fall speed, as the sim keeps it: sixteenths of a cell a tick.
		if blast.has("impact"):
			m["blast_impact"] = int(round(float(blast["impact"]) * 16.0 / 60.0))
		if blast.has("temp"):
			m["blast_temp"] = float(blast["temp"])
		m["blast_flame"] = bool(blast.get("flame", false))
		if blast.has("inhibit"):
			m["blast_inhibit"] = _fam_bit(blast["inhibit"], e)
	var absorbs: Dictionary = e.get("absorbs", {})
	if not absorbs.is_empty():
		m["absorb_to"] = _ref(absorbs, "to", e)
		m["absorb_chance"] = float(absorbs.get("chance", 0.1))
	if e.has("plume"):
		m["plume"] = _ref(e, "plume")
	var bursts: Dictionary = e.get("bursts", {})
	if not bursts.is_empty():
		m["bursts_at"] = float(bursts.get("at", 100.0))
		m["plume"] = _ref(bursts, "into", e)
	var grows: Dictionary = e.get("grows", {})
	if not grows.is_empty():
		var over := PackedByteArray()
		over.resize(256)
		for nm in _list(grows.get("over", [])):
			if ids.has(nm):
				over[ids[nm]] = 1
			else:
				push_error("%s: grows over unknown material %s" % [e.get("name", "?"), nm])
		m["grow_over"] = over
		m["grow_feed"] = _fam_bit(grows.get("feed", ""), e)
		m["grow_reach"] = int(grows.get("reach", 1))
		m["grow_chance"] = float(grows.get("chance", 0.003))
	var body: Dictionary = e.get("body", {})
	if not body.is_empty():
		m["body_w"] = int(body.get("w", 4))
		m["body_h"] = int(body.get("h", 2))


## The bit of a family name (0, with an error, for one that no material carries).
static func _fam_bit(nm: String, owner: Dictionary) -> int:
	if not families.has(nm):
		push_error("%s: %s is not a family" % [owner.get("name", "?"), nm])
		return 0
	return int(families[nm])


## One name or a list of them, as a list.
static func _list(v) -> Array:
	return v if v is Array else [v]


## Every material id in a family, or the one id a material name means (empty
## for an unknown name).
static func members(nm: String) -> PackedInt32Array:
	ensure()
	var out := PackedInt32Array()
	if ids.has(nm):
		out.append(ids[nm])
	elif families.has(nm):
		var bit: int = families[nm]
		for m in 256:
			if family_of[m] & bit:
				out.append(m)
	return out


## The reaction table for the sim (A1). Each "when" names two materials or
## families (a family rule stands for every pair of their members); "becomes"
## names what each side turns into, or "same" to keep it. Rules written for a
## material pair go in first, so they override the family rules behind them
## (the sim keeps the first rule it sees for a pair). Optional keys: min_temp and
## max_temp (degrees the first cell must be within), heat (degrees given to both
## outputs), catalyst (a family) and boost (how many times the chance with one
## of that family touching).
static func expand_reactions(rules: Array) -> Array:
	var by_rank := [[], [], []]
	for rx: Dictionary in rules:
		var w: Array = rx.get("when", [])
		var b: Array = rx.get("becomes", [])
		if w.size() != 2 or b.size() != 2:
			push_error("Reaction needs two names in 'when' and two in 'becomes': %s" % rx)
			continue
		var rank := 0
		for nm in w:
			if families.has(nm):
				rank += 1
			elif not ids.has(nm):
				push_error("Reaction names unknown material or family %s" % nm)
				rank = -1
				break
		if rank < 0:
			continue
		var extra := {}
		for key in ["min_temp", "max_temp", "heat", "boost", "emit_chance"]:
			if rx.has(key):
				extra[key] = float(rx[key])
		if rx.has("emit"):
			if not ids.has(rx["emit"]):
				push_error("Reaction emits unknown material %s" % rx["emit"])
			else:
				extra["emit"] = int(ids[rx["emit"]])
		if rx.has("catalyst"):
			if not families.has(rx["catalyst"]):
				push_error("Reaction catalyst %s is not a family" % rx["catalyst"])
			else:
				extra["catalyst"] = int(families[rx["catalyst"]])
		for a in members(w[0]):
			for bb in members(w[1]):
				var r := {
					"a": a, "b": bb,
					"out_a": a if b[0] == "same" else ids.get(b[0], 0),
					"out_b": bb if b[1] == "same" else ids.get(b[1], 0),
					"chance": float(rx.get("chance", 1.0)),
				}
				r.merge(extra)
				by_rank[rank].append(r)
	return by_rank[0] + by_rank[1] + by_rank[2]


## The family names a material carries.
static func families_of(m: int) -> PackedStringArray:
	ensure()
	var out := PackedStringArray()
	for nm in families:
		if family_of[m] & int(families[nm]):
			out.append(nm)
	return out


## Id of the material `e[key]` names, or -1. `owner` names the entry in errors.
static func _ref(e: Dictionary, key: String, owner: Dictionary = {}) -> int:
	if not e.has(key):
		return -1
	var nm: String = e[key]
	if not ids.has(nm):
		var who: Dictionary = owner if not owner.is_empty() else e
		push_error("%s: %s refers to unknown material %s" % [who.get("name", "?"), key, nm])
		return -1
	return ids[nm]


static func _pal_row(e: Dictionary, stage: int, stages: int, life_max: int, burn_life: int) -> Array:
	var c := Color(e.get("color", "#000000"))
	var c2 := Color(e.get("color2", e.get("color", "#000000")))
	var ac := Color(e.get("accent", e.get("color", "#000000")))
	var style := maxi(STYLES.find(e.get("style", "rock")), 0)
	var mixv = e.get("mix", 0.5)
	var mix := 0.5
	if mixv is Array:
		var f := stage / float(maxi(stages - 1, 1))
		mix = lerpf(float(mixv[0]), float(mixv[1]), f)
	else:
		mix = float(mixv)
	var flags := 0
	if bool(e.get("rock", false)):
		flags |= F_ROCK
	if burn_life > 0:
		flags |= F_BURNS
	if bool(e.get("glints", false)):
		flags |= F_GLINTS
	if bool(e.get("sensed", false)):
		flags |= F_SENSED
	return [c, c2, ac, style, mix, float(e.get("grain", 0.25)), flags, life_max, burn_life]


## The renderer's palette: 256 x 4 texels, one column per material id.
##   row 0: color, style (alpha = style / 255)
##   row 1: color2, mix
##   row 2: accent, grain
##   row 3: flags / 255, life_max / 255, burn_life / 255
static func palette_image() -> Image:
	ensure()
	if _palette != null:
		return _palette
	var img := Image.create(256, 4, false, Image.FORMAT_RGBA8)
	for id in 256:
		var row = _pal_rows[id]
		if row == null:
			continue
		var c: Color = row[0]
		var c2: Color = row[1]
		var ac: Color = row[2]
		img.set_pixel(id, 0, Color(c.r, c.g, c.b, row[3] / 255.0))
		img.set_pixel(id, 1, Color(c2.r, c2.g, c2.b, clampf(row[4], 0.0, 1.0)))
		img.set_pixel(id, 2, Color(ac.r, ac.g, ac.b, clampf(row[5], 0.0, 1.0)))
		img.set_pixel(id, 3, Color(row[6] / 255.0, clampi(row[7], 0, 255) / 255.0, clampi(row[8], 0, 255) / 255.0, 1.0))
	_palette = img
	return img


## A material's main colour (for the HUD).
static func color_of(m: int) -> Color:
	ensure()
	var row = _pal_rows[m]
	return Color.WHITE if row == null else row[0]


static func id_of(nm: String) -> int:
	ensure()
	return ids.get(nm, -1)


static func name_of(m: int) -> String:
	ensure()
	return names[m]


static func kind_of(m: int) -> int:
	ensure()
	return kinds[m]


static func dig_rate(m: int) -> float:
	ensure()
	return dig_rates[m]


static func dig_power(m: int) -> float:
	ensure()
	return dig_powers[m]


## The stockpiles a cell of `m` pays into when dug or swallowed (often one, sometimes none).
static func yields_of(m: int) -> PackedInt32Array:
	ensure()
	return yields[m]


## How much a cell of `m` pays into each of its stockpiles, against dirt's 1.
static func worth_of(m: int) -> float:
	ensure()
	return worths[m]


## The first stockpile `m` pays into, or -1.
static func yield_of(m: int) -> int:
	ensure()
	var ys: PackedInt32Array = yields[m]
	return ys[0] if ys.size() > 0 else -1


static func is_hot(m: int) -> bool:
	ensure()
	return hots[m] != 0


static func is_burnable(m: int) -> bool:
	ensure()
	return burns[m] != 0


static func is_corrosive(m: int) -> bool:
	ensure()
	return corrosives[m] != 0


## Open space: nothing, or a gas.
static func is_thin(m: int) -> bool:
	ensure()
	var k := kinds[m]
	return k == K_EMPTY or k == K_GAS


static func sighted_text(m: int) -> String:
	ensure()
	return sighted[m]


## Somewhere a building can go: open air, gas, or a liquid that isn't hot.
static func buildable_in(m: int) -> bool:
	ensure()
	var k := kinds[m]
	return k == K_EMPTY or k == K_GAS or (k == K_LIQUID and hots[m] == 0)


static var _masks := {}
static var _dig_ids := PackedInt32Array()


## Every material that can be dug.
static func dig_ids() -> PackedInt32Array:
	ensure()
	if _dig_ids.is_empty():
		for m in 256:
			if dig_rates[m] > 0.0:
				_dig_ids.append(m)
	return _dig_ids


## A byte per material id, 1 where `what` holds: "open" (buildable_in), "closed"
## (not), "solid" (static or powder), "dig" (diggable) or "dig_no_obsidian". For
## the engine's rectangle queries.
static func mask(what: String) -> PackedByteArray:
	ensure()
	if not _masks.has(what):
		var out := PackedByteArray()
		out.resize(256)
		for m in 256:
			var k := kinds[m]
			var hit := false
			match what:
				"open": hit = buildable_in(m)
				"closed": hit = not buildable_in(m)
				"solid": hit = k == K_STATIC or k == K_POWDER
				"dig": hit = dig_rates[m] > 0.0
				"liquid": hit = k == K_LIQUID
				"worth_liquid": hit = k == K_LIQUID and yield_of(m) >= 0
				"powder": hit = k == K_POWDER
				"dig_no_obsidian": hit = dig_rates[m] > 0.0 and names[m] != "Obsidian"
				"dig_no_hot": hit = dig_rates[m] > 0.0 and names[m] != "Hot rock"
				"dig_no_obsidian_no_hot": hit = dig_rates[m] > 0.0 and names[m] != "Obsidian" and names[m] != "Hot rock"
			out[m] = 1 if hit else 0
		_masks[what] = out
	return _masks[what]
