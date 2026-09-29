ELIS_PACKAGE_SMOKE_PROOF_V1
status=passed
source_commit=79c455a515f141e25e2cfed5b65d6d730a6aee5e
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36503315073
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36503315116
release=v0.1.0-rc.5
release_workflow_run=https://github.com/rufl/ELIS/actions/runs/36503334405
checked_utc=2026-09-29T00:52:59Z
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
  rc.5 release archives and manifests: SHA256SUMS pass
scope=release-package and deployment-smoke contract only
hardware_status=not applicable
deployment_release=v0.1.0-rc.5
deployment_preview=local immutable receiver previews passed for ddjarin/windows-x86_64 and chopper/linux-x86_64
deployment_ddjarin=passed: native deployment completed; version=0.1.0-rc.5 build_id=79c455a515f141e25e2cfed5b65d6d730a6aee5e sha256=2644c5b42960c7846bc74928377a4206b23be9271158720ee54636603c3a8f5f size=127718897 active=true
deployment_chopper=passed: native deployment completed; version=0.1.0-rc.5 build_id=79c455a515f141e25e2cfed5b65d6d730a6aee5e sha256=523cb54fe732808c3db5657da5b4225989c33783b95fe7597f929a9edfbd16f6 size=2357624 active=true
deployment_unblock=none: both configured receivers report the requested version, build_id, SHA-256, size, and active=true
