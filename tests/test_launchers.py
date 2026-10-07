"""Integration fixtures for Steam discovery; does not change HOME or real installs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")


class SteamLaunchers(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="primordia-steam-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.steam = self.root / "Steam client"
        (self.steam / "steamapps").mkdir(parents=True)
        self.env = dict(os.environ, STEAM_DIR=str(self.steam), GODOT_BIN="", PRIMORDIA_BACKEND="script")

    def install(self, library, binary_name="godot.linuxbsd.editor.x86_64"):
        apps = library / "steamapps"
        folder = apps / "common" / "Godot Engine"
        folder.mkdir(parents=True, exist_ok=True)
        (apps / "appmanifest_404790.acf").write_text(
            '"AppState"\n{\n "appid" "404790"\n "installdir" "Godot Engine"\n}\n'
        )
        executable = folder / binary_name
        executable.write_text('#!/bin/sh\nprintf "<%s>\\n" "$@"\n')
        executable.chmod(0o755)
        return executable

    def resolve(self, env=None):
        # Explicit search root prevents fixtures from scanning real Steam installs.
        return subprocess.run(
            [BASH, "-c", 'set -euo pipefail; source "$1"; resolve_godot "$2"',
             "fixture", str(PROJECT / "tools/godot.sh"), str(self.steam)],
            env=env or self.env, text=True, capture_output=True,
        )

    def test_steam_wins_over_path_and_preserves_spaces(self):
        engine = self.install(self.steam)
        path_bin = self.root / "bin"
        path_bin.mkdir()
        (path_bin / "godot4").symlink_to(engine)
        self.env["PATH"] = str(path_bin) + os.pathsep + self.env["PATH"]
        result = self.resolve()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(engine))

    def test_modern_custom_library(self):
        library = self.root / "Games on second disk"
        engine = self.install(library, "godot.x11.opt.tools.64")
        (self.steam / "steamapps/libraryfolders.vdf").write_text(
            '"libraryfolders"\n{\n "1"\n {\n "path" "' + str(library) + '"\n }\n}\n'
        )
        self.assertEqual(self.resolve().stdout.strip(), str(engine))

    def test_legacy_custom_library_and_escaped_backslash(self):
        library = self.root / "Old Games\\Library"
        engine = self.install(library)
        config = self.steam / "config"
        config.mkdir()
        escaped = str(library).replace("\\", "\\\\")
        (config / "libraryfolders.vdf").write_text('"LibraryFolders"\n{\n "1" "' + escaped + '"\n}\n')
        self.assertEqual(self.resolve().stdout.strip(), str(engine))

    def test_explicit_override_wins_and_invalid_override_fails(self):
        self.install(self.steam)
        override = self.root / "chosen engine"
        override.write_text("#!/bin/sh\nexit 0\n")
        override.chmod(0o755)
        self.env["GODOT_BIN"] = str(override)
        self.assertEqual(self.resolve().stdout.strip(), str(override))
        self.env["GODOT_BIN"] = str(self.root / "missing")
        result = self.resolve()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("GODOT_BIN is not an executable", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_path_fallback(self):
        path_bin = self.root / "bin"
        path_bin.mkdir()
        engine = path_bin / "godot4"
        engine.write_text("#!/bin/sh\nexit 0\n")
        engine.chmod(0o755)
        self.env["PATH"] = str(path_bin) + os.pathsep + self.env["PATH"]
        self.assertEqual(self.resolve().stdout.strip(), str(engine))

    def test_missing_engine_has_actionable_error(self):
        path_bin = self.root / "bin"
        path_bin.mkdir()
        (path_bin / "cat").symlink_to(shutil.which("cat"))
        self.env["PATH"] = str(path_bin)
        result = self.resolve()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Install Godot Engine in Steam", result.stderr)

    def test_real_launcher_forwards_arguments_without_shell_expansion(self):
        self.install(self.steam)
        result = subprocess.run(
            [BASH, str(PROJECT / "tools/run.sh"), "--editor", "--", "text with spaces", "$(not-a-command)"],
            cwd=self.root, env=self.env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(),
                         ["<--path>", f"<{PROJECT}>", "<--editor>", "<-->",
                          "<text with spaces>", "<$(not-a-command)>"])


    def test_fluid_launcher_preserves_overrides_and_steam_discovery(self):
        self.install(self.steam)
        result = subprocess.run(
            [BASH, str(PROJECT / "tools/fluid_compare.sh"), "pbf",
             "--chemicals=50000", "--output=path with spaces"],
            cwd=self.root, env=self.env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            "<--path>", f"<{PROJECT}>", "<--rendering-method>", "<mobile>",
            "<--script>", "<tests/frame_profile.gd>", "<-->", "<--benchmark>",
            "<--chemicals=50000>", "<--output=path with spaces>", "<--particle-engine=current>", "<--fluid=pbf>",
            "<--fixture=normal>", "<--locomotion=cilia>", "<--chemicals=20000>",
            "<--frame-step=fixed>", "<--frames=180>",
        ])

    def test_original_particle_engine_modes(self):
        self.install(self.steam)
        for mode in ["uniform", "liquidfun"]:
            result = subprocess.run(
                [BASH, str(PROJECT / "tools/fluid_compare.sh"), mode, "--parcels=on"],
                cwd=self.root, env=self.env, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            arguments = result.stdout.splitlines()
            self.assertIn(f"<--particle-engine={mode}>", arguments)
            self.assertIn("<--fluid=current>", arguments)
            self.assertIn("<--parcels=on>", arguments)

    def test_fluid_launcher_rejects_unknown_solver(self):
        self.install(self.steam)
        result = subprocess.run(
            [BASH, str(PROJECT / "tools/fluid_compare.sh"), "unknown"],
            cwd=self.root, env=self.env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("Usage:", result.stderr)


    def test_resident_launcher_preserves_arguments(self):
        self.install(self.steam)
        for mode in ["gpu", "cpu-texture", "cpu-multimesh"]:
            result = subprocess.run(
                [BASH, str(PROJECT / "tools/particles_compare.sh"), mode,
                 "--count=50000", "--output=path with spaces"],
                cwd=self.root, env=self.env, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("<--backend=" + mode + ">", result.stdout.splitlines())
            self.assertIn("<--output=path with spaces>", result.stdout.splitlines())
        result = subprocess.run(
            [BASH, str(PROJECT / "tools/particles_compare.sh"), "bad"],
            cwd=self.root, env=self.env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
