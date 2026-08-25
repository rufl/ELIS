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

mkdir -p "$work/game/tiles"
head -c 4096 /dev/zero > "$work/game/tiles/world"
printf '%s\n' \
  'Palette = {' \
  '  [1] = 0x0000,' \
  '  [2] = 0x7C00,' \
  '  [3] = 0x03E0,' \
  '  [4] = 0x001F,' \
  '}' > "$work/game/palette.lua"
printf '1 4096 tiles/world {"type":"bitmap","width":16,"height":16,"tiles":16}\n' \
  > "$work/game/lupi_manifest.txt"

env SDL_VIDEODRIVER=dummy \
  ./zig-out/bin/elis-studio \
  --game-root="$work/game" \
  --project="$work/starter.elisworld" \
  --export="$work/starter.lua" \
  --save-export \
  --capture="$work/studio.bmp" \
  --smoke

test -s "$work/starter.elisworld"
test -s "$work/starter.lua"
test -s "$work/studio.bmp"
grep -q 'layers = { "background", "terrain", "objects", "foreground" }' "$work/starter.lua"
grep -q 'lupi_metadata = { editor = "ELIS Workshop", schema = 2' "$work/starter.lua"
grep -q 'smart_terrain = {' "$work/starter.lua"

# Reload the exact saved artifact through the compact, reduced-motion Studio
# presentation. Together with the roomy default capture this exercises both
# responsive density policies without pretending dummy-video is human QA.
env SDL_VIDEODRIVER=dummy \
  ./zig-out/bin/elis-studio \
  --game-root="$work/game" \
  --project="$work/starter.elisworld" \
  --export="$work/reloaded.lua" \
  --save-export \
  --presentation=studio \
  --reduce-motion \
  --window-width=960 \
  --window-height=600 \
  --capture="$work/studio-compact.bmp" \
  --smoke
cmp "$work/starter.lua" "$work/reloaded.lua"
test -s "$work/studio-compact.bmp"

# Load the exported table through the real compatible ui.map path. This proves
# that Studio metadata remains reserved and the strict layer array is accepted.
cp "$work/reloaded.lua" "$work/game/map.lua"
printf '%s\n' \
  'local map = require("map")' \
  'function update()' \
  '  ui.cls(0)' \
  '  ui.map(map, 0, 0)' \
  'end' > "$work/game/game.lua"
env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$work/game" 1 "$work/exported-map.ppm" >/dev/null
test -s "$work/exported-map.ppm"

echo "ELIS Workshop asset/palette/responsive/save/export/reload/simulator smoke: pass"
