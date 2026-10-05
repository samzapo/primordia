# Revision 5 — oriented chemistry and a living light cycle

This revision implements direct microtubule editing, camera lock/settings changes, spike pursuit, photosynthesis and the owner's approved chemistry additions. It supersedes earlier feeding variants and control schemes. Scientific motivation and explicit abstractions live in [references.md](../references.md).

## Controls and anatomy

- **Escape** toggles paused settings, including **Quit game**.
- **Space** locks/unlocks following the cell's position without pausing or rotating the world. Pan free view by dragging empty water or middle-dragging. Simulation activity and hidden population replacements follow the actual view.
- **Left drag on the cell with the build menu open** creates a microtubule between membrane points, tube points or free interior points. Hover and scroll changes tension; right-click removes a group. There is no build card or separate tool mode. Selected-organ placement takes precedence during assembly. Creation, tension changes and removal are disabled outside build; closing build cancels an unfinished drag.
- **Tab** retains paused organ assembly. **1–9 / 0** select the ten illustrated organs; wheel size, neighbor displacement, membrane anchoring, HUD scale and F11 fullscreen remain.
- Proboscis and engulfing pores are removed. Grazing pores remain. A hunting spike senses lower total organic biomass at long range, pursues, faces the prey and damages through its physical tip. Toxin vesicles remain as explicitly requested.
- Photosynthesis combines light seeking with carbon-limited fixation and oxygen release. New toxin-neutralizing and acidifying organs join it; grazing pores secrete enzymes and repair bodies secrete buffers.

## Chemistry and tradeoffs

Eleven external particle species carry amount, motion and orientation. Visible caps mark their reactive face. Compatible close contacts react whenever their faces align, with no extra success roll. Random thermal motion and probabilistic decay remain. Cell secretion and photosynthesis are biological emission processes, distinct from pair reactions.

Cells are the only external particle sources. Initial clouds represent accounted pre-observation cell products; no habitat food/oxygen spawner runs afterward. Death, secretion, leaks, respiration and photosynthesis supply the ecosystem. Replacement organisms remain explicit hidden population events with recorded material input.

Reusable enzymes digest waste. Antitoxin binds toxin into harmless waste. Nutrients aggregate without creating material. Acid carriers and buffers alter a transported, finite-capacity acid-equivalent field, visible as pink water. Moderate acidity favors the modeled digestive enzyme; sustained excess raises ATP maintenance, stresses metabolism and eventually harms health. Nutrient aggregation has no acid bonus.

Decoys temporarily reduce chemical sensing range. Automatic ATP-funded cleaning, faster cleaning with repair bodies and passive release at zero ATP provide counters. Purple occupancy rings and status text expose the effect. Chemical decoys do not disable light sensing.

These are coarse game rules, not molecular chemistry. The sources distinguish directional binding, acid-sensitive enzyme activity, receptor recovery and photosynthesis from the game's combined organs and numerical choices.

## Validation

Godot **4.7.2** on `eka-workstation-samzapo`, Ryzen 9 9950X:

- **412 assertions, zero failures**, including oriented versus misaligned reactions, catalyst reuse, neutralization and organic accounting, decay statistics, acidity/buffer stress and recovery, carbon-limited photosynthesis, cell-source provenance, reversible receptor competition, spike contact/pursuit and free-camera replacement placement.
- Existing fluid, membrane, particle-exclusion, topology, growth, material-budget and seeded-replay coverage remains. GUI tests exercise Escape, Space, Tab, drag/release placement, hover-wheel tension, scale/fullscreen preferences and the ten organ cards.
- **Seven Steam launcher fixtures pass.** Steam-first discovery is unchanged.
- A **30-second autonomous hunting fixture killed one prey**, ate and processed **22.95 food**, and retained **100 health**.
- The untouched default grazing build processed **23.6 food** and died at **75.3 simulated seconds**. It offers time to adapt, but does not automatically reach the 40-food/90-second milestone. Closed ecology and long-run diet balance need playtesting.
- A crowded 13-cell fixture averaged **8.84 ms/tick** over 360 ticks; largest player movement was **0.47 units/tick**. The default run took **18.05 seconds** of wall time, with an observed **8.68 ms** maximum tick.
- A separate **1,200-tick CPU profile** after 120 warmup ticks measured **3.280 ms median / 5.827 ms p95**, ending with two active cells and 142 active particles. Fine reaction-grid neighbor searches bound contact candidates locally.
- **360 crowded rendered frames** completed with 13 active cells and 677 active particles, without script or polygon-triangulation errors. Gameplay, assembly, chemistry, free view and settings were captured; gameplay, assembly, chemistry and 175% settings layouts were visually inspected. The settings Quit button exited successfully.
- A 600-frame, **1440 × 900 llvmpipe software-rendered** run with two rendering threads measured **21.205 ms median / 29.174 ms p95** frame intervals. End-of-run moving averages were **3.137 ms simulation / 1.065 ms preparation**. These are workstation software-rendering measurements, not GPU results or a 60-FPS guarantee. The driver did not support VSync switching.

The final camera replacement correction was covered by the full 412-assertion suite after the rendered captures/profile; it does not alter drawing. The subsequent build-menu-only microtubule correction passes 419 assertions, including blocked creation/tension/removal during play, canceled placement on menu closure and restored editing on reopening. Authored captures and concise validation records are retained privately outside Git.

The owner's Steam Godot / RTX 3090 / Threadripper 2990WX machine remains inaccessible. Use F3 there for real frame pacing. Dense chemistry, extreme growth and large tension networks still require target-machine profiling. The finite torus, stabilized star-shaped membrane, nonphysical exterior-particle shunting and coarse fluid model remain implementation limits; saves and metagame remain deferred.
