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

## Revision 44 — persistent shared world

Read docs/REVISION_44.md and docs/deployment.md. The authorized private service keeps native GPU chemistry/transport on samzapo-desktop; WebGL browsers present server poses. Union every active camera's fixed detail footprint and preserve existing coarse out-of-camera ecology, including zero clients. Shared editors submit paid, validated live commands and never pause authority; local single-player keeps its CPU default/pause. Hold gameplay objectives and balance tests until the owner restores them; retain physical and infrastructure checks. Preserve data-only shared-reference checkpoints, RNG, all particle owners/escrow, durable edit receipts, invitation/account privacy and fail-closed recovery. Resume saved time after downtime without catch-up. Deploy Primordia independently on port 8766 with internal loopback 8767; GSOC hosting was explicitly inspected for this task only. No unrelated repository/chat access follows from that exception.

## October 14, 2026 — resident default

Explicit owner direction: normal play now always uses the resident implementation. This supersedes older CPU-default launch instructions. Keep the browser as a WebGL presentation client, require a real hardware GPU for persistent deployment, and retain explicit CPU reference paths for correctness comparisons.

## October 14, 2026 — multiplayer density reduction

Explicit owner correction: lower the particle count to one tenth while bringing multiplayer into operation. The catalog now targets roughly 700 visible chemicals, seeds 3,760 external parcels and uses tenfold parcel quantities rather than deleting material. This supersedes the Revision 43 density increase. Keep the resident hardware GPU and particle-only chemistry. Trusted older checkpoints receive one guarded, conservative resolution conversion with an independently retained original generation; never perform that scan every tick or combine distinct chemical species, owners, pathway sources or compartments. Gameplay balance/objective tests remain held.

## October 14 — perception domain separation and Follow

Explicit owner direction: split internal and external particle simulation interests. Exteroception hides internal chemical packets and schedules them offscreen; Interoception hides external packets/chemistry, schedules the unrequested exterior offscreen and greys/dims the actual area outside the focused membrane. Read docs/REVISION_45.md. Preserve the resident external GPU/cold ownership path, physical intracellular transport/reactions, exactly-once retained elapsed time and per-domain multiplayer interest unions. Neither view switching nor dead-lineage observation grants particles, ATP, tissue, AP, editing authority or a new living body. Follow always says Follow, highlighted active and dim off; living observation focus is separate from owned selection. Keep gameplay/objective/balance tests held and retain domain conservation, clock, UI, recovery and real-GPU checks.

Revision 46 moves visible intracellular transport and local chemistry into per-cell components of the existing main-device resident backend. Read `docs/REVISION_46.md`. CPU particles/bins are empty while that component owns them. Preserve finite double quantities/fuel, full-width identities/source/compartment, stable spatial/species query order, compact exactly-once body receipts, device-side rollback/growth, explicit ownership transfers and complete detached checkpoints. Do not introduce a CPU pose mirror or per-tick full-pool downloads. Native presentation samples resident textures; browser presentation interpolates instanced snapshots. Camera visibility determines promotion; hidden domains keep the existing coarse clock and real chemistry. Version 2 reduces only internal resolution for previously converted worlds, retaining the original generation independently; never repeat exterior conversion or discard chemical inventory to meet a record-count target. Keep explicit broad seed coverage and installed catalyst sites.

The persistent authority disables display VSync and caps its render loop independently of its 60 Hz physics. Web music uses the authored score with a build-generated, content-addressed 17-instrument bank and browser Web Audio, without worker threads or a live GDScript mixer. Preserve touch enable/mute/volume, bounded voices, gesture-based audio start, environment filtering, cleared mute/reset tails, read-only living-cell observation and native music behavior. Generated banks/manifests stay out of Git. Verify real GPU correctness and browser audio output separately from physical phone frame rate or speaker audibility. Gameplay/objective/balance holds remain.

Version 3 additionally coalesces released digestive catalyst material locally on both CPU and GPU. Preserve installed catalyst sites, active vacuoles and sparse facts. A v2 upgrade must not repeat ordinary substrate coarsening; retain independent v1/v2/v3 backups with exact durable-publisher destinations. Inspect actual species counts rather than assuming the target reduction was achieved.

Revision 47 makes reproductive investment and release automatic for living cells, including offscreen and disconnected worlds. Read docs/REVISION_47.md. Use the existing paid offspring quote and particle reserve transfers, retain operating floors, installed anatomy and safe placement, keep the parent selected, and bound family/global populations and blocked retries. Reuse unowned family ledgers on login; never substitute the managed player for another reproducing parent. Preserve prepaid dormant succession and fail honestly on exhaustion. No sign-in-triggered free founder or world reset is authorized by this feature. Gameplay/objective/balance tests remain held.

Revision 48 implements the owner-authorized persistent introduction rules: maintain a fifteen-living-cell floor, replace an exhausted account with a new starter lineage, and archive/reseed an entirely empty pond. This supersedes the earlier no-founder/no-reset rule for the shared server only. Read docs/REVISION_48.md. Preserve existing keys/sessions, paid reproduction, safe placement, bounded retries, the 64-body GPU limit and fail-closed checksummed archives; new starter inventory must remain an explicit introduction rather than free resources credited to an existing body. Gameplay/objective/balance tests remain held.

## Revision 49 — simplified food-vacuole model

