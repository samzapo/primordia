# Revision 19 — living ecology outside the camera

Living cells now advance offscreen instead of freezing. Their physiology and internal parameters stay shared with visible cells; coarse encounters consume real resources. Killed cells lyse into particles, and predators/scavengers collect that material through the same absorption system. There is no private food award for a kill.

## Model

- Detailed biology runs at full speed throughout the view and the existing cell-extent halo. Outside it, each cell accumulates actual elapsed time and updates on a staggered one-second schedule. Eight bounded internal steps per second reuse ordinary metabolism, repair, sensing, secretion, photosynthesis, propulsion and fluid coupling. Shape solving and detailed collision iteration resume in the halo.
- Nutrient, oxygen and carbon absorption sample real particles in a wider region. Rates depend on pore collection area, flow-relative motion and pumping; the swept-area coefficient is calibrated at 1.7. Actual gut/storage limits still apply. No pore means no nutrient absorption; a solid stem blocks collection across it, and hidden collection cannot take visible particles.
- Hunting requires a functioning hunting receptor and an existing pheromone-derived intent. Bodies must meet within the hidden contact bound, with no solid stem between them. Spike facing, working anatomy, size, closing speed, defenses, repair capability, mobility and explicit flight affect the hazard. Expected working spike contact spends real ATP. The death probability is 1 - exp(-rate * elapsed); surviving a roll does not receive damage or a hidden stat adjustment. A successful attack imposes a three-second handling interval.
- The complete corpse and retained oxygen become ordinary particles, once. There is no ownership reservation for the predator. Uptake, storage, metabolism and competition determine who benefits. Existing population replacements still have explicitly accounted input material; this revision adds no replacement bonus or NPC reproductive AI.
- Photosynthesis and secretion use event counts rather than a single yes/no opportunity per large step. This avoids systematically starving those pathways offscreen. Every event still pays the usual substrate, biomass and ATP costs.
- Chemistry in patches around hidden living cells uses the existing oriented pair rules, toxin/decoy effects, acid carriers and buffers. Per-packet chemical timestamps prevent overlapping patches from double-processing elapsed time. The acid field also receives coarse transport. Banked successors remain explicitly dormant.
- Camera entry settles pending time once, including motion costs. Editing pauses both levels. Coarse random draws are separate from the foreground stream; pheromone reports remain immutable, backdated emission snapshots with ordinary expiry.

## Paired balance trials

Godot 4.7.2 on the shared Linux workstation. Twelve validation seeds (1100–1111), 30 simulated seconds each, identical starting anatomy/material for each on/offscreen pair; 168 primary runs across seven fixtures. Fixtures use an 80% view, disable solid plants to isolate physiological/encounter balance, and give no ongoing resource source or replacement endowment. Separate tests cover obstacle blocking. These short ensembles measure approximation bias, not whole-expedition difficulty or proof of statistical equivalence.

All cells survived these stocked short fixtures. Final biomass and food uptake means follow. Values are visible → hidden; starting biomass is 40.

| Fixture | Biomass | Nutrients eaten | ATP | Prey killed |
| --- | ---: | ---: | ---: | ---: |
| graze | 55.20 → 55.99 | 24.23 → 25.35 | 129.04 → 129.82 | 0% → 0% |
| scarce | 40.95 → 40.82 | 3.62 → 3.30 | 85.38 → 84.03 | 0% → 0% |
| photo | 52.72 → 52.37 | 0.00 → 0.00 | 113.98 → 114.99 | 0% → 0% |
| hybrid | 63.87 → 64.24 | 23.73 → 26.58 | 135.88 → 135.86 | 0% → 0% |
| hunt | 55.04 → 55.76 | 22.41 → 23.36 | 145.59 → 134.40 | 83% → 75% |
| hunt_armored | 53.25 → 50.83 | 20.59 → 20.11 | 121.58 → 86.44 | 58% → 33% |
| hunt_flee | 46.12 → 49.39 | 5.51 → 13.57 | 81.75 → 91.15 | 42% → 33% |

Photosynthesis-only fixed carbon: 23.40 → 22.81. Hybrid fixed carbon: 15.25 → 12.30. The maximum accounted organic-material error was 2.3e-12. Respiration losses and explicitly recorded inputs are included in that ledger.

Average final biomass differs by under 8% across these fixtures. That does **not** mean every rate matches: the armored hunting fixture has fewer hidden kills and lower hunter ATP; successful hidden encounters with fleeing prey leave more accessible food than the visible trajectory often collects. The latter produces about 53% more net biomass gain despite a 7% difference in final biomass. No role-specific stat correction conceals these differences. Twelve trials give wide binomial uncertainty; default hunting kill estimates should not be read as exact probabilities.

Removing direct corpse transfer eliminated a privileged reward path and improved ordinary hunting intake alignment. The wider capture area remains an approximation of missed encounters; future tuning should compare longer campaigns, moving cameras, population competition, chemical strategies and additional anatomy.

### Scheduling sensitivity

