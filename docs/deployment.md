# Primordia private deployment

Primordia follows the existing GSOC user-service pattern on `samzapo-desktop`, with an independent port and state directory. Open **http://192.168.1.25:8766** once for certificate setup, then use **https://192.168.1.25:8766** to play on the home network. `/api/network` lists current physical-interface home URLs if the address changes.

The first sign-in needs one of the owner-issued personal access keys. Give one key to each player. The browser stores an opaque account identity locally and resumes it on reconnect; using the same access key on another browser resumes the same lineage and disconnects the previous browser. The owner retains the plaintext key list privately outside source; the target stores only its hashes in `~/.local/share/primordia-deploy/access-keys.json`. Later key batches append to the registry instead of replacing earlier keys. See `docs/remote_access.md` for provisioning and router inspection. This revision does not expose administrative world resets or client-selected resource balances.

## One-time phone HTTPS setup

The same port handles the plain HTTP setup page and the HTTPS game. Download `primordia-lan-ca.crt` from the setup page. On Android, search Settings for **Install a certificate**, select **CA certificate**, and choose the downloaded file. Depending on the phone, this is under Security & privacy, More security settings, or Encryption & credentials. Open the HTTPS game address after installation. Installing the CA establishes trust; accepting a browser warning is not the setup procedure.

The CA signing key stays private in `~/.local/share/primordia-deploy/tls/authority/`. Retain that directory with the world state: replacing the CA requires every device to install a new certificate. Its name constraints permit private IP ranges and localhost, excluding public hostnames. The server certificate includes current physical-interface LAN addresses and loopback; it renews automatically without replacing the CA. `/api/network` lists HTTPS addresses. Other devices can import the same CA into their browser/system trust store. Remove **Primordia Private LAN CA** from user-installed trusted credentials to revoke local trust.

Godot 4.7.2's launcher requires a secure context even for the single-threaded build, and its audio initialization uses AudioWorklet. A plain HTTP LAN IP fails this requirement; localhost testing alone does not cover LAN access. Production assets and WebSockets require TLS. The public CA certificate and read-only health remain available over HTTP on the same port for bootstrap and local supervision.

Phone key entry uses Godot's browser keyboard bridge, enabled by `html/experimental_virtual_keyboard` in the Web export preset. The sign-in field requests a password keyboard so the browser masks the key. Mobile validation must include a touch followed by browser text insertion; desktop key events alone do not exercise this path.

## Continuous deployment

Pushes to `main` run `.github/workflows/deploy.yml`. The guarded runner is `samzapo-desktop`. The source has its own revision branch and Git worktree in `~/.local/share/primordia-deploy/releases/samzapo--persistent-multiplayer--<commit>` before changing `current`. The Actions process installs/restarts the service and exits; systemd keeps the world running. Builds and isolated candidate checks finish before the short checkpointed service switch. A second job proves the service survives Actions cleanup and an independent saved-world restart. Stable deployment also checks that the experimental process, pond and keys remain intact, retains private feedback in both instances, and verifies public HTTPS/WSS assets for both paths.

Godot and templates are checksum-pinned in `tools/toolchain.json`. Large dependencies download only over verified wired routes. The target needs Python 3.10+, curl, Git, CMake, a C++ compiler, Xvfb/xauth, a user systemd manager and Vulkan hardware. The deployer enables lingering for its own user and verifies it. It does not change GSOC configuration or use sudo.

State, access-key hashes, TLS authority and service credentials remain under `~/.local/share/primordia-deploy/`, outside release/checkouts. The service holds an exclusive world lock. Do not start another authority on those saves. Systemd sends termination to the supervisor first, allowing the world to write its final checkpoint before stopping its private display. Restart resumes saved simulation time and increments the connection epoch. A forced crash can lose uncheckpointed ordinary simulation since the last 30-second save; acknowledged successful edits are saved before acknowledgement.

## Operator commands

On the target, use:

```sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user status primordia.service
systemctl --user restart primordia.service
systemctl --user stop primordia.service
curl --fail --cacert "$HOME/.local/share/primordia-deploy/tls/authority/ca.pem" https://127.0.0.1:8766/health
```

