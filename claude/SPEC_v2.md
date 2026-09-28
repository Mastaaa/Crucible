# Crucible — v2 Spec

Sep 26, 2026 · @Alexandra Evelyn Hawk

v2 turns the network into a lifeline: every machine burns power that the network has to deliver, and that power comes from reactions you stage in the sim. A Lab turns power into research, which unlocks tools as you make discoveries on the way down; the Borer and the Warren are the two researched ways to dig.

## v3 direction

Set on Sep 27 after phase 3. Where an older section disagrees, this one wins; the tech tree below gets redrawn around the new tools in phase 6.

- **Pacing:** an incremental curve that ramps slowly. You start out taking a pixel at a time and end up opening whole shafts and placing whole layouts at once. Research turns into upgrade tiers with steeply rising costs, and the danger grows with depth through what the materials do.
- **Sandbox:** between Noita's per-pixel simulation and Creeper World's network building, centred on how your expansion meets the world. New materials, deposits and curios turn up slowly; you shield the network from them, exploit their reactions, or get blindsided by them.
- **Engine:** the sim moves to C++ as a Godot extension on Noita's architecture: chunks with dirty rects, checkerboard multithreading, materials and reactions as data, then fire, gases, free particles, explosions and, later, rigid chunks.
- **Drill:** one, placed next to the Hub at the start and not buildable. Extremely slow with long range, upgraded for speed and range until it reaches near the Crucible. Replaces the buildable Drill and Drill Advance.
- **Thumper:** blasts at set intervals, cratering the terrain and launching itself. Small power cost per blast; radius, efficiency, blast power and interval are upgradeable.
- **Strut:** spans a gap up to a maximum length and stops terrain collapsing near its anchors on both sides. No upkeep, no deliveries, builds instantly. Collapse starts as crumbling (wide unsupported spans break into rubble); rigid chunks come later.
- **Borer:** runs until its power is gone; an upgrade makes it head back to where it was placed at half power and wait to recharge.
- **Warren:** stays as designed, and mites have to live with the new materials and hazards too.
- **Materials:** Coal (1 Stone, and 1 power the moment it's banked) and Sulfur (1 Stone and 1 Glimmer; eats nearby structures over time) come first; more are being drafted. Links between buildings get HP: hazards wear them down, and a broken link needs a delivery to repair, sent from whichever side still reaches it.

## Why v2

The MVP's sim holds up, but nothing depended on the network and the Drill turned the descent into a loop. The target, in Alex's words:

> The fun of experimenting with different ways of interacting with the world and watching your network of creations interact with the pixel environment without your direct input, and facing the consequences of not engaging in the former two activities carefully and strategically, typically in cascading and catastrophic (though not fully unrecoverable) fashion.

| In the MVP | In v2 |
| --- | --- |
| Descent is a loop: Conduit, Drill, sell, repeat | Power sets digging speed, and each band needs its own researched tools |
| A Drill that reaches its limit is scrap | Borers never finish; the starter Drill can Advance |
| Nothing runs once built, so the network only matters during construction | Machines burn power as they work; the network is their supply line |
| A flood costs construction time and nothing else | A cut line starves the pumps, and the flood worsens on its own |
| The one digging tool is precise and safe | Mites dig whole zones blind; a Borer keeps going until something stops it |

## Scale and fog of war

Everything built gets smaller and the camera moves closer, so the network stays intimate while the world feels large. Starting ranges are short, and research stretches them at a power cost.

| What | MVP | v2 start |
| --- | --- | --- |
| Camera | the whole map width on screen | about 1.5× closer, panning sideways as well as down |
| Conduit | 3×3, links 24 cells | 2×2, links 16 cells |
| Buildings reach a Conduit within | 12 cells | 8 cells |
| Drill | 5×5, reach 48 | 3×3, reach 12 |
| Channels and tunnels | 5 wide | 3 wide |
| Hub | 12×8 | 8×6 |
| Drill sense for hidden pockets | 16 cells | 10 cells |

The map stays 256×1024 cells, so the world grows relative to everything in it.

**Fog of war.** Every building sees a small radius around itself: the Hub 20 cells, Conduits 8, machines 6, and a Lamp (Tier 1) 16. Each 4×4 patch of the map is in one of three states.

- **Unexplored:** generic rock for its depth, as now.
- **Remembered:** seen once, out of sight now. It shows the terrain as you last saw it, dimmed, and its water and lava don't update until something of yours looks again.
- **Visible:** live.

The early warnings stay: lava glow and drill sense still show through the fog, and a damaged building raises an alert wherever it is. The difference is that a flood working its way down a tunnel nobody's watching arrives unannounced. With the camera closer and the fog down, the depth ruler doubles as a minimap of your network and its alerts.

## Power

Power is a fifth resource: machines burn it as they work, and the network has to keep it coming. It's stockpiled at the Hub and in Caches, and travels in packets like building materials, one power per packet.

- **Floor:** the Hub makes 2 power/s on its own, forever, so no game is ever past recovery.
- **Reserves:** every powered machine holds a small reserve (10 power; Borer 30) and asks for packets as it drains. An empty reserve stops the machine where it stands.
- **Delivery:** a request goes to the nearest source with stock, measured along the network. The Hub sends 6 packets/s, a Cache 4, a generator 2.
- **Priority:** the Crucible, then Hoppers and Floodgates (they hold back hazards), then blueprints, then everything else.

| Consumer | Power cost |
| --- | --- |
| Drill, Borer | 0.1 per cell of dirt, 0.2 stone, 0.4 glimmer, 0.8 obsidian |
| Warren mites | 0.15 per cell dug and hauled home |
| Hopper | 0.02 per cell swallowed |
| Spout | 1 per packet of water (10 cells) |
| Floodgate | 1 per open or close |
| Lab | up to 2/s while researching |
| Crucible | 4/s while charging |

The cascade this is built for: a breach drowns a Conduit, the Hoppers past it run their reserves dry, the water climbs faster, and more Conduits drown. A Cache and a second route decide how far it spreads. All numbers in this spec are first-pass values for tuning.

## Generators and springs

A generator is a building with a hollow core that makes power from whatever flows through it, so every power plant is a reaction you stage in the sim.

| Generator | Runs on | Output | The catch |
| --- | --- | --- | --- |
| Waterwheel (Tier 1) | water falling through its core | 0.05 per cell, up to 2/s | the water lands somewhere below, usually on something you care about |
| Steam Turbine (Tier 3) | steam rising through its core | 0.2 per cell, up to 4/s | steam that gets past it scalds the Conduits above |

**Springs** are new to the world. One sits at the floor of every aquifer and in some caves, adding about 10 water cells/s forever, so a drained aquifer refills and a Waterwheel under a spring is steady power. A breached spring never stops on its own.

No free lunch: a Spout-to-Hopper loop costs 0.12 power per cell of water and a Waterwheel pays 0.05. With 16 cells of clearance required between wheels, a loop needs three stacked wheels before it earns anything, and then it earns very little.

## Cache

A Cache is storage at the front, and it's what keeps a severed line from being fatal. It holds 60 power and 60 of each material, and nearby requests draw from it before the Hub. The network tops it up whenever the Hub has packets to spare. Excavators within 24 cells of it (along the network) bank what they dig there, so building at depth stops waiting on the round trip. Tier 1, 16 stone.

## Research

A Lab turns delivered power into progress on the tech picked in the Research tab. A tech opens once its tier's discovery has happened and its parent techs are done, so the tree follows what you find on the way down.

- **Starting kit, no research needed:** Hub, Conduit, Drill, Hopper, Bulkhead, Lab.
- **Lab:** 4×3, 16 stone. Draws up to 2 power/s while a tech is picked; a second Lab doubles the pace. From Tier 2 on, techs also want Glimmer (Obsidian at Tier 4) delivered to the Lab by packet, like construction.
- **Research tab (T):** the tree by tier, one tech at a time, a progress bar, and for each locked tech the discovery or parent it's waiting on.
- **Discoveries:** Tier 1 is open from the start, Tier 2 opens at the first glimmer mined, Tier 3 at the first lava seen, and Tier 4 when the Crucible comes into view.
- **Build bar:** shows only what you've unlocked.

## Tech tree

Seventeen techs in four tiers. A tier opens with a discovery and a tech with its parents, and both digging lines carry you through hot rock.

[embedded content: tech tree · 4 tiers, 17 techs]

Arrows are prerequisites, and a tech without one needs only its tier's discovery. Obsidian Saw takes either digging line and sits on everyone's critical path, since the recipe needs obsidian.

| Tier | Tech | What it adds | Needs | Research cost |
| --- | --- | --- | --- | --- |
| 1 | Waterwheel | Generator: power from water falling through it | none | 60 power |
| 1 | Spout | Releases stockpiled water where you put it | none | 80 power |
| 1 | Cache | Storage for power and materials at the front | none | 60 power |
| 1 | Lamp | Sees 16 cells into the fog for 0.1 power/s | none | 40 power |
| 1 | Warren | Mites dig a set zone around the Warren (soft ground only) | none | 100 power |
| 1 | Tuned Bit | Drill digs 50% faster and draws 50% more power per cell | none | 60 power |
| 1 | Long Shaft | Drill reaches 18 cells instead of 12 | none | 60 power |
| 2 | Floodgate | A Bulkhead that opens and closes on a sensor | Spout | 120 power, 5 glimmer |
| 2 | Relay Mast | A Conduit that links 28 cells instead of 16 | Cache | 120 power, 10 glimmer |
| 2 | Sounding | Mites leave a one-cell skin against any liquid | Warren | 100 power, 5 glimmer |
| 2 | Hard Teeth | Mites dig stone and glimmer; zones 1.5× larger | Warren | 150 power, 10 glimmer |
| 2 | Borer | Self-advancing excavator for stone and glimmer | Tuned Bit | 200 power, 10 glimmer |
| 3 | Steam Turbine | Generator: power from steam rising through it | Waterwheel | 250 power, 15 glimmer |
| 3 | Ember Brood | Mites dig hot rock; 5 per Warren | Hard Teeth | 250 power, 15 glimmer |
| 3 | Obsidian Saw | Any excavator can cut obsidian | Hard Teeth or Borer | 200 power, 10 glimmer |
| 3 | Coolant Jacket | Borer cuts hot rock, venting steam behind it | Borer | 250 power, 15 glimmer |
| 4 | Tremor Dampers | Tremors crumble no stone within 12 cells of one | Obsidian Saw | 300 power, 20 obsidian |

## Excavators

Three ways to dig, and none of them take dig orders.

**Drill (starting kit).** The MVP drill, demoted: 3×3 with a 12-cell reach, a third of a Borer's speed, and it stops at hot rock and obsidian. Tuned Bit and Long Shaft buy it speed and reach, each at a higher power draw per cell. When it's done, Advance packs it up and rebuilds it at the end of its own channel for 2 stone, so it's never scrap.

**Borer (Tier 2; 24 stone, 4 glimmer).** A 3×3 machine that grinds the rock ahead of it and creeps into the space it clears, trailing a 3-wide tunnel. You set its heading and can turn it any time. It keeps going until its reserve runs out or it meets something it can't chew: bedrock, a building, or a solid row of lava. Its speed is the lower of its bore rate and what its power supply allows, and water ahead of it gets pushed out behind it. When it outruns its Conduits it runs on its 30-power reserve and then stalls, so descending means laying a lifeline behind a machine that will happily drill into an aquifer if nobody steers it.

**Warren (Tier 1; 20 stone).** A 5×3 colony of 3 mites that digs out a zone set relative to the Warren, picked in its panel the way a Drill's direction is. Nothing gets highlighted.

| Zone | Shape and size |
| --- | --- |
| Pit | 7 wide × 8 deep, below it |
| Gallery | 10 long × 5 tall, to the left or right |
| Den | radius 5, all around it |

- Mites work outward from the Warren, nearest reachable cell first: dig it, haul it home, bank it.
- They cling to any surface, drown after 5 s underwater, and die in lava or steam. The Warren breeds a replacement every 20 s for 2 stone.
- They dig everything in the zone, including the wall between them and whatever the fog was hiding, until you research Sounding.
- Tier 1 mites dig only soft ground (dirt, loose dirt, rubble). Hard Teeth adds stone and glimmer; Ember Brood adds hot rock.
- A finished zone can be swapped for another shape or side, or the Warren can Advance to the far edge of what it dug.

## Heat

Below depth 600 the rock is hot, and nothing cuts it without a heat tech: Drills and early mites stop at the line. Coolant Jacket lets a Borer through for 1 water per 20 cells, vented as steam out of its tail, up your shaft and onto any Conduits in it. Ember Brood lets mites through, though they still die in lava. Either way the last third of the descent gets planned: water and power delivered to the front, and the power line kept out of the chimney (or a Steam Turbine put in it).

## The Crucible finale

The recipe stays at 32 Glimmer, 48 Obsidian and 64 Water, and charging now also draws a steady 4 power/s. If deliveries stop for 5 s the charge drains, as before. Tremors still shake 200 stone cells loose every 15 s, now onto a network carrying its heaviest load; Tremor Dampers spare whatever sits within 12 cells of one. The finale tests everything you built on the way down.

## Build order

Ten phases, each ending in something playable. Phases 1 to 4 are done; everything after phase 3 was redrawn once phase 3 was done.

| Phase | Builds | Playable after |
| --- | --- | --- |
| 1 · Scale and fog (done) | Smaller footprints and ranges, a closer camera that pans both ways, fog of war with vision from buildings | The MVP at the new scale, half-blind |
| 2 · Power (done) | Power, reserves, delivery from several sources, power costs on machines; Waterwheel, springs, Cache, Lamp | The topsoil, played with upkeep |
| 3 · Research (done) | Lab, Research tab, discoveries and prerequisites, a build bar driven by unlocks, Tuned Bit and Long Shaft | The first real v2 loop |
| 4 · Engine (done) | The sim rebuilt in C++ on Noita's architecture; materials and reactions in a data file | The same game, much faster |
| 5 · Chemistry | Fire, gases, free particles, explosions, simple temperature; Coal and Sulfur; breakable links | A world that reacts |
| 6 · Digging | The fixed Drill and its upgrade tiers, the Thumper, the Borer with return-to-base; the tech tree redrawn | The new descent |
| 7 · Warren | Warren and mites, living with the new hazards | All the digging tools |
| 8 · Collapse | Crumbling terrain and Struts; rigid chunks if the engine has room | Cave-ins |
| 9 · Depth | Heat, deeper materials and curios, the Crucible's power draw | Start to finish |
| 10 · Pacing | The incremental curve, then the autoplay bot and tuning | A tuned run |

## Held for later

- Blasting charges and cave-ins in wide caverns: both fit the cascade idea, and both wait until v2 plays well.
- A research queue, sound, a title screen and saving.

## Decisions

- [x] Names stay for now: power, Borer, Warren, mites.
- [x] The Drill becomes one fixed, upgradeable machine next to the Hub (was: buildable, very slow, with speed and reach research).
- [x] Tiers open by discovery, and techs by finishing their parents.
- [x] The sim moves to C++ on Noita's architecture, and that port comes before any new gameplay.
- [x] Collapse starts as crumbling; rigid chunks come later.
- [x] The Warren stays as designed, and mites interact with the new systems.

## Open questions

- [ ] How close the camera sits: 1.5× is the starting guess, 2× if the network still feels big.
- [ ] Which materials join Coal and Sulfur (being drafted).
- [ ] How a Thumper gets its power while it's bouncing around.
- [ ] How wide the fixed Drill's shaft is, and whether it can turn.
