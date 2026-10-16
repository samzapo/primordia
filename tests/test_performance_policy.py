import contextlib
import io
import json
import math
import os
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from performance_policy import evaluate

class PerformancePolicy(unittest.TestCase):
    good = {"simulation_hz": 30, "simulation_wall_ratio": 1, "tick_ms_p95": 20}
    def test_healthy_default_is_strict_and_clean(self):
        self.assertEqual(evaluate(self.good), [])
    def test_budget_miss_fails_by_default(self):
        for key, value in [("simulation_wall_ratio", .94), ("tick_ms_p95", 39)]:
            with self.assertRaises(ValueError): evaluate(dict(self.good, **{key:value}))
    def test_explicit_rollout_records_both_misses(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            warnings = evaluate(dict(self.good, simulation_wall_ratio=.94, tick_ms_p95=39), True)
        self.assertEqual({row["metric"] for row in warnings}, {"simulation_wall_ratio", "tick_ms_p95"})
        self.assertIn("::warning::", output.getvalue())
    def test_configured_cadence_and_invalid_or_stopped_measurements_remain_hard(self):
        for key,value in [("simulation_hz",15),("simulation_wall_ratio",math.nan),("simulation_wall_ratio",0),("tick_ms_p95",math.inf)]:
            with self.assertRaises(ValueError): evaluate(dict(self.good, **{key:value}), True)
    def test_real_godot_override_cannot_downgrade_functional_failures(self):
        godot = os.environ.get("GODOT_BIN")
        if not godot: self.skipTest("GODOT_BIN is required for the real policy fixture")
        for mode,functional,expected,warnings in [("0",False,1,0),("1",False,0,1),("1",True,1,1)]:
            env = os.environ.copy(); env["PRIMORDIA_PERFORMANCE_WARNINGS"]=mode
            command=[godot,"--headless","--path",str(ROOT),"--script","tests/deployment_warning_policy.gd","--","--particle-backend=cpu"]
            if functional: command.append("--functional-failure")
            result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=25)
            self.assertEqual(result.returncode, expected, result.stdout+result.stderr)
            line=next(row for row in result.stdout.splitlines() if row.startswith("POLICY_RESULT "))
            summary=json.loads(line.split(" ",1)[1])
            self.assertEqual(summary["performance_warnings"],warnings)
            self.assertNotIn("SCRIPT ERROR:",result.stdout+result.stderr)
            self.assertNotIn("Parse Error:",result.stdout+result.stderr)

if __name__=="__main__": unittest.main()
