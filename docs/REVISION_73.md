# Revision73 — reduce current-curve drawing stalls

Owner reports6FPS on mobile. Investigate client work separately from server simulation, transport and actual phone rendering. The read-only server sample had zero connected players: it advanced about26simulation steps per second, with no backend/checkpoint errors. This is idle evidence and does not establish loaded phone performance.

The current-curve admission index retained stale replaced segments in its buckets, and repeatedly scanned a curve's own old segments. Group buckets by curve identity, remove replaced entries, skip the owned group before visiting segments, and use per-query integer stamps instead of a fresh deduplication dictionary. Size bins to the required clearance and cache conservative segment bounds before exact geometry tests. Keep the original crossing/distance predicates, full paths, sample counts, fade/advection and physics.

A deterministic935-case differential fixture compares admission with an independent all-pairs geometry oracle across clearances, anonymous paths, repeated owner replacement, self-crossings and invalid points. Existing rendered flow tests remain required.

Bounded native CPU observations use a1080x2340window,1440x3120logical viewport,0.75final scale and0.6stroke zoom. Crest generation averaged18.44ms before and10.13ms after; worst observed46.09ms and24.51ms. Streamlines averaged12.94ms before and10.34ms after. The admitted counts remain23pale/32gold crests and41pale/16gold streamlines. These are workstation GDScript measurements, not WebGL/physical-phone FPS or proof of the full cause.

An earlier64x64diagnostic window exaggerated clearance/index cost and is invalid for phone conclusions. Always retain window/logical viewport/final transform and stroke zoom with such profiles. A self-intersection grid experiment was slower and was discarded.

No biomass/AP limit, chemistry/particle reduction, pond cull, flow-length reduction or new schedule is introduced. Stage on experimental with the current fresh-main-copy policy, preserving main, keys and private feedback. Physical-phone FPS and pause/view response remain awaiting owner evidence.

## Bounded current artwork on touch devices

Index optimization alone does not guarantee a phone frame budget. Touch devices begin with at most24ordinary and12gold full-length curves. Two costly rebuilds above8ms reduce this to16/8 and then8/4, with a250ms adjustment interval. Recovery requires eight seconds of rebuilds below3ms before restoring one level. Desktop retains64/32. This budget changes only current-art samples; particles, cells, fields, chemistry and all resource balances are untouched.

Excess visible curves retire through the existing fade rather than being deleted. The same32-segment full-length geometry, actual local flow/induced input, noncrossing admission and camera movement remain. The combined949 assertions include935geometry comparisons plus budget/downshift/recovery/fade retention checks. Existing browser diagnostics gain FPS, frame/view-sync time and current-art budget, without new screen labels or server/player-data uploads. Physical-phone FPS still awaits owner verification.

## Stable promotion

Owner authorizes merging the verified Revision66–73 batch to main. One stable-only gameplay summary replaces the iterative playtest announcements for main players; historical IDs, audiences and acknowledgement progress remain intact. Existing older applicable missed updates still appear in order. Stable deployment retains the actual saved main world, living cells/anatomy, accounts, five keys and private feedback, with the experimental process preserved. Functional/hardware/restart/public-delivery gates remain required; phone FPS remains unverified.

Stable delivery correction: continuous atmospheric emissions can remain in admission escrow after each physics tick and prevent any camera from becoming fully ready. Before an eligible external publication, commit one ordinary emission/census receipt on the resident GPU without advancing chemistry, motion, feeding or cell resources. Keep cold-region and refused-admission readiness checks strict, and retain acknowledgement backpressure. The isolated slow-observer fixture now injects post-tick gases continuously and checks exactly-once census transfer and unchanged biology.
