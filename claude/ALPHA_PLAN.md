# Crucible: Alpha plan (draft v1)

The working spec for the Alpha roadmap (phases A1 to A7), agreed with Alex in a brainstorm
and kept here as a copy of the Claude Docs doc "Alpha materials: property axes and starter
set (draft)" (https://claude.ai/code/artifact/27a9810d-e60d-4ea8-b10c-3e3c917a4c81), which
also holds the discussion and Alex's inline answers. Nothing here is implemented. PROJECT_BRIEF
carries the phase list and the standing decisions; this file carries the design behind them.
Where it conflicts with the v3 roadmap or standing decisions in PROJECT_BRIEF, this file wins
from A1 on.

## Premise and voice
- The player is an autonomous machine built to reach and light the Crucibles. The Hub is its
  base. Each world is a separate location with exactly one Crucible.
- Orders are phrased as flat instructions ("Instruction 4: deliver 30 Stone to the Hub."). They
  say what, never how. The existing event tracker is the only log, with the occasional cryptic
  line at a milestone.
- The first 10 to 15 minutes lacked a goal and a loop; the game read as a restrictive sandbox.
  Speed was not the problem.

## Settled decisions
- Modular machines fully replace the current buildings. Hard cut at A3. Survivors: Hub,
  Crucible, Nodes (the Conduits), Lab, Lamp, Strut (as Brace) and Bulkhead. The Warren is
  repurposed as the Drone Cage. The fixed Drill retires.
- Temperature is a real per-cell field that leaks slowly between neighbours, with melting,
  boiling and freezing points as material data. Heat and cold are one system. It reworks
  phase 9's hot rock.
- Reactions run on family tags with per-material overrides. The table is fixed for Alpha.
  Randomised per-seed chemistry is parked for a post-Alpha "pocket dimension" update.
- About 25 new materials. Each has a home range: where and at what depth it can spawn.
- Goods follow an Applied Energistics 2 model: Bus Hoppers import pixels as resource units
  onto the network and export units back to pixels. Vault cells pool into banks like EnderIO
  capacitor banks, with one terminal per cluster.
- Research consumes produced goods (Factorio style): players gather and automate each new
  resource before they can research the tech to dig for more. Machines unlock mainly by
  research tier; material discovery and curios join later.
- Late game is the same machines made better (Mk I to IV, paid in refined goods, a few new
  modes), not many new machines. Schematics are dropped.
- Hub power trickle drops from 2 to about 0.2 power/s. Windmills are the first real generator.
- Modules are rigid bodies with typed faces, connected by contact. Signals pass by adjacency
  only. Walls are real cells of a casing material, held together as one body with an integrity
  number, so a breach spills contents and a dead module drops as wreckage.
- The world widens slightly. Biomes are patches inside depth bands, built on the A2 spawn-region
  system.
- Placement is at 90 degrees; modules rotate freely in the world afterwards, and connect only at
  multiples of 90.

## Phases
| Phase | Scope | Exit check |
|---|---|---|
| A1 (done) | Per-cell temperature field, family-tag reaction rules, catalyst modifier, existing reactions and hot rock migrated, lab bench mode (paint any material, see temperature). | Current game plays as before on the new rules. Tests and the bot's baselines hold or are re-baselined with reasons. |
| A2 | Wave 1 materials (about 12), a spawn-region system (home range and depth band per material), the hand-placed Spoil Heap near the Hub. The impact, swell and setting engine extensions left from A1. | Every wave 1 reaction demonstrable on the lab bench. Existing features keep each seed's layout. |
| A3 | Hard cut of the legacy buildings, keeping the survivors above. Machine framework core and the starter quarry. Chute, Conveyor, Bus Hopper. Goal layer v1: skippable tutorial as Hub instructions, chapter milestones in the event tracker, research that consumes goods. Hub trickle cut. | A fresh run's first 15 minutes play through the new loop. The gaps the cut exposes are written down. |
| A4 | Gantry, Piston, Turntable, full Cutter, Laser Excavator with filler swap, tethered Thumper, Macerator, Press. Warren becomes the Drone Cage. Tests and the bot rewritten for the new machines. | The bot digs from the surface to the Magma band on the new machines. |
| A5 | Wave 2 materials to about 25, processing chains, sensors, Mk upgrades, Vault cells. | Every tier is reachable through goods. The bot completes a run. |
| A6 | Slightly wider world, biome patches, depth bands reworked for temperature, surface generators. | Biomes visibly differ and gate resources. |
| A7 | Pacing against the bot, retune, screenshots, STATUS rough edges. | A first run lands near the 2 hour target. |

