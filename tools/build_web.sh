#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/tools/godot.sh"
godot_bin="$(resolve_godot)"
web_project="$(python3 "$project_dir/tools/prepare_web.py")"
mkdir -p "$project_dir/build/web"
report_file="$(mktemp "${TMPDIR:-/tmp}/primordia-web-build.XXXXXX")"
trap 'rm -f -- "$report_file"' EXIT
checked_godot() {
  : > "$report_file"
  PRIMORDIA_BACKEND=script "$godot_bin" "$@" 2>&1 | tee "$report_file"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' "$report_file"; then
    echo "Godot reported an error while building the web client." >&2
    return 1
  fi
}
checked_godot --headless --path "$web_project" --script "$project_dir/tools/music_bank.gd" -- --output-dir="$project_dir/build/web" --manifest="$web_project/data/music_bank_manifest.json"
checked_godot --headless --path "$web_project" --editor --import --quit
checked_godot --headless --path "$web_project" --export-release Web "$project_dir/build/web/index.html"
python3 "$project_dir/tools/version_web.py" "$project_dir/build/web"

python3 "$project_dir/tools/check_web_music.py" "$project_dir/build/web"
