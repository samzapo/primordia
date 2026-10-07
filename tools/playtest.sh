#!/usr/bin/env bash
# Explicit desktop backend comparison; ordinary run.sh retains the CPU default.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
backend="${1:-resident}"
if [[ $# -gt 0 ]]; then shift; fi
case "$backend" in
  resident|cpu|cpu-matching) ;;
  *) echo "Usage: tools/playtest.sh [resident|cpu|cpu-matching] [Godot arguments]" >&2; exit 2;;
esac
export PRIMORDIA_PARTICLES="$backend"
exec "$project_dir/tools/run.sh" --rendering-method mobile "$@"
