# Crucible: work in progress

Open this folder in Godot 4.7 and press Play (F5). F1 in game lists the controls.
This file is the full history, newest phase first. The short "where it stands" version
Claude reads each session is claude/STATUS.md.

## A5 part 3: wave 2 materials and the Electrolyser

Tests: the full suite is 29 lines `FAILURES: 0` (new: scenario_wave2; scenario_quarry gained K). No engine change: `bin/` is as PR #26 left it.
Design: claude/WAVE2_MATERIALS.md (the table, the machines, the choices). Alex's call on the draft: "skip the exotic materials for now and
just stick with the rest of the list", so Recoil and Hover are not built and Pumice and Cinder stayed out.

- Twelve materials, ids 54 to 68 with three derived (Pitch stone, Wire, Vitriol grit): Brine, Salt, Lye, Chlor, Lift, Pitch, Chillant, Filings,
  Veinstone, Lumen, Gall, Vitriol. 35 reactions, in `data/materials.json`. Brine, Salt, Chlor, Lumen, Veinstone, Gall and Vitriol are in the ground
  (seven spawn rows added last in `spawn_regions.json`, so no earlier row moved); the rest are made.
- Chains: a Boiler on Brine leaves Salt, on Slick leaves Pitch (a new `residue` face on its left); a Chiller turns Brine into Chillant;
  a Furnace smelts Veinstone with Flux into Wire bodies; a Macerator grinds a Ferrite bar to Filings; the Combustor burns Pitch (4 power a cell) and
  Lift (1). The Electrolyser (`processing/electrolyser.gd`, tech Tier 3 after the Boiler) splits Brine into Lye, Chlor and Lift and Water into Lift, each out of its own face.
- Casing: `acid` in the data weighs a corrosive material (Gall 2, Chlor 1.5, Vitriol 0.5, Sourwater 1). `casing.wear` scales a scan's chance by the worst
  acid present, so Gall costs twice Sourwater; Plating Mk IV still removes Sourwater's wear and leaves a quarter of Gall's.
- Ferrite bar and Rime changed: a bar now shatters to Filings, and Rime joins the Cold family (its own reactions are unchanged).
- Winch: a docked rig whose Tank holds a good the full bank cannot take says "The goods bank is full: free room in it to unload the Tank." instead of
  "Emptying." (Alex's pick on the full-bank card was "Leave it"). scenario_quarry K.
- Left out of the draft, on purpose: Lumen's impact-to-power (no hook for it), Chlor killing mites (there are none), Pitch sealing a casing leak (no such
  mechanic). Gall boils at 800 rather than 140, or the Magma band's 550 degrees would have boiled it away.
- Gotchas found: a vessel sizes its interior at its first scan and a gas added before that can vent out of the top row (wait half a second after
  placing); a Tank is a free body, so a side Tank must rest on ground at the face's height; `ages_exposed` gases (Hush, Chlor, Lift) age whenever air touches them
  in a half empty Tank.

## A5 part 9, seventh piece: the bot reaches the chamber's bedrock

Tests: unchanged (the suite does not run the bot; the last full run, 28 lines `FAILURES: 0`, was PR #38). No game change: `tests/autoplay.gd` only.

- With `--cheat` now setting Drill Shaft 9 (a 4350 cable), the seed 7 bot reaches depth 3000 at 115:10, 3500 at 118:50, 4000 at 122:25 and
  4473 at 126:00, where the Cutter stops on "Bedrock ahead": the chamber's bedrock shell begins near 4500 and the one way through it is the
  40-cell plug of hot rock (`info["plug_x"]`, 189 on seed 7). The bot's rig stands 75 cells left of that, so a straight shaft cannot get in.
- New flag `--plug` stands the rig over the plug (`x0 = plug_x + 7`). On seed 7 that rig wedges, tilted 0.068 radians, at depth 461, 25 rows
  under the surface Stone lumps at x 190 to 200: a new place has its own jams, so `--plug` is untried below that.
- Alex closed part 9 here (10-08, "Stop here"): the delivery waits for a later phase.
- What a full run still needs: a rig over the plug, a hole through the plug, a Node chain from the Hub down the shaft to under the plug (about
  55 Nodes at 80 rows each, built by packet), and the delivery (32 Glimmer, 48 Obsidian, 64 Water, 4 power/s). The bot banks its own Ferrite
  too only if a second shaft crosses a seam.

## A5 part 9, sixth piece: springs at a quarter of their rate

Tests: twenty-seven scenarios and engine_compare end `FAILURES: 0`; scenario_depth gained an H. No engine change.
Alex's call (10-07, "Slow it" on the card about the flooded shaft): a spring now tops up 2 * S * S cells a second, a quarter of before
(`D.SPRING_CELLS_PER_S`), so a breached aquifer still floods the shaft but takes far longer to reach the surface. Capping springs at the
aquifer's roof and leaving it were the other options on the card.

- scenario_depth H: one spring in a walled room puts 2000 cells in it in ten seconds (fails at the old rate, which fills the room).
- Two older scenarios turned out to lean on the old pace and chance. scenario_power C let a single air bubble sit against the Node's
  outline, which kept the Node from drowning; it now fills the air round the Node after the flood. scenario_collapse's 150-wide stone roof
  weathered 14 cells instead of 7 with the shifted random stream; the threshold went from 10 to 20, against 214 for the wide roof.
- Cheated bot, seed 7, 140 game minutes: no flood. Depth 3000 at 115:10 and 3500 at 118:50 (Hot rock), 3835 at 121:20, where the cable runs out
  ("Drill Shaft research lengthens it"; the bot cheats Drill Shaft 8). The shaft holds no standing water above depth 2550 and steam below;
  the surface Nodes were not drowned; Plating Mk I and II (cheated Ferrite) hold the casings. Crucible depth is about 4350, so the next wall
  is cable length, then the plug in the Crucible chamber's ceiling.

## A5 part 9, fifth piece: Ferrite moves above the Sulfur, the Funnel takes Throughput, the Cutter stops ignoring its own casing

Tests: twenty-seven scenarios and engine_compare end `FAILURES: 0`; scenario_upgrades C gained a Funnel case and scenario_quarry a J. No engine change.
Alex's notes (10-07): scoot Ferrite up so a player can reinforce machines before the Sulfur needs it, and make the Funnel's transfer rate upgradeable.

- Ferrite seams now sit at depth 1600 to 2300 in Stone only (`data/spawn_regions.json`, a little thicker: aspect 4), above the Sulfur band at
  about 2500: three seams anywhere across the world and a fourth in the Hub's middle third (the last row, so no other row's layout moved).
  Mk III and IV still want Glass from the Magma band. Where the wave 1 table said "Stone 2400 to Magma 3600", the build now wins.
  One vertical shaft crosses a seam once, about 2 units of Ferrite (Mk I wants 2, Mk II wants 5 and 2 Flux), so a player gets Mk II by a
  second shaft along the seam. The bot (no Ferrite cheat) banked 0.38 units, so its cheat stays at 10 Ferrite.
- `funnel.gd` banks `MU.rate(bank)` cells a scan, so Throughput levels 2 and 4 take it from 40 to 80 and 120 (scenario_upgrades C).
  Rate was never what held the rig at the dock: the Tank emptied 40 cells a scan and a Tank is about 4800 cells, so a Funnel needs
  twelve seconds. The hour at the dock was the full-bank hold, which is still Alex's open card.
- Found with the bot: with Plating not researched, the Cutter stopped for good at depth 2256 to 2297 on "Obsidian ahead". The wall was one
  corner pixel of its own casing: the body hangs tilted by 0.005 radians, its front edge sat at y.495, and the slice in front of the
  front rounds into the casing's last row. The rig then stood still (no room, no motion) so the reading never cleared. `Cutter.counts_ahead`
  now leaves out cells the Cutter owns, in both the clearance check and the dig loop (scenario_quarry J). I first tried making the Winch
  wait 30 ticks for the reading to last; it did not help, because the stalled rig makes the reading last.
- Found with the bot, not fixed: by minute 100 the cheated bot's shaft is full of Water from depth 550 to 2950, and by 121 it spills onto the
  surface pad (659 Water cells at rows 150 to 200), which drowns the Nodes at depth 190 and steams. Cause: `game.gd` `_springs` tops up the
  water standing over every aquifer, pocket and cave spring with no ceiling, so a breached aquifer refills the whole shaft column for good.
  Alex picked "Slow it" (sixth piece).
- Proposal, not built: the last wave 2 slots (Gall, Vitriol, and Recoil or Hover), in `/mnt/project-files/plans/a5-wave2-draft.md`.

## A5 part 9, fourth piece: Plating gets the bot past the Sulfur

Tests: twenty-seven scenarios and engine_compare end `FAILURES: 0`; scenario_fluids G gained a full-bank case. No engine change.
Alex's note: the corrosion should be answered by upgrades and repair systems. Upgrades turned out to be enough for this stretch.

- Cheated bot, seed 7, with Plating researched (Mk I at 57:56, Mk II at 76:16): reaches the Sulfur at 77:31 (depth 2500), the
  Tank casing corrodes at 81:56 and the rig keeps working: trips to 2756 and on, no Cutter lost through minute 121. Without
  Plating the Cutter was lost at 84:31 in the same seed. The bot now researches Plating twice and rebuilds a lost digger
  (`_swap`: a digger missing from the rig is hung again, paid for).
- Plating needs banked Ferrite (2, then 5 and 2 Flux). Ferrite spawns in blobs at depth 2400 to 3600, the same band as the
  Sulfur, and the bot's straight shaft does not hit one, so the cheat banks 10 Ferrite. Whether a player finds it before the
  casing goes is a pacing question for the end-of-Alpha tuning.
- Found and fixed: with oil drunk as a good, the goods bank (30 units) fills with Slick and a full bank holds the Funnel's
  goods back, so a Tank still holding oil sits "Emptying" at the dock for good (bot: 60 minutes docked). The Cutter now drinks
  wade liquids only while the bank has room (`cutter.gd`, scenario_fluids G). A Tank that already holds oil when the bank
  fills still jams; the bot's cheat clears Slick from the bank each pass. This is a design question for Alex: the Funnel
  voiding what a full bank cannot take, or letting the rig go down with held goods as ballast, instead of holding the rig.
- Next wall, after minute 117: Nodes at depth 190 drown and a steam scald, and at 123:45 the Cutter stops at the dock on
  Obsidian ahead (water and lava have met under the rig at the surface). Not looked into yet.
- No repair module was built. The only repairs in the game are the Node's, for blueprints and structures; a casing repair
  module (a Mender that relays casing cells from banked Stone, in the Shorer's style) is a proposal for Alex if Plating proves
  too slow to buy.

## A5 part 9, third piece: the Cutter wades through oil

Tests: twenty-seven scenarios and engine_compare end `FAILURES: 0`; scenario_fluids F now uses Sourwater and G is new. No engine change.
Alex picked "Wade through" on the decision card for the oil pool at depth 780.

- `cutter.gd` `WADE := ["Slick"]`: `drinkable()` is a stockpile's liquid plus the WADE list, and `bad_liquids()` is every liquid
  the rig cannot drink. The Cutter sinks into oil without a halt and drinks it like seep water (up to its intake, into the Tank,
  banked as Slick at the Funnel). Lava, Slag, Sourwater and Quickmire still stop it. Oil only burns; the others melt, corrode or bind.
- scenario_fluids G: a rig sinks through a 20 row pocket of oil and 10 rows into the floor below it with no halt (600 Slick taken
  in), and a pocket of Sourwater still halts it. G fails without the rule. F, the Pump swap, moved to Sourwater because oil no
  longer halts the Cutter.
- Cheated bot, seed 7: gets through the oil at once (depth 1000 at 14:45, 1500 at 34:25, 2000 at 53:51, 2500 at 78:51). At 78:36
  Sulfur turns up ("eats buildings and links near it"), at 79:31 the Tank casing is corroding, and at 84:31 the Cutter is lost.
  Nothing rebuilds it, so the bot sits at the surface from there. The A4 Magma-band goal is still open, but the wall is now
  corrosion, not oil.
- Next for part 9 (a plan for Alex, nothing built): the bot rebuilds a lost digger; it banks the goods Plating needs (Ferrite,
  Glass; Plating is the casing's answer to acid, see `Casing.wear`) and researches it; then it carries the Crucible recipe down
  the Node chain.

## A5 part 9, second half: the rig gets down and up, the oil stays

Tests: twenty-seven scenarios and engine_compare end `FAILURES: 0`; scenario_quarry H and I are new. No engine change.
Alex picked "Plow breaks plugs" on the decision card for the cave-in plug on the climb. It went in as GDScript only.

- The Winch's plow on the climb now clears static rock as well as powder (`winch.gd` `plow_mask()`: every solid kind but
  Obsidian and Bedrock), inside the rig's own width; the walls beside the shaft stay and the spoil is lost. scenario_quarry H
  lays Stone across the shaft over a rig and checks that it docks, that the wall beside the shaft is untouched and that
  the Tank's casing is whole.
- Found with the bot: on the way down the Tank stopped at depth 638 in open shaft while the Winch kept driving the rest of
  the rig, so the Cutter pulled out of its join and fell 100 cells. One rubble cell against the Tank's wall was enough (bodies
  do not push powder, and the Cutter's own dig window does not reach the Tank's sides). At 659 it was a second cell. The Winch now
  runs `_plow_down` while the rig is let down: every module but an Excavator (a leading Pump counts as a module here, it
  stops on any solid cell) clears powder three columns to either side and four rows under it. Static rock stays. scenario_quarry I
  checks the reach, the Excavator exemption and that the rock is left.
