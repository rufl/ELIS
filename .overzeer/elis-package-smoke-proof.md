ELIS_PACKAGE_SMOKE_PROOF_V1
status=passed
source_commit=e539ab52cfc6ebf153a98e5ae4d6bc2dc37e39c9
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36507535856
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36507535860
release=v0.1.0-rc.6
release_workflow_run=https://github.com/rufl/ELIS/actions/runs/36507546444
checked_utc=2026-09-29T01:44:46Z
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
  rc.6 release archives and manifests: SHA256SUMS pass
scope=release-package and deployment-smoke contract only
hardware_status=not applicable
deployment_release=v0.1.0-rc.6
deployment_preview=local immutable receiver previews passed for ddjarin/windows-x86_64 and chopper/linux-x86_64
deployment_ddjarin=passed: native deployment completed; version=0.1.0-rc.6 build_id=e539ab52cfc6ebf153a98e5ae4d6bc2dc37e39c9 sha256=bc0f27420f4e3a1b00c4bdd777ad4c4b0446946a41686457a6a679948f179bf4 size=127718883 active=true
deployment_chopper=passed: native deployment completed; version=0.1.0-rc.6 build_id=e539ab52cfc6ebf153a98e5ae4d6bc2dc37e39c9 sha256=46fad5fab9ab74f2bebd94a1e9f1f1243f386c1d0009b89cfb855e88f80715b2 size=2358185 active=true
deployment_unblock=none: both configured receivers report the requested version, build_id, SHA-256, size, and active=true
