# Crucible: Wave 2 materials (A5 part 3, built)

Twelve new materials, ids 54 to 68 (three of them derived), in `data/materials.json`, with 35 reactions, seven spawn
rows, the Electrolyser and the machine hooks that make and use them. The draft was `/mnt/project-files/plans/a5-wave2-draft.md`;
Alex's picks on it were "skip the exotic materials for now and stick with the rest of the list", so Recoil and Hover are
not here (no engine change in this part; `bin/` is as PR #26 left it) and Pumice and Cinder stayed out. With wave 1 the
world has 24 authored materials. Where this file and the draft disagree, this file is the build.

## The table

| Id | Name | Phase | Families | Made by / found in | Does |
|---|---|---|---|---|---|
| 54 | Brine | liquid | Aqueous, Conductive | pockets, Stone band 1800-2900 | Density 11. Two hot cells (105 or more) make Steam and Salt; a lone cell at 200 becomes Salt. Freezes only below -15, to Chillant, where Water freezes to Ice at 0. Withers Weft. |
| 55 | Salt | powder | Granular | seams, Stone band 1500-2600; Boiler residue | Melts Ice and Rime into Brine, dissolves slowly in Water, withers Weft. Ferrite beside it smelts to Slag at 1000 (a rough flux, no bars). |
| 56 | Lye | liquid | Alkaline | the Electrolyser | Density 13. Lye + Sourwater and Lye + Gall make Brine and heat. Scrubs Chlor out of the air without being spent (0.03). Dissolves Slick and Pitch. |
| 57 | Chlor | gas | Corrosive | pockets, Stone band 2200-2950; the Electrolyser | Density 9, sinks and pools. Eats Ferrite, Ferrite bar, Veinstone and Wire into Rubble; turns Water into Sourwater; kills Weft. Acid strength 1.5. |
| 58 | Lift | gas | Volatile | the Electrolyser | Buoyancy 8, vents. A spark or 450 degrees flashes it (blast radius 4). Burns in a Combustor for 1 power a cell. |
| 59 | Pitch | liquid | Fuel | a Boiler on Slick | Density 20, crawls (`slow` 3). Burns long. Sets to Pitch stone below 0, or in a Caster. Combustor fuel at 4 power a cell, the richest there is. |
| 60 | Chillant | liquid | Aqueous, Cold | a Chiller on Brine | Placed at -40 with heat mass 10, so it holds its cold for good in a room at 20. Freezes Water, quenches Lava to Obsidian and Slag to crust, rains Slick out of Wisp. Wakes back into Brine above 8 degrees. |
| 61 | Filings | powder | Metallic, Fuel | a Macerator on a Ferrite bar | Burns fast and hot (life 50, 900 degrees) and leaves Slag. |
| 62 | Veinstone | static | Metallic | seams in the hot rock, 3000-4000 | Durability 7, dig rate 14. With Flux at 850 degrees it smelts to Slag and Wire bodies, as Ferrite does to bars. |
| 63 | Lumen | static | Mineral, Crystalline | small clumps, 2800-3600 | Light 70, glints through the fog. Acid leaves it alone. |
| 64 | Gall | liquid | Corrosive, Aqueous | pockets in the hot rock, 3100-3800 | Density 16. Acid strength 2. Pits Mineral and Ferrite at twice Sourwater's rate, wears Obsidian and Glass slowly (0.0015), leaves Glimmer and other Crystalline alone. Spends into Sourwater, which keeps eating. Boils at 800, so it survives the 550 degree Magma band. |
| 65 | Vitriol | static | Corrosive, Crystalline | seams in the hot rock, 3100-3900 | Quiet while dry. `Vitriol + Water -> Gall + Gall` (0.02). Falls as Vitriol grit. Acid strength 0.5. |
| 66 | Pitch stone | static | none | derived | Set Pitch. Acid and water leave it alone. Softens back to Pitch at 160. |
| 67 | Wire | static, body 8 x 2 | Metallic, Conductive | derived (Furnace) | The Veinstone bar. |
| 68 | Vitriol grit | powder | Granular, Corrosive | derived | Vitriol's loose form. Turns to Gall in Water at twice the rate. |

All of them except Pitch stone bank as goods at worth 6. Lye, Lift, Pitch, Chillant and Filings are only made, never found.

## Machines

- **Boiler** gets a fourth face, `residue` on the left, passing Salt and Pitch. Its `pass` is now a list: gas up, residue left.
- **Chiller** passes Chillant as well as Ice.
- **Furnace** passes Wire as well as bars, and smelts Veinstone.
- **Combustor** needs no change: `fuel` in the data (Pitch 4, Lift 1) is all it reads.
- **Macerator** needs no change: Ferrite bar now `shatters_to` Filings.
- **Electrolyser** (`processing/electrolyser.gd`, tech Tier 3, after the Boiler, 14 Glimmer): faces in (down), `lift` (up),
  `lye` (left), `chlor` (right). A scan splits up to 12 cells (Throughput raises it) for 0.5 power a cell: two Brine become
  two Lye, one Chlor and one Lift; a Water cell becomes one Lift (the oxygen vents, it is not a material). Brine and Water
  stay in until split, and a vessel short of room splits fewer. Each product leaves by its own face.

## Casing

`acid` in the data is how hard a corrosive material hits a casing (default 1; Gall 2, Chlor 1.5, Vitriol 0.5). `casing.wear`
sums contents weighted by it and scales the chance to a scan by the worst acid present, so Gall costs twice what Sourwater
does. Plating still takes a quarter of the chance a level and Mk IV removes it, except against acid of strength 2 or more,
which keeps a quarter (`PLATING_STRONG`).

## Choices to know about

- Gall is not boiled away by the Magma band's 550 degrees, unlike what the draft's 140 would have done; it boils at 800.
- Lumen glows and shows through the fog, and does nothing else. The draft also had it turn an impact into power (a Plate
  under it); that needs a new hook and was left out.
- The draft's "kills mites" for Chlor was dropped (there are no mites), and Pitch stone does not seal a casing leak
  (there is no leak-sealing mechanic); it is a stone that acid and water leave alone.
- Lift's gas life is long (about 80 seconds) because a Tank is a closed room and a gas ages while it has air beside it.
- A reaction on two cells of one material (`Brine + Brine`, `Slick + Slick`) is how a boil leaves a residue: one cell
  becomes the gas and the other the residue, so volume is kept.
- A Tank is a free body: a side Tank next to the Electrolyser must rest on ground at the face's height or it falls out of
  its join. `scenario_wave2` has the geometry.
- Lye + Chlor in one vessel react (0.03). The Electrolyser's products pass out the scan after they are made, which is
  fast enough to lose only a few Chlor.

## Tests

`tests/scenario_wave2.gd`: eleven bench scenarios (one per material family of behaviour) and the machines on seed 7:
Boiler residue, Chiller, Furnace Wire, the Electrolyser with three Tanks, the Combustor's Pitch, casing wear by acid, and
Plating IV against Sourwater and Gall. `scenario_quarry` K covers the Winch's "goods bank is full" message.
