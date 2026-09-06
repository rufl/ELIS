#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"
optimize_mode="${1:-ReleaseFast}"
case "$optimize_mode" in
  Debug|ReleaseSafe|ReleaseFast|ReleaseSmall) ;;
  *) echo "invalid Zig optimization mode: $optimize_mode" >&2; exit 2 ;;
esac
if [[ "${MSYSTEM:-}" != UCRT64 || "$(gcc -dumpmachine)" != x86_64-w64-mingw32 ]]; then
  echo "Build Windows binaries in an MSYS2 UCRT64 shell with the native x86_64 GCC toolchain" >&2
  exit 1
fi
for tool in zig gcc pkg-config windres cygpath; do
  command -v "$tool" >/dev/null || { echo "missing build tool: $tool" >&2; exit 1; }
done
if [[ "$(zig version)" != 0.16.0 ]]; then
  echo "ELIS requires Zig 0.16.0" >&2
  exit 1
fi
lua_pkg=lua5.4
if [[ "$(pkg-config --modversion "$lua_pkg")" != 5.4.* ]]; then
  echo "ELIS requires mingw-w64-ucrt-x86_64-lua54 (Lua 5.4), not the unversioned Lua package" >&2
  exit 1
fi
# Use the Windows trust store, not a build-machine CA-bundle path.
pacman -Q mingw-w64-ucrt-x86_64-curl-winssl >/dev/null
packages=(sdl2 "$lua_pkg" libzip libcurl sndfile)
pkg-config --exists "${packages[@]}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p zig-out/bin "$work_dir/local-cache" "$work_dir/global-cache"
# Native Zig cannot consume MSYS virtual paths. Convert every include/library
# path explicitly and disable MSYS's heuristic argv rewriting for the Zig call.
include_flags=()
for directory in $(pkg-config --cflags-only-I "${packages[@]}" | tr ' ' '\n'); do
  include_flags+=(-I "$(cygpath -m "${directory#-I}")")
done
include_flags+=(-isystem "$(cygpath -m "$MINGW_PREFIX/include")")
read -r -a define_flags <<< "$(pkg-config --cflags-only-other "${packages[@]}")"
# Manifest selects UTF-8 for Win32 narrow filesystem APIs (Windows 10 1903+).
# The Zig main owns SDL startup, so SDL2main is deliberately not linked.
windres -I src src/windows.rc "$work_dir/windows-resource.o"
for program in elis elis-studio; do
  source=src/main.zig
  [[ "$program" != elis-studio ]] || source=src/studio_app.zig
  MSYS2_ARG_CONV_EXCL='*' \
  ZIG_LOCAL_CACHE_DIR="$(cygpath -m "$work_dir/local-cache")" \
  ZIG_GLOBAL_CACHE_DIR="$(cygpath -m "$work_dir/global-cache")" \
  zig build-obj "$source" -target x86_64-windows-gnu -lc -D_UCRT \
    -fno-stack-check "-O$optimize_mode" "${include_flags[@]}" "${define_flags[@]}" \
    "-femit-bin=$(cygpath -m "$work_dir/$program.o")"
  # Keep the actual MinGW UCRT startup and import libraries; Zig emits only the
  # application object. GUI subsystem still supports redirected diagnostic I/O.
  libraries=()
  for flag in $(pkg-config --libs "${packages[@]}"); do
    case "$flag" in -lSDL2main|-mwindows|-mconsole) ;; *) libraries+=("$flag");; esac
  done
  gcc -mwindows -Wl,--stack,16777216 "$work_dir/$program.o" "$work_dir/windows-resource.o" \
    -o "zig-out/bin/$program.exe" "${libraries[@]}" \
    -lntdll -lws2_32 -ladvapi32 -lshell32 -lole32 -luserenv -lbcrypt -lm
 done

echo "built zig-out/bin/elis.exe and zig-out/bin/elis-studio.exe"
