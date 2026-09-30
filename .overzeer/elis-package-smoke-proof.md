ELIS_PACKAGE_SMOKE_PROOF_V1
status=passed
source_commit=d999355d254c57453a061b2028491be274375936
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36687673612
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36687673429
release=v0.1.0-rc.8
release_workflow_run=https://github.com/rufl/ELIS/actions/runs/36688831624
checked_utc=2026-09-30T08:47:40Z
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
  rc.8 release archives and manifests: SHA256SUMS pass
scope=release-package and deployment-smoke contract only
hardware_status=not applicable
deployment_release=v0.1.0-rc.8
deployment_preview=remote immutable receiver previews passed for ddjarin/windows-x86_64 and chopper/linux-x86_64
deployment_ddjarin=passed: native deployment completed; deployment_id=4bbe60fd8d2de104221ac603b7161d2d version=0.1.0-rc.8 build_id=d999355d254c57453a061b2028491be274375936 sha256=e0b1980a4d023be6f5a5bc953e9fd29574d9655ce39334aa5b5294edefeb7581 size=127721495 active=true freshness=current status=succeeded
deployment_chopper=passed: native deployment completed; deployment_id=b802d0228925f7fd28a76ece7ecc6b8f version=0.1.0-rc.8 build_id=d999355d254c57453a061b2028491be274375936 sha256=a96302ce3dae9a9951839f3ac805a69ee71ce6c30974b23abbf7203b4eefa188 size=2361935 active=true freshness=current status=succeeded
deployment_unblock=none: both configured receivers report the requested version, build_id, SHA-256, size, active=true, freshness=current, and status=succeeded