Between A3 and A5 the old mid-game (Borer, Thumper, Coolant Jacket, Turbine) has no replacement,
so no run can be finished. Scenario tests and the bot that place legacy buildings stop being
usable at A3 and are rewritten in A4.

## Temperature and reactions (A1)
Done. As built (details in claude/STATUS.md): an int16 per cell in eighths of a degree, a
pass every 8 ticks over the chunks that are changing, per-material `conduct`, `sink`, `hold`,
`temp`, `heats`/`cools` {at, to, cost} and `kindle`, and an ambient per row. Families so far:
Fuel (coal, sulfur), Corrosive (sulfur, fumes), Molten (lava). Reactions gained `min_temp`,
`max_temp`, `heat`, `catalyst` and `boost`. Impact triggers, the swell and the setting stage
moved to A2, to land with the wave 1 materials that use them. The Coolant Jacket still reads the
Hot rock material; A3 cuts it. The fog went black where nothing has been seen (Alex, during A1).
The plan as written:
- The field is a slow pass like erosion, dirty-rect driven. Each material carries a
  conductivity and melting, boiling and freezing points. Lava, steam, obsidian, ice and smelting
  fall out of the same rule. Phase 9's hot rock and the Coolant Jacket's rules are rebuilt on it.
- Machines read the temperature of their neighbouring cells. A Boiler turns power into heat in
  what it touches; a Chiller does the reverse; a Thermoelectric Plate turns a difference into
  power.
- Families: one or two tags per material, reactions written between families first and
  per-material overrides after. Candidates: Fuel, Volatile, Corrosive, Binding, Catalytic,
  Absorbent, Crystalline, Shock-sensitive, Smothering. Settle the list while watching reactions
  on the lab bench.
- Engine extensions: a catalyst modifier on reaction chance, impact triggers from per-cell fall
  speed, a one-cell-to-many swell, a timed setting stage (the aux byte already holds burn and gas
  timers).
- Budget: a fresh game ticks in about 0.7 ms today. Watch the tick time and the save size.

## Materials (A2, A5)
A2 built the wave 1 materials from this table plus two (Wisp, Weft); see claude/WAVE1_MATERIALS.md
("Built as" lists where the build differs). The table below is the original pitch list.
Today's data has 28 entries and two reactions (Molten + Water, Fire + Water); hot rock's
boiling moved to the temperature pass in A1. Placeholder names for the first ten pitches:

| Name | Phase | Family | Behaviour |
|---|---|---|---|
| Slick | liquid | Fuel | Oily, floats on water, burns long. Doubles as oil for later enemies. |
| Sourwater | liquid | Corrosive | Turns Stone and Sand to Rubble slowly; with Sulfur grit makes a lot of fumes. |
| Hush | gas | Smothering | Heavy, pools, puts out Fire, chokes mites and drones, harmless to buildings. |
| Quickmire | liquid | Binding | Sets into a stone-like mass in about ten seconds on powder. Cement. |
| Flux | powder | Catalytic | Raises reaction chance beside it without being consumed. Smelting needs it. |
| Ferrite | static ore | none | Dense. In heat with Flux it smelts into bars (rigid bodies) and slag. |
| Rattle | powder | Shock-sensitive | Detonates on a hard landing or heat. |
| Bloat | powder | Absorbent | Soaks liquid and swells; heat bursts it into steam. |
| Glass | static | Crystalline | Sand + Lava. Lets sky light through. |
| Rime | solid | Cold | Freezes Water to Ice and quenches Lava to Obsidian. |

