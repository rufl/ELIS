#!/usr/bin/env bash
set -euo pipefail

# Every invocation, including malformed-archive failures, must stay headless.
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
tmp="$(mktemp -d /tmp/elis-smoke.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

# Valid manifest metadata can exhaust Lua before any cartridge code executes.
# It must report a load failure rather than aborting outside lua_pcall.
python3 - "$tmp/sprite-heap" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
prefix = "/".join("d" * 120 + str(i) for i in range(6))
(root / prefix).mkdir(parents=True)
game = b"function update() end\n"
(root / "game.lua").write_bytes(game)
rows = [f"1 {len(game)} game.lua {{}}"]
for index in range(4080):
    relative = f"{prefix}/{index:04d}" + "x" * 196
    (root / relative).write_bytes(b"\1")
    rows.append(f'{index + 2} 1 {relative} {{"type":"bitmap","width":1,"height":1}}')
(root / "lupi_manifest.txt").write_text("\n".join(rows) + "\n")
PY
ZIG_LOCAL_CACHE_DIR="$tmp/build-cache" \
ZIG_GLOBAL_CACHE_DIR="$tmp/global-cache" \
zig build native -Doptimize=ReleaseSafe >/dev/null

set +e
sprite_heap_output="$(./zig-out/bin/elis --screenshot "$tmp/sprite-heap" 1 "$tmp/sprite-heap.ppm" 2>&1)"
sprite_heap_rc=$?
set -e
test "$sprite_heap_rc" -eq 1
grep -q 'sprite initialization.*not enough memory' <<<"$sprite_heap_output"
test ! -e "$tmp/sprite-heap.ppm"

help_out="$(./zig-out/bin/elis --help 2>&1)"
grep -q '^Usage:$' <<<"$help_out"
grep -q 'elis --benchmark GAME_DIRECTORY FRAMES' <<<"$help_out"
test -L ./zig-out/bin/lupinho-zig
ldd ./zig-out/bin/elis | grep -q 'liblua5.4'
constraints="$(./zig-out/bin/elis --lupi-constraints 2>&1)"
grep -q '^LUPI_CONSTRAINTS_V1$' <<<"$constraints"
grep -q '^lua=5.4$' <<<"$constraints"
grep -q '^esp32_psram_bytes=8388608$' <<<"$constraints"
grep -q '^lua_heap_bytes_max=4194304$' <<<"$constraints"
grep -q '^archive_entries_max=4096$' <<<"$constraints"
grep -q '^host_demo_download_bytes_max=67108864$' <<<"$constraints"
grep -q '^discrete_gpu=none$' <<<"$constraints"
grep -q '^player_slots=3$' <<<"$constraints"
grep -q '^tileset_pixels_max=49152$' <<<"$constraints"
grep -q '^raster_work_items_max=2073600$' <<<"$constraints"
grep -q '^runtime_map_layers_max=256$' <<<"$constraints"
grep -q '^map_layer_limit=not_published$' <<<"$constraints"
grep -q '^workshop_lua_data_entries_max=4096$' <<<"$constraints"
grep -q '^workshop_lua_source_bytes_max=131072$' <<<"$constraints"

# Exercise the same atomic save/load path used by the language and controls
# screens without touching the developer's real profile.
mkdir -p "$tmp/profile"
settings_out="$(env XDG_DATA_HOME="$tmp/profile" ./zig-out/bin/elis --self-test-settings 2>&1)"
grep -q 'settings round-trip: pass' <<<"$settings_out"
python3 scripts/settings_upgrade_smoke.py

mkdir -p "$tmp/init-constants"
printf '%s\n' \
  'assert(BTN_Z ~= nil and UP ~= nil)' \
  'local captured = BTN_Z' \
  'function update() assert(captured == BTN_Z) end' \
  > "$tmp/init-constants/game.lua"
./zig-out/bin/elis --screenshot "$tmp/init-constants" 1 "$tmp/init-constants.ppm" >/dev/null

