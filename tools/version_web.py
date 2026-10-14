#!/usr/bin/env python3
"""Give the exported game pack a content-specific URL without duplicating the engine."""
import hashlib
import json
from pathlib import Path
import re

CONFIG = re.compile(r"const GODOT_CONFIG = ([^\r\n]+);")

def version(web_root: Path) -> dict:
    page = web_root / "index.html"
    html = page.read_text()
    match = CONFIG.search(html)
    if match is None:
        raise ValueError("Exported page has no Godot configuration")
    config = json.loads(match.group(1))
    original = config.get("mainPack") or config["executable"] + ".pck"
    if Path(original).name != original or not original.endswith(".pck"):
        raise ValueError("Exported pack must be a filename within the web build")
    pack = web_root / original
    digest = hashlib.sha256(pack.read_bytes()).hexdigest()
    name = f"index-{digest[:24]}.pck"
    destination = web_root / name
    if pack != destination:
        if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
            raise ValueError("Existing versioned pack has different contents")
        pack.replace(destination)
    config["mainPack"] = name
    sizes = config.setdefault("fileSizes", {})
    sizes.pop(original, None)
    sizes[name] = destination.stat().st_size
    html = html[:match.start(1)] + json.dumps(config, separators=(",", ":")) + html[match.end(1):]
    pending = page.with_name("index.html.versioning")
    pending.write_text(html)
    pending.replace(page)
    return {"main_pack": name, "sha256": digest, "bytes": destination.stat().st_size}

if __name__ == "__main__":
    import sys
    print(json.dumps(version(Path(sys.argv[1]))))
