# Crucible: ideas parking lot

Alex's notes, brainstorms and wants that aren't scheduled yet. Kept by the "ideas" chat.
Phase sessions don't read this by default; open it when Alex points a phase at an entry.
Each entry: what Alex asked for, a rough phase, and short notes on where it touches what
already exists (hooks and friction), with open questions. Nothing here is decided until it
moves into PROJECT_BRIEF's roadmap or standing decisions.

---

## Where these landed (Alpha plan, 2026-10-01)
Scheduled in claude/ALPHA_PLAN.md and PROJECT_BRIEF's Alpha roadmap. The entries below stay as the
original notes.
- 1 (power): Windmills are in the starter kit (A3) and the Hub's trickle drops to about 0.2/s.
  Solar, Thermoelectric Plate, Combustor and a geyser or oil Tap are parts in the catalogue
  (A5, A6).
- 2 (fuck around and find out): the Gantry, Winch and Turntable replace movable buildings (A4).
  The tutorial is written as Hub instructions and is skippable. The Warren is repurposed as the
  Drone Cage hauler.
- 3 (enemies) and 7's curios, wreckage, weather: parked past Alpha. 4 (mites as bodies): done in 8d.
- 5, 6 and 8 (refining, composites, pixel handling): A3 to A5. Vessel modules, Bus Hopper
  import and export, Mk I to IV upgrades paid in refined goods, Pump, Sieve, Blower and Caster.
- 7's byproducts and hazard-proofing: byproducts fall out of the temperature and reaction rules;
  hazard-proofing is picked up by the Mk upgrades.

---

## 1. Early power generation (logged 2026-09-28)
Rough phase: 9 (Depth) for deposits; the starter generator could land sooner.

**Alex:** There's a power system but almost no way to make power, especially early.
- **Windmills / Solar Panels:** the first generator, available from the start. A painfully
  slow free trickle. Windmills must sit on the surface; solar panels need a direct line to
  the top of the map (so one at the bottom of an open pit works).
- **Geysers / Oil / Nodes:** generate randomly underground. Once excavated, a machine placed
  on one produces power continually. Some are finite and run dry; others are unlimited but
  more dangerous and/or less efficient.
- **Hub's own power (added 2026-09-28):** windmills don't replace the Hub's built-in trickle;
  the Hub's rate gets nerfed slightly to make room for them.

**Hooks and friction**
- What exists now: the Hub's built-in floor trickle, the Waterwheel (T1, falling water),
  Coal (1 power when banked; seams are already a finite power deposit), Caches as storage.
  Steam Turbine (phase 9: steam rising through it; steam only from what the player stages).
- Solar is nearly free to build: the engine already lights cells with sky light down open
  shafts, per cell, with rock shadows. A panel can read the light on its own cells, so the
  pit rule falls out on its own, and anything that later roofs the shaft (a cave-in, a Strut,
  another building) quietly dims it.
- Rescale (8b) makes the surface 2-3x wider, which is more room for windmills.
- Geysers are a cousin of springs (springs already add water forever). A steam geyser gives
  the Steam Turbine a natural home; its danger is the scald that already hits Conduits.
- Oil would be a new material (flammable liquid). Alex wants to design the wider material set
  before more are implemented, so it belongs in that list.
- Open: does the geyser/oil machine need the deposit fully uncovered, or just touching it?
  Finite deposits: fixed amount, or a slow refill?

---

## 2. Gameplay feel: "fuck around and find out" (logged 2026-09-28)
Rough phase: 10 (Pacing), though the rescale (8b) touches the same overlay code.

**Alex:** The feeling should be letting the player try things and see what happens, rather
than planning and getting sad when it doesn't work. Less emphasis on telling the player how
an action will affect them or the environment.
- **Few or no guides:** little or no visual indication of building ranges and areas of effect.
  Players shouldn't know exactly what or how much a machine will dig until it's done it.
