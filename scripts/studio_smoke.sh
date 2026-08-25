#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
work="$(mktemp -d /tmp/elis-studio-smoke.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/build-cache" "$work/build-global"

ZIG_LOCAL_CACHE_DIR="$work/build-cache" \
ZIG_GLOBAL_CACHE_DIR="$work/build-global" \
zig build native -Doptimize=ReleaseSafe >/dev/null

env SDL_VIDEODRIVER=dummy \
  ./zig-out/bin/elis-studio \
  --project="$work/starter.elisworld" \
  --export="$work/starter.lua" \
  --save-export \
  --capture="$work/studio.bmp" \
  --smoke

test -s "$work/starter.elisworld"
test -s "$work/starter.lua"
test -s "$work/studio.bmp"
grep -q 'layers = { "background", "terrain", "objects", "foreground" }' "$work/starter.lua"
grep -q 'lupi_metadata = { editor = "ELIS Studio"' "$work/starter.lua"

# Reload the exact saved artifact through the native application path.
env SDL_VIDEODRIVER=dummy \
  ./zig-out/bin/elis-studio \
  --project="$work/starter.elisworld" \
  --export="$work/reloaded.lua" \
  --save-export \
  --smoke
cmp "$work/starter.lua" "$work/reloaded.lua"

# Load the exported table through the real compatible ui.map path. This proves
# that Studio metadata remains reserved and the strict layer array is accepted.
mkdir -p "$work/game/tiles"
cp "$work/reloaded.lua" "$work/game/map.lua"
head -c 256 /dev/zero > "$work/game/tiles/world"
printf '%s\n' \
  'local map = require("map")' \
  'function update()' \
  '  ui.cls(0)' \
  '  ui.map(map, 0, 0)' \
  'end' > "$work/game/game.lua"
printf '1 256 tiles/world {"type":"bitmap","width":16,"height":16,"tiles":1}\n' \
  > "$work/game/lupi_manifest.txt"
env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$work/game" 1 "$work/exported-map.ppm" >/dev/null
test -s "$work/exported-map.ppm"

echo "ELIS Studio native save/export/reload/simulator smoke: pass"
