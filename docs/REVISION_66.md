# Revision 66 — family fusion, usable controls and sustained energy

Owner-approved R23–R41, October 18, 2026. Deploy to experimental first, without resetting either pond. Main awaits playtesting.

## Physiology and chemistry

Leaves still consume physically local CO2 and solar work. Direct ATP allocation rises from 2 to 4 per fixed unit, replacing the former 2 units of heat. Existing fuel and total work remain explicit. Acceptance covers a basic one-leaf cell in dim water, and two leaves plus two mitochondria supporting continuous toxin/pore production, movement and protection in bright water. These builds remain vulnerable to damage and harmful acid.

New founders and paid daughters start with one ordinary, reabsorbable leaf. The division quote includes its 12 units of material. Existing cells are not backfilled.

Air exchange visits 20 seeded groups over five simulation seconds. CO2 relaxes toward 8 units per 64×64 area over 10 seconds. The owner's final correction adds a much smaller oxygen source: target 0.5, relaxation 60 seconds. Both rates use the multiplier 1 + 2|curl|/(|curl| + 0.05) from centered differences of the existing water velocity. This is an authored 2D mixing proxy. Photosynthesis remains the main renewable oxygen producer.

Both gases enter real exterior ownership, with jittered source positions, bounded carrier admission, saved phase clocks and separate source/removal counters. No cell receives a stock grant or particle-pose mirror. CO2 and oxygen glyph ink is one-half size; physical contact and amounts are unchanged.

Mild acid's optimum moves to 0.25. At that optimum, real nutrient joins double their allocation-bonus increment, still capped at 50% and funded by existing fuel. Spent food cannot regain fuel by joining. Enzyme/waste binding shares the optimum. Acid maintenance begins above 0.4; buffers respond above 0.4 or to actual cellular stress. These values are normalized game quantities, not pH.

## Family and behavior

Automatic division defaults off per cell. Paid preparation and the readiness ring remain, with controls for one cell or its family. A committed birth grants one AP to the parent and one to the daughter.

Family investment changes preserve explicit individual exceptions. Use family deliberately clears an override. Daughters of family followers remain followers; deliberate individual strategies are inherited as individual settings.

Fusion requires living, same-lineage contact. Automatic donors must be unattended and at least 60 seconds old; recipients wait 120 seconds between fusions. Received family chemical traces guide approach. Four nearby family signatures increase the attempt rate from 0.02/s to 0.2/s. Live body lookup validates ownership and physical contact only, never navigation.

All donor organs reabsorb first, using ordinary sequential AP refunds. All existing AP and internal parcels transfer. The receiver keeps 90% of remaining solids and ATP; ordinary waste and heat receive the rest. Food/waste vacuoles retain their grouping and digestion age. Fusion awards no birth AP, death event, toxin-sac burst or new generation. The receiver keeps its identity and anatomy. Selected donors and unrelated lineages cannot be consumed.

Weapon permission is independent of the navigation winner. Hunting/flight receptors still receive immutable local signals; larger defended, family and expired targets remain ineligible. A missing receptor and a lack of eligible signals have distinct messages. Glands offer ordinary hunting-receptor construction when one is missing.

## Water and presentation

The historical 0.35 global tide multiplier was already removed in main. Following the owner's report of stagnant water, hourly ambient forcing is now twice its former 0.65–1.3 range: 1.3–2.6. Flow version 4 refreshes saved targets within the hour and invalidates the derived event base. Existing velocity approaches the new target through ordinary coupling. Local plant damping, migrating eddies, source-local gold and full stream histories remain.

Family scrolling has fixed repeatable arrow buttons. Sun/Shade selection resolves stable IDs and waits for authoritative results. Instinct shows the current state and an optional direction arrow. Appendages share their parent cell's drawing order. GPU resident labels ownership separately from visibility, cold storage and queued handoffs.

## Persistence and acceptance

Preserve cells, anatomy, accounts, keys, feedback, old signal expiries and saved settings. Validate native/reference chemistry, resident hardware GPU ownership, conservation, authenticated receipts, pointer input, portrait layouts and checkpoint recovery. Broad rendering-speed benchmarks remain held.

Gameplay and Mechanics use platform-specific, audience-friendly descriptions and scientific references. This revision's update notice is experimental-only.

