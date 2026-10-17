#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
export PRIMORDIA_INVITE=bounded-infrastructure-fixture
python3 "$project_dir/tests/test_experimental.py"
report_file="$(mktemp "${TMPDIR:-/tmp}/primordia-network.XXXXXX")"
trap 'rm -f -- "$report_file"; if [[ -n ${recovery_state:-} ]]; then rm -rf -- "$recovery_state"; fi' EXIT
"$godot_bin" --headless --path "$project_dir" --script tests/player_help_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'PLAYER HELP: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/release_notes_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'RELEASE NOTES: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/particle_charge_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'PARTICLE CHARGE: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/habitat_census_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'HABITAT CENSUS: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/particle_budget_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'PARTICLE BUDGET: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/feedback_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'FEEDBACK: [0-9]+ assertions, 0 failures' "$report_file"
python3 "$project_dir/tests/test_feedback.py"
"$godot_bin" --headless --path "$project_dir" --script tests/cell_retention_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'CELL RETENTION: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/nameplates_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'NAMEPLATES: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/normal_output_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'NORMAL OUTPUT: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/nutrient_binding_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'NUTRIENT BINDING: [0-9]+ assertions, 0 failures' "$report_file"
for script in anatomy_access_run feedback_latest_run shade_steering_run behavior_tree_run; do
  "$godot_bin" --headless --path "$project_dir" --script "tests/$script.gd" -- --particle-backend=cpu 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq '(ANATOMY ACCESS|FEEDBACK LATEST|SHADE STEERING|BEHAVIOR TREE): [0-9]+ assertions, 0 failures' "$report_file"
done
for script in induced_currents_run lineage_start_network camera_motion_run feedback_pass_network; do
  "$godot_bin" --headless --path "$project_dir" --script "tests/$script.gd" -- --particle-backend=cpu 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq '(INDUCED CURRENTS|LINEAGE START NETWORK|CAMERA MOTION|FEEDBACK PASS NETWORK): [0-9]+ assertions, 0 failures' "$report_file"
done
for script in camera_delivery_run camera_streaming_network; do
  "$godot_bin" --headless --path "$project_dir" --script "tests/$script.gd" -- --particle-backend=cpu 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq '(CAMERA DELIVERY|CAMERA STREAMING NETWORK): [0-9]+ assertions, 0 failures' "$report_file"
done
for script in light_field snapshot_playback network_state network_live; do
  "$godot_bin" --headless --path "$project_dir" --script "tests/$script.gd" 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq '(LIGHT FIELD|SNAPSHOT PLAYBACK|NETWORK LIVE|NETWORK CORRECTNESS): [0-9]+ assertions, 0 failures' "$report_file"
