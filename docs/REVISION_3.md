# Revision 3 — readable behavior and smoother play

The owner's second playtest requested effective pursuit for engulfing/proboscis mouths, explicit approach/avoid sensing variants, much smoother frames, continued biomass growth, a full-screen microscope, paused Tab assembly, larger adjustable text, fullscreen, and anchored organs. Preserve the successful nutrient-current patterns and two-way fluid interaction. These requirements supersede earlier floating-organ and automatic-avoidance behavior.

## Delivered behavior

- **Explicit receptors:** nutrient/food approach, hunting/smaller-prey approach, host/larger-cell approach, and flight/other-cell avoidance. Flight requires an installed flight receptor and has priority while it senses another cell. Removal cancels flight memory and queued flight packets. Neither food sensing nor a mouth implicitly flees.
- **Usable specialized mouths:** engulfing pores and proboscises detect nearby compatible cell traces. Dedicated hunting/host receptors extend the range. Signals still travel inside the cell and propulsion still supplies movement. Engulfing needs at least 1.15 times the prey radius; parasitism needs a host larger than 1.05 times the player's radius. Mouth contacts grip through momentum-conserving damping, pierce local defenses, and transfer accounted-for resources. Visible links, moving food particles, progress arcs and status text explain the interaction.
- **Anchored anatomy:** the selected membrane material coordinate stays fixed. The organ follows growth, rotation and deformation without drifting along the surface. Physical packing and biomass still limit attachment.
- **Continued growth:** radius remains uncapped, and food/oxygen/ATP storage and metabolic throughput grow with effective surface area. Available food, oxygen, inertia, propulsion and damage remain practical constraints.
- **Interface:** world fills the viewport; HUD overlays it. Tab toggles paused assembly, F/C choose feeding/receptor variants, F11 toggles fullscreen. Settings offers persistent fullscreen and 85–175% HUD/font scale; menus scroll. F3 shows FPS and measured CPU costs. Wheel zoom and growth-driven camera pullback keep anatomy visible. Replacement waits if zoom exposes all possible spawn space.

## Performance changes

The spatial grid persists between ticks; active particles update buckets only when crossing a boundary. Particle movement, chemistry, toxin contact and rendering query nearby buckets instead of repeatedly scanning all stored particles. Fluid activity enumerates only relevant nodes; bilinear sampling avoids allocation, and the original tide field is cached. Fluid mass, viscosity, propulsion reaction and implicit two-way drag remain intact.

Membrane rest geometry, cumulative arcs and outlines reuse storage/caches. Cell drawings update at simulation ticks, with interpolated native transforms between ticks. Particle rendering sends one bulk buffer per species, sized to visible demand. Native GUI controls replace per-frame text/card drawing, and current marks update at 15 Hz.

## Validation

Godot **4.7.2**, workstation **Ryzen 9 9950X (16 cores)**:

- **201 assertions pass**, covering the previous conservation/contact/ecology checks plus anchored growth, explicit flight and its removal, mouth pursuit, longer receptor reach, local armor, feeding-grip momentum, growing metabolism, incremental/seam spatial queries, deferred replacement, persisted display settings, focused-GUI Tab input, F11 state and camera interpolation.
- All **7 Steam launcher fixtures** pass. Steam discovery is unchanged.
- The default 90-second run processed **112.6 food**, stayed at full health and reached the shared milestone. It took **11.42 seconds** wall time (**2.11 ms/tick** average, **4.40 ms** observed maximum), ending with 2 active / 19 stored cells and 366 active / 3,529 stored particles. The previous revision's run took 29.04 seconds, about 5.38 ms/tick; behavior and active populations differ, so this is a scenario comparison, not a controlled renderer benchmark.
- The crowded 13-cell fixture averaged **3.55 ms/tick**. Autonomous 30-second feeding trials processed **37.9 food** for the parasite (43.7 stolen) and **47.5** for the engulfer (2 prey consumed), both at full health. These fixtures demonstrate functioning interactions, not equal difficulty across habitats.
- A 1,200-tick profile after 120 warmup ticks measured **1.85 ms median / 2.16 ms p95**. At the end, 2 cells and 408 particles were active. Run `./tools/run.sh --headless --script res://tests/profile.gd` for the same CPU-only profile.
- A 600-frame, 1440 × 900 **software-rendered** run (Mesa llvmpipe, two rendering threads) measured 10.40 ms median / 27.58 ms p95 frame intervals, with approximately 0.63 ms frame preparation and 2.45 ms simulation in the end-of-run moving averages. This validates the rendered path and identifies CPU preparation cost; it does not establish RTX performance. Software-driver VSync switching was unavailable.
- Gameplay, assembly, flight controls and settings were captured and visually inspected at normal and enlarged text sizes. Native fullscreen/windowed transitions passed under Xvfb. Captures and measurement records remain private outside source control.

The owner's separate Steam Godot / RTX 3090 / Threadripper 2990WX Linux machine is inaccessible to this task. Its actual frame pacing needs playtesting with F3; no GPU or minimum-hardware guarantee is inferred from workstation results. The 4096 × 2560 torus is still finite, and extreme growth/zoom can expose all stored work. Molecular chemistry, an incompressible fluid solver, a complete deformable contact manifold, saves, audio and metagame progression remain outside this revision.
