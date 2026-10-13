# Primordia development

## Project isolation

Explicit owner instruction, October 5, 2026: Primordia is isolated from all other chats and projects, including Deployment and Weft. Do not list, read, search, import, reuse or send context across that boundary in either direction. Keep Primordia decisions and memory inside its project directories; never write them into global memory or unrelated projects. Earlier external-project references in historical chat text do not authorize access.

Never access the Eka-Robotics GitHub organization through any tool, browser, API, CLI or local checkout, including read-only operations and discovery. The only project repository is `https://github.com/samzapo/primordia.git`, privately owned by `samzapo`. Verify destinations before network operations. Public documentation and explicit public dependencies remain allowed except anything owned by Eka-Robotics. Do not enumerate unrelated chats, projects, organizations or repositories.

The project-local `.codex/config.toml` requests disabling generated-memory input/output and account app connectors by default for future sessions that load trusted project configuration. It is not a filesystem sandbox or an organization credential restriction; do not claim complete technical isolation without verifying those separately. App-managed conversation history remains app-managed.

Read `docs/DESIGN.md` before changing gameplay, `docs/REVISION_27.md` for authoritative particle ownership and live density limits, `docs/REVISION_26.md` for numeric particle handoff/cache contracts and density gates, `docs/REVISION_25.md` for opt-in GPU fluid experiments, dense packet costs and failed physics promotion gates, `docs/REVISION_24.md` for ATP tuning, patch-aware foraging, exploration duty and death/relative-flow presentation, `docs/REVISION_23.md` for resource/upkeep previews, size drag, porous plants, longer trails, non-occluding water cues and removal of particle beat pulsing, `docs/REVISION_22.md` for signal tuning and anatomical editing, `docs/REVISION_21.md` for live-frame profiling and CPU batching, `docs/REVISION_20.md` for membrane depth/streamers/wakes, `docs/REVISION_19.md` for coarse offscreen ecology and lysis, `docs/REVISION_18.md` for offscreen transport, `docs/REVISION_17.md` for impulse contacts and the separate hunting receptor, `docs/REVISION_16.md` for current crisis goals, paid succession and local discovery history, `docs/REVISION_15.md` for full-viewport activity, varied fractal plants and brief particle tracking, `docs/REVISION_14.md` for inherited themes/environmental timbre/event music, `docs/REVISION_13.md` for pheromone-only inter-cell perception, `docs/REVISION_12.md` for starting networks and music, `docs/REVISION_11.md` for current cell controls and inspection, `docs/REVISION_10.md` for the art direction, and `docs/REVISION_9.md` for run rules (earlier revision documents are historical). Do not treat proposed details or open questions as settled requirements. Preserve no direct cell control, the current documented anatomy, particle-driven interactions, and the bright vector-style cellular art direction.

The user runs Godot through Steam on a separate Linux machine. Keep Steam discovery as the default in both launchers; support custom libraries and Flatpak. The prototype was validated with Godot 4.7.2. Run `tools/test.sh`; `GODOT_BIN` is an optional explicit override. Tests must fail on script errors even when the Godot process exits zero. For launcher changes, also run `python3 tests/test_launchers.py` (isolated fixtures; never alter a real Steam install). Keep the simulation independent of scene-tree and rendering code.

Do not commit `.godot/`, exported builds, downloaded engine binaries, captures, or logs. Keep authored sources and stable Godot `.uid` identifiers. Generated imports must be recreated automatically.

Record scientific abstractions honestly. Do not describe the current reaction rules as molecular chemistry, circular collision proxies as full soft-body contact, or local reproducibility as cross-platform determinism.

For every new biological or physical mechanic, maintain at least one source for its real-world motivating phenomenon in `references.md`. Prefer primary research or authoritative technical documentation; distinguish evidence, modeled rule and game simplification. Explicit user direction, October 4, 2026.

