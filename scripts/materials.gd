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
static var yields: Array = []           # per id: PackedInt32Array of stockpiles
static var hots := PackedByteArray()
static var burns := PackedByteArray()
static var corrosives := PackedByteArray()
static var sighted := PackedStringArray()
static var ids := {}                    # name -> first id
static var sim_materials: Array = []    # for CrucibleSim.configure
static var sim_reactions: Array = []
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
	yields.resize(256)
	for i in 256:
		yields[i] = PackedInt32Array()
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
		for s in stages:
			var mid := id + s
			names[mid] = e.get("name", "Unknown")
			kinds[mid] = kind
			dig_rates[mid] = float(e.get("dig_rate", 0.0))
			dig_powers[mid] = float(e.get("dig_power", 0.2))
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
				"expires_to": _ref(e, "expires_to"),
				"expires_alt": _ref(e, "expires_alt"),
				"alt_chance": float(e.get("alt_chance", 0.0)),
				"light": int(e.get("light", 0)),
				"opacity": int(e.get("opacity", 0)),
				"structure": bool(e.get("structure", false)),
				"span": int(e.get("span", 0)),
				"overhang": int(e.get("overhang", 0)),
				"cohesive": bool(e.get("cohesive", false)),
				"wash_to": _ref(e, "wash_to"),
				"wash": float(e.get("wash", 0.0)),
			}
			if e.has("cave"):
				m["cave"] = float(e["cave"])
			if not burn.is_empty():
				m["burn_life"] = int(burn.get("life", 60))
				m["ignite"] = float(burn.get("ignite", 0.05))
				m["burn_speed"] = float(burn.get("speed", 0.1))
				m["burns_to"] = _ref(burn, "to", e)
				m["burn_gas"] = _ref(burn, "gas", e)
				m["gas_chance"] = float(burn.get("gas_chance", 0.0))
				m["flame_chance"] = float(burn.get("flame_chance", 0.0))
			if e.has("age_chance"):
				m["age_chance"] = int(e["age_chance"])
				m["age_to"] = mid + 1 if s < stages - 1 else _ref(e, "condenses_to")
			sim_materials.append(m)
			_pal_rows[mid] = _pal_row(e, s, stages, int(life[1]), int(m.get("burn_life", 0)))
	for rx: Dictionary in data.get("reactions", []):
		var w: Array = rx.get("when", [])
		var b: Array = rx.get("becomes", [])
		if w.size() != 2 or b.size() != 2:
			push_error("Reaction needs two materials in 'when' and two in 'becomes': %s" % rx)
			continue
		sim_reactions.append({
			"a": ids.get(w[0], 0), "b": ids.get(w[1], 0),
			"out_a": ids.get(b[0], 0), "out_b": ids.get(b[1], 0),
			"chance": float(rx.get("chance", 1.0)),
		})


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
