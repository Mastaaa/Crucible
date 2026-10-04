extends RefCounted
## One placed structure: the Hub, the Crucible, a Node, a Bulkhead or a Brace. It is a blueprint
## until its full cost has arrived by packet (a Brace is built at once). Machines are modules,
## not buildings (scripts/machines/).

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
# Network
var send_tokens := 0.0      # the Hub: packets it may send
var enabled := true
var connected := false
var was_connected := false
var drowned := false
var wet_scans := 0         # consecutive damage scans disagreeing with `drowned`
var link = null            # the relay this building draws packets through
var active_relay := false  # relays only: built, switched on and not drowned
var parent = null          # relays only: next relay toward the Hub
var net_dist := 0.0        # relays only: path length from the Hub

var horizontal := false    # a Brace laid flat

# Repairs
var repairing := false     # a Stone is on its way to patch it up

# Scan cache slots (-1: not in that list)
var scan_idx := -1
var seg_idx := -1

# Anchoring: a building needs rock (or a building that's held up) touching it,
# corners included; without it, it falls until it lands on something.
var touching := PackedInt32Array()   # ids of buildings next to this one (the hazard scan's cache)
var falling := false
var fall_v := 0.0          # cells a second
var fall_acc := 0.0
var fell := 0              # cells fallen this time

# Brace: the rock cells its ends rest on (each holds the rock round it)
var anchor_a := Vector2i(-1, -1)
var anchor_b := Vector2i(-1, -1)

# Feedback
var flash := 0.0
var alert_cd := 0.0


func center() -> Vector2:
	return Vector2(x + w * 0.5, y + h * 0.5)


func rect() -> Rect2i:
	return Rect2i(x, y, w, h)


func has_cell(cx: int, cy: int) -> bool:
	return cx >= x and cx < x + w and cy >= y and cy < y + h


func title() -> String:
	return D.B_NAMES[type]


func is_relay() -> bool:
	return type == D.B_HUB or type == D.B_NODE


## Only the Hub sends packets.
func is_source() -> bool:
	return type == D.B_HUB


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
