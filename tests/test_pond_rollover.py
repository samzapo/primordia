#!/usr/bin/env python3
"""Verify real exit-75 relaunch/durability, without a survival or balance run."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class PondRollover(unittest.TestCase):
    def test_empty_authority_relaunches_from_archived_state(self):
        project = Path(__file__).resolve().parents[1]
        godot = os.environ["GODOT_BIN"]
        with tempfile.TemporaryDirectory(prefix="primordia-runtime-restart-") as scratch:
            environment = dict(os.environ, PRIMORDIA_RUNTIME_RESTART_STATE=scratch,
                               PRIMORDIA_INVITE="bounded-rollover-fixture")
            environment.pop("PRIMORDIA_ACCESS_KEYS_FILE", None)
            command = [godot, "--headless", "--path", str(project), "--script",
                       "tests/pond_runtime_restart.gd"]
            for arguments, expected, marker in [(["--", "--die"], 75, "POND_RUNTIME_EXIT"),
                                                ([], 0, "POND_RUNTIME_RESUMED")]:
                result = subprocess.run(command + arguments, env=environment,
                                        capture_output=True, text=True, timeout=45)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, expected, output)
                self.assertIn(marker, output)
                self.assertNotRegex(output, r"SCRIPT ERROR:|(?m:^ERROR:)|Parse Error:|Compile Error:")


if __name__ == "__main__":
    unittest.main()
