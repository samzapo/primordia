#!/usr/bin/env python3
"""One-time operator install of the already-live experimental Caddy route."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

def install(root):
    if os.geteuid()!=0:raise RuntimeError("Run this one-time configuration install with sudo")
    manifest=json.loads((root/"caddy-route-manifest.json").read_text())
    source=root/"Caddyfile.with-experimental"
    destination=Path("/etc/caddy/Caddyfile")
    digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    if digest(destination)==manifest["candidate_sha256"]:return
    if digest(destination)!=manifest["original_sha256"]:
        raise RuntimeError("Caddyfile changed after preparation; preserve it and prepare a fresh scoped candidate")
    candidate=source.read_bytes()
    if hashlib.sha256(candidate).hexdigest()!=manifest["candidate_sha256"]:raise RuntimeError("Prepared candidate changed")
    subprocess.run(["caddy","adapt","--config",str(source),"--adapter","caddyfile"],check=True,stdout=subprocess.DEVNULL)
    backup=destination.with_name("Caddyfile.before-primordia-experimental")
    if backup.exists():
        if digest(backup)!=manifest["original_sha256"]:raise RuntimeError("Different retained backup already exists")
    else:shutil.copy2(destination,backup)
    fd,name=tempfile.mkstemp(prefix=".primordia-caddy-",dir=destination.parent)
    try:
        with os.fdopen(fd,"wb") as handle:
            handle.write(candidate);handle.flush();os.fsync(handle.fileno())
        os.chmod(name,destination.stat().st_mode & 0o777)
        os.chown(name,destination.stat().st_uid,destination.stat().st_gid)
        if digest(destination)!=manifest["original_sha256"]:
            raise RuntimeError("Caddyfile changed during validation; existing configuration retained")
        os.replace(name,destination)
    finally:
        Path(name).unlink(missing_ok=True)
    print("Experimental route is now retained in Caddy's boot configuration. The already-live proxy and game were not restarted.")
if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--root",type=Path,required=True)
    install(p.parse_args().root.resolve())
