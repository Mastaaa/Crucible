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

## Units one dug or swallowed cell of `m` pays into each of its stockpiles.
static func cell_units(m: int) -> float:
	return M.worth_of(m) / CELLS_PER_UNIT

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
const B_TURBINE := 17

const B_NAMES := ["Hub", "Conduit", "Drill", "Hopper", "Spout", "Bulkhead", "Floodgate", "Crucible",
		"Waterwheel", "Cache", "Lamp", "Lab", "Thumper", "Borer", "Relay Mast", "Warren", "Strut",
		"Steam Turbine"]
const B_LETTERS := ["HUB", "C", "D", "V", "S", "", "F", "", "", "K", "L", "LAB", "T", "B", "M", "W", "", ""]
const B_SIZES := [Vector2i(8, 6) * S, Vector2i(2, 2) * S, Vector2i(3, 3) * S, Vector2i(3, 2) * S,
		Vector2i(2, 2) * S, Vector2i(2, 2) * S, Vector2i(2, 6) * S, Vector2i(14, 8) * S,
		Vector2i(3, 5) * S, Vector2i(3, 3) * S, Vector2i(2, 2) * S, Vector2i(4, 3) * S,
		Vector2i(2, 2) * S, Vector2i(3, 3) * S, Vector2i(2, 3) * S, Vector2i(5, 3) * S, Vector2i(1, 1) * S,
		Vector2i(4, 4) * S]
const B_HP := [1000.0, 100.0, 100.0, 100.0, 100.0, 200.0, 200.0, 1000.0, 100.0, 150.0, 60.0, 120.0,
		80.0, 150.0, 120.0, 120.0, 60.0, 120.0]
# Cost per building as [stone, glimmer, obsidian, water, power].
const B_COSTS := [[0, 0, 0, 0, 0], [2, 0, 0, 0, 0], [5, 0, 0, 0, 0], [3, 0, 0, 0, 0],
		[3, 2, 0, 0, 0], [1, 0, 0, 0, 0], [3, 1, 0, 0, 0], [0, 0, 0, 0, 0],
		[6, 0, 0, 0, 0], [8, 0, 0, 0, 0], [2, 0, 0, 0, 0], [8, 0, 0, 0, 0],
		[3, 0, 0, 0, 0], [14, 0, 0, 0, 0], [4, 1, 0, 0, 0], [10, 0, 0, 0, 0], [2, 0, 0, 0, 0],
		[10, 4, 0, 0, 0]]
const B_COLORS := [Color("#f2c14e"), Color("#7cc4ff"), Color("#ff9a52"), Color("#5fd1b0"),
		Color("#5aa9ff"), Color("#9aa3b5"), Color("#c7a2ff"), Color("#ffd27a"),
		Color("#8fd3ff"), Color("#e2b86a"), Color("#fff0a0"), Color("#e59ad8"),
		Color("#ff7a6b"), Color("#f0a04b"), Color("#9ad8ff"), Color("#c9a36b"), Color("#d8c08a"),
		Color("#c8d2e6")]
const B_BLURBS := [
	"Holds the stockpile and sends every packet.",
	"Extends the network. Links to other Conduits within 160 cells.",
	"Bores a 30-wide shaft straight down from beside the Hub and banks what it removes. Drill Bit and Drill Shaft research make it faster and deeper.",
	"Swallows loose material that falls into its mouth.",
	"Releases stockpiled Water, 600 cells per packet.",
	"A wall with 200 HP. Holds lava for 8 seconds.",
	"A Bulkhead that opens and closes.",
	"The goal. Feed it, light it.",
	"Makes power from water falling through it, in at the top and out of the bottom.",
	"Stores power and materials at the front. Serves nearby machines first; nearby digging banks here.",
	"Lights 200 cells round it while it has power. Rock casts shadows.",
	"Turns power into progress on the tech picked in the Research tab (T). Each Lab adds up to 2 power/s.",
	"Goes off every few seconds, cratering the ground under it and throwing itself up. Drag it where you want it. What it breaks flies as rubble for Hoppers to catch.",
	"Grinds a 30-wide tunnel the way it's pointed and follows it, until its power runs out or it meets something it can't cut. Turn it any time.",
	"A Conduit on a mast: links other relays within 280 cells.",
	"A colony of mites that hollows out a chamber over it, then tunnels toward the marker you set in its panel and digs out a small circle there. They go their own way getting there.",
	"A beam across a gap, rock to rock. Holds up what rests on it, and nothing within 50 cells of either end caves in or crumbles. Built at once from the Hub's Stone; no upkeep.",
	"Makes power from steam rising through it, in at the bottom and out of the top. What gets past it still scalds Conduits.",
]
# Build list: keys 1-9, 0, then letters. Only what's unlocked shows; the keys stay put.
const PALETTE := [B_CONDUIT, B_THUMPER, B_HOPPER, B_BULKHEAD, B_LAB, B_SPOUT, B_FLOODGATE,
		B_WATERWHEEL, B_CACHE, B_LAMP, B_BORER, B_MAST, B_WARREN, B_STRUT, B_TURBINE]
