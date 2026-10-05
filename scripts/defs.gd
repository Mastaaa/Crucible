extends RefCounted
## Shared constants for Crucible: map size, materials, resources and buildings.
## Everything tunable lives here, except the materials themselves: those are in
## data/materials.json (read through materials.gd).

const M = preload("res://scripts/materials.gd")

const W := 768
const H := 5120
# Phase 8b: everything built is S times its v2 size against the cells (sizes, ranges,
# speeds and radii are S times the v2 numbers; amounts counted in cells, S * S times).
# The world is 3x wider and 5x deeper than v2's 256 x 1024, its features 4x bigger.
const S := 10
const GROUND_Y := 200
const TICKS_PER_S := 60
const DT := 1.0 / 60.0
const CELLS_PER_UNIT := 6.0 * S * S   # cells dug or swallowed for one unit of a resource
# Free fall: powders and liquids with open space under them speed up by this
# (cells a second, per second) to at most this (cells a second; 15 a tick at most).
const SIM_FALL_ACCEL := 900.0
const SIM_FALL_MAX := 600.0
# How much closer than "whole map width on screen" the camera normally sits.
const CAMERA_CLOSER := 1.5

# --- Materials --------------------------------------------------------------
# Ids are fixed (see data/materials.json). Test what a cell is with the helpers
# below (is_solid, is_liquid, is_thin), not with id ranges:
#   0 air | 1-5 static | 6 settled dirt | 7-8 powders | 9-10 liquids
#   11-18 steam (eight ageing stages, then it condenses) | 19-28 Phase 5 chemistry
#   29-32 Phase 8 ground (packed dirt, gravel, sand, clay) | 33 mite | 34 hot rock | 35-53 wave 1 (A2)
const AIR := 0
const BEDROCK := 1
const STONE := 2
const GLIMMER := 3
const OBSIDIAN := 4
const BUILDING := 5
const DIRT := 6
const LOOSE_DIRT := 7
const RUBBLE := 8
const WATER := 9
const LAVA := 10
const STEAM := 11
const STEAM_LAST := 18
const FIRE := 19
const SMOKE := 20
const ASH := 21
const COAL := 22
const COAL_CHUNKS := 23
const SULFUR := 24
const SULFUR_GRIT := 25
const FUMES := 26
const GLIMMER_SHARDS := 27
const OBSIDIAN_SHARDS := 28
# Phase 8: mundane ground, told apart by how it holds up and how water wears it.
const PACKED_DIRT := 29
const GRAVEL := 30
const SAND := 31
const CLAY := 32
const MITE := 33          # a mite that's a body (thrown, falling, tumbling): phase 8d
const HOT_ROCK := 34      # the Magma band's rock: phase 9 (needs Coolant Jacket or Ember Brood)
# A2, wave 1 (claude/WAVE1_MATERIALS.md): twelve authored, seven made by reactions.
const SLICK := 35
const SOURWATER := 36
const HUSH := 37
const QUICKMIRE := 38
const FLUX := 39
const FERRITE := 40
const RATTLE := 41
const BLOAT := 42
const GLASS := 43
const RIME := 44
const WISP := 45
const WEFT := 46
const ICE := 47
const SLAG := 48
const SLAG_CRUST := 49
const MIRE_STONE := 50
const SETTING_MIRE := 51
const SWOLLEN_BLOAT := 52
const FERRITE_BAR := 53

static func mat_name(m: int) -> String:
	return M.name_of(m)

static func is_drillable(m: int) -> bool:
	return M.dig_rate(m) > 0.0

static func is_liquid(m: int) -> bool:
	return M.kind_of(m) == M.K_LIQUID

## Open space: air, or a gas (steam, smoke, fumes, flames).
static func is_thin(m: int) -> bool:
	return M.is_thin(m)

## Solid enough to hold a building up or give dirt something to lean on.
static func is_solid(m: int) -> bool:
	var k := M.kind_of(m)
	return k == M.K_STATIC or k == M.K_POWDER

