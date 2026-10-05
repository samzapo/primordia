# Primordia — core design

Established by the project owner on October 4, 2026. These requirements persist across implementation iterations.

- This is a physics- and chemistry-based simulation game with particle-based triggers and rendering.
- The player manages a cell. The cell stage of Spore is a gameplay reference.
- Eat to grow and survive predation.
- The player has no direct control over cell movement or actions.
- The player may add propulsion, protection, offensive, regenerative, feeding, and sensing organelles.
- Organelle composition and placement determine cell motion and behavior.
- The visual reference is Kurzgesagt's immune-system and cellular-biology videos: bright, cartoony, vectorized graphics throughout. Primordia uses its own procedural shapes, palettes, and characters.

## First playable interpretation (revision 1)

A 2D desktop prototype in Godot, with CPU simulation and GPU rendering. This direction was proposed and approved as a starting point, not as a permanent restriction on platforms or scientific fidelity.

The player pauses for anatomical assembly, chooses an organelle, and attaches it to one of eight membrane sockets. There are no movement keys, click-to-move commands, or player-aimed attacks. Observation and anatomy are the player's inputs.

Gameplay particles are authoritative: their positions and species determine absorption, chemical signaling, and toxin contact. Cosmetic effects may supplement them but may not replace the interaction system.

## Revision 2 direction

The owner's first playtest established the next design: floating membrane organelles limited by physical surface area, biomass-dependent volume and inertia, internal tension elements supporting noncircular pressure-driven shapes, organelle damage and biomass repair, significant two-way fluid interaction, and an invisible wrapping map viewed through a following microscope camera.

The visible center simulates fully, the vignette fringe slows, and offscreen state is dormant except for explicit game triggers. Other organisms use the same rules; hunters can die, release nutrients, and be replaced. Waste participates in chemistry. Grazing, predation, engulfment, and parasitism are important feeding paths, including a proboscis specialization within the existing feeding category. Keep innate behavior and assembly pause; defer metagame decisions.

See [the revision-two specification](REVISION_2.md) for requirements, implementation sequence, acceptance evidence, and confirmed decisions. The specification also records validation and the numerical limits of the current revision.

## Revision 3 direction

The second playtest superseded floating attachments: organelles are now anchored to a chosen material location on the membrane, following growth and deformation without tangential drift. Biomass and radius have no arbitrary upper cap; metabolic throughput and storage scale with growth.

Engulfing mouths and proboscises pursue nearby compatible cells through particle signals. Dedicated hunting/host receptors extend their reach. A separate, explicit flight receptor is the only source of fleeing; feeding and nutrient sensing never silently add avoidance. Show contact and feeding progress clearly.

Preserve the observed current-driven nutrient patterns and substantial two-way cell/fluid interaction while reducing frame cost. Fill the screen with the world and overlay the HUD. Tab toggles paused assembly; settings provide persistent text/HUD scaling and fullscreen (also F11). The six categories, indirect control, shared NPC rules, and deferred metagame remain unchanged.

See [revision three](REVISION_3.md) for behavior, controls, and validation.

## Revision 4 direction

Feeding pores now own their food/prey/host sensing and pump the surrounding finite-mass fluid. Keep only flight as a separate receptor. The detecting pore/receptor faces its target; translation approaches food or retreats from a threat. A pore visibly pulses on consumption. External particles must be excluded from the cell interior, with nonphysical shunting allowed.

During placement the wheel changes organ size, cost grows with area, and a larger flagellum produces more thrust. Inserting an organ anywhere on the membrane pushes neighbors aside; anchoring resumes afterward. Engulfing pores also graze and require more than 50% coverage of the prey body before damage. Restore illustrated build cards with right-click variant cycling, health/ATP bars, and visible nucleus-to-organelle/membrane resource spending.

Lower inertia and replace the ellipse tendency with a softer, amorphous pressure membrane. The owner can place microtubules between arbitrary membrane points or points on other microtubules, including tube-to-tube connections, and adjust their tension to control shape. Branch points are simulated junctions. Preserve valid render polygons under this deformation; reported CanvasItem triangulation failures are a defect to fix.

See [revision four](REVISION_4.md) for controls, implementation boundaries and validation. These requirements supersede separate pursuit receptors and strict no-displacement insertion from earlier revisions.

## Revision 5 direction

Escape opens settings with Quit. Space toggles position-follow camera lock without pausing; free view can pan. With the build menu open, direct left drag on the cell places a microtubule, with membrane, existing-link or interior endpoints; hover and scroll adjusts tension. There is no microtubule build card. Creation, tension adjustment and removal are restricted to the build menu; closing it cancels pending placement.

Remove proboscis and engulfing pores. Grazing pores remain. Spikes sense and pursue lower total biomass at long range and puncture on contact. The owner clarified that toxin vesicles remain too. Photosynthesis adds light-seeking behavior, carbon fixation and oxygen release. All external particles originate in cells; remove automatic habitat particle replenishment.

The owner replaced the initial probabilistic-reaction proposal with orientation-controlled contact reactions. Compatible binding faces react deterministically. Decay remains probabilistic and thermal motion rotates particles. Add reusable digestive enzymes, nutrient aggregation, toxin-neutralizing particles/organs, acid-secreting organs and buffering particles. Moderate acidity favors digestive enzymes; maintenance costs and accumulating internal stress provide the downside. Nutrient aggregation stays separate from acidity. The owner approved this scientifically motivated alternative.

Receptor competition is approved for playtesting: decoys temporarily weaken chemical sensing; automatic ATP-funded cleaning, faster repair-body cleaning and energy-independent release prevent permanent blockage. Keep visible status and recovery feedback.

Maintain at least one reference to a real motivating phenomenon for biological/physical mechanics in [references.md](../references.md), with explicit game approximations. These latest instructions supersede previous restrictions on anatomy expansion and feeding specialization. See [revision five](REVISION_5.md) for controls and evidence.

## Proposed expansion areas

- More varied ecosystems and organisms with their own organelle-derived behavior.
- Richer chemical species and internal signaling, with readable reaction feedback.
- Improved cell-contact mechanics and an explicitly chosen fluid model.
- More attachment geometry, organelle costs, progression, and tradeoffs.
- Profiling on actual target devices before selecting C++ or GPU acceleration.

These are future directions, not features already implemented.
