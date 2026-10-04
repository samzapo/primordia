#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
if ! command -v "$godot_bin" >/dev/null 2>&1; then
  echo "Install Godot 4.7.2 or set GODOT_BIN to its executable." >&2
  exit 1
fi
exec "$godot_bin" --path "$project_dir" "$@"