const PALETTE_KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "B", "M", "G", "X", "U"]
const STARTING_KIT := [B_CONDUIT, B_HOPPER, B_BULKHEAD, B_LAB]

# --- Network -----------------------------------------------------------------
const RELAY_RANGE := 16.0 * S
const MAST_RANGE := 28.0 * S
const LINK_RANGE := 8.0 * S
const HUB_PACKETS_PER_S := 6.0
const CACHE_PACKETS_PER_S := 4.0
const GEN_PACKETS_PER_S := 2.0
const PACKET_SPEED := 60.0 * S

# --- Power ------------------------------------------------------------------------
const HUB_POWER_PER_S := 0.2        # the floor: the Hub always makes this much
const POWER_RESERVE := 10.0         # what each powered machine holds
const HOPPER_POWER_PER_CELL := 0.02 / (S * S)
const SPOUT_POWER_PER_PACKET := 1.0
const GATE_POWER := 1.0
const LAMP_POWER_PER_S := 0.1
const WHEEL_POWER_PER_CELL := 0.08 / (S * S)
const WHEEL_CELLS_PER_S := 25.0 * S * S   # most water a Waterwheel passes a second (2 power/s)
const TURBINE_POWER_PER_CELL := 0.4 / (S * S)   # 4/s from the ~1000 cells/s a room of steam pushes through it (phase 10)
const TURBINE_CELLS_PER_S := 10.0 * S * S        # the most it takes: its 4/s
                                                  # gives about half that (2 power/s)
const GEN_BUFFER := 20.0            # power a generator holds before the rest goes to the Hub
const CACHE_CAP := 60.0
const CACHE_TOPUP := [30.0, 0.0, 0.0, 0.0, 60.0]   # what the network keeps a Cache stocked with
const CACHE_BANK_RANGE := 24.0 * S  # digging this close to a Cache banks into it
const SPRING_CELLS_PER_S := 8.0 * S * S   # a Waterwheel under a spring makes about 0.6 power/s
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

