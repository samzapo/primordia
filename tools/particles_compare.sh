#!/usr/bin/env bash
# Standalone resident transport/rendering diagnostic. Steam remains the default.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
mode="${1:-gpu}"
if [[ $# -gt 0 ]]; then shift; fi
case "$mode" in
  validate) script=tests/resident_gpu.gd; options=() ;;
  gpu|cpu-texture|cpu-multimesh) script=tests/resident_benchmark.gd; options=("--backend=$mode") ;;
  *) echo "Usage: tools/particles_compare.sh {validate|gpu|cpu-texture|cpu-multimesh} [options]" >&2; exit 2 ;;
esac
if [[ "${PRIMORDIA_BACKEND:-native}" != script ]]; then "$project_dir/tools/build_native.sh" >&2; fi
exec "$godot_bin" --path "$project_dir" --rendering-method mobile --script "$script" -- "$@" "${options[@]}"
