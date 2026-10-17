#!/usr/bin/env python3
"""Supervise only Primordia's world, private display, and browser gateway."""
import argparse
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import threading
import time

from web_gateway import create

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--world-port", type=int, default=8767)
    parser.add_argument("--cpu", action="store_true")
    parser.add_argument("--proxy-loopback", action="store_true",
                        help="Private HTTP gateway for the experimental HTTPS reverse proxy")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    state = args.state.resolve()
    state.mkdir(parents=True, exist_ok=True)
    lock = (state / "world.lock").open("a+")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    (state / "stop.request").unlink(missing_ok=True)
    gateway = create(source / "build/web", state, args.port, args.world_port,
                     bind="127.0.0.1" if args.proxy_loopback else "0.0.0.0",
                     tls_directory=None if args.proxy_loopback else state.parent / "tls",
                     trusted_proxy=args.proxy_loopback)
    worker = threading.Thread(target=gateway.serve_forever, daemon=True)
    worker.start()
    command = [str(args.godot), "--path", str(source)]
    if args.cpu:
        command += ["--headless"]
    else:
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24 -nolisten tcp"] + command
        command += ["--rendering-method", "mobile", "--rendering-driver", "vulkan",
                    "--gpu-index", "0", "--resolution", "64x64", "--disable-vsync", "--max-fps", "60"]
    command += ["res://scenes/world_server.tscn", "--",
                f"--state-dir={state}", f"--port={args.world_port}"]
    if args.cpu:
        command += ["--cpu"]
    environment = os.environ.copy()
    environment.pop("RUNNER_TRACKING_ID", None)
    # The service configuration, never a browser request or inherited build env,
    # selects which pond’s update notices the authority can offer.
    environment["PRIMORDIA_INSTANCE"] = "experimental" if args.proxy_loopback else "stable"
    child = subprocess.Popen(command, cwd=source, env=environment, start_new_session=True)
    stopping = threading.Event()
    def renew_certificates():
        from lan_tls import provision
        while not stopping.wait(3600):
            try:
                gateway.tls_context = provision(gateway.tls_directory)
            except (OSError, ValueError, subprocess.CalledProcessError, RuntimeError):
                # Retain the working pair and report renewal failure without private material.
                print("Primordia LAN TLS renewal failed; existing certificate retained", flush=True)
    if gateway.tls_directory:
        threading.Thread(target=renew_certificates, daemon=True).start()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stopping.set())
    try:
        while child.poll() is None and not stopping.wait(.25):
            pass
    finally:
        stopping.set()
        if child.poll() is None:
            (state / "stop.request").write_text("graceful checkpoint and stop\n")
            try:
                child.wait(timeout=40)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
        gateway.shutdown()
        gateway.server_close()
        lock.close()
    return child.returncode

if __name__ == "__main__":
    raise SystemExit(main())