mkdir -p "$tmp/frame-error"
printf 'function update() error("frame failure") end\n' > "$tmp/frame-error/game.lua"
set +e
frame_error_output="$(./zig-out/bin/elis --screenshot "$tmp/frame-error" 1 "$tmp/frame-error.ppm" 2>&1)"
frame_error_rc=$?
set -e
test "$frame_error_rc" -ne 0
grep -q 'frame failure' <<<"$frame_error_output"
test ! -e "$tmp/frame-error.ppm"
set +e
benchmark_error_output="$(./zig-out/bin/elis --benchmark "$tmp/frame-error" 1 2>&1)"
benchmark_error_rc=$?
set -e
test "$benchmark_error_rc" -ne 0
grep -q 'frame failure' <<<"$benchmark_error_output"

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

# Physical Lupi mode reserves half of the ESP32-S3 N16R8's 8 MiB PSRAM for
# engine/assets/audio, so an individual game cannot grow Lua beyond 4 MiB.
mkdir -p "$tmp/heap-limit"
printf '%s\n' \
  'local oversized = string.rep("x", 5 * 1024 * 1024)' \
  'function update() end' > "$tmp/heap-limit/game.lua"
set +e
heap_output="$(./zig-out/bin/elis --screenshot "$tmp/heap-limit" 1 "$tmp/heap-limit.ppm" 2>&1)"
heap_rc=$?
set -e
test "$heap_rc" -ne 0
grep -q 'not enough memory' <<<"$heap_output"
test ! -e "$tmp/heap-limit.ppm"

# A compressed archive cannot expand beyond the N16 flash ceiling.
mkdir -p "$tmp/flash-limit"
printf 'function update() end\n' > "$tmp/flash-limit/game.lua"
truncate -s $((17 * 1024 * 1024)) "$tmp/flash-limit/oversized.bin"
(cd "$tmp/flash-limit" && zip -q -r "$tmp/flash-limit.lupi" .)
set +e
flash_output="$(./zig-out/bin/elis "$tmp/flash-limit.lupi" 2>&1)"
flash_rc=$?
set -e
test "$flash_rc" -ne 0
grep -q 'InvalidLupiArchive' <<<"$flash_output"

# Compressed input and central-directory work are bounded even when payloads
# are tiny, preventing oversized or metadata-heavy archives from stalling load.
cp "$tmp/game.lupi" "$tmp/oversized-archive.lupi"
dd if=/dev/zero bs=1M count=17 status=none >> "$tmp/oversized-archive.lupi"
set +e
archive_output="$(./zig-out/bin/elis "$tmp/oversized-archive.lupi" 2>&1)"
archive_rc=$?
set -e
test "$archive_rc" -ne 0
grep -q 'InvalidLupiArchive' <<<"$archive_output"
python3 - "$tmp/entry-limit.lupi" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    for index in range(4097):
        archive.writestr(f"empty/{index}", b"")
PY
set +e
entry_output="$(./zig-out/bin/elis "$tmp/entry-limit.lupi" 2>&1)"
entry_rc=$?
set -e
test "$entry_rc" -ne 0
grep -q 'InvalidLupiArchive' <<<"$entry_output"
escape_name="elis-runtime-smoke-escape-$$"
python3 - "$tmp/traversal.lupi" "$escape_name" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("../" + sys.argv[2], b"unsafe")
PY
set +e
traversal_output="$(./zig-out/bin/elis "$tmp/traversal.lupi" 2>&1)"
traversal_rc=$?
set -e
test "$traversal_rc" -ne 0
grep -q 'InvalidLupiArchive' <<<"$traversal_output"
test ! -e "/tmp/$escape_name"
python3 - "$tmp/backslash.lupi" "$tmp/duplicate.lupi" <<'PY'
import sys
import warnings
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("nested\\payload", b"unsafe")
with warnings.catch_warnings():
    warnings.simplefilter("ignore", UserWarning)
    with zipfile.ZipFile(sys.argv[2], "w") as archive:
        archive.writestr("game.lua", b"function update() end\n")
        archive.writestr("game.lua", b"function update() error('shadowed') end\n")
