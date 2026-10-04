# First cell architecture

## Simulation owns the world

`scripts/simulation.gd` is independent of scene nodes, input, and rendering. It advances at 60 Hz with a seeded RNG. Arrays contain nutrient, oxygen, waste, predator-trace, and toxin particles. `spatial_grid.gd` supplies nearby particle candidates; actual radius tests determine interactions.

A tick advects particles through a gentle flow, builds the spatial grid, reads receptors, applies organelle forces, processes feeding and metabolism, resolves predation and toxin contact, removes consumed particles, and replenishes the pool within a population limit. Iteration order is stable within the same engine build. Per-tick spatial-grid indices are used before particle-array compaction.

Receptors combine nearby food direction and predator-trace avoidance. Their local boundary response turns the cell away from walls. Flagella turn those signals into forces at membrane sockets. There is no direct player movement input. Toxin vesicles fire along the perceived chemical gradient, not at player-selected targets.

The current metabolism is a deliberately coarse reaction: one substrate unit and one oxygen unit yield three energy units, 0.8 biomass units, and a waste emission. These units are an explicit game abstraction, not balanced molecular chemistry. The limiting reagent constrains the reaction. Repair, thrust, toxin emission, and maintenance consume resources.

## Membrane

`scripts/membrane.gd` maintains 28 boundary particles with damped position integration, XPBD edge constraints, and an enclosed-area constraint. Each substep resets multipliers; six solver iterations enforce compliance. Weak shape recovery and recentering stabilize the ring. Growth increases its target area. Catmull–Rom interpolation supplies the rendered outline.

References: [XPBD paper](https://mmacklin.com/xpbd.pdf). The implementation is a small 2D application of the method, with gameplay-oriented stabilization.

Whole-organism motion is currently solved separately from the ring. Predator contact uses circular collision proxies and compresses nearby membrane points. This is not yet a fully coupled soft-body collision or fluid solver.

## Rendering and interaction

`scripts/pond.gd` draws the UI, habitat, cells, and procedural organelle art. Each particle species has one `MultiMeshInstance2D`; a signed-distance circle shader renders antialiased particles from authoritative simulation positions. The world layer clips to the pond. The UI remains outside that clip region.

Assembly temporarily pauses simulation. Interface actions call the simulation's validated install/remove operations. Observation pause is independent of assembly pause. All attachments spend biomass; recycling refunds half. Restart constructs a new seeded world.

## Tests and boundaries

`tests/run.gd` includes numerical invariants, organelle behavior, particle triggers, complete simulation runs, and UI input. It verifies a viable adaptation strategy can feed and survive the initial milestone. The CLI runners inspect both process exit and script-error output because Godot may report script errors while returning a successful process status.

The prototype targets a few hundred gameplay particles, one player, and one hunter. MultiMesh rendering does not establish the capacity of the simulation. Profile receptor queries, membrane solving, and particle updates separately before increasing scale or moving kernels into a C++ GDExtension.

Potential next changes should preserve the simulation/render boundary: internal signaling particles, multiple autonomous organisms, membrane-to-membrane collision constraints, and richer chemical accounting.
