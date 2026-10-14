# Revision 45 — perception domains and living camera observation

The mobile camera uses two fixed world anchors for combined pan, rotation and zoom. Follow is a fixed-label toggle: highlighted/pressed when active and dim when inactive. It centers a living camera target. An ended owned lineage can observe an existing living cell; camera focus never changes account selection, adopts a body, creates life or grants editing/resources. When the observer target dies, a surviving existing body becomes the target. With no living body, Follow is unavailable and the view reports that state.

## Two perception views

Exteroception shows external particles and hides all intracellular chemical packet drawings. Interoception shows the focused body's internal particles and hides external chemical particles and reaction sparks. The entire scene outside the real membrane is desaturated and dimmed; UI controls retain normal contrast. A 256×256 render-only mask reuses the membrane mesh and follows its interpolated position/heading. It does not approximate the membrane with a circle, change physical geometry or download GPU chemical state. No visible focus means the whole scene is outside and dimmed.

Internal chemical glyphs render at one fifth of their former diameter (one twenty-fifth of the filled area), using the same size rule for owned and observed cells. Their orientation marks, signal glyphs and cosmetic AP parcels use the same visual reduction. Physical packet amounts, contact radii and transport are unchanged; organelles and vacuole boundaries retain their size.

The touch button names the destination view: Interoception while outside, Exteroception while inside. Desktop I switches views. Entering Interoception returns to cell follow if the camera was free. Two-finger manipulation and the local view Pause remain available in either mode. A paused browser keeps its latest full snapshot while the authority continues.

## Independent simulation interests

External camera footprints are the union of Exteroception peers. Existing resident GPU ownership, sparse cold storage, finite intake/exposure and coarse transport/chemistry handle regions not requested by those cameras, including when every player looks inside. Interoception views never retain an exterior fine footprint. Intracellular fine interest is a deduplicated union of focused body IDs. A second viewer cannot double-step a cell, and an external viewer cannot downgrade internal detail requested by someone else.

Internal chemistry has an independent retained elapsed clock. Viewed interiors use each authoritative simulation tick; hidden interiors accumulate time and execute staggered existing offscreen-period updates using the same local transport/reaction code and maximum 0.125-second substeps. Body physiology no longer calls a second chemistry advance when the split owns that clock. Promotion consumes all deferred time once, and pending time/deadlines survive saves. Legacy checkpoints transfer their unresolved coupled body interval into the new chemical clock once. Host downtime still performs no catch-up.

Movement, uptake, ATP spending, synthesis, excretion and secretion keep physical particle inventories. Neither switching modes nor focus supplies tissue, ATP, AP, particles or wall-time credit. Cold/fine trajectories and short-term availability can differ because their cadence differs; this is the existing offscreen approximation, not exact trajectory equivalence or molecular chemistry. Independently constructed Sim reference fixtures keep the legacy coupled path unless they explicitly enable perception domains.

Interoception snapshots publish current cell graphs without waiting for an external GPU pose gather and carry no exterior pose bytes. Exteroception keeps the existing prepared-view gather/coverage rules. Mode values are validated. This revision retains the resident hardware-GPU deployment requirement and data-only checkpoint contracts.

## Checks and limits

Correctness checks cover dead-selection observation without editing privilege, fixed Follow styling, elapsed-time migration/promotion and checkpoint recovery, internal material conservation, mixed/all-inside camera unions and advancing zero-exterior snapshots. Native/reference, real GPU network fixtures and phone-sized browser tests remain required. Gameplay objectives, economy tuning, survival and balance acceptance remain held. Packet density remains the owner's reduced setting.

Rendered masks and touch checks on desktop Chrome with a hardware-GPU authority do not establish physical-phone performance, battery/thermal behavior or sustained 60 FPS. Perception keeps current bounded habitat, body count, frame and ownership capacities.

The follow-up dense-snapshot transport repair distinguishes accepted sign-in from preparation, removes key/reconnect controls during loading, negotiates lossless internal packet columns and one-outstanding-snapshot flow control, and checks the decoded 8 MiB frame bound before compression. It preserves full checkpoints and particle fields; see [deployment](deployment.md#accepted-sign-in-and-dense-snapshot-delivery).
