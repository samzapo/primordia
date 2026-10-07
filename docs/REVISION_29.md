# Revision 29 — retain collisions, cull contact candidates

Ordinary gameplay restores soft particle–particle repulsion. The overlap trial looked worse to the owner and did not improve dense performance. Its settings checkbox and persisted preference are removed, so an old saved collision-free choice cannot carry into this revision. New worlds and restarts use collisions in native and script gameplay.

The explicit profiler option `--particle-collisions=off` remains for diagnostics. Currents, independent diffusion, oriented binding, material accounting, membrane exclusion and plant permeability retain their existing rules. Branch/fork artwork does not define physical collision geometry.

## Exact optimizations

**Tighter grid broad phase:** the old chemistry loop visited every grid bin inside a fixed 18-unit search square. The native loop now uses the particle's tick-cached radius plus the largest eligible partner radius, with a small conservative float-coordinate margin. This gives a tighter AABB over the same grid. Bins outside it cannot contain an accepted contact. Remaining bins retain their traversal order, and contacts retain the same circular distance test and separation arithmetic.

The bound uses the radii cached for that chemistry pass, including the largest indexed particle; it does not shrink interaction radii or cap neighbors. Wrapped contacts and grid-edge cases remain eligible. The original wider search is available by passing `--hotpaths=reaction_bounds`.

**Lazy acidity:** acid-independent contacts no longer sample the acidity field. Enzyme/waste still samples before computing its acidity-dependent alignment threshold. Aligned waste/oxygen recycling still reads the current acidity. Other reactions and repulsion use their original calculations. `--hotpaths=reaction_acid` restores eager sampling.

Both switches are profiling ablations: naming one disables that optimization. Ordinary gameplay enables both. The script backend retains the reference search/calculations.

## Per-item measurements

Godot 4.7.2, Ryzen 9950X / RTX 5080, Mobile renderer, GPU-rendered virtual Wayland output, 1440×900 at the widest 80% view. The current medium, paid cilia, music, bloom, streamers, wakes and sparks remain active. Dummy audio and a virtual display are not an owner-machine or speaker playtest. The owner's RTX 3090 / Threadripper 2990WX Steam setup remains untested.

Each fixed trace starts from 50,000 uniformly distributed finite chemical packets and advances 120 ticks across 120 displayed frames: two simulated seconds. The original and combined paths have two trials in reversed order; individual ablations have one trial each. All paths use collisions.

| Path | Whole-frame mean | Whole-frame p95 | Chemistry per tick |
| --- | --- | --- | --- |
| Original wide search + eager acidity | 39.75 / 37.58 ms | 57.75 / 56.98 ms | 13.62 / 13.56 ms |
| Tight bounds only | 31.78 ms | 48.01 ms | 7.95 ms |
| Lazy acidity only | 38.22 ms | 57.04 ms | 13.49 ms |
| Both | 30.64 / 32.12 ms | 46.65 / 44.71 ms | 7.84 / 7.78 ms |

Combined repeated means improve from **38.66 to 31.38 ms**, about **19%**. Chemistry improves from **13.59 to 7.81 ms**, about **43%**. The dominant gain is grid culling. Lazy acidity's chemistry difference is small enough that these trials do not establish a meaningful independent gain; it avoids unnecessary work without changing outcomes.

Every fixed 50k trace finishes with identical reaction event counts, accounted packet material and all three random states: 30,972 merges, 299 decays and 639.32362812373 accounted material. This preserves the collision-on result from Revision 28. These fixtures still shrink; their minimum observed packet count is 19,606. They do not prove sustained 50k capacity.

A separate fixed 20k pair improves whole-frame mean from **20.32 to 17.77 ms**, with p95 from 24.28 to 20.90 ms and matching outcomes.

## Live catch-up

One eight-second live trace per path and density:

| Initial packets / path | Mean / p95 frame | Simulated / wall seconds | Catch-up |
| --- | --- | --- | --- |
| 20k original | 12.05 / 20.89 ms | 7.98 / 8.00 s | Up to four ticks per frame |
| 20k optimized | 9.59 / 17.95 ms | 7.98 / 8.00 s | Up to two ticks per frame |
| 50k original | 40.01 / 156.80 ms | 6.80 / 8.00 s | 15 eight-tick frames |
| 50k optimized | 40.28 / 140.12 ms | 7.17 / 8.01 s | 12 eight-tick frames |

