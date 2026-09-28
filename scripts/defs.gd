extends RefCounted
## Shared constants for Crucible: map size, materials, resources and buildings.
## Everything tunable lives here, except the materials themselves: those are in
## data/materials.json (read through materials.gd).

const M = preload("res://scripts/materials.gd")

const W := 256
const H := 1024
const GROUND_Y := 40
const TICKS_PER_S := 60
const DT := 1.0 / 60.0
const CELLS_PER_UNIT := 6.0     # v2 scale: 3-wide channels, so a unit is fewer cells
# How much closer than "whole map width on screen" the camera normally sits.
const CAMERA_CLOSER := 1.5

# --- Materials --------------------------------------------------------------
# Ids are fixed (see data/materials.json). Test what a cell is with the helpers
# below (is_solid, is_liquid, is_thin), not with id ranges:
#   0 air | 1-5 static | 6 settled dirt | 7-8 powders | 9-10 liquids
#   11-18 steam (eight ageing stages, then it condenses) | 19-28 Phase 5 chemistry
#   29-32 Phase 8 ground (packed dirt, gravel, sand, clay)
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
## The Drill works at DRILL_SPEED of this (faster with Drill Bit), a Borer at
## BORER_SPEED.
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

# --- Buildings ---------------------------------------------------------------
const B_HUB := 0
const B_CONDUIT := 1
const B_DRILL := 2
const B_HOPPER := 3
const B_SPOUT := 4
const B_BULKHEAD := 5
const B_FLOODGATE := 6
const B_CRUCIBLE := 7
const B_WATERWHEEL := 8
const B_CACHE := 9
const B_LAMP := 10
const B_LAB := 11
const B_THUMPER := 12
const B_BORER := 13
const B_MAST := 14
const B_WARREN := 15
const B_STRUT := 16

const B_NAMES := ["Hub", "Conduit", "Drill", "Hopper", "Spout", "Bulkhead", "Floodgate", "Crucible",
		"Waterwheel", "Cache", "Lamp", "Lab", "Thumper", "Borer", "Relay Mast", "Warren", "Strut"]
const B_LETTERS := ["HUB", "C", "D", "V", "S", "", "F", "", "", "K", "L", "LAB", "T", "B", "M", "W", ""]
const B_SIZES := [Vector2i(8, 6), Vector2i(2, 2), Vector2i(3, 3), Vector2i(3, 2),
		Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 6), Vector2i(14, 8),
		Vector2i(3, 5), Vector2i(3, 3), Vector2i(2, 2), Vector2i(4, 3),
		Vector2i(2, 2), Vector2i(3, 3), Vector2i(2, 3), Vector2i(5, 3), Vector2i(1, 1)]
const B_HP := [1000.0, 100.0, 100.0, 100.0, 100.0, 200.0, 200.0, 1000.0, 100.0, 150.0, 60.0, 120.0,
		80.0, 150.0, 120.0, 120.0, 60.0]
# Cost per building as [stone, glimmer, obsidian, water, power].
const B_COSTS := [[0, 0, 0, 0, 0], [2, 0, 0, 0, 0], [5, 0, 0, 0, 0], [3, 0, 0, 0, 0],
		[3, 2, 0, 0, 0], [1, 0, 0, 0, 0], [3, 1, 0, 0, 0], [0, 0, 0, 0, 0],
		[6, 0, 0, 0, 0], [8, 0, 0, 0, 0], [2, 0, 0, 0, 0], [8, 0, 0, 0, 0],
		[3, 0, 0, 0, 0], [14, 0, 0, 0, 0], [4, 1, 0, 0, 0], [10, 0, 0, 0, 0], [2, 0, 0, 0, 0]]
const B_COLORS := [Color("#f2c14e"), Color("#7cc4ff"), Color("#ff9a52"), Color("#5fd1b0"),
		Color("#5aa9ff"), Color("#9aa3b5"), Color("#c7a2ff"), Color("#ffd27a"),
		Color("#8fd3ff"), Color("#e2b86a"), Color("#fff0a0"), Color("#e59ad8"),
		Color("#ff7a6b"), Color("#f0a04b"), Color("#9ad8ff"), Color("#c9a36b"), Color("#d8c08a")]
