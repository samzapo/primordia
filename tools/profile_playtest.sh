#!/usr/bin/env bash
# A bounded real-window capture using the same Steam/native launch path.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
backend="${1:-resident}"
if [[ $# -gt 0 ]]; then shift; fi
case "$backend" in
  resident|cpu|cpu-matching) ;;
  *) echo "Usage: tools/profile_playtest.sh [resident|cpu|cpu-matching] [profiler options]" >&2; exit 2;;
esac
mkdir -p "$project_dir/build/profiles"
output="$project_dir/build/profiles/playtest-$(date +%Y%m%d-%H%M%S)-$$.json"
export PRIMORDIA_PROFILE_COMMIT="$(git -C "$project_dir" rev-parse HEAD)"
export PRIMORDIA_PARTICLES="$backend"
particle_backend="$backend"
matching=off
if [[ "$backend" == cpu-matching ]]; then particle_backend=cpu; matching=on; fi
echo "Capturing gameplay at 80% play zoom; report: $output" >&2
exec "$project_dir/tools/run.sh" --rendering-method mobile --script tests/frame_profile.gd -- --benchmark   "$@" "--particle-backend=$particle_backend" "--pair-matching=$matching" --fixture=normal   --seconds=30 --fps-limit=60 --vsync=on --max-steps=auto "--output=$output"
