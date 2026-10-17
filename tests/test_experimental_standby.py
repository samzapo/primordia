#!/usr/bin/env python3
"""Exercise suspension with temporary state, never a live service."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import experimental_standby as standby

class StandbyTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home=Path(self.tmp.name)
        self.root=self.home/".local/share/primordia-experimental"
        self.stable=self.home/".local/share/primordia-deploy"
        self.root.mkdir(parents=True);self.stable.mkdir()
        (self.root/"state/feedback").mkdir(parents=True)
        (self.root/"state/world-0.pworld").write_bytes(b"saved cells and accounts")
        (self.root/"state/world-1.pworld").write_bytes(b"previous saved cells and accounts")
        (self.root/"state/feedback/fixture.json").write_text("private fixture")
        (self.root/"access-keys.json").write_text("fixture registry")
        self.expected="a"*40
        self.baseline={"build":self.expected,"tick":100}
        self.health={"build":"b"*40,"world_id":"fixture-pond","backend":"gpu",
                     "backend_error":"","checkpoint_error":"","accounts":1,"access_keys":5}
        self.state={"MainPID":"0","ActiveState":"inactive","UnitFileState":"disabled"}
    def enter(self):
        with patch("pathlib.Path.home",return_value=self.home),patch.object(standby,"stable_identity",return_value=self.baseline),patch.object(standby,"guard",return_value={**self.baseline,"tick":101}),patch.object(standby,"get_json",return_value=self.health),patch.object(standby,"unit_status",side_effect=[self.state] if (self.root/"standby.json").exists() else [{"MainPID":"42","ActiveState":"active","UnitFileState":"enabled"},self.state]),patch.object(standby.time,"sleep"),patch.object(standby.subprocess,"run") as run:
            result=standby.enter(self.root,self.stable,self.expected)
        return result,run
    def test_only_experimental_stops_and_state_is_preserved(self):
        before=standby.protected(self.root)
        value,run=self.enter()
        run.assert_called_once_with(["systemctl","--user","disable","--now","primordia-experimental.service"],check=True)
        self.assertEqual(standby.protected(self.root),before)
        self.assertEqual(value["world_id"],"fixture-pond")
        self.assertEqual(value["accounts"],1)
        self.assertEqual(value["access_keys"],5)
        self.assertEqual((self.root/"standby.json").stat().st_mode&0o777,0o600)
        again,run=self.enter()
        self.assertEqual(value,again);run.assert_not_called()
    def test_wrong_stable_revision_cannot_stop_anything(self):
        with patch("pathlib.Path.home",return_value=self.home),patch.object(standby,"stable_identity",return_value=self.baseline),patch.object(standby.subprocess,"run") as run:
            with self.assertRaises(RuntimeError):standby.enter(self.root,self.stable,"c"*40)
            run.assert_not_called()
    def test_stable_root_is_never_a_standby_target(self):
        with patch("pathlib.Path.home",return_value=self.home),patch.object(standby.subprocess,"run") as run:
            with self.assertRaises(ValueError):standby.enter(self.stable,self.stable,self.expected)
            run.assert_not_called()
    def test_marked_standby_cannot_hide_an_active_unit(self):
        self.enter()
        for field,value in [("MainPID","123"),("ActiveState","active"),("UnitFileState","enabled")]:
            with self.subTest(field=field),patch.object(standby,"unit_status",return_value={**self.state,field:value}):
                with self.assertRaises(RuntimeError):standby.standby_identity(self.root)
    def test_checkpoint_keys_and_reports_cannot_change_silently(self):
        self.enter()
        for name in ["state/world-0.pworld","access-keys.json","state/feedback/fixture.json"]:
            path=self.root/name;before=path.read_bytes();path.write_bytes(before+b"change")
            with self.subTest(name=name),patch.object(standby,"unit_status",return_value=self.state):
                with self.assertRaises(RuntimeError):standby.standby_identity(self.root)
            path.write_bytes(before)
    def test_cached_stable_health_waits_for_a_fresh_tick(self):
        states=[{"MainPID":"42","ActiveState":"active","UnitFileState":"enabled"},self.state]
        with patch("pathlib.Path.home",return_value=self.home),patch.object(standby,"stable_identity",return_value=self.baseline),patch.object(standby,"guard",side_effect=[self.baseline]*3+[{**self.baseline,"tick":101}]),patch.object(standby,"get_json",return_value=self.health),patch.object(standby,"unit_status",side_effect=states),patch.object(standby.time,"sleep") as sleep,patch.object(standby.subprocess,"run"):
            value=standby.enter(self.root,self.stable,self.expected)
        self.assertEqual(value["state"],"standby");self.assertEqual(sleep.call_count,3)
    def test_interrupted_standby_finishes_without_starting_any_service(self):
        (self.root/"state/health.json").write_text(json.dumps(self.health))
        before=standby.protected(self.root)
        with patch("pathlib.Path.home",return_value=self.home),patch.object(standby,"stable_identity",return_value=self.baseline),patch.object(standby,"guard",return_value={**self.baseline,"tick":101}),patch.object(standby,"get_json") as request,patch.object(standby,"unit_status",return_value=self.state),patch.object(standby.subprocess,"check_output",return_value=self.health["build"]),patch.object(standby.subprocess,"run") as run:
            value=standby.enter(self.root,self.stable,self.expected)
        run.assert_not_called();request.assert_not_called()
        self.assertEqual(standby.protected(self.root),before)
        self.assertEqual(value["state"],"standby")
    def test_imported_service_query_supplies_user_bus_environment(self):
        for inherited in [{},{"XDG_RUNTIME_DIR":"/fixture/runtime"}]:
            with self.subTest(inherited=inherited),patch.dict(os.environ,inherited,clear=True),patch.object(standby.subprocess,"check_output",return_value="MainPID=0\nActiveState=inactive\nUnitFileState=disabled\n") as query:
                value=standby.unit_status()
                expected=inherited.get("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}")
                self.assertEqual(query.call_args.kwargs["env"]["XDG_RUNTIME_DIR"],expected)
                self.assertEqual(value,self.state)
                self.assertEqual(dict(os.environ),inherited)
    def test_bad_backend_refuses_suspension(self):
        self.health["backend_error"]="fixture failure"
        with patch("pathlib.Path.home",return_value=self.home),patch.object(standby,"stable_identity",return_value=self.baseline),patch.object(standby,"get_json",return_value=self.health),patch.object(standby,"unit_status",return_value={"MainPID":"42","ActiveState":"active","UnitFileState":"enabled"}),patch.object(standby.subprocess,"run") as run:
            with self.assertRaises(RuntimeError):standby.enter(self.root,self.stable,self.expected)
            run.assert_not_called()

if __name__=="__main__":unittest.main()