The gateway exposes read-only bounded telemetry: build revision, world ID/epoch/tick, simulation time/wall ratio, camera and packet counts, GPU/backend status, checkpoint age, full reconciliation cost and file-write cost and tick-cost percentiles. It also reports peak per-phase tick costs since the previous metric sample, detailed-view readiness, successful snapshot sends, publication state and stream admission/eviction queues. The host-telemetry workflow also records hardware/load samples. Logs never contain invitations, bearer tokens or request bodies. Source, saves and installation media are retained; generated artifacts are rebuilt and not published in Git.

A failed candidate restores the previous service/release without deleting saves. Retain `access-keys.json` with state and the private CA; do not replace live identities when preparing another release. Current schema-compatible releases can read both checkpoint generations. For a future incompatible state format, prepare a migration and an independently retained compatible checkpoint before deploying. If both generations are invalid, startup refuses to reseed; repair/restore storage deliberately.

## Validation

`tools/test_network.sh` checks exact state identity/particles/RNG and real two-client CPU authority behavior. `tools/test_network.sh gpu` adds hardware Vulkan fixtures under private Xvfb displays, including a full world and a two-Hz observer stress case, and rejects software rendering or CPU fallback. `tests/test_web_gateway.py` verifies trusted HTTPS, certificate rejection, private key permissions, HTTP bootstrap and encrypted duplex snapshots. Deployment readiness and post-job restart checks use verified HTTPS with the retained CA. `tools/build_web.sh` exports the browser client from an automatically prepared source-only project. `tools/test.sh` retains the broader native physical suite, explicitly selects the CPU reference for headless scene fixtures, and invokes networking checks after it. Normal play and deployment retain the resident GPU default.

Gameplay, objective and balance groups are enabled through `tests/test_policy.gd` following the owner's October 15 restoration. Test harnesses use finite authored fixtures; they do not spawn free material in the product.

### IPv6 browser connections