PY
for hostile_archive in "$tmp/backslash.lupi" "$tmp/duplicate.lupi"; do
  set +e
  hostile_output="$(./zig-out/bin/elis "$hostile_archive" 2>&1)"
  hostile_rc=$?
  set -e
  test "$hostile_rc" -ne 0
  grep -q 'InvalidLupiArchive' <<<"$hostile_output"
done

mkdir -p "$tmp/manifest-limit"
printf 'function update() end\n' > "$tmp/manifest-limit/game.lua"
printf '1 %d payload.bin {"type":"data"}\n' $((17 * 1024 * 1024)) \
  > "$tmp/manifest-limit/lupi_manifest.txt"
set +e
manifest_output="$(./zig-out/bin/elis --screenshot "$tmp/manifest-limit" 1 "$tmp/manifest-limit.ppm" 2>&1)"
manifest_rc=$?
set -e
test "$manifest_rc" -ne 0
grep -q 'GameExceedsLupiFlash' <<<"$manifest_output"
mkdir -p "$tmp/manifest-malformed"
printf 'function update() end\n' > "$tmp/manifest-malformed/game.lua"
printf 'malformed\n' > "$tmp/manifest-malformed/lupi_manifest.txt"
set +e
malformed_output="$(./zig-out/bin/elis --screenshot "$tmp/manifest-malformed" 1 "$tmp/malformed.ppm" 2>&1)"
malformed_rc=$?
set -e
test "$malformed_rc" -ne 0
grep -q 'GameExceedsLupiFlash' <<<"$malformed_output"
mkdir -p "$tmp/manifest-mismatch"
printf 'function update() end\n' > "$tmp/manifest-mismatch/game.lua"
printf '1 1 game.lua {"type":"lua_code"}\n' > "$tmp/manifest-mismatch/lupi_manifest.txt"
set +e
mismatch_output="$(./zig-out/bin/elis --screenshot "$tmp/manifest-mismatch" 1 "$tmp/mismatch.ppm" 2>&1)"
mismatch_rc=$?
set -e
test "$mismatch_rc" -ne 0
grep -q 'GameExceedsLupiFlash' <<<"$mismatch_output"
mkdir -p "$tmp/manifest-duplicate"
printf 'function update() end\n' > "$tmp/manifest-duplicate/game.lua"
game_size="$(stat -c %s "$tmp/manifest-duplicate/game.lua")"
printf '1 %s game.lua {"type":"lua_code"}\n2 %s game.lua {"type":"lua_code"}\n' \
  "$game_size" "$game_size" > "$tmp/manifest-duplicate/lupi_manifest.txt"
set +e
duplicate_output="$(./zig-out/bin/elis --screenshot "$tmp/manifest-duplicate" 1 "$tmp/duplicate.ppm" 2>&1)"
duplicate_rc=$?
set -e
test "$duplicate_rc" -ne 0
grep -q 'GameExceedsLupiFlash' <<<"$duplicate_output"
mkdir -p "$tmp/manifest-json"
printf 'function update() end\n' > "$tmp/manifest-json/game.lua"
game_size="$(stat -c %s "$tmp/manifest-json/game.lua")"
printf '1 %s game.lua {not-json}\n' "$game_size" > "$tmp/manifest-json/lupi_manifest.txt"
set +e
json_output="$(./zig-out/bin/elis --screenshot "$tmp/manifest-json" 1 "$tmp/json.ppm" 2>&1)"
json_rc=$?
set -e
test "$json_rc" -ne 0
grep -q 'GameExceedsLupiFlash' <<<"$json_output"
mkdir -p "$tmp/manifest-package"
printf 'function update() end\n' > "$tmp/manifest-package/game.lua"
game_size="$(stat -c %s "$tmp/manifest-package/game.lua")"
padding_size=$((16 * 1024 * 1024 - game_size))
truncate -s "$padding_size" "$tmp/manifest-package/padding.bin"
printf '1 %s game.lua {"type":"lua_code"}\n2 %s padding.bin {"type":"data"}\n' \
  "$game_size" "$padding_size" > "$tmp/manifest-package/lupi_manifest.txt"
