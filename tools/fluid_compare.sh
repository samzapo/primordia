#!/usr/bin/env bash
# Explicit diagnostic only. Steam discovery remains the default.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
mode="${1:-grid}"
if [[ $# -gt 0 ]]; then shift; fi
case "$mode" in
  validate) script=tests/fluid_compare_gpu.gd; options=() ;;
  resident) script=tests/fluid_solver_benchmark.gd; options=() ;;
  current|grid|pbf|uniform|liquidfun)
    script=tests/frame_profile.gd
    if [[ "$mode" == uniform || "$mode" == liquidfun ]]; then
      particle_mode="$mode"; mode=current
    else particle_mode=current; fi
    options=("--particle-engine=$particle_mode" "--fluid=$mode" --fixture=normal --locomotion=cilia --chemicals=20000 --frame-step=fixed --frames=180)
    ;;
  *) echo "Usage: tools/fluid_compare.sh {validate|resident|current|grid|pbf|uniform|liquidfun} [profile options]" >&2; exit 2 ;;
esac
if [[ "${PRIMORDIA_BACKEND:-native}" != script ]]; then "$project_dir/tools/build_native.sh" >&2; fi
# Optional arguments precede defaults so --chemicals/--frames etc can override.
exec "$godot_bin" --path "$project_dir" --rendering-method mobile --script "$script" -- --benchmark "$@" "${options[@]}"
