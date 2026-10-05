# Revision 9 — adaptation, ecological tides and lineage

This is the approved action-economy proposal's first prototype. It uses the existing ten organs, physics and orientation chemistry. Dominance, dormancy, refuge objectives and persistent progression remain future work.

## A run

Start with a grazing pore, flagellum, 36 unspent biomass and 3 adaptation points (AP). The first mutation draft is available immediately. Six 120-second tides lead to a 90-second Long Dusk finale: 13:30 of unpaused simulation in total. Tab and settings stop both physics and the run clock. Looking away does not stop the clock; dormant cells cannot earn offspring viability.

Each of the five pre-finale tide transitions grants 3 AP; unused AP carry forward. Tides forecast more producers, a greater hunter share, toxin-bearing arrivals, reduced light, then armored hunters. Habitat profiles remain available. Population changes happen through replacements, not nutrient rain. At wide zoom, up to two announced arrivals per tide may fill vacant population places in visible water after a 30-second warning, at least 700 units beyond the player's extent and clear of other cells and plants.

The starting reserve increased from 18 to 36 after initial automated runs repeatedly exhausted repair material before the economy developed. In the balanced profile, three hunter population slots open with Lean Current at 4:00; the initial ecosystem has the player and fifteen grazers. Lean/rich challenge profiles retain their opening hunters. This is an initial-condition balance choice, not a new source of particles. Death releases both retained organic material and retained oxygen once; it does not create oxygen.

## Paid plans

- Tab opens a paused preview. **Apply & resume** commits; **Undo plan** resets the preview; **Cancel, Tab or opening settings** discards it. Choosing a draft or challenge is also provisional until Apply.
- **Grow** retains illustrated organ cards and scroll-wheel sizing. A new organ costs its ordinary biomass price times size squared, plus at least 1 AP, rounded up by area.
- **Modify** lists existing organs, their specializations, free movement, resizing, damage restoration and recycling. Microtubule dragging and tension remain free, build-only edits.
- Enlargement accumulates all positive area changes. Many small increments cost the same AP as one equivalent expansion. Shrinking cannot recover spent adaptation or reset that accumulation.
- Shrink/recycle returns 50% of actual removed material; the other half becomes waste on Apply. No AP is refunded. Damage-restoration records retain the original kind, size and trait; replacing lost anatomy costs actual tissue, with zero AP.
- A mutation costs 2 AP per rounded-up unit area and 12 biomass per unit area. On a damaged organ, tissue is incorporated at its current health fraction; the unused share stays in biomass for subsequent repair. One trait per organ prevents multiplicative stacking. Gold centers mark specialized organs.
- Below 20 ATP and with little gut food, cells can mobilize biomass above an 8-unit repair reserve at up to 0.3 units per second times growth scale. This feeds the ordinary metabolic pathways. Reproductive reserves stay protected until withdrawn. It is a short bridge through food gaps, not free energy.
- With insufficient oxygen, remaining digestive throughput can ferment food: 2 ATP and 0.3 biomass per unit, versus 5 ATP and 0.7 biomass with oxygen. Fermentation returns 0.3 waste and 0.1 carbon; 0.3 leaves the represented pool as unrecoverable end products, recorded in the loss ledger. That loss prevents a closed fermentation/enzyme energy loop. NPCs use the same rule.
- Enzymes secrete when waste is nearby; neutralizers respond to foreign toxin; repair buffers respond to acidity. Acid secretion remains deliberate environmental modification. Checks occur only on scheduled secretion attempts. Routine ATP estimates use current food, oxygen and light with all secretors active; they exclude damage, pursuit and combat. Below 12 ATP, discretionary secretion and toxin volleys rest. Feeding and repair continue to receive resources.

Menus cannot reroll drafts or refresh allowances. Cancelled plans cannot leak waste into the live environment. The editor snapshots the player's tension network and restores the original object on cancellation.

## Twelve persistent blueprints

One of three offers can be kept each tide. At least one offer comes from feeding, repair, defense or photosynthesis when any unlearned traits in those groups remain. Kept traits are available for the rest of the run; all baseline organs remain available regardless of the draft.

| Blueprint | Benefit and tradeoff |
| --- | --- |
| Economical stroke | Half propulsion ATP, 20% less thrust. |
| Layered cortex | 60% more local organ health; additional tissue contributes mass. |
| Barbed spike | 50% more damage per ATP; 70% more ATP per attack. |
| Recuperative repair | 60% stronger repair contribution, 40% more ATP per repair. |
| Wide intake | 30% wider intake and stronger suction; continuous ATP upkeep. |
| Concentrated digestion | Twice the enzyme secretion, 60% greater ATP cost per packet, slower dispersal. |
| Long-range flight | 50% greater sensing range; continuous ATP upkeep. |
| Sun specialist | 70% faster fixation at half light or above, 40% slower below it. |
| Shade specialist | 60% faster fixation below half light, 30% slower above it. |
| Pulsed toxin | 2.5× volley output and material/ATP costs; twice the interval. |
| Dense neutralization | 70% greater antitoxin secretion; 90% greater ATP cost per packet. |
| Acid pulse | 70% greater acid secretion; 90% greater ATP cost per packet; shared acid exposure. |

