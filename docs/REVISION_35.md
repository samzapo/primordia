# Revision 35 — mutual-choice GPU reaction prototype

The standalone resident diagnostic now supports circular contacts, collision impulses and oriented pair chemistry. Ordinary gameplay still uses the established CPU simulation. This is not the fully coupled GPU game backend.

## Matching contract

After the spatial grid is built, one parallel voting pass and one parallel commit pass replace the experimental serial reaction loop. A candidate must satisfy circular reach, species compatibility, facing, fixed acidity and finite-resource conditions. Pheromones and dead slots are excluded.

Both endpoints evaluate a pair in canonical ID order. Rank is the weaker endpoint's facing alignment, quantized into 1,025 levels. Equally ranked edges use a shared tick-dependent hash of the two slot IDs. Endpoint IDs break rare hash collisions, producing a total edge order. This is a reproducible tie-breaker within this diagnostic, not a claim of cross-device floating-point determinism or molecular kinetics.

Only mutually selected partners react. The lower ID writes both endpoints; all other invocations write only their own unmatched slot or return. Products cannot participate until the next update. One round can leave feasible pairs unmatched; it is neither a maximum matching nor necessarily a maximal matching. It intentionally changes the old sequential reaction semantics.

Collision impulses are accumulated per particle from immutable pre-reaction state, including contacts that subsequently react. Commit applies those impulses before product velocity mixing. This differs from the old reaction-first suppression of a successful pair's impulse, but preserves equal/opposite pair impulses without floating-point atomics or conflicting velocity writes. Orientation affects chemistry, not collision geometry.

The sorted periodic grid uses 16-unit bins. Contact diagnostics retain 64 IDs per particle plus the complete count; voting always scans the full grid neighborhood and never uses a truncated contact list. Supported input chemical diameter is at most 17 units. Dead slots retain identity and have zero diameter/material; no compaction is implemented.

## Scope

Modes: off (default), contacts, collisions, chemistry, configured through resident_particles.gd before initialization. There are two reaction dispatches after neighbor preparation, not two total GPU dispatches: the current bitonic grid construction requires many sorting dispatches.

Pair rules include enzyme digestion, toxin neutralization, acid/buffer neutralization, waste/oxygen recycling, toxin spoilage and same-species aggregation. Acidity is a fixed test parameter. Unary decay, spatial acidity evolution, cell feeding/emission/exclusion, product-reserve bookkeeping, stable handles across compaction and the full game bridge remain pending. The existing CPU transport comparator is not a matching chemistry implementation.

No phone, APK, iOS, full-game FPS or thermal claim follows from this prototype. Default gameplay and density are unchanged.

## Validation and measurement

Run on the workstation's NVIDIA RTX 5080, Godot 4.7.2 Mobile/Vulkan renderer through a headless Weston hardware display. The user's RTX 3090 and phones were not measured.

- 3,340 GPU assertions, including delayed product eligibility and pheromone exclusion.
- Independent brute-force CPU votes versus GPU votes: periodic seam contacts, equal-score contention, partial workgroups and neighborhoods exceeding 64 candidates, across eight tick seeds.
- Misalignment rejects chemistry; each matched endpoint is consumed at most once; aggregation conserves material.
- Pair fixtures cover every implemented transformation, inhibited enzyme digestion and neutralization capacity.
- Six existing GPU transport parity cases passed. Native gameplay: 69,707 assertions passed; script fallback: 3,294 assertions passed. These are separate regression gates, not full GPU gameplay validation.

The 50,000-slot benchmark advances 30 fixed steps after one warmup interaction, then waits for a full snapshot. Values below include queued execution and the completion/readback fence, divided by 30. They are batch throughput, not per-frame latency or rendered FPS. A first frame-paced experiment measured roughly 24 ms across every mode and was rejected as a simulation timing measure.

| Distribution | Contact mode | Collision mode | Chemistry mode |
|---|---:|---:|---:|
| Uniform | 0.565 ms | 0.670 ms | 0.641 ms |
| Clustered | 1.056 ms | 2.169 ms | 1.492 ms |

Chemistry finishes with 47,268 live uniform particles and 34,067 clustered particles, so its lower cost than collisions is not evidence of a cheaper kernel at equal density. No serial chemistry speedup is claimed. These are short single-run measurements, not sustained results. Last-tick counters are not cumulative event totals.

Commands (Steam engine discovery remains available through the existing launcher):

~~~sh
godot --path . --rendering-method mobile --script tests/resident_matching_gpu.gd
godot --path . --rendering-method mobile --script tests/resident_matching_benchmark.gd
~~~

A real RenderingDevice display is required. The small portable export manifest includes all new shader sources; actual Android export/device verification remains pending.