Explicit owner direction supersedes Revision 43/46 intracellular particle-energy contracts. Read docs/REVISION_49.md. ATP, biomass and reproductive ATP reserves are numerical quantities. Only ingested nutrient material and resulting waste inhabit the cytoplasm; use the bounded resident GPU implementation when visible and existing coarse methods when hidden. Do not restore seeded cofactors, catalysts, pathway graphs, osmosis or ATP/ADP clouds. Preserve finite material/fuel, archived audited migration, the existing access keys/account graph, paid automatic reproduction and the fifteen-cell persistent floor. Gameplay/objective/balance tests remain held. Real-time performance checks, conservation, UI and persistence checks remain active.

## October 15, 2026 — mobile vacuoles and restored tests

The owner re-enables gameplay and balance tests, including objectives, superseding every earlier hold. Keep the suites enabled in tests/test_policy.gd; update retired-model expectations to the current direct food-vacuole rules rather than restoring respiration/fermentation or physical hunting spikes. Revision50 uses at least ten simulation seconds of vacuole residence, one integrated carrier per food/waste compartment, decorative half-size contents, cell-attached interoception camera controls and mobile top menus/resources. Read docs/REVISION_50.md. Preserve finite mass/fuel, existing saves/keys, resident GPU ownership and real-time acceptance.

## Revision 51 — owner restored features

Read docs/REVISION_51.md. The latest owner request restores bounded oxygen/carbon particle respiration, fermentation, emergency surplus-biomass fuel and photosynthesis; this supersedes the retired-path restrictions only for this small loop. ATP/biomass remain numerical, with shaped cosmetic transaction feedback. Preserve ten-second food/waste carriers, resident visible ownership and real-time budgets. Successful paid division awards 2 AP and independently offers a free mutation with 10% probability. Hourly calendar conditions replace persistent tide progression. Microtubules are procedural-only with faint lines and no handles; reject old edit commands. Mobile selected-icon cancel, bottom descriptions and Pause/settings are required. Existing pond, account graph, keys and enabled gameplay/balance/objective tests remain intact.

## October 15, 2026 — retain cells and forgive transient starvation

Explicit owner direction: preserve players' actual cells across service restarts;
they are attached to their cells. Do not reset the pond to repair nutrition.
Read the Persistent pond survival section of docs/DESIGN.md. The archived,
versioned food-supply upgrade only adds audited exterior particles once. Explicit
new-cell introductions receive cell-derived stock, while paid divisions/login/
camera changes/restarts grant none. Keep the richer food quantities at the same
packet count and longer core food/carbon/oxygen lifetimes across backends.
Reclaim uncommitted daughter reserves before starvation and preserve the saved
five-minute starvation grace/gradual damage clock. Keep normal physical feeding,
photosynthesis, finite accounting and enabled gameplay/balance tests.
Browser snapshots must deliver bounded recent death facts using the correct
account's previously selected/followed body, without replay on reconnect or
resume. Succession and lysis stay immediate and do not wait for animation.

## October 15, 2026 — private player feedback

The owner chose a private server inbox, exportable through GitHub Actions. Keep
feedback under retained state/feedback, independent of rotating pond saves;
confirm only durable writes and preserve drafts across retries. Signed-in
players submit from Pause/settings without GitHub access. Treat report text as
untrusted data. Export only through samzapo/primordia private Actions; never
include access keys, session credentials or private account fingerprints.

## October 15, 2026 — persistent names, stronger offense and update boundaries

The owner requests 2 AP per committed cell division and stronger offensive
organelles. Current potency is toxin150/unit, pore32/second and acid parcel
capacity0.5; Buffer remains0.25. Share the authored catalog across native, resident
and coarse paths; retain finite costs/contact and no physical hunting spikes.
Population evolves by rebalance; never cap, cull or reset it for performance.
Players name themselves in Pause; retain names with accounts and draw labels over
owned-lineage cells, highlighted while connected and dim offline. Preserve all
saved cell biology across ordinary updates and fail closed before simulation
starts if the canonical retention comparison loses a body or changes old state.
Keep exact stopped generations for rollback. Extinct ponds still archive under
the existing explicit restart rule. A new fluid-instability screenshot alone is
not proof of numerical runaway: inspect actual saved/live velocities, body motion
and the visual streamline integration before changing physics or claiming a cause.

## October 15, 2026 — slower flow, full stream history and plant drag

Latest correction: the cells and particles also moved wildly; the issue was not
limited to visual streaks. Do not shorten streams: retain8.4second history and
20secondseed lifecycle. Current maintained tide is35% of its prior amplitude;
versioned hourly target refresh changes it without resetting water/cells or
slowing worldtime. Plants damp real water using bounded exponential nodal drag
rasterized from actual branches, including permeable fine foliage. Apply in both
native/reference field updates and the offscreen complement; chemical packets
remain permeable. Density/opacity reduction is presentation only. A finite saved
sample does not rule out earlier spikes. Record current evidence and limitations.


## October 15, 2026 — authorized rollout with performance warnings

The owner says to send this update out and monitor performance. For this rollout,
timing-target misses may be explicit warnings, selected by a manual workflow
input or the exact head-commit marker [allow-performance-warnings]. Unmarked
future pushes remain strict. Do not suppress functional, hardware-GPU, finite
state, checkpoint or all-cell retention checks; keep the30Hz configured cadence
and measured targets. Record and monitor timing misses honestly. This request
does not authorize GPU clock/power changes, pond resets or population culling.


## October 16, 2026 — accessible anatomy and original ambient current