done
"$godot_bin" --headless --path "$project_dir" --script tests/pond_nutrition.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'POND NUTRITION: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/death_network.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'NETWORK DEATHS: [0-9]+ assertions, 0 failures' "$report_file"
"$godot_bin" --headless --path "$project_dir" --script tests/reproduction_accounting.gd 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'REPRODUCTION ACCOUNTING: [0-9]+ assertions, 0 failures' "$report_file"
recovery_state="$(mktemp -d "${TMPDIR:-/tmp}/primordia-recovery.XXXXXX")"
PRIMORDIA_RECOVERY_TEST_STATE="$recovery_state" "$godot_bin" --headless --path "$project_dir" --script tests/pond_recovery_accounting.gd 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'POND RECOVERY ACCOUNTING: [0-9]+ assertions, 0 failures' "$report_file"
rm -rf -- "$recovery_state"
recovery_state="$(mktemp -d "${TMPDIR:-/tmp}/primordia-restart.XXXXXX")"
PRIMORDIA_RESTART_TEST_STATE="$recovery_state" "$godot_bin" --headless --path "$project_dir" --script tests/pond_restart_network.gd 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'POND RESTART NETWORK: [0-9]+ assertions, 0 failures' "$report_file"
rm -rf -- "$recovery_state"
if [[ "${1:-}" == gpu ]]; then
  xvfb-run -a -s '-screen 0 1280x1000x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/feedback_visual_gpu.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq 'FEEDBACK VISUAL GPU: [0-9]+ assertions, 0 failures' "$report_file"
  xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/particle_budget_gpu.gd 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq 'PARTICLE BUDGET GPU: [0-9]+ assertions, 0 failures' "$report_file"
  xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/resident_environment_gpu.gd 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq 'ENVIRONMENT_VALIDATION [0-9]+ checks' "$report_file"
  xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/particle_stability_gpu.gd 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:|returned to CPU' "$report_file"; then exit 1; fi
  grep -Eq 'PARTICLE_STABILITY_VALIDATION [0-9]+ checks' "$report_file"
  grep -Eq 'NVIDIA|AMD|Intel' "$report_file"
  ! grep -Eiq 'llvmpipe|lavapipe|swiftshader' "$report_file"
  xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/nutrient_binding_run.gd -- --particle-backend=cpu --gpu 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq 'NUTRIENT BINDING: [0-9]+ assertions, 0 failures' "$report_file"
  xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/normal_output_run.gd -- --particle-backend=cpu --gpu 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq 'NORMAL OUTPUT: [0-9]+ assertions, 0 failures' "$report_file"
  xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/resident_plant_flow_gpu.gd 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:|returned to CPU' "$report_file"; then exit 1; fi
  grep -Eq 'RESIDENT PLANT FLOW: [0-9]+ assertions, 0 failures' "$report_file"
  grep -Eq 'NVIDIA|AMD|Intel' "$report_file"
  ! grep -Eiq 'llvmpipe|lavapipe|swiftshader' "$report_file"
  xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/resident_cytoplasm_gpu.gd 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq 'CYTOPLASM GPU: [0-9]+ assertions, 0 failures' "$report_file"
  grep -Eq 'NVIDIA|AMD|Intel' "$report_file"
  ! grep -Eiq 'llvmpipe|lavapipe|swiftshader' "$report_file"
  xvfb-run -a -s '-screen 0 1440x900x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --script tests/food_render_gpu.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq 'FOOD RENDER GPU: [0-9]+ assertions, 0 failures' "$report_file"
  # Browser presentation uses Compatibility; this is a pixel-correctness
  # fixture, separate from hardware resident simulation/performance checks.
  xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method gl_compatibility --rendering-driver opengl3 --script tests/vacuole_compatibility_gpu.gd 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
  grep -Eq 'VACUOLE COMPATIBILITY GPU: [0-9]+ assertions, 0 failures' "$report_file"
  for renderer in mobile gl_compatibility; do
    driver=vulkan
    [[ "$renderer" != gl_compatibility ]] || driver=opengl3
    xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method "$renderer" --rendering-driver "$driver" --script tests/membrane_render_gpu.gd 2>&1 | tee "$report_file"
    if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
    grep -Eq 'MEMBRANE RENDER GPU: [0-9]+ assertions, 0 failures' "$report_file"
    xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method "$renderer" --rendering-driver "$driver" --script tests/death_render_gpu.gd 2>&1 | tee "$report_file"
    if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
    grep -Eq 'DEATH RENDER GPU: [0-9]+ assertions, 0 failures' "$report_file"
    xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method "$renderer" --rendering-driver "$driver" --script tests/light_field_render_gpu.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
    if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
    grep -Eq 'LIGHT RENDER GPU: [0-9]+ assertions, 0 failures' "$report_file"
    xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method "$renderer" --rendering-driver "$driver" --script tests/water_tint_gpu.gd 2>&1 | tee "$report_file"
    if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
    grep -Eq 'WATER TINT GPU: [0-9]+ assertions, 0 failures' "$report_file"
    xvfb-run -a -s '-screen 0 1280x1600x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method "$renderer" --rendering-driver "$driver" --script tests/anatomy_render_gpu.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
    if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
    grep -Eq 'ANATOMY RENDER GPU: [0-9]+ assertions, 0 failures' "$report_file"
  done
  # Match run_service.py presentation pacing; chemistry/physics remain at 30 Hz.
  for scope in fixture full-world slow-observer recovery; do
    extra=()
    [[ "$scope" != full-world ]] || extra=(--full-world --realtime)
    [[ "$scope" != slow-observer ]] || extra=(--slow-observer)
    [[ "$scope" != recovery ]] || extra=(--recovery)
    xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --resolution 64x64 --disable-vsync --max-fps 60 --script tests/network_live.gd -- --gpu "${extra[@]}" 2>&1 | tee "$report_file"
    if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:|returned to CPU' "$report_file"; then exit 1; fi
    grep -Eq 'NETWORK LIVE: [0-9]+ assertions, 0 failures' "$report_file"
    grep -Eq 'NVIDIA|AMD|Intel' "$report_file"
    ! grep -Eiq 'llvmpipe|lavapipe|swiftshader' "$report_file"
  done
  if [[ -n "${PRIMORDIA_VERIFY_CHECKPOINT_DIR:-}" ]]; then
    xvfb-run -a -s '-screen 0 1280x720x24 -nolisten tcp' "$godot_bin" --path "$project_dir" --rendering-method mobile --rendering-driver vulkan --gpu-index 0 --resolution 64x64 --disable-vsync --max-fps 60 --script tests/realtime_checkpoint_gpu.gd 2>&1 | tee "$report_file"
    if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
    grep -Eq 'AGED CHECKPOINT GPU: [0-9]+ assertions, 0 failures' "$report_file"
  fi
fi

"$godot_bin" --headless --path "$project_dir" --script tests/restored_biology_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'RESTORED BIOLOGY: [0-9]+ assertions, 0 failures' "$report_file"

"$godot_bin" --headless --path "$project_dir" --script tests/touch_zoom_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'TOUCH CONTROLS: [0-9]+ assertions, 0 failures' "$report_file"

"$godot_bin" --headless --path "$project_dir" --script tests/mobile_vacuoles_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'MOBILE VACUOLES: [0-9]+ assertions, 0 failures' "$report_file"

"$godot_bin" --headless --path "$project_dir" --script tests/world_status_run.gd 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'WORLD SELECTION: [0-9]+ assertions, 0 failures' "$report_file"

"$godot_bin" --headless --path "$project_dir" --script tests/perception_run.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'PERCEPTION: [0-9]+ assertions, 0 failures' "$report_file"

"$godot_bin" --headless --path "$project_dir" --script tests/snapshot_transport.gd -- --particle-backend=cpu 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'SNAPSHOT TRANSPORT: [0-9]+ assertions, 0 failures' "$report_file"

GODOT_BIN="$godot_bin" python3 "$project_dir/tests/test_pond_rollover.py"
python3 "$project_dir/tests/test_web_gateway.py"
python3 "$project_dir/tests/test_web_version.py"
python3 "$project_dir/tests/test_web_build.py"
python3 "$project_dir/tests/test_model_rollback.py"
python3 "$project_dir/tests/test_authority_affinity.py"
GODOT_BIN="$godot_bin" python3 "$project_dir/tests/test_performance_policy.py"

"$godot_bin" --headless --path "$project_dir" --script tests/network_live.gd -- --personal-keys 2>&1 | tee "$report_file"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then exit 1; fi
grep -Eq 'NETWORK LIVE: [0-9]+ assertions, 0 failures' "$report_file"
