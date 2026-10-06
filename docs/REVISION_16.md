# Revision 16 — establish a continuing lineage

The expedition now has an explicit goal: establish a lineage through three ecological crises. Reproduction is an early strategic choice, and losing a body hands management to existing family in the same habitat.

## Goal and readable progress

The opening message gives the chapter objective and first action. The nucleus shows three progress arcs; its hover description gives the current task, viable seconds, crisis deadline, next tide and forecast. The offspring bud shows reserved tissue/ATP, dormant bodies and a readiness pulse. These are cell-local controls, with no new permanent HUD panes.

| Phase | Simulation time | Pressure and objective |
| --- | --- | --- |
| Emergence | 0:00–2:00 | Establish feeding, then prepare a successor. |
| Lean Current | 2:00–6:00 | Reduced light lowers production; hunting arrivals make feeding, protection or avoidance matter. |
| Chemical Bloom | 6:00–10:00 | A named arriving rival buys toxin anatomy. Neutralization, repair and avoidance offer different responses. |
| Long Dusk | 10:00–13:30 | Light falls toward 32%, then 25% of the habitat field. A descendant must sustain its own metabolism. |

Each crisis requires **60 observed viable seconds**: at least 50% health, 10 ATP and feeding/carbon fixation within the previous 15 seconds, while the current body is actively simulated. Seconds can accumulate across interruptions; they are not a continuous survival streak. The first two crises can be earned by any managed family member. Long Dusk requires generation one or later.

At 13:30, all three crisis records must be complete, and the current descendant must have accumulated 60 viable seconds in its own tenure and still meet the viability conditions. Handoffs preserve earned crisis progress but reset the new body's personal viability observation. Parking a dormant body offscreen cannot earn time or satisfy the final check. Looking away does not stop the expedition clock.

This replaces the old automatic 12-minute division and immediate player-death failure. The expedition still has a definite endpoint; a larger campaign is not implemented.

## Reproduce before you need to recover

Enter the cell with Tab and click its offspring bud:

- **Fund / reclaim:** transfer up to ten tissue and ten ATP into or out of reproductive reserves.
- **Release successor:** spend the quoted resources to place a juvenile in safe nearby water. It lives autonomously while management stays with the parent.
- **Store dormant successor:** pay the same cost to bank a complete dormant body.
- **Follow generation:** continue managing an existing living relative. The family tree also lets you choose a living branch.

The quote covers a healthy copy of current organs and inherited microtubules, a juvenile body, 12 usable tissue, six stored food and eight carbon, less any body tissue partitioned from the parent. Sixty reserved ATP covers 40 in the child and 20 spent on division; up to twelve oxygen transfers if available. Reproduction grants no AP refund or new blueprint roll.

Birth commits the parent's paid edits before transferring material. Editing then continues on the correct depleted body. Following family works both while editing and through history during observation; it cannot leave a hidden build state that freezes the world. The new body and parent redraw immediately.

There may be **four living family members** and **three dormant bodies**. Each additional body has its own actual inventory. This is a resource allocation decision, not a repeatable respawn token purchase.

## Death continues the habitat

A new expedition includes one separate, accounted generation-zero founder reserve. It is part of the initial population inventory, not a descendant achievement or material created on death.

When the managed body dies:

1. Its retained material enters the ordinary death-release chemistry once.
2. Management follows the youngest living family generation, preferring the healthier body on a tie. That body is neither healed nor teleported.
3. With no living family, the oldest funded reserve searches near its stored location for safe water. If blocked, it waits without losing the body while the habitat and crisis clock continue.
4. Only exhaustion of living family and reserves ends the expedition early.

AP spending, learned choices, drafts, crisis records, enemies, particles and world time carry on. The camera reattaches to the successor, and the existing inherited musical motif continues without resetting the sample clock. Personal viability begins again for the new managed body.