- tests/autoplay.gd (bot): `_exchange` hangs the new digger with `_hang` (snaps under the Tank, tries a row or two lower, keeps
  only a placement that joined) and keeps a `pending` swap until there is room; it prints each halt with its depth.
- Cheated bot, seed 7: now climbs out of the oil at 9:25, swaps to the Pump, drains, swaps back to the Cutter, and goes down
  the old shaft again. The oil does not stay drained: the Cutter halts on Slick again at depth 778 to 792 each time, the Pump
  goes down 790 to 816 and drains what it reaches, the Cutter goes back, and it halts again two minutes later. Ten trips
  in 40 game minutes make no depth and each Cutter costs Stone (19 to 3). Everything points at a pool at about depth 780 that
  refills the pocket while the rig is up; the Pump on its own removes what the Tank holds and no more.
- Not done: bot banks goods for research, Crucible delivery, the run itself. The oil pool is the next blocker and it is a design
  call (see claude/STATUS.md). Alex's idea of machines that push and drag loose pixels and bodies is logged as claude/IDEAS.md
  entry 11 and needs an engine proposal first.

## A5 part 9, first half: the Pump leads a rig

Tests: twenty-seven scenarios and engine_compare end `FAILURES: 0`; scenario_fluids F is new. No engine change.
Alex picked "Pump beside Cutter" on the decision card. The geometry does not allow it: a shaft is 30 wide (the
Cutter's dig window) and each of the two modules is 26, and a Pump's mouth only reaches liquid when it is the lowest
module. What went in is the closest workable version, the Pump in the Cutter's place on the Tank's lower face.

- The Pump leads its rig like a Cutter: `room` is 0 while liquid sits in its mouth (it drains first), then the clear rows
  below; dry with rock below it sets `stuck` and a `stop` text, so the Winch brings the rig up ("The Pump has drained what
  it can reach."). On a rig it is powered through the Winch's network, as the Cutter is.
- The Winch's hold now keys on which module digs (`_key` adds its definition), so swapping the Cutter for the Pump, or
  back, lifts a halt that would otherwise wait for research.
- Fixed: a module placed against a moving rig is added to the mover's rig at once (`machines.gd` `_join_rig`). Before, it
  fell away from the Tank for up to a scan and lost its join.
- scenario_fluids F: the Cutter halts on a pocket of oil and the rig comes up; the Pump goes on, drains the pocket to
  nothing, the Funnel banks the oil as Slick, and the Cutter goes back and the Winch lowers again.
- tests/autoplay.gd (bot): researches Chute and Pump, and swaps the digger when the Winch halts on a liquid and again
  when the Pump is done. Cheated bot, seed 7: still no run. The rig halts on Slick at 9:20 (depth 803), starts up, and
  stalls at about depth 770 with 83 stalls counted, 602 cells of cable out: the shaft above the Tank is plugged with
  Stone, Dirt and Water from cave-ins, and the Winch's plow only clears loose powder. The swap never gets its turn
  because the rig does not reach the surface. The next blocker is the plug, not the oil.
- Not built: anything that clears a static plug on the climb (an up-facing Cutter has no room for its spoil; a Shorer
  has no way through the Tank's Funnel face; the Winch's plow deleting static rock would be an engine proposal).

## A5 part 8: Mk upgrades paid in goods

Tests: twenty-seven scenarios and engine_compare end `FAILURES: 0`; scenario_upgrades is new. No engine change.

- A tech step may carry `goods` ({good name: units}), and data/instructions.json has a per-tier `research_bank`
  (Tier 3 wants 2 Flux, Tier 4 wants 2 Glass on top of what a tech lists). `Goals.research_bank` adds them up. The Lab
  takes them out of `game.goods` from the same `goods_per_s` quota as the stock materials (`game.tech_bank`, saved);
  `tech_mats_done` waits for both. The research list and the top bar name them ("needs 2 Flux").
- Three upgrades with four levels each (Mk I to IV), tiers 2, 2, 3 and 4, power 1200 to 5600:
  - Throughput: every level adds half again to a module's moves a scan (`MU.rate`: pass faces, Bus Hopper, Conveyor, Pump,
    Macerator, Shorer, and the degrees a Boiler, Chiller or Furnace adds a scan). Goods: Flux, Ferrite, Glass, Ferrite bar.
  - Efficiency: every level takes a tenth off what a module draws (`MU.take_power`, so every module, the Lab's research
    excluded). Goods: Rime, Ferrite, Glass, Ferrite bar.
  - Plating: casing stands 100 degrees hotter a level (`Casing.PLATING_MELT`) and acid takes a quarter less of its
    chance a level, none at level 4. This is the hazard-proofing IDEAS.md asked the Mk upgrades to carry. The breach
    leak itself is unchanged.
- The goods order is the chain: Flux and Rime come from the Spoil Heap, Ferrite from deep ore, Glass and Ferrite bars
  from the Furnace (Tier 3), so the last levels need the processing chain, not only mining.
- Drill Bit, Drill Shaft and Tank Size keep their stock-material costs.

## A5 part 7: sensors and the Thermoelectric Plate

Tests: twenty-six scenarios and engine_compare end `FAILURES: 0`; scenario_sensing is new. No engine change.

- `sensing/sensor.gd` is three modules (data/modules/sensing.json), each 14 by 14 with one signal face `sig` on its left:
  the Thermometer (signal on while the average temperature in its `front` mouth is at or past a setting), the Material
  Sensor (on while the mouth holds at least 6 cells of the material it watches) and the Timer (on for half of every
  period). A click steps the setting: temperature 50, 100, 300, 600, 900; the watched material through a short list;
  the Timer 2, 4, 8, 16 seconds. The state is `m["signal"]` and `m["reading"]`.
- Signals pass by contact and no further. A module with a signal face named `gate` that touches a sensor works only
  while that signal is on; one whose gate touches nothing works as it always did. Gated modules skip `scan` and `_pass`
  and say "Off: its signal is off." The Pump, Boiler, Chiller, Furnace, Combustor, Shorer and Caster carry a gate face.
  `machines.gd` `gated`.
- `power/thermoelectric.gd`, the Thermoelectric Plate (20 by 10): pays 0.001 power a degree of difference between the
  strip in front of it and the strip behind it, to a cap of 0.8 a second, into the Hub's stock. It needs a Node or the
  Hub in reach. It reads cells of the world only; a vessel interior does not count.
- Techs: Timer and Thermometer at tier 1, Material Sensor at tier 2, Thermoelectric Plate at tier 3.
- Bug found by the test: a JSON number list holds floats, so `Array.find(int)` missed and a click wrapped to the first
  step. `sensor.gd` `_at` compares as ints.

## A5 part 6: the Shorer

Tests: twenty-five scenarios and engine_compare end `FAILURES: 0`; scenario_shorer is new. No engine change.

- `support/shorer.gd`, a free body (14 by 16) with an `in` face down, so it sits on a Tank's `out` face and rides a rig.
  Powder it holds (anything the Press could squeeze: `M.pressed_of`) is set, a cell for a cell, into the open air of a
  strip along its `front` side (`depth` 3 cells, as long as the module; turn it with R to pick the side), as the rock the
  powder presses to: Rubble to Stone, Sand to Glass. It fills air only, never liquid, ground or bodies, at `rate` 6
  cells a scan for 0.05 power a cell, and lays the strip again when cells that hang free weather away.
- A definition may carry `accepts` (the filters of `pass`, plus `pressable`): `MU.add` refuses what it does not match,
  so a Tank keeps its Water and Ash instead of clogging the Shorer. `MU.accepts`.
- Entry 9 of IDEAS.md asked whether it lays casing cells or Braces and whether it takes the Cutter's mount face. It lays
  rock into the gap and takes a pixel face of its own. How a rig should carry one beside a Cutter (the Tank's only
  free pixel face is `out`, which the Cutter's spoil passes through) is untried: this part only gives the module.

## A5 part 5: Pump, Sieve, Centrifuge

Tests: twenty-four scenarios and engine_compare end `FAILURES: 0`; scenario_fluids is new. No engine change.

- `logistics/pump.gd`: a free body shaped like the Cutter (a mech `mount` face and an `out` face up), so on a rig it hangs
  under a Tank in place of a Cutter. Its mouth (`front`, `depth` 4 rows, the Bus Hopper's rectangle) takes the liquid cells
  there a slice at a time, up to `rate` 30 a scan, for 0.004 power a cell, into its interior and out of `out`. Liquid
  only (the new `M.mask("liquid")` already existed); powder stays. It reaches four rows, so a deep pool is pumped from
  the top down as the rig lowers, not from a distance. This is the answer to oil and floods ahead of a rig, untried on
  the bot (the rig is still built by hand).
- `pass` may be a list of rules, one per out face (`machines.gd` `_pass_rule`). A rule may carry `power` (a cell moved,
  needs a Node or the Hub in reach) and the filters `kinds`, `mats`, `heavy`, `light` (`MU.passes`; `heavy` and `light`
  look at the module's contents, with a single material left only `heavy` takes it). `M.density_of` is the data density
  (statics 100). Modules count what they pass in `m["passed"]`.
- `processing/separator.gd` is the kind of both vessels (capacity and report). Sieve: liquids and gases out of the top
  `fluid` face, powder and rock out of the left `solid` face. Centrifuge: the lightest material out of the top `light`
  face, the densest out of the left `heavy` face, 0.01 power a cell. Both stand 26 by 30, bolted, with `in` down at 6.
- Not here: the Electrolyser. Its products (Brine, Lye, Lift) are wave 2 materials, so it comes with part 3.

## A5 part 4: heat processing

Tests: twenty-three scenarios and engine_compare end `FAILURES: 0`; scenario_thermal is new. No engine change, `bin/` as the
widening left it.

- One script, `processing/thermal.gd`, is the Boiler, the Chiller and the Furnace. Each is a bolted vessel with an interior;
  `params.target` is the temperature it holds. Every scan, while the average of the occupied cells is short of the target,
  it adds (or takes) `rate` degrees on those cells, run by run along each row (`heat_rect` on a one-row rectangle), for
  `power` a second from the Hub. Heating the empty space above the load instead left a Furnace at its target in the air
  and its Ferrite cold, so the smelt stalled; the occupied-cell version smelted 5 bars from 150 Ferrite and 80 Flux in the
  probe. An empty vessel does nothing. Boiler 130 degrees, Chiller -20, Furnace 950 (Sand fuses at 900, Ferrite and Flux
  smelt between 850 and Flux's own melting at 1000).
- `pass` in a definition may carry `kinds` (states of matter) or `mats` (names): `MU.passes`. The Boiler lets gas out,
  the Chiller Ice, the Furnace Glass, Ferrite bar, Slag and Slag crust; the rest stays in to cook. Layout is vertical:
  Tank, vessel, Tank, joined face to face (the vessel's `in` is down at 6, its `out` up at 13, which line up with a Tank's
  `out` and `in`).
- `processing/caster.gd`, the Press for liquids: a slab (12 by 8) of one liquid with a `casts_to` (data key: Lava to
  Obsidian, Slag to Slag crust, Quickmire to Mire stone, Water to Ice) is set after 4 seconds into a block body out of
  its front. `power/combustor.gd` burns a cell every `burn` seconds (richest `fuel` first: Slick 3, Coal and Coal chunks
  2) into the Hub's power, idle at the cap. `M.cast_of`, `M.fuel_of`.
- Casing wear, `casing.gd` `wear`, once a scan for modules with an interior: the hottest interior cell above the
  definition's `melts` (default 1150, Boiler 700, Furnace 1500) costs one to six casing pixels a scan, and corrosive
  contents cost one now and then (a chance up to 0.1 a scan at 400 units). Integrity falls and the usual rules apply
  (DEAD at 0.5). It raises one alert per module. The damage-scaled breach leak (PR #27) picks wear up on its own: a worn vessel that has a hole leaks faster as more casing goes.
- `MU.add` lays a solid (Ice, Glass, Ferrite, Obsidian) from the floor up instead of `put_cells`, which starts at the top
  row where a solid then hangs. `MU.capacity` takes `params.cap` from the first scan on: a box that shrank at its first
  scan used to drop whatever was put in before it (the Combustor lost its fuel that way in the first test run).
- Not here: the Thermoelectric Plate (moved to sensors), and nothing yet makes use of a Caster block beyond the
  Macerator turning it back to powder.

## A5 part 3 prep: the family mask widened

Tests: twenty-two scenarios and engine_compare end `FAILURES: 0`. The engine changed (family fields), so close Godot before
pulling and restart after.

- Alex chose "Widen" on the decision card. A material's `family` tags, the catalyst, inhibit and feed masks on materials
  and reactions, and the reaction rule's catalyst are 32 bits now (were 16, all used by wave 1). `materials.gd` allows 32
  tags. No data changed, so no material behaves differently; a throwaway pair of materials in tags 17 and 30 reacted
  through a family rule on a bench run (not kept as a test, wave 2's materials will cover it).

## Breach leaks follow the damage

Tests: all scenarios and engine_compare end `FAILURES: 0`; scenario_interior E gained a pinhole against a gutted wall. No engine change.

- Alex: an interior should leak according to how much damage the machine has taken. A breached module now spills
  `Casing.leak(integrity)` units a scan: LEAK_MAX (60) times the share of casing lost over the share at which the module
  becomes wreckage (half), at least one. A two-pixel hole in a Tank seeps about 1 a scan; a wall with a fifth of the casing
  gone pours about 25. It replaces the flat 6 a scan. Taken from the interior (or the count) the same way as before, the
  most common material first.

## Machine interiors, parts 2 and 3: drawn, and on every vessel

Tests: twenty-two scenarios and engine_compare end `FAILURES: 0`; scenario_interior gained part H. No engine change, `bin/` as part 1 left it.

- Part 2: `scripts/interior_layer.gd`, a child of the overlay drawn behind it. Each interior's open box goes to a texture of
  material ids (refreshed only when the sim changed) and a small canvas shader runs it through the palette image, squeezed
  into the module's cavity, so a Tank of sand under water shows its layers. The Tank's old fill polygon only draws for a
  module with no sim. `tests/shot_interior.gd` takes the screenshot.
- Part 3: `"interior": true` is on the Press, Macerator, Bus Hopper, Cutter and Laser as well as the Tank. The Funnel, Chute,
  Conveyor and Drone Cage keep counts (they pass things on). The box width follows the layout the module was placed in, so
  a Tank placed turned has a box as wide as its turned cavity.
- Cost: five interiors on a rig took about 0.08 ms a tick over the same rig without them (2.0 to 2.1 ms a tick, headless,
  `sim` and modules together).
- A module that holds material for a process (the A5 vessels) only needs the flag and `MU.add` / `MU.take`.

## Machine interiors, part 1: the Tank gets a sim of its own

Tests: twenty-two scenarios and engine_compare end `FAILURES: 0`; scenario_interior is new. The engine changed
(`put_cells`, `take_cells`), so `bin/` is rebuilt: close Godot before pulling.

- Alex's pitch (2026-10-05): a machine runs its own pixel simulation inside it instead of reaching into the world's.
  A definition with `"interior": true` (the Tank, for now) gets a small `CrucibleSim` in `m["sim"]`, built by
  `scripts/machines/interior.gd`. One cell in it is one unit, so capacities and balance are as they were. The Tank packs
  four units to a slot of its hollow, so the box is the cavity's inner width (22) and as tall as the capacity needs (52
  rows at Tank Size 1), padded with bedrock to a multiple of 32.
- Gravity points down in the module's own frame, so a Turntable can swing a Tank without sloshing it. Reactions and heat
  run inside: lava poured on water makes rock in the Tank. Casing damage from it waits for A5's casing melting.
- `MU.add` puts cells in at the top of the box (engine `put_cells`), `MU.take` takes the topmost (`take_cells`). Every
  place that used to subtract from `m["contents"]` calls `MU.take` now. `contents` stays a count per material, recounted
  from the sim at every scan, so the Funnel, Bus Hopper, Press and the HUD read it as before. Tests that set a Tank's
  contents by hand call `MC.add_contents` now.
- A breach still leaks six units a scan from the most common material, taken out of the interior; the leak stops
  when the hole is repaired. Wreckage throws the interior out as it threw the count.
- Saves: each interior is stored apart (`state["interiors"]`, the engine's bytes). A module with none saved (an older
  save) gets a fresh interior filled from its counts. No version bump.
- Not yet: the interior is invisible (the Tank still draws a fill level), and the box does not follow a module that is
  not a Tank. Both are the next two parts.

## A5 part 2: Vault cells

Tests: twenty-one scenarios and engine_compare end `FAILURES: 0`; scenario_vault is new. No engine change, `bin/` as it was.

- Vault Cell (`scripts/machines/logistics/vault.gd`, Tier 2 research after Bus Hopper, 12 Stone and 4 Glimmer): a bolted
  16 x 16 cell with a power face on every side. Cells set side by side join into a bank. A bank with a Node or the Hub in
  reach (any cell of it) raises the Hub's power store by 150 and its goods store by 40 units a cell; a bank out of reach
  adds nothing. There is no separate terminal: the HUD's Goods list shows the total against the cap, and the cell's
  panel says how many cells its bank has.
- Caps: the Hub alone holds 100 power (as before) and 30 units of goods, all kinds together. `game.power_cap()` and
  `goods_cap()` give the sums; the Hub's trickle, Windmills and Instruction rewards stop at the power cap. With the goods
  bank full, a Funnel and a Bus Hopper hold goods back (what pays a stockpile still banks).
- Losing a cell takes its share: power over the new cap is lost, goods scale down together, and an alert reports it.
  Power that coal banked over the cap stays until then.
- This is the answer to the Crucible's power gap in claude/STATUS.md: a few cells hold the 4 power/s a charge draws.
  The Hub's packets still take about 10 s to get power down to it.

## A5 part 1: goods bank and Bus Hopper

Tests: twenty scenarios and engine_compare end `FAILURES: 0`; scenario_goods is new. The engine did not change, so
`bin/` is as it was.

- Goods bank: `game.goods` maps a material id to units. A material marked `"good": true` in the data banks there
  under its own id instead of a stockpile, a cell paying `worth` / 600 units (6 for every good, so 100 cells a
  unit). The goods are the wave 1 materials a recipe could want: Slick, Sourwater, Hush, Quickmire, Flux, Ferrite,
  Rattle, Bloat, Glass, Rime, Wisp, Slag and Ferrite bar. Flux, Ferrite and the bar no longer pay Stone and Rime no
  longer pays Water. The Funnel banks goods too (`game.bank_cells`), the bank is saved, and the first of each good
  is noted in the event log.
- Terminal: a Goods list at the bottom right (`scripts/goods_panel.gd`), one row per banked good in the good's colour,
  hidden while the bank is empty and moved up when the Crucible panel is showing.
- Bus Hopper (`scripts/machines/logistics/bus_hopper.gd`, Tier 1 research after Chute, 10 Stone): a bolted
  26 x 22 module with an open mouth on top, an `in` face on its left and an `out` face on its right. Importing (the
  default) it banks the loose powder, liquid and gas in its mouth (anything that is a good or pays a stockpile) and
  what a joined Tank, Chute or Conveyor passes in. A click cycles it through exporting each banked good (and Water,
  from the Hub's stockpile) and back to importing. Exporting takes units into its hollow and passes them out of
  `out` into what is joined there, or pours them out of the mouth when nothing is. Needs a Node or the Hub in reach
  and 0.004 power a cell.
- Not yet: a cap on banked goods (Vault cells, part 2, give the bank a size), goods as research costs (part 8), and
  an eyedropper filter. The unit is the same 600-cell unit as the stockpiles.
- Found on the way: `sim.add_particle` takes velocity in cells a tick (4 at most); machines.gd's breach `_spill` passes
  30, which flings a particle off the map in a tick. Left alone.

## A4 end: the bot, and what it found

Tests: nineteen scenarios and engine_compare end `FAILURES: 0` (this part changes only tests/autoplay.gd and
docs). Alex chose both bot modes on the decision card: a cheated bot that tests what the machines can dig, and
the fair-pace bot as a probe that only reports depth and time.

- `tests/autoplay.gd` gains `--cheat` (Drill Bit 5, Drill Shaft 8, Tank Size 3 from the start, the Hub's power
  held at 100), alert printing (every non-info alert, once), and under `--dump` a look at the shaft above the
  Tank (loose bodies and rows of cells). It still builds the rig, a Lab and a Windmill and picks research;
  the new machines do not help it dig down a shaft, so it does not build them.
- Fair pace, seed 7, rig left of the Hub: Drill Bit at 4:26, depth 500 at 23:20, about 640 by 55:00 (Stone 12,
  power 0 all the way), Weft appears at 61:00 and a run of cave-ins climbs the shaft from depth 600 at 62:00
  to 390 at 68:00; the Cutter is lost at 67:00 and the rig is a Tank on a cable from then on. Nowhere near the
  Magma band (row 3000) in 90 game minutes.
- Cheated, seed 7: the rig reaches depth 803 (about 20 minutes in), where the Cutter halts on "Slick ahead"
  (oil: every liquid but the stockpile's water stops it). It climbs to unload with a Tank full of Water (the
  aquifers it drank), and stalls on the way up at about depth 770: the shaft above the Tank is plugged with
  static Dirt and Stone from cave-ins (at depths 411 and 393 in this run) and flooded between. The plow only
  clears loose powder, so it never gets through; the run sits there with the winch in "up" for the rest of
  the clock.
- So the A4 goal (the bot digs from the surface to the Magma band) is not met, and the cause is not a machine
  gap. What stops the rig is shaft hazards the Cutter rig cannot answer: a flooded or caved-in shaft above it,
  and oil or other liquids in its path. Candidates for what answers them (none built): a Pump or Water Jet to
  drain a flooded shaft, an up-facing Excavator or a Thumper carried above the Tank to open a plug, and a rule
  for when the Winch gives up on a plug. See claude/STATUS.md.

## A4 part: Drone Cage

Tests: nineteen scenarios and engine_compare end `FAILURES: 0`; scenario_haulers is new (the Drone Cage and
its research gate). The engine did not change, so `bin/` is as it was.

- Drone Cage (`scripts/machines/haulers/drone_cage.gd`, the Warren reworked; Tier 2 research after Conveyor,
  14 Stone and 6 Glimmer): a bolted 30 x 20 cage of four drones with a pixel face on top. A drone flies
  (30 cells a second, over anything) to a spot of loose powder in a square of ground centred on the cage,
  scoops the 6 x 6 cells round it (`dig_rect` on the powder mask), flies home and drops the load into the
  cage's hollow (200 cells), which the `pass` rule moves out of the top face into a joined Tank, Funnel or
  Chute. The spot is the nearest powder to the cage that no drone is already heading for, found by halving the
  square and trying the halves nearest first (a few counts; nearest-first came from a sketch Alex shared). A trip costs 0.4 power from the Hub's stock; no power, no
  Node or Hub in reach, or a full hollow keeps the drones home. It never lifts rock, liquid or a casing.
  Click it to cycle the square's size (60, 100 or 160 across; the middle is the start). Not built: a
  highlighted pickup area and a separate drop point (the A5 UI), and drone hazards (Hush, fire, crush).
  Needs no mites: the Warren's creature code is gone.

## A4 part: Chute and Conveyor

Tests: eighteen scenarios and engine_compare end `FAILURES: 0`; scenario_logistics is new (Chutes, the
Conveyor, their research gates). The engine did not change, so `bin/` is as it was. These were A3 scope that
the cut left unbuilt; Bus Hopper moves to A5 with Vault cells.

- Chute (`logistics/chute.gd`, Tier 1 research, 3 Stone): a bolted 14 x 24 pipe with a pixel face at each end.
  The `pass` rule moves what is passed in at the bottom out of the top, 60 cells a scan, so a line of Chutes
  joined end to end (R turns them) carries a Tank's, Macerator's or Excavator's powder across a gap. It holds
  60 cells, so a blocked line backs up to its source. No filters yet (the eyedropper filters stay in the plan
  for Funnels and Chutes).
- Conveyor (`logistics/conveyor.gd`, Tier 1 research after Chute, 10 Stone): a bolted 50 x 10 belt, its top
  `front` up, a pixel face at each end (`end_a`, `end_b`). Loose powder lying in the 4 rows over the belt, and
  whatever a joined module passes in at an end, is lifted onto a queue and arrives at the far end after the
  length over 12 cells a second; there it goes into the module joined at that end (Tank, Funnel, Chute) or,
  with nothing joined, is set down off the end a cell at a time where there is open air (a taken spot makes
  it wait, so a pile backs the belt up). Loose rigid bodies lying on the belt are driven along at belt speed
  (`drive_body`) and let go when they pass the end. It draws 0.05 power/s while it has anything to carry and
  does nothing without power or a Node or the Hub in reach. Click it to reverse. Four directions, by turns.

## A4 part: Macerator and Press

Tests: seventeen scenarios and engine_compare end `FAILURES: 0`; scenario_processing is new (the Macerator, the
Press, their research gates). The engine did not change, so `bin/` is as it was.

- Macerator (`scripts/machines/processing/macerator.gd`, Tier 2 research, 12 Stone and 4 Glimmer): bolted, 26 x 18,
  with an open mouth (its `front`, up) 3 rows deep. A loose rigid body touching the mouth is ground away
  24 cells a scan: each cell becomes what it shatters to (`M.ground_of`: Stone to Rubble, Glass to Sand) and goes
  into the Macerator's hollow and out of its pixel face (`out`, left side) into a joined Tank or Funnel. It never
  grinds a module's casing. It pays power per cell (4 times the cell's dig power) from the Hub's stock and needs a
  Node or the Hub in reach. A body it has started on is flagged so it doesn't settle back into the ground
  (a body that comes to rest settles within half a second and is rock again, so a Macerator is meant to take
  bodies on the way in: from a chute, a Conveyor or a fall, not off the ground).
- Press (`scripts/machines/processing/press.gd`, Tier 2 research, 12 Stone and 4 Glimmer): bolted, 26 x 18. Powder
  joined into its `in` face (down: a Tank under it) is pressed, once it holds 96 cells of one kind, into a 12 x 8
  block of the rock that powder is the shards of (`M.pressed_of`: Rubble to Stone, Loose dirt to Dirt, Sand to
  Glass), made a rigid body out of its front (right). It takes 3 seconds and 3 power a block and needs open air
  over the block's footprint ("Blocked: no room in front for the block." otherwise). One cell of block for one cell
  of powder.
- Materials: `M.shatters` per id, `M.ground_of`, `M.pressed_of`. New group file `data/modules/processing.json`.

## A4 part: the tethered Thumper

Tests: sixteen scenarios and engine_compare end `FAILURES: 0`; scenario_excavators gains E (the Thumper).
**The engine changed** (`explode_cone`), so `bin/` is rebuilt: close Godot before pulling and restart it after.

- Engine: `explode_cone(x, y, radius, power, dir, half)` is `explode` limited to rays within `half` radians of
  `dir`. A cone is rock and debris only (no flash, bodies aren't pushed). `explode` itself calls it with a full
  circle and takes the same path as before.
- Thumper (`scripts/machines/excavation/thumper.gd`, Tier 1 research, 14 Stone and 4 Glimmer): a 24 x 18 block
  with a mechanical `hook` on top. It hangs from a Winch cable. Any hard landing (a drop at 14 cells a second
  or faster, then a sudden stop) sets off a 90 degree cone out of its front; power is the landing speed over 12,
  at most 14, so a drop of ten cells or more beats Obsidian's durability of 10. The cone's tip sits half the
  Thumper's width behind its front, so the hole is as wide as the Thumper by the time the rig gets there.
- Winch with a Thumper (`winch.gd`, `_thump`): docked, down until the Thumper has made under half a cell of
  headway for 12 ticks, lift 18 cells, drop (the cable goes slack and the rig falls free), down again. While it
  lowers, loose powder under the Thumper is shoved aside and lost, the way a rig hauled up plows, so the
  rubble from a blast doesn't hold the rig up. The lift costs 0.6 power/s. Three blasts in a row that break
  fewer than 3 cells halt the rig ("The Thumper has nothing left below it to break."); a click on the Winch
  starts it again. The cable limit (Drill Shaft) and no Node or Hub in reach stop it as they stop a Cutter rig.
- The rubble is lost, so a Thumper rig opens a shaft without a yield: it is how a rig gets through rock the
  Cutter can't cut. A Cutter that rides down the same shaft afterwards has only soft ground left to clear.

## A4 part: the full Cutter and the Laser Excavator

Tests: sixteen scenarios and engine_compare end `FAILURES: 0`; scenario_excavators is new (Hot rock, a Cutter
on a Piston, the Laser, its research gate). The engine did not change, so `bin/` is as it was.

- Cutter: Hot rock opens at Drill Bit level 4 (it stopped the Cutter at every level before; Obsidian stays
  the Laser's). The Cutter gained a mechanical face, `mount`, so it can ride a Piston, Gantry or Turntable as
  well as a Winch rig; any mover that carries a module now sets `rig_of` and `powered` on it, so the Cutter
  digs on its own (into its own hollow until it is full, or through a Tank above it). It digs along the nearest
  axis of where it faces, so a Turntable aims it in quarter turns.
- Laser Excavator (`scripts/machines/excavation/laser.gd`, Tier 2 research, 16 Stone and 6 Glimmer): a
  one-pixel beam of 40 cells along its front. It takes the first solid cell the beam meets when that is ore
  (worth 2 or more: Glimmer, Obsidian, Coal, Sulfur and the wave 1 ores) and leaves any other rock alone, saying
  what it stopped on. With Filler on (click it) each cell it takes becomes Stone, paid from the Hub's stock, so
  the wall keeps its shape and the beam stops there. 10 cells a second, six times the Cutter's power per cell,
  into its own hollow and up into a Tank by its pixel face. It needs a carrier (a Winch rig does not descend for
  it, only the Cutter drives that).

## A4 part: Turntable

Tests: fifteen scenarios and engine_compare end `FAILURES: 0`; scenario_movers gains D (the Turntable, a
save of it) and E (the research gates). **The engine changed** (`drive_body` takes a spin), so `bin/` is
rebuilt: close Godot before pulling and restart it after.

- The Turntable (`scripts/machines/movers/turntable.gd`) is a pinned 14 x 14 hub with a mechanical face on
  each side. It turns about its own middle and swings whatever is joined to its faces (and what those are
  joined to) round with it, as one rigid arm. Click it to cycle hold (rests at the nearest quarter turn),
  step (a quarter turn, a pause, another) and spin (clockwise, a revolution in about 5 s). Turning costs
  power. Unlocked by Turntable research (Tier 1, needs Piston).
- A swing holds each joined module on the pose its place in the hub's frame asks for, so an arm that was
  held back catches up once the obstruction goes. When something solid keeps an arm more than 3 cells off
  its pose the hub stops turning that way and says "Blocked."; the other way stays open.
- Engine: `drive_body(id, vx, vy, spin)`. A driven body turns at `spin` radians a tick (it used to be
  held at zero spin). Old three-argument calls keep working.
- Movers still only drive what is joined to their faces; a Piston or Gantry carried by a Turntable (or a
  Turntable on a Gantry) needs a bolted module that rides a rig, which none of them does yet.

## A4 part: Piston and Gantry

Tests: fifteen scenarios and engine_compare end `FAILURES: 0`; scenario_movers is new (Piston, Gantry, a
save, the research gates). The engine did not change, so `bin/` is as it was and Godot need not be closed
before pulling.

- Two movers on one behaviour (`scripts/machines/movers/slide.gd`). A bolted-down module holds a load at
  its mechanical face and slides it in a straight line. The Piston pushes it out 20 cells along the face's
  normal; the Gantry carries it up to 80 cells along its rail. Click a mover to cycle run (out and back
  with a pause), out, back. Moving costs power, holding costs none, and a load that meets something solid
  reports "Blocked." Both are researched (Piston and Gantry, Tier 1).
- Movers add up: a module's drive is now the sum of what every mover asks (`MU.drive`), handed to the engine
  once a tick, and `MU.rig` is the shared walk from a load to everything joined to it. The Winch uses both.
- A module placed against a free face joins it at once instead of at the next scan, so a load put on a mover
  is already hooked when the mover scans. (Hooking the Winch at placement instead moved the rig's resting
  height by half a cell and the Cutter's front slice then read its own bottom wall as Obsidian ahead; the
  slice's rounding against the body's stamped rows is a latent edge in cutter.gd, left alone.)
- Nothing mounts on a mover's load yet (the Cutter, Tank and others only have the faces they had). A mover
  on a mover waits for the Turntable's PR, which is also the one that changes the engine.

## A3 part: quarry rig jam fix

Tests: fourteen scenarios and engine_compare end `FAILURES: 0`; scenario_quarry gains G (sand behind the
rig). The engine did not change, so `bin/` is as it was and Godot need not be closed before pulling.

- The seed 7 rig no longer stalls "jammed on the way up" at about row 450 (it did on main before the
  cut too). Loose sand slumped into the shaft behind the rig, lodged in the Tank through its open hook
  hole and piled on its roof, and bodies can't push powder, so the rig could not lift it.
- A cable's hook now stays shut (the Winch's join no longer opens the Tank's casing), and the Winch
  ploughs loose powder (never rock) out of the rig's path on the way up. The spoil is lost. A rig
  under a rubble of loose powder gets through the same way; a static plug or a rigid body above it
  would still jam it.
- With the jam gone the quarry bot on seed 7 reaches depth 500 at 23:20 and goes on to 600. It still
  has not delivered 30 Stone after 90 game-minutes (25 Stone): that is pacing (a trip banks a few Stone
  and the rig waits on power shared with the Lab), tuning for the end of Alpha.

## A3 part: the legacy cut

Tests: fourteen scenarios and engine_compare end `FAILURES: 0` (scenario_digging and scenario_warren are
gone). The engine did not change, so `bin/` is as it was and Godot need not be closed before pulling.
Saves from before this are not readable (save VERSION 2).

- Gone: the Drill, Thumper, Borer, Hopper, Spout, Floodgate, Waterwheel, Steam Turbine, Cache, Relay
  Mast and the Warren (scripts/warren.gd, mites, the jacket and Saw rules, breach alerts and the pause
  option, the cells-drilled stat). The Warren comes back in A4 as the Drone Cage.
- Kept: the Hub and the Crucible, Node (the old Conduit), Bulkhead, Brace (the old Strut), the Lab and
  the Lamp. Lab and Lamp are modules now (data/modules/support.json), so research and light run off the
  Hub's stock like every other machine; the Lamp opens with its tech. Nodes stay a structure: the
  packet network still carries blueprints, repairs and the Crucible's supplies, and fog sight hangs off
  them. Build keys are 1 Node, 2 Bulkhead, 3 Brace; machines are buttons.
- Every module now glows a little and sees (the Drill used to light the descent): a quarry is never
  dark, a lit Lamp lights 200 cells and the Cutter senses hidden pockets. The minimap and Home/End use
  modules too.
- The tutorial is the quarry: build the rig, deliver 30 Stone, build a Lab, finish one research, reach
  depth 500, deliver 20 Water. The "legacy" flags are gone from data/instructions.json.
- Tests: scenario_power is the Hub trickle and Node chains (drowning, reach); scenario_research runs on
  the Lab module and the remaining techs; scenario_light, bodies, depth, run, goals, chemistry and
  collapse lost what used the removed buildings. tests/autoplay.gd is a quarry bot that builds the rig,
  a Lab and a Windmill beside the Hub and researches in a fixed order; descent, smoke_v2 and the shots of
  removed buildings are deleted.
- Bot baseline (seed 7, rig left of the Hub, 0:00 to 1:30): Drill Bit at 4:26, depth 210 at 5:00, 306 at
  10:00, 452 at 14:00, then the rig stalls on the way up with a full Tank ("jammed on the way up") for the
  rest of the run; 11 techs by 1:03. Instruction 2 (30 Stone) never completes. The same stall happens on
  main (0a6bcb8) with the same rig, so the cut did not cause it. Built right of the Hub the rig digs
  to about 265 and crawls. Power sits at 0 until research is done: a Lab eats 2/s against 0.2 from the
  Hub and a Windmill's gusts.
- Gaps written down in claude/STATUS.md: pacing, the jam, tiers 2 and 3 having no techs of their own,
  the Crucible's 4 power/s against a 100-power Hub store, no breach alerts, nothing that pumps or pours
  water, modules drifting a cell across a save.

## A3 part: starter kit modules

Tests: sixteen suites end `FAILURES: 0` (scenario_quarry is new). The engine changed (`drive_body`):
close Godot before pulling, restart after.

- Five modules in the Build list from the start, a few Stone each: Cutter Excavator, Tank, Winch,
  Funnel and Windmill. Place the Cutter on the ground, the Tank on it, the Funnel and the Winch on
  top (a picked module snaps onto a free matching face, R turns it); the Winch and Funnel are
  bolted in place wherever they are put.
- The rig works by itself: the Cutter digs a 30-wide tunnel in soft ground (dirt, sand, gravel,
  packed dirt) with a wobbling edge, the Winch lets the rig down as rows open and hauls it up
  when the Tank is full, the Funnel empties the Tank into the Hub's stockpile, and it goes
  down again. Stone stops it ("The Excavator stopped: Stone ahead") until Drill Bit research
  lifts the Cutter's hardness; the cable is as long as Drill Shaft allows; Tank Size is a new
  upgrade. Water that seeps into the tunnel is drunk into the Tank.
- Power comes from the Hub's stock when the Winch has a Conduit or the Hub within reach. The
  Windmill (open sky, gusts of 0.15 to 0.45 power/s) feeds the same stock.
- Hover a module for its readout. The old Drill still runs; the legacy cut is the next step.
- Engine: `drive_body`, a body that takes its velocity from the game (no gravity).

## A2 done: wave 1 materials

Tests: fifteen suites end `FAILURES: 0` (scenario_wave1 and scenario_spawn are new). The engine
changed (new material behaviours): close Godot before pulling, restart after.

What's new:
- Twelve materials: Slick (oil that floats and burns on water), Sourwater (acid), Hush (a
  heavy gas that smothers fire), Quickmire (cement), Flux (a catalyst), Ferrite (ore that
  smelts to bars), Rattle (goes off on a hard landing, heat or fire), Bloat (soaks liquid and
  swells), Glass, Rime (far below freezing, quenches), Wisp (a glowing gas that flashes) and
  Weft (a fungus that eats sand and dirt beside water). Seven more come out of reactions: Ice,
  Slag, Slag crust, Mire stone, Setting mire, Swollen bloat and Ferrite bar.
- Alien chemistry on a fixed table: sand beside lava goes to Glass; Flux triples burn rates
  and setting; a Wisp cloud flashes at a spark and a Rattle pile goes off in a wave; Hush
  holds both back; Rime rains Slick out of Wisp. Open the Lab Bench and paint them together.
- Engine: a timed setting stage, blasts from impact, heat or fire, a swell that remembers the
  liquid it soaked, growth, heat mass, and rigid bodies forged by a reaction (the bars).
- Home ranges for all twelve in data/spawn_regions.json (pockets and seams by depth band; the
  Spoil Heap gets a Slick puddle, Flux, a Rime chip and Weft). They do not yet sit against
  aquifers or lava as the spec says: the table has no relational placement.
- Wave 1 numbers that changed from the spec are listed in claude/WAVE1_MATERIALS.md ("Built as").

## A3 part: machine framework core

Tests: every suite ends `FAILURES: 0`, with the new scenario_modules. The engine changed
(module bodies; the save flags them): close Godot before pulling, restart after.

- A module is a rigid body whose walls are real cells of a casing material (Obsidian
  stands in until A1's casing list). It never settles back into ground.
- Faces are typed (pixel, power, mechanical, signal). Two faces of one type and width
  that touch square on, at a multiple of 90 degrees, join: both open (their wall pixels
  leave the casing) and close again when the contact ends.
- Integrity is the share of the designed casing left. A hole through the wall's full
  thickness is a breach and spills the contents out of it; under half, the module is
  wreckage (an ordinary body) and drops everything.
- Placement is at 90 degrees (R turns it); bodies turn freely afterwards.
- Three throwaway test modules (Box, Plug, Cap) sit at the end of the Build list. No real
  catalogue yet, and the legacy buildings are untouched.

## A1 done: temperature and reactions

Tests: thirteen suites end `FAILURES: 0` (with the goal layer's scenario_goals), including
the new scenario_temperature. The engine changed (temperature, reactions, saving): close
Godot before pulling, restart after.

What's new:
- Every cell has a temperature. A slow pass (every 8 ticks, only where something is
  changing) leaks heat between neighbours by their conductivity, holds sources at their
  heat (lava 1100, fire 450, burning coal 500) and pulls rock back toward its depth's
  ambient: about 15 at the surface, 90 at the Stone band's bottom, 550 in the Magma band.
- Melting, boiling and catching fire are data. Water boils at 100. Hot rock under 250
  is stone again, stone over 800 is hot rock, either over 1200 is lava, and lava under
  600 is obsidian. Coal kindles at 700 when it has an open side, sulfur at 600.
- Reactions can name a family on either side (Fuel, Corrosive, Molten so far), and a
  rule written for a material pair overrides the family's. A rule can want a
  temperature window, warm what it makes, and run faster beside a catalyst family.
- Lab Bench on the title screen: a flat open room at 20 degrees, the whole map known,
  a brush with every material plus Heat, Cool and Blast (F9; [ ] material, Shift + [ ]
  size). F6 paints the temperature over the map, there or in a run; the cursor line
  shows the degrees under it. The bench never touches the save.
- Fog: ground never seen is black, bedrock included. Seen ground shows live while it's
  lit and dimmed as last seen while it isn't. The glimmer glints and lava glow that
  used to show through the fog are gone; the Drill's sense outline stays.

Rules that changed:
- Hot rock is the Magma band's stone held hot by its ambient. Water boils on it by
  conduction, at about the old rate (the depth test's room: 296 of 12,000 cells quenched
  in 60 s). Carried near the surface it cools to stone within half a minute; scenario_depth
  keeps its shallow set-pieces hot with `keep_hot`.
- Stone beside lava heats into hot rock a few cells deep. Fuel still catches from lava
  and flames touching it as before, and now also from heat alone, past its kindle point
  with an open side.
- The Hot rock + Water reaction is gone (the pass does it); Lava + Water is now Molten +
  Water.
- The Coolant Jacket, Ember Brood and the Drill still check for the Hot rock material,
  not the degrees. A3 cuts those machines.

Engine: `get_temp`, `set_temp`, `heat_rect`, `heat_circle`, `rect_temp`, `set_ambient`,
`reset_temps`, `set_temp_params`, `paint_circle`, `get_stat_tchunks`. The save is version
2 (temperatures, the pass's awake chunks, body temperatures); a version 1 save loads
with temperatures from the ambient. The heat texture is now the hottest cell per 4x4
block. The pass costs about 0.2 ms a tick in a fresh game, with 150 to 200 of the
map's 3840 chunks awake: prof_scale's tick went from 1.40 to 1.55 ms against main on the
same container (the sim's share from 0.11 to 0.39).

## A2 spawn regions done: the Spoil Heap (branch claude/alpha-spawn-regions-cocmr1)

`data/spawn_regions.json` names where a material may appear: areas (a mound beside the
Hub, a patch inside a depth band) and spawn rows (material, area or x/depth home range,
host materials, clumps, radius, shape). `scripts/spawn_regions.gd` paints them into the
map before the sim takes it, from its own random stream. The first user is the Spoil
Heap: a gravel mound 230-290 cells off the Hub (side by seed) with clumps of Sulfur,
Coal, Clay and Sand standing in for the wave 1 oddities. Rows may name materials that
don't exist yet (skipped until they do), so wave 1 is a data edit. Existing features
still come from worldgen.gd; moving them into the table is left alone to keep each
seed's layout. Seeds 5, 7, 11, 23 are identical outside the Heap (tests/scenario_spawn.gd).
No engine change. scenario_power and scenario_chemistry clear the Heap in `fresh()`:
they carve shafts open to the surface where seed 7's Heap stands.

## A3 (part): goal layer v1

The Hub issues flat orders from data/instructions.json: a five-step tutorial (skippable
from the first run), then a standing order every 150 s. Rewards are power paid into the
Hub. Depth bands are chapters with one objective each, logged through the event tracker.
A panel shows the run goal, depth, a tremor line, the chapter and the open order.
Research now also eats goods by tier (Stone, plus Water at tier 3). The Hub trickle is
0.2 power/s. scenario_goals is new; scenario_power and scenario_research were adjusted for
the trickle. The descent probe now takes ~1800 s to depth 500; the bot was not re-run.

## Phase 10 done: pacing (the pre-alpha is complete)

Tests: eleven suites end `FAILURES: 0`, with the new scenario_run. The engine changed
(saving; condensing steam): close Godot before pulling, restart after.

A run, start to finish:
- Title screen: Continue (the one save slot, with its seed and time), Start Run (a
  random seed, or type one), Quit. Esc opens it from a run. The run saves on quit, on
  going to the title and every 5 minutes. A loaded run steps exactly as the saved one.
  A save of a 45-minute run is about 480 KB and takes about 80 ms (the engine's
  snapshot, 47 MB before compression, is written into one buffer: 30 ms, was 100-350).
- Speeds: pause, 1x, 2x, 4x on the top bar and keys. When the machine can't keep up,
  the frame rate holds and the game runs slower; the bar shows the speed it's managing.
- Lost: the Hub takes damage like any building (blasts, falling rock, fire, lava,
  sulfur, collisions). It patches itself with one of its own Stones every 10 s at
  most while under 60%, and a banner warns under 35%. When it goes, the run is over
  and its save erased.
- Won: the Crucible lit. A summary lists the milestones with times (tiers, depth
  bands, firsts, the Crucible) and the run's numbers; Keep going, Replay, New seed, Title.
- Dragging with a build tool lays a line: Conduits and Masts 0.75 of their range apart,
  Lamps a light apart, the rest side by side (40 at most). What can't go down yet shows
  dashed and goes down once the network reaches it; right-click cuts a line.

Rules that changed:
- Deposits bank 6x a cell: glimmer, obsidian, coal, sulfur and their shards (the
  rescale had left them scarce against 600-cell units).
- Borers stop short of lava ("Lava ahead"). With the Coolant Jacket, a Drill or Borer
  facing lava quenches it into obsidian from its tank, a cell of water a cell, and cuts
  it with the Saw; a jacketed Borer in lava or flames boils 0.05 water a second off its
  tank instead of burning (dry, it burns). So obsidian comes from diving jacketed Borers
  into lava, or from water poured on it as before.
- Water that lands on or against a jacketed Borer goes into its tank. Boring down, its
  own steam condensed up the shaft and rained back onto it, and the pool on its roof
  drowned the Conduit line following it.
- Condensing steam: half turns back to water, half is lost. Before, a finished jacket
  tunnel kept its steam cycling (boiling on the hot rock, condensing, dripping back)
  indefinitely, scalding its Conduits: about 27 Stone a minute of repairs. Water still
  quenches hot rock as slowly as before, so a staged steam room under a Turbine lasts.
- Steam Turbine: 0.4 power a steam cell (per v2 cell) up to 4/s, which is about what a
  room of steam pushes through its core (before, 2/s was as far as it got).
- Mites at v2's pace against the buildings (twice as fast as phase 8b left them).

The curve (tuned with the bot):
- Research power is v2's x3 at Tier 1 and x4 from Tier 2 (Borer 450, Drill Shaft 120 /
  240 / 450 / 780, Coolant Jacket and Obsidian Saw 1000 each), Glimmer costs x2.
- Borers dig at 0.3 of full pace (0.5 made the middle of a run a sprint).
- The Crucible takes 1.5 packets a second (about 1.6 minutes of charge to hold through
  its tremors). Its 4 power/s is twice what the Hub makes, and the Hub's packets take
  about 10 s to get down there against a 5 s reserve: it wants Caches nearby.
- Descent probe (seed 7, one Lab on the Hub's power): head 500 at 1.5 min, 700 at 5.5,
  1000 at 13.5, 1400 at 19.5 (was 700 at 2, 1000 at 5, 1400 at 7).

The bot (tests/autoplay.gd, rebuilt): plays a whole run headless on the map it knows,
through the game's own calls, on the Hub's power alone. It researches the Drill down
through the Topsoil and the Borer; bores a column from the Drill's foot to the hot
rock with a Conduit line after it; sweeps Glimmer bands; taps an aquifer into a Hopper
in the column (and, when a tap caves in or runs dry, drops Hoppers into the aquifer or
taps the next); tunnels over the nearest lava and Thumps down to it (Tier 3);
researches the Coolant Jacket and the Saw; dives jacketed Borers into that lava pocket
and then the lava lake for obsidian; bores down to the bedrock on a path clear of lava
and caves and on through the plug; hangs a Conduit under the dome for the Crucible;
fills three Caches and lights it, holding everything else and relaying the line
whenever a tremor knocks it out. Seed 7 (before: the old numbers; tuned: resumed
through checkpoints at 30:00 and 45:00 while the tap and endgame were fixed):

| | before | tuned |
|---|---|---|
| Stone band | 7:39 | 20:02 |
| Tier 2 | 9:14 | 22:08 |
| Tier 3 | 13:03 | 25:55 |
| Coolant Jacket, Saw | 20:07 | 37:00, 45:00 |
| bedrock | 25:12 | 51:37 |
| Tier 4 | 26:18 | 52:45 |
| the Crucible lit | 29:12 | 1:00:01 |

Other seeds, same numbers (several runs resumed from checkpoints while the bot was
being fixed, so treat single minutes loosely):

| | 5 | 7 | 11 | 23 |
|---|---|---|---|---|
| Stone band | 20:40 | 20:02 | 20:12 | 20:55 |
| Tier 2 | 21:37 | 22:09 | 20:45 | 22:27 |
| Tier 3 | 27:43 | 25:40 | 27:05 | 27:08 |
| bedrock | 52:06 | 51:16 | 51:17 | 51:38 |
| Tier 4 | 54:01 | 52:40 | 53:16 | 53:01 |
| the Crucible lit | (stalled) | 1:00:01 | 58:39 | 59:07 |

The curve holds across seeds; the bot's logistics don't always. Its water, Stone and
Conduit lines through steam are seed-sensitive: seed 5 stalled at 47 of 48 Obsidian
with its line to the Crucible not going down, and the final bot's own run of seed 7
from scratch linked the Crucible at 52:52 and then stalled once on Stone (the Caches
never built) and once on a plug Borer cut off from its water. What it copes with now:
an aquifer the Drill floods into its shaft (the column starts over the water, and the
shaft's pool becomes a last-resort tap), taps that cave in or run dry (Hoppers into
the aquifer, then the next aquifer), a Thumper's line after its wandering crater,
broken lines (restarted from the nearest live relay; a general mender for cut-off
relays), water pooled at the column's foot (drained first), a spent lava pocket (the
lava lake next), Stone running short (sweeps for Stone), and tremors cutting the
Crucible off mid-charge (the line relaid).

## Phase 9 done: depth (10, pacing, is next)

Tests: ten suites end `FAILURES: 0`, with the new scenario_depth. The engine changed:
close Godot before pulling, restart after. Deeper materials and curios wait until after
phase 10 (Alex's call).
- Hot rock: a new material filling the Magma band's rock from a wobbling line near row
  3000 down, the plug into the chamber included (seed 7: about 1.09 million cells). It
  looks like dark rock with ember flecks and spans like stone (150); the two count as
  one kind for hanging, so a roof of both holds as one (engine: a material's `kin`).
- Water on hot rock boils into steam (a pool 300 wide loses about 900 cells a second)
  and, kept wet, slowly quenches it to stone (about 40 floor cells in a minute there).
  Engine: a cell with something to react with beside it stays awake until it does, so a
  resting pool keeps boiling (before, it stopped once the pool settled).
- The Drill and Borers stop at hot rock ("Hot rock below/ahead: it needs the Coolant
  Jacket"). With the Coolant Jacket they cut it for 1 Water per 2000 cells (v2's 1 per
  20, scaled), from a 4-Water tank the network fills; all of it goes up as steam, up the
  Drill's shaft or out of a Borer's tail. A Borer charging up waits for its tank while
  the network has water, and with Homing a dry one heads home like a flat one.
- Mites dig hot rock with Ember Brood. Thumpers break it like stone.
- Steam Turbine (Tier 3, after Waterwheel; key U; 40 x 40; 10 Stone, 4 Glimmer): steam
  rising into its bottom comes out of its top, 0.2 power a steam cell (per v2 cell) up
  to 4/s. A room packed with steam under one gives about 2/s: that's as fast as steam
  rises into a 40-wide core. It's a generator like the Waterwheel (holds 20, sends the
  rest). Steam only comes from what the player sets up.
- The Crucible draws 4 power/s while charging (a 20-power reserve, filled ahead of every
  machine); out of power for 5 s, the charge drains as it does when packets stop.
- Help (F1), the Drill Shaft text and the Crucible panel say all this. tests/shot_depth.gd
  shoots a pool boiling under a Turbine hung in a chimney (about 0.3 power/s from a pool
  140 wide).
- Speed and pace as main, measured side by side on a slow, noisy container: prof_scale
  about 1.9 ms a tick on both, bench_net 6.1 against 5.9 at 60 s; descent unchanged (700
  at 2 min, 1000 at 5, 1400 at 7). Worldgen takes about 0.1 s more.

## Phase 8d done: mites as bodies (9, depth, is next)

Tests: nine suites end `FAILURES: 0`; scenario_bodies has a mites section. The engine
changed: close Godot before pulling, restart after.
- A mite walks and clings as before. When it has nothing within two bites to hold on to
  (the ground it clung to caved in or was dug away) or a blast reaches it, it becomes
  a small body (3x3 cells of a new material, Mite): it falls, tumbles, piles up and
  gets thrown, then walks again from where it lands once it's still, heading home.
- Landing faster than 480 cells/s (a fall of about 130 cells) kills it ("A mite fell too
  far"); a burning one keeps burning in the air. Seed 7's buried chamber now takes 81 s
  (76 before; a mite or two falls off the dome's roof as it's eaten away), the marker
  circle 228 s.
- Rock crushes a mite by weight and speed: 3000 or more (cells x cells/s; a 20-cell
  pebble at 150) crushes it, less squeezes it into the next open bite. Mites never
  crush each other.
- Engine: creature bodies never turn back into ground and grip on contact (no
  rolling); `remove_body`; impacts say which body was hit.
- Walking and clinging stay the mite's own rather than physical: a physical mite can't
  climb a ceiling, and 3x3 bodies in 4-wide tunnels would jam against each other.

## Phase 8c done: rigid bodies (8d, mites as bodies, is next)

Tests: nine suites (`bash native/run_tests.sh`, about 7 minutes, now with
scenario_bodies) end `FAILURES: 0`. The engine changed: close Godot before pulling, and
restart it after.
- Rigid bodies in the engine (native/src/bodies.cpp). A body is a piece of ground with its
  own bitmap and pose, sitting in the grid as ordinary cells tagged with its id, so
  powder piles on it, water flows round it and buildings rest on it. It falls (900
  cells/s^2, up to 600), turns, bounces a little, slides and tips over edges, sinks
  slowly through liquid (pushing it up out of the way) and is shoved by blasts.
- Ceilings cave in as pieces: a stretch of ceiling due to come down breaks off a slab
  (24-64 wide, 6-20 deep, ragged on top, narrowing upward like the arch it leaves) with
  its material's cave rate a sweep. The arch still forms, faster than before. Stretches
  under 4 wide, or over a gap under 20 tall (a crawlspace, like a mite tunnel), crumble a
  cell at a time as before.
- A body that hits something faster than its toughness shatters into what its ground
  crumbles into (dirt at 130 cells/s, a drop of about 9 cells; stone at 190, about 20);
  a gentler landing leaves it lying, and it turns back into ground after half a second
  still. Blasts and drills take cells off it; under 12 left and it crumbles.
- Crushing: falling rock hurts the building it hits by its weight and speed (an
  800-cell slab at 300 cells/s does 144 HP; a Conduit has 100), wears a link it falls
  through, and kills mites.
- Falling buildings (still upright boxes, falling straight down) are hurt landing past
  200 cells/s, up to 75% of their HP at 400, and so is a building they land on; water
  breaks the fall. They relink where they land, as before.
- Thumper collisions: thrown or blasted into rock or a building sideways or upward past
  300 cells/s, it's hurt, and so is the building (the hardest flick costs 37 of its 80
  HP). Its own blasts launch it at most 220, and landing never hurts.
- Stone roofs: a notch weathered into one no longer cuts it if stone roofs the notch
  within 8 cells (before, any notch two deep brought a whole stone roof down).
- Tools: tests/bench_bodies.gd (cost of many bodies), tests/shot_bodies.gd (screenshots
  of a ceiling breaking up). Removed five orphaned tmp_*.gd.uid files.
- Numbers (this container measures main's build at 1.3 ms a fresh-game tick, where the
  last one measured 0.7): a fresh game ticks the same as main; the network bench
  averages the same (worst ticks are network rebuilds, ~38 ms, as before); 100 slabs
  in the air at once cost 3.5 ms a tick (worst 14), 180 cost 6.3. Descent probe
  unchanged: 700 at 2 min, 1000 at 5, 1400 at 7.

## Phase 8b done: the rescale (8c, rigid bodies, is next)

Tests: all eight suites (`bash native/run_tests.sh`, about 6 minutes) end
`FAILURES: 0` at the new scale. The engine changed a lot: close Godot before
pulling, and restart it after so it picks up the new library. Descent probe (depths
5x): 700 at 2 min, 1000 at 5, 1400 (Tier 1's deepest) at 7, v2's curve.
- The world is 768 x 5120 cells (v2: 256 x 1024). Its layout is v2's, 3x across and
  5x down; its features (caves, aquifers, veins, pockets, the lava lake, the
  chamber) are 4x bigger each way. Seed 7 generates in about 0.8 s.
- Everything built is 10x its v2 size against the cells (`D.S`): the Hub is 80 x 60,
  a Conduit 20 x 20, the Drill 30 wide. Ranges, speeds and radii are 10x (Conduits
  link 160, Masts 280, the Hub lights 220); amounts counted in cells are 100x (a unit
  of a resource is 600 cells, a Hopper takes up to 9000 cells a second, power per
  cell dug is a hundredth). Costs in resources and times are v2's.
- Buildings end up about 2.5x bigger against the caves than in v2, and the map is
  narrower in building terms (about 5 relays across at full spacing). The camera
  zooms smoothly from the whole width (about 1.3 px a cell) to 6 px a cell.
- Free fall (new): sand, dirt, water and anything else that falls speeds up (900
  cells/s^2, up to 600 cells/s) through air instead of dropping a cell a tick; into
  water it still sinks slowly. Water spreads 16/8 cells a tick, lava 8/4.
- Mites work in bites of 4 x 4 cells: a mite nibbles one out a cell at a time,
  hops to the next nearby, and carries up to 8 bites home a trip. They cling to
  surfaces as before. A buried Warren's chamber takes about 76 s; a marker 218
  cells off about 13 minutes (pace is for phase 10).
- Collapse: spans are 10x (dirt 70, stone 150, packed dirt 240), overhangs as in
  v2 (it's the slope an arch narrows by), so arches keep their shape at 10x. The
  sweep covers 512 rows a tick; an arch rises a row about every 2.5 s. A stone roof
  no longer drops a whole row when weathering takes one cell out of it (its own kind
  above a gap bridges it). Loose powder only holds a building up from underneath,
  resting on something. Struts are 10 cells thick where the gap allows.
- Light works on 4 x 4 blocks now (radii reach 220), and only for explored ground
  on screen plus what buildings watch. The map is drawn from 256 x 256 tiles and
  only tiles that changed are uploaded; the "as last seen" picture is kept by the
  engine. Placement snapping, the Drill's channel scan and row digging, Drill
  sense, corrosion and Hopper rims all run in the engine or skip empty work.
- Springs give their full rate (they gave at most 60 cells a second before); the
  Waterwheel passes water along its whole underside.
- Speed: a fresh seed-7 game ticks in about 0.7 ms; the network bench (383
  buildings) about 2.5 ms a tick once its own floors cave in, and a network rebuild
  there about 34 ms.
- Not ported: the screenshot scripts (`tests/shot_*.gd`), `smoke_v2`, `flow`,
  `scenario_water*` and the autoplay bot still use v2 coordinates.

### Phase 8b choices
- Decided with Alex: 768 x 5120; features scale with the world (4x), not the
  buildings; mites nibble small bites in short bursts; falling gets real speed now.
- Overhang stays v2's (a slope); spans, dig rates and glow radii are 10x.
- Mites move 100 cells/s (1.7x the straight 10x) and nibble at twice full pace; the
  Warren's detour is 2 x S (at bite granularity that still gets round a snag).
- The cave-in alert counts 12 x S cells (a caving front is 10x wider, not 100x).

## Phase 8 of 10 done: collapse (8b, the 10x rescale, and 8c, rigid bodies, are next)

Tests: `tests/scenario_collapse.gd` 0 failures; power, research, chemistry, light,
digging, warren and engine_compare pass. The engine changed: close Godot before
copying, and restart it after so it picks up the new library. Descent probe: 140 at
2 min, 200 at 5, 280 at 8 (7.5 before; packed dirt digs slower).
- Collapse (engine): every kind of ground has a span, the widest open run (air, gas
  or liquid) it can roof over, and an overhang. A ceiling wider than its span caves
  in from the middle, a row at a time, becoming what it crumbles into, until what's
  left is an arch (each row within its overhang of the run's ends) or its own rubble
  piles up and props it. Rock, powder and buildings under a ceiling hold it up; water
  doesn't. A sweep covers 128 rows a tick, bottom up (the map every 8 ticks, about
  0.06 ms a tick). Each material's `cave` is the chance a sweep that an unsupported
  cell gives way. Settling (20 s after digging) and Strut holds stop it.
- Worldgen runs the rule once (`stabilize`), clearing what would cave in, so caves and
  aquifers start as arches that stand (seed 7: about 700 cells, mostly tents of air
  over the Topsoil aquifers). Weathering still sheds ceiling cells, which sets off
  small cascades now and then.
- Cave-ins over 12 cells in a couple of seconds raise an alert, only on explored
  ground.
- Strut (Tier 1, 60 power; 2 Stone, key X, 60 HP): click in a gap and it spans it
  through the cursor, rock to rock, flat or upright (R), up to 16 cells, 1 cell thick.
  Built at once from the Hub's stock: no blueprint, no link, no upkeep. It props what
  rests on it, and rock within 5 cells of either anchor never caves in, weathers,
  erodes or loosens (the engine keeps a hold count per cell). It snaps (destroyed, to
  rubble) when either anchor stops being rock. The ghost shows the span, both anchors
  and their holds; selected, it rings them.
- Tremor Dampers (Tier 4; needs Obsidian Saw and Strut): tremors crumble no stone
  within 12 cells of a Strut.
- Ground (ids 29-32, all mundane: physics and water only). Spans: gravel 4, dirt 7,
  coal and sulfur 9, clay 11, glimmer none (never gives), stone 15, packed dirt 24.
  - Packed dirt: slow to dig, hardly ever comes down; thickens toward the bottom of
    the Topsoil. Water softens it to dirt very slowly.
  - Dirt: weathers as before; water wears it to sand.
  - Sand: a powder, pours the moment it's opened; water carries it off (to air).
    Pockets in the upper Topsoil, never within 3 cells of water or open space.
  - Gravel: comes down almost at once (cave 0.9, crumbles and loosens to rubble);
    water doesn't touch it. Patches, and a bed along the Topsoil/Stone boundary.
  - Clay: water doesn't touch it; lines the lower half of the Topsoil aquifers.
  - Stone is cohesive: it hangs only from its own kind, counted along the row (or
    from rock that never gives), so a lump held up by dirt alone drops once it's
    undermined. Water wears it to dirt, very slowly.
  - Coal comes down twice as fast as dirt (crumble 1.0, cave 0.5). Glimmer never does.
  - Wash pass: 48 cells a tick; a wet dirt face turns to sand in about 20 minutes.
  - Mites dig sand and gravel from the start, packed dirt and clay with Hard Teeth.
  - The brush (F9) has dirt, packed dirt, gravel, sand and clay.
- Data file: `span`, `overhang`, `cave`, `cohesive`, `wash_to`, `wash` (see its notes).
- Keys: every palette key now works from the keyboard (G for the Warren didn't).
- The GDScript fallback sim has no collapse, holds, shields or wash.
- Tests: `tests/scenario_collapse.gd` (spans and arches, stone, water, settling, the
  alert, worldgen, Struts flat and upright, too wide, holds against weathering,
  snapping, a Conduit on a thin roof, Tremor Dampers, packed dirt, gravel, glimmer,
  a stone lump, washing), `tests/shot_collapse.gd` (screenshot). Older tests that
  carved rooms into seed 7 now wall them with plain dirt (sand pockets poured in), the
  light test's floating ledge is bedrock, the Warren's Sounding pool is held (its skin
  would cave in), and the network bench roofs its rooms with bedrock.
  `tests/mapdump.gd` colours from the data file.

### Phase 8 choices
- Decided with Alex: spans and arches; natural caves settled at worldgen; Struts as
  straight beams; rigid bodies later. Mundane ground per Alex's list, plus Clay.
- The bench's first 5 s now include its own rooms caving in; steady state is about
  1.1 ms a tick, as before.

### Phase 8b plan: the 10x rescale (decided 2026-09-28)
- Structures 10x bigger against the pixels (Hub 80x60, Drill 30x30, Conduit 20x20...).
- World 2-3x wider and 4-5x deeper (e.g. 640 x 4608 or 768 x 5120 cells).
- Touches: C++ W/H (compile-time 256x1024), worldgen and fog/explored maps (GDScript
  loops over every cell), the map texture (split into tiles), minimap, camera and zoom,
  every tunable counted in cells (ranges, spans, speeds, CELLS_PER_UNIT, light), and
  the tests' hard-coded coordinates. Benchmark sizes first.
- Rigid bodies (falling chunks, falling buildings, Thumper collisions) move to 8c.

## Phase 7 of 10 done: the Warren

Tests: `tests/scenario_warren.gd` 0 failures; digging, research, power, chemistry,
light and engine_compare pass; the descent probe is unchanged (140 at 2 min, 200 at
5, 280 at 7.5). The engine changed this phase (settling): close Godot before
copying, and restart it after so it picks up the new library.
- Warren (Tier 1, 100 power; 10 Stone, 5x3, key G, 120 HP): a colony of 3 mites.
  First they hollow out a half-circle chamber over it (radius 6 from the middle of
  its floor line, so the ground it stands on stays). Then, with a marker set, they
  tunnel toward it and dig out a circle of radius 3 round it. The marker goes down
  from the panel (Set marker, then click within 32 cells; Clear marker takes it
  away) and shows as a small diamond. The chamber, the line to the marker and the
  circle are outlined only while placing the Warren or with it selected. The panel
  says what they're on, mites, cells dug, how far off the marker is, the next mite
  and losses.
- The tunnel is a simple rule, so you can steer it without drawing it: each free
  mite takes the cell it can reach that's nearest the marker, give or take a quirk
  fixed to that cell (up to 3 cells' worth, `WARREN_WOBBLE`), and never more than 8
  cells off the straight line (`WARREN_TUNNEL_SLACK`). They start from wherever they
  can already walk to that's nearest, so a tunnel may begin some way from the Warren
  or branch off an old one. They won't dig more than 4 cells further from the marker
  than the nearest point they've reached (`WARREN_DETOUR`): that takes them round a
  small snag, and a wall they can't cut stops them once they've felt round it (the
  panel says so). Within a cell of the circle's edge they switch to digging it out.
- Mites: one breadth-first search from the Warren's doorstep a second (sooner after
  a dig) finds what they can reach and the way there. They crawl 6 cells/s over any
  surface (water included), dig at a quarter of full pace for half the Drill's base
  power a cell out of the Warren's 10-power reserve, carry the cell home and bank it
  (the nearest Cache in reach, else the Hub). With the reserve empty they wait at
  home. Digging clears fog 3 cells round the cell.
- What they dig: dirt, loose dirt, rubble, coal chunks and ash; Hard Teeth (Tier 2,
  150 power, 10 Glimmer) adds stone, glimmer, coal and shards, and makes the chamber,
  the circle and the marker's range 1.5x bigger (9, 4.5, 48). Never sulfur. Never
  what holds the Warren up: the solid cells under it, or, with nothing under it,
  whatever touches it. If the ground goes anyway, it falls like any other building.
- Hazards: water drowns a mite in 5 s and fumes choke it in 5 s; lava and steam kill
  it; ground or debris landing on it crushes it (and anything sharing its cell). One
  that catches fire runs about lighting what it brushes and burns out in 3 s. They
  path round fumes, steam, lava and flames they can see. A mite lost from home for
  8 s is gone. Each loss is an alert. The first colony comes with the build; after
  that a replacement every 20 s for 1 Stone while linked.
- Sounding (Tier 2, 100 power, 5 Glimmer): mites leave a one-cell skin next to any
  liquid. Without it they dig into an aquifer if it's in the way.
- Ember Brood (Tier 3, 250 power, 15 Glimmer): 5 mites per Warren, and they walk
  through fire without catching (lava still kills them). Hot rock comes with phase 9.
- Settling (engine): when the Drill, a Borer or a mite digs a cell out, the solid
  cells next to it hold still for 20 s (`SETTLE_S`, `SETTLE_RADIUS` in `defs.gd`):
  weathering, erosion and loosening pass them over and held powder doesn't fall.
  Then physics carries on as before, so there's time to prop a new hole up (a
  Bulkhead now, Struts in phase 8). Liquids aren't held, so breaches flood at once.
  Blasts and tremors aren't dug cells and don't settle. The GDScript fallback sim
  has no settling.
- Help (F1) has a Warren paragraph and the settling line; G is in the keys.
- Tests: `tests/scenario_warren.gd` (the chamber's shape, nearest-first, sulfur
  skipped, a buried colony digging its chamber, crushed, lava, fire panic, breeding,
  settling, a marker tunnel and its circle, a stone shell stopping them, clearing the
  marker, Sounding round a pool in stone, Ember Brood in fire, drowning, choking),
  `tests/shot_warren.gd` (screenshot).

### Phase 7 choices
- Decided with Alex: burning mites spread fire; mites skip sulfur and fumes; falling
  ground crushes them; the Warren runs on a power reserve; no Advance (the Warren
  stays put and mites keep its footing; if it's knocked loose it falls, and becomes
  a rigid body in phase 8); Ember Brood mites are fireproof; settling; a chamber over
  the Warren and a marker to tunnel to, in place of the spec's Pit, Gallery and Den.
- Costs halved like everything else at this scale: Warren 10 Stone (spec 20), a
  replacement mite 1 Stone (spec 2).
- Out in the open the chamber is mostly sky, so a surface Warren goes straight to
  waiting for a marker; buried in a cave or a Borer's tunnel it hollows out a room.
- Numbers from the tests: a buried Warren's chamber (34 cells of dirt) takes about
  20 s; a marker 22 cells off takes about 4 minutes (a 47-cell tunnel and the
  circle); round a stone shell they dug for about 8 minutes before stopping.
- Sounding's skin is one cell. In stone it lasts; in dirt it weathers once its 20 s
  of settling are up, and the water comes through unless it's propped.
- Mites have no gravity of their own: one whose surface is dug away stays put until
  it next moves.

## Phase 6 of 10 done: digging

Tests: `tests/scenario_digging.gd` 0 failures; power, research, chemistry, light and
engine_compare pass. No engine changes this phase: the libraries in `bin/` are as they
were, so Godot needs no restart. Numbers are first-pass; pacing is phase 10.
- The Drill: one, fixed on the Hub's right from the start. It isn't in the build list,
  can't be demolished, and blasts, fire and falls leave it alone. It bores a 3-wide
  shaft straight down at an eighth of full pace (dirt 0.75 rows a second, stone 0.375).
  Drill Bit (5 levels): 1.5x faster a level at 1.2x the power per cell. Drill Shaft
  (9 levels): reach 30, then 60, 100, 160, 240, 330, 450, 590, 730 and 870 (the bedrock
  over the chamber). Power per cell also climbs with depth, double the base 300 rows
  down. It looks over its channel 96 rows a tick for fill that fell in, so a full-length
  shaft costs about 0.16 ms a tick. Its panel caps the reach in steps of 10.
- Thumper (Tier 1, 50 power; 3 Stone, 2x2, key 2): goes off every 6 s with a charge a
  cell under it. Radius 3.5 and power 3, which breaks dirt, coal and sulfur; 1.5 power a
  blast. Upgrades: Thumper Charge (power 5 for stone, 6 glimmer, 8, 10 obsidian), Blast
  Radius (4.5, 5.5, 6.5), Thumper Efficiency (1.1, 0.8, 0.55 a blast), Thumper Rhythm
  (4.5, 3.4, 2.5 s). Its body steps aside for the blast so what goes up flies clear;
  then it's thrown up at 20 cells/s plus 2 per point of power, drifting up to 2.5
  sideways, and lands in or by its crater. Debris only: what it breaks flies as rubble,
  much of it falls back in, and a Hopper by the crater catches it. Alone it sinks about
  a cell every four or five blasts; with the fill taken away, about a cell a blast.
  Its blasts hurt your buildings and links nearby (not itself or its own link), and
  its flash can light coal. It holds 10 power and links when it lands near a relay; out
  of range it blasts on its reserve, then waits.
- Dragging: press on a built Thumper and move the mouse. It follows the cursor through
  anything open (air, gas, liquid) at up to 45 cells/s, stops against rock, and is off
  the network while held. Let go and it keeps its speed, so a flick throws it.
  Collision damage waits for rigid bodies in phase 8.
- Borer (Tier 1, 150 power; 14 Stone, 3x3, key B): points down, left, right or up (R
  while placing, its panel after). It charges up where it's placed, then grinds the
  three cells in front of it at half full pace and moves into the space: 8 cells/s
  through open space for 0.02 power a cell, digging at the Drill's base power per cell.
  Liquid it moves through goes round it. It stops at bedrock, a building, a face of
  solid lava, the map edge, obsidian (until the Obsidian Saw) or an empty reserve, and
  its panel says which. Out past the network it runs on its reserve: 30, and 50, 80,
  120 with Borer Cells.
- Homing (Tier 2, 180 power, 8 Glimmer): a Borer out of reach at half power turns back
  along the path it took (climbing where it fell). It heads out again as soon as it's
  linked and topped up, or waits where it started until it is, then bores on past
  where it turned. A building in its tunnel stops it; within network range it
  recharges there.
- Relay Mast (Tier 2, 120 power, 10 Glimmer; 4 Stone, 1 Glimmer, 2x3, key M): a
  Conduit that links relays within 28 cells. A link holds when either end reaches, so
  a Conduit 25 cells from a Mast links to it. It drowns and burns like a Conduit.
- Obsidian Saw (Tier 3, 250 power, 12 Glimmer): obsidian stops the Drill and Borers
  until it's done. A Thumper at Charge 4 breaks obsidian into shards for Hoppers.
- Tech tree: plain techs by tier plus an Upgrades column. Each upgrade level costs more
  than the last, and later levels wait for their tier (the table is in `defs.gd`).
  Tuned Bit and Long Shaft are gone (Drill Bit and Drill Shaft replace them). Steam
  Turbine and Coolant Jacket moved to phase 9 with heat; Warren, Sounding, Hard Teeth
  and Ember Brood stay in 7, Tremor Dampers in 8.
- Build list: 1 Conduit, 2 Thumper, 3 Hopper, 4 Bulkhead, 5 Lab, 6 Spout, 7 Floodgate,
  8 Waterwheel, 9 Cache, 0 Lamp, B Borer, M Relay Mast. Starting kit: Conduit, Hopper,
  Bulkhead, Lab.
- Movers (Thumpers, Borers) keep their links, hazard-scan entries, light and sight up
  to date as they go without rebuilding the network. The 400-building bench runs 1.08
  ms a tick (1.05 before).
- Descent probe (`tests/descent.gd`, rewritten for the fixed Drill): one Lab researching
  Drill Bit and Drill Shaft on the Hub's own power. On seed 7 the shaft reaches depth
  140 at 2 min, 200 at 5 and 280, Tier 1's deepest, at 7.5. The next levels want
  Glimmer, which starts 40-odd rows further down, so a Borer has to fetch the first.
  The seed-7 shaft breaks into an aquifer at depth 107, which floods it up to about 79.
- Tests: `tests/scenario_digging.gd` (the fixed Drill, Thumper, dragging and throwing,
  Borer stops, Homing, Relay Mast), `tests/shot_dig.gd` (screenshot). Older tests now
  use the fixed Drill where they need one, and the screenshot scripts keep off its spot.

### Phase 6 choices the spec left open
- The shaft is 3 wide and straight down; the Borer and Thumper do the sideways work.
- A new Borer charges up before it sets off, so it doesn't leave with an empty reserve.
- Homing turns back only as far as it has to: linked and topped up, it heads out again.
- A Thumper's own flash singes it (under half an HP a blast); it only raises an alert
  below half health.
- Drills placed by test scripts keep the old 12-row reach; players can't place one.

## Phase 5 of 10 done: chemistry

Tests: `tests/scenario_chemistry.gd` 0 failures; engine_compare, power, research and
the descent probe unchanged (depth 335 in 347 s).
- Engine: each cell carries an extra byte (burn time left, or a gas's life). Fire
  spreads cell to cell and needs air, so buried or flooded coal goes out. Lava and
  flames light what burns. Gases rise or sink by buoyancy and sort by density. Free
  particles (blast debris, crumbling ceilings) fly and rejoin the grid. Blasts cast
  rays that spend energy on what they break. Weathering drops cells from ceilings:
  dirt every few seconds per span, stone about a hundred times slower. Same result
  on 1 thread or 4.
- Materials (ids 19-28): Fire, Smoke, Ash, Coal (Stone + Power), Coal chunks,
  Sulfur (Stone + Glimmer, corrosive), Sulfur grit, Sulfur fumes, Glimmer shards,
  Obsidian shards. Colours and render styles live in the data file; the shader reads
  a palette built from it.
- World: coal seams in the Topsoil and Stone, a coal cap over one lava pocket behind
  a stone skin, sulfur crusts beside lava and nodules in deep stone.
- Game: fire and corrosion damage buildings. Links (each building's line to its
  relay) wear under fire, sulfur and lava, and break. Worn links, broken links and
  damaged buildings ask for a Stone to mend them. First sightings of coal, sulfur,
  fire and fumes get a note. The brush (F9) has Coal, Sulfur, Fire and Blast.
- Speed: the hazard scans keep their building and link lists between runs and
  rebuild them only when a building comes or goes or the network is rebuilt; a
  building with nothing near it is skipped in one check. Buildings and links are
  scanned on alternate beats, three ticks apart. Repair requests look only at
  buildings that have been hurt. On the 400-building bench the scans went from
  0.15 to 0.04 ms a tick and the whole tick from 1.08 to 0.95 ms. The biggest
  remaining slice there is fog of war (about 0.13 ms a tick, GDScript).
- Help (F1): a paragraph on coal, sulfur, fire, links and crumbling ceilings; the
  body scrolls now, so the panel fits a 720-tall window with its buttons showing.
  `tests/shot_help.gd` takes a picture of it.
- Balance (burn rates, corrosion, repair costs) waits for a hand playthrough.

### Light and anchoring (end of phase 5)
First time only: restart Godot after this update so it picks up the new engine library.
- Underground is dark. The C++ sim spreads light per cell every quarter second from
  the Hub (22 cells), powered Lamps (20), a pilot light on every machine and Drill
  head (3), the Crucible (10), glowing materials (lava 10, fire and burning cells 8,
  glimmer 2) and the sky: open cells straight down from the top of the map are
  sunlit, so the surface and open shafts are lit, spilling about 12 cells sideways.
  Light loses a cell's worth per cell of air, two through liquid, five through rock,
  so it lights a wall's face and dies a few cells in. Buildings are clear to it.
  Each material's glow and opacity live in the data file ("light", "opacity").
- Fog works like Terraria's map: a block is explored when it's lit and within sight
  of one of your buildings (Hub 24, Conduits 12, machines 10, a lit Lamp its whole
  pool). Explored ground shows live whenever it's lit, even with nothing watching,
  and as last seen, dimmed and still, when it isn't. Lit open space gets a faint warm
  haze so pools of light read. Tier 3 (lava) and Tier 4 (the Crucible) open when one
  of your buildings actually sees them. Glimmer still glints through the fog.
- Anchoring: every building but the Hub and the Crucible needs something solid
  touching it (corners count), or a building that's held up; a row of Bulkheads
  hangs off a wall by its end. Anything that loses that falls as one piece, 60
  cells/s² up to 40 cells/s, swapping places with air, gas or liquid, drops out of
  the network on the way, and lands on the first solid thing or building under it,
  where it links up again. No fall damage; lava still kills. A Drill boring down
  from where it stands rests on the lip of its shaft; one that does fall into its
  channel keeps the rest of the channel below it.
- Placement snaps: a ghost that's floating or poking into rock jumps to the nearest
  legal spot within 5 cells that touches rock, a spot resting on something counting
  as a bit nearer, and a faint box marks the cursor. A spot that's already fine stays
  put; with nothing in reach it stays under the cursor and says why. Bulkheads are
  laid by hand and don't snap. `tests/shot_snap.gd` takes a picture of it.
- Speed: the light pass runs only near explored or watched ground (0.8 ms on the
  400-building bench, four times a second); vision there went from 1.9 to 0.7 ms a
  refresh. The bench tick is 1.05 ms (0.95 before).
- Without the C++ library, the GDScript sim lights whole blocks in each light's
  radius with no shadows or glow.
- Tests: `tests/scenario_light.gd` (dark cave, Lamp on and off, a wall's shadow,
  sunlight down a shaft, lava seen without a Lamp, a Conduit losing its ledge,
  falling into a pool, a row of Bulkheads cut from its wall, a Drill on its lip,
  the ghost snapping),
  `tests/shot_light.gd` (screenshot). The bench now puts a floor under everything.

## Phase 4 of 10 done: the engine (plan redrawn after phase 3; see "v3 direction" in the spec)
- The falling-sand sim is C++ now, loaded as a Godot extension from `bin/` (Windows DLL and
  Linux library, source in `native/`). It follows Noita's engine as described in Petri
  Purho's GDC talk: 32x32 chunks with dirty rectangles, in-place bottom-up updates, and four
  checkerboard passes that can run on separate threads, each chunk with its own random
  stream so the result doesn't depend on thread count.
- Materials and reactions live in `data/materials.json`: kind (empty, static, powder, liquid,
  gas), density, how liquids spread, how gases age, what erodes, crumbles or glows, what
  digging costs and yields, and which pairs react. Edit it and restart to change the world.
- Plays the same as phase 3, much faster: a 7,200-cell slab of water collapsing into a cave
  took 1,040 ms of sim time over its 10 s in the old sim and 14 ms here (~75x); 100,000 cells
  of falling water run at about 1 ms a tick. A 400-building network went from 1.4 to 0.9 ms a tick; the rest is
  game logic still in GDScript.
- If the extension doesn't load, the game falls back to the old GDScript sim and says so.
  F3 shows which one is running. First time only: restart Godot after this update so it
  picks up the extension.
- Small changes that come with the data-driven rules: heavier liquids sink through lighter
  ones (lava can slip diagonally into water, then reacts), gases bubble up through any
  liquid, Hoppers swallow any powder or liquid that's worth something, and buildings can
  go in any liquid that isn't hot.
- Tests: `tests/engine_compare.gd` runs the same set-pieces on both sims (water conserved,
  same settling level, same obsidian from water on lava, similar erosion) and checks one
  thread and four give identical cells. `-- --gdscript-sim` forces the old sim for any test.

## v2, phase 3 of 7 done: research
- The build list starts with the kit: Conduit, Drill, Hopper, Bulkhead and the new Lab. Everything
  else is researched. Keys are fixed: 1 Conduit, 2 Drill, 3 Hopper, 4 Bulkhead, 5 Lab, 6 Spout,
  7 Floodgate, 8 Waterwheel, 9 Cache, 0 Lamp; locked ones stay hidden.
- Lab (5, 4x3, 8 Stone): turns up to 2 power/s from its reserve into the tech you've picked.
  Two Labs, twice the pace. Tier 2+ techs also want Glimmer (Tier 4 Obsidian) sent to a Lab by
  packet, served like a blueprint.
- Research tab (T, or the button in the top bar): all 17 techs by tier, one picked at a time,
  progress kept if you switch, and what each locked tech is waiting on. The top bar shows the
  current pick and its progress.
- Tiers open with discoveries: Tier 2 at the first Glimmer mined, Tier 3 at the first lava one of
  your buildings sees, Tier 4 when the Crucible comes into view.
- Techs whose content comes in later phases (Warren, Borer, Relay Mast, Hard Teeth, Sounding and
  all of Tiers 3-4) show in the tab marked with their phase and can't be picked yet.
- The Drill works at a third of full pace now (dirt 2 cells of depth a second, stone 1).
  Tuned Bit: 1.5x faster at 1.5x the power per cell. Long Shaft: reach 18; the rows past 12 cost
  1.5x power, and Drills already at full reach carry on down when it finishes.
- "Pause on breach" moved into the Help panel to make room for the research button.
- Tests: `tests/scenario_research.gd`, `tests/shot_research.gd` (screenshot of the tab), and
  `tests/descent.gd`, a pacing probe: one shaft dug Drill-by-Drill with a Lab researching Tier 1
  on the side reaches the Stone band (depth 335) in about 6 minutes on seed 7.

## Phase 3 choices the spec left open
- Lab costs 8 Stone (spec 16), halved like every other cost at this scale.
- Long Shaft's extra power applies only to the six new rows.
- The Floodgate is gated now (Tier 2, after Spout) since the building already existed.
- The Drill doesn't stop at hot rock or obsidian yet; that arrives with heat and the Obsidian Saw
  in phase 6, so the obsidian farm still works in the meantime.

## v2, phase 2 of 7 done: power
- Power is a fifth resource. The Hub makes 2/s on its own and holds up to 100; you start with 20.
- Drills (0.1 power per dirt cell, 0.2 stone, 0.4 glimmer, 0.8 obsidian), Hoppers (0.02 per cell),
  Spouts (1 per packet poured), Floodgates (1 per open or close) and Lamps (0.1/s) each keep a
  10-power reserve that the network refills by packet. They keep running on it when cut off,
  and stop where they stand when it's empty (a blinking bolt).
- Requests go to the nearest source that has stock: the Hub, a Cache or a Waterwheel. Power goes
  to the emptiest machine first; Hoppers and Floodgates under half jump ahead of blueprints.
- Waterwheel (7): water landing on its top runs through and out underneath, 0.08 power a cell,
  up to 2/s. It keeps 10 for machines nearby and sends the rest to the Hub. Water pooled under it
  stalls it.
- Springs sit on the floor of every aquifer and pocket and in some caves, adding 8 water cells/s
  wherever there's room. A drained aquifer fills back up; a breached one never stops. A wheel
  under a spring makes about 0.65/s. Found springs show as a blue pulse.
- Cache (8): holds up to 60 of everything, is kept stocked with 30 Stone and 60 Power, serves
  whatever is nearest first, and anything dug or swallowed within 24 cells banks into it.
  A Cache on a cut-off stretch keeps it linked and running until it's empty.
- Lamp (9): sees 16 cells into the fog while it has power.
- The top bar shows totals held anywhere, and power made and used per second (red when short).
- Network rebuilds use a bucket grid and a heap (60 ms -> 12 ms on a 400-building network);
  dispatch skips what nothing can send (1.7 -> 0.1 ms/tick there).
- Tests: `tests/scenario_power.gd` (starvation, wheel under a spring, Cache past a cut, a cut-off
  Hopper under a flood), `tests/bench_net.gd`, `tests/shot_power.gd` (screenshot).

## Phase 2 numbers that differ from the spec
- Waterwheel 0.08 power a cell up to 25 cells/s (spec: 0.05 up to 40); same 2/s ceiling.
- Springs 8 cells/s (spec: about 10), since a unit is 6 cells at this scale.
- The Hub's own power store is capped at 100, so idling doesn't bank unlimited power.
- Costs are scaled like phase 1: Waterwheel 6 Stone, Cache 8, Lamp 2.

## v2, phase 1 of 7 done: scale and fog of war (see the "Crucible — v2 Spec" doc)
- Everything built is smaller: Hub 8x6, Conduit 2x2, Drill 3x3 with a 3-wide channel and 12 reach,
  Hopper 3x2, Spout and Bulkhead 2x2, Floodgate 2x6, Crucible 14x8. Costs scaled down to match,
  and a resource unit is now 6 cells (3-wide channels move less rock).
- Conduits link 16 cells, everything else within 8 of one; drill sense 10; sensors 16.
- Camera sits about 1.5x closer and pans sideways: A / D, arrow keys, Shift + wheel, middle-drag.
- Fog of war: buildings see a radius (Hub 20, Conduits 8, the rest 6, plus each drill's head).
  Out of sight, the map shows as you last saw it, dimmed and frozen.
- The depth bar is now a minimap: your network, alerts from the last 30 s, and the view box.
  Click it to jump.
- The Crucible sits 7 below the dome ceiling now, so a ceiling Conduit still reaches it.
- Not yet: the autoplay bot still expects the old sizes and will stall; it gets rebuilt in phase 7.
  `tests/smoke_v2.gd`, `tests/scenario_power.gd` and `tests/scenario_research.gd` are the quick
  checks for now.

## Working
- Sand sim (chunked dirty rects, ~0.2-0.8 ms/tick), shader renderer, fog, lava glow, drill-sense outlines
- Seeded world: layers, aquifers, glimmer veins with lodes, caves, pockets, lava lake, chamber + altar + plug
- Hub, Conduits, links, packets, blueprints, Drill, Hopper, Spout, Bulkhead, Floodgate, sensors
- Damage, drowning, erosion, alerts, Crucible panel/charge/tremors/win screen, HUD, depth ruler
- Full runs: the autoplay bot wins seeds 5, 7, 11 and 23 in 15-20 min (a person should land around 25-40)

## Changed from the spec (found in testing)
- Crucible sits on a bedrock altar under the plug; plug position roams (was unreachable)
- Recipe is 32 Glimmer, 48 Obsidian, 64 Water (was 40/60/80: too long once farm water is counted)
- Packets move 60 cells/s (40 left the deep network feeling sluggish)
- Hoppers 90 cells/s (30 couldn't keep up with a breach) and also drink water from their sides
- Buildings can be placed in water; a drowned Conduit still links buildings, just doesn't relay
- Drills stop only at all-lava rows; steam scalds only Conduits (farms cooked themselves)
- Hub trickles Stone while below 12 (soft-lock guard); erosion cut ~10x
- Conduit drowning has hysteresis: drowned after 0.5 s under, back after 2 s with air around it
- Each Drill reports each liquid breach once; nearby alerts of one kind merge
- Glimmer glints through the fog, and every vein swells into a lode somewhere, so tunnels can be planned
- Nothing moves diagonally between two solid cells that only touch at a corner (steam was leaking past drill bodies)

## Design notes from the bot runs
- The lava lake is the real obsidian farm. Pockets are small; a pocket farm tops out near 30.
- Water poured on the lake spreads over the crust and sits there; drills dipped across the lake drain it
  back down onto fresh lava. Spout sensors just above the lava stop the waste.
- A shaft drill plugs its own shaft: water that seeps in pools on top of it. A Hopper parked above the
  next drill catches the seep.

## Next
- Play it by hand: feel of the first ten minutes, readability of the farm and the network overlay
- Balance pass after a human run (recipe, spout glimmer cost, pocket sizes)
- Sound and a title screen; decide whether there should be a lose state (right now you can only stall)

Tests (headless): `godot --headless --path . --script tests/scenario_power.gd` (and the other tests/)
Map picture: `godot --headless --path . --script tests/mapdump.gd -- --seed=7 --out=map.png`
