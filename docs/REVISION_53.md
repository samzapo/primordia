# Revision 53 — global particle census and probabilistic exterior outflow

The mobile view previously counted only its received camera snapshot and reused
that length as the habitat total. The server now sends a compact, independent
census with global internal and external totals. Exterior parcels include nearby
GPU state, live cold chunks and paid emission/trace escrow. Cold chunks maintain live counts at ownership boundaries;
dead retained storage slots are excluded. The browser labels its camera count
separately. Older server compatibility shows a waiting state rather than inventing
a global total. Internal carriers are included in the total and also shown
separately. Only the exterior count is regulated.

The owner's requested performance guard explicitly permits destroying external
particles. Every world second, when the live global count N exceeds limit L, each
exterior parcel is removed with probability 1-L/N. All species, owners and
locations use the same probability. Expected per-species counts/material shares
are retained; actual ratios fluctuate and the limit is soft. Emissions and new
introductions can temporarily exceed it. Default shared-server limit is 5000;
PRIMORDIA_PARTICLE_LIMIT configures it, and0 disables it. Local CPU comparisons
default off. This is an artificial computational outflow, not a new biochemical
reaction. It removes real material and may affect ecology.

GPU thinning stays on the resident device, returning only32 bytes of statistics.
Cold storage and pending/sub-float emissions receive the same probability.
Removed organic material is added to the existing exterior loss ledger and a
separate thinning subset counter; removed food potential is recorded separately.
No cell, internal content, player resource, account, key or feedback is culled.
The independent saved RNG/counter/deadline survive restart. Never reroll game RNG.

Sole blocking GPU receipts now trim the dispatch watermark to the last live slot,
including one for empty pools, while keeping all allocation and generation
counters intact. Refills reuse slots with incremented
generations; saved particles are not reset to make a benchmark pass.

A separate defect allowed acid/buffer field quantization to leave a small
negative charge in exhausted waste, later rejected on GPU re-admission. Clamp
spent charge at its producer on reference/native/GPU paths. Startup repairs only
known waste residues between -1e-6 and0; substantive negative values and negative
nutrient fuel remain invalid. Chemical material and every saved cell stay exact.

Capacity comparisons on the copied real pond, with two full exterior cameras,
did not establish a performance-safe maximum: initial7132/5000/4000/3000/1500/0
particles all missed the30Hz target. Even zero initial particles regrew1098 and
ran at0.84 simulation/wall speed. Other cases ran at0.64–0.71. These are bounded
tick observations alongside idle production, not rendered/mobile FPS or an exact
isolated hardware capacity. The5000 limit is a growth guard, not a claim of
real-time acceptance. Remaining GPU handoff and cell biology/motion costs need
separate work. The one-off probe now requires explicit dispatch or the exact
particle-capacity-probe commit marker; no monitoring schedule was created.