## How fast a material gives way, in cells of depth per second, at full pace.
## The Cutter works at its own fraction of this (faster with Drill Bit).
static func bore_rate(m: int) -> float:
	return M.dig_rate(m)

# --- Stockpile ---------------------------------------------------------------
const R_STONE := 0
const R_GLIMMER := 1
const R_OBSIDIAN := 2
const R_WATER := 3
const R_POWER := 4
const NRES := 5
const RES_NAMES := ["Stone", "Glimmer", "Obsidian", "Water", "Power"]
const RES_COLORS := [Color("#b4b4bd"), Color("#5fe3cb"), Color("#a77be6"), Color("#4ea3f5"), Color("#f5d25a")]
const START_STONE := 60.0
const START_POWER := 20.0
# Safety net against a soft-lock: while the Hub holds less than this much Stone,
# it scrapes up one more every HUB_TRICKLE_S seconds.
const HUB_TRICKLE_BELOW := 12.0
const HUB_TRICKLE_S := 8.0

## Which stockpile a captured cell lands in first (-1: it can't be stockpiled).
static func mat_res(m: int) -> int:
	return M.yield_of(m)

## Every stockpile a captured cell pays into, one unit each per CELLS_PER_UNIT
## cells (Coal: Stone and Power; Sulfur: Stone and Glimmer; Ash: nothing).
static func mat_yields(m: int) -> PackedInt32Array:
	return M.yields_of(m)

## Units one dug or swallowed cell of `m` pays into each of its stockpiles.
static func cell_units(m: int) -> float:
	return M.worth_of(m) / CELLS_PER_UNIT

# --- Buildings ---------------------------------------------------------------
# The structures: the Hub and Crucible (fixed, one each per world), the Node that
# carries the network, and what holds ground up (Brace) or holds it back (Bulkhead).
# Everything that works is a module (scripts/machines/, data/modules/*.json).
const B_HUB := 0
const B_NODE := 1
const B_BULKHEAD := 2
const B_CRUCIBLE := 3
const B_BRACE := 4

const B_NAMES := ["Hub", "Node", "Bulkhead", "Crucible", "Brace"]
const B_LETTERS := ["HUB", "N", "", "", ""]
const B_SIZES := [Vector2i(8, 6) * S, Vector2i(2, 2) * S, Vector2i(2, 2) * S, Vector2i(14, 8) * S,
		Vector2i(1, 1) * S]
const B_HP := [1000.0, 100.0, 200.0, 1000.0, 60.0]
# Cost per building as [stone, glimmer, obsidian, water, power].
const B_COSTS := [[0, 0, 0, 0, 0], [2, 0, 0, 0, 0], [1, 0, 0, 0, 0], [0, 0, 0, 0, 0], [2, 0, 0, 0, 0]]
const B_COLORS := [Color("#f2c14e"), Color("#7cc4ff"), Color("#9aa3b5"), Color("#ffd27a"), Color("#d8c08a")]
const B_BLURBS := [
	"Holds the stockpile and sends every packet.",
	"Extends the network. Links to other Nodes within 160 cells.",
	"A wall with 200 HP. Holds lava for 8 seconds.",
	"The goal. Feed it, light it.",
	"A beam across a gap, rock to rock. Holds up what rests on it, and nothing within 50 cells of either end caves in or crumbles. Built at once from the Hub's Stone; no upkeep.",
]
# Build list: keys 1-3. Only what's unlocked shows; the keys stay put. Modules have their own
# section under it (machines.gd).
const PALETTE := [B_NODE, B_BULKHEAD, B_BRACE]
const PALETTE_KEYS := ["1", "2", "3"]
const STARTING_KIT := [B_NODE, B_BULKHEAD]

# --- Network -----------------------------------------------------------------
const RELAY_RANGE := 16.0 * S
const LINK_RANGE := 8.0 * S
const HUB_PACKETS_PER_S := 6.0
const PACKET_SPEED := 60.0 * S

