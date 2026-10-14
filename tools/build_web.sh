#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
web_project="$(python3 "$project_dir/tools/prepare_web.py")"
mkdir -p "$project_dir/build/web"
PRIMORDIA_BACKEND=script "$godot_bin" --headless --path "$web_project" --script "$project_dir/tools/music_bank.gd" -- --output-dir="$project_dir/build/web" --manifest="$web_project/data/music_bank_manifest.json"
PRIMORDIA_BACKEND=script "$godot_bin" --headless --path "$web_project" --editor --import --quit
PRIMORDIA_BACKEND=script "$godot_bin" --headless --path "$web_project" --export-release Web "$project_dir/build/web/index.html"
python3 "$project_dir/tools/version_web.py" "$project_dir/build/web"

python3 "$project_dir/tools/check_web_music.py" "$project_dir/build/web"
