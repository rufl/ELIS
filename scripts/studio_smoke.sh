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
./zig-out/bin/elis-studio --self-test-atlas-identity

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
grep -q 'lupi_metadata = { editor = "ELIS Workshop", schema = 4' "$work/starter.lua"
grep -q 'entities = {' "$work/starter.lua"
grep -q 'entity_schemas = {' "$work/starter.lua"
grep -q 'smart_terrain = {' "$work/starter.lua"
grep -Fq 'solid = {[' "$work/starter.lua"
grep -q 'foreground = {},' "$work/starter.lua"
test "$(stat -c %s "$work/starter.lua")" -le $((128 * 1024))

# Export fails closed when a selected tileset exceeds lupi-codec's official
# 49,152-pixel ceiling, even though the source project remains saveable.
mkdir -p "$work/unsafe-game/tiles"
head -c 49408 /dev/zero > "$work/unsafe-game/tiles/world"
printf '1 49408 tiles/world {"type":"bitmap","width":16,"height":16,"tiles":193}\n' \
  > "$work/unsafe-game/lupi_manifest.txt"
if env SDL_VIDEODRIVER=dummy \
  ./zig-out/bin/elis-studio \
  --game-root="$work/unsafe-game" \
  --project="$work/unsafe.elisworld" \
  --export="$work/unsafe.lua" \
  --save-export \
  --smoke >/dev/null 2>&1; then
  echo "oversized Lupi tileset unexpectedly exported" >&2
  exit 1
fi
test ! -e "$work/unsafe.lua"

# Tile references must also fit the selected manifest asset.
mkdir -p "$work/short-game/tiles"
head -c 256 /dev/zero > "$work/short-game/tiles/world"
printf '1 256 tiles/world {"type":"bitmap","width":16,"height":16,"tiles":1}\n' \
  > "$work/short-game/lupi_manifest.txt"
if env SDL_VIDEODRIVER=dummy \
  ./zig-out/bin/elis-studio \
  --game-root="$work/short-game" \
  --project="$work/short.elisworld" \
  --export="$work/short.lua" \
  --template=platformer \
  --save-export \
  --smoke >/dev/null 2>&1; then
  echo "out-of-range Lupi tile unexpectedly exported" >&2
  exit 1
fi
test ! -e "$work/short.lua"

# A stale manifest cannot stand in for the exact on-disk bitmap bytes.
mkdir -p "$work/truncated-game/tiles"
head -c 4095 /dev/zero > "$work/truncated-game/tiles/world"
printf '1 4096 tiles/world {"type":"bitmap","width":16,"height":16,"tiles":16}\n' \
  > "$work/truncated-game/lupi_manifest.txt"
if env SDL_VIDEODRIVER=dummy \
  ./zig-out/bin/elis-studio \
  --game-root="$work/truncated-game" \
  --project="$work/truncated.elisworld" \
  --export="$work/truncated.lua" \
  --save-export \
  --smoke >/dev/null 2>&1; then
  echo "truncated Lupi tileset unexpectedly exported" >&2
  exit 1
fi
test ! -e "$work/truncated.lua"

# A named creation template must produce deterministic schema-aware source data
# without changing the default project path behavior above.
env SDL_VIDEODRIVER=dummy \
  ./zig-out/bin/elis-studio \
  --game-root="$work/game" \
  --project="$work/puzzle.elisworld" \
  --export="$work/puzzle.lua" \
  --template=puzzle \
  --save-export \
  --smoke
grep -q 'enemy = { name = "Crate"' "$work/puzzle.lua"
grep -q 'pickup = { name = "Switch"' "$work/puzzle.lua"
grep -q 'kind = "trigger"' "$work/puzzle.lua"

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
refresh_runtime_manifest() {
  printf '%s\n' \
    '1 4096 tiles/world {"type":"bitmap","width":16,"height":16,"tiles":16}' \
    "2 $(stat -c %s "$work/game/palette.lua") palette.lua {\"type\":\"lua_code\"}" \
    "3 $(stat -c %s "$work/game/map.lua") map.lua {\"type\":\"lua_code\"}" \
    "4 $(stat -c %s "$work/game/game.lua") game.lua {\"type\":\"lua_code\"}" \
    > "$work/game/lupi_manifest.txt"
}
printf '%s\n' \
  'local map = require("map")' \
  'assert(ui.stat(0) < 4 * 1024 * 1024)' \
  'function update()' \
  '  ui.cls(0)' \
  '  for _, layer in ipairs(map.layers) do ui.map(map[layer], 0, 0) end' \
  'end' > "$work/game/game.lua"
refresh_runtime_manifest
env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$work/game" 1 "$work/exported-map.ppm" >/dev/null
test -s "$work/exported-map.ppm"
printf '%s\n' \
  'local map = require("map")' \
  'function update()' \
  '  ui.cls(0)' \
  '  ui.map(map.map, 0, 0)' \
  'end' > "$work/game/game.lua"
refresh_runtime_manifest
env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$work/game" 1 "$work/exported-combined.ppm" >/dev/null
cmp "$work/exported-map.ppm" "$work/exported-combined.ppm"

echo "ELIS Workshop asset/palette/responsive/save/export/reload/simulator smoke: pass"
