#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  echo "Rendered-frame acceptance requires a hardware desktop display." >&2
  exit 1
fi
"$project_dir/tools/build_native.sh" >&2
report_file="$(mktemp "${TMPDIR:-/tmp}/primordia-frames.XXXXXX")"
trap 'rm -f -- "$report_file"' EXIT
for perception in exteroception interoception; do
  frame_trace="$project_dir/build/frame-budget-$perception.json"
  rm -f -- "$frame_trace"
  "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --audio-driver Dummy --resolution 1440x900 --script tests/frame_profile.gd -- --fixture=normal --fps-limit=60 --seconds=12 --particle-backend=resident --perception="$perception" --output="$frame_trace" 2>&1 | tee "$report_file"
  ! grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"
  python3 "$project_dir/tools/check_frame_budget.py" "$frame_trace"
done
