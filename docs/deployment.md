# Primordia private deployment

Primordia follows the existing GSOC user-service pattern on `samzapo-desktop`, with an independent port and state directory. Open **http://192.168.1.25:8766** once for certificate setup, then use **https://192.168.1.25:8766** to play on the home network. `/api/network` lists current physical-interface home URLs if the address changes.

The first sign-in needs one of the owner-issued personal access keys. Give one key to each player. The browser stores an opaque account identity locally and resumes it on reconnect; using the same access key on another browser resumes the same lineage and disconnects the previous browser. The owner retains the plaintext key list privately outside source; the target stores only its hashes in `~/.local/share/primordia-deploy/access-keys.json`. Later key batches append to the registry instead of replacing earlier keys. See `docs/remote_access.md` for provisioning and router inspection. This revision does not expose administrative world resets or client-selected resource balances.

## One-time phone HTTPS setup

The same port handles the plain HTTP setup page and the HTTPS game. Download `primordia-lan-ca.crt` from the setup page. On Android, search Settings for **Install a certificate**, select **CA certificate**, and choose the downloaded file. Depending on the phone, this is under Security & privacy, More security settings, or Encryption & credentials. Open the HTTPS game address after installation. Installing the CA establishes trust; accepting a browser warning is not the setup procedure.

The CA signing key stays private in `~/.local/share/primordia-deploy/tls/authority/`. Retain that directory with the world state: replacing the CA requires every device to install a new certificate. Its name constraints permit private IP ranges and localhost, excluding public hostnames. The server certificate includes current physical-interface LAN addresses and loopback; it renews automatically without replacing the CA. `/api/network` lists HTTPS addresses. Other devices can import the same CA into their browser/system trust store. Remove **Primordia Private LAN CA** from user-installed trusted credentials to revoke local trust.

Godot 4.7.2's launcher requires a secure context even for the single-threaded build, and its audio initialization uses AudioWorklet. A plain HTTP LAN IP fails this requirement; localhost testing alone does not cover LAN access. Production assets and WebSockets require TLS. The public CA certificate and read-only health remain available over HTTP on the same port for bootstrap and local supervision.

Phone key entry uses Godot's browser keyboard bridge, enabled by `html/experimental_virtual_keyboard` in the Web export preset. The sign-in field requests a password keyboard so the browser masks the key. Mobile validation must include a touch followed by browser text insertion; desktop key events alone do not exercise this path.

## Continuous deployment

Pushes to `samzapo/persistent-multiplayer` run `.github/workflows/deploy.yml`. The guarded runner is `samzapo-desktop`. The source has its own revision branch and Git worktree in `~/.local/share/primordia-deploy/releases/samzapo--persistent-multiplayer--<commit>` before changing `current`. The Actions process installs/restarts the service and exits; systemd keeps the world running. A second job proves the service survives Actions cleanup.

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

Gameplay objective and balance groups stay disabled through `tests/test_policy.gd` until the owner requests restoration. Test harnesses use finite authored fixtures; they do not spawn free material in the product.

### IPv6 browser connections

Godot 4.7.2 reconstructs WebSocket URLs without restoring IPv6 host brackets ([upstream report](https://github.com/godotengine/godot/issues/123457)). The browser client corrects only its registered malformed address before calling the browser WebSocket constructor. Already valid URLs, native clients, protocol/binary data and certificate validation retain their ordinary behavior. Run `node tests/test_websocket_address.js` for address and transport-contract checks; browser verification must also sign in over a trusted bracketed IPv6 origin and receive advancing snapshots. A failed WebSocket connection alone does not establish a certificate failure.

Browser exports automatically give the game pack a content-specific filename through `tools/version_web.py`. A changed client therefore downloads through a new `mainPack` URL, while the large engine runtime can be reused. HTML and runtime assets use `Cache-Control: no-cache` to revalidate on reload, and health/account setup responses retain `no-store`. Run `python3 tests/test_web_version.py` and the TLS gateway fixture to check update delivery; both run during network/CD checks. Generated manifests and renamed packs remain build outputs.

A newly changed camera waits for a subsequent detailed simulation tick before GPU publication. Repeated identical camera reports retain that readiness rather than postponing it; the client sends camera changes at up to five per second and idle keepalives every two seconds. The slow-observer fixture deliberately repeats identical reports faster than simulation ticks and requires real particle snapshots, paid edit receipts and continued zero-client simulation. This cadence is confined to the fixture, and does not change production biology or particle density.

### Reduced multiplayer particle resolution

The October 14 owner correction sets `visible_target=700`, `seed_packets=1` and `parcel_scale=10`. New worlds use 3,760 external parcels, one tenth of the former 37,600, with tenfold starting amounts so the conversion does not remove material. External emission quantum is 1.8 and the shared native/reference/GPU aggregation limit is 5. Intracellular emission quanta also scale by ten; every pathway still consumes nearby physical particles.

On the first load of an older shared checkpoint, the authority retains its validated generation as `before-particle-resolution-v1.pworld` outside the rotating pair. It then groups at most ten compatible ordinary nutrient/oxygen/carbon/waste parcels within the same 256-unit storage chunk and matching owner, product metadata and elapsed-time clocks. Pheromones and specialized secretions retain their records. Within each cell, only matching species/source/compartment parcels in an eight-unit neighborhood coalesce; installed catalytic particles remain distinct. Amounts, food-fuel capacity, intracellular fuel and weighted linear momentum are retained, and no random stream advances. Weighted representative positions make this an explicit coarser resolution rather than exact trajectory equivalence. Species/source/chunk boundaries and partially filled groups mean a saved world's count need not become exactly one tenth.

The checkpoint records the conversion version and counts. Later restarts do not repeat it. Metrics report the retained conversion, parcel scale and visible target along with phase costs; the target is a density setting, not a population cap. Gameplay objectives and balance acceptance remain held.
