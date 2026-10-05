# Revision 4 — pumping pores and shapeable cells

This revision implements the owner's twelve-part playtest feedback, the reported CanvasItem polygon-triangulation failure, and player-controlled microtubule placement/tension.

## Behavior and controls

- Feeding pores pull on real surrounding fluid. Nutrients and other cells respond through transport/drag, with reaction impulses on the pumping cell.
- Nutrient/prey/host sensing is integrated into its feeding pore. The only separate receptor is flight. The detecting organ faces the target; travel approaches food or retreats from a threat.
- Pores visibly pulse when they consume. External particles are shunted out to the membrane rather than passing beneath cell bodies.
- The wheel sizes selected anatomy during assembly; cost and flagellum strength grow with area. Insertion pushes neighboring organs aside while keeping the new attachment where clicked. Anchoring resumes during play.
- Engulfing pores also graze. Their opening must cover **more than 50% of prey body area before damage**, then absorb retained material and contents on death, spilling anything beyond gut capacity. Aperture size matters independently of body size. Balanced starters have smaller hunter mouths than the armored rich-water variant, preserving adaptation time under the same rules.
- Effective inertial mass/rotation are lower. A soft, lobed pressure membrane and fluid traction replace the ellipse template. Ordered radial outlines fix the invalid-polygon failure, with pressure, bending and tensile constraints still affecting the simulated shape.
- Illustrated cards return, with **right-click on the feeding card** to cycle variants. **Health and ATP bars** return. Yellow ATP packets and pink biomass-funded repair packets visibly travel from the nucleus to organs or membrane.
- **7 / Microtubules** opens the shape tool. Connect any membrane point or point on a microtubule to another. Branches create movable junctions. Adjust a new link immediately with the tension slider, or use **Select a link to adjust** for an existing one. Split segments share their original tension setting. Right-click removes a link group or cancels a pending connection. Shape changes preview while paused.

Tab assembly, F11 fullscreen, persistent HUD scaling, wheel zoom during observation, six organelle categories, indirect control and the existing fluid currents remain. Microtubule construction/tension tuning is currently free. There is no seventh organelle category or behavior programming system.

## Validation

Godot 4.7.2 on `eka-workstation-samzapo`, Ryzen 9 9950X:

- **367 assertions, zero failures**, including fluid momentum, pump-induced motion of passive cells, scaled cost/thrust, insertion displacing both neighbors, organ-facing pursuit/retreat, strict area-coverage damage, consumption pulses, particle exclusion, membrane-to-tube and tube-to-tube branching, tension-driven shape change, graph removal, triangulation under compression, 80 contour-lookup comparisons, real resource-spending animations, and microtubule GUI placement/slider input.
- **Seven Steam launcher fixtures pass.** Launchers and Steam-first discovery are unchanged.
- The default 90-second run processed **202.9 food**, survived encounters and finished at **100 health**. Wall time was **16.14 seconds** (about **2.99 ms/tick** on average; **5.62 ms** observed maximum), ending with 2 active / 19 stored cells and 258 active / 3,148 stored particles.
- The crowded 13-cell fixture averaged **5.89 ms/tick**; its largest player displacement in one tick was **1.16 units**, distinguishing ordinary faster swimming from teleportation. Autonomous 30-second parasite and engulfing fixtures processed **28.0** and **33.0** food respectively, both at full health; the engulfer consumed two prey.
- A 1,200-tick profile after 120 warmup ticks measured **3.42 ms median / 3.97 ms p95**, ending with 3 active cells and 214 active particles. The new constraints and interactions cost more than revision three; these scenario measurements are not fixed frame-rate guarantees.
- **360 rendered crowded-contact frames completed without script or polygon-triangulation errors.** Gameplay, illustrated assembly, microtubule editing and large HUD layouts were captured and inspected.
- A 600-frame 1440 × 900 run on **Mesa llvmpipe with two software-rendering threads** measured **13.96 ms median / 16.83 ms p95** frame intervals. End-of-run moving averages were about 3.81 ms simulation and 2.00 ms frame preparation. This is software-rendered workstation evidence, not a measurement of the owner's RTX 3090. VSync switching was unsupported by that driver.

The owner's separate Threadripper 2990WX / RTX 3090 machine remains inaccessible. Use F3 there to assess actual frame pacing. Long-term diet balance and very large authored tension networks need playtesting. The torus is finite, the membrane remains a stabilized star-shaped 2D model, and particle shunting is deliberately nonphysical. Saves, metagame progression and molecular/incompressible-fluid fidelity remain deferred. Authored visual evidence and validation records are retained privately outside Git.
