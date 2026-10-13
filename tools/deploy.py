#!/usr/bin/env python3
"""Build retained authored source on the target, then switch one private service."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import secrets
import subprocess
import signal
import time
from urllib.request import build_opener, ProxyHandler

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

def health(build, previous=None):
    opener = build_opener(ProxyHandler({}))
    deadline = time.monotonic() + 120
    first = None
    while time.monotonic() < deadline:
        try:
            with opener.open("http://127.0.0.1:8766/health", timeout=3) as response:
                value = json.load(response)
            if value.get("build") != build or value.get("backend") != "gpu" or value.get("backend_error") or value.get("checkpoint_error"):
                raise ValueError("Unhealthy build or GPU backend")
            if any(name in value.get("gpu", "").lower() for name in ["llvmpipe", "lavapipe", "swiftshader"]):
                raise ValueError("Software GPU rejected")
            if previous and (value["world_id"] != previous["world_id"] or value["tick"] < previous["tick"] or value["epoch"] <= previous["epoch"]):
                raise ValueError("World identity/time did not resume")
            if first is not None and value["tick"] > first:
                print(json.dumps(value, sort_keys=True), flush=True)
                return value
            first = value["tick"] if first is None else first
        except (OSError, ValueError, KeyError): pass
        time.sleep(2)
    raise RuntimeError("Candidate did not pass live GPU and checkpoint health checks")

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
    subprocess.run(["systemctl", "--user", "stop", UNIT], check=False)
    unit_dir = Path.home() / ".config/systemd/user"
    unit_dir.mkdir(parents=True, exist_ok=True)
    unit = unit_dir / UNIT
    old_unit = unit.read_text() if unit.exists() else None
    unit.write_text("[Unit]\nDescription=Primordia persistent GPU world and browser gateway\nAfter=network-online.target\n\n[Service]\nType=simple\nUMask=0077\nWorkingDirectory=" + quote(current) + "\nEnvironmentFile=" + quote(credential) + "\nEnvironment=PRIMORDIA_BUILD_SHA=" + sha + "\nExecStart=/usr/bin/python3 " + quote(current / "tools/run_service.py") + " --godot " + quote(godot) + " --state " + quote(state) + " --port 8766 --world-port 8767\nRestart=on-failure\nRestartSec=5\nTimeoutStopSec=60\nKillMode=control-group\n\n[Install]\nWantedBy=default.target\n")
    switch(current, candidate)
    try:
        run("systemctl", "--user", "daemon-reload")
        run("systemctl", "--user", "enable", "--now", UNIT)
        report = health(sha, previous)
        (root / "last-deploy.json").write_text(json.dumps(report, indent=2))
    except BaseException:
        subprocess.run(["systemctl", "--user", "stop", UNIT], check=False)
        if old and old_unit:
            unit.write_text(old_unit)
            switch(current, old)
            run("systemctl", "--user", "daemon-reload")
            run("systemctl", "--user", "start", UNIT)
            print("Previous service restored; world saves retained", flush=True)
        raise
    print("Private browser endpoint is port 8766; invitation remains in " + str(credential), flush=True)

if __name__ == "__main__": main()
