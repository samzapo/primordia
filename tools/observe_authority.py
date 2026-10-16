#!/usr/bin/env python3
"""Read-only, bounded hardware samples from an owned candidate process tree."""
import csv
import io
import json
import os
from pathlib import Path
import subprocess
import threading
import time

class Sampler:
    def __init__(self, root):
        self.root = root
        self.finished = threading.Event()
        self.samples = []
        self.previous = {}
        self.worker = threading.Thread(target=self._loop, daemon=True)

    def start(self):
        self.worker.start()

    def stop(self):
        self.finished.set()
        self.worker.join(timeout=5)
        print("AUTHORITY_HARDWARE_SAMPLES " + json.dumps(self.samples[-45:]), flush=True)

    @staticmethod
    def _stat(path):
        value = path.read_text()
        name, fields = value[value.index("(")+1:value.rindex(")")], value[value.rindex(")")+2:].split()
        return name, fields

    def sample(self):
        # Read only comm/stat for discovery, then only our descendants' threads.
        parents = {}
        for path in Path("/proc").glob("[0-9]*/stat"):
            try:
                name, fields = self._stat(path)
                parents[int(path.parent.name)] = (int(fields[1]), name)
            except (OSError, ValueError, IndexError, UnicodeError):
                continue
        owned = {self.root}
        for _ in range(12):
            found = {pid for pid, (parent, _) in parents.items() if parent in owned}
            if found <= owned:
                break
            owned.update(found)
        value = {"wall": time.time(), "load": os.getloadavg(), "authorities": []}
        for pid in sorted(owned):
            if pid not in parents or "godot" not in parents[pid][1].lower():
                continue
            threads = []
            for path in Path(f"/proc/{pid}/task").glob("*/stat"):
                try:
                    name, fields = self._stat(path)
                    tid = int(path.parent.name)
                    ticks = int(fields[11])+int(fields[12])
                    cpu = int(fields[36])
                    sched = (path.parent/"schedstat").read_text().split()
                    runtime, delay = int(sched[0]), int(sched[1])
                    previous = self.previous.get(tid, (ticks, runtime, delay))
                    self.previous[tid] = (ticks, runtime, delay)
                    row = {"tid": tid, "name": name, "cpu": cpu, "state": fields[0],
                           "runtime_ms": (runtime-previous[1])/1e6, "runqueue_ms": (delay-previous[2])/1e6}
                    try:
                        row["cpu_khz"] = int(Path(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_cur_freq").read_text())
                    except (OSError, ValueError):
                        pass
                    threads.append(row)
                except (OSError, ValueError, IndexError, UnicodeError):
                    continue
            hot = sorted(threads, key=lambda row: row["runtime_ms"], reverse=True)[:4]
            for row in threads:
                if (row["tid"]==pid or "render" in row["name"].lower()) and row not in hot:
                    hot.append(row)
            value["authorities"].append({"pid": pid, "threads": len(threads), "hot": hot})
        try:
            fields = "name,pstate,clocks.current.sm,clocks.current.memory,utilization.gpu,utilization.memory,power.draw,temperature.gpu"
            result = subprocess.run(["nvidia-smi", "--query-gpu="+fields, "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=2)
            if result.returncode==0:
                value["gpus"] = [dict(zip(fields.split(","), row)) for row in csv.reader(io.StringIO(result.stdout), skipinitialspace=True)]
        except (OSError, subprocess.TimeoutExpired):
            pass
        self.samples.append(value)
        self.samples = self.samples[-150:]

    def _loop(self):
        while not self.finished.is_set():
            try:
                self.sample()
            except (OSError, ValueError, IndexError, UnicodeError):
                pass
            if self.finished.wait(1):
                break
