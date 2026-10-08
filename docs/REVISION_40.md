# Revision 40 — resident playtest performance repair

The owner reported 3 FPS, a 33.94 ms tick, and 2,056 audio underruns on the Threadripper 2990WX / RTX 3090, launched through tools/playtest.sh resident. Revision 39's Ryzen 9950X / RTX 5080 measurements did not establish acceptable performance on that computer.

## Scope and architecture target

The owner reports that the CPU game's appearance and coarse offscreen behavior
already work well. Preserve that baseline. The desired GPU contribution is a
dense nearby particle soup, with no per-frame work proportional to total world
size. The target is a bounded GPU window with a halo, CPU-managed sparse chunks,
and conservative transfers to the existing coarse ecology. See the October 7
large-world contract in [DESIGN.md](DESIGN.md).

**This revision is an intermediate performance checkpoint.** It tiers cell work,
but the GPU particle pool and 64 x 40 fluid field still cover the fixed torus.
Chunk-local coordinates, streamed particle ownership and large-world storage are
not implemented. Do not call the whole-world backend the final scaling solution
or consider these measurements validation of the proposed hybrid.

## Cell simulation tiers

Nearby cells retain detailed membranes, three motion substeps and swept contacts.
Hidden cells use staggered approximately 0.1-second updates of the existing CPU
offscreen physiology, cheaper motion, paid secretion and family-safe hunting.
The membrane solver does not run for hidden bodies. Elapsed time accumulates;
promotion drains the unresolved interval once before detailed updates resume.
There are no altered storage, metabolism, repair or combat stats.

Hidden uptake and exposure operate on real GPU packets. Feeding uses the existing
offscreen swept-area formula and 1-exp(-rate*dt) encounter probability, shared
storage caps and ordered finite competition. Visible packets are excluded from
widened hidden feeding. Hunting relies on received pheromones and releases a
corpse through ordinary lysis, with no automatic resource credit. Coarse and
detailed consumers share the existing two GPU exchanges per tick. Exposure
overflow drains with the same hazard seed rather than rerolling probability.

The detailed footprint covers the widest playable view at 80% zoom, including
viewport aspect ratio and the existing outer activity halo. Zoom changes the
view, not feeding mode. Free camera travel can change which area receives detail;
that is not claimed to produce bit-identical trajectories. Future streaming may
ease camera/zoom transitions while chunks prepare, as authorized by the owner.

F3 distinguishes detailed and coarse **cell** counts from **GPU habitat particles**.
The latter is still a global pool count, not a count of glyphs on screen.
CPU displays its detailed region and habitat total separately. The trace includes
cell detail scope and particle scope; --full-habitat=on is a detailed-cell ablation
for resident and a full-footprint comparison for CPU.

## Changes

- Reuse the fixed resident fluid activity mask instead of recomputing all 2,560 nodes each tick.
- Perform reaction-buffer clearing on the render thread with on-device clears, replacing a roughly 1 MiB CPU zero allocation/upload per tick. Environment upload and clearing retain command order.
- Skip unused feeding-request construction in exposure exchanges. Hover requests return only their sparse result: 80 bytes for picking or 64 bytes for generation-checked tracking, with a separate immutable pheromone report when needed. They no longer request a field/inventory/event reduction.
- Batch the six ordered body–fluid impulses, membrane traction samples, and radial outline construction in native code. Keep the reference implementations and profiler ablations. These native calculations retain geometry resolution, forces and ordered arithmetic; cell cadence changes are separately controlled by the detail-tier ablation.
- Refill the existing music sample queue between simulation ticks as well as between rendered frames. Observation and ecology stay on their existing paths; audio never advances biology.
- Bound catch-up to two ticks per displayed frame, dropping to one when the smoothed tick exceeds 16 ms; recover to two below 12 ms. Every executed simulation tick remains 1/60 second.

The catch-up limit is a **responsiveness safeguard**, not additional simulation throughput. If hardware cannot complete sixty ticks per real second, the whole game's clock runs slower. F3 explicitly reports Simulation/wall alongside ticks/frame, total simulation time per frame, and tick time. No missing time is converted into free feeding, aging, or invented resources. Both the prior eight-step limit and the new safeguard can fall behind real time under sustained overload. Benchmarks must report that ratio, not call smoother presentation real-time simulation.

