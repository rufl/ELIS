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

# Run native cache, catalog, and loader regressions with the same private CRT
# workaround used by the existing native input tests.
mkdir -p "$tmp/test-cache" "$tmp/test-global"
linker_cc="${ELIS_LINK_CC:-${ZILF_LINK_CC:-gcc-15}}"
command -v "$linker_cc" >/dev/null 2>&1 || linker_cc=gcc
crt1_path="$("$linker_cc" -print-file-name=crt1.o)"
[[ -f "$crt1_path" ]] || { echo "could not locate crt1.o through $linker_cc" >&2; exit 1; }
objcopy --remove-section=.sframe --remove-section=.rela.sframe "$crt1_path" "$tmp/crt1.o"
ZIG_LOCAL_CACHE_DIR="$tmp/test-cache" ZIG_GLOBAL_CACHE_DIR="$tmp/test-global" \
zig test-obj --test-no-exec -fPIC -fno-stack-check -lc \
  $(pkg-config --cflags sdl2 lua5.4 libzip libcurl sndfile) \
  src/main.zig -femit-bin="$tmp/runtime-tests.o"
"$linker_cc" -nostartfiles -no-pie -Wl,-z,noexecstack "$tmp/crt1.o" "$tmp/runtime-tests.o" \
  -o "$tmp/runtime-tests" $(pkg-config --libs sdl2 lua5.4 libzip libcurl sndfile) -lm -lpthread -ldl -lc
"$tmp/runtime-tests"

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

# Cartridge modules take precedence over same-named launch-directory modules.
mkdir -p "$tmp/module-root"
printf 'return "host"\n' > "$tmp/helper.lua"
printf 'return "cartridge"\n' > "$tmp/module-root/helper.lua"
printf '%s\n' \
  'assert(require("helper") == "cartridge")' \
  'function update() end' > "$tmp/module-root/game.lua"
(cd "$tmp" && "$root/zig-out/bin/elis" --screenshot \
  "$tmp/module-root" 1 "$tmp/module-root.ppm") >/dev/null

# All filename loaders share Lua's BOM/shebang handling and Lupi binary
# integers, while loadfile/dofile keep their Lua 5.4 return and mode contracts.
python3 - "$tmp/file-loaders" <<'PY'
import pathlib
import sys

