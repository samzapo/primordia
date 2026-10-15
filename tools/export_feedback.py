#!/usr/bin/env python3
"""Export a bounded private feedback page without editing the server inbox."""
import argparse
import json
from pathlib import Path
import re

PATTERN = re.compile(r"[a-f0-9]{32}\.json")

def export(inbox: Path, before_report: str = "", limit: int = 50) -> dict:
    reports = []
    if inbox.exists():
        for path in sorted(inbox.iterdir()):
            if not PATTERN.fullmatch(path.name) or path.is_symlink():
                continue
            if path.stat().st_size > 32768:
                raise ValueError("Oversized feedback record")
            record = json.loads(path.read_text())
            if record.get("version") != 1 or record.get("id") != path.stem:
                raise ValueError("Invalid feedback record")
            reports.append({key: record[key] for key in ["id", "created_unix", "content", "context"]})
    reports.sort(key=lambda item: (item["created_unix"], item["id"]), reverse=True)
    total = len(reports)
    if before_report:
        index = next((i for i, item in enumerate(reports) if item["id"] == before_report), None)
        if index is None:
            raise ValueError("Unknown report cursor")
        reports = reports[index + 1:]
    selected = []
    for report in reports[:min(max(limit, 1), 50)]:
        if len(json.dumps(selected + [report], ensure_ascii=False).encode()) > 500000:
            break
        selected.append(report)
    more = len(reports) > len(selected)
    return {"version": 1, "total_reports": total, "exported": len(selected), "more": more,
            "next_cursor": selected[-1]["id"] if more and selected else "", "reports": selected}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inbox", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--before-report", default="")
    args = parser.parse_args()
    result = export(args.inbox, args.before_report)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(f'Exported {result["exported"]} of {result["total_reports"]} reports.')
    if result["more"]:
        print("More reports remain; next cursor: " + result["next_cursor"])

if __name__ == "__main__":
    main()
