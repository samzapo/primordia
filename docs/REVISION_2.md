# Revision 2 — living cells in a liquid ecosystem

Historical specification: [revision three](REVISION_3.md) supersedes attachment drift, receptor behavior, growth scaling, and interface/performance details.

Status: design specification from the owner's playtest feedback, October 4, 2026. The design questions are resolved and the second playable implementation is present. Validation and numerical limits are recorded below.

## Preserve what works

The owner played the first prototype and found that swapping organelles gave substantial control over an autonomous cell. Preserve that indirect control and readable behavior. Keep the existing six organelle categories and assembly pause. Organelles retain innate responses; do not introduce a player-programmed rule editor or wiring system. Preserve the bright, cartoony, vectorized cellular art direction.

The target is Godot installed through Steam on a separate Linux machine unavailable to this task. Shipping platforms and permanent progression are not being expanded in this revision.

## Anatomy, mass, and shape

- Remove the eight-slot limit. Organelles float on the membrane and can move along it, subject to physical packing and available surface area.
- Retain attachment/resource costs, but impose no arbitrary organelle-count cap. Additional mass and inertia are physical tradeoffs.
- Biomass determines internal volume. Growth supplies more membrane surface for organelles, increases inertia, slows response to the same propulsion, and exposes more surface to damage.
- Track mass incorporated in the body, reserves, and organelles consistently. Assembly and repair must not duplicate biomass. Volume must respond to retained biomass rather than only a lifetime food counter.
- Retain hydrostatic pressure as the basis of the membrane shape. Add internal microtubule-inspired tension elements that can support noncircular shapes against that pressure.
- Organelle mass and location affect both translation and rotation. A heavier cell or an asymmetric attachment pattern should have observable consequences.
- Damage is local: an organelle at the point of impact takes damage first. Exposed membrane can be punctured even while organelles elsewhere remain intact. Punctures leak biomass and the membrane heals quickly. Organelles repair themselves by consuming biomass.
- Preserve a distinct role for the existing regenerative organelle when baseline organelle self-repair is added; it could accelerate repair or repair the body. The final balance must make its cost meaningful.

The game still presents a 2D world. The implementation must explicitly document how effective volume, surface capacity, mass, and rendered dimensions relate; it must not claim to solve full 3D cell geometry.

## Contact and the liquid medium

The reported clipping/teleportation through a hunter when cornered is a defect. Fix contact handling itself, with regression scenarios for compressed and overlapping cells, independently of removing the walls.

The fluid must carry meaningful mass relative to cells. Cell motion must displace or accelerate surrounding fluid, and the fluid must exert forces back on cells. Local currents and eddies must affect swimming, collisions, and the transport of chemical particles. A passive flow animation does not satisfy this requirement.

Prototype and measure the coupled cell/fluid system before scaling up the ecosystem. Select the numerical method against evidence for stability, momentum exchange, deformation, and performance. Keep externally driven currents, damping, and other modeled momentum/energy sources explicit.

## A continuous microscope view

- The map wraps, with no visible boundary or corner traps.
- The camera follows the player's cell. Crossing a world seam must preserve continuous visible motion and local interactions.
- Use a microscope-like vignette around the camera view.
- Full simulation runs near the center. Activity slows through the darkened fringe.
- Outside the camera's active region, simulation stops. Organisms and resources retain their state rather than continuously advancing offscreen.
- Explicit game triggers may change dormant state, such as population replacement or a habitat event. Record those changes distinctly from simulation ticks.
- Resume nearby state without duplicated resources, time jumps, sudden impulses, or visible spawning. Keep wrapping distance calculations consistent for physics, sensing, feeding, fluid coupling, and rendering.

This supports a larger stored ecosystem while bounding the actively simulated region. Camera framing and any later zoom feature must preserve a useful activity budget and avoid obvious pause/unpause artifacts.

## Shared organisms, damage, and death

Player and non-player cells use the same core organelle, mass, sensing, metabolism, damage, repair, feeding, and death systems. Their anatomy and innate responses can differ; hunters must not receive an invulnerability/reset exception.

A killed hunter yields a substantial nutrient resource appropriate to its biomass. Death removes that individual. Population replacement creates a different individual through an explicit ecosystem rule, preferably beyond the visible region; it must not silently refill the dying hunter's health.

## Chemistry with ecological consequences

Use recognizable substances and consistent reaction rules, with internal particle signals connecting sensing to organelle activity. The player does not configure signal-routing circuitry.

Waste participates in the ecosystem through waste/debris enters a resource-limited decomposition and recycling chain, influencing local nutrient availability and oxygen demand. Specify the energy input and conversion losses so recycling cannot create unlimited food or energy.

Transport food, oxygen, waste, signals, and offensive chemicals through the same local fluid environment where appropriate. Make chemical differences readable without requiring the player to manage a molecular inventory manually.

## Several viable ways to thrive

This is a central design requirement, not an optional later polish item:

- Environmental feeding: consume resources available in the medium.
- Carnivory: damage or kill other cells and obtain their biomass.
- Engulfment: sufficient size and feeding capability allow consumption of smaller cells.
- Parasitism: extract resources from a larger living host using a proboscis-like feeding adaptation.

Parasitic feeding is included in this revision as a proboscis specialization of the existing feeding organelle. Keep grazing and engulfment within that same category; do not add a seventh organelle category.

Use a common survival/growth objective that can be reached with different diets. Avoid a victory counter that only credits environmental nutrient particles. Costs, anatomy, risk, and resource conversion should distinguish feeding strategies.