Dormant bodies are deliberately outside active physics: no upkeep, particle production, damage or offscreen reproduction. This bounded seed-bank abstraction is explained alongside its biological motivation in [references.md](../references.md#dormant-reserves-and-continuing-lineages).

## Decisions and rival composition

Passive income is now **two AP** at each of the first five tide changes. One optional challenge per tide can earn **two more** at its deadline, including the transition into the final tide:

| Challenge | Requirement on the accepting body at the deadline |
| --- | --- |
| Growth | Ingest at least 18 external material, retain a net 18 organic mass increase, and finish at ≥60% health. |
| Feeding | Take in external resources or fix carbon totaling at least 12, and finish at ≥60% health. |
| Stability | Finish with a continuous 30 seconds at ≥60% health and ≥25 ATP. |

Choose within the first 90 seconds of the tide. The same body must be managed at the deadline; handing off does not create another challenge or draft. Ordinary construction, recycling, repair and paid blueprint specialization retain their costs.

Balanced habitat reserves one introduction for 2:30, 6:30 and 10:30. Actual arrival still requires valid space. The first eligible introduction after each crisis warning becomes **Spindle** (protection/feeding), **Cinder** (toxin), or **Bastion** (protection/repair), buying its additions with ordinary tissue. Existing exposure-driven counter-adaptations remain bounded. A name appears on hover or in sense view; functional organs and particles communicate the threat, not occupation-based body coloring or hidden immunity.

This changes composition and timing rather than increasing the base NPC population or adding particle sources.

## Shared biology, player-specific expedition

Other cells obey the same physiology, fluid/contact/chemical rules, anatomical material costs and pheromone-only perception. AP, draft choices, family management, dormant reserves, crisis achievements and persistent discoveries belong to the player's lineage.

NPCs do **not** reproduce or maintain a dormant bank in this revision. Their population uses the habitat's bounded arrival/replacement events, with explicit material accounting. Their movement and activity remain anatomy-driven, not a reproduction behavior tree. The owner explicitly accepts this distinction and requested that it be stated.

## Family history and remembered choices

The nucleus's **Family & goals** branch shows linked parent/child records, generations, active/living/dormant/dead state and the last damaging process on death. Settings also opens history during observation or after defeat. It pauses biology without enabling anatomical editing; right-click closes it.

History retains up to 128 family records per expedition and 64 expedition summaries. The local `user://lineage_history.json` file also retains discovered blueprint identities. A remembered blueprint can replace the current tide's ordinary draft choice. It grants neither installed anatomy nor extra currency/stat multipliers.

Writes use a temporary file and rename, validate fields on reload, and retry a failed save with a visible notice. Headless suites, benchmark and capture modes do not touch player history. Tests use a separate disposable JSON fixture.

**This is not a full world save.** Relaunching the application or explicitly starting a new expedition rebuilds the habitat while retaining history and blueprint options. Ordinary in-session death preserves the current habitat. Body colors and the musical motif follow existing lineage rules.

## Validation

Godot **4.7.2**: full native suite **3,240 assertions**, reference suite **2,181**, zero failures. The rendered interface passes **141 checks on each of Vulkan Mobile and OpenGL Compatibility**. Compatibility uses llvmpipe; these are correctness checks, not NVIDIA OpenGL speed measurements. Import and whitespace checks pass.

Coverage includes paid material/ATP/oxygen partition, founder inventory, living-family preference, blocked hatching, bank capacity, no death-driven AP/draft refresh, independent viability, explicit terminal reasons, stored-body inactivity, rival costs and history persistence/corrupt-field handling. Scene tests cover birth and handoff during editing, following family outside editing, camera/audio continuity, terminal history, immediate affordability updates and tooltip bounds at 175% text size. Nucleus/family captures were inspected; stale tooltip height after text reflow was corrected.

### Full expedition probes

The final `careful` policy in `tests/economy_playtest.gd` uses ordinary purchases, mutations, reserves and autonomous movement at the playable **80%** view, with actual 60 Hz steps. It installs photosynthesis, prioritizes early reproduction, reclaims reserves when ATP is low, and uses the available paid defensive/efficiency choices. It injects no resources or health, does not reposition cells and does not alter crisis counters.

| Seed | Final generation | Crisis viable seconds | Final health / ATP | Result |
| --- | ---: | --- | --- | --- |
| 41 | 1 | 231 / 157 / 162 | 45.5% / 0 | Lost: health, ATP and recent metabolism were below the final requirements. |
| 20261004 (default) | 1 | 214 / 238 / 209 | 100% / 19.8 | Won at 13:30; paid shade-leaf and enzyme-pore specializations supported the lineage. |

Earlier exploratory grazing, hunting and photosynthetic policies exposed the tradeoff between buying starting anatomy and accumulating reproductive tissue. Reproduction-first variants produced early successors and exercised real death handoffs, but their sampled seed-41 expeditions lost. These are a few scripted policies, not a difficulty curve or proof that every diet is balanced. Human playtesting, especially successful pure-grazing and hunting strategies, remains necessary.

### Widest-view rendering cost

Workstation: Ryzen 9 9950X / RTX 5080, 1440×900 Xvfb, Vulkan Mobile, native simulation, Dummy audio driver. Each live fixture uses 12 warm-up frames and 36 measured frame intervals; workloads ran serially after the long tests. Dense starts with four times the packets; growth with 256 times unspent player biomass. Family endows and pays for three real births, reaching the four-living-family cap without changing the NPC population.

CPU tick is the displayed smoothed physics-step measurement at the end, separate from whole-frame median/p95. These short live samples include scheduling and evolving-state variation; they are not controlled audio-cost estimates or a 60 FPS acceptance pass.

| Fixture | Bloom | Music-off median ms | Music-on median ms | Music-on p95 ms | CPU tick ms (on) | Audio skips (on) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |

| Normal | Off | 33.366 | 32.751 | 33.867 | 5.752 | 0 |
| Normal | On | 33.343 | 33.050 | 36.279 | 5.784 | 0 |
| Dense | Off | 99.820 | 102.829 | 142.341 | 9.861 | 55 |
| Dense | On | 99.565 | 100.380 | 133.638 | 9.754 | 60 |
| Growth | Off | 46.893 | 47.152 | 48.388 | 5.729 | 0 |
| Growth | On | 47.058 | 47.363 | 53.679 | 5.721 | 0 |
| Family | Off | 38.954 | 44.975 | 47.154 | 7.953 | 0 |
| Family | On | 45.630 | 49.498 | 51.239 | 7.876 | 0 |

Normal/growth/dense medians remain in the broad range recorded in revision fifteen. A full family raises active cells from six to nine in these fixtures and CPU ticks from roughly 5.8 to 7.9 ms. **Wide-view performance is still inadequate:** dense frames are about 100 ms and starve audio refills; music-off remains slow. The new family fixture reaches roughly 45–50 ms with music. No improvement or target-frame-rate claim is made.

Dormant reserves do not add simulated bodies; family/history bookkeeping is bounded. The live-family cost is real and is not hidden by freezing visible cells, lowering the 80% camera limit or deleting particles.

The owner's Steam Godot / RTX 3090 / Threadripper machine and physical audio device remain untested. Full habitat saves, NPC reproductive AI, a larger campaign and further rendering optimization remain outside this revision.