The widest playable view is now 80% (owner correction, October 5, 2026), including after growth/build fitting. Performance acceptance must include that play limit, dense particle clusters and large cells. Keep historical half, quarter and 0.15 zoom fixtures as explicitly marked diagnostic stress workloads, not playable camera settings. Close-view timings alone are insufficient. Keep independent benchmark switches for native kernels, fluid work, spatial queries, scheduling and native rendering. Report CPU ticks separately from rendered frame intervals and GPU transport-only throughput. Do not enable an experimental backend by default solely because its isolated kernel is faster. Run native and GDScript suites; the native suite includes differential chemistry/transport/field checks. Preserve explicit CPU fallback and Steam discovery. Generated libraries, dependency source caches and binding output stay in ignored build/; keep the pinned build recipe.

Procedural generation and finite fractals are core visual requirements. Preserve seeded fern, radial, fan and spiral plant obstacles, spatially varied water, cached artwork and readable function colors. Validate geometry/contact independently of art, and benchmark obstacle work and rendering separately at wide zoom.

The current player interface has fixed-size organ construction, no Undo/redo/discard-plan controls, and no persistent HUD/build panes. Preserve cell-local factories/resources, direct anatomy editing, nucleus/offspring decisions and the nonphysical particle magnifier. Microtubules remain edit-only; wheel zoom must never resize an organ.

Engaging original progressive techno is a core design requirement. Preserve anatomy/proximity/biomass sonification, the independent audio sample clock, bounded mixing and music-volume control. Particle beat pulsing and its settings control were explicitly removed in Revision 23. Audio must never mutate ecology or gate gameplay on the beat. Keep synthesized banks/previews generated from source rather than checked in. Benchmark audio on/off at the widest playable view. Preserve inherited lineage melodies, light/acidity filtering, and bounded local event accents; mute, restart and editing must not replay old reaction history.

Pheromones are the sole informational input for sensing other cells. Preserve source metadata as emission-time snapshots; never resolve a source ID to live position, mass, hostility or survival during perception. These point tracers follow current plus diffusion, decay quickly even offscreen, and ignore all particle/solid contacts. Preserve the reference, native and opt-in GPU paths and local inspection without live-source lookup.

The whole rectangular view and a short offscreen margin must stay fully active. Slowdown belongs outside the screen, including for partly visible large cells. Do not couple the peripheral blur to simulation dormancy. Particle inspection briefly tracks dictionary identity through motion, reactions and compaction; suppress stale or hidden targets and keep it independent of ecology.


Preserve same-world lineage succession: ordinary death must not refresh AP, drafts, crisis time or ecology. Dormant successors hold prepaid tissue/energy, with one explicitly accounted founder reserve in the starting inventory. Keep local history/knowledge separate from full-world saving, and recalling a known blueprint must consume the ordinary draft choice. Family/history UI stays cell-local; no Undo, organ resizing or persistent HUD returns. Validate born/adopted bodies through both simulation and paused-editor transitions.

Pore-forming secretion has no sensing or steering. The hunting receptor alone selects smaller or undefended prey from immutable local pheromone reports; flight remains explicit and higher priority. Preserve finite particle secretion, local membrane binding and shared physical rules; do not grant hidden hunter bonuses or resolve emitted identities into live target data.


Particle transport never freezes or loses elapsed time outside the view. Keep bounded, staggered coarse advection/diffusion and background flow refresh, timestamped camera catch-up and global pheromone expiry. Revision 23 makes all chemical packets permeable to plant stems; retain solid cell contacts, not particle/stem barriers. Living offscreen cells now receive staggered coarse biology; only explicitly banked successors remain dormant. Preserve shared resource costs/caps, real finite-packet absorption, pheromone-only hunting intent, no statistical hunting kills anywhere, and full lysis without privileged auto-consumption. Nearby hidden chemistry retains orientation and timestamped unary processing; empty far regions still defer particle reactions. Check on/offscreen accounting, elapsed time and performance; gameplay balance testing is held by the owner. Preserve sqrt(dt) diffusion, independent background random draws, material accounting, native/reference/GPU parity and cursor continuity through compaction. Benchmark against frozen and 60 Hz background transport as well as whole-game 80% view; transport throughput is not rendered FPS.


