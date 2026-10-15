import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))
from deploy import retain_model_boundary, restore_model_boundary


class ModelRollback(unittest.TestCase):
    def test_generations_and_failed_state_survive_without_changing_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            state = root / "state"
            state.mkdir()
            keys = root / "access-keys.json"
            keys.write_text("fixture-existing-registry")
            for index in range(2):
                (state / f"world-{index}.pworld").write_bytes(f"old-generation-{index}".encode())
            backup = retain_model_boundary(state, root, "before-model-")
            for index in range(2):
                (state / f"world-{index}.pworld").write_bytes(f"new-generation-{index}".encode())
            restore_model_boundary(state, backup, root)
            failed = list(root.glob("failed-food-vacuoles-v1-*"))
            self.assertEqual(len(failed), 1)
            for index in range(2):
                self.assertEqual((state / f"world-{index}.pworld").read_bytes(), f"old-generation-{index}".encode())
                self.assertEqual((failed[0] / f"world-{index}.pworld").read_bytes(), f"new-generation-{index}".encode())
            self.assertEqual(keys.read_text(), "fixture-existing-registry")

    def test_corrupt_backup_fails_before_touching_current_world(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            state = root / "state"
            state.mkdir()
            (state / "world-0.pworld").write_bytes(b"old")
            backup = retain_model_boundary(state, root, "before-model-")
            (backup / "world-0.pworld").write_bytes(b"corrupt")
            (state / "world-0.pworld").write_bytes(b"new")
            with self.assertRaisesRegex(RuntimeError, "failed validation"):
                restore_model_boundary(state, backup, root)
            self.assertEqual((state / "world-0.pworld").read_bytes(), b"new")


if __name__ == "__main__":
    unittest.main()