const B_BLURBS := [
	"Holds the stockpile and sends every packet.",
	"Extends the network. Links to other Conduits within 16 cells.",
	"Bores a 3-wide shaft straight down from beside the Hub and banks what it removes. Drill Bit and Drill Shaft research make it faster and deeper.",
	"Swallows loose material that falls into its mouth.",
	"Releases stockpiled Water, 6 cells per packet.",
	"A wall with 200 HP. Holds lava for 8 seconds.",
	"A Bulkhead that opens and closes.",
	"The goal. Feed it, light it.",
	"Makes power from water falling through it, in at the top and out of the bottom.",
	"Stores power and materials at the front. Serves nearby machines first; nearby digging banks here.",
	"Lights 20 cells round it while it has power. Rock casts shadows.",
	"Turns power into progress on the tech picked in the Research tab (T). Each Lab adds up to 2 power/s.",
	"Goes off every few seconds, cratering the ground under it and throwing itself up. Drag it where you want it. What it breaks flies as rubble for Hoppers to catch.",
	"Grinds a 3-wide tunnel the way it's pointed and follows it, until its power runs out or it meets something it can't cut. Turn it any time.",
	"A Conduit on a mast: links other relays within 28 cells.",
	"A colony of mites that hollows out a chamber over it, then tunnels toward the marker you set in its panel and digs out a small circle there. They go their own way getting there.",
	"A beam across a gap, rock to rock. Holds up what rests on it, and nothing within 5 cells of either end caves in or crumbles. Built at once from the Hub's Stone; no upkeep.",
]
# Build list: keys 1-9, 0, then letters. Only what's unlocked shows; the keys stay put.
const PALETTE := [B_CONDUIT, B_THUMPER, B_HOPPER, B_BULKHEAD, B_LAB, B_SPOUT, B_FLOODGATE,
		B_WATERWHEEL, B_CACHE, B_LAMP, B_BORER, B_MAST, B_WARREN, B_STRUT]
const PALETTE_KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "B", "M", "G", "X"]
const STARTING_KIT := [B_CONDUIT, B_HOPPER, B_BULKHEAD, B_LAB]

# --- Network -----------------------------------------------------------------
const RELAY_RANGE := 16.0
const MAST_RANGE := 28.0
const LINK_RANGE := 8.0
const HUB_PACKETS_PER_S := 6.0
const CACHE_PACKETS_PER_S := 4.0
const GEN_PACKETS_PER_S := 2.0
const PACKET_SPEED := 60.0

# --- Power ------------------------------------------------------------------------
const HUB_POWER_PER_S := 2.0        # the floor: the Hub always makes this much
const POWER_RESERVE := 10.0         # what each powered machine holds
const HOPPER_POWER_PER_CELL := 0.02
const SPOUT_POWER_PER_PACKET := 1.0
const GATE_POWER := 1.0
const LAMP_POWER_PER_S := 0.1
const WHEEL_POWER_PER_CELL := 0.08
const WHEEL_CELLS_PER_S := 25.0     # most water a Waterwheel passes a second (2 power/s)
const GEN_BUFFER := 20.0            # power a generator holds before the rest goes to the Hub
const CACHE_CAP := 60.0
const CACHE_TOPUP := [30.0, 0.0, 0.0, 0.0, 60.0]   # what the network keeps a Cache stocked with
const CACHE_BANK_RANGE := 24.0      # digging this close to a Cache banks into it
const SPRING_CELLS_PER_S := 8.0     # a Waterwheel under a spring makes about 0.6 power/s
const CAVE_SPRING_CHANCE := 0.4
const HUB_POWER_CAP := 100.0        # the Hub's own power store; Caches hold more out at the front

## Power a Drill spends to remove one cell of `m`.
static func power_per_cell(m: int) -> float:
	return M.dig_power(m)

