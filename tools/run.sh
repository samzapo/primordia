#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
if [[ "${PRIMORDIA_BACKEND:-native}" != script ]]; then
  "$project_dir/tools/build_native.sh" >&2
fi
export PRIMORDIA_PARTICLES="${PRIMORDIA_PARTICLES:-resident}"
renderer_args=()
if [[ "$PRIMORDIA_PARTICLES" == resident ]]; then
  renderer_args=(--rendering-method mobile)
fi
exec "$godot_bin" --path "$project_dir" "${renderer_args[@]}" "$@"
