# Crucible: Wave 1 materials (A2 design table, built)

Design table for the twelve wave 1 materials of phase A2 in `ALPHA_PLAN.md`. Built in A2 on
top of A1's temperature field: the data is in `data/materials.json` (ids 35 to 53), the
engine extensions in `native/src/crucible_sim.cpp`, the home ranges in
`data/spawn_regions.json`, the bench demonstrations in `tests/scenario_wave1.gd`. The tables
below are the design as written; "Built as" at the end lists where the build differs, and
the build wins where the two disagree.

## Assumptions about A1 (checked against A1's code: see "Built as")

1. **Temperature units.** One signed number per cell, called degrees. Water freezes at 0 and
   boils at 100. Ambient is about 15 on the surface, about 30 through the Stone band and rises
   through the Magma band to a few hundred. Lava sits near 1100 and freezes to Obsidian at 700.
   Stone melts well above 1200, so ordinary rock never melts unless something hotter than lava
   pushes it.
2. **Material data fields.** `melts_at`, `boils_at`, `freezes_at` (each with a target material),
   `conductivity` (0 to 1; Water 0.5, Stone 0.3, Air 0.02) and `families` (one or two tags). A
   per-material `heat_mass` (default 1; higher cells take more heat to move) is wanted for Rime
   and is the one field this doc adds. If A1 has no such number, Rime falls back to the
   reaction rows noted in its entry.
3. **Engine extensions.** The four named in the plan arrive with A1: the catalyst modifier on
   reaction chance, impact triggers from per-cell fall speed, a one-cell-to-many swell and a
   timed setting stage in the aux byte. Wave 1 also needs two the plan does not name: a
   reaction that emits a rigid body (Ferrite bars) and a reaction that reads what a cell soaked
   up (swollen Bloat). Both are flagged where they appear.
4. **Reaction notation.** `A + B -> A' + B' @chance` as in today's data, where A and B may be
   a material or a family tag, `T>=n` is a temperature condition on either cell, and `x3` is
   the catalyst multiplier. A family rule expands to one row per member pair.
5. **Existing materials get tags.** The migration is A1's job. The table in "Family list" is a
   suggestion so the wave 1 rules have something to match.

## Family list (settled for wave 1)

Sixteen tags. One or two per material, reactions written between families first and
per-material overrides after. "Cold" from the plan is dropped: with a real temperature field
cold is a number, and Water freezing and Lava quenching are melting-point data.

| Family | Meaning | Members, existing and new |
|---|---|---|
| Aqueous | water-based fluids | Water, Steam, Sourwater |
| Molten | liquid rock and metal | Lava, Slag |
| Mineral | solid ground that acid wears | Stone, Dirt, Packed dirt, Gravel, Clay, Hot rock, Obsidian, Glimmer, Glass, Mire stone |
| Granular | loose powders that cement can bind | Loose dirt, Rubble, Sand, Ash, shards, Sulfur grit, Coal chunks, Flux |
| Flame | open fire | Fire |
| Fuel | burns for a long time | Coal, Coal chunks, Sulfur, Sulfur grit, Slick |
| Volatile | flashes into a blast or flame when lit | Wisp |
| Corrosive | eats ground, metal and buildings | Sulfur, Sulfur grit, Sulfur fumes, Sourwater |
| Binding | sets loose material into rock | Quickmire |
| Catalytic | speeds reactions beside it, unspent | Flux |
| Absorbent | soaks liquid and swells | Bloat, swollen Bloat |
| Crystalline | resists acid, shatters on impact | Glimmer, Obsidian, Glass |
| Shock-sensitive | detonates on impact or heat | Rattle |
| Smothering | puts out flame and fuel fires | Hush |
| Metallic | conducts well, smelts | Ferrite, Slag |
| Mimetic | spreads by converting what it touches | Weft |

Obsidian and Glimmer carry two tags (Mineral and Crystalline), as does Sulfur grit (Granular
and Corrosive), Sulfur (Fuel and Corrosive) and Sourwater (Aqueous and Corrosive). Crystalline
resisting Corrosive means acid strips Stone off a Glimmer vein and leaves the crystal standing.

## The twelve

Densities follow the existing scale (Water 10, Lava 30, Sand 50). Conductivity is on the 0 to
1 scale above. `heat_mass` only where it differs from 1.