# --- Power ------------------------------------------------------------------------
# Power is the Hub's stock. Modules draw on it directly while a Node or the Hub is in reach
# (MU.networked) and generators (Windmill) add to it; only the Crucible's charge still travels
# by packet.
const HUB_POWER_PER_S := 0.2        # the floor: the Hub always makes this much
const LAMP_POWER_PER_S := 0.1
const HUB_POWER_CAP := 100.0        # the Hub's power store
const SPRING_CELLS_PER_S := 8.0 * S * S   # a spring tops its aquifer up by this much water
const CAVE_SPRING_CHANCE := 0.4

## Power a dug cell of `m` costs (the Cutter's base rate, before depth and Drill Bit).
static func power_per_cell(m: int) -> float:
	return M.dig_power(m)

## Nodes pass the network on: the Hub and every Node.
static func is_relay_type(t: int) -> bool:
	return t == B_HUB or t == B_NODE

## Nodes drown, steam scalds them and lava destroys them.
static func is_node(t: int) -> bool:
	return t == B_NODE

## How far a relay links to other relays (a link holds when either end reaches).
static func relay_range(_t: int) -> float:
	return RELAY_RANGE

## Everything but a Brace draws on the network through a link.
static func needs_link(t: int) -> bool:
	return t != B_BRACE

# --- Machines ----------------------------------------------------------------
# Drill Shaft research lengthens the Winch's cable: the depth (in rows below the surface of
# the world) the rig may go to by level. The last reaches the bedrock shell over the chamber.
const SHAFT_REACHES := [150, 300, 500, 800, 1200, 1650, 2250, 2950, 3650, 4350]
# Mites were the Warren's: the engine still has creature bodies, which shatter above this fall speed.
const CREATURE_FALL_V := 480.0
# Settling: when a building digs a cell out, the solid cells round it hold still
# this long (no weathering, erosion or loosening; held powder doesn't fall), so
# there's time to shore the hole up. Liquids aren't held.
const SETTLE_S := 20.0
const SETTLE_RADIUS := S
# Collapse (phase 8): a ceiling wider than its material's span (see "span" and
# "overhang" in the data file) caves in from the middle until it's an arch. The
# engine sweeps COLLAPSE_ROWS rows a tick, bottom up (the whole map every 10 ticks).
const COLLAPSE_ROWS := 512
const CAVE_ALERT_CELLS := 12 * S     # cells down in a couple of seconds before it's called a cave-in (a front S times wider)
# Brace: a beam S cells thick across a gap, rock at both ends, built at once.
const BRACE_MAX := 16 * S            # longest gap it spans
const BRACE_THICK := S               # how thick the beam is, where the gap allows
const BRACE_HOLD := 5 * S            # rock within this of either anchor never caves in, weathers or loosens
const BRACE_DAMP_R := 12.0 * S       # with Tremor Dampers, tremors spare stone this close to a Brace
const SENSE_RADIUS := 10.0 * S  # a Cutter feels hidden pockets this far off
# Light and fog. A block is explored when it's lit and within sight of one of your
# buildings; after that it shows live whenever it's lit, and as last seen (dimmed)
# when it isn't. Light fades a cell per cell of air, twice that through liquid and
# five times through rock (see "opacity" in data/materials.json). Radii in cells.
const LIGHT_HUB := 22.0 * S
const LIGHT_LAMP := 20.0 * S
const LIGHT_PILOT := 3.0 * S    # every module: enough to see it work
const LIGHT_CRUCIBLE := 10.0 * S
const SUN_LIGHT := 12 * S       # the sky, and straight down open shafts
const LIGHT_VIEW_PAD := 256     # explored ground this far past the screen stays lit (live)
const SIGHT_HUB := 24.0 * S
const SIGHT_NODE := 12.0 * S
const SIGHT_MACHINE := 10.0 * S # a lit Lamp watches its whole pool of light
const REVEAL_START := 20.0 * S  # known round the Hub from the start
# Anchoring: a building with nothing solid (or no held-up building) touching it falls.
const FALL_ACCEL := 60.0 * S    # cells a second, per second
const FALL_MAX := 40.0 * S      # cells a second
const FALL_WATER_MAX := 10.0 * S  # fastest a building sinks through liquid
const PLACE_SNAP := 5 * S       # a ghost that's floating or poking into rock snaps to a legal spot this near
const LAVA_DPS := 25.0
const STEAM_DPS := 5.0          # to Nodes only

