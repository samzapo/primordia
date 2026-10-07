#!/usr/bin/env python3
"""Read-only telemetry for one explicitly selected, already-authorized ADB device."""
import argparse, datetime, json, subprocess, time
from pathlib import Path
def read(serial, *args):
    try:
        result = subprocess.run(["adb", "-s", serial, "shell", *args],
                                capture_output=True, text=True, timeout=10)
        return {"ok": result.returncode == 0, "stdout": result.stdout, "stderr": result.stderr}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"ok": False, "error": str(error)}
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--serial", required=True)
    p.add_argument("--seconds", type=int, default=600)
    p.add_argument("--interval", type=int, default=30)
    p.add_argument("--label", required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    if not 1 <= a.seconds <= 1800 or not 5 <= a.interval <= 60:
        p.error("Use 1..1800 seconds and 5..60 second intervals")
    model = read(a.serial, "getprop", "ro.product.model")
    if not model["ok"]:
        p.error("Selected device unavailable: " + str(model))
    report = {"label": a.label, "model": model["stdout"].strip(),
              "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "note": "Read-only ADB observations. Battery temperature is not SoC temperature. "
                      "Charging/power state and OS thermal status must be interpreted separately; "
                      "battery-percent changes do not directly measure workload energy.",
              "samples": []}
    start = time.monotonic()
    while True:
        report["samples"].append({"elapsed_s": time.monotonic()-start,
                                  "thermalservice": read(a.serial, "dumpsys", "thermalservice"),
                                  "battery": read(a.serial, "dumpsys", "battery")})
        a.output.write_text(json.dumps(report, indent=2)+"\n")
        remaining = a.seconds-(time.monotonic()-start)
        if remaining <= 0:
            break
        time.sleep(min(a.interval, remaining))
if __name__ == "__main__":
    main()
