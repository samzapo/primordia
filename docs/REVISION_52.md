# Revision 52 — stable crowded particles and resident admission backpressure

The external chemical contact pass previously summed one full overlap impulse
for every neighbour. A 128-parcel coincident cloud could launch at 2031 world
units/second in one pass while the cells and water stayed ordinary.

Each pair now divides its existing separation impulse by the greater of the two
complete overlap degrees. Each endpoint receives the same divisor and opposite
impulse. A parcel's total contact impulse is bounded by its largest isolated
overlap impulse because every pair divisor is at least its own degree. Isolated
pairs keep their old behavior. This is a soft crowding approximation; it makes
crowded relaxation gentler, and is not a calibrated fluid or molecular solver.

The GPU counts complete neighbourhoods independently of its 64-entry diagnostic
pair list. Native ordered/matching paths and the script reference use the same
rule. Native degree counting uses a complete local immutable grid because the
ordered chemistry cache deliberately contains only higher-ID candidates.
No neighbours or chemical binding choices are dropped. Transport, diffusion,
plant drag, ambient current, stream history, material and fuel rules stay intact.
No saved velocity is clipped or reset during upgrade.

A refused device emission remains paid escrow and retries after uptake, decay
or eviction frees a slot. Full capacity still delivers the tick's body/query
receipt; it no longer switches the whole habitat to CPU. Real device errors
retain the existing complete ownership recovery. Metrics expose allocation,
work slots, pending emissions and cumulative refusals so a growing backlog stays
visible. There is no CPU pose mirror for nearby particles and no particle cull.

The read-only checkpoint inspector reports bounded launch-velocity percentiles,
per-kind maxima, finite-state counts and eight fastest samples without account
credentials or restoring a simulation. A finite later sample cannot prove that
a previous transient launch did not occur.

Regression coverage includes repeated 5,120-particle admissions/evictions in the
100,000-slot target allocation, full-capacity paid-emission retry/conservation,
dense 2/16/128-parcel clouds, asymmetric contact degrees, an unchanged isolated
fast launch, reaction matching, transfers, native/reference parity and saved
world retention. These are correctness checks; rendered speed benchmarks remain
on hold.
