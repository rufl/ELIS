#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

./scripts/test_studio.sh
./scripts/parity_smoke.sh
./scripts/runtime_smoke.sh
./scripts/studio_smoke.sh

echo "ELIS full verification matrix: pass"
