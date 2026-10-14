#!/usr/bin/env python3
"""Bounded, IP-restricted relay to the existing local SSH server; no sudo/config writes."""
import ipaddress
import datetime
import re
import shutil
import sys
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time

DURATION_SECONDS = 45 * 60

def inspect():
    report = {"ssh_inspection": True, "host": socket.gethostname(), "account": os.environ.get("USER"), "port": 22}
    try:
        with socket.create_connection(("127.0.0.1", 22), timeout=3) as connection:
            connection.settimeout(3)
            report["banner"] = connection.recv(256).decode(errors="replace").strip()
        scan = subprocess.run(["ssh-keyscan", "-T", "3", "-t", "ed25519", "127.0.0.1"], capture_output=True, text=True, timeout=6)
        report["host_keys"] = [line.split()[1:3] for line in scan.stdout.splitlines() if line and not line.startswith("#")]
        report["ssh_available"] = report["banner"].startswith("SSH-2.0-") and bool(report["host_keys"])
    except (OSError, subprocess.TimeoutExpired) as error:
        report["ssh_available"] = False
        report["reason"] = type(error).__name__
    print(json.dumps(report), flush=True)
    return report

def launch(report, address):
    environment = dict(os.environ)
    environment.setdefault("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid()))
    active = subprocess.check_output(["systemctl", "--user", "list-units", "primordia-operator-ssh-*", "--state=active,activating", "--no-legend", "--plain"], text=True, env=environment).strip()
    if active:
        raise ValueError("A Primordia operator tunnel is already active; reuse or stop that owned session first")
    identifier = os.environ["GITHUB_RUN_ID"] + "-" + os.environ.get("GITHUB_RUN_ATTEMPT", "1")
    if not re.fullmatch(r"[0-9]+-[0-9]+", identifier):
        raise ValueError("Invalid run identity")
    root = Path.home()/".local/share/primordia-deploy/operator-ssh"
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    task = root/("samzapo--remote-ipv6--ssh-" + identifier)
    task.mkdir(mode=0o700)
    source = task/"ssh_tunnel.py"
    shutil.copyfile(__file__, source)
    source.chmod(0o600)
    unit = "primordia-operator-ssh-" + identifier
    args = ["systemd-run", "--user", "--collect", "--unit=" + unit,
            "--description=Temporary Primordia operator SSH access", "--working-directory=" + str(task),
            "--property=RuntimeMaxSec=" + str(DURATION_SECONDS + 10), "--property=KillMode=control-group",
            "--property=UMask=0077", "--property=NoNewPrivileges=yes", "--property=Restart=no"]
    for key, value in {"GITHUB_REPOSITORY": "samzapo/primordia", "GITHUB_ACTOR": "samzapo", "RUNNER_NAME": "samzapo-desktop",
                       "PRIMORDIA_SSH_START": "true", "PRIMORDIA_SSH_CLIENT_IPV4": address, "RUNNER_TEMP": str(task)}.items():
        args.append("--setenv=" + key + "=" + value)
    args.extend([sys.executable, str(source), "--serve"])
    subprocess.run(args, env=environment, check=True)
    expires = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=DURATION_SECONDS)).isoformat()
    try:
        for attempt in range(18):
            time.sleep(2)
            log = subprocess.check_output(["journalctl", "--user", "-u", unit, "-o", "cat", "-n", "40", "--no-pager"], text=True, env=environment)
            candidates = re.findall(r"tcp://([a-zA-Z0-9.-]+):([0-9]+)", log)
            endpoints = [(host, int(port)) for host, port in candidates if host.endswith((".pinggy.link", ".pinggy.online", ".pinggy.io")) and 1 <= int(port) <= 65535]
            if endpoints:
                host, port = endpoints[-1]
                value = {"ssh_tunnel_ready": True, "hostname": host, "port": port, "account": report["account"],
                         "allowed_client_ipv4": address, "expires_utc": expires, "unit": unit + ".service", "host_keys": report["host_keys"],
                         "private_task_directory": str(task)}
                output = task/"connection.json"
                with os.fdopen(os.open(output, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600), "w") as stream:
                    json.dump(value, stream, indent=2)
                print(json.dumps(value), flush=True)
                return
            state = subprocess.run(["systemctl", "--user", "is-active", unit], capture_output=True, text=True, env=environment)
            if state.stdout.strip() not in {"active", "activating"}:
                print(log[-3000:], flush=True)
                raise RuntimeError("SSH relay unit exited before becoming ready")
        print(json.dumps({"unrecognized_relay_endpoints": candidates}), flush=True)
        raise TimeoutError("SSH relay did not publish an endpoint in 36 seconds")
    except BaseException:
        subprocess.run(["systemctl", "--user", "stop", unit], env=environment, check=False)
        raise

def main():
    if os.environ.get("GITHUB_REPOSITORY") != "samzapo/primordia" or os.environ.get("GITHUB_ACTOR") != "samzapo" or os.environ.get("RUNNER_NAME") != "samzapo-desktop" or socket.gethostname() != "samzapo-desktop":
        raise ValueError("Only the owner-authorized Primordia runner may launch operator access")
    report = inspect()
    if os.environ.get("PRIMORDIA_SSH_START") != "true":
        return
    if not report["ssh_available"]:
        raise ValueError("Existing local SSH service is required; no service installation or privileged change attempted")
    address = ipaddress.ip_address(os.environ.get("PRIMORDIA_SSH_CLIENT_IPV4", ""))
    if address.version != 4 or not address.is_global:
        raise ValueError("One exact public client IPv4 address is required; no unrestricted relay permitted")
    if "--serve" not in sys.argv:
        launch(report, str(address))
        return
    # An isolated SSH client config prevents using or forwarding the runner's credentials.
    with tempfile.TemporaryDirectory(prefix="samzapo--remote-ipv6--ssh-", dir=os.environ["RUNNER_TEMP"]) as folder:
        args = ["ssh", "-F", "/dev/null", "-T", "-p", "443",
                "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=" + str(Path(folder)/"relay_known_hosts"),
                "-o", "GlobalKnownHostsFile=/dev/null", "-o", "IdentityAgent=none", "-o", "IdentityFile=none",
                "-o", "IdentitiesOnly=yes", "-o", "PreferredAuthentications=none", "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=20", "-o", "ServerAliveCountMax=3",
                "-o", "ExitOnForwardFailure=yes", "-R", "0:127.0.0.1:22", "tcp@free.pinggy.io", "w:" + str(address)]
        environment = {key: os.environ[key] for key in ["PATH", "HOME", "LANG"] if key in os.environ}
        process = None
        def interrupted(signum, frame):
            raise KeyboardInterrupt
        old_handlers = {number: signal.signal(number, interrupted) for number in [signal.SIGTERM, signal.SIGINT]}
        try:
            print(json.dumps({"ssh_tunnel_start": True, "allowed_client_ipv4": str(address), "duration_seconds": DURATION_SECONDS,
                              "target": "127.0.0.1:22", "relay": "free.pinggy.io", "router_changed": False}), flush=True)
            process = subprocess.Popen(args, stdin=subprocess.DEVNULL, env=environment, start_new_session=True)
            try:
                status = process.wait(timeout=DURATION_SECONDS)
                if status:
                    raise RuntimeError("SSH relay exited with code " + str(status))
            except subprocess.TimeoutExpired:
                print("Operator SSH tunnel expired after 45 minutes", flush=True)
        finally:
            if process and process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
            for number, handler in old_handlers.items(): signal.signal(number, handler)

if __name__ == "__main__":
    main()
