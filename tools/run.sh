#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
if [[ "${PRIMORDIA_BACKEND:-native}" != script ]]; then
  "$project_dir/tools/build_native.sh" >&2
fi
exec "$godot_bin" --path "$project_dir" "$@"
