#!/usr/bin/env python3
"""Atomically publish private feedback without replacing another report."""
import os
from pathlib import Path
import re
import sys

def synchronize(final: Path) -> None:
    final = final.resolve()
    if not re.fullmatch(r"[a-f0-9]{32}\.json", final.name):
        raise ValueError("Invalid feedback destination")
    with final.open("rb") as source:
        os.fsync(source.fileno())
    for directory in [final.parent, final.parent.parent]:
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

def publish(temporary: Path, final: Path) -> None:
    temporary, final = temporary.resolve(), final.resolve()
    if temporary.parent != final.parent or not re.fullmatch(r"[a-f0-9]{32}\.json", final.name) or temporary.name != final.name + ".tmp":
        raise ValueError("Invalid feedback destination")
    os.chmod(final.parent, 0o700)
    os.chmod(temporary, 0o600)
    with temporary.open("rb") as source:
        os.fsync(source.fileno())
    os.link(temporary, final)
    temporary.unlink()
    synchronize(final)

if __name__ == "__main__":
    if sys.argv[1] == "--sync":
        synchronize(Path(sys.argv[2]))
    else:
        publish(Path(sys.argv[1]), Path(sys.argv[2]))