| Name | Phase | Density | Families | Melts | Boils | Freezes | Cond. | Colour |
|---|---|---|---|---|---|---|---|---|
| Slick | liquid | 8 | Fuel | - | 260 -> Smoke | thickens at -30 | 0.10 | `#2b2216` / `#6a4d8c` sheen |
| Sourwater | liquid | 12 | Aqueous, Corrosive | - | 105 -> Sulfur fumes | -5 -> Ice | 0.50 | `#a6c92b` / `#d8e65a` |
| Hush | gas | 8 (buoyancy -4) | Smothering | - | - | - | 0.03 | `#5d6f8c` / `#7f90ad` |
| Quickmire | liquid | 14 | Binding | - | 350 -> Smoke | - | 0.30 | `#d9c4a0` / `#b89c70` |
| Flux | powder | 40 | Granular, Catalytic | 1000 -> Slag | - | - | 0.20 | `#cfc3d9` / `#f0eaf5` |
| Ferrite | static | 90 | Metallic | 1250 -> Slag | - | - | 0.80 | `#6d4a45` / `#a3665a` |
| Rattle | powder | 55 | Shock-sensitive | - | - | - | 0.15 | `#9c2f5e` / `#d9a0b8` |
| Bloat | powder | 12 | Absorbent | - | - | - | 0.05 | `#e8dcc0` / `#c9b98d` |
| Glass | static | - | Crystalline, Mineral | 1700 -> Lava | - | - | 0.25 | `#a8dce6` / `#ffffff` |
| Rime | static | - | (none; heat_mass 20) | 10 -> Water | - | - | 0.90 | `#9bd0f2` / `#e8f6ff` |
| Wisp | gas | 1 (buoyancy +4) | Volatile | - | - | condenses at -20 -> Slick | 0.02 | `#f2e6ff` / `#b58cff` glow |
| Weft | static | - | Mimetic | dies at 80 -> Ash | - | dormant below 5 | 0.10 | `#4e6b3a` / `#9fb56a` |

Glass melting at 1700 puts it out of reach of Lava, so it stays. Sand gets the new data row:
Sand melts at 900 -> Glass, and Lava's neighbours reach that.

### Derived materials

Produced by reactions, not authored as part of the twelve. They count toward the Alpha total
of about 25 and appear in the home table only where stated.

| Name | Phase | Made by | Notes |
|---|---|---|---|
| Mire stone | static | Quickmire setting | Mineral, durability 6, cohesive, kin Stone, breaks to Rubble at 450. |
| Slag | liquid above 700, static below | Ferrite or Flux melting, smelting | Molten and Metallic. Freezes at 700 to Slag crust (static, durability 4, no yield). |
| Swollen Bloat | powder | Bloat soaking a liquid | Absorbent, density 20, aux byte holds what it soaked. |
| Ice | static | Water below 0 | May already exist after A1; listed so the Rime and Sourwater rows have a target. |
| Ferrite bar | rigid body | smelting | A body, not a cell material. Fallback if A1 cannot emit bodies: a static Ferrite ingot cell. |

## Reactions by family

Written first, as rules between families. Numbers are per update of either cell unless stated.

| Rule | Effect | Chance |
|---|---|---|
| Fuel + Flame, or Fuel at its flash point | ignites per the material's `burn` block | per `burn.ignite` |
| Smothering + Flame | Flame -> Air | 0.5 |
| Smothering + a burning cell | the burn stops, the cell keeps its material | 0.5 |
| Corrosive + Mineral | Mineral -> Rubble, Corrosive spends (Sourwater -> Water, fumes thin) | 0.01 per contact, spend 0.3 |
| Corrosive + Metallic | Metallic -> Rubble | 0.03 |
| Corrosive + Crystalline | nothing | - |
| Binding + Granular | both start the aux timer; after about ten seconds both become Mire stone | 1.0 to start |
| Catalytic beside any reacting pair | chance x3, capped at 1.0, Catalytic unspent | modifier |
| Absorbent + any liquid | liquid cell consumed, Bloat becomes swollen Bloat and a neighbour cell fills with swollen Bloat | 0.1 |
| Shock-sensitive + (impact over 300 cells/s, or T>=140, or Flame, or a blast) | blast, radius 6 | 1.0 |
| Volatile + (Flame, or T>=120) | flash: Fire burst plus a radius 3 blast | 1.0 |
| Metallic + Catalytic, T>=850 | smelt: Metallic -> Slag, Catalytic stays; one Ferrite bar per 40 smelted cells | 0.02 |
| Mimetic + Granular or Dirt, while touching Aqueous within 2 cells | converts the cell to Weft, drinks the water cell (Aqueous -> Air) | 0.003 |
| Crystalline + impact over 400 cells/s | shatters to Sand (Glimmer and Obsidian keep their own shards) | 1.0 |