October 18 visibility correction: the owner found the quarter-size CO2 and oxygen glyphs too small. Both now render at twice that size in the shared full/detail textures, while inspection remains readable. Following the supplied earth.nullschool.net wave-animation reference, streamlines use soft, shallow wavelet crests on the existing advected strips. Each strip carries staggered bright marks and a faint continuous history. Width increases from 0.90 to 3.60 pixels, with ordinary/source peak opacity rising from 0.16/0.34 to 0.58/0.72. These are presentation tracers following the real flow, not simulated surface waves. Counts, full 8.4-second trail history, gold-source masks and all simulation parameters are unchanged.

October 18 crest-orientation correction: the owner clarified that the visible crest line must be perpendicular to travel. A broad highlight along a narrow streamline was still appearing as an along-flow dash, especially at close zoom or higher water speeds. Crests now span 10 screen pixels across the local velocity normal, with a roughly 2-pixel thickness measured using fragment derivatives along the path. A shallow bow and soft trailing glow remain. Crest thickness no longer stretches with speed or zoom. Full trail history, source-local gold, strip budget and all physics remain unchanged. Validate actual rendered crest dimensions and motion in horizontal, vertical and diagonal flows at wide and close zoom; no speed benchmark.

October 18 current-display correction supersedes both earlier crest attempts. One wave sample is one continuous 10–100 µm crest segment. Its center advects through the actual displayed current; its shape follows the local velocity normal. The original continuous 8.4-second Streamlines remain available. Pause offers Wave crests and Streamlines on desktop and mobile, remembering the choice.

Both styles represent this flow field and must not cross. The renderer admits complete curves only when their segments clear retained curves, including self-intersections. It omits conflicting samples rather than truncating trails. A conservative clearance of stroke width plus twice the maximum cached speed over the 50 ms geometry interval protects separation between geometry refreshes. Centers still advect each display frame; GPU batches render cached, checked curves. Shape refreshes when the field, mode or view needs it. This is bounded presentation data, not ecological particles or authoritative simulation state.

Gold uses denser samples on a fixed world lattice near active sources and a local tint mask. Source position controls only sampling density and color; source migration never supplies a line’s direction or motion. Both styles and their center advection use the same blended signed velocity cache. Keep full trails, resident chemistry, shared RNG, both ponds, cells, keys and feedback unchanged. Validate connected crest ink, micrometre scale, current-speed motion, independent segment intersections between refreshes, actual mobile/desktop Pause input and preference reload. Broad rendering-speed benchmarks remain held.

Stroke width and separation use the final viewport stretch as well as camera zoom. Logical-pixel widths alone became subpixel marks in a narrow viewport and made mathematically continuous lines appear dotted. Curves remain physically sized; only ink thickness is calibrated in actual output pixels.


October 18 induced-overlay correction supersedes gold tinting of total-flow curves. Pale samples still follow the blended actual water velocity, including denser sampling throughout an induced source's full footprint. A separate gold layer uses the opposite display style: gold Streamlines over Wave crests, or gold crests over Streamlines. It integrates only the existing sparse induced-forcing raster from induced_currents.gd, never source migration, ambient tide or cell motion. The identical sparse raster helper also supplies physical targets without changing their values; presentation caches and blends two10Hz input rasters instead of evaluating every event at every curve integration point. These are two visualizations of current contributions, not interacting physical waves.

The visible input footprint expands from the old22%core radius to the full source radius, with soft spatial edges. Physical source size, strength, lifetime, migration, plant damping and all ecological state are unchanged. Source masks and individual persistent curves fade in over0.4s and out over0.8s in simulation time. Moving fixed-lattice neighborhoods no longer replace visible lines abruptly. Existing safe paths retain their identities when a proposed replacement conflicts, retrying later instead of repeatedly retiring/reseeding. They fade when no longer wanted; new curves start transparent. Input line opacity does not duplicate the source's spatial/envelope mask. When a shape refresh is blocked, its center stays at the last safe pose until a replacement fits, rather than drifting into another curve. Both layers share whole-curve collision admission and preserve full streamline histories. Curve shape changes ease over0.25s, while active centers advect using their respective fields. Retiring curves keep their last safe geometry during the fade.

Validate both opposite-style combinations on hardware Vulkan and OpenGL, pale-vs-gold pixels, full-footprint locality, input-only direction when ambient flow differs, identity/opacity continuity on source disappearance, nonintersecting complete curves, actual Pause pointer input and remembered style. Keep the existing functional suite and deployment/restart checks; no rendering-speed campaign or physical-phone FPS claim.