Godot 4.7.2 reconstructs WebSocket URLs without restoring IPv6 host brackets ([upstream report](https://github.com/godotengine/godot/issues/123457)). The browser client corrects only its registered malformed address before calling the browser WebSocket constructor. Already valid URLs, native clients, protocol/binary data and certificate validation retain their ordinary behavior. Run `node tests/test_websocket_address.js` for address and transport-contract checks; browser verification must also sign in over a trusted bracketed IPv6 origin and receive advancing snapshots. A failed WebSocket connection alone does not establish a certificate failure.

Browser exports automatically give the game pack a content-specific filename through `tools/version_web.py`. A changed client therefore downloads through a new `mainPack` URL, while the large engine runtime can be reused. HTML and runtime assets use `Cache-Control: no-cache` to revalidate on reload, and health/account setup responses retain `no-store`. Run `python3 tests/test_web_version.py` and the TLS gateway fixture to check update delivery; both run during network/CD checks. Generated manifests and renamed packs remain build outputs.

A newly changed camera waits for a subsequent detailed simulation tick before GPU publication. Repeated identical camera reports retain that readiness rather than postponing it; the client sends camera changes at up to five per second and idle keepalives every two seconds. The slow-observer fixture deliberately repeats identical reports faster than simulation ticks and requires real particle snapshots, paid edit receipts and continued zero-client simulation. This cadence is confined to the fixture, and does not change production biology or particle density.

### Reduced multiplayer particle resolution

The October 14 owner correction sets `visible_target=700`, `seed_packets=1` and `parcel_scale=10`. New worlds use 3,760 external parcels, one tenth of the former 37,600, with tenfold starting amounts so the conversion does not remove material. External emission quantum is 1.8 and the shared native/reference/GPU aggregation limit is 5. Intracellular emission quanta also scale by ten; every pathway still consumes nearby physical particles.

On the first load of an older shared checkpoint, the authority retains its validated generation as `before-particle-resolution-v1.pworld` outside the rotating pair. It then groups at most ten compatible ordinary nutrient/oxygen/carbon/waste parcels within the same 256-unit storage chunk and matching owner, product metadata and elapsed-time clocks. Pheromones and specialized secretions retain their records. Within each cell, only matching species/source/compartment parcels in an eight-unit neighborhood coalesce; installed catalytic particles remain distinct. Amounts, food-fuel capacity, intracellular fuel and weighted linear momentum are retained, and no random stream advances. Weighted representative positions make this an explicit coarser resolution rather than exact trajectory equivalence. Species/source/chunk boundaries and partially filled groups mean a saved world's count need not become exactly one tenth.

The checkpoint records the conversion version and counts. Later restarts do not repeat it. Metrics report the retained conversion, parcel scale and visible target along with phase costs; the target is a density setting, not a population cap. Gameplay objectives and balance acceptance remain held.

### Phone zoom and view pause

After sign-in, touch devices show Pause, − and + at the upper right, with a Follow toggle below. Joining or reconnecting starts centered on a living focus cell when one exists. Follow stays labelled Follow, highlighted when active and dim when off. Tap it to unlock the view or restore an upright cell-centered view. An ended lineage observes an existing living cell without ownership or resource changes. Two fingers immediately unlock the camera and anchor to world coordinates; translate, twist and pinch/spread together to pan, rotate and zoom. Both anchors remain under their fingers within the existing 0.8–12× zoom limits; at a limit, the gesture centroid stays anchored. One-finger dragging does not move the camera, and lifting one of the two fingers stops camera manipulation without a jump. The −/+ buttons remain available.

Targets are at least 48 CSS pixels tall and retain their size on a high-density canvas. Gestures cannot select anatomy, begin a microtubule or move a cell. World drawing, background sampling, picking and cell-local controls share the same rotated projection. The authority receives bounded rectangles covering the rotated viewport and its widest-view detail footprint, so corner regions use the ordinary high-fidelity camera simulation. Zoom retains its fixed widest-view detail rule. Cell drawing and follow position use the same snapshot interpolation, including coarse server cells; the selected body remains available for immediate refocus after panning away.

Pause freezes this browser's displayed cells and particles. The authority keeps running for everyone, and this client continues its connection and buffers only the latest full snapshot. The label reads “View paused · world continues”; Resume immediately presents the latest received state without replaying missed frames. Zoom remains available while paused; cell edits require Resume. A reconnect starts in the live state. Native single-player Pause stops its local simulation, and P is a keyboard alternative.

`tests/touch_zoom_run.gd` checks gesture routing, combined anchor alignment across wrapping seams, projection/picking, zoom limits, follow/free and initial/refocus framing, cancellation, touch target size, local pause/resume and bounded shared-view buffering. It runs in network/CD correctness checks using the explicit CPU reference. Resident hardware GPU gates remain required. Gameplay objective and balance tests remain held. Broader phone editing gestures remain deferred.

### Perception domains

The button below Follow switches to the named destination: Interoception or Exteroception. Outside view draws external chemical packets and runs hidden intracellular chemistry on its retained offscreen clock. Inside view draws the focused body's intracellular packets, hides exterior particles and greys/dims every pixel outside its actual membrane; exterior chemistry uses the ordinary offscreen path where no other Exteroception camera requests detail. Inside snapshots continue without an external GPU gather. Mixed viewers preserve the union of each domain's detail interests. I is the desktop shortcut. Pause remains a local view freeze in both modes.

Follow camera focus is separate from the owned lineage. If that lineage has ended, a surviving existing cell is available for observation without adoption or editing rights. Read-only host telemetry includes a bounded saved-selection report; it reads checksummed graph references in an isolated scratch project without restoring objects or touching live state. It excludes account keys, bearer tokens and identity hashes. See [Revision 45](REVISION_45.md) for independent-clock and recovery contracts.

### Accepted sign-in and dense snapshot delivery

After authentication, the client saves its bearer identity, clears and hides the personal key field, and replaces Sign in with a status saying Signed in while camera water prepares. Repeated sign-in cannot restart an open/connecting session. The first complete snapshot dismisses the status automatically. Ordinary transport retries reuse the saved identity; only an explicit credential rejection requests a key again. Reloading the current client resumes the saved identity.

Browser hello negotiates compact cytoplasm and snapshot acknowledgements. The compact presentation graph stores the eleven current internal packet fields in 80-byte lossless rows, with a per-chemistry species table; IDs/source/compartment remain signed 64-bit, quantities/fuel/heading remain double precision and Vector2 coordinates retain their original precision. Unknown future packet metadata uses the full graph rather than discarding fields. Checkpoints keep the original data-only dictionary format and authoritative particle arrays are never modified for publication.

Both decoded and compressed protocol frames retain the 8 MiB bound. The sender checks the decoded size before gzip, so compression cannot hide an undeliverable frame. A rejected snapshot produces an explicit accepted-sign-in loading error. The 55,000-packet regression fixture shrinks from about 15.8 MB decoded to 4.4 MB and round-trips every field exactly. This is presentation serialization, not packet coalescence, density tuning or a simulation speed claim.

For negotiated clients, at most one complete world snapshot awaits processing acknowledgement. Correct epoch/serial acknowledgement releases the next snapshot; a slow browser does not accumulate a queue of large graphs. Paused clients acknowledge receipt while retaining only the latest full graph. Simulation and other clients continue independently. Older clients retain the legacy format and pacing until reloaded. Host telemetry includes the number of snapshots waiting for acknowledgement and read-only saved cytoplasm counts. Network checks cover withheld/incorrect/correct acknowledgements, dense gzip/codec round trips, automatic loading dismissal and accepted credential presentation. Gameplay/objective/balance tests remain held.

## Automatic population continuity

The shared authority maintains fifteen living cells, recovers existing families/backups first, then introduces a new lineage for an exhausted account. No camera or sign-in action is required. An empty pond exits after a durable checkpoint; the existing systemd restart policy launches a fresh population only after retaining two independently checksummed copies of the predecessor under `state/archives/pond-<world-id>--epoch-<epoch>--tick-<tick>/`. The access-key registry stays at the deployment root, outside pond storage. Existing session grants carry forward to living founders. Healthy saved-world restarts keep the current identity and simulated time. Health exposes `minimum_living_cells`, `introduced_cells`, `lineage_restarts`, `pond_restarts`, `previous_world_id` and `pond_archive`. See [Revision 48](REVISION_48.md) for the explicit starter-inventory and capacity rules.

## Revision 49 chemistry migration and performance gate

The current food-vacuole model supersedes intracellular pathway/particle-ATP descriptions above. Before loading a legacy checkpoint, the server archives its complete original graph under state/archives/pond-<id>--epoch-<epoch>--tick-<tick>/, then records a one-time numerical ATP/reserve and finite food/waste conversion audit in subsequent checkpoints. Existing keys and account/session references are retained. Rollback requires that archive and the previous source, with the service stopped; retain the current state as evidence before restoring either. Keep access-keys.json unchanged.

Desktop rendering uses tools/test_frame_budget.sh against the first-cell workload on a real display. CD checks mixed-camera hardware authority throughput and live simulation/wall rate with the actual service render surface, independent of full-window Xvfb presentation. It rejects a merely advancing world that runs below 0.98× or exceeds the 33.33 ms p95 tick budget at the deployed 30 Hz cadence. See REVISION_49.md for the comparable workload, results and phone-validation limitation.

## Revision 51 model boundary

The small food-vacuole model now also contains bounded oxygen/carbon particles for local respiration, fermentation and photosynthesis. Before the first upgraded checkpoint, the server independently archives the pre-upgrade pond, then records biochemistry_version=1. Preserve that archive for rollback, the live account graph and all existing keys. No fresh pond or credential replacement is part of this revision. Division AP/mutation state and hourly calendar conditions are checkpointed; restart must not re-award historical births or reroll the current hour. See [Revision 51](REVISION_51.md).

## Private player feedback inbox

Signed-in players open Pause / settings, then **Feature request / Bug report**.
They choose a report type and submit a title and details. Browser fields use
native HTML text input/IME and retain unfinished drafts across reloads. Retrying
an unconfirmed report reuses its ID. The server confirms only after durable
publication; feedback is independent of paid edits and works during local Pause.

Reports live under the retained service state directory, in
feedback/<32-character-id>.json. This is independent of rotating world saves
and remains across deployments and pond resets. Files are private (0600, inbox
0700); basic server build, client pack, world/tick/cell/perception facts are
attached. Session tokens, access keys, IP addresses and email addresses are not
automatically collected. Reporter text is untrusted data, never permission to
execute commands or change the game.

Run the **Primordia feedback inbox** GitHub Actions workflow against
samzapo/persistent-multiplayer. It produces a private summary and downloadable
feedback.json artifact, with up to 50 reports / approximately 500 KB per page.
If more remain, rerun with the returned next_cursor as before_report. The export
omits private account fingerprints and does not delete or mark server records.
Download artifacts expire after seven days; original reports remain in the
server inbox. No new GitHub credential or player GitHub account is required.
The workflow also exports once when its own file is published, which registers
the workflow on the deployment branch.

There is a 30-second per-account limit on new submissions, an eight-job bounded
write queue and a 5,000-report inbox ceiling. Existing-report retries remain
idempotent. A worker handles file synchronization outside simulation ticks.
Offline/local-only sessions can retain a draft and must connect to the shared
pond to submit it.


## Independent experimental instance

The default branch main is the stable game source and stable CD follows main.
Approved experimental features are squash-merged into main after validation.
Experimental source/CD uses samzapo/experimental-server or an explicitly selected
feature branch through .github/workflows/experimental.yml.

The same samzapo-desktop machine and public HTTPS8766 serve /experimental/.
Caddy strips that prefix and proxies to loopback HTTP8768; its independent Godot
authority listens on loopback8769. No router rule/new machine/public port.
The existing / and /health retain their stable upstream and source revision.
Experimental /health and /ws belong to its own pond. Public setup/CA/network
discovery/metrics endpoints remain denied in that prefix too.

The experimental deployment root is ~/.local/share/primordia-experimental,
service primordia-experimental.service. Saves, feedback, accounts, opaque browser
identities, deploy lock, runtime, releases and current symlink are independent.
Existing access-key hashes are copied once, never plaintext keys or stable
accounts/cells/checkpoints/feedback. A key signs into separate lineages per pond.
The experimental web build uses a different IndexedDB mount and custom user
directory, plus separate feedback draft storage. Its visible badge identifies
the pond. All URLs/assets/music/secure WebSockets retain the /experimental/
prefix. Stable client/storage formats remain unchanged.

Experimental CD never stops stable. It builds with conservative concurrency,
checks shared capacity and unchanged stable process/revision/pond/epoch/keys,
tests a small resident hardware-GPU network fixture, then replaces only the
experimental service. It verifies exact saved cells on its own restart and
trusted public HTTPS/WSS delivery, including foreign-origin rejection.
Changing later experimental releases needs no proxy rewrite or stable restart.
No rendering-speed benchmark or scheduled monitor is added.

One-time path registration uses Caddy's existing loopback config API with ETag /
If-Match; it preserves the existing stable routing and listener. It can cause
normal WebSocket reconnects during that initial proxy reload; world authority
keeps running. If Caddy boots from its root-owned /etc/caddy/Caddyfile rather than
--resume, the already-validated candidate must also be installed there once.
The deploy report prints the exact sudo command. The narrow installer checks
both old/new SHA256, retains the original file, and atomically installs only
that candidate. CI never runs it with sudo or resumes earlier stopped helpers.

Sources: [Caddy path routing](https://caddyserver.com/docs/caddyfile/directives/handle),
[conditional configuration API](https://caddyserver.com/docs/api),
[Web persistence](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

### Pond-specific update messages

Every authored release notice declares its audience: shared, stable, or
experimental. Stable sign-ins skip experimental-only announcements, and
experimental sign-ins skip stable-only promotion messages. Keep historical notice
IDs so existing seen_release values stay valid. Acknowledgements advance to the
next visible notice, oldest first, across hidden entries; filtering never rewinds
an account or clears a visible message. The supervisor selects the audience from
its configured pond before launching the authority, independently of inherited
build variables or browser input. Review these audiences during every promotion.

### Explicit fresh experimental pond

The experimental.yml manual dispatch has an optional reset_pond boolean, default false. Use it only for an owner-authorized ecology reset, such as Revision60. The job retains the stopped predecessor, prepares a new world with existing account credentials/names and update acknowledgements, preserves the five-key registry and private feedback, and then validates normal hardware/backend delivery and saved-world restart. Pushes cannot activate this reset. Stable is never a target of this tool. A failed install restores the predecessor and previous release.
