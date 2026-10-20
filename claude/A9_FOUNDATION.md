# A9 foundation: the contract the tracks build on

The foundation PR set the rules and left every new part as a stub. A track fills in behaviour and keeps
these rules. `tests/scenario_layers.gd` checks them; `LY.validate` (scripts/machines/layers.gd) is the
definition format as code and runs over every definition.

## Layers
A definition names its `layer`: `base`, `machine`, `interior`, `exterior`, `line`, `standalone` or `anchored`.
No layer means the Build list's "Other" group (everything the kit has no place for yet: movers, power,
sensors, the Caster and Centrifuge chambers). The Build list groups by layer and hides a heading
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
`LY.bases_of`, `LY.links`. The first rule that makes a part hold for a peer is in: a Heater (thermal.gd) sets
`m["waits"]` while a Blender on the same base has `stirring` set, and reads "Waiting for the Blender to finish stirring."
The overseer still only names and reports; each part decides for itself.

## Stubs
`"stub": true`, `"kind": "stub"`, `"track": "processing" | "exterior" | "tools"`. A stub has its layer, faces,
`attach` points, a placeholder price and a blurb saying what it will do. It never shows in the Build list
(`MC.unlocked` is false) and says "Not built yet." when placed by hand. To fill one in: give it a real `kind` and
behaviour script (register it in `MC.ensure_defs`), a `tech` in `defs.gd` TECHS, drop `stub` and `track`, keep the
layer rules. Four stubs are left (the exterior track is built; see scripts/machines/exterior/ and scripts/machines/lines.gd):

- tools (`tools.json`): Area Vac, Scoop, Grabber, Floodlight

Not stubs: the processing and exterior tracks are done (see below), the Conveyor line is the existing Conveyor until a line beats
it, and the Case is real.

## Processing recut (what the exterior and line threads can rely on)
Parts: Press, Heater, Chiller, Blender (machines on a base's socket); Sieve, Macerator, Electrolyser, Heat
Dispersal Unit (interior strips between bases). The Caster and Centrifuge are still chambers fed by a Tank's `pass`
rule. Behaviour is in `scripts/machines/processing/`; `base_work.gd` ("BW") is the shared helper.
- A machine works on its base through the wall: `BW.plug_base(g, m)` is the first base in `LY.bases_of`. Press,
  Heater, Chiller and Blender have a plug on each side (`plug_l`, `plug_r`), are 30 tall with the plugs 9 down, so
  they stand flush with the ground beside a Tank (30 tall) or sit between two bases and work on the first. A
  cantilevered machine tips the whole assembly; stay flush or add a second plug.
- `m["lets"]` and `m["holds"]` are lists of `pass` style rules a machine publishes each scan (machines.gd clears
  them first, so a part that is off holds nothing back). `BW.may_leave(g, base, mat)` reads them across a base's
  machine neighbours: a `holds` match stays in, and when any neighbour has `lets` only a match may leave. A base's
  own `pass` rules (`_pass_rule`), and any strip drawing from it, ask it. A Heater on Boil lets gas and what
  boiling leaves; the Press holds its pressable powder. Tick order is scan machines, `_pass` the bases, scan the rest.
- A strip names its pixel faces `in` and `out` (HDU: `a`, `b`) and takes from `BW.ends(g, m, def)[0]` into `[1]`
  with `BW.carry`. The Electrolyser has a third, `gas`, because Lye and Chlor eat each other in one base; `LY.validate`
  allows two or three pixel faces on a strip, the first two opposite. Every pixel face needs a base (`base_each_face`).
- Reach: a module needs a built Node or the Hub centre within 80 cells of its rect, as before. The Hub rect is
  x 472..552 on y 140..200, so a part left of x 392 needs a Node.
- Save version 5. A version 4 save loads: `MC.retire_recut` takes down every Boiler, Furnace, Chiller, Press, Sieve,
  Macerator and Electrolyser module (the ids are reused for the new parts, which have different faces), refunds their
  price (`RECUT_COSTS`), unlinks their neighbours and raises one alert. Module ids of the new parts are stable.
- Techs: Boiler is now the Heater (id `boiler`), Furnace is "Smelting" (id `furnace`, adds Smelt mode to the Heater),
  plus new Blender and HDU. Tests: processing, thermal, fluids, wave2, interior, layers.

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
