#!/usr/bin/env python3
"""Web staging and zero-exit Godot-error regression checks."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare_web", ROOT / "tools/prepare_web.py")
prepare_web = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare_web)


class WebBuildTests(unittest.TestCase):
    def test_staged_client_includes_font_and_license_without_generated_imports(self):
        with tempfile.TemporaryDirectory(prefix="primordia-web-inputs-") as directory:
            source = Path(directory)
            for name in ("scripts", "shaders", "scenes", "data", "web"):
                (source / name).mkdir()
            font = source / "assets/fonts"
            font.mkdir(parents=True)
            for name in ("ComicNeue-Regular.ttf", "OFL.txt", "ComicNeue-Regular.ttf.import"):
                (font / name).write_text(name)
            (source / "project.godot").write_text(
                'renderer/rendering_method="mobile"\n')
            (source / "export_presets.cfg").write_text("")
            target = prepare_web.prepare(source)
            self.assertEqual((target / "assets/fonts/ComicNeue-Regular.ttf").read_text(),
                             "ComicNeue-Regular.ttf")
            self.assertEqual((target / "assets/fonts/OFL.txt").read_text(), "OFL.txt")
            self.assertFalse((target / "assets/fonts/ComicNeue-Regular.ttf.import").exists())
            self.assertIn('"gl_compatibility"', (target / "project.godot").read_text())

    def run_build(self, fail_stage=0, message="", engine_status=0):
        with tempfile.TemporaryDirectory(prefix="primordia-web-build-") as directory:
            source = Path(directory)
            tools = source / "tools"
            tools.mkdir()
            for name in ("build_web.sh", "godot.sh"):
                shutil.copyfile(ROOT / "tools" / name, tools / name)
            (tools / "prepare_web.py").write_text(
                "from pathlib import Path\nprint(Path(__file__).resolve().parents[1])\n")
            for name in ("version_web.py", "check_web_music.py"):
                (tools / name).write_text(
                    "from pathlib import Path\n"
                    "Path(__file__).with_suffix('.called').touch()\n")
            engine = source / "fake-godot"
            engine.write_text(
                "#!/usr/bin/env python3\n"
                "import os\nfrom pathlib import Path\n"
                "p=Path(__file__).with_suffix('.count')\n"
                "count=int(p.read_text())+1 if p.exists() else 1\n"
                "p.write_text(str(count))\n"
                "if count==int(os.environ['FAIL_STAGE']):\n"
                " print(os.environ['GODOT_ERROR'])\n"
                " raise SystemExit(int(os.environ['ENGINE_STATUS']))\n")
            engine.chmod(0o700)
            result = subprocess.run(["bash", str(tools / "build_web.sh")], text=True,
                                    capture_output=True, env={**os.environ,
                                        "GODOT_BIN": str(engine),
                                        "FAIL_STAGE": str(fail_stage),
                                        "GODOT_ERROR": message,
                                        "ENGINE_STATUS": str(engine_status)})
            called = [(tools / (name + ".called")).exists()
                      for name in ("version_web", "check_web_music")]
            count = int(engine.with_suffix(".count").read_text())
            return result, count, called

    def test_success_runs_all_stages_and_artifact_checks(self):
        result, count, called = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(count, 3)
        self.assertEqual(called, [True, True])

    def test_zero_exit_script_errors_stop_each_engine_stage(self):
        for stage in (1, 2, 3):
            with self.subTest(stage=stage):
                result, count, called = self.run_build(stage, "SCRIPT ERROR: Parse Error: missing font")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(count, stage)
                self.assertEqual(called, [False, False])

    def test_other_engine_errors_also_block_publication(self):
        for message in ("ERROR: Failed to load resource", "Compile Error: depended script"):
            with self.subTest(message=message):
                result, _, called = self.run_build(3, message)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(called, [False, False])

    def test_nonzero_engine_status_stops_build(self):
        result, count, called = self.run_build(2, "engine failed", 7)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, 2)
        self.assertEqual(called, [False, False])


if __name__ == "__main__":
    unittest.main()
