# Revision 49 — direct digestion, readable interiors and real-time performance

The owner restores the first-cell lifecycle for this revision. ATP, biomass and
reproductive ATP reserves are numbers. Physical nutrient material enters at the
oral groove, circulates in food vacuoles, digests directly into numeric resources,
then remains as waste until a waste vacuole reaches the cytoproct and expels it.

## Model and ownership

There is no initial intracellular molecular cloud. Each cell owns at most twelve
food and twelve waste parcels. Parcels carry finite material and fuel; bounded
coalescence changes resolution without discarding either. Actual digestion has
one shared per-cell capacity, rather than capacity multiplied by parcel count.
The retained tissue fraction is 0.7 of fueled material; numeric ATP receives only
the remaining fuel after the tissue's represented potential is retained. Spent
nutrients become waste without free ATP or tissue. These are game abstractions,
not molecular stoichiometry or biological ATP-yield claims.

The current food/waste model replaces active glycolysis, respiration,
fermentation, biosynthesis/salvage graphs, cofactors, ATP/ADP particles,
autocatalysis, photosynthetic metabolism and osmosis. Old pathway commands are
rejected; the local panel is a read-only lifecycle explanation. Historical
catalog entries remain for external packets and archived data compatibility.

Visible intracellular parcels are authoritative on the main RenderingDevice.
GPU buffers are bounded to 32 slots with at most 24 live parcels; numeric ATP and
biomass use compact receipts. No full particle export is needed by fine digestion.
Hidden interiors hand back to bounded coarse CPU execution, preserving elapsed
time. External resident/cold transport remains the existing implementation.
The server keeps detailed recent ATP ledgers and cosmetic transfer effects for
connected players’ selected/focused bodies. Other bodies retain all numeric
resource updates and full physical simulation without generating unseen UI
records. This policy changes presentation accounting only.

Numeric ATP spending, turnover, reserve investment and division no longer scan
cytoplasmic packets. Oral/ciliary suction and the observed fluid-grid union have
serial native fast paths matching the existing node order, reference field
weights and paired body/water impulses. CPU fallback remains available; profiler
hotpaths suction and field_views disable these independently for comparisons. Automatic paid reproduction and persistent population
recovery continue under their existing shared rules.

## Presentation and controls

Food and waste use the existing nutrient/waste vector artwork, with camera-scaled
size and an internal magnifier with names and lifecycle roles. A phone tap opens
the same inspection. The actual deformed membrane clips interior glyphs; the
mask excludes the artwork's 1.95-radius halo. An opaque membrane-shaped backing
and explicit foreground order prevent other organisms showing through the
focused cell. The entire exterior is grey/dim in interoception.

Snapshots contain numeric resources and bounded food/waste state. Hidden
interiors omit parcel/vacuole poses. Presentation uses server timestamp spacing
and retargets from currently rendered positions/angles, preserving continuity
when a packet arrives early or late. It stops at the latest authoritative state
when updates stop. This is presentation only and does not advance chemistry.
Music, mobile input, Follow, two-finger camera manipulation and local Pause are
preserved. Desktop controls remain I for perception and M for settings.

## Saved-world migration

Before restoring a pre-v49 world, the authority writes an independent two-slot,
checksummed archive of its complete original checkpoint. Loading converts paid
ATP and reserved ATP to numeric resources once; retained organic intermediates
become finite food/waste with their existing fuel; retained compartment tissue
returns to biomass. Account/lineage references, access hashes, edit receipts and
world identity survive. The next checkpoint records food_vacuole_version=1 and
a per-cell conversion audit. Historical density conversions cannot re-run the
retired chemistry reducers on this model. A failed archive aborts startup.

Rollback across this model boundary requires the original archived checkpoint
as well as the old code. Do not run old chemistry against the new active save.
Never replace access-keys.json or the existing account graph when rolling back.

## Performance and acceptance

Comparable recorded first-cell baseline: Godot 4.7.2, RTX 5080/Ryzen 9950X,
1440×900, widest 80% view, resident backend, music on, 60 FPS cap, 12 measured
seconds after warmup: 60.00 FPS, 18.70 ms p95, 5.58 ms simulation/frame,
0.999 simulation/wall ratio (Revision 42).

Current equivalent X11 hardware runs:

| View | FPS | p95 frame ms | Simulation/frame ms | Simulation/wall |
| --- | ---: | ---: | ---: | ---: |
| Exteroception | 59.96 | 18.34 | 5.56 | 0.9994 |
| Interoception | 59.97 | 19.54 | 4.22 | 0.9996 |

These runs contain 16–17 cells. The separate mixed-client GPU authority fixture,
with finite loaded food vacuoles, measured 1.001× simulation and 7.88 ms p95 ticks
with 17 living cells. Workstation evidence does not establish phone frame rate.

Desktop tools/test_frame_budget.sh checks actual rendered frame pacing (59 FPS
minimum, 20.5 ms p95 maximum with modest display-jitter allowance) using a real
hardware desktop display. CD checks hardware GPU ownership, simulation/wall
0.98–1.02, mixed wide cameras, bounded interior population and saved restart.
The authority fixture matches the deployed 64×64 compute-submission surface; its
client camera rectangles still cover the full widest view. The target Xvfb
full-window diagnostic spent about 67 ms at its render boundary even with
biology frozen, so virtual-display native drawing is not the mobile frame gate.
Live service health also rejects a simulation below 0.98× or a p95 tick over
16.67 ms. Mere tick advancement no longer qualifies a slow server as healthy.

Gameplay/objective/balance tests stay held. Conservation, paid reproduction,
migration idempotence, checkpoint integrity, external native/reference parity,
GPU ownership, membrane-mask pixels, internal inspection and networking remain
active correctness/performance checks.
