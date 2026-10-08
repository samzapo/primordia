# Revision 41 — bounded GPU window and sparse CPU particles

The explicit `./tools/playtest.sh resident` option now keeps nearby particles on
the GPU and retains distant packets in sparse CPU chunks. The ordinary CPU game
remains the default. This removes the requirement to transport, collide, react
and draw every stored world particle on the GPU each frame. It does **not** yet
make the entire habitat generator, fluid field or cell scheduler unbounded.

## Ownership and simulation

- A fixed widest-playable-view footprint plus a buffer defines GPU residency.
  Zooming in does not shrink it or change feeding. Chunk-aligned boundaries
  keep transition work outside the visible rectangle.
- CPU chunks retain the actual species, amount, capacity, velocity, angle,
  age, owner, immutable pheromone report and absolute clocks. They are not
  duplicate GPU poses or aggregate resources that can be spent twice.
- The background scheduler visits at most eight heap entries and transports
  at most 256 packets per tick. It uses the existing large-step midpoint
  advection, exponential launch drag and independent square-root-time Brownian
  displacement. A distant chunk need not be scanned every frame.
- Due coarse cells borrow only nearby chunks. Transport and chemistry settle
  on chunk deadlines; feeding, exposure and physiology retain existing finite
  resource rules. The cell cadence remains Revision 40's staggered 0.1 seconds.
  Paid hunting, family filtering, lysis and ordinary corpse absorption remain.
- CPU/GPU sensing merges food-bin mass/moments and the newest locally received
  report for each source **before** deciding which target is eligible. A newer
  report that prey is now large and defended invalidates an older edible report
  even when the two packets have different execution owners.
- Transfer-out receipts hold up to 512 complete packets, at most every six
  simulation ticks. Overflow stays on the GPU. Tickets make retries and
  acknowledgements exactly once; recovery also retains unacknowledged escrow.
- Up to 256 cold packets are admitted each tick, after elapsed transport and
  chemistry are settled. They enter before the next GPU step. Camera travel
  waits for admission and eviction backlogs and advances by overlapping chunks.
  Reversing direction still keeps the full display within prepared water.
  Display zoom may temporarily tighten during a viewport expansion while the
  new footprint loads; its request never changes the resource rules.
- GPU allocation remains bounded at 65,536 slots in the desktop option. Compute,
  sorting and drawing use the highest allocated live-slot watermark rather than
  traversing all reserved slots. Slots retain generation checks through reuse.
  This watermark can retain the peak local workload; it is not a compactor.
- Streaming pheromone queries use a local hash table instead of an ever-growing
  map of every organism encountered. Complete summaries have explicit bounded
  capacities (128 food bins or 64 locally received sources); overflow recovers
  to CPU without discarding material or silently truncating perception.

Cold chunks return as units when no transport occurred. Native batches handle
transport, food/report queries and spatial regrouping. CPU arrays briefly hold
borrowed cold packets inside the serial bridge scope and are empty at the end
of each resident tick. There is never a retained mirror of GPU particle poses.

F3 labels **GPU nearby particles** separately from **CPU stored** slots. Nearby
includes the preparation buffer, not just visible pixels. Cold slot counts may
include dead or expired records awaiting a scheduled reclamation visit; expired
reports cannot guide cells. Frame traces also record GPU work slots, cold work,
transfer traffic and cold preparation/sensing time.

## Measurements

Godot 4.7.2, Ryzen 9950X / RTX 5080, Mobile renderer, 1440×900, 80% zoom, owned
Weston GL display, Dummy audio, 60 FPS cap, twelve measured wall seconds. These
are workstation results, not measurements of the owner's Threadripper/RTX 3090.
The dense fixture starts with 50,000 finite packets distributed around the
habitat; it shrinks through actual chemistry and feeding.

| Run | Mean tick | FPS | p95 / p99 frame | Simulation / wall |
| --- | ---: | ---: | ---: | ---: |
| Whole-GPU reference, normal habitat | 5.34 ms | 60.03 | 17.97 / 18.62 ms | 0.999 |
| Final streaming, normal habitat | 5.89 ms | 60.03 | 18.26 / 18.89 ms | 0.999 |
| Whole-GPU reference, 50k habitat | 5.92 ms | 60.04 | 19.04 / 19.61 ms | 0.999 |
| Initial streaming, 50k habitat | 19.13 ms | 41.78 | 47.41 / 62.53 ms | 0.682 |
| Native cold transport/sensing | 14.75 ms | 51.73 | 36.09 / 45.37 ms | 0.876 |
| Return unchanged chunks as units | 11.44 ms | 58.53 | 31.60 / 39.12 ms | 0.993 |
| Final streaming, native regrouping | 10.61 ms | 59.04 | 28.36 / 35.43 ms | 0.997 |