# --- Research -------------------------------------------------------------------
const LAB_POWER_PER_S := 2.0        # the most one Lab turns into research a second
# Tiers open with a discovery. Tier 1 is open from the start.
const TIER_DISCOVERY := ["", "", "the first Glimmer mined", "the first lava seen", "the Crucible in view"]
const TIER_FOUND := ["", "", "Glimmer", "Lava", "The Crucible"]

# The tech tree. "needs": parent techs (all of them, or any one when "any" is set);
# "mats": materials the Labs must be sent, [stone, glimmer, obsidian, water, power];
# "building": what it adds to the build list; "module": a module (data/modules) it unlocks;
# "phase": the build that implements it, for techs whose content doesn't exist yet (they show
# but can't be picked). Upgrades have "levels" instead of one cost: each level is researched in
# turn, costs more than the last and may want a later tier open.
# The A3 cut left a short tree (the retired buildings' techs went with them); A4 and A5 grow it
# around goods.
const TECHS := [
	{"id": "lamp", "name": "Lamp", "tier": 1, "needs": [], "power": 120, "module": "lamp",
		"text": "A module that lights 200 cells round it for 0.1 power/s. Everywhere else underground stays dark."},
	{"id": "piston", "name": "Piston", "tier": 1, "needs": [], "power": 150, "module": "piston",
		"text": "A bolted module that pushes whatever is joined to its mechanical face 20 cells out along it, and back."},
	{"id": "gantry", "name": "Gantry", "tier": 1, "needs": [], "power": 200, "module": "gantry",
		"text": "A bolted rail that carries whatever is joined to its mechanical face up to 80 cells along it."},
	{"id": "turntable", "name": "Turntable", "tier": 1, "needs": ["piston"], "power": 260, "module": "turntable",
		"text": "A pinned hub that swings whatever is joined to its mechanical faces round, a quarter turn at a time or without stopping."},
	{"id": "laser", "name": "Laser Excavator", "tier": 2, "needs": [], "power": 900, "mats": [0, 12, 0, 0, 0], "module": "laser",
		"text": "A module with a one-pixel beam that strips ore off a wall without cutting a tunnel: it takes the first solid cell in its beam if that is ore, and can leave Stone in its place."},
	{"id": "thumper", "name": "Thumper", "tier": 1, "needs": [], "power": 250, "module": "thumper",
		"text": "A block hung from a Winch that is lifted and dropped: each hard landing blasts a 90 degree cone below it and breaks rock the Cutter can't."},
	{"id": "chute", "name": "Chute", "tier": 1, "needs": [], "power": 120, "module": "chute",
		"text": "A bolted pipe: powder passed into one end comes out of the other, so a line of them carries it across a gap."},
	{"id": "conveyor", "name": "Conveyor", "tier": 1, "needs": ["chute"], "power": 220, "module": "conveyor",
		"text": "A bolted belt that carries loose powder and loose rigid bodies lying on it along its length, and lets them into a Tank or Funnel at the end."},
	{"id": "bus_hopper", "name": "Bus Hopper", "tier": 1, "needs": ["chute"], "power": 300, "module": "bus_hopper",
		"text": "A bolted module that banks loose pixels as goods, and spits a banked good (or Water) back out as pixels."},
	{"id": "drone_cage", "name": "Drone Cage", "tier": 2, "needs": ["conveyor"], "power": 900, "mats": [0, 8, 0, 0, 0], "module": "drone_cage",
		"text": "A bolted cage of drones that fly out, lift loose powder from a square of ground round it and bring it back, to pass on into a Tank or Funnel."},
	{"id": "macerator", "name": "Macerator", "tier": 2, "needs": [], "power": 700, "module": "macerator",
		"text": "A bolted module with an open mouth that grinds loose rigid bodies (a collapsed slab, a Press's block) to powder."},
	{"id": "press", "name": "Press", "tier": 2, "needs": [], "power": 700, "module": "press",
		"text": "A bolted module that squeezes powder into a solid block (a rigid body): Rubble becomes Stone, Loose dirt becomes Dirt."},
	{"id": "brace", "name": "Brace", "tier": 1, "needs": [], "power": 180, "building": B_BRACE,
		"text": "A beam across a gap, rock to rock (up to 160 cells). It props what rests on it and holds rock within 50 cells of each end."},
	{"id": "tremor_dampers", "name": "Tremor Dampers", "tier": 4, "needs": ["brace"], "power": 1200,
		"mats": [0, 0, 20, 0, 0], "text": "Tremors crumble no stone within 120 cells of a Brace."},
	# Upgrades.
	{"id": "drill_bit", "name": "Drill Bit", "tier": 1, "needs": [],
		"text": "The Cutter digs 50% faster a level, and each level costs 20% more power per cell. Harder ground opens up: Clay and Stone first, Hot rock at level 4.",
		"levels": [{"tier": 1, "power": 180}, {"tier": 1, "power": 390}, {"tier": 2, "power": 1040, "mats": [0, 16, 0, 0, 0]},
			{"tier": 2, "power": 2000, "mats": [0, 32, 0, 0, 0]}, {"tier": 3, "power": 3600, "mats": [0, 48, 8, 0, 0]}]},
	{"id": "drill_shaft", "name": "Drill Shaft", "tier": 1, "needs": [],
		"text": "The Winch's cable lengthens: the rig reaches 300, 500, 800, 1200, 1650, 2250, 2950, 3650, then 4350 rows (the bedrock over the chamber). Deep rows cost more power, and past about 2800 rows the rock is hot.",
		"levels": [{"tier": 1, "power": 120}, {"tier": 1, "power": 240}, {"tier": 1, "power": 450}, {"tier": 1, "power": 780},
			{"tier": 2, "power": 1680, "mats": [0, 20, 0, 0, 0]}, {"tier": 2, "power": 2600, "mats": [0, 40, 0, 0, 0]},
			{"tier": 3, "power": 3800, "mats": [0, 60, 0, 0, 0]}, {"tier": 3, "power": 5200, "mats": [0, 60, 10, 0, 0]},
			{"tier": 3, "power": 7200, "mats": [0, 80, 20, 0, 0]}]},
	{"id": "tank_size", "name": "Tank Size", "tier": 1, "needs": [],
		"text": "Tanks hold more: half, then the full, double and four times what their hollow packs.",
		"levels": [{"tier": 1, "power": 150}, {"tier": 2, "power": 520, "mats": [0, 12, 0, 0, 0]},
			{"tier": 3, "power": 1100, "mats": [0, 28, 0, 0, 0]}]},
]

