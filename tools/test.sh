#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
if [[ "${PRIMORDIA_BACKEND:-native}" != script ]]; then
  "$project_dir/tools/build_native.sh" >&2
  cmake --build "$project_dir/build/native" --target primordia_worker_test --parallel "${PRIMORDIA_BUILD_JOBS:-2}" >&2
  "$project_dir/build/native/primordia_worker_test"
  cmake --build "$project_dir/build/native" --target primordia_dictionary_probe --parallel "${PRIMORDIA_BUILD_JOBS:-2}" >&2
  memory_report="$(mktemp "${TMPDIR:-/tmp}/primordia-memory.XXXXXX")"
  trap 'rm -f -- "$memory_report"' EXIT
  "$godot_bin" --headless --path "$project_dir" --script tests/native_dictionary_lifetime.gd 2>&1 | tee "$memory_report"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$memory_report" || ! grep -q 'DICTIONARY_RESULT: 8 assertions, 0 failures' "$memory_report"; then
    echo "Native Dictionary lifetime regression failed." >&2
    exit 1
  fi
  rm -f -- "$memory_report"
  trap - EXIT
fi
report_file="$(mktemp "${TMPDIR:-/tmp}/primordia-test.XXXXXX")"
trap 'rm -f -- "$report_file"' EXIT
# Fresh worktrees have no imported font/resources yet. Generate imports here
# and reject import errors before running an apparently successful partial suite.
"$godot_bin" --headless --path "$project_dir" --editor --import --quit 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then
  echo "Godot reported an import error." >&2
  exit 1
fi
"$godot_bin" --headless --path "$project_dir" --script tests/run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then
  echo "Godot reported a script or runtime error." >&2
  exit 1
fi
if ! grep -Eq 'RESULT: [0-9]+ assertions, 0 failures' "$report_file"; then
  echo "The suite did not finish successfully." >&2
  exit 1
fi

"$project_dir/tools/test_network.sh"
