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
ldd ./zig-out/bin/elis | grep -q 'liblua5.4'
constraints="$(./zig-out/bin/elis --lupi-constraints 2>&1)"
grep -q '^LUPI_CONSTRAINTS_V1$' <<<"$constraints"
grep -q '^lua=5.4$' <<<"$constraints"
grep -q '^esp32_psram_bytes=8388608$' <<<"$constraints"
grep -q '^lua_heap_bytes_max=4194304$' <<<"$constraints"
grep -q '^archive_entries_max=4096$' <<<"$constraints"
grep -q '^discrete_gpu=none$' <<<"$constraints"
grep -q '^player_slots=3$' <<<"$constraints"
grep -q '^tileset_pixels_max=49152$' <<<"$constraints"
grep -q '^map_layer_limit=not_published$' <<<"$constraints"
grep -q '^workshop_lua_data_entries_max=4096$' <<<"$constraints"
grep -q '^workshop_lua_source_bytes_max=131072$' <<<"$constraints"

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

run_game "$root/mazestein3d"
while IFS= read -r -d '' game_file; do
  run_game "$(dirname "$game_file")"
done < <(find "$root/demos" -mindepth 2 -maxdepth 3 -name game.lua -print0)
echo "runtime smoke: pass"
