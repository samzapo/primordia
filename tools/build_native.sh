#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
mkdir -p build
: > build/.gdignore
python3 "$project_dir/tools/compile_chemistry.py"
native_opt="${PRIMORDIA_NATIVE_OPT:-baseline}"
case "$native_opt" in baseline|lto|pgo-generate|pgo-use) ;; *) echo "Invalid PRIMORDIA_NATIVE_OPT" >&2; exit 2 ;; esac
profile_changed=false
if [[ "$native_opt" == pgo-use && -f build/native/.source_stamp ]] &&
   find build/native/pgo-data -type f -newer build/native/.source_stamp -print -quit | grep -q .; then
  profile_changed=true
fi
# Fast launches after a successful build. Source/config updates trigger a rebuild.
if [[ "$profile_changed" == false && -f build/native/.optimization_stamp && "$(cat build/native/.optimization_stamp)" == "$native_opt" && -f build/native/primordia.gdextension && -f build/native/libprimordia.so && -f build/native/.source_stamp ]] &&
   ! find native data tools/build_native.sh tools/compile_chemistry.py tools/fetch_liquidfun.py tools/patch_godot_cpp.py -type f -newer build/native/.source_stamp -print -quit | grep -q .; then
  exit 0
fi
# Pinned, reproducible dependency; generated bindings/binaries stay under build/.
revision=714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa
if [[ ! -d build/godot-cpp/.git ]]; then
  mkdir -p build
  git clone --depth 1 --branch godot-4.4-stable https://github.com/godotengine/godot-cpp.git build/godot-cpp
fi
[[ "$(git -C build/godot-cpp rev-parse HEAD)" == "$revision" ]] || { echo "Unexpected godot-cpp revision" >&2; exit 1; }
python3 "$project_dir/tools/fetch_liquidfun.py"
cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Release -DPRIMORDIA_NATIVE_OPT="$native_opt"
cmake --build build/native --target primordia --parallel "${PRIMORDIA_BUILD_JOBS:-2}"
cat > build/native/primordia.gdextension <<'EXTENSION'
[configuration]
entry_symbol = "primordia_library_init"
compatibility_minimum = "4.4"
[libraries]
linux.x86_64 = "res://build/native/libprimordia.so"
linux.arm64 = "res://build/native/libprimordia.so"
macos = "res://build/native/libprimordia.dylib"
EXTENSION
printf '%s\n' "$native_opt" > build/native/.optimization_stamp
touch build/native/.source_stamp