The mouth follows the actual oral membrane curve and scales with small cells.
Controlled cells and their local factories draw above uncontrolled anatomy;
owned family cells also draw above NPC lineages. Overlapping clickable structures
must remain individually accessible through temporary choices. Double-tap adopts
a living owned family member through the validated existing follow command.
Photosynthesis always offers free, mutually exclusive Sun/Shade adaptations;
other mutations retain their discovery requirements. Acid tint is stronger and
has a broader bounded visual footprint; buffers restore blue through real acid
neutralization. This is presentation, not extra chemical material or damage.
The owner restores the original ambient current strength, superseding the prior
35% reduction; retain plant drag and refresh only the maintained target through
flow version2 without resetting saved water or any cells. Scheduled monitoring
was removed at the owner's request; do not resume or recreate it.


October16 continuation: standard installation and lost-organ restoration cost
one AP only. No biomass/ATP construction debit; retain operating ATP, repair
and reproduction costs. AP-funded organ tissue is an explicit external_input
source; canceling local construction rolls it back. Persistent NPC lineages may
spend their retained AP on bounded random fitting organs, excluding all account
roots even offline. Use the same priced path; do not borrow player AP or reroll
progression on restart. Update retired tissue-price tests to this economy and
keep conservation checks against the explicit source.


October16 owner hold: do not run rendering-speed/FPS/frame-budget benchmarks
until the owner asks to resume. Field updates after focused correctness, real
GPU/backend, network and checkpoint/all-cell retention checks. Do not claim a
rendered speed target passed from those checks. Existing performance-warning
rollout support may record timing observations; preserve all hard correctness,
GPU and save-retention failures. Monitoring schedules remain deleted.



October16 owner adds saved per-organ Output (100/150/200/300/400%) independent
of steering. Default100 preserves old behavior. Shared work/ATP helpers cover
ordinary/resident/offscreen execution with a small inefficiency. Preserve finite
emission material/carbon, ATP-backed sensory/protective boosts and baseline
photosynthesis/sensing at zero ATP. Validate settings through editor commands;
adjusting the percentage itself is free.

October16 nutrient continuation: extend existing joining, not a duplicate pathway.
Mild acid assists contact alignment; excess acid still harms cells. Nutrient
parcels gain a bounded ATP-per-unit allocation bonus, funded from their existing
heat/tissue fuel budget. Keep true fuel unchanged, no rejuvenation of depleted
food, no bonus from resolution coalescing, and proportional uptake/lysis.
External capacity>amount encodes fully fueled food plus bonus; internal nutrition
is an additive amount-weighted fact, resident clock.y. Omit zero fields on old
packets so update retention remains exact. All backends share authored bounds.


October16 particle stability: read docs/REVISION_52.md. External soft separation
uses the same symmetric maximum-endpoint-degree divisor on resident, native and
script paths. Count complete overlap neighbourhoods, not capped diagnostic
contacts or higher-ID reaction caches. Retain isolated-pair behavior, transport,
binding/material rules, current strength and full stream history. Full GPU
admission retains/retries paid escrow and still delivers body receipts; it must
not force a CPU fallback. Expose backlog/capacity operational metrics rather
than silently deleting particles or hiding device errors. Do not reset the
saved pond or clip existing velocities during this update.


October16 global particle budget: the owner explicitly authorizes probabilistic
external particle destruction above a limit, superseding prior no-particle-cull
instructions for this exterior-only budget. Read docs/REVISION_53.md. Apply one
global survival probability to GPU, cold and paid/trace escrow; keep species
proportions in expectation and account material/fuel outflow explicitly. Never
cull cells, organs, internal contents, accounts, keys or feedback. Default shared
limit5000 is a growth guard, not a verified performance maximum. Preserve all
saved cell state and the independent thinning clock/RNG across updates. Report
server habitat counts separately from camera snapshots and dead storage slots.
Clamp spent field charge, repair only known tiny legacy waste residue, and retain
strict rejection of substantive negative inventory. Rendering benchmarks and
schedules remain held; capacity probes require explicit dispatch or marker.


October16 player update notices: after each public game update, include a brief
player-facing change log shown once after sign-in and the first ready world view.
The owner approved the first What’s new in the pond copy in
scripts/network/release_notes.gd and wants this voice used routinely. Before every
public update, append a new authored release ID and brief bullets with the
substantial changes in that release, preserving earlier entries. Use plain gameplay language, a few short
bullets and Back to the pond; exclude implementation details, commit IDs,
benchmarks and deployment jargon. The first copy required approval and is now
approved; later copy follows this standard workflow without repeated approval.
Retain acknowledgement on the player account only after a durable save, so
reconnects/devices/restarts do not replay it. A later release appears again. The
shared world continues while reading; no new HUD or automatic world pause.


October16 player guide requirement: keep Pause → Gameplay and Mechanics current
with every shipped feature, changed rule, organelle, gesture or shortcut.
data/player_guide.json is authored player copy, not a dump of historical design
documents or retired chemistry catalog entries. Gameplay shows only the current
touch or desktop controls, never keyboard/mouse shortcuts on mobile. Mechanics
uses short descriptions of active rules, grouped for reading, with clickable
HTTPS links to the matching scientific grounding already retained in references.md.
Clearly identify fictional recipes, costs, probabilities, presentation and
persistent-world rules as game choices. Do not restore retired pathways by
documenting them as available. Review/update this content alongside release notes
before every public deployment; keep explanations simple for the game audience.


October16 reader correction: the first canvas pop-up was blank on the owner’s
phone despite passing geometry/text-property tests. Web update/help readers now
use native HTML panels with real browser visibility, scrolling and close checks;
never infer visible text from data or rectangles alone. Keep a fixed close
button and never require a server response to leave a reader. Acknowledgement
still counts only after durable server save, with bounded background retries.