The catalyst does not apply to Shock-sensitive triggers, so Flux never sets off Rattle on its
own. It does apply to the Binding timer, so Flux beside Quickmire sets it in about three
seconds.

## Per material

Each entry: reactions beyond the family table (overrides), home range, lab bench recipe. The
bench recipes assume A1's bench: paint any material, see temperature, with a Lava and a Fire
brush available as heat sources.

### 1. Slick
- Reactions: the Fuel rules, flash point 150, `burn.life` 600 (Coal chunks is 150). Floats on
  Water and spreads thin; the burning film rides the surface. Override: Slick + Lava ignites
  at once. Slick + Sourwater and Slick + Water do not mix.
- Cold: thickens at -30 (the `slow` value rises to 12), no material change.
- Home: Topsoil, y 700-1500, any x. Region: a seep pocket against the roof of an aquifer, 3 to 4
  per seed, about 3,000 cells each. Also in the Spoil Heap as a puddle.
- Bench: paint Slick over Water, then drop Fire on it. Flame crawls across the surface for about
  ten seconds. Add Hush above and the flame dies.

### 2. Sourwater
- Reactions: the Corrosive rules. Override: Sourwater + Metallic -> Wisp + Rubble at 0.03
  (acid on ore bubbles off a light gas). Sourwater + Sulfur grit -> Sulfur fumes + Sourwater at
  0.2, which is today's "a lot of fumes". Sourwater + Water -> Water + Water at 0.002 (a flood
  dilutes it). Sourwater + Weft -> Rubble + Rubble at 0.2.
- Home: Stone band, y 2000-3000. Region: a water pocket beside a Sulfur deposit, 2 per seed,
  about 2,500 cells. It sits denser than Water, so it sinks to the pocket floor.
- Bench: pour onto Stone and watch it pit to Rubble while the pool turns to Water. Pour onto
  Ferrite: Wisp rises. Pour onto Glass: nothing.

### 3. Hush
- Reactions: the Smothering rules. Override: Hush + Wisp -> Air + Air at 0.2. Hush + Rattle
  inhibits detonation while Hush is adjacent. Chokes mites and drones through a `smothers` flag
  the Warren and Drone Cage read; harmless to buildings.
- Gas: density 8, buoyancy -4, no `vents`, so it pools on cave floors and thins slowly (life
  600 to 900).
- Home: Stone band, y 1500-3000. Region: a cave floor, one cave in three holds a layer 4 to 8
  cells deep. Seeps in over time from cracks, so there is no hand-placed hazard marker.
- Bench: Fire above a Hush layer goes out as it falls through. A Rattle pile under Hush survives
  a lit match.

### 4. Quickmire
- Reactions: the Binding rule. Water does not stop it. Heat above 450 breaks Mire stone back to
  Rubble. Override: Quickmire + Flux sets in 3 seconds (the catalyst rule); Quickmire + Rattle
  binds the Rattle and defuses it.
- Home: Topsoil, y 400-1500. Region: the Clay lining of an aquifer, a pocket 600 to 800 cells
  behind the lining. A leak under the lining sets whatever powder is below.
- Bench: pour over a Sand pile, wait ten seconds, the pile is Mire stone. Add Flux and time it
  again.

### 5. Flux
- Reactions: the Catalytic modifier. Override: melts at 1000 -> Slag, so Lava eats it.
  A Flux cell beside Hot rock + Water raises that pair's 0.05 to 0.15.
- Home: Stone band, y 1700-2800. Region: pale horizontal seams, same generator as Glimmer
  seams, about 12,000 cells per seed spread over 3 to 4 seams. Also the Spoil Heap as a pile.
- Bench: Coal chunks burn at their normal rate; Coal chunks with Flux beside burn faster.
  Ferrite plus Lava with and without Flux shows the smelt.

