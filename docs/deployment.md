# Primordia private deployment

Primordia follows the existing GSOC user-service pattern on `samzapo-desktop`, with an independent port and state directory. Open **http://192.168.1.25:8766** once for certificate setup, then use **https://192.168.1.25:8766** to play on the home network. `/api/network` lists current physical-interface home URLs if the address changes.

The first sign-in needs one of the owner-issued personal access keys. Give one key to each player. The browser stores an opaque account identity locally and resumes it on reconnect; using the same access key on another browser resumes the same lineage and disconnects the previous browser. The owner retains the plaintext key list privately outside source; the target stores only its hashes in `~/.local/share/primordia-deploy/access-keys.json`. Later key batches append to the registry instead of replacing earlier keys. See `docs/remote_access.md` for provisioning and router inspection. This revision does not expose administrative world resets or client-selected resource balances.

## One-time phone HTTPS setup

The same port handles the plain HTTP setup page and the HTTPS game. Download `primordia-lan-ca.crt` from the setup page. On Android, search Settings for **Install a certificate**, select **CA certificate**, and choose the downloaded file. Depending on the phone, this is under Security & privacy, More security settings, or Encryption & credentials. Open the HTTPS game address after installation. Installing the CA establishes trust; accepting a browser warning is not the setup procedure.

The CA signing key stays private in `~/.local/share/primordia-deploy/tls/authority/`. Retain that directory with the world state: replacing the CA requires every device to install a new certificate. Its name constraints permit private IP ranges and localhost, excluding public hostnames. The server certificate includes current physical-interface LAN addresses and loopback; it renews automatically without replacing the CA. `/api/network` lists HTTPS addresses. Other devices can import the same CA into their browser/system trust store. Remove **Primordia Private LAN CA** from user-installed trusted credentials to revoke local trust.

Godot 4.7.2's launcher requires a secure context even for the single-threaded build, and its audio initialization uses AudioWorklet. A plain HTTP LAN IP fails this requirement; localhost testing alone does not cover LAN access. Production assets and WebSockets require TLS. The public CA certificate and read-only health remain available over HTTP on the same port for bootstrap and local supervision.

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

The gateway exposes read-only bounded telemetry: build revision, world ID/epoch/tick, simulation time/wall ratio, camera and packet counts, GPU/backend status, checkpoint age, full reconciliation cost and file-write cost and tick-cost percentiles. The host-telemetry workflow also records hardware/load samples. Logs never contain invitations, bearer tokens or request bodies. Source, saves and installation media are retained; generated artifacts are rebuilt and not published in Git.

A failed candidate restores the previous service/release without deleting saves. Retain `access-keys.json` with state and the private CA; do not replace live identities when preparing another release. Current schema-compatible releases can read both checkpoint generations. For a future incompatible state format, prepare a migration and an independently retained compatible checkpoint before deploying. If both generations are invalid, startup refuses to reseed; repair/restore storage deliberately.

## Validation

`tools/test_network.sh` checks exact state identity/particles/RNG and real two-client CPU authority behavior. `tools/test_network.sh gpu` adds a hardware Vulkan test under a private Xvfb display and rejects software rendering or CPU fallback. `tests/test_web_gateway.py` verifies trusted HTTPS, certificate rejection, private key permissions, HTTP bootstrap and encrypted duplex snapshots. Deployment readiness and post-job restart checks use verified HTTPS with the retained CA. `tools/build_web.sh` exports the browser client from an automatically prepared source-only project. `tools/test.sh` retains the broader native physical suite and invokes networking checks after it.

Gameplay objective and balance groups stay disabled through `tests/test_policy.gd` until the owner requests restoration. Test harnesses use finite authored fixtures; they do not spawn free material in the product.