set +e
package_output="$(./zig-out/bin/elis --screenshot "$tmp/manifest-package" 1 "$tmp/package.ppm" 2>&1)"
package_rc=$?
set -e
test "$package_rc" -ne 0
grep -q 'GameExceedsLupiFlash' <<<"$package_output"
mkdir -p "$tmp/manifest-undeclared"
printf 'function update() require("hidden") end\n' > "$tmp/manifest-undeclared/game.lua"
printf 'return true\n' > "$tmp/manifest-undeclared/hidden.lua"
game_size="$(stat -c %s "$tmp/manifest-undeclared/game.lua")"
printf '1 %s game.lua {"type":"lua_code"}\n' "$game_size" \
  > "$tmp/manifest-undeclared/lupi_manifest.txt"
set +e
undeclared_output="$(./zig-out/bin/elis --screenshot "$tmp/manifest-undeclared" 1 "$tmp/undeclared.ppm" 2>&1)"
undeclared_rc=$?
set -e
test "$undeclared_rc" -ne 0
grep -q 'GameExceedsLupiFlash' <<<"$undeclared_output"

# Renderer coordinates are signed 32-bit for upstream compatibility, but
# hostile extremes must remain bounded and the per-frame budget must reset.
mkdir -p "$tmp/raster-bounds"
cat > "$tmp/raster-bounds/game.lua" <<'LUA'
local minimum = -2147483648
local maximum = 2147483647
local frame = 0
local palette = {}
for index = 1, 256 do palette[index] = 0 end
function update()
  ui.palset(1, 0x7c00)
  ui.cls(0)
  if frame == 0 then
    ui.line(minimum, minimum, maximum, maximum, 1)
  elseif frame == 1 then
    ui.circfill(0, 0, maximum, 1)
  elseif frame == 2 then
    ui.draw_rect(minimum, minimum, maximum, maximum, true, 1)
  elseif frame == 3 then
    ui.trisfill(minimum, 0, 0, 0, maximum, 0, 1)
  elseif frame == 4 then
    ui.set_pallet(maximum, maximum, palette)
  elseif frame == 5 then
    ui.spr({ path = "game.lua", width = maximum, height = maximum }, 0, 0)
    ui.map({ metadata = { width = maximum, height = maximum, tile_size = maximum } })
  else
    ui.rectfill(10, 10, 11, 11, 1)
  end
  frame = frame + 1
end
LUA
timeout 10s ./zig-out/bin/elis --screenshot \
  "$tmp/raster-bounds" 7 "$tmp/raster-bounds.ppm" >/dev/null

mkdir -p "$tmp/raster-degenerate"
printf 'function update() ui.draw_rect(0, 0, 0, 2147483647, true, 1) end\n' \
  > "$tmp/raster-degenerate/game.lua"
timeout 10s ./zig-out/bin/elis --screenshot \
  "$tmp/raster-degenerate" 1 "$tmp/raster-degenerate.ppm" >/dev/null
python3 - "$tmp/raster-bounds.ppm" <<'PY'
from pathlib import Path
import sys

payload = Path(sys.argv[1]).read_bytes().split(b"\n", 3)[3]
pixel = (10 * 480 + 10) * 3
assert payload[pixel:pixel + 3] == bytes((255, 0, 0))
PY

run_game "$root/mazestein3d"
while IFS= read -r -d '' game_file; do
  run_game "$(dirname "$game_file")"
done < <(find "$root/demos" -mindepth 2 -maxdepth 3 -name game.lua -print0)
echo "runtime smoke: pass"
