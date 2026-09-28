ELIS_PACKAGE_SMOKE_PROOF_V1
status=passed
source_commit=bdbd5cd06726c1c3a9a19e6a99ca668a51cd39e9
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36498354775
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36498354765
release=v0.1.0-rc.4
release_workflow_run=https://github.com/rufl/ELIS/actions/runs/36498391875
checked_utc=2026-09-28T23:52:27Z
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
  rc.4 release archives and manifests: SHA256SUMS pass
scope=release-package and deployment-smoke contract only
hardware_status=not applicable
deployment_release=v0.1.0-rc.4
deployment_preview=local immutable receiver previews passed for ddjarin/windows-x86_64 and chopper/linux-x86_64
deployment_ddjarin=blocked: authenticated native deployment returned HTTP 502 (RemoteHttpStatus); receiver active state not proven
deployment_chopper=passed: native deployment completed; version=0.1.0-rc.4 build_id=bdbd5cd06726c1c3a9a19e6a99ca668a51cd39e9 sha256=76d78ada9e08647a94868e1e1b9334a70d978aafc161091ae90724108c9c8111 size=2353999 active=true
deployment_unblock=ddjarin receiver reachability/validation must pass, then endpoint status must report version, build_id, SHA-256, size, and active=true