Membrane shading follows the real deformed outline and uses explicit mesh rings; do not reintroduce unsafe polygon triangulation or replace the silhouette with a circle. Streamers read the signed fluid cache in bounded GPU batches, with world-anchored periodic seeds and simulation-time animation. Disturbance glints are presentation-only: preserve existing fluid, chemical particles and random streams. Keep ablation switches in the visual benchmark, rather than restoring flow arrows or new permanent panes to the player interface.

Whole-frame performance evidence must aggregate every catch-up tick. Keep mesh/sync and simulation subphases nested, renderer measurements delayed, and counts explicit even at zero. Do not label a tick timer or transport kernel as rendered FPS. Benchmark real hardware display paths, verify the GPU, and retain software/virtual-display and shared-load limitations. Compare optimizations at equal simulation horizons as well as live wall time. Preserve reference switches, sequential contacts, packet identity/order/timestamps and random draw streams; do not claim cross-platform determinism from local parity.


Keep anatomical steering separate from suction, absorption, secretion and photosynthesis. Use current per-organ weights at reception and delivery, retain the bounded switch margin, explicit flight priority and immutable family signatures. Zero steering must not disable physical feeding. Membrane-mounted art, previews, outlets, weapons and facing use the local outward normal. The tissue comparison is editing-only and uses usable biomass with a common stock/cost area scale. Wider microtubule hover stays edit-only; cell-adjacent lens suppression also invalidates tracked particles. Reaction sparks are bounded presentation samples of successful pair reactions, never a chemistry gate or a new random draw.

Plants are porous to chemistry in both transport tiers and coarse chemical intake/exposure; hidden predation still requires actual chemical contact. Historical particle/stem contact helpers are diagnostic only and default off. AP is a build-only top-right gold-blob cluster, never an internal coin target or transfer effect. Follow zoom centers on the cell; free zoom keeps the cursor anchor.

ATP bookkeeping is bounded and read-only: actual gross/stored/spent rates, shared-area sacs and per-organ paid costs must not alter energy/RNG. Keep steady estimates explicit, upgrade cost/delta previews free, reserve transfers distinct and rates pause-stable. Size-dependent membrane drag is shared across detailed/coarse motion; preserve conservative impulses and no hard advection speed cap. Every cell wake draws below all bodies; broad water shimmer only changes the background brightness, with no scene warp or camera motion. Use parallel native compilation within verified host capacity; PRIMORDIA_BUILD_JOBS remains an explicit override.

Revision 24 adds inherited exploration gain and a response-cycle split against current organ steering gain. Sensing/memory continue during wandering; flight bypasses the cycle. Patch sensing reuses local finite-packet queries, bounded spatial bins and wrapped moments, then selects actual nearby food. Never add live prey lookup or remote patch awareness. Shared ATP parameters apply to detailed/coarse/player/NPC physiology; finite fuel, tissue outputs, repair/combat/AP prices and loss accounting remain. Death bursts and death-site framing are bounded presentation snapshots; actual lysis and immediate paid succession still advance normally. Wakes use local water minus body/obstacle velocity, transformed once into the appropriate frame; do not use absolute world speed.

The Revision 24 starter has a grazing pore and neither cilia nor flagellum. Both propulsion organs are separate paid, fixed-size purchases; do not remove flagella or give the player free cilia. Preserve shared conservative ciliary pumping/motion, ordinary ATP costs and coarse execution. Cilia use existing receptor/exploration direction, never add target detection or direct nutrient absorption, and move all fluid-carried particles including hazards. Preserve the distinct synthesized cilia voice.


