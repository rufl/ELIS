ELIS_PACKAGE_SMOKE_PROOF_V1
status=partial
source_commit=44795f3484135ecbf6c928b17a92752bc395fe84
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36740734199
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36740734247
release=v0.1.0-rc.9
release_workflow_run=https://github.com/rufl/ELIS/actions/runs/36740841546
checked_utc=2026-09-30T16:37:27Z
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
deployment_ddjarin=blocked: native upload ended with "zeer native: stopped safely (Timeout)"; DDJARIN then reported offline on the tailnet, so endpoint activation could not be queried and remains unconfirmed
deployment_chopper=passed: authenticated curl deployment completed; deployment_id=3450d77ab0b19d875436fbe526850318 version=0.1.0-rc.9 build_id=44795f3484135ecbf6c928b17a92752bc395fe84 sha256=9f7634426e1d90b2d3f26c148e74c02b4acf0bae26ecd69267a9cf54fafa33ae size=2365505 active=true freshness=current
deployment_unblock=return DDJARIN to the tailnet, rerun the exact rc.9 Windows deployment, and confirm version, build_id, SHA-256, size, and active=true from the endpoint
