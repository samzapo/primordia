#!/usr/bin/env python3
"""Provision checksum-pinned Godot and only web templates in a private runtime."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

from check_wired_route import verify

def digest(path):
    value = hashlib.sha512()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

def download(asset, target):
    if target.exists() and digest(target) == asset["sha512"]:
        return
    verify()
    partial = target.with_suffix(target.suffix + ".part")
    job = subprocess.Popen(["curl", "--fail", "--location", "--retry", "2",
                            "--silent", "--show-error", "--output", str(partial), asset["url"]])
    try:
        while True:
            try:
                result = job.wait(timeout=15)
                break
            except subprocess.TimeoutExpired:
                verify()
        if result:
            raise RuntimeError("Official runtime download failed")
        verify()
    except BaseException:
        job.terminate()
        job.wait()
        raise
    if digest(partial) != asset["sha512"]:
        raise RuntimeError(f"Checksum mismatch; incomplete media retained at {partial}")
    partial.replace(target)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    root = args.runtime_dir.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    recipe = json.loads(Path(__file__).with_name("toolchain.json").read_text())
    version = recipe["version"]
    binary = root / f"Godot_v{version}-stable_linux.x86_64"
    archive = root / f"Godot_v{version}-stable_linux.x86_64.zip"
    download(recipe["assets"][archive.name], archive)
    if not binary.exists():
        with zipfile.ZipFile(archive) as media:
            binary.write_bytes(media.read(binary.name))
        binary.chmod(0o755)
    (root / "_sc_").touch()
    templates = root / f"Godot_v{version}-stable_export_templates.tpz"
    download(recipe["assets"][templates.name], templates)
    destination = root / "editor_data/export_templates" / f"{version}.stable"
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(templates) as media:
        for member in media.namelist():
            name = Path(member).name
            if name.startswith("web") and name.endswith(".zip"):
                final = destination / name
                if not final.exists():
                    with media.open(member) as source, final.open("wb") as output:
                        while block := source.read(1024 * 1024):
                            output.write(block)
    print(f"Godot runtime: {binary}", flush=True)

if __name__ == "__main__":
    main()