Revision 25 fluid prototypes are diagnostic only, selected explicitly by the comparison harness. Ordinary gameplay keeps the established medium. Preserve distinct solvent/chemical state and finite fixture material; do not turn packet splitting into a gameplay source. Resident solver timing excludes chemistry, body feedback and drawing; fixed-step rendered throughput is not live FPS. Grid light-body feedback and PBF boundary density remain unresolved. Do not promote either backend or hide errors with speed caps, changed body mass or omitted obstacles. GPU checks require a real RenderingDevice display; script/headless tests alone cannot validate compute. Keep Steam discovery and explicit failure for unsupported options/capacities.

Revision 26 keeps public packet dictionaries current while carrying numeric state across native transport, grid repair, chemistry and drawing. Preserve scoped lazy imports, stable query/RNG order, identity and optional timestamp defaults. Biological mutations must invalidate the affected render snapshot; external direct edits call invalidate_particle_render(index), or no index for all. Paused editing bypasses cached poses. Reaction activity/contact radius are private numeric scratch, not retained packet facts. Benchmark packets and render_cache independently; include chemical publication in total tick cost. This is a compatibility migration stage, not a fully authoritative array pool or GPU chemistry. Do not raise normal packet density on the strength of a fixed-step throughput gain; the 20k/60 FPS live target remains unmet.

Revision 27 ordinary native Pond scenes own particles in a persistent C++ pool. Public particles/pheromones arrays are empty during ownership, never current or stale pose mirrors. Use particle_count(), native spatial/biological batches, and explicit detached particle_snapshot()/particle_snapshots() for inspection/diagnostics. Prepare direct dictionary fixtures before enable_particle_pool(), or disable ownership explicitly before editing; incompatible switches export once before the next tick. Preserve sparse emission metadata, timestamp defaults, ordered finite consumption/reactions and all random streams. Monotonic handles must survive slot compaction and retire safely; inspector snapshots carry their current _index. Benchmark --hotpaths=pool against ordinary ownership, retain independent older packing/cache switches, include all catch-up and inspection costs, and report import/export counters. Do not infer sustained 20k/60 FPS or promote density/GPU solvers from the shrinking live fixture. Read docs/REVISION_27.md for contracts, evidence and limits.

Revision 28 defaults chemical particle–particle repulsion off. Keep circular reaction encounter ranges, oriented binding, translational/rotational random walks, current advection, finite accounting, feeding, membrane exclusion and pheromone exemptions. The persisted Escape Particle collisions option restores the old separation impulses in native pool, native dictionaries and script, including hidden chemistry, without restarting/exporting the pool. Orientation never defines physical particle shape. Benchmark the setting explicitly; changed distributions and aggregation mean later counts/ecology differ. The overlap trial did not achieve the 50k/60 FPS goal. Read docs/REVISION_28.md for evidence and limits.

Revision 29 supersedes Revision 28 overlap defaults: ordinary native/script gameplay always starts with soft particle collisions, including after restart; no persisted collision toggle or settings checkbox remains. Keep overlap only as an explicit profiler diagnostic. Native chemistry bounds use the tick-cached maximum partner radius plus a conservative rounding margin; retain ordered bins, every actual contact, separation arithmetic and RNG draws. Lazy acidity must still sample enzyme/waste before alignment and waste/oxygen for aligned recycling. Reference-wide bounds/eager acidity remain selectable with --hotpaths=reaction_bounds,reaction_acid for exact outcome comparison and per-item benchmarks. Do not replace collision or reaction circles with bin membership on the strength of these exact optimizations. Read docs/REVISION_29.md.

Revision 30 neighbor backends are explicit diagnostics. Ordinary chemistry keeps the established grid with no neighbor cache, collisions enabled and unchanged density. Packed indices must not reorder authoritative slots; BVH/quadtree/cache candidates must restore original periodic bin/insertion order before sequential reactions/impulses. Preserve cached radii for each chemistry pass and read current species/facing/acid/alive/reacted state. Cache invalidation covers ordered identities/handles, activation and conservative displacement/radius growth; overflow uses exact uncached search. Compare equal-horizon outcomes separately from live catch-up, and include uniform/clumped clouds, large cells and varied packet radii. Index capacity reductions and shrinking clouds do not establish 50k/60 FPS.

