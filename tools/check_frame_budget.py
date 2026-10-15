#!/usr/bin/env python3
"""Enforce the first-cell normal rendered workload on real hardware."""
import json
import sys
from frame_report import report


def check(data):
    result = report(data)
    gpu = data.get("gpu", "").lower()
    if not gpu or any(name in gpu for name in ("llvmpipe", "lavapipe", "swiftshader")):
        raise ValueError("Frame budget requires a hardware GPU")
    if data.get("backend") != "resident" or data.get("zoom") != .8 or not data.get("music"):
        raise ValueError("Expected resident backend, widest playable view and music")
    ratio = result["simulation_seconds"] / result["wall_seconds"]
    # Historical first-cell: 60 FPS, 18.70 ms p95. Allow ordinary display jitter,
    # while rejecting slow simulation or the previous second-long stalls.
    if result["fps"] < 59 or result["wall_p95_ms"] > 20.5 or not .98 <= ratio <= 1.02:
        raise ValueError(f"Frame budget missed: {result['fps']:.2f} FPS, p95 {result['wall_p95_ms']:.2f} ms, {ratio:.3f}x simulation")
    return {"fps": result["fps"], "p95_ms": result["wall_p95_ms"], "simulation_wall_ratio": ratio,
            "cells": result["ranges"]["cells"], "gpu": data["gpu"]}


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as source:
        print("FRAME_BUDGET " + json.dumps(check(json.load(source)), sort_keys=True))