base = pathlib.Path(sys.argv[1])
game = r'''
assert(0b101 == 5)
-- Replacing the former helper global must not replace the captured compiler.
__lupi_compile_file = function() error("compiler replaced") end
__lupi_load_file = __lupi_compile_file
assert(require("helper") == 5)
assert(require("helper_plain") == 7)
local root = debug.getinfo(1, "S").source:match("^@(.*)/game.lua$")
local function values(...)
  local result = table.pack(...)
  assert(result.n == 4 and result[1] == 5 and result[2] == nil)
  assert(result[3] == "0b101" and result[4] == nil)
end
values(assert(loadfile("returns.lua"))())
values(dofile("returns.lua"))
values(dofile(root .. "/returns.lua"))
assert(assert(loadfile("empty.lua"))() == nil)
assert(assert(loadfile("lexical.lua"))() == 9)
for _, filename in ipairs({"env.lua", "env_binary.lua"}) do
  assert(assert(loadfile(filename))() == _G)
  assert(assert(loadfile(filename, nil))() == _G)
  assert(assert(loadfile(filename, nil, nil))() == nil)
  local environment = { marker = 23 }
  assert(assert(loadfile(filename, "t", environment))() == environment)
  assert(assert(loadfile(filename, "bt"))() == _G)
  assert(assert(loadfile(filename, "t"))() == _G)
  for _, mode in ipairs({"b", ""}) do
    local result = table.pack(loadfile(filename, mode))
    assert(result.n == 2 and result[1] == nil and type(result[2]) == "string")
  end
end
local dumped = string.dump(function() return 31, "0b101" end)
local function write(name, content)
  local file = assert(io.open(root .. "/" .. name, "wb"))
  assert(file:write(content))
  assert(file:close())
end
write("compiled.lua", dumped)
write("prefixed.lua", "\239\187\191#!/usr/bin/lua\n" .. dumped)
for _, filename in ipairs({"compiled.lua", "prefixed.lua"}) do
  for _, mode in ipairs({"b", "bt"}) do
    local first, second = assert(loadfile(filename, mode, {}))()
    assert(first == 31 and second == "0b101")
  end
  assert(assert(loadfile(filename))() == 31)
  assert(dofile(filename) == 31)
  local chunk, err = loadfile(filename, "t")
  assert(chunk == nil and type(err) == "string")
end
assert(not pcall(require, "compiled")) -- Cartridge modules remain text-only.
for _, filename in ipairs({"missing.lua", "syntax.lua", "malformed.lua"}) do
  local result = table.pack(loadfile(filename))
  assert(result.n == 2 and result[1] == nil and type(result[2]) == "string")
  assert(not pcall(dofile, filename))
end
local _, syntax_error = loadfile("syntax.lua")
assert(syntax_error:find("syntax.lua:3:", 1, true), syntax_error)
local ok, module_error = pcall(require, "syntax")
assert(not ok and module_error:find("syntax.lua:3:", 1, true), module_error)
local ok, runtime_error = pcall(dofile, "runtime.lua")
assert(not ok and runtime_error:find("runtime.lua:3:", 1, true), runtime_error)
assert(not pcall(loadfile, {}))
assert(not pcall(loadfile, "env.lua", {}))
assert(not pcall(dofile, {}))
write("entry-bytecode/game.lua", dumped)
function update() end
'''
for name, prefix in (("bom", b"\xef\xbb\xbf"),
                     ("shebang", b"#!/usr/bin/lua 0b111\n"),
                     ("both", b"\xef\xbb\xbf#!/usr/bin/lua\n")):
    root = base / name
    (root / "entry-bytecode").mkdir(parents=True)
    (root / "game.lua").write_bytes(prefix + game.encode())
    for filename, source in {
        "helper.lua": "return 0b101\n",
        "helper_plain.lua": "return 7\n",
        "returns.lua": 'return 0b101, nil, "0b101", nil\n',
        "env.lua": "return _ENV\n",
        "env_binary.lua": "local number = 0b101; return _ENV, number\n",
        "malformed.lua": "return 0b102\n",
        "lexical.lua": '''-- 0b110
local quoted = "escaped \\" 0b111"
local long = [==[0b101]==]
--[=[0b111]=]
assert(quoted == 'escaped " 0b111' and long == "0b101")
return 0b100 + 0B101
''',
    }.items():
        (root / filename).write_bytes(prefix + source.encode())
    (root / "empty.lua").write_bytes(b"")
    diagnostic_prefix = b"\xef\xbb\xbf#!/usr/bin/lua\n\n"
    (root / "syntax.lua").write_bytes(diagnostic_prefix + b"local = 0b1\n")
    (root / "runtime.lua").write_bytes(diagnostic_prefix + b'error("loader failure")\n')

for name, expression in {
    "loadfile-omitted": "assert(loadfile())()",
    "loadfile-nil": "assert(loadfile(nil))()",
    "loadfile-env": 'assert(loadfile(nil, "t", { marker = 37 }))()',
    "dofile-omitted": "dofile()",
    "dofile-nil": "dofile(nil)",
}.items():
    root = base / name
    root.mkdir()
    (root / "game.lua").write_text(
        f"local result = table.pack({expression})\n"
        'assert(result.n == 3 and result[1] == 37 and result[2] == nil and result[3] == "stdin")\n'
        "function update() end\n"
    )
PY
for loader_case in bom shebang both; do
  ./zig-out/bin/elis --screenshot "$tmp/file-loaders/$loader_case" 1 \
    "$tmp/file-loaders/$loader_case.ppm" >/dev/null
  set +e
  bytecode_output="$(./zig-out/bin/elis --screenshot \
    "$tmp/file-loaders/$loader_case/entry-bytecode" 1 "$tmp/bytecode.ppm" 2>&1)"
  bytecode_rc=$?
  set -e
  test "$bytecode_rc" -eq 1
  grep -q "attempt to load a binary chunk" <<<"$bytecode_output"
  test ! -e "$tmp/bytecode.ppm"
done
for stdin_case in loadfile-omitted loadfile-nil dofile-omitted dofile-nil; do
  printf 'return 37, nil, "stdin"\n' | ./zig-out/bin/elis --screenshot \
    "$tmp/file-loaders/$stdin_case" 1 "$tmp/file-loaders/$stdin_case.ppm" >/dev/null
done
printf 'return marker, nil, "stdin"\n' | ./zig-out/bin/elis --screenshot \
  "$tmp/file-loaders/loadfile-env" 1 "$tmp/file-loaders/loadfile-env.ppm" >/dev/null

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