### 6. Ferrite
- Reactions: the Metallic rules. Smelting needs Flux and T>=850; the products are Slag and
  Ferrite bars, and the bars are the first rigid body emitted by a reaction. Conducts heat at
  0.8, so a vein pipes heat from a lava pocket upward and the bench shows a glow running along
  it.
- Dig: durability 8, `dig_rate` 12. Yields Stone at worth 6 until A3 adds goods banks.
- Home: Stone band lower half and the top of Magma, y 2400-3600. Region: a vein like a Glimmer
  seam, kept within 40 cells of a lava pocket, about 20,000 cells per seed. Smelting happens
  by itself where Flux seams reach it, so some tunnels start already half-forged.
- Bench: Ferrite, Flux and Lava in a row. Bars drop out after a few seconds, Slag pools under
  them.

### 7. Rattle
- Reactions: the Shock-sensitive rules, detonation threshold 300 cells/s of fall speed (a fall
  from about 30 cells), 140 degrees. Chains through neighbouring Rattle cells. Override: Rattle
  + Sourwater -> Rattle + Rubble at 0.01 (acid wears the casing off, the cell then goes off).
- Home: Stone band, y 1800-2900. Region: a sealed powder pocket in solid stone, 6 per seed, about
  400 cells each. The stone holds it, and digging under it drops it.
- Bench: drop a column from height and count the bangs. Heat a single cell with Fire.

### 8. Bloat
- Reactions: the Absorbent rule. A soaked cell is swollen Bloat with the liquid recorded in the
  aux byte. At 100 degrees it bursts into a plume that depends on what it soaked: Steam for
  Aqueous, a Fire flare for Fuel, Sulfur fumes for Corrosive. Dry Bloat ignites at 180 and burns
  to Ash and Smoke. Swollen Bloat from Slick burns for a long time (`burn.life` 600).
- Home: Topsoil, y 300-900. Region: dry puffball pockets in Dirt, at least 20 cells away from any
  aquifer, 5 per seed, about 600 cells each. A few sit one cell off an aquifer lining by design.
- Bench: Bloat in a basin, add Water, watch the basin overflow with swollen cells. Heat it and
  count the steam.

### 9. Glass
- Reactions: Sand + Lava reaches the data row: Sand melts at 900 -> Glass. The Crystalline
  rules: immune to Sourwater, shatters to Sand on a hard impact. Light passes at `opacity` 1.
  Glass makes a casing candidate for the A3 module walls and the Tank, since acid does not
  touch it.
- Home: Magma band, y 3000-3800. Region: a vitrified rim, 2 cells thick, around lava pockets,
  sparse. Mostly a made material: Sand and Lava meeting at the bench or in a built furnace.
- Bench: paint Sand and Lava side by side. A clear seam forms at the line within seconds.

### 10. Rime
- Reactions: `heat_mass` 20, born at -60. Neighbours drop toward it by conduction (0.9); Water
  next to it reaches 0 and freezes to Ice, Lava reaches 700 and freezes to Obsidian, both from
  melting-point data. The cell is consumed: it warms until 10 degrees and becomes Water.
  Fallback if A1 has no `heat_mass`: Rime + Water -> Rime + Ice at 0.1 and Rime + Lava -> Rime
  + Obsidian at 0.2, with Rime becoming Water at 0.002.
- Override: Wisp + Rime -> Slick (cold condenses the gas into oil). Slick next to Rime
  thickens.
- Home: Stone band, y 1800-2800. Region: a frost halo, 3 to 4 cells thick, around a water pocket,
  3 per seed, about 1,500 cells. Worldgen leaves the Water inside, and the temperature field
  freezes the rim at load. A chip also goes in the Spoil Heap.
- Bench: Rime beside Lava quenches it to Obsidian. Rime beside Water freezes a ring of Ice.
  Rime in a Wisp cloud rains Slick.

### 11. Wisp
- Reactions: the Volatile rules. Glows on its own (`light` 40, radius 8), so opening a pocket
  lights the cave. Override: Wisp + Hush -> Air + Air at 0.2. Condenses at -20 to Slick. Drifts up
  and vents at the top, life 400 to 800.
- Home: Stone band, y 2000-3200. Region: a sealed gas pocket, 4 per seed, about 1,200 cells. Also
  made by Sourwater on Metallic. Unopened pockets glow faintly through the fog.
