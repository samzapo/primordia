#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
export PRIMORDIA_INVITE=bounded-infrastructure-fixture
report_file="$(mktemp "${TMPDIR:-/tmp}/primordia-network.XXXXXX")"
trap 'rm -f -- "$report_file"' EXIT
for script in network_state network_live; do
  "$godot_bin" --headless --path "$project_dir" --script "tests/$script.gd" 2>&1 | tee "$report_file"
  ! grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"
  grep -Eq 'NETWORK (LIVE|CORRECTNESS): [0-9]+ assertions, 0 failures' "$report_file"
done
if [[ "${1:-}" == gpu ]]; then
  xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/resident_cytoplasm_gpu.gd 2>&1 | tee "$report_file"
  ! grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"
  grep -Eq 'CYTOPLASM GPU: [0-9]+ assertions, 0 failures' "$report_file"
  grep -Eq 'NVIDIA|AMD|Intel' "$report_file"
  ! grep -Eiq 'llvmpipe|lavapipe|swiftshader' "$report_file"
  for scope in fixture full-world slow-observer; do
    extra=()
    [[ "$scope" != full-world ]] || extra=(--full-world)
    [[ "$scope" != slow-observer ]] || extra=(--slow-observer)
    xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/network_live.gd -- --gpu "${extra[@]}" 2>&1 | tee "$report_file"
    ! grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:|returned to CPU' "$report_file"
    grep -Eq 'NETWORK LIVE: [0-9]+ assertions, 0 failures' "$report_file"
    grep -Eq 'NVIDIA|AMD|Intel' "$report_file"
    ! grep -Eiq 'llvmpipe|lavapipe|swiftshader' "$report_file"
  done
fi

"$godot_bin" --headless --path "$project_dir" --script tests/touch_zoom_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
! grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"
grep -Eq 'TOUCH CONTROLS: [0-9]+ assertions, 0 failures' "$report_file"

"$godot_bin" --headless --path "$project_dir" --script tests/world_status_run.gd 2>&1 | tee "$report_file"
! grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"
grep -Eq 'WORLD SELECTION: [0-9]+ assertions, 0 failures' "$report_file"

"$godot_bin" --headless --path "$project_dir" --script tests/perception_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
! grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"
grep -Eq 'PERCEPTION: [0-9]+ assertions, 0 failures' "$report_file"

"$godot_bin" --headless --path "$project_dir" --script tests/snapshot_transport.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
! grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"
grep -Eq 'SNAPSHOT TRANSPORT: [0-9]+ assertions, 0 failures' "$report_file"

python3 "$project_dir/tests/test_web_gateway.py"
python3 "$project_dir/tests/test_web_version.py"

"$godot_bin" --headless --path "$project_dir" --script tests/network_live.gd -- --personal-keys 2>&1 | tee "$report_file"
! grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"
grep -Eq 'NETWORK LIVE: [0-9]+ assertions, 0 failures' "$report_file"