These affect organ operation and emitted packets. They do not add reaction-success dice, new organs, direct steering or manual attacks.

## Risks and resistance

An optional challenge can award at most 1 additional AP per tide. Accept before its final 30 seconds:

- Growth: retain 18 additional total organic material, ingest at least 18 material from externally owned packets, and finish at 60% health or better.
- Stability: finish with 30 consecutive seconds above 60% health and 25 ATP, while actively simulated.

Growth uses packet source ownership as an anti-recycling check; mixed packet chemistry does not provide a full atom-by-atom ancestry model. Neither ordinary kills nor individual particles grant AP.

Actual player toxin/spike damage, acid secretion and photosynthetic production accumulate exposure records. At each transition, a sufficiently strong dominant exposure announces a corresponding response. After 30 seconds, at most two adapted replacements per tide can buy a neutralizer, cortex, repair body or competing feeding pore. Only every third incoming cell is eligible. It pays biomass and has normal maintenance, contact and damage rules. No immunity, player-matched biomass or instantaneous changes to existing NPCs are applied.

This is a coarse, compressed selection mechanic, not a genetic population simulation or intentional evolution by individual cells.

## Lineage victory

The Lineage panel quotes additional reserves for a juvenile offspring with the current anatomy: at least 30 structural tissue, 12 biomass, 6 food, 8 dissolved carbon and the healthy material of every inherited organ. The parent transfers up to the juvenile structural requirement from its own body, retaining at least 30 structural tissue; the reserve pays for the rest. This is a real partition, not a discount that manufactures tissue. Larger anatomies require more structural tissue to fit with 20% perimeter spare. It also shows 60 reserved ATP and the available oxygen; division transfers up to 12 oxygen but does not require it. Reserving transfers biomass into reproductive tissue and ATP into a store; withdrawing reverses it subject to the cell's current ATP capacity. Reserved tissue contributes to mass and volume. The button stops tissue allocation at the current quote and ATP allocation at 60 independently, so a small offspring can still receive its full energy budget.

At 12:00, a funded cell automatically divides once there is nearby space. It can complete division until 12:30. The offspring receives the quoted reserve plus the parent’s structural contribution, up to 12 parental oxygen and 40 ATP; division consumes the remaining 20 ATP. Organs and traits inherit at their current size, with an independently copied microtubule network. The parent remains an autonomous neighbor. Both inherit the same self-signature: automatic pursuit/flight, spikes, toxins and decoys distinguish their own lineage from unrelated cells. This extends self-recognition; it does not protect against unrelated attackers, acidity or starvation. The camera, editor and objective follow the offspring; AP and blueprints do not reset.

At 13:30, win if the offspring has accumulated at least 60 healthy, active seconds with real food metabolism or carbon fixation within the preceding 15 seconds, health at least 50%, and ATP at least 10. It must still have at least 50% health at the deadline. Parent death before division, offspring death, missing tissue/ATP reserves, or insufficient sustained viability loses the run. The ending pauses the simulation; R starts again.

No organic material or oxygen is created by division. This is stylized reserve-funded reproduction, not simulated DNA replication, chromosome segregation or literal ATP stoichiometry. See [references](../references.md).

## Validation and limitations

The regression suite covers transactions, cumulative pricing, mutation material conservation, restoration, deterministic drafts, bounded grants, delayed paid counters, offspring transfer and viability. The independent GDScript backend runs the same economy cases. UI validation includes 100% and 175% text, anatomy, drafts, reserves and terminal feedback.

Use `tests/economy_playtest.gd` for repeatable autonomous management policies across seeds and diets. These are scripted build decisions, not a measure of human win rate. It records all AP spending, resources, phases and outcomes. Directly funded division fixtures are separate from these earned-resource playtests.

`tests/benchmark.gd -- --cases=all --economy=on|off` isolates run bookkeeping on identical starting states. Continue using half, quarter and minimum zoom, dense particles and growth-induced zoom. CPU tick measurements are not rendered FPS. The existing wide-view rendering limitation remains a separate issue; this revision does not claim to fix it.

### Recorded results

Godot 4.7.2 on the workstation's Ryzen 9 9950X and RTX 5080: **1,730 native assertions and 676 GDScript assertions passed, with zero failures**. The owner's Steam/RTX 3090/Threadripper machine has not been tested.

Two scripted policies earned lineage victories without injected resources under the final rules:

| Seed | Starting specialization / policy | Ending | Healthy active offspring time |
| --- | --- | --- | ---: |
| 113 | Spike hunter / reserve | Won at 13:30, 100% health | 90 s |
| 20261004 | Photosynthesis / invest | Won at 13:30, 100% health | 74 s |