The Spoil Heap near the Hub holds a few odd materials from the first wave, optional and
unexplained. It is the first use of the spawn-region system that A6 extends into biomes.

## Modules
Faces are typed: pixel (Chute or Funnel), power, mechanical mount (Gantry, Piston, Winch) and
signal. A face stays closed until something connects and re-closes after. Chutes and Funnels
chain only in a straight line. Funnels and Chutes take whitelist or blacklist filters picked
with an eyedropper, and powered ones pull matching pixels from a short range. Machines mounted
on movers keep their ports live while they move. Casing material matters: conductivity,
melting point and corrosion apply to the walls.

### Starter quarry (A3)
Players start with the modules needed to dig, and a skippable tutorial in Hub instructions walks
them through the first quarry: a limited Cutter Excavator (soft ground, a wobbling three-pixel
tunnel), a Tank, a Winch, a Funnel, a Windmill and Nodes. The Excavator faces down off the Tank.
The Winch pays out cable as the shaft deepens, and the Tank's fill drives it: full goes up,
empty goes down. At the top the Tank docks with the Funnel and empties into the Hub. Cable
length, Excavator hardness and Tank size are the first limits research lifts. An aquifer fills
the Tank with water and the Hub banks it.

### Parts catalogue
"Sketch" parts are from Alex's drawings, "Chat" parts were named afterwards, the rest are pitches.

| Group | Parts |
|---|---|
| Storage and network | Tank (sketch), Bus Hopper (sketch), Vault cells, Sump (overflow drain, slow), Vent, Valve |
| Moving pixels | Funnel and Chute (sketch), Conveyor (sketch, any angle, carries loose pixels and loose bodies), Pump, Blower, Sieve (by grain class), Auger (screw conveyor for steep powder) |
| Moving machines | Gantry (sketch), Piston (sketch), Winch and Pulley (chat), Turntable, Clamp |
| Excavation | Laser Excavator (sketch, one-pixel beam for stripping ore from walls, can swap mined cells for filler), Cutter Excavator (sketch), tethered Thumper (sketch, impact-triggered, 90 degree cone), Water Jet, Splitter (clean slabs as bodies) |
| Processing | Boiler (chat), Chiller, Macerator (chat, grinds bodies to pixels), Press, Furnace, Caster (molten in, rigid body out as it cools), Centrifuge (by density), Agitator, Condenser, Electrolyser |
| Sensing | Thermometer, Level gauge, Material Sensor, Scale, Timer |
| Power | Windmill, Solar Panel, Steam Turbine and Waterwheel (carry over), Thermoelectric Plate, Combustor, Tap (geyser or oil deposit) |
| Support | Radiator Fin, Insulator Plate, Lamp, Bulkhead, Brace |
| Haulers | Drone Cage (the Warren reworked): drones pick up loose pixels in a highlighted area and drop them elsewhere |

Strongest on the sim rather than on menus: Caster, Thermoelectric Plate, Centrifuge, Winch and
Splitter.

## Goals and loop (A3 on)
1. Run goal, always visible: reach and light the Crucible. A depth readout and a faint tremor
   from below keep it present. Its recipe stays hidden until it comes into view.
2. Band chapters: each depth band has an objective and a hazard that guards the next. The
   existing discovery gates (first Glimmer, first lava, the Crucible in view) become objectives,
   reported through the event tracker.
3. Hub instructions: a short standing order every few minutes asking for a delivered amount of
   something. Rewards are research progress or parts.

## Parked until after Alpha
Enemies, curios and wreckage, surface weather, Schematics, logic and cross-machine engineering,
the pocket dimension with randomised chemistry, more than one Crucible per world.

## To settle during the phases
- Family list and the casing material list.
- Tech tree rebuilt around goods; how the tier discovery gates map onto chapters.
- HUD for 25 or more banked resources (a terminal-style list).
- How much of the Sump's voiding is allowed so hazards do not simply vanish.
- Temperature tick budget and the save format.
