#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
work="$(mktemp -d /tmp/elis-studio-tests.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/model-cache" "$work/model-global" "$work/assets-cache" "$work/assets-global" \
  "$work/debug-cache" "$work/debug-global" "$work/input-cache" "$work/input-global"

ZIG_LOCAL_CACHE_DIR="$work/model-cache" \
ZIG_GLOBAL_CACHE_DIR="$work/model-global" \
zig test src/studio/model.zig

ZIG_LOCAL_CACHE_DIR="$work/assets-cache" \
ZIG_GLOBAL_CACHE_DIR="$work/assets-global" \
zig test src/studio/assets.zig

ZIG_LOCAL_CACHE_DIR="$work/debug-cache" \
ZIG_GLOBAL_CACHE_DIR="$work/debug-global" \
zig test src/debug.zig

# Native imports need the same disposable CRT workaround as build_native.sh.
# Keep the UTF-8 input test in the normal gate rather than relying on compile-only coverage.
linker_cc="${ELIS_LINK_CC:-${ZILF_LINK_CC:-gcc-15}}"
command -v "$linker_cc" >/dev/null 2>&1 || linker_cc=gcc
crt1_path="$("$linker_cc" -print-file-name=crt1.o)"
[[ -f "$crt1_path" ]] || { echo "could not locate crt1.o through $linker_cc" >&2; exit 1; }
objcopy --remove-section=.sframe --remove-section=.rela.sframe \
  "$crt1_path" "$work/crt1.o"
ZIG_LOCAL_CACHE_DIR="$work/input-cache" \
ZIG_GLOBAL_CACHE_DIR="$work/input-global" \
zig test-obj --test-no-exec -fPIC -fno-stack-check -lc \
  $(pkg-config --cflags sdl2 lua5.4 libzip libcurl sndfile) src/input.zig -femit-bin="$work/input.o"
"$linker_cc" -nostartfiles -no-pie -Wl,-z,noexecstack "$work/crt1.o" "$work/input.o" \
  -o "$work/input-test" $(pkg-config --libs sdl2) -lm -lpthread -ldl -lc
"$work/input-test"

echo "ELIS Workshop, input, and instrumentation tests: pass"