Streaming is **not faster than the whole-GPU reference in this small fixed
habitat on the RTX 5080**. It trades CPU cold simulation and transfer overhead
for bounded GPU work. Native batching removes much of the first implementation's
regression, but dense cold preparation still produces frame spikes. The normal
run is suitable for the next comparative desktop playtest; these measurements
do not establish sustained 50k visible gameplay or phone performance.

The final normal run ended with 1,932 GPU packets and 1,874 stored CPU slots;
GPU work used 1,948 slots rather than all 65,536 reserved slots. The dense run
started with 19,527 GPU / 30,473 cold packets and ended with 14,034 GPU / 27,414
cold slots. All measured runs had zero whole-pool gameplay readbacks, no CPU
fallback and zero measured audio underruns.

An isolated unbounded-coordinate cold-store test grew retained state from
1,000 to 10,000 to 100,000 one-packet chunks. The same 2,000 scheduled updates
and local-region queries cost 12.45, 14.66 and 18.12 microseconds per service.
Scheduler storage stayed exactly one entry per chunk. This demonstrates sparse
scheduling rather than a per-frame world scan; it is **not** a large-world
whole-game benchmark. Heap work is logarithmic, and relevant local density and
selected cell queries still affect cost.

Intermediate rows measure successive implementations, including their changing
coarse trajectories and simulated horizons; they are not exact-outcome or
single-variable performance claims. Compact GPU dispatch alone reduced the
normal streaming tick only from 7.03 to 6.93 ms before native cold work was added.

## Validation and reproduction

Completed on the final source: **70,552 native assertions**, **3,471 script
assertions**, **16,353 affected GPU/UI checks** (including 5,315 streaming checks)
and **15 launcher tests**, all passing. Validation treats Godot script/runtime
errors as failures even when its process exits successfully.

Automated checks cover overflow/retry/acknowledgement, wrapped boundaries,
immutable metadata and absolute expiry, stale handles, more than 1,024 historical
pheromone identities including hash collisions, complete sensory summaries,
camera reversal, sparse scheduling, native/reference transport and queries,
paid editing/succession, CPU recovery and conservation. Travel transfers more
than 2,000 packets with organic-budget error below 0.00002 units. Cycling zoom
retains identical ATP, biomass, position, chemistry counts and random state.

Run the ordinary native and script suites with `./tools/test.sh` and
`PRIMORDIA_BACKEND=script ./tools/test.sh`. The real-device GPU regression is
`tests/resident_streaming_gpu.gd`; the headless storage diagnostic is
`tests/streaming_scaling.gd`. Existing gameplay, perception, exchange, exposure,
queued-exchange, environment and UI GPU suites remain required.

For a playtest or a shareable frame trace, using Steam Godot discovery:

```sh
./tools/playtest.sh resident
./tools/profile_playtest.sh resident
./tools/profile_playtest.sh cpu-matching
```

The frame profiler accepts `--resident-streaming=off` for the whole-GPU reference.
The comparison changes simulation resolution and therefore trajectories; do not
compare particle totals as though they were identical workloads. Profiler logs
and raw captures remain ignored generated evidence; authored reports are retained.

## Remaining limits

The running habitat still wraps at 4096×2560, with a fixed 64×40 fluid/acidity
field. The sparse store supports unbounded chunk keys, but larger coordinate
spaces need tiled fields, cell scheduling and corresponding rendering work.
The GPU neighbor grid also still uses the current toroidal coordinates; it must
become a window-local grid before increasing world dimensions.
The current GPU exchange still supports at most 64 cells per batch. Cold
transport/chemistry approximate endpoint encounters; cross-tier contacts outside
the display are not identical to continuous all-GPU dynamics. No resources are
invented to compensate. Cold preparation, chunk deadline staggering and cell
query scheduling remain performance targets. The CPU default is unchanged.
