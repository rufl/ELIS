#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
work="$(mktemp -d /tmp/elis-studio-tests.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/model-cache" "$work/model-global" "$work/debug-cache" "$work/debug-global"

ZIG_LOCAL_CACHE_DIR="$work/model-cache" \
ZIG_GLOBAL_CACHE_DIR="$work/model-global" \
zig test src/studio/model.zig

ZIG_LOCAL_CACHE_DIR="$work/debug-cache" \
ZIG_GLOBAL_CACHE_DIR="$work/debug-global" \
zig test src/debug.zig

echo "ELIS Studio and instrumentation tests: pass"
