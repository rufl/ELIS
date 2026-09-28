ELIS_PACKAGE_SMOKE_PROOF_V1
status=passed
source_commit=9ce0f276412e8366623ce0e1523c413c0db69868
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36427518479
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36427518461
release=v0.1.0-rc.3
release_workflow_run=https://github.com/rufl/ELIS/actions/runs/36428804657
checked_utc=2026-09-28T13:48:21Z
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
  rc.3 release archives and manifests: SHA256SUMS pass
scope=release-package and deployment-smoke contract only
hardware_status=not applicable
deployment_release=v0.1.0-rc.3
deployment_preview=local immutable receiver previews passed for ddjarin/windows-x86_64 and chopper/linux-x86_64
deployment_ddjarin=blocked: authenticated native deployment timed out; receiver active state not proven
deployment_chopper=blocked: DeploymentSmokeFailed; active deployment was not changed
deployment_unblock=receiver reachability/validation must pass, then endpoint status must report version, build_id, SHA-256, size, and active=true