## Index of a tech in TECHS by id, or -1.
static func tech_index(id: String) -> int:
	for i in TECHS.size():
		if TECHS[i]["id"] == id:
			return i
	return -1

# --- Crucible ----------------------------------------------------------------
# Indexed like the stockpile: [stone, glimmer, obsidian, water, power].
const RECIPE := [0, 32, 48, 64, 0]
const CRUCIBLE_PACKETS_PER_S := 1.5  # phase 10: a longer charge to hold
const CRUCIBLE_STALL_S := 5.0
const CRUCIBLE_DRAIN_PER_S := 0.01
const CRUCIBLE_POWER_PER_S := 4.0   # drawn while charging (phase 9)
const CRUCIBLE_POWER_RESERVE := 20.0
const TREMOR_EVERY_S := 15.0
const TREMOR_CELLS := 200 * S * S

# --- World layers (depth bands, in cells) --------------------------------------
const LAYERS := [
	{"name": "Surface", "top": 0, "bottom": 200, "color": Color("#6d7bb8")},
	{"name": "Topsoil", "top": 200, "bottom": 1500, "color": Color("#8a5f3c")},
	{"name": "Stone", "top": 1500, "bottom": 3000, "color": Color("#7d7f8c")},
	{"name": "Magma", "top": 3000, "bottom": 4500, "color": Color("#b0503a")},
	{"name": "Chamber", "top": 4500, "bottom": 5120, "color": Color("#d9a441")},
]

