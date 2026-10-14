#!/usr/bin/env python3
"""Publish a complete checkpoint after synchronizing file and directory state."""
import os
from pathlib import Path
import sys

def publish(temporary: Path, final: Path) -> None:
    temporary, final = temporary.resolve(), final.resolve()
    if temporary.parent != final.parent or final.name not in {"world-0.pworld", "world-1.pworld", "before-particle-resolution-v1.pworld", "before-particle-resolution-v2.pworld", "before-particle-resolution-v3.pworld"}:
        raise ValueError("Invalid checkpoint destination")
    with temporary.open("rb") as handle:
        os.fsync(handle.fileno())
    os.replace(temporary, final)
    directories = [final.parent]
    if final.parent.parent.name == "archives":
        # Persist both newly created archive directory entries before reseeding.
        directories.extend([final.parent.parent, final.parent.parent.parent])
    for directory in directories:
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

if __name__ == "__main__":
    publish(Path(sys.argv[1]), Path(sys.argv[2]))
