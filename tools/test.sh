#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
if ! command -v "$godot_bin" >/dev/null 2>&1; then
  echo "Install Godot 4.7.2 or set GODOT_BIN to its executable." >&2
  exit 1
fi
report_file="$(mktemp "${TMPDIR:-/tmp}/primordia-test.XXXXXX")"
trap 'rm -f -- "$report_file"' EXIT
"$godot_bin" --headless --path "$project_dir" --script tests/run.gd 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then
  echo "Godot reported a script or runtime error." >&2
  exit 1
fi
if ! grep -Eq 'RESULT: [0-9]+ assertions, 0 failures' "$report_file"; then
  echo "The suite did not finish successfully." >&2
  exit 1
fi