## Generators: Waterwheels and Steam Turbines hold what they make and send it.
static func is_generator(t: int) -> bool:
	return t == B_WATERWHEEL or t == B_TURBINE

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
const DRILL_REACHES := [150, 300, 500, 800, 1200, 1650, 2250, 2950, 3650, 4350]   # by Drill Shaft level
const DRILL_DEEP_ROWS := 1500.0     # power per cell goes up by its base every this many rows down
const DRILL_SCAN_ROWS := 1024       # rows of channel a Drill looks over for loose fill in a tick
const DRILL_REACH := 12 * S         # a Drill placed by a test script (not the fixed one)
# Thumper: blasts under itself on a timer and is thrown up by it. Indexed by
# upgrade level (Thumper Charge, Blast Radius, Efficiency, Rhythm).
const THUMP_POWERS := [3, 5, 6, 8, 10]      # beats dirt, coal and sulfur; stone 5, glimmer 6, obsidian 10
const THUMP_RADII := [3.5 * S, 4.5 * S, 5.5 * S, 6.5 * S]
const THUMP_COSTS := [1.5, 1.1, 0.8, 0.55]  # power per blast
const THUMP_INTERVALS := [6.0, 4.5, 3.4, 2.5]
const THUMP_DEPTH := S               # the charge goes off this many cells under it
const THUMP_LAUNCH := 20.0 * S      # cells/s up off a blast, plus 2 * S per point of blast power
const THUMP_DRIFT := 2.5 * S        # most sideways speed a blast adds, cells/s: it lands in or by its crater
const DRAG_SPEED := 45.0 * S        # fastest a dragged Thumper follows the cursor, cells/s
const FLY_WATER_MAX := 10.0 * S     # fastest anything sinks through liquid
# Borer: grinds the rock in front of it at BORER_SPEED of full pace, moves into
# the space, runs on its reserve out past the network.
const BORER_SPEED := 0.3             # phase 10: 0.5 made the mid-game a sprint
const BORER_MOVE_PER_S := 8.0 * S   # cells a second through open space
const BORER_MOVE_POWER := 0.02 / S  # power per cell moved
const BORER_RESERVES := [30.0, 50.0, 80.0, 120.0]   # by Borer Cells level
# Warren (phase 7): its mites dig a half-circle chamber over it, then tunnel toward
# its marker and hollow out a small circle there, hauling each cell home to bank.
# Hard Teeth scales the chamber, the circle and the marker's range by WARREN_TEETH_SCALE.
const WARREN_DOME_R := 6.0 * S       # the chamber over it, from the middle of its floor line
const WARREN_MARKER_RANGE := 32.0 * S   # furthest a marker can sit from it
const WARREN_MARKER_R := 3.0 * S     # the circle dug out at the marker
const WARREN_TUNNEL_SLACK := 8.0 * S # furthest off the straight line to the marker they'll wander
const WARREN_WOBBLE := 3.0 * S       # how much each cell's quirk counts against its distance to the marker
const WARREN_DETOUR := 2.0 * S       # furthest back from their nearest point to the marker they'll dig to get round something
const WARREN_SKIN := S               # with Sounding, cells of ground they leave against a liquid
const WARREN_TEETH_SCALE := 1.5
const WARREN_MITES := 3
const WARREN_MITES_EMBER := 5
const WARREN_BREED_S := 20.0         # a replacement mite every this long
const WARREN_BREED_COST := 1.0       # Stone, taken from the Hub or a Cache like a blueprint
const WARREN_POWER_FRAC := 0.5       # power per cell dug, of the Drill's base rate
const WARREN_REACH_MARGIN := 3 * S   # mites path through open cells this far outside the zone
const MITE_SPEED := 4.0              # of full pace, nibbling a cell (phase 10: v2's pace against building size)
const MITE_BURST := 8                # bites (4 x 4 cells) nibbled out a trip before hauling them home
const MITE_MOVE_PER_S := 20.0 * S    # cells a second along a surface
const MITE_DROWN_S := 5.0            # under liquid this long and it drowns
const MITE_CHOKE_S := 5.0            # in fumes this long and it chokes
const MITE_BURN_S := 3.0             # alight this long, running and lighting what it brushes, then dead
# Mites as bodies (phase 8d): a mite walks and clings on its own, and turns into a
# MITE_SIZE-square body the moment physics takes it (it loses its grip, a blast
# catches it); it walks again once it lies still. Anything moving into it with at
# least MITE_CRUSH (cells of it x cells a second) crushes it; less squeezes it aside.
const MITE_SIZE := 3
const MITE_CRUSH := 3000.0          # a 20-cell pebble at 150; a falling mite (9 cells) never does
const MITE_FALL_V := 480.0          # landing faster than this kills one (a fall of about 130 cells)
const MITE_GRIP := 2                # bites off it can reach to cling to
const MITE_SOFT := [DIRT, LOOSE_DIRT, RUBBLE, COAL_CHUNKS, ASH, SAND, GRAVEL]   # Tier 1
const MITE_HARD := [STONE, GLIMMER, COAL, GLIMMER_SHARDS, OBSIDIAN_SHARDS, PACKED_DIRT, CLAY]   # added by Hard Teeth
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
# Strut: a beam S cells thick across a gap, rock at both ends, built at once.
const STRUT_MAX := 16 * S            # longest gap it spans
const STRUT_THICK := S               # how thick the beam is, where the gap allows
const STRUT_HOLD := 5 * S            # rock within this of either anchor never caves in, weathers or loosens
const STRUT_DAMP_R := 12.0 * S       # with Tremor Dampers, tremors spare stone this close to a Strut
const SENSE_RADIUS := 10.0 * S  # drills feel hidden pockets this far off
const SENSOR_RANGE := 16.0 * S  # how far a Spout or Floodgate sensor can sit from it
# Light and fog. A block is explored when it's lit and within sight of one of your
# buildings; after that it shows live whenever it's lit, and as last seen (dimmed)
# when it isn't. Light fades a cell per cell of air, twice that through liquid and
# five times through rock (see "opacity" in data/materials.json). Radii in cells.
const LIGHT_HUB := 22.0 * S
const LIGHT_LAMP := 20.0 * S
const LIGHT_PILOT := 3.0 * S    # every machine and Drill head: enough to see it work
const LIGHT_CRUCIBLE := 10.0 * S
const SUN_LIGHT := 12 * S       # the sky, and straight down open shafts
const LIGHT_VIEW_PAD := 256     # explored ground this far past the screen stays lit (live)
const SIGHT_HUB := 24.0 * S
const SIGHT_CONDUIT := 12.0 * S
const SIGHT_MACHINE := 10.0 * S # a lit Lamp watches its whole pool of light
const REVEAL_START := 20.0 * S  # known round the Hub from the start
const REVEAL_DIG := 6.0 * S     # a Drill knows the rock round its head as it reaches
# Anchoring: a building with nothing solid (or no held-up building) touching it falls.
const FALL_ACCEL := 60.0 * S    # cells a second, per second
const FALL_MAX := 40.0 * S      # cells a second
const PLACE_SNAP := 5 * S       # a ghost that's floating or poking into rock snaps to a legal spot this near
const HOPPER_RATE := 90.0 * S * S   # cells a second; fast enough to keep up with a full aquifer breach
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
	{"id": "waterwheel", "name": "Waterwheel", "tier": 1, "needs": [], "power": 180, "building": B_WATERWHEEL,
		"text": "Generator: power from water falling through it."},
	{"id": "spout", "name": "Spout", "tier": 1, "needs": [], "power": 240, "building": B_SPOUT,
		"text": "Releases stockpiled Water where you put it."},
	{"id": "cache", "name": "Cache", "tier": 1, "needs": [], "power": 180, "building": B_CACHE,
		"text": "Storage for power and materials out at the front."},
	{"id": "lamp", "name": "Lamp", "tier": 1, "needs": [], "power": 120, "building": B_LAMP,
		"text": "Lights 200 cells round it for 0.1 power/s. Everywhere else underground stays dark."},
	{"id": "thumper", "name": "Thumper", "tier": 1, "needs": [], "power": 150, "building": B_THUMPER,
		"text": "Blasts the ground under it every few seconds and throws itself up. Drag it anywhere; Hoppers catch the rubble."},
	{"id": "borer", "name": "Borer", "tier": 1, "needs": [], "power": 450, "building": B_BORER,
		"text": "A digger you point and let go: it tunnels until its power runs out or it meets something it can't cut."},
	{"id": "warren", "name": "Warren", "tier": 1, "needs": [], "power": 300, "building": B_WARREN,
		"text": "Mites dig a chamber round the Warren, then tunnel toward a marker you set (soft ground only)."},
	{"id": "strut", "name": "Strut", "tier": 1, "needs": [], "power": 180, "building": B_STRUT,
		"text": "A beam across a gap, rock to rock (up to 160 cells). It props what rests on it and holds rock within 50 cells of each end."},
	{"id": "floodgate", "name": "Floodgate", "tier": 2, "needs": ["spout"], "power": 480, "mats": [0, 10, 0, 0, 0],
		"building": B_FLOODGATE, "text": "A Bulkhead that opens and closes on a sensor."},
	{"id": "relay_mast", "name": "Relay Mast", "tier": 2, "needs": ["cache"], "power": 480, "mats": [0, 20, 0, 0, 0],
		"building": B_MAST, "text": "A Conduit on a mast that links 280 cells instead of 160."},
	{"id": "homing", "name": "Homing", "tier": 2, "needs": ["borer"], "power": 720, "mats": [0, 16, 0, 0, 0],
		"text": "A Borer at half power heads back the way it came, recharges, then goes back to work."},
	{"id": "sounding", "name": "Sounding", "tier": 2, "needs": ["warren"], "power": 400, "mats": [0, 10, 0, 0, 0],
		"text": "Mites leave a 10-cell skin against any liquid."},
	{"id": "hard_teeth", "name": "Hard Teeth", "tier": 2, "needs": ["warren"], "power": 600, "mats": [0, 20, 0, 0, 0],
		"text": "Mites dig stone, glimmer and coal; chamber, marker circle and marker range 1.5x larger."},
	{"id": "obsidian_saw", "name": "Obsidian Saw", "tier": 3, "needs": ["hard_teeth", "borer"], "any": true, "power": 1000,
		"mats": [0, 24, 0, 0, 0], "text": "The Drill and Borers cut obsidian. Until then it stops them."},
	{"id": "steam_turbine", "name": "Steam Turbine", "tier": 3, "needs": ["waterwheel"], "power": 1000, "mats": [0, 30, 0, 0, 0],
		"building": B_TURBINE, "text": "Generator: power from steam rising through it."},
	{"id": "ember_brood", "name": "Ember Brood", "tier": 3, "needs": ["hard_teeth"], "power": 1000, "mats": [0, 30, 0, 0, 0],
		"text": "5 mites per Warren; they dig hot rock and walk through fire (lava still kills them)."},
	{"id": "coolant_jacket", "name": "Coolant Jacket", "tier": 3, "needs": ["borer"], "power": 1000, "mats": [0, 30, 0, 0, 0],
		"text": "The Drill and Borers cut hot rock, for 1 Water per 2000 cells, all of it vented as steam behind them. A jacketed Borer shrugs off lava while its tank has water, and both quench lava they face into obsidian, a cell of water a cell. Water that lands on a jacketed Borer goes into its tank."},
	{"id": "tremor_dampers", "name": "Tremor Dampers", "tier": 4, "needs": ["obsidian_saw", "strut"], "power": 1200,
		"mats": [0, 0, 20, 0, 0], "text": "Tremors crumble no stone within 120 cells of a Strut."},
	# Upgrades.
	{"id": "drill_bit", "name": "Drill Bit", "tier": 1, "needs": [],
		"text": "The Drill digs 50% faster a level, and each level costs 20% more power per cell.",
		"levels": [{"tier": 1, "power": 180}, {"tier": 1, "power": 390}, {"tier": 2, "power": 1040, "mats": [0, 16, 0, 0, 0]},
			{"tier": 2, "power": 2000, "mats": [0, 32, 0, 0, 0]}, {"tier": 3, "power": 3600, "mats": [0, 48, 8, 0, 0]}]},
	{"id": "drill_shaft", "name": "Drill Shaft", "tier": 1, "needs": [],
		"text": "The Drill reaches deeper: 300, 500, 800, 1200, 1650, 2250, 2950, 3650, then 4350 rows (the bedrock over the chamber). Deep rows cost more power, and past about 2800 rows the rock is hot: that needs the Coolant Jacket.",
		"levels": [{"tier": 1, "power": 120}, {"tier": 1, "power": 240}, {"tier": 1, "power": 450}, {"tier": 1, "power": 780},
			{"tier": 2, "power": 1680, "mats": [0, 20, 0, 0, 0]}, {"tier": 2, "power": 2600, "mats": [0, 40, 0, 0, 0]},
			{"tier": 3, "power": 3800, "mats": [0, 60, 0, 0, 0]}, {"tier": 3, "power": 5200, "mats": [0, 60, 10, 0, 0]},
			{"tier": 3, "power": 7200, "mats": [0, 80, 20, 0, 0]}]},
	{"id": "thump_charge", "name": "Thumper Charge", "tier": 1, "needs": ["thumper"],
		"text": "Harder blasts: through stone, then glimmer, then (at the last level) obsidian.",
		"levels": [{"tier": 1, "power": 180}, {"tier": 2, "power": 600, "mats": [0, 12, 0, 0, 0]},
			{"tier": 3, "power": 1200, "mats": [0, 30, 0, 0, 0]}, {"tier": 3, "power": 2000, "mats": [0, 50, 0, 0, 0]}]},
	{"id": "thump_radius", "name": "Blast Radius", "tier": 1, "needs": ["thumper"],
		"text": "Thumper craters 10 cells wider each level (35, 45, 55, 65).",
		"levels": [{"tier": 1, "power": 150}, {"tier": 2, "power": 560, "mats": [0, 12, 0, 0, 0]},
			{"tier": 3, "power": 1200, "mats": [0, 30, 0, 0, 0]}]},
	{"id": "thump_efficiency", "name": "Thumper Efficiency", "tier": 1, "needs": ["thumper"],
		"text": "Less power a blast: 1.5, 1.1, 0.8, 0.55.",
		"levels": [{"tier": 1, "power": 120}, {"tier": 2, "power": 480, "mats": [0, 10, 0, 0, 0]},
			{"tier": 2, "power": 960, "mats": [0, 20, 0, 0, 0]}]},
	{"id": "thump_rhythm", "name": "Thumper Rhythm", "tier": 1, "needs": ["thumper"],
		"text": "Blasts come quicker: every 6, 4.5, 3.4, then 2.5 seconds.",
		"levels": [{"tier": 1, "power": 150}, {"tier": 2, "power": 600, "mats": [0, 12, 0, 0, 0]},
			{"tier": 3, "power": 1280, "mats": [0, 30, 0, 0, 0]}]},
	{"id": "tank_size", "name": "Tank Size", "tier": 1, "needs": [],
		"text": "Tanks hold more: half, then the full, double and four times what their hollow packs.",
		"levels": [{"tier": 1, "power": 150}, {"tier": 2, "power": 520, "mats": [0, 12, 0, 0, 0]},
			{"tier": 3, "power": 1100, "mats": [0, 28, 0, 0, 0]}]},
	{"id": "borer_cells", "name": "Borer Cells", "tier": 1, "needs": ["borer"],
		"text": "A Borer holds more power, so it gets further past the network: 30, 50, 80, 120.",
		"levels": [{"tier": 1, "power": 240}, {"tier": 2, "power": 800, "mats": [0, 16, 0, 0, 0]},
			{"tier": 3, "power": 1600, "mats": [0, 40, 0, 0, 0]}]},
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
# Coolant Jacket: the Drill and Borers cut hot rock for water (v2: 1 per 20 cells),
# and it all goes up as steam, from the cut (a Borer steps past it: out its tail).
const COOLANT_WATER_PER_CELL := 1.0 / (20.0 * S * S)
const COOLANT_STEAM_PER_CELL := COOLANT_WATER_PER_CELL * CELLS_PER_UNIT   # 0.3
const COOLANT_CAP := 4.0            # water a Drill or Borer holds for its jacket
const JACKET_LAVA_WATER := 0.05     # water a second a jacketed Borer boils off touching lava, instead of burning (phase 10)
const QUENCH_WATER_PER_CELL := 1.0 / CELLS_PER_UNIT   # a jacket quenching lava it faces to obsidian: a cell of water a cell

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
# Blasts: the sandbox brush's (the Thumper's come from its upgrades). Power is what
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
# Thumper collisions: hitting rock or a building sideways or upward faster than
# THUMP_BUMP_SAFE hurts it, and the building, by THUMP_BUMP_DAMAGE per cell a second over.
const THUMP_BUMP_SAFE := 30.0 * S
const THUMP_BUMP_DAMAGE := 0.25   # the hardest flick (450) into rock: 37 of its 80


## What the engine's bodies are set up with (sim_factory).
static func body_params() -> Dictionary:
	return {"accel": SIM_FALL_ACCEL, "max_speed": SIM_FALL_MAX, "shatter": BODY_SHATTER,
			"shatter_per_durability": BODY_SHATTER_PER_DUR, "crush_min": CRUSH_MIN_V,
			"min_cells": BODY_MIN_CELLS, "piece_min": PIECE_WIDTH.x, "piece_max": PIECE_WIDTH.y,
			"thick_min": PIECE_THICK.x, "thick_max": PIECE_THICK.y, "piece_room": PIECE_ROOM, "pieces": true,
			"creature_shatter": MITE_FALL_V}
