# Revision 38 — desktop cell feedback from resident particles

Desktop performance and correctness are the current integration gates. Phone performance remains a design goal; Pixel 9 Pro XL, Galaxy Z Flip7 and Apple-device measurements are future validation, not a prerequisite for desktop work.

This revision adds resident pheromone ownership and GPU grazing/hunting/flight queries to the finite feeding bridge. The compact results drive the existing CPU signal-delivery and resource routines in a coupled diagnostic. **Ordinary gameplay still uses the CPU pool. This is not yet a complete GPU game backend or a measured game-FPS gain.**

## What is implemented

- Sparse initial owner metadata and immutable pheromone reports: source ID, lineage, emitted position, mass, radius, hostility, defense, emission time and sampled expiry. IDs remain 32-bit integers, not float approximations. Reading a report never resolves a live source cell.
- Global signal expiry during transport and exchange, independent of camera or receptor presence. New reports replace metadata only after their emission was accepted into a free slot. Expiry and slot reuse preserve generation handles; refused emissions do not overwrite a report.
- The newest locally received report per source supersedes older reports before prey eligibility is evaluated. Family/self exclusion, smaller-or-undefended prey, threat selection, incumbent weighting and emission-time target positions follow the existing perception rules.
- Grazing retains finite nutrient-mass bins, neighboring-bin patch weighting, the mild travel penalty and the inner switch to an actual packet. It excludes self-owned food from steering, without changing physical feeding.
- Grazing, hunting and flight each return an 80-byte result in the same receipt as feeding, emissions and sparse inspection. There is no full particle download inside a timed step.
- Existing CPU signal delivery retains organ weights, flight priority, the switch margin, signal travel, expiry and exploration duty. Static light sensing stays on the CPU.
- The shared grid can include pheromones for queries; both endpoints of physical contact screening and reaction voting explicitly exclude them. Orientation still affects reactions and drawing, never physical shape.

The CPU remains authoritative for cell resources. Each completed receipt is credited before metabolism, maintenance, healing and the next capacity snapshot. The diagnostic does not overlap dependent physiological updates, invent new reserves or grant stale feeding capacity.

## Desktop measurements

Godot 4.7.2, Vulkan Mobile, RTX 5080 on the shared workstation, through a task-owned hardware-rendered Weston output. Each run advances 120 fixed 1/60-second steps from 50,000 slots, with eight actual cells and one approximately 140-unit-radius membrane. Two repetitions reverse method order. All methods use identical initial material, fixed flow and stationary body centers; membranes deform and growth changes their capacities.

Values below are the mean of the two run means and the mean of their per-run p95s. These are exploratory subsystem measurements, not confidence intervals.

| Distribution and method | Completed step mean | Per-run p95 mean |
| --- | ---: | ---: |
| Uniform, queries disabled | 3.59 ms | 4.02 ms |
| Uniform, queries packed into workgroups | 4.67 ms | 13.88 ms |
| Uniform, queries spread across workgroups | **4.01 ms** | **6.93 ms** |
| Uniform, wait for each async receipt | 50.13 ms | 50.43 ms |
| Clustered, queries disabled | 6.38 ms | 10.59 ms |
| Clustered, queries packed into workgroups | 8.68 ms | 24.30 ms |
| Clustered, queries spread across workgroups | **6.86 ms** | **11.80 ms** |
| Clustered, wait for each async receipt | 50.22 ms | 50.41 ms |

Packing a small receptor batch into one workgroup concentrates divergent food/report processing on one compute unit. Giving each receptor its own workgroup lowers total coupled-step mean by about 14% uniform and 21% clustered relative to that packed query implementation; its p95 boundary is about 50% lower. The packed layout remains available through `perception_spread_queries=false` for ablation. This does not compare against the full CPU game.

The immediate handoff is the practical desktop baseline. The approximately 50 ms asynchronous result is a dependent readback round trip through queued frames, not 50 ms of GPU computation. An asynchronous API alone does not remove a data dependency.

Each run executes 288 receptor requests at the existing sensing cadence. Average transfers are approximately 10.2 kB uploaded and 579 bytes read back per step, including geometry and real metabolic waste emissions. CPU biology costs approximately 1.1 ms per step. Timed full-pool readbacks: zero. Final material, ATP, oxygen, metabolic throughput, accepted emissions and live counts agree within 0.00001 across handoff/query-layout variants.

