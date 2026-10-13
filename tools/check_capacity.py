#!/usr/bin/env python3
"""Observe aggregate build pressure without inspecting other tasks' arguments."""
from pathlib import Path
import json
import os

def inspect():
    memory = {line.split(":", 1)[0]: int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()}
    counts = {}
    for path in Path("/proc").glob("[0-9]*/comm"):
        try: name = path.read_text().strip()
        except OSError: continue
        if name in {"cc1", "cc1plus", "clang", "clang++", "cmake", "ninja", "make", "bazel", "rustc", "ld"}:
            counts[name] = counts.get(name, 0) + 1
    value = {"available_GiB": round(memory["MemAvailable"] / 1048576, 2),
             "swap_free_GiB": round(memory["SwapFree"] / 1048576, 2),
             "load": os.getloadavg(), "build_processes": counts,
             "memory_pressure": Path("/proc/pressure/memory").read_text().strip()}
    print(json.dumps(value), flush=True)
    if memory["MemAvailable"] < 8 * 1048576 or sum(counts.get(k, 0) for k in ["cc1plus", "clang", "clang++", "rustc"]) > 4:
        raise RuntimeError("Insufficient shared capacity for a Primordia build; retry later")

if __name__ == "__main__": inspect()
