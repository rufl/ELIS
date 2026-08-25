#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
tmp="$(mktemp -d /tmp/elis-parity.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

ZIG_LOCAL_CACHE_DIR="$tmp/build-cache" \
ZIG_GLOBAL_CACHE_DIR="$tmp/global-cache" \
zig build native -Doptimize=ReleaseSafe >/dev/null

ZIG_LOCAL_CACHE_DIR="$tmp/test-cache" \
ZIG_GLOBAL_CACHE_DIR="$tmp/test-global-cache" \
zig test src/debug.zig >/dev/null
./zig-out/bin/elis --self-test-parity
env SDL_VIDEODRIVER=dummy ./zig-out/bin/elis --self-test-compositor
./zig-out/bin/elis --screenshot tests/parity 1 "$tmp/parity.ppm" >/dev/null

# Golden output from upstream commit 379a599. The image contains the exact
# rectangle, circle, degenerate triangle, uppercase/lowercase font, palette,
# and transparent palette-zero behavior used by the differential harness.
expected="45daf4b1e214299dc646741262cc19ac98930bcc14a13c7d6a30bd844ff404a4"
actual="$(sha256sum "$tmp/parity.ppm" | awk '{print $1}')"
test "$actual" = "$expected"

render_expected="4bdc24126c8d5a33987d8db28155ff74797e25850c399bbbb2f46c0bba667be2"
./zig-out/bin/elis --screenshot tests/render-matrix 1 "$tmp/render-matrix.ppm" >/dev/null
render_actual="$(sha256sum "$tmp/render-matrix.ppm" | awk '{print $1}')"
test "$render_actual" = "$render_expected"

asset_expected="50a18d87ae2a6e81888061e13fa8f7b654e083232315acab358063324309bf5b"
./zig-out/bin/elis --screenshot tests/asset-resolution 1 "$tmp/asset-resolution.ppm" >/dev/null
asset_actual="$(sha256sum "$tmp/asset-resolution.ppm" | awk '{print $1}')"
test "$asset_actual" = "$asset_expected"

bitmap_game="$tmp/bitmap-matrix"
cp -R tests/bitmap-matrix "$bitmap_game"
printf '\001\000\002\003\004\005\000\006' > "$bitmap_game/sheet"
bitmap_expected="af5cad276b052712e624fc7dde61ddd03cc8d424a343f0339e46a7b6312d53e9"
./zig-out/bin/elis --screenshot "$bitmap_game" 1 "$tmp/bitmap-matrix.ppm" >/dev/null
bitmap_actual="$(sha256sum "$tmp/bitmap-matrix.ppm" | awk '{print $1}')"
test "$bitmap_actual" = "$bitmap_expected"

layer_expected="63d09b6f7a86760c34b7bf88e2495b629f0d9f0d74301b46c547e1c717bf4114"
for run in {1..16}; do
  layer_frame="$tmp/layer-order-$run.ppm"
  ./zig-out/bin/elis --screenshot tests/layer-order 1 "$layer_frame" >/dev/null 2>&1
  layer_actual="$(sha256sum "$layer_frame" | awk '{print $1}')"
  test "$layer_actual" = "$layer_expected"
done

echo "debug instrumentation state: pass"
echo "upstream parity smoke: pass"
echo "complete raster matrix: pass"
echo "deterministic asset resolution: pass"
echo "sprite/tile/map bitmap matrix: pass"
echo "deterministic map layer order: pass (16 processes)"
