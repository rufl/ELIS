ELIS_PACKAGE_SMOKE_PROOF_V1
status=passed
source_commit=e641bb5
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36325436323
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36325436294
checked_utc=2026-09-27
contract=--package-smoke
commands=
  ./zig-out/bin/elis --package-smoke
  extracted Linux package wrapper --package-smoke
  python3 scripts/smoke_release.py <archive>
results=
  Linux build: pass
  Windows build: pass
  extracted Linux smoke including --package-smoke: pass
  extracted Windows smoke including --package-smoke: pass
  Verify: pass
scope=release-package and deployment-smoke contract only
hardware_status=not applicable
