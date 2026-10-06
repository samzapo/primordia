#!/usr/bin/env python3
"""Summarize a bounded frame_profile.gd trace without mixing nested phase times."""
import argparse
import collections
import json
import math
import statistics

def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered)-1, math.ceil(len(ordered)*fraction)-1)]

def report(data, discard=1):
    rows = data["rows"][discard:]
    if not rows:
        raise ValueError("Trace has no complete frames after discard")
    ticks = sum(row["ticks"] for row in rows)
    phase_names = sorted({key for row in rows for key in row["phases_ms"]})
    mean = statistics.mean(row["wall_ms"] for row in rows)
    result = {
        "frames": len(rows), "wall_mean_ms": mean, "fps": 1000/mean,
        "wall_p50_ms": percentile([r["wall_ms"] for r in rows], .5),
        "wall_p95_ms": percentile([r["wall_ms"] for r in rows], .95),
        "wall_max_ms": max(r["wall_ms"] for r in rows),
        "ticks": ticks, "ticks_per_frame": ticks/len(rows),
        "tick_histogram": dict(collections.Counter(r["ticks"] for r in rows)),
        "catchup_percent": 100*sum(r["ticks"] > 1 for r in rows)/len(rows),
        "capped_percent": 100*sum(r["ticks"] == data["max_steps"] for r in rows)/len(rows),
        "phase_mean_ms": {key: statistics.mean(r["phases_ms"].get(key,0) for r in rows) for key in phase_names},
        "sim_phase_per_tick_ms": {key: sum(r["phases_ms"].get(key,0) for r in rows)/ticks for key in phase_names if key.startswith("sim.")} if ticks else {},
        "count_per_tick": {key: sum(r["counts"].get(key,0) for r in rows)/ticks for key in sorted({k for r in rows for k in r["counts"]})} if ticks else {},
        "ranges": {key: [min(r[key] for r in rows),max(r[key] for r in rows)] for key in ["cells","active_cells","views","particles","active_particles","background_particles","pheromones","draw_calls"]},
        "render_boundary_mean_ms": statistics.mean(r["render_boundary_ms"] for r in rows),
        "engine_render_setup_mean_ms": statistics.mean(r["render_setup_ms"] for r in rows),
        "engine_render_cpu_mean_ms": statistics.mean(r["render_cpu_ms"] for r in rows),
        "engine_render_gpu_mean_ms": statistics.mean(r["render_gpu_ms"] for r in rows),
        "music_skip_delta": rows[-1]["audio_skips"]-rows[0]["audio_skips"],
        "music_skips_at_start": rows[0]["audio_skips"],
        "music_ready_percent": 100*sum(r["audio_ready"] for r in rows)/len(rows),
        "simulation_seconds": sum(r["sim_dt"] for r in rows),
        "wall_seconds": sum(r["wall_ms"] for r in rows)/1000,
    }
    # Lagged correlation: a long frame precedes additional fixed ticks.
    x = [r["wall_ms"] for r in rows[:-1]]
    y = [r["ticks"] for r in rows[1:]]
    if len(x)>1 and statistics.pstdev(x)>0 and statistics.pstdev(y)>0:
        mx,my = statistics.mean(x),statistics.mean(y)
        result["previous_frame_next_tick_correlation"] = sum((a-mx)*(b-my) for a,b in zip(x,y))/math.sqrt(sum((a-mx)**2 for a in x)*sum((b-my)**2 for b in y))
    else:
        result["previous_frame_next_tick_correlation"] = None
    # Top-level CPU callbacks + renderer boundary; nested timings must not be added.
    result["unattributed_mean_ms"] = statistics.mean(r["wall_ms"]-r["phases_ms"].get("ticks",0)-r["phases_ms"].get("process",0)-r["render_boundary_ms"] for r in rows)
    result["metadata"] = {k:v for k,v in data.items() if k!="rows"}
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace")
    parser.add_argument("--discard",type=int,default=1,help="Discard the initial partial frame (default 1)")
    args = parser.parse_args()
    with open(args.trace,encoding="utf-8") as source:
        print(json.dumps(report(json.load(source),args.discard),indent=2))

if __name__ == "__main__":
    main()
