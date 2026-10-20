# A9 foundation: the contract the tracks build on

The foundation PR set the rules and left every new part as a stub. A track fills in behaviour and keeps
these rules. `tests/scenario_layers.gd` checks them; `LY.validate` (scripts/machines/layers.gd) is the
definition format as code and runs over every definition.

## Layers
A definition names its `layer`: `base`, `machine`, `interior`, `exterior`, `line`, `standalone` or `anchored`.
No layer means the Build list's "Other" group (everything the kit has no place for yet: movers, power,
sensors, the processing chambers until they are recut). The Build list groups by layer and hides a heading
while nothing under it is unlocked.

| Layer | What it is | What it asks of itself (`needs`, default) |
|---|---|---|
| base | Tank, Case, Vault Cell. Holds contents, has side sockets (w 10) and, for contents, side ports (pixel, w 6). | nothing; validate wants at least one socket face |
| machine | Plugs into a base's socket and acts on its contents through the wall. | `["socket"]`: a socket face joined to a base |
| interior | A strip with two pixel faces on opposite sides; works on what passes between two bases. | `["base_each_face"]`: every pixel face joined to a base |
| exterior | Plugs into a socket; Pump, Cutter and the like hang by pixel and mech faces instead. | `["socket"]`, or `"needs": []` (the six existing exterior parts have it) |
| line | Pipe, Cable, Network, and the Chute and Conveyor until the lines beat them. | nothing; a stub line has an `inventory` |
| standalone | Stands on a line where its centre meets it. | nothing |
| anchored | Bolted in place (`"anchored": true`). | nothing |

A part short of its `needs` does no work and says what is missing (`m["needs"]`, also its `state`). The check runs
every machine scan (`LY.scan`); a part just placed is checked at once (`LY.placed`).

## Sockets
Face type `socket` (`F.SOCKET`, width `F.SOCKET_W` = 10). A socket joins a socket by the usual contact rule and stays
shut: no wall pixels leave, so the base keeps its integrity and its contents. The part reaches the base's contents
through the wall: `LY.bases_of(g, m)` gives the base module ids, and a base's `sim`, `box` and `contents` are the same
as ever. A part that needs a base is bolted to it (`LY.weld`, auto bolts owned by the part), so the assembly moves
and falls as one piece. Ports (pixel faces on a base's sides) open when an interior strip joins them, as any pixel
face does.

Tank, Case and Vault Cell have a left and a right socket (`socket_l`, `socket_r`); Tank and Case have ports
(`port_l`, `port_r`). Old saves get the new faces closed on load (`MC.migrate`).

## The overseer
`LY.scan` finds each assembly (modules joined by face links or joints, two or more) and writes `g.overseers[id]`
(`id` = lowest module id; `members`, `lead`, `name`) and `m["overseer"]`. It is derived each scan and not saved. The
names come from data/overseer.json. `LY.line(g, m)` is the one-line readout: name, part count, any part that is
held up (`m["waits"]` or `m["needs"]`), then the lead's status (`m["state"]`, else the first line of its `info`).
Hover text ends with it.

The overseer recognises and coordinates; every part works alone. What a part can publish for neighbours:
`m["offers"]` (words) and `m["waits"]` (a reason it is held up by a neighbour). Finding neighbours: `LY.peers`,
`LY.bases_of`, `LY.links`. Nothing yet makes a part hold for a peer; the processing track adds the first such rules
(a Heater holds while the Blender stirs) in its own parts, and `waits` is how they show.

## Stubs
`"stub": true`, `"kind": "stub"`, `"track": "processing" | "exterior" | "tools"`. A stub has its layer, faces,
`attach` points, a placeholder price and a blurb saying what it will do. It never shows in the Build list
(`MC.unlocked` is false) and says "Not built yet." when placed by hand. To fill one in: give it a real `kind` and
behaviour script (register it in `MC.ensure_defs`), a `tech` in `defs.gd` TECHS, drop `stub` and `track`, keep the
layer rules. Fifteen stubs:

- processing (`processing.json`): Blender, Heat Dispersal Unit
- exterior (`exterior.json`): Spout, Vacuum, Energy Port, Pipe Hookup, Anchor Hookup, Pipe Router; the lines Pipe, Cable, Network
- tools (`tools.json`): Area Vac, Scoop, Grabber, Floodlight

Not stubs: Heater and Chiller are recuts of the Boiler, Furnace and Chiller (processing track), the Conveyor line
is the existing Conveyor until a line beats it, and the Case is real.

## Line parts and inventory
`"inventory": {"cap": N}` is what a line part carries in transit. It is the part's `contents`, with `MU.capacity`
reading the cap. When such a part is taken down or lost, `LY.rescue` first hands its contents to the nearest joined
module that takes them (Alex's note: a broken Pipe puts what it carried back into the neighbour that sent it). Alex's
other notes still to build: a fixed power cost per pixel at a Network I/O Port, and inventories on Nodes (Nodes are
structures, not modules, so that is the exterior track's call). Whether a Cable's in-transit power is `contents` is
open (`contents` is keyed by material).

## Attach points
Hookups declare `attach` lists as in the A8 contract (tests/scenario_a9_points.gd). The stubs Pipe Hookup, Anchor
Hookup, Pipe Router, Pipe, Cable and Network already declare theirs, so the Pipe and Cable checks in that file would
pass today. The thread that lands Pipe and Cable flips `A9 := false` there.

## Ownership and testing
- processing track: processing.json, processing/*.gd; tests processing, thermal, fluids, wave2, interior, shorer.
- exterior track: logistics (new parts), exterior.json; tests logistics, a9_points, contraptions.
- tools track: tools.json and its own scenario.
- Only one engine-changing PR merges at a time. The foundation made no engine change.
- Tests that place modules in the open air let them fall; bodies that fall far break on landing. Build a few cells
  above the ground (see scenario_layers `AIR_Y`).
