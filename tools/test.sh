#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
if [[ "${PRIMORDIA_BACKEND:-native}" != script ]]; then
  "$project_dir/tools/build_native.sh" >&2
  cmake --build "$project_dir/build/native" --target primordia_worker_test --parallel "${PRIMORDIA_BUILD_JOBS:-2}" >&2
  "$project_dir/build/native/primordia_worker_test"
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
