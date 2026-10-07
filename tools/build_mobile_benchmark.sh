#!/usr/bin/env bash
# Build the same small native CPU reference into the generated export project.
# Existing pinned godot-cpp sources required; never download a mobile toolchain.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
mode="${1:-android}"
case "$mode" in android|desktop) ;; *) echo "Usage: tools/build_mobile_benchmark.sh {android|desktop}" >&2; exit 2;; esac
[[ -d build/godot-cpp/.git ]] || { echo "Run tools/build_native.sh first to prepare pinned bindings." >&2; exit 1; }
[[ "$(git -C build/godot-cpp rev-parse HEAD)" == 714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa ]] || { echo "Unexpected binding revision" >&2; exit 1; }
options=()
if [[ "$mode" == android ]]; then
  [[ -n "${ANDROID_NDK_ROOT:-}" && -f "$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" ]] || { echo "Set ANDROID_NDK_ROOT to an installed Android NDK; no toolchain is downloaded." >&2; exit 1; }
  options=(-DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24)
fi
python3 tools/prepare_mobile_benchmark.py
out="$root/build/resident-mobile/native/$mode"
cmake -S native/resident -B "build/resident-$mode" -DCMAKE_BUILD_TYPE=Release -DRESIDENT_OUTPUT_DIR="$out" "${options[@]}"
cmake --build "build/resident-$mode" --target primordia_resident --parallel "${PRIMORDIA_BUILD_JOBS:-2}"
cat > build/resident-mobile/native/resident.gdextension <<'EXTENSION'
[configuration]
entry_symbol="primordia_resident_init"
compatibility_minimum="4.4"
[libraries]
android.arm64="res://native/android/libprimordia_resident.so"
linux.x86_64="res://native/desktop/libprimordia_resident.so"
macos="res://native/desktop/libprimordia_resident.dylib"
EXTENSION