## Buildings that run on power.
static func uses_power(t: int) -> bool:
	return t == B_DRILL or t == B_HOPPER or t == B_SPOUT or t == B_FLOODGATE or t == B_LAMP or t == B_LAB \
			or t == B_THUMPER or t == B_BORER or t == B_WARREN

## Relays pass the network on: the Hub, Conduits and Relay Masts.
static func is_relay_type(t: int) -> bool:
	return t == B_HUB or t == B_CONDUIT or t == B_MAST

## Conduits and Masts: they drown, steam scalds them and lava destroys them.
static func is_conduit(t: int) -> bool:
	return t == B_CONDUIT or t == B_MAST

## How far a relay links to other relays (a link holds when either end reaches).
static func relay_range(t: int) -> float:
	return MAST_RANGE if t == B_MAST else RELAY_RANGE

## Everything but a Strut draws on the network through a link.
static func needs_link(t: int) -> bool:
	return t != B_STRUT

## Things that move on their own: their light, sight and links follow them.
static func is_mover(t: int) -> bool:
	return t == B_THUMPER or t == B_BORER

# --- Machines ----------------------------------------------------------------
# The Drill: one, fixed beside the Hub from the start, boring a 3-wide shaft
# straight down. Drill Bit levels make it faster (and dearer per cell), Drill
# Shaft levels deeper; the last reaches the bedrock shell over the chamber.
const DRILL_SPEED := 1.0 / 8.0      # of full pace, before any Drill Bit
const DRILL_BIT_SPEED := 1.5        # per Drill Bit level
const DRILL_BIT_POWER := 1.2        # power per cell, per Drill Bit level
const DRILL_REACHES := [30, 60, 100, 160, 240, 330, 450, 590, 730, 870]   # by Drill Shaft level
const DRILL_DEEP_ROWS := 300.0      # power per cell goes up by its base every this many rows down
const DRILL_SCAN_ROWS := 96         # rows of channel a Drill looks over for loose fill in a tick
const DRILL_REACH := 12             # a Drill placed by a test script (not the fixed one)
# Thumper: blasts under itself on a timer and is thrown up by it. Indexed by
# upgrade level (Thumper Charge, Blast Radius, Efficiency, Rhythm).
const THUMP_POWERS := [3, 5, 6, 8, 10]      # beats dirt, coal and sulfur; stone 5, glimmer 6, obsidian 10
const THUMP_RADII := [3.5, 4.5, 5.5, 6.5]
const THUMP_COSTS := [1.5, 1.1, 0.8, 0.55]  # power per blast
const THUMP_INTERVALS := [6.0, 4.5, 3.4, 2.5]
const THUMP_DEPTH := 1               # the charge goes off this many cells under it
const THUMP_LAUNCH := 20.0          # cells/s up off a blast, plus 2 per point of blast power
const THUMP_DRIFT := 2.5            # most sideways speed a blast adds, cells/s: it lands in or by its crater
const DRAG_SPEED := 45.0            # fastest a dragged Thumper follows the cursor, cells/s
const FLY_WATER_MAX := 10.0         # fastest anything sinks through liquid
# Borer: grinds the rock in front of it at BORER_SPEED of full pace, moves into
# the space, runs on its reserve out past the network.
const BORER_SPEED := 0.5
const BORER_MOVE_PER_S := 8.0       # cells a second through open space
const BORER_MOVE_POWER := 0.02      # power per cell moved
const BORER_RESERVES := [30.0, 50.0, 80.0, 120.0]   # by Borer Cells level
# Warren (phase 7): its mites dig a half-circle chamber over it, then tunnel toward
# its marker and hollow out a small circle there, hauling each cell home to bank.
# Hard Teeth scales the chamber, the circle and the marker's range by WARREN_TEETH_SCALE.
const WARREN_DOME_R := 6.0           # the chamber over it, from the middle of its floor line
const WARREN_MARKER_RANGE := 32.0    # furthest a marker can sit from it
const WARREN_MARKER_R := 3.0         # the circle dug out at the marker
const WARREN_TUNNEL_SLACK := 8.0     # furthest off the straight line to the marker they'll wander
const WARREN_WOBBLE := 3.0           # how much each cell's quirk counts against its distance to the marker
const WARREN_DETOUR := 4.0           # furthest back from their nearest point to the marker they'll dig to get round something
const WARREN_TEETH_SCALE := 1.5
const WARREN_MITES := 3
const WARREN_MITES_EMBER := 5
const WARREN_BREED_S := 20.0         # a replacement mite every this long
const WARREN_BREED_COST := 1.0       # Stone, taken from the Hub or a Cache like a blueprint
const WARREN_POWER_FRAC := 0.5       # power per cell dug, of the Drill's base rate
const WARREN_REACH_MARGIN := 3       # mites path through open cells this far outside the zone
const MITE_SPEED := 0.25             # of full pace, digging one cell
const MITE_MOVE_PER_S := 6.0         # cells a second along a surface
const MITE_DROWN_S := 5.0            # under liquid this long and it drowns
const MITE_CHOKE_S := 5.0            # in fumes this long and it chokes
const MITE_BURN_S := 3.0             # alight this long, running and lighting what it brushes, then dead
const MITE_SOFT := [DIRT, LOOSE_DIRT, RUBBLE, COAL_CHUNKS, ASH, SAND, GRAVEL]   # Tier 1
const MITE_HARD := [STONE, GLIMMER, COAL, GLIMMER_SHARDS, OBSIDIAN_SHARDS, PACKED_DIRT, CLAY]   # added by Hard Teeth
# Settling: when a building digs a cell out, the solid cells round it hold still
# this long (no weathering, erosion or loosening; held powder doesn't fall), so
# there's time to shore the hole up. Liquids aren't held.
const SETTLE_S := 20.0
const SETTLE_RADIUS := 1
# Collapse (phase 8): a ceiling wider than its material's span (see "span" and
# "overhang" in the data file) caves in from the middle until it's an arch. The
# engine sweeps COLLAPSE_ROWS rows a tick, bottom up (the whole map every 8 ticks).
const COLLAPSE_ROWS := 128
const CAVE_ALERT_CELLS := 12         # cells down in a couple of seconds before it's called a cave-in
# Strut: a 1-cell beam across a gap, rock at both ends, built at once.
const STRUT_MAX := 16                # longest gap it spans
const STRUT_HOLD := 5                # rock within this of either anchor never caves in, weathers or loosens
const STRUT_DAMP_R := 12.0           # with Tremor Dampers, tremors spare stone this close to a Strut
const SENSE_RADIUS := 10.0      # drills feel hidden pockets this far off
const SENSOR_RANGE := 16.0      # how far a Spout or Floodgate sensor can sit from it
# Light and fog. A block is explored when it's lit and within sight of one of your
# buildings; after that it shows live whenever it's lit, and as last seen (dimmed)
# when it isn't. Light fades a cell per cell of air, twice that through liquid and
# five times through rock (see "opacity" in data/materials.json). Radii in cells.
const LIGHT_HUB := 22.0
const LIGHT_LAMP := 20.0
const LIGHT_PILOT := 3.0        # every machine and Drill head: enough to see it work
const LIGHT_CRUCIBLE := 10.0
const SUN_LIGHT := 12           # the sky, and straight down open shafts
const LIGHT_VIEW_PAD := 64      # explored ground this far past the screen stays lit (live)
const SIGHT_HUB := 24.0
const SIGHT_CONDUIT := 12.0
const SIGHT_MACHINE := 10.0     # a lit Lamp watches its whole pool of light
const REVEAL_START := 20.0      # known round the Hub from the start
const REVEAL_DIG := 6.0         # a Drill knows the rock round its head as it reaches
# Anchoring: a building with nothing solid (or no held-up building) touching it falls.
const FALL_ACCEL := 60.0        # cells a second, per second
const FALL_MAX := 40.0          # cells a second
const PLACE_SNAP := 5           # a ghost that's floating or poking into rock snaps to a legal spot this near
const HOPPER_RATE := 90.0      # cells a second; fast enough to keep up with a full aquifer breach
const SPOUT_RATES := [0.5, 1.0, 2.0]
const SPOUT_QUEUE_MAX := 20
const LAVA_DPS := 25.0
const STEAM_DPS := 5.0          # to Conduits only

