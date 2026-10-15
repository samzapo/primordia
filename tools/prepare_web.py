#!/usr/bin/env python3
"""Stage authored client inputs without desktop extensions or generated caches."""
from pathlib import Path
import shutil

def prepare(source: Path) -> Path:
    target = source / "build/web-project"
    target.mkdir(parents=True, exist_ok=True)
    for name in ("scripts", "shaders", "scenes", "data", "web", "assets"):
        destination = target / name
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source / name, destination,
                        ignore=shutil.ignore_patterns("*.tmp", "*.log", "*.import", "__pycache__"))
    for name in ("project.godot", "export_presets.cfg"):
        shutil.copyfile(source / name, target / name)
    # The authority/local game use resident GPU rendering. Browsers present the
    # authority's poses using WebGL, which requires the Compatibility renderer.
    project = target / "project.godot"
    config = project.read_text().replace('"4.7", "Mobile"', '"4.7", "GL Compatibility"')
    config = config.replace('renderer/rendering_method="mobile"', 'renderer/rendering_method="gl_compatibility"')
    config = config.replace('renderer/rendering_method.mobile="mobile"', 'renderer/rendering_method.mobile="gl_compatibility"')
    project.write_text(config)
    return target

if __name__ == "__main__":
    print(prepare(Path(__file__).resolve().parents[1]))