The owner requests every missed update, oldest first until all are cleared.
Append to ReleaseNotes.RELEASES; never replace historical player copy. The saved
last-cleared release advances only one known release at a time; old duplicate
acks must not move it backwards. Preserve legacy seen_release values. Show Next
update until the last message, then Back to the pond. On acknowledgement failure,
leave the game accessible and defer the uncleared queue until next sign-in.

October16 phone-motion continuation: owner resumes scoped presentation-pacing
work after discontinuing the earlier iOS investigation. Read docs/REVISION_54.md.
Network views interpolate actual captured endpoints on one bounded playback
timeline; camera, particles and internal poses must agree. No local chemistry or
unbounded extrapolation. Preserve immediate death delivery, exact view pause,
live resume, saved cells/accounts/keys and deleted schedules. This authorizes
focused jitter/frame-pacing checks, not a broad rendering benchmark restart.

October16 illumination continuation: owner requests diffuse irregular sun/shade
regions roughly 100–1000um across, replacing the visible regular grid. Read
docs/REVISION_55.md. Preserve the 0.2um/unit calibration and existing pond size:
upper-scale regions span the pond. Use one seeded continuous periodic field for
photosynthesis, phototaxis, water and bloom, preserving mean illumination/weather.
Derived caches consume no ecological RNG or saved cell state. Keep normalized R8
display filtering portable and test actual pixels without broad FPS benchmarks.


October16 illumination correction: Revision55 field-only acceptance missed the
old shader's independent glow spots and dim-weather contrast collapse, reported
again on the owner's phone. Read docs/REVISION_56.md. Remove independent light
sources, strengthen spatial contrast without changing photosynthetic energy,
and confine animated caustics to lit water. Use actual default-art pixels in
portrait and dim conditions; a uniform diagnostic/daytime screenshot alone
does not establish visual acceptance. Preserve pause/toggle, acid readability,
saved world/cells and the rendering-speed benchmark hold.


October16 stable/experimental continuation: main is the default and first stable
source7df04de. The owner authorizes a second game instance on the same machine
and HTTPS port under /experimental/. Read docs/deployment.md. Keep its process,
ports8768/8769 (loopback only), root/state/accounts/feedback/browser IndexedDB
and CD independent from stable. Reuse existing key hashes without copying live
cells/checkpoints/accounts/reports. Experimental deploys must never stop stable;
verify stable PID/build/pond/epoch/registry plus continued time. Never auto-run
a privileged helper or resume stopped ingress/router helpers. Caddy route
updates use conditional ETags, preserve existing configuration, and report any
remaining one-time root-owned boot-file install. No new schedules/FPS campaigns.

October16 approved R1–R5: read docs/REVISION_57.md. Stage on experimental first. Multiplayer new-lineage changes ownership only after explicit confirmation and the ordinary durable sequenced receipt; preserve old family alive/anatomy/history/account/key/pond, saved cooldown and NPC eligibility. Toxin75/pore16 restore pre-buff damage. Perception exits retain zoom with destination clamping. Induced currents are weak seed/time-derived external tide targets shared by all solver/activity paths; preserve plant drag, physical velocities, ecology RNG and full trail history. Gold is restricted to water immediately around source centers, never whole trails or all currents. Draw actual bound pore material outside the real membrane; no invented particles, hit targets or damage. Update guide/release notices, validate actual pixels and keep broad FPS benchmarks held.

October16 camera correction: discrete visible camera relocations ease smoothly, including follow/recenter, family/lineage switch, perception, build framing and live resume. Keep direct gestures exact and Pause frozen. Use one displayed camera pose for world transforms, inverse pointer mapping, inspector headings and network camera interests; do not add lag to ordinary snapshot tracking. Initial unseen sign-in may initialize directly. See Revision57 and camera_motion.gd.

October16 induced-current correction: owner reports sources too rare. Thirty-two staggered spiral/directional event lanes leave an event active at all times. Owner specifies30–100µm diameter,10–50µm/s migration,1–20second lifetime; gold stays source-local. The owner explicitly halves plant dissipation (coefficient and cap), retaining plant geometry and particle permeability. Blend overlapping targets, never reset saved water/cells or gate sources on cameras. See Revision57.

October17 camera particle delivery: owner reports empty water briefly after moving the camera. Read Revision58. Gather a bounded border of real resident packets, retain captured coverage through asynchronous GPU gather/encoding, and keep per-camera visible counts distinct from buffered records. Prioritize actual visible chunks and gate publication by each observer’s prepared coverage, never global unrelated admission/eviction queues. Fixed server overscan stays independent of zoom and never adds local client chemistry, particles or motion prediction. Preserve ACK backpressure, request limits, pause/perception/death and saved cells/keys. Experimental first; no broad FPS campaign.


October17 stable promotion: the owner explicitly authorizes squash promotion of
the tested experimental update into main and stable deployment. Stable CD now
follows main; feature branches remain experimental until explicitly promoted.
Preserve each instance's independent saved cells, accounts, five-key registry and
private feedback. Check the experimental process/pond identity across stable
updates as well as the stable all-cell retention and saved-world restart.


October17 notice separation correction: an experimental-pond announcement leaked
into main when source branches merged. ReleaseNotes entries must declare an
audience (shared/stable/experimental). Main must never queue experimental-only
notices; stable promotion announcements must not appear in the experimental pond.
Keep historical IDs and saved acknowledgement positions, skipping hidden entries
when validating the next acknowledgement. The service selects the audience;
clients cannot choose it. Promotion must explicitly review notice audiences.