These demonstrate predatory and nonpredatory feasibility, not a statistical win rate. Earlier pure-grazing policies lost: seed 113 lacked division reserves at 12:30; seed 20261004 died at 11:03.6. Those two runs preceded removal of the oxygen division gate and are retained as qualified balance warnings, not final-build samples. Pure grazing needs more tuning and broader playtesting.

The table separates median CPU simulation ticks from actual frame intervals. CPU measurements used 60 warm-up and 180 measured ticks per fixture, with economy bookkeeping on/off. Live rendering used a 1440×900 Xvfb display, Vulkan Mobile, 20 warm-up and 60 measured frames, including simulation catch-up. The growth fixture widens the effective view beyond its selected zoom.

| Fixture | Selected zoom | CPU tick, economy off / on (ms) | Live frame median / p95 (ms) |
| --- | ---: | ---: | ---: |
| Normal | 50% | 5.788 / 5.822 | 32.200 / 33.922 |
| Normal | 25% | 12.300 / 12.228 | 129.734 / 135.577 |
| Normal | 15% | 13.752 / 13.723 | 145.115 / 151.516 |
| 4× initial packets | 50% | 12.761 / 12.784 | 98.728 / 139.467 |
| 4× initial packets | 25% | 30.098 / 30.319 | 259.462 / 297.389 |
| 4× initial packets | 15% | 31.468 / 31.737 | 265.611 / 315.437 |
| Three simultaneous ruptures | 50% | 4.784 / 5.046 | 29.324 / 30.801 |
| Three simultaneous ruptures | 25% | 11.418 / 11.352 | 100.461 / 129.485 |
| Three simultaneous ruptures | 15% | 12.737 / 12.551 | 136.233 / 147.466 |
| 256× biomass | 50% | 9.162 / 9.257 | 78.015 / 83.197 |
| 256× biomass | 25% | 13.681 / 13.636 | 150.641 / 157.133 |
| 256× biomass | 15% | 14.078 / 13.531 | 150.727 / 158.087 |
| Funded offspring fixture | 50% | 6.197 / 6.111 | 50.184 / 51.717 |
| Funded offspring fixture | 25% | 12.818 / 12.862 | 140.641 / 143.895 |
| Funded offspring fixture | 15% | 14.198 / 14.178 | 153.129 / 160.253 |

Run-director bookkeeping averaged 1.87–3.44 microseconds per tick. The on/off differences were small and mixed in sign; this short serial sample does not establish an overall speedup or a precise aggregate cost. Three death emissions were included at measurement start in dedicated reruns: CPU event creation took 1.67–2.11 ms with the economy enabled. Live death-event frame maxima were 33.904 / 135.370 / 150.722 ms at 50 / 25 / 15% selected zoom.

**The 60 FPS wide-view target is still unmet.** For example, normal quarter zoom measured 129.734 ms median per rendered frame, and dense quarter zoom 259.462 ms. Neither a CPU tick nor a reported GPU interval is the whole game's frame time. These virtual-display results locate a substantial remaining performance limitation; they are not a substitute for the owner's actual display and Steam runtime.

UI checks covered Grow, Modify, Genome, Lineage, terminal feedback and 100%/175% text scale. **F3 now shows zoom percentage beside FPS**, relative to the default view. When growth or the build panel widens the actual view, it also shows the selected wheel setting, for example `Zoom 12.5% (selected 25.0%)`. A focused rendered check verified normal 25% and growth-adjusted 12.5% at 175% HUD scale. This is a readout; it does not introduce zoom persistence or change wheel behavior.

## Reproducing the checks

The launcher still discovers Steam Godot by default. These commands use the ordinary game resource rules; the playtest manager makes paid anatomy/reserve decisions between simulation ticks and never injects food or founding resources.

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh
./tools/run.sh --headless --script tests/economy_playtest.gd -- --seeds=113 --diets=hunter --policy=reserve
./tools/run.sh --headless --script tests/economy_playtest.gd -- --seeds=20261004 --diets=photo --policy=invest
./tools/run.sh --headless --script tests/benchmark.gd -- --cases=all --zooms=0.5,0.25,0.15 --warmup=60 --ticks=180 --economy=on
./tools/run.sh --rendering-method mobile --script tests/economy_render_benchmark.gd
```

For the CPU ablation, repeat with `--economy=off`; add `--scale=4` for dense packets, `--deaths=3` for three simultaneous ruptures, `--growth=256` for growth-induced zoom, or `--offspring=on` for a deliberately funded division fixture. Each switch is an independent case. The live renderer covers these five fixtures at all three zoom levels with 20 warm-up and 60 measured frames. Funded/expanded benchmark fixtures are performance inputs, not earned victories.

The playtest manager supports `reserve`, `invest` and `flight` policies. It records adaptation spending and viable offspring time. Its historical `kills` field counts NPC deaths throughout the simulated ecosystem, not kills attributed to the player.
