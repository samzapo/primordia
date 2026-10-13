# Revision 44 — persistent multiplayer and a browser client

This revision runs one private, authoritative native GPU world on `samzapo-desktop`. The browser presents real server state with WebGL 2. Transport, external reactions, intracellular cycles, paid emissions, physiology and offscreen ecology keep their existing particle ownership rules. The browser never advances biology or supplies resource values.

## Accepted direction

Gameplay objectives, timed expedition endings and progression design are deferred. The shared service uses the sandbox evolution mode, continues after the selected cell dies, and does not introduce scripted replacement populations. Objective and balance tests are held until the owner asks to restore them. Physical, conservation, networking, recovery and rendering checks remain enabled.

Every active camera contributes its fixed widest-view detail footprint. Native transport, cell activity, fluid activity and GPU exchange use the union. Streaming adds the existing chunk/halo preparation; regions outside every camera use the existing cold/coarse methods. The world continues with no clients. Missing view updates expire after ten seconds, so an inactive tab cannot retain detailed simulation indefinitely. Display zoom does not improve feeding. Camera movement waits for prepared particle ownership before publishing detailed water.

Opening assembly or chemistry editors never pauses the shared world. Edits run on the authority at a tick boundary, validate lineage ownership and epoch/edit versions, use ordinary tissue/AP costs, and retain bounded idempotency receipts. Successful edits and receipts are checkpointed together before acknowledgement. Local single-player retains its existing assembly pause and CPU default.

A powered-off host does no simulation. Restart restores the last valid checkpoint and continues from that simulation time, without wall-time catch-up or free resource accrual.

## State and network contracts

Eight accounts can claim distinct existing living lineages using a private invitation. Creation does not grant a new cell or resource stock. A per-browser bearer identity resumes the same account; there is one active connection per identity. Account ledgers, selection, command sequence, random streams, cell chemistry, skeletons, membranes, cold packets, GPU-owned packets and emission/transfer escrow are saved as a data-only object graph with shared references preserved. Clients send bounded JSON actions; the server never deserializes client objects.

Two SHA-256 checked checkpoint generations use fsync, atomic rename and directory fsync. A corrupt newer generation falls back to the older valid one. Existing invalid storage fails closed rather than creating a replacement world. Persistent formats are versioned; future incompatible code needs an explicit migration. The private state directory must be retained separately from releases.

The GPU publishes a deduplicated view union at up to ten updates per second with one asynchronous compact pose gather in flight. Browser shaders interpolate real particle position/angle and exclude visual interpolation from membranes. The existing procedural particle atlas, cell art, water and chemistry editors are reused. Ordinary publication does not export chemical metadata or checkpoint the full world. Checkpoints deliberately reconcile complete ownership. Client outbound queues and frame sizes are bounded; slow clients can skip visual snapshots while the world keeps advancing.

## Deployment

`tools/deploy.py` stages only committed authored source into a revision-named private release and builds native libraries and browser assets on the target. Checksum-pinned Godot 4.7.2 and its web templates live in a private runtime. Generated libraries, imported projects, browser packages and caches stay out of Git and are never copied from a CI checkout into releases. Wired routes and aggregate memory/build pressure are checked before and during long provisioning/build steps.

The independent user service is `primordia.service`; it supervises a private Xvfb display, the real Vulkan GPU authority and the HTTP/WebSocket gateway. Port **8766** serves the browser, `/ws`, `/health`, `/metrics` and `/api/network`. The world socket is **8767**, bound only to loopback. GSOC remains on 8765. User-manager lingering permits startup and continued operation without an interactive login. A service lock prevents two authorities from writing the same world.

The deployment workflow targets the authorized working branch. It performs native compilation, checkpoint/network checks, real GPU integration under its unattended display, web export, candidate health checks and a separate post-job verification. Candidate failure restores the prior code/service while preserving saves. The host telemetry workflow includes read-only world metrics.

## Practical bounds

This remains one bounded 4096 by 2560 toroidal habitat with at most eight camera regions and 100,000 GPU slots. Capacity, frame sizes, cell renderer bounds and preparation queues are explicit. Larger/unbounded worlds, load distribution, host-downtime catch-up, browser-side compute and cross-platform bitwise equivalence are future work.

The service uses the same private HTTP/LAN access model requested for GSOC. The invitation and saved identity are credentials for that private connection; public Internet access requires HTTPS and an access policy. A public hostname is unnecessary for this revision.

Measure actual simulation/wall ratio and view load. Passing short integration checks establishes ownership and service operation, not sustained 50k/60 FPS or phone performance. Checkpointing can pause a frame; the latest telemetry reports its cost.
