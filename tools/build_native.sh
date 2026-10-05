#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
mkdir -p build
: > build/.gdignore
# Fast launches after a successful build. Source/config updates trigger a rebuild.
if [[ -f build/native/primordia.gdextension && -f build/native/libprimordia.so && -f build/native/.source_stamp ]] &&
   ! find native tools/build_native.sh -type f -newer build/native/.source_stamp -print -quit | grep -q .; then
  exit 0
fi
# Pinned, reproducible dependency; generated bindings/binaries stay under build/.
revision=714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa
if [[ ! -d build/godot-cpp/.git ]]; then
  mkdir -p build
  git clone --depth 1 --branch godot-4.4-stable https://github.com/godotengine/godot-cpp.git build/godot-cpp
fi
[[ "$(git -C build/godot-cpp rev-parse HEAD)" == "$revision" ]] || { echo "Unexpected godot-cpp revision" >&2; exit 1; }
cmake -S native -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --target primordia --parallel "${PRIMORDIA_BUILD_JOBS:-2}"
cat > build/native/primordia.gdextension <<'EXTENSION'
[configuration]
entry_symbol = "primordia_library_init"
compatibility_minimum = "4.4"
[libraries]
linux.x86_64 = "res://build/native/libprimordia.so"
macos = "res://build/native/libprimordia.dylib"
EXTENSION
touch build/native/.source_stamp
