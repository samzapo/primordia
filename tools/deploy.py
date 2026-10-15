#!/usr/bin/env python3
"""Build retained authored source on the target, then switch one private service."""
import argparse
import fcntl
import hashlib
import json
import re
import os
from pathlib import Path
import secrets
import subprocess
import signal
import ssl
import shutil
import tempfile
import time
from urllib.request import build_opener, ProxyHandler, HTTPSHandler, Request

from check_capacity import inspect
from check_wired_route import verify

UNIT = "primordia.service"

def run(*args, **kwargs):
    job = subprocess.Popen(args, start_new_session=True, **kwargs)
    try:
        while True:
            try:
                status = job.wait(timeout=15)
                break
            except subprocess.TimeoutExpired:
                inspect()
                verify()
        if status: raise subprocess.CalledProcessError(status, args)
    except BaseException:
        if job.poll() is None:
            os.killpg(job.pid, signal.SIGTERM)
            job.wait()
        raise

def quote(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%") + '"'

def switch(link, destination):
    temporary = link.with_name("current.next")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(destination)
    temporary.replace(link)

def retained_restart(value, previous, state):
    """Allow a new pond only with its explicit, durable predecessor archive."""
    if value.get("previous_world_id") != previous.get("world_id") or value.get("pond_restarts", 0) <= previous.get("pond_restarts", 0):
        return False
    relative = value.get("pond_archive", "")
    if not re.fullmatch(r"archives/pond-" + re.escape(previous["world_id"]) + r"--epoch-[0-9]+--tick-[0-9]+", relative):
        return False
    for slot in ("world-0.pworld", "world-1.pworld"):
        path = state / relative / slot
        if not path.is_file(): return False
        with path.open("rb") as handle:
            digest = handle.readline().strip().decode("ascii")
            if hashlib.sha256(handle.read()).hexdigest() != digest: return False
    return True

def health(build, previous=None, ca_file=None, state=None):
    context = ssl.create_default_context(cafile=str(ca_file))
    opener = build_opener(ProxyHandler({}), HTTPSHandler(context=context))
    deadline = time.monotonic() + 120
    first = None
    while time.monotonic() < deadline:
        try:
            with opener.open("https://127.0.0.1:8766/health", timeout=3) as response:
                value = json.load(response)
            if value.get("build") != build or value.get("backend") != "gpu" or value.get("backend_error") or value.get("checkpoint_error"):
                raise ValueError("Unhealthy build or GPU backend")
            if any(name in value.get("gpu", "").lower() for name in ["llvmpipe", "lavapipe", "swiftshader"]):
                raise ValueError("Software GPU rejected")
            if previous:
                if value["epoch"] <= previous["epoch"]:
                    raise ValueError("World epoch did not advance")
                if value["world_id"] == previous["world_id"]:
                    if value["tick"] < previous["tick"]: raise ValueError("World time did not resume")
                elif state is None or not retained_restart(value, previous, state):
                    raise ValueError("New pond is missing its retained predecessor")
            if value.get("automatic_pond_restart") and value.get("living_cells", 0) < value.get("minimum_living_cells", 15):
                raise ValueError("Pond population is below its configured floor")
            if first is not None and value["tick"] > first and value.get("uptime_seconds",0)>=10:
                if value.get("simulation_hz") != 30 or not .98 <= value.get("simulation_wall_ratio",0) <= 1.02 or value.get("tick_ms_p95",float("inf"))>1000/30:
                    raise ValueError("Authority misses its documented real-time 30 Hz budget")
                if value.get("food_vacuole_version")!=1 or value.get("internal_packets",0)>24*value.get("living_cells",0):
                    raise ValueError("Unbounded or obsolete internal chemistry")
                with opener.open("https://127.0.0.1:8766/music-bank.json", timeout=3) as response:
                    music = json.load(response)
                if not re.fullmatch(r"music-bank-[a-f0-9]{24}\.bin", music["file"]) or not 0 < music["bytes"] < 4 * 1024 * 1024:
                    raise ValueError("Invalid deployed music manifest")
                with opener.open(Request("https://127.0.0.1:8766/" + music["file"], method="HEAD"), timeout=3) as response:
                    if int(response.headers.get("Content-Length", -1)) != music["bytes"]:
                        raise ValueError("Deployed music bank is unavailable")
                value["music_delivery"] = {"file": music["file"], "bytes": music["bytes"], "http": 200}
                print(json.dumps(value, sort_keys=True), flush=True)
                return value
            first = value["tick"] if first is None else first
        except (OSError, ValueError, KeyError): pass
        time.sleep(2)
    raise RuntimeError("Candidate did not pass live GPU and checkpoint health checks")

def _sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def retain_model_boundary(state, root, prefix):
    """Retain exact stopped-service generations before crossing model formats."""
    target = Path(tempfile.mkdtemp(prefix=prefix, dir=root))
    manifest = {}
    for name in ("world-0.pworld", "world-1.pworld"):
        source = state / name
        if source.exists():
            destination = target / name
            shutil.copyfile(source, destination)
            destination.chmod(0o600)
            with destination.open("rb") as saved:
                os.fsync(saved.fileno())
            manifest[name] = hashlib.sha256(destination.read_bytes()).hexdigest()
    if not manifest:
        raise RuntimeError("No stopped world generations to retain before migration")
    (target / "manifest.json").write_text(json.dumps(manifest, sort_keys=True))
    with (target / "manifest.json").open("rb") as saved:
        os.fsync(saved.fileno())
    _sync_directory(target)
    _sync_directory(root)
    return target


def restore_model_boundary(state, backup, root):
    manifest = json.loads((backup / "manifest.json").read_text())
    for name, digest in manifest.items():
        if name not in ("world-0.pworld", "world-1.pworld") or hashlib.sha256((backup / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError("Model rollback archive failed validation; service remains stopped")
    # Retain the failed new-model world before restoring the old format. Keys and
    # the other source/evidence archives are never replaced or removed.
    retain_model_boundary(state, root, "failed-food-vacuoles-v1-")
    for name in manifest:
        temporary = state / (name + ".rollback")
        shutil.copyfile(backup / name, temporary)
        temporary.chmod(0o600)
        with temporary.open("rb") as saved:
            os.fsync(saved.fileno())
        temporary.replace(state / name)
    _sync_directory(state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.home() / ".local/share/primordia-deploy")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    if os.environ.get("RUNNER_NAME") != "samzapo-desktop":
        raise RuntimeError("Deployment requires the authorized samzapo-desktop runner")
    os.environ.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    root = args.root.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    root.chmod(0o700)
    lock = (root / "deploy.lock").open("a+")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    sha = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    branch = subprocess.check_output(["git", "-C", str(source), "branch", "--show-current"], text=True).strip()
    print(f"Execution host: {os.uname().nodename}; branch: {branch or sha}; deployment root: {root}", flush=True)
    verify(); inspect()
    releases = root / "releases"
    releases.mkdir(exist_ok=True)
    candidate = releases / ("samzapo--persistent-multiplayer--" + sha)
    repository = root / "repository.git"
    release_branch = "samzapo/persistent-multiplayer/" + sha
    if not repository.exists(): run("git", "init", "--bare", str(repository))
    if not candidate.exists():
        run("git", "--git-dir", str(repository), "fetch", "--update-shallow", "--no-tags", str(source), sha)
        run("git", "--git-dir", str(repository), "worktree", "add", "-b", release_branch, str(candidate), sha)
    else:
        actual = subprocess.check_output(["git", "-C", str(candidate), "branch", "--show-current"], text=True).strip()
        head = subprocess.check_output(["git", "-C", str(candidate), "rev-parse", "HEAD"], text=True).strip()
        if actual != release_branch or head != sha:
            raise RuntimeError("Existing release directory is not owned by this revision")
    (root / "OWNERSHIP.json").write_text(json.dumps({"repository":"samzapo/primordia", "owner":"persistent-multiplayer-20261013", "release":str(candidate), "revision":sha,"retention":"Active service and state retained; no automatic deletion of source or saves"}, indent=2))
    runtime = root / "runtime"
    run("python3", str(candidate / "tools/provision_runtime.py"), "--runtime-dir", str(runtime))
    version = json.loads((candidate / "tools/toolchain.json").read_text())["version"]
    godot = runtime / f"Godot_v{version}-stable_linux.x86_64"
    environment = os.environ.copy()
    environment.update(GODOT_BIN=str(godot), PRIMORDIA_BUILD_JOBS="2")
    # Generated artifacts are produced here, never copied out of another checkout.
    run("bash", str(candidate / "tools/build_native.sh"), env=environment)
    inspect()
    run(str(godot), "--headless", "--path", str(candidate), "--editor", "--import", "--quit", env=environment)
    if any((root / "state" / name).exists() for name in ("world-0.pworld", "world-1.pworld")):
        environment["PRIMORDIA_VERIFY_CHECKPOINT_DIR"] = str(root / "state")
    run("bash", str(candidate / "tools/test_network.sh"), "gpu", env=environment)
    inspect()
    run("bash", str(candidate / "tools/build_web.sh"), env=environment)
    state = root / "state"
    state.mkdir(mode=0o700, exist_ok=True)
    credential = root / "credentials.env"
    if not credential.exists():
        descriptor = os.open(credential, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(descriptor, "w") as output:
            output.write("PRIMORDIA_INVITE=" + secrets.token_hex(24) + "\n")
    credential.chmod(0o600)
    registry = root / "access-keys.json"
    configured = os.environ.get("PRIMORDIA_ACCESS_KEY_HASHES", "")
    if configured:
        incoming = json.loads(configured)
        hashes = incoming.get("hashes", []) if isinstance(incoming, dict) else []
        if not hashes or any(not isinstance(value,str) or not re.fullmatch(r"[a-f0-9]{64}",value) for value in hashes):
            raise RuntimeError("Invalid personal access key hashes")
        existing = json.loads(registry.read_text()).get("hashes",[]) if registry.exists() else []
        hashes = sorted(set(existing + hashes))
        if len(hashes)>1024: raise RuntimeError("Access key registry capacity exceeded")
        pending = registry.with_suffix(".json.next")
        descriptor = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor,"w") as output:
            output.write(json.dumps({"hashes":hashes})+"\n");output.flush();os.fsync(output.fileno())
        pending.replace(registry);registry.chmod(0o600)
        descriptor=os.open(root,os.O_RDONLY)
        try:os.fsync(descriptor)
        finally:os.close(descriptor)
    from lan_tls import provision
    provision(root / "tls")  # Validate retained CA and candidate TLS before stopping the world.
    current = root / "current"
    old = current.resolve() if current.is_symlink() else None
    previous = None
    if (state / "health.json").exists():
        previous = json.loads((state / "health.json").read_text())
    # Own-user lingering makes this user's service manager survive logout/boot.
    linger = subprocess.check_output(["loginctl", "show-user", str(os.getuid()), "-p", "Linger", "--value"], text=True).strip()
    if linger != "yes": run("loginctl", "enable-linger", str(os.getuid()))
    if subprocess.check_output(["loginctl", "show-user", str(os.getuid()), "-p", "Linger", "--value"], text=True).strip() != "yes":
        raise RuntimeError("User service boot persistence is unavailable")
    unit_dir = Path.home() / ".config/systemd/user"
    unit_dir.mkdir(parents=True, exist_ok=True)
    unit = unit_dir / UNIT
    old_unit = unit.read_text() if unit.exists() else None
    unit_text = "[Unit]\nDescription=Primordia persistent GPU world and browser gateway\nAfter=network-online.target\n\n[Service]\nType=simple\nUMask=0077\nWorkingDirectory=" + str(current).replace("%", "%%") + "\nEnvironmentFile=" + str(credential).replace("%", "%%") + "\nEnvironment=PRIMORDIA_BUILD_SHA=" + sha + "\nExecStart=/usr/bin/python3 " + quote(current / "tools/run_service.py") + " --godot " + quote(godot) + " --state " + quote(state) + " --port 8766 --world-port 8767\nRestart=on-failure\nRestartSec=5\nTimeoutStopSec=60\nKillMode=mixed\n\n[Install]\nWantedBy=default.target\n"
    if registry.exists():
        unit_text = unit_text.replace("Environment=PRIMORDIA_BUILD_SHA=", "Environment=" + quote("PRIMORDIA_ACCESS_KEYS_FILE="+str(registry)) + "\nEnvironment=PRIMORDIA_BUILD_SHA=")
    validation_dir = root / "unit-candidate"
    validation_dir.mkdir(exist_ok=True)
    validation_unit = validation_dir / UNIT
    validation_unit.write_text(unit_text)
    validation = subprocess.run(["systemd-analyze", "--user", "verify", str(validation_unit)], capture_output=True, text=True)
    if validation.returncode or str(validation_unit) in validation.stderr:
        raise RuntimeError("Candidate systemd unit did not validate: " + validation.stderr)
    subprocess.run(["systemctl", "--user", "stop", UNIT], check=False)
    migration_backup = None
    try:
        if old and previous and previous.get("food_vacuole_version", 0) < 1:
            migration_backup = retain_model_boundary(state, root, "before-food-vacuoles-v1-")
        staged_unit = unit.with_suffix(".service.new")
        staged_unit.write_text(unit_text)
        staged_unit.replace(unit)
        switch(current, candidate)
        run("systemctl", "--user", "daemon-reload")
        run("systemctl", "--user", "enable", "--now", UNIT)
        report = health(sha, previous, root / "tls/authority/ca.pem", state)
        if previous and report.get("accounts", 0) < previous.get("accounts", 0):
            raise RuntimeError("Deployment lost a retained account")
        report["access_registry_sha256"] = hashlib.sha256(registry.read_bytes()).hexdigest() if registry.exists() else None
        (root / "last-deploy.json").write_text(json.dumps(report, indent=2))
    except BaseException:
        subprocess.run(["systemctl", "--user", "stop", UNIT], check=False)
        if old and old_unit:
            if migration_backup is not None:
                restore_model_boundary(state, migration_backup, root)
            unit.write_text(old_unit)
            switch(current, old)
            run("systemctl", "--user", "daemon-reload")
            run("systemctl", "--user", "start", UNIT)
            print("Previous service restored; world saves retained", flush=True)
        raise
    print("Private HTTPS browser endpoint is port 8766; HTTP on that port provides certificate setup. Invitation remains in " + str(credential), flush=True)

if __name__ == "__main__": main()