Revision 31 adds explicit original-LiquidFun and uniform-radius particle diagnostics; current grid/fluid/density remain defaults. Read docs/REVISION_31.md. Build the checksum-pinned original source under ignored build/ automatically; do not commit fetched sources or binaries. Pheromones never enter its contact system. Uniform physical radius is separate from circular chemical binding reach. Foreground fine steps use LiquidFun; coarse/catch-up contacts retain circular fallback. Experimental integration footprints are independent of display zoom/pan: regression tests must retain identical feeding, tissue, ATP, material and RNG through camera cycles. Conservative parcels share distant advection only, preserving every child and independent random draws; do not claim weighted collisions/reactions or full-world offline saving already exist. Keep engine selection explicit, validate native ownership, and benchmark solver, chemical grid, transport grouping and whole frames independently. Desktop C++ timings do not establish mobile ARM64, battery/thermal behavior or sustained 50k/60 FPS.

Revision 32 reuses separate foreground/background chemistry scratch. Refresh every candidate field on reuse; scratch size remains the exact candidate count. Preserve scalar transport arithmetic, single-read ordered IDs and random draw order. Keep the --hotpaths=scratch_reuse allocation ablation and exact native/dictionary parity tests; see docs/REVISION_32.md for whole-frame evidence and the rejected raw-array-view experiment.

Revision 33 uses at most eight simulation lanes (seven persistent workers plus caller). Keep engine/RNG operations on the submitting thread; workers only read immutable geometry or write exclusively owned numeric slots. Join before grid updates, chemistry commits or publication. Preserve ordered reactions/impulses and all RNG draws. Overfull contact lists and duplicate diagnostic IDs require complete serial fallback. Keep serial/transport/contact/layout ablations, paired wide-view benchmarks and worker scheduler regression checks. Compiler PGO/LTO modes are explicit; no fast-math, host-only ISA requirements, fetched/generated profile data in Git or GPU backend promotion without full coupling validation. Read docs/REVISION_33.md.

Revision 34 resident particles are a standalone transport/rendering diagnostic, never an automatic gameplay backend. Main-device RD work stays on the render thread; do not free Godot's device or add per-frame snapshots. Preserve scoped counter-based fixture noise, finite inventory, CPU/GPU tolerance checks, warmup/completion fences, readback accounting and CPU-lane ablations. The touch export's raw shader text must be included; missing native ARM64 disables CPU comparisons rather than substituting script timings. Pixel 9 Pro XL/Galaxy Z Flip7 thermal results, Android cross-build/export and Apple-device validation remain pending until tested. See docs/REVISION_34.md.

Revision 35 adds an explicitly opt-in resident GPU matching diagnostic, superseding ordered commits only within that diagnostic. After grid preparation, immutable mutual-best votes and disjoint pair commits permit one reaction per particle per update; products wait one update. Keep symmetric canonical scores, tick-dependent tie resolution, full overflow neighborhoods, finite bookkeeping and pheromone exclusions. Collision impulses precede reactions in this diagnostic and include reacting contacts. Fixed acidity/pair rules are not full chemistry or cell coupling. Ordinary gameplay remains ordered CPU; do not promote from short shrinking-cloud batch timings. See docs/REVISION_35.md.

Revision 36 adds opt-in resident cell-exchange receipts and a full-game native matching diagnostic; neither is default. Respect shared body capacities, paid-emission escrow/refusal, generation handles, sparse inspection and draining receipts before close. The GPU bridge is not full physiology or pheromone metadata ownership. CPU matching uses snapshot pair rules after unary chemistry; it intentionally differs from ordered chemistry but must be lane-deterministic. Keep native pool/grid prerequisites, duplicate-ID fallback and explicit comparison options. The owner's conditional autonomous migration authority does not waive material, sensing, whole-frame gates. Desktop integration is judged on desktop correctness and whole-frame evidence; mobile testing remains a future design/validation target, not a gate for desktop work (owner correction, October 7, 2026). See docs/REVISION_36.md.

