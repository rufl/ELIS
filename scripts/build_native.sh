#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"
optimize_mode="${1:-ReleaseFast}"
case "$optimize_mode" in
  Debug|ReleaseSafe|ReleaseFast|ReleaseSmall) ;;
  *) echo "invalid Zig optimization mode: $optimize_mode" >&2; exit 2 ;;
esac
stack_check_flags=()
if [[ "$optimize_mode" == "ReleaseSafe" ]]; then
  stack_check_flags=(-fno-stack-check)
fi
mkdir -p zig-out/bin
lua_pkg="lua5.4"
if [[ "$(pkg-config --modversion "$lua_pkg")" != 5.4.* ]]; then
  echo "ELIS requires Lua 5.4 for physical Lupi console compatibility" >&2
  exit 1
fi
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
linker_cc="${ELIS_LINK_CC:-${ZILF_LINK_CC:-gcc-15}}"
if ! command -v "$linker_cc" >/dev/null 2>&1; then
  linker_cc="gcc"
fi

# GCC 16 emits .sframe relocations in crt1.o that Zig 0.16 cannot link yet.
# Keep the workaround local and recoverable; never modify the system CRT.
objcopy --remove-section=.sframe --remove-section=.rela.sframe \
  /usr/lib/crt1.o "$work_dir/crt1.o"

# Zig 0.16 can misclassify a failed lazy cache-directory creation as a
# read-only standard-library error. Create both isolated caches explicitly so
# clean builds are reliable in restricted and containerized environments.
mkdir -p "$work_dir/local-cache" "$work_dir/global-cache"

build_zig_object() {
  local source="$1"
  local output="$2"
  ZIG_LOCAL_CACHE_DIR="$work_dir/local-cache" \
  ZIG_GLOBAL_CACHE_DIR="$work_dir/global-cache" \
  zig build-obj -fPIC "${stack_check_flags[@]}" -lc \
    "-O$optimize_mode" \
    $(pkg-config --cflags sdl2 "$lua_pkg" libzip libcurl sndfile) \
    "$source" -femit-bin="$output"
}

# The manual GCC link cannot resolve Zig 0.16's __zig_probe_stack, while
# -fcompiler-rt currently crashes build-obj. Bounds/overflow checks remain
# enabled in ReleaseSafe; only Zig's separate stack probing is disabled.
# Some restricted filesystems also make Zig 0.16 report a transient false
# `ReadOnlyFileSystem` while opening std.zig. Retrying with the now-initialized
# isolated cache is safe and makes clean builds deterministic.
build_object_with_retry() {
  local source="$1"
  local output="$2"
  local label="$3"
  local build_log="$work_dir/zig-build-$label.log"
  for attempt in 1 2 3; do
    if build_zig_object "$source" "$output" >"$build_log" 2>&1; then
      return
    fi
    if [[ "$attempt" -eq 3 ]]; then
      cat "$build_log" >&2
      exit 1
    fi
  done
}

build_object_with_retry src/main.zig "$work_dir/elis.o" elis
build_object_with_retry src/studio_app.zig "$work_dir/elis-studio.o" studio

"$linker_cc" -nostartfiles "$work_dir/crt1.o" "$work_dir/elis.o" \
  -o zig-out/bin/elis \
  $(pkg-config --libs sdl2 "$lua_pkg" libzip libcurl sndfile) -lm -lpthread -ldl -lc \
  -Wl,-dynamic-linker,/lib64/ld-linux-x86-64.so.2

"$linker_cc" -nostartfiles "$work_dir/crt1.o" "$work_dir/elis-studio.o" \
  -o zig-out/bin/elis-studio \
  $(pkg-config --libs sdl2 "$lua_pkg" libzip libcurl sndfile) -lm -lpthread -ldl -lc \
  -Wl,-dynamic-linker,/lib64/ld-linux-x86-64.so.2

# Keep the former executable name as a compatibility entry point for scripts
# and local shortcuts created before the ELIS rename.
ln -sfn elis zig-out/bin/lupinho-zig

echo "built zig-out/bin/elis and zig-out/bin/elis-studio"