F3 also distinguishes native versus script cell support and separates CPU receipt preparation from the complete GPU handoff (command submission, blocking completion, and decoding). That handoff is wall time, not isolated GPU shader time.

## Reproduce on the playtest machine

~~~sh
./tools/playtest.sh resident
./tools/profile_playtest.sh resident
./tools/profile_playtest.sh cpu-matching
~~~

The profile launcher uses Steam discovery and the normal native rebuild, opens the real game window with normal audio, then captures thirty seconds at 80% zoom. It writes a JSON report under ignored build/profiles/ and exits. It records the source commit, CPU/GPU, native availability, viewport, VSync request, catch-up policy, phase timings and simulation/wall clocks. An ordinary capture does not multiply particle density.

Examples:

~~~sh
./tools/profile_playtest.sh resident --seconds=12 --max-steps=8
./tools/profile_playtest.sh resident --full-habitat=on
./tools/profile_playtest.sh cpu-matching --full-habitat=on
./tools/profile_playtest.sh resident --hotpaths=body_fluid,traction,outline
~~~

Profiler-only --tick-delay-ms injects explicitly labeled latency to reproduce overload; --tick-audio=off isolates catch-up audio service. Neither is a gameplay option. --max-steps=auto is the gameplay policy; 1..8 retain fixed diagnostic limits. --vsync=on/off permits comparison with the real display path.

## Evidence

Godot 4.7.2, Ryzen 9950X / RTX 5080, Vulkan Mobile, 1440 x 900,
80% zoom, normal opening fixture, music enabled, twelve measured seconds after
warmup. An owned hardware-rendered headless Weston session used Dummy audio;
it is not the owner's physical display/audio path.

| Version | Mean tick | Mean detailed cells | Frame rate (60 cap) | Simulated / wall time |
| --- | ---: | ---: | ---: | ---: |
| Original Revision 39 | 9.50 ms | 16 | 60.03 FPS | 1.00 |
| Native/transfer repairs, all cells detailed | 7.71 ms | 16 | 60.03 FPS | 1.00 |
| Same repairs, nearby detail + coarse cells | 5.46 ms | 6.35 | 60.03 FPS | 1.00 |

The cell tiers lower tick cost by approximately 29% against the repaired
all-detailed ablation; combined repairs lower it about 42% against Revision 39.
These are short single-run measurements, not a sustained-performance guarantee.
The coarse run ends with 3,858 packets versus 4,010 in the all-detailed run:
approximate offscreen ecology changes the trajectory, so this is a workload
comparison, not identical-outcome arithmetic optimization. All runs report zero
audio skips. The owner's Threadripper/3090 improvement remains unmeasured.

An explicitly injected 28 ms delay per tick reproduced the catch-up failure:
eight steps per frame gave about 3.35 FPS. Refilling audio between ticks removed
794 reported skips without improving throughput. With the final bounded policy,
the same injected delay gives 26.20 FPS, approximately one tick per frame and zero
skips, but simulation runs at only 0.43x wall time. The injected delay is excluded
from ordinary tick-phase timing and separately labeled in the trace. This proves
a responsiveness/audio safeguard, not faster physics.

Validation covers native/script CPU suites, finite GPU cell/particle material,
elapsed-time retention/promotion, zoom invariance, time-scaled uptake/exposure,
periodic foreground exclusion, competing mouths, family toxins, overflow without
rerolls, exposure/query/queue/environment/UI regressions and launcher fixtures.
The native suite passes 69,940 assertions and the script suite 3,297. Affected GPU/UI suites pass 11,038 checks; fifteen launcher fixtures pass. Organic inventory error
in the four-second coarse gameplay fixture is under 0.00002; normal gameplay has
zero full particle readbacks. Explicit test snapshots/fallbacks are counted.

Native drag, traction and outline calculations are compared with the original
ordered scalar operations across seams, partial/global activity, rotating/large
cells, tension networks and dents. Float-vector differences are tolerance-bound;
long chaotic trajectories need not be bit-identical.

The optional experimental separate-render-thread check completes its GPU assertions
but Godot 4.7.2 reports a render-device finalization error at shutdown. An empty
SceneTree with no game code reproduces it on this host. These experimental-mode
runs are not counted as clean passes; the default Safe rendering mode passes.

No mobile, 50k sustained gameplay, arbitrarily large world, or final GPU/CPU
streaming performance is established by this checkpoint.
