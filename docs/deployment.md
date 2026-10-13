# Primordia private deployment

Primordia follows the existing GSOC user-service pattern on `samzapo-desktop`, with an independent port and state directory. Open **http://192.168.1.25:8766** on the home network. `/api/network` lists current physical-interface home URLs if the address changes.

The first connection needs the invitation from `~/.local/share/primordia-deploy/credentials.env` on the target. Keep that file private. The browser stores its account identity locally and resumes it on reconnect; clearing site data loses that identity. This revision does not expose administrative world resets or client-selected resource balances.

## Continuous deployment

Pushes to `samzapo/persistent-multiplayer` run `.github/workflows/deploy.yml`. The guarded runner is `samzapo-desktop`. The source is built and validated in `~/.local/share/primordia-deploy/releases/samzapo--persistent-multiplayer--<commit>` before changing `current`. The Actions process installs/restarts the service and exits; systemd keeps the world running. A second job proves the service survives Actions cleanup.

Godot and templates are checksum-pinned in `tools/toolchain.json`. Large dependencies download only over verified wired routes. The target needs Python 3.12+, curl, Git, CMake, a C++ compiler, Xvfb/xauth, a user systemd manager and Vulkan hardware. The deployer enables lingering for its own user and verifies it. It does not change GSOC configuration or use sudo.

State and credentials remain under `~/.local/share/primordia-deploy/`, outside release/checkouts. The service holds an exclusive world lock. Do not start another authority on those saves. A graceful service stop writes a final checkpoint. Restart resumes saved simulation time and increments the connection epoch. A forced crash can lose uncheckpointed ordinary simulation since the last 30-second save; acknowledged successful edits are saved before acknowledgement.

## Operator commands

On the target, use:

```sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user status primordia.service
systemctl --user restart primordia.service
systemctl --user stop primordia.service
curl --fail http://127.0.0.1:8766/health
```

The gateway exposes read-only bounded telemetry: build revision, world ID/epoch/tick, simulation time/wall ratio, camera and packet counts, GPU/backend status, checkpoint age/cost and tick-cost percentiles. The host-telemetry workflow also records hardware/load samples. Logs never contain invitations, bearer tokens or request bodies. Source, saves and installation media are retained; generated artifacts are rebuilt and not published in Git.

A failed candidate restores the previous service/release without deleting saves. Current schema-compatible releases can read both checkpoint generations. For a future incompatible state format, prepare a migration and an independently retained compatible checkpoint before deploying. If both generations are invalid, startup refuses to reseed; repair/restore storage deliberately.

## Validation

`tools/test_network.sh` checks exact state identity/particles/RNG and real two-client CPU authority behavior. `tools/test_network.sh gpu` adds a hardware Vulkan test under a private Xvfb display and rejects software rendering or CPU fallback. `tools/build_web.sh` exports the browser client from an automatically prepared source-only project. `tools/test.sh` retains the broader native physical suite and invokes networking checks after it.

Gameplay objective and balance groups stay disabled through `tests/test_policy.gd` until the owner requests restoration. Test harnesses use finite authored fixtures; they do not spawn free material in the product.
