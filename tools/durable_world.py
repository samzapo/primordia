#!/usr/bin/env python3
"""Publish a complete checkpoint after synchronizing file and directory state."""
import os
from pathlib import Path
import sys

def publish(temporary: Path, final: Path) -> None:
    temporary, final = temporary.resolve(), final.resolve()
    if temporary.parent != final.parent or final.name not in {"world-0.pworld", "world-1.pworld", "before-particle-resolution-v1.pworld"}:
        raise ValueError("Invalid checkpoint destination")
    with temporary.open("rb") as handle:
        os.fsync(handle.fileno())
    os.replace(temporary, final)
    descriptor = os.open(final.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)

if __name__ == "__main__":
    publish(Path(sys.argv[1]), Path(sys.argv[2]))