- Bench: Wisp and Fire flash. Sourwater over Ferrite fills the bench with Wisp. A lit Wisp cloud
  over Slick shows the chain.

### 12. Weft
- Reactions: the Mimetic rule, so it spreads only where Water is within 2 cells. It converts Dirt,
  Loose dirt and Sand, not Clay or Stone. Weft cells are weak (durability 1, span 20), so a
  patch undermines what it spreads through. Dormant below 5, dies at 80 to Ash. Burns slowly
  (`burn.life` 120). Override: Weft + Hush -> Ash + Hush at 0.05. Weft + Rime goes dormant.
- Home: Topsoil, y 300-1300. Region: a seed patch in Dirt within 8 cells of an aquifer's outer
  edge but outside the Clay lining, 2 per seed, about 150 cells. Also the Spoil Heap.
- Bench: a Weft cell in Dirt beside a Water cell. Watch it eat sideways and drink. Add Rime or Lava
  to stop it.

## Home table for the spawn-region data

Depth bands are the worldgen bands: Topsoil y 200-1500, Stone 1500-3000, Magma 3000-4500,
Bedrock below. W was 768 and is 1024 since A6, so x is in fractions of width. The
region kind names are the ones the spawn-region thread should support; where its schema calls
them something else the rows map one to one.

| Material | Depth band (y) | x | Region kind | Per seed | Cells each |
|---|---|---|---|---|---|
| Slick | Topsoil 700-1500 | 0.05-0.95 | pocket, against an aquifer roof | 3-4 | 3,000 |
| Sourwater | Stone 2000-3000 | 0.05-0.95 | pocket, beside a Sulfur deposit | 2 | 2,500 |
| Hush | Stone 1500-3000 | any | cave floor layer | 1 in 3 caves | 4-8 deep |
| Quickmire | Topsoil 400-1500 | 0.05-0.95 | pocket behind an aquifer lining | 4 | 700 |
| Flux | Stone 1700-2800 | any | seam | 3-4 seams | 12,000 total |
| Ferrite | Stone 2400 to Magma 3600 (moved in A5, see "Built as") | any | vein within 40 cells of lava | 3 veins | 20,000 total |
| Rattle | Stone 1800-2900 | 0.05-0.95 | sealed pocket in rock | 6 | 400 |
| Bloat | Topsoil 300-900 | 0.05-0.95 | pocket in Dirt, 20+ from aquifers | 5 | 600 |
| Glass | Magma 3000-3800 | any | rim, 2 cells, around lava pockets | per lava pocket | crust |
| Rime | Stone 1800-2800 | 0.05-0.95 | rim, 3-4 cells, around a water pocket | 3 | 1,500 |
| Wisp | Stone 2000-3200 | 0.05-0.95 | sealed gas pocket | 4 | 1,200 |
| Weft | Topsoil 300-1300 | 0.05-0.95 | seed patch, near an aquifer edge | 2 | 150 |

Every placement draws from its own random stream, so cell checksums for seeds 5, 7, 11 and 23
hold outside the new regions (the A2 exit check). Pocket counts and sizes are first guesses
and get tuned in A2 with the checksum and the 0.7 ms tick in view.

### Spoil Heap

A hand-placed pile near the Hub, the first user of the region system. Optional and
unexplained, as the plan says. Contents:

- A Slick puddle in a dirt basin.
- A Flux pile.
- A Rime chip, kept away from the Water.
- A Weft patch, small, with a patch of Dirt to feed on. The first thing a player learns is to
  dig it out.

Position: within 120 cells of the Hub rect, on the surface at y 215-300, on the side of the Hub
that the pad does not already use. The spawn-region thread owns the exact rule.

## Lab bench demonstrations

The A2 exit check is that every wave 1 reaction runs on the bench. A bench scenario for each
row of the family table and each override, in this order:

1. Slick fire on Water, snuffed by Hush.
2. Sourwater on Stone, Ferrite and Glass.
3. Quickmire on Sand with and without Flux.
4. Flux catalysing Hot rock + Water, Coal chunks, Quickmire.
5. Ferrite smelted with Flux and Lava to bars and Slag.
6. Rattle by fall, heat and chain.
7. Bloat soaking Water, Slick and Sourwater and bursting each.
8. Sand + Lava -> Glass.
9. Rime quenching Lava and freezing Water.
10. Wisp flash, Wisp + Hush and Wisp + Rime -> Slick.
11. Weft spreading, then stopped by Rime, Hush and fire.
12. An unscripted pass: the bench loaded with every wave 1 material in one basin, left running.
    Alex wants chemistry that surprises, so this one is the test that nobody has predicted the
    outcome of.

