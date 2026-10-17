#!/usr/bin/env python3
"""Suspend only the experimental pond, preserving state until the next CD."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from experimental_instance import UNIT, isolated_root, stable_identity, guard, get_json, feedback_identity

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def protected(root):
    files={name:sha(root/"state"/name) for name in ("world-0.pworld","world-1.pworld") if (root/"state"/name).is_file()}
    if not files:raise RuntimeError("Experimental checkpoint is unavailable")
    feedback=feedback_identity(root/"state")
    return {"checkpoints":files,"registry_sha256":sha(root/"access-keys.json"),
            "feedback_sha256":hashlib.sha256(json.dumps(feedback,sort_keys=True).encode()).hexdigest(),
            "feedback_count":len(feedback)}

def unit_status():
    output=subprocess.check_output(["systemctl","--user","show",UNIT,"-p","MainPID","-p","ActiveState","-p","UnitFileState"],text=True)
    return dict(line.split("=",1) for line in output.splitlines() if "=" in line)

def standby_identity(root):
    marker=root/"standby.json"
    if not marker.exists():return None
    if marker.is_symlink():raise RuntimeError("Experimental standby marker cannot be a link")
    value=json.loads(marker.read_text())
    if value.get("instance")!="experimental" or value.get("state")!="standby":raise RuntimeError("Invalid standby identity")
    status=unit_status()
    if status.get("MainPID")!="0" or status.get("ActiveState")!="inactive" or status.get("UnitFileState")!="disabled":
        raise RuntimeError("Experimental standby requires an inactive, disabled unit")
    for key,item in protected(root).items():
        if value.get(key)!=item:raise RuntimeError("Experimental saved state changed during standby: "+key)
    return value

def enter(root,stable,expected):
    isolated_root(root,stable)
    baseline=stable_identity(stable)
    if baseline["build"]!=expected:raise RuntimeError("Deploy and verify the expected stable release before standby")
    with (root/"deploy.lock").open("a+") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        existing=standby_identity(root)
        if existing is not None:return existing
        before=get_json("http://127.0.0.1:8768/health")
        if before["backend"]!="gpu" or before.get("backend_error") or before.get("checkpoint_error"):
            raise RuntimeError("Experimental service must be healthy before suspension")
        registry=sha(root/"access-keys.json");feedback=feedback_identity(root/"state")
        # SIGTERM makes run_service save a final checkpoint. Disable at boot too.
        subprocess.run(["systemctl","--user","disable","--now",UNIT],check=True)
        contents=protected(root)
        if contents["registry_sha256"]!=registry or not all(feedback_identity(root/"state").get(name)==digest for name,digest in feedback.items()):
            raise RuntimeError("Experimental keys or private feedback changed during standby")
        time.sleep(1)
        after=guard(stable,baseline)
        if after["tick"]<=baseline["tick"]:raise RuntimeError("Stable pond did not keep advancing")
        value={"version":1,"instance":"experimental","state":"standby","build":before["build"],
               "world_id":before["world_id"],"accounts":before["accounts"],"access_keys":before["access_keys"],
               "stable_build":expected,**contents}
        marker=root/"standby.json";temporary=root/"standby.json.tmp"
        temporary.write_text(json.dumps(value,indent=2)+"\n");temporary.chmod(0o600);temporary.replace(marker)
        return standby_identity(root)

def main():
    if os.environ.get("RUNNER_NAME")!="samzapo-desktop" or os.uname().nodename!="samzapo-desktop":
        raise RuntimeError("Standby requires the authorized game host")
    os.umask(0o077);os.environ.setdefault("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}")
    expected=os.environ.get("EXPECTED_STABLE_SHA","")
    if len(expected)!=40:raise RuntimeError("Expected stable revision is required")
    root=Path.home()/".local/share/primordia-experimental";stable=Path.home()/".local/share/primordia-deploy"
    value=enter(root,stable,expected)
    print("EXPERIMENTAL_STANDBY "+json.dumps(value))
if __name__=="__main__":main()
