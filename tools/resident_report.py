#!/usr/bin/env python3
"""Summarize frame distributions over time; never infer battery energy or game FPS."""
import json, math, statistics, sys
def summary(rows):
    if not rows:
        return {}
    wall = sorted(r["wall_ms"] for r in rows)
    return {"frames": len(rows), "mean_ms": statistics.mean(wall),
            "p95_ms": wall[min(len(wall)-1, math.ceil(.95*len(wall))-1)],
            "main_work_ms": statistics.mean(r["main_work_ms"] for r in rows),
            "delayed_render_gpu_ms": statistics.mean(r["render_gpu_ms"] for r in rows)}
def summarize(report):
    if not report.get("finite") or (report.get("interactions","off") != "chemistry" and report.get("material_before") != report.get("material_after")):
        raise ValueError("Invalid state or changed finite inventory")
    rows = report["rows"]
    windows = {}
    for row in rows:
        windows.setdefault(int(row["elapsed_s"]//30), []).append(row)
    return {"backend": report["backend"], "particles": report["particles"],
            "threads": report["threads"], "distribution": report["distribution"],
            "interactions": report.get("interactions","off"), "grid_backend": report.get("grid_backend","bitonic"),
            "warmup_alive": report.get("warmup_alive"), "final_alive": report.get("final_alive"),
            "material_before": report["material_before"], "material_after": report["material_after"],
            "material_validation": "Reaction yields require separate rule/ledger validation" if report.get("interactions") == "chemistry" else "Unchanged finite inventory",
            "fps_limit": report["fps_limit"], "duration_s": rows[-1]["elapsed_s"],
            "all": summary(rows),
            "completed_mean_upper_bound_ms": (sum(r["wall_ms"] for r in rows)+report.get("final_drain_and_readback_ms",0))/len(rows),
            "final_drain_and_readback_ms": report.get("final_drain_and_readback_ms"),
            "windows_30s": {str(k*30): summary(v) for k,v in windows.items()},
            "scope": report["scope"], "thermal": report["thermal"]}
if __name__ == "__main__":
    for filename in sys.argv[1:]:
        with open(filename) as f:
            print(json.dumps({"file": filename, **summarize(json.load(f))}, indent=2))