- **Movable buildings, Creeper World style:** click-drag a selected building and it slowly moves
  itself to the spot. Unlike Creeper World, it paths around terrain instead of floating
  through rock.

**Hooks and friction**
- Already in the spirit: the Warren (mites dig their own way to a marker, nothing
  highlighted), the Thumper (thrown by its own blasts), the Borer (runs until something stops it).
- Currently tells the player things: overlay draws the Warren chamber arc, the dashed line to
  its marker and the marker circle; placement ghosts snap to legal spots within 5; link and
  range lines; Strut span previews. Worth sorting into "what will happen" (candidates to strip)
  and "is this legal / is this linked" (plausibly stays) when it's picked up.
- Moving buildings meets the anchoring rule: a building that crawls along surfaces stays
  anchored as it goes, which fits. The Thumper is already draggable (it's thrown, not walked).
- Conflicts with standing decisions: the Warren never moves (no Advance) and the Drill is fixed.
  "All buildings movable" would reopen the Warren one; the Drill, Hub and Crucible are likely exempt.
- Open: does a moving building keep its links while it travels, or drop them and relink on
  arrival? Does it work while moving? What happens if the ground under it caves mid-trip
  (overlaps rigid bodies, 8c)?

---

## 3. Enemies (logged 2026-09-28)
Rough phase: after the planned roadmap (post-10).

**Alex:** Enemies, Noita-style: they interact with the particle sim in satisfying ways (acid
spit, oil blood), with some ways to defend against them. Mainly for pace disruption.

**Hooks and friction**
- Mites (warren.gd) are the existing creature code: BFS pathing, a state machine, and deaths by
  burning, drowning, choking and crushing. Enemies can likely share the plumbing, more so if
  mites become rigid bodies first (entry 4).
- Materials are data, so spit and blood are just materials: acid spit behaves like sulfur's
  corrosion; oil blood overlaps with the Oil idea in entry 1 (a dead enemy as fuel, or as a fire).
- Pace disruption ties into phase 10's incremental curve.
- Open: where they come from (nests or curios uncovered while digging would fit "uncover curios");
  what they want (buildings, links, the Crucible, power?); the defence toolset (turrets, or
  sim-based: flood the tunnel, light it on fire, collapse it on them).

---

## 4. Mites as rigid bodies (logged 2026-09-28)
Done in phase 8d, as a hybrid: walking and clinging stay the creature's own; physics
(falling, throws, crushing, piling up) takes over whenever it loses its grip or is hit,
and hands it back once it lies still. Kept below for the reasoning.

**Alex:** Once rigid-body physics is in, mites should become rigid bodies by default instead of
"very smart pixels".

**Hooks and friction**
- Today a mite is a single coloured cell with a state machine and BFS pathing in warren.gd.
  The rescale (8b) already makes structures 10x bigger against the pixels, so a one-cell mite
  would look even smaller next to a 10x Warren; rigid-body mites can be sized with everything else.
- What rigid bodies would give them for free: falling, being thrown by Thumper blasts, being
  crushed by falling chunks with real weight, piling up.
- Pathing still has to live somewhere: the digging rule (nearest reachable cell, per-cell wobble)
  stays, the movement between cells becomes physical. The BFS may need to treat "reachable" as
  "walkable by a body this size".
- Makes a shared creature base for enemies (entry 3) more natural.

---

## 5. Refining and processing (logged 2026-09-28)
Rough phase: unassigned; likely alongside 9 (Depth, new materials) or before 10 (Pacing).

**Alex:** The game is begging for processing: oil refining, ore smelting, crafting/fabrication,
maybe chemical synthesis. A series of buildings that turn resources into better resources, which
also adds more traffic to the network.
- **In-world preferred (added 2026-09-28):** Alex adores the idea of refining and resource
  management happening in the sim. Condition: the ways of manipulating pixels have to fit the
  automation-only rule (buildings do everything) and must not be frustrating or finicky. See entry 8.

**Hooks and friction**
- Resources now: Stone, Glimmer, Obsidian, Water, Power, moved as packets. Consumers today are
  construction, Labs (power, then Glimmer/Obsidian at later tiers) and the Crucible recipe.
  A processing chain adds packets in both directions (raw in, product out), which is exactly the
  network load the packet priority system was built to arbitrate.
- Heat (phase 9) is a natural gate for smelting and refining.
- Materials design ties in: refined goods need raw inputs, and Alex is drafting the wider material
  set. Oil (entry 1) is already a candidate raw input.
- Sinks for refined goods: later tech costs, the Crucible recipe, better buildings (e.g. Conduits
  that resist lava or sulfur), Strut upgrades.
- Open: how many new resource types the HUD and Caches can carry before it gets noisy.

---

## 6. How the ideas mesh (logged 2026-09-28)
Rough phase: framing for 9, 10 and post-10; not a feature on its own.

**Alex:**
- **Composite upgrades:** building upgrade tiers require more complex composite (refined) resources.
- **Defence as a sink:** with enemies, defensive buildings require or consume composite resources
  as ammo (Mindustry is the reference; that's roughly what this addition makes).
- **Heat as an environmental resource:** some machines need it to run, but it can't be harvested
  or carried over the network.

**Hooks and friction**
- Heat exists since phase 9 as a material: hot rock fills the Magma band (from about row 3000).
  Machines reading heat from their own cells works the same way solar would read light (entry 1).
- Composite upgrades give entry 5 (refining) its main sink.
- Tension with entry 2: factory chains are the most "plan it out and get sad" genre there is.
  Entries 5 and 8 keep processing on the sim side.

---

## 7. Claude's pitches (logged 2026-09-28)
Suggestions Claude made when Alex asked for input. Unmarked ones are not decisions.

- **Wreckage (Alex likes):** destroyed buildings drop scrap into the world, salvageable by Hoppers.
  Keeps catastrophes recoverable. Alex: a source of unique upgrades and structures (see Curios).
- **Curios (Alex likes):** the brief promises curios but nothing exists. Ideas: dead machines from a
  previous expedition (repair with Stone, unknown effect when powered), relics granting a modifier,
  pockets of exotic material. Alex: curios and wreckage should grant *unique* upgrades and
  structures available only through them.
- **Site resources:** generalise heat into a class of things a machine takes from where it stands
  and the network can't carry: heat, sunlight, falling water, rising gas, maybe depth/pressure.
  Solar, Waterwheel, Steam Turbine and the smelter become one rule. Placement matters, and
  movable buildings (entry 2) earn their keep: drag the smelter to the lava.
- **Byproducts go into the world:** every processor outputs a sim material (slag, fumes, waste water,
  spent oil). The factory keeps making hazards, which keeps it FAFO instead of a spreadsheet.
- **Enemies drawn by what the player does:** noise (Thumper blasts loud, Borer medium, mites quiet),
  heat, and light. Light is the sharpest: the fog system needs light to see, and light draws them.
  Attacks become a consequence of expansion instead of a timer.
- **Ammo that acts in the sim:** turrets fire materials (oil flamer, water cannon, acid sprayer,
  sand to bury). Defence is also terrain editing and can backfire (lighting your own coal seam).
- **Hazard-proofing as the resource spine:** each depth band's hazard is answered by a composite made
  from the band above (e.g. lava-proof Conduits need an obsidian composite, sulfur-proof links need
  a refined coating). Progression = what the network can survive.
- **Surface weather:** rain fills open pits, wind varies windmill output, lightning hits the tallest
  surface building. Environmental pace disruption before enemies exist.
- **Deadpan event log:** a feed narrating disasters in the game's tone ("Conduit 14 drowned.").
  Helps the player notice cascades they weren't watching, without telling them ahead of time.

---

## 8. Pixel handling for in-world refining (logged 2026-09-28)
Rough phase: with entry 5.

**Alex's condition:** new ways to move and manipulate pixels that fit automation-only and aren't
finicky.

**What exists:** Hopper (swallows cells, banks them), Spout (releases stockpiled water), Bulkhead
(walls), Floodgate (sensor-driven wall), Thumper (blasts), the diggers, Waterwheel (hollow core that
reads what flows through it).

**Claude's pitches (not adopted):**
- **Vessel buildings:** a refinery is a hollow chamber, like the Waterwheel's core. The network
  delivers packets, the building spits them into its own chamber as pixels, the reaction runs in the
  sim inside it, and a built-in Hopper at the bottom banks what comes out. The player never routes
  pixels by hand; the sim part is visible and contained, and it can still fail (cracked walls,
  overflow, a fire that spreads out of the vent).
- **Forgiving by construction:** wide intakes, overflow that spills out instead of jamming, recipes
  that tolerate impurity (lower yield, more slag) instead of failing outright.
- **Missing verbs:** nothing moves pixels sideways or up yet. Candidates: a Pump (liquid up a pipe
  from A to B), a Sieve (liquids pass, powders stay), a Blower (pushes gas).
- **Byproducts vent:** slag, fumes and waste leave through an outlet into the world (entry 7), which is
  where the FAFO comes back in.
- Open: do vessels read heat and light from their site (entry 7, site resources), or carry their
  own? Does a breached vessel spill its whole contents?

---

## 9. Shorer: a module that lays its own supports (logged 2026-10-05)
Rough phase: A5, Support group. Parked until Alex says go on A5.

**Alex:** A module that attaches to machines and lays support structures as needed, as long as it is
fed the right materials, so an up-facing Excavator can keep the walls intact while the machine keeps
excavating the roof.
- Touches: the Laser Excavator's filler swap (refills only the cells it mines), the Press (makes the
  Stone blocks a Shorer could be fed), Brace and Bulkhead (the hand-placed supports it would replace).
- The A4 bot runs lost the shaft to cave-ins above the rig (Tank full, shaft plugged with Dirt and
  Stone), so the module would have to shore behind the rig as it passes.
- Open: does it lay casing cells or place Braces? Which materials hold, and how much does a metre
  of shaft cost? Does it share the cutter's mount face or take its own?
- Probe first: an up-facing Excavator on the cheated bot (placement rotation already exists) shows how
  much shoring a shaft needs.

---

## 10. Machine interiors and pocket dimensions (logged 2026-10-05)
Rough phase: interiors now (before A5 part 3); pocket dimensions after Alpha.

**Alex:** each machine runs its own pixel sim inside it instead of reaching into the world's. It moves with
the machine and resizes as modules change. Feasibility write-up: plans/pocket-sim-feasibility.md in the project files.
- Interiors (in the build): `interior: true` in a definition, `scripts/machines/interior.gd`; the Tank first. Gravity
  is down in the machine's frame. A breach leaks the interior out gradually, faster the more casing is gone
  (Alex's call, 2026-10-05, over the full "dissolve into the world at once" version: a 9000-cell Tank released in one
  tick would flood the world sim).
- Pocket dimensions (parked): a separate, persistent sim made by a machine, never dissolved into the world. Only
  machines nest a sim in the world sim. A dimension freezes while nothing powered is dialed to it, and it is
  inaccessible while its link is severed.
- Dialing (Alex, borrowing RFTools): a dimension is a registry record keyed by an ID, so several Projector modules
  can dial the same one and move goods in and out. Creating one is a menu of properties (Dimlets, simplified):
  size, ambient temperature, gravity, terrain mix, chemistry variant. Confirming asks the Projector for a large
  amount of goods whose type and rarity follow the spec. Every property is already settable per sim instance
  (`configure`, `set_fall`, `set_ambient`, `set_size`).
- Open: where IDs come from and what they cost; what goods leaving a random-chemistry pocket are worth outside;
  whether a dimension survives its builder machine (the registry says yes).
