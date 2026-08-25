#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
tmp="$(mktemp -d /tmp/elis-smoke.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
ZIG_LOCAL_CACHE_DIR="$tmp/build-cache" \
ZIG_GLOBAL_CACHE_DIR="$tmp/global-cache" \
zig build native -Doptimize=ReleaseSafe >/dev/null

help_out="$(./zig-out/bin/elis --help 2>&1)"
grep -q 'Uso: elis' <<<"$help_out"
test -L ./zig-out/bin/lupinho-zig

# Exercise the same atomic save/load path used by the language and controls
# screens without touching the developer's real profile.
mkdir -p "$tmp/profile"
settings_out="$(env XDG_DATA_HOME="$tmp/profile" ./zig-out/bin/elis --self-test-settings 2>&1)"
grep -q 'settings round-trip: pass' <<<"$settings_out"

cp -R tests/api "$tmp/game"
dd if=/dev/zero of="$tmp/game/tile.bin" bs=1 count=1 status=none

run_game() {
  local target="$1"
  local output rc
  set +e
  output="$(timeout 1s env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./zig-out/bin/elis "$target" 2>&1)"
  rc=$?
  set -e
  test "$rc" -eq 124
  test -z "$output"
}

run_game "$tmp/game"
(cd "$tmp/game" && zip -q -r "$tmp/game.lupi" .)
run_game "$tmp/game.lupi"
run_game "$root/mazestein3d"
for demo in "$root"/demos/*; do
  [[ -f "$demo/game.lua" ]] && run_game "$demo"
done
echo "runtime smoke: pass"
