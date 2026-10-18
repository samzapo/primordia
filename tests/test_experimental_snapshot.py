#!/usr/bin/env python3
"""Isolated stable-copy, failure, immutable-source and serialized-graph tests."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from experimental_snapshot import capture
from deploy import retain_model_boundary, restore_model_boundary

def checkpoint(path, body):
    path.write_bytes(hashlib.sha256(body).hexdigest().encode()+b"\n"+body)

class SnapshotTests(unittest.TestCase):
    def test_only_checkpoints_are_copied_and_files_are_independent(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);stable=root/"stable";stable.mkdir();exp=root/"experimental";exp.mkdir()
            checkpoint(stable/"world-0.pworld",b"first")
            checkpoint(stable/"world-1.pworld",b"second")
            (stable/"feedback").mkdir();(stable/"feedback/private.json").write_text("private stable")
            (stable/"world-0.pworld.tmp").write_text("incomplete")
            before={p.name:p.read_bytes() for p in stable.glob("*.pworld")}
            copied,manifest=capture(stable,exp)
            self.assertEqual(set(p.name for p in copied.iterdir()),set(before))
            self.assertEqual({p.name:p.read_bytes() for p in copied.iterdir()},before)
            self.assertEqual(set(manifest),set(before))
            for name in before:
                self.assertNotEqual((copied/name).stat().st_ino,(stable/name).stat().st_ino)
            checkpoint(stable/"world-0.pworld",b"new main")
            self.assertEqual((copied/"world-0.pworld").read_bytes(),before["world-0.pworld"])

    def test_corrupt_generation_falls_back_but_no_valid_source_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);stable=root/"stable";stable.mkdir();exp=root/"experimental";exp.mkdir()
            (stable/"world-0.pworld").write_bytes(b"corrupt")
            checkpoint(stable/"world-1.pworld",b"valid")
            copied,manifest=capture(stable,exp)
            self.assertEqual(set(manifest),{"world-1.pworld"})
            (stable/"world-1.pworld").unlink()
            with self.assertRaises(RuntimeError):capture(stable,exp)

    def test_live_rename_keeps_the_open_generation_consistent(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);stable=root/"stable";stable.mkdir();exp=root/"experimental";exp.mkdir()
            slot=stable/"world-0.pworld";checkpoint(slot,b"old valid")
            replacement=stable/"next";checkpoint(replacement,b"new valid")
            original=os.open
            def publish_after_open(path,flags,*args,**kwargs):
                fd=original(path,flags,*args,**kwargs)
                if Path(path)==slot:os.replace(replacement,slot)
                return fd
            with patch("experimental_snapshot.os.open",side_effect=publish_after_open):
                copied,_=capture(stable,exp)
            self.assertTrue((copied/slot.name).read_bytes().endswith(b"old valid"))
            self.assertTrue(slot.read_bytes().endswith(b"new valid"))

    def test_aliases_and_oversized_sources_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);stable=root/"stable";stable.mkdir();exp=root/"experimental";exp.mkdir()
            checkpoint(stable/"world-0.pworld",b"source")
            with self.assertRaises(ValueError):capture(stable,stable)
            link=root/"link";link.symlink_to(stable,target_is_directory=True)
            with self.assertRaises(ValueError):capture(link,exp)
            (stable/"world-1.pworld").symlink_to(stable/"world-0.pworld")
            with self.assertRaises(OSError):capture(stable,exp)
            (stable/"world-1.pworld").unlink()
            with patch("experimental_snapshot.MAX_BYTES",8):
                with self.assertRaises(RuntimeError):capture(stable,exp)

    def test_failed_install_restores_the_experimental_predecessor_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);state=root/"state";state.mkdir()
            for name in ("world-0.pworld","world-1.pworld"):checkpoint(state/name,b"previous experiment")
            (state/"feedback").mkdir();report=state/"feedback/private.json";report.write_text("keep")
            backup=retain_model_boundary(state,root,"predecessor-")
            for name in ("world-0.pworld","world-1.pworld"):checkpoint(state/name,b"failed candidate")
            restore_model_boundary(state,backup,root,"failed-copy-")
            self.assertTrue((state/"world-0.pworld").read_bytes().endswith(b"previous experiment"))
            self.assertEqual(report.read_text(),"keep")

    @unittest.skipUnless(os.environ.get("GODOT_BIN"),"GODOT_BIN required for the real data-graph fixture")
    def test_real_checksummed_world_graph_and_repeated_updates(self):
        with tempfile.TemporaryDirectory(prefix="primordia-pond-fork-") as directory:
            project=Path(__file__).resolve().parents[1]
            result=subprocess.run([os.environ["GODOT_BIN"],"--headless","--path",str(project),
                "--script","tests/pond_fork_run.gd","--","--particle-backend=cpu"],
                env={**os.environ,"PRIMORDIA_FORK_FIXTURE":directory},capture_output=True,text=True,timeout=45)
            output=result.stdout+result.stderr
            self.assertEqual(result.returncode,0,output)
            self.assertRegex(output,r"POND FORK: [0-9]+ assertions, 0 failures")
            self.assertNotRegex(output,r"SCRIPT ERROR:|(?m:^ERROR:)|Parse Error:|Compile Error:")

if __name__=="__main__":unittest.main()