Revision 37 defaults the resident diagnostic to stable radix bin sorting; retain the bitonic comparison and canonical per-bin IDs. Queued GPU exchanges require fixed-capacity reservations, stable cell identity/order, separate receipt slots, ordered exactly-once delivery, and draining before reconciliation or close. The capacity interval is not full GPU physiology: never skip biology or spend stale intake to claim a speedup. Preserve the inline oxygen-support ablation and exact physical-outline tests. Read docs/REVISION_37.md; whole-game promotion gates remain. Phone performance remains a design goal, not a prerequisite for desktop integration.

Revision 38 adds opt-in resident owner/report metadata, global pheromone expiry and compact grazing/hunting/flight query receipts. Preserve immutable emitted facts, exact integer IDs, family filtering, newest local reports, food-patch geometry, signal delivery and CPU resource authority. Never skip CPU biology while claiming a coupled benchmark. Keep query-layout ablation, capacity rejection, emission refusal/generation safety and full neighborhood traversal; retain explicit limits and float/tie-order differences. Read docs/REVISION_38.md. Ordinary gameplay remains CPU until complete coupling and wide-view rendered validation pass; phone testing is not a gate for desktop integration.

## Revision 39 — desktop resident gameplay

The resident backend is an explicit playable desktop option: tools/playtest.sh resident; cpu-matching and cpu remain comparisons. Preserve Steam discovery and the unchanged tools/run.sh CPU default. Read docs/REVISION_39.md. Do not describe this as sustained 50k gameplay or measured phone performance.

Resident particles own all chemical state and sparse emitted metadata. Keep ordinary CPU arrays empty; draw from the texture. Cells retain real resources and shared physiology/membrane/contact code. Credit intake/loss/events exactly once, drain toxin overflow before projection, and retain every refused or sub-float paid emission. Preserve field chemistry, immutable family-safe perception, secretion demand, generation-safe inspection, reaction sparks/music, build pause, cancellation, restart, and paid same-world succession.

Revision 39 originally advanced the whole habitat at detailed cadence; Revision 40 and the owner's large-world direction supersede that scope. Do not restore offscreen freezing, add resource bonuses, or let display zoom affect intake or recruitment. CPU fallback explicitly exports state/metadata plus escrow, never resets; benchmarks must reject fallback as a GPU measurement. Keep bounds explicit and retain diagnostic ablations. Future phone coarsening must preserve finite accounting.


## Revision 40 — performance checkpoint and bounded-world target

Read docs/REVISION_40.md and the October 7 bounded-world contract in DESIGN.md.
The existing CPU offscreen behavior is the owner's successful reference. Target
bounded nearby GPU particles plus sparse CPU world chunks, not a whole-world GPU
pass. The current cell-tier implementation is intermediate: particle/fluid
storage remains a fixed whole-habitat torus; do not claim streaming is complete.

Keep coarse CPU physiology and paid hunting shared, GPU uptake finite, promotion
elapsed time exact, hazards time-scaled and overflow retries on the same lottery.
Zoom must not change feeding; use the fixed widest-view footprint plus halo.
Camera/zoom easing for future chunk preparation is authorized, without resource
gains or visible frozen boundaries. Preserve CPU default and full-detail ablation.

Native body-fluid, traction and outline batches retain ordered formulas and
reference tests. Main RenderingDevice changes stay on its render thread. Sparse
picking must not download chemistry/field totals. Music refills between ticks;
bounded catch-up is a responsiveness safeguard that can slow simulated time.
Always report simulation/wall rate, count scope, real frame costs and native
availability. Workstation results do not establish Threadripper/3090 performance
or sustained 50k/mobile/large-world readiness.