# --- Heat (phase 9) ---------------------------------------------------------------
const HOT_TOP := 3000               # hot rock from here down (wobbling by up to 24)

# --- Temperature (A1) --------------------------------------------------------------
# Every cell has a temperature (degrees) that the engine leaks between neighbours
# and pulls back toward the depth's ambient (data/materials.json has the material
# side). The ambient climbs with depth and steps up to the Magma band's just above
# HOT_TOP's wobble, so hot rock stays hot rock (it cools to stone under 250) and
# stone stays stone (it heats to hot rock over 800: only next to lava).
const AMBIENT_SURFACE := 15
const AMBIENT_TOPSOIL_BOTTOM := 30
const AMBIENT_STONE_BOTTOM := 90    # under water's boiling point: the Stone band's pockets keep
const AMBIENT_MAGMA := 550
const AMBIENT_RAMP := 50            # rows over which the Stone band's ambient climbs to the Magma band's
const AMBIENT_RAMP_END := HOT_TOP - 30
const TEMP_EVERY := 8               # ticks between temperature passes
const TEMP_SINK_EVERY := 1          # passes between pulls toward the ambient
const TEMP_SINK := 1.0 / 256        # the fraction of the gap each pull closes (none within 32 degrees)
const BENCH_AMBIENT := 20           # the lab bench's flat ambient

static func ambient_at(y: int) -> int:
	if y < GROUND_Y:
		return AMBIENT_SURFACE
	var topsoil_end: int = LAYERS[1]["bottom"]
	if y < topsoil_end:
		return int(lerpf(AMBIENT_SURFACE, AMBIENT_TOPSOIL_BOTTOM, (y - GROUND_Y) / float(topsoil_end - GROUND_Y)))
	var ramp_start := AMBIENT_RAMP_END - AMBIENT_RAMP
	if y < ramp_start:
		return int(lerpf(AMBIENT_TOPSOIL_BOTTOM, AMBIENT_STONE_BOTTOM, (y - topsoil_end) / float(ramp_start - topsoil_end)))
	if y < AMBIENT_RAMP_END:
		return int(lerpf(AMBIENT_STONE_BOTTOM, AMBIENT_MAGMA, smoothstep(0.0, 1.0, (y - ramp_start) / float(AMBIENT_RAMP))))
	return AMBIENT_MAGMA

## The ambient per row, for the engine (a flat one at `flat` degrees on the bench).
static func ambient_rows(flat := -1) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(H)
	for y in H:
		out[y] = flat if flat >= 0 else ambient_at(y)
	return out

static func temp_params() -> Dictionary:
	return {"every": TEMP_EVERY, "sink_every": TEMP_SINK_EVERY, "sink": TEMP_SINK}

