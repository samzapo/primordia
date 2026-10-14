#!/usr/bin/env python3
"""Check that changed client packs cannot share a cached download URL."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from version_web import CONFIG, version

class WebVersion(unittest.TestCase):
    def export(self, root, payload):
        (root / "index.pck").write_bytes(payload)
        config = {"executable":"index", "experimentalVK":True, "args":[],
                  "fileSizes":{"index.pck":len(payload), "index.wasm":4}}
        (root / "index.html").write_text("before\nconst GODOT_CONFIG = " + json.dumps(config) + ";\nafter")

    def test_pack_updates_get_new_urls_while_engine_is_reused(self):
        with tempfile.TemporaryDirectory(prefix="primordia-web-version-") as directory:
            root = Path(directory)
            (root / "index.wasm").write_bytes(b"wasm")
            (root / "index.js").write_text("engine runtime")
            self.export(root, b"old client")
            before = version(root)
            self.assertFalse((root / "index.pck").exists())
            self.export(root, b"corrected client")
            after = version(root)
            self.assertNotEqual(before["main_pack"], after["main_pack"])
            self.assertEqual((root / before["main_pack"]).read_bytes(), b"old client")
            self.assertEqual((root / after["main_pack"]).read_bytes(), b"corrected client")
            config = json.loads(CONFIG.search((root / "index.html").read_text()).group(1))
            self.assertEqual(config["mainPack"], after["main_pack"])
            self.assertEqual(config["fileSizes"][after["main_pack"]], len(b"corrected client"))
            self.assertNotIn("index.pck", config["fileSizes"])
            self.assertEqual(config["executable"], "index")
            self.assertTrue(config["experimentalVK"])
            self.assertEqual((root / "index.wasm").read_bytes(), b"wasm")
            self.assertEqual((root / "index.js").read_text(), "engine runtime")
            self.assertTrue((root / "index.html").read_text().startswith("before\n"))
            self.assertTrue((root / "index.html").read_text().endswith("\nafter"))
            page = (root / "index.html").read_bytes()
            self.assertEqual(version(root), after)
            self.assertEqual((root / "index.html").read_bytes(), page)

    def test_identical_exports_have_identical_pack_urls(self):
        with tempfile.TemporaryDirectory(prefix="primordia-web-version-") as directory:
            root = Path(directory)
            self.export(root, b"same client")
            first = version(root)
            self.export(root, b"same client")
            self.assertEqual(version(root), first)

    def test_invalid_manifest_preserves_existing_inputs(self):
        with tempfile.TemporaryDirectory(prefix="primordia-web-version-") as directory:
            root = Path(directory)
            self.export(root, b"retained client")
            page = root / "index.html"
            page.write_text('const GODOT_CONFIG = {"mainPack":"../outside.pck"};')
            with self.assertRaises(ValueError):version(root)
            self.assertEqual((root / "index.pck").read_bytes(), b"retained client")
            page.write_text("no engine manifest")
            with self.assertRaises(ValueError):version(root)
            self.assertEqual((root / "index.pck").read_bytes(), b"retained client")

if __name__ == "__main__":unittest.main()