## Revision 41 — bounded particle ownership

Read docs/REVISION_41.md. The explicit resident playtest now defaults to sparse
cold CPU chunks and a bounded nearby GPU window. Ordinary CPU gameplay remains
the default. Preserve fixed widest-view resolution, bounded admission/eviction,
absolute clock catch-up, exactly-once receipts, transfer escrow during recovery,
finite resource accounting and complete cross-owner sensory summaries. Never
truncate source/food summaries silently or revive expired pheromone facts.

Cold packets are authoritative, disjoint from GPU-owned poses. Serial CPU scopes
may borrow them into temporary arrays; those arrays must be empty when a resident
tick returns. Return unmoved chunks as units, batch native transport/query/rebin
work and keep the scheduler to one indexed-heap entry per chunk. Do not substitute
a full stored-world scan or snapshot. CPU fallback must include cold state,
GPU state, paid emissions and unacknowledged transfer escrow exactly once.

GPU work/drawing uses a stable slot watermark within bounded allocation. Do not
break generation handles to reduce work. Camera travel waits for admission and
eviction and keeps the whole rectangle inside prepared water, including reversals.
Keep count scopes explicit: nearby GPU includes a halo; CPU stored can include
unreclaimed dead/expired slots. Record whole frames and sim/wall rates, not only
mean ticks. The current fixed habitat/fluid grid and all-cell scheduling still
need further scaling; do not claim an unbounded whole game or sustained 50k/mobile
performance. Whole-GPU reference: frame profiler --resident-streaming=off.

## Revision 42 anatomy and audio invariants

- Generated cells and successors retain one inherent oral groove. It uses the
  legacy feeding structure type but is neither a purchase nor armor; do not
  allow recycling, moving, resizing or specializing it through organ tools.
- Tissue volume is represented linearly by membrane area. ATP has no storage
  cap; concentration-dependent turnover is shared by fine and coarse biology.
- Intracellular parcels in build mode represent existing resources only.
  Internal animation cannot advance external biology or grant ATP, tissue/AP.
- No anonymous backing music. Notes identify their nucleus, equipped organ or
  real food vacuole; visible pitch-colored waves follow audio playback.
- All suction uses body-relative linear and angular velocity with paired
  impulses. Godot Vector2.orthogonal() has the opposite sign to (-y,x);
  use (-y,x) for angular surface velocity and positive steering torque.

## Revision 43 — owner balance-test hold

Explicit owner instruction, October 13, 2026: disable every test whose purpose
is gameplay balance until further notice. Keep the assertions in source for
later restoration, gated by tests/test_policy.gd. Do not run economy playtests,
survival/viability campaigns, autonomous kill-rate acceptance or ATP-yield
tuning while this hold is active. Continue correctness tests for conservation,
finite input/output, local particle transport/reactions, paid actions, physics,
UI, determinism and native/reference/GPU consistency.

## Revision 43 — current chemistry contracts

Read docs/REVISION_43.md before changing the sandbox. Hunting spikes and hidden
statistical kills are retired. Preserve finite tags/subunits, local membrane
assembly, inhibitor/repair material and immutable pheromone/family safety.
Every chemical transport path, including cytoplasmic energy, redox and offspring
ATP reserves, uses particles. Derived totals are readouts; graph edges must never
credit stocks or teleport a molecule. Editing pauses actual intracellular
movement and all chemistry. Keep paid catalysts/compartments, source-bound local
reactions, finite fuel, real local ADP/ATP conversion and species-preserving
lysis. NAD/adenylate/water organic material weight is zero in every backend.

The tenfold richer default is explicitly authorized and supersedes prior
unchanged-density instructions. F3 distinguishes visible chemical packets,
represented-material packets and signals. Counts and performance are separate
from balance, which remains held. Generate native catalog tables from authored
data/chemistry.json automatically; do not commit their deterministic output.
