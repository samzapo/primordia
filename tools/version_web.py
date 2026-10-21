#!/usr/bin/env python3
"""Give the exported game pack a content-specific URL without duplicating the engine."""
import hashlib
import json
from pathlib import Path
import re
import os

CONFIG = re.compile(r"const GODOT_CONFIG = ([^\r\n]+);")

def version(web_root: Path, instance: str = "stable") -> dict:
    if instance not in {"stable", "experimental"}: raise ValueError("Unknown game instance")
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
    if instance == "experimental":
        # A different IndexedDB mount, not merely different files in one mount.
        config["persistentPaths"] = ["/userfs/primordia-experimental"]
    sizes = config.setdefault("fileSizes", {})
    sizes.pop(original, None)
    sizes[name] = destination.stat().st_size
    html = html[:match.start(1)] + json.dumps(config, separators=(",", ":")) + html[match.end(1):]
    if instance == "experimental" and 'id="primordia-instance"' not in html:
        html = html.replace("</body>", '<aside id="primordia-instance" style="position:fixed;bottom:calc(8px + env(safe-area-inset-bottom, 0px));left:8px;z-index:5000;pointer-events:none;padding:4px 8px;border-radius:6px;background:#35234bd9;color:#f2ddff;font:14px sans-serif">Experimental pond</aside></body>')
    if "// primordia-touch-canvas:" not in html and "const engine = new Engine(GODOT_CONFIG);" in html:
        setup = (Path(__file__).resolve().parents[1] / "web/primordia_viewport.js").read_text()
        html = html.replace("const engine = new Engine(GODOT_CONFIG);", setup + "\nconst engine = new Engine(GODOT_CONFIG);", 1)
    if "$PRIMORDIA_SPLASH" in html:
        splash = (Path(__file__).resolve().parents[1] / "assets/ui/primordia-cell.svg").read_text()
        html = html.replace("$PRIMORDIA_SPLASH", splash)
    pending = page.with_name("index.html.versioning")
    pending.write_text(html)
    pending.replace(page)
    return {"main_pack": name, "sha256": digest, "bytes": destination.stat().st_size}

if __name__ == "__main__":
    import sys
    print(json.dumps(version(Path(sys.argv[1]), os.environ.get("PRIMORDIA_INSTANCE", "stable"))))
