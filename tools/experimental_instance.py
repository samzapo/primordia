#!/usr/bin/env python3
"""Deploy only the independent experimental pond; never stop or replace stable."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import time
from urllib.request import build_opener, ProxyHandler
from check_capacity import inspect
from check_wired_route import verify
from deploy import quote, switch, retain_model_boundary, restore_model_boundary
from experimental_routing import prepare_and_apply

UNIT="primordia-experimental.service"
PORT=8768
WORLD_PORT=8769
OPENER=build_opener(ProxyHandler({}))
def get_json(url):
    with OPENER.open(url,timeout=5) as response:return json.load(response)
def stable_identity(root):
    value=get_json("http://127.0.0.1:8766/health")
    pid=subprocess.check_output(["systemctl","--user","show","primordia.service","-p","MainPID","--value"],text=True).strip()
    if pid in {"","0"} or value.get("backend")!="gpu" or value.get("backend_error") or value.get("checkpoint_error"):
        raise RuntimeError("Stable service is not healthy; experimental deployment must wait")
    return {"build":value["build"],"world_id":value["world_id"],"epoch":value["epoch"],"pid":pid,
            "release":str((root/"current").resolve()),"registry_sha256":hashlib.sha256((root/"access-keys.json").read_bytes()).hexdigest(),
            "tick":value["tick"]}
def guard(root,baseline):
    current=stable_identity(root)
    if any(current[k]!=v for k,v in baseline.items() if k!="tick") or current["tick"]<baseline["tick"]:
        raise RuntimeError("Stable identity changed during experimental work; stopping only owned work")
    return current
def run(*command,stable,baseline,**kwargs):
    guard(stable,baseline);inspect();verify()
    process=subprocess.Popen(command,start_new_session=True,**kwargs)
    try:
        while True:
            try:
                code=process.wait(timeout=15);break
            except subprocess.TimeoutExpired:
                guard(stable,baseline);inspect();verify()
        if code:raise subprocess.CalledProcessError(code,command)
    except BaseException:
        if process.poll() is None:os.killpg(process.pid,signal.SIGTERM);process.wait()
        raise
    guard(stable,baseline)
def isolated_root(root,stable):
    root=root.resolve();stable=stable.resolve()
    if root==stable or root.is_relative_to(stable) or stable.is_relative_to(root):
        raise ValueError("Experimental and stable roots must be disjoint")
    expected=Path.home()/".local/share/primordia-experimental"
    if root!=expected.resolve():raise ValueError("Unexpected experimental deployment root")
    for name in ["state","access-keys.json","credentials.env","repository.git","runtime","releases","current"]:
        if not (root/name).resolve().is_relative_to(root):
            raise ValueError("Experimental storage cannot resolve outside its own root")
def unit_text(current,godot,state,credentials,registry,sha):
    return (
        "[Unit]\nDescription=Primordia independent experimental GPU pond\nAfter=network-online.target\n\n"
        "[Service]\nType=simple\nUMask=0077\nWorkingDirectory="+str(current).replace("%","%%")+"\n"
        "EnvironmentFile="+quote(credentials)+"\nEnvironment=PRIMORDIA_BUILD_SHA="+sha+"\n"
        "Environment="+quote("PRIMORDIA_ACCESS_KEYS_FILE="+str(registry))+"\n"
        "ExecStart=/usr/bin/python3 "+quote(current/"tools/run_service.py")+" --godot "+quote(godot)+
        " --state "+quote(state)+" --port 8768 --world-port 8769 --proxy-loopback\n"
        "Restart=on-failure\nRestartSec=5\nTimeoutStopSec=60\nKillMode=mixed\n\n[Install]\nWantedBy=default.target\n")
def health(sha,stable_world,previous=None):
    end=time.monotonic()+120;first=None
    while time.monotonic()<end:
        try:
            value=get_json("http://127.0.0.1:8768/health")
            assert value["build"]==sha and value["backend"]=="gpu" and value["world_id"]!=stable_world
            assert not value["backend_error"] and not value["checkpoint_error"]
            assert not any(x in value["gpu"].lower() for x in ["lavapipe","llvmpipe","swiftshader"])
            if previous:
                assert value["world_id"]==previous["world_id"] and value["epoch"]>previous["epoch"] and value["tick"]>=previous["tick"]
                retention=value["cell_retention"]
                assert retention["ok"] and not retention["missing"] and not retention["changed"]
            if first is not None and value["tick"]>first and value["uptime_seconds"]>=8:return value
            first=value["tick"] if first is None else first
        except (OSError,ValueError,KeyError,AssertionError):pass
        time.sleep(2)
    raise RuntimeError("Experimental authority did not pass independent hardware/checkpoint health")
def requested_reset(environment):
    value=environment.get("PRIMORDIA_RESET_POND","0")
    if value not in ("0","1"):raise ValueError("Invalid reset request")
    if value=="1" and environment.get("GITHUB_EVENT_NAME")!="workflow_dispatch":
        raise ValueError("Pond resets require an explicit workflow dispatch")
    return value=="1"

def feedback_identity(state):
    directory=state/"feedback"
    if not directory.exists():return {}
    return {str(path.relative_to(directory)):hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(directory.rglob("*")) if path.is_file()}

def main():
    if os.environ.get("RUNNER_NAME")!="samzapo-desktop" or os.uname().nodename!="samzapo-desktop":
        raise RuntimeError("Experimental deployment requires samzapo-desktop")
    os.environ.setdefault("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}")
    os.umask(0o077)
    reset_pond=requested_reset(os.environ)
    stable=Path.home()/".local/share/primordia-deploy"
    root=Path.home()/".local/share/primordia-experimental"
    isolated_root(root,stable)
    baseline=stable_identity(stable)
    if subprocess.check_output(["loginctl","show-user",str(os.getuid()),"-p","Linger","--value"],text=True).strip()!="yes":
        raise RuntimeError("Existing user service boot persistence must be enabled")
    ownership=root/"OWNERSHIP.json"
    if root.exists():
        if ownership.exists():
            owner=json.loads(ownership.read_text())
            if owner.get("repository")!="samzapo/primordia" or owner.get("owner")!="experimental-server-20261016":
                raise RuntimeError("Existing experimental root has different ownership")
        elif any(root.iterdir()):raise RuntimeError("Unclaimed nonempty experimental root; inspect before changing it")
    root.mkdir(mode=0o700,parents=True,exist_ok=True)
    ownership.write_text(json.dumps({"repository":"samzapo/primordia","owner":"experimental-server-20261016","retention":"Retain independent experimental state and source"}))
    lock=(root/"deploy.lock").open("a+");fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    source=Path(__file__).resolve().parents[1]
    sha=subprocess.check_output(["git","-C",str(source),"rev-parse","HEAD"],text=True).strip()
    call=lambda *cmd,**kw:run(*cmd,stable=stable,baseline=baseline,**kw)
    repository=root/"repository.git";releases=root/"releases";releases.mkdir(exist_ok=True)
    if not repository.exists():call("git","init","--bare",str(repository))
    candidate=releases/("samzapo--experimental-server--"+sha)
    branch="samzapo/experimental-server/"+sha
    if not candidate.exists():
        call("git","--git-dir",str(repository),"fetch","--update-shallow","--no-tags",str(source),sha)
        call("git","--git-dir",str(repository),"worktree","add","-b",branch,str(candidate),sha)
    actual=subprocess.check_output(["git","-C",str(candidate),"branch","--show-current"],text=True).strip()
    assert actual==branch and subprocess.check_output(["git","-C",str(candidate),"rev-parse","HEAD"],text=True).strip()==sha
    (root/"OWNERSHIP.json").write_text(json.dumps({"repository":"samzapo/primordia","owner":"experimental-server-20261016","release":str(candidate),"revision":sha,"state":"Independent experimental pond; never share stable state or unit","retention":"Retain source/saves, no automatic deletion"}))
    runtime=root/"runtime"
    call("python3",str(candidate/"tools/provision_runtime.py"),"--runtime-dir",str(runtime))
    version=json.loads((candidate/"tools/toolchain.json").read_text())["version"]
    godot=runtime/f"Godot_v{version}-stable_linux.x86_64"
    environment={**os.environ,"GODOT_BIN":str(godot),"PRIMORDIA_BUILD_JOBS":"2","PRIMORDIA_INSTANCE":"experimental"}
    environment.pop("PRIMORDIA_ACCESS_KEYS_FILE",None)
    call("bash",str(candidate/"tools/build_native.sh"),env=environment)
    call("cmake","--build",str(candidate/"build/native"),"--target","primordia_dictionary_probe","--parallel","2",env=environment)
    memory_log=root/"dictionary-lifetime-fixture.log"
    with memory_log.open("w") as output:
        call("timeout","60s",str(godot),"--headless","--path",str(candidate),"--script","tests/native_dictionary_lifetime.gd",env=environment,stdout=output,stderr=subprocess.STDOUT)
    memory_result=memory_log.read_text();print(memory_result,flush=True)
    if re.search(r"SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:",memory_result,re.M) or "DICTIONARY_RESULT: 8 assertions, 0 failures" not in memory_result:
        raise RuntimeError("Native Dictionary lifetime fixture failed")

    call(str(godot),"--headless","--path",str(candidate),"--editor","--import","--quit",env=environment)
    for script,marker in [("feedback_pass_run","FEEDBACK PASS"),("feedback_latest_run","FEEDBACK LATEST"),("normal_output_run","NORMAL OUTPUT")]:
        path=root/(script+"-fixture.log")
        with path.open("w") as output:
            call("timeout","90s",str(godot),"--headless","--path",str(candidate),"--script","tests/"+script+".gd","--","--particle-backend=cpu",env=environment,stdout=output,stderr=subprocess.STDOUT)
        result=path.read_text();print(result,flush=True)
        if re.search(r"SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:",result,re.M) or not re.search(marker+r": \d+ assertions, 0 failures",result):
            raise RuntimeError("Experimental feedback correctness fixture failed")
    call("bash",str(candidate/"tools/build_web.sh"),env=environment)
    # Small real-GPU protocol fixture, with no stable outage or frame benchmark.
    fixture_log=root/"gpu-network-fixture.log"
    with fixture_log.open("w") as output:
        call("timeout","150s","xvfb-run","-a","-s","-screen 0 1280x720x24 -nolisten tcp",str(godot),
            "--path",str(candidate),"--rendering-method","mobile","--rendering-driver","vulkan","--gpu-index","0",
            "--resolution","64x64","--disable-vsync","--max-fps","60","--script","tests/network_live.gd","--","--gpu",
            env={**environment,"PRIMORDIA_INVITE":"experimental-private-fixture"},stdout=output,stderr=subprocess.STDOUT)
    result=fixture_log.read_text();print(result,flush=True)
    if re.search(r"SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:|returned to CPU|llvmpipe|lavapipe|swiftshader",result,re.M|re.I) or not re.search(r"NETWORK LIVE: \d+ assertions, 0 failures",result) or "backend=gpu" not in result:
        raise RuntimeError("Experimental GPU protocol fixture failed")
    # Focused feature acceptance on the real target; no FPS campaign or live reports.
    for script,flags,marker in [
        ("resident_admission_gpu",[],"RESIDENT ADMISSION"),
        ("lineage_start_network",["--gpu"],"LINEAGE START NETWORK"),
        ("feedback_pass_gpu",[],"FEEDBACK PASS GPU"),
        ("normal_output_run",["--particle-backend=cpu","--gpu"],"NORMAL OUTPUT"),
        ("feedback_pass_network",["--gpu"],"FEEDBACK PASS NETWORK"),
        ("feedback_latest_gpu",["--particle-backend=cpu"],"FEEDBACK LATEST GPU"),
        ("feedback_visual_gpu",["--particle-backend=cpu"],"FEEDBACK VISUAL GPU"),
        ("resident_plant_flow_gpu",[],"RESIDENT PLANT FLOW"),
        ("camera_streaming_network",["--gpu"],"CAMERA STREAMING NETWORK"),
    ]:
        path=root/(script+"-fixture.log")
        try:
            with path.open("w") as output:
                call("timeout","120s","xvfb-run","-a","-s","-screen 0 1280x1000x24 -nolisten tcp",str(godot),
                    "--path",str(candidate),"--rendering-method","mobile","--rendering-driver","vulkan","--gpu-index","0",
                    "--script","tests/"+script+".gd","--",*flags,
                    env={**environment,"PRIMORDIA_INVITE":"experimental-private-fixture"},stdout=output,stderr=subprocess.STDOUT)
        finally:
            # Retain the real assertion on failure; call() otherwise raises first.
            report=path.read_text();print(report,flush=True)
        if re.search(r"SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:|returned to CPU|llvmpipe|lavapipe|swiftshader",report,re.M|re.I) or not re.search(marker+r": [0-9]+ assertions, 0 failures",report):
            raise RuntimeError("Experimental feature fixture failed: "+script)
    guard(stable,baseline)
    state=root/"state";state.mkdir(mode=0o700,exist_ok=True)
    registry=root/"access-keys.json"
    source_keys=(stable/"access-keys.json").read_bytes()
    if registry.exists() and registry.read_bytes()!=source_keys:
        raise RuntimeError("Existing experimental keys differ; synchronize deliberately")
    if not registry.exists():registry.write_bytes(source_keys);registry.chmod(0o600)
    credentials=root/"credentials.env"
    if not credentials.exists():credentials.write_text("PRIMORDIA_INVITE="+secrets.token_hex(24)+"\n");credentials.chmod(0o600)
    current=root/"current";old=current.resolve() if current.is_symlink() else None
    previous=json.loads((state/"health.json").read_text()) if (state/"health.json").exists() else None
    unit_dir=Path.home()/".config/systemd/user";unit_dir.mkdir(parents=True,exist_ok=True)
    unit=unit_dir/UNIT
    if unit.exists() and (old is None or str(root) not in unit.read_text()):
        raise RuntimeError("Existing experimental unit lacks an owned release")
    old_unit=unit.read_text() if unit.exists() else None
    if unit.is_symlink():raise RuntimeError("Experimental unit cannot be a link to another service")
    text=unit_text(current,godot,state,credentials,registry,sha)
    staged=root/UNIT;staged.write_text(text)
    validation=subprocess.run(["systemd-analyze","--user","verify",str(staged)],capture_output=True,text=True)
    if validation.returncode:raise RuntimeError("Experimental systemd unit is invalid: "+validation.stderr)
    backup=None
    reset_report=None
    try:
        subprocess.run(["systemctl","--user","stop",UNIT],check=bool(old))
        if old:backup=retain_model_boundary(state,root,"before-experimental-update-")
        protected_feedback=feedback_identity(state)
        protected_keys=hashlib.sha256(registry.read_bytes()).hexdigest()
        if reset_pond:
            if old is None or backup is None:raise RuntimeError("Reset requires a retained existing experimental pond")
            path=root/"fresh-pond-reset.log"
            with path.open("w") as output:
                call(str(godot),"--headless","--path",str(candidate),"--script","tools/reset_pond.gd","--",
                     "--state-dir="+str(state),"--confirm-sha="+sha,
                     env={**environment,"PRIMORDIA_INSTANCE":"experimental","PRIMORDIA_BUILD_SHA":sha},
                     stdout=output,stderr=subprocess.STDOUT)
            result=path.read_text();print(result,flush=True)
            if re.search(r"SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:",result,re.M):raise RuntimeError("Fresh pond preparation failed")
            reset_report=json.loads(next(line.removeprefix("POND_RESET ") for line in result.splitlines() if line.startswith("POND_RESET ")))
            if previous:
                assert reset_report["previous_world_id"]==previous["world_id"] and reset_report["world_id"]!=previous["world_id"]
                assert reset_report["accounts"]==reset_report["accounts_before"]
        if feedback_identity(state)!=protected_feedback or hashlib.sha256(registry.read_bytes()).hexdigest()!=protected_keys:
            raise RuntimeError("Private feedback or access registry changed during pond preparation")
        unit.write_text(text);switch(current,candidate)
        call("systemctl","--user","daemon-reload")
        call("systemctl","--user","enable","--now",UNIT)
        report=health(sha,baseline["world_id"],None if reset_pond else previous)
        if reset_report:assert report["world_id"]==reset_report["world_id"] and report["accounts"]==reset_report["accounts"]
        # Prove this instance persists independently through its own restart.
        call("systemctl","--user","restart",UNIT)
        restarted=health(sha,baseline["world_id"],report)
        route=prepare_and_apply(root)
        after=guard(stable,baseline)
        if after["tick"]<=baseline["tick"]:raise RuntimeError("Stable world did not advance")
        record={"revision":sha,"experimental":restarted,"initial":report,"routing":route,"pond_reset":reset_report,"predecessor_archive":str(backup) if reset_pond else None,"feedback_retained":all(feedback_identity(state).get(name)==digest for name,digest in protected_feedback.items()),
                "stable_before":baseline,"stable_after":after,"stable_unit_restarted":False,
                "separate_state":str(state),"key_registry_sha256":hashlib.sha256(registry.read_bytes()).hexdigest()}
        (root/"last-deploy.json").write_text(json.dumps(record,indent=2))
        print("EXPERIMENTAL_DEPLOYMENT "+json.dumps(record),flush=True)
    except BaseException:
        subprocess.run(["systemctl","--user","stop",UNIT],check=False)
        if old and old_unit:
            if backup:restore_model_boundary(state,backup,root,"failed-experimental-update-")
            unit.write_text(old_unit);switch(current,old)
            call("systemctl","--user","daemon-reload");call("systemctl","--user","start",UNIT)
        raise
if __name__=="__main__":main()
