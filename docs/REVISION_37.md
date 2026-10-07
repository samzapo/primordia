# Revision 37 — stable GPU grids and queued cell exchange

## Scope and decision

The resident GPU experiment now uses a stable radix grid by default, with the previous bitonic grid retained as an explicit comparison. A bounded asynchronous exchange queue keeps finite feeding-capacity reservations on the GPU. Ordinary gameplay still uses the existing native CPU engine; these changes do not raise normal density or constitute a complete GPU game port.

This advances the first two priorities of the approved optimization plan. Persistent SIMD-friendly CPU storage and weighted collision/reaction parcels remain later work. Full GPU physiology, perception and chemistry remain prerequisites for integrating the resident pipeline into the game.

## Stable grid

Four stable four-bit radix iterations replace the global bitonic sorting network. Each iteration counts digits by workgroup, scans block counts and scatters particles with a stable rank inside its workgroup. The 16-bit bin key covers all 40,960 periodic bins and the inactive sentinel. Initial IDs are ordered, so stability reproduces the exact old per-bin ID ordering without rearranging authoritative slots.

At 50k particles, sorting takes 12 dispatches instead of 136. Including initialization and range construction, the complete grid takes 14 instead of 138. The old method remains available with configure_grid("bitonic") before initialization. The new sorter uses no subgroup/vendor-specific instructions. It adds temporary sorting/histogram storage; it does not compact dead slots or change handles.

Correctness fixtures cover 1, 127, 128, 129, 4,097, 50k and 100k slots, partial workgroups, boundary bins, all-dead input and 50k particles in one bin. Independent expected keys and ranges match exactly. Uniform, clustered and seam trajectories retain bit-identical particle state, impulses, votes, contacts and reaction totals versus the old grid in the tested cases. This is local equivalence, not cross-platform determinism.

## Finite exchange queue

configure_exchange() retains the existing one-outstanding-request behavior. configure_exchange(8, true) enables up to eight in-flight exchanges with resident capacity reservations.

- The first request starts a capacity interval from actual remaining gut, oxygen and carbon storage. GPU feeding subtracts from those remaining capacities on every step, even before a receipt reaches the CPU. Reusing a stale CPU snapshot cannot allocate that room again.
- All requests in the interval retain the same cell objects, IDs, order and capacities. Position and membrane deformation may change. Duplicate IDs, replaced cells, changed capacities and a full queue are rejected explicitly.
- Each queue slot has a separate receipt buffer. Asynchronous callbacks are delivered in submission order, exactly once, even if they arrive out of order. A full queue applies backpressure; it never drops a simulation update.
- Paid emissions retain their existing caller-owned escrow contract. Refused emissions remain in escrow. Close drains every outstanding receipt before freeing GPU resources.
- After all receipts have arrived and been credited, end_capacity_epoch() permits a fresh interval. The caller must account for actual spending before importing newly available room. Pending reservations cannot be reset.
- An exact parallel oxygen prepass computes membrane eligibility before the ordered finite feeding transaction. The comparison switch exchange_parallel_oxygen=false retains the original inline support calculation. Both paths use the physical outline and the same margin; no circle approximation replaces the membrane.
- Startup reports insufficient compute/storage-buffer limits explicitly. The exchange shader requires eleven storage-buffer bindings, so phone compatibility must be measured rather than inferred.

**Limit:** this is a fixed-capacity exchange pipeline, not GPU physiology. Metabolism, ATP use, growth, death, births and capacity changes require draining/reconciliation; dependent cell behavior cannot simply spend delayed intake. Full resource accounts, immutable pheromone metadata, perception, toxin/decoy exposure, unary chemistry and dynamic acidity still need integration. No production CPU/GPU feedback dependency is claimed solved by buffering alone.

## Completed GPU work measurements

Godot 4.7.2, RTX 5080 / Ryzen 9950X, Mobile/Vulkan, hardware-rendered headless Weston. Each timed batch has 60 completed steps after shader warmup and resetting the same initial state; its final completion/readback is included. Three repetitions alternate backend order. Values below are medians of those three batch means, not full-game frame times.

| 50k-slot workload | Bitonic | Radix |
|---|---:|---:|
| Uniform grid construction | 0.466 ms | 0.068 ms |
| Clustered grid construction | 0.439 ms | 0.063 ms |
| Uniform transport and circular collisions | 0.646 ms | 0.278 ms |
| Clustered transport and circular collisions | 1.737 ms | 1.384 ms |
| Uniform transport, collisions and matching reactions | 0.645 ms | 0.264 ms |
| Clustered transport, collisions and matching reactions | 1.206 ms | 0.824 ms |

Collision-only runs retain all 50k particles. Chemistry runs finish with 45,709 uniform or 31,686 clustered particles for both grids; they are not sustained-50k chemistry claims. No full-game speedup follows from these kernel/batch measurements.

## Rendered particle scene

1440×900, 80% zoom, 60 warmup ticks and 300 measured frames. Both modes retain 50k particles, the same finite material, circular collisions, orientation and direct texture drawing. The completed mean includes the final drain/readback amortized across the capture.

