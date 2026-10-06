# Revision 22 — coherent steering and anatomical editing

Grazing could interrupt an active hunt because each signal reaching the nucleus overwrote the remembered target. Initial sensing ranked hunting above food, but delivery ignored that rank. This revision adds anatomical signal tuning and checks competition at both ends of the signal path.

## Controls and steering

Pause with **Tab**, click a grazing pore, hunting receptor or photosynthetic organ, then click **Steering**. It cycles **100 → 200 → 400 → Off → 25 → 50 → 100%**. Hover the organ to inspect its setting. Each organ has its own strength, inherited by paid offspring and preserved in paused editing. Tuning changes directional salience, not size, range, thrust, intake or resource costs.

Try **hunting 200%, grazing 25%** for a hunter/scavenger. Valid hunting cues retain pursuit despite delayed weaker food signals. When the trail stops refreshing and the existing **1.2-second** memory expires, food can take over. **Grazing Off** leaves suction, digestion and absorption working, but will not navigate toward distant nutrients.

The cell chooses one organ and one direction. A competitor needs more than a **20% lead** to interrupt valid memory; the same margin at reception keeps near-ties from starving the incumbent's refresh signals. Older arrivals cannot rewind newer samples of the same target. Explicit flight always wins. Destroying/removing/disabling the selected organ invalidates its signals and memory.

Base salience remains food **1**, light **0.7**, and hunting approximately **2–3** depending on report age, with existing small distance/target preferences. The new multiplier applies to that salience. No vector blending, concentration calibration, free physical power, extra particle scan, live prey lookup or death oracle is introduced.

## Family protection

Own-lineage pheromones remain excluded at reception. Internal packets and target memory now also retain the **emitted family signature** and reject family pursuit/flight before and after delivery. Paid parent/child fixtures verify inheritance, both sensing directions at maximum hunting strength, adoption, delayed signals and remembered-target invalidation.

Contact and hidden-hunting paths already exclude same-lineage tissue injury. Actual parent/offspring fixtures verify harmless spike contact in both directions while preserving obstruction. This does not prevent acid stress, starvation or attacks by unrelated cells. Friendly spike injury was not reproducible in the current checkout; the exact cause of the earlier reported death remains unknown.

## Tissue comparison

A translucent **Available tissue** blob appears at the top right only in build mode. Selecting an organ displays **Needed tissue** beside it. Their areas use a common tissue scale: equal blobs mean exactly enough. Pink plus **Need more tissue** indicates a shortfall; **Needs AP** distinguishes sufficient tissue with insufficient adaptation points.

Only usable biomass is shown. Body tissue, installed organs and funded offspring reserves are excluded. Purchases, recycling and reserve transfers update the comparison. Large stocks shrink both blobs by the same factor, preserving their ratio; zero stock is an empty outline. Explicit triangle-fan geometry avoids polygon triangulation. There is no permanent pane or numeric biomass readout.

## Normal-mounted organs and quieter interaction

Organ artwork and placement ghosts face smooth outward normals of the rendered membrane curve. Attachment offsets, pore intake/suction centers, secretion outlets, receptor facing and spike contact/sweep axes share that direction. Reversible flagella push along their mounted axis rather than an arbitrary target vector. Detailed and coarse weapons use the same geometry.

Microtubule hover/tension/removal reaches **16 screen pixels** to either side, multiplied by accessibility scale. Nearest-link selection, factory priority and edit-only gating remain intact.

Particle magnification is suppressed inside each living cell and within a UI-scaled **24 screen pixels** of its deformed membrane. The check uses interpolated body/camera poses and periodic wrapping. Tracking releases immediately when the cursor or tracked packet enters this zone. Particle visibility and ecology remain unchanged; pheromones can still be inspected in open water.

## Reaction sparks

Successful oriented two-particle reactions emit a brief **0.24-second white-gold spark** at their wrapped midpoint. All supported pair rules trigger it. Failed collisions, unary decay and secretion do not. Flashes use simulation time, so pausing preserves their phase.

Both chemistry backends sample at most **64 points per call** without limiting actual reactions. A **128-event** ring and one **128-quad** shader batch bound storage/draw cost; expired or offscreen effects are culled. Presentation uses no random draws and changes no material, fluid, chemistry, music or sensing. The frame profiler accepts **--sparks=off** for ablation.

## Validation

Godot **4.7.2** passes the complete suites: **3,788 native assertions** and **2,661 reference assertions**, each with **zero failures** and no script errors. Regression fixtures cover competing arrivals, preference tuning, near-tie stability, zero-steering feeding/current, flight, expiry, inherited settings, family signals/contacts, deformed normals, common-area tissue comparison, wider hover, lens suppression and successful/failed reaction feedback. Both suites include a 90-second simulated ecosystem run.

Rendered checks pass under **OpenGL Compatibility** and **Vulkan Mobile**. Captured tissue availability/shortfall, the steering control and reaction sparks were visually checked.

At **1440 × 900**, the widest playable **80% zoom**, bloom and music enabled, an eight-second dense live run averaged **114.5 FPS** (**8.73 ms mean**, **17.97 ms p95**). It contained 16 cells, six active cells and 11,029–13,789 stored particles, with 2,315–3,656 active. There were **no catch-up/capped frames or skipped audio samples**.

A separate frozen-ecology comparison isolates the presentation cost of **128 simultaneous sparks**:

| Sparks | Mean frame | p95 frame | Draw calls |
| --- | ---: | ---: | ---: |
| Off | 2.430 ms | 2.637 ms | 248 |
| On | 2.524 ms | 2.729 ms | 249 |

The measured difference is **0.094 ms** and one draw call. These frozen-scene numbers are not live-game FPS; they exclude simulation work.

Measurements used **Ryzen 9 9950X / RTX 5080**, NVIDIA 595.91.07, a headless Wayland compositor and two logical CPUs (14, 15) on a shared workstation. They establish current behavior on this host, not a speedup over Revision 21 or results for the owner's RTX 3090 / Threadripper machine.

These constants and normal-axis mobility remain playtest choices. Automated invariants do not establish human balance or identify the exact circumstances of an earlier family death. Scientific motivation and honest abstractions are retained in [references.md](../references.md#competing-chemical-cues-and-anatomical-signal-strength).
