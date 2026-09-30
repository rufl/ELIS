ELIS_PACKAGE_SMOKE_PROOF_V1
status=passed
source_commit=44795f3484135ecbf6c928b17a92752bc395fe84
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36740734199
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36740734247
release=v0.1.0-rc.9
release_workflow_run=https://github.com/rufl/ELIS/actions/runs/36740841546
checked_utc=2026-09-30T16:48:56Z
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
  rc.9 release archives, per-target manifests, aggregate ZTASH manifest, and SHA256SUMS: pass
  ZTASH immutable preview for ddjarin/windows-x86_64 and chopper/linux-x86_64: pass
scope=release-package and deployment-smoke contract only
hardware_status=not applicable
deployment_release=v0.1.0-rc.9
deployment_preview=passed: exact rc.9 archives matched the aggregate manifest for ddjarin/windows-x86_64 and chopper/linux-x86_64 before mutation
deployment_ddjarin=passed: authenticated curl deployment completed after the receiver returned; deployment_id=f141f544ed4a787654c54ab1cf4fefdd version=0.1.0-rc.9 build_id=44795f3484135ecbf6c928b17a92752bc395fe84 sha256=bef43b7d3d2b5bbea94178ae2d747a2bff290f3fee4d88ee24c79478d456d167 size=127723448 active=true freshness=current
deployment_chopper=passed: authenticated curl deployment completed; deployment_id=3450d77ab0b19d875436fbe526850318 version=0.1.0-rc.9 build_id=44795f3484135ecbf6c928b17a92752bc395fe84 sha256=9f7634426e1d90b2d3f26c148e74c02b4acf0bae26ecd69267a9cf54fafa33ae size=2365505 active=true freshness=current
deployment_unblock=none: both configured receivers report the requested version, build_id, SHA-256, size, active=true, and freshness=current
