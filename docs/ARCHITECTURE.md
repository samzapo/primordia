# Living cell architecture

## Authoritative state

`simulation.gd` advances at 60 Hz, independent of scenes, rendering, and input. `cell.gd` supplies the same anatomy, material accounting, damage, repair, volume, and inertia for the player and NPCs. Initial roles select anatomy; they do not supply invulnerability or a separate pursuit controller. The seeded RNG and stable array order support replay on one engine/platform.

The world is a 4096 × 2560 torus. `medium.gd` defines nearest-image distances and wrapping; the spatial grid wraps its buckets too. Rendering projects the nearest image around the player's cell, so the following camera never jumps at a seam. The visible center advances fully, the elliptical fringe slows smoothly, and positions outside the ellipse do not advance. Dormant fluid nodes cannot exchange impulses with active neighbors. Death/replacement events are recorded separately; replacement is explicit external ecosystem input.

A tick updates the active fluid, transports active particles, rebuilds local queries, processes chemistry and cell biology, updates anatomy, applies three motion/contact substeps, then feeding between cells and toxin contact. Death removes individuals once. Rebuild the particle grid after compaction before replenishment; its indices are only valid for the array used to build it.

## Cell material and geometry

Organic material is tracked in structural body mass, available biomass, organs, gut substrate, and pending waste. Assembly transfers reserves into organs. Damage releases their lost material; repair incorporates reserves. Recycling returns half the remaining material and releases the other half as waste. A puncture drains reserves, then structure, and emits nutrient material at the wound. Local leakage packets merge only with active neighbors to keep continuous leakage from generating excessive tiny particles.

Effective volume is `body + biomass`. Render radius follows a sphere-inspired cube root of that volume, projected into 2D. Capacity uses the actual 2D membrane perimeter and each organ's arc footprint plus clearance. It is not a full 3D surface-packing model. Organ angles drift with relative tangential flow and resolve packing. Shrinkage sheds crowded organs as accounted-for debris.

Translational mass includes retained organic material. Rotational inertia includes distributed cytoplasm and organ mass at its attachment radius. Propulsion at asymmetric locations produces torque. There is no historical-food-only growth counter; losing retained mass reduces size.

`membrane.gd` solves 28 boundary nodes with compliant XPBD edge and enclosed-area constraints. Four internal tensile chords and elliptical rest geometry support noncircular shapes while preserving pressure-driven area. The art displays the actual chords. This remains a stabilized 2D membrane model, not a microtubule or cytoskeleton material simulation.

Contacts use radial extents sampled from the membrane. Sweeps prevent a moving body from crossing another between steps; iterative mass-weighted overlap and velocity impulses separate compressed bodies. Contact locally compresses membrane nodes. This is a hybrid body/ring model, not a full deformable contact manifold. Deep initial overlap has no unique physical history; the solver selects a consistent separation normal.

## Finite-mass liquid

The medium has 64 × 40 velocity nodes, spaced 64 world units apart. Each has 22 mass units, comparable to the material surrounding a starting cell of about 100 units. Bilinear sampling transports chemicals. Six cell boundary points exchange implicit drag impulses with active fluid nodes. Each body impulse has an equal and opposite fluid impulse, including reaction to propulsion. Rotational velocity participates in drag. Undriven viscosity exchanges velocity symmetrically, conserving linear momentum.

Periodic currents initialize local eddies. A weak relaxation toward that field is an explicit external tide, a momentum/energy source and sink. Dormant nodes retain their velocity. The numerical tests disable forcing to measure conservation and dissipative drag independently.

This is a mass-lumped viscous medium with fixed density, not an incompressible fluid solver: no pressure projection, moving free surface, or volume-exclusion calculation is claimed. It provides substantial two-way motion coupling. Fluid traction does not yet solve membrane shape jointly with contact and pressure.

## Chemical and sensory particles

Five external species are authoritative: nutrient, oxygen, waste, cell trace, and toxin. Actual local particle contact triggers absorption, decomposition, or damage; rendered particles are not a substitute for the simulation.

In game units, respiration consumes one food and one oxygen unit, producing five ATP, 0.8 biomass, and 0.2 waste. Waste decomposition requires nearby oxygen and yields 0.6 food per waste unit; the remaining 0.4 leaves the organic pool as a recorded respiration loss. Photosynthetic habitat input explicitly replenishes local food and oxygen. Recycling cannot create an infinite resource loop. These are coarse resource rules, not molecular stoichiometry.

Receptors detect food and size-bearing cell traces. Signals physically travel inward through the cell before changing its innate target and offensive response. A grazer favors food and avoids larger traces; an engulfer pursues smaller traces; a parasite approaches larger hosts. No behavior wiring editor is introduced.

The feeding category has three modes. Grazers absorb nutrient packets, including carcasses. Engulfers damage sufficiently smaller cells through mouth contact and transfer a gut-capacity-limited portion upon death, releasing the remainder. Proboscises puncture local defenses and drain larger living hosts. All food enters the same metabolism and milestone counter. Organelle categories remain unchanged.

Damage is local. An organ at impact absorbs damage first. Exposed membrane can develop a leaking hole even when other organs survive. Baseline closure is quick; membrane and organ restoration use reserves and ATP, and regenerative organs accelerate both. Lethal damage cannot be undone by the healing phase. A hunter's death releases retained organic material once; replacement has a fresh identity beyond view and its initial material is logged as ecosystem input.

## Rendering, input, and limits

`pond.gd` draws original procedural cells and organs, membrane tension chords, internal signals, current marks, and interface cards. Five MultiMeshes draw external chemicals. `microscope.gdshader` darkens the activity fringe; status UI renders above it. All world art is clipped to the viewport. Assembly pauses simulation, and the click is projected onto the membrane rather than quantized to sockets.

The current render allocation is 5,000 visible instances per external species. This is a rendering allocation, not evidence for that many actively simulated particles. Resource packets can carry fractional or multiple material units. The stored ecosystem is larger than the active window; scanning stored arrays still has CPU cost, so unbounded world populations are not promised.

Tests cover conservation, local damage, all feeding interactions, seam behavior, dormancy, pressure/tension stability, compressed contacts, death/replacement, deterministic replay, a crowded fixture, a 90-second default run, 30-second autonomous parasite/engulfer fixtures, and UI actions. Captures are inspected separately. The launchers fail on script errors even if Godot exits zero. Profiling on the owner's machine remains necessary before performance targets or acceleration decisions.
