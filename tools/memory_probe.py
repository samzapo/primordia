#!/usr/bin/env python3
"""Bounded read-only Primordia memory samples; never decode or change a world."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

STATUS_KEYS = {"VmPeak", "VmSize", "VmHWM", "VmRSS", "RssAnon", "RssFile", "RssShmem", "VmSwap", "Threads"}
HEALTH_KEYS = ["build", "world_id", "epoch", "tick", "living_cells", "accounts",
    "packets", "stored_packets", "cold_packets", "internal_packets", "resident_capacity",
    "resident_work_slots", "pending_particle_emissions", "stream_queue", "views", "peers",
    "uptime_seconds", "backend", "gpu", "backend_error", "checkpoint_error"]
ROOTS = {"stable": Path.home()/".local/share/primordia-deploy",
         "experimental": Path.home()/".local/share/primordia-experimental"}

def command(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=5)
        return result.returncode, result.stdout[:300000]
    except (OSError, subprocess.TimeoutExpired):
        return -1, ""

def status(pid):
    fields = {}
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        key, _, value = line.partition(":")
        if key in STATUS_KEYS:
            fields[key] = int(value.split()[0])
    return fields

def rollup(pid):
    result = {}
    for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
        key, _, value = line.partition(":")
        if key in {"Rss", "Pss", "Pss_Anon", "Pss_File", "Pss_Shmem", "Private_Clean",
                   "Private_Dirty", "Anonymous", "Swap", "SwapPss"}:
            result[key+"_KiB"] = int(value.split()[0])
    return result

def services():
    result = {}
    for instance in ROOTS:
        unit = "primordia.service" if instance == "stable" else "primordia-experimental.service"
        code, raw = command(["systemctl", "--user", "show", unit, "-p", "MainPID",
            "-p", "ControlGroup", "-p", "ActiveState", "-p", "MemoryCurrent", "-p", "MemoryPeak"])
        info = dict(line.split("=", 1) for line in raw.splitlines() if "=" in line)
        pids = []
        group = info.get("ControlGroup", "")
        if group.startswith("/") and ".." not in Path(group).parts:
            path = Path("/sys/fs/cgroup")/group.lstrip("/")
            try:
                pids = [int(pid) for pid in (path/"cgroup.procs").read_text().split()]
                for name in ["memory.current", "memory.peak", "memory.swap.current"]:
                    if (path/name).exists(): info[name] = (path/name).read_text().strip()
                info["memory.stat"] = {key:int(value) for key,value in
                    [line.split() for line in (path/"memory.stat").read_text().splitlines()]
                    if key in {"anon", "file", "kernel", "pagetables", "slab", "shmem", "sock"}}
            except OSError: pass
        result[instance] = {"status": code, "unit": unit, "pids": pids, "memory": info}
    return result

def sample():
    memory = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, _, value = line.partition(":")
        if key in {"MemTotal", "MemAvailable", "SwapTotal", "SwapFree"}:
            memory[key+"_KiB"] = int(value.split()[0])
    owned = services()
    owners = {pid:instance for instance,info in owned.items() for pid in info["pids"]}
    godots = []
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            name = (proc/"comm").read_text().strip()
            if "godot" not in name.lower(): continue
            pid = int(proc.name)
            row = {"pid":pid, "instance":owners.get(pid, "other_Godot"), "status_KiB_except_threads":status(pid)}
            # Only the two owned service trees get detailed memory inspection.
            if pid in owners:
                row["smaps"] = rollup(pid)
                raw = (proc/"stat").read_text()
                fields = raw[raw.rindex(")")+2:].split()
                row["age_seconds"] = float(Path("/proc/uptime").read_text().split()[0])-int(fields[19])/os.sysconf("SC_CLK_TCK")
            godots.append(row)
        except (OSError, ValueError, IndexError): pass
    health = {}
    for instance,root in ROOTS.items():
        try:
            with (root/"state/health.json").open() as source: raw = source.read(262145)
            if len(raw)>262144: raise ValueError("Oversized health")
            value = json.loads(raw)
            health[instance] = {key:value.get(key) for key in HEALTH_KEYS}
            health[instance]["checkpoint_files"] = {name:(root/"state"/name).stat().st_size
                for name in ["world-0.pworld", "world-1.pworld"] if (root/"state"/name).is_file()}
        except (OSError, ValueError):
            health[instance] = {"status":"unavailable"}
    return {"unix":time.time(), "host_memory":memory, "load":os.getloadavg(),
            "services":owned, "godot_processes":godots, "health":health}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples",type=int,choices=range(1,4),default=3)
    parser.add_argument("--interval",type=int,choices=range(0,11),default=10)
    args = parser.parse_args()
    if os.environ.get("RUNNER_NAME")!="samzapo-desktop" or os.uname().nodename!="samzapo-desktop":
        raise RuntimeError("Requires the authorized Primordia runner")
    os.environ.setdefault("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}")
    samples = []
    for i in range(args.samples):
        samples.append(sample())
        if i+1<args.samples:time.sleep(args.interval)
    pids = {row["pid"] for value in samples for row in value["godot_processes"]}
    code, raw = command(["nvidia-smi", "--query-compute-apps=pid,used_gpu_memory", "--format=csv,noheader,nounits"])
    gpu = []
    if code==0:
        for line in raw.splitlines():
            fields = [part.strip() for part in line.split(",")]
            if len(fields)==2 and fields[0].isdigit() and int(fields[0]) in pids:
                gpu.append({"pid":int(fields[0]),"gpu_memory_MiB":fields[1]})
    _, journal = command(["journalctl","--user","-u","primordia.service","-u","primordia-experimental.service",
        "--since","-2 hours","--no-pager","-n","120","-o","json"])
    events = []
    for line in journal.splitlines():
        try:
            item = json.loads(line);message = item.get("MESSAGE","")
            if any(word in message.lower() for word in ["memory peak","out of memory","oom-kill","failed with result"]):
                events.append({"unit":item.get("_SYSTEMD_USER_UNIT",""),"message":message[:1000]})
        except (ValueError,AttributeError):pass
    result = {"scope":"Read-only kernel memory, owned units and small health files. No world decoding, process arguments/environments, restarts or player feedback.",
        "samples":samples, "gpu_process_memory":gpu, "memory_journal_events":events[-20:]}
    print("MEMORY_PROBE "+json.dumps(result),flush=True)

if __name__=="__main__":main()
