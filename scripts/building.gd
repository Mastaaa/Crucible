extends RefCounted
## One placed structure. It is a blueprint until its full cost has arrived by packet.

const D = preload("res://scripts/defs.gd")

var id := 0
var type := 0
var x := 0
var y := 0
var w := 1
var h := 1
var hp := 100.0
var max_hp := 100.0
var built := false
var dead := false
var order := 0
var cost := PackedInt32Array([0, 0, 0, 0, 0])
var delivered := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
var inflight := PackedInt32Array([0, 0, 0, 0, 0])
# Power
var power := 0.0            # reserve a powered machine runs on
var starved := false        # wanted to work, had no power
var store := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])   # Caches and generators: what they hold
var send_tokens := 0.0      # sources: packets they may send
var gen_tokens := 0.0       # generators: cells they may pass this tick
var flow := 0.0             # generators: smoothed power made per second
var spin := 0.0             # generators: wheel angle, for drawing
var enabled := true
var connected := false
var was_connected := false
var drowned := false
var wet_scans := 0         # consecutive damage scans disagreeing with `drowned`
var link = null            # the relay this building draws packets through
var active_relay := false  # relays only: built, switched on and not drowned
var parent = null          # relays only: next relay toward the Hub
var net_dist := 0.0        # relays only: path length from the Hub

# Drill (and the Borer's heading)
var dir := 0               # 0 down, 1 left, 2 right (Borer: 3 up)
var fixed := false         # the Drill beside the Hub: can't be demolished, hurt or dislodged
var reach := 0             # how far the channel has been opened
var reach_limit := D.DRILL_REACH
var work := 0.0            # seconds of boring banked this tick
var scan_from := 0
var rescan := 0
var cells_bored := 0

# Hopper
var filter := 0            # 0 everything, 1 water only, 2 solids only
var intake := 0.0
var cells_taken := 0

# Spout
var rate_idx := 1
var tokens := 0.0
var queue := 0             # water cells waiting to pour

# Sensor (Spout, Floodgate)
var sensor_on := false
var sx := 0
var sy := 0
var sensor_wet := false

# Floodgate
var gate_mode := 0         # 0 closed, 1 open, 2 open while the sensor is wet
var gate_open := false
var horizontal := false

# Repairs
var repairing := false     # a Stone is on its way to patch it up

# Flight (a Thumper thrown by its own blast, or dragged): the building moves a
# cell at a time through anything open, carrying liquid round it.
var flying := false
var held := false          # being dragged by the player
var hold_at := Vector2.ZERO   # where the drag wants its centre, in cells
var vx := 0.0              # cells a second
var vy := 0.0
var fx := 0.0              # sub-cell position, for the integer x and y
var fy := 0.0
var blasts := 0

# Borer
var mode := 0              # 0 boring, 1 heading home, 2 recharging at home, 3 heading back out
var trail: Array = []      # Vector2i positions it has stood at, oldest first (its start is trail[0])
var trail_idx := 0         # where it is along the trail while homing
var stuck := ""            # why it has stopped, if it has
var moved := 0             # cells moved in all

# Scan cache slots, so a mover can patch its own entry (-1: not in that list)
var scan_idx := -1
var seg_idx := -1

# Anchoring: a building needs rock (or a building that's held up) touching it,
# corners included; without it, it falls until it lands on something.
var touching := PackedInt32Array()   # ids of buildings next to this one (the hazard scan's cache)
var falling := false
var fall_v := 0.0          # cells a second
# Warren (phase 7)
var marker := Vector2i(-1, -1)   # where its mites tunnel to (none: -1)
var stage := ""            # what the mites are on: dome, tunnel, marker, done, idle, blocked
var mites: Array = []      # one Dictionary per living mite (see warren.gd)
var breed_t := 0.0         # seconds toward the next replacement mite
var zone_left := -1        # cells still to dig in its chamber and marker circle (-1: not searched)
var cells_dug := 0
var bred := false          # its first colony has come out
var mites_lost := 0
var last_loss := ""        # what killed the last mite it lost
var search := {}           # warren.gd search(): distances home, paths, targets nearest first
var search_t := 0.0
var search_due := true
var fall_acc := 0.0
var fell := 0              # cells fallen this time

# Strut: the rock cells its ends rest on (each holds the rock round it)
var anchor_a := Vector2i(-1, -1)
var anchor_b := Vector2i(-1, -1)

# Feedback
var flash := 0.0
var alert_cd := 0.0
var breach_cd := 0.0
var breached := 0      # bit 1: has hit water, bit 2: has hit lava (each is reported once)


func center() -> Vector2:
	return Vector2(x + w * 0.5, y + h * 0.5)


func rect() -> Rect2i:
	return Rect2i(x, y, w, h)


func has_cell(cx: int, cy: int) -> bool:
	return cx >= x and cx < x + w and cy >= y and cy < y + h


func title() -> String:
	return D.B_NAMES[type]


func is_relay() -> bool:
	return type == D.B_HUB or type == D.B_CONDUIT


## Hub, Caches and generators send packets.
func is_source() -> bool:
	return type == D.B_HUB or type == D.B_CACHE or type == D.B_WATERWHEEL


## Share of the build cost that has arrived, 0..1.
func progress() -> float:
	var total := 0.0
	var got := 0.0
	for r in D.NRES:
		total += cost[r]
		got += minf(delivered[r], cost[r])
	return 1.0 if total <= 0.0 else got / total


func fully_delivered() -> bool:
	for r in D.NRES:
		if delivered[r] < cost[r]:
			return false
	return true


## Units of resource r still to be sent (not delivered, not in flight).
func still_needed(r: int) -> int:
	return cost[r] - int(delivered[r]) - inflight[r]


## Point at the end of the drill channel, row `reach`.
func drill_head() -> Vector2:
	if type == D.B_BORER:
		return center()
	match dir:
		1:
			return Vector2(x - reach, y + h * 0.5)
		2:
			return Vector2(x + w + reach, y + h * 0.5)
	return Vector2(x + w * 0.5, y + h + reach)


## How many cells wide the channel is (the drill's width across its heading).
func lanes() -> int:
	return w if dir == 0 else h


## Cell (x, y) of lane k (0..lanes-1) at channel row r.
func channel_cell(r: int, k: int) -> Vector2i:
	match dir:
		1:
			return Vector2i(x - 1 - r, y + k)
		2:
			return Vector2i(x + w + r, y + k)
	return Vector2i(x + k, y + h + r)


## Which channel row a cell sits in (the inverse of channel_cell).
func channel_row(c: Vector2i) -> int:
	match dir:
		1:
			return x - 1 - c.x
		2:
			return c.x - (x + w)
	return c.y - (y + h)


## The full channel as a rectangle (for drawing), out to `rows`.
func channel_rect(rows: int) -> Rect2i:
	match dir:
		1:
			return Rect2i(x - rows, y, rows, h)
		2:
			return Rect2i(x + w, y, rows, h)
	return Rect2i(x, y + h, w, rows)