October17 approved feedback R9–R15: read docs/REVISION_59.md. Stage all on experimental; stable promotion awaits owner playtest. NPC strategies globally replace random buying:floor(10%)Hunter, remainder evenly Producer/Grazer; preserve existing anatomy. Player family/body opt-in investment persists; connected selected cells remain manual. Keep75/25new photosynthetic food partition, finite mitochondrial ATP allocation and native/resident/coarse parity. Counterattack perception uses immutable local reports; contact permissions enforce peaceful/player immunity. Sanctuary is fictional, prevents death/organ destruction and offspring, and gives2AP only after a fully paid full-material/ATP cycle. Disable its indiscriminate acid/decoys. Preserve saved bodies, source permissions and current family history.
Pinned godot-cpp Dictionary move assignment leaks initialized owners; the verified build backport must run before binding generation in both recipes. Keep minimal lifetime and sustained authority evidence separate; don't repeat the disproven GPU-upload diagnosis or claim every historical allocation was attributed. No copied generated SDK/build artifacts, no rendering-speed campaign.

October17 final pre-experimental collection adds R16–R20 by explicit owner approval. Preserve the current camera until a family command commits, show desktop AP supply only while building, suppress stale editing hints, derive organ readiness without modifying work, and keep lineage HSV color purely presentational and owner-scoped/durable. Validate actual portrait pixels and touch-density scaling; the color picker must retain accessible Save/Back. Keep player guide and experimental-only notice current.

Color-modal validation correction: Canvas z-index does not change Control GUI picking order. Raise the modal in the UI tree on open; test actual clicks/touches over the visible Pause menu. Direct wheel.choose calls and bounds/pixel checks alone missed this input-layer defect. Exported browser acceptance must use isolated fixture accounts/state, never synthetic production sign-ins or feedback.

October17 owner playtest correction: internal construction needs a recognizable cell-local factory, with a raised chamber plate and build-symbol badge, never a new screen label in both desktop/mobile and exterior/interior views. Selecting or moving an internal organ automatically uses the existing smooth Interoception camera transition. Investment presents Hunter/Producer/Grazer illustrated cells simultaneously for direct choice, with explicit scope, Manual and Inherit; do not restore strategy cycling. Keep both guides and experimental-only release notices current.

Owner overlap-picker correction: prefer matching artwork over names/abbreviations. Both factories, the actual lineage nucleus, ATP/offspring stores and installed/lost organs use shared world artwork in overlap choices; pink rings identify lost organs. Keep captions for descriptions and accessibility, with no new permanent labels.

Investment-panel target acceptance caught overflow at large UI scale. Bound the temporary panel’s effective scale by both viewport dimensions; verify desktop, portrait, dense touch, short landscape and enlarged UI settings with actual pointer input. Preserve all three pictures and explicit controls. Experimental fixture subprocess failures must print their retained assertion output before propagating the failure, without bypassing any gate.

October17 owner correction: read Revision60. Shade leaves seek soft light using the local gradient (darker above0.45, brighter below0.35; no drive inside the band); Sun retains light seeking. Reject stale opposing light intentions without changing ecology RNG; later owner direction below replaces manual Steering. Output/overdrive is removed: hide controls/readouts, reject the old command, ignore retained legacy percentages across all backends, and keep mutation effects. Preserve exact saved anatomy instead of migrating/deleting old output fields. Update the player guide and experimental notice; validate normal-output parity and deploy experimental only.

October17 final owner continuation supersedes manual Exploration/response-cycle and per-organ Steering. Read Revision60. Use one shared local-signal behavior tree for selected/unattended player cells, NPCs and all activity/backend paths. Prioritize harm/escape, ATP recovery, biomass, then opportunistic hunt/light/search. Never look up live sources or remote family positions; dispersion uses fresh received immutable family chemistry. Respect actual sensory/motor organs and ordinary ATP/material/contact costs; resting only stops propulsion. Preserve legacy percentage fields inert and reject retired commands. Hunter/Producer/Grazer investments use complementary, diverse supporting anatomy and own condition; retain NPC10%Hunter quotas, saved opt-in/manual semantics and ordinary AP fitting/accounting. Sanctuary was subsequently withdrawn; see the final correction below. With every organelle/chemistry addition, explicitly maintain behavior capabilities, investment roles or deliberate manual-only exclusions, targeted tests, scientific abstractions, player guide and audience-filtered release text. This is standing development upkeep, not authorization for a schedule or a stable promotion.

October17 final owner correction: remove Sanctuary entirely; it must not be deployed as an available organ or active immunity/growth rule. Family menus list living relatives/reserves and retain only highest generation and total cells ever; deceased records leave the active ledger. The owner explicitly authorizes this large update to reset pond state and remove incompatible history. For the current experimental deployment only, use the explicit reset_pond dispatch input, retain keys/accounts/names/private feedback and rollback predecessor, verify a genuinely new experimental pond and its normal subsequent restart. Stable stays untouched pending promotion. This supersedes strict old-cell/anatomy retention for this one reset, not the ordinary update default. Do not keep a hidden functioning Sanctuary or silently enable reset on pushes/future updates.

October17 division correction: daughters inherit only the effective investment
strategy, not purchased organs, mutations or the parent's sampled cytoskeleton.
New bodies have one ordinary inherent oral groove and their own sampled shape.
Quote only this basic body/tissue; retain paid material/ATP transfer, parent
anatomy, lineage identity and 2AP per committed division. A Manual parent assigns
a uniformly random Hunter/Producer/Grazer only after a birth can commit. Save the
daughter's strategy as a body override; NPC quota balancing must respect it.
Quotas continue to guide unassigned NPCs, while reproduction may change the mix.
Failed/blocked births neither draw strategy randomness nor leave overrides.
Death removes obsolete body investment entries. Existing bodies and banked
reserves are not rewritten; ordinary persistent experimental rollout only.

