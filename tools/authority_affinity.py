"""Select CPUs near the simulation GPU, restricted to its memory-backed NUMA node."""
from pathlib import Path
import os
import re
import subprocess

def parse_cpus(value):
    result = set()
    for part in value.strip().split(","):
        if not part: continue
        bounds = part.split("-")
        if len(bounds) == 1: result.add(int(bounds[0]))
        elif len(bounds) == 2:
            lo, hi = map(int, bounds)
            if lo < 0 or hi < lo: raise ValueError("Invalid CPU range")
            result.update(range(lo, hi + 1))
        else: raise ValueError("Invalid CPU range")
    return result

def choose(sysroot, bus, allowed):
    """No host changes: return an eligible local set or None for default scheduling."""
    root = Path(sysroot)
    try:
        domain, device = bus.lower().split(":", 1)
        pci = f"{int(domain, 16):04x}:{device}"
        node = int((root / "bus/pci/devices" / pci / "numa_node").read_text())
        if node < 0: return None
        directory = root / f"devices/system/node/node{node}"
        memory = (directory / "meminfo").read_text()
        match = re.search(r"MemTotal:\s+([0-9]+)", memory)
        if not match or int(match[1]) <= 0: return None
        cpus = parse_cpus((directory / "cpulist").read_text()) & set(allowed)
        return cpus if cpus else None
    except (OSError, ValueError):
        return None

def detect():
    try:
        result = subprocess.run(["nvidia-smi", "--query-gpu=pci.bus_id", "--format=csv,noheader"],
                                capture_output=True, text=True, timeout=5, check=True)
        bus = result.stdout.splitlines()[0].strip()
        return choose("/sys", bus, os.sched_getaffinity(0))
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        return None