## Open questions

- **Count.** Twelve authored plus five derived puts wave 1 at 17, or 16 if A1 already supplies Ice. If the 25
  target for Alpha counts authored materials only, wave 2 grows by five.
- **Resource yields.** (A5 part 1: settled.) The wave 1 materials a recipe could want carry `good` in the data and
  bank as goods under their own id at worth 6; none of them pays Stone or Water any more.
- **Heat mass.** Rime wants `heat_mass`; confirm against the A1 field list when A1 is pushed.
- **Body emit.** Ferrite bars need a reaction that creates a rigid body. If A1 does not provide
  one, the ingot fallback stands until A3's Caster.
- **Weft near the Hub.** A fed spreader next to the base is a choice. Drop it from the Spoil Heap
  if Alex would rather it not be there.
- **Home ranges** are first guesses. The spawn-region thread's schema decides final field names.

## Built as

A1's real schema, then the places the build differs from the tables above.

**A1 checks.**
- Temperature units hold: degrees, water 0 and 100, ambient by depth. Two numbers differ: lava
  quenches to Obsidian under 600 (not 700) and holds itself at 1100, so a cold neighbour never
  drags it down on its own. Stone turns to Hot rock at 800 and anything over 1200 melts.
- A1 names the points `heats` and `cools` ({at, to, cost}) and `conduct`; it had no `heat_mass`.
  A2 added `heat_mass` (Rime is 20): a cell's degrees move by its pass's change divided by it,
  so Rime takes 20 times the heat to warm.
- A1 had no rigid body emitted by a reaction. A2 adds it: a reaction can `emit` a material
  that has a `body` size, and the engine forges that body beside the reacting cells.

**Engine extensions** (all data driven, run by the cell pass; blasts and bodies run after it
in position order so thread count never matters):
- `sets` {to, speed, catalyst, boost}: the setting stage. aux counts down from `life`.
- `blast` {radius, power, impact, temp, flame, inhibit}: impact triggers from per-cell fall
  speed, heat, adjacent fire; the like of it within the radius goes off a few ticks later (a
  wave); a cell of the `inhibit` family touching it holds it back.
- `absorbs` {to, chance} and `bursts` {at, into}: the swell. The swollen cell keeps the
  liquid's id in aux; a liquid's `plume` says what a swollen cell of it bursts into.