October17 mobile font correction: Comic Neue lacks the investment checkmark
glyph. Investment scope, Manual/Inherit and strategy cards use a shared authored
vector selection-mark texture, never a font-dependent tick. Retain the active
card highlight and verify actual touch choices and marker textures on target.

October17 AP pricing correction: each cell's next added/restored organ costs
the number of currently installed non-inherent organs (0,1,2,...). The inherent
oral groove is excluded. Selling, loss or removal lowers that current count;
Selling refunds max(0,actual installation AP paid minus1). Store construction_ap
on each newly installed/restored organ; unknown legacy normal prices refund0.
Do not use a lifetime construction counter. Automatic
investment and both desktop/mobile factory, placement, resource and restoration
previews use this same Cell.construction_price. Zero AP must allow a first free
build. Existing cells derive price from actual anatomy without a save migration.

October 17 low-power correction: read Revision 62. Replace ATP shutdowns with a
shared 25% operating floor for functional motors/pumping, secretion, weapon
recharge, active gland repair and receptor cleaning. Enter below 12 ATP, recover
at 18 to avoid flicker; preserve the bounded low_power latch in behavior.
Status/presentation reads must not change it. Passive photosynthesis/digestion,
sensing and protection keep their existing ATP-independent rules. Keep finite
material, valid targets/needed secretion and broken-organ gates; charge only
actual available ATP, never invent ATP or negative stocks. Quarter baseline
work without sufficient ATP is an explicit game allowance, not a biochemical
conservation claim. Weapon parcels remain unchanged and recharge advances at
quarter rate. Shared fine/resident/coarse helpers and offscreen intake estimates
must agree. Low ATP no longer removes hunting intent when prey is the only cue;
digestion/rest and emergency priority still apply. Feasible mitochondrial
investment gains priority during shortage. Update guides/experimental notice
and functional GPU/persistence tests; preserve the pond, keys and feedback.

October 17 family-menu correction: each current relative/reserve uses a live
anatomy portrait behind a tiny generation-number badge in the bottom corner,
matching factory badges. Keep the selected body marked and ordinary follow
validation/input. Refresh growth, installed/damaged organs and lineage color
while open; remove deceased entries. Owned off-camera portraits travel as small,
data-only presentation snapshots, never extra camera interests, chemistry poses
or simulated client bodies. Capture/drawing must not alter ecology or RNG.
Validate actual desktop/touch pixels and pointer selection; preserve both ponds.

October 17 family-grid correction: show all current relative/reserve portraits
in one responsive desktop/touch grid. Remove the G-generation summary action
and More pagination, including the generic desktop five-choice limit. Keep
highest-generation/lifetime totals as small header text and per-cell generation
as a tiny corner badge. Allow the family menu to use the screen; scroll only
when its contents exceed the viewport. Close remains fixed and reachable while
scrolling. Preserve live portraits, validated follow and ordinary pond retention.

October 17 direct-division correction: banked/dormant offspring are retired.
Do not create founder reserves, store paid bodies or hatch old backups. The
owner explicitly waives reserve/history retention for this update: discard old
stored bodies on the next authority tick, recording their material as removed;
do not release them or reset the living pond. Preserve ordinary living cells,
accounts, five keys and feedback. Keep paid automatic growth and actual safe
live division, basic daughter/strategy inheritance, 2AP awards and normal
living-family succession. The bud offers only Divide now. Show only living
relatives in portraits/help; there is no storage bank or dormant recovery.

October 17 restart acceptance found an exhausted/sub-float cold nutrient reaching
resident GPU admission as a zero float32 dose. Keep strict exchange validation
and hardware GPU gates. Cold promotion must pass through the same enqueue
escrow as paid emissions, retaining positive sub-float material and food capacity.
Retire only exactly empty material/capacity slots; never round up a dose or cull
positive matter to make a deployment pass. Validate the real handoff and restart.

October 17 stable family promotion and standby: the owner explicitly authorizes
promoting the verified experimental build to main and suspending experimental
until the next batch. Keep experimental release-notice IDs/audiences; add one
stable-only gameplay notice instead of leaking playtest announcements. Preserve
the living stable pond, accounts, five keys and private feedback. Only after
stable CD and retention/delivery checks pass, use the explicit experimental
standby operation. Keep its saved pond/keys/feedback and disable only its unit;
future stable updates must preserve standby, and the next authorized experimental
deploy resumes it without reset. Newly collected R21/R22 remain proposals only.

Standby acceptance correction: /health reads a periodically published snapshot,
not a fresh tick per HTTP request. Wait for a new tick with bounded polling;
a one-second delay falsely failed after successful shutdown. Finish interrupted
standby from the owned stopped release and matching saved health without starting
it. Standby uses its task-owned source checkout, permitting a scoped repair
against an explicitly supplied exact deployed stable revision.

Standby user-bus correction: user-service queries must supply XDG_RUNTIME_DIR
inside the query helper, including imported/read-only verification. An environment
set in an earlier Python subprocess does not propagate to the next process.
Test the imported helper with an empty environment as well as an existing path.

October 17 recycling correction supersedes per-organ paid-price refunds: return
max(0,current installed non-inherent organ count minus1), before removal.
With four added organs, recycling any one returns3AP; three return2AP.
The inherent oral groove is excluded; missing/rejected/duplicate removals return
nothing. Do not depend on construction_ap history or migrate saved anatomy.
Menu actions resolve organ IDs at click time because live snapshots replace
dictionaries while menus stay open. Only authoritative committed receipts report
AP returned in multiplayer; preserve exactly-once refunds and checkpointing.

