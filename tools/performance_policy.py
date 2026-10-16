"""Keep timing targets measurable while allowing an explicitly authorized rollout."""
import json
import math

def evaluate(metrics, allow_warnings=False):
    if metrics.get("simulation_hz") != 30:
        raise ValueError("Authority must retain its documented 30 Hz simulation cadence")
    ratio = float(metrics.get("simulation_wall_ratio", float("nan")))
    p95 = float(metrics.get("tick_ms_p95", float("nan")))
    if not math.isfinite(ratio) or ratio <= 0 or not math.isfinite(p95) or p95 < 0:
        raise ValueError("Authority timing measurements are invalid or stopped")
    warnings = []
    if not .98 <= ratio <= 1.02:
        warnings.append({"metric": "simulation_wall_ratio", "actual": ratio, "target_min": .98, "target_max": 1.02})
    if p95 > 1000 / 30:
        warnings.append({"metric": "tick_ms_p95", "actual": p95, "target_max": 1000 / 30})
    if warnings and not allow_warnings:
        raise ValueError("Authority misses its documented real-time 30 Hz budget: " + json.dumps(warnings))
    if warnings:
        print("::warning::Authorized rollout retains performance shortfalls: " + json.dumps(warnings), flush=True)
    return warnings