| Workload | Bitonic completed mean | Radix completed mean |
|---|---:|---:|
| Uniform | 0.781 ms | 0.437 ms |
| Initially clustered | 0.981 ms | 0.631 ms |

These are uncapped particle-scene throughput results, not playable ecosystem FPS. This scene excludes cells, plants, biology, music and live catch-up. The separate exchange fixture below includes large-cell geometry. Desktop virtual-output results do not establish phone performance.

A one-minute, initially clustered collision-only run at the 60 FPS cap records 3,602 measured frames: mean 16.660 ms, p95 16.848 ms, completed mean including final drain 16.664 ms. All 50k particles and 300.0000026 units of material remain. This validates sustained desktop collision/drawing at the cap, not sustained whole-game chemistry, battery use or phone thermals.

A separate 300-frame reactive drawing smoke finishes normally with finite state. Its population falls from 31,686 after warmup to 27,813, and reaction yields change packet material; it is not used as a sustained-density or whole-game speed claim.

## Exchange measurements

Two runs reverse method order. Each has 50k initial slots, eight actual Cell objects (one 141-unit membrane radius), 60 transport/reaction/exchange steps, and 4.8 units of paid fixture emissions. Per-step transfers remain 10,752 uploaded bytes and 640 receipt bytes. No blocking fallback, lost receipts or refused emissions occurred in this fixture.

Before the oxygen prepass, immediate / dependent asynchronous / eight-deep pipelined means were:

| Distribution | Immediate receipt | Wait for each async receipt | Pipeline |
|---|---:|---:|---:|
| Uniform | 3.75 ms | 50.16 ms | 8.26 ms |
| Clustered | 7.97 ms | 50.17 ms | 12.34 ms |

The queue overlaps readback latency but is still slower than immediate readback in this saturated-submission fixture. The approximately 50 ms is dependency round-trip time, not GPU compute cost. Do not present the 50-to-8 ms comparison as a whole-game speedup.

An independent paired oxygen-prepass comparison gives immediate 3.72 to 3.60 ms uniform and 8.07 to 7.83 ms clustered; pipelined values change from 8.26 to 8.15 ms and 12.32 to 12.20 ms. This is a modest saving, unlike the grid change. Particle counts, intake totals and remaining material agree between compared exchange paths. End populations are 44,341 and 29,349; cells only consume resources in this fixture and do not run a full autonomous ecosystem.

## Reproduce

Use the usual Steam-discovering launcher, with a real Mobile/Forward+ display:

~~~sh
./tools/particles_compare.sh gpu --count=50000 --frames=300 --interactions=collisions --grid=bitonic --output=/tmp/bitonic.json
./tools/particles_compare.sh gpu --count=50000 --frames=300 --interactions=collisions --grid=radix --output=/tmp/radix.json
python3 tools/resident_report.py /tmp/bitonic.json /tmp/radix.json
~~~

Add --distribution=clustered or --interactions=chemistry explicitly. Reports include interaction mode, grid, live counts and material. Chemistry changes must be checked against reaction rules; the report does not assume unchanged inventory in that mode. Native CPU comparators reject non-off interaction modes because they implement transport only.

GPU scripts: tests/resident_grid_gpu.gd, tests/resident_queue_gpu.gd, tests/resident_grid_benchmark.gd and tests/resident_queue_benchmark.gd. Existing transport, reaction and exchange GPU suites remain applicable. Run these using the Steam Godot executable with --path . --rendering-method mobile --script PATH; headless/Compatibility cannot validate them. The mobile benchmark generator includes the new raw shader and script automatically.

## Validation and remaining work

GPU validation: 114 grid assertions, 1,111 queue assertions, 3,340 matching assertions, 296 original exchange assertions and six GPU/native transport comparisons. Coverage includes overfull bins, exact trajectory comparisons, overlapping consumers, the second 32-bit oxygen-mask word, emission refusal, reordered receipts, queue backpressure, capacity reconciliation and draining close.

The complete native suite passes 69,807 assertions and the independent script fallback passes 3,294. All 11 launcher fixtures pass. The repository and generated portable benchmark both import without script errors; the generated manifest includes the radix shader. Steam discovery and normal gameplay defaults are preserved.

These measurements were made on a shared workstation. The rendered pairs are short exploratory captures, not confidence intervals or owner-device measurements.

The next integration work is complete cell resource/perception ownership with latency and ecological equivalence checks. Then compare the full game at 80% view with dense clusters, large cells and sustained populations before choosing a default. GPU live-slot compaction, CPU SIMD storage and true coarse reaction/collision parcels remain unimplemented. Pixel 9 Pro XL, Galaxy Z Flip7, Apple-device and thermal tests remain pending.

## Technical basis

- [AMD FidelityFX Parallel Sort](https://gpuopen.com/manuals/fidelityfx_sdk/techniques/parallel-sort/): count, prefix-scan and scatter organization. Primordia implements a small portable stable radix variant for its bin keys; it does not import AMD's vendor-tuned shaders.
- [Godot asynchronous buffer readback](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html#class-renderingdevice-method-buffer-get-data-async): results arrive after queued frames. Bounded reservations and receipt ownership address that dependency within the tested capacity interval.