October 17 growing-family correction: read Revision63. The owner approves R21/R22 and removal of the four-cell family limit for experimental first. Retain paid live division, safe placement and64-body resident safety. Report authoritative whole-pond readiness, never infer it from camera-visible cells; bud and nucleus both expose Investment. Toxin sacs store finite paid material, included once in mass/inertia and saved anatomy, and release ordinary toxin exactly once on death before nutrient lysis. Recycling/loss/restoration must not duplicate contents. No extra senses, remote damage or suicide behavior. Keep behavior/investment roles, art, live portraits, science guide and experimental-only release copy current. Faster free tag/subunit decay must not change bound assembly. Resume saved experimental without reset and preserve stable; promotion awaits playtest.

October17 growing-family promotion: the owner authorizes deploying the tested Revision63 batch to main. Preserve the exact tested gameplay from experimental e2d6cc0, keep experimental-only notice IDs/audiences, and add a separate stable gameplay notice. Preserve both living ponds, accounts, five-key registries and private feedback through deployment/restart checks. After stable acceptance, return experimental to standby through the documented explicit workflow, retaining its saved state for the next batch.

October17 final AP/investment correction: read Revision64. AP belongs to each
cell; relatives cannot spend it. Committed division grants parent1AP and
daughter1AP; readiness grants nothing. One-time legacy pools go to the
authenticated selected body without duplicating AP or altering cells/anatomy.
This update starts all saved investment on Manual. NPCs and Manual daughters
also default Manual; remove old quotas/random birth choices. Explicit strategies
may buy or reabsorb unsuitable/excess anatomy using their own AP, with one saved
automatic action per cell per60 simulation seconds. Keep essential food/energy
and last defenses. Remove organ Move and reject stale commands. The player
action is Reabsorb; its unchanged current-count refund goes to that body.
Update guides/notices and validate ownership, migration, cooldown and receipts.
Owner authorizes these corrections with the pending main promotion; preserve
both ponds/accounts/keys/feedback and return experimental to standby afterward.

October17 survival correction: read Revision65. One healthy leaf must sustain a basic cell throughout the pond, including dim water. Ambient carbon enters only real exterior packets through bounded local saturation and an explicit open-system ledger, independent of cameras/accounts; do not assign stocks to cells. Preserve native pool, dictionary and resident/cold ownership, elapsed time and finite accounting. Settling old carbon precedes mixing fresh material; never export the full GPU pool for supply. Larger anatomy pays shared maintenance, with extra leaves and mitochondrial food allocation providing support. Defer reproductive investment during starvation. Keep the behavior/investment guide, references and stable-only release notice current. Owner authorizes direct main rollout for these rebalances, preserving all live bodies/accounts/keys/feedback and experimental standby.

October18 approved R23–R41: read Revision66. Experimental first; preserve both ponds and main standby separation. Final owner steering adds a small atmospheric O2 source and increases air exchange with absolute fluid curl. Photosynthesis remains the main renewable O2 producer. Manual division defaults off; new cells have one ordinary paid-quote leaf. Fusion reabsorbs all donor organs before same-family physical transfer, never consumes selected donors or awards division AP. Preserve explicit individual investment exceptions and clearly expose Use family. Do not revive live-source navigation, global culling, organ Move or broad rendering-speed benchmarks.


October18 induced-current display correction: read the final water-presentation
sections of Revision66. Denser local-current samples stay pale. A separate gold
opposite-style layer shows only actual induced forcing (gold Streamlines over
Wave crests; gold crests over Streamlines), never source migration or ambient
velocity. Full-source visual footprint replaces the22%gold core; physical
forcing parameters stay unchanged. Persistent masks/curves fade in/out, and
conflicting retired curves retain safe geometry through their fade instead of
vanishing. Preserve complete paths, shared noncrossing admission, remembered
Pause choice, functional hardware checks and experimental-only notices.

October18 division-control correction: read Revision67. Instinct toggles a saved local intent readout/arrow, on by default; never switch off AI. Start division now queues one paid birth when blocked/unfunded, highlights Divide and clears only on successful commit or cancellation. It switches that parent out of continuous auto and never arms the daughter. Preserve authenticated exactly-once receipts, saved request state, ordinary1+1AP, material/safe-position/population gates and all cells. Auto divide stays separate in the Divide submenu. Default older display preferences to crests once, then remember deliberate choices. Experimental first; no rendering-speed campaign.

October18 mitochondrial upgrade: read Revision68. Preserve baseline biomass and digestion throughput. Each healthy organ adds50% baseline aerobic ATP, capped5x, funded solely by unallocated finite food energy. Fresh food18, tissue7.5, explicit solar input; no refueling saved parcels, structural lysis or depleted nutrients. Update both CPU/resident GPU, guide/status/science and experimental-only notice; preserve both ponds.

October18 merge selection: read Revision69. Merge zooms smoothly to the recipient neighborhood; direct click/tap chooses only an unattended same-lineage body with a current received family cue. Export IDs/expiries, not new live positions. Revalidate at request/commit; keep no live-source navigation. Dim other cells with actual membrane masks, preserve Cancel/gestures and both ponds. Rename only player-facing modes Internal/External; retain wire/state identifiers. Experimental first; no rendering-speed campaign.