20k keeps pace with wall time in this shrinking fixture, with lower stalls. The 50k live mean barely changes, while simulation advances further and p95 improves; catch-up still amplifies slow ticks. **The sustained 50k/60 FPS goal remains unmet.** These short trials on a shared workstation are not long-run frame pacing or owner-hardware validation. Default gameplay density is unchanged.

## Why not use bin membership as a reaction?

A same-bin, aligned reaction rule could omit some geometry checks, but it changes reaction reach and creates boundary-dependent encounters unless adjacent bins are included. Physical repulsion would still require distances for nonreacting contacts. Faster packet merging would also lower subsequent work by changing the chemistry, rather than proving an equivalent collision optimization.

For this revision the owner delegated that choice, and the exact broad-phase improvement gives a substantial measured saving while preserving the game. Bin-based chemistry remains a possible separately measured approximation; it is not adopted here.

## Verification and reproduction

- Native suite: **7,038 assertions, zero failures**.
- Independent script suite: **3,288 assertions, zero failures**.
- Editor import and whitespace checks pass.
- Exact packet fields, reactions, material, clocks, render buffers and random states match the original path in full ecology tests. Pair tests cover every species/order/alignment/acidity combination with both collision choices. Dense edge tests cover wrapped boundaries, all species, repeated reactions, mixed particle sizes and detailed/coarse chemistry.
- Twelve new rendered comparison traces complete. One completed fixed trace required the runner to stop its owned Godot process after a Wayland shutdown stall; the saved trace was validated before cleanup. No timeout or script error interrupted measurement.

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh

# Original collision path; disable both optimizations.
./tools/fluid_compare.sh current --chemicals=50000 --frames=120 --hotpaths=reaction_bounds,reaction_acid --output=/tmp/primordia-original.json

# Optimized collision path.
./tools/fluid_compare.sh current --chemicals=50000 --frames=120 --output=/tmp/primordia-optimized.json
python3 tools/fluid_report.py /tmp/primordia-original.json /tmp/primordia-optimized.json
```

Use `--hotpaths=reaction_acid` for tight bounds only, `--hotpaths=reaction_bounds` for lazy acidity only, or `--frame-step=live --seconds=8` for live traces. Raw benchmark and validation evidence stays in project-local task records rather than generated committed assets.

[references.md](../references.md) retains the scientific motivation and approximation limits for diffusion, chemical encounters and soft repulsion.

## Other collision-search candidates

These are recommendations, not additional implemented backends in Revision 29:

- A compact, spatially sorted grid keeps nearby particle data contiguous; [NVIDIA's broad-phase chapter](https://developer.nvidia.com/gpugems/gpugems3/part-v-physics-simulation/chapter-32-broad-phase-collision-detection-cuda) describes cell sorting and indexing.
- Buffered Verlet neighbor lists reuse a conservative pair set across steps. [LAMMPS](https://docs.lammps.org/Developer_par_neigh.html) documents the movement margin and rebuilding. Primordia also needs invalidation for growing contact radii, emissions and removals.
- Stenciled or multilevel grids narrow searches for different interaction sizes. [HOOMD Stencil](https://hoomd-blue.readthedocs.io/en/latest/hoomd/md/nlist/stencil.html) is a primary implementation reference.
- BVHs bound particle groups rather than empty space. [HOOMD Tree](https://hoomd-blue.readthedocs.io/en/latest/hoomd/md/nlist/tree.html) discusses sparse/mixed-size advantages and benchmarking. [Howard et al. (2019)](https://arxiv.org/abs/1901.08088) measured quantized GPU BVHs against grids; those gains are not a Primordia result.

The next recommended comparison is a packed grid versus a BVH on uniform clouds, dense clumps and varied radii, including structure updates, candidate counts, memory and whole live frames. Neighbor caching is a separate layer that can accompany either. A 2D quadtree is also possible; an octree's third dimension is unnecessary for this game. Large bodies and small chemical particles need not share one accelerator. GPU acceleration must account for the existing transfer-cost limitation before adoption.