# --- Hazards -------------------------------------------------------------------
# The random-sample passes check more cells on the bigger map (15x v2's area), so
# each cell is checked as often as before.
# Dirt erosion: random samples every other tick across the Topsoil band.
const ERODE_SAMPLES := 15
# Weathering: cells checked a tick, anywhere on the map, for a ceiling that
# crumbles (see "crumble" in the data file). Stone crumbles about a hundred times
# slower than dirt.
const WEATHER_SAMPLES := 720
# Water wear: cells checked a tick for one touching water that washes ("wash" in the
# data file). With dirt's 0.08, a wet dirt face turns to sand in about 20 minutes.
const WASH_SAMPLES := 720
const FIRE_DPS := 6.0               # to a building with half its outline in flames
const CORRODE_DPS := 1.0            # to a building with CORRODE_FULL corrosive cells nearby
const CORRODE_REACH := 3 * S        # how far from a building corrosion counts
const CORRODE_FULL := 12.0 * S * S
# Repairs: a built building under REPAIR_BELOW of its HP asks the network for one
# Stone, which puts back REPAIR_HP of its HP.
const REPAIR_BELOW := 0.6
const REPAIR_HP := 0.4
# The Hub (phase 10): hurt like any building, and the run is lost when it goes. It
# patches itself with a Stone of its own at most every HUB_FIX_S seconds, and warns
# once under HUB_WARN of its HP.
const HUB_FIX_S := 10.0
const HUB_WARN := 0.35
# Links (each building's line to the relay it draws through) wear down too; a
# broken one is out of the network until a Stone arrives to mend it.
const LINK_HP := 20.0
const LINK_FIRE_DPS := 4.0          # with 4 or more burning cells on the line
const LINK_CORRODE_DPS := 0.25      # with 8 or more corrosive cells on or beside it
const LINK_LAVA_DPS := 20.0
const LINK_REPAIR_BELOW := 0.5
# Blasts: the sandbox brush's. Power is what
# a material's durability must not beat (stone 5, glimmer 6, obsidian 10).
const BLAST_RADIUS := 6.0 * S
const BLAST_POWER := 6
const BLAST_DAMAGE := 10.0          # per point of power, to a building at the centre
const LINK_BLAST := 3.0             # per point of power, to a link through the centre
# Rigid bodies (phase 8c). A ceiling that caves in breaks off in pieces that fall as
# bodies (stretches narrower than 4 cells still crumble). A body shatters into what
# its ground crumbles into when it hits something faster than its toughness, and
# turns back into ground once it comes to rest. Speeds in cells a second.
const BODY_SHATTER := 90.0          # every body's toughness...
const BODY_SHATTER_PER_DUR := 20.0  # ... plus this per point of its ground's durability (dirt 130: a
                                    # drop of 9 cells; stone 190: 20)
const BODY_MIN_CELLS := 12          # a piece smaller than this crumbles instead
const PIECE_WIDTH := Vector2i(24, 64)   # how wide a piece breaking off a ceiling is, in cells
const PIECE_THICK := Vector2i(6, 20)    # ... and how deep
const PIECE_ROOM := 2 * S           # a ceiling over a lower gap than this (a crawlspace) crumbles instead
# Crushing: an impact of at least CRUSH_MIN_V hurts the building it lands on by
# CRUSH_DAMAGE per cell of the body per cell a second; a body crossing a link wears
# it by CRUSH_LINK the same way (once a crossing).
const CRUSH_MIN_V := 60.0
const CRUSH_DAMAGE := 6.0e-4        # an 800-cell slab at 300: 144
const CRUSH_LINK := 1.0e-4          # ... and 24 to a link
# Falling buildings are hurt landing: nothing up to FALL_SAFE_V, then up to
# FALL_HURT of their HP at FALL_MAX.
const FALL_SAFE_V := 200.0         # a fall of about 33 cells
const FALL_HURT := 0.75

## What the engine's bodies are set up with (sim_factory).
static func body_params() -> Dictionary:
	return {"accel": SIM_FALL_ACCEL, "max_speed": SIM_FALL_MAX, "shatter": BODY_SHATTER,
			"shatter_per_durability": BODY_SHATTER_PER_DUR, "crush_min": CRUSH_MIN_V,
			"min_cells": BODY_MIN_CELLS, "piece_min": PIECE_WIDTH.x, "piece_max": PIECE_WIDTH.y,
			"thick_min": PIECE_THICK.x, "thick_max": PIECE_THICK.y, "piece_room": PIECE_ROOM, "pieces": true,
			"creature_shatter": CREATURE_FALL_V}
