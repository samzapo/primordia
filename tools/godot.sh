#!/usr/bin/env bash
# Shared resolver for Linux launchers. Steam app 404790 is Godot Engine.
# Source this file; no environment, registry, Steam, or installation changes.

steam_libraries() {
  local steam_root="$1" manifest
  printf '%s\n' "$steam_root"
  for manifest in "$steam_root/steamapps/libraryfolders.vdf" "$steam_root/config/libraryfolders.vdf"; do
    [ -f "$manifest" ] || continue
    # Modern VDF stores a path field; older versions store index/path pairs.
    # Paths are data, never shell code. Preserve spaces and escaped backslashes.
    awk -F '"' '
      function unescape(value, result, i, char) {
        result = ""
        for (i = 1; i <= length(value); i++) {
          char = substr(value, i, 1)
          if (char == "\\" && substr(value, i + 1, 1) == "\\") i++
          result = result char
        }
        return result
      }
      $2 == "path" || ($2 ~ /^[0-9]+$/ && $4 ~ /^\//) { print unescape($4) }
    ' "$manifest"
  done
}

steam_godot() {
  local steam_root library manifest install_dir executable install_root
  local -a roots=("$@")
  # Optional roots isolate integration fixtures without changing HOME.
  if [ "$#" -eq 0 ]; then
    [ -z "${STEAM_DIR:-}" ] || roots+=("$STEAM_DIR")
    roots+=(
      "$HOME/.steam/steam"
      "$HOME/.steam/root"
      "${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
      "$HOME/.local/share/Steam"
      "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
      "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    )
  fi
  for steam_root in "${roots[@]}"; do
    [ -d "$steam_root" ] || continue
    while IFS= read -r library; do
      manifest="$library/steamapps/appmanifest_404790.acf"
      [ -f "$manifest" ] || continue
      install_dir="$(awk -F '"' '$2 == "installdir" { print $4; exit }' "$manifest")"
      case "$install_dir" in ''|.|..|*/*) continue ;; esac
      install_root="$library/steamapps/common/$install_dir"
      for executable in \
        "$install_root/godot.x11.opt.tools.64" \
        "$install_root/godot.linuxbsd.editor.x86_64" \
        "$install_root/godot.linuxbsd.editor.arm64" \
        "$install_root/godot" \
        "$install_root"/Godot_v*.x86_64 \
        "$install_root"/Godot_v*.arm64; do
        if [ -f "$executable" ] && [ -x "$executable" ]; then
          printf '%s\n' "$executable"
          return 0
        fi
      done
    done < <(steam_libraries "$steam_root")
  done
  return 1
}

resolve_godot() {
  local executable
  if [ -n "${GODOT_BIN:-}" ]; then
    if executable="$(command -v "$GODOT_BIN")" && [ -f "$executable" ] && [ -x "$executable" ]; then
      printf '%s\n' "$executable"
      return 0
    fi
    printf 'GODOT_BIN is not an executable: %s\n' "$GODOT_BIN" >&2
    return 1
  fi
  if executable="$(steam_godot "$@")"; then
    printf '%s\n' "$executable"
    return 0
  fi
  for executable in godot4 godot; do
    if command -v "$executable" >/dev/null 2>&1; then
      command -v "$executable"
      return 0
    fi
  done
  cat >&2 <<'MESSAGE'
Godot was not found. Install Godot Engine in Steam, then retry.
Custom Steam root: STEAM_DIR=/path/to/Steam ./tools/run.sh
Explicit executable: GODOT_BIN=/path/to/godot ./tools/run.sh
MESSAGE
  return 1
}