October18 Revision69 follow-up: bound the Family panel to the visible viewport with measured header rows and actual touch dragging anywhere, including portraits, header buttons and margins; retain tap actions and arrow/wheel/focus controls. Disable kinship immunity for offensive particle contacts across CPU/coarse/resident GPU, including self exposure; keep hunter receptors targeting non-family cells. Preserve both ponds; experimental first.

October18 Revision69 receptor steering: free Flight/Hunting/Toward family/Away from family at a dedicated receptor factory; exclude these from AP build tiers/refunds. Hunter selects any detected non-family cell without size/defense filters. Flight avoids real nearby toxins and armed non-family signals. Family receptors use actual local chemical snapshots and survival-first shared behavior; no live-ID navigation. Counterattack remains a productive gland. Experimental first, preserve ponds.

October18 resource-warning correction: read Revision70. Replace the critical-resource text with independent amber ATP-sac and coral actual-membrane blinks at the existing10ATP/30health thresholds. Only the selected living cell signals; preserve empty-sac quantity, anatomy visibility, pause-aware presentation, input and all biology/RNG/saved state. Experimental first; frozen-view investigation remains open pending actual connected-device evidence.

October18 experimental reset policy: on every experimental deploy, replace its
pond with an independent copy of main's latest valid published checkpoint.
Preserve the exact cell/account/lineage/chemistry graph and keys, but issue a new
experimental world identity. Never stop or modify main, copy stable feedback,
alias storage, or overwrite experimental feedback. Archive the experimental
predecessor for rollback; ordinary restarts keep the current experimental pond.
This supersedes earlier preserve-experimental/reset-input deployment rules.

October18 steady merge selection: read Revision71. Retain actual family-pheromone receipts for five simulation seconds for merge selection/approach only, without live position lookup or refresh from queries. Revalidate donor ownership/contact/life. Provide actual-touch Cancel merge and eligible overlap picking. A committed merge gets a bounded1.2s frozen-art pull-in, no extra biology/death or replay on reconnect/pause. Experimental first, refreshed from main under current policy.

October18 air-exchange correction: use local fluid speed rather than curl for enhanced CO2/O2 exchange. Keep the still-water baseline, saturation and finite accounting. Sample only the current staggered group once for both gases; preserve whole-pond coverage. Read Revision71; no claim that this alone diagnoses the reported phone slowdown.

October18 immediate selected merge: read Revision72. Explicit player selection commits in the same authoritative transaction without seeking/contact delay. Preserve recent received pheromone, lineage/ownership/life gates, with no growth-clearance or biomass/AP ceiling; reject without queued navigation. Discard legacy manual approach orders; autonomous fusion remains contact-based. Keep the pull-in art, completion receipt, exactly-once transfer, guide and experimental-only release notice. Experimental first with current fresh-main-copy policy.

October18 mobile6FPS investigation: read Revision73. Keep current-curve admission exact while removing replaced bucket entries, grouping by owner, caching conservative bounds and reusing visit stamps. Retain the935-case all-pairs differential oracle and rendered flow checks. Always record physical/logical viewport, final transform and stroke zoom; the64x64diagnostic window exaggerates curve clearance cost. Native CPU improvements and idle zero-peer server samples do not establish phone FPS. No biomass/AP caps, density/length reduction, world cull or broad rendering-speed campaign. Experimental first under fresh-main-copy policy.

Revision73 touch-current budget: only touch UI adapts current-art density (24/12 initially,16/8 then8/4 after sustained costly rebuilds). Keep full length/32segments and fade retired curves; desktop remains64/32. Recovery takes8seconds of cheap rebuilds. No simulation/density/resource or new user-facing labels. Combined949 assertions include geometry and work-budget behavior; browser diagnostics are local only.

October18 stable promotion: the owner authorizes Revision66–73 on main. Preserve the verified experimental gameplay and both living ponds. Add one stable-only consolidated gameplay notice for the final batch; keep all prior IDs/audiences and acknowledgement order, without replaying iterative experimental notices on main. Retain the documented phone-performance limitation: native/target checks do not establish physical-phone FPS. Use normal hooks, required hardware/state/delivery gates and existing authorized timing-warning policy; no broad rendering-speed campaign or new schedule.

October18 finite-repair incident: read Revision74. Free receptors have zero
represented material; never divide biomass by their zero per-health material
cost, even when no repair is needed. Limit ordinary repairs by time/damage and
positive material cost only. Preserve ATP debit and physical accounting. A
persistent authority must stop before recovery/publication on invalid physical
or resource state or loss of its required GPU, and must not rotate valid saves
with NaN. Intentional infinity deadlines and NaN oral-angle sentinels are valid.
Retain incident generations before same-pond checkpoint recovery; no reset,
unrelated gameplay changes or new performance campaign follows from this fix.

October19 main family-cap hotfix: read Revision75. Limit each lineage to12
living cells through ordinary finite merges, never a reset/cull. Permit paid
division and1+1AP first, then fold only its excess newborn into the parent
before follow selection. Reconcile oversized saved families during authority
ticks, youngest generations first and preferably into their older parent.
Same-generation fallback uses age then ID. Never consume connected selected
donors; retry protected excess later. Only cap merges bypass cues/contact/age/
cooldown. Preserve merge yields/refunds, finite guards, lifetime counts,
same-pond startup all-cell retention, accounts, keys, feedback and experimental.
Update guide and stable-only notice; no rendering-speed campaign.

October19 continuation: Auto divide starts on for new cells. Preserve saved
choices and parent-to-daughter inheritance; one-shot still disables continuous
auto. Maintain the cap, paid resource accounting and1+1AP.