# --- Research -------------------------------------------------------------------
const LAB_POWER_PER_S := 2.0        # the most one Lab turns into research a second
# Tiers open with a discovery. Tier 1 is open from the start.
const TIER_DISCOVERY := ["", "", "the first Glimmer mined", "the first lava seen", "the Crucible in view"]
const TIER_FOUND := ["", "", "Glimmer", "Lava", "The Crucible"]

# The tech tree. "needs": parent techs (all of them, or any one when "any" is set);
# "mats": materials the Labs must be sent, [stone, glimmer, obsidian, water, power];
# "building": what it adds to the build list; "phase": the build that implements
# it, for techs whose content doesn't exist yet (they show but can't be picked).
# Upgrades have "levels" instead of one cost: each level is researched in turn,
# costs more than the last and may want a later tier open.
const TECHS := [
	{"id": "waterwheel", "name": "Waterwheel", "tier": 1, "needs": [], "power": 60, "building": B_WATERWHEEL,
		"text": "Generator: power from water falling through it."},
	{"id": "spout", "name": "Spout", "tier": 1, "needs": [], "power": 80, "building": B_SPOUT,
		"text": "Releases stockpiled Water where you put it."},
	{"id": "cache", "name": "Cache", "tier": 1, "needs": [], "power": 60, "building": B_CACHE,
		"text": "Storage for power and materials out at the front."},
	{"id": "lamp", "name": "Lamp", "tier": 1, "needs": [], "power": 40, "building": B_LAMP,
		"text": "Lights 20 cells round it for 0.1 power/s. Everywhere else underground stays dark."},
	{"id": "thumper", "name": "Thumper", "tier": 1, "needs": [], "power": 50, "building": B_THUMPER,
		"text": "Blasts the ground under it every few seconds and throws itself up. Drag it anywhere; Hoppers catch the rubble."},
	{"id": "borer", "name": "Borer", "tier": 1, "needs": [], "power": 150, "building": B_BORER,
		"text": "A digger you point and let go: it tunnels until its power runs out or it meets something it can't cut."},
	{"id": "warren", "name": "Warren", "tier": 1, "needs": [], "power": 100, "building": B_WARREN,
		"text": "Mites dig a chamber round the Warren, then tunnel toward a marker you set (soft ground only)."},
	{"id": "strut", "name": "Strut", "tier": 1, "needs": [], "power": 60, "building": B_STRUT,
		"text": "A beam across a gap, rock to rock (up to 16 cells). It props what rests on it and holds rock within 5 cells of each end."},
	{"id": "floodgate", "name": "Floodgate", "tier": 2, "needs": ["spout"], "power": 120, "mats": [0, 5, 0, 0, 0],
		"building": B_FLOODGATE, "text": "A Bulkhead that opens and closes on a sensor."},
	{"id": "relay_mast", "name": "Relay Mast", "tier": 2, "needs": ["cache"], "power": 120, "mats": [0, 10, 0, 0, 0],
		"building": B_MAST, "text": "A Conduit on a mast that links 28 cells instead of 16."},
	{"id": "homing", "name": "Homing", "tier": 2, "needs": ["borer"], "power": 180, "mats": [0, 8, 0, 0, 0],
		"text": "A Borer at half power heads back the way it came, recharges, then goes back to work."},
	{"id": "sounding", "name": "Sounding", "tier": 2, "needs": ["warren"], "power": 100, "mats": [0, 5, 0, 0, 0],
		"text": "Mites leave a one-cell skin against any liquid."},
	{"id": "hard_teeth", "name": "Hard Teeth", "tier": 2, "needs": ["warren"], "power": 150, "mats": [0, 10, 0, 0, 0],
		"text": "Mites dig stone, glimmer and coal; chamber, marker circle and marker range 1.5x larger."},
	{"id": "obsidian_saw", "name": "Obsidian Saw", "tier": 3, "needs": ["hard_teeth", "borer"], "any": true, "power": 250,
		"mats": [0, 12, 0, 0, 0], "text": "The Drill and Borers cut obsidian. Until then it stops them."},
	{"id": "steam_turbine", "name": "Steam Turbine", "tier": 3, "needs": ["waterwheel"], "power": 250, "mats": [0, 15, 0, 0, 0],
		"phase": 9, "text": "Generator: power from steam rising through it."},
	{"id": "ember_brood", "name": "Ember Brood", "tier": 3, "needs": ["hard_teeth"], "power": 250, "mats": [0, 15, 0, 0, 0],
		"text": "5 mites per Warren, and they walk through fire (lava still kills them)."},
	{"id": "coolant_jacket", "name": "Coolant Jacket", "tier": 3, "needs": ["borer"], "power": 250, "mats": [0, 15, 0, 0, 0],
		"phase": 9, "text": "Borer cuts hot rock, venting steam behind it."},
	{"id": "tremor_dampers", "name": "Tremor Dampers", "tier": 4, "needs": ["obsidian_saw", "strut"], "power": 300,
		"mats": [0, 0, 20, 0, 0], "text": "Tremors crumble no stone within 12 cells of a Strut."},
	# Upgrades.
	{"id": "drill_bit", "name": "Drill Bit", "tier": 1, "needs": [],
		"text": "The Drill digs 50% faster a level, and each level costs 20% more power per cell.",
		"levels": [{"tier": 1, "power": 60}, {"tier": 1, "power": 130}, {"tier": 2, "power": 260, "mats": [0, 8, 0, 0, 0]},
			{"tier": 2, "power": 500, "mats": [0, 16, 0, 0, 0]}, {"tier": 3, "power": 900, "mats": [0, 24, 8, 0, 0]}]},
	{"id": "drill_shaft", "name": "Drill Shaft", "tier": 1, "needs": [],
		"text": "The Drill reaches deeper: 60, 100, 160, 240, 330, 450, 590, 730, then 870 rows (the bedrock over the chamber). Deep rows cost more power.",
		"levels": [{"tier": 1, "power": 40}, {"tier": 1, "power": 80}, {"tier": 1, "power": 150}, {"tier": 1, "power": 260},
			{"tier": 2, "power": 420, "mats": [0, 10, 0, 0, 0]}, {"tier": 2, "power": 650, "mats": [0, 20, 0, 0, 0]},
			{"tier": 3, "power": 950, "mats": [0, 30, 0, 0, 0]}, {"tier": 3, "power": 1300, "mats": [0, 30, 10, 0, 0]},
			{"tier": 3, "power": 1800, "mats": [0, 40, 20, 0, 0]}]},
	{"id": "thump_charge", "name": "Thumper Charge", "tier": 1, "needs": ["thumper"],
		"text": "Harder blasts: through stone, then glimmer, then (at the last level) obsidian.",
		"levels": [{"tier": 1, "power": 60}, {"tier": 2, "power": 150, "mats": [0, 6, 0, 0, 0]},
			{"tier": 3, "power": 300, "mats": [0, 15, 0, 0, 0]}, {"tier": 3, "power": 500, "mats": [0, 25, 0, 0, 0]}]},
	{"id": "thump_radius", "name": "Blast Radius", "tier": 1, "needs": ["thumper"],
		"text": "Thumper craters a cell wider each level (3.5, 4.5, 5.5, 6.5).",
		"levels": [{"tier": 1, "power": 50}, {"tier": 2, "power": 140, "mats": [0, 6, 0, 0, 0]},
			{"tier": 3, "power": 300, "mats": [0, 15, 0, 0, 0]}]},
	{"id": "thump_efficiency", "name": "Thumper Efficiency", "tier": 1, "needs": ["thumper"],
		"text": "Less power a blast: 1.5, 1.1, 0.8, 0.55.",
		"levels": [{"tier": 1, "power": 40}, {"tier": 2, "power": 120, "mats": [0, 5, 0, 0, 0]},
			{"tier": 2, "power": 240, "mats": [0, 10, 0, 0, 0]}]},
	{"id": "thump_rhythm", "name": "Thumper Rhythm", "tier": 1, "needs": ["thumper"],
		"text": "Blasts come quicker: every 6, 4.5, 3.4, then 2.5 seconds.",
		"levels": [{"tier": 1, "power": 50}, {"tier": 2, "power": 150, "mats": [0, 6, 0, 0, 0]},
			{"tier": 3, "power": 320, "mats": [0, 15, 0, 0, 0]}]},
	{"id": "borer_cells", "name": "Borer Cells", "tier": 1, "needs": ["borer"],
		"text": "A Borer holds more power, so it gets further past the network: 30, 50, 80, 120.",
		"levels": [{"tier": 1, "power": 80}, {"tier": 2, "power": 200, "mats": [0, 8, 0, 0, 0]},
			{"tier": 3, "power": 400, "mats": [0, 20, 0, 0, 0]}]},
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
const CRUCIBLE_PACKETS_PER_S := 2.0
const CRUCIBLE_STALL_S := 5.0
const CRUCIBLE_DRAIN_PER_S := 0.01
const TREMOR_EVERY_S := 15.0
const TREMOR_CELLS := 200

# --- World layers (depth bands, in cells) --------------------------------------
const LAYERS := [
	{"name": "Surface", "top": 0, "bottom": 40, "color": Color("#6d7bb8")},
	{"name": "Topsoil", "top": 40, "bottom": 300, "color": Color("#8a5f3c")},
	{"name": "Stone", "top": 300, "bottom": 600, "color": Color("#7d7f8c")},
	{"name": "Magma", "top": 600, "bottom": 900, "color": Color("#b0503a")},
	{"name": "Chamber", "top": 900, "bottom": 1024, "color": Color("#d9a441")},
]

# --- Hazards -------------------------------------------------------------------
# Dirt erosion: random samples every other tick across the Topsoil band. A fresh
# 260-row dirt shaft sheds roughly one cell every five seconds.
const ERODE_SAMPLES := 1
# Weathering: cells checked a tick, anywhere on the map, for a ceiling that
# crumbles (see "crumble" in the data file). A 60-cell dirt ceiling drops a cell
# every few seconds; stone about a hundred times slower.
const WEATHER_SAMPLES := 48
# Water wear: cells checked a tick for one touching water that washes ("wash" in the
# data file). With dirt's 0.08, a wet dirt face turns to sand in about 20 minutes.
const WASH_SAMPLES := 48
const FIRE_DPS := 6.0               # to a building with half its outline in flames
const CORRODE_DPS := 1.0            # to a building with CORRODE_FULL corrosive cells nearby
const CORRODE_REACH := 3            # how far from a building corrosion counts
const CORRODE_FULL := 12.0
# Repairs: a built building under REPAIR_BELOW of its HP asks the network for one
# Stone, which puts back REPAIR_HP of its HP.
const REPAIR_BELOW := 0.6
const REPAIR_HP := 0.4
# Links (each building's line to the relay it draws through) wear down too; a
# broken one is out of the network until a Stone arrives to mend it.
const LINK_HP := 20.0
const LINK_FIRE_DPS := 4.0          # with 4 or more burning cells on the line
const LINK_CORRODE_DPS := 0.25      # with 8 or more corrosive cells on or beside it
const LINK_LAVA_DPS := 20.0
const LINK_REPAIR_BELOW := 0.5
# Blasts: the sandbox brush's (the Thumper's come from its upgrades). Power is what
# a material's durability must not beat (stone 5, glimmer 6, obsidian 10).
const BLAST_RADIUS := 6.0
const BLAST_POWER := 6
const BLAST_DAMAGE := 10.0          # per point of power, to a building at the centre
const LINK_BLAST := 3.0             # per point of power, to a link through the centre