Twelve identical seeds per interval, hidden-only trials, 30 seconds. Metabolic substeps remain bounded; the cell visit interval changes.

| Visit interval | Grazer biomass | Photosynthetic biomass | Hunter biomass | Hunter kill fraction |
| --- | ---: | ---: | ---: | ---: |
| 0.5 s | 55.76 | 52.46 | 57.08 | 92% |
| 1 s | 55.99 | 52.37 | 55.76 | 75% |
| 2 s | 55.31 | 53.31 | 58.94 | 100% |

Resource growth is stable across this range; hunting is more sensitive to delayed perception and encounters. Keep the default at one second. The isolated constant-hazard test also checks the analytic survival probability at 0.25, 1 and 2 seconds; it does not prove that moving spatial encounters are timestep-independent.

## Validation and performance

Final full suites: **3,569 native assertions and 2,510 script-fallback assertions, zero failures**, including 42 focused ecology checks. Coverage includes real-time debt/camera transitions, editing pause, starvation, capacity and mass accounting, lysis/scavenging, plant barriers, no visible statistical kills, pheromone/receptor requirements, orientation-preserving neutralization/competition, per-packet chemistry time, event multiplicity and an analytic hazard ensemble. Existing tests also exercise populated 90-second ecosystems, contacts, family succession, chemistry parity and the interface.

Performance host: AMD Ryzen 9 9950X, RTX 5080, Linux, Godot 4.7.2. This is shared-host evidence, not measurements on the player’s RTX 3090/2990WX. Runs were serial.

CPU ablation: 600 measured ticks after 60 warmup ticks, **80% effective zoom**, native backend. Dense multiplies starting packets by four; growth multiplies starting player biomass by 256 without zooming out further. The comparison disables only offscreen biology; coarse background transport stays enabled.

| Fixture | Frozen biology median / p95 tick ms | Coarse biology median / p95 tick ms | Mean coarse-biology phase ms |
| --- | ---: | ---: | ---: |
| normal | 6.40 / 7.16 | 7.12 / 11.66 | 0.68 |
| dense | 12.61 / 15.65 | 13.16 / 29.25 | 2.18 |
| growth | 6.76 / 7.20 | 6.89 / 11.38 | 0.67 |

Rendered measurements: Vulkan Mobile, 1440×900, 80% effective zoom, 36 sampled frame intervals per fixture; each range covers bloom off/on. These are live presentation frames, not headless CPU tick times.

| Biology / music | Normal median frame ms | Dense median frame ms | Growth median frame ms | Dense audio skips |
| --- | ---: | ---: | ---: | ---: |
| frozen / off | 35.0–35.6 | 138.5–142.4 | 51.4–51.7 | 0–0 |
| frozen / on | 35.2–35.6 | 139.4–142.2 | 51.8–51.9 | 130–140 |
| coarse / off | 42.2–44.4 | 165.6–201.3 | 58.7–63.8 | 0–0 |
| coarse / on | 40.0–43.0 | 163.5–166.7 | 59.0–59.1 | 222–238 |

Coarse biology costs about 0.7 ms per tick in the normal/growth phase measurement, but dense patches are burstier (2.2 ms mean phase, 29 ms p95 complete tick). The simple paired one-/two-cell fixtures ran around 3–4× cheaper hidden than visible; that comparison includes their local particles and is not a whole-game FPS claim.

**Performance limitation:** rendered frames remain well above a 16.7 ms budget, and this feature adds cost relative to frozen biology. Dense scenes still underrun audio. This revision provides ongoing offscreen life at reduced simulation detail; it does not solve the existing wide-view rendering bottleneck. The density-dependent background chemistry/absorption bursts are a concrete next optimization target.


## Scope and remaining approximations

This is shared physiology with reduced spatial/temporal resolution, not full distant soft-body physics. Membrane shape is rescaled with growth but its constraints are not solved between visits. Coarse toxin exposure approximates encounters; receptor binding and particle pair chemistry retain orientation. Particle chemistry far from every living cell still defers until a cell or the view approaches, and coarse pair sampling misses encounters between endpoints. Empty distant chemistry is not globally simulated at full fidelity.

Player AP, drafts, crisis visibility requirements, paid dormant successors and family progression keep their existing scope. The player receives no offscreen physiology exemption. A free camera does not earn observed-crisis progress while its current body is elsewhere.

### Reproduce

Run the normal native and script suites with tools/test.sh and PRIMORDIA_BACKEND=script. The authored tests/ecology_balance.gd accepts --modes, --seeds, --seconds, --seed-start, --views=hidden and --period. Example arguments: --modes=graze,scarce,photo,hybrid,hunt,hunt_armored,hunt_flee --seeds=12 --seconds=30 --seed-start=1100. tests/visual_benchmark.gd accepts --camera=play --mode=live --zooms=0.8 --biology=coarse|off --music=on|off; retain the independent background-transport switch.

Scientific motivation and simplifications: [coarse ecology and lysis](../references.md#coarse-ecology-encounter-limits-and-lysis).