- `grows` {over, feed, reach, chance}: Weft's spread.
- `burn.catalyst`/`burn.boost` (Flux speeds a burn), `burn.wet` (Slick keeps burning on water;
  Hush still puts it out), and a reaction with chance 0 (it blocks the family rule it would
  match without doing anything, and doesn't keep cells awake).
- A reaction that leaves a side as it was no longer rewrites that cell, so a setting cell
  keeps its timer.

**Numbers and rules that changed.**
- Impact: Rattle goes off over 240 cells a second of fall speed (about a 32 cell drop; the
  300 in the table is a 50 cell drop at today's gravity).
- Slick: `burn.life` tops out at 255 in the engine, so 600 is out. It burns 120 steps at 0.15, at
  170 degrees (flash point 150), which crawls over a film in about 15 seconds. Thickening at
  -30 is dropped: nothing in the engine takes a viscosity change from temperature yet.
- Corrosion: only Sourwater eats Mineral. Sulfur, Sulfur grit and fumes are Corrosive too, and
  sulfur nodules sit inside Stone, so the family rule as written would dissolve the ground
  round every deposit. Sourwater + Mineral is 0.004 and spends the acid cell every time (the
  table's 0.01 with a 0.3 spend needs two rules for one pair); Flux triples it. Sourwater +
  Water is 0.0003. The Metallic rule is written for Ferrite and Ferrite bars only (the family
  includes liquid Slag). Sourwater + Weft leaves Water and Rubble. Sourwater + Rattle warms the
  Rattle by 160 degrees, which sets it off.
- Quickmire: a Setting mire stage (id 51, Binding) sits between the liquid and Mire stone. The
  family rule Binding + Granular spreads it at 0.05; the timer is about ten seconds (about
  three beside Flux). Quickmire and Setting mire leave Flux alone, so the catalyst stays loose.
- Flux: Hot rock + Water boiling is a temperature rule in A1, so there is no reaction for the
  catalyst to speed. Flux triples Coal, Coal chunks and Slick burn rates, the setting timer,
  and the acid rules.
- Smelting: Ferrite + Flux at 850 degrees or more, 0.02, written for the material pair (Slag is
  Metallic too). One reaction in 40 forges a 6 x 2 Ferrite bar body (a random 1 in 40, not a
  count). The bar falls as a body and lies as static Ferrite bar cells once it settles.
- Glass: Sand's `heats` row (900 to Glass) stands, but a bench pass leaves Sand beside lava at
  about 120 degrees, so Sand + Molten -> Glass at 0.01 does the work. Glass has no per-cell
  impact rule: it breaks as a body, with a toughness from its durability of 3 (a 24 x 8 slab
  dropped 120 cells shatters to Sand).
- Rime: A1's lava holds 1100, so Rime + Lava -> Rime + Obsidian (0.2) is a reaction, as is
  Rime + Slag -> crust. Water freezing is plain temperature: Water `cools` at 0 to Ice (id 47,
  new), Ice melts at 3. Rime alone in open air at 20 degrees lasts well over half a minute.
- Bloat: only dry Bloat absorbs, and a soaked cell fills one open neighbour too (two or three
  swollen cells for each Bloat and liquid cell). Swollen Bloat keeps its liquid's id in
  aux, so it cannot also burn (burning uses aux): a soaked Slick cell bursts into Fire at 100
  degrees instead of burning for a long time. Dry Bloat kindles at 180.
- Weft: 0.03 an update (0.003 gave a cell a minute). It needs 5 degrees or more, so Rime stops it,
  and it withers to Ash at 80. Weft cells update every tick; a patch costs nothing measurable.
- Hush: life 200 to 255 steps at 0.05 (about 80 seconds of open air). `ages_exposed` on Hush and
  Wisp: a gas cell with only ground, liquid or its own kind beside it neither ages nor wakes, so
  a sealed pocket keeps for ever and costs nothing; a layer thins from its exposed face.
- Slag (id 48) holds no temperature; it freezes to Slag crust at 700 and the crust remelts at 800.
  Slag + Water gives crust and Steam.
- Hush + Rattle is the Rattle's `inhibit` field, not a reaction row.

**Home ranges** are blobs and seams (a blob with an `aspect`) in `data/spawn_regions.json`.
The spawn system has no relational placement, so these are not enforced: against an aquifer roof
or lining, beside a Sulfur deposit, a vein within 40 cells of lava, a Glass rim round lava, a
frost halo round a water pocket, a Bloat pocket 20 cells from water. Hush is a blob over cave air
in the Stone band, Rime a cold blob in Stone (it freezes whatever water it meets), Glass a speckle
in Hot rock. The Spoil Heap holds a Slick puddle, Flux, a Rime chip and Weft (kept: Alex has not
asked for Weft to go). Worldgen's arching clears 11 to 382 Stone cells under the new pockets
per seed (checked on 5, 7, 11, 23); all other cells outside the new regions are unchanged.

**Bench.** `tests/scenario_wave1.gd` runs the twelve demonstrations from "Lab bench
demonstrations" (the twelfth is a 120 x 60 basin of everything, left for a minute, run on one
thread and on four, which agree cell for cell). Not yet scripted: the Spoil Heap's Slick puddle
and Weft near the Hub; both only wake when something wets them.

**Count.** Twelve authored, seven derived (Ice, Slag, Slag crust, Mire stone, Setting mire,
Swollen bloat, Ferrite bar): 19 new materials, 47 in all. The 25 target for Alpha counts the
authored twelve, so wave 2 still wants about thirteen.

**Ferrite moved up (A5, Alex's call).** Plating wants Ferrite before the Sulfur band (about 2500) eats a casing, so
the seams now sit at depth 1600 to 2300, in Stone only: three anywhere across the world and a fourth within the Hub's
middle third (`data/spawn_regions.json`, the last row, so no other row's layout moved). A straight shaft from the Hub
meets Ferrite between depth 1600 and 1900 on seeds 5, 7, 11, 23, 42 and 99. Mk III and IV still want Glass from the
Magma band.
