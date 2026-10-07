#!/usr/bin/env python3
"""Compare rendered fluid fixtures; distinguish fixed-tick throughput from live FPS."""
import argparse
import json
from pathlib import Path
from frame_report import report

def summarize(path):
    with path.open(encoding="utf-8") as source:
        data = json.load(source)
    # Fixed-step traces start with a full manually scheduled tick; live traces
    # retain their startup/zero-tick frames to expose the catch-up transition.
    measured = report(data, discard=0)
    seconds = measured["simulation_seconds"]
    result = {
        "trace": path.name, "fluid": data.get("fluid", "current"),
        "fixture": data["fixture"], "distribution": data.get("distribution"),
        "requested_chemicals": data.get("requested_chemicals"),
        "frame_step": data.get("frame_step", "live"),
        "frames": measured["frames"], "wall_seconds": measured["wall_seconds"],
        "simulation_seconds": seconds, "mean_ms": measured["wall_mean_ms"],
        "p50_ms": measured["wall_p50_ms"], "p95_ms": measured["wall_p95_ms"],
        "ticks": measured["ticks"], "tick_histogram": measured["tick_histogram"],
        "phase_mean_ms": measured["phase_mean_ms"],
        "phase_per_tick_ms": measured["sim_phase_per_tick_ms"],
        "ranges": measured["ranges"], "music_skip_delta": measured["music_skip_delta"],
        "quality": data.get("fluid_quality", {}),
        "settings": data.get("fluid_settings", {}),
        "body_feedback": data.get("fluid_feedback", "on"),
        "events": data.get("chemistry_events", {}),
        "events_per_sim_second": {
            kind: count/seconds if seconds else None
            for kind, count in data.get("chemistry_events", {}).items()
        },
        "packet_material_final": data.get("material_remaining"),
    }
    rate_name = ("fixed_tick_throughput_fps" if result["frame_step"] == "fixed"
                 else "rendered_fps")
    result[rate_name] = measured["fps"]
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("traces", type=Path, nargs="+")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    content = json.dumps({"comparisons": [summarize(p) for p in args.traces]}, indent=2)
    if args.output:
        args.output.write_text(content+"\n", encoding="utf-8")
    else:
        print(content)

if __name__ == "__main__":
    main()
