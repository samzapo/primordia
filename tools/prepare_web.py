#!/usr/bin/env python3
"""Stage authored client inputs without desktop extensions or generated caches."""
from pathlib import Path
import shutil
import os

def prepare(source: Path, instance: str = "stable") -> Path:
    if instance not in {"stable", "experimental"}: raise ValueError("Unknown game instance")
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
    if instance == "experimental":
        config = config.replace('[application]', '[application]'+chr(10)+'config/use_custom_user_dir=true'+chr(10)+'config/custom_user_dir_name="primordia-experimental"', 1)
    project.write_text(config)
    return target

if __name__ == "__main__":
    print(prepare(Path(__file__).resolve().parents[1], os.environ.get("PRIMORDIA_INSTANCE", "stable")))
