#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

zig fmt --check build.zig src/*.zig src/studio/*.zig
for script in scripts/*.sh; do
  bash -n "$script"
done

./scripts/test_studio.sh
./scripts/parity_smoke.sh
./scripts/runtime_smoke.sh
./scripts/studio_smoke.sh
./scripts/mr_rescue_smoke.sh

echo "ELIS full verification matrix: pass"
