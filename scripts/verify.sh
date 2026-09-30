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
python3 scripts/test_package_ztash_manifest.py
python3 scripts/test_package_mr_rescue_playtest.py
python3 scripts/test_mr_rescue_hardware_gate.py
python3 scripts/test_mr_rescue_release_audit.py

echo "ELIS full verification matrix: pass"
