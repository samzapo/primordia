# Primordia — core design

Established by the project owner on October 4, 2026. These requirements persist across implementation iterations.

- This is a physics- and chemistry-based simulation game with particle-based triggers and rendering.
- The player manages a cell. The cell stage of Spore is a gameplay reference.
- Eat to grow and survive predation.
- The player has no direct control over cell movement or actions.
- The player may add propulsion, protection, offensive, regenerative, feeding, and sensing organelles.
- Organelle composition and placement determine cell motion and behavior.
- Procedural generation and finite fractals are major visual design elements: seeded branching colonies, radial repetition, nested detail and varied habitat color fields. Geometry must remain readable and affordable at wide zoom.
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

## Revision 6 graphics direction

The owner requested visible particle orientation using branched, forked and rounded shapes, with complement illustrations as a visual reference, then requested a brighter graphics revision. Keep original vector artwork, species readability, particle-authoritative orientation and batched rendering. The owner selected luminous colors like a bright coral reef: blue/teal water and vivid coral/gold/violet/green anatomy, with colorful shadows. The owner explicitly rejected occupation-based body colors: cell bodies share a consistent palette; organelles and their produced particles communicate function. The owner requested bloom in lit areas and water color driven by acidity; bloom remains a presentation effect and buffering reverses the acid tint. New complement mechanics remain suggestions in [the proposal](COMPLEMENT_PROPOSAL.md), not approved gameplay requirements.

## Revision 7 performance direction

The owner reports that normal play requires a wider view than the earlier benchmarks, and that wider views have serious performance problems. All five proposed efficiency approaches are approved targets, with independent measurements of gains and losses. Prioritize compiled simulation kernels, GPU computation experiments and efficient fluid work; also improve spatial query coverage and slower/less detailed updates where behavior permits. Preserve visible oriented chemistry, fluid/cell interaction, indirect control and uncapped growth. Do not hide scaling problems by reducing the active habitat or silently deleting particles. See [revision seven](REVISION_7.md) for implementation, ablations and limits.

## Revision 8 procedural habitat direction

The owner selected the large plant obstacles and varied water colors in the supplied Spore cell-stage reference. Add original, seeded, rotationally symmetric branching colonies that affect the playing field. Make procedural generation and fractals a persistent visual design principle, rather than a one-off decoration. Preserve luminous vector-style art, functional organelle/particle colors, light and acid meaning, and the existing anatomy-driven cell control.

The first implementation uses finite recursive branching for plant-like scenery with solid main stems, and periodic fractal noise for water color. Fine fronds are decorative. These are fixed environmental obstacles, not new food sources or organs. See [revision eight](REVISION_8.md) for the collision approximations, performance evidence and remaining limits.

The owner subsequently replaced the dark microscope vignette with a soft peripheral blur. Keep the center and HUD sharp, preserve water brightness at the edges, and retain existing simulation activity falloff.

## Proposed expansion areas

- More varied ecosystems and organisms with their own organelle-derived behavior.
- Richer chemical species and internal signaling, with readable reaction feedback.
- Improved cell-contact mechanics and an explicitly chosen fluid model.
- More attachment geometry, organelle costs, progression, and tradeoffs.
- Further native cell/membrane work and a fully resident GPU chemistry design, guided by wide-view benchmarks on actual target devices.

These are future directions, not features already implemented.


## Revision 9: run economy

The approved first action-economy prototype is implemented in [Revision 9](REVISION_9.md). Adaptation points constrain deliberate anatomy; biomass and ATP remain conserved physical/operational resources. Assembly is transactional, with free positioning and tension changes, paid growth/specialization, partial tissue recycling and zero-AP restoration. The run has seeded mutation drafts, forecasted tides, bounded costly opponent variants and reserve-funded offspring viability as its default win condition. No direct steering, extra organ types or persistent metagame have been added.

The run director tracks a few scalar exposures and events independently of camera dormancy. Particle chemistry remains orientation-based. Build estimates describe current conditions rather than promising future income. Public source motivation and game abstractions are recorded in references.md.
