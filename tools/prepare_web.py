#!/usr/bin/env python3
"""Stage authored client inputs without desktop extensions or generated caches."""
from pathlib import Path
import shutil

def prepare(source: Path) -> Path:
    target = source / "build/web-project"
    target.mkdir(parents=True, exist_ok=True)
    for name in ("scripts", "shaders", "scenes", "data"):
        destination = target / name
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source / name, destination,
                        ignore=shutil.ignore_patterns("*.tmp", "*.log", "__pycache__"))
    for name in ("project.godot", "export_presets.cfg"):
        shutil.copyfile(source / name, target / name)
    return target

if __name__ == "__main__":
    print(prepare(Path(__file__).resolve().parents[1]))