Final populations are **39,896 uniform and 26,798 clustered**, following reactions, finite intake and pheromone expiry. This is two simulated seconds with a shrinking population, not sustained 50k gameplay. The queries-disabled case is an overhead ablation, not equivalent autonomous behavior.

## API and bounds

Call `configure_interactions(...)`, `configure_exchange()`, then `configure_perception(initial_time)` before initialization. Pass sparse metadata with `initialize(state, flow, metadata)`. All initial and emitted pheromones require a valid owner/report/expiry; unsupported records fail before submission.

`ResidentPerception.requests(cells, dt, now)` snapshots receptors due to sample this tick. Pass the resulting queries as the fifth argument to `exchange(cells, emissions, handles, asynchronous, queries)`. A successful receipt contains `senses`; `ResidentPerception.for_cell(...)` adapts these to the optional completed-results argument of `Simulation._sense`. Ordinary two-argument calls keep their original CPU query path.

Queries use the pre-feeding particle state. Accepted emissions become visible to a subsequent query. Run receptor cleaning before taking the request snapshot. Deliver the completed sense results before crediting feeding, so prey comparisons use pre-feeding cell mass. The helper accounts for memory expiring during the coming local step. Resource credit and metabolism follow the receipt. The API does not itself credit resources or refund refused products; the caller owns these transactions.

Current limits are 256 receptor requests and 1,024 distinct source IDs over a pool's lifetime, in addition to the existing 64-body and emission/inspection limits. Source registrations are retained even if a submitted emission was refused for lack of a free particle slot. Overflow rejects the request; it never returns a truncated neighborhood. Production integration still needs source-table retirement/reuse or growth. Reports and query scratch add roughly 7.4 MB at 50k slots, excluding the existing contact/grid/exchange buffers.

Equal-time and equal-score ties use canonical 64-unit bin/slot order, matching an initially built CPU grid. The incremental CPU grid can have a different insertion order after movement; such exact ties are not promised to select identical packets across backends. GPU geometry, times and weights use float32; threshold-rounding and long-horizon ecological equivalence remain validation concerns. This is not cross-platform determinism.

## Validation

Validation passed: 69,807 native and 3,294 script assertions; 372 new perception, 296 exchange, 1,111 queue, 3,340 matching and 114 grid GPU checks; six GPU/native transport comparisons; 11 launcher fixtures; repository and portable-project imports.

The dedicated GPU suite checks report copying, exact 32-bit identities, stale-report suppression, family/self exclusion, global expiry, generation reuse, refused emissions, combined asynchronous inspection, unchanged collision/reaction outcomes, full source/query capacities, patch targets over periodic seams and reaches from 50 to 4,096 units, and identical results between query layouts. It compares delivered signals with both dictionary and authoritative native-pool perception.

The coupled fixture uses the existing CPU receptor delivery, metabolism, upkeep, healing and membrane functions, with waste emitted from actual accumulated material. It verifies equal-horizon resource/population outcomes and finite final state. It does not use GPU-computed biology or a capacity-only shortcut.

Run the GPU tests with a real Mobile/Forward+ display, using the Steam-discovered Godot executable or the explicit `GODOT_BIN` override:

~~~sh
"$GODOT_BIN" --path . --rendering-method mobile --script tests/resident_perception_gpu.gd
"$GODOT_BIN" --path . --rendering-method mobile --script tests/resident_coupling_benchmark.gd
~~~

Headless/Compatibility runs cannot validate compute. The portable benchmark generator includes the new script, shader and mutation-rule dependency; this packaging check is not a phone-performance result.

## Remaining integration

The resident path still needs the rest of particle/cell coupling: toxin and decoy exposure, secretion demand queries, spatially varying acidity and unary chemistry, changing flow, photosynthesis and death/lysis emission bookkeeping, offscreen ecology and succession. Complete drawing, music, motion/contact and live catch-up are outside this fixture.

After those paths share authoritative particle state, compare whole rendered frames at the 80% playable view with large moving cells and dense clusters. Sustain the intended population and verify finite accounting and ecology over longer runs before choosing a new gameplay default. GPU live-slot compaction, full CPU SIMD storage and true coarse collision/reaction parcels remain separate optimization targets.
