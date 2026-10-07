#!/usr/bin/env python3
"""Generate a small isolated Godot export project from retained authored inputs."""
from pathlib import Path
import shutil
ROOT = Path(__file__).resolve().parents[1]
FILES = [
    "shaders/compute/resident_contacts.glsl.txt", "shaders/compute/resident_vote.glsl.txt",
    "shaders/compute/resident_commit.glsl.txt",
    "scripts/resident_particles.gd", "scripts/resident_fixture.gd",
    "scripts/resident_benchmark.gd", "scripts/resident_mobile.gd",
    "scripts/particle_art.gd", "shaders/resident_particles.gdshader",
    "shaders/compute/resident_particles.glsl.txt", "scenes/resident_mobile.tscn",
]
def prepare():
    out = ROOT / "build" / "resident-mobile"
    # Retired generated shader name from the initial import-based prototype.
    for name in ["shaders/compute/resident_particles.glsl", "shaders/compute/resident_particles.glsl.import"]:
        (out / name).unlink(missing_ok=True)
    for name in FILES:
        dst = out / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, dst)
    (out / "project.godot").write_text('''config_version=5
[application]
config/name="Primordia Particle Benchmark"
run/main_scene="res://scenes/resident_mobile.tscn"
config/features=PackedStringArray("4.7", "Mobile")
[display]
window/size/viewport_width=1440
window/size/viewport_height=900
window/stretch/mode="canvas_items"
window/handheld/orientation=0
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
environment/defaults/default_clear_color=Color(0.063,0.176,0.224,1)
''')
    (out / "export_presets.cfg").write_text('''[preset.0]
name="Android benchmark"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter="*.txt"
exclude_filter=""
export_path=""
[preset.0.options]
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
package/unique_name="org.primordia.particlebenchmark"
package/name="Primordia Particle Benchmark"
permissions/internet=false
''')
    print(out)
if __name__ == "__main__":
    prepare()