## External pressures

Introduce understandable run/habitat conditions that encourage adaptation:

- Scarce environmental nutrients make predation or parasitism valuable.
- Abundant nutrients with heavily armored, difficult-to-kill hunters reward protection and sustained repair.
- Local chemistry and currents can alter which anatomy is effective.

Dangerous hunters remain governed by the shared rules. Near-invulnerability should arise from their build and available resources. The goal is several viable strategies across different conditions; no single mandatory anatomy should solve every run.

Persistent campaigns, roguelike unlocks, inheritance, and other metagame decisions are deferred. They are not prerequisites for this revision.

## Implementation sequence

1. **Physical foundation and continuous view:** replace wall-bound contact with wrapping coordinates, a following microscope view, and an explicit active region. Build and validate significant two-way cell/fluid coupling and stable cell contacts.
2. **Living anatomy:** free membrane placement and packing, biomass-dependent volume/mass/inertia, pressure plus internal tension, and organelle damage/self-repair. Preserve the ease of paused anatomical changes.
3. **Shared ecology and resource cycles:** migrate other organisms to the same systems, implement actual hunter death and replacement, make waste consequential, and extend particle signaling.
4. **Feeding strategies and environmental pressures:** implement the agreed feeding scope, vary habitat conditions, and demonstrate contrasting viable builds. Profile on the target Linux machine before choosing native/GPU acceleration.

Each step should remain playable and have focused behavioral and numerical checks. The fluid/body coupling experiment is the main technical feasibility step; do not postpone it until after building a large ecosystem on an unsuitable motion model.

## Acceptance evidence

- Organelle capacity follows available membrane surface; motion responds to added mass and asymmetric inertia.
- Pressure and internal tension support stable noncircular cells through growth, contact, and fluid forces.
- Contact stress does not teleport a cell through another cell.
- Currents move cells, and moving cells measurably move the surrounding medium.
- World seams are visually continuous and preserve interactions.
- Dormant state is unchanged by ordinary ticks; explicit triggers are the only offscreen changes. Waking preserves state and resource accounting.
- Local particle interactions cause feeding, signaling, offensive effects, and chemical transformations.
- Organelles take damage and spend biomass on repair under the agreed rule; regenerative organelles remain useful.
- Hunters can die once, release accounted-for nutrients, and be replaced without a health-reset loophole.
- Different diets/builds can reach the same growth/survival objective under suitable environmental conditions.
- Performance evidence includes active organism/particle counts and target-machine CPU/GPU/frame timing. No unmeasured scale or frame-rate guarantee.

## Confirmed decisions and performance reference

- Attacks are local. Exposed membrane can develop holes and leak biomass; membrane closure is quick. An organelle elsewhere is not a global shield.
- Include proboscis/parasitic feeding now within the existing feeding category.
- The owner's separate Linux machine runs Steam Godot **4.7.2**, an **Nvidia RTX 3090**, and an **AMD Ryzen Threadripper 2990WX (32 cores)**. RAM was not specified.
- Treat that machine as a high-end reference for exploring upper simulation capacity, not a minimum requirement. Keep conservative defaults and measure CPU and GPU costs separately before setting performance targets. No benchmark has been run on the owner's machine.

No gameplay design questions remain open for starting this revision.

## Validation and remaining limits

The implementation includes the six categories with three feeding modes, continuous placement and packing, biomass-dependent geometry/inertia, local punctures and repair, internal signals, a shared cell model, hunter death/replacement, waste recycling, a wrapping microscope view, and locally active two-way fluid interaction.

Automated validation covers material accounting, momentum exchange, dissipative drag, pressure/tension stability, compressed contacts, seam feeding, dormant state, grazing/parasitism/engulfment interactions, hunter death exactly once, shared food progress, and interface controls. The suite passes 164 assertions. A crowded fixture and a 90-second autonomous default run are included, alongside 30-second parasite and engulfer trials against targets with stationary anatomy. These trials use ordinary fluid/biology rules and no steering after setup. Steam launcher fixtures pass all seven tests. Rendered gameplay and assembly receive separate visual inspection.

The medium is a finite-mass viscous grid with explicit tidal forcing, not an incompressible Navier–Stokes solver. Body/ring contact uses swept radial extents rather than a full soft-body contact manifold. Fluid traction does not yet solve ring deformation jointly with pressure. Feeding strategies share the objective and their interactions are tested; comparable difficulty and long-term viability across all habitats still require player feedback.

On the validation workstation (Ryzen 9 9950X, Godot 4.7.2), the 90-second run took 29.04 seconds of wall time: about 5.38 ms per simulation tick, with a 11.21 ms observed maximum. At its end, 2 of 19 stored cells and 214 of 3,221 particles were active. The crowded fixture started with 13 cells and averaged 6.35 ms per tick over 360 ticks. The default grazer processed 98.5 food and reached the milestone at full health. The parasite trial processed 42.0 food; the engulfer processed 43.1 food after consuming two cells. Both ended at full health. These are fixture results, not general difficulty guarantees. The workstation is shared; another build was active near the end of the final run, so timings are observations rather than performance thresholds.

Local headless measurements are CPU simulation evidence only. They do not include GPU rendering and do not establish performance on the owner's RTX 3090 / Threadripper machine. No minimum hardware or population-scale guarantee has been set. Saves, audio, permanent progression, and new organelle categories remain outside this revision.
